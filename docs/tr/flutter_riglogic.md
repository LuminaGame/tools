[English](../en/flutter_riglogic.md)

# flutter_riglogic

`flutter_riglogic`, Epic Games'in OpenRigLogic kütüphanesini Dart FFI ile bağlar. MetaHuman `.dna` dosyalarını okur ve yüz rig'lerini (PSD'ler, RBF'ler, joint transform'ları ve blend shape ağırlıkları) her frame hesaplar. Dosya yolları `flutter_riglogic/` paket dizinine görelidir.

**Bu sayfada:**

- [Native build](#native-build)
- [Native C köprüsü](#native-c-köprüsü)
  - [`src/riglogic_c.h`](#srcriglogic_ch)
- [Dart API](#dart-api)
  - [`lib/src/bindings.dart`](#libsrcbindingsdart)
  - [`lib/src/dna_reader.dart`](#libsrcdna_readerdart)
  - [`lib/src/rig_instance.dart`](#libsrcrig_instancedart)
  - [`lib/src/rig_logic.dart`](#libsrcrig_logicdart)

## Native build

`hook/build.dart`, `src/riglogic_c.cpp`'yi `flutter_riglogic` dynamic library'sine derler (code asset `package:flutter_riglogic/src/riglogic_native.dart`; `lib/src/riglogic_native.dart` içindeki `@Native` fonksiyonlarla çağrılır; `RigLogicBindings` gerekirse kütüphaneyi yoluyla açmaya düşer):

- **Kaynaktan** (varsayılan; paket pub.dev'den böyle build olur): vendored OpenRigLogic kaynakları (`third_party/openriglogic/src/**/*.cpp`) wrapper ile birlikte, bir response file üzerinden ve altı rotation order'ın hepsi açık olarak derlenir. Android'de libc++ static link edilir.
- **Prebuilt static library**: `third_party/openriglogic/lib` ya da `riglogic_lib_dir` user-define'ı `riglogic.lib` / `libriglogic.a` içeriyorsa (`tool/build_openriglogic*` build eder) yalnızca wrapper derlenir ve kütüphane link edilir. O klasörü `lib/src/hook/riglogic_lib_dir.dart` çözer (pub.dev `hook/build.dart` dışında hook dosyası kabul etmez).

## Native C köprüsü

Aşağıdaki C fonksiyonları paketin `src/` header'larında tanımlanır ve Dart'tan FFI ile çağrılır.

### `src/riglogic_c.h`

| C Fonksiyonu | İmzası | Açıklama ve Ne İşe Yaradığı |
| :--- | :--- | :--- |
| `rl_dna_reader_create_from_file` | `RL_C_API rl_dna_reader_t* rl_dna_reader_create_from_file(const char...` | Disk üzerindeki MetaHuman DNA ikili dosyasını okuyarak DNA reader nesnesi oluşturur. |
| `rl_dna_reader_create_from_memory` | `RL_C_API rl_dna_reader_t* rl_dna_reader_create_from_memory(const vo...` | Bellekteki DNA bayt dizisinden DNA reader nesnesi oluşturur. |
| `rl_dna_reader_destroy` | `RL_C_API void rl_dna_reader_destroy(rl_dna_reader_t* reader);` | DNA reader nesnesini bellekten temizler. |
| `rl_dna_reader_get_name` | `RL_C_API const char* rl_dna_reader_get_name(const rl_dna_reader_t* ...` | DNA dosyasındaki karakter veya rig adını döndürür. |
| `rl_dna_reader_get_lod_count` | `RL_C_API uint16_t rl_dna_reader_get_lod_count(const rl_dna_reader_t...` | Karakterin tanımlı detay seviyesi (LOD) sayısını döndürür. |
| `rl_dna_reader_get_joint_count` | `RL_C_API uint16_t rl_dna_reader_get_joint_count(const rl_dna_reader...` | Karakter iskeletindeki toplam eklem/kemik sayısını döndürür. |
| `rl_dna_reader_get_joint_name` | `RL_C_API const char* rl_dna_reader_get_joint_name(const rl_dna_read...` | Belirtilen indisteki eklem/kemik adını döndürür. |
| `rl_dna_reader_get_blend_shape_channel_count` | `RL_C_API uint16_t rl_dna_reader_get_blend_shape_channel_count(const...` | Toplam morph target / blend shape kanal sayısını döndürür. |
| `rl_dna_reader_get_blend_shape_channel_name` | `RL_C_API const char* rl_dna_reader_get_blend_shape_channel_name(con...` | Belirtilen indisteki blend shape kanal adını döndürür. |
| `rl_dna_reader_get_raw_control_count` | `RL_C_API uint16_t rl_dna_reader_get_raw_control_count(const rl_dna_...` | Ham kontrolcü (raw control) kanal sayısını döndürür. |
| `rl_dna_reader_get_raw_control_name` | `RL_C_API const char* rl_dna_reader_get_raw_control_name(const rl_dn...` | Belirtilen indisteki mimik kontrol kanalının adını döndürür. |
| `rl_dna_reader_get_gui_control_count` | `RL_C_API uint16_t rl_dna_reader_get_gui_control_count(const rl_dna_...` | GUI kontrolcü sayısını döndürür. |
| `rl_dna_reader_get_gui_control_name` | `RL_C_API const char* rl_dna_reader_get_gui_control_name(const rl_dn...` | Belirtilen indisteki GUI kontrol kanal adını döndürür. |
| `rl_dna_reader_get_animated_map_count` | `RL_C_API uint16_t rl_dna_reader_get_animated_map_count(const rl_dna...` | Kırışıklık haritası (animated normal map) sayısını döndürür. |
| `rl_dna_reader_get_animated_map_name` | `RL_C_API const char* rl_dna_reader_get_animated_map_name(const rl_d...` | Belirtilen kırışıklık haritası adını döndürür. |
| `rl_riglogic_create` | `RL_C_API rl_riglogic_t* rl_riglogic_create(rl_dna_reader_t* reader);` | DNA okuyucu verisinden makine öğrenimi ve deformasyon motoru olan RigLogic örneğini inşa eder. |
| `rl_riglogic_destroy` | `RL_C_API void rl_riglogic_destroy(rl_riglogic_t* rl);` | RigLogic motor nesnesini bellekten temizler. |
| `rl_riglogic_calculate` | `RL_C_API void rl_riglogic_calculate(rl_riglogic_t* rl, rl_riginstan...` | Girdi kontrol değerlerine göre rig örneğinin kemik dönüşümlerini ve blend shape ağırlıklarını hesaplar. |
| `rl_riginstance_create` | `RL_C_API rl_riginstance_t* rl_riginstance_create(rl_riglogic_t* rl);` | Belirtilen RigLogic motoru için bağımsız bir karakter çalışma zamanı örneği (instance) oluşturur. |
| `rl_riginstance_destroy` | `RL_C_API void rl_riginstance_destroy(rl_riginstance_t* inst);` | RigInstance örneğini bellekten temizler. |
| `rl_riginstance_get_raw_control_count` | `RL_C_API uint16_t rl_riginstance_get_raw_control_count(const rl_rig...` | Örnekteki kontrol kanalı sayısını döndürür. |
| `rl_riginstance_get_raw_control` | `RL_C_API float rl_riginstance_get_raw_control(const rl_riginstance_...` | Belirtilen indisteki kontrol değerini (0.0 - 1.0) okur. |
| `rl_riginstance_set_raw_control` | `RL_C_API void rl_riginstance_set_raw_control(rl_riginstance_t* inst...` | Belirtilen kontrol kanalına yeni bir mimik giriş değeri atar. |
| `rl_riginstance_get_lod` | `RL_C_API uint16_t rl_riginstance_get_lod(const rl_riginstance_t* in...` | RigInstance'ın anlık LOD seviyesini döndürür. |
| `rl_riginstance_set_lod` | `RL_C_API void rl_riginstance_set_lod(rl_riginstance_t* inst, uint16...` | RigInstance'ın anlık LOD seviyesini günceller. |
| `rl_riginstance_get_joint_outputs` | `RL_C_API uint32_t rl_riginstance_get_joint_outputs(const rl_riginst...` | Hesaplanmış 3B kemik konum, rotasyon ve ölçek dizisini döndürür. |
| `rl_riginstance_get_blend_shape_outputs` | `RL_C_API uint32_t rl_riginstance_get_blend_shape_outputs(const rl_r...` | Hesaplanmış blend shape katsayı dizisini döndürür. |
| `rl_riginstance_get_animated_map_outputs` | `RL_C_API uint32_t rl_riginstance_get_animated_map_outputs(const rl_...` | Hesaplanmış kırışıklık haritası katsayılarını döndürür. |

## Dart API

### `lib/src/bindings.dart`

**Üst Düzey Fonksiyonlar (Top-level Functions):**

- **`Pointer<RlDnaReader> Function(Pointer<Utf8> path)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<RlDnaReader> Function(Pointer<Utf8> path)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<RlDnaReader> Function(Pointer<Uint8> data, IntPtr size)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<RlDnaReader> Function(Pointer<Uint8> data, int size)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`int Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: `Function` işlemini gerçekleştirir.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`int Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: `Function` işlemini gerçekleştirir.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`int Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: `Function` işlemini gerçekleştirir.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`int Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: `Function` işlemini gerçekleştirir.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`int Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<RlRigLogic> Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<RlRigLogic> Function(Pointer<RlDnaReader> reader)`**: `Function` işlemini gerçekleştirir.
- **`Void Function(Pointer<RlRigLogic> rl, Pointer<RlRigInstance> inst)`**: `Function` işlemini gerçekleştirir.
- **`void Function(Pointer<RlRigLogic> rl, Pointer<RlRigInstance> inst)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<RlRigInstance> Function(Pointer<RlRigLogic> rl)`**: `Function` işlemini gerçekleştirir.
- **`Pointer<RlRigInstance> Function(Pointer<RlRigLogic> rl)`**: `Function` işlemini gerçekleştirir.
- **`Uint16 Function(Pointer<RlRigInstance> inst)`**: `Function` işlemini gerçekleştirir.
- **`int Function(Pointer<RlRigInstance> inst)`**: `Function` işlemini gerçekleştirir.
- **`Float Function(Pointer<RlRigInstance> inst, Uint16 index)`**: `Function` işlemini gerçekleştirir.
- **`double Function(Pointer<RlRigInstance> inst, int index)`**: `Function` işlemini gerçekleştirir.
- **`Void Function(Pointer<RlRigInstance> inst, Uint16 index, Float value)`**: `Function` işlemini gerçekleştirir.
- **`void Function(Pointer<RlRigInstance> inst, int index, double value)`**: `Function` işlemini gerçekleştirir.
- **`Void Function(Pointer<RlRigInstance> inst, Uint16 lod)`**: `Function` işlemini gerçekleştirir.
- **`void Function(Pointer<RlRigInstance> inst, int lod)`**: `Function` işlemini gerçekleştirir.
- **`int Function(Pointer<RlRigInstance> inst, Pointer<Pointer<Float>> outData)`**: `Function` işlemini gerçekleştirir.

#### `class RlDnaReader`

`RlDnaReader`: İlgili modülün veri modelini veya temel işlevselliğini temsil eden `class` yapısıdır.

#### `class RlRigLogic`

`RlRigLogic`: İlgili modülün veri modelini veya temel işlevselliğini temsil eden `class` yapısıdır.

#### `class RlRigInstance`

`RlRigInstance`: İlgili modülün veri modelini veya temel işlevselliğini temsil eden `class` yapısıdır.

#### `class RigLogicBindings`

`RigLogicBindings`: İlgili modülün veri modelini veya temel işlevselliğini temsil eden `class` yapısıdır.

**Yapıcı Metotlar (Constructors):**
- `RigLogicBindings._init()`: `RigLogicBindings._init()` nesnesini ilklendirir.

**Fonksiyonlar, Metotlar ve Erişimciler:**

| Metot / Getter | İmzası | Ne İşe Yarar? |
| :--- | :--- | :--- |
| `dnaReaderCreateFromFile` | `final RlDnaReaderCreateFromFileDart dnaReaderCreateFromFile` | `dnaReaderCreateFromFile` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderCreateFromMemory` | `final RlDnaReaderCreateFromMemoryDart dnaReaderCreateFromMemory` | `dnaReaderCreateFromMemory` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderDestroy` | `final RlDnaReaderDestroyDart dnaReaderDestroy` | `dnaReaderDestroy` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetName` | `final RlDnaReaderGetNameDart dnaReaderGetName` | `dnaReaderGetName` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetLodCount` | `final RlDnaReaderGetLodCountDart dnaReaderGetLodCount` | `dnaReaderGetLodCount` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetJointCount` | `final RlDnaReaderGetJointCountDart dnaReaderGetJointCount` | `dnaReaderGetJointCount` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetJointName` | `final RlDnaReaderGetJointNameDart dnaReaderGetJointName` | `dnaReaderGetJointName` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetBlendShapeChannelCount` | `dnaReaderGetBlendShapeChannelCount` | `dnaReaderGetBlendShapeChannelCount` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetBlendShapeChannelName` | `dnaReaderGetBlendShapeChannelName` | `dnaReaderGetBlendShapeChannelName` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetRawControlCount` | `final RlDnaReaderGetRawControlCountDart dnaReaderGetRawControlCount` | `dnaReaderGetRawControlCount` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetRawControlName` | `final RlDnaReaderGetRawControlNameDart dnaReaderGetRawControlName` | `dnaReaderGetRawControlName` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetGuiControlCount` | `final RlDnaReaderGetGuiControlCountDart dnaReaderGetGuiControlCount` | `dnaReaderGetGuiControlCount` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetGuiControlName` | `final RlDnaReaderGetGuiControlNameDart dnaReaderGetGuiControlName` | `dnaReaderGetGuiControlName` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetAnimatedMapCount` | `final RlDnaReaderGetAnimatedMapCountDart dnaReaderGetAnimatedMapCount` | `dnaReaderGetAnimatedMapCount` alanını (field/property) ve ilişkili veriyi saklar. |
| `dnaReaderGetAnimatedMapName` | `final RlDnaReaderGetAnimatedMapNameDart dnaReaderGetAnimatedMapName` | `dnaReaderGetAnimatedMapName` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigLogicCreate` | `final RlRigLogicCreateDart rigLogicCreate` | `rigLogicCreate` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigLogicDestroy` | `final RlRigLogicDestroyDart rigLogicDestroy` | `rigLogicDestroy` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigLogicCalculate` | `final RlRigLogicCalculateDart rigLogicCalculate` | `rigLogicCalculate` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceCreate` | `final RlRigInstanceCreateDart rigInstanceCreate` | `rigInstanceCreate` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceDestroy` | `final RlRigInstanceDestroyDart rigInstanceDestroy` | `rigInstanceDestroy` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceGetRawControlCount` | `final RlRigInstanceGetRawControlCountDart rigInstanceGetRawControlCount` | `rigInstanceGetRawControlCount` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceGetRawControl` | `final RlRigInstanceGetRawControlDart rigInstanceGetRawControl` | `rigInstanceGetRawControl` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceSetRawControl` | `final RlRigInstanceSetRawControlDart rigInstanceSetRawControl` | `rigInstanceSetRawControl` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceGetLod` | `final RlRigInstanceGetLodDart rigInstanceGetLod` | `rigInstanceGetLod` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceSetLod` | `final RlRigInstanceSetLodDart rigInstanceSetLod` | `rigInstanceSetLod` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceGetJointOutputs` | `final RlRigInstanceGetOutputsDart rigInstanceGetJointOutputs` | `rigInstanceGetJointOutputs` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceGetBlendShapeOutputs` | `final RlRigInstanceGetOutputsDart rigInstanceGetBlendShapeOutputs` | `rigInstanceGetBlendShapeOutputs` alanını (field/property) ve ilişkili veriyi saklar. |
| `rigInstanceGetAnimatedMapOutputs` | `final RlRigInstanceGetOutputsDart rigInstanceGetAnimatedMapOutputs` | `rigInstanceGetAnimatedMapOutputs` alanını (field/property) ve ilişkili veriyi saklar. |
| `isAvailable` | `bool get isAvailable` | Mevcut durumun veya yeteneğin doğruluğunu kontrol eder (`bool` döndürür). |

### `lib/src/dna_reader.dart`

#### `class DnaReader`

Reads MetaHuman DNA files containing joint hierarchy, blend shape mappings, and rig behavior parameters.

**Yapıcı Metotlar (Constructors):**
- `DnaReader._(this._handle)`: `DnaReader._(this._handle)` nesnesini ilklendirir.
- `DnaReader.fromFile(String path)`: Creates a [DnaReader] from a DNA file on disk.
- `DnaReader.fromMemory(Uint8List bytes)`: Creates a [DnaReader] from an in-memory byte buffer.

**Fonksiyonlar, Metotlar ve Erişimciler:**

| Metot / Getter | İmzası | Ne İşe Yarar? |
| :--- | :--- | :--- |
| `handle` | `Pointer<RlDnaReader> get handle` | Olayı, girdiyi veya kullanıcı eylemini işler. |
| `name` | `String get name` | `name` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `lodCount` | `int get lodCount` | `lodCount` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `jointCount` | `int get jointCount` | `jointCount` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `getJointName` | `String getJointName(int index)` | `JointName` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `blendShapeChannelCount` | `int get blendShapeChannelCount` | `blendShapeChannelCount` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `getBlendShapeChannelName` | `String getBlendShapeChannelName(int index)` | `BlendShapeChannelName` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `rawControlCount` | `int get rawControlCount` | `rawControlCount` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `getRawControlName` | `String getRawControlName(int index)` | `RawControlName` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `guiControlCount` | `int get guiControlCount` | `guiControlCount` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `getGuiControlName` | `String getGuiControlName(int index)` | `GuiControlName` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `animatedMapCount` | `int get animatedMapCount` | `animatedMapCount` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `getAnimatedMapName` | `String getAnimatedMapName(int index)` | `AnimatedMapName` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `dispose` | `void dispose()` | Yerel FFI göstericilerini, dinleyicileri ve bellek bloklarını serbest bırakır. |

### `lib/src/rig_instance.dart`

#### `class RigInstance`

An instance of a rig driven by [RigLogic], containing runtime state, control inputs, and calculated joint transforms and blend shape outputs.

**Yapıcı Metotlar (Constructors):**
- `RigInstance._(this._handle)`: `RigInstance._(this._handle)` nesnesini ilklendirir.
- `RigInstance.create(RigLogic rigLogic)`: `RigInstance.create(RigLogic rigLogic)` nesnesini ilklendirir.

**Fonksiyonlar, Metotlar ve Erişimciler:**

| Metot / Getter | İmzası | Ne İşe Yarar? |
| :--- | :--- | :--- |
| `handle` | `Pointer<RlRigInstance> get handle` | Olayı, girdiyi veya kullanıcı eylemini işler. |
| `rawControlCount` | `int get rawControlCount` | `rawControlCount` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `getRawControl` | `double getRawControl(int index) => RigLogicBindings.instance.rigInstance...` | `RawControl` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `setRawControl` | `void setRawControl(int index, double value)` | `RawControl` parametresini günceller ve sisteme uygular. |
| `lod` | `int get lod` | `lod` özelliğinin anlık değerini okuyan getter erişimcisi. |
| `lod` | `lod(int value) => RigLogicBindings.instance.rigInstanceSetLod(handle, va...` | `lod` işlemini gerçekleştirir. |
| `getJointOutputs` | `List<double> getJointOutputs()` | `JointOutputs` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `getBlendShapeOutputs` | `List<double> getBlendShapeOutputs()` | `BlendShapeOutputs` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `getAnimatedMapOutputs` | `List<double> getAnimatedMapOutputs()` | `AnimatedMapOutputs` bilgisini veya alt nesnesini sorgulayıp döndürür. |
| `dispose` | `void dispose()` | Yerel FFI göstericilerini, dinleyicileri ve bellek bloklarını serbest bırakır. |

### `lib/src/rig_logic.dart`

#### `class RigLogic`

Evaluates MetaHuman facial rigs using machine-learned behavior, PSDs (Pose-Space Deformers), and RBFs.

**Yapıcı Metotlar (Constructors):**
- `RigLogic._(this._handle)`: `RigLogic._(this._handle)` nesnesini ilklendirir.
- `RigLogic.create(DnaReader reader)`: `RigLogic.create(DnaReader reader)` nesnesini ilklendirir.

**Fonksiyonlar, Metotlar ve Erişimciler:**

| Metot / Getter | İmzası | Ne İşe Yarar? |
| :--- | :--- | :--- |
| `handle` | `Pointer<RlRigLogic> get handle` | Olayı, girdiyi veya kullanıcı eylemini işler. |
| `calculate` | `void calculate(RigInstance instance)` | Girdi verilerini matematiksel olarak işleyerek deformasyon, matris veya kemik dönüşümlerini hesaplar. |
| `dispose` | `void dispose()` | Yerel FFI göstericilerini, dinleyicileri ve bellek bloklarını serbest bırakır. |

---

[Önceki: flutter_assimp](flutter_assimp.md) | [Üst: Lumina tools dokümantasyonu](../README.tr.md) | [Sonraki: flutter_gstreamer](flutter_gstreamer.md)
