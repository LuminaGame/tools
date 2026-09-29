import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gstreamer/flutter_gstreamer.dart'
    show FrameRate, GStreamer, GStreamerException, VideoEncoder, VideoInput, Vp8Quality;

import 'tools.dart';
import 'video.dart';

/// VP8 / WebM encoding of smoke frames: in-process with GStreamer
/// (flutter_gstreamer, [Vp8Quality.smoke]) where it is installed, else with
/// `ffmpeg` (libvpx) using the same quality settings.
abstract final class SmokeWebm {
  /// The VP8 encoder settings every smoke video is encoded with: constant
  /// quality near-lossless (quantizer 0–16, cq-level 6) at up to 20 Mbit/s,
  /// good-quality mode (`deadline=1000000`, `cpu-used=2`), never the realtime
  /// `deadline=1`, which is the lowest quality, and a keyframe at least every
  /// 150 frames. The same as flutter_gstreamer's [Vp8Quality.smoke].
  static const List<String> vp8QualitySettings = [
    'end-usage=cq',
    'cq-level=6',
    'min-quantizer=0',
    'max-quantizer=16',
    'target-bitrate=20000000',
    'deadline=1000000',
    'cpu-used=2',
    'keyframe-max-dist=150',
  ];

  /// The ffmpeg (libvpx) counterpart of [vp8QualitySettings], used where
  /// GStreamer is not installed.
  static const List<String> ffmpegVp8QualitySettings = [
    '-c:v', 'libvpx', //
    '-crf', '6',
    '-qmin', '0',
    '-qmax', '16',
    '-b:v', '20M',
    '-deadline', 'good',
    '-cpu-used', '2',
    '-g', '150',
    '-auto-alt-ref', '0',
  ];

  /// yuv420p needs even dimensions: ffmpeg pads an odd side by one pixel.
  static const List<String> _ffmpegEvenPad = ['-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2'];

  static bool? _encodesPng;
  static bool? _encodesRgba;

  /// Whether GStreamer loads with every element the in-process PNG-frame
  /// encoder needs (pngdec, vp8enc, webmmux, …).
  static bool get gstreamerEncodesPng => _encodesPng ??= SmokeVideo.gstreamerAvailable &&
      GStreamer.instance.missingElements(VideoEncoder.requiredElements(VideoInput.png)).isEmpty;

  /// Whether GStreamer loads with every element the in-process RGBA encoder
  /// needs (appsrc, videoconvert, vp8enc, webmmux, filesink).
  static bool get gstreamerEncodesRgba => _encodesRgba ??= SmokeVideo.gstreamerAvailable &&
      GStreamer.instance.missingElements(VideoEncoder.requiredElements(VideoInput.rgba)).isEmpty;

  /// Whether any encoder is available: GStreamer or ffmpeg.
  static bool get available => gstreamerEncodesPng || gstreamerEncodesRgba || SmokeTools.ffmpeg != null;

  /// Encodes the back-to-back RGBA frames in the file [rawFrames] into a VP8
  /// WebM at [out], played at [rateNumerator] / [rateDenominator] fps (an
  /// exact rational rate, so the video runs exactly frames / rate). A
  /// GStreamer failure comes back as a non-zero exit code with the error as
  /// stderr. Throws a [ProcessException] when GStreamer is missing and ffmpeg
  /// cannot be started.
  static ProcessResult encodeRawRgba({
    required String rawFrames,
    required String out,
    required int width,
    required int height,
    required int rateNumerator,
    required int rateDenominator,
  }) {
    if (gstreamerEncodesRgba) {
      final frameBytes = width * height * 4;
      final input = File(rawFrames).openSync();
      VideoEncoder? encoder;
      try {
        encoder = VideoEncoder.rgba(
          width: width,
          height: height,
          out: File(out),
          frameRate: FrameRate(rateNumerator, rateDenominator),
          quality: Vp8Quality.smoke,
        );
        while (true) {
          final frame = input.readSync(frameBytes);
          if (frame.length < frameBytes) break;
          encoder.addFrame(frame);
        }
        encoder.finish();
        return ProcessResult(0, 0, '', '');
      } on GStreamerException catch (e) {
        return ProcessResult(0, 1, '', 'GStreamer: $e');
      } finally {
        encoder?.abort();
        input.closeSync();
      }
    }
    final ffmpeg = SmokeTools.ffmpeg;
    if (ffmpeg == null) {
      throw const ProcessException('ffmpeg', [], 'neither GStreamer (vp8enc, webmmux) nor ffmpeg was found');
    }
    return Process.runSync(ffmpeg, [
      '-y', '-hide_banner', '-loglevel', 'error', //
      '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', '${width}x$height',
      '-framerate', '$rateNumerator/$rateDenominator',
      '-i', rawFrames,
      ..._ffmpegEvenPad,
      ...ffmpegVp8QualitySettings,
      '-pix_fmt', 'yuv420p',
      '-f', 'webm',
      out,
    ]);
  }

