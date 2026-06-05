const { createRelayState } = require('./relayService');

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

module.exports = {
  performPumpAction,
  performPumpActionAsync,
};
