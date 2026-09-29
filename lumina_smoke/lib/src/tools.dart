import 'dart:io';

/// Where the `ffmpeg` / `ffprobe` executables the smoke system falls back to
/// (when GStreamer is not installed) are found.
///
/// `LUMINA_SMOKE_FFMPEG` / `LUMINA_SMOKE_FFPROBE` (or the older
/// `FILAMENT_SMOKE_FFMPEG` / `FILAMENT_SMOKE_FFPROBE`) name an executable
/// file; otherwise ffprobe is looked for next to that ffmpeg, then each tool
/// by its bare name on the PATH.
abstract final class SmokeTools {
  static String? _ffmpeg;
  static bool _ffmpegResolved = false;
  static String? _ffprobe;
  static bool _ffprobeResolved = false;

  /// The ffmpeg to start, or null when there is none.
  static String? get ffmpeg {
    if (_ffmpegResolved) return _ffmpeg;
    _ffmpegResolved = true;
    return _ffmpeg = _fromEnvironment(const ['LUMINA_SMOKE_FFMPEG', 'FILAMENT_SMOKE_FFMPEG']) ?? _onPath('ffmpeg');
  }

  /// The ffprobe to start, or null when there is none.
  static String? get ffprobe {
    if (_ffprobeResolved) return _ffprobe;
    _ffprobeResolved = true;
    final configured = _fromEnvironment(const ['LUMINA_SMOKE_FFPROBE', 'FILAMENT_SMOKE_FFPROBE']);
    if (configured != null) return _ffprobe = configured;
    final ffmpegPath = ffmpeg;
    if (ffmpegPath != null && ffmpegPath != 'ffmpeg') {
      final sibling = File('${File(ffmpegPath).parent.path}${Platform.pathSeparator}ffprobe${Platform.isWindows ? '.exe' : ''}');
      if (sibling.existsSync()) return _ffprobe = sibling.path;
    }
    return _ffprobe = _onPath('ffprobe');
  }

  /// Forgets the resolved paths (tests that change the environment).
  static void resetForTesting() {
    _ffmpegResolved = false;
    _ffprobeResolved = false;
  }

  static String? _fromEnvironment(List<String> names) {
    for (final name in names) {
      final value = Platform.environment[name];
      if (value != null && value.isNotEmpty && File(value).existsSync()) return value;
    }
    return null;
  }

  /// [tool] by its bare name when it starts (`<tool> -version` exits 0),
  /// else null. The OS resolves the name on the PATH (with PATHEXT on
  /// Windows); never `which`, which Windows lacks and which Git Bash answers
  /// with an MSYS path no process can start.
  static String? _onPath(String tool) {
    try {
      return Process.runSync(tool, const ['-version']).exitCode == 0 ? tool : null;
    } on ProcessException {
      return null;
    }
  }
}
