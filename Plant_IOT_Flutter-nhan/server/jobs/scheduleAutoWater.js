const cron = require('node-cron');
const { runAutoWaterCycle } = require('../services/autoWaterService');

const VN_TZ = 'Asia/Ho_Chi_Minh';
const jobs = [];
let relayHooks = {};

function setRelayHooks(hooks) {
  relayHooks = hooks || {};
}

function runCycle(slot) {
  runAutoWaterCycle(slot, relayHooks).catch((err) => {
    console.error(`[AUTO-WATER] Failed ${slot}:`, err.message);
  });
}

function startAutoWaterScheduler(hooks) {
  setRelayHooks(hooks);

  const morningJob = cron.schedule(
    '0 6 * * *',
    () => runCycle('morning'),
    { timezone: VN_TZ },
  );
  const afternoonJob = cron.schedule(
    '0 17 * * *',
    () => runCycle('afternoon'),
    { timezone: VN_TZ },
  );

  jobs.push(morningJob, afternoonJob);
  console.log('[AUTO-WATER] Scheduled: 6:00 sáng & 17:00 chiều (Asia/Ho_Chi_Minh)');
  return jobs;
}

function stopAutoWaterScheduler() {
  jobs.forEach((job) => job.stop());
  jobs.length = 0;
}

module.exports = {
  startAutoWaterScheduler,
  stopAutoWaterScheduler,
  setRelayHooks,
};
