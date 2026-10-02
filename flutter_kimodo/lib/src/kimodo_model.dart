import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/flutter_kimodo_bindings.g.dart' as b;
import 'kimodo_exception.dart';
import 'kimodo_motion.dart';
import 'kimodo_runtime.dart';

/// How a motion is sampled.
class KimodoGenerationOptions {
  /// The random seed: the same prompt, length and seed give the same motion.
  final int seed;

  /// DDIM denoising steps (1..1000); Kimodo is trained for 100.
  final int diffusionSteps;

  /// Classifier-free guidance on the text: higher follows the prompt more
  /// literally.
  final double textCfg;

  /// Classifier-free guidance on constraints (unused without constraints).
  final double constraintCfg;

  const KimodoGenerationOptions({
    this.seed = 0,
    this.diffusionSteps = 100,
    this.textCfg = 2.0,
    this.constraintCfg = 2.0,
  });
}

/// One prompt of a sequence and how long it lasts.
class KimodoSegment {
  final String prompt;

  /// 2..300 frames (at most 10 s at 30 fps).
  final int frames;

  const KimodoSegment(this.prompt, this.frames);
}

/// A loaded Kimodo model (motion GGUF + text encoder GGUF) living on its own
/// background isolate: loading and generating block for seconds to minutes,
/// so they never run on the caller's isolate. Requests are served one at a
/// time, in order. Call [dispose] to free the model (several GB of memory).
class KimodoModel {
  /// Longest single prompt: 10 s at 30 fps.
  static const int maxFrames = 300;

  /// Most prompts in one sequence.
  static const int maxSegments = 16;

  final String motionGguf;
  final String textGguf;
  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _replies;
  final StreamIterator<dynamic> _replyStream;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  KimodoModel._(
    this.motionGguf,
    this.textGguf,
    this._isolate,
    this._commands,
    this._replies,
    this._replyStream,
  );

  /// Loads [motionGguf] (for example `kimodo-soma-rp-v1.1-f32.gguf`) and
  /// [textGguf] (`Llama-3-Kimodo-Q4_K_M.gguf`, with `tokenizer.gguf` beside
  /// it) on a new isolate, after applying [backend] to the process
  /// ([KimodoRuntime.configure]). Throws [KimodoException] with kimodo's
  /// reason when either cannot be read.
  static Future<KimodoModel> load({
    required String motionGguf,
    required String textGguf,
    KimodoBackend? backend,
    String? runtimeDir,
  }) async {
    final replies = ReceivePort('kimodo replies');
    final stream = StreamIterator<dynamic>(replies);
    final isolate = await Isolate.spawn(
      _worker,
      replies.sendPort,
      debugName: 'kimodo',
      errorsAreFatal: false,
    );
    if (!await stream.moveNext()) {
      throw const KimodoException('The kimodo isolate did not start.');
    }
    final commands = stream.current as SendPort;
    final chosen = backend ?? KimodoBackend.fromEnvironment();
    commands.send(<String, Object?>{
      'op': 'load',
      'motion': motionGguf,
      'text': textGguf,
      'runtimeDir': runtimeDir,
      'device': chosen.device.index,
      'threads': chosen.threads,
      'vulkanName': chosen.vulkanDeviceName,
    });
    await stream.moveNext();
    final reply = stream.current as Map;
    if (reply['error'] != null) {
      isolate.kill(priority: Isolate.immediate);
      replies.close();
      throw KimodoException(reply['error'] as String);
    }
    return KimodoModel._(
      motionGguf,
      textGguf,
      isolate,
      commands,
      replies,
      stream,
    );
  }

  /// Generates [frames] (1..[maxFrames]) frames of motion for [prompt].
  Future<KimodoMotion> generate(
    String prompt, {
    required int frames,
    KimodoGenerationOptions options = const KimodoGenerationOptions(),
  }) {
    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be empty');
    }
    RangeError.checkValueInInterval(frames, 1, maxFrames, 'frames');
    return _request({
      'op': 'generate',
      'prompt': prompt,
      'frames': frames,
      ..._options(options),
    });
  }

  /// Generates one motion from [segments] played in order, each blended into
  /// the next over [transitionFrames] (1..60, shorter than every segment
  /// after the first) frames.
  Future<KimodoMotion> generateSequence(
    List<KimodoSegment> segments, {
    int transitionFrames = 5,
    KimodoGenerationOptions options = const KimodoGenerationOptions(),
  }) {
    if (segments.isEmpty || segments.length > maxSegments) {
      throw ArgumentError.value(
        segments.length,
        'segments',
        'needs 1..$maxSegments segments',
      );
    }
    RangeError.checkValueInInterval(
      transitionFrames,
      1,
      60,
      'transitionFrames',
    );
    for (final s in segments) {
      if (s.prompt.trim().isEmpty) {
        throw ArgumentError.value(s.prompt, 'segments', 'a prompt is empty');
      }
      RangeError.checkValueInInterval(s.frames, 2, maxFrames, 'segment frames');
    }
    return _request({
      'op': 'sequence',
      'prompts': [for (final s in segments) s.prompt],
      'frames': [for (final s in segments) s.frames],
      'transition': transitionFrames,
      ..._options(options),
    });
  }

  /// Frees the model and ends its isolate.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final previous = _queue;
    _queue = () async {
      await previous.catchError((_) {});
      _commands.send({'op': 'dispose'});
      await _replyStream.moveNext();
      _replies.close();
      _isolate.kill();
    }();
    await _queue;
  }

  static Map<String, Object> _options(KimodoGenerationOptions o) {
    RangeError.checkValueInInterval(
      o.diffusionSteps,
      1,
      1000,
      'diffusionSteps',
    );
    if (!o.textCfg.isFinite || !o.constraintCfg.isFinite) {
      throw ArgumentError('CFG weights must be finite');
    }
    return {
      'seed': o.seed,
      'steps': o.diffusionSteps,
      'textCfg': o.textCfg,
      'constraintCfg': o.constraintCfg,
    };
  }

  Future<KimodoMotion> _request(Map<String, Object?> command) {
    if (_disposed) throw StateError('KimodoModel is disposed');
    final result = Completer<KimodoMotion>();
    final previous = _queue;
    _queue = () async {
      await previous.catchError((_) {});
      _commands.send(command);
      await _replyStream.moveNext();
      final reply = _replyStream.current as Map;
      if (reply['error'] != null) {
        result.completeError(KimodoException(reply['error'] as String));
      } else {
        result.complete(
          KimodoMotion(
            frames: reply['frames'] as int,
            joints: reply['joints'] as int,
            localRotationsXyzw: (reply['rotations'] as TransferableTypedData)
                .materialize()
                .asFloat32List(),
            rootPositions: (reply['roots'] as TransferableTypedData)
                .materialize()
                .asFloat32List(),
          ),
        );
      }
    }();
    return result.future;
  }
}

