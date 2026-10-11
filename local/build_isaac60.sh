#!/usr/bin/env bash
set -euo pipefail

data_root="/mnt/38_store/myx/robolab"
build_dir="$(mktemp -d "$data_root/isaac60-build.XXXXXX")"
lab_commit="37ddf626871758333d6ed89cf64ad702aef127d0"
printf 'Building isolated RoboLab environment in %s\n' "$build_dir"
curl --fail --location \
    "https://api.github.com/repos/isaac-sim/IsaacLab/tarball/$lab_commit" \
    --output "$build_dir/isaaclab.tar.gz"
mkdir -p "$build_dir/IsaacLab"
tar -xzf "$build_dir/isaaclab.tar.gz" --strip-components=1 -C "$build_dir/IsaacLab"
patch --batch -p1 -d "$build_dir/IsaacLab" \
    < "/home/myx/RoboLab/local/isaaclab-sim60.patch"
cp -a "/home/myx/openpi/packages/openpi-client" "$build_dir/openpi-client"
docker --host "unix:///run/docker-robolab.sock" build --network=host \
    -f "/home/myx/RoboLab/local/Dockerfile.isaac60" \
    -t "robolab:isaac60" "$build_dir"
