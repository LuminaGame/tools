import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:flutter_gstreamer/src/bindings/gstreamer.g.dart' as raw;
import 'package:flutter_gstreamer/src/exceptions.dart';
import 'package:flutter_gstreamer/src/gstreamer.dart';

/// What [MediaProbe.probe] found out about a media file.
final class MediaInfo {
  MediaInfo({
    required this.durationNs,
    required this.seekable,
    this.containerCaps,
    this.videoCaps,
    this.width,
    this.height,
    this.frameRateNumerator = 0,
    this.frameRateDenominator = 1,
    this.videoBitrate,
    this.audioStreams = 0,
  });

  /// Playback length in nanoseconds.
  final int durationNs;

  /// Playback length.
  Duration get duration => Duration(microseconds: durationNs ~/ 1000);

  /// Playback length in seconds.
  double get durationSeconds => durationNs / 1e9;

  final bool seekable;

  /// The top-level stream's caps, e.g. `video/webm` (null for a bare stream).
  final String? containerCaps;

  /// The first video stream's caps, e.g. `video/x-vp8, width=(int)1024, ...`.
  final String? videoCaps;

  /// The first video stream's size (null without a video stream).
  final int? width;
  final int? height;

  /// The first video stream's frame rate (0/1 when unknown or variable).
  final int frameRateNumerator;
  final int frameRateDenominator;

  /// Frames per second, or null when unknown.
  double? get fps => frameRateNumerator > 0 && frameRateDenominator > 0
      ? frameRateNumerator / frameRateDenominator
      : null;

  /// The video stream's nominal bitrate in bit/s, when the container says.
  final int? videoBitrate;

  final int audioStreams;

  /// The container's media type (`video/webm`, `video/quicktime`, ...).
  String? get containerType => _mediaType(containerCaps);

  /// The video codec's media type (`video/x-vp8`, `video/x-h264`, ...).
  String? get videoCodec => _mediaType(videoCaps);

  static String? _mediaType(String? caps) => caps?.split(',').first.trim();

  @override
  String toString() =>
      'MediaInfo(${durationSeconds.toStringAsFixed(3)} s, ${width}x$height @ '
      '$frameRateNumerator/$frameRateDenominator, $containerType / $videoCodec)';
}

/// Reads a media file's duration, frame size, frame rate and formats with
/// GStreamer's `GstDiscoverer` (synchronous; no FFmpeg needed).
abstract final class MediaProbe {
  /// Probes [file]. Throws [GStreamerException] when it is missing or not a
  /// media file GStreamer can read.
  static MediaInfo probe(
    File file, {
    Duration timeout = const Duration(seconds: 30),
    GStreamer? gstreamer,
  }) {
    final gst = gstreamer ?? GStreamer.instance;
    final b = gst.bindings;
    if (!file.existsSync()) {
      throw GStreamerException('No such file: ${file.path}');
    }
    return using((arena) {
      final err = arena<ffi.Pointer<raw.GError>>();
      final uriPtr = b.gst_filename_to_uri(
        file.absolute.path.toNativeUtf8(allocator: arena).cast(),
        err,
      );
      final uriError = takeError(b, err.value);
      final uri = takeString(b, uriPtr);
      if (uri == null) {
        throw GStreamerException(
          'Not a valid file name: ${file.path} ($uriError)',
        );
      }

      err.value = ffi.nullptr;
      final discoverer = b.gst_discoverer_new(
        timeout.inMicroseconds * 1000,
        err,
      );
      final newError = takeError(b, err.value);
      if (discoverer == ffi.nullptr) {
        throw GStreamerException('gst_discoverer_new failed: $newError');
      }
      try {
        err.value = ffi.nullptr;
        final info = b.gst_discoverer_discover_uri(
          discoverer,
          uri.toNativeUtf8(allocator: arena).cast(),
          err,
        );
        final error = takeError(b, err.value);
        if (info == ffi.nullptr) {
          throw GStreamerException(
            'Could not probe ${file.path}: ${error ?? 'unknown error'}',
          );
        }
        try {
          final result = b.gst_discoverer_info_get_result(info);
          if (result != raw.GstDiscovererResult.GST_DISCOVERER_OK) {
            throw GStreamerException(
              'Could not probe ${file.path}: ${error ?? _resultName(result)}',
            );
          }
          return _read(b, info);
        } finally {
          b.g_object_unref(info.cast());
        }
      } finally {
        b.g_object_unref(discoverer.cast());
      }
    });
  }

  static MediaInfo _read(
    raw.GStreamerBindings b,
    ffi.Pointer<raw.GstDiscovererInfo> info,
  ) {
    String? capsOf(ffi.Pointer<raw.GstDiscovererStreamInfo> s) {
      final caps = b.gst_discoverer_stream_info_get_caps(s);
      if (caps == ffi.nullptr) return null;
      try {
        return takeString(b, b.gst_caps_to_string(caps));
      } finally {
        b.gst_mini_object_unref(caps.cast());
      }
    }

    final top = b.gst_discoverer_info_get_stream_info(info);
    String? containerCaps;
    if (top != ffi.nullptr) {
      final nick = b
          .gst_discoverer_stream_info_get_stream_type_nick(top)
          .cast<Utf8>()
          .toDartString();
      if (nick == 'container') containerCaps = capsOf(top);
      b.g_object_unref(top.cast());
    }

    final audio = b.gst_discoverer_info_get_audio_streams(info);
    final audioCount = b.g_list_length(audio);
    b.gst_discoverer_stream_info_list_free(audio);

    final videos = b.gst_discoverer_info_get_video_streams(info);
    try {
      int? width, height, bitrate;
      var num = 0, den = 1;
      String? videoCaps;
      if (videos != ffi.nullptr) {
        final v = videos.ref.data.cast<raw.GstDiscovererVideoInfo>();
        width = b.gst_discoverer_video_info_get_width(v);
        height = b.gst_discoverer_video_info_get_height(v);
        num = b.gst_discoverer_video_info_get_framerate_num(v);
        den = b.gst_discoverer_video_info_get_framerate_denom(v);
        final br = b.gst_discoverer_video_info_get_bitrate(v);
        bitrate = br == 0 ? null : br;
        videoCaps = capsOf(v.cast());
      }
      return MediaInfo(
        durationNs: b.gst_discoverer_info_get_duration(info),
        seekable: b.gst_discoverer_info_get_seekable(info) != 0,
        containerCaps: containerCaps,
        videoCaps: videoCaps,
        width: width,
        height: height,
        frameRateNumerator: num,
        frameRateDenominator: den == 0 ? 1 : den,
        videoBitrate: bitrate,
        audioStreams: audioCount,
      );
    } finally {
      b.gst_discoverer_stream_info_list_free(videos);
    }
  }

  static String _resultName(int result) => switch (result) {
    raw.GstDiscovererResult.GST_DISCOVERER_URI_INVALID => 'invalid URI',
    raw.GstDiscovererResult.GST_DISCOVERER_ERROR => 'discoverer error',
    raw.GstDiscovererResult.GST_DISCOVERER_TIMEOUT => 'timed out',
    raw.GstDiscovererResult.GST_DISCOVERER_BUSY => 'discoverer busy',
    raw.GstDiscovererResult.GST_DISCOVERER_MISSING_PLUGINS => 'missing plugins',
    _ => 'GstDiscovererResult $result',
  };
}
