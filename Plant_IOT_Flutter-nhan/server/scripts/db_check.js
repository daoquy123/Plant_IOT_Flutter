/**
 * Kiểm tra / sửa nhẹ SQLite (integrity + bảng bắt buộc).
 * Usage: node scripts/db_check.js
 */
const path = require('path');
const fs = require('fs');
const sqlite3 = require('sqlite3').verbose();
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const DB_PATH = path.resolve(__dirname, '..', process.env.DB_PATH || './data/plant_iot.db');

function openDb() {
  return new Promise((resolve, reject) => {
    const db = new sqlite3.Database(DB_PATH, (err) => {
      if (err) reject(err);
      else resolve(db);
    });
  });
}

function get(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.get(sql, params, (err, row) => {
      if (err) reject(err);
      else resolve(row);
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

function run(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function onRun(err) {
      if (err) reject(err);
      else resolve(this);
    });
  });
}

async function main() {
  console.log('DB path:', DB_PATH);
  if (!fs.existsSync(DB_PATH)) {
    console.error('ERROR: Database file not found.');
    process.exit(1);
  }

  const stat = fs.statSync(DB_PATH);
  console.log('Size:', stat.size, 'bytes');

  const db = await openDb();
  const integrity = await get(db, 'PRAGMA integrity_check');
  console.log('integrity_check:', integrity['integrity_check']);

  const tables = await all(
    db,
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
  );
  console.log('Tables:', tables.map((t) => t.name).join(', '));

  const counts = {
    sensor_readings: await get(db, 'SELECT COUNT(*) AS c FROM sensor_readings'),
    pump_runs: await get(db, 'SELECT COUNT(*) AS c FROM pump_runs'),
    relay_states: await get(db, 'SELECT COUNT(*) AS c FROM relay_states'),
  };
  console.log('Row counts:', counts);

  if (!tables.some((t) => t.name === 'app_settings')) {
    console.log('Creating missing app_settings table...');
    await run(
      db,
      `CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )`,
    );
  }

  try {
    await all(
      db,
      `SELECT
         date(recorded_at, '+7 hours') AS d,
         COUNT(*) AS n
       FROM sensor_readings
       GROUP BY d
       ORDER BY d DESC
       LIMIT 3`,
    );
    console.log('Analytics sensor query: OK');
  } catch (err) {
    console.error('Analytics sensor query FAILED:', err.message);
  }

  try {
    await all(
      db,
      `SELECT
         date(started_at, '+7 hours') AS d,
         COUNT(*) AS n
       FROM pump_runs
       GROUP BY d
       ORDER BY d DESC
       LIMIT 3`,
    );
    console.log('Analytics pump query: OK');
  } catch (err) {
    console.error('Analytics pump query FAILED:', err.message);
  }

  db.close();
  console.log('\nDone.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
