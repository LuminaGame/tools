import 'dart:io' show Platform;

/// The process environment (`LUMINA_MOUSE_CAPTURE`).
Map<String, String> processEnvironment() => Platform.environment;
