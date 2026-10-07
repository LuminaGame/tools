import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gstreamer/src/exceptions.dart';
import 'package:flutter_gstreamer/src/gstreamer.dart';
import 'package:flutter_gstreamer/src/pipeline.dart';

/// What [VideoEncoder.addFrame] receives.
enum VideoInput {
  /// Complete PNG files (any size, but all frames the same size); decoded by
  /// GStreamer's `pngdec`.
  png,

  /// Tightly packed 8-bit RGBA pixels, `width * height * 4` bytes per frame.
  rgba,
}

/// The output format. Only VP8 in WebM for now.
enum VideoFormat {
  /// VP8 (`vp8enc`) in a WebM container (`webmmux`).
  webmVp8,
}

/// An exact rational frame rate (`numerator / denominator` frames per second).
final class FrameRate {
  const FrameRate(this.numerator, [this.denominator = 1])
    : assert(numerator > 0),
      assert(denominator > 0);

  /// [fps] as the smallest exact fraction with a denominator of 1, 10, 100,
  /// 1000 or 1001 (29.97 → 2997/100); other values are rounded to 1/1000.
  factory FrameRate.fromFps(double fps) {
    if (!(fps > 0) || !fps.isFinite) {
      throw ArgumentError.value(fps, 'fps', 'must be a positive finite number');
    }
    for (final den in const [1, 10, 100, 1000, 1001]) {
      final n = fps * den;
      if ((n - n.roundToDouble()).abs() < 1e-6) {
        return FrameRate._reduced(n.round(), den);
      }
    }
    return FrameRate._reduced((fps * 1000).round(), 1000);
  }

  factory FrameRate._reduced(int n, int d) {
    final g = n.gcd(d);
    return FrameRate(n ~/ g, d ~/ g);
  }

  final int numerator;
  final int denominator;

  /// Frames per second as a double.
  double get fps => numerator / denominator;

  /// The presentation time of frame [index] in nanoseconds (exact, so
  /// `300` frames at `30/1` end at exactly 10 s).
  int timestampNs(int index) => index * 1000000000 * denominator ~/ numerator;

  @override
  bool operator ==(Object other) =>
      other is FrameRate &&
      other.numerator * denominator == numerator * other.denominator;

  @override
  int get hashCode => (numerator / denominator).hashCode;

  /// `numerator/denominator`, the caps notation.
  @override
  String toString() => '$numerator/$denominator';
}

/// `vp8enc` settings. The defaults ([smoke]) are the Lumina smoke-video
/// settings: quality over speed — constrained quality `cq-level=6` capped at
/// 20 Mbit/s, quantizer 0–16, libvpx's "good" deadline (1 s per frame; below
/// one frame interval libvpx drops to realtime) with `cpu-used=2`, and a
/// keyframe at least every 150 frames.
final class Vp8Quality {
  const Vp8Quality({
    this.cqLevel = 6,
    this.minQuantizer = 0,
    this.maxQuantizer = 16,
    this.targetBitrate = 20000000,
    this.deadline = 1000000,
    this.cpuUsed = 2,
    this.keyframeMaxDistance = 150,
    this.threads,
  });

  /// The smoke-video settings (the same as `vp8QualitySettings` in Lumina's
  /// SmokeArtifacts and its ffmpeg `libvpx -crf 6 -b:v 20M -qmin 0 -qmax 16
  /// -quality good -cpu-used 2 -g 150` counterpart).
  static const smoke = Vp8Quality();

  final int cqLevel;
  final int minQuantizer;
  final int maxQuantizer;

  /// Bits per second.
  final int targetBitrate;

  /// Microseconds per frame the encoder may spend (`1` = realtime).
  final int deadline;
  final int cpuUsed;
  final int keyframeMaxDistance;

  /// Encoder threads (null: vp8enc's default).
  final int? threads;

  /// The `vp8enc` properties, as `gst-launch` would write them.
  Map<String, String> get properties => {
    'end-usage': 'cq',
    'cq-level': '$cqLevel',
    'min-quantizer': '$minQuantizer',
    'max-quantizer': '$maxQuantizer',
    'target-bitrate': '$targetBitrate',
    'deadline': '$deadline',
    'cpu-used': '$cpuUsed',
    'keyframe-max-dist': '$keyframeMaxDistance',
    if (threads != null) 'threads': '$threads',
  };
}

