[English](https://github.com/LuminaGame/tools/blob/main/flutter_assimp/README.md)

# flutter_assimp

3D modelleri uygulamanın içinde glTF 2.0 binary'ye (GLB) dönüştürmek için [Open Asset Import Library (Assimp)](https://github.com/assimp/assimp) Dart FFI binding'leri: FBX, OBJ, Collada, 3DS, PLY, DirectX ve STL girer; bir GLB ve neyin dönüştürüldüğünü anlatan bir JSON raporu çıkar. Küçük bir C bridge (`src/assimp_bridge.cpp`) Assimp'i sürer; paketin native-assets build hook'u onu paketle gelen Assimp kaynaklarıyla birlikte derler, C++ derleyicisi dışında kurulacak bir şey yoktur. [Lumina](https://github.com/LuminaGame/lumina) modelleri GLB tabanlı asset pipeline'ına bununla import eder.

## Özellikler

- Dosyadan dosyaya (`convertFileToGlb`), dosyadan rapor ile birlikte byte'lara (`convertFileForImport`) ve byte'lardan byte'lara (`convertMemoryToGlb`).
- FBX (binary ve ASCII), OBJ (+MTL), Collada (`.dae`, zip'li `.zae`), 3DS, PLY, DirectX (`.x`) ve STL okur.
- İsteğe bağlı normalize: kaynağın birim ölçeğini ve eksen sistemini (FBX GlobalSettings) sahneye işler; GLB standart glTF olur (metre, +Y yukarı, +Z ön).
- İsteğe bağlı collision hull mesh'lerinin (`UCX_`, `UBX_`, `USP_`, `UCP_`) çıkarılması; noktaları ve üçgenleriyle raporda döner.
- Kaynak metadata'sı, animasyon take'leri, mesh, skinned mesh, materyal ve node sayıları ile materyal başına renkler, PBR değerleri ve texture yollarını içeren bir rapor.
- Skinned mesh'ler ve animasyonlar korunur (take başına bir glTF animasyonu).

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
flutter pub add flutter_assimp
```

Gereksinimler: Dart 3.12 veya sonrası (native assets destekli Flutter) ve platformun C++ toolchain'i:

- Windows: "Desktop development with C++" workload'u kurulu Visual Studio 2022 (ya da Build Tools).
- Linux: `clang` ve zlib header'ları (`zlib1g-dev`; Flutter Linux desktop gereksinimleri bunları zaten getirir).
- Android: Flutter'ın Android toolchain'inin kurduğu Android NDK.
- macOS / iOS: Xcode.

## Kullanım

```dart
import 'package:flutter_assimp/flutter_assimp.dart';

Future<void> convert() async {
  if (FlutterAssimp.isAvailable) {
    print(FlutterAssimp.version); // ör. "5.0 (commit 4673545f)"
  }

  // Dosyadan dosyaya.
  final ok = await FlutterAssimp.convertFileToGlb('crate.fbx', 'crate.glb');
  if (!ok) print(FlutterAssimp.lastError);

  // Import pipeline'ı için: GLB byte'ları ve bir rapor.
  final result = FlutterAssimp.convertFileForImport(
    'SM_Barrel.fbx',
    options: AssimpConvertOptions.all, // normalize | stripCollision
  );
  if (result.success) {
    final glb = result.glb!; // Uint8List
    print('${glb.length} bytes, unit scale ${result.report['unit_scale']}, '
        'hulls ${result.report['collision']}');
  } else {
    print(result.error);
  }

  // Bellekte; `hint` kaynak formatın uzantısıdır.
  final bytes = await File('crate.obj').readAsBytes();
  final fromMemory = await FlutterAssimp.convertMemoryToGlb(bytes, hint: 'obj');
  print(fromMemory?.length);

  print(FlutterAssimp.isSupportedFormat('model.dae')); // true
}
```

(`File`, `dart:io`'dan gelir.) `AssimpConvertOptions.normalize` birimleri ve eksenleri işler, `AssimpConvertOptions.stripCollision` collision hull'larını çıkarır ve raporda listeler. Native bridge yüklenmemişse `convertFileToGlb`, `PATH`'teki `assimp` komut satırı aracına düşer; diğer çağrılar bridge'e ihtiyaç duyar. `AssimpBindings` bridge'e düşük seviyeli erişim verir.

Tam bir dönüşüm için [example/main.dart](https://github.com/LuminaGame/tools/blob/main/flutter_assimp/example/main.dart)'a bakın.

## Native kütüphane nasıl derlenir

`hook/build.dart`, `flutter_assimp`'i dynamic library olarak derler ve code asset olarak paketler; Dart onu `@Native` binding'leriyle çağırır.

- **Paketle gelen kaynaklardan (varsayılan).** Hook bridge'i `third_party/assimp` altındaki Assimp 5.0 kaynaklarıyla (Google Filament'in patch'lenmiş Assimp kopyası; yukarıdaki importer'lara ve glTF 2 exporter'a indirgenmiş) tek bir derleyici çalıştırmasında derler. zlib Windows'ta `third_party/zlib`'den, diğer platformlarda sistemden gelir. İlk build masaüstü bir makinede yaklaşık 20 saniye sürer; sonraki build'ler cache'lenmiş kütüphaneyi kullanır. `tool/vendor_assimp.dart` paketle gelen kaynakları bir Filament checkout'undan yeniler.
- **Bir Filament build'ine karşı (isteğe bağlı).** `filament_dir` user-define'ı (uygulamanın root pubspec'ine göreli) Assimp static kütüphanesi olan bir Google Filament build'ini gösteriyorsa (Windows'ta `out/cmake-release-windows/third_party/libassimp/tnt/assimp.lib`, diğerlerinde `out/cmake-release/third_party/libassimp/tnt/libassimp.a`), hook o kütüphaneyi link eder ve yalnızca bridge'i, exporter'ı ve ek importer'ları derler. Lumina böyle build eder:

  ```yaml
  hooks:
    user_defines:
      flutter_assimp:
        filament_dir: filament
        libcxx_dir: flutter_filament/third_party/libcxx # yalnızca Linux: Filament'in build edildiği libc++
  ```

## Ek bilgiler

- Kaynak, issue'lar ve katkı: [LuminaGame/tools](https://github.com/LuminaGame/tools) ([issue'lar](https://github.com/LuminaGame/tools/issues)).
- Testler: `flutter test test/import_formats_test.dart test/fbx_import_conversion_test.dart`. FBX testleri Lumina'nın test-assets klasöründeki gerçek Unreal export'larını okur (`../test-assets` ya da `LUMINA_TEST_ASSETS`); klasör yoksa atlanır. `src/assimp_bridge.h` değişince binding'leri `dart run tool/ffigen.dart` ile yeniden üretin.
- Lisans: GPL-3.0 ([LICENSE](LICENSE)). Paketle gelen Assimp (BSD-3-Clause), contrib kütüphaneleri ve zlib kendi lisanslarını korur; bkz. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
