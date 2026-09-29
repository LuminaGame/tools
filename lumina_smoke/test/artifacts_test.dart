import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/lumina_smoke.dart';

import 'support/videos.dart';

/// Whether [tool] is on this process's PATH, asked of the platform's own
/// lookup (`where.exe` on Windows, `which` elsewhere): the oracle the
/// resolver under test must agree with.
bool _onPath(String tool) {
  try {
    final r = Process.runSync(Platform.isWindows ? 'where.exe' : 'which', [tool]);
    return r.exitCode == 0 && '${r.stdout}'.trim().isNotEmpty;
  } on ProcessException {
    return false;
  }
}

Map<String, dynamic> _sidecar(File artifact) =>
    jsonDecode(File(artifact.path.replaceAll(RegExp(r'\.[a-z0-9]+$'), '.json')).readAsStringSync()) as Map<String, dynamic>;

/// [count] distinct PNG frames (a grey ramp); the default size is the
/// smallest video frame SmokeArtifacts accepts.
List<Uint8List> _rampFrames(int count, {int w = 1024, int h = 768}) => [
      for (var f = 0; f < count; f++) SmokeArtifacts.encodePng(w, h, Uint8List(w * h * 4)..fillRange(0, w * h * 4, f % 256)),
    ];

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('smoke_artifacts_test_');
    SmokeArtifacts.overrideDirForTesting(tempDir);
    SmokeArtifacts.resetRecordedAssets();
  });

  tearDown(() {
    SmokeArtifacts.overrideDirForTesting(null);
    SmokeArtifacts.resetRecordedAssets();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('screenshots and sidecars', () {
    test('a test name becomes a lower-case file name', () {
      expect(SmokeArtifacts.sanitizeTestName('camera: perspective sync'), 'camera_perspective_sync');
      expect(SmokeArtifacts.sanitizeTestName('___foo::bar---baz___'), 'foo_bar_baz');
      expect(SmokeArtifacts.sanitizeTestName('Render Smoke: Suzanne (OpenGL)'), 'render_smoke_suzanne_opengl');
    });

    test('saveScreenshot writes the PNG and a sidecar with the declared name, and overwrites on a second call', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);
      final file = SmokeArtifacts.saveScreenshot('launcher: hub renders recents', png,
          usedAssets: ['Props/Barrels'], metrics: {'frames': 3});
      expect(file.path, endsWith('launcher_hub_renders_recents.png'));
      expect(file.readAsBytesSync(), png);
      final json = _sidecar(file);
      expect(json['test'], 'launcher: hub renders recents');
      expect(json['file'], 'launcher_hub_renders_recents.png', reason: 'relative: the folder can be copied to share');
      expect(json['screenshot'], 'launcher_hub_renders_recents.png');
      expect(json['usedAssets'], ['Props/Barrels']);
      expect(json['metrics'], {'frames': 3});
      expect(json['savedAt'], isA<int>());

      final png2 = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 8, 7]);
      final again = SmokeArtifacts.saveScreenshot('launcher: hub renders recents', png2);
      expect(again.path, file.path);
      expect(again.readAsBytesSync(), png2);
      expect(tempDir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')), hasLength(1));
      expect(_sidecar(again)['usedAssets'], ['Props/Barrels'], reason: 'assets add up, never get dropped');
    });

    test('saveScreenshotToDir writes into the given directory', () {
      final dir = Directory('${tempDir.path}/custom');
      final file = SmokeArtifacts.saveScreenshotToDir('camera: perspective sync', Uint8List.fromList([1, 2]), dir);
      expect(file.parent.path, dir.path);
      expect(File('${dir.path}/camera_perspective_sync.json').existsSync(), isTrue);
    });

    test('a sidecar of another test that sanitizes to the same file name is replaced, never merged', () {
      SmokeArtifacts.saveScreenshot('Foo: bar', Uint8List.fromList([1]), usedAssets: ['a.glb']);
      final file = SmokeArtifacts.saveScreenshot('foo bar', Uint8List.fromList([2]));
      final json = _sidecar(file);
      expect(json['test'], 'foo bar');
      expect(json.containsKey('usedAssets'), isFalse);
    });

    test('recorded assets and passed assets end up in the sidecar once each', () {
      final assets = SmokeArtifacts.testAssetsDir.path;
      SmokeArtifacts.recordAsset('$assets/Props/Barrels/empty_barrel.glb');
      SmokeArtifacts.recordAsset('$assets/Props/Barrels/empty_barrel.glb');
      final file = SmokeArtifacts.saveScreenshot('asset test', SmokeArtifacts.encodePng(2, 2, Uint8List(16)),
          usedAssets: ['$assets/fixtures/blackjack_blender2.glb']);
      final used = (_sidecar(file)['usedAssets'] as List).cast<String>();
      expect(used, hasLength(2));
      expect(used, contains(endsWith('empty_barrel.glb')));
      expect(used, contains(endsWith('blackjack_blender2.glb')));
      SmokeArtifacts.resetRecordedAssets();
      expect(SmokeArtifacts.recordedAssets, isEmpty);
    });

    test('the backend a runner names is recorded in the sidecar', () {
      final file = SmokeArtifacts.saveScreenshot('backend hint', Uint8List.fromList([1]));
      final backend = Platform.environment['LUMINA_SMOKE_BACKEND'] ?? Platform.environment['FILAMENT_SMOKE_BACKEND'];
      expect(_sidecar(file)['backend'], backend);
    });

    test('clear wipes an owned directory but refuses the shared one', () {
      SmokeArtifacts.saveScreenshot('test1', Uint8List.fromList([1]));
      expect(tempDir.listSync(), hasLength(2)); // png + json
      SmokeArtifacts.clear();
      expect(tempDir.existsSync(), isTrue);
      expect(tempDir.listSync(), isEmpty);

      // A smoke run publishes into the package's build/smoke_artifacts, which
      // every smoke test shares: one test clearing it deletes the evidence
      // another run has just written, silently.
      SmokeArtifacts.overrideDirForTesting(null);
      expect(SmokeArtifacts.clear, throwsA(isA<StateError>().having((e) => e.message, 'message', contains('shared'))));
      SmokeArtifacts.overrideDirForTesting(tempDir);

      SmokeArtifacts.saveScreenshot('temp test', Uint8List.fromList([1]));
      SmokeArtifacts.clearDir(tempDir);
      expect(tempDir.listSync(), isEmpty);
    });

    test('the default directory is build/smoke_artifacts of the package, or LUMINA_SMOKE_OUT', () {
      SmokeArtifacts.overrideDirForTesting(null);
      addTearDown(() => SmokeArtifacts.overrideDirForTesting(tempDir));
      final env = Platform.environment['LUMINA_SMOKE_OUT'];
      final expected = env ?? '${SmokeArtifacts.packageRoot.path}${Platform.pathSeparator}build${Platform.pathSeparator}smoke_artifacts';
      expect(SmokeArtifacts.dir.path, expected);
      expect(File('${SmokeArtifacts.packageRoot.path}/pubspec.yaml').existsSync(), isTrue);
    });

    test('testAssetsDir is the override, else LUMINA_TEST_ASSETS, else the nearest test-assets folder', () {
      SmokeArtifacts.testAssetsDirOverride = tempDir.path;
      addTearDown(() => SmokeArtifacts.testAssetsDirOverride = null);
      expect(SmokeArtifacts.testAssetsDir.path, tempDir.path);
      SmokeArtifacts.testAssetsDirOverride = null;
      final dir = SmokeArtifacts.testAssetsDir;
      if (!dir.existsSync()) return markTestSkipped('no test-assets checkout next to this workspace');
      expect(Directory('${dir.path}/Props').existsSync(), isTrue);
    });
  });

  group('PNG', () {
    test('encodePng writes a decodable header with the size', () {
      final rgba = Uint8List(4 * 3 * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 255;
        rgba[i + 3] = 255;
      }
      final png = SmokeArtifacts.encodePng(4, 3, rgba);
      expect(png.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(SmokeArtifacts.pngSize(png), (4, 3));
      expect(SmokeArtifacts.pngSize(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('encodeRgbaToPng swaps BGRA and flips rows; the pixels survive a round trip through zlib', () {
      final bgra = Uint8List.fromList([
        0, 0, 255, 255, 0, 255, 0, 255, // row 0: red, green (as BGRA)
        255, 0, 0, 255, 255, 255, 255, 255, // row 1: blue, white
      ]);
      final png = SmokeArtifacts.encodeRgbaToPng(bgra, 2, 2, bgra: true, flipY: true);
      final idatAt = _indexOf(png, 'IDAT'.codeUnits);
      final len = ByteData.sublistView(png).getUint32(idatAt - 4);
      final raw = ZLibDecoder().convert(png.sublist(idatAt + 4, idatAt + 4 + len));
      // Row 0 of the image is row 1 of the buffer, as RGBA.
      expect(raw.sublist(0, 9), [0, 0, 0, 255, 255, 255, 255, 255, 255]);
      expect(raw.sublist(9, 18), [0, 255, 0, 0, 255, 0, 255, 0, 255]);
    });
  });

  group('the smoke-video rules', () {
    test('are constants: 10 s at 30 fps (300 frames), 1024×768, no frame held over 2 s', () {
      expect(SmokeArtifacts.minimumVideoSeconds, 10);
      expect(SmokeArtifacts.minimumVideoFps, 30);
      expect(SmokeArtifacts.minimumVideoWidth, 1024);
      expect(SmokeArtifacts.minimumVideoHeight, 768);
      expect(SmokeArtifacts.maximumFrameHoldSeconds, 2);
      expect(SmokeArtifacts.framesForSeconds(30), 300);
      expect(SmokeArtifacts.framesForSeconds(60), 600);
      expect(SmokeArtifacts.framesDurationSeconds(300, 30), 10);
      expect(SmokeArtifacts.vp8QualitySettings, allOf(contains('deadline=1000000'), isNot(contains('deadline=1'))));
    });

    test('saveVideoFromPngFrames encodes a WebM and records it in the sidecar', () {
      if (noEncoderReason != null) return markTestSkipped(noEncoderReason!);
      SmokeArtifacts.recordAsset('Props/AC_units/ac_unit_a_300x300.glb');
      final frames = _rampFrames(300);
      final video = SmokeArtifacts.saveVideoFromPngFrames('video smoke: spinning', frames, fps: 30);
      expect(video.path, endsWith('video_smoke_spinning.webm'));
      expect(video.readAsBytesSync().sublist(0, 4), [0x1A, 0x45, 0xDF, 0xA3], reason: 'EBML magic');
      final probed = SmokeArtifacts.probeVideo(video.path)!;
      expect(probed.seconds, closeTo(10, 0.05), reason: 'the probe agrees with frames / fps');
      expect((probed.width, probed.height), (1024, 768), reason: 'encoded at the frame size');

      final json = _sidecar(video);
      expect(json['test'], 'video smoke: spinning');
      expect(json['video'], 'video_smoke_spinning.webm');
      expect(json['videoType'], 'video/webm');
      expect(json['frameCount'], 300);
      expect(json['fps'], 30);
      expect(json['durationSeconds'], 10);
      expect(json['width'], 1024);
      expect(json['height'], 768);
      expect(json['encoder'], SmokeWebm.gstreamerEncodesPng ? 'GStreamer' : 'ffmpeg',
          reason: 'GStreamer encodes where it is installed; ffmpeg only where it is not');
      expect((json['usedAssets'] as List).single, 'Props/AC_units/ac_unit_a_300x300.glb');

      // A later screenshot does not clobber the video keys.
      SmokeArtifacts.saveScreenshot('video smoke: spinning', frames.first);
      final json2 = _sidecar(video);
      expect(json2['video'], 'video_smoke_spinning.webm');
      expect(json2['file'], 'video_smoke_spinning.png');
    });

    test('saveVideoFromPngFrames refuses an empty list, and short, stretched, choppy, frozen or small videos', () {
      expect(() => SmokeArtifacts.saveVideoFromPngFrames('empty', const []), throwsArgumentError);
      expect(
        () => SmokeArtifacts.saveVideoFromPngFrames('short smoke: 2 s dolly', _rampFrames(60, w: 8, h: 8), fps: 30),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('short smoke: 2 s dolly'), contains('2.00 s'), contains('300 frames')))),
      );
      // 5 frames at 0.4 fps last 12.5 s, but every frame holds for 2.5 s.
      expect(() => SmokeArtifacts.saveVideoFromPngFrames('stretched smoke', _rampFrames(5), fps: 0.4),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('stretched smoke'))));
      // 150 frames at 15 fps last 10 s but are too choppy.
      expect(
        () => SmokeArtifacts.saveVideoFromPngFrames('choppy smoke', _rampFrames(150, w: 8, h: 8), fps: 15),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('choppy smoke'), contains('15.00 fps')))),
      );
      final frozen = List.filled(300, _rampFrames(1).single);
      expect(
        () => SmokeArtifacts.saveVideoFromPngFrames('frozen smoke', frozen, fps: 30),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('frozen smoke'), contains('repeats one frame')))),
      );
      expect(
        () => SmokeArtifacts.saveVideoFromPngFrames('small smoke', _rampFrames(300, w: 320, h: 240), fps: 30),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('small smoke'), contains('320×240'), contains('1024×768')))),
      );
      expect(tempDir.listSync(), isEmpty, reason: 'nothing is written for a refused video');
      // A pause shorter than 2 s inside a moving video is fine.
      final paused = [..._rampFrames(240, w: 8, h: 8), ...List.filled(60, _rampFrames(1, w: 8, h: 8).single)];
      SmokeArtifacts.checkFramesMove('paused smoke', paused, 30);
    });

    test('saveEncodedVideo checks the declared length, rate and size', () {
      final webm = Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 1, 2, 3, 4]);
      expect(() => SmokeArtifacts.saveEncodedVideo('enc short', webm, frameCount: 60, fps: 30),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('enc short'))));
      expect(() => SmokeArtifacts.saveEncodedVideo('enc 9 s', webm, durationSeconds: 9),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('9.00 s'))));
      expect(() => SmokeArtifacts.saveEncodedVideo('enc unknown', webm),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('enc unknown'))),
          reason: 'fake bytes: neither the metadata nor a probe can tell the length');
      expect(() => SmokeArtifacts.saveEncodedVideo('enc slow', webm, durationSeconds: 10, fps: 24, width: 1024, height: 768),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('24.00 fps'))));
      expect(() => SmokeArtifacts.saveEncodedVideo('enc no rate', webm, durationSeconds: 10, width: 1024, height: 768),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('frame rate'))));
      expect(() => SmokeArtifacts.saveEncodedVideo('enc small', webm, frameCount: 300, fps: 30, width: 640, height: 480),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('640×480'))));
      expect(() => SmokeArtifacts.saveEncodedVideo('enc no size', webm, frameCount: 300, fps: 30),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains('enc no size'))));
      expect(tempDir.listSync(), isEmpty);
      final ok = SmokeArtifacts.saveEncodedVideo('enc ok', webm, frameCount: 300, fps: 30, width: 1024, height: 768);
      expect(ok.existsSync(), isTrue);
    });

    test('saveVideo measures a real video, writes it and records the measurements', () {
      if (noEncoderReason != null) return markTestSkipped(noEncoderReason!);
      final file = SmokeArtifacts.saveVideoToDir(
        'level streaming: multi asset video test',
        realVideo(),
        Directory('${tempDir.path}/videos'),
        usedAssets: ['Props/Barrels/fuel_barrel_black.glb', 'Props/AC_units/ac_unit_a_300x300.glb'],
      );
      expect(file.path, endsWith('level_streaming_multi_asset_video_test.webm'));
      final json = _sidecar(file);
      expect(json['video'], 'level_streaming_multi_asset_video_test.webm');
      expect(json['durationSeconds'], closeTo(10.0, SmokeVideo.toleranceSeconds));
      expect(json['fps'], closeTo(30.0, 0.01));
      expect((json['width'], json['height']), (fw, fh));
      expect(json['usedAssets'], ['Props/Barrels/fuel_barrel_black.glb', 'Props/AC_units/ac_unit_a_300x300.glb']);
      expect(SmokeArtifacts.videoDurationSeconds(file), closeTo(10.0, SmokeVideo.toleranceSeconds));
      expect(SmokeArtifacts.videoFramesPerSecond(file), closeTo(30.0, 0.01));
      expect(SmokeArtifacts.videoFrameSize(file), (fw, fh));
    });

    test('saveVideo refuses a real video under 10 s, 30 fps or 1024×768 and writes nothing', () {
      final short = legacyWebm(seconds: 3, width: fw, height: fh);
      if (short == null) return markTestSkipped(noEncoderReason ?? 'no encoder');
      expect(() => SmokeArtifacts.saveVideo('pie: too short', short),
          throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('pie: too short'), contains('3.00 s')))));
      expect(() => SmokeArtifacts.saveVideo('stutter', legacyWebm(seconds: 11, width: fw, height: fh)!),
          throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('stutter'), contains('10.00 fps')))));
      expect(
        () => SmokeArtifacts.saveVideo('thumbnail', legacyWebm(seconds: 11, width: 640, height: 360)!, fps: 30),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('thumbnail'), contains('640×360')))),
      );
      expect(tempDir.listSync(), isEmpty);
    });

    test('encodeWebmFromRgbaFrames refuses one frame stretched over the video', () {
      expect(
        () => SmokeArtifacts.encodeWebmFromRgbaFrames(
            width: fw, height: fh, frames: movingFrames(5), frameDurationMs: 2500, testName: 'slideshow'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('slideshow'), contains('0.40 fps')))),
      );
    });
  });

  // `which` does not exist on Windows (and Git Bash's answers with an MSYS
  // path no process can start), so ffmpeg / ffprobe are found by starting
  // them by name.
  group('ffmpeg and ffprobe are found on the PATH', () {
    final ffmpegOnPath = _onPath('ffmpeg');
    final ffprobeOnPath = _onPath('ffprobe');

    test('ffmpeg on the PATH makes the video encoder available', () {
      if (!ffmpegOnPath) return markTestSkipped('ffmpeg is not on the PATH here');
      expect(SmokeTools.ffmpeg, isNotNull);
      expect(SmokeArtifacts.videoEncoderAvailable, isTrue);
    });

    test('encodeWebmFromPngFrames encodes a WebM that the probe reads back', () {
      if (noEncoderReason != null) return markTestSkipped(noEncoderReason!);
      final png = SmokeArtifacts.encodePng(64, 48, Uint8List(64 * 48 * 4)..fillRange(0, 64 * 48 * 4, 200));
      final webm = SmokeArtifacts.encodeWebmFromPngFrames(List.filled(30, png));
      expect(webm.sublist(0, 4), [0x1A, 0x45, 0xDF, 0xA3]);
      if (!ffprobeOnPath && !SmokeVideo.gstreamerAvailable) return;
      final file = File('${tempDir.path}/v.webm')..writeAsBytesSync(webm);
      final probe = SmokeArtifacts.probeVideo(file.path)!;
      expect((probe.width, probe.height), (64, 48));
    });
  });
}

int _indexOf(Uint8List bytes, List<int> pattern) {
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var ok = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
