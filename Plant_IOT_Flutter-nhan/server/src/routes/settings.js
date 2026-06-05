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

/** Gửi thử một chu kỳ tưới (pump_on → chờ → pump_off). */
router.post('/auto-water/test', (req, res, next) => {
  const hooks = {
    io: req.app.locals.io,
    publishRelayState: req.app.locals.publishRelayState,
  };
  runAutoWaterCycle('manual_test', hooks, { force: true })
    .then((result) => res.json({ success: true, ...result }))
    .catch(next);
});

router.post('/reports/email/test', (req, res, next) => {
  const slot = String(req.body?.slot || 'morning').toLowerCase() === 'evening'
    ? 'evening'
    : 'morning';
  sendScheduledReport(slot)
    .then((result) => {
      if (result.skipped) {
        return res.status(503).json({
          success: false,
          message: 'Email chưa cấu hình trên server (.env EMAIL_*)',
        });
      }
      return res.json({ success: true, ...result });
    })
    .catch(next);
});

module.exports = router;
