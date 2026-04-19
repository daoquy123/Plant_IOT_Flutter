const { getDb } = require('../config/database');

function createRelayState({ relay_id, relay_name, state, triggered_by }, callback) {
  const db = getDb();
  const sql = `
    INSERT INTO relay_states (
      relay_id,
      relay_name,
      state,
      triggered_by,
      changed_at
    ) VALUES (?, ?, ?, ?, ?)
  `;

  const values = [
    relay_id,
    relay_name || `Relay ${relay_id}`,
    state ? 1 : 0,
    triggered_by || 'app',
    new Date().toISOString()
  ];

  db.run(sql, values, function(err) {
    if (err) {
      return callback(err);
    }
    // Get updated relay status after insert
    getRelayStatus(callback);
  });
}

function getRelayStatus(callback) {
  const db = getDb();
  const sql = `
    SELECT relay_id, relay_name, state, triggered_by, changed_at
    FROM relay_states
    WHERE id IN (
      SELECT MAX(id) FROM relay_states GROUP BY relay_id
    )
    ORDER BY relay_id
  `;

  db.all(sql, (err, rows) => {
    if (err) {
      return callback(err);
    }
    callback(null, rows);
  });
}

function getRelayHistory({ limit = 100, offset = 0 }, callback) {
  const db = getDb();
  const sql = 'SELECT * FROM relay_states ORDER BY changed_at DESC LIMIT ? OFFSET ?';

  db.all(sql, [limit, offset], (err, rows) => {
    if (err) {
      return callback(err);
    }
    callback(null, rows);
  });
}

module.exports = { createRelayState, getRelayStatus, getRelayHistory };
