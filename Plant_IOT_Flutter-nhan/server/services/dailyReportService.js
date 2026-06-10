const { getDb } = require('../config/database');
const { sendMail, isEmailConfigured } = require('./emailService');
const { adcToPercent } = require('./sensorAlertService');

const VN_OFFSET_MS = 7 * 60 * 60 * 1000;

function vnNow() {
  return new Date(Date.now() + VN_OFFSET_MS);
}

function vnDateKey(date = vnNow()) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function vnToUtcIso(dateKey, hour) {
  const h = String(hour).padStart(2, '0');
  return new Date(`${dateKey}T${h}:00:00+07:00`).toISOString();
}

function formatDateLabel(dateKey) {
  const [y, m, d] = dateKey.split('-');
  return `${d}/${m}/${y}`;
}

/** @returns {{ slot: 'morning' | 'evening', label: string, startIso: string, endIso: string }} */
function reportWindowForSlot(slot) {
  const now = vnNow();
  const todayKey = vnDateKey(now);

  if (slot === 'morning') {
    return {
      slot,
      label: `Buổi sáng (00:00–12:00) ngày ${formatDateLabel(todayKey)}`,
      startIso: vnToUtcIso(todayKey, 0),
      endIso: vnToUtcIso(todayKey, 12),
    };
  }

  const eveningDateKey = todayKey;
  const morningDateKey = (() => {
    const d = new Date(`${eveningDateKey}T12:00:00+07:00`);
    d.setUTCDate(d.getUTCDate() - 1);
    return vnDateKey(d);
  })();

  return {
    slot,
    label: `Buổi chiều/tối (12:00–24:00) ngày ${formatDateLabel(morningDateKey)}`,
    startIso: vnToUtcIso(morningDateKey, 12),
    endIso: vnToUtcIso(eveningDateKey, 0),
  };
}

function round1(value) {
  if (value == null || !Number.isFinite(Number(value))) return null;
  return Math.round(Number(value) * 10) / 10;
}

function queryOne(db, sql, params) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) reject(err);
      else resolve(row || {});
    });
  });
}

/** Thống kê cả ngày theo lịch VN (00:00–24:00). */
async function fetchDayStats(dateKey) {
  const startIso = vnToUtcIso(dateKey, 0);
  const endDate = new Date(`${dateKey}T00:00:00+07:00`);
  endDate.setUTCDate(endDate.getUTCDate() + 1);
  const endIso = endDate.toISOString();
  return fetchReportStats(startIso, endIso);
}

async function fetchReportStats(startIso, endIso) {
  const db = getDb();
  const sensorRow = await queryOne(
    db,
    `SELECT
       AVG(temperature) AS avg_temperature,
       AVG(humidity) AS avg_humidity,
       AVG(soil_moisture) AS avg_soil_moisture,
       AVG(rain) AS avg_rain,
       COUNT(*) AS sample_count
     FROM sensor_readings
     WHERE recorded_at >= ? AND recorded_at < ?`,
    [startIso, endIso],
  );
  const pumpRow = await queryOne(
    db,
    `SELECT COUNT(*) AS pump_count
     FROM pump_runs
     WHERE started_at >= ? AND started_at < ?`,
    [startIso, endIso],
  );

  return {
    avgTemperature: round1(sensorRow.avg_temperature),
    avgHumidity: round1(sensorRow.avg_humidity),
    avgSoilMoisture: adcToPercent(sensorRow.avg_soil_moisture),
    avgRain: adcToPercent(sensorRow.avg_rain),
    sampleCount: Number(sensorRow.sample_count) || 0,
    pumpCount: Number(pumpRow.pump_count) || 0,
  };
}

function fmt(value, unit = '') {
  if (value == null) return '—';
  return `${value}${unit}`;
}

function buildReportContent(window, stats) {
  const lines = [
    `Báo cáo vườn thông minh — ${window.label}`,
    '',
    `Nhiệt độ trung bình: ${fmt(stats.avgTemperature, ' °C')}`,
    `Độ ẩm đất trung bình: ${fmt(stats.avgSoilMoisture, ' %')}`,
    `Độ ẩm không khí trung bình: ${fmt(stats.avgHumidity, ' %')}`,
    `Mưa (độ ẩm cảm biến mưa) trung bình: ${fmt(stats.avgRain, ' %')}`,
    `Số lần chạy bơm: ${stats.pumpCount}`,
    '',
    `Số mẫu cảm biến: ${stats.sampleCount}`,
    `Khoảng thời gian (UTC): ${window.startIso} → ${window.endIso}`,
  ];

  const html = `
    <h2>Báo cáo vườn thông minh</h2>
    <p><strong>${window.label}</strong></p>
    <table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse;font-family:sans-serif;">
      <tr><td>Nhiệt độ trung bình</td><td>${fmt(stats.avgTemperature, ' °C')}</td></tr>
      <tr><td>Độ ẩm đất trung bình</td><td>${fmt(stats.avgSoilMoisture, ' %')}</td></tr>
      <tr><td>Độ ẩm không khí trung bình</td><td>${fmt(stats.avgHumidity, ' %')}</td></tr>
      <tr><td>Mưa (độ ẩm cảm biến) trung bình</td><td>${fmt(stats.avgRain, ' %')}</td></tr>
      <tr><td>Số lần chạy bơm</td><td>${stats.pumpCount}</td></tr>
      <tr><td>Số mẫu cảm biến</td><td>${stats.sampleCount}</td></tr>
    </table>
    <p style="color:#666;font-size:12px;">Plant IoT — gửi tự động lúc 12:00 trưa và 00:00 đêm (giờ VN).</p>
  `;

  return {
    subject: `[Plant IoT] ${window.label}`,
    text: lines.join('\n'),
    html,
  };
}

async function sendScheduledReport(slot) {
  if (!isEmailConfigured()) {
    console.warn('[EMAIL] Skipped report — email not configured');
    return { skipped: true, reason: 'not_configured' };
  }

  const window = slot === 'evening'
    ? reportWindowForSlot('evening')
    : reportWindowForSlot('morning');
  const stats = await fetchReportStats(window.startIso, window.endIso);
  const content = buildReportContent(window, stats);
  const info = await sendMail(content);
  console.log(`[EMAIL] Sent ${slot} report to ${info.envelope?.to || 'recipient'} (${stats.sampleCount} samples)`);
  return { skipped: false, slot, stats, messageId: info.messageId };
}

module.exports = {
  vnNow,
  vnDateKey,
  formatDateLabel,
  vnToUtcIso,
  reportWindowForSlot,
  fetchReportStats,
  fetchDayStats,
  buildReportContent,
  sendScheduledReport,
  fmt,
};
