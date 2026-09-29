import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'bindings/gstreamer.g.dart';
import 'exceptions.dart';

/// The GStreamer shared libraries, opened at run time with
/// [ffi.DynamicLibrary] (no link-time dependency on GStreamer).
///
/// Lookup order (the first that has the GStreamer core library wins):
///  1. the explicit `root` passed to [open] — nothing else is tried then;
///  2. the `FLUTTER_GSTREAMER_ROOT`, `GSTREAMER_1_0_ROOT_MSVC_X86_64`,
///     `GSTREAMER_1_0_ROOT_MINGW_X86_64` and `GSTREAMER_1_0_ROOT_X86_64`
///     environment variables (the official installers set the latter);
///  3. the default install folders — Windows: per-user
///     `%LOCALAPPDATA%\Programs\gstreamer\1.0\msvc_x86_64`, then
///     `%ProgramFiles%\gstreamer\1.0\msvc_x86_64` and
///     `C:\gstreamer\1.0\msvc_x86_64` (and the `mingw_x86_64` variants);
///     macOS: `/Library/Frameworks/GStreamer.framework/Versions/1.0`,
///     `/opt/homebrew`, `/usr/local`;
///  4. Windows: every `PATH` folder holding `gstreamer-1.0-0.dll`;
///     Linux / macOS: the system dynamic loader (`libgstreamer-1.0.so.0`).
///
/// A root is the install prefix (holding `bin/` and `lib/`), or the library
/// folder itself. When a root is used, its library folder is put on `PATH`
/// (Windows, so dependent DLLs and plugins resolve), and — unless the
/// process environment already sets them — `GST_PLUGIN_SYSTEM_PATH` points at
/// `<root>/lib/gstreamer-1.0` and `GST_PLUGIN_SCANNER` at
/// `<root>/libexec/gstreamer-1.0/gst-plugin-scanner[.exe]`, so the plugins of
/// that same install are the ones found. `GST_PLUGIN_PATH` (extra plugin
/// folders) is left to the user.
final class GStreamerLibraries {
  GStreamerLibraries._(this.root, this.paths, this._libraries);

  /// The install root the libraries came from, or null when the system
  /// loader found them (Linux / macOS without a root).
  final String? root;

  /// The library files (or bare names for the system loader) that were
  /// opened: GStreamer core, app, pbutils, GObject, GLib.
  final List<String> paths;

  final List<ffi.DynamicLibrary> _libraries;

  /// Raw bindings resolving every symbol across the opened libraries.
  late final GStreamerBindings bindings = GStreamerBindings.fromLookup(lookup);

  /// Looks [symbol] up in the opened libraries (core first).
  ffi.Pointer<T> lookup<T extends ffi.NativeType>(String symbol) {
    for (final lib in _libraries) {
      if (lib.providesSymbol(symbol)) return lib.lookup<T>(symbol);
    }
    throw ArgumentError.value(
      symbol,
      'symbol',
      'not exported by the GStreamer libraries ${paths.join(', ')}',
    );
  }

  /// The library base names, in lookup order.
  static const _names = [
    'gstreamer-1.0',
    'gstapp-1.0',
    'gstpbutils-1.0',
    'gobject-2.0',
    'glib-2.0',
  ];

