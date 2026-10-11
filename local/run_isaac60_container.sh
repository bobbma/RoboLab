#!/usr/bin/env bash
set -euo pipefail

docker_socket="unix:///run/docker-robolab.sock"
image="${ROBO_CONTAINER_IMAGE:-robolab:isaac60}"
base="/mnt/38_store/myx/robolab/docker/isaac60"
gpu="${PI05_EVAL_GPU:-1}"

docker --host "$docker_socket" image inspect "$image" >/dev/null
for directory in cache compute-cache kit-cache kit-data kit-logs config; do
    mkdir -p "$base/$directory"
done

# Docker isolates both CUDA and Vulkan to the same physical GPU selection.
exec docker --host "$docker_socket" run -it --rm --pull=never --init \
    --entrypoint /isaac-sim/python.sh \
    --runtime=nvidia --gpus "\"device=$gpu\"" --network=host \
    --user "$(id -u):$(id -g)" --group-add 1234 --shm-size=4g --ulimit core=0 \
    -e ACCEPT_EULA=Y -e OMNI_KIT_ACCEPT_EULA=Y \
    -e NVIDIA_DRIVER_CAPABILITIES=all -e HOME=/isaac-sim \
    -e PYTHONUNBUFFERED=1 -e PYTHONDONTWRITEBYTECODE=1 \
    -e MPLCONFIGDIR=/isaac-sim/.cache/matplotlib \
    -e PYTHONPATH=/home/myx/RoboLab:/isaac-sim/extsDeprecated/omni.isaac.ml_archive/pip_prebundle \
    -e HUB__CACHE__PATH=/isaac-sim/.cache/hub \
    -v "$base/cache:/isaac-sim/.cache:rw" \
    -v "$base/compute-cache:/isaac-sim/.nv/ComputeCache:rw" \
    -v "$base/kit-cache:/isaac-sim/kit/cache:rw" \
    -v "$base/kit-data:/isaac-sim/kit/data:rw" \
    -v "$base/kit-logs:/isaac-sim/kit/logs:rw" \
    -v "$base/config:/isaac-sim/.nvidia-omniverse/config:rw" \
    -v "/home/myx/RoboLab:/home/myx/RoboLab:ro" \
    -v "/mnt/38_store/myx/robolab:/mnt/38_store/myx/robolab:rw" \
    --workdir /home/myx/RoboLab \
    "$image" "$@"
