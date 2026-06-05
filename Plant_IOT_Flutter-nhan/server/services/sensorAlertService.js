const { config } = require('../config/env');
const { getLatestReading } = require('./sensorService');
const { sendMail, isEmailConfigured } = require('./emailService');
const {
  getSensorAlertEnabledAsync,
  getSettingAsync,
  setSettingAsync,
} = require('./settingsService');

const LAST_SENT_KEY = 'sensor_alert_last_sent';
const ONE_HOUR_MS = 60 * 60 * 1000;

function adcToPercent(raw) {
  if (raw == null || Number.isNaN(Number(raw))) return null;
  const clamped = Math.max(0, Math.min(4095, Number(raw)));
  const ratio = (4095 - clamped) / 4095;
  return Math.round(ratio * 100);
}

function fmtNum(value, digits = 1) {
  if (value == null || Number.isNaN(Number(value))) return '—';
  return Number(value).toFixed(digits);
}

/**
 * Đánh giá cảm biến mới nhất — trả về danh sách cảnh báo (tiếng Việt).
 */
function evaluateSensorAlerts(reading) {
  if (!reading || typeof reading !== 'object') return [];

  const alerts = [];
  const temp = reading.temperature != null ? Number(reading.temperature) : null;
  const humid = reading.humidity != null ? Number(reading.humidity) : null;
  const soilPct = adcToPercent(reading.soil_moisture);
  const rainPct = adcToPercent(reading.rain);

  const tMin = config.SENSOR_ALERT_TEMP_MIN;
  const tMax = config.SENSOR_ALERT_TEMP_MAX;
  const soilMin = config.SENSOR_ALERT_SOIL_MIN;
  const soilMax = config.SENSOR_ALERT_SOIL_MAX;
  const rainMin = config.SENSOR_ALERT_RAIN_MIN;
  const rainMax = config.SENSOR_ALERT_RAIN_MAX;
  const humidMin = config.SENSOR_ALERT_HUMIDITY_MIN;
  const humidMax = config.SENSOR_ALERT_HUMIDITY_MAX;

  if (temp != null && !Number.isNaN(temp)) {
    if (temp > tMax) {
      alerts.push(
        `Nhiệt độ quá cao (${fmtNum(temp)}°C, trên ${tMax}°C). Cần cẩn thận nhiệt độ hoặc bật màn che.`,
      );
    }
    if (temp < tMin) {
      alerts.push(
        `Nhiệt độ quá thấp (${fmtNum(temp)}°C, dưới ${tMin}°C). Cần theo dõi và bảo vệ cây.`,
      );
    }
  }

  if (humid != null && !Number.isNaN(humid)) {
    if (humid > humidMax) {
      alerts.push(
        `Ẩm không khí quá cao (${fmtNum(humid, 0)}%, trên ${humidMax}%). Cần thông thoáng.`,
      );
    }
    if (humid < humidMin) {
      alerts.push(
        `Ẩm không khí quá thấp (${fmtNum(humid, 0)}%, dưới ${humidMin}%). Cần tăng độ ẩm.`,
      );
    }
  }

  if (soilPct != null) {
    if (soilPct > soilMax) {
      alerts.push(
        `Ẩm đất quá cao (${soilPct}%, trên ${soilMax}%). Cần hạn chế tưới.`,
      );
    }
    if (soilPct < soilMin) {
      alerts.push(
        `Ẩm đất quá thấp (${soilPct}%, dưới ${soilMin}%). Cần tưới nước.`,
      );
    }
  }

  if (rainPct != null) {
    if (rainPct > rainMax) {
      alerts.push(
        `Lượng mưa quá cao (${rainPct}%, trên ${rainMax}%). Cần che chắn hoặc thoát nước.`,
      );
    }
    if (rainPct < rainMin) {
      alerts.push(
        `Lượng mưa quá thấp (${rainPct}%, dưới ${rainMin}%). Kiểm tra cảm biến hoặc tăng tưới nếu cần.`,
      );
    }
  }

  return alerts;
}

function getLatestReadingAsync() {
  return new Promise((resolve, reject) => {
    getLatestReading((err, row) => {
      if (err) reject(err);
      else resolve(row);
    });
  });
}

async function getLastAlertSentAt() {
  const raw = await getSettingAsync(LAST_SENT_KEY);
  if (!raw) return null;
  const ts = Date.parse(raw);
  return Number.isFinite(ts) ? ts : null;
}

async function markAlertSent() {
  await setSettingAsync(LAST_SENT_KEY, new Date().toISOString());
}

/**
 * Kiểm tra ngưỡng — tối đa 1 email/giờ khi bật trong Cấu hình.
 */
async function checkAndSendSensorAlert({ force = false } = {}) {
  const enabled = await getSensorAlertEnabledAsync();
  if (!enabled && !force) {
    return { skipped: true, reason: 'disabled' };
  }

  if (!isEmailConfigured()) {
    return { skipped: true, reason: 'email_not_configured' };
  }

  const lastSent = await getLastAlertSentAt();
  if (!force && lastSent != null && Date.now() - lastSent < ONE_HOUR_MS) {
    return { skipped: true, reason: 'rate_limited' };
  }

  const reading = await getLatestReadingAsync();
  if (!reading?.recorded_at) {
    return { skipped: true, reason: 'no_sensor_data' };
  }

  const alerts = evaluateSensorAlerts(reading);
  if (alerts.length === 0) {
    return { skipped: true, reason: 'within_thresholds' };
  }

  const bodyLines = [
    'Hệ thống phát hiện thông số vượt hoặc dưới ngưỡng cho phép:',
    '',
    ...alerts.map((line) => `• ${line}`),
    '',
    'Thông số hiện tại:',
    `- Nhiệt độ: ${fmtNum(reading.temperature)}°C (ngưỡng ${config.SENSOR_ALERT_TEMP_MIN}–${config.SENSOR_ALERT_TEMP_MAX}°C)`,
    `- Ẩm không khí: ${fmtNum(reading.humidity, 0)}% (ngưỡng ${config.SENSOR_ALERT_HUMIDITY_MIN}–${config.SENSOR_ALERT_HUMIDITY_MAX}%)`,
    `- Ẩm đất: ${adcToPercent(reading.soil_moisture) ?? '—'}% (ngưỡng ${config.SENSOR_ALERT_SOIL_MIN}–${config.SENSOR_ALERT_SOIL_MAX}%)`,
    `- Mưa: ${adcToPercent(reading.rain) ?? '—'}% (ngưỡng ${config.SENSOR_ALERT_RAIN_MIN}–${config.SENSOR_ALERT_RAIN_MAX}%)`,
    '',
    `Thời điểm đo: ${reading.recorded_at}`,
  ];

  const text = bodyLines.join('\n');
  const html = `
    <h2>Cảnh báo thông số vườn</h2>
    <ul>${alerts.map((line) => `<li>${line}</li>`).join('')}</ul>
    <p><strong>Thời điểm đo:</strong> ${reading.recorded_at}</p>
    <p style="color:#666;font-size:12px;">Tối đa 1 email cảnh báo mỗi giờ khi bật trong app.</p>
  `;

  await sendMail({
    subject: '[Plant IoT] Cảnh báo thông số vườn',
    text,
    html,
  });

  await markAlertSent();
  console.log(`[SENSOR-ALERT] Sent email (${alerts.length} warning(s))`);

  return {
    skipped: false,
    alertCount: alerts.length,
    alerts,
  };
}

module.exports = {
  evaluateSensorAlerts,
  checkAndSendSensorAlert,
  adcToPercent,
};
