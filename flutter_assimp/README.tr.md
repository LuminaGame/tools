[English](README.md)

# flutter_assimp

In-process 3D model dönüşümü için [Open Asset Import Library (Assimp)](https://github.com/assimp/assimp) Dart FFI binding'leri. Küçük bir C bridge (`src/assimp_bridge.cpp`) modeli Assimp ile yükler ve glTF 2.0 binary (GLB) olarak yazar. Lumina bunu FBX, OBJ, Collada (DAE), 3DS, PLY, DirectX (X) ve STL dosyalarını GLB tabanlı asset pipeline'ına import etmek için kullanır.

Bridge, paketin native assets hook'u (`hook/build.dart`) tarafından ilk `flutter run` / `flutter test` sırasında derlenir; elle yapılacak bir build adımı yoktur. Assimp'i kendisi build etmez, bir Google Filament build'indeki Assimp kütüphanesini link eder.

Platformlar: Linux ve Windows (hook'ta bir macOS dalı da var).

## Gereksinimler

- Prebuilt **Google Filament v1.77.0** ([lumina](https://github.com/LuminaGame/lumina) repo'sunda anlatılan local patch'lerle). Hook şunları kullanır:
  - `<filament>/third_party/libassimp` içindeki Assimp kaynakları ve header'ları: Filament'in Assimp kütüphanesinde yalnız FBX ve OBJ importer'ları vardır, bu yüzden hook Collada, 3DS, PLY, DirectX ve STL importer'larını da (`contrib/irrXML`, `contrib/unzip` ve `third_party/libz` header'larıyla) `third_party/libassimp/code` klasöründen, kaynaklar oradaysa derler; yoksa bridge yalnız FBX ve OBJ okur;
  - Linux / macOS: `<filament>/out/cmake-release/third_party/libassimp/tnt/libassimp.a` ve `third_party/zstd/tnt/libzstd.a`;
  - Windows: `<filament>/out/cmake-release-windows/third_party/libassimp/tnt/assimp.lib`, `zstd/tnt/zstd.lib`, `libz/tnt/z.lib`.
- Linux: clang ve lumina repo'sundaki bundled libc++ (`flutter_filament/third_party/libcxx`).
- Windows: C++ workload'u kurulu Visual Studio 2022.

## Hook, Filament'i ve libc++'ı nerede bulur

| Ne | Sırayla |
|---|---|
| Filament | 1. `LUMINA_FILAMENT_DIR` (yalnızca hook doğrudan çalıştırıldığında; hooks runner `LUMINA_*` değişkenlerini iletmez) 2. workspace root pubspec'te `hooks: user_defines: flutter_assimp:` altındaki `filament_dir`, o pubspec'e göre relative 3. `<paket root>/../filament` |
| libc++ (Linux) | 1. `LUMINA_LIBCXX_DIR` 2. `libcxx_dir` user-define'ı 3. `<paket root>/../../lumina/flutter_filament/third_party/libcxx` |

Git dependency olarak kullanıldığında paket pub cache'te durur; user-define'ları uygulamanızın root pubspec'inde verin:

```yaml
dependencies:
  flutter_assimp:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_assimp

hooks:
  user_defines:
    flutter_assimp:
      filament_dir: filament                          # bu pubspec'e göre relative
      libcxx_dir: flutter_filament/third_party/libcxx # yalnızca Linux
```

## Kullanım

```dart
import 'package:flutter_assimp/flutter_assimp.dart';

if (FlutterAssimp.isAvailable) {
  print(FlutterAssimp.version); // ör. "5.0 (commit 4673545f)"
}

// Dosyadan dosyaya. Native bridge yüklü değilse PATH'teki `assimp`
// CLI'ına düşer.
final ok = await FlutterAssimp.convertFileToGlb('crate.fbx', 'crate.glb');
if (!ok) print(FlutterAssimp.lastError);

// Import pipeline'ı için: yalnızca native bridge, GLB byte'ları ve bir rapor.
final result = FlutterAssimp.convertFileForImport(
  'SM_Barrel.fbx',
  options: AssimpConvertOptions.all, // normalize | stripCollision
);
if (result.success) {
  final glb = result.glb!;              // Uint8List
  final unitScale = result.report['unit_scale'];
  final hulls = result.report['collision'];
} else {
  print(result.error);
}

// Bellekte; `hint` kaynak formatın uzantısıdır.
final glb = await FlutterAssimp.convertMemoryToGlb(bytes, hint: 'obj');

FlutterAssimp.isSupportedFormat('model.dae'); // true: FlutterAssimp.importExtensions'tan biri
```

`AssimpConvertOptions`:

- `normalize`, kaynağın birim ölçeğini ve eksen sistemini (FBX GlobalSettings) sahneye işler; GLB metre cinsinden, +Y up, +Z front olarak çıkar.
- `stripCollision`, collision hull mesh'lerini (adı `UCX_`, `UBX_`, `USP_`, `UCP_` ile başlayanlar) kaldırır ve raporda listeler.

Rapor (`AssimpImportConversion.report`) ayrıca kaynak metadata'sını, eksenleri, animation take'lerini, mesh / skinned mesh / material / node sayılarını ve material başına detayları (renkler, PBR değerleri, texture path'leri) içerir. `AssimpBindings` bridge'e low-level erişim sağlar.

## Development

`src/assimp_bridge.h` değişince `@Native` binding'lerini (`lib/src/third_party/assimp_c.g.dart`) yeniden üretin:

```bash
dart run tool/ffigen.dart
```

Test'ler:

```bash
flutter test test/flutter_assimp_test.dart test/fbx_import_conversion_test.dart
```

Dönüşüm test'leri [test-assets](https://github.com/LuminaGame/test-assets) repo'sundaki gerçek FBX dosyalarını kullanır (`../test-assets` ya da `LUMINA_TEST_ASSETS`); dosyalar yoksa skip edilir.

## Lisans

GPL-3.0 (bkz. [LICENSE](LICENSE)). Assimp BSD-3-Clause, Google Filament Apache-2.0 lisanslıdır; ikisi de kendi lisansını korur.
