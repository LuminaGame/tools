import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A prebuilt kimodo archive could not be found, verified or unpacked.
class KimodoPrebuiltException implements Exception {
  final String message;
  const KimodoPrebuiltException(this.message);

  @override
  String toString() => 'KimodoPrebuiltException: $message';
}

/// The prebuilt kimodo runtime (kimodo + ggml shared libraries, headers,
/// licences) that flutter_kimodo's hook bundles.
///
/// `tool/build_kimodo.*` writes `<work>/dist/kimodo-<version>-<os>-x64.<zip|tar.gz>`
/// with a `.sha256` sidecar (`sha256sum` format) and installs the unpacked
/// folder at `<work>/prebuilt/<version>/<os>-x64`; [ensure] does the same
/// from an archive in `<work>/dist/` or one downloaded from
/// `<baseUrl>/kimodo-<version>/<archive>`.
abstract final class KimodoPrebuilt {
  static const String defaultBaseUrl =
      'https://github.com/LuminaGame/tools/releases/download';

  /// `windows`, `linux` or `macos` for this host.
  static String hostOs() => Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
      ? 'macos'
      : 'linux';

  static String platform(String os) => '$os-x64';

  static String baseName(String version, String os) =>
      'kimodo-$version-${platform(os)}';

  static String archiveName(String version, String os) =>
      '${baseName(version, os)}.${os == 'windows' ? 'zip' : 'tar.gz'}';

  static String releaseTag(String version) => 'kimodo-$version';

  static Uri archiveUri(
    String version,
    String os, {
    String baseUrl = defaultBaseUrl,
  }) =>
      Uri.parse('$baseUrl/${releaseTag(version)}/${archiveName(version, os)}');

  /// The library whose presence marks an installed folder.
  static String marker(String os) => switch (os) {
    'windows' => 'bin/kimodo.dll',
    'macos' => 'lib/libkimodo.dylib',
    _ => 'lib/libkimodo.so',
  };

  /// `<work>/prebuilt/<version>/<os>-x64`.
  static Directory installDir(Directory work, String version, String os) =>
      Directory(p.join(work.path, 'prebuilt', version, platform(os)));

  /// Checks [archive] against its `<archive>.sha256` sidecar; returns the
  /// hash.
  static Future<String> verify(File archive) async {
    final sidecar = File('${archive.path}.sha256');
    if (!sidecar.existsSync()) {
      throw KimodoPrebuiltException('${sidecar.path} is missing');
    }
    final expected = sidecar
        .readAsStringSync()
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
    final actual = (await sha256.bind(archive.openRead()).first).toString();
    if (actual != expected) {
      throw KimodoPrebuiltException(
        'SHA-256 mismatch for ${archive.path}: expected $expected, got $actual',
      );
    }
    return actual;
  }

  /// Installs [version] for [os] under [work] and returns the folder: kept
  /// when already installed (unless [force]); else unpacked from
  /// `<work>/dist/<archive>`, downloaded there from [baseUrl] first when
  /// absent. The archive is verified before anything is unpacked.
  static Future<Directory> ensure({
    required String version,
    required Directory work,
    String? os,
    String baseUrl = defaultBaseUrl,
    bool force = false,
    HttpClient? client,
    void Function(String message)? log,
  }) async {
    final target = os ?? hostOs();
    final install = installDir(work, version, target);
    if (!force && File(p.join(install.path, marker(target))).existsSync()) {
      return install;
    }
    final dist = Directory(p.join(work.path, 'dist'))
      ..createSync(recursive: true);
    final archive = File(p.join(dist.path, archiveName(version, target)));
    if (!archive.existsSync() || !File('${archive.path}.sha256').existsSync()) {
      final uri = archiveUri(version, target, baseUrl: baseUrl);
      log?.call('downloading $uri');
      await _download(uri, archive, client);
      await _download(
        Uri.parse('$uri.sha256'),
        File('${archive.path}.sha256'),
        client,
      );
    }
    final hash = await verify(archive);
    log?.call('${archive.path} sha256 $hash');
    await unpack(archive, install, baseName(version, target));
    if (!File(p.join(install.path, marker(target))).existsSync()) {
      throw KimodoPrebuiltException('${archive.path} has no ${marker(target)}');
    }
    return install;
  }

  /// Unpacks [archive] (one top folder [topFolder]) so its content becomes
  /// [destination], replacing what was there.
  static Future<void> unpack(
    File archive,
    Directory destination,
    String topFolder,
  ) async {
    final staging = Directory('${destination.path}.unpack');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    // bsdtar (Windows 10+) reads zip archives too.
    final tar = Platform.isWindows
        ? p.join(
            Platform.environment['SystemRoot'] ?? r'C:\Windows',
            'System32',
            'tar.exe',
          )
        : 'tar';
    final result = await Process.run(tar, [
      '-x',
      '-f',
      archive.path,
      '-C',
      staging.path,
    ]);
    if (result.exitCode != 0) {
      throw KimodoPrebuiltException(
        'unpacking ${archive.path} failed: ${result.stderr}',
      );
    }
    final top = Directory(p.join(staging.path, topFolder));
    if (!top.existsSync()) {
      staging.deleteSync(recursive: true);
      throw KimodoPrebuiltException(
        '${archive.path} does not hold $topFolder/',
      );
    }
    if (destination.existsSync()) destination.deleteSync(recursive: true);
    destination.parent.createSync(recursive: true);
    top.renameSync(destination.path);
    staging.deleteSync(recursive: true);
  }

  static Future<void> _download(Uri uri, File to, HttpClient? client) async {
    final http = client ?? HttpClient();
    try {
      final response = await (await http.getUrl(uri)).close();
      if (response.statusCode != 200) {
        throw KimodoPrebuiltException('GET $uri: HTTP ${response.statusCode}');
      }
      final part = File('${to.path}.part');
      await response.pipe(part.openWrite());
      part.renameSync(to.path);
    } finally {
      if (client == null) http.close();
    }
  }
}
