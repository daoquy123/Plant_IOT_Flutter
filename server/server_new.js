const path = require('path');
const fs = require('fs');
const http = require('http');
const express = require('express');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');

const { config, validateEnv } = require('./config/env');
const { runMigrations, cleanOldData } = require('./config/database');
const authMiddleware = require('./middleware/auth');
const errorHandler = require('./middleware/errorHandler');
const { requestLogger } = require('./middleware/logger');
const rateLimiter = require('./middleware/rateLimiter');
const sensorRoutes = require('./src/routes/sensors');
const historyRoutes = require('./src/routes/history');
const relayRoutes = require('./src/routes/relay');
const cameraRoutes = require('./src/routes/camera');
const healthRoutes = require('./src/routes/health');

const UPLOADS_DIR = path.resolve(__dirname, config.UPLOADS_DIR);
const LOGS_DIR = path.resolve(__dirname, 'logs');
fs.mkdirSync(UPLOADS_DIR, { recursive: true });
fs.mkdirSync(LOGS_DIR, { recursive: true });

validateEnv();
runMigrations();
cleanOldData();

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    credentials: true,
  },
  allowEIO3: true,
});

app.locals.io = io;
app.use(helmet());
app.use(cors({ origin: true, credentials: true }));
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

const PORT = config.PORT;
const serverInstance = server.listen(PORT, () => {
  console.log(`🚀 Plant IoT server listening on port ${PORT}`);
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
      console.log('Socket.IO closed');
      process.exit(0);
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
