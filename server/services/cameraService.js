const fs = require('fs');
const path = require('path');
const { getDb } = require('../config/database');
const { config } = require('../config/env');

const uploadBasePath = path.resolve(__dirname, '..', config.UPLOADS_DIR);

function saveImage(file, { capturedAt } = {}, callback) {
  const db = getDb();
  const sql = `
    INSERT INTO camera_images (
      filename,
      filepath,
      file_size,
      captured_at
    ) VALUES (?, ?, ?, ?)
  `;

  const values = [
    file.filename,
    file.path,
    file.size,
    capturedAt || new Date().toISOString()
  ];

  db.run(sql, values, function(err) {
    if (err) {
      return callback(err);
    }

    const result = {
      id: this.lastID,
      filename: file.filename,
      filepath: file.path,
      file_size: file.size,
      captured_at: capturedAt || new Date().toISOString()
    };

    callback(null, result);
  });
}

function getLatestImage(callback) {
  const db = getDb();
  const sql = 'SELECT id, filename, filepath, file_size, captured_at FROM camera_images ORDER BY captured_at DESC LIMIT 1';

  db.get(sql, (err, row) => {
    if (err) {
      return callback(err);
    }
    callback(null, row || null);
  });
}

function listImages({ limit = 50, offset = 0 }, callback) {
  const db = getDb();
  const sql = 'SELECT id, filename, filepath, file_size, captured_at FROM camera_images ORDER BY captured_at DESC LIMIT ? OFFSET ?';

  db.all(sql, [limit, offset], (err, rows) => {
    if (err) {
      return callback(err);
    }
    callback(null, rows);
  });
}

function cleanupOldImages(days, callback) {
  const db = getDb();
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - days);

  const sql = 'SELECT id, filepath FROM camera_images WHERE captured_at <= ?';
  db.all(sql, [cutoffDate.toISOString()], (err, rows) => {
    if (err) {
      return callback ? callback(err) : console.error('Error querying old images:', err);
    }

    let deletedCount = 0;
    const deletePromises = rows.map(row => {
      return new Promise((resolve) => {
        fs.unlink(row.filepath, (err) => {
          if (err) {
            console.warn('Failed to delete stale image file:', row.filepath, err.message);
          }
          resolve();
        });
      });
    });

    Promise.all(deletePromises).then(() => {
      const deleteSql = 'DELETE FROM camera_images WHERE id IN (' + rows.map(() => '?').join(',') + ')';
      const ids = rows.map(row => row.id);

      if (ids.length > 0) {
        db.run(deleteSql, ids, function(err) {
          if (err) {
            console.error('Error deleting image records:', err);
          } else {
            deletedCount = this.changes;
            console.log(`Cleaned up ${deletedCount} old image records`);
          }
          if (callback) callback(null, deletedCount);
        });
      } else {
        if (callback) callback(null, 0);
      }
    });
  });
}

function getUploadsDirectorySize(callback) {
  getDirectorySize(uploadBasePath, callback);
}

function getDirectorySize(directory, callback) {
  if (!fs.existsSync(directory)) {
    return callback(null, 0);
  }

  fs.readdir(directory, (err, files) => {
    if (err) {
      return callback(err);
    }

    let total = 0;
    let processed = 0;

    if (files.length === 0) {
      return callback(null, 0);
    }

    files.forEach(file => {
      const fullPath = path.join(directory, file);
      fs.stat(fullPath, (err, stats) => {
        if (!err) {
          if (stats.isDirectory()) {
            getDirectorySize(fullPath, (err, size) => {
              total += size;
              processed++;
              if (processed === files.length) {
                callback(null, total);
              }
            });
          } else {
            total += stats.size;
            processed++;
            if (processed === files.length) {
              callback(null, total);
            }
          }
        } else {
          processed++;
          if (processed === files.length) {
            callback(null, total);
          }
        }
      });
    });
  });
}

module.exports = {
  saveImage,
  getLatestImage,
  listImages,
  cleanupOldImages,
  getUploadsDirectorySize,
  getDirectorySize,
};
