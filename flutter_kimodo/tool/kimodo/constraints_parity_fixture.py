# Writes test/fixtures/constraints_parity.json: the conditioning tensors
# NVIDIA Kimodo's Python reference builds for a set of constraints on the
# SOMA30 skeleton, so KimodoConstraints.encode is checked bit for bit against
# it (test/kimodo_constraints_test.dart).
#
#   KIMODO_UPSTREAM_DIR=/path/to/nv-tlabs/kimodo python tool/kimodo/constraints_parity_fixture.py
#
# Needs torch, numpy, einops and scipy; kimodo's package __init__ (text
# encoders, hydra) is bypassed, only its skeleton, geometry, constraint and
# motion representation modules are imported. The poses are random local
# rotations through the reference's own forward kinematics; the fixture keeps
# them (local quaternions, root positions, global positions and rotations) so
# the Dart side can check its forward kinematics too.
import json
import os
import sys
import types

import torch

UPSTREAM = os.environ.get("KIMODO_UPSTREAM_DIR")
if not UPSTREAM:
    sys.exit("set KIMODO_UPSTREAM_DIR to an nv-tlabs/kimodo checkout")
pkg = types.ModuleType("kimodo")
pkg.__path__ = [os.path.join(UPSTREAM, "kimodo")]
sys.modules["kimodo"] = pkg

from kimodo.constraints import (  # noqa: E402
    EndEffectorConstraintSet,
    FullBodyConstraintSet,
    LeftFootConstraintSet,
    LeftHandConstraintSet,
    RightFootConstraintSet,
    RightHandConstraintSet,
    Root2DConstraintSet,
)
from kimodo.geometry import axis_angle_to_matrix, matrix_to_quaternion  # noqa: E402
from kimodo.motion_rep.reps.kimodo_motionrep import KimodoMotionRep  # noqa: E402
from kimodo.skeleton import SOMASkeleton30  # noqa: E402

LENGTH = 40
torch.manual_seed(7)
torch.set_default_dtype(torch.float64)
skeleton = SOMASkeleton30()
rep = KimodoMotionRep(skeleton, fps=30)
J = skeleton.nbjoints

# A walking-ish random pose per frame: small local rotations, the root moving
# forward and turning.
axis_angles = (torch.rand(LENGTH, J, 3) - 0.5) * 0.6
axis_angles[:, 0] = torch.tensor([0.0, 1.0, 0.0]) * torch.linspace(0.0, 1.2, LENGTH)[:, None]
local = axis_angle_to_matrix(axis_angles)
roots = torch.stack(
    [torch.linspace(0.0, 0.8, LENGTH), 0.92 + 0.03 * torch.sin(torch.arange(LENGTH) * 0.4), torch.linspace(0.0, 2.4, LENGTH)],
    dim=-1,
)
global_rots, positions, _ = skeleton.fk(local, roots)


def frames(*f):
    return torch.tensor(list(f))


def ee(cls, fr, smooth=None, **kw):
    fr = frames(*fr)
    return cls(skeleton, fr, positions[fr], global_rots[fr], smooth, **kw)


cases = {
    "root2d_with_heading": [
        Root2DConstraintSet(
            skeleton,
            frames(0, 12, 39),
            torch.tensor([[0.0, 0.0], [0.4, 1.1], [0.9, 2.7]]),
            global_root_heading=torch.tensor([[1.0, 0.0], [0.8, 0.6], [0.0, 1.0]]),
        )
    ],
    "root2d_dense": [
        Root2DConstraintSet(skeleton, torch.arange(LENGTH), positions[:, 0][:, [0, 2]].clone()),
    ],
    "left_hand": [ee(LeftHandConstraintSet, (10, 25))],
    "right_hand": [ee(RightHandConstraintSet, (5,))],
    "left_foot": [ee(LeftFootConstraintSet, (3, 30))],
    "right_foot": [ee(RightFootConstraintSet, (17,))],
    "end_effector_hips_and_feet": [ee(EndEffectorConstraintSet, (8,), joint_names=["Hips", "LeftFoot", "RightFoot"])],
    "full_body": [
        FullBodyConstraintSet(skeleton, frames(20), positions[[20]], global_rots[[20]]),
        FullBodyConstraintSet(
            skeleton, frames(33), positions[[33]], global_rots[[33]], torch.tensor([[0.5, 2.0]])
        ),
    ],
    # Overlapping frames: a dense path and an end-effector at the same frame.
    "path_and_left_hand": [
        Root2DConstraintSet(skeleton, torch.arange(0, 30), positions[:30, 0][:, [0, 2]] + 0.05),
        ee(LeftHandConstraintSet, (15,)),
        FullBodyConstraintSet(skeleton, frames(28), positions[[28]], global_rots[[28]]),
    ],
}


def describe(constraint):
    out = {"type": type(constraint).__name__, "frames": constraint.frame_indices.tolist()}
    if isinstance(constraint, Root2DConstraintSet):
        out["smooth_root_2d"] = constraint.smooth_root_2d.tolist()
        if constraint.global_root_heading is not None:
            out["global_root_heading"] = constraint.global_root_heading.tolist()
        return out
    out["smooth_root_2d"] = constraint.smooth_root_2d.tolist()
    if isinstance(constraint, EndEffectorConstraintSet):
        out["joint_names"] = list(constraint.joint_names)
    return out


result = {
    "length": LENGTH,
    "skeleton": {"names": list(skeleton.bone_order_names), "hips": list(skeleton.hip_joint_idx)},
    "pose": {
        "local_xyzw": matrix_to_quaternion(local)[..., [1, 2, 3, 0]].tolist(),
        "roots": roots.tolist(),
        "positions": positions.tolist(),
        "global_rotations": global_rots.tolist(),
    },
    "cases": {},
}
for name, constraints in cases.items():
    observed, mask = rep.create_conditions_from_constraints(constraints, LENGTH, to_normalize=False, device="cpu")
    flat_mask = mask.reshape(-1)
    flat_obs = observed.reshape(-1)
    nz = torch.nonzero(flat_mask).reshape(-1)
    assert (flat_obs[~flat_mask] == 0).all()
    result["cases"][name] = {
        "constraints": [describe(c) for c in constraints],
        "masked": [[int(i), float(flat_obs[i])] for i in nz],
    }

out = os.path.join(os.path.dirname(__file__), "..", "..", "test", "fixtures", "constraints_parity.json")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    json.dump(result, f, separators=(",", ":"))
    f.write("\n")
print(f"wrote {os.path.normpath(out)}: {sum(len(c['masked']) for c in result['cases'].values())} masked values")
