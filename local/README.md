# Local Pi0.5 evaluation

`run_pi05_eval.sh` now defaults to the isolated Isaac Sim 6.0 container
`robolab:isaac60`. This fixes the native Sim 5.1 RTX SceneDB crash on the
current NVIDIA 615.71.09 host driver. The old environment is preserved.
See [CONTAINER_SETUP.md](CONTAINER_SETUP.md) for build/storage details and
[RTX_FIX_PLAN.md](RTX_FIX_PLAN.md) for the diagnosis and compatibility scope.

RoboLab is installed in `/home/myx/RoboLab`; OpenPI is in `/home/myx/openpi`.
Assets, model checkpoints, logs and output live under
`/mnt/38_store/myx/robolab`.

Start the policy server in one terminal (do not start another if port 8000
already has the Pi0.5 server):

```bash
CUDA_DEVICE_ORDER=PCI_BUS_ID bash "/home/myx/RoboLab/local/run_pi05_server.sh"
```

After it reports `server listening on 0.0.0.0:8000`, run:

```bash
bash "/home/myx/RoboLab/local/run_pi05_eval.sh"
```

The defaults are physical GPU 2 for the policy server and GPU 1 for the
simulator. Override with `PI05_SERVER_GPU` and `PI05_EVAL_GPU`, respectively.
Docker isolates the simulator GPU for both CUDA and Vulkan; its internal
CUDA device is `cuda:0`. The launcher forwards additional evaluation
arguments and saves complete output to a timestamped file under `logs`.
Results go through the `output` symlink to the data root.

Example with a separate output directory:

```bash
bash "/home/myx/RoboLab/local/run_pi05_eval.sh" \
  --num-envs 1 --num-runs 1 --output-folder-name my-pi05-run
```

The default tasks are `BananaInBowlTask` and `RubiksCubeAndBananaTask`.
A completed output directory is resumed/skipped by RoboLab, so use a new
name when a fresh evaluation is intended.

## Build and rollback

```bash
bash "/home/myx/RoboLab/local/build_isaac60.sh"
```

The build uses only the dedicated Docker socket
`unix:///run/docker-robolab.sock` and preserves the old native environment.
`ROBO_CONTAINER_IMAGE` can select an existing alternate image tag or ID.

To explicitly select the preserved native 5.1 environment:

```bash
PI05_EVAL_BACKEND=native51 bash "/home/myx/RoboLab/local/run_pi05_eval.sh"
```

This rollback selects the old software; it does not fix its known RTX crash
with the current driver. No driver change or reboot is part of this setup.
The historical CUDA-index backport remains in `isaaclab-cuda-index.patch`;
it did not fix the underlying old RTX engine crash.

## Validation and limits

### Sim 6 contact-filter compatibility (2026-09-28)

The local Isaac Lab patch resolves contact filters to exact USD actor paths
before creating the PhysX contact view. Sim 6 wildcard matching could include
same-named descendants of `plate_large`, reject the filter cardinality, then
raise `NoneType.filter_count` while starting `BagelsOnPlateTask`.

Each sensor row uses its own environment's actor, and filter columns retain
their configured order. Missing or ambiguous matches now fail with the
sensor path and filter expression. Empty filters keep net-force-only behavior.
The fix is included in `isaaclab-sim60.patch` for subsequent image rebuilds.

The default image is now
`sha256:bb9d334e421d5604e78d1eb6d4aac258dd0822844229acd484a4c0608bc3ddfb`.
The previous image is retained as `robolab:isaac60-before-contact-fix-20260928`.
Contact and frame regression tests passed 10/10, including two environments,
lifting only one plate, exact batch filter paths, and an unfiltered net-force
sensor (`logs/bagels-contact-tests-v2.log`).

The full Bagels evaluation ran all 900 steps (60 simulated seconds), exported
HDF5 and both videos, and exited 0. Pi0.5 did not complete the placement goal
in that episode (`success=false`, score 0); initialization/runtime operation
and policy task success are separate outcomes. Results are in
`output/bagels-contact-fix-validation`, with log
`logs/pi05-eval-20260928T095208Z-3298128.log`. Both 899-frame videos decode,
and recorded actions/poses contain 900 finite samples. This full run used
the filtered-contact fix in candidate `a6417f132e7d`; the final image adds
the empty-filter guard, covered by the subsequent 10/10 regression run.

Run the task using the normal entry point:

```bash
bash "/home/myx/RoboLab/local/run_pi05_eval.sh" --task BagelsOnPlateTask
```

Already running containers keep their original image; the updated image is
used when starting a new container. The fix does not change task assets,
contact thresholds, or success conditions.

### Initial migration validation (2026-09-27)

The real-scene contract check passed for Torch tensors, WXYZ quaternion
read/write (with XYZW in raw PhysX), and all three RGB cameras at their
configured resolutions. A complete policy evaluation produced 2/2 successful
episodes (271 and 456 steps) in `output/isaac60-full-validation` with videos,
HDF5 trajectories and `episode_results.jsonl`. Its log is
`logs/isaac60-full-validation-v2.log` under the data root.

The original command was then run without additional arguments using the
rebuilt image `sha256:3ef28586084f41db316ee8384d5636ac3a64ab847dca8d43836d1fd5629a4142`.
It exited 0 with another 2/2 successful episodes (135 and 772 steps).
Output: `output/2026-09-27_10-58-19_pi05`; full log:
`logs/pi05-eval-20260927T105738Z-1029788.log`. Both runs passed artifact checks:
recorded steps match result rows, pose/action values are finite, WXYZ root
quaternions are preserved, and all video first/last frames decode.

Project validation passed all 130 tests in `test_isaaclab.py`,
`test_tasks_valid.py`, `test_registered_envs.py`, and `test_frame_contract.py`,
including a real recorded episode. Log: `logs/isaac60-project-tests.log`;
machine-readable result: `output/isaac60-project-tests/pytest-result.json`.
The patched Lab source also passed clean patch application and Python syntax
checks; the build script was exercised from a fresh source extraction.

The environment uses locally patched Isaac Lab v2.3.2 with Sim 6.0 to retain
RoboLab semantics. Validation covers the rigid-body evaluation route, not
soft-body simulation or all Isaac Lab features. Two successful episodes
verify operation; they do not establish benchmark statistics or numerical
and visual equivalence to Sim 5.1. Non-fatal headless display, OmniHub bypass
and material warnings remain in the full logs.
