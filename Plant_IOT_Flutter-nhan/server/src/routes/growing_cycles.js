const express = require('express');
const {
  rowToCycle,
  getActiveCycle,
  listCycles,
  startCycle,
  endCycle,
} = require('../../services/growingCycleService');

const router = express.Router();

router.get('/active', (req, res, next) => {
  getActiveCycle((err, row) => {
    if (err) return next(err);
    res.json({ success: true, cycle: rowToCycle(row) });
  });
});

router.get('/', (req, res, next) => {
  const limit = req.query.limit;
  listCycles({ limit }, (err, rows) => {
    if (err) return next(err);
    res.json({
      success: true,
      cycles: (rows || []).map(rowToCycle),
    });
  });
});

router.post('/start', (req, res, next) => {
  const body = req.body || {};
  startCycle(
    {
      started_at: body.started_at,
      note: body.note,
    },
    (err, row) => {
      if (err) {
        if (err.statusCode === 409) {
          return res.status(409).json({ success: false, error: err.message });
        }
        return next(err);
      }
      res.status(201).json({ success: true, cycle: rowToCycle(row) });
    },
  );
});

router.post('/:id/end', (req, res, next) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id)) {
    return res.status(400).json({ success: false, error: 'id không hợp lệ' });
  }
  endCycle(id, (err, row) => {
    if (err) {
      if (err.statusCode === 404) {
        return res.status(404).json({ success: false, error: err.message });
      }
      return next(err);
    }
    res.json({ success: true, cycle: rowToCycle(row) });
  });
});

module.exports = router;
