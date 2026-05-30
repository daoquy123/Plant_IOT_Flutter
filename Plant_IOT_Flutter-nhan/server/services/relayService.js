const { getDb } = require('../config/database');

function relayTypeForId(relayId) {
  if (Number(relayId) === 1) return 'shade';
  if (Number(relayId) === 2) return 'pump';
  return 'relay';
}

function recordAppEvent({ event_type, entity_type, entity_id, action, payload }, callback = () => {}) {
  const db = getDb();
  const sql = `
    INSERT INTO app_events (
      event_type,
      entity_type,
      entity_id,
      action,
      payload_json,
      created_at
    ) VALUES (?, ?, ?, ?, ?, ?)
  `;
  db.run(
    sql,
    [
      event_type,
      entity_type || null,
      entity_id != null ? String(entity_id) : null,
      action || null,
      payload ? JSON.stringify(payload) : null,
      new Date().toISOString(),
    ],
    callback
  );
}

function recordPumpRun({ relayStateId, relay_id, relay_name, state, triggered_by, device_id, changed_at }, callback) {
  const db = getDb();
  if (Number(relay_id) !== 2) return callback();

  if (state) {
    const sql = `
      INSERT INTO pump_runs (
        relay_state_on_id,
        relay_id,
        relay_name,
        triggered_by,
        device_id,
        started_at
      ) VALUES (?, ?, ?, ?, ?, ?)
    `;
    return db.run(
      sql,
      [
        relayStateId,
        relay_id,
        relay_name || 'Pump',
        triggered_by || 'app',
        device_id || null,
        changed_at,
      ],
      callback
    );
  }

  const sql = `
    UPDATE pump_runs
    SET relay_state_off_id = ?,
        ended_at = ?,
        duration_seconds = CAST((julianday(?) - julianday(started_at)) * 86400 AS INTEGER)
    WHERE id = (
      SELECT id FROM pump_runs
      WHERE ended_at IS NULL
      ORDER BY started_at DESC
      LIMIT 1
    )
  `;
  return db.run(sql, [relayStateId, changed_at, changed_at], callback);
}

function createRelayState({ relay_id, relay_name, state, triggered_by, device_id }, callback) {
  const db = getDb();
  const changedAt = new Date().toISOString();
  const relayType = relayTypeForId(relay_id);
  const sql = `
    INSERT INTO relay_states (
      relay_id,
      relay_name,
      relay_type,
      state,
      triggered_by,
      device_id,
      changed_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `;

  const values = [
    relay_id,
    relay_name || `Relay ${relay_id}`,
    relayType,
    state ? 1 : 0,
    triggered_by || 'app',
    device_id || null,
    changedAt
  ];

  db.run(sql, values, function(err) {
    if (err) {
      return callback(err);
    }
    const relayStateId = this.lastID;
    recordPumpRun(
      {
        relayStateId,
        relay_id,
        relay_name: relay_name || `Relay ${relay_id}`,
        state: !!state,
        triggered_by,
        device_id,
        changed_at: changedAt,
      },
      (pumpErr) => {
        if (pumpErr) {
          return callback(pumpErr);
        }
        if ((triggered_by || '').startsWith('app')) {
          recordAppEvent({
            event_type: 'relay_changed',
            entity_type: relayType,
            entity_id: relay_id,
            action: state ? `${relayType}_on` : `${relayType}_off`,
            payload: { relay_id, relay_name, state, triggered_by, device_id },
          });
        }
        getRelayStatus(callback);
      }
    );
  });
}

function getRelayStatus(callback) {
  const db = getDb();
  const sql = `
    SELECT relay_id, relay_name, relay_type, state, triggered_by, device_id, changed_at
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

function getPumpRuns({ limit = 100, offset = 0 }, callback) {
  const db = getDb();
  const sql = 'SELECT * FROM pump_runs ORDER BY started_at DESC LIMIT ? OFFSET ?';

  db.all(sql, [limit, offset], (err, rows) => {
    if (err) {
      return callback(err);
    }
    callback(null, rows);
  });
}

module.exports = {
  createRelayState,
  getRelayStatus,
  getRelayHistory,
  getPumpRuns,
  recordAppEvent,
};
