const fs = require('fs');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
const { config } = require('./env');

const databasePath = path.resolve(__dirname, '..', config.DB_PATH);
const databaseDir = path.dirname(databasePath);
fs.mkdirSync(databaseDir, { recursive: true });

let db;

function getDb() {
  if (!db) {
    db = new sqlite3.Database(databasePath, (err) => {
      if (err) {
        console.error('Error opening database:', err.message);
      } else {
        console.log('Connected to SQLite database');
        db.run('PRAGMA journal_mode = WAL');
        db.run('PRAGMA foreign_keys = ON');
      }
    });
  }
  return db;
}

function runMigrations() {
  const database = getDb();
  const migrations = `
    CREATE TABLE IF NOT EXISTS sensor_readings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      temperature REAL,
      humidity REAL,
      soil_moisture INTEGER,
      rain INTEGER,
      device_id TEXT,
      recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_sensor_readings_recorded_at ON sensor_readings(recorded_at);

    CREATE TABLE IF NOT EXISTS relay_states (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      relay_id INTEGER NOT NULL,
      relay_name TEXT,
      state INTEGER DEFAULT 0,
      triggered_by TEXT DEFAULT 'app',
      changed_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_relay_states_relay_id ON relay_states(relay_id);

    CREATE TABLE IF NOT EXISTS camera_images (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      filename TEXT NOT NULL,
      filepath TEXT NOT NULL,
      file_size INTEGER,
      captured_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_camera_images_captured_at ON camera_images(captured_at);

    CREATE TABLE IF NOT EXISTS chat_messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS notifications (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      message TEXT,
      sensor_value REAL,
      is_read INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS device_status (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_id TEXT NOT NULL,
      ip_address TEXT,
      last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
      is_online INTEGER DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_device_status_device_id ON device_status(device_id);
  `;

  database.exec(migrations, (err) => {
    if (err) {
      console.error('Migration error:', err.message);
    } else {
      console.log('Database migrations completed');
    }
  });
}

function cleanOldData() {
  const database = getDb();
  const retentionSensor = config.SENSOR_RETENTION_DAYS || 30;
  const retentionImages = config.IMAGE_RETENTION_DAYS || 7;

  const sensorCutoff = new Date();
  sensorCutoff.setDate(sensorCutoff.getDate() - retentionSensor);

  database.run(
    'DELETE FROM sensor_readings WHERE recorded_at < ?',
    [sensorCutoff.toISOString()],
    function(err) {
      if (err) {
        console.error('Error cleaning sensor data:', err.message);
      } else {
        console.log(`Cleaned ${this.changes} old sensor readings`);
      }
    }
  );

  const imageCutoff = new Date();
  imageCutoff.setDate(imageCutoff.getDate() - retentionImages);

  database.all(
    'SELECT filepath FROM camera_images WHERE captured_at < ?',
    [imageCutoff.toISOString()],
    (err, rows) => {
      if (err) {
        console.error('Error querying old images:', err.message);
        return;
      }

      rows.forEach((row) => {
        fs.unlink(row.filepath, (unlinkErr) => {
          if (unlinkErr) console.error('Error deleting file:', unlinkErr.message);
        });
      });

      database.run(
        'DELETE FROM camera_images WHERE captured_at < ?',
        [imageCutoff.toISOString()],
        function(deleteErr) {
          if (deleteErr) {
            console.error('Error cleaning image records:', deleteErr.message);
          } else {
            console.log(`Cleaned ${this.changes} old image records`);
          }
        }
      );
    }
  );
}

function closeDb() {
  if (db) {
    db.close((err) => {
      if (err) {
        console.error('Error closing database:', err.message);
      } else {
        console.log('Database connection closed');
      }
    });
  }
}

module.exports = {
  getDb,
  closeDb,
  cleanOldData,
  runMigrations,
};