/// Encodes frames into a video file in-process through a GStreamer
/// `appsrc ! (pngdec !) videoconvert ! vp8enc ! webmmux ! filesink` pipeline.
///
/// Every frame is shown for exactly `1 / frameRate`: frame `i` is stamped
/// with [FrameRate.timestampNs] `(i)`, so `n` frames play for `n / fps`
/// seconds (300 frames at 30/1 → 10.000 s).
///
/// One-shot:
/// ```dart
/// VideoEncoder.encodePngFrames(pngs, out: File('smoke.webm'));   // 30 fps
/// ```
/// Streaming (frames as they are rendered):
/// ```dart
/// final enc = VideoEncoder.rgba(width: 1024, height: 768, out: file);
/// for (...) enc.addFrame(rgbaBytes);
/// enc.finish();                                  // waits for the muxer
/// ```
final class VideoEncoder {
  VideoEncoder._(
    this.input,
    this.out,
    this.frameRate,
    this._pipeline,
    this._src,
    this._frameBytes,
  );

  /// The frame kind [addFrame] expects.
  final VideoInput input;

  /// The file being written.
  final File out;

  final FrameRate frameRate;
  final GstPipeline _pipeline;
  final GstAppSrc _src;
  final int? _frameBytes;
  int _frames = 0;
  bool _closed = false;

  /// Frames added so far.
  int get frameCount => _frames;

  /// The GStreamer elements an encoder for [input] and [format] needs.
  static List<String> requiredElements(
    VideoInput input, [
    VideoFormat format = VideoFormat.webmVp8,
  ]) => [
    'appsrc',
    if (input == VideoInput.png) 'pngdec',
    'videoconvert',
    'vp8enc',
    'webmmux',
    'filesink',
  ];

  /// An encoder taking PNG files.
  factory VideoEncoder.png({
    required File out,
    FrameRate frameRate = const FrameRate(30),
    VideoFormat format = VideoFormat.webmVp8,
    Vp8Quality quality = Vp8Quality.smoke,
    GStreamer? gstreamer,
  }) => _open(
    VideoInput.png,
    out,
    frameRate,
    format,
    quality,
    gstreamer,
    null,
    null,
  );

  /// An encoder taking raw RGBA frames of [width] × [height].
  factory VideoEncoder.rgba({
    required int width,
    required int height,
    required File out,
    FrameRate frameRate = const FrameRate(30),
    VideoFormat format = VideoFormat.webmVp8,
    Vp8Quality quality = Vp8Quality.smoke,
    GStreamer? gstreamer,
  }) {
    if (width <= 0) throw ArgumentError.value(width, 'width', 'must be > 0');
    if (height <= 0) throw ArgumentError.value(height, 'height', 'must be > 0');
    return _open(
      VideoInput.rgba,
      out,
      frameRate,
      format,
      quality,
      gstreamer,
      width,
      height,
    );
  }

  static VideoEncoder _open(
    VideoInput input,
    File out,
    FrameRate rate,
    VideoFormat format,
    Vp8Quality quality,
    GStreamer? gstreamer,
    int? width,
    int? height,
  ) {
    final gst = gstreamer ?? GStreamer.instance;
    gst.requireElements(
      requiredElements(input, format),
      purpose: 'encoding ${format.name} video',
    );
    out.parent.createSync(recursive: true);
    if (out.existsSync()) out.deleteSync();
    final frameBytes = width == null ? null : width * height! * 4;
    // block=true: addFrame waits while the queue holds max-bytes, so a fast
    // producer never buffers the whole video in memory.
    final maxBytes = frameBytes == null ? 16 << 20 : frameBytes * 4;
    final pipeline = GstPipeline.parse(
      'appsrc name=src format=time block=true is-live=false max-bytes=$maxBytes '
      '! ${input == VideoInput.png ? 'pngdec ! ' : ''}videoconvert ! video/x-raw,format=I420 '
      '! vp8enc name=enc ! webmmux ! filesink name=sink',
      gstreamer: gst,
    );
    try {
      pipeline.element('enc')!.setAll(quality.properties);
      pipeline.element('sink')!.set('location', out.absolute.path);
      final src = pipeline.appSrc('src');
      src.setCaps(
        input == VideoInput.png
            ? 'image/png,framerate=$rate,parsed=(boolean)true'
            : 'video/x-raw,format=RGBA,width=$width,height=$height,framerate=$rate',
      );
      pipeline.play();
      return VideoEncoder._(input, out, rate, pipeline, src, frameBytes);
    } catch (_) {
      pipeline.dispose();
      rethrow;
    }
  }

