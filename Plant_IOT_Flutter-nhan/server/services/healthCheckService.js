const fs = require('fs');
const path = require('path');
const { config } = require('../config/env');
const { getLatestImage } = require('./cameraService');
const { createConversation, insertMessage } = require('./chatService');

const DEFAULT_MODEL = 'resnet';
const CAPTURE_TIMEOUT_MS = 25000;
const CAPTURE_POLL_MS = 500;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function promisify(fn, ...args) {
  return new Promise((resolve, reject) => {
    fn(...args, (err, result) => {
      if (err) reject(err);
      else resolve(result);
    });
  });
}

function stripDiacritics(input) {
  return String(input || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D');
}

function truncate16(text) {
  const normalized = stripDiacritics(text).trim();
  if (normalized.length <= 16) return normalized;
  return normalized.slice(0, 16);
}

function formatPredictReply(json, model) {
  const payload = json?.result && typeof json.result === 'object' ? json.result : json;
  const label =
    payload?.label_vietnamese ||
    payload?.label ||
    payload?.prediction ||
    payload?.disease ||
    payload?.class ||
    payload?.result;
  const conf =
    payload?.confidence ||
    payload?.score ||
    payload?.prob ||
    payload?.probability;
  const modelTag = model ? ` [${model}]` : '';
  if (label != null && typeof conf === 'number') {
    const pct = Math.round(Math.min(100, Math.max(0, conf <= 1 ? conf * 100 : conf)));
    return `Phat hien${modelTag}: ${label} — ${pct}%`;
  }
  if (label != null) return `Phat hien${modelTag}: ${label}`;
  return payload?.message || json?.message || 'Khong co ket qua';
}

function buildLcdLines(replyText) {
  const clean = stripDiacritics(replyText);
  const match = clean.match(/Phat hien(?:\s*\[[^\]]+\])?:\s*(.+?)\s*(?:—|-)\s*(\d+)%/i);
  if (match) {
    return {
      line1: truncate16(match[1].trim()),
      line2: truncate16(`Do tin: ${match[2]}%`),
    };
  }
  const parts = clean.split(/\s+—\s+|\s+-\s+/);
  if (parts.length >= 2) {
    return {
      line1: truncate16(parts[0]),
      line2: truncate16(parts[1]),
    };
  }
  const midpoint = Math.min(16, Math.ceil(clean.length / 2));
  return {
    line1: truncate16(clean.slice(0, midpoint)),
    line2: truncate16(clean.slice(midpoint)),
  };
}

async function waitForNewCameraImage(beforeImage, timeoutMs = CAPTURE_TIMEOUT_MS) {
  const beforeId = beforeImage?.id ?? null;
  const beforeCapturedAt = beforeImage?.captured_at ?? null;
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const latest = await promisify(getLatestImage);
    if (!latest) {
      await sleep(CAPTURE_POLL_MS);
      continue;
    }
    const isNew =
      beforeId == null ||
      latest.id !== beforeId ||
      (beforeCapturedAt && latest.captured_at !== beforeCapturedAt);
    if (isNew) return latest;
    await sleep(CAPTURE_POLL_MS);
  }
  return null;
}

async function predictImageFile(imagePath, model = DEFAULT_MODEL) {
  const buffer = fs.readFileSync(imagePath);
  const form = new FormData();
  const blob = new Blob([buffer], { type: 'image/jpeg' });
  form.append('file', blob, 'capture.jpg');
  form.append('model', model);

  const endpoint = `${config.AI_SERVER_URL.replace(/\/$/, '')}/predict`;
  const response = await fetch(endpoint, { method: 'POST', body: form });
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`AI predict failed (${response.status}): ${raw.slice(0, 200)}`);
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new Error(`AI predict returned invalid JSON: ${err.message}`);
  }
}

async function runHealthCheck({
  publishCameraCommand,
  io,
  model = DEFAULT_MODEL,
  deviceId = 'esp32_garden_main',
}) {
  if (typeof publishCameraCommand !== 'function') {
    throw new Error('MQTT camera command publisher is not available.');
  }

  const beforeImage = await promisify(getLatestImage);
  const command = {
    type: 'capture',
    request_id: `health-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    requested_at: new Date().toISOString(),
  };
  const published = publishCameraCommand(command);
  if (!published) {
    throw new Error('MQTT broker is not connected. Capture command was not sent.');
  }

  const image = await waitForNewCameraImage(beforeImage);
  if (!image?.filepath || !fs.existsSync(image.filepath)) {
    throw new Error('Timed out waiting for a new camera image.');
  }

  const predictJson = await predictImageFile(image.filepath, model);
  const reply = formatPredictReply(predictJson, model);
  const lcd = buildLcdLines(reply);
  const imageUrl = image.public_url || null;
  const userText = `[Kiem tra suc khoe cay - ${model}]`;

  const conversation = await promisify(createConversation, {
    title: 'ESP32 - Kiem tra suc khoe',
    model,
    source: 'esp32_button',
    deviceId,
    imageUrl,
  });

  const userMessage = await promisify(insertMessage, {
    conversationId: conversation.id,
    role: 'user',
    content: userText,
  });
  const aiMessage = await promisify(insertMessage, {
    conversationId: conversation.id,
    role: 'ai',
    content: reply,
  });

  const payload = {
    conversation,
    messages: [userMessage, aiMessage],
    reply,
    lcd,
    image_url: imageUrl,
    model,
    device_id: deviceId,
  };

  if (io) {
    io.emit('ai-analysis', { analysis: reply, source: 'esp32_button', model });
    io.emit('esp32-health-check', payload);
  }

  return payload;
}

module.exports = {
  runHealthCheck,
  buildLcdLines,
  formatPredictReply,
  truncate16,
};