  /// Finds and opens the GStreamer libraries (see the class comment for the
  /// search order). Throws [GStreamerNotFoundException] when none are found
  /// or they fail to load.
  static GStreamerLibraries open({String? root}) {
    final searched = <String>[];
    if (root != null) {
      final found = _probeRoot(root, searched);
      if (found == null) {
        throw GStreamerNotFoundException(
          'GStreamer 1.x was not found under ${_slash(root)} (no ${_fileName('gstreamer-1.0')} in it, '
          'its bin/ or its lib/ folder).',
          searched: searched,
        );
      }
      return _openIn(found.$1, found.$2, searched);
    }
    for (final candidate in _defaultRoots()) {
      final found = _probeRoot(candidate, searched);
      if (found != null) return _openIn(found.$1, found.$2, searched);
    }
    if (Platform.isWindows) {
      for (final dir in (Platform.environment['PATH'] ?? '').split(';')) {
        if (dir.trim().isEmpty) continue;
        final found = _probeRoot(dir.trim(), searched);
        if (found != null) return _openIn(found.$1, found.$2, searched);
      }
      throw GStreamerNotFoundException(
        'GStreamer 1.x is not installed. Install the MSVC x86_64 runtime from '
        'https://gstreamer.freedesktop.org/download/ (it sets GSTREAMER_1_0_ROOT_MSVC_X86_64), '
        'or pass its folder as root.',
        searched: searched,
      );
    }
    // Linux / macOS: the system loader.
    final libs = <ffi.DynamicLibrary>[];
    final names = [for (final n in _names) _fileName(n)];
    for (final name in names) {
      searched.add('$name (system loader)');
      try {
        libs.add(ffi.DynamicLibrary.open(name));
      } on ArgumentError catch (e) {
        throw GStreamerNotFoundException(
          'GStreamer 1.x could not be loaded ($name). Install it '
          '(${Platform.isMacOS ? 'the GStreamer.framework runtime or `brew install gstreamer`' : 'e.g. `apt install libgstreamer1.0-0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good`'}), '
          'or pass its folder as root.',
          searched: searched,
          cause: e,
        );
      }
    }
    return GStreamerLibraries._(null, names, libs);
  }

  static List<String> _defaultRoots() {
    final env = Platform.environment;
    return [
      for (final v in [
        'FLUTTER_GSTREAMER_ROOT',
        'GSTREAMER_1_0_ROOT_MSVC_X86_64',
        'GSTREAMER_1_0_ROOT_MINGW_X86_64',
        'GSTREAMER_1_0_ROOT_X86_64',
      ])
        if (env[v] != null && env[v]!.trim().isNotEmpty) env[v]!.trim(),
      if (Platform.isWindows) ...[
        for (final flavour in ['msvc_x86_64', 'mingw_x86_64']) ...[
          if (env['LOCALAPPDATA'] != null)
            '${env['LOCALAPPDATA']}/Programs/gstreamer/1.0/$flavour',
          '${env['ProgramFiles'] ?? 'C:/Program Files'}/gstreamer/1.0/$flavour',
          'C:/gstreamer/1.0/$flavour',
        ],
      ],
      if (Platform.isMacOS) ...[
        '/Library/Frameworks/GStreamer.framework/Versions/1.0',
        '/opt/homebrew',
        '/usr/local',
      ],
    ];
  }

  /// The library folder and install root under [root], or null.
  static (String libDir, String installRoot)? _probeRoot(
    String root,
    List<String> searched,
  ) {
    final r = _slash(root).replaceFirst(RegExp(r'/+$'), '');
    final dirs = Platform.isWindows
        ? ['$r/bin', r]
        : [
            '$r/lib',
            '$r/lib/x86_64-linux-gnu',
            '$r/lib/aarch64-linux-gnu',
            '$r/lib64',
            r,
          ];
    for (final dir in dirs) {
      for (final file in _fileNames('gstreamer-1.0')) {
        final path = '$dir/$file';
        searched.add(path);
        if (File(path).existsSync()) {
          final isLibFolder = dir == r;
          final installRoot = isLibFolder
              ? Directory(r).parent.path.replaceAll('\\', '/')
              : r;
          return (dir, installRoot);
        }
      }
    }
    return null;
  }

  static GStreamerLibraries _openIn(
    String libDir,
    String installRoot,
    List<String> searched,
  ) {
    final files = <String>[];
    for (final name in _names) {
      final file = _fileNames(name)
          .map((f) => '$libDir/$f')
          .firstWhere(
            (p) => File(p).existsSync(),
            orElse: () => throw GStreamerNotFoundException(
              'GStreamer under $installRoot is incomplete: no ${_fileName(name)} in $libDir.',
              searched: searched,
            ),
          );
      files.add(file);
    }
    _prepareEnvironment(libDir, installRoot);
    final libs = <ffi.DynamicLibrary>[];
    for (final file in files) {
      try {
        if (Platform.isWindows) _Win32.loadWithAlteredSearchPath(file);
        libs.add(ffi.DynamicLibrary.open(file));
      } on ArgumentError catch (e) {
        throw GStreamerNotFoundException(
          'GStreamer was found at $installRoot but $file failed to load.',
          searched: searched,
          cause: e,
        );
      }
    }
    return GStreamerLibraries._(installRoot, files, libs);
  }