  /// Encodes a file of back-to-back [width] × [height] RGBA frames into WebM
  /// bytes, each frame shown [frameDurationMs] (or at [framesPerSecond] when
  /// given). Throws a [StateError] when encoding fails: a smoke video is real
  /// frames or nothing, never a synthetic stand-in.
  static Uint8List encodeRawFile(
    File rawFrames, {
    required int width,
    required int height,
    required int frameDurationMs,
    int? framesPerSecond,
  }) {
    final tempDir = Directory.systemTemp.createTempSync('smoke_webm_');
    try {
      final outFile = File('${tempDir.path}/out.webm');
      // An exact rational frame rate keeps the duration exact (1500 ms → 2/3).
      final (rateNum, rateDen) = framesPerSecond != null ? (framesPerSecond, 1) : (1000, frameDurationMs);
      final ProcessResult result;
      try {
        result = encodeRawRgba(
          rawFrames: rawFrames.path,
          out: outFile.path,
          width: width,
          height: height,
          rateNumerator: rateNum,
          rateDenominator: rateDen,
        );
      } on ProcessException catch (e) {
        throw StateError('WebM encoding needs GStreamer (vp8enc, webmmux) or ffmpeg (libvpx): $e');
      }
      if (result.exitCode != 0 || !outFile.existsSync() || outFile.lengthSync() == 0) {
        throw StateError('WebM encoding failed (exit ${result.exitCode}): ${result.stderr}');
      }
      return outFile.readAsBytesSync();
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Encodes PNG frames of one resolution into WebM bytes at [fps], at that
  /// resolution (no scaling; ffmpeg pads an odd side by one pixel, GStreamer
  /// keeps it). Throws a [StateError] when no encoder is available or
  /// encoding fails.
  static Uint8List encodePngFrames(List<Uint8List> pngFrames, {double fps = 30}) {
    if (pngFrames.isEmpty) {
      throw ArgumentError.value(pngFrames, 'pngFrames', 'must contain at least one frame');
    }
    if (fps <= 0) throw ArgumentError.value(fps, 'fps', 'must be > 0');
    final tmp = Directory.systemTemp.createTempSync('smoke_webm_');
    try {
      final out = File('${tmp.path}/out.webm');
      if (gstreamerEncodesPng) {
        try {
          VideoEncoder.encodePngFrames(pngFrames, out: out, frameRate: FrameRate.fromFps(fps), quality: Vp8Quality.smoke);
        } on GStreamerException catch (e) {
          throw StateError('GStreamer failed to encode the WebM: $e');
        }
        return out.readAsBytesSync();
      }
      final ffmpeg = SmokeTools.ffmpeg;
      if (ffmpeg == null) {
        throw StateError('No video encoder: neither GStreamer (vp8enc, webmmux, pngdec) nor ffmpeg was found '
            '(install GStreamer, or put ffmpeg on the PATH / set LUMINA_SMOKE_FFMPEG)');
      }
      for (var i = 0; i < pngFrames.length; i++) {
        File('${tmp.path}/frame_${i.toString().padLeft(5, '0')}.png').writeAsBytesSync(pngFrames[i]);
      }
      final result = Process.runSync(ffmpeg, [
        '-y', '-hide_banner', '-loglevel', 'error', //
        '-framerate', fps.toString(),
        '-i', '${tmp.path}/frame_%05d.png',
        ..._ffmpegEvenPad,
        ...ffmpegVp8QualitySettings,
        '-pix_fmt', 'yuv420p',
        out.path,
      ]);
      if (result.exitCode != 0 || !out.existsSync() || out.lengthSync() == 0) {
        throw StateError('ffmpeg failed (exit ${result.exitCode}): ${result.stderr}');
      }
      return out.readAsBytesSync();
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}
