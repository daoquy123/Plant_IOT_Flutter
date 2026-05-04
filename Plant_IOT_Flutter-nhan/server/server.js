const path = require('path');
const fs = require('fs');
const http = require('http');
const mqtt = require('mqtt');
const express = require('express');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');

const { config, validateEnv, buildCorsOriginFunction } = require('./config/env');
const { getDb, runMigrations, cleanOldData, closeDb } = require('./config/database');
const authMiddleware = require('./middleware/auth');
const errorHandler = require('./middleware/errorHandler');
const { requestLogger } = require('./middleware/logger');
const rateLimiter = require('./middleware/rateLimiter');
const sensorRoutes = require('./src/routes/sensors');
const historyRoutes = require('./src/routes/history');
const relayRoutes = require('./src/routes/relay');
const cameraRoutes = require('./src/routes/camera');
const healthRoutes = require('./src/routes/health');
const { insertReading } = require('./services/sensorService');
const { createRelayState, getRelayStatus } = require('./services/relayService');

const UPLOADS_DIR = path.resolve(__dirname, config.UPLOADS_DIR);
const LOGS_DIR = path.resolve(__dirname, 'logs');
fs.mkdirSync(UPLOADS_DIR, { recursive: true });
fs.mkdirSync(LOGS_DIR, { recursive: true });

validateEnv();
getDb();
runMigrations();
cleanOldData();

const app = express();
const corsOrigin = buildCorsOriginFunction();
const MQTT_TOPICS = {
  sensor: 'garden/sensor',
  relaySet: 'garden/relay/set',
  relayState: 'garden/relay/state',
};

function toNumber(value) {
  if (value === undefined || value === null || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseBoolean(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value === 1;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    if (normalized === 'true' || normalized === '1' || normalized === 'on') return true;
    if (normalized === 'false' || normalized === '0' || normalized === 'off') return false;
  }
  return null;
}

app.set('trust proxy', config.TRUST_PROXY);

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: config.CORS_ORIGINS ? corsOrigin : true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    credentials: true,
  },
  allowEIO3: true,
  pingTimeout: 60000,
  pingInterval: 25000,
  connectTimeout: 45000,
});

io.use((socket, next) => {
  const apiKey =
    socket.handshake.headers['x-api-key'] ||
    socket.handshake.auth?.apiKey ||
    socket.handshake.query?.apiKey;
  if (!apiKey || apiKey !== config.API_KEY) {
    const err = new Error('Unauthorized socket: invalid or missing API key');
    err.data = { code: 401 };
    return next(err);
  }
  return next();
});

io.on('connection', (socket) => {
  console.log(`Socket connected: ${socket.id}`);
});

app.locals.io = io;
app.locals.mqtt = null;
app.locals.publishRelayState = () => {};

