const rateLimit = require('express-rate-limit');

/**
 * Global API limiter for human-facing traffic.
 * Realtime IoT camera/sensor/control endpoints are skipped to avoid throttling ESP32 loops.
 */
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => {
    const path = req.path || '';
    const method = req.method || '';

    // Camera streaming/control from ESP32-CAM (high-frequency, must not be 429-limited).
    if (path === '/api/camera/frame' && method === 'POST') return true;
    if (path === '/api/camera/upload' && method === 'POST') return true;

    // Sensor/relay IoT endpoints can be frequent depending on firmware strategy.
    if (path.startsWith('/api/sensors')) return true;
    if (path.startsWith('/api/relay')) return true;

    return false;
  },
});

module.exports = apiLimiter;
