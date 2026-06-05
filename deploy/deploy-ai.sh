#!/usr/bin/env bash
set -euo pipefail

# Deploy AI service (FastAPI + TensorFlow) on Ubuntu VPS.
# Usage (on VPS):
#   cd /var/www/plant-iot
#   bash deploy/deploy-ai.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
REPO_URL="${PLANT_IOT_GIT_URL:-https://github.com/daoquy123/Plant_IOT_Flutter.git}"

echo "[1/6] Pull latest code..."
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git fetch --all
  git reset --hard origin/main
else
  echo "WARN: ${ROOT_DIR} is not a git repo — rsync app/ + deploy/ from GitHub..."
  TMP="$(mktemp -d /tmp/plant-iot-pull.XXXXXX)"
  git clone --depth 1 -b main "$REPO_URL" "$TMP"
  rsync -a "$TMP/app/" "$ROOT_DIR/app/"
  rsync -a "$TMP/deploy/" "$ROOT_DIR/deploy/"
  rm -rf "$TMP"
fi

if [[ ! -f "$ROOT_DIR/app/logging_setup.py" ]]; then
  echo "ERROR: thiếu app/logging_setup.py — code logging chưa được deploy."
  exit 1
fi
if ! grep -q configure_ai_logging "$ROOT_DIR/app/main.py"; then
  echo "ERROR: app/main.py chưa có configure_ai_logging — git pull/rsync thất bại."
  exit 1
fi
echo "OK: detailed logging code present"

echo "[2/6] Python venv + dependencies..."
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements-ai-prod.txt

echo "[3/6] Verify model weights..."
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

echo "[4/6] PM2 restart AI..."
mkdir -p logs
export PYTHONUNBUFFERED=1
export AI_LOG_LEVEL="${AI_LOG_LEVEL:-INFO}"
pm2 delete plant-ai 2>/dev/null || true
pm2 start "$ROOT_DIR/.venv/bin/uvicorn" \
  --name plant-ai \
  --interpreter none \
  --cwd "$ROOT_DIR" \
  --update-env \
  -- \
  app.main:app --host 0.0.0.0 --port 8000 --workers 1
pm2 save
echo "PYTHONUNBUFFERED=1 AI_LOG_LEVEL=$AI_LOG_LEVEL"

echo "[5/6] Health check..."
sleep 3
curl -fsS "http://127.0.0.1:8000/health" && echo

echo "[6/6] Verify startup log (grep plant-ai in error log)..."
sleep 1
if grep -q "\[plant-ai\] service started" /root/.pm2/logs/plant-ai-error.log 2>/dev/null; then
  echo "OK: detailed logging active"
else
  echo "WARN: chưa thấy '[plant-ai] service started' — thử: pm2 logs plant-ai --lines 20"
fi

echo "Done. Flutter Settings -> URL AI Server: http://103.116.38.192:8000"
echo "Xem log predict: pm2 logs plant-ai | grep '\\[plant-ai\\]'"
