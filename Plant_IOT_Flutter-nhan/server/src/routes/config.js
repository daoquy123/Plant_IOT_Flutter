const express = require('express');
const { config } = require('../../config/env');

const router = express.Router();

/** Public config for Flutter (no secrets). Values from server `.env`. */
router.get('/', (req, res) => {
  res.json({
    success: true,
    public_server_url: config.PUBLIC_SERVER_URL,
    ai_server_url: config.AI_SERVER_URL,
    camera_url: config.CAMERA_URL,
  });
});

module.exports = router;
