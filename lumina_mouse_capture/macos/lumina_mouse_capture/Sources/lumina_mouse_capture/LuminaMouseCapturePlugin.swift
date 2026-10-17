import Cocoa
import CoreGraphics
import FlutterMacOS

public class LuminaMouseCapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private weak var registrar: FlutterPluginRegistrar?
  private var eventSink: FlutterEventSink?
  private var captured = false
  private var cursorHidden = false
  private var eventMonitor: Any?
  private var observers: [NSObjectProtocol] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = LuminaMouseCapturePlugin(registrar: registrar)
    let channel = FlutterMethodChannel(
      name: "lumina_mouse_capture",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: channel)

    let events = FlutterEventChannel(
      name: "lumina_mouse_capture/events",
      binaryMessenger: registrar.messenger
    )
    events.setStreamHandler(instance)
  }

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  deinit {
    releaseCapture(emitLostReason: nil)
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  private static func isDisabledByEnvironment() -> Bool {
    guard let raw = ProcessInfo.processInfo.environment["LUMINA_MOUSE_CAPTURE"] else {
      return false
    }
    let val = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return val == "off" || val == "record"
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "support":
      if Self.isDisabledByEnvironment() {
        result([
          "kind": "disabled",
          "pointerLock": false,
          "relativeMotion": false,
          "detail": "LUMINA_MOUSE_CAPTURE is off: nothing captures the pointer",
        ])
      } else if registrar?.view != nil {
        result([
          "kind": "macos",
          "pointerLock": true,
          "relativeMotion": true,
          "detail": "CGAssociateMouseAndMouseCursorPosition",
        ])
      } else {
        result([
          "kind": "unsupported",
          "pointerLock": false,
          "relativeMotion": false,
          "detail": "no Flutter view",
        ])
      }

    case "capture":
      if Self.isDisabledByEnvironment() {
        result(false)
        return
      }
      var centre: CGPoint?
      if let args = call.arguments as? [String: Any],
         let x = (args["x"] as? NSNumber)?.doubleValue,
         let y = (args["y"] as? NSNumber)?.doubleValue {
        centre = CGPoint(x: x, y: y)
      }
      result(startCapture(centre: centre))

    case "release":
      releaseCapture(emitLostReason: nil)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startCapture(centre: CGPoint?) -> Bool {
    guard let view = registrar?.view, let window = view.window else {
      return false
    }
    if !window.isKeyWindow || window.isMiniaturized {
      return false
    }

    let bounds = view.bounds
    let targetInView: NSPoint
    if let c = centre {
      // Flutter logical coordinates have top-left origin; NSView may or may not be flipped.
      let vy = view.isFlipped ? c.y : (bounds.height - c.y)
      targetInView = NSPoint(x: c.x, y: vy)
    } else {
      targetInView = NSPoint(x: bounds.midX, y: bounds.midY)
    }
    let pointInWindow = view.convert(targetInView, to: nil)
    let pointInScreen = window.convertPoint(toScreen: pointInWindow)
    // Convert AppKit bottom-left screen coordinates to Quartz top-left global display coordinates.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
    let quartzPoint = CGPoint(x: pointInScreen.x, y: primaryHeight - pointInScreen.y)

    CGWarpMouseCursorPosition(quartzPoint)
    CGAssociateMouseAndMouseCursorPosition(0)
    if !cursorHidden {
      CGDisplayHideCursor(CGMainDisplayID())
      cursorHidden = true
    }

    if !captured {
      captured = true
      installMonitors(for: window)
      sendEvent(["type": "locked"])
    }
    return true
  }

  private func installMonitors(for window: NSWindow) {
    removeMonitors()
    let mask: NSEvent.EventTypeMask = [
      .mouseMoved,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged,
    ]
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
      guard let self = self, self.captured else { return event }
      let dx = Double(event.deltaX)
      let dy = Double(event.deltaY)
      if dx != 0.0 || dy != 0.0 {
        self.sendEvent([
          "type": "motion",
          "dx": dx,
          "dy": dy,
        ])
      }
      return event
    }

    let nc = NotificationCenter.default
    observers.append(
      nc.addObserver(
        forName: NSWindow.didResignKeyNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        self?.releaseCapture(emitLostReason: "focus")
      }
    )
    observers.append(
      nc.addObserver(
        forName: NSWindow.willMiniaturizeNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        self?.releaseCapture(emitLostReason: "minimized")
      }
    )
    observers.append(
      nc.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        self?.releaseCapture(emitLostReason: "window")
      }
    )
    observers.append(
      nc.addObserver(
        forName: NSApplication.didResignActiveNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.releaseCapture(emitLostReason: "focus")
      }
    )
  }

  private func removeMonitors() {
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
    let nc = NotificationCenter.default
    for observer in observers {
      nc.removeObserver(observer)
    }
    observers.removeAll()
  }

  private func releaseCapture(emitLostReason: String?) {
    let wasCaptured = captured
    captured = false
    removeMonitors()
    CGAssociateMouseAndMouseCursorPosition(1)
    if cursorHidden {
      CGDisplayShowCursor(CGMainDisplayID())
      cursorHidden = false
    }
    if wasCaptured, let reason = emitLostReason {
      sendEvent([
        "type": "lost",
        "reason": reason,
      ])
    }
  }

  private func sendEvent(_ payload: [String: Any]) {
    eventSink?(payload)
  }
}
