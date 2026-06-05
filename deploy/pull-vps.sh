#!/usr/bin/env bash
# Pull code GitHub -> VPS /var/www/plant-iot (Node + AI).
# Chạy TRÊN VPS:
#   curl -fsSL https://raw.githubusercontent.com/daoquy123/Plant_IOT_Flutter/main/deploy/pull-vps.sh | bash
# hoặc sau khi đã có deploy/:
#   bash /var/www/plant-iot/deploy/pull-vps.sh
set -euo pipefail

REPO_URL="${PLANT_IOT_GIT_URL:-https://github.com/daoquy123/Plant_IOT_Flutter.git}"
BRANCH="${PLANT_IOT_BRANCH:-main}"
DEPLOY_ROOT="${DEPLOY_ROOT:-/var/www/plant-iot}"
PULL_DIR="${PULL_DIR:-/tmp/plant-iot-pull}"

echo "=== [1/5] Clone ${REPO_URL} (${BRANCH}) -> ${PULL_DIR} ==="
rm -rf "$PULL_DIR"
git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$PULL_DIR"
echo "Commit: $(git -C "$PULL_DIR" rev-parse --short HEAD) $(git -C "$PULL_DIR" log -1 --pretty=%s)"

mkdir -p "$DEPLOY_ROOT/server"

echo "=== [2/5] Sync Node server -> ${DEPLOY_ROOT}/server (giữ .env, data, uploads) ==="
rsync -a --delete \
  --exclude 'node_modules/' \
  --exclude '.env' \
  --exclude 'data/' \
  --exclude 'uploads/' \
  --exclude 'logs/' \
  "$PULL_DIR/Plant_IOT_Flutter-nhan/server/" "$DEPLOY_ROOT/server/"

echo "=== [3/5] Sync AI app + deploy scripts -> ${DEPLOY_ROOT} ==="
rsync -a "$PULL_DIR/app/" "$DEPLOY_ROOT/app/"
rsync -a "$PULL_DIR/deploy/" "$DEPLOY_ROOT/deploy/"
chmod +x "$DEPLOY_ROOT/deploy/"*.sh 2>/dev/null || true

if [[ ! -f "$DEPLOY_ROOT/server/.env" ]]; then
  echo "WARN: chưa có ${DEPLOY_ROOT}/server/.env — copy từ .env.example và điền API_KEY, email..."
fi

echo "=== [4/5] npm install + restart plant-iot ==="
cd "$DEPLOY_ROOT/server"
npm install --omit=dev
if pm2 describe plant-iot >/dev/null 2>&1; then
  pm2 restart plant-iot
else
  pm2 start server.js --name plant-iot --cwd "$DEPLOY_ROOT/server"
fi
pm2 save

echo "=== [5/5] Restart plant-ai (logging chi tiết) ==="
cd "$DEPLOY_ROOT"
export AI_LOG_LEVEL="${AI_LOG_LEVEL:-INFO}"
bash deploy/deploy-ai.sh

echo ""
echo "=== Done ==="
echo "Node:  pm2 logs plant-iot --lines 20"
echo "AI:    pm2 logs plant-ai | grep '\\[plant-ai\\]'"
echo "Health: curl -s http://127.0.0.1:3000/health && curl -s http://127.0.0.1:8000/health"
