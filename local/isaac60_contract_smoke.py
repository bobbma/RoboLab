"""Check the Torch/WXYZ and RGB contracts on a real RoboLab scene."""

import math

import cv2  # noqa: F401 -- load before Isaac Lab
from isaaclab.app import AppLauncher

launcher = AppLauncher(headless=True, enable_cameras=True, device="cuda:0", multi_gpu=False)
app = launcher.app
exit_code = 0
try:
    import torch

    from robolab.core.environments.factory import get_envs
    from robolab.core.environments.runtime import create_env
    from robolab.registrations.droid.auto_env_registrations_jointpos import auto_register_droid_envs

    auto_register_droid_envs(task_dirs=["benchmark"], task=["BananaInBowlTask"])
    names = get_envs(task=["BananaInBowlTask"])
    assert names, "BananaInBowlTask was not registered"
    env, cfg = create_env(names[0], num_envs=1, device="cuda:0")
    try:
        env.reset()
        robot = env.scene["robot"]
        for name in ("root_pos_w", "root_quat_w", "joint_pos"):
            assert isinstance(getattr(robot.data, name), torch.Tensor), name

        initial_pose = robot.data.root_state_w[:, :7].clone()
        pose = initial_pose.clone()
        pose[:, 3:] = torch.tensor([math.sqrt(0.5), 0, 0, math.sqrt(0.5)], device=env.device)
        robot.write_root_pose_to_sim(pose)
        robot.update(env.physics_dt)
        raw_pose = robot.root_physx_view.get_root_transforms().clone()
        expected_xyzw = pose[:, [4, 5, 6, 3]]
        assert torch.allclose(raw_pose[:, 3:], expected_xyzw, atol=1e-5), raw_pose
        assert torch.allclose(robot.data.root_quat_w, pose[:, 3:], atol=1e-5)
        robot.write_root_pose_to_sim(initial_pose)
        env.reset()

        actions = torch.zeros((env.num_envs, env.action_manager.total_action_dim), device=env.device)
        for _ in range(5):
            env.step(actions)

        camera_count = 0
        for name, sensor in env.scene.sensors.items():
            output = getattr(sensor.data, "output", {})
            if "rgb" not in output:
                continue
            pixels = output["rgb"]
            assert isinstance(pixels, torch.Tensor), name
            assert pixels.dtype == torch.uint8 and pixels.ndim == 4, (name, pixels.shape, pixels.dtype)
            assert pixels[..., :3].float().std() > 0, f"Constant RGB image: {name}"
            print(f"CAMERA_CONTRACT_PASSED {name} {tuple(pixels.shape)}", flush=True)
            camera_count += 1
        assert camera_count > 0, "No RGB camera was checked"
        print("ISAAC60_CONTRACT_PASSED torch=True quaternion=WXYZ raw_physx=XYZW", flush=True)
    finally:
        env.close()
except Exception:
    import traceback

    traceback.print_exc()
    exit_code = 1
    raise
finally:
    app.close(wait_for_replicator=False, exit_code=exit_code)
