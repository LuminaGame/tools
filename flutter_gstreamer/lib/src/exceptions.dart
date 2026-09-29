/// GStreamer's shared libraries could not be found or loaded.
///
/// Thrown by `GStreamerLibraries.open` / `GStreamer.init` (and everything
/// that initialises GStreamer on first use) when GStreamer is not installed,
/// or an explicit `root` does not hold it. Catch it to fall back to another
/// encoder or to skip.
class GStreamerNotFoundException implements Exception {
  GStreamerNotFoundException(
    this.message, {
    this.searched = const [],
    this.cause,
  });

  /// What went wrong, with a hint on how to install / point at GStreamer.
  final String message;

  /// The library files or folders that were tried, in order.
  final List<String> searched;

  /// The underlying loader error, when a library was found but failed to load.
  final Object? cause;

  @override
  String toString() {
    final b = StringBuffer('GStreamerNotFoundException: $message');
    if (searched.isNotEmpty) b.write('\nSearched:\n  ${searched.join('\n  ')}');
    if (cause != null) b.write('\nCause: $cause');
    return b.toString();
  }
}

/// A GStreamer call failed: initialisation, a pipeline description that does
/// not parse, a missing element, an ERROR message on a pipeline's bus, a
/// timeout, or a file the discoverer cannot read.
class GStreamerException implements Exception {
  GStreamerException(this.message, {this.debug, this.source});

  /// GStreamer's (or this package's) error message.
  final String message;

  /// GStreamer's debug detail (file, function, element internals), if any.
  final String? debug;

  /// The name of the element that posted the error, if any.
  final String? source;

  @override
  String toString() {
    final b = StringBuffer('GStreamerException: ');
    if (source != null) b.write('[$source] ');
    b.write(message);
    if (debug != null && debug!.isNotEmpty) b.write('\n$debug');
    return b.toString();
  }
}
