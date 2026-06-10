const { config } = require('../config/env');
const { sendMail, isEmailConfigured } = require('./emailService');
const {
  vnNow,
  vnDateKey,
  formatDateLabel,
  fetchDayStats,
  fmt,
} = require('./dailyReportService');
const {
  getWateringBoostActiveAsync,
  setWateringBoostActiveAsync,
  getWateringSessionsPerDayAsync,
  NORMAL_WATERING_SESSIONS,
  BOOST_WATERING_SESSIONS,
} = require('./settingsService');

function buildDayReportLines(dateKey, stats) {
  const label = formatDateLabel(dateKey);
  return [
    `Ngày ${label}`,
    '',
    `Nhiệt độ trung bình: ${fmt(stats.avgTemperature, ' °C')}`,
    `Độ ẩm đất trung bình: ${fmt(stats.avgSoilMoisture, ' %')}`,
    `Độ ẩm không khí trung bình: ${fmt(stats.avgHumidity, ' %')}`,
    `Mưa (cảm biến) trung bình: ${fmt(stats.avgRain, ' %')}`,
    `Số lần chạy bơm: ${stats.pumpCount}`,
    `Số mẫu cảm biến: ${stats.sampleCount}`,
    '',
    `Ngưỡng ẩm đất an toàn: ≥ ${config.SENSOR_ALERT_SOIL_MIN}%`,
  ];
}

function buildDayReportHtml(dateKey, stats, extraHtml) {
  const label = formatDateLabel(dateKey);
  return `
    <h2>Báo cáo ẩm đất — ${label}</h2>
    <table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse;font-family:sans-serif;">
      <tr><td>Nhiệt độ trung bình</td><td>${fmt(stats.avgTemperature, ' °C')}</td></tr>
      <tr><td>Độ ẩm đất trung bình</td><td>${fmt(stats.avgSoilMoisture, ' %')}</td></tr>
      <tr><td>Độ ẩm không khí trung bình</td><td>${fmt(stats.avgHumidity, ' %')}</td></tr>
      <tr><td>Mưa (cảm biến) trung bình</td><td>${fmt(stats.avgRain, ' %')}</td></tr>
      <tr><td>Số lần chạy bơm</td><td>${stats.pumpCount}</td></tr>
      <tr><td>Số mẫu cảm biến</td><td>${stats.sampleCount}</td></tr>
      <tr><td>Ngưỡng ẩm đất an toàn</td><td>≥ ${config.SENSOR_ALERT_SOIL_MIN}%</td></tr>
    </table>
    ${extraHtml || ''}
    <p style="color:#666;font-size:12px;">Kiểm tra tự động lúc 22:00 mỗi ngày (giờ VN).</p>
  `;
}

async function sendBoostActivatedEmail(dateKey, stats) {
  const threshold = config.SENSOR_ALERT_SOIL_MIN;
  const extraText = [
    '',
    `⚠ Độ ẩm đất trung bình (${stats.avgSoilMoisture}%) thấp hơn ngưỡng an toàn (${threshold}%).`,
    '',
    `Từ ngày mai hệ thống sẽ tưới tự động ${BOOST_WATERING_SESSIONS} lần/ngày (6:00, 12:00, 17:00) thay vì ${NORMAL_WATERING_SESSIONS} lần.`,
    'Gợi ý trong chatbot cũng cập nhật tương ứng.',
    '',
    'Khi ẩm đất trở lại bình thường, lịch tưới sẽ về 2 lần/ngày và bạn sẽ nhận email thông báo.',
  ].join('\n');

  const extraHtml = `
    <p style="color:#c0392b;"><strong>Độ ẩm đất trung bình (${stats.avgSoilMoisture}%) thấp hơn ngưỡng ${threshold}%.</strong></p>
    <p>Từ <strong>ngày mai</strong> hệ thống tưới tự động <strong>${BOOST_WATERING_SESSIONS} lần/ngày</strong> (6:00, 12:00, 17:00) thay vì ${NORMAL_WATERING_SESSIONS} lần.</p>
    <p>Gợi ý lịch tưới trong chatbot cũng hiển thị <strong>${BOOST_WATERING_SESSIONS} lần</strong>.</p>
  `;

  await sendMail({
    subject: `[Plant IoT] Ẩm đất thấp — tăng tưới lên ${BOOST_WATERING_SESSIONS} lần/ngày`,
    text: [...buildDayReportLines(dateKey, stats), extraText].join('\n'),
    html: buildDayReportHtml(dateKey, stats, extraHtml),
  });
}

