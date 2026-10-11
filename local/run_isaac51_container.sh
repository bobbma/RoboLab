#!/usr/bin/env bash
set -euo pipefail

export DOCKER_HOST="unix:///run/docker-robolab.sock"
image="${ROBO_CONTAINER_IMAGE:-nvcr.io/nvidia/isaac-sim:5.1.0}"
base="/mnt/38_store/myx/robolab/docker/isaac-sim"
gpu="${PI05_EVAL_GPU:-1}"

docker info >/dev/null
docker image inspect "$image" >/dev/null
for directory in cache/main cache/computecache cache/kit logs/kit-portable config data/kit-portable pkg; do
    if [[ ! -d "$base/$directory" ]]; then
        printf 'Missing container directory: %s\n' "$base/$directory" >&2
        exit 1
    fi
done

exec docker run --rm --pull=never --init --entrypoint bash \
    --runtime=nvidia --gpus "\"device=$gpu\"" --network=host \
    --user "$(id -u):$(id -g)" --group-add 1234 --shm-size=2g --ulimit core=0 \
    -e ACCEPT_EULA=Y -e OMNI_KIT_ACCEPT_EULA=Y \
    -e NVIDIA_DRIVER_CAPABILITIES=all -e HOME=/isaac-sim \
    -v "$base/cache/main:/isaac-sim/.cache:rw" \
    -v "$base/cache/computecache:/isaac-sim/.nv/ComputeCache:rw" \
    -v "$base/cache/kit:/isaac-sim/kit/cache:rw" \
    -v "$base/data/kit-portable:/isaac-sim/kit/data:rw" \
    -v "$base/logs/kit-portable:/isaac-sim/kit/logs:rw" \
    -v "$base/logs:/isaac-sim/.nvidia-omniverse/logs:rw" \
    -v "$base/config:/isaac-sim/.nvidia-omniverse/config:rw" \
    -v "$base/data:/isaac-sim/.local/share/ov/data:rw" \
    -v "$base/pkg:/isaac-sim/.local/share/ov/pkg:rw" \
    -v "/home/myx/RoboLab:/home/myx/RoboLab:ro" \
    -v "/mnt/38_store/myx/robolab:/mnt/38_store/myx/robolab:rw" \
    "$image" "$@"
