[English](https://github.com/LuminaGame/tools/blob/main/flutter_riglogic/README.md)

# flutter_riglogic

Epic Games'in [OpenRigLogic](https://github.com/EpicGames/openriglogic) kütüphanesi ve DNA reader'ı için Dart FFI binding'leri: bir MetaHuman `.dna` dosyasını okur ve yüz rig'ini real-time hesaplar; control değerlerinden joint transform'larına, blend shape ağırlıklarına ve animated map değerlerine. Native kod, paketin native-assets build hook'u tarafından paketle gelen OpenRigLogic kaynaklarından derlenir; C++ derleyicisi dışında kurulacak bir şey yoktur. [Lumina](https://github.com/LuminaGame/lumina) MetaHuman yüzlerini bununla sürer.

## Özellikler

- `DnaReader`: binary bir `.dna`'yı diskten ya da bellekten okur: isim, LOD sayısı, joint'ler, blend shape channel'ları, raw ve GUI control'ler, animated map'ler.
- `RigLogic`: bir `DnaReader`'dan kurulan rig evaluator (joint'ler, blend shape'ler, animated map'ler, PSD, RBF ve machine-learned behavior).
- `RigInstance`: tek bir karakterin control değerleri, LOD'u ve hesaplanan output'ları.
- CMake yok, prebuilt binary yok: hook OpenRigLogic'i ve C wrapper'ı ilk build'de platformun toolchain'iyle derler ve sonucu cache'ler.

## Platform desteği

| Platform | Durum |
|---|---|
| Windows x64 | Doğrulandı (`flutter test`, `flutter build windows`) |
| Linux x64 | Doğrulandı (`flutter test`, `flutter build linux`) |
| Android arm64 | Build ve link oluyor (`flutter build apk`); libc++ static link edilir |
| macOS, iOS | Xcode clang'ıyla derlenmesi beklenir; henüz doğrulanmadı |
| Web | Desteklenmez (`dart:ffi`) |

## Başlarken

```bash
flutter pub add flutter_riglogic
```

Gereksinimler: Dart 3.12 veya sonrası (native assets destekli Flutter) ve platformun C++ toolchain'i:

- Windows: "Desktop development with C++" workload'u kurulu Visual Studio 2022 (ya da Build Tools).
- Linux: `clang` (Flutter Linux desktop gereksinimlerinde zaten var).
- Android: Flutter'ın Android toolchain'inin kurduğu Android NDK.
- macOS / iOS: Xcode.

## Kullanım

```dart
import 'package:flutter_riglogic/flutter_riglogic.dart';

void evaluate(String dnaPath) {
  final reader = DnaReader.fromFile(dnaPath);
  print('${reader.name}: ${reader.jointCount} joints, '
      '${reader.blendShapeChannelCount} blend shapes, '
      '${reader.rawControlCount} raw controls');

  final rig = RigLogic.create(reader);
  final instance = RigInstance.create(rig)..lod = 0;

  instance.setRawControl(0, 1.0);
  rig.calculate(instance);

  final joints = instance.getJointOutputs(); // List<double>
  final weights = instance.getBlendShapeOutputs(); // List<double>
  final maps = instance.getAnimatedMapOutputs(); // List<double>
  print('${joints.length} joint values, ${weights.length} weights, ${maps.length} maps');

  instance.dispose();
  rig.dispose();
  reader.dispose();
}
```

`DnaReader.fromMemory(bytes)` bellekteki bir DNA'yı okur (örneğin `rootBundle`'dan). Native kütüphane yüklenmemişse factory'ler `UnsupportedError` fırlatır. Her nesne native bellek tutar: işiniz bitince `dispose()` çağırın.

[Example](https://github.com/LuminaGame/tools/tree/main/flutter_riglogic/example), küçük bir DNA yükleyip raw control'leri slider olarak listeleyen ve hesaplanan output'ları gösteren bir Flutter uygulamasıdır.

## Native kütüphane nasıl derlenir

`hook/build.dart`, `flutter_riglogic`'i dynamic library olarak derler ve code asset olarak paketler; Dart onu `@Native` binding'leriyle çağırır.

- **Kaynaktan (varsayılan).** Hook C wrapper'ı (`src/riglogic_c.cpp`) paketle gelen OpenRigLogic kaynaklarıyla (`third_party/openriglogic/src`, yaklaşık 100 dosya) birlikte derler. İlk build yaklaşık 20 saniye sürer; sonraki build'ler cache'lenmiş kütüphaneyi kullanır.
- **Prebuilt static library (isteğe bağlı).** `third_party/openriglogic/lib` (ya da `riglogic_lib_dir` user-define'ının gösterdiği klasör) `riglogic.lib` / `libriglogic.a` içeriyorsa yalnızca wrapper derlenir ve o kütüphane link edilir. `tool/build_openriglogic.{sh,bat}` ve `tool/build_openriglogic_android.{sh,bat}` onu CMake ile build eder. Uygulama user-define'ı kendi root pubspec'inde, o pubspec'e göreli olarak verir:

  ```yaml
  hooks:
    user_defines:
      flutter_riglogic:
        riglogic_lib_dir: third_party/openriglogic/lib
        libcxx_dir: path/to/libcxx   # yalnızca Linux: prebuilt kütüphanenin build edildiği libc++
  ```

## Ek bilgiler

- Kaynak, issue'lar ve katkı: [LuminaGame/tools](https://github.com/LuminaGame/tools) ([issue'lar](https://github.com/LuminaGame/tools/issues)). Testler: `flutter test test/dna_reader_test.dart test/rig_logic_test.dart` (gerçek DNA fixture'ı `test/fixtures/sample.dna`'yı okurlar); `dart run tool/inspect_dna.dart` o fixture'ın joint, blend shape ve control'lerini yazdırır.
- Lisans: GPL-3.0 ([LICENSE](LICENSE)). Paketle gelen OpenRigLogic, Epic Games tarafından MIT lisansıyla dağıtılır; bkz. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Epic'in MetaHuman araçlarından gelen DNA dosyaları Epic'in kendi lisans koşullarına tabidir; bu paket yalnızca küçük, sentetik bir test DNA'sı içerir.
