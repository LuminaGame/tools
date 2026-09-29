/// HTML escaping and ANSI-coloured console output as HTML.
library;

/// [text] with `&`, `<`, `>`, `"` and `'` escaped.
String escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const _ansiBasic = [
  '#000000', '#cd3131', '#0dbc79', '#e5e510', '#2472c8', '#bc3fbc', '#11a8cd', '#e5e5e5', //
  '#666666', '#f14c4c', '#23d18b', '#f5f543', '#3b8eea', '#d670d6', '#29b8db', '#ffffff',
];

/// The colour of xterm-256 palette entry [n].
String _ansi256(int n) {
  if (n < 16) return _ansiBasic[n];
  if (n < 232) {
    const steps = [0, 95, 135, 175, 215, 255];
    final i = n - 16;
    return _hex(steps[i ~/ 36], steps[(i ~/ 6) % 6], steps[i % 6]);
  }
  final g = 8 + (n - 232) * 10;
  return _hex(g, g, g);
}

String _hex(int r, int g, int b) => '#${[r, g, b].map((c) => c.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join()}';

/// Console output with its ANSI colour codes (a logger's `\x1B[36m[INFO]`,
/// flutter test's red failures) turned into coloured spans, and HTML
/// escaped. SGR codes set colour and style; every other escape sequence
/// (cursor moves, line erases) is dropped, as a terminal would not show it
/// either.
String ansiToHtml(String text) {
  final out = StringBuffer();
  final sequence = RegExp(r'\x1B\[([0-9;?]*)([A-Za-z])|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|\x1B[@-_]');
  String? fg; // class suffix (e.g. '36') or a css colour
  String? bg;
  var bold = false, dim = false, italic = false, underline = false;
  var open = false;

  void close() {
    if (open) out.write('</span>');
    open = false;
  }

  void start() {
    final classes = <String>[
      if (bold) 'ansi-b',
      if (dim) 'ansi-d',
      if (italic) 'ansi-i',
      if (underline) 'ansi-u',
      if (fg != null && !fg.startsWith('#')) 'ansi-$fg',
      if (bg != null && !bg.startsWith('#')) 'ansi-bg-$bg',
    ];
    final styles = <String>[
      if (fg != null && fg.startsWith('#')) 'color:$fg',
      if (bg != null && bg.startsWith('#')) 'background:$bg',
    ];
    if (classes.isEmpty && styles.isEmpty) return;
    out.write('<span');
    if (classes.isNotEmpty) out.write(' class="${classes.join(' ')}"');
    if (styles.isNotEmpty) out.write(' style="${styles.join(';')}"');
    out.write('>');
    open = true;
  }

  String? extended(List<int> codes, int i, void Function(int consumed) advance) {
    if (i + 1 >= codes.length) return null;
    if (codes[i + 1] == 5 && i + 2 < codes.length) {
      advance(2);
      return _ansi256(codes[i + 2]);
    }
    if (codes[i + 1] == 2 && i + 4 < codes.length) {
      advance(4);
      return _hex(codes[i + 2], codes[i + 3], codes[i + 4]);
    }
    return null;
  }

  var last = 0;
  for (final m in sequence.allMatches(text)) {
    out.write(escapeHtml(text.substring(last, m.start)));
    last = m.end;
    if (m.group(2) != 'm') continue;
    final codes = (m.group(1) ?? '').isEmpty ? [0] : m.group(1)!.split(';').map((c) => int.tryParse(c) ?? 0).toList();
    for (var i = 0; i < codes.length; i++) {
      final c = codes[i];
      if (c == 0) {
        fg = bg = null;
        bold = dim = italic = underline = false;
      } else if (c == 1) {
        bold = true;
      } else if (c == 2) {
        dim = true;
      } else if (c == 3) {
        italic = true;
      } else if (c == 4) {
        underline = true;
      } else if (c == 22) {
        bold = dim = false;
      } else if (c == 23) {
        italic = false;
      } else if (c == 24) {
        underline = false;
      } else if ((c >= 30 && c <= 37) || (c >= 90 && c <= 97)) {
        fg = '$c';
      } else if (c == 39) {
        fg = null;
      } else if ((c >= 40 && c <= 47) || (c >= 100 && c <= 107)) {
        bg = c >= 100 ? _ansiBasic[c - 100 + 8] : '$c';
      } else if (c == 49) {
        bg = null;
      } else if (c == 38 || c == 48) {
        final colour = extended(codes, i, (n) => i += n);
        if (c == 38) fg = colour ?? fg;
        if (c == 48) bg = colour ?? bg;
      }
    }
    close();
    start();
  }
  out.write(escapeHtml(text.substring(last)));
  close();
  return out.toString();
}
