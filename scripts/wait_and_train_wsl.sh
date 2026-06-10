#!/usr/bin/env bash
set -e
ROOT="/mnt/d/Downloads/Plant_IOT_Flutter"
LOG="$ROOT/logs/train_wsl.log"
mkdir -p "$ROOT/logs"
exec > >(tee -a "$LOG") 2>&1

echo "[$(date)] Waiting for pip install..."
while pgrep -f "pip install -r requirements-gpu-wsl" >/dev/null 2>&1; do
  sleep 20
done
echo "[$(date)] Pip finished. Starting training pipeline..."
sed -i 's/\r$//' "$ROOT/scripts/run_train_wsl.sh"
bash "$ROOT/scripts/run_train_wsl.sh"
echo "[$(date)] All done."
