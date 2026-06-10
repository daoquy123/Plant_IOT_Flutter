const { config } = require('../config/env');
const { sendMail, isEmailConfigured } = require('./emailService');
const {
  vnNow,
  vnDateKey,
  formatDateLabel,
  fetchDayStats,
  fmt,
} = require('./dailyReportService');
const { countUnhealthyForDay, countAllForDay } = require('./leafAnalysisService');
const {
  getWateringBoostLeafActiveAsync,
  setWateringBoostLeafActiveAsync,
  getWateringBoostActiveAsync,
  NORMAL_WATERING_SESSIONS,
  BOOST_WATERING_SESSIONS,
} = require('./settingsService');

function soilMaxForLeafBoost() {
  return config.SENSOR_ALERT_SOIL_MIN + config.LEAF_HEALTH_SOIL_MAX_OFFSET;
}

function buildLeafDayReportLines(dateKey, stats, leafStats) {
  const label = formatDateLabel(dateKey);
  const soilCap = soilMaxForLeafBoost();
  return [
    `Ngày ${label}`,
    '',
    `Số lần phân tích lá vàng trở lên: ${leafStats.unhealthyCount}`,
    `Tổng số lần phân tích AI trong ngày: ${leafStats.totalAnalyses}`,
    `Ngưỡng kích hoạt: ≥ ${config.LEAF_HEALTH_MIN_UNHEALTHY_COUNT} lần lá vàng+`,
    '',
    `Nhiệt độ trung bình: ${fmt(stats.avgTemperature, ' °C')}`,
    `Độ ẩm đất trung bình: ${fmt(stats.avgSoilMoisture, ' %')}`,
    `Độ ẩm không khí trung bình: ${fmt(stats.avgHumidity, ' %')}`,
    `Số lần chạy bơm: ${stats.pumpCount}`,
    '',
    `Điều kiện ẩm đất: chưa vượt ${soilCap}% (ngưỡng ${config.SENSOR_ALERT_SOIL_MIN}% + ${config.LEAF_HEALTH_SOIL_MAX_OFFSET}%)`,
  ];
}

function buildLeafDayReportHtml(dateKey, stats, leafStats, extraHtml) {
  const label = formatDateLabel(dateKey);
  const soilCap = soilMaxForLeafBoost();
  return `
    <h2>Báo cáo sức khỏe lá — ${label}</h2>
    <table cellpadding="6" cellspacing="0" border="1" style="border-collapse:collapse;font-family:sans-serif;">
      <tr><td>Lá vàng trở lên (trong ngày)</td><td><strong>${leafStats.unhealthyCount}</strong></td></tr>
      <tr><td>Tổng phân tích AI</td><td>${leafStats.totalAnalyses}</td></tr>
      <tr><td>Độ ẩm đất TB</td><td>${fmt(stats.avgSoilMoisture, ' %')}</td></tr>
      <tr><td>Nhiệt độ TB</td><td>${fmt(stats.avgTemperature, ' °C')}</td></tr>
      <tr><td>Số lần bơm</td><td>${stats.pumpCount}</td></tr>
      <tr><td>Ngưỡng ẩm đất cho phép tăng tưới</td><td>≤ ${soilCap}%</td></tr>
    </table>
    ${extraHtml || ''}
    <p style="color:#666;font-size:12px;">Kiểm tra tự động lúc 22:00 mỗi ngày (giờ VN).</p>
  `;
}

async function sendLeafBoostActivatedEmail(dateKey, stats, leafStats) {
  const extraText = [
    '',
    `⚠ Trong ngày có ${leafStats.unhealthyCount} lần phân tích lá vàng trở lên (≥ ${config.LEAF_HEALTH_MIN_UNHEALTHY_COUNT}).`,
    `Độ ẩm đất TB ${stats.avgSoilMoisture}% chưa vượt ${soilMaxForLeafBoost()}%.`,
    '',
    `Tình trạng cây chưa ổn — từ ngày mai tưới tự động ${BOOST_WATERING_SESSIONS} lần/ngày (6:00, 12:00, 17:00).`,
    'Gợi ý lịch tưới trong chatbot cũng cập nhật.',
    '',
    `Khi số lần lá vàng+ trong ngày dưới ${config.LEAF_HEALTH_MIN_UNHEALTHY_COUNT}, lịch tưới về ${NORMAL_WATERING_SESSIONS} lần và có thông báo.`,
  ].join('\n');

  const extraHtml = `
    <p style="color:#c0392b;"><strong>Cây không ổn:</strong> ${leafStats.unhealthyCount} lần lá vàng+ / ngày.</p>
    <p>Ẩm đất TB ${stats.avgSoilMoisture}% ≤ ${soilMaxForLeafBoost()}% — hệ thống <strong>tăng tưới lên ${BOOST_WATERING_SESSIONS} lần/ngày</strong> từ ngày mai.</p>
  `;

  await sendMail({
    subject: `[Plant IoT] Cây không ổn — tăng tưới lên ${BOOST_WATERING_SESSIONS} lần/ngày`,
    text: [...buildLeafDayReportLines(dateKey, stats, leafStats), extraText].join('\n'),
    html: buildLeafDayReportHtml(dateKey, stats, leafStats, extraHtml),
  });
}

