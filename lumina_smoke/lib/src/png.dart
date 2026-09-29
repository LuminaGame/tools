import 'dart:io';
import 'dart:typed_data';

/// A dependency-free RGBA8 / BGRA8 to PNG encoder (no filtering, zlib level
/// 6) and a PNG header reader.
abstract final class SmokePng {
  /// Encodes [w] × [h] RGBA8 pixels as a PNG. [flipY] flips the rows (for
  /// GL-style bottom-up readbacks); [bgra] swaps the red and blue channels of
  /// a BGRA8 buffer.
  static Uint8List encode(int w, int h, Uint8List rgba, {bool flipY = false, bool bgra = false}) {
    if (rgba.length < w * h * 4) {
      throw ArgumentError('rgba buffer too small for ${w}x$h RGBA8');
    }
    final raw = BytesBuilder(copy: false);
    for (var row = 0; row < h; row++) {
      final srcRow = flipY ? h - 1 - row : row;
      raw.addByte(0); // filter: none
      final start = srcRow * w * 4;
      final end = start + w * 4;
      if (bgra) {
        final line = Uint8List.fromList(Uint8List.sublistView(rgba, start, end));
        for (var i = 0; i < line.length; i += 4) {
          final b = line[i];
          line[i] = line[i + 2];
          line[i + 2] = b;
        }
        raw.add(line);
      } else {
        raw.add(Uint8List.sublistView(rgba, start, end));
      }
    }
    final idat = ZLibEncoder(level: 6).convert(raw.takeBytes());

    final out = BytesBuilder(copy: false)..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    void chunk(String type, List<int> data) {
      out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
      final body = Uint8List.fromList([...type.codeUnits, ...data]);
      out.add(body);
      out.add((ByteData(4)..setUint32(0, _crc32(body))).buffer.asUint8List());
    }

    final ihdr = ByteData(13)
      ..setUint32(0, w)
      ..setUint32(4, h)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6); // colour type RGBA
    chunk('IHDR', ihdr.buffer.asUint8List());
    chunk('IDAT', idat);
    chunk('IEND', const []);
    return out.takeBytes();
  }

  /// Width and height from a PNG's IHDR chunk; null when [png] is not a PNG.
  static (int, int)? size(Uint8List png) {
    const magic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (png.length < 24) return null;
    for (var i = 0; i < 8; i++) {
      if (png[i] != magic[i]) return null;
    }
    final bd = ByteData.sublistView(png);
    return (bd.getUint32(16), bd.getUint32(20));
  }

  // Table-driven CRC-32: frames of 1024×768 and up make the bitwise version
  // a noticeable share of every recorded frame.
  static final Uint32List _crcTable = () {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1;
      }
      t[n] = c;
    }
    return t;
  }();

  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}