  static void _prepareEnvironment(String libDir, String installRoot) {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final path = _Win32.getEnv('PATH') ?? '';
      final native = libDir.replaceAll('/', '\\');
      final entries = path
          .split(';')
          .map((e) => e.toLowerCase().replaceAll('/', '\\'));
      if (!entries.contains(native.toLowerCase())) {
        _setEnv('PATH', '$native;$path');
      }
    }
    final pluginDir = '$installRoot/lib/gstreamer-1.0';
    if (env['GST_PLUGIN_SYSTEM_PATH'] == null &&
        env['GST_PLUGIN_SYSTEM_PATH_1_0'] == null &&
        Directory(pluginDir).existsSync()) {
      _setEnv('GST_PLUGIN_SYSTEM_PATH', _native(pluginDir));
    }
    final scanner =
        '$installRoot/libexec/gstreamer-1.0/gst-plugin-scanner${Platform.isWindows ? '.exe' : ''}';
    if (env['GST_PLUGIN_SCANNER'] == null &&
        env['GST_PLUGIN_SCANNER_1_0'] == null &&
        File(scanner).existsSync()) {
      _setEnv('GST_PLUGIN_SCANNER', _native(scanner));
    }
  }

  static String _native(String path) =>
      Platform.isWindows ? path.replaceAll('/', '\\') : path;

  static String _slash(String path) => path.replaceAll('\\', '/');

  /// The primary file name of library [name] on this OS.
  static String _fileName(String name) => _fileNames(name).first;

  static List<String> _fileNames(String name) {
    if (Platform.isWindows) return ['$name-0.dll', 'lib$name-0.dll'];
    if (Platform.isMacOS) return ['lib$name.0.dylib', 'lib$name.dylib'];
    return ['lib$name.so.0', 'lib$name.so'];
  }

  /// Sets a variable in the process environment (visible to GLib's
  /// `g_getenv` and to child processes such as gst-plugin-scanner).
  static void _setEnv(String name, String value) {
    if (Platform.isWindows) {
      _Win32.setEnv(name, value);
    } else {
      using((arena) {
        final setenv = ffi.DynamicLibrary.process()
            .lookupFunction<
              ffi.Int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int),
              int Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int)
            >('setenv');
        setenv(
          name.toNativeUtf8(allocator: arena),
          value.toNativeUtf8(allocator: arena),
          1,
        );
      });
    }
  }
}

/// The few kernel32 calls the Windows loader needs.
abstract final class _Win32 {
  static final _kernel32 = ffi.DynamicLibrary.open('kernel32.dll');

  static final _loadLibraryExW = _kernel32
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(
          ffi.Pointer<Utf16>,
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
        ),
        ffi.Pointer<ffi.Void> Function(
          ffi.Pointer<Utf16>,
          ffi.Pointer<ffi.Void>,
          int,
        )
      >('LoadLibraryExW');

  static final _setEnvironmentVariableW = _kernel32
      .lookupFunction<
        ffi.Int32 Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>),
        int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>)
      >('SetEnvironmentVariableW');

  static final _getEnvironmentVariableW = _kernel32
      .lookupFunction<
        ffi.Uint32 Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, ffi.Uint32),
        int Function(ffi.Pointer<Utf16>, ffi.Pointer<Utf16>, int)
      >('GetEnvironmentVariableW');

  /// `LOAD_WITH_ALTERED_SEARCH_PATH`: resolve [path]'s own DLL dependencies
  /// from its folder first. The handle stays loaded, so the following
  /// `DynamicLibrary.open(path)` reuses it.
  static void loadWithAlteredSearchPath(String path) => using((arena) {
    _loadLibraryExW(
      path.replaceAll('/', '\\').toNativeUtf16(allocator: arena),
      ffi.nullptr,
      0x00000008,
    );
  });

  static void setEnv(String name, String value) => using((arena) {
    _setEnvironmentVariableW(
      name.toNativeUtf16(allocator: arena),
      value.toNativeUtf16(allocator: arena),
    );
  });

  static String? getEnv(String name) => using((arena) {
    final n = name.toNativeUtf16(allocator: arena);
    final size = _getEnvironmentVariableW(n, ffi.nullptr, 0);
    if (size == 0) return null;
    final buf = arena<ffi.Uint16>(size).cast<Utf16>();
    _getEnvironmentVariableW(n, buf, size);
    return buf.toDartString();
  });
}
