[Türkçe](README.tr.md)

# flutter_jolt

Dart FFI bindings for [Jolt Physics](https://github.com/jrouwe/JoltPhysics): a native physics world with rigid bodies, shapes (box, sphere, capsule, cylinder, convex hull, height field, compounds), swing-twist and hinge constraints, contacts and ray casts. Part of the [Lumina](https://github.com/LuminaGame/lumina) game engine, where it is the physics backend on native desktop.

## Setup

Jolt is fetched and built, not vendored. Build the pinned release once (Windows: Visual Studio 2022; Linux: clang and the lumina repo's bundled libc++):

```bash
tool\build_jolt.bat        # Windows
bash tool/build_jolt.sh    # Linux
```

This writes `third_party/jolt/` (headers, static library, the defines it was built with). The native-assets hook links it on the next `flutter test` / `flutter run`. An app that depends on the package from git points the `jolt_dir` user-define of its workspace root pubspec at such a folder. Without a Jolt build the package compiles without its native library and `JoltPhysics.isAvailable` is false.

## Use

```dart
import 'package:flutter_jolt/flutter_jolt.dart';
import 'package:vector_math/vector_math_64.dart';

if (JoltPhysics.isAvailable) {
  final world = JoltWorld();
  final ground = JoltShape.box(Vector3(50, 0.5, 50));
  world.createBody(ground, JoltBodySettings(motionType: JoltMotionType.static_, position: Vector3(0, -0.5, 0)));
  ground.release();
  final ball = JoltShape.sphere(0.5);
  final id = world.createBody(ball, JoltBodySettings(position: Vector3(0, 3, 0)));
  ball.release();
  for (var i = 0; i < 120; i++) {
    world.step(1 / 60);
  }
  print(world.bodyState(id).centerOfMass);
  world.dispose();
}
```

Units are metres, kilograms, seconds and radians. The full reference is [docs/en/flutter_jolt.md](../docs/en/flutter_jolt.md).

## Licence

GPLv3 (`LICENSE`). Jolt Physics is MIT; see `THIRD_PARTY_NOTICES.md`.
