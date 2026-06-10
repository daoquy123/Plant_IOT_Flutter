const cron = require('node-cron');
const { config } = require('../config/env');
const {
  loadLatestCameraImageBytes,
  predictWithResNet,
} = require('../services/pestAlertService');
const { recordFromPredictResult } = require('../services/leafAnalysisService');

const VN_TZ = 'Asia/Ho_Chi_Minh';
const jobs = [];

async function runHourlyLeafAnalysis() {
  if (!(config.AI_SERVER_URL || '').trim()) {
    return { skipped: true, reason: 'no_ai_server' };
  }

  const image = await loadLatestCameraImageBytes();
  if (!image) {
    return { skipped: true, reason: 'no_image' };
  }

  let prediction;
  try {
    prediction = await predictWithResNet(image.bytes, image.filename);
  } catch (err) {
    console.error('[LEAF-SCAN] Predict failed:', err.message);
    return { skipped: true, reason: 'predict_failed', error: err.message };
  }

  const { result } = prediction;
  await recordFromPredictResult({
    result,
    model: 'resnet',
    source: 'hourly_scan',
  });

  return {
    skipped: false,
    label: result?.label ?? null,
    unhealthy: result?.label != null,
  };
}

function startLeafAnalysisScheduler() {
  const hourlyJob = cron.schedule(
    '20 * * * *',
    () => {
      runHourlyLeafAnalysis().catch((err) => {
        console.error('[LEAF-SCAN] Hourly analysis failed:', err.message);
      });
    },
    { timezone: VN_TZ },
  );

  jobs.push(hourlyJob);
  console.log('[LEAF-SCAN] Scheduled hourly leaf analysis at :20 (Asia/Ho_Chi_Minh)');
  return jobs;
}

function stopLeafAnalysisScheduler() {
  jobs.forEach((job) => job.stop());
  jobs.length = 0;
}

module.exports = {
  startLeafAnalysisScheduler,
  stopLeafAnalysisScheduler,
  runHourlyLeafAnalysis,
};
