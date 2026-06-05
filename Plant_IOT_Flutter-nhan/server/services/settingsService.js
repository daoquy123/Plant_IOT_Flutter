const { getDb } = require('../config/database');

const AUTO_WATER_KEY = 'auto_water';

function getSetting(key, callback) {
  const db = getDb();
  db.get('SELECT value FROM app_settings WHERE key = ?', [key], (err, row) => {
    if (err) return callback(err);
    callback(null, row?.value ?? null);
  });
}

function setSetting(key, value, callback) {
  const db = getDb();
  const sql = `
    INSERT INTO app_settings (key, value, updated_at)
    VALUES (?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET
      value = excluded.value,
      updated_at = excluded.updated_at
  `;
  db.run(sql, [key, String(value), new Date().toISOString()], callback);
}

function getAutoWaterEnabled(callback) {
  getSetting(AUTO_WATER_KEY, (err, raw) => {
    if (err) return callback(err);
    callback(null, raw === 'true' || raw === '1');
  });
}

function setAutoWaterEnabled(enabled, callback) {
  setSetting(AUTO_WATER_KEY, enabled ? 'true' : 'false', callback);
}

function getAutoWaterEnabledAsync() {
  return new Promise((resolve, reject) => {
    getAutoWaterEnabled((err, enabled) => {
      if (err) reject(err);
      else resolve(enabled);
    });
  });
}

function setAutoWaterEnabledAsync(enabled) {
  return new Promise((resolve, reject) => {
    setAutoWaterEnabled(enabled, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

module.exports = {
  getAutoWaterEnabled,
  setAutoWaterEnabled,
  getAutoWaterEnabledAsync,
  setAutoWaterEnabledAsync,
};
