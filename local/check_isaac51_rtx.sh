#!/usr/bin/env bash
set -euo pipefail

# Keep the reference test independent of host Python packages and NFS caches.
export DOCKER_HOST="unix:///run/docker-robolab.sock"
gpu="${PI05_EVAL_GPU:-1}"
log_dir="/mnt/38_store/myx/robolab/logs"
mkdir -p "$log_dir"
log_file="$log_dir/isaac51-rtx-reference-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
printf 'Official Isaac Sim RTX reference test. Full log: %s\n' "$log_file"

docker run --rm --pull=never --init --entrypoint bash \
    --runtime=nvidia --gpus "\"device=$gpu\"" --network=host \
    --user 1234:1234 --shm-size=2g --ulimit core=0 \
    -e ACCEPT_EULA=Y -e OMNI_KIT_ACCEPT_EULA=Y \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -v "/home/myx/RoboLab/local/isaac51_rtx_smoke.py:/tmp/isaac51_rtx_smoke.py:ro" \
    nvcr.io/nvidia/isaac-sim:5.1.0 \
    -c 'timeout 180 ./python.sh "/tmp/isaac51_rtx_smoke.py"' 2>&1 | tee "$log_file"
