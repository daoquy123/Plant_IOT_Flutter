#!/usr/bin/env bash
which python3
pip3 show tensorflow 2>/dev/null | head -2
for py in /home/*/.venv/bin/python /home/*/venv/bin/python /home/*/miniconda3/bin/python; do
  if [ -x "$py" ]; then
    echo "=== $py ==="
    "$py" -c "import tensorflow as tf; print('TF', tf.__version__); print('GPU', tf.config.list_physical_devices('GPU'))" 2>&1 | tail -3
  fi
done
source /mnt/d/Downloads/Plant_IOT_Flutter/.venv-wsl/bin/activate
python -c "import tensorflow as tf; print('venv-wsl GPU', tf.config.list_physical_devices('GPU'))" 2>&1 | tail -2
