const { config } = require('../config/env');
const { runPumpSession } = require('./relayActionService');
const { getAutoWaterEnabledAsync } = require('./settingsService');
const { sendMail, isEmailConfigured } = require('./emailService');

const VN_OFFSET_MS = 7 * 60 * 60 * 1000;

function vnNowLabel() {
  const d = new Date(Date.now() + VN_OFFSET_MS);
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}

function slotLabel(slot) {
  if (slot === 'morning') return '6:00 sáng';
  if (slot === 'noon') return '12:00 trưa';
  if (slot === 'afternoon') return '17:00 chiều';
  return slot;
}

async function notifyAutoWaterStarted(slot) {
  if (!isEmailConfigured()) return;
  const when = vnNowLabel();
  const label = slotLabel(slot);
  await sendMail({
    subject: `[Plant IoT] Đang tự động tưới (${label})`,
    text: [
      'Hệ thống vừa bật máy bơm tự động.',
      '',
      `Khung giờ: ${label}`,
      `Thời điểm: ${when} (giờ VN)`,
      '',
      'Máy bơm chạy một phiên (bật → chờ → tự tắt) giống trang Điều khiển.',
    ].join('\n'),
    html: `
      <h2>Đang tự động tưới</h2>
      <p>Hệ thống vừa <strong>bật máy bơm</strong> theo lịch tưới tự động.</p>
      <ul>
        <li>Khung giờ: <strong>${label}</strong></li>
        <li>Thời điểm: <strong>${when}</strong> (giờ VN)</li>
      </ul>
      <p style="color:#666;font-size:12px;">Cùng luồng relay với trang Điều khiển trong app.</p>
    `,
  });
}

/**
 * One auto-water cycle: pump_on (same as control screen) → wait → pump_off.
 */
async function runAutoWaterCycle(slot, hooks, { force = false } = {}) {
  const enabled = await getAutoWaterEnabledAsync();
  if (!enabled && !force) {
    console.log(`[AUTO-WATER] Skipped ${slot} — disabled in settings`);
    return { skipped: true, reason: 'disabled' };
  }

  const durationSeconds = Math.max(5, config.AUTO_WATER_PUMP_SECONDS);
  console.log(`[AUTO-WATER] Starting ${slot}: pump session (${durationSeconds}s)`);

  const result = await runPumpSession('auto_water', hooks, {
    durationSeconds,
    onStarted: () =>
      notifyAutoWaterStarted(slot).catch((err) => {
        console.error('[AUTO-WATER] Email notify failed:', err.message);
      }),
  });
  console.log(`[AUTO-WATER] Finished ${slot}: session ended`);

  return { skipped: false, slot, durationSeconds: result.durationSeconds };
}

module.exports = {
  runAutoWaterCycle,
  slotLabel,
};
