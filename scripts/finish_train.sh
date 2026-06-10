#!/usr/bin/env bash
set -e
ROOT="/mnt/d/Downloads/Plant_IOT_Flutter"
source "$ROOT/scripts/env_gpu.sh"
KERAS_DIR="$HOME/.keras/models"
mkdir -p "$KERAS_DIR"
VGG="$KERAS_DIR/vgg16_weights_tf_dim_ordering_tf_kernels_notop.h5"
if [ ! -f "$VGG" ]; then
  echo "Downloading VGG16 weights..."
  curl -L --retry 5 -o "$VGG" \
    https://storage.googleapis.com/tensorflow/keras-applications/vgg16/vgg16_weights_tf_dim_ordering_tf_kernels_notop.h5
fi

cd "$ROOT/app/ml"
echo "=== VGG16+CBAM ==="
python train_vgg16_cbam.py --seed 123 --batch-size 48

echo "=== Charts ==="
python generate_report_charts.py --model resnet50_cbam --weights ../checkpoints/resnet50_cbam_best.weights.h5 --history ../checkpoints/resnet50_cbam_training_history.json --prefix resnet50_cbam_ --fig-dir ../../reports/figures --reports-dir ../../reports
python generate_report_charts.py --model vgg16_cbam --weights ../checkpoints/vgg16_cbam_best.weights.h5 --history ../checkpoints/training_history.json --prefix vgg16_cbam_ --fig-dir ../../reports/figures --reports-dir ../../reports
echo "DONE"
