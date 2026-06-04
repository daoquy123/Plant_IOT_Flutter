#!/usr/bin/env bash
# Cài API chu kỳ trồng trên VPS (layout: /var/www/plant-iot/server)
set -euo pipefail

ROOT="${1:-/var/www/plant-iot}"
SERVER="$ROOT/server"
REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/daoquy123/Plant_IOT_Flutter/main/Plant_IOT_Flutter-nhan}"

echo "Server dir: $SERVER"
mkdir -p "$SERVER/services" "$SERVER/src/routes"

curl -fsSL -o "$SERVER/services/growingCycleService.js" \
  "$REPO_BASE/server/services/growingCycleService.js"
curl -fsSL -o "$SERVER/src/routes/growing_cycles.js" \
  "$REPO_BASE/server/src/routes/growing_cycles.js"
curl -fsSL -o "$SERVER/src/routes/config.js" \
  "$REPO_BASE/server/src/routes/config.js"
curl -fsSL -o "$SERVER/server.js" "$REPO_BASE/server/server.js"
curl -fsSL -o "$SERVER/config/database.js" "$REPO_BASE/server/config/database.js"

if ! grep -q "growing_cycles" "$SERVER/server.js"; then
  sed -i "/const configRoutes = require/a const growingCycleRoutes = require('./src/routes/growing_cycles');" "$SERVER/server.js"
  sed -i "/app.use('\/api\/camera', cameraRoutes);/a app.use('/api/growing-cycles', growingCycleRoutes);" "$SERVER/server.js"
  echo "Patched server.js"
else
  echo "server.js already has growing-cycles route"
fi

sqlite3 "$SERVER/data/plant_iot.db" "CREATE TABLE IF NOT EXISTS growing_cycles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  note TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_growing_cycles_started_at ON growing_cycles(started_at);
CREATE INDEX IF NOT EXISTS idx_growing_cycles_ended_at ON growing_cycles(ended_at);"

cd "$SERVER"
npm install --production
cd "$ROOT"
pm2 restart plant-iot

echo "Done. Test:"
echo "curl -sS -H \"X-API-KEY: YOUR_KEY\" http://127.0.0.1:3000/api/growing-cycles/active"
