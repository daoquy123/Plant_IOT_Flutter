const express = require('express');
const { insertReading, getLatestReading } = require('../../services/sensorService');

const router = express.Router();

function toNumber(value) {
  if (value === undefined || value === null || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

router.post('/', (req, res, next) => {
  const body = req.body || {};
  const payload = {
    temperature: toNumber(body.temperature) ?? toNumber(body.air_temp),
    humidity: toNumber(body.humidity) ?? toNumber(body.air_humidity),
    soil_moisture: toNumber(body.soil_moisture) ?? toNumber(body.moisture),
    rain: toNumber(body.rain),
    device_id: body.device_id,
    recorded_at: body.recorded_at,
  };

  insertReading(payload, (err, sensor) => {
    if (err) {
      return next(err);
    }

    req.app.locals.io.emit('sensor', sensor);
    res.json({ success: true, sensor });
  });
});

router.get('/latest', (req, res, next) => {
  getLatestReading((err, sensor) => {
    if (err) {
      return next(err);
    }
    res.json({ success: true, sensor });
  });
});

module.exports = router;
