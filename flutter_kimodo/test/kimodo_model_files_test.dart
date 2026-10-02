import 'dart:io';

import 'package:flutter_kimodo/flutter_kimodo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kimodo_files'));
  tearDown(() => dir.deleteSync(recursive: true));

  void touch(String relative) => File(p.join(dir.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync('gguf');

  test('finds the motion model and the preferred text encoder', () {
    touch('models/kimodo-soma-rp-v1.1-f32.gguf');
    touch('text/Llama-3-Kimodo-Q8_0.gguf');
    touch('text/Llama-3-Kimodo-Q4_K_M.gguf');
    touch('text/tokenizer.gguf');
    final q4 = KimodoModelFiles.find(dir)!;
    expect(p.basename(q4.motion), 'kimodo-soma-rp-v1.1-f32.gguf');
    expect(p.basename(q4.text), 'Llama-3-Kimodo-Q4_K_M.gguf');
    expect(p.basename(q4.tokenizer), 'tokenizer.gguf');
    final q8 = KimodoModelFiles.find(dir, quantization: 'Q8_0')!;
    expect(p.basename(q8.text), 'Llama-3-Kimodo-Q8_0.gguf');
  });

  test('falls back to another quantisation that has its tokenizer', () {
    touch('kimodo-soma-rp-v1.1-f32.gguf');
    touch('Llama-3-Kimodo-Q8_0.gguf');
    touch('tokenizer.gguf');
    expect(
      p.basename(KimodoModelFiles.find(dir)!.text),
      'Llama-3-Kimodo-Q8_0.gguf',
    );
  });

  test('is null without the motion model or the tokenizer', () {
    touch('Llama-3-Kimodo-Q4_K_M.gguf');
    touch('tokenizer.gguf');
    expect(KimodoModelFiles.find(dir), isNull);
    File(p.join(dir.path, 'tokenizer.gguf')).deleteSync();
    touch('kimodo-soma-rp-v1.1-f32.gguf');
    expect(KimodoModelFiles.find(dir), isNull);
    expect(KimodoModelFiles.find(Directory(p.join(dir.path, 'none'))), isNull);
  });

  test('the default folder is KIMODO_MODELS_DIR, else the plugin data', () {
    expect(
      KimodoModelFiles.defaultDirectory({'KIMODO_MODELS_DIR': dir.path}).path,
      dir.path,
    );
    final data = p.join(dir.path, 'data');
    expect(
      KimodoModelFiles.defaultDirectory({'LUMINA_DATA_DIR': data}).path,
      p.join(data, 'plugin_data', 'lumina_plugin_kimodo', 'models'),
    );
  });
}
