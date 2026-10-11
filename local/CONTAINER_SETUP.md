# Isaac Sim container deployment

## Current Sim 6 environment (2026-09-27)

The isolated `robolab:isaac60` image renders successfully on this host with
its unchanged NVIDIA 615.71.09 driver. The original Sim 5.1 image and native
environment remain available, but their RTX initialization still crashes.
See [RTX_FIX_PLAN.md](RTX_FIX_PLAN.md) for diagnosis and migration scope.

Build the Sim 6 environment:

```bash
bash "/home/myx/RoboLab/local/build_isaac60.sh"
```

Run a command in it:

```bash
bash "/home/myx/RoboLab/local/run_isaac60_container.sh" \
  "/home/myx/RoboLab/local/isaac60_contract_smoke.py"
```

The base image is pinned by its multi-platform digest:
`nvcr.io/nvidia/isaac-sim:6.0.0@sha256:68735a60b6c15c85e0dd0098570c6d2cc79e928f2d068ce2790aa43284ac165d`.
The amd64 manifest is
`sha256:a9d06fb72cc2b39b2bf1cacc002e9f7cd1a5bbe3c3cfbbcf2e6de3a1d726d101`.

The Dockerfile preserves the image Python 3.12, Torch 2.11.0+cu128, NumPy
2.3.1 and Warp 1.13 stack. Isaac Lab v2.3.2 source is pinned by commit and
patched locally for Sim 6; the local OpenPI client is installed without
resolving its old NumPy constraint. This is a custom rigid-body evaluation
environment, not a generally supported Lab 2 / Sim 6 distribution. Full
soft-body support and numerical equivalence to Sim 5.1 are not claimed.

Base image metadata reports some missing pip dependencies even though GPU
libraries are bundled by Isaac Sim. Do not blindly run a resolver that
replaces the bundled CUDA/Torch stack. Additional pip packages and the local
OpenPI checkout are not fully locked; package versions from the validation
image are recorded in `logs/isaac60-packages.txt` under the data root. The
build script fixes source inputs but does not promise byte-identical images.

`PI05_EVAL_GPU` selects a physical GPU (default 1) through Docker, isolating
both CUDA and Vulkan. Inside the container use `cuda:0`. Do not additionally
set `CUDA_VISIBLE_DEVICES` inside it. `ROBO_CONTAINER_IMAGE` can select a
previously built image ID or tag. The project is mounted read-only and the
data root read-write. Persistent Sim 6 caches are under `docker/isaac60` in
the data root, separate from Sim 5.1 caches.

## Installed services and storage

The user approved the local image-storage exception on 2026-09-27.

- Docker service: docker-robolab.service (enabled).
- Containerd service: containerd-robolab.service (enabled).
- Docker API: unix:///run/docker-robolab.sock.
- Dedicated containerd API: /run/containerd-robolab/containerd.sock.
- Image layers, writable layers, build cache and containerd metadata:
  /data/myx/robolab-docker on local ext4.
- Persistent application caches, assets, models, logs and output:
  /mnt/38_store/myx/robolab on NFS.
- Installed configuration: /etc/docker/robolab.json and
  /etc/docker/containerd-robolab.toml.
- Service units: /etc/systemd/system/docker-robolab.service and
  /etc/systemd/system/containerd-robolab.service.
- Source configuration copies are in this directory.

The dedicated Docker daemon uses overlay2 and a separate containerd namespace.
It disables bridge creation, iptables management, and IP-forwarding changes.
The shared Docker daemon was not restarted or reconfigured. The host NVIDIA
driver was not changed. The new services were registered with systemd.

Always specify the dedicated socket when managing RoboLab images. The shared
daemon stores images in /var/lib/docker on the nearly full root partition.
Bind mounts alone do not relocate image layers. Do not use NFS directly as
an overlay2 backing filesystem.

## Preserved Sim 5.1 image

Image: nvcr.io/nvidia/isaac-sim:5.1.0

Multi-platform digest:
sha256:f3563cb2ba0c18af0b2fb321360dcb73a917b899f879e3213623d6bee484fa54

Linux amd64 manifest:
sha256:93b0f99635ab126fb5b33298d513c11520f119f0ee60ff8414ccef67ea977829

Compressed layers total approximately 7.09 GiB. The official image contains
Ubuntu 24.04.2, torch 2.7.0+cu128, and torchvision 0.22.0+cu128.

## Reproduce the historical Sim 5.1 checks

Inspect the dedicated daemon:

    docker --host "unix:///run/docker-robolab.sock" info

Run the official compatibility checker:

    bash "/home/myx/RoboLab/local/check_isaac51_container.sh"

Run the clean RTX reference test:

    bash "/home/myx/RoboLab/local/check_isaac51_rtx.sh"

Both scripts default to physical GPU 1. Override with PI05_EVAL_GPU.
The RTX script uses the image's default UID/GID 1234:1234, fresh local
container caches, and a 180-second timeout. Temporary caches in this
reference test live in the disposable container layer on /data; stdout and
stderr are saved under the NFS logs directory. The test should produce
RTX_SMOKE_PASSED after rendering a 256x256 image, but currently crashes during
SimulationApp initialization before reaching that point. The python.sh
wrapper returns exit code 1 after reporting a segmentation fault.

For general standalone commands, run_isaac51_container.sh supplies persistent
NFS cache mounts. It runs as the invoking user's UID/GID with supplementary
container group 1234 to read the official installation. It also mounts the
Python launcher's portable Kit cache/data/log directories, which differ from
the paths used by the official application launch scripts. The project is
mounted read-only; the data root is mounted read-write. The launcher filters
GPU devices through Docker without setting CUDA_VISIBLE_DEVICES.

All launchers use the dedicated daemon, never implicitly pull a missing
image, accept the Isaac Sim EULA, and do not opt into optional telemetry.

## Evidence

Logs under /mnt/38_store/myx/robolab/logs:

- isaac51-docker-pull.log: official image downloaded successfully.
- isaac51-container-check-console.log: System checking result: PASSED;
  driver 615.71.09 reported as supported by the checker.
- isaac51-container-rtx-smoke.log: initial custom-user run encountered cache
  permissions; superseded by subsequent tests.
- isaac51-container-rtx-smoke-v2.log: portable cache mounts added; RTX crash.
- isaac51-container-rtx-official-user.log: clean reference run with default
  image user and fresh local caches; same librtx.scenedb.plugin.so crash.

An ancillary read-only check of the pre-existing shared GPU 0 container
returned 'Failed to initialize NVML: Unknown Error' before this session's
systemd daemon-reload. Its container remained running. This observation
was not investigated or repaired as part of the RoboLab container setup.

## Historical Sim 5.1 diagnosis

The compatibility checker passed, but real RTX startup failed in both the
native environment and the clean official 5.1 container. GDB and upstream
IsaacSim issues #619 and #677 identify the old Kit RTX/new driver
compatibility path. The working route on this host is the isolated Sim 6
engine above; no host driver downgrade or reboot was performed.

## Sources

- https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/install_container.html
- https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/requirements.html
- https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/arch-overview.html