async function sendLeafBoostRevertedEmail(dateKey, stats, leafStats) {
  const extraText = [
    '',
    `✓ Số lần lá vàng+ trong ngày còn ${leafStats.unhealthyCount} (dưới ${config.LEAF_HEALTH_MIN_UNHEALTHY_COUNT}).`,
    '',
    `Lịch tưới tự động trở lại ${NORMAL_WATERING_SESSIONS} lần/ngày (6:00 và 17:00).`,
    'Gợi ý trong chatbot cũng cập nhật.',
  ].join('\n');

  const extraHtml = `
    <p style="color:#27ae60;"><strong>Tình trạng lá đã cải thiện</strong> (${leafStats.unhealthyCount} lần lá vàng+).</p>
    <p>Lịch tưới về <strong>${NORMAL_WATERING_SESSIONS} lần/ngày</strong>.</p>
  `;

  await sendMail({
    subject: `[Plant IoT] Cây ổn định — về lịch tưới ${NORMAL_WATERING_SESSIONS} lần/ngày`,
    text: [...buildLeafDayReportLines(dateKey, stats, leafStats), extraText].join('\n'),
    html: buildLeafDayReportHtml(dateKey, stats, leafStats, extraHtml),
  });
}

/**
 * 22:00: đếm lá vàng+ trong ngày.
 * - Không có phân tích AI trong ngày → bỏ qua
 * - ≥ 10 lần lá vàng+ và ẩm đất TB ≤ min+15% → boost leaf + email
 * - Đang boost leaf và < 10 lá vàng+ → tắt boost leaf + email
 */
async function runNightlyLeafHealthCheck({ dateKey = null } = {}) {
  const todayKey = dateKey || vnDateKey(vnNow());
  const [unhealthyCount, totalAnalyses] = await Promise.all([
    countUnhealthyForDay(todayKey),
    countAllForDay(todayKey),
  ]);

  const leafStats = {
    unhealthyCount,
    totalAnalyses,
  };

  if (totalAnalyses <= 0) {
    return { skipped: true, reason: 'no_analyses', dateKey: todayKey, ...leafStats };
  }

  const stats = await fetchDayStats(todayKey);
  const soilCap = soilMaxForLeafBoost();
  const boostLeafActive = await getWateringBoostLeafActiveAsync();
  const minUnhealthy = config.LEAF_HEALTH_MIN_UNHEALTHY_COUNT;
  const unhealthyHigh = leafStats.unhealthyCount >= minUnhealthy;
  const unhealthyOk = leafStats.unhealthyCount < minUnhealthy;
  const soilAllowsBoost = stats.avgSoilMoisture != null
    && stats.sampleCount > 0
    && stats.avgSoilMoisture <= soilCap;

  if (boostLeafActive) {
    if (!unhealthyOk) {
      return {
        skipped: true,
        reason: 'still_unhealthy_boost_active',
        dateKey: todayKey,
        ...leafStats,
        avgSoilMoisture: stats.avgSoilMoisture,
      };
    }
    await setWateringBoostLeafActiveAsync(false);
    if (isEmailConfigured()) {
      await sendLeafBoostRevertedEmail(todayKey, stats, leafStats);
    }
    console.log(`[LEAF-PLAN] Reverted leaf boost — ${leafStats.unhealthyCount} unhealthy analyses`);
    return {
      action: 'reverted',
      dateKey: todayKey,
      ...leafStats,
      sessionsPerDay: NORMAL_WATERING_SESSIONS,
    };
  }

  if (unhealthyHigh && soilAllowsBoost) {
    await setWateringBoostLeafActiveAsync(true);
    if (isEmailConfigured()) {
      await sendLeafBoostActivatedEmail(todayKey, stats, leafStats);
    }
    console.log(
      `[LEAF-PLAN] Leaf boost activated — ${leafStats.unhealthyCount} unhealthy, soil ${stats.avgSoilMoisture}%`,
    );
    return {
      action: 'boosted',
      dateKey: todayKey,
      ...leafStats,
      avgSoilMoisture: stats.avgSoilMoisture,
      sessionsPerDay: BOOST_WATERING_SESSIONS,
    };
  }

  if (unhealthyHigh && !soilAllowsBoost) {
    return {
      skipped: true,
      reason: 'soil_too_high_for_boost',
      dateKey: todayKey,
      ...leafStats,
      avgSoilMoisture: stats.avgSoilMoisture,
      soilCap,
    };
  }

  return {
    skipped: true,
    reason: 'within_threshold',
    dateKey: todayKey,
    ...leafStats,
  };
}

async function getLeafHealthPlanSummary() {
  const todayKey = vnDateKey(vnNow());
  const [unhealthyCount, totalAnalyses] = await Promise.all([
    countUnhealthyForDay(todayKey),
    countAllForDay(todayKey),
  ]);
  const boostLeafActive = await getWateringBoostLeafActiveAsync();
  const boostAny = await getWateringBoostActiveAsync();
  return {
    todayUnhealthyCount: unhealthyCount,
    todayTotalAnalyses: totalAnalyses,
    minUnhealthyToBoost: config.LEAF_HEALTH_MIN_UNHEALTHY_COUNT,
    soilMaxForBoost: soilMaxForLeafBoost(),
    boostLeafActive,
    boostActive: boostAny,
  };
}

module.exports = {
  runNightlyLeafHealthCheck,
  getLeafHealthPlanSummary,
  soilMaxForLeafBoost,
};
