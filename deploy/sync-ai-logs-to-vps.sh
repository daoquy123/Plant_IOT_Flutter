#!/usr/bin/env bash
# Đồng bộ code AI (logging chi tiết) lên VPS.
# Usage: VPS=root@103.116.38.192 REMOTE=/var/www/plant-iot bash deploy/sync-ai-logs-to-vps.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VPS="${VPS:-root@103.116.38.192}"
REMOTE="${REMOTE:-/var/www/plant-iot}"

echo "Sync -> ${VPS}:${REMOTE}"
rsync -avz \
  "${ROOT_DIR}/app/main.py" \
  "${ROOT_DIR}/app/logging_setup.py" \
  "${VPS}:${REMOTE}/app/"

rsync -avz "${ROOT_DIR}/app/ml/predictor.py" "${VPS}:${REMOTE}/app/ml/"
rsync -avz "${ROOT_DIR}/deploy/deploy-ai.sh" "${VPS}:${REMOTE}/deploy/"

echo "Restart plant-ai..."
ssh "${VPS}" "cd ${REMOTE} && export AI_LOG_LEVEL=INFO && bash deploy/deploy-ai.sh"

echo "Done — pm2 logs plant-ai --lines 30"
