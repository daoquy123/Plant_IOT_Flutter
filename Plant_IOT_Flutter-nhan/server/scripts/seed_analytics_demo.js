/**
 * Seed sensor_readings + pump_runs for analytics chart (VN calendar days).
 * Usage (from server/): node scripts/seed_analytics_demo.js
 * Optional: DB_PATH=./data/plant_iot.db node scripts/seed_analytics_demo.js
 */
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'data', 'plant_iot.db');

/** VN local hour -> ISO UTC for SQLite date(..., '+7 hours') bucketing */
function vnToIso(dateKey, hour) {
  const h = String(hour).padStart(2, '0');
  return new Date(`${dateKey}T${h}:00:00+07:00`).toISOString();
}

const DAYS = [
  { date: '2026-05-31', temp: 30.2, humidity: 86.5, pumps: 4 },
  { date: '2026-06-01', temp: 29.8, humidity: 88.2, pumps: 3 },
  { date: '2026-06-02', temp: 31.5, humidity: 84.0, pumps: 5 },
  { date: '2026-06-03', temp: 28.6, humidity: 91.0, pumps: 2 },
  { date: '2026-06-04', temp: 30.8, humidity: 85.5, pumps: 4 },
];

const READING_HOURS = [6, 8, 10, 12, 14, 16, 18, 20];
const PUMP_HOURS = [7, 11, 15, 18, 21];

function jitter(base, spread, index) {
  const wave = Math.sin(index * 1.7) * spread * 0.6;
  const step = (index % 3 - 1) * spread * 0.25;
  return Math.round((base + wave + step) * 10) / 10;
}

function openDb() {
  return new Promise((resolve, reject) => {
    const db = new sqlite3.Database(DB_PATH, (err) => {
      if (err) reject(err);
      else resolve(db);
    });
  });
}

function run(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function onRun(err) {
      if (err) reject(err);
      else resolve(this);
    });
  });
}

function all(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.all(sql, params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows);
    });
  });
}

async function clearRange(db, dateKeys) {
  for (const dateKey of dateKeys) {
    await run(
      db,
      `DELETE FROM sensor_readings
       WHERE date(recorded_at, '+7 hours') = ?`,
      [dateKey],
    );
    await run(
      db,
      `DELETE FROM pump_runs
       WHERE date(started_at, '+7 hours') = ?`,
      [dateKey],
    );
    console.log(`Cleared existing data for ${dateKey}`);
  }
}

async function seed() {
  console.log(`DB: ${DB_PATH}`);
  const db = await openDb();
  const dateKeys = DAYS.map((d) => d.date);

  const existing = await all(
    db,
    `SELECT date(recorded_at, '+7 hours') AS d, COUNT(*) AS n
     FROM sensor_readings
     WHERE date(recorded_at, '+7 hours') IN (${dateKeys.map(() => '?').join(',')})
     GROUP BY d`,
    dateKeys,
  );
  if (existing.length) {
    console.log('Existing sensor buckets:', existing);
  }

  await clearRange(db, dateKeys);

  for (const day of DAYS) {
    for (let i = 0; i < READING_HOURS.length; i += 1) {
      const hour = READING_HOURS[i];
      const temp = jitter(day.temp, 1.2, i);
      const humidity = jitter(day.humidity, 2.5, i + 2);
      const soil = Math.round(45 + (humidity - day.humidity) * 0.3 + i);
      const recorded_at = vnToIso(day.date, hour);
      await run(
        db,
        `INSERT INTO sensor_readings (
          temperature, humidity, soil_moisture, rain, device_id, source, recorded_at
        ) VALUES (?, ?, ?, 0, 'seed-demo', 'seed', ?)`,
        [temp, humidity, soil, recorded_at],
      );
    }

    const pumpHours = PUMP_HOURS.slice(0, day.pumps);
    for (let p = 0; p < pumpHours.length; p += 1) {
      const started_at = vnToIso(day.date, pumpHours[p]);
      const ended_at = new Date(new Date(started_at).getTime() + (45 + p * 12) * 1000).toISOString();
      await run(
        db,
        `INSERT INTO pump_runs (
          relay_id, relay_name, triggered_by, device_id, started_at, ended_at, duration_seconds
        ) VALUES (2, 'Pump', 'seed', 'seed-demo', ?, ?, ?)`,
        [started_at, ended_at, 45 + p * 12],
      );
    }

    const summary = await all(
      db,
      `SELECT
         date(recorded_at, '+7 hours') AS d,
         ROUND(AVG(temperature), 1) AS avg_t,
         ROUND(AVG(humidity), 1) AS avg_h,
         COUNT(*) AS samples
       FROM sensor_readings
       WHERE date(recorded_at, '+7 hours') = ?
       GROUP BY d`,
      [day.date],
    );
    const pumps = await all(
      db,
      `SELECT COUNT(*) AS c FROM pump_runs WHERE date(started_at, '+7 hours') = ?`,
      [day.date],
    );
    const row = summary[0] || {};
    console.log(
      `${day.date}: temp ${row.avg_t}°C, humidity ${row.avg_h}%, samples ${row.samples}, pumps ${pumps[0]?.c || 0}`,
    );
  }

  db.close();
  console.log('\nDone. Restart app or pull-to-refresh Biểu đồ (7D).');
  console.log('On VPS: copy script and run with same DB_PATH as production.');
}

seed().catch((err) => {
  console.error(err);
  process.exit(1);
});
