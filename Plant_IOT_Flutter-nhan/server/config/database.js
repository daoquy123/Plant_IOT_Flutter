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
      raw_payload TEXT,
      source TEXT,
      recorded_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_sensor_readings_recorded_at ON sensor_readings(recorded_at);

    CREATE TABLE IF NOT EXISTS relay_states (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      relay_id INTEGER NOT NULL,
      relay_name TEXT,
      relay_type TEXT,
      state INTEGER DEFAULT 0,
      triggered_by TEXT DEFAULT 'app',
      device_id TEXT,
      changed_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_relay_states_relay_id ON relay_states(relay_id);

    CREATE TABLE IF NOT EXISTS camera_images (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      filename TEXT NOT NULL,
      filepath TEXT NOT NULL,
      public_url TEXT,
      device_id TEXT,
      request_id TEXT,
      upload_source TEXT,
      file_size INTEGER,
      uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      captured_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_camera_images_captured_at ON camera_images(captured_at);

    CREATE TABLE IF NOT EXISTS camera_capture_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_id TEXT NOT NULL UNIQUE,
      device_id TEXT,
      status TEXT NOT NULL,
      requested_by TEXT DEFAULT 'app',
      requested_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_camera_capture_requests_requested_at ON camera_capture_requests(requested_at);

    CREATE TABLE IF NOT EXISTS pump_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      relay_state_on_id INTEGER,
      relay_state_off_id INTEGER,
      relay_id INTEGER DEFAULT 2,
      relay_name TEXT DEFAULT 'Pump',
      triggered_by TEXT DEFAULT 'app',
      device_id TEXT,
      started_at DATETIME NOT NULL,
      ended_at DATETIME,
      duration_seconds INTEGER,
      FOREIGN KEY(relay_state_on_id) REFERENCES relay_states(id),
      FOREIGN KEY(relay_state_off_id) REFERENCES relay_states(id)
    );

    CREATE INDEX IF NOT EXISTS idx_pump_runs_started_at ON pump_runs(started_at);

    CREATE TABLE IF NOT EXISTS app_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_type TEXT NOT NULL,
      entity_type TEXT,
      entity_id TEXT,
      action TEXT,
      payload_json TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_app_events_created_at ON app_events(created_at);

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

    CREATE TABLE IF NOT EXISTS growing_cycles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      note TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_growing_cycles_started_at ON growing_cycles(started_at);
    CREATE INDEX IF NOT EXISTS idx_growing_cycles_ended_at ON growing_cycles(ended_at);

    CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS leaf_analysis_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      label TEXT NOT NULL,
      label_vietnamese TEXT,
      confidence REAL,
      model TEXT,
      source TEXT,
      device_id TEXT,
      analyzed_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE INDEX IF NOT EXISTS idx_leaf_analysis_analyzed_at ON leaf_analysis_log(analyzed_at);
    CREATE INDEX IF NOT EXISTS idx_leaf_analysis_label ON leaf_analysis_log(label);
  `;

  database.exec(migrations, (err) => {
    if (err) {
      console.error('Migration error:', err.message);
    } else {
      console.log('Database migrations completed');
      runSchemaUpgrades(database);
    }
  });
}

function addColumnIfMissing(database, table, column, definition) {
  database.all(`PRAGMA table_info(${table})`, (err, rows) => {
    if (err) {
      console.error(`Error reading schema for ${table}:`, err.message);
      return;
    }
    if (rows.some((row) => row.name === column)) return;
    database.run(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`, (alterErr) => {
      if (alterErr) {
        console.error(`Error adding column ${table}.${column}:`, alterErr.message);
      }
    });
  });
}

function ensureColumnAndIndex(database, table, column, definition, indexSql) {
  database.all(`PRAGMA table_info(${table})`, (err, rows) => {
    if (err) {
      console.error(`Error reading schema for ${table}:`, err.message);
      return;
    }
    const createIndex = () => database.run(indexSql, (indexErr) => {
      if (indexErr) {
        console.error(`Error creating index for ${table}.${column}:`, indexErr.message);
      }
    });
    if (rows.some((row) => row.name === column)) {
      createIndex();
      return;
    }
    database.run(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`, (alterErr) => {
      if (alterErr) {
        console.error(`Error adding column ${table}.${column}:`, alterErr.message);
        return;
      }
      createIndex();
    });
  });
}

function ensureChatTables(database) {
  database.run(`
    CREATE TABLE IF NOT EXISTS chat_conversations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT,
      model TEXT,
      source TEXT,
      device_id TEXT,
      image_url TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  `, (err) => {
    if (err) {
      console.error('Error creating chat_conversations:', err.message);
    }
  });
  addColumnIfMissing(database, 'chat_messages', 'conversation_id', 'INTEGER');
}

function runSchemaUpgrades(database) {
  ensureChatTables(database);
  addColumnIfMissing(database, 'sensor_readings', 'raw_payload', 'TEXT');
  addColumnIfMissing(database, 'sensor_readings', 'source', 'TEXT');
  addColumnIfMissing(database, 'relay_states', 'relay_type', 'TEXT');
  addColumnIfMissing(database, 'relay_states', 'device_id', 'TEXT');
  addColumnIfMissing(database, 'camera_images', 'public_url', 'TEXT');
  addColumnIfMissing(database, 'camera_images', 'device_id', 'TEXT');
  ensureColumnAndIndex(
    database,
    'camera_images',
    'request_id',
    'TEXT',
    'CREATE INDEX IF NOT EXISTS idx_camera_images_request_id ON camera_images(request_id)'
  );
  addColumnIfMissing(database, 'camera_images', 'upload_source', 'TEXT');
  addColumnIfMissing(database, 'camera_images', 'uploaded_at', 'DATETIME');
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
