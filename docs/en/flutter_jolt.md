[Türkçe](../tr/flutter_jolt.md)

# flutter_jolt

`flutter_jolt` binds [Jolt Physics](https://github.com/jrouwe/JoltPhysics) (MIT) through Dart FFI: a native physics world with rigid bodies, shapes, constraints, contacts and ray casts. The Lumina engine uses it as its physics backend on native desktop (see the engine's `docs/en/lumina/physics.md`); on the web it runs as a WebAssembly module (see Web below); the pure-Dart solver stays as the fallback. Units are Jolt's: metres, kilograms, seconds, radians; the world has no preferred up axis. File paths are relative to the `flutter_jolt/` package directory.

**On this page:**

- [Native build](#native-build)
- [Native C bridge](#native-c-bridge)
- [Dart API](#dart-api)
- [Collision filtering](#collision-filtering)
- [Web (WebAssembly)](#web-webassembly)
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

`hook/build.dart` compiles `src/jolt_c.cpp` into the `flutter_jolt` dynamic library (code asset `package:flutter_jolt/src/jolt_native.dart`) with exactly the defines in `jolt_defines.txt` (on x64 with clang/gcc also the instruction-set flags they imply, `joltIsaFlags`: `-msse4.1`, `-msse4.2 -mpopcnt`, …, since Jolt's headers use those intrinsics inline) and links the static library. The build folder comes from (`lib/src/hook/jolt_dir.dart`):

1. `LUMINA_JOLT_DIR` (only when the hook runs directly; the hooks runner forwards no `LUMINA_*` variables);
2. the `jolt_dir` user-define in the app's workspace root pubspec (`hooks: user_defines: flutter_jolt: jolt_dir: <path>`), when it holds the library;
3. `third_party/jolt` in the package.

When none holds a library the hook prints a note and emits **no code asset**: the package still compiles, `JoltPhysics.isAvailable` is false and callers fall back. On Linux the hook requires the bundled libc++ (`libcxx_dir`). On Linux and Android the Jolt and libc++ archives are linked after the wrapper's object (as `libraries`, so GNU ld takes what the wrapper needs from them) with `-z defs`, so a missing symbol fails the build instead of the library failing to load.

## Native C bridge

`src/jolt_c.h` declares the C API (`jolt_*`, exported with `JOLT_C_EXPORT`); `tool/ffigen.dart` generates the `@Native` bindings in `lib/src/jolt_bindings.g.dart` (needs libclang; `LIBCLANG_PATH` names its folder). Groups:

- **World**: `jolt_world_create` (body / pair / contact capacities, worker threads), `jolt_world_destroy`, gravity, solver settings (velocity / position steps, Baumgarte, speculative contact distance, penetration slop, sleep time and threshold), `jolt_world_step` (returns Jolt's update error bits; the step runs on the world's own stepping thread with a 16 MB stack while the caller waits, because Jolt's narrow phase can need more stack than a Dart mutator thread has), broad-phase optimisation, body counts.
- **Shapes** (reference counted, released with `jolt_shape_release`): box, sphere, capsule (Y axis), cylinder (Y axis), convex hull, height field (row-major samples, `jolt_heightfield_no_collision()` holes, about 1 mm precision), scaled, rotated/translated, centre-of-mass offset, static compound; `jolt_shape_set_user_data` names a leaf for contacts and ray hits.
- **Bodies**: `jolt_body_create` from `JoltBodySettings` (motion type, pose, velocities, user data, friction, restitution, damping, gravity factor, mass and inertia override, allowed DOFs, continuous collision, sensor), destroy, owner and profiles (filtering), material with combine modes, shape, mass properties, motion type, damping, gravity factor, CCD, transform, velocity, kinematic moves, forces, torques, impulses, activation; `jolt_world_get_body_states` reads many bodies at once (`JOLT_BODY_STATE_STRIDE` doubles: centre of mass, rotation, linear and angular velocity, active, shape origin).
- **Contacts**: `jolt_world_get_contacts` returns the added and persisted contacts of the last step, sorted by body: the two bodies and leaf user data, the mean point, the normal (from body A to body B), an estimated normal impulse (the impulse through the centres of mass that stops the bodies approaching at the contact, with restitution, from the velocities before the solver ran), penetration and point count.
- **Cloth (soft bodies)**: `jolt_cloth_settings_init`, `jolt_soft_body_create` (vertices, inverse masses with 0 pinning a vertex, triangles; edge, shear and bend compliances, dihedral or distance bending, long range attachments (tethers) to the pinned vertices, iterations, damping, friction, vertex radius), `jolt_soft_body_get_vertices` (world positions), `jolt_soft_body_set_vertex` (move or pin a vertex), `jolt_soft_body_set_inverse_mass` (pin where it is, or free), `jolt_soft_body_drive_vertices` (move pinned vertices to targets over the next step; a pin keeps that velocity until driven again), `jolt_soft_body_get_local_vertices` (positions and area-weighted normals in a frame of the caller's, e.g. a component's centimetres), `jolt_soft_body_apply_wind` (aerodynamic: each face is pushed along its normal by the part of the relative wind that hits it). Build a soft body near its vertices (`position` at their centre): vertices far from the body origin made cloth unstable, and so do near-rigid compliances on very light vertices (scale compliances with the inverse mass).
- **Skinned cloth** (garments): `jolt_skinned_cloth_create` with a `JoltClothSkin` (inverse bind matrices, four joints and weights per vertex, per-vertex max distance and backstop), `jolt_soft_body_skin` (joint matrices in the world each step, hard skin on the first), `jolt_body_set_cloth_collider` (a cloth ignores the other bodies of its owner, as set with `jolt_body_set_owner`, except its colliders). Dart: `createCloth(..., skin: JoltClothSkin(...))`, `skinCloth`, `setBodyClothCollider`.
- **Carrying a cloth** along a rigid motion: `jolt_soft_body_carry` (a world 4x4 delta and an amount 0..1: every free vertex moves that share of the way to where the motion takes it and its velocity turns as much; `include_pinned` also moves the pinned vertices, all the way, for a teleport). Dart: `carryCloth(body, delta, amount, includePinned:)`. Lumina uses it for a cloth's inertia scale and teleports.
- **Broad phase proxies** (scene queries): `jolt_world_add_box_proxy` / `jolt_world_set_box_proxy` (a static box body standing for an axis-aligned box, with user data), `jolt_world_broad_phase_ray`, `jolt_world_broad_phase_box_cast` and `jolt_world_broad_phase_box` (the user data of every body whose bounds a segment, a moving box or a box touches; a superset until `jolt_world_optimize_broad_phase` rebuilds the tree after proxies moved). Dart: `addBoxProxy`, `setBoxProxy`, `broadPhaseRay`, `broadPhaseBoxCast`, `broadPhaseBox`. Lumina's collision subsystem uses them in a world of its own.
- **Self-collision**: `jolt_soft_body_set_self_collision(world, body, distance)`: after every step a vertex closer than `distance` (m) to one of the cloth's own triangles is pushed out (the triangle back by its barycentric weights) and stops approaching it; a vertex that close to the triangle at rest (its neighbours) is skipped. One pass over a grid of cells as large as the longest edge; about 0.3 ms per step for a 441-vertex sheet. Dart: `setClothSelfCollision(body, distance)` (0 switches it off).
- **Queries**: `jolt_world_cast_ray`.
- **Constraints**: `jolt_constraint_swing_twist` (twist about the frame's X axis, plane axis Y, normal and plane half cones, twist range, friction torque) and `jolt_constraint_hinge` (limits within `-π ≤ min ≤ 0 ≤ max ≤ π`), frames relative to each body's centre of mass; limits, friction torque, a velocity motor (`jolt_constraint_set_velocity_motor`), a position motor (`jolt_constraint_set_position_motor`: a spring of a frequency and damping ratio toward a target rotation; a hinge reads the angle about X), solver iterations for the constraint's island (`jolt_constraint_set_solver_steps`), enable, impulses.

## Dart API

`package:flutter_jolt/flutter_jolt.dart`:

- `JoltPhysics`: `isAvailable` (probes the library once, never throws), `loadError` (why it is false: no code asset, or the loader's message), `version` (`5.6.0`), `ensureAvailable()` (its error names `loadError`).
- `JoltWorld({maxBodies, maxBodyPairs, maxContactConstraints, workerThreads, gravity})`: `gravity`, `solverSettings` (`JoltSolverSettings`), `step(dt, collisionSteps:)`, `createBody(shape, JoltBodySettings)` → body id, `destroyBody` (removes its constraints first), `setBodyOwner`, `setBodyProfiles`, `setBodyMaterial`, `setBodyShape`, `setBodyMassProperties`, `setBodyMotionType`, `setBodyDamping`, `setBodyGravityFactor`, `setBodyContinuousCollision`, `setBodyTransform`, `setBodyVelocity`, `moveKinematic`, `addForce` / `addTorque` / `addImpulse` / `addAngularImpulse`, `activateBody` / `deactivateBody` / `isBodyActive`, `bodyMass`, `bodyState` / `readBodyStates` + `stateAt` / `stateBuffer`, `contacts()`, `castRay`, `setProfileMatrix`, `ignorePair`, `addSwingTwist` / `addHinge` / `removeConstraint` (a `JoltConstraint` has `setLimits`, `maxFrictionTorque`, `setVelocityMotor`, `setPositionMotor`, `setSolverSteps`, `enabled`, `lambdas`), `dispose()`.
- `JoltShape`: `box`, `sphere`, `capsule`, `cylinder`, `convexHull`, `heightField`, `scaled`, `rotatedTranslated`, `offsetCenterOfMass`, `compound`; `userData`, `centerOfMass`, `volume`, `localBounds`, `release()` (a `NativeFinalizer` frees a forgotten shape).
- Cloth (`JoltWorldCloth` extension, `lib/src/jolt_cloth.dart`): `createCloth(vertices, triangles, inverseMasses:, position:, rotation:, settings: JoltClothSettings(...))`, `clothVertexCount`, `clothVertices` (world positions into a `Float32List`), `setClothVertex`, `setClothInverseMass`, `driveClothVertices`, `clothLocalVertices`, `applyClothWind`; `JoltClothBend`, `JoltClothTethers`.
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

## Web (WebAssembly)

The web runs the same C API as one WebAssembly module, `web/flutter_jolt.{js,wasm}` (gitignored):

- **Build**: `tool/web/build_jolt_wasm.sh` (emsdk, default `~/emsdk` else `EMSDK=...`, and a Dart SDK on `PATH` for the defines writer) fetches the pinned Jolt release into `third_party/jolt-wasm/`, builds it with Jolt's own wasm32 flags (`USE_WASM_SIMD`: WASM SIMD with Emscripten's SSE 4.2 emulation, no exceptions) and links `src/jolt_c.cpp` into the module: single-threaded (no `SharedArrayBuffer`, so no COOP/COEP headers), a 16 MB stack, growing memory, BigInt for 64-bit values, every `jolt_*` function of the header exported. `OPT=-O1` links faster. Under Emscripten a world steps on the calling thread with Jolt's single-threaded job system.
- **Dart**: wrappers import `lib/src/jolt_ffi.dart`, `jolt_ffi_package.dart` and `jolt_c.dart`, which export `dart:ffi`, `package:ffi` and the ffigen bindings natively and `lib/src/web_ffi/` (a `dart:ffi` / `package:ffi` layer over the module's heap, adapted from flutter_filament's) plus `lib/src/jolt_bindings.web.g.dart` on the web. `dart run tool/ffigen_web.dart` generates that file from the ffigen output (run it after `tool/ffigen.dart`; `test/web/bindings_lockstep_test.dart` fails otherwise).
- **Start-up**: `await JoltPhysics.ensureInitialized(moduleUrl: 'flutter_jolt.js')` loads the module (natively a no-op); until then `JoltPhysics.isAvailable` is false. The Lumina engine calls it through `LuminaPhysicsSubsystem.prepareJolt()` while a web game loads, and its web build stages the two files next to the game's `index.html`.
- **Tests**: `node --test test/web/module_test.mjs` (every export, a sphere resting on a box); `test/web/browser_tests_test.dart` compiles `test/web/browser_main.dart` with dart2js, serves it beside the module and runs the world, shape, constraint, cloth and broad phase test files in headless Chrome through `test/support/test_api.dart` (`flutter_test` natively, a small browser runner on the web), and reports the timings. On the Windows development machine `flutter test --platform chrome` never connects to its page (even a trivial test), so the suite drives Chrome itself.
- **Measured** (Chrome 155, this machine): the module is 1.40 MB of wasm plus 19 KB of JavaScript and loads in about 40 ms; all 29 tests pass; a step of a settled pile of 200 boxes takes about 0.3 ms on one thread.

## Limits

- Contact impulses are estimates for the step (no rotation terms), not the solved impulses.
- Height fields keep about 8 bits per sample per block (a few millimetres on metre-scale terrain) and are static only.
- Built and tested on Windows x64 and Linux x64 (Ubuntu, clang 21) and as WebAssembly (single-threaded); Android, macOS and iOS are not built yet.

---

[Previous: flutter_riglogic](flutter_riglogic.md) · [Next: flutter_kimodo](flutter_kimodo.md)
