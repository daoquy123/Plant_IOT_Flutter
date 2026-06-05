const cron = require('node-cron');
const { config } = require('../config/env');
const { isEmailConfigured } = require('../services/emailService');
const { sendScheduledReport } = require('../services/dailyReportService');

const VN_TZ = 'Asia/Ho_Chi_Minh';
const jobs = [];

function runReport(slot) {
  sendScheduledReport(slot).catch((err) => {
    console.error(`[EMAIL] Failed to send ${slot} report:`, err.message);
  });
}

function startDailyEmailScheduler() {
  if (!config.EMAIL_REPORTS_ENABLED) {
    console.log('[EMAIL] Daily reports disabled (EMAIL_REPORTS_ENABLED=false)');
    return [];
  }
  if (!isEmailConfigured()) {
    console.warn('[EMAIL] Daily reports not started — missing EMAIL_* or REPORT_EMAIL_TO');
    return [];
  }

  const noonJob = cron.schedule(
    '0 12 * * *',
    () => runReport('morning'),
    { timezone: VN_TZ },
  );
  const midnightJob = cron.schedule(
    '0 0 * * *',
    () => runReport('evening'),
    { timezone: VN_TZ },
  );

  jobs.push(noonJob, midnightJob);
  console.log('[EMAIL] Scheduled reports: 12:00 trưa & 00:00 đêm (Asia/Ho_Chi_Minh)');
  return jobs;
}

function stopDailyEmailScheduler() {
  jobs.forEach((job) => job.stop());
  jobs.length = 0;
}

module.exports = {
  startDailyEmailScheduler,
  stopDailyEmailScheduler,
};
