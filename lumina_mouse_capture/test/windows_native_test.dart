@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Windows plugin's capture state machine, built with CMake and run
/// against its fake OS layer (`windows/test/pointer_capture_test.cpp`). The
/// test executable links only the state machine, never the Win32 layer, so
/// nothing here can clip, hide or move the pointer.
void main() {
  final packageDir = Directory.current.path;
  final windowsDir = '$packageDir${Platform.pathSeparator}windows';

  test('the state machine calls no Win32 pointer function itself', () {
    final source = File('$windowsDir${Platform.pathSeparator}pointer_capture.cpp').readAsStringSync();
    for (final call in [
      'ClipCursor(',
      'SetCursorPos(',
      'ShowCursor(',
      'RegisterRawInputDevices(',
      'GetRawInputData(',
      'SetCapture(',
      'GetCursorPos(',
    ]) {
      expect(source.contains(call), isFalse, reason: 'pointer_capture.cpp must go through PointerOs, not $call');
    }
  });

  test(
    'the capture state machine passes against the fake OS layer',
    () async {
      final cmake = _findCmake();
      if (cmake == null) {
        markTestSkipped('cmake not found (PATH or Visual Studio)');
        return;
      }
      final build = Directory.systemTemp.createTempSync('lmc_win_');
      addTearDown(() {
        try {
          build.deleteSync(recursive: true);
        } on FileSystemException {
          // A virus scanner may still hold the executable.
        }
      });
      final configure = await Process.run(cmake, ['-S', '$windowsDir${Platform.pathSeparator}test', '-B', build.path]);
      expect(configure.exitCode, 0, reason: '${configure.stdout}\n${configure.stderr}');
      final compile = await Process.run(cmake, ['--build', build.path, '--config', 'Debug']);
      expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');

      final exe = [
        '${build.path}${Platform.pathSeparator}Debug${Platform.pathSeparator}pointer_capture_tests.exe',
        '${build.path}${Platform.pathSeparator}pointer_capture_tests.exe',
      ].firstWhere((p) => File(p).existsSync(), orElse: () => '');
      expect(exe, isNotEmpty, reason: 'pointer_capture_tests.exe was not built');
      final run = await Process.run(exe, const []);
      final output = '${run.stdout}';
      printOnFailure(output);
      expect(run.exitCode, 0, reason: output);
      for (final name in [
        'capture locks: position saved, raw input, cursor hidden, clipped',
        'relative samples become one motion per flush',
        'absolute samples become deltas',
        'focus loss reports lost and restores the cursor',
        'minimise and destroy report lost',
        'release is idempotent',
        'teardown releases',
        'refused captures touch nothing',
        'display and DPI changes re-clip',
      ]) {
        expect(output, contains('PASS $name'));
      }
      expect(output, contains(' 0 failed'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// cmake on PATH, or the one Visual Studio ships.
String? _findCmake() {
  final onPath = Process.runSync('where', ['cmake'], runInShell: true);
  if (onPath.exitCode == 0) {
    final first = '${onPath.stdout}'.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (first.isNotEmpty) return first.trim();
  }
  final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
  final vswhere = '$programFilesX86\\Microsoft Visual Studio\\Installer\\vswhere.exe';
  if (!File(vswhere).existsSync()) return null;
  final found = Process.runSync(vswhere, ['-latest', '-products', '*', '-property', 'installationPath']);
  final install = '${found.stdout}'.trim();
  if (found.exitCode != 0 || install.isEmpty) return null;
  final cmake = '$install\\Common7\\IDE\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin\\cmake.exe';
  return File(cmake).existsSync() ? cmake : null;
}
