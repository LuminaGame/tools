import 'dart:io';

import 'package:flutter_gstreamer/flutter_gstreamer.dart';
import 'package:test/test.dart';

void main() {
  late GStreamer gst;

  setUpAll(() => gst = GStreamer.init());

  group('init', () {
    test('loads GStreamer 1.x and reports its version', () {
      expect(GStreamer.isInitialized, isTrue);
      expect(gst.version.major, 1);
      expect(gst.version.minor, greaterThanOrEqualTo(16));
      expect(gst.versionString, startsWith('GStreamer 1.'));
      expect(
        identical(GStreamer.init(), gst),
        isTrue,
        reason: 'init is idempotent',
      );
      expect(gst.libraries.paths, isNotEmpty);
    });

    test('finds the elements the WebM encoder and the probe need', () {
      for (final element in VideoEncoder.requiredElements(VideoInput.png)) {
        expect(gst.hasElement(element), isTrue, reason: element);
      }
      expect(gst.missingElements(['vp8enc', 'no-such-element-xyz']), [
        'no-such-element-xyz',
      ]);
    });
  });

  group('GstPipeline', () {
    test('runs a pipeline to EOS', () {
      final pipeline = GstPipeline.parse(
        'videotestsrc num-buffers=15 ! video/x-raw,width=64,height=48 ! fakesink name=sink',
      );
      addTearDown(pipeline.dispose);
      expect(pipeline.element('sink'), isNotNull);
      expect(pipeline.element('nope'), isNull);
      pipeline.play();
      pipeline.waitForEos(timeout: const Duration(seconds: 20));
      expect(pipeline.state, GstState.playing);
      pipeline.stop();
      expect(pipeline.state, GstState.nullState);
    });

    test('an unknown element fails to parse with a GStreamerException', () {
      expect(
        () =>
            GstPipeline.parse('videotestsrc ! no-such-element-xyz ! fakesink'),
        throwsA(
          isA<GStreamerException>().having(
            (e) => e.message,
            'message',
            contains('no-such-element-xyz'),
          ),
        ),
      );
    });

    test('a runtime error on the bus surfaces from waitForEos', () {
      final missing =
          '${Directory.systemTemp.path}/gst_missing_${DateTime.now().microsecondsSinceEpoch}.bin';
      final pipeline = GstPipeline.parse('filesrc name=src ! fakesink');
      addTearDown(pipeline.dispose);
      pipeline.element('src')!.set('location', missing);
      expect(
        () {
          pipeline.play();
          pipeline.waitForEos(timeout: const Duration(seconds: 20));
        },
        throwsA(
          isA<GStreamerException>().having((e) => e.source, 'source', 'src'),
        ),
      );
    });

    test('sets element properties from their string form', () {
      final pipeline = GstPipeline.parse('videotestsrc name=src ! fakesink');
      addTearDown(pipeline.dispose);
      pipeline.element('src')!.set('num-buffers', '5');
      pipeline.play();
      pipeline.waitForEos(timeout: const Duration(seconds: 20));
    });
  });
}
