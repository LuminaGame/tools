import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gstreamer/flutter_gstreamer.dart' show GStreamer, GStreamerException, MediaProbe;

import 'package:lumina_smoke/src/tools.dart';

/// What [SmokeVideo] measured of one video file.
class SmokeVideoInfo {
  const SmokeVideoInfo({this.seconds, this.width, this.height, this.fps, this.encoder});

  /// Length in seconds, or null when it could not be read.
  final double? seconds;

  /// Frame size in pixels, or null when it could not be read.
  final int? width;
  final int? height;

  /// Frames per second, or null when it could not be read.
  final double? fps;

  /// What wrote the file (`GStreamer`, `ffmpeg`, or the muxing application a
  /// WebM names), or null when it does not say.
  final String? encoder;

  /// Whether every field is known.
  bool get isComplete => seconds != null && width != null && height != null && fps != null;

  /// Whether nothing is known.
  bool get isEmpty => seconds == null && width == null && height == null && fps == null;

  /// This, with the fields it lacks taken from [other].
  SmokeVideoInfo orElse(SmokeVideoInfo other) => SmokeVideoInfo(
        seconds: seconds ?? other.seconds,
        width: width ?? other.width,
        height: height ?? other.height,
        fps: fps ?? other.fps,
        encoder: encoder ?? other.encoder,
      );

  /// Whether this video is under the minimum length (or its length is
  /// unknown).
  bool get isTooShort => seconds == null || SmokeVideo.isTooShort(seconds!);

  /// Whether this video is under the minimum frame size (or its size is
  /// unknown).
  bool get isTooSmall => width == null || height == null || SmokeVideo.isTooSmall(width!, height!);

  /// Whether this video is under the minimum frame rate (or its rate is
  /// unknown).
  bool get isTooSlow => fps == null || SmokeVideo.isTooSlow(fps!);

  /// Whether this video breaks any of the smoke-video minimums.
  bool get breaksRule => isTooShort || isTooSmall || isTooSlow;

  /// `10.00 s, 1024×768, 30 fps`, with `… unknown` for what was not read.
  String get describe => '${seconds == null ? 'length unknown' : '${seconds!.toStringAsFixed(2)} s'}, '
      '${width == null || height == null ? 'size unknown' : '$width×$height'}, '
      '${fps == null ? 'fps unknown' : '${fps!.toStringAsFixed(fps! == fps!.roundToDouble() ? 0 : 2)} fps'}';

  @override
  String toString() => 'SmokeVideoInfo($describe)';
}

/// The smoke-video rules and how a video is measured.
///
/// Every smoke video shows the scenario as it runs: at least [minimumSeconds]
/// long, [minimumWidth] × [minimumHeight] or larger, [minimumFps] real frames
/// per second or more, and no frame held longer than
/// [maximumFrameHoldSeconds].
///
/// Plain Dart on purpose (`dart:io` and flutter_gstreamer's `dart:ffi`): the
/// report runner uses it under `dart run`.
abstract final class SmokeVideo {
  /// Every smoke video runs at least this long.
  static const double minimumSeconds = 10.0;

  /// Every smoke video is at least this wide…
  static const int minimumWidth = 1024;

  /// …and at least this tall.
  static const int minimumHeight = 768;

  /// Every smoke video plays at least this many frames per second, each a
  /// real frame of the running scene.
  static const int minimumFps = 30;

  /// Frame-rate slack for rates stored as a rounded frame duration (a 33 ms
  /// frame is 30.3 fps) or as NTSC 29.97.
  static const double fpsTolerance = 0.5;

  /// The size smoke renders default to: 16:9 at [minimumHeight].
  static const int defaultWidth = 1366;
  static const int defaultHeight = 768;

  /// The longest a single frame may stay on screen: a video is frames
  /// captured while the scene runs, never one frame stretched.
  static const double maximumFrameHoldSeconds = 2.0;

  /// Container rounding: a 10 s encode reads back as 9.999999 s.
  static const double toleranceSeconds = 0.05;

  /// Whether [seconds] is under [minimumSeconds], allowing [toleranceSeconds].
  static bool isTooShort(double seconds) => seconds < minimumSeconds - toleranceSeconds;

  /// Whether [fps] is under [minimumFps], allowing [fpsTolerance].
  static bool isTooSlow(double fps) => fps < minimumFps - fpsTolerance;

  /// Whether a [width] × [height] frame is under [minimumWidth] × [minimumHeight].
  static bool isTooSmall(int width, int height) => width < minimumWidth || height < minimumHeight;

