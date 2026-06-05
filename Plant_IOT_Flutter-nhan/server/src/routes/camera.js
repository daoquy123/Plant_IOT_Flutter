const path = require('path');
const express = require('express');
const multer = require('multer');
const { config } = require('../../config/env');
const {
  saveImage,
  getLatestImage,
  listImages,
  setLatestFrame,
  getLatestFrame,
  createCaptureRequest,
} = require('../../services/cameraService');

const router = express.Router();
const uploadDirectory = path.resolve(__dirname, '../../', config.UPLOADS_DIR);
const streamRawParser = express.raw({ type: 'image/jpeg', limit: '2mb' });
const MAX_STREAM_FPS = 12;
const activeStreamViewers = new Set();
let lastStreamFps = 8;
let lastFrameAt = 0;

const storage = multer.diskStorage({
  destination: uploadDirectory,
  filename: (req, file, cb) => {
    const sanitized = file.originalname.replace(/[^a-zA-Z0-9.-_]/g, '_');
    cb(null, `${Date.now()}_${sanitized}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: config.MAX_FILE_SIZE_MB * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image uploads are allowed.'));
    }
    cb(null, true);
  },
});

function buildPublicUrl(req, filename) {
  const proto = req.get('x-forwarded-proto') || req.protocol;
  const host = req.get('host');
  return `${proto}://${host}/uploads/${filename}`;
}

function buildStreamStartCommand(fps = lastStreamFps) {
  const safeFps = Math.min(MAX_STREAM_FPS, Math.max(1, Number(fps) || lastStreamFps));
  lastStreamFps = safeFps;
  return {
    type: 'stream_start',
    fps: safeFps,
    requested_at: new Date().toISOString(),
  };
}

function resumeStreamForActiveViewers(app) {
  if (activeStreamViewers.size === 0) return false;
  if (typeof app.locals.publishCameraCommand !== 'function') return false;
  return app.locals.publishCameraCommand(buildStreamStartCommand());
}

function publishCameraCommand(req, res, command) {
  if (typeof req.app.locals.publishCameraCommand !== 'function') {
    return res.status(503).json({
      success: false,
      message: 'MQTT camera command publisher is not available.',
    });
  }

  const published = req.app.locals.publishCameraCommand(command);
  if (!published) {
    return res.status(503).json({
      success: false,
      message: 'MQTT broker is not connected. Camera command was not sent.',
    });
  }

  return null;
}

router.post('/upload', upload.single('image'), (req, res, next) => {
  if (!req.file) {
    return res.status(400).json({ success: false, message: 'Missing image file.' });
  }

  const url = buildPublicUrl(req, req.file.filename);
  saveImage(req.file, {
    capturedAt: req.body.captured_at,
    publicUrl: url,
    deviceId: req.body.device_id || req.body.deviceId || 'esp32_cam_main',
    requestId: req.body.request_id || req.body.requestId,
    uploadSource: req.body.upload_source || 'esp32-cam',
  }, (err, image) => {
    if (err) {
      return next(err);
    }

    req.app.locals.io.emit('camera', { ...image, url });
    req.app.locals.io.emit('capture-done', {
      imageUrl: url,
      imageId: image.id,
      capturedAt: image.captured_at,
      timestamp: Date.now(),
    });

    res.json({
      success: true,
      image: { ...image, url },
    });
  });
});

router.post('/frame', streamRawParser, (req, res) => {
  const frameBuffer = req.body;
  if (!Buffer.isBuffer(frameBuffer) || frameBuffer.length === 0) {
    return res.status(400).json({ success: false, message: 'Missing JPEG frame payload.' });
  }

  const ts = Date.now();
  lastFrameAt = ts;
  setLatestFrame(frameBuffer);
  req.app.locals.io.emit('frame-update', { size: frameBuffer.length, ts });
  req.app.locals.io.emit('camera-frame', {
    image: frameBuffer,
    size: frameBuffer.length,
    deviceId: req.get('x-device-id') || 'esp32_cam_main',
    ts,
  });
  return res.json({ success: true });
});

router.get('/frame', (req, res) => {
  const frameBuffer = getLatestFrame();
  if (!frameBuffer) {
    return res.status(404).json({ success: false, message: 'No frame available.' });
  }

  res.setHeader('Content-Type', 'image/jpeg');
  return res.send(frameBuffer);
});

router.post('/request-capture', (req, res) => {
  const command = {
    type: 'capture',
    request_id: `capture-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    requested_at: new Date().toISOString(),
  };

  const publishError = publishCameraCommand(req, res, command);
  const published = !publishError;
  createCaptureRequest({
    requestId: command.request_id,
    deviceId: req.body?.device_id || 'esp32_cam_main',
    status: published ? 'published' : 'mqtt_unavailable',
    requestedBy: req.body?.requested_by || 'app',
  }, (err) => {
    if (err) {
      return console.error('Failed to record camera capture request:', err.message);
    }
  });
  if (publishError) return publishError;

  req.app.locals.io.emit('capture-requested', command);
  return res.json({ success: true, command });
});

router.post('/stream/start', (req, res) => {
  const fps = Math.min(MAX_STREAM_FPS, Math.max(1, Number(req.body?.fps) || 8));
  const viewerId = req.body?.viewer_id?.toString().trim() || 'app';
  activeStreamViewers.add(viewerId);
  const command = buildStreamStartCommand(fps);

  // Always publish so ESP32-CAM can resume after an unexpected reboot/power loss.
  const publishError = publishCameraCommand(req, res, command);
  if (publishError) {
    activeStreamViewers.delete(viewerId);
    return publishError;
  }

  req.app.locals.io.emit('camera-stream-status', {
    enabled: true,
    fps,
    viewers: activeStreamViewers.size,
    timestamp: Date.now(),
  });
  return res.json({ success: true, command, viewers: activeStreamViewers.size });
});

router.post('/stream/stop', (req, res) => {
  const viewerId = req.body?.viewer_id?.toString().trim() || 'app';
  activeStreamViewers.delete(viewerId);

  if (activeStreamViewers.size > 0) {
    req.app.locals.io.emit('camera-stream-status', {
      enabled: true,
      viewers: activeStreamViewers.size,
      timestamp: Date.now(),
    });
    return res.json({ success: true, skipped: 'active_viewers_remaining', viewers: activeStreamViewers.size });
  }

  const command = {
    type: 'stream_stop',
    requested_at: new Date().toISOString(),
  };

  const publishError = publishCameraCommand(req, res, command);
  if (publishError) return publishError;

  req.app.locals.io.emit('camera-stream-status', {
    enabled: false,
    viewers: 0,
    timestamp: Date.now(),
  });
  return res.json({ success: true, command, viewers: 0 });
});

router.get('/command', (req, res) => {
  return res.status(410).json({
    success: false,
    message: 'Camera command polling is disabled. ESP32-CAM now receives commands via MQTT.',
  });
});

router.get('/latest', (req, res, next) => {
  getLatestImage((err, image) => {
    if (err) {
      return next(err);
    }

    if (!image) {
      return res.json({
        success: true,
        image: null,
        message: 'No camera images found.',
      });
    }

    res.json({
      success: true,
      image: {
        ...image,
        url: image.public_url || buildPublicUrl(req, image.filename),
      },
    });
  });
});

router.get('/list', (req, res, next) => {
  const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 50));
  const offset = Math.max(0, Number(req.query.offset) || 0);

  listImages({ limit, offset }, (err, images) => {
    if (err) {
      return next(err);
    }

    res.json({
      success: true,
      images: images.map((image) => ({
        ...image,
        url: image.public_url || buildPublicUrl(req, image.filename),
      })),
    });
  });
});

module.exports = router;
module.exports.resumeStreamForActiveViewers = resumeStreamForActiveViewers;
module.exports.getActiveStreamViewerCount = () => activeStreamViewers.size;
module.exports.getLastFrameAt = () => lastFrameAt;
