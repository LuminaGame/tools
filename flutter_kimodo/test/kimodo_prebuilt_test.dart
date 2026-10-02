import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_kimodo/flutter_kimodo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Packs a real archive the way tool/build_kimodo.* does (one top folder,
/// `tar`, a `sha256sum`-format sidecar) into `<work>/dist`.
Future<File> _pack(Directory work, String version, String os) async {
  final name = KimodoPrebuilt.baseName(version, os);
  final stage = Directory(p.join(work.path, 'stage', name));
  File(p.join(stage.path, KimodoPrebuilt.marker(os)))
    ..createSync(recursive: true)
    ..writeAsStringSync('not a real library');
  File(
    p.join(stage.path, 'lumina-kimodo.json'),
  ).writeAsStringSync('{"version": "$version"}');
  final dist = Directory(p.join(work.path, 'dist'))..createSync();
  final archive = File(
    p.join(dist.path, KimodoPrebuilt.archiveName(version, os)),
  );
  final tar = Platform.isWindows
      ? p.join(Platform.environment['SystemRoot']!, 'System32', 'tar.exe')
      : 'tar';
  final result = await Process.run(tar, [
    if (os == 'windows') ...['-a', '-c', '-f'] else '-czf',
    archive.path,
    name,
  ], workingDirectory: stage.parent.path);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  final hash = sha256.convert(archive.readAsBytesSync());
  File(
    '${archive.path}.sha256',
  ).writeAsStringSync('$hash  ${p.basename(archive.path)}\n');
  return archive;
}

void main() {
  late Directory work;
  setUp(() => work = Directory.systemTemp.createTempSync('kimodo_prebuilt'));
  tearDown(() => work.deleteSync(recursive: true));

  final os = KimodoPrebuilt.hostOs();

  test('names archives per platform and release', () {
    expect(
      KimodoPrebuilt.archiveName('5679ff1-lumina.1', 'windows'),
      'kimodo-5679ff1-lumina.1-windows-x64.zip',
    );
    expect(
      KimodoPrebuilt.archiveName('5679ff1-lumina.1', 'linux'),
      'kimodo-5679ff1-lumina.1-linux-x64.tar.gz',
    );
    expect(
      KimodoPrebuilt.archiveUri('5679ff1-lumina.1', 'windows').toString(),
      'https://github.com/LuminaGame/tools/releases/download/'
      'kimodo-5679ff1-lumina.1/kimodo-5679ff1-lumina.1-windows-x64.zip',
    );
  });

  test('installs a local archive after checking its SHA-256', () async {
    await _pack(work, '1.0-test', os);
    final dir = await KimodoPrebuilt.ensure(version: '1.0-test', work: work);
    expect(dir.path, KimodoPrebuilt.installDir(work, '1.0-test', os).path);
    expect(
      File(p.join(dir.path, KimodoPrebuilt.marker(os))).readAsStringSync(),
      'not a real library',
    );
    // Installed: kept, even once the archive is gone.
    File(
      p.join(work.path, 'dist', KimodoPrebuilt.archiveName('1.0-test', os)),
    ).deleteSync();
    expect(
      (await KimodoPrebuilt.ensure(version: '1.0-test', work: work)).path,
      dir.path,
    );
  });

  test('refuses an archive whose SHA-256 does not match', () async {
    final archive = await _pack(work, '1.0-test', os);
    File(
      '${archive.path}.sha256',
    ).writeAsStringSync('${'0' * 64}  ${p.basename(archive.path)}\n');
    await expectLater(
      KimodoPrebuilt.ensure(version: '1.0-test', work: work),
      throwsA(
        isA<KimodoPrebuiltException>().having(
          (e) => e.message,
          'message',
          contains('SHA-256 mismatch'),
        ),
      ),
    );
    expect(
      KimodoPrebuilt.installDir(work, '1.0-test', os).existsSync(),
      isFalse,
    );
  });

  test('the locally built prebuilt is installed with its checksum', () async {
    final package = Directory.current.path;
    final version = File(
      p.join(package, 'tool', 'kimodo', 'VERSION'),
    ).readAsStringSync().trim();
    final local = Directory(p.join(package, 'third_party', 'kimodo'));
    final archive = File(
      p.join(local.path, 'dist', KimodoPrebuilt.archiveName(version, os)),
    );
    if (!archive.existsSync()) {
      markTestSkipped('no local build: run tool/build_kimodo.ps1 or .sh');
      return;
    }
    expect(await KimodoPrebuilt.verify(archive), hasLength(64));
    final installed = KimodoPrebuilt.installDir(local, version, os);
    expect(
      File(p.join(installed.path, KimodoPrebuilt.marker(os))).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(installed.path, 'include', 'kimodo_lumina.h')).existsSync(),
      isTrue,
    );
  });
}
