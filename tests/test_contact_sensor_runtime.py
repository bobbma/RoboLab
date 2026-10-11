# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""Contact filters must select actor roots and stay within each environment."""

import torch
from isaaclab.sensors import ContactSensorCfg

from robolab.core.environments import runtime
from robolab.core.environments.factory import get_envs
from robolab.core.environments.runtime import create_env
from robolab.core.sensors.contact_sensor_utils import get_contact_sensors
from robolab.registrations.droid.auto_env_registrations_jointpos import auto_register_droid_envs


def test_bagels_contact_filters_and_environment_isolation(monkeypatch):
    # plate_large contains same-named descendants: wildcard filtering in Sim 6
    # used to select three entries and fail before the first environment step.
    auto_register_droid_envs(task=["BagelsOnPlateTask"])
    name = get_envs(task=["BagelsOnPlateTask"])[0]
    parse_env_cfg = runtime.parse_env_cfg

    def with_net_contact_sensor(*args, **kwargs):
        cfg = parse_env_cfg(*args, **kwargs)
        cfg.scene.plate_net_contact = ContactSensorCfg(prim_path=cfg.scene.plate_large.prim_path)
        return cfg

    monkeypatch.setattr(runtime, "parse_env_cfg", with_net_contact_sensor)
    env, cfg = create_env(name, num_envs=2, device="cuda:0")
    try:
        env.reset()
        actions = torch.zeros((2, env.action_manager.total_action_dim), device=env.device)
        for _ in range(10):
            env.step(actions)

        sensors = get_contact_sensors(env.scene)
        for sensor in sensors.values():
            matrix = sensor.data.force_matrix_w
            if not sensor.cfg.filter_prim_paths_expr:
                assert matrix is None
                assert torch.isfinite(sensor.data.net_forces_w).all()
                continue
            assert matrix.shape == (2, 1, len(sensor.cfg.filter_prim_paths_expr), 3)
            assert torch.isfinite(matrix).all()

        # A supported plate must have nonzero force; merely returning zeros
        # instead of initializing contact reporting cannot satisfy this test.
        support = sensors["plate_large__table"].data.force_matrix_w
        assert torch.all(torch.linalg.vector_norm(support[:, 0, 0], dim=-1) > 0.1)
        net = sensors["plate_net_contact"].data.net_forces_w
        assert torch.all(torch.linalg.vector_norm(net[:, 0], dim=-1) > 0.1)

        # Lift only the second plate. Its contact must disappear while the
        # first environment continues reporting support from its own table.
        plate = env.scene["plate_large"]
        pose = plate.data.root_state_w[1:2, :7].clone()
        pose[:, 2] += 1.0
        env_ids = torch.tensor([1], device=env.device)
        plate.write_root_pose_to_sim(pose, env_ids=env_ids)
        plate.write_root_velocity_to_sim(torch.zeros((1, 6), device=env.device), env_ids=env_ids)
        for _ in range(3):
            env.step(actions)
        support = sensors["plate_large__table"].data.force_matrix_w
        assert torch.linalg.vector_norm(support[0, 0, 0]) > 0.1
        torch.testing.assert_close(support[1], torch.zeros_like(support[1]), atol=1e-5, rtol=0)

        # Batch columns retain the configured object order used by WorldState.
        objects = [obj for obj in cfg.contact_object_list if obj != "table"]
        batch = sensors["gripper__all_objs"].data.force_matrix_w
        expected_paths = [
            [f"/World/envs/env_{env_id}/scene/{obj}" for obj in objects]
            for env_id in range(2)
        ]
        assert sensors["gripper__all_objs"].contact_physx_view.filter_paths == expected_paths
        for column, obj in enumerate(objects):
            pair = sensors[f"gripper__{obj}"].data.force_matrix_w
            torch.testing.assert_close(batch[:, :, column], pair[:, :, 0])
    finally:
        env.close()
