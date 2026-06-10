const fs = require('fs');
const path = require('path');
const { Blob } = require('buffer');
const { config } = require('../config/env');
const { getLatestImage, getLatestFrame } = require('./cameraService');
const { sendMail, isEmailConfigured } = require('./emailService');
const {
  getPestAlertEnabledAsync,
  getSettingAsync,
  setSettingAsync,
} = require('./settingsService');
const { recordFromPredictResult } = require('./leafAnalysisService');

const LAST_SENT_KEY = 'pest_alert_last_sent';
const ONE_HOUR_MS = 60 * 60 * 1000;
const PEST_MODEL = 'resnet';

/** Nhãn lớp sâu — khớp app/ml/labels.py */
const PEST_CLASS_LABELS = new Set(['la_sau', 'sau']);

function getLatestImageAsync() {
  return new Promise((resolve, reject) => {
    getLatestImage((err, row) => {
      if (err) reject(err);
      else resolve(row);
    });
  });
}

function resolvePredictUrl() {
  const raw = (config.AI_SERVER_URL || '').trim().replace(/\/$/, '');
  if (!raw) return null;
  if (raw.includes('/predict')) return raw;
  return `${raw}/predict`;
}

function isPestPrediction(result) {
  if (!result || typeof result !== 'object') return false;
  const label = (
    result.label
    ?? result.prediction
    ?? result.class
    ?? result.disease
  );
  if (label == null) return false;
  const normalized = String(label).trim().toLowerCase();
  return PEST_CLASS_LABELS.has(normalized);
}

function formatConfidence(result) {
  const conf = result.confidence ?? result.probability ?? result.score ?? result.prob;
  if (typeof conf !== 'number' || Number.isNaN(conf)) return null;
  const pct = conf <= 1 ? Math.round(conf * 100) : Math.round(conf);
  return `${pct}%`;
}

