import 'dart:io';

import '../video.dart';

/// One PNG or video linked from the report (never embedded: the report is
/// shared together with its `build/smoke_artifacts/` folder).
class ReportMedia {
  ReportMedia({
    required this.fileName,
    required this.mimeType,
    required this.path,
    required this.relativePath,
    this.label,
    this.video,
    this.savedAt = 0,
    this.missing = false,
  });

  /// The file's name.
  final String fileName;
  final String mimeType;

  /// Absolute path of the file; the report links it relative to the page it
  /// is on.
  final String path;

  /// The path under the artifact directory, `/`-separated.
  final String relativePath;

  /// The declared test name the file was saved under (its sidecar's `test`);
  /// null for a file no sidecar names.
  final String? label;

  /// What was measured of a video; null for an image.
  final SmokeVideoInfo? video;

  /// When the sidecar was written (milliseconds since the epoch); orders a
  /// test's gallery the way the scenario saved it.
  final int savedAt;

  /// A sidecar names the file, but it is not there.
  final bool missing;

  bool get isVideo => mimeType.startsWith('video/');
  bool get isImage => !isVideo;

  /// Length of a video in seconds; null for an image or an unmeasured video.
  double? get videoSeconds => video?.seconds;

  /// A video under the minimum length, or of unknown length.
  bool get isShortVideo => isVideo && !missing && (video?.isTooShort ?? true);

  /// A video under the minimum size, or of unknown size.
  bool get isSmallVideo => isVideo && !missing && (video?.isTooSmall ?? true);

  /// A video under the minimum frame rate, or of unknown rate.
  bool get isSlowVideo => isVideo && !missing && (video?.isTooSlow ?? true);

  /// Whether this video breaks any of the smoke-video minimums.
  bool get breaksVideoRule => isShortVideo || isSmallVideo || isSlowVideo;

  /// The rules this video breaks, as `3.0 s < 10 s` etc.
  List<String> get violations {
    if (!isVideo || missing) return const [];
    final v = video;
    return [
      if (isShortVideo)
        v?.seconds == null
            ? 'length unknown'
            : '${v!.seconds!.toStringAsFixed(1)} s < ${SmokeVideo.minimumSeconds.toStringAsFixed(0)} s',
      if (isSlowVideo)
        v?.fps == null ? 'fps unknown' : '${v!.fps!.toStringAsFixed(1)} fps < ${SmokeVideo.minimumFps} fps',
      if (isSmallVideo)
        v?.width == null || v?.height == null
            ? 'size unknown'
            : '${v!.width}×${v.height} < ${SmokeVideo.minimumWidth}×${SmokeVideo.minimumHeight}',
    ];
  }

  /// The MIME type of a PNG, WebM or MP4 file name; null for anything else.
  static String? mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return null;
  }

  /// [file] as report media (a video measured with [SmokeVideo.probe], with
  /// [declared] filling what the probe cannot read); null for a file that is
  /// neither PNG nor video.
  static ReportMedia? load(
    File file, {
    required String relativePath,
    String? label,
    SmokeVideoInfo declared = const SmokeVideoInfo(),
    int savedAt = 0,
  }) {
    final name = file.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final mime = mimeFor(name);
    if (mime == null) return null;
    final exists = file.existsSync();
    final isVideo = mime.startsWith('video/');
    return ReportMedia(
      fileName: name,
      mimeType: mime,
      path: file.absolute.path,
      relativePath: relativePath,
      label: label,
      video: isVideo ? (exists ? SmokeVideo.probe(file).orElse(declared) : declared) : null,
      savedAt: savedAt,
      missing: !exists,
    );
  }
}