  static bool? _gstreamer;

  /// Whether GStreamer loads in this process (then its discoverer measures
  /// videos before ffprobe is tried).
  static bool get gstreamerAvailable => _gstreamer ??= GStreamer.isAvailable();

  /// Measures the video in [file]: GStreamer's discoverer (flutter_gstreamer's
  /// `MediaProbe`, in-process) when GStreamer is installed, then ffprobe, then
  /// what a WebM declares in its header (Segment Info Duration, Video
  /// PixelWidth / PixelHeight, DefaultDuration). The first complete answer
  /// wins; otherwise the fields are merged in that order.
  static SmokeVideoInfo probe(File file) {
    if (!file.existsSync()) return const SmokeVideoInfo();
    var info = const SmokeVideoInfo();
    if (gstreamerAvailable) {
      try {
        final media = MediaProbe.probe(file);
        info = SmokeVideoInfo(
          seconds: media.durationNs > 0 ? media.durationSeconds : null,
          width: media.width,
          height: media.height,
          fps: media.fps,
        );
        if (info.isComplete) return info.orElse(SmokeVideoInfo(encoder: encoderOf(file)));
      } on GStreamerException {
        // Not a file the discoverer reads: try ffprobe.
      }
    }
    info = info.orElse(_ffprobe(file));
    if (info.isComplete) return info.orElse(SmokeVideoInfo(encoder: encoderOf(file)));
    try {
      return info.orElse(webmInfo(file.readAsBytesSync()));
    } on FileSystemException {
      return info;
    }
  }

