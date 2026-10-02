[English](README.md)

# Lumina tools

[Lumina](https://github.com/LuminaGame/lumina) game engine'inin ve editor'ü Lumina Studio'nun üzerine kurulduğu native ve FFI paketleri. Lumina, Google Filament üzerinde çalışan bir Flutter/Dart 3D game engine'idir; buradaki paketler model import, yüz rig'i hesaplama, video encode ve pointer capture işlerini üstlenir.

Dokümantasyon: [docs/README.tr.md](docs/README.tr.md).

| Paket | Ne işe yarar |
|---|---|
| [`flutter_assimp`](flutter_assimp/) | [Assimp](https://github.com/assimp/assimp) için Dart FFI binding'leri: FBX, OBJ, DAE, 3DS, Blend ve diğer formatları glTF 2.0 binary'ye (GLB) çevirir. Assimp kütüphanesini bir Filament build'inden link eder. |
| [`flutter_kimodo`](flutter_kimodo/) | [kimodo.cpp](https://github.com/localai-org/kimodo.cpp) için Dart FFI binding'leri: NVIDIA Kimodo ile metinden hareket üretimi (GGUF ağırlıklar, CPU ve Vulkan), arka plan isolate'inde. |
| [`flutter_riglogic`](flutter_riglogic/) | Epic Games'in [OpenRigLogic](https://github.com/EpicGames/openriglogic) kütüphanesi için Dart FFI binding'leri: MetaHuman `.dna` dosyalarını okur ve yüz rig'lerini hesaplar. |
| [`flutter_gstreamer`](flutter_gstreamer/) | Sistemde kurulu GStreamer 1.x için saf Dart FFI binding'leri, run time'da yüklenir: pipeline'lar, PNG ya da RGBA frame'lerden VP8/WebM encode, media probe. Engine'in smoke test'leri videolarını bununla kaydeder. |
| [`lumina_smoke`](lumina_smoke/) | Engine paketlerinin ortak smoke test sistemi: test adıyla eşleşen sidecar JSON'lu PNG ve VP8/WebM artifact'ler, smoke video kuralları (10 s, 1024×768, 30 fps) ve probe, frame recorder'lar, link'li HTML smoke raporunu yazan `flutter test` runner'ı. |
| [`lumina_mouse_capture`](lumina_mouse_capture/) | Linux'ta (Wayland pointer constraints, X11 grab ve warp) ve Windows'ta (raw input, clip edilmiş gizli imleç) relative motion ile pointer capture yapan Flutter plugin'i; diğer platformlarda capture yapılmaz. |

İlgili repo'lar: [lumina](https://github.com/LuminaGame/lumina) (engine ve editor), [plugins](https://github.com/LuminaGame/plugins), [marketplace](https://github.com/LuminaGame/marketplace), [test-assets](https://github.com/LuminaGame/test-assets).

## Gereksinimler

- Dart `^3.12.0` içeren Flutter SDK.
- Workspace script'leri için [melos](https://melos.invertase.dev/) 7 (root pubspec'te dev dependency; `dart pub global activate melos` ile `melos` PATH'e girer, ya da `dart run melos` kullanın).
- Native paketler (`flutter_assimp`, `flutter_riglogic`) için:
  - **Linux**: clang, CMake ve lumina repo'sunda `flutter_filament/third_party/libcxx` altında gelen bundled libc++.
  - **Windows**: C++ workload'u kurulu Visual Studio 2022 (MSVC), CMake ve Ninja.
  - `flutter_assimp` için prebuilt **Google Filament v1.77.0** (lumina repo'sunda anlatılan local patch'lerle).
- `flutter_gstreamer` için: base ve good plugin set'leriyle GStreamer 1.x.
- Linux'ta `lumina_mouse_capture` için: GTK 3, Wayland desteği için de `wayland-client`, `wayland-scanner` ve `wayland-protocols`.

## Kurulum

Lumina repo'ları yan yana checkout edilecek şekilde tasarlandı:

```
<dir>/
  lumina/        https://github.com/LuminaGame/lumina
  tools/         bu repo
  plugins/       https://github.com/LuminaGame/plugins
  marketplace/   https://github.com/LuminaGame/marketplace
  filament/      prebuilt out/ klasörleriyle patch'li Filament v1.77.0
  test-assets/   https://github.com/LuminaGame/test-assets (opsiyonel, Git LFS)
```

```bash
git clone https://github.com/LuminaGame/tools.git
cd tools
ln -s ../filament filament            # Windows: mklink /J filament ..\filament
ln -s ../test-assets test-assets      # opsiyonel; Windows: mklink /J test-assets ..\test-assets
dart pub get                          # workspace'teki tüm paketleri resolve eder
```

`filament/` ve `test-assets/` gitignore'daki link'lerdir. Repo bir Dart pub workspace'idir: root `pubspec.yaml` paketleri `workspace:` altında listeler, her pakette `resolution: workspace` vardır ve tek bir `pubspec.lock` hepsini kapsar.

### Filament

`flutter_assimp`, küçük bir C++ bridge'i `filament/third_party/libassimp` içindeki Assimp kaynaklarına karşı derler ve Filament build'inin static kütüphanelerini link eder:

- Linux / macOS: `filament/out/cmake-release/third_party/libassimp/tnt/libassimp.a` ve `.../zstd/tnt/libzstd.a`
- Windows: `filament/out/cmake-release-windows/third_party/{libassimp,zstd,libz}/tnt/*.lib`

Filament'in nasıl build ve patch edileceği [lumina](https://github.com/LuminaGame/lumina) repo'sunda anlatılıyor.

### OpenRigLogic

`flutter_riglogic`, `flutter_riglogic/third_party/openriglogic` altındaki vendored kaynaklardan build edilen static bir OpenRigLogic kütüphanesini link eder:

```bash
bash flutter_riglogic/tool/build_openriglogic.sh              # Linux   -> third_party/openriglogic/lib/libriglogic.a
flutter_riglogic\tool\build_openriglogic.bat                  # Windows -> third_party\openriglogic\lib\riglogic.lib
flutter_riglogic\tool\build_openriglogic_android.bat [abi]    # Android (Windows host) -> third_party\openriglogic\lib\android\<abi>\libriglogic.a
bash flutter_riglogic/tool/build_openriglogic_android.sh [abi]# Android (Linux host)   -> third_party/openriglogic/lib/android/<abi>/libriglogic.a
```

### kimodo.cpp

`flutter_kimodo`, `flutter_kimodo/tool/kimodo/UPSTREAM` dosyasında sabitlenen commit'ten build edilen hazır bir kimodo.cpp (kimodo + ggml paylaşımlı kütüphaneleri) paketler:

```bash
powershell -ExecutionPolicy Bypass -File flutter_kimodo\tool\build_kimodo.ps1   # Windows: VS 2022; Vulkan SDK kuruluysa Vulkan
bash flutter_kimodo/tool/build_kimodo.sh                                      # Linux
dart run flutter_kimodo/tool/fetch_prebuilt.dart                              # yerel ya da yayınlanmış arşivi açar
```

Ayrıntılar: [docs/tr/flutter_kimodo.md](docs/tr/flutter_kimodo.md).

### Native assets hook ayarları

`flutter_assimp` ve `flutter_riglogic` native assets hook'ları path'leri **build edilen uygulamanın workspace root pubspec'indeki** `hooks: user_defines:` bölümünden okur (path'ler o pubspec'e göre relative). Environment variable'lar bunları ezer, ama yalnızca hook doğrudan çalıştırıldığında: Flutter/Dart hooks runner `LUMINA_*` değişkenlerini hook'a iletmez.

| Ayar | Paket | Environment override | Varsayılan |
|---|---|---|---|
| `filament_dir` | flutter_assimp | `LUMINA_FILAMENT_DIR` | `<paket>/../filament` (bu repo'nun `filament/` link'i) |
| `libcxx_dir` (Linux) | ikisi de | `LUMINA_LIBCXX_DIR` | `<paket>/../../lumina/flutter_filament/third_party/libcxx` |
| `riglogic_lib_dir` | flutter_riglogic | `LUMINA_RIGLOGIC_LIB_DIR` | `<paket>/third_party/openriglogic/lib` |

Bu repo'nun root pubspec'i `flutter_assimp: filament_dir: filament` ayarını yapar.

## Paketleri başka bir repo'dan kullanmak

Git dependency olarak ekleyin:

```yaml
dependencies:
  flutter_assimp:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_assimp
  flutter_gstreamer:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_gstreamer
```

Git'ten resolve edilen paket pub cache'te durur ve yanında Filament yoktur; bu yüzden uygulamanın workspace root pubspec'i hook'lara nereye bakacaklarını söyler. Örneğin lumina repo'su gibi düzenlenmiş (kendi `filament/` link'i olan) bir workspace'te:

```yaml
hooks:
  user_defines:
    flutter_assimp:
      filament_dir: filament
      libcxx_dir: flutter_filament/third_party/libcxx
    flutter_riglogic:
      libcxx_dir: flutter_filament/third_party/libcxx
      riglogic_lib_dir: ../tools/flutter_riglogic/third_party/openriglogic/lib
```

Yan yana checkout'larla local development için, kullanan workspace'in root'undaki gitignore'lu bir `pubspec_overrides.yaml` git dependency'lerini bu checkout'a yönlendirir (pub workspace'ler override'ları yalnızca root'tan okur):

```yaml
dependency_overrides:
  flutter_assimp:
    path: ../tools/flutter_assimp
  flutter_riglogic:
    path: ../tools/flutter_riglogic
  flutter_gstreamer:
    path: ../tools/flutter_gstreamer
  lumina_smoke:
    path: ../tools/lumina_smoke
  lumina_mouse_capture:
    path: ../tools/lumina_mouse_capture
```

## Development

```bash
melos run analyze        # her pakette flutter analyze
melos run format         # dart format
melos run format:check   # format'lanmamış kaynak varsa fail eder
melos run test           # test/ klasörü olan her pakette, sırayla flutter test
```

Test'ler gerçek native kütüphaneleri ve gerçek dosyaları kullanır, mock yoktur. `test-assets/` (ya da `LUMINA_TEST_ASSETS`) içindeki modellere ihtiyaç duyan test'ler asset'ler yoksa skip edilir. Asset'leri almak için:

```bash
git lfs install
git clone https://github.com/LuminaGame/test-assets.git ../test-assets
```

## Lisans

GPL-3.0 (bkz. [LICENSE](LICENSE)); her pakette aynı lisans dosyası vardır. Third-party kod kendi lisansını korur: OpenRigLogic (MIT, `flutter_riglogic/third_party/openriglogic/LICENSE`), Assimp (BSD-3-Clause), Google Filament (Apache-2.0) ve GStreamer (LGPL; dinamik yüklenir, dağıtılmaz).