/// Media, asset badges and the video verdict shared by test cards and the
/// cards of artifacts that match no test.
mixin MediaHolder {
  final List<ReportMedia> media = [];
  final List<String> usedAssets = [];

  List<ReportMedia> get screenshots => media.where((m) => m.isImage).toList();
  List<ReportMedia> get videos => media.where((m) => m.isVideo).toList();
  List<ReportMedia> get shortVideos => media.where((m) => m.isShortVideo).toList();
  List<ReportMedia> get smallVideos => media.where((m) => m.isSmallVideo).toList();
  List<ReportMedia> get slowVideos => media.where((m) => m.isSlowVideo).toList();

  /// Videos that break a smoke-video rule (too short, too small or too slow).
  List<ReportMedia> get badVideos => media.where((m) => m.breaksVideoRule).toList();

  bool get hasPng => media.any((m) => m.isImage);
  bool get hasVideo => media.any((m) => m.isVideo);

  /// Adds [item] unless the same file is already there, keeping save order.
  void addMedia(ReportMedia item) {
    if (media.any((m) => m.path == item.path)) return;
    media.add(item);
    media.sort((a, b) {
      final bySave = a.savedAt.compareTo(b.savedAt);
      return bySave != 0 ? bySave : a.fileName.compareTo(b.fileName);
    });
  }

  void addAssets(Iterable<String> assets) {
    for (final a in assets) {
      if (!usedAssets.contains(a)) usedAssets.add(a);
    }
  }

  /// The first screenshot's absolute path (the report shows them all).
  String? get screenshotPath => screenshots.isEmpty ? null : screenshots.first.path;

  /// The first video's absolute path (the report shows them all).
  String? get videoPath => videos.isEmpty ? null : videos.first.path;
  String? get videoType => videos.isEmpty ? null : videos.first.mimeType;
}

/// One test of the run, with the artifacts matched to it.
class TestResultItem with MediaHolder {
  TestResultItem({
    required this.id,
    required this.name,
    required this.suite,
    required this.startTimeMs,
    this.leafName,
    this.backend,
    this.run = 0,
    this.category = 'Other',
  })  : durationMs = 0,
        status = 'running';

  final String id;
  String name;

  /// [name] without its enclosing groups (the name passed to `test()`).
  String? leafName;

  /// The test file's path as `flutter test` reported it.
  String suite;

  /// The GPU backend it ran on; null for a package without backends.
  final String? backend;

  /// The runner invocation (`flutter test` process) it belongs to.
  final int run;
  int startTimeMs;
  int durationMs;

  /// 'passed', 'failed', 'skipped' or 'running'.
  String status;
  String? error;
  String? stackTrace;
  final List<String> prints = [];

  /// The page it is on.
  String category;

  bool get isFailure => status == 'failed' || status == 'error';
  bool get isSkipped => status == 'skipped';
  bool get isPassed => status == 'passed' || status == 'success';

  /// Whether it is a smoke test: in a smoke folder or file, named so, or
  /// carrying artifacts.
  bool get isSmoke =>
      suite.replaceAll(r'\', '/').toLowerCase().contains('smoke') ||
      name.toLowerCase().contains('smoke') ||
      media.isNotEmpty;
}

/// Artifacts whose sidecar names no test of the report (or files no sidecar
/// names), shown as their own card.
class OrphanedArtifact with MediaHolder {
  OrphanedArtifact({required this.testName, this.backend, this.category = 'Other'});

  /// The declared test name, or the file name without its extension.
  final String testName;
  final String? backend;

  /// The page it is on.
  String category;

  /// The files on this card.
  String get fileName => media.map((m) => m.fileName).join(', ');
}

/// Everything a report shows.
class SmokeReportModel {
  SmokeReportModel({
    required this.tests,
    required this.orphanedArtifacts,
    required this.categories,
    required this.totalCount,
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.shortVideoCount,
    required this.smallVideoCount,
    required this.slowVideoCount,
    required this.artifactCount,
    required this.wallDurationMs,
    required this.timestamp,
    required this.exitCode,
    required this.dartVersion,
  });

  /// Failures first, then passed, then skipped; by name within each.
  final List<TestResultItem> tests;
  final List<OrphanedArtifact> orphanedArtifacts;

  /// The report's pages, in order.
  final List<String> categories;
  final int totalCount;
  final int passedCount;

  /// Failed tests plus unmatched artifact cards with a video that breaks a
  /// smoke-video rule.
  final int failedCount;
  final int skippedCount;

  /// Videos under the minimum length, size and frame rate.
  final int shortVideoCount;
  final int smallVideoCount;
  final int slowVideoCount;
  final int artifactCount;
  final int wallDurationMs;
  final DateTime timestamp;

  /// 1 when a test of the counted runs failed, a counted run crashed, or a
  /// counted video breaks a rule; else 0.
  final int exitCode;
  final String dartVersion;

  bool get hasFailures => failedCount > 0;

  /// Every video that breaks a rule, with where it is.
  List<ReportMedia> get badVideos => [
        for (final t in tests) ...t.badVideos,
        for (final o in orphanedArtifacts) ...o.badVideos,
      ];
}
