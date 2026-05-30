const express = require('express');
const { insertReading, getLatestReading } = require('../../services/sensorService');
const { getDb } = require('../../config/database');

const router = express.Router();
const LOCAL_OFFSET_HOURS = 7;

function toNumber(value) {
  if (value === undefined || value === null || value === '') {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

router.post('/', (req, res, next) => {
  console.log('Received sensor data:', JSON.stringify(req.body, null, 2));
  const body = req.body || {};
  const payload = {
    temperature: toNumber(body.temperature) ?? toNumber(body.air_temp),
    humidity: toNumber(body.humidity) ?? toNumber(body.air_humidity),
    soil_moisture: toNumber(body.soil_moisture) ?? toNumber(body.moisture),
    rain: toNumber(body.rain),
    device_id: body.device_id,
    raw_payload: body,
    source: 'http',
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

function analyticsConfig(range) {
  if (range === '1d') {
    return {
      bucket: 'hour',
      count: 24,
      start: new Date(Date.now() - 24 * 60 * 60 * 1000),
      labelExpr: "strftime('%H:00', recorded_at, '+7 hours')",
      bucketExpr: "strftime('%Y-%m-%dT%H:00:00', recorded_at, '+7 hours')",
      pumpBucketExpr: "strftime('%Y-%m-%dT%H:00:00', started_at, '+7 hours')",
    };
  }
  const days = range === '30d' ? 30 : 7;
  return {
    bucket: 'day',
    count: days,
    start: new Date(Date.now() - days * 24 * 60 * 60 * 1000),
    labelExpr: "strftime('%d/%m', recorded_at, '+7 hours')",
    bucketExpr: "date(recorded_at, '+7 hours')",
    pumpBucketExpr: "date(started_at, '+7 hours')",
  };
}

function pad2(value) {
  return String(value).padStart(2, '0');
}

function buildBuckets(cfg) {
  const buckets = [];
  const now = new Date(Date.now() + LOCAL_OFFSET_HOURS * 60 * 60 * 1000);
  if (cfg.bucket === 'hour') {
    const end = new Date(now);
    end.setUTCMinutes(0, 0, 0);
    for (let i = cfg.count - 1; i >= 0; i -= 1) {
      const d = new Date(end.getTime() - i * 60 * 60 * 1000);
      buckets.push({
        bucket_key: d.toISOString().slice(0, 13) + ':00:00',
        label: `${pad2(d.getUTCHours())}:00`,
      });
    }
    return buckets;
  }

  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  for (let i = cfg.count - 1; i >= 0; i -= 1) {
    const d = new Date(end.getTime() - i * 24 * 60 * 60 * 1000);
    buckets.push({
      bucket_key: d.toISOString().slice(0, 10),
      label: `${pad2(d.getUTCDate())}/${pad2(d.getUTCMonth() + 1)}`,
    });
  }
  return buckets;
}

router.get('/analytics', (req, res, next) => {
  const range = String(req.query.range || '7d').toLowerCase();
  const cfg = analyticsConfig(range);
  const db = getDb();
  const startIso = cfg.start.toISOString();

  const sensorSql = `
    SELECT
      ${cfg.bucketExpr} AS bucket_key,
      ${cfg.labelExpr} AS label,
      AVG(temperature) AS avg_temperature,
      AVG(humidity) AS avg_humidity,
      AVG(soil_moisture) AS avg_soil_moisture,
      AVG(rain) AS avg_rain,
      COUNT(*) AS sample_count
    FROM sensor_readings
    WHERE recorded_at >= ?
    GROUP BY bucket_key
    ORDER BY bucket_key ASC
  `;

  const pumpSql = `
    SELECT
      ${cfg.pumpBucketExpr} AS bucket_key,
      COUNT(*) AS pump_count
    FROM pump_runs
    WHERE started_at >= ?
    GROUP BY bucket_key
  `;

  db.all(sensorSql, [startIso], (sensorErr, sensorRows) => {
    if (sensorErr) {
      return next(sensorErr);
    }
    db.all(pumpSql, [startIso], (pumpErr, pumpRows) => {
      if (pumpErr) {
        return next(pumpErr);
      }
      const sensorByBucket = new Map(sensorRows.map((row) => [row.bucket_key, row]));
      const pumpByBucket = new Map(pumpRows.map((row) => [row.bucket_key, Number(row.pump_count) || 0]));
      const buckets = buildBuckets(cfg).map((bucket) => {
        const row = sensorByBucket.get(bucket.bucket_key) || {};
        return {
          bucket_key: bucket.bucket_key,
          label: row.label || bucket.label,
          avg_temperature: row.avg_temperature ?? null,
          avg_humidity: row.avg_humidity ?? null,
          avg_soil_moisture: row.avg_soil_moisture ?? null,
          avg_rain: row.avg_rain ?? null,
          sample_count: row.sample_count || 0,
          pump_count: pumpByBucket.get(bucket.bucket_key) || 0,
        };
      });
      res.json({
        success: true,
        range,
        bucket: cfg.bucket,
        buckets,
      });
    });
  });
});

module.exports = router;
