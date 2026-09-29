import 'dart:io';

/// [path] absolute, normalised, with `/` separators and no trailing `/`
/// (lower-cased on Windows, whose paths are case-insensitive), so prefix
/// checks such as "inside `test/smoke`" hold on every platform.
String normalizeSmokePath(String path) {
  var p = File(path).absolute.uri.normalizePath().toFilePath(windows: Platform.isWindows).replaceAll(r'\', '/');
  if (Platform.isWindows) p = p.toLowerCase();
  while (p.length > 1 && p.endsWith('/') && !p.endsWith(':/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// Whether [path] is [dir] or inside it (both normalised with
/// [normalizeSmokePath]).
bool isSmokePathWithin(String path, String dir) {
  final p = normalizeSmokePath(path);
  final d = normalizeSmokePath(dir);
  return p == d || p.startsWith(d.endsWith('/') ? d : '$d/');
}

/// [path] with `/` separators (a Windows listing says `\`).
String slashPath(String path) => path.replaceAll(r'\', '/');

/// The URL a page written into [pageDir] uses for the artifact at
/// [artifactPath]: relative when both are on the same root
/// (`../smoke_artifacts/a%20b.png`), else an absolute `file://` URI. Every
/// path segment is percent-encoded (artifact names carry spaces and `#`).
///
/// Both paths may be POSIX (`/home/u/…`) or Windows (`C:\…`, `C:/…`, UNC)
/// paths; a Windows path is compared case-insensitively and by drive, so two
/// drives never share a root.
String artifactHref(String artifactPath, String pageDir) {
  final target = _segments(artifactPath);
  final base = _segments(pageDir);
  final sameRoot = target.root.toLowerCase() == base.root.toLowerCase();
  if (!sameRoot) return _fileUri(target);
  bool same(String a, String b) => target.windows ? a.toLowerCase() == b.toLowerCase() : a == b;
  var common = 0;
  while (common < target.parts.length && common < base.parts.length && same(target.parts[common], base.parts[common])) {
    common++;
  }
  if (common == 0 && target.root.isEmpty) return _fileUri(target);
  return [
    for (var i = common; i < base.parts.length; i++) '..',
    for (var i = common; i < target.parts.length; i++) Uri.encodeComponent(target.parts[i]),
  ].join('/');
}

typedef _Split = ({String root, List<String> parts, bool windows});

/// [path] made absolute (against the working directory) and split into its
/// root (`C:`, `//server/share`, or empty for `/`) and segments, with `.`
/// and `..` resolved.
_Split _segments(String path) {
  var p = path.replaceAll(r'\', '/');
  final isDrive = RegExp(r'^[A-Za-z]:/').hasMatch(p) || RegExp(r'^[A-Za-z]:$').hasMatch(p);
  final isUnc = p.startsWith('//');
  final isPosixAbsolute = p.startsWith('/') && !isUnc;
  if (!isDrive && !isUnc && !isPosixAbsolute) {
    p = '${Directory.current.absolute.path.replaceAll(r'\', '/')}/$p';
    return _segments(p);
  }
  String root;
  String rest;
  if (isDrive) {
    root = p.substring(0, 2).toUpperCase();
    rest = p.substring(2);
  } else if (isUnc) {
    final parts = p.substring(2).split('/');
    root = '//${parts.take(2).join('/')}';
    rest = parts.skip(2).join('/');
  } else {
    root = '';
    rest = p;
  }
  final out = <String>[];
  for (final s in rest.split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(s);
  }
  return (root: root, parts: out, windows: isDrive || isUnc);
}

String _fileUri(_Split p) {
  final encoded = p.parts.map(Uri.encodeComponent).join('/');
  if (p.root.isEmpty) return 'file:///$encoded';
  if (p.root.startsWith('//')) return 'file:${p.root}/$encoded';
  return 'file:///${p.root}/$encoded';
}
