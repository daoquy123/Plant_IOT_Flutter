const cron = require('node-cron');
const { isEmailConfigured } = require('../services/emailService');
const { config } = require('../config/env');
const { checkAndSendPestAlert } = require('../services/pestAlertService');

const VN_TZ = 'Asia/Ho_Chi_Minh';
const jobs = [];

function startPestAlertScheduler() {
  if (!isEmailConfigured()) {
    console.warn('[PEST-ALERT] Scheduler not started — email not configured');
    return [];
  }
  if (!(config.AI_SERVER_URL || '').trim()) {
    console.warn('[PEST-ALERT] Scheduler not started — missing AI_SERVER_URL');
    return [];
  }

  const hourlyJob = cron.schedule(
    '35 * * * *',
    () => {
      checkAndSendPestAlert().catch((err) => {
        console.error('[PEST-ALERT] Hourly check failed:', err.message);
      });
    },
    { timezone: VN_TZ },
  );

  jobs.push(hourlyJob);
  console.log('[PEST-ALERT] Scheduled ResNet camera check every hour (max 1 email/hour if pest)');
  return jobs;
}

function stopPestAlertScheduler() {
  jobs.forEach((job) => job.stop());
  jobs.length = 0;
}

module.exports = {
  startPestAlertScheduler,
  stopPestAlertScheduler,
};