/** Thời điểm ảnh — chỉ ngày/tháng/năm (giờ VN). */
function formatCapturedDate(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) {
    const m = String(iso).match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (m) return `${m[3]}/${m[2]}/${m[1]}`;
    return String(iso);
  }
  const vn = new Date(d.getTime() + 7 * 60 * 60 * 1000);
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(vn.getUTCDate())}/${pad(vn.getUTCMonth() + 1)}/${vn.getUTCFullYear()}`;
}

async function loadLatestCameraImageBytes() {
  const row = await getLatestImageAsync();
  if (row?.filepath && fs.existsSync(row.filepath)) {
    return {
      bytes: fs.readFileSync(row.filepath),
      filename: row.filename || path.basename(row.filepath),
      source: 'camera_images',
      capturedAt: row.captured_at,
      publicUrl: row.public_url,
    };
  }

  const frame = getLatestFrame();
  if (frame && Buffer.isBuffer(frame) && frame.length > 0) {
    return {
      bytes: frame,
      filename: `stream_frame_${Date.now()}.jpg`,
      source: 'live_frame',
      capturedAt: new Date().toISOString(),
      publicUrl: null,
    };
  }

  return null;
}

function mimeForImageFilename(filename) {
  const ext = path.extname(filename || '').toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.webp') return 'image/webp';
  if (ext === '.gif') return 'image/gif';
  return 'image/jpeg';
}

async function predictWithResNet(imageBytes, filename) {
  const predictUrl = resolvePredictUrl();
  if (!predictUrl) {
    throw new Error('AI_SERVER_URL chưa cấu hình');
  }
  if (!imageBytes || !Buffer.isBuffer(imageBytes) || imageBytes.length < 100) {
    throw new Error('Ảnh camera không hợp lệ hoặc rỗng');
  }

  const safeName = filename || 'camera.jpg';
  const form = new FormData();
  const blob = new Blob([imageBytes], { type: mimeForImageFilename(safeName) });
  form.append('file', blob, safeName);
  form.append('model', PEST_MODEL);

  const response = await fetch(predictUrl, {
    method: 'POST',
    body: form,
    signal: AbortSignal.timeout(120000),
  });

  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`AI predict HTTP ${response.status}: ${raw.slice(0, 200)}`);
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error('AI server không trả JSON hợp lệ');
  }

  const result = parsed?.result && typeof parsed.result === 'object'
    ? parsed.result
    : parsed;

  return { raw: parsed, result };
}

async function getLastPestAlertSentAt() {
  const raw = await getSettingAsync(LAST_SENT_KEY);
  if (!raw) return null;
  const ts = Date.parse(raw);
  return Number.isFinite(ts) ? ts : null;
}

async function markPestAlertSent() {
  await setSettingAsync(LAST_SENT_KEY, new Date().toISOString());
}

/**
 * Mỗi giờ: lấy ảnh camera mới nhất → ResNet → email nếu lớp sâu.
 * Không có ảnh thì bỏ qua. Tối đa 1 email/giờ.
 */
async function checkAndSendPestAlert({ force = false } = {}) {
  const enabled = await getPestAlertEnabledAsync();
  if (!enabled && !force) {
    return { skipped: true, reason: 'disabled' };
  }

  if (!isEmailConfigured()) {
    return { skipped: true, reason: 'email_not_configured' };
  }

  const image = await loadLatestCameraImageBytes();
  if (!image) {
    return { skipped: true, reason: 'no_image' };
  }

  let prediction;
  try {
    prediction = await predictWithResNet(image.bytes, image.filename);
  } catch (err) {
    console.error('[PEST-ALERT] ResNet predict failed:', err.message);
    return { skipped: true, reason: 'predict_failed', error: err.message };
  }

  const { result } = prediction;
  await recordFromPredictResult({
    result,
    model: PEST_MODEL,
    source: 'pest_alert',
  }).catch((err) => {
    console.error('[PEST-ALERT] Failed to log leaf analysis:', err.message);
  });

  if (!isPestPrediction(result)) {
    return {
      skipped: true,
      reason: 'no_pest',
      label: result?.label ?? result?.label_vietnamese,
    };
  }

  const lastSent = await getLastPestAlertSentAt();
  if (!force && lastSent != null && Date.now() - lastSent < ONE_HOUR_MS) {
    return {
      skipped: true,
      reason: 'rate_limited',
      label: result?.label ?? result?.label_vietnamese,
    };
  }

  const labelVi = result.label_vietnamese
    ?? result.label
    ?? 'Sâu bệnh';
  const capturedDate = formatCapturedDate(image.capturedAt);

  const text = [
    'Cảnh báo: có sâu đang xâm nhập vườn.',
    '',
    `Phát hiện: ${labelVi}`,
    '',
    `Nguồn ảnh: ${image.source}`,
    capturedDate ? `Thời điểm ảnh: ${capturedDate}` : null,
    image.publicUrl ? `URL: ${image.publicUrl}` : null,
  ].filter(Boolean).join('\n');

  const html = `
    <h2>Có sâu đang xâm nhập vườn</h2>
    <p>Hệ thống vừa phân tích ảnh camera và phát hiện dấu hiệu sâu bệnh.</p>
    <ul>
      <li><strong>${labelVi}</strong></li>
      <li>Nguồn ảnh: ${image.source}</li>
      ${capturedDate ? `<li>Thời điểm ảnh: ${capturedDate}</li>` : ''}
    </ul>
    <p style="color:#666;font-size:12px;">Kiểm tra mỗi giờ khi bật trong app. Tối đa 1 email/giờ.</p>
  `;

  await sendMail({
    subject: '[Plant IoT] Cảnh báo — sâu đang xâm nhập vườn',
    text,
    html,
  });

  await markPestAlertSent();
  console.log(`[PEST-ALERT] Sent email — ${labelVi}`);

  return {
    skipped: false,
    label: result.label,
    label_vietnamese: labelVi,
    confidence: formatConfidence(result),
  };
}

module.exports = {
  checkAndSendPestAlert,
  isPestPrediction,
  loadLatestCameraImageBytes,
  predictWithResNet,
  PEST_CLASS_LABELS,
};
