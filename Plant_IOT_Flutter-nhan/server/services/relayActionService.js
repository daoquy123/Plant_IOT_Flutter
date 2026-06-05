const { config } = require('../config/env');
const { createRelayState } = require('./relayService');

let pumpSessionActive = false;

function isPumpSessionActive() {
  return pumpSessionActive;
}

function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function sessionDurationSeconds(override) {
  const raw = override ?? config.PUMP_SESSION_SECONDS ?? config.AUTO_WATER_PUMP_SECONDS;
  return Math.max(5, Number(raw) || 60);
}

/**
 * Same relay path as POST /api/relay with action pump_on | pump_off.
 * @param {{ io?: import('socket.io').Server, publishRelayState?: (status: unknown) => void }} hooks
 */
function performPumpAction(state, triggeredBy, hooks, callback) {
  createRelayState(
    {
      relay_id: 2,
      relay_name: 'Pump',
      state: !!state,
      triggered_by: triggeredBy,
    },
    (err, relayStatus) => {
      if (err) {
        return callback(err);
      }
      if (hooks?.io) {
        hooks.io.emit('relay', { relay_status: relayStatus });
      }
      if (typeof hooks?.publishRelayState === 'function') {
        hooks.publishRelayState(relayStatus);
      }
      callback(null, {
        relay_status: relayStatus,
        command: {
          pump: !!state,
          action: state ? 'pump_on' : 'pump_off',
        },
      });
    },
  );
}

function performPumpActionAsync(state, triggeredBy, hooks) {
  return new Promise((resolve, reject) => {
    performPumpAction(state, triggeredBy, hooks, (err, result) => {
      if (err) reject(err);
      else resolve(result);
    });
  });
}

/**
 * One pump work session: pump_on → wait → pump_off (manual control & auto-water).
 */
async function runPumpSession(triggeredBy, hooks, { durationSeconds, onStarted } = {}) {
  if (pumpSessionActive) {
    const err = new Error('Pump session already running');
    err.code = 'PUMP_SESSION_BUSY';
    throw err;
  }

  pumpSessionActive = true;
  const seconds = sessionDurationSeconds(durationSeconds);

  try {
    await performPumpActionAsync(true, triggeredBy, hooks);
    if (typeof onStarted === 'function') {
      await onStarted();
    }
    await delay(seconds * 1000);
    await performPumpActionAsync(false, triggeredBy, hooks);
    return { durationSeconds: seconds };
  } finally {
    pumpSessionActive = false;
  }
}

module.exports = {
  performPumpAction,
  performPumpActionAsync,
  runPumpSession,
  isPumpSessionActive,
  sessionDurationSeconds,
};
