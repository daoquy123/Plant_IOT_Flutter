const cron = require('node-cron');
const { isEmailConfigured } = require('../services/emailService');
const { runNightlySoilMoistureCheck } = require('../services/soilMoisturePlanService');
const { runNightlyLeafHealthCheck } = require('../services/leafHealthPlanService');

const VN_TZ = 'Asia/Ho_Chi_Minh';
const jobs = [];

function startSoilMoisturePlanScheduler() {
  const nightlyJob = cron.schedule(
    '0 22 * * *',
    () => {
      runNightlySoilMoistureCheck().catch((err) => {
        console.error('[SOIL-PLAN] Nightly check failed:', err.message);
      });
      runNightlyLeafHealthCheck().catch((err) => {
        console.error('[LEAF-PLAN] Nightly check failed:', err.message);
      });
    },
    { timezone: VN_TZ },
  );

  jobs.push(nightlyJob);
  console.log('[SOIL-PLAN] Scheduled nightly soil + leaf health check at 22:00 (Asia/Ho_Chi_Minh)');
  if (!isEmailConfigured()) {
    console.warn('[SOIL-PLAN] Email not configured — plan changes still apply, notifications skipped');
  }
  return jobs;
}

function stopSoilMoisturePlanScheduler() {
  jobs.forEach((job) => job.stop());
  jobs.length = 0;
}

module.exports = {
  startSoilMoisturePlanScheduler,
  stopSoilMoisturePlanScheduler,
};
