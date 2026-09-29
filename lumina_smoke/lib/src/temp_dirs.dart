import 'dart:io';

/// Temporary directories of recordings a killed run left behind.
///
/// A recording streams its raw frames (≈ 4 MB each at 1366×768) into the
/// system temp directory; a test process killed before its teardown leaves
/// them there, and a few of them fill a per-user temp quota, after which no
/// process can even start.
abstract final class SmokeTempDirs {
  static final Set<String> _purgedPrefixes = {};

  /// Deletes the system temp directories whose name starts with [prefix] and
  /// in which nothing was written for [olderThan], once per prefix and
  /// process. A live recording appends to its frames file every frame, so it
  /// is never taken for a stale one. Directories another user owns, or that
  /// are deleted concurrently, are skipped.
  static void purgeStale(String prefix, {Duration olderThan = const Duration(minutes: 30), bool force = false}) {
    if (!force && !_purgedPrefixes.add(prefix)) return;
    final cutoff = DateTime.now().subtract(olderThan);
    try {
      for (final entity in Directory.systemTemp.listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!name.startsWith(prefix)) continue;
        try {
          if (isStale(entity, cutoff)) entity.deleteSync(recursive: true);
        } on FileSystemException {
          // Not ours, or already gone.
        }
      }
    } on FileSystemException {
      // An unreadable temp directory is not the recorder's problem.
    }
  }

  /// Whether nothing in [dir] was modified after [cutoff]: every file in it
  /// (recursively) is older, or, for an empty directory, the directory itself.
  static bool isStale(Directory dir, DateTime cutoff) {
    final files = dir.listSync(recursive: true, followLinks: false).whereType<File>().toList();
    if (files.isEmpty) return dir.statSync().modified.isBefore(cutoff);
    return files.every((f) => f.statSync().modified.isBefore(cutoff));
  }
}
