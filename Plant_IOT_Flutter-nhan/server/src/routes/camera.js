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
  setCommand,
  getCommand,
} = require('../../services/cameraService');

const router = express.Router();
const uploadDirectory = path.resolve(__dirname, '../../', config.UPLOADS_DIR);
const streamRawParser = express.raw({ type: 'image/jpeg', limit: '2mb' });

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

router.post('/upload', upload.single('image'), (req, res, next) => {
  if (!req.file) {
    return res.status(400).json({ success: false, message: 'Missing image file.' });
  }

  saveImage(req.file, { capturedAt: req.body.captured_at }, (err, image) => {
    if (err) {
      return next(err);
    }

    const url = buildPublicUrl(req, req.file.filename);
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

  setLatestFrame(frameBuffer);
  req.app.locals.io.emit('frame-update', { size: frameBuffer.length, ts: Date.now() });
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
  console.log('>>> before setCommand');

  setCommand({ type: 'capture', requestedAt: new Date().toISOString() });

  console.log('>>> after setCommand');

  return res.json({ success: true });
});

router.get('/command', (req, res) => {
  const command = getCommand();
  return res.json({
    success: true,
    command: command || null,
  });
});

router.get('/latest', (req, res, next) => {
  getLatestImage((err, image) => {
    if (err) {
      return next(err);
    }

    if (!image) {
      return res.status(404).json({ success: false, message: 'No camera images found.' });
    }

    res.json({
      success: true,
      image: {
        ...image,
        url: buildPublicUrl(req, image.filename),
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
        url: buildPublicUrl(req, image.filename),
      })),
    });
  });
});

module.exports = router;