// --- worker isolate ---------------------------------------------------------

const int _errLen = 4096;

void _worker(SendPort replies) {
  final commands = ReceivePort('kimodo commands');
  replies.send(commands.sendPort);
  Pointer<b.kimodo_model> model = nullptr;
  commands.listen((message) {
    final command = message as Map;
    try {
      switch (command['op']) {
        case 'load':
          KimodoRuntime.open(runtimeDir: command['runtimeDir'] as String?);
          KimodoRuntime.configure(
            KimodoBackend(
              device: KimodoDevice.values[command['device'] as int],
              threads: command['threads'] as int,
              vulkanDeviceName: command['vulkanName'] as String?,
            ),
          );
          model = _load(command['motion'] as String, command['text'] as String);
          replies.send(const {'ok': true});
        case 'generate':
        case 'sequence':
          replies.send(_generate(model, command));
        case 'dispose':
          if (model != nullptr) b.flutter_kimodo_model_free(model);
          model = nullptr;
          replies.send(const {'ok': true});
          commands.close();
      }
    } on KimodoException catch (e) {
      replies.send({'error': e.message});
    } catch (e) {
      replies.send({'error': '$e'});
    }
  });
}

Pointer<b.kimodo_model> _load(String motion, String text) => using((arena) {
  final err = arena<Char>(_errLen);
  final loaded = b.flutter_kimodo_model_load(
    motion.toNativeUtf8(allocator: arena).cast(),
    text.toNativeUtf8(allocator: arena).cast(),
    err,
    _errLen,
  );
  if (loaded == nullptr) {
    throw KimodoException(
      'Loading the Kimodo model failed: ${err.cast<Utf8>().toDartString()} '
      '(motion: $motion, text: $text)',
    );
  }
  return loaded;
});

Map<String, Object> _generate(Pointer<b.kimodo_model> model, Map command) =>
    using((arena) {
      if (model == nullptr) throw const KimodoException('No model is loaded');
      final err = arena<Char>(_errLen);
      final options = arena<b.kimodo_generation_options>();
      options.ref
        ..size = sizeOf<b.kimodo_generation_options>()
        ..seed = command['seed'] as int
        ..frames = command['op'] == 'generate' ? command['frames'] as int : 0
        ..diffusion_steps = command['steps'] as int
        ..text_cfg_weight = command['textCfg'] as double
        ..constraint_cfg_weight = command['constraintCfg'] as double;
      final Pointer<b.kimodo_motion> motion;
      if (command['op'] == 'generate') {
        motion = b.flutter_kimodo_generate(
          model,
          (command['prompt'] as String).toNativeUtf8(allocator: arena).cast(),
          options,
          err,
          _errLen,
        );
      } else {
        final prompts = (command['prompts'] as List).cast<String>();
        final frames = (command['frames'] as List).cast<int>();
        final promptArray = arena<Pointer<Char>>(prompts.length);
        final frameArray = arena<Uint32>(frames.length);
        for (var i = 0; i < prompts.length; i++) {
          promptArray[i] = prompts[i].toNativeUtf8(allocator: arena).cast();
          frameArray[i] = frames[i];
        }
        motion = b.flutter_kimodo_generate_sequence(
          model,
          promptArray,
          frameArray,
          prompts.length,
          command['transition'] as int,
          options,
          err,
          _errLen,
        );
      }
      if (motion == nullptr) {
        throw KimodoException(
          'Kimodo generation failed: ${err.cast<Utf8>().toDartString()}',
        );
      }
      try {
        final frames = b.flutter_kimodo_motion_frames(motion);
        final joints = b.flutter_kimodo_motion_joints(motion);
        final rotations = b.flutter_kimodo_motion_local_rotations_xyzw(motion);
        final roots = b.flutter_kimodo_motion_root_positions(motion);
        if (rotations == nullptr || roots == nullptr) {
          throw const KimodoException('Kimodo returned an empty motion');
        }
        return {
          'frames': frames,
          'joints': joints,
          'rotations': TransferableTypedData.fromList([
            Float32List.fromList(rotations.asTypedList(frames * joints * 4)),
          ]),
          'roots': TransferableTypedData.fromList([
            Float32List.fromList(roots.asTypedList(frames * 3)),
          ]),
        };
      } finally {
        b.flutter_kimodo_motion_free(motion);
      }
    });
