[Türkçe](../tr/flutter_jolt.md)

# flutter_jolt

`flutter_jolt` binds [Jolt Physics](https://github.com/jrouwe/JoltPhysics) (MIT) through Dart FFI: a native physics world with rigid bodies, shapes, constraints, contacts and ray casts. The Lumina engine uses it as its physics backend on native desktop (see the engine's `docs/en/lumina/physics.md`); the pure-Dart solver stays for the web and as the fallback. Units are Jolt's: metres, kilograms, seconds, radians; the world has no preferred up axis. File paths are relative to the `flutter_jolt/` package directory.

**On this page:**

- [Native build](#native-build)
- [Native C bridge](#native-c-bridge)
- [Dart API](#dart-api)
- [Collision filtering](#collision-filtering)
- [Limits](#limits)

## Native build

Jolt is fetched, not vendored. `tool/jolt_version.txt` pins the release (tag `v5.6.0` and its commit); `tool/build_jolt.bat` (Windows, Visual Studio 2022, CMake and Ninja from Visual Studio) and `tool/build_jolt.sh` (Linux, clang with the bundled libc++ of the lumina repo, `-fPIC`) clone it into the gitignored `third_party/jolt/src`, refuse any other commit, build the `Jolt` static library and write a self-contained build folder:

| Path | Content |
|---|---|
| `third_party/jolt/include/Jolt/...` | the headers |
| `third_party/jolt/lib/Jolt.lib` / `libJolt.a` | the static library (`/MT` static CRT on Windows) |
| `third_party/jolt/jolt_defines.txt` | the `JPH_*` defines the library was compiled with (read from CMake's `compile_commands.json` by `tool/write_jolt_defines.dart`) |
| `third_party/jolt/VERSION` | tag and commit |

Build options: single precision, no cross-platform determinism (the same binary is deterministic, which replays and tests need), 16-bit object layers, C++ exceptions and RTTI on, no debug renderer, profiler, object stream or GPU compute, the x86-64 SSE4.2 baseline (no AVX, so games run on older CPUs), no link-time optimisation. `--clean` deletes the folder first.

`hook/build.dart` compiles `src/jolt_c.cpp` into the `flutter_jolt` dynamic library (code asset `package:flutter_jolt/src/jolt_native.dart`) with exactly the defines in `jolt_defines.txt` and links the static library. The build folder comes from (`lib/src/hook/jolt_dir.dart`):

1. `LUMINA_JOLT_DIR` (only when the hook runs directly; the hooks runner forwards no `LUMINA_*` variables);
2. the `jolt_dir` user-define in the app's workspace root pubspec (`hooks: user_defines: flutter_jolt: jolt_dir: <path>`), when it holds the library;
3. `third_party/jolt` in the package.

When none holds a library the hook prints a note and emits **no code asset**: the package still compiles, `JoltPhysics.isAvailable` is false and callers fall back. On Linux the hook requires the bundled libc++ (`libcxx_dir`).

## Native C bridge

`src/jolt_c.h` declares the C API (`jolt_*`, exported with `JOLT_C_EXPORT`); `tool/ffigen.dart` generates the `@Native` bindings in `lib/src/jolt_bindings.g.dart` (needs libclang; `LIBCLANG_PATH` names its folder). Groups:

- **World**: `jolt_world_create` (body / pair / contact capacities, worker threads), `jolt_world_destroy`, gravity, solver settings (velocity / position steps, Baumgarte, speculative contact distance, penetration slop, sleep time and threshold), `jolt_world_step` (returns Jolt's update error bits), broad-phase optimisation, body counts.
- **Shapes** (reference counted, released with `jolt_shape_release`): box, sphere, capsule (Y axis), cylinder (Y axis), convex hull, height field (row-major samples, `jolt_heightfield_no_collision()` holes, about 1 mm precision), scaled, rotated/translated, centre-of-mass offset, static compound; `jolt_shape_set_user_data` names a leaf for contacts and ray hits.
- **Bodies**: `jolt_body_create` from `JoltBodySettings` (motion type, pose, velocities, user data, friction, restitution, damping, gravity factor, mass and inertia override, allowed DOFs, continuous collision, sensor), destroy, owner and profiles (filtering), material with combine modes, shape, mass properties, motion type, damping, gravity factor, CCD, transform, velocity, kinematic moves, forces, torques, impulses, activation; `jolt_world_get_body_states` reads many bodies at once (`JOLT_BODY_STATE_STRIDE` doubles: centre of mass, rotation, linear and angular velocity, active, shape origin).
- **Contacts**: `jolt_world_get_contacts` returns the added and persisted contacts of the last step, sorted by body: the two bodies and leaf user data, the mean point, the normal (from body A to body B), Jolt's estimated normal impulse (`EstimateCollisionResponse`), penetration and point count.
- **Queries**: `jolt_world_cast_ray`.
- **Constraints**: `jolt_constraint_swing_twist` (twist about the frame's X axis, plane axis Y, normal and plane half cones, twist range, friction torque) and `jolt_constraint_hinge` (limits within `-π ≤ min ≤ 0 ≤ max ≤ π`), frames relative to each body's centre of mass; limits, friction torque, a velocity motor (`jolt_constraint_set_velocity_motor`), a position motor (`jolt_constraint_set_position_motor`: a spring of a frequency and damping ratio toward a target rotation; a hinge reads the angle about X), solver iterations for the constraint's island (`jolt_constraint_set_solver_steps`), enable, impulses.

## Dart API

`package:flutter_jolt/flutter_jolt.dart`:

- `JoltPhysics`: `isAvailable` (probes the library once, never throws), `version` (`5.6.0`), `ensureAvailable()`.
- `JoltWorld({maxBodies, maxBodyPairs, maxContactConstraints, workerThreads, gravity})`: `gravity`, `solverSettings` (`JoltSolverSettings`), `step(dt, collisionSteps:)`, `createBody(shape, JoltBodySettings)` → body id, `destroyBody` (removes its constraints first), `setBodyOwner`, `setBodyProfiles`, `setBodyMaterial`, `setBodyShape`, `setBodyMassProperties`, `setBodyMotionType`, `setBodyDamping`, `setBodyGravityFactor`, `setBodyContinuousCollision`, `setBodyTransform`, `setBodyVelocity`, `moveKinematic`, `addForce` / `addTorque` / `addImpulse` / `addAngularImpulse`, `activateBody` / `deactivateBody` / `isBodyActive`, `bodyMass`, `bodyState` / `readBodyStates` + `stateAt` / `stateBuffer`, `contacts()`, `castRay`, `setProfileMatrix`, `ignorePair`, `addSwingTwist` / `addHinge` / `removeConstraint` (a `JoltConstraint` has `setLimits`, `maxFrictionTorque`, `setVelocityMotor`, `setPositionMotor`, `setSolverSteps`, `enabled`, `lambdas`), `dispose()`.
- `JoltShape`: `box`, `sphere`, `capsule`, `cylinder`, `convexHull`, `heightField`, `scaled`, `rotatedTranslated`, `offsetCenterOfMass`, `compound`; `userData`, `centerOfMass`, `volume`, `localBounds`, `release()` (a `NativeFinalizer` frees a forgotten shape).
- `JoltBodySettings`, `JoltBodyState`, `JoltContact`, `JoltRayHit`, `JoltMotionType`, `JoltDofs`, `JoltCombineMode`, `JoltConstraint` with `JoltSwingTwistSettings` / `JoltHingeSettings`.

```dart
if (JoltPhysics.isAvailable) {
  final world = JoltWorld(workerThreads: 2);
  final ground = JoltShape.box(Vector3(50, 0.5, 50));
  world.createBody(ground, JoltBodySettings(motionType: JoltMotionType.static_, position: Vector3(0, -0.5, 0)));
  ground.release();
  final box = JoltShape.box(Vector3.all(0.5));
  final id = world.createBody(box, JoltBodySettings(position: Vector3(0, 2.5, 0), mass: 10));
  box.release();
  for (var i = 0; i < 120; i++) {
    world.step(1 / 120);
  }
  print(world.bodyState(id).centerOfMass); // resting on the ground
  world.dispose();
}
```

## Collision filtering

A `SimShapeFilter` decides before the narrow phase, so filtered pairs cost nothing:

- **Profiles**: every leaf of a body has a profile index (`setBodyProfiles`, indexed by the leaf's user data); two leaves touch only when `setProfileMatrix` says their profiles block each other. An index outside the matrix blocks everything. Lumina maps its collision channels and responses to profiles.
- **Owners**: bodies with the same non-zero owner (`setBodyOwner`) collide only when both are dynamic or kinematic and both allow it (`collidesWithOwner`), and never with a static body of that owner.
- **Ignored pairs**: `ignorePair(a, b)` (Jolt keeps colliding constrained bodies; ignore the pair of a joint).

Materials: friction combines static friction while the surfaces barely slide (under 1 cm/s) and dynamic friction otherwise; the larger combine mode of the two bodies wins (average < min < multiply < max).

## Limits

- Contact impulses are Jolt's estimate for the step, not the solved impulse.
- Height fields keep about 8 bits per sample per block (a few millimetres on metre-scale terrain) and are static only.
- Built and tested on Windows x64; the Linux script mirrors it. Android, macOS, iOS and the web (WebAssembly) are not built yet.

---

[Previous: flutter_riglogic](flutter_riglogic.md) · [Next: flutter_kimodo](flutter_kimodo.md)
