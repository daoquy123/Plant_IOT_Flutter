#!/usr/bin/env bash
set -euo pipefail

# Deploy AI service (FastAPI + TensorFlow) on Ubuntu VPS.
# Usage (on VPS):
#   cd /var/www/plant-iot
#   bash deploy/deploy-ai.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/5] Pull latest code..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git fetch --all
  git reset --hard origin/main
fi

echo "[2/5] Python venv + dependencies..."
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements-ai-prod.txt

echo "[3/5] Verify model weights..."
WEIGHTS=(
  "app/checkpoints/vgg16_cbam_best.weights.h5"
  "app/checkpoints/resnet50_best.weights.h5"
)
for w in "${WEIGHTS[@]}"; do
  if [[ ! -f "$w" ]]; then
    echo "WARN: missing $w (vgg16/resnet predict may fail until uploaded)"
  else
    echo "OK: $w"
  fi
done

echo "[4/5] PM2 restart AI..."
mkdir -p logs
pm2 delete plant-ai 2>/dev/null || true
pm2 start "$ROOT_DIR/.venv/bin/uvicorn" \
  --name plant-ai \
  --interpreter none \
  --cwd "$ROOT_DIR" \
  -- \
  app.main:app --host 0.0.0.0 --port 8000 --workers 1
pm2 save

echo "[5/5] Health check..."
sleep 3
curl -fsS "http://127.0.0.1:8000/health" && echo
echo "Done. Flutter Settings -> URL AI Server: http://103.116.38.192:8000"
