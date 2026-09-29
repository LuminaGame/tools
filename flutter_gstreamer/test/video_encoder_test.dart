import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gstreamer/flutter_gstreamer.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// 300 real PNG frames (a square moving over a colour ramp) at [width]×[height].
List<Uint8List> pngFrames(int count, int width, int height) => [
  for (var i = 0; i < count; i++)
    img.encodePng(_frame(i, count, width, height), level: 1),
];

img.Image _frame(int i, int count, int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(
    image,
    color: img.ColorRgb8((i * 255) ~/ count, 40, 255 - (i * 255) ~/ count),
  );
  final x = (i * (width - 64)) ~/ count;
  img.fillRect(
    image,
    x1: x,
    y1: height ~/ 3,
    x2: x + 64,
    y2: height ~/ 3 + 64,
    color: img.ColorRgb8(255, 255, 255),
  );
  return image;
}

/// ffprobe (FFmpeg), for an independent cross-check, or null when absent.
String? _ffprobe() {
  final local = Platform.environment['LOCALAPPDATA'];
  final candidates = [
    if (local != null) '$local/Microsoft/WinGet/Links/ffprobe.exe',
    for (final dir in (Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    ))
      if (dir.isNotEmpty)
        '$dir/${Platform.isWindows ? 'ffprobe.exe' : 'ffprobe'}',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

void main() {
  late Directory tmp;

  setUpAll(() {
    GStreamer.init();
    tmp = Directory.systemTemp.createTempSync('gst_encoder_test_');
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  group('VideoEncoder.encodePngFrames', () {
    const width = 1024, height = 768, count = 300;
    late File out;
    late MediaInfo info;

    setUpAll(() {
      out = File('${tmp.path}/ten_seconds.webm');
      VideoEncoder.encodePngFrames(
        pngFrames(count, width, height),
        out: out,
        frameRate: const FrameRate(30),
      );
      info = MediaProbe.probe(out);
    });

    test('writes a non-empty file', () {
      expect(out.existsSync(), isTrue);
      expect(out.lengthSync(), greaterThan(10000));
    });

    test('probe: 300 frames at 30 fps last 10.0 s', () {
      expect(info.durationSeconds, closeTo(10.0, 0.1));
      expect(info.duration.inMilliseconds, closeTo(10000, 100));
    });

    test('probe: frame size and frame rate', () {
      expect(info.width, width);
      expect(info.height, height);
      expect(info.fps, closeTo(30, 1e-9));
      expect(info.frameRateNumerator / info.frameRateDenominator, 30);
    });

    test('is VP8 in a WebM container', () {
      expect(info.containerType, 'video/webm');
      expect(info.videoCodec, 'video/x-vp8');
      final head = out.openSync()..setPositionSync(0);
      final bytes = head.readSync(64);
      head.closeSync();
      expect(bytes.sublist(0, 4), [
        0x1A,
        0x45,
        0xDF,
        0xA3,
      ], reason: 'EBML magic');
      expect(
        latin1.decode(bytes, allowInvalid: true),
        contains('webm'),
        reason: 'EBML DocType',
      );
    });

    test('ffprobe agrees (skipped when FFmpeg is not installed)', () {
      final ffprobe = _ffprobe();
      if (ffprobe == null) {
        markTestSkipped('ffprobe not found');
        return;
      }
      final r = Process.runSync(ffprobe, [
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_entries',
        'stream=codec_name,width,height,avg_frame_rate:format=format_name,duration',
        '-of',
        'json',
        out.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final json = jsonDecode('${r.stdout}') as Map<String, dynamic>;
      final stream = (json['streams'] as List).single as Map<String, dynamic>;
      final format = json['format'] as Map<String, dynamic>;
      expect(stream['codec_name'], 'vp8');
      expect(stream['width'], width);
      expect(stream['height'], height);
      expect(stream['avg_frame_rate'], '30/1');
      expect(format['format_name'], contains('webm'));
      expect(double.parse(format['duration'] as String), closeTo(10.0, 0.1));
    });
  });

  group('VideoEncoder (RGBA, streaming)', () {
    test('encodes raw RGBA frames added one by one', () {
      const w = 160, h = 120, n = 60;
      final out = File('${tmp.path}/rgba.webm');
      final encoder = VideoEncoder.rgba(
        width: w,
        height: h,
        out: out,
        frameRate: const FrameRate(30),
      );
      for (var i = 0; i < n; i++) {
        encoder.addFrame(
          _frame(
            i,
            n,
            w,
            h,
          ).convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba),
        );
      }
      expect(encoder.frameCount, n);
      encoder.finish();
      final info = MediaProbe.probe(out);
      expect(info.durationSeconds, closeTo(2.0, 0.1));
      expect((info.width, info.height), (w, h));
      expect(info.fps, closeTo(30, 1e-9));
      expect(info.videoCodec, 'video/x-vp8');
    });

    test(
      'a wrongly sized RGBA frame is rejected before it reaches GStreamer',
      () {
        final encoder = VideoEncoder.rgba(
          width: 8,
          height: 8,
          out: File('${tmp.path}/bad.webm'),
        );
        addTearDown(encoder.abort);
        expect(() => encoder.addFrame(Uint8List(10)), throwsArgumentError);
      },
    );

    test('non-integer rates stay exact rationals', () {
      expect(FrameRate.fromFps(30).toString(), '30/1');
      expect(FrameRate.fromFps(29.97).toString(), '2997/100');
      expect(const FrameRate(1000, 1500).fps, closeTo(2 / 3, 1e-12));
      expect(const FrameRate(30).timestampNs(300), 10000000000);
    });

    test('no frames is an ArgumentError', () {
      expect(
        () => VideoEncoder.encodePngFrames(
          const [],
          out: File('${tmp.path}/none.webm'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('MediaProbe', () {
    test('a file that is not media fails with a GStreamerException', () {
      final junk = File('${tmp.path}/junk.webm')
        ..writeAsStringSync('not a video');
      expect(() => MediaProbe.probe(junk), throwsA(isA<GStreamerException>()));
    });

    test('a missing file fails with a GStreamerException', () {
      expect(
        () => MediaProbe.probe(File('${tmp.path}/missing.webm')),
        throwsA(isA<GStreamerException>()),
      );
    });
  });
}
