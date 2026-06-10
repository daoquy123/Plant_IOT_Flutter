#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/d/Downloads/Plant_IOT_Flutter"
cd "$ROOT"

echo "=== Setup WSL venv ==="
if [[ ! -d .venv-wsl ]]; then
  python3 -m venv .venv-wsl
fi
source .venv-wsl/bin/activate
python -m pip install --upgrade pip
pip install -r requirements-gpu-wsl.txt
pip install scikit-learn matplotlib seaborn

echo "=== GPU check ==="
python scripts/check_gpu.py

echo "=== Train ResNet50+CBAM ==="
cd app/ml
python train_resnet50.py --use-cbam --seed 123 --batch-size 48

echo "=== Train VGG16+CBAM ==="
python train_vgg16_cbam.py --seed 123 --batch-size 48

echo "=== Generate charts ResNet50+CBAM ==="
python generate_report_charts.py \
  --model resnet50_cbam \
  --weights ../checkpoints/resnet50_cbam_best.weights.h5 \
  --history ../checkpoints/resnet50_cbam_training_history.json \
  --prefix resnet50_cbam_ \
  --fig-dir ../../reports/figures \
  --reports-dir ../../reports

echo "=== Generate charts VGG16+CBAM ==="
python generate_report_charts.py \
  --model vgg16_cbam \
  --weights ../checkpoints/vgg16_cbam_best.weights.h5 \
  --history ../checkpoints/training_history.json \
  --prefix vgg16_cbam_ \
  --fig-dir ../../reports/figures \
  --reports-dir ../../reports

echo "=== DONE ==="
