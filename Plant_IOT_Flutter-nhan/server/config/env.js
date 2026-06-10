const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

function getEnvVar(key, fallback) {
  const value = process.env[key] ?? fallback;
  if (value === undefined || value === '') {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

const corsRaw = (process.env.CORS_ORIGINS || '').trim();
const trustProxyRaw = (process.env.TRUST_PROXY || '1').trim();

const config = {
  NODE_ENV: process.env.NODE_ENV || 'production',
  HOST: process.env.HOST || '0.0.0.0',
  PORT: Number(process.env.PORT || 3000),
  API_KEY: getEnvVar('API_KEY'),
  DB_PATH: getEnvVar('DB_PATH'),
  UPLOADS_DIR: getEnvVar('UPLOADS_DIR'),
  MAX_FILE_SIZE_MB: Number(process.env.MAX_FILE_SIZE_MB || 5),
  SENSOR_RETENTION_DAYS: Number(process.env.SENSOR_RETENTION_DAYS || 30),
  IMAGE_RETENTION_DAYS: Number(process.env.IMAGE_RETENTION_DAYS || 7),
  LOG_LEVEL: process.env.LOG_LEVEL || 'info',
  /** Comma-separated origins, e.g. https://103.116.38.192. Empty = allow any origin (reflect). */
  CORS_ORIGINS: corsRaw,
  /** Express trust proxy (1 = first proxy hop, true = trust all). Required behind Nginx for correct HTTPS URLs. */
  TRUST_PROXY: trustProxyRaw === 'true' ? true : Number(trustProxyRaw) || 1,
  MQTT_URL: process.env.MQTT_URL || 'mqtt://localhost:1883',
  MQTT_CLIENT_ID: process.env.MQTT_CLIENT_ID || `plant-server-${process.pid}`,
  MQTT_USERNAME: process.env.MQTT_USERNAME || '',
  MQTT_PASSWORD: process.env.MQTT_PASSWORD || '',
  MQTT_USE_API_KEY_AUTH: (process.env.MQTT_USE_API_KEY_AUTH || 'false').toLowerCase() === 'true',
  /** Base URL for Flutter IoT API (Settings → Server URL). */
  PUBLIC_SERVER_URL: (process.env.PUBLIC_SERVER_URL || 'http://103.116.38.192').trim(),
  /** FastAPI leaf AI base URL (Flutter appends `/predict`). */
  AI_SERVER_URL: (process.env.AI_SERVER_URL || 'http://103.116.38.192:8000').trim(),
  /** Optional camera stream / latest image URL. */
  CAMERA_URL: (process.env.CAMERA_URL || '').trim(),
  /** Gmail SMTP — optional, for daily email reports. */
  EMAIL_HOST: (process.env.EMAIL_HOST || 'smtp.gmail.com').trim(),
  EMAIL_PORT: Number(process.env.EMAIL_PORT || 587),
  EMAIL_HOST_USER: (process.env.EMAIL_HOST_USER || '').trim(),
  EMAIL_HOST_PASSWORD: (process.env.EMAIL_HOST_PASSWORD || '').replace(/\s+/g, ''),
  DEFAULT_FROM_EMAIL: (process.env.DEFAULT_FROM_EMAIL || process.env.EMAIL_HOST_USER || '').trim(),
  REPORT_EMAIL_TO: (process.env.REPORT_EMAIL_TO || process.env.EMAIL_HOST_USER || '').trim(),
  EMAIL_REPORTS_ENABLED: (process.env.EMAIL_REPORTS_ENABLED || 'true').toLowerCase() !== 'false',
  /** Seconds per pump work session (manual control & auto-water). */
  PUMP_SESSION_SECONDS: Number(
    process.env.PUMP_SESSION_SECONDS || process.env.AUTO_WATER_PUMP_SECONDS || 60,
  ),
  /** Seconds pump stays on during auto-water cycle (alias of session length). */
  AUTO_WATER_PUMP_SECONDS: Number(
    process.env.AUTO_WATER_PUMP_SECONDS || process.env.PUMP_SESSION_SECONDS || 60,
  ),
  /** Sensor alert thresholds (email when out of range, max 1/hour). */
  SENSOR_ALERT_TEMP_MIN: Number(process.env.SENSOR_ALERT_TEMP_MIN || 22),
  SENSOR_ALERT_TEMP_MAX: Number(process.env.SENSOR_ALERT_TEMP_MAX || 32),
  SENSOR_ALERT_SOIL_MIN: Number(process.env.SENSOR_ALERT_SOIL_MIN || 45),
  SENSOR_ALERT_SOIL_MAX: Number(process.env.SENSOR_ALERT_SOIL_MAX || 85),
  SENSOR_ALERT_RAIN_MIN: Number(process.env.SENSOR_ALERT_RAIN_MIN || 10),
  SENSOR_ALERT_RAIN_MAX: Number(process.env.SENSOR_ALERT_RAIN_MAX || 85),
  SENSOR_ALERT_HUMIDITY_MIN: Number(process.env.SENSOR_ALERT_HUMIDITY_MIN || 45),
  SENSOR_ALERT_HUMIDITY_MAX: Number(process.env.SENSOR_ALERT_HUMIDITY_MAX || 85),
  /** Lá vàng+ trong ngày để tăng tưới (kiểm tra 22:00). */
  LEAF_HEALTH_MIN_UNHEALTHY_COUNT: Number(process.env.LEAF_HEALTH_MIN_UNHEALTHY_COUNT || 10),
  /** Ẩm đất TB phải ≤ SOIL_MIN + offset mới tăng tưới vì lá xấu. */
  LEAF_HEALTH_SOIL_MAX_OFFSET: Number(process.env.LEAF_HEALTH_SOIL_MAX_OFFSET || 15),
};

function validateEnv() {
  if (!config.API_KEY || config.API_KEY.length < 32) {
    throw new Error('API_KEY must be defined and at least 32 characters long');
  }
  if (!Number.isFinite(config.PORT) || config.PORT <= 0) {
    throw new Error('PORT must be a positive integer');
  }
  if (!Number.isFinite(config.MAX_FILE_SIZE_MB) || config.MAX_FILE_SIZE_MB <= 0) {
    throw new Error('MAX_FILE_SIZE_MB must be a positive number');
  }
  if (!Number.isFinite(config.SENSOR_RETENTION_DAYS) || config.SENSOR_RETENTION_DAYS <= 0) {
    throw new Error('SENSOR_RETENTION_DAYS must be a positive number');
  }
  if (!Number.isFinite(config.IMAGE_RETENTION_DAYS) || config.IMAGE_RETENTION_DAYS <= 0) {
    throw new Error('IMAGE_RETENTION_DAYS must be a positive number');
  }
  if (!config.MQTT_URL.trim()) {
    throw new Error('MQTT_URL must not be empty');
  }
}

/** @returns {(origin: string | undefined, cb: (err: Error | null, allow?: boolean) => void) => void} */
function buildCorsOriginFunction() {
  const allowed = config.CORS_ORIGINS
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  if (allowed.length === 0) {
    return (origin, cb) => cb(null, true);
  }
  return (origin, cb) => {
    if (!origin) return cb(null, true);
    if (allowed.includes('*')) return cb(null, true);
    if (allowed.includes(origin)) return cb(null, true);
    return cb(null, false);
  };
}

module.exports = { config, validateEnv, buildCorsOriginFunction };
