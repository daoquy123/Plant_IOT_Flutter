/**
 * Gửi thử email báo cáo ngay (không đợi cron).
 * Usage (from server/):
 *   npm run email:report
 *   npm run email:report -- morning
 *   npm run email:report -- evening
 */
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { getDb } = require('../config/database');
const { sendScheduledReport } = require('../services/dailyReportService');

const slot = (process.argv[2] || 'morning').toLowerCase() === 'evening' ? 'evening' : 'morning';

getDb();

sendScheduledReport(slot)
  .then((result) => {
    if (result.skipped) {
      console.error('Email skipped:', result.reason);
      process.exit(1);
    }
    console.log('Sent:', result);
    process.exit(0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
