const express = require('express');
const rateLimit = require('express-rate-limit');

const app = express();

app.use(express.json());

// =====================================================
// TRUST PROXY (nếu dùng VPS + Nginx / Cloudflare)
// =====================================================
app.set('trust proxy', 1);

// =====================================================
// IOT LIMITER (thoáng hơn)
// =====================================================
const iotUploadLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 phút
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,

  keyGenerator: (req) => {
    return (
      req.header('X-API-KEY') +
      ':' +
      (req.body?.device_id || 'unknown')
    );
  },
});

// =====================================================
// API LIMITER (cho user/web)
// =====================================================
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 phút
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
});

// =====================================================
// APPLY IOT LIMITER (chỉ cho IoT routes)
// =====================================================
app.use('/api/sensors', iotUploadLimiter);
app.use('/api/relay', iotUploadLimiter);
app.use('/api/camera/upload', iotUploadLimiter);

// =====================================================
// APPLY API LIMITER (LOẠI TRỪ IoT)
// =====================================================
app.use('/api', (req, res, next) => {
  // loại trừ các route IoT
  if (
    req.path.startsWith('/sensors') ||
    req.path.startsWith('/relay') ||
    req.path.startsWith('/camera/upload')
  ) {
    return next();
  }

  // còn lại áp limiter cho user
  apiLimiter(req, res, next);
});

// =====================================================
// ROUTES DEMO
// =====================================================

// IoT
app.post('/api/sensors', (req, res) => {
  res.json({ message: 'Sensor data received' });
});

app.get('/api/relay/status', (req, res) => {
  res.json({
    relay_status: [
      { relay_id: 1, state: true },
      { relay_id: 2, state: false },
    ],
  });
});

// User API
app.get('/api/users', (req, res) => {
  res.json({ message: 'User API OK' });
});

module.exports = apiLimiter;