async function sendBoostRevertedEmail(dateKey, stats) {
  const extraText = [
    '',
    `✓ Độ ẩm đất trung bình (${stats.avgSoilMoisture}%) đã về mức an toàn (≥ ${config.SENSOR_ALERT_SOIL_MIN}%).`,
    '',
    `Lịch tưới tự động trở lại ${NORMAL_WATERING_SESSIONS} lần/ngày (6:00 và 17:00).`,
    'Gợi ý trong chatbot cũng cập nhật tương ứng.',
  ].join('\n');

  const extraHtml = `
    <p style="color:#27ae60;"><strong>Độ ẩm đất trung bình (${stats.avgSoilMoisture}%) đã về mức an toàn.</strong></p>
    <p>Lịch tưới tự động trở lại <strong>${NORMAL_WATERING_SESSIONS} lần/ngày</strong> (6:00 và 17:00).</p>
  `;

  await sendMail({
    subject: `[Plant IoT] Ẩm đất ổn định — về lịch tưới ${NORMAL_WATERING_SESSIONS} lần/ngày`,
    text: [...buildDayReportLines(dateKey, stats), extraText].join('\n'),
    html: buildDayReportHtml(dateKey, stats, extraHtml),
  });
}

/**
 * 22:00 mỗi ngày: kiểm tra ẩm đất TB trong ngày.
 * - Không có dữ liệu → bỏ qua
 * - Thấp + chưa boost → bật boost (3 lần/ngày từ mai) + email
 * - Boost + đã ổn → tắt boost (2 lần/ngày) + email
 * - Còn lại → không làm gì
 */
async function runNightlySoilMoistureCheck({ dateKey = null } = {}) {
  const todayKey = dateKey || vnDateKey(vnNow());
  const stats = await fetchDayStats(todayKey);

  if (stats.avgSoilMoisture == null || stats.sampleCount <= 0) {
    return { skipped: true, reason: 'no_data', dateKey: todayKey };
  }

  const threshold = config.SENSOR_ALERT_SOIL_MIN;
  const boostActive = await getWateringBoostActiveAsync();
  const isLow = stats.avgSoilMoisture < threshold;
  const isOk = stats.avgSoilMoisture >= threshold;

  if (boostActive) {
    if (!isOk) {
      return {
        skipped: true,
        reason: 'still_low_boost_active',
        dateKey: todayKey,
        avgSoilMoisture: stats.avgSoilMoisture,
      };
    }
    if (isOk) {
      await setWateringBoostActiveAsync(false);
      if (isEmailConfigured()) {
        await sendBoostRevertedEmail(todayKey, stats);
      }
      console.log(
        `[SOIL-PLAN] Reverted to ${NORMAL_WATERING_SESSIONS}x/day — avg soil ${stats.avgSoilMoisture}%`,
      );
      return {
        action: 'reverted',
        dateKey: todayKey,
        avgSoilMoisture: stats.avgSoilMoisture,
        sessionsPerDay: NORMAL_WATERING_SESSIONS,
      };
    }
  } else if (isLow) {
    await setWateringBoostActiveAsync(true);
    if (isEmailConfigured()) {
      await sendBoostActivatedEmail(todayKey, stats);
    }
    console.log(
      `[SOIL-PLAN] Boost activated — avg soil ${stats.avgSoilMoisture}% < ${threshold}%`,
    );
    return {
      action: 'boosted',
      dateKey: todayKey,
      avgSoilMoisture: stats.avgSoilMoisture,
      sessionsPerDay: BOOST_WATERING_SESSIONS,
    };
  }

  return {
    skipped: true,
    reason: 'within_threshold',
    dateKey: todayKey,
    avgSoilMoisture: stats.avgSoilMoisture,
  };
}

async function getWateringPlan() {
  const boostActive = await getWateringBoostActiveAsync();
  const sessionsPerDay = await getWateringSessionsPerDayAsync();
  return {
    boostActive,
    sessionsPerDay,
    normalSessions: NORMAL_WATERING_SESSIONS,
    boostSessions: BOOST_WATERING_SESSIONS,
    soilThresholdMin: config.SENSOR_ALERT_SOIL_MIN,
    schedule: boostActive
      ? ['06:00', '12:00', '17:00']
      : ['06:00', '17:00'],
  };
}

module.exports = {
  runNightlySoilMoistureCheck,
  getWateringPlan,
  sendBoostActivatedEmail,
  sendBoostRevertedEmail,
};
