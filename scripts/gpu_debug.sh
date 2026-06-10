#!/usr/bin/env bash
export TF_CPP_MIN_LOG_LEVEL=0
source /mnt/d/Downloads/Plant_IOT_Flutter/.venv-wsl/bin/activate
python /mnt/d/Downloads/Plant_IOT_Flutter/scripts/check_gpu.py 2>&1 | grep -E 'dlopen|GPU|library|cuda|Could not|Skipping'