  /// [probe] for bytes not yet on disk, written to a temporary `.[extension]`
  /// file first.
  static SmokeVideoInfo probeBytes(Uint8List bytes, {String extension = 'webm'}) {
    final dir = Directory.systemTemp.createTempSync('smoke_video_probe_');
    try {
      final file = File('${dir.path}/probe.$extension')..writeAsBytesSync(bytes, flush: true);
      return probe(file);
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// What wrote the WebM [file], from the muxing application its header
  /// names (see [encoderName]); null when it names none or is not a WebM.
  static String? encoderOf(File file) {
    try {
      final raf = file.openSync();
      try {
        // The Segment Info sits at the start of the file.
        return webmInfo(raf.readSync(64 * 1024)).encoder;
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      return null;
    }
  }

  /// `GStreamer` for a GStreamer muxer (`GStreamer matroskamux version …`),
  /// `ffmpeg` for libavformat (`Lavf…`), else [muxingApp] itself.
  static String? encoderName(String? muxingApp) {
    final app = muxingApp?.trim();
    if (app == null || app.isEmpty) return null;
    if (app.contains('GStreamer')) return 'GStreamer';
    if (app.startsWith('Lavf') || app.contains('ffmpeg')) return 'ffmpeg';
    return app;
  }

  static SmokeVideoInfo _ffprobe(File file) {
    final ffprobe = SmokeTools.ffprobe;
    if (ffprobe == null) return const SmokeVideoInfo();
    try {
      final result = Process.runSync(ffprobe, [
        '-v', 'error', //
        '-select_streams', 'v:0',
        '-show_entries', 'format=duration:stream=width,height,avg_frame_rate,r_frame_rate',
        '-of', 'json',
        file.path,
      ]);
      if (result.exitCode != 0) return const SmokeVideoInfo();
      final json = jsonDecode(result.stdout.toString());
      if (json is! Map) return const SmokeVideoInfo();
      final streams = json['streams'];
      final stream = streams is List && streams.isNotEmpty && streams.first is Map ? streams.first as Map : const {};
      final format = json['format'] is Map ? json['format'] as Map : const {};
      final seconds = double.tryParse('${format['duration']}');
      return SmokeVideoInfo(
        seconds: seconds != null && seconds.isFinite && seconds > 0 ? seconds : null,
        width: stream['width'] is int ? stream['width'] as int : null,
        height: stream['height'] is int ? stream['height'] as int : null,
        fps: _rate(stream['avg_frame_rate']) ?? _rate(stream['r_frame_rate']),
      );
    } on ProcessException {
      return const SmokeVideoInfo();
    } on FormatException {
      return const SmokeVideoInfo();
    }
  }

  /// An ffprobe rational such as `1000/33`; null for `0/0` or garbage.
  static double? _rate(Object? value) {
    if (value == null) return null;
    final parts = '$value'.split('/');
    final num = double.tryParse(parts.first);
    final den = parts.length > 1 ? double.tryParse(parts[1]) : 1.0;
    if (num == null || den == null || num <= 0 || den <= 0) return null;
    return num / den;
  }

  /// The Duration, and the first video track's pixel size and frame rate
  /// (DefaultDuration), a WebM / Matroska stream declares in its header, and
  /// its encoder (MuxingApp, else WritingApp; see [encoderName]); fields it
  /// does not declare are null. A truncated stream (only the start of a
  /// file) still gives what its first bytes declare.
  static SmokeVideoInfo webmInfo(Uint8List bytes) {
    const segment = 0x18538067;
    const info = 0x1549A966;
    const tracks = 0x1654AE6B;
    const trackEntry = 0xAE;
    const video = 0xE0;
    const timecodeScale = 0x2AD7B1;
    const duration = 0x4489;
    const pixelWidth = 0xB0;
    const pixelHeight = 0xBA;
    const defaultDuration = 0x23E383;
    const muxingApp = 0x4D80;
    const writingApp = 0x5741;
    const containers = {segment, info, tracks, trackEntry, video};

    final data = ByteData.sublistView(bytes);
    var scale = 1000000; // Matroska default: 1 ms ticks.
    double? ticks;
    int? width;
    int? height;
    int? frameNanos;
    String? muxer;
    String? writer;

    // An EBML variable-length integer at [pos]: an element ID (length marker
    // kept) or a size (marker stripped; all ones means "unknown size").
    (int value, int length, bool unknown)? vint(int pos, {required bool keepMarker}) {
      if (pos >= bytes.length) return null;
      final first = bytes[pos];
      var length = 1;
      var mask = 0x80;
      while (length <= 8 && (first & mask) == 0) {
        length++;
        mask >>= 1;
      }
      if (length > 8 || pos + length > bytes.length) return null;
      var value = keepMarker ? first : first & (mask - 1);
      var allOnes = (first & (mask - 1)) == mask - 1;
      for (var i = 1; i < length; i++) {
        value = (value << 8) | bytes[pos + i];
        if (bytes[pos + i] != 0xFF) allOnes = false;
      }
      return (value, length, !keepMarker && allOnes);
    }

    int uint(int start, int end) {
      var v = 0;
      for (var i = start; i < end; i++) {
        v = (v << 8) | bytes[i];
      }
      return v;
    }

    void walk(int pos, int end) {
      var seenTrack = false;
      while (pos < end) {
        final id = vint(pos, keepMarker: true);
        if (id == null) return;
        final size = vint(pos + id.$2, keepMarker: false);
        if (size == null) return;
        final bodyStart = pos + id.$2 + size.$2;
        final bodyEnd = size.$3 ? end : bodyStart + size.$1;
        if (bodyEnd < bodyStart) return;
        final element = id.$1;
        // A container cut off by the end of the bytes is read as far as it goes.
        if (bodyEnd > bytes.length && !containers.contains(element)) return;
        if (containers.contains(element)) {
          // Only the first track: the video a smoke saves.
          if (element != trackEntry || !seenTrack) walk(bodyStart, bodyEnd > bytes.length ? bytes.length : bodyEnd);
          if (element == trackEntry) seenTrack = true;
        } else if (element == timecodeScale) {
          final v = uint(bodyStart, bodyEnd);
          if (v > 0) scale = v;
        } else if (element == duration) {
          final length = bodyEnd - bodyStart;
          if (length == 4) ticks = data.getFloat32(bodyStart);
          if (length == 8) ticks = data.getFloat64(bodyStart);
        } else if (element == pixelWidth) {
          width ??= uint(bodyStart, bodyEnd);
        } else if (element == pixelHeight) {
          height ??= uint(bodyStart, bodyEnd);
        } else if (element == defaultDuration) {
          frameNanos ??= uint(bodyStart, bodyEnd);
        } else if (element == muxingApp) {
          muxer ??= utf8.decode(bytes.sublist(bodyStart, bodyEnd), allowMalformed: true);
        } else if (element == writingApp) {
          writer ??= utf8.decode(bytes.sublist(bodyStart, bodyEnd), allowMalformed: true);
        }
        pos = bodyEnd;
      }
    }

    walk(0, bytes.length);
    final t = ticks;
    return SmokeVideoInfo(
      seconds: t == null || !t.isFinite || t <= 0 ? null : t * scale / 1e9,
      width: width,
      height: height,
      fps: frameNanos == null || frameNanos! <= 0 ? null : 1e9 / frameNanos!,
      encoder: encoderName(muxer ?? writer),
    );
  }
}
