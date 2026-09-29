import 'dart:io';

import 'package:flutter_gstreamer/flutter_gstreamer.dart';
import 'package:test/test.dart';

/// Loading failures: kept in their own file (their own isolate) so no
/// earlier successful [GStreamer.init] is cached when they run.
void main() {
  late Directory empty;

  setUp(() => empty = Directory.systemTemp.createTempSync('gst_empty_root_'));
  tearDown(() => empty.deleteSync(recursive: true));

  test(
    'an explicit root without GStreamer throws GStreamerNotFoundException',
    () {
      expect(
        () => GStreamerLibraries.open(root: empty.path),
        throwsA(
          isA<GStreamerNotFoundException>()
              .having((e) => e.searched, 'searched', isNotEmpty)
              .having(
                (e) => e.toString(),
                'message',
                contains(empty.path.replaceAll('\\', '/')),
              ),
        ),
      );
    },
  );

  test(
    'GStreamer.init with an empty root fails cleanly and leaves nothing cached',
    () {
      expect(
        () => GStreamer.init(root: empty.path),
        throwsA(isA<GStreamerNotFoundException>()),
      );
      expect(GStreamer.isInitialized, isFalse);
      expect(GStreamer.isAvailable(root: empty.path), isFalse);
      // The failure is not sticky: the default lookup still works afterwards.
      expect(GStreamer.isAvailable(), isTrue);
      expect(GStreamer.isInitialized, isTrue);
    },
  );

  test(
    'GStreamerNotFoundException is an Exception with a readable message',
    () {
      try {
        GStreamerLibraries.open(root: empty.path);
        fail('expected GStreamerNotFoundException');
      } on Exception catch (e) {
        expect(e, isA<GStreamerNotFoundException>());
        expect(e.toString(), startsWith('GStreamerNotFoundException: '));
        expect(e.toString(), contains('GStreamer'));
      }
    },
  );
}
