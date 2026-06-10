const express = require('express');
const {
  getAutoWaterEnabled,
  setAutoWaterEnabled,
  getSensorAlertEnabled,
  setSensorAlertEnabled,
  getPestAlertEnabled,
  setPestAlertEnabled,
} = require('../../services/settingsService');
const { runAutoWaterCycle } = require('../../services/autoWaterService');
const { sendScheduledReport } = require('../../services/dailyReportService');
const { checkAndSendSensorAlert } = require('../../services/sensorAlertService');
const { checkAndSendPestAlert } = require('../../services/pestAlertService');
const {
  getWateringPlan,
  runNightlySoilMoistureCheck,
} = require('../../services/soilMoisturePlanService');

const router = express.Router();

router.get('/auto-water', (req, res, next) => {
  getAutoWaterEnabled((err, enabled) => {
    if (err) return next(err);
    res.json({ success: true, enabled: !!enabled });
  });
});

router.put('/auto-water', (req, res, next) => {
  const enabled = req.body?.enabled === true
    || req.body?.enabled === 1
    || String(req.body?.enabled).toLowerCase() === 'true';
  setAutoWaterEnabled(enabled, (err) => {
    if (err) return next(err);
    res.json({ success: true, enabled });
  });
});

router.get('/sensor-alert', (req, res, next) => {
  getSensorAlertEnabled((err, enabled) => {
    if (err) return next(err);
    res.json({ success: true, enabled: !!enabled });
  });
});

router.put('/sensor-alert', (req, res, next) => {
  const enabled = req.body?.enabled === true
    || req.body?.enabled === 1
    || String(req.body?.enabled).toLowerCase() === 'true';
  setSensorAlertEnabled(enabled, (err) => {
    if (err) return next(err);
    res.json({ success: true, enabled });
  });
});

/** @deprecated — dùng /sensor-alert */
router.get('/email-report', (req, res, next) => {
  getSensorAlertEnabled((err, enabled) => {
    if (err) return next(err);
    res.json({ success: true, enabled: !!enabled });
  });
});

/** @deprecated — dùng /sensor-alert */
router.put('/email-report', (req, res, next) => {
  const enabled = req.body?.enabled === true
    || req.body?.enabled === 1
    || String(req.body?.enabled).toLowerCase() === 'true';
  setSensorAlertEnabled(enabled, (err) => {
    if (err) return next(err);
    res.json({ success: true, enabled });
  });
});

router.post('/sensor-alert/test', (req, res) => {
  res.status(202).json({
    success: true,
    started: true,
    message: 'Đã chạy kiểm tra ngưỡng — email chỉ gửi nếu vượt ngưỡng.',
  });
  checkAndSendSensorAlert({ force: true }).catch((err) => {
    console.error('[SENSOR-ALERT] Manual test failed:', err.message);
  });
});

router.get('/pest-alert', (req, res, next) => {
  getPestAlertEnabled((err, enabled) => {
    if (err) return next(err);
    res.json({ success: true, enabled: !!enabled });
  });
});

router.put('/pest-alert', (req, res, next) => {
  const enabled = req.body?.enabled === true
    || req.body?.enabled === 1
    || String(req.body?.enabled).toLowerCase() === 'true';
  setPestAlertEnabled(enabled, (err) => {
    if (err) return next(err);
    res.json({ success: true, enabled });
  });
});

router.post('/pest-alert/test', (req, res) => {
  res.status(202).json({
    success: true,
    started: true,
    message: 'Đã chạy kiểm tra ResNet trên ảnh camera — email chỉ gửi nếu phát hiện sâu.',
  });
  checkAndSendPestAlert({ force: true }).catch((err) => {
    console.error('[PEST-ALERT] Manual test failed:', err.message);
  });
});

/** Gửi thử một chu kỳ tưới (pump_on → chờ → pump_off). Trả 202 ngay — tránh Nginx 504. */
router.post('/auto-water/test', (req, res) => {
  const hooks = {
    io: req.app.locals.io,
    publishRelayState: req.app.locals.publishRelayState,
  };
  res.status(202).json({
    success: true,
    started: true,
    message: 'Đã bắt đầu chu kỳ tưới thử (~60s). Kiểm tra bơm và Gmail.',
  });
  runAutoWaterCycle('manual_test', hooks, { force: true }).catch((err) => {
    console.error('[AUTO-WATER] Manual test failed:', err.message);
  });
});

router.get('/watering-plan', async (req, res, next) => {
  try {
    const plan = await getWateringPlan();
    res.json({ success: true, ...plan });
  } catch (err) {
    next(err);
  }
});

router.post('/watering-plan/check', (req, res) => {
  res.status(202).json({
    success: true,
    started: true,
    message: 'Đã chạy kiểm tra ẩm đất TB hôm nay (logic 22:00).',
  });
  runNightlySoilMoistureCheck().catch((err) => {
    console.error('[SOIL-PLAN] Manual check failed:', err.message);
  });
});

router.post('/reports/email/test', (req, res) => {
  const slot = String(req.body?.slot || 'morning').toLowerCase() === 'evening'
    ? 'evening'
    : 'morning';
  res.status(202).json({
    success: true,
    started: true,
    message: 'Đã gửi yêu cầu email báo cáo. Kiểm tra hộp thư trong vài phút.',
  });
  sendScheduledReport(slot)
    .then((result) => {
      if (result.skipped) {
        console.warn('[EMAIL] Test report skipped — not configured');
      }
    })
    .catch((err) => {
      console.error('[EMAIL] Test report failed:', err.message);
    });
});

module.exports = router;
