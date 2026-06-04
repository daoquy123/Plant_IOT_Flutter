const { getDb } = require('../config/database');

function normalizeDateInput(value) {
  if (!value) return null;
  const raw = String(value).trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    return raw;
  }
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.toISOString();
}

function rowToCycle(row) {
  if (!row) return null;
  return {
    id: row.id,
    started_at: row.started_at,
    ended_at: row.ended_at,
    note: row.note,
    created_at: row.created_at,
  };
}

function getActiveCycle(callback) {
  const db = getDb();
  db.get(
    `SELECT * FROM growing_cycles
     WHERE ended_at IS NULL
     ORDER BY started_at DESC
     LIMIT 1`,
    callback,
  );
}

function listCycles({ limit = 20 }, callback) {
  const db = getDb();
  const safeLimit = Math.min(Math.max(Number(limit) || 20, 1), 100);
  db.all(
    `SELECT * FROM growing_cycles
     ORDER BY started_at DESC
     LIMIT ?`,
    [safeLimit],
    callback,
  );
}

function startCycle({ started_at, note }, callback) {
  const startedAt = normalizeDateInput(started_at);
  if (!startedAt) {
    return callback(new Error('started_at không hợp lệ (YYYY-MM-DD)'));
  }

  getActiveCycle((activeErr, activeRow) => {
    if (activeErr) return callback(activeErr);
    if (activeRow) {
      const err = new Error('Đang có chu kỳ trồng chưa kết thúc');
      err.statusCode = 409;
      return callback(err);
    }

    const db = getDb();
    db.run(
      `INSERT INTO growing_cycles (started_at, note, created_at)
       VALUES (?, ?, ?)`,
      [startedAt, note || null, new Date().toISOString()],
      function onInsert(err) {
        if (err) return callback(err);
        db.get('SELECT * FROM growing_cycles WHERE id = ?', [this.lastID], callback);
      },
    );
  });
}

function endCycle(id, callback) {
  const db = getDb();
  const endedAt = new Date().toISOString();
  db.run(
    `UPDATE growing_cycles
     SET ended_at = ?
     WHERE id = ? AND ended_at IS NULL`,
    [endedAt, id],
    function onUpdate(err) {
      if (err) return callback(err);
      if (this.changes === 0) {
        const notFound = new Error('Không tìm thấy chu kỳ đang hoạt động');
        notFound.statusCode = 404;
        return callback(notFound);
      }
      db.get('SELECT * FROM growing_cycles WHERE id = ?', [id], callback);
    },
  );
}

module.exports = {
  rowToCycle,
  getActiveCycle,
  listCycles,
  startCycle,
  endCycle,
};