app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
app.use(cors({ origin: corsOrigin, credentials: true }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(requestLogger);
app.use(rateLimiter);
app.use('/uploads', express.static(UPLOADS_DIR, { maxAge: '1h' }));

app.use('/health', healthRoutes);
app.use('/api', authMiddleware);
app.use('/api/sensors', sensorRoutes);
app.use('/api/sensors', historyRoutes);
app.use('/api/relay', relayRoutes);
app.use('/api/camera', cameraRoutes);

app.use(errorHandler);

const mqttOptions = {
  clientId: config.MQTT_CLIENT_ID,
  reconnectPeriod: 2000,
  connectTimeout: 30_000,
  clean: true,
  will: {
    topic: 'garden/server/status',
    payload: JSON.stringify({
      clientId: config.MQTT_CLIENT_ID,
      status: 'offline',
      timestamp: Date.now(),
    }),
    qos: 1,
    retain: true,
  },
};
if (config.MQTT_USE_API_KEY_AUTH) {
  mqttOptions.username = config.MQTT_USERNAME || 'plant-server';
  mqttOptions.password = config.API_KEY;
} else {
  if (config.MQTT_USERNAME) mqttOptions.username = config.MQTT_USERNAME;
  if (config.MQTT_PASSWORD) mqttOptions.password = config.MQTT_PASSWORD;
}

const mqttClient = mqtt.connect(config.MQTT_URL, mqttOptions);
app.locals.mqtt = mqttClient;
app.locals.publishRelayState = (relayStatus) => {
  if (!mqttClient.connected) return;
  mqttClient.publish(
    MQTT_TOPICS.relayState,
    JSON.stringify({
      relay_status: relayStatus,
      timestamp: Date.now(),
    }),
    { retain: true, qos: 1 },
    (err) => {
      if (err) {
        console.error('[MQTT] Failed publishing relay state:', err.message);
      }
    }
  );
};

mqttClient.on('connect', () => {
  console.log(`[MQTT] Connected to broker: ${config.MQTT_URL}`);
  mqttClient.subscribe([MQTT_TOPICS.sensor, MQTT_TOPICS.relaySet], { qos: 1 }, (err) => {
    if (err) {
      console.error('[MQTT] Subscribe failed:', err.message);
      return;
    }
    console.log(`[MQTT] Subscribed: ${MQTT_TOPICS.sensor}, ${MQTT_TOPICS.relaySet}`);
  });
  mqttClient.publish(
    'garden/server/status',
    JSON.stringify({
      clientId: config.MQTT_CLIENT_ID,
      status: 'online',
      timestamp: Date.now(),
    }),
    { retain: true, qos: 1 }
  );
  getRelayStatus((err, relayStatus) => {
    if (err) {
      console.error('[MQTT] Failed reading relay state for initial publish:', err);
      return;
    }
    app.locals.publishRelayState(relayStatus);
  });
});

mqttClient.on('reconnect', () => {
  console.log('[MQTT] Reconnecting...');
});

mqttClient.on('error', (err) => {
  console.error('[MQTT] Client error:', err.message);
});

mqttClient.on('offline', () => {
  console.warn('[MQTT] Client offline');
});

mqttClient.on('message', (topic, messageBuffer) => {
  let payload;
  try {
    payload = JSON.parse(messageBuffer.toString('utf8'));
  } catch (err) {
    console.error(`[MQTT] Invalid JSON on topic ${topic}:`, err.message);
    return;
  }

  if (topic === MQTT_TOPICS.sensor) {
    const sensorPayload = {
      temperature: toNumber(payload.temperature) ?? toNumber(payload.air_temp),
      humidity: toNumber(payload.humidity) ?? toNumber(payload.air_humidity),
      soil_moisture: toNumber(payload.soil_moisture) ?? toNumber(payload.moisture),
      rain: toNumber(payload.rain),
      device_id: payload.device_id,
      recorded_at: payload.recorded_at,
    };
    insertReading(sensorPayload, (err, sensor) => {
      if (err) {
        console.error('[MQTT] Failed to persist sensor reading:', err);
        return;
      }
      io.emit('sensor', sensor);
    });
    return;
  }

  if (topic === MQTT_TOPICS.relaySet) {
    const relayId = Number(payload.relay_id);
    const state = parseBoolean(payload.state);
    if (!Number.isInteger(relayId) || relayId <= 0 || state === null) {
      console.warn('[MQTT] Ignored invalid relay/set payload:', payload);
      return;
    }

    createRelayState(
      {
        relay_id: relayId,
        relay_name: payload.relay_name,
        state,
        triggered_by: payload.triggered_by || 'mqtt',
      },
      (err, relayStatus) => {
        if (err) {
          console.error('[MQTT] Failed to persist relay command:', err);
          return;
        }
        io.emit('relay', { relay_status: relayStatus });
        app.locals.publishRelayState(relayStatus);
      }
    );
  }
});

const HOST = config.HOST;
const PORT = config.PORT;
const serverInstance = server.listen(PORT, HOST, () => {
  console.log(
    `Plant IoT server listening on http://${HOST}:${PORT} (NODE_ENV=${config.NODE_ENV})`
  );
});

const cleanupTimer = setInterval(() => {
  try {
    cleanOldData();
  } catch (err) {
    console.error('Failed scheduled cleanup:', err);
  }
}, 1000 * 60 * 60 * 12);

function shutdown(signal) {
  console.log(`Received ${signal}, closing server...`);
  clearInterval(cleanupTimer);
  serverInstance.close(() => {
    io.close(() => {
      mqttClient.end(true, {}, () => {
        closeDb();
        console.log('Socket.IO and MQTT closed');
        process.exit(0);
      });
    });
  });
  setTimeout(() => {
    console.error('Force shutdown after timeout');
    process.exit(1);
  }, 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('uncaughtException', (err) => {
  console.error('Uncaught exception:', err);
  process.exit(1);
});
process.on('unhandledRejection', (reason) => {
  console.error('Unhandled rejection:', reason);
});
