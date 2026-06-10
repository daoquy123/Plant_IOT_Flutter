const { getDb } = require('../config/database');

const AUTO_WATER_KEY = 'auto_water';
const SENSOR_ALERT_KEY = 'sensor_alert';
const LEGACY_EMAIL_REPORT_KEY = 'email_report';
const PEST_ALERT_KEY = 'pest_alert';
const WATERING_BOOST_KEY = 'watering_boost_active';
const WATERING_BOOST_SOIL_KEY = 'watering_boost_soil';
const WATERING_BOOST_LEAF_KEY = 'watering_boost_leaf';

const NORMAL_WATERING_SESSIONS = 2;
const BOOST_WATERING_SESSIONS = 3;

function getSetting(key, callback) {
  const db = getDb();
  db.get('SELECT value FROM app_settings WHERE key = ?', [key], (err, row) => {
    if (err) return callback(err);
    callback(null, row?.value ?? null);
  });
}

function getSettingAsync(key) {
  return new Promise((resolve, reject) => {
    getSetting(key, (err, value) => {
      if (err) reject(err);
      else resolve(value);
    });
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

function setSettingAsync(key, value) {
  return new Promise((resolve, reject) => {
    setSetting(key, value, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

function parseEnabled(raw, defaultValue = false) {
  if (raw == null || raw === '') return defaultValue;
  return raw === 'true' || raw === '1';
}

function getAutoWaterEnabled(callback) {
  getSetting(AUTO_WATER_KEY, (err, raw) => {
    if (err) return callback(err);
    callback(null, parseEnabled(raw, false));
  });
}

function setAutoWaterEnabled(enabled, callback) {
  setSetting(AUTO_WATER_KEY, enabled ? 'true' : 'false', callback);
}

function getSensorAlertEnabled(callback) {
  getSetting(SENSOR_ALERT_KEY, (err, raw) => {
    if (err) return callback(err);
    if (raw != null && raw !== '') {
      return callback(null, parseEnabled(raw, true));
    }
    getSetting(LEGACY_EMAIL_REPORT_KEY, (legacyErr, legacyRaw) => {
      if (legacyErr) return callback(legacyErr);
      callback(null, parseEnabled(legacyRaw, true));
    });
  });
}

function setSensorAlertEnabled(enabled, callback) {
  setSetting(SENSOR_ALERT_KEY, enabled ? 'true' : 'false', callback);
}

function getPestAlertEnabled(callback) {
  getSetting(PEST_ALERT_KEY, (err, raw) => {
    if (err) return callback(err);
    callback(null, parseEnabled(raw, false));
  });
}

function setPestAlertEnabled(enabled, callback) {
  setSetting(PEST_ALERT_KEY, enabled ? 'true' : 'false', callback);
}

function getWateringBoostSoilActive(callback) {
  getSetting(WATERING_BOOST_SOIL_KEY, (err, raw) => {
    if (err) return callback(err);
    if (raw != null && raw !== '') {
      return callback(null, parseEnabled(raw, false));
    }
    getSetting(WATERING_BOOST_KEY, (legacyErr, legacyRaw) => {
      if (legacyErr) return callback(legacyErr);
      callback(null, parseEnabled(legacyRaw, false));
    });
  });
}

function setWateringBoostSoilActive(enabled, callback) {
  setSetting(WATERING_BOOST_SOIL_KEY, enabled ? 'true' : 'false', callback);
}

function getWateringBoostLeafActive(callback) {
  getSetting(WATERING_BOOST_LEAF_KEY, (err, raw) => {
    if (err) return callback(err);
    callback(null, parseEnabled(raw, false));
  });
}

function setWateringBoostLeafActive(enabled, callback) {
  setSetting(WATERING_BOOST_LEAF_KEY, enabled ? 'true' : 'false', callback);
}

function getWateringBoostActive(callback) {
  getWateringBoostSoilActive((soilErr, soilBoost) => {
    if (soilErr) return callback(soilErr);
    getWateringBoostLeafActive((leafErr, leafBoost) => {
      if (leafErr) return callback(leafErr);
      callback(null, !!(soilBoost || leafBoost));
    });
  });
}

function setWateringBoostActive(enabled, callback) {
  setWateringBoostSoilActive(enabled, callback);
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

function getSensorAlertEnabledAsync() {
  return new Promise((resolve, reject) => {
    getSensorAlertEnabled((err, enabled) => {
      if (err) reject(err);
      else resolve(enabled);
    });
  });
}

function setSensorAlertEnabledAsync(enabled) {
  return new Promise((resolve, reject) => {
    setSensorAlertEnabled(enabled, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

function getPestAlertEnabledAsync() {
  return new Promise((resolve, reject) => {
    getPestAlertEnabled((err, enabled) => {
      if (err) reject(err);
      else resolve(enabled);
    });
  });
}

function setPestAlertEnabledAsync(enabled) {
  return new Promise((resolve, reject) => {
    setPestAlertEnabled(enabled, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

function getWateringBoostSoilActiveAsync() {
  return new Promise((resolve, reject) => {
    getWateringBoostSoilActive((err, enabled) => {
      if (err) reject(err);
      else resolve(enabled);
    });
  });
}

function setWateringBoostSoilActiveAsync(enabled) {
  return new Promise((resolve, reject) => {
    setWateringBoostSoilActive(enabled, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

function getWateringBoostLeafActiveAsync() {
  return new Promise((resolve, reject) => {
    getWateringBoostLeafActive((err, enabled) => {
      if (err) reject(err);
      else resolve(enabled);
    });
  });
}

function setWateringBoostLeafActiveAsync(enabled) {
  return new Promise((resolve, reject) => {
    setWateringBoostLeafActive(enabled, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

function getWateringBoostActiveAsync() {
  return new Promise((resolve, reject) => {
    getWateringBoostActive((err, enabled) => {
      if (err) reject(err);
      else resolve(enabled);
    });
  });
}

function setWateringBoostActiveAsync(enabled) {
  return setWateringBoostSoilActiveAsync(enabled);
}

async function getWateringSessionsPerDayAsync() {
  const boost = await getWateringBoostActiveAsync();
  return boost ? BOOST_WATERING_SESSIONS : NORMAL_WATERING_SESSIONS;
}

module.exports = {
  getAutoWaterEnabled,
  setAutoWaterEnabled,
  getAutoWaterEnabledAsync,
  setAutoWaterEnabledAsync,
  getSensorAlertEnabled,
  setSensorAlertEnabled,
  getSensorAlertEnabledAsync,
  setSensorAlertEnabledAsync,
  getPestAlertEnabled,
  setPestAlertEnabled,
  getPestAlertEnabledAsync,
  setPestAlertEnabledAsync,
  getWateringBoostActive,
  setWateringBoostActive,
  getWateringBoostSoilActive,
  setWateringBoostSoilActive,
  getWateringBoostLeafActive,
  setWateringBoostLeafActive,
  getWateringBoostSoilActiveAsync,
  setWateringBoostSoilActiveAsync,
  getWateringBoostLeafActiveAsync,
  setWateringBoostLeafActiveAsync,
  getWateringBoostActiveAsync,
  setWateringBoostActiveAsync,
  getWateringSessionsPerDayAsync,
  NORMAL_WATERING_SESSIONS,
  BOOST_WATERING_SESSIONS,
  getSettingAsync,
  setSettingAsync,
};
