/// The raw ffigen-generated GStreamer / GLib bindings
/// (`lib/src/bindings/gstreamer.g.dart`, see `tool/ffigen.dart`).
///
/// Get a ready instance from `GStreamer.init().bindings`. Import this library
/// with a prefix (`as gst`): names such as `GstElement` also exist as
/// wrappers in `package:flutter_gstreamer/flutter_gstreamer.dart`.
library;

export 'src/bindings/gstreamer.g.dart';
