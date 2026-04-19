const express = require('express');
const { getHistory } = require('../../services/sensorService');

const router = express.Router();

function parseLimit(raw) {
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    return 100;
  }
  return Math.min(500, Math.round(value));
}

router.get('/history', (req, res, next) => {
  getHistory(
    {
      from: req.query.from,
      to: req.query.to,
      limit: parseLimit(req.query.limit),
    },
    (err, history) => {
      if (err) {
        return next(err);
      }
      res.json({ success: true, history });
    }
  );
});

module.exports = router;
