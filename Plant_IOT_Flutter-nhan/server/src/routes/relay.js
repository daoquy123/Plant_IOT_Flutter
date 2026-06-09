const express = require('express');
const { config } = require('../../config/env');
const {
  createRelayState,
  getRelayStatus,
  getRelayHistory,
  getPumpRuns,
} = require('../../services/relayService');
const {
  isPumpSessionActive,
  runPumpSession,
  sessionDurationSeconds,
} = require('../../services/relayActionService');

const router = express.Router();

function parseBoolean(value) {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === 'true' || normalized === '1' || normalized === 'on';
  }
  return null;
}

/** Map optional high-level actions to relay_id + state (ESP32 / Flutter convenience). */
function actionToRelay(body) {
  const action = body.action != null ? String(body.action).trim().toLowerCase() : '';
  if (!action) return null;
  const map = {
    shade_on: { relay_id: 1, state: true, relay_name: body.relay_name || 'Shade' },
    shade_off: { relay_id: 1, state: false, relay_name: body.relay_name || 'Shade' },
    pump_on: { relay_id: 2, state: true, relay_name: body.relay_name || 'Pump' },
    pump_off: { relay_id: 2, state: false, relay_name: body.relay_name || 'Pump' },
  };
  return map[action] || null;
}

router.post('/', (req, res, next) => {
  const body = req.body || {};
  const action = body.action != null ? String(body.action).trim().toLowerCase() : '';

  if (action === 'pump_start') {
    if (isPumpSessionActive()) {
      return res.status(409).json({
        success: false,
        message: 'Máy bơm đang trong phiên tưới. Vui lòng đợi hết phiên.',
      });
    }

    const hooks = {
      io: req.app.locals.io,
      publishRelayState: req.app.locals.publishRelayState,
    };
    const durationSeconds = sessionDurationSeconds(body.duration_seconds);
    const triggeredBy = body.triggered_by || 'app_action';

    res.status(202).json({
      success: true,
      started: true,
      duration_seconds: durationSeconds,
      message: `Đã bắt đầu phiên tưới ${durationSeconds}s.`,
    });

    runPumpSession(triggeredBy, hooks, { durationSeconds }).catch((err) => {
      console.error('[PUMP-SESSION] Manual session failed:', err.message);
    });
    return;
  }

  let relayId = Number(body.relay_id);
  let state = parseBoolean(body.state);
  let relayName = body.relay_name;
  let triggeredBy = body.triggered_by || 'app';

  if (!Number.isInteger(relayId) || relayId <= 0 || state === null) {
    const fromAction = actionToRelay(body);
    if (fromAction) {
      relayId = fromAction.relay_id;
      state = fromAction.state;
      relayName = body.relay_name || fromAction.relay_name;
      triggeredBy = body.triggered_by || 'app_action';
    }
  }

  if (!Number.isInteger(relayId) || relayId <= 0) {
    return res.status(400).json({
      success: false,
      message: 'relay_id is required and must be a positive integer (or use action: shade_on/shade_off/pump_on/pump_off).',
    });
  }

  if (state === null) {
    return res.status(400).json({
      success: false,
      message: 'state is required (boolean) or use action: shade_on/shade_off/pump_on/pump_off.',
    });
  }

  createRelayState({
    relay_id: relayId,
    relay_name: relayName,
    state,
    triggered_by: triggeredBy,
    device_id: body.device_id,
  }, (err, relayStatus) => {
    if (err) {
      return next(err);
    }

    req.app.locals.io.emit('relay', { relay_status: relayStatus });
    if (typeof req.app.locals.publishRelayState === 'function') {
      req.app.locals.publishRelayState(relayStatus);
    }
    res.json({
      success: true,
      relay_status: relayStatus,
      command: {
        cover: relayId === 1 ? state : undefined,
        pump: relayId === 2 ? state : undefined,
        action: relayId === 1
          ? (state ? 'shade_on' : 'shade_off')
          : relayId === 2
            ? (state ? 'pump_on' : 'pump_off')
            : undefined,
      },
    });
  });
});

router.get('/', (req, res, next) => {
  getRelayStatus((err, relayStatus) => {
    if (err) {
      return next(err);
    }
    res.json({ success: true, relay_status: relayStatus });
  });
});

/** Alias for clients that call GET .../relay/status */
router.get('/status', (req, res, next) => {
  getRelayStatus((err, relayStatus) => {
    if (err) {
      return next(err);
    }
    res.json({ success: true, relay_status: relayStatus });
  });
});

router.get('/pump-runs', (req, res, next) => {
  const limit = Math.min(500, Math.max(1, Number(req.query.limit) || 100));
  const offset = Math.max(0, Number(req.query.offset) || 0);
  getPumpRuns({ limit, offset }, (err, pump_runs) => {
    if (err) {
      return next(err);
    }
    res.json({ success: true, pump_runs });
  });
});

router.get('/history', (req, res, next) => {
  const limit = Math.min(500, Math.max(1, Number(req.query.limit) || 100));
  const offset = Math.max(0, Number(req.query.offset) || 0);
  getRelayHistory({ limit, offset }, (err, relay_history) => {
    if (err) {
      return next(err);
    }
    res.json({ success: true, relay_history });
  });
});

module.exports = router;
