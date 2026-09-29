[English](../en/flutter_assimp.md)

# flutter_assimp

`flutter_assimp`, Open Asset Import Library'yi (Assimp) Dart FFI ile bağlar ve 40'tan fazla 3D formatı (FBX, OBJ, DAE, STL, Blend ve diğerleri) diskte ya da bellekte, Lumina engine'inin yüklediği format olan binary glTF 2.0'a (`.glb`) dönüştürür. Dosya yolları `flutter_assimp/` paket dizinine görelidir.

**Bu sayfada:**

- [Native C köprüsü](#native-c-köprüsü)
  - [`src/assimp_bridge.h`](#srcassimp_bridgeh)
- [Dart API](#dart-api)
  - [`lib/flutter_assimp.dart`](#libflutter_assimpdart)
  - [`lib/src/assimp_bindings.dart`](#libsrcassimp_bindingsdart)

## Native C köprüsü

Aşağıdaki C fonksiyonları paketin `src/` header'larında tanımlanır ve Dart'tan FFI ile çağrılır.

### `src/assimp_bridge.h`

| C Fonksiyonu | İmzası | Açıklama ve Ne İşe Yaradığı |
| :--- | :--- | :--- |
| `assimp_get_last_error` | `ASSIMP_EXPORT const char* assimp_get_last_error();` | Son gerçekleşen Assimp dosya okuma veya dönüştürme işleminde oluşan hata metnini döndürür. |
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
| `version` | `static String get version` | Returns the underlying native Assimp library version (e.g. "6.0.5"). |
| `lastError` | `static String get lastError` | Returns the last error message from native Assimp operations. |
| `isSupportedFormat` | `static bool isSupportedFormat(String pathOrExtension)` | Checks if a file path or extension is a supported 3D import format. |

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
