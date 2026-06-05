/**
 * Giảm số bản ghi pump_runs trong ngày (VN +7) xuống target.
 * Usage (from server/):
 *   node scripts/fix_pump_count_today.js 13
 * Optional: DB_PATH=./data/plant_iot.db node scripts/fix_pump_count_today.js 13
 */
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const DB_PATH = process.env.DB_PATH || path.join(__dirname, '..', 'data', 'plant_iot.db');
const TARGET = Math.max(0, parseInt(process.argv[2] || '13', 10));

function vnTodayKey() {
  const now = new Date(Date.now() + 7 * 60 * 60 * 1000);
  const y = now.getUTCFullYear();
  const m = String(now.getUTCMonth() + 1).padStart(2, '0');
  const d = String(now.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

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

function run(db, sql, params = []) {
  return new Promise((resolve, reject) => {
    db.run(sql, params, function onRun(err) {
      if (err) reject(err);
      else resolve(this);
    });
  });
}

async function main() {
  const today = vnTodayKey();
  console.log(`DB: ${DB_PATH}`);
  console.log(`VN today: ${today}, target pump_runs: ${TARGET}`);

  const db = await openDb();
  const before = await get(
    db,
    `SELECT COUNT(*) AS c FROM pump_runs WHERE date(started_at, '+7 hours') = ?`,
    [today],
  );
  const current = Number(before?.c) || 0;
  console.log(`Current count: ${current}`);

  if (current <= TARGET) {
    console.log('Nothing to delete.');
    db.close();
    return;
  }

  const toDelete = current - TARGET;
  const result = await run(
    db,
    `DELETE FROM pump_runs
     WHERE id IN (
       SELECT id FROM (
         SELECT id FROM pump_runs
         WHERE date(started_at, '+7 hours') = ?
         ORDER BY started_at ASC
         LIMIT ?
       )
     )`,
    [today, toDelete],
  );

  const after = await get(
    db,
    `SELECT COUNT(*) AS c FROM pump_runs WHERE date(started_at, '+7 hours') = ?`,
    [today],
  );
  console.log(`Deleted: ${result.changes}, remaining: ${after?.c ?? '?'}`);
  db.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
