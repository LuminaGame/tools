import 'dart:async';

import 'package:flutter/services.dart';

import 'mouse_capture_backend.dart';

/// The native backend: `linux/lumina_mouse_capture_plugin.cc` and
/// `windows/lumina_mouse_capture_plugin.cpp`.
///
/// Wire format:
/// - `lumina_mouse_capture` method channel: `support` → `{kind, pointerLock,
///   relativeMotion, detail}`, `capture` `{x, y}` (optional) → bool,
///   `release` → null;
/// - `lumina_mouse_capture/events` event channel: `{type: motion, dx, dy}`,
///   `{type: locked}`, `{type: lost, reason}` (`reason` optional).
///
/// A missing plugin (an app that was not rebuilt, a platform without it) is
/// reported as [MouseCaptureBackendKind.unsupported], never thrown.
class MethodChannelMouseCaptureBackend implements MouseCaptureBackend {
  MethodChannelMouseCaptureBackend();

  static const MethodChannel channel = MethodChannel('lumina_mouse_capture');
  static const EventChannel eventChannel = EventChannel('lumina_mouse_capture/events');

  Stream<MouseCaptureEvent>? _events;

  @override
  Stream<MouseCaptureEvent> get events => _events ??= eventChannel
      .receiveBroadcastStream()
      .handleError((Object _) {}, test: (e) => e is MissingPluginException)
      .map(_decode)
      .where((e) => e != null)
      .cast<MouseCaptureEvent>();

  static MouseCaptureEvent? _decode(dynamic message) {
    if (message is! Map) return null;
    switch (message['type']) {
      case 'motion':
        final dx = message['dx'];
        final dy = message['dy'];
        if (dx is! num || dy is! num) return null;
        return MouseCaptureMotion(dx.toDouble(), dy.toDouble());
      case 'locked':
        return const MouseCaptureLocked();
      case 'lost':
        final reason = message['reason'];
        return MouseCaptureLost(reason is String ? reason : null);
    }
    return null;
  }

  @override
  Future<MouseCaptureSupport> support() async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('support');
      if (result == null) return MouseCaptureSupport.none;
      final kind = MouseCaptureBackendKind.values.where((k) => k.name == result['kind']).firstOrNull ??
          MouseCaptureBackendKind.unsupported;
      return MouseCaptureSupport(
        kind: kind,
        pointerLock: result['pointerLock'] == true,
        relativeMotion: result['relativeMotion'] == true,
        detail: (result['detail'] as String?) ?? '',
      );
    } on MissingPluginException {
      return const MouseCaptureSupport(
        kind: MouseCaptureBackendKind.unsupported,
        detail: 'the lumina_mouse_capture plugin is not built into this app',
      );
    } on PlatformException catch (e) {
      return MouseCaptureSupport(kind: MouseCaptureBackendKind.unsupported, detail: e.message ?? e.code);
    }
  }

  @override
  Future<bool> capture({Offset? centre}) async {
    try {
      final ok = await channel.invokeMethod<bool>(
        'capture',
        centre == null ? null : <String, double>{'x': centre.dx, 'y': centre.dy},
      );
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> release() async {
    try {
      await channel.invokeMethod<void>('release');
    } on MissingPluginException {
      // Nothing was captured.
    } on PlatformException {
      // Nothing more to do: the native side logs its own failures.
    }
  }
}
