const express = require('express');
const {
  getAutoWaterEnabled,
  setAutoWaterEnabled,
} = require('../../services/settingsService');
const { runAutoWaterCycle } = require('../../services/autoWaterService');
const { sendScheduledReport } = require('../../services/dailyReportService');

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
