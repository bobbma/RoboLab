# RTX crash diagnosis and completed migration

Status: isolated upgrade authorized and implemented. Isaac Sim 6.0 renders
successfully on this host; the real BananaInBowl scene passes camera and
Torch/WXYZ pose contracts. Both default tasks completed successfully in a
direct container evaluation and through the original launcher, with exit 0
and verified video/HDF5 artifacts. See README.md for the logs and results.

The derived `robolab:isaac60` image uses Isaac Lab v2.3.2 at commit
`37ddf626871758333d6ed89cf64ad702aef127d0`, plus `isaaclab-sim60.patch`.
This is a locally maintained compatibility combination, not an official
Isaac Lab release supporting Sim 6. It retains RoboLab Torch tensors and
WXYZ quaternions instead of migrating to Lab 3 ProxyArray/XYZW conventions.

The patch adapts Kit experiences, rendering presets, the physics tensor API
namespace, removed schema lookups used by rigid material binding, camera
scalar types, and headless viewport handling. Headless rendering explicitly
attaches the RTX Hydra engine; without that step the new engine returns
empty camera buffers. Buffer sizes are checked before the tiled-camera Warp
kernel to prevent illegal CUDA accesses.

Official Sim 6 adaptation reference: Isaac Lab commit
`4614feb199da3772ae5e5a81d054705390ebc346`. The Hydra attachment follows the
renderer initialization in Isaac Lab 3.0.0-beta2.

Validation is scoped to this project's rigid-body DROID tasks. Soft-body
simulation has not been migrated. Rendering and physics numerics may change;
benchmark equivalence to Sim 5.1 is not established.

## Evidence collected on 2026-09-27

- Host: RTX 4090, NVIDIA 615.71.09. `cuInit` succeeds and reports driver API
  13.4. PyTorch 2.7.0+cu128 successfully computes and verifies CUDA results.
- The official Isaac Sim 5.1 container reproduces the crash with one GPU,
  fresh caches, no network, and no RoboLab or host Python dependencies.
  Detailed log: `/mnt/38_store/myx/robolab/logs/rtx-container-verbose.log`.
- GDB catches the original Pi0.5 entry point at scenedb offset `0x1e9c0f`:
  `lock add %r13d,0x3380(%rbp)`, with `rbp=0`. This is a native null-pointer
  access, not a Python exception or a CUDA version rejection.
  Log: `/mnt/38_store/myx/robolab/logs/pi05-rtx-gdb.log`.
- Upstream IsaacSim issue #619 reports the identical three scenedb offsets
  (`+0x123ef`, `+0x12766`, `+0x14a14`). NVIDIA attributes that report to
  compatibility between Kit 107.3.3 and the newer driver.
- In issue #677, the reporter and a maintainer confirm Isaac Sim 6.0.0's
  updated RTX stack fixes that crash on their machine without changing its
  driver. Subsequent local rendering and full evaluation also passed on
  this host without changing its driver.

## Authorized migration and acceptance criteria

1. Pull the official 6.0.0 image through `unix:///run/docker-robolab.sock`.
   Registry metadata checked on 2026-09-27:
   - Index digest: `sha256:68735a60b6c15c85e0dd0098570c6d2cc79e928f2d068ce2790aa43284ac165d`.
   - Linux amd64 digest: `sha256:a9d06fb72cc2b39b2bf1cacc002e9f7cd1a5bbe3c3cfbbcf2e6de3a1d726d101`.
   - Compressed layers: approximately 9.97 GiB.
   - Existing daemon storage: `/data/myx/robolab-docker`.
2. Run `local/isaac51_rtx_smoke.py` in the new image using the same clean,
   single-GPU setup as the 5.1 reference. The script name reflects its origin;
   the acceptance criterion is an actual nonblack 256x256 RTX image and a
   successful process exit, not merely the compatibility checker.
3. Only if rendering passes, build a separate RoboLab environment with an
   Isaac Lab source adapted for 6.0, and adapt any changed APIs needed
   by this project. Do not replace the existing 5.1 environment in place.
4. Verify task loading, camera output, Pi0.5 server communication, and a
   complete evaluation episode for each default task: BananaInBowlTask and
   RubiksCubeAndBananaTask. Use separate validation output directories.
5. Switch `local/run_pi05_eval.sh` to the verified environment, retain its
   argument forwarding and logging, and document how to select the old
   environment. Do not claim completion until that entry point works.

The migration does not include host driver changes, reboots, interruption
of other GPU workloads, Git commits, or pushes. The clean 6.0 renderer and
the migrated evaluation both passed.

## Sources

- https://docs.nvidia.com/deploy/cuda-compatibility/why-cuda-compatibility.html
- https://github.com/isaac-sim/IsaacSim/issues/619
- https://github.com/isaac-sim/IsaacSim/issues/677
- https://docs.omniverse.nvidia.com/dev-guide/latest/common/technical-requirements.html
- https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/requirements.html
