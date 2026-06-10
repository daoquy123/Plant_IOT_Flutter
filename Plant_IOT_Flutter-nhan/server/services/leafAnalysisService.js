const { getDb } = require('../config/database');
const { vnToUtcIso } = require('./dailyReportService');

/** Lá vàng trở lên — không tính la_khoe, co */
const UNHEALTHY_LEAF_LABELS = new Set(['la_vang', 'la_sau', 'sau']);

function normalizeLabel(result) {
  if (!result || typeof result !== 'object') return null;
  const raw = result.label
    ?? result.prediction
    ?? result.class
    ?? result.disease;
  if (raw == null) return null;
  return String(raw).trim().toLowerCase();
}

function isUnhealthyLeafLabel(label) {
  if (!label) return false;
  return UNHEALTHY_LEAF_LABELS.has(String(label).trim().toLowerCase());
}

function extractConfidence(result) {
  const conf = result?.confidence ?? result?.probability ?? result?.score ?? result?.prob;
  if (typeof conf !== 'number' || Number.isNaN(conf)) return null;
  return conf <= 1 ? conf : conf / 100;
}

function recordLeafAnalysis({
  label,
  labelVietnamese = null,
  confidence = null,
  model = 'resnet',
  source = 'unknown',
  deviceId = null,
  analyzedAt = null,
}) {
  const normalized = String(label || '').trim().toLowerCase();
  if (!normalized) {
    return Promise.resolve({ inserted: false, reason: 'empty_label' });
  }

  const db = getDb();
  const sql = `
    INSERT INTO leaf_analysis_log (
      label, label_vietnamese, confidence, model, source, device_id, analyzed_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `;
  const ts = analyzedAt || new Date().toISOString();

  return new Promise((resolve, reject) => {
    db.run(
      sql,
      [
        normalized,
        labelVietnamese,
        confidence,
        model,
        source,
        deviceId,
        ts,
      ],
      function onRun(err) {
        if (err) reject(err);
        else resolve({ inserted: true, id: this.lastID, unhealthy: isUnhealthyLeafLabel(normalized) });
      },
    );
  });
}

async function recordFromPredictResult({
  result,
  model,
  source,
  deviceId = null,
}) {
  const label = normalizeLabel(result);
  if (!label) return { inserted: false, reason: 'no_label' };
  return recordLeafAnalysis({
    label,
    labelVietnamese: result?.label_vietnamese ?? null,
    confidence: extractConfidence(result),
    model,
    source,
    deviceId,
  });
}

function dayBoundsIso(dateKey) {
  return {
    startIso: vnToUtcIso(dateKey, 0),
    endIso: (() => {
      const end = new Date(`${dateKey}T00:00:00+07:00`);
      end.setUTCDate(end.getUTCDate() + 1);
      return end.toISOString();
    })(),
  };
}

function countUnhealthyForDay(dateKey) {
  const { startIso, endIso } = dayBoundsIso(dateKey);
  const db = getDb();
  const placeholders = [...UNHEALTHY_LEAF_LABELS].map(() => '?').join(', ');

  return new Promise((resolve, reject) => {
    db.get(
      `SELECT COUNT(*) AS unhealthy_count
       FROM leaf_analysis_log
       WHERE analyzed_at >= ? AND analyzed_at < ?
         AND label IN (${placeholders})`,
      [startIso, endIso, ...UNHEALTHY_LEAF_LABELS],
      (err, row) => {
        if (err) reject(err);
        else resolve(Number(row?.unhealthy_count) || 0);
      },
    );
  });
}

function countAllForDay(dateKey) {
  const { startIso, endIso } = dayBoundsIso(dateKey);
  const db = getDb();
  return new Promise((resolve, reject) => {
    db.get(
      `SELECT COUNT(*) AS total FROM leaf_analysis_log
       WHERE analyzed_at >= ? AND analyzed_at < ?`,
      [startIso, endIso],
      (err, row) => {
        if (err) reject(err);
        else resolve(Number(row?.total) || 0);
      },
    );
  });
}

module.exports = {
  UNHEALTHY_LEAF_LABELS,
  normalizeLabel,
  isUnhealthyLeafLabel,
  recordLeafAnalysis,
  recordFromPredictResult,
  countUnhealthyForDay,
  countAllForDay,
};
