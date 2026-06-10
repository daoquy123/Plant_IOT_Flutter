#!/usr/bin/env bash
source /mnt/d/Downloads/Plant_IOT_Flutter/.venv-wsl/bin/activate
SITE=$(python -c "import site; print(site.getsitepackages()[0])")
export LD_LIBRARY_PATH=$(find "$SITE/nvidia" -name 'lib' -type d 2>/dev/null | tr '\n' ':'):/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}
export TF_CPP_MIN_LOG_LEVEL=2
