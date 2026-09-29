import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_smoke/lumina_smoke.dart';

import 'support/videos.dart';

void main() {
  group('SmokeVideo', () {
    test('the rules allow container rounding and rounded frame rates', () {
      expect(SmokeVideo.isTooSlow(30.3), isFalse);
      expect(SmokeVideo.isTooSlow(29.97), isFalse);
      expect(SmokeVideo.isTooSlow(25), isTrue);
      expect(SmokeVideo.isTooShort(9.999999), isFalse);
      expect(SmokeVideo.isTooShort(9.96), isFalse);
      expect(SmokeVideo.isTooShort(9.94), isTrue);
      expect(SmokeVideo.isTooSmall(1024, 768), isFalse);
      expect(SmokeVideo.isTooSmall(1280, 720), isTrue);
      expect((SmokeVideo.defaultWidth, SmokeVideo.defaultHeight), (1366, 768));
    });

    test('measures a real WebM, and the WebM header alone gives the same answer', () {
      if (noEncoderReason != null) return markTestSkipped(noEncoderReason!);
      final bytes = realVideo();
      final probed = SmokeVideo.probeBytes(bytes);
      expect(probed.seconds, closeTo(10.0, SmokeVideo.toleranceSeconds));
      expect((probed.width, probed.height), (fw, fh), reason: 'encoded at the render size, never scaled');
      expect(probed.fps, closeTo(30.0, 0.01));
      expect(probed.breaksRule, isFalse);
      expect(probed.describe, '10.00 s, 1024×768, 30 fps');

      final header = SmokeVideo.webmInfo(bytes);
      expect(header.seconds, closeTo(10.0, SmokeVideo.toleranceSeconds),
          reason: 'the header gives the length where neither GStreamer nor ffprobe is installed');
      expect((header.width, header.height), (fw, fh));
      expect(header.fps, closeTo(30.0, 0.01));

      final encoder = SmokeWebm.gstreamerEncodesRgba ? 'GStreamer' : 'ffmpeg';
      expect(probed.encoder, encoder, reason: 'GStreamer encodes where it is installed; ffmpeg only where it is not');
      expect(header.encoder, encoder);
      expect(SmokeVideo.webmInfo(Uint8List.sublistView(bytes, 0, 4096)).encoder, encoder,
          reason: 'the start of the file names the muxer');
    });

    test('names the encoder from the muxing application', () {
      expect(SmokeVideo.encoderName('GStreamer matroskamux version 1.28.6'), 'GStreamer');
      expect(SmokeVideo.encoderName('Lavf61.7.100'), 'ffmpeg');
      expect(SmokeVideo.encoderName('mkvmerge v80'), 'mkvmerge v80');
      expect(SmokeVideo.encoderName(null), isNull);
      expect(SmokeVideo.encoderName(' '), isNull);
    });

    test('garbage and missing files measure as unknown, which breaks the rules', () {
      expect(SmokeVideo.webmInfo(Uint8List.fromList([1, 2, 3, 4])).seconds, isNull);
      final missing = SmokeVideo.probe(File('${Directory.systemTemp.path}/no_such_smoke_video.webm'));
      expect(missing.isEmpty, isTrue);
      expect(missing.breaksRule, isTrue);
      expect(missing.describe, 'length unknown, size unknown, fps unknown');
      const partial = SmokeVideoInfo(seconds: 12);
      expect(partial.orElse(const SmokeVideoInfo(seconds: 3, fps: 30)).seconds, 12);
      expect(partial.orElse(const SmokeVideoInfo(fps: 30)).fps, 30);
    });
  });

  group('SmokeVideoRecorder', () {
    test('refuses a video under 10 s, naming the test and its length', () {
      expect(
        () => record(90, testName: 'walks too briefly'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('walks too briefly'), contains('3.00 s')))),
      );
    });

    test('refuses a frozen stretch: ten seconds at 30 fps, but three of them one still image', () {
      // Frame 9 held through frame 99: 91 frames.
      expect(
        () => record(310, testName: 'frozen', frozen: (i) => i >= 10 && i < 100),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('frozen'), contains('3.03 s')))),
      );
    });

    test('refuses a rate under 30 fps and a size under 1024×768 up front', () {
      expect(
        () => SmokeVideoRecorder(width: fw, height: fh, fps: 15, testName: 'choppy'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('choppy'), contains('15.00 fps')))),
      );
      expect(
        () => SmokeVideoRecorder(width: 1280, height: 720, testName: 'letterbox'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('letterbox'), contains('1280×720')))),
      );
    });

    test('refuses a frame of the wrong size and counts what it recorded', () {
      final recorder = SmokeVideoRecorder(width: fw, height: fh, testName: 'sizes');
      addTearDown(recorder.discard);
      recorder.addFrame(frame(1));
      recorder.addFrame(frame(1));
      expect(recorder.frameCount, 2);
      expect(recorder.seconds, closeTo(2 / 30, 1e-9));
      expect(recorder.longestStillSeconds, closeTo(2 / 30, 1e-9));
      expect(() => recorder.addFrame(Uint8List(16)), throwsStateError);
    });
  });

  group('stale temporary directories', () {
    test('a directory nothing was written to for 30 minutes is purged, a live one is kept', () {
      final stale = Directory.systemTemp.createTempSync('smoke_purge_test_');
      final live = Directory.systemTemp.createTempSync('smoke_purge_test_');
      addTearDown(() {
        for (final d in [stale, live]) {
          if (d.existsSync()) d.deleteSync(recursive: true);
        }
      });
      final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));
      File('${stale.path}/frames.rgba')
        ..writeAsBytesSync(List.filled(16, 0))
        ..setLastModifiedSync(twoHoursAgo);
      File('${live.path}/frames.rgba').writeAsBytesSync(List.filled(16, 0));
      SmokeTempDirs.purgeStale('smoke_purge_test_', force: true);
      expect(stale.existsSync(), isFalse, reason: 'nothing written for two hours');
      expect(live.existsSync(), isTrue, reason: 'a live recording is left alone');
    });
  });
}
