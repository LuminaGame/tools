[English](README.md)

# flutter_riglogic

Epic Games'in [OpenRigLogic](https://github.com/EpicGames/openriglogic) kütüphanesi ve DNA reader'ı için Dart FFI binding'leri. Lumina bunu MetaHuman yüz rig'lerini real-time hesaplamak için kullanır.

OpenRigLogic, input control değerlerinden rig output'larını (joint transform'ları, blend shape ağırlıkları, animated map değerleri) hesaplar. Bu paket onu üç sınıfla sarar:

- `DnaReader`, binary bir `.dna` dosyasını (diskten ya da bellekten) okur: isim, LOD sayısı, joint'ler, blend shape channel'ları, raw ve GUI control'ler, animated map'ler.
- `RigLogic`, bir `DnaReader`'dan rig evaluator'ı kurar.
- `RigInstance`, tek bir karakterin control değerlerini, LOD'unu ve hesaplanan output'larını tutar.

C wrapper (`src/riglogic_c.h`, `src/riglogic_c.cpp`) paketin native assets hook'u (`hook/build.dart`) tarafından derlenir ve vendored kaynaklardan bir kere build ettiğiniz static OpenRigLogic kütüphanesini link eder.

Platformlar: Linux ve Windows (hook'ta bir macOS dalı da var).

## Gereksinimler

- Linux: clang, CMake ve [lumina](https://github.com/LuminaGame/lumina) repo'sundaki bundled libc++ (`flutter_filament/third_party/libcxx`).
- Windows: C++ workload'u kurulu Visual Studio 2022, CMake ve Ninja.

## OpenRigLogic'i build etmek

OpenRigLogic (MIT) `third_party/openriglogic/` altında vendored olarak gelir. İlk `flutter run` / `flutter test` öncesinde static kütüphaneyi build edin:

```bash
bash tool/build_openriglogic.sh     # Linux: clang + bundled libc++, -fPIC -> third_party/openriglogic/lib/libriglogic.a
```

```bat
tool\build_openriglogic.bat         :: Windows: MSVC, static CRT (/MT) -> third_party\openriglogic\lib\riglogic.lib
```

Linux script'i libc++'ı `LUMINA_LIBCXX_DIR` üzerinden, yoksa `../../lumina/flutter_filament/third_party/libcxx` altında bulur. Windows script'i MSVC environment'ı aktif değilse `vswhere` ile kurar.

## Hook input'larını nerede bulur

| Ne | Sırayla |
|---|---|
| OpenRigLogic kütüphanesi | 1. `LUMINA_RIGLOGIC_LIB_DIR` (yalnızca hook doğrudan çalıştırıldığında; hooks runner `LUMINA_*` değişkenlerini iletmez) 2. workspace root pubspec'te `hooks: user_defines: flutter_riglogic:` altındaki `riglogic_lib_dir`, o pubspec'e göre relative, kütüphane oradaysa 3. `<paket root>/third_party/openriglogic/lib` |
| libc++ (Linux) | 1. `LUMINA_LIBCXX_DIR` 2. `libcxx_dir` user-define'ı 3. `<paket root>/../../lumina/flutter_filament/third_party/libcxx` |

Kütüphaneyi barındırmayan bir `riglogic_lib_dir` paketin kendi build'ine bırakır; böylece bir uygulama prebuilt kütüphaneyi bağladığı klasörü adlandırabilir, bu paketin geliştirme checkout'u ise yerinde build edilmiş kütüphaneyi kullanmaya devam eder. `libriglogic.a` / `riglogic.lib` ikisinde de yoksa hook, build script'ini adıyla anan bir hatayla durur. Git dependency pub cache'te durur ve orada kütüphane build edilmemiştir; bu yüzden `riglogic_lib_dir`'i build script'ini çalıştırdığınız bir checkout'a yönlendirin:

```yaml
dependencies:
  flutter_riglogic:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_riglogic

hooks:
  user_defines:
    flutter_riglogic:
      riglogic_lib_dir: ../tools/flutter_riglogic/third_party/openriglogic/lib
      libcxx_dir: flutter_filament/third_party/libcxx   # yalnızca Linux
```

## Kullanım

```dart
import 'package:flutter_riglogic/flutter_riglogic.dart';

final reader = DnaReader.fromFile('assets/face.dna');
print('${reader.name}: ${reader.jointCount} joint, '
    '${reader.blendShapeChannelCount} blend shape, ${reader.rawControlCount} raw control');

final rig = RigLogic.create(reader);
final instance = RigInstance.create(rig)..lod = 0;

instance.setRawControl(0, 1.0);
rig.calculate(instance);

final joints = instance.getJointOutputs();          // List<double>
final weights = instance.getBlendShapeOutputs();    // List<double>
final maps = instance.getAnimatedMapOutputs();      // List<double>

instance.dispose();
rig.dispose();
reader.dispose();
```

`DnaReader.fromMemory(bytes)` bellekteki bir DNA'yı okur. Native kütüphane yüklü değilse factory'ler `UnsupportedError` fırlatır.

`example/`, `assets/sample.dna` dosyasını yükleyip rig'in control'lerini süren bir Flutter uygulamasıdır. Paket klasöründe `dart run tool/inspect_dna.dart`, `test/fixtures/sample.dna` içindeki joint'leri, blend shape'leri ve control'leri yazdırır.

## Test'ler

```bash
flutter test test/dna_reader_test.dart test/rig_logic_test.dart
```

Gerçek binary DNA fixture'ı `test/fixtures/sample.dna` üzerinde çalışırlar.

## Lisans

GPL-3.0 (bkz. [LICENSE](LICENSE)). `third_party/openriglogic/` altındaki vendored OpenRigLogic, Epic Games tarafından MIT lisansıyla yayınlanmıştır (bkz. [LICENSE](third_party/openriglogic/LICENSE)).
