import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/gstreamer.g.dart' as raw;
import 'exceptions.dart';
import 'gstreamer.dart';

/// `GstState`.
enum GstState {
  voidPending(0),
  nullState(1),
  ready(2),
  paused(3),
  playing(4);

  const GstState(this.value);

  /// The C enum value.
  final int value;

  static GstState fromValue(int value) =>
      values.firstWhere((s) => s.value == value);
}

/// `GST_CLOCK_TIME_NONE`: "no timestamp" / "wait forever".
const int gstClockTimeNone = -1;

/// A message popped from a pipeline's bus.
final class GstBusMessage {
  GstBusMessage({
    required this.type,
    required this.typeName,
    this.source,
    this.error,
    this.debug,
  });

  /// The `GstMessageType` bit (`raw.GstMessageType.GST_MESSAGE_EOS`, ...).
  final int type;

  /// `gst_message_type_get_name`, e.g. `eos`, `error`.
  final String typeName;

  /// The name of the object that posted it.
  final String? source;

  /// For ERROR / WARNING messages: the GError message.
  final String? error;

  /// For ERROR / WARNING messages: the debug detail.
  final String? debug;

  bool get isEos => type == raw.GstMessageType.GST_MESSAGE_EOS;
  bool get isError => type == raw.GstMessageType.GST_MESSAGE_ERROR;
  bool get isWarning => type == raw.GstMessageType.GST_MESSAGE_WARNING;

  @override
  String toString() =>
      'GstBusMessage($typeName${source == null ? '' : ' from $source'}'
      '${error == null ? '' : ': $error'})';
}

/// A pipeline built from a `gst-launch`-style description
/// (`gst_parse_launch`), with its bus.
///
/// ```dart
/// final p = GstPipeline.parse('videotestsrc num-buffers=30 ! vp8enc ! webmmux ! filesink name=out');
/// p.element('out')!.set('location', path);   // no quoting issues with paths
/// p.play();
/// p.waitForEos();                            // throws GStreamerException on an ERROR message
/// p.dispose();
/// ```
final class GstPipeline {
  GstPipeline._(this._gst, this._pipeline)
    : _bus = _gst.bindings.gst_element_get_bus(_pipeline);

  final GStreamer _gst;
  final ffi.Pointer<raw.GstElement> _pipeline;
  final ffi.Pointer<raw.GstBus> _bus;
  final _children = <GstElement>[];
  bool _disposed = false;

  raw.GStreamerBindings get _b => _gst.bindings;

  /// The raw `GstElement*` of the pipeline (valid until [dispose]).
  ffi.Pointer<raw.GstElement> get pointer => _pipeline;

  /// Parses [description] (initialising GStreamer on first use). Throws
  /// [GStreamerException] when it does not parse or names an unknown element.
  factory GstPipeline.parse(String description, {GStreamer? gstreamer}) {
    final gst = gstreamer ?? GStreamer.instance;
    final b = gst.bindings;
    return using((arena) {
      final err = arena<ffi.Pointer<raw.GError>>();
      final element = b.gst_parse_launch(
        description.toNativeUtf8(allocator: arena).cast(),
        err,
      );
      final error = takeError(b, err.value);
      if (element == ffi.nullptr || error != null) {
        // gst_parse_launch may return a partial pipeline with a recoverable
        // error (e.g. a missing element): treat that as a failure too.
        if (element != ffi.nullptr) {
          b.gst_element_set_state(element, GstState.nullState.value);
          b.gst_object_unref(element.cast());
        }
        throw GStreamerException(
          'Could not build pipeline "$description": ${error ?? 'unknown error'}',
        );
      }
      return GstPipeline._(gst, element);
    });
  }

  /// The element named [name] in the pipeline, or null. The wrapper stays
  /// valid until [dispose].
  GstElement? element(String name) {
    _checkAlive();
    final el = using(
      (arena) => _b.gst_bin_get_by_name(
        _pipeline.cast(),
        name.toNativeUtf8(allocator: arena).cast(),
      ),
    );
    if (el == ffi.nullptr) return null;
    final wrapper = GstElement._(_gst, el, name);
    _children.add(wrapper);
    return wrapper;
  }

  /// The `appsrc` named [name]; throws [ArgumentError] when there is none.
  GstAppSrc appSrc(String name) {
    final el = element(name);
    if (el == null) {
      throw ArgumentError.value(
        name,
        'name',
        'no element with this name in the pipeline',
      );
    }
    return GstAppSrc._(el);
  }

