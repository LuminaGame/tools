/// How a package groups its tests into report pages ("categories"): one per
/// module or feature area, in report order.
///
/// A test's category comes from its file (`suite`, a path) and then its
/// name:
///
/// 1. [pathRules]: the first whose text the normalised path contains, and
///    [namePrefixes]: the first the lower-cased name starts with;
/// 2. [folders]: a folder (under the last `/test/`) that decides whatever
///    the file is called;
/// 3. the file name's keywords (see [longestMatch]);
/// 4. [fallbackFolders]: a folder that decides when the file name does not;
/// 5. the test name's keywords;
/// 6. [other].
///
/// Paths are compared with `/` separators and lower-cased, so a Windows
/// suite path (`C:\…\test\smoke\x_test.dart`) is grouped like a POSIX one.
class TestCategories {
  const TestCategories(
    this.categories, {
    this.longestMatch = false,
    this.folders = const {},
    this.fallbackFolders = const {},
    this.pathRules = const {},
    this.namePrefixes = const {},
    this.other = 'Other',
  });

  /// The categories in report order, each with its keywords.
  final List<(String, List<String>)> categories;

  /// How keywords match. `false`: the first category with a keyword the text
  /// contains wins. `true`: a keyword matches only at the start of a word of
  /// the `_`-separated text (`pawn` matches `pawn_input`, not `spawn_actor`)
  /// and the longest matching keyword wins, a tie going to the earlier
  /// category.
  final bool longestMatch;

  /// Test folders that decide the category whatever the file is called.
  final Map<String, String> folders;

  /// Test folders that decide only when the file name does not.
  final Map<String, String> fallbackFolders;

  /// Path fragments (lower case, `/`-separated) that decide first.
  final Map<String, String> pathRules;

  /// Test-name prefixes (lower case) that decide first.
  final Map<String, String> namePrefixes;

  /// The category of a test nothing matches.
  final String other;

  /// The category names in report order.
  List<String> get names => [for (final c in categories) c.$1];

  /// The category of the test [name] in the file [suite].
  String categoryOf(String suite, String name) {
    final path = suite.replaceAll(r'\', '/').toLowerCase();
    final lowerName = name.toLowerCase();
    for (final rule in pathRules.entries) {
      if (path.contains(rule.key)) return rule.value;
    }
    for (final rule in namePrefixes.entries) {
      if (lowerName.startsWith(rule.key)) return rule.value;
    }
    final underTest = path.contains('/test/') ? path.substring(path.lastIndexOf('/test/') + 6) : path;
    final segments = underTest.split('/');
    final folderNames = segments.sublist(0, segments.length - 1);
    for (final f in folderNames) {
      final category = folders[f];
      if (category != null) return category;
    }
    final file = longestMatch ? segments.last.replaceAll(RegExp(r'(_test)?\.dart$'), '') : segments.last;
    final byFile = _byKeyword(file);
    if (byFile != null) return byFile;
    for (final f in folderNames.reversed) {
      final category = fallbackFolders[f];
      if (category != null) return category;
    }
    final byName = longestMatch ? _byKeyword(lowerName.replaceAll(RegExp(r'[^a-z0-9]+'), '_')) : _byKeyword(lowerName);
    return byName ?? other;
  }

  String? _byKeyword(String text) {
    if (!longestMatch) {
      for (final (category, keywords) in categories) {
        if (keywords.any(text.contains)) return category;
      }
      return null;
    }
    final words = '_$text';
    String? best;
    var bestLength = 0;
    for (final (category, keywords) in categories) {
      for (final k in keywords) {
        if (k.length > bestLength && words.contains('_$k')) {
          best = category;
          bestLength = k.length;
        }
      }
    }
    return best;
  }

  /// Position of [category] in the report; unknown ones ([other]) go last.
  int orderOf(String category) {
    final i = categories.indexWhere((c) => c.$1 == category);
    return i < 0 ? categories.length : i;
  }
}
