/// Dart FFI bindings to GStreamer 1.x, loaded dynamically at run time.
///
/// * [GStreamer] — find, load and initialise GStreamer; version, element checks.
/// * [GstPipeline] / [GstElement] / [GstAppSrc] — `gst_parse_launch`
///   pipelines, properties, state changes, bus messages, appsrc buffers.
/// * [VideoEncoder] — PNG or RGBA frames → VP8/WebM, in-process.
/// * [MediaProbe] — duration, size, frame rate and formats of a media file.
///
/// The raw ffigen bindings are in `package:flutter_gstreamer/bindings.dart`
/// (import it with a prefix: its C type names overlap these wrappers).
library;

export 'package:flutter_gstreamer/src/exceptions.dart';
export 'package:flutter_gstreamer/src/gstreamer.dart' show GStreamer, GStreamerVersion;
export 'package:flutter_gstreamer/src/libraries.dart';
export 'package:flutter_gstreamer/src/media_probe.dart';
export 'package:flutter_gstreamer/src/pipeline.dart';
export 'package:flutter_gstreamer/src/video_encoder.dart';