  /// Requests [state]. Throws [GStreamerException] (with the bus error, if
  /// any) when the change fails; an asynchronous change is not waited for.
  void setState(GstState state) {
    _checkAlive();
    final r = _b.gst_element_set_state(_pipeline, state.value);
    if (r == raw.GstStateChangeReturn.GST_STATE_CHANGE_FAILURE) {
      final error = _popError();
      throw error ??
          GStreamerException(
            'Setting the pipeline to ${state.name} failed (no error message on the bus).',
          );
    }
  }

  void play() => setState(GstState.playing);
  void pause() => setState(GstState.paused);

  /// Back to NULL: releases devices and files (a filesink closes its file).
  void stop() => setState(GstState.nullState);

  /// The current state (does not wait for a pending change).
  GstState get state => using((arena) {
    final s = arena<ffi.UnsignedInt>(2);
    _b.gst_element_get_state(_pipeline, s, s + 1, 0);
    return GstState.fromValue(s[0]);
  });

  /// Sends an end-of-stream event into the pipeline (for sources that do not
  /// end by themselves).
  void sendEos() {
    _checkAlive();
    _b.gst_element_send_event(_pipeline, _b.gst_event_new_eos());
  }

  /// Pops the next bus message matching [types] (a `GstMessageType` mask,
  /// all by default), waiting up to [timeout] (null: do not wait).
  GstBusMessage? pop({
    Duration? timeout,
    int types = raw.GstMessageType.GST_MESSAGE_ANY,
  }) {
    _checkAlive();
    final msg = _b.gst_bus_timed_pop_filtered(
      _bus,
      timeout == null ? 0 : timeout.inMicroseconds * 1000,
      types,
    );
    if (msg == ffi.nullptr) return null;
    try {
      return _read(msg);
    } finally {
      _b.gst_mini_object_unref(msg.cast());
    }
  }

  /// Waits for end-of-stream. Throws [GStreamerException] for an ERROR
  /// message (naming the element that posted it) or when [timeout] passes.
  void waitForEos({Duration timeout = const Duration(minutes: 10)}) {
    final m = pop(
      timeout: timeout,
      types:
          raw.GstMessageType.GST_MESSAGE_EOS |
          raw.GstMessageType.GST_MESSAGE_ERROR,
    );
    if (m == null) {
      throw GStreamerException(
        'Timed out after $timeout waiting for end-of-stream.',
      );
    }
    if (m.isError) {
      throw GStreamerException(
        m.error ?? 'unknown error',
        debug: m.debug,
        source: m.source,
      );
    }
  }

  /// Throws the first ERROR message already on the bus, if any (does not wait).
  void throwIfError() {
    final e = _popError();
    if (e != null) throw e;
  }

  GStreamerException? _popError() {
    final m = pop(types: raw.GstMessageType.GST_MESSAGE_ERROR);
    if (m == null) return null;
    return GStreamerException(
      m.error ?? 'unknown error',
      debug: m.debug,
      source: m.source,
    );
  }

  /// `gst_element_query_duration` in nanoseconds, or null when unknown.
  int? queryDurationNs() => _query(_b.gst_element_query_duration);

  /// `gst_element_query_position` in nanoseconds, or null when unknown.
  int? queryPositionNs() => _query(_b.gst_element_query_position);

  int? _query(
    int Function(ffi.Pointer<raw.GstElement>, int, ffi.Pointer<ffi.LongLong>) q,
  ) {
    _checkAlive();
    return using((arena) {
      final v = arena<ffi.LongLong>();
      return q(_pipeline, raw.GstFormat.GST_FORMAT_TIME, v) != 0 && v.value >= 0
          ? v.value
          : null;
    });
  }

  GstBusMessage _read(ffi.Pointer<raw.GstMessage> msg) {
    final type = msg.ref.type;
    final src = msg.ref.src;
    final source = src == ffi.nullptr
        ? null
        : takeString(_b, _b.gst_object_get_name(src));
    final typeName = _b
        .gst_message_type_get_name(type)
        .cast<Utf8>()
        .toDartString();
    String? error, debug;
    if (type == raw.GstMessageType.GST_MESSAGE_ERROR ||
        type == raw.GstMessageType.GST_MESSAGE_WARNING) {
      using((arena) {
        final err = arena<ffi.Pointer<raw.GError>>();
        final dbg = arena<ffi.Pointer<ffi.Char>>();
        if (type == raw.GstMessageType.GST_MESSAGE_ERROR) {
          _b.gst_message_parse_error(msg, err, dbg);
        } else {
          _b.gst_message_parse_warning(msg, err, dbg);
        }
        error = takeError(_b, err.value);
        debug = takeString(_b, dbg.value);
      });
    }
    return GstBusMessage(
      type: type,
      typeName: typeName,
      source: source,
      error: error,
      debug: debug,
    );
  }

