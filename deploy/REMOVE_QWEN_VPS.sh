#!/usr/bin/env bash
# Gỡ Ollama + chat Qwen trên VPS layout /var/www/plant-iot
set -euo pipefail

echo "=== Dừng Ollama ==="
systemctl stop ollama 2>/dev/null || true
systemctl disable ollama 2>/dev/null || true

echo "=== Gỡ Ollama (nếu đã cài) ==="
if command -v ollama >/dev/null 2>&1; then
  rm -f /usr/local/bin/ollama
fi
rm -rf /usr/share/ollama /usr/local/lib/ollama 2>/dev/null || true
rm -f /etc/systemd/system/ollama.service
systemctl daemon-reload 2>/dev/null || true

echo "=== Xóa model Ollama (~400MB) ==="
rm -rf /root/.ollama /usr/share/ollama 2>/dev/null || true

echo "=== Xóa code chat trong plant-iot ==="
ROOT="${1:-/var/www/plant-iot}"
rm -rf "$ROOT/app/chat"
if [[ -f /tmp/plant-iot-new/app/main.py ]]; then
  cp /tmp/plant-iot-new/app/main.py "$ROOT/app/main.py"
fi

echo "=== Restart API (chỉ predict ảnh) ==="
cd "$ROOT"
pm2 delete plant-ai 2>/dev/null || true
pm2 start "$ROOT/.venv/bin/uvicorn" \
  --name plant-ai \
  --interpreter none \
  --cwd "$ROOT" \
  -- \
  app.main:app --host 0.0.0.0 --port 8000 --workers 1
pm2 save

sleep 3
curl -fsS "http://127.0.0.1:8000/health" && echo
echo "Done. /api/chat đã bỏ — chỉ còn /predict."
