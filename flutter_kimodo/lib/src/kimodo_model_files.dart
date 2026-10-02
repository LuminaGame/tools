import 'dart:io';

import 'package:path/path.dart' as p;

/// The GGUF files one Kimodo model needs, found in a folder.
///
/// The text encoder GGUF must have `tokenizer.gguf` beside it (kimodo.cpp
/// reads it from the same folder).
class KimodoModelFiles {
  /// The SOMA motion model (Kimodo-SOMA-RP-v1.1, F32).
  static const String motionFileName = 'kimodo-soma-rp-v1.1-f32.gguf';

  /// Text encoder file per quantisation.
  static const Map<String, String> textFileNames = {
    'Q4_K_M': 'Llama-3-Kimodo-Q4_K_M.gguf',
    'Q8_0': 'Llama-3-Kimodo-Q8_0.gguf',
  };

  static const String tokenizerFileName = 'tokenizer.gguf';

  /// Where models are looked for when no folder is given: `KIMODO_MODELS_DIR`,
  /// else the Kimodo plugin's model folder in Lumina's per-user data
  /// (`%LOCALAPPDATA%\Lumina\plugin_data\lumina_plugin_kimodo\models`,
  /// `~/.local/share/lumina/...`, `~/Library/Application Support/Lumina/...`;
  /// `LUMINA_DATA_DIR` replaces the Lumina part).
  static Directory defaultDirectory([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final explicit = env['KIMODO_MODELS_DIR'];
    if (explicit != null && explicit.isNotEmpty) return Directory(explicit);
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    final String data;
    final override = env['LUMINA_DATA_DIR'];
    if (override != null && override.isNotEmpty) {
      data = override;
    } else if (Platform.isWindows) {
      final local = env['LOCALAPPDATA'];
      data = p.join(
        local != null && local.isNotEmpty
            ? local
            : p.join(home, 'AppData', 'Local'),
        'Lumina',
      );
    } else if (Platform.isMacOS) {
      data = p.join(home, 'Library', 'Application Support', 'Lumina');
    } else {
      final xdg = env['XDG_DATA_HOME'];
      data = xdg != null && xdg.isNotEmpty
          ? p.join(xdg, 'lumina')
          : p.join(home, '.local', 'share', 'lumina');
    }
    return Directory(
      p.join(data, 'plugin_data', 'lumina_plugin_kimodo', 'models'),
    );
  }

  final String motion;
  final String text;

  const KimodoModelFiles(this.motion, this.text);

  String get tokenizer => p.join(p.dirname(text), tokenizerFileName);

  /// The files in [directory] (searched up to three folders deep): the
  /// motion model and a text encoder with its tokenizer, preferring
  /// [quantization] (`Q4_K_M`, `Q8_0`) and else any `Llama-3-Kimodo-*.gguf`.
  /// Null when either is missing.
  static KimodoModelFiles? find(
    Directory directory, {
    String quantization = 'Q4_K_M',
  }) {
    if (!directory.existsSync()) return null;
    final files = <File>[];
    void walk(Directory dir, int depth) {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is File) files.add(e);
        if (e is Directory && depth < 3) walk(e, depth + 1);
      }
    }

    walk(directory, 0);
    String? named(String name) {
      for (final f in files) {
        if (p.basename(f.path) == name) return f.path;
      }
      return null;
    }

    bool hasTokenizer(String path) =>
        File(p.join(p.dirname(path), tokenizerFileName)).existsSync();
    final motion = named(motionFileName);
    if (motion == null) return null;
    final preferred = textFileNames[quantization];
    var text = preferred == null ? null : named(preferred);
    if (text == null || !hasTokenizer(text)) {
      text = null;
      for (final f in files) {
        final name = p.basename(f.path);
        if (name.startsWith('Llama-3-Kimodo-') &&
            name.endsWith('.gguf') &&
            hasTokenizer(f.path)) {
          text = f.path;
          break;
        }
      }
    }
    return text == null ? null : KimodoModelFiles(motion, text);
  }

  @override
  String toString() => 'KimodoModelFiles(motion: $motion, text: $text)';
}