  /// Adds the next frame (a PNG file or RGBA pixels, per [input]). Throws
  /// [ArgumentError] for a frame of the wrong kind or size and
  /// [GStreamerException] when the pipeline has failed.
  void addFrame(Uint8List frame) {
    if (_closed) throw StateError('VideoEncoder is already finished');
    if (_frameBytes != null && frame.length != _frameBytes) {
      throw ArgumentError.value(
        frame.length,
        'frame',
        'an RGBA frame must be exactly $_frameBytes bytes',
      );
    }
    if (input == VideoInput.png && !_isPng(frame)) {
      throw ArgumentError.value(
        frame.length,
        'frame',
        'not a PNG file (no PNG signature)',
      );
    }
    final pts = frameRate.timestampNs(_frames);
    try {
      _src.pushBuffer(
        frame,
        ptsNs: pts,
        durationNs: frameRate.timestampNs(_frames + 1) - pts,
      );
    } on GStreamerException {
      _pipeline.throwIfError(); // the real cause, when the pipeline posted one
      rethrow;
    }
    _frames++;
    if (_frames % 30 == 0) _pipeline.throwIfError();
  }

  /// Ends the stream and waits (up to [timeout]) until the muxer has written
  /// and closed [out]. Throws [GStreamerException] on a pipeline error, a
  /// timeout, or an empty output.
  void finish({Duration timeout = const Duration(minutes: 10)}) {
    if (_closed) throw StateError('VideoEncoder is already finished');
    _closed = true;
    try {
      if (_frames == 0) {
        throw StateError('VideoEncoder.finish without any frame');
      }
      _src.endOfStream();
      _pipeline.waitForEos(timeout: timeout);
      _pipeline.stop();
    } finally {
      _pipeline.dispose();
    }
    if (!out.existsSync() || out.lengthSync() == 0) {
      throw GStreamerException(
        'The encoder finished but wrote no data to ${out.path}',
      );
    }
  }

  /// Stops without finishing the file (which is left incomplete).
  void abort() {
    if (_closed) return;
    _closed = true;
    _pipeline.dispose();
  }

  /// Encodes [pngFrames] (all the same size) into [out] at [frameRate].
  static void encodePngFrames(
    Iterable<Uint8List> pngFrames, {
    required File out,
    FrameRate frameRate = const FrameRate(30),
    VideoFormat format = VideoFormat.webmVp8,
    Vp8Quality quality = Vp8Quality.smoke,
    Duration timeout = const Duration(minutes: 10),
  }) {
    if (pngFrames.isEmpty) {
      throw ArgumentError.value(pngFrames, 'pngFrames', 'no frames');
    }
    _encodeAll(
      VideoEncoder.png(
        out: out,
        frameRate: frameRate,
        format: format,
        quality: quality,
      ),
      pngFrames,
      timeout,
    );
  }

  /// Encodes [rgbaFrames] (each `width * height * 4` bytes) into [out].
  static void encodeRgbaFrames(
    Iterable<Uint8List> rgbaFrames, {
    required int width,
    required int height,
    required File out,
    FrameRate frameRate = const FrameRate(30),
    VideoFormat format = VideoFormat.webmVp8,
    Vp8Quality quality = Vp8Quality.smoke,
    Duration timeout = const Duration(minutes: 10),
  }) {
    if (rgbaFrames.isEmpty) {
      throw ArgumentError.value(rgbaFrames, 'rgbaFrames', 'no frames');
    }
    _encodeAll(
      VideoEncoder.rgba(
        width: width,
        height: height,
        out: out,
        frameRate: frameRate,
        format: format,
        quality: quality,
      ),
      rgbaFrames,
      timeout,
    );
  }

  static void _encodeAll(
    VideoEncoder encoder,
    Iterable<Uint8List> frames,
    Duration timeout,
  ) {
    try {
      frames.forEach(encoder.addFrame);
      encoder.finish(timeout: timeout);
    } finally {
      encoder.abort();
    }
  }

  static bool _isPng(Uint8List b) =>
      b.length > 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;
}
