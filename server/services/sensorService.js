const { getDb } = require('../config/database');

function insertReading(payload, callback) {
  const db = getDb();
  const sql = `
    INSERT INTO sensor_readings (
      temperature,
      humidity,
      soil_moisture,
      rain,
      device_id,
      recorded_at
    ) VALUES (?, ?, ?, ?, ?, ?)
  `;

  const values = [
    payload.temperature ?? null,
    payload.humidity ?? null,
    payload.soil_moisture ?? null,
    payload.rain ?? null,
    payload.device_id ?? null,
    payload.recorded_at ?? new Date().toISOString()
  ];

  db.run(sql, values, function(err) {
    if (err) {
      return callback(err);
    }
    // Get the latest reading after insert
    getLatestReading(callback);
  });
}

function getLatestReading(callback) {
  const db = getDb();
  db.get(
    'SELECT * FROM sensor_readings ORDER BY recorded_at DESC LIMIT 1',
    (err, row) => {
      if (err) {
        return callback(err);
      }
      callback(null, row || {});
    }
  );
}

function getHistory({ from, to, limit = 100 }, callback) {
  const db = getDb();
  let sql = 'SELECT * FROM sensor_readings';
  const conditions = [];
  const params = [];

  if (from) {
    conditions.push('recorded_at >= ?');
    params.push(from);
  }
  if (to) {
    conditions.push('recorded_at <= ?');
    params.push(to);
  }

  if (conditions.length > 0) {
    sql += ' WHERE ' + conditions.join(' AND ');
  }

  sql += ' ORDER BY recorded_at DESC LIMIT ?';
  params.push(limit);

  db.all(sql, params, (err, rows) => {
    if (err) {
      return callback(err);
    }
    callback(null, rows);
  });
}

function getLatestSensorTime(callback) {
  const db = getDb();
  db.get(
    'SELECT recorded_at FROM sensor_readings ORDER BY recorded_at DESC LIMIT 1',
    (err, row) => {
      if (err) {
        return callback(err);
      }
      callback(null, row);
    }
  );
}

function getSensorCount(callback) {
  const db = getDb();
  db.get('SELECT COUNT(*) AS count FROM sensor_readings', (err, row) => {
    if (err) {
      return callback(err);
    }
    callback(null, row ? row.count : 0);
  });
}

module.exports = {
  insertReading,
  getLatestReading,
  getHistory,
  getLatestSensorTime,
  getSensorCount,
};
