#!/usr/bin/env bash
set -e
ROOT="/mnt/d/Downloads/Plant_IOT_Flutter"
cd "$ROOT"
source .venv-wsl/bin/activate

echo "=== GPU check ==="
python scripts/check_gpu.py

echo "=== Train ResNet50+CBAM ==="
cd app/ml
python train_resnet50.py --use-cbam --seed 123 --batch-size 48

echo "=== Train VGG16+CBAM ==="
python train_vgg16_cbam.py --seed 123 --batch-size 48

echo "=== Charts ResNet50+CBAM ==="
python generate_report_charts.py \
  --model resnet50_cbam \
  --weights ../checkpoints/resnet50_cbam_best.weights.h5 \
  --history ../checkpoints/resnet50_cbam_training_history.json \
  --prefix resnet50_cbam_ \
  --fig-dir ../../reports/figures \
  --reports-dir ../../reports

echo "=== Charts VGG16+CBAM ==="
python generate_report_charts.py \
  --model vgg16_cbam \
  --weights ../checkpoints/vgg16_cbam_best.weights.h5 \
  --history ../checkpoints/training_history.json \
  --prefix vgg16_cbam_ \
  --fig-dir ../../reports/figures \
  --reports-dir ../../reports

echo "=== DONE ==="
