const { config } = require('../config/env');
const { performPumpActionAsync } = require('./relayActionService');
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
  if (slot === 'afternoon') return '17:00 chiều';
  return slot;
}

function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
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
      'Máy bơm được điều khiển qua cùng API relay như trang Điều khiển (pump_on → pump_off).',
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

  const durationMs = Math.max(5, config.AUTO_WATER_PUMP_SECONDS) * 1000;
  console.log(`[AUTO-WATER] Starting ${slot}: pump_on (${config.AUTO_WATER_PUMP_SECONDS}s)`);

  await performPumpActionAsync(true, 'auto_water', hooks);
  await notifyAutoWaterStarted(slot).catch((err) => {
    console.error('[AUTO-WATER] Email notify failed:', err.message);
  });

  await delay(durationMs);

  await performPumpActionAsync(false, 'auto_water', hooks);
  console.log(`[AUTO-WATER] Finished ${slot}: pump_off`);

  return { skipped: false, slot, durationSeconds: config.AUTO_WATER_PUMP_SECONDS };
}

module.exports = {
  runAutoWaterCycle,
  slotLabel,
};
