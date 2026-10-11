#!/usr/bin/env bash
set -euo pipefail

source "/home/myx/RoboLab/local/pi05_env.sh"
export CUDA_VISIBLE_DEVICES="${PI05_SERVER_GPU:-2}"
export CUDA_VISIBLE_DEVICES=6 \
export XLA_PYTHON_CLIENT_MEM_FRACTION=0.5

cd "/home/myx/openpi"
exec "/mnt/38_store/myx/robolab/venv-openpi/bin/python" \
    "scripts/serve_policy.py" --port=8030 policy:checkpoint \
    --policy.config=pi05_droid_jointpos \
    --policy.dir=gs://openpi-assets-simeval/pi05_droid_jointpos "$@"
