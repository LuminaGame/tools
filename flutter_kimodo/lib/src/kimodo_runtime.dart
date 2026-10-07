import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:flutter_kimodo/src/bindings/flutter_kimodo_bindings.g.dart' as b;
import 'package:flutter_kimodo/src/kimodo_exception.dart';

/// Where kimodo runs.
enum KimodoDevice {
  /// Vulkan when the build has it and a device exists, else the CPU.
  auto,
  cpu,
  vulkan,
}

/// A Vulkan physical device as the system Vulkan loader lists it.
class KimodoVulkanDevice {
  /// Index in `vkEnumeratePhysicalDevices` order (what
  /// `GGML_VK_VISIBLE_DEVICES` indexes).
  final int index;
  final String name;

  /// `VkPhysicalDeviceType`: 1 integrated, 2 discrete, 3 virtual, 4 CPU.
  final int type;

  const KimodoVulkanDevice(this.index, this.name, this.type);

  bool get isDiscrete => type == 2;

  @override
  String toString() => '#$index $name${isDiscrete ? ' (discrete)' : ''}';
}

/// The backend a process loads its Kimodo models on.
class KimodoBackend {
  final KimodoDevice device;

  /// CPU threads; 0 uses every core.
  final int threads;

  /// Picks the Vulkan device whose name contains this (case-insensitive),
  /// for example `RTX PRO 2000`; null leaves GGML's choice (the first
  /// dedicated GPU).
  final String? vulkanDeviceName;

  const KimodoBackend({
    this.device = KimodoDevice.auto,
    this.threads = 0,
    this.vulkanDeviceName,
  });

  /// From the environment: `KIMODO_DEVICE` (`auto`, `cpu`, `vulkan`),
  /// `KIMODO_THREADS`, and the Vulkan device name from
  /// `KIMODO_VULKAN_DEVICE`, else `FILAMENT_GPU` (the GPU Lumina renders on).
  factory KimodoBackend.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final device = switch (env['KIMODO_DEVICE']?.toLowerCase()) {
      'cpu' => KimodoDevice.cpu,
      'vulkan' => KimodoDevice.vulkan,
      _ => KimodoDevice.auto,
    };
    final name = env['KIMODO_VULKAN_DEVICE'] ?? env['FILAMENT_GPU'];
    return KimodoBackend(
      device: device,
      threads: int.tryParse(env['KIMODO_THREADS'] ?? '') ?? 0,
      vulkanDeviceName: name == null || name.isEmpty ? null : name,
    );
  }

  @override
  String toString() =>
      'KimodoBackend(${device.name}, threads: $threads, vulkan: ${vulkanDeviceName ?? 'default'})';
}

/// The kimodo runtime of this process: loads the prebuilt kimodo library
/// (bundled next to flutter_kimodo by the native-assets hook) and holds the
/// process-wide backend settings. Every call is synchronous and cheap;
/// generation runs through `KimodoModel` on a background isolate.
abstract final class KimodoRuntime {
  static const int _errLen = 2048;

  /// Loads kimodo: from [runtimeDir], `LUMINA_KIMODO_RUNTIME_DIR`, or the
  /// folder holding flutter_kimodo (the bundled copy). Idempotent.
  static void open({String? runtimeDir}) {
    if (b.flutter_kimodo_is_open() != 0) return;
    final dir = runtimeDir ?? Platform.environment['LUMINA_KIMODO_RUNTIME_DIR'];
    using((arena) {
      final err = arena<Char>(_errLen);
      final path = dir == null || dir.isEmpty
          ? nullptr
          : dir.toNativeUtf8(allocator: arena).cast<Char>();
      if (b.flutter_kimodo_open(path, err, _errLen) == 0) {
        throw KimodoException(
          'Loading the kimodo runtime failed: ${err.cast<Utf8>().toDartString()}',
        );
      }
    });
  }

  static bool get isOpen => b.flutter_kimodo_is_open() != 0;

  /// The loaded kimodo library's path.
  static String get libraryPath {
    open();
    return b.flutter_kimodo_library_path().cast<Utf8>().toDartString();
  }

  /// The kimodo C ABI version of the loaded library.
  static int get abiVersion {
    open();
    return b.flutter_kimodo_abi_version();
  }

  /// The backends compiled into the loaded library (`cpu`, `vulkan`).
  static List<String> get backends {
    open();
    final text = b.flutter_kimodo_backends().cast<Utf8>().toDartString();
    return [
      for (final s in text.split(','))
        if (s.trim().isNotEmpty) s.trim(),
    ];
  }

  static bool get hasVulkan => backends.contains('vulkan');

  /// The Vulkan devices of the system loader (empty without one); needs no
  /// kimodo library.
  static List<KimodoVulkanDevice> vulkanDevices() {
    final count = b.flutter_kimodo_vulkan_device_count();
    return using((arena) {
      final buf = arena<Char>(256);
      return [
        for (var i = 0; i < count; i++)
          if (b.flutter_kimodo_vulkan_device_name(i, buf, 256) >= 0)
            KimodoVulkanDevice(
              i,
              buf.cast<Utf8>().toDartString(),
              b.flutter_kimodo_vulkan_device_type(i),
            ),
      ];
    });
  }

  /// The first Vulkan device whose name contains [name]
  /// (case-insensitive), or null.
  static KimodoVulkanDevice? findVulkanDevice(String name) {
    final needle = name.toLowerCase();
    for (final d in vulkanDevices()) {
      if (d.name.toLowerCase().contains(needle)) return d;
    }
    return null;
  }

  /// Applies [backend] to the process. GGML reads the Vulkan device list
  /// once, at the first model load, so call this before it; later calls
  /// change the CPU / Vulkan choice and the thread count but not the device.
  ///
  /// A [KimodoBackend.vulkanDeviceName] no device matches is ignored on
  /// [KimodoDevice.auto] and an error on [KimodoDevice.vulkan].
  static void configure(KimodoBackend backend) {
    open();
    if (backend.device == KimodoDevice.vulkan && !hasVulkan) {
      throw const KimodoException(
        'This kimodo build has no Vulkan backend (rebuild it with the Vulkan SDK installed).',
      );
    }
    var index = -1;
    final name = backend.vulkanDeviceName;
    if (name != null && backend.device != KimodoDevice.cpu && hasVulkan) {
      final found = findVulkanDevice(name);
      if (found != null) {
        index = found.index;
      } else if (backend.device == KimodoDevice.vulkan) {
        throw KimodoException(
          'No Vulkan device matches "$name" (found: ${vulkanDevices().join(', ')}).',
        );
      }
    }
    using((arena) {
      final err = arena<Char>(_errLen);
      if (b.flutter_kimodo_configure(
            backend.device.index,
            backend.threads,
            index,
            err,
            _errLen,
          ) ==
          0) {
        throw KimodoException(
          'Configuring kimodo failed: ${err.cast<Utf8>().toDartString()}',
        );
      }
    });
  }
}
