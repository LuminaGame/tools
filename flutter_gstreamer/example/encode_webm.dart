// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gstreamer/flutter_gstreamer.dart';
import 'package:image/image.dart' as img;

/// Encodes 10 s of generated 640×360 PNG frames at 30 fps into a VP8 WebM
/// and probes it.
///
///     dart run example/encode_webm.dart [out.webm]
void main(List<String> args) {
  if (!GStreamer.isAvailable()) {
    print('GStreamer is not installed.');
    exitCode = 1;
    return;
  }
  print(GStreamer.instance.versionString);
  final out = File(
    args.isNotEmpty
        ? args.first
        : '${Directory.systemTemp.path}/flutter_gstreamer_example.webm',
  );
  const width = 640, height = 360, frames = 300;
  final encoder = VideoEncoder.png(out: out, frameRate: const FrameRate(30));
  for (var i = 0; i < frames; i++) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(20, 20, 40));
    final x = i * (width - 80) ~/ frames;
    img.fillRect(
      image,
      x1: x,
      y1: 140,
      x2: x + 80,
      y2: 220,
      color: img.ColorRgb8(255, 200, 0),
    );
    encoder.addFrame(Uint8List.fromList(img.encodePng(image, level: 1)));
  }
  encoder.finish();
  print('${out.path}: ${out.lengthSync()} bytes');
  print(MediaProbe.probe(out));
}
