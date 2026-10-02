import 'dart:io';

import 'package:flutter_kimodo/flutter_kimodo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KimodoRuntime', () {
    test('loads the bundled kimodo library with its ggml backends', () {
      KimodoRuntime.open();
      expect(KimodoRuntime.isOpen, isTrue);
      expect(KimodoRuntime.abiVersion, 1);
      expect(KimodoRuntime.backends, contains('cpu'));
      final path = KimodoRuntime.libraryPath;
      expect(
        path,
        endsWith(Platform.isWindows ? 'kimodo.dll' : 'libkimodo.so'),
      );
      expect(File(path).existsSync(), isTrue);
    });

    test('lists the Vulkan devices of the system loader by name', () {
      final devices = KimodoRuntime.vulkanDevices();
      if (devices.isEmpty) {
        markTestSkipped('no Vulkan loader or device on this machine');
        return;
      }
      for (final d in devices) {
        expect(d.name, isNotEmpty);
        expect(d.index, devices.indexOf(d));
      }
      final wanted = Platform.environment['FILAMENT_GPU'] ?? 'RTX PRO 2000';
      final found = KimodoRuntime.findVulkanDevice(wanted.toLowerCase());
      if (found == null) {
        markTestSkipped('no Vulkan device named "$wanted": $devices');
        return;
      }
      expect(found.name.toLowerCase(), contains(wanted.toLowerCase()));
      expect(found.isDiscrete, isTrue);
    });

    test('configures the CPU backend; Vulkan needs a Vulkan build', () {
      expect(
        () => KimodoRuntime.configure(
          const KimodoBackend(device: KimodoDevice.cpu, threads: 4),
        ),
        returnsNormally,
      );
      if (KimodoRuntime.hasVulkan) {
        expect(
          () => KimodoRuntime.configure(
            const KimodoBackend(
              device: KimodoDevice.vulkan,
              vulkanDeviceName: 'no such gpu 0000',
            ),
          ),
          throwsA(
            isA<KimodoException>().having(
              (e) => e.message,
              'message',
              contains('no such gpu'),
            ),
          ),
        );
      } else {
        expect(
          () => KimodoRuntime.configure(
            const KimodoBackend(device: KimodoDevice.vulkan),
          ),
          throwsA(
            isA<KimodoException>().having(
              (e) => e.message,
              'message',
              contains('Vulkan'),
            ),
          ),
        );
      }
      KimodoRuntime.configure(const KimodoBackend());
    });
  });

  group('KimodoBackend.fromEnvironment', () {
    test('reads the device, threads and Vulkan device name', () {
      final b = KimodoBackend.fromEnvironment({
        'KIMODO_DEVICE': 'cpu',
        'KIMODO_THREADS': '6',
        'KIMODO_VULKAN_DEVICE': 'RTX PRO 2000',
      });
      expect(b.device, KimodoDevice.cpu);
      expect(b.threads, 6);
      expect(b.vulkanDeviceName, 'RTX PRO 2000');
    });

    test('falls back to the GPU Lumina renders on, then to the defaults', () {
      final b = KimodoBackend.fromEnvironment({'FILAMENT_GPU': 'RTX PRO 2000'});
      expect(b.device, KimodoDevice.auto);
      expect(b.vulkanDeviceName, 'RTX PRO 2000');
      final d = KimodoBackend.fromEnvironment(const {});
      expect(d.device, KimodoDevice.auto);
      expect(d.threads, 0);
      expect(d.vulkanDeviceName, isNull);
    });
  });
}
