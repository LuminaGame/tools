[English](../en/flutter_assimp.md)

# flutter_assimp

`flutter_assimp`, Open Asset Import Library'yi (Assimp) Dart FFI ile bağlar ve FBX, OBJ, Collada (DAE), 3DS, PLY, DirectX (X) ve STL dosyalarını diskte ya da bellekte, Lumina engine'inin yüklediği format olan binary glTF 2.0'a (`.glb`) dönüştürür. Dosya yolları `flutter_assimp/` paket dizinine görelidir.

Doku koordinatları glTF kuralıyla çıkar (v = 0 görüntünün üstünde): FBX, OBJ, Collada ve diğer formatların V-yukarı koordinatları her UV setinde ve her dönüşümde (dosya ya da bellek) `1 - v` olarak yazılır. Assimp 5.0'ın `Exporter::Export`'u bir exporter'ı aynı sahne kopyası üzerinde iki kez çalıştırır ve glTF exporter'ı V'yi yerinde çevirir; bu yüzden köprü o exporter'ı `glb2-once` adıyla bir kez daha kaydeder ve yalnızca ilk çalıştırmada yazar. Düz `glb2` girişi dosyaya dönüştürürken kaynağın V-yukarı koordinatlarını geri verirdi. Bu düzeltmeden önce dönüştürülmüş bir GLB V-yukarı koordinatlar taşır ve dokularını ters çizer; kaynağı yeniden dönüştürün (içe aktarın).

**Bu sayfada:**

- [Native build](#native-build)
- [Native C köprüsü](#native-c-köprüsü)
  - [`src/assimp_bridge.h`](#srcassimp_bridgeh)
- [Dart API](#dart-api)
  - [`lib/flutter_assimp.dart`](#libflutter_assimpdart)
  - [`lib/src/assimp_bindings.dart`](#libsrcassimp_bindingsdart)

## Native build

`hook/build.dart` bridge'i `flutter_assimp` dynamic library'sine derler (code asset `package:flutter_assimp/src/third_party/assimp_c.g.dart`):

- **Paketle gelen kaynaklar** (varsayılan; paket pub.dev'den böyle build olur): `third_party/assimp` altındaki Assimp 5.0 kaynakları (Filament'in patch'li kopyası; derlenen dosyaları `third_party/assimp/sources.txt` listeler, `tool/vendor_assimp.dart <filament checkout>` onları yeniler) bir response file üzerinden tek derleyici çalıştırmasına verilir. FBX, OBJ, Collada, 3DS, PLY, DirectX ve STL dışındaki importer'lar `ASSIMP_BUILD_NO_*_IMPORTER` ile kapatılır, böylece Assimp'in importer registry'si bu yedisini kaydeder; `src/vendored/` glTF 2 exporter'ı glTF header'ları görünür şekilde derler. zlib Windows'ta `third_party/zlib`, diğer platformlarda sistem kütüphanesidir.
- **Filament build'i** (Lumina): `filament_dir`, `out/cmake-release-windows/third_party/libassimp/tnt/assimp.lib` (Windows) ya da `out/cmake-release/third_party/libassimp/tnt/libassimp.a` içeren bir Filament build'ini gösterdiğinde bridge onu link eder, ek importer'ları o checkout'tan derler ve kendisi kaydeder (`FLUTTER_ASSIMP_EXTRA_IMPORTERS`).

## Native C köprüsü

Aşağıdaki C fonksiyonları paketin `src/` header'larında tanımlanır ve Dart'tan FFI ile çağrılır.

### `src/assimp_bridge.h`

| C Fonksiyonu | İmzası | Açıklama ve Ne İşe Yaradığı |
| :--- | :--- | :--- |
| `assimp_get_last_error` | `ASSIMP_EXPORT const char* assimp_get_last_error();` | Son gerçekleşen Assimp dosya okuma veya dönüştürme işleminde oluşan hata metnini döndürür. |
| `assimp_get_import_extensions` | `ASSIMP_EXPORT const char* assimp_get_import_extensions();` | Bridge'in import ettiği dosya uzantıları, Assimp'in listelediği gibi: `"*.fbx;*.obj;*.dae;…"`. |
| `assimp_convert_file_to_glb` | `ASSIMP_EXPORT int assimp_convert_file_to_glb( const char* input_pat...` | Disk üzerindeki herhangi bir 3D model dosyasını (FBX, OBJ, DAE, STL, BLEND vb.) okuyup üçgenleştirerek standart glTF 2.0 (.glb) ikili dosyası olarak kaydeder. |
| `assimp_convert_memory_to_glb` | `ASSIMP_EXPORT int assimp_convert_memory_to_glb( const uint8_t* in_b...` | Bellekteki (RAM) 3D model bayt dizisini belirtilen format ipucuna göre doğrudan glTF 2.0 (.glb) ikili bayt tamponuna dönüştürür. |
| `assimp_free_blob` | `ASSIMP_EXPORT void assimp_free_blob(uint8_t* blob);` | C tarafında tahsis edilen GLB bellek bloğunu serbest bırakarak bellek sızıntısını önler. |

## Dart API

### `lib/flutter_assimp.dart`

#### `class FlutterAssimp`

High-performance native Assimp 3D asset conversion bridge for Dart & Flutter.

**Fonksiyonlar, Metotlar ve Erişimciler:**

| Metot / Getter | İmzası | Ne İşe Yarar? |
| :--- | :--- | :--- |
| `isAvailable` | `static bool get isAvailable` | Returns true if the native Assimp library is loaded and available. |
| `version` | `static String get version` | Returns the underlying native Assimp library version (e.g. "5.0 (commit 4673545f)"). |
| `lastError` | `static String get lastError` | Returns the last error message from native Assimp operations. |
| `importExtensions` | `static Set<String> get importExtensions` | Yüklü bridge'in import ettiği küçük harfli uzantılar (noktasız): FBX, OBJ, Collada (`dae`, `zae`), 3DS (`3ds`, `prj`), PLY, DirectX (`x`) ve STL; hook ister paketle gelen Assimp kaynaklarını derlesin ister bir Filament build'ini link etsin (ek importer kaynaklarını içermeyen eski bir Filament prebuilt'i bridge'i yalnız FBX ve OBJ ile derler). Bridge yoksa: paketin okumak üzere derlendiği formatlar. |
| `isSupportedFormat` | `static bool isSupportedFormat(String pathOrExtension)` | [pathOrExtension] (bir yol, `.ext` ya da `ext`) bridge'in import ettiği bir 3D formatı mı ([importExtensions]). |

### `lib/src/assimp_bindings.dart`

#### `class AssimpBindings`

`AssimpBindings`: İlgili modülün veri modelini veya temel işlevselliğini temsil eden `class` yapısıdır.

**Yapıcı Metotlar (Constructors):**
- `AssimpBindings._init()`: `AssimpBindings._init()` nesnesini ilklendirir.

**Fonksiyonlar, Metotlar ve Erişimciler:**

| Metot / Getter | İmzası | Ne İşe Yarar? |
| :--- | :--- | :--- |
| `isAvailable` | `bool get isAvailable` | Mevcut durumun veya yeteneğin doğruluğunu kontrol eder (`bool` döndürür). |
| `getVersion` | `String getVersion()` | `Version` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `getLastError` | `String getLastError()` | `LastError` bilgisini veya alt nesnesini sorgulayıp döndürür. |

---

[Önceki: Lumina tools dokümantasyonu](../README.tr.md) | [Üst: Lumina tools dokümantasyonu](../README.tr.md) | [Sonraki: flutter_riglogic](flutter_riglogic.md)
