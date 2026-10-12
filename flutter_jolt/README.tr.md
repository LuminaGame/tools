[English](README.md)

# flutter_jolt

[Jolt Physics](https://github.com/jrouwe/JoltPhysics) için Dart FFI binding'leri: rigid body'ler, şekiller (kutu, küre, kapsül, silindir, convex hull, height field, compound), swing-twist ve hinge constraint'leri, temaslar ve ray cast'lerle native bir fizik dünyası. [Lumina](https://github.com/LuminaGame/lumina) oyun motorunun parçasıdır; orada native masaüstündeki fizik backend'idir.

## Kurulum

Jolt vendored değildir; indirilip build edilir. Sabitlenen sürümü bir kez build edin (Windows: Visual Studio 2022; Linux: clang ve lumina repo'sunun paketli libc++'ı):

```bash
tool\build_jolt.bat        # Windows
bash tool/build_jolt.sh    # Linux
```

Bu, `third_party/jolt/` klasörünü yazar (header'lar, static kütüphane, derlendiği define'lar). Native-assets hook'u bir sonraki `flutter test` / `flutter run` sırasında onu link eder. Paketi git'ten kullanan bir uygulama, workspace root pubspec'indeki `jolt_dir` user-define'ını böyle bir klasöre yönlendirir. Jolt build'i yoksa paket native kütüphanesi olmadan derlenir ve `JoltPhysics.isAvailable` false olur.

## Kullanım

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

Birimler metre, kilogram, saniye ve radyandır. Tam referans: [docs/tr/flutter_jolt.md](../docs/tr/flutter_jolt.md).

## Lisans

GPLv3 (`LICENSE`). Jolt Physics MIT lisanslıdır; bkz. `THIRD_PARTY_NOTICES.md`.
