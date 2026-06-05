const cron = require('node-cron');
const { isEmailConfigured } = require('../services/emailService');
const { checkAndSendSensorAlert } = require('../services/sensorAlertService');

const VN_TZ = 'Asia/Ho_Chi_Minh';
const jobs = [];

function startSensorAlertScheduler() {
  if (!isEmailConfigured()) {
    console.warn('[SENSOR-ALERT] Scheduler not started — email not configured');
    return [];
  }

  const hourlyJob = cron.schedule(
    '5 * * * *',
    () => {
      checkAndSendSensorAlert().catch((err) => {
        console.error('[SENSOR-ALERT] Hourly check failed:', err.message);
      });
    },
    { timezone: VN_TZ },
  );

  jobs.push(hourlyJob);
  console.log('[SENSOR-ALERT] Scheduled threshold check every hour (max 1 email/hour)');
  return jobs;
}

function stopSensorAlertScheduler() {
  jobs.forEach((job) => job.stop());
  jobs.length = 0;
}

module.exports = {
  startSensorAlertScheduler,
  stopSensorAlertScheduler,
};