  void _checkAlive() {
    if (_disposed) throw StateError('GstPipeline was disposed');
  }

  /// Stops the pipeline and releases it, its bus and every element handed
  /// out by [element]. Safe to call twice.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _b.gst_element_set_state(_pipeline, GstState.nullState.value);
    for (final c in _children) {
      c._release();
    }
    _b.gst_object_unref(_bus.cast());
    _b.gst_object_unref(_pipeline.cast());
  }
}

/// An element of a [GstPipeline] (owned by it: released by
/// [GstPipeline.dispose]).
class GstElement {
  GstElement._(this._gst, this._element, this.name);

  final GStreamer _gst;
  final ffi.Pointer<raw.GstElement> _element;
  bool _released = false;

  /// The element's name in the pipeline.
  final String name;

  /// The raw `GstElement*`.
  ffi.Pointer<raw.GstElement> get pointer => _element;

  /// Sets property [property] from its string form, like `gst-launch` does
  /// (`gst_util_set_object_arg`): numbers, booleans, enum nicks, caps, paths
  /// with spaces — no quoting needed.
  void set(String property, String value) {
    _check();
    using(
      (arena) => _gst.bindings.gst_util_set_object_arg(
        _element.cast(),
        property.toNativeUtf8(allocator: arena).cast(),
        value.toNativeUtf8(allocator: arena).cast(),
      ),
    );
  }

  /// Sets every entry of [properties] with [set].
  void setAll(Map<String, String> properties) => properties.forEach(set);

  void _check() {
    if (_released) {
      throw StateError('GstElement "$name" belongs to a disposed pipeline');
    }
  }

  void _release() {
    if (_released) return;
    _released = true;
    _gst.bindings.gst_object_unref(_element.cast());
  }
}

/// An `appsrc` element: the application pushes buffers into the pipeline.
final class GstAppSrc {
  GstAppSrc._(this.element);

  /// The underlying element (for [GstElement.set]).
  final GstElement element;

  raw.GStreamerBindings get _b => element._gst.bindings;
  ffi.Pointer<raw.GstAppSrc> get _src => element._element.cast();

  /// `gst_app_src_set_caps` from a caps string such as
  /// `video/x-raw,format=RGBA,width=640,height=480,framerate=30/1`.
  void setCaps(String caps) {
    element._check();
    using((arena) {
      final c = _b.gst_caps_from_string(
        caps.toNativeUtf8(allocator: arena).cast(),
      );
      if (c == ffi.nullptr) {
        throw ArgumentError.value(caps, 'caps', 'not a valid caps string');
      }
      _b.gst_app_src_set_caps(_src, c);
      _b.gst_mini_object_unref(c.cast());
    });
  }

  /// Copies [data] into a new buffer stamped with [ptsNs] / [durationNs]
  /// (nanoseconds; null leaves them unset) and pushes it. With the appsrc
  /// `block=true` property this waits while the queue is full. Returns
  /// normally for `GST_FLOW_OK`; throws [GStreamerException] otherwise (the
  /// pipeline is flushing, at EOS or has failed).
  void pushBuffer(Uint8List data, {int? ptsNs, int? durationNs}) {
    element._check();
    final buffer = _b.gst_buffer_new_allocate(
      ffi.nullptr,
      data.length,
      ffi.nullptr,
    );
    if (buffer == ffi.nullptr) {
      throw GStreamerException(
        'gst_buffer_new_allocate(${data.length}) failed',
      );
    }
    using((arena) {
      final map = arena<raw.GstMapInfo>();
      if (_b.gst_buffer_map(buffer, map, raw.GstMapFlags.GST_MAP_WRITE) == 0) {
        _b.gst_mini_object_unref(buffer.cast());
        throw GStreamerException('gst_buffer_map failed');
      }
      map.ref.data.cast<ffi.Uint8>().asTypedList(data.length).setAll(0, data);
      _b.gst_buffer_unmap(buffer, map);
    });
    buffer.ref.pts = ptsNs ?? gstClockTimeNone;
    buffer.ref.dts = gstClockTimeNone;
    buffer.ref.duration = durationNs ?? gstClockTimeNone;
    final flow = _b.gst_app_src_push_buffer(_src, buffer); // takes the buffer
    if (flow != raw.GstFlowReturn.GST_FLOW_OK) {
      throw GStreamerException(
        'appsrc "${element.name}" refused a buffer (GstFlowReturn $flow)',
      );
    }
  }

  /// Signals end-of-stream: the pipeline finishes once the queued buffers
  /// have been processed.
  void endOfStream() {
    element._check();
    _b.gst_app_src_end_of_stream(_src);
  }
}
