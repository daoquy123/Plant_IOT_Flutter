const { config } = require('../config/env');

function authMiddleware(req, res, next) {
  if (req.path === '/health') {
    return next();
  }

  const apiKey = req.header('X-API-KEY') || '';
  if (!apiKey || apiKey !== config.API_KEY) {
    return res.status(401).json({
      success: false,
      message: 'Unauthorized. Missing or invalid X-API-KEY.',
    });
  }

  return next();
}

module.exports = authMiddleware;
