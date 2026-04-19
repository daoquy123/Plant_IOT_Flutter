const fs = require('fs');
const path = require('path');
const os = require('os');
const express = require('express');
const { config } = require('../../config/env');
const { getSensorCount, getLatestSensorTime } = require('../../services/sensorService');
const { getUploadsDirectorySize } = require('../../services/cameraService');

const router = express.Router();
const databasePath = path.resolve(__dirname, '../../', config.DB_PATH);

router.get('/', (req, res, next) => {
  const dbStat = fs.existsSync(databasePath) ? fs.statSync(databasePath) : null;

  // Get sensor count
  getSensorCount((err, sensorCount) => {
    if (err) {
      return next(err);
    }

    // Get latest sensor time
    getLatestSensorTime((err, lastSensor) => {
      if (err) {
        return next(err);
      }

      // Get uploads directory size
      getUploadsDirectorySize((err, uploadSize) => {
        if (err) {
          return next(err);
        }

        res.json({
          success: true,
          uptime_seconds: process.uptime(),
          node_env: config.NODE_ENV,
          database_size_bytes: dbStat ? dbStat.size : 0,
          sensor_record_count: sensorCount,
          last_sensor_recorded_at: lastSensor?.recorded_at || null,
          upload_directory_size_bytes: uploadSize,
          memory: {
            total_bytes: os.totalmem(),
            free_bytes: os.freemem(),
          },
        });
      });
    });
  });
});

module.exports = router;
