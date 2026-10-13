/// Native platforms link the library at build time: nothing to load.
Future<void> loadJoltModule(String moduleUrl) async {}

/// Whether this is a web build.
const bool joltIsWeb = false;
