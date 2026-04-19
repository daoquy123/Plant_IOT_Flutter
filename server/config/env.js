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
  /** Comma-separated origins, e.g. https://five-small-snowflake.site. Empty = allow any origin (reflect). */
  CORS_ORIGINS: corsRaw,
  /** Express trust proxy (1 = first proxy hop, true = trust all). Required behind Nginx for correct HTTPS URLs. */
  TRUST_PROXY: trustProxyRaw === 'true' ? true : Number(trustProxyRaw) || 1,
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
