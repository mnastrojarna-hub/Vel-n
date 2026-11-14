import 'dart:ui';

/// Minimal SVG path-data parser (M L H V C S Q T A Z, absolute + relative)
/// → [Path]. Synchronous and dependency-free, so v2 line icons render in the
/// first frame and in widget tests (no async SVG loading).
Path parseSvgPath(String d) {
  final p = Path();
  final t = _Tokens(d);
  var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
  double? lcx, lcy; // last control point (S / T reflection)
  var cmd = '';
  var prev = '';
  while (t.more) {
    final at = t.i;
    if (t.isCommand) {
      cmd = t.command();
    } else if (cmd.toUpperCase() == 'Z' || cmd.isEmpty) {
      break; // numbers without a command → invalid data, stop safely
    }
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        cx = ox + t.num();
        cy = oy + t.num();
        p.moveTo(cx, cy);
        sx = cx;
        sy = cy;
        lcx = null;
        cmd = rel ? 'l' : 'L'; // implicit lineto after the first pair
        break;
      case 'L':
        cx = ox + t.num();
        cy = oy + t.num();
        p.lineTo(cx, cy);
        lcx = null;
        break;
      case 'H':
        cx = ox + t.num();
        p.lineTo(cx, cy);
        lcx = null;
        break;
      case 'V':
        cy = oy + t.num();
        p.lineTo(cx, cy);
        lcx = null;
        break;
      case 'C':
        final x1 = ox + t.num(), y1 = oy + t.num();
        final x2 = ox + t.num(), y2 = oy + t.num();
        cx = ox + t.num();
        cy = oy + t.num();
        p.cubicTo(x1, y1, x2, y2, cx, cy);
        lcx = x2;
        lcy = y2;
        break;
      case 'S':
        final c = prev.toUpperCase();
        final x1 = (c == 'C' || c == 'S') && lcx != null ? 2 * cx - lcx : cx;
        final y1 = (c == 'C' || c == 'S') && lcy != null ? 2 * cy - lcy : cy;
        final x2 = ox + t.num(), y2 = oy + t.num();
        cx = ox + t.num();
        cy = oy + t.num();
        p.cubicTo(x1, y1, x2, y2, cx, cy);
        lcx = x2;
        lcy = y2;
        break;
      case 'Q':
        final x1 = ox + t.num(), y1 = oy + t.num();
        cx = ox + t.num();
        cy = oy + t.num();
        p.quadraticBezierTo(x1, y1, cx, cy);
        lcx = x1;
        lcy = y1;
        break;
      case 'T':
        final c = prev.toUpperCase();
        final x1 = (c == 'Q' || c == 'T') && lcx != null ? 2 * cx - lcx : cx;
        final y1 = (c == 'Q' || c == 'T') && lcy != null ? 2 * cy - lcy : cy;
        cx = ox + t.num();
        cy = oy + t.num();
        p.quadraticBezierTo(x1, y1, cx, cy);
        lcx = x1;
        lcy = y1;
        break;
      case 'A':
        final rx = t.num(), ry = t.num(), rot = t.num();
        final large = t.flag(), sweep = t.flag();
        cx = ox + t.num();
        cy = oy + t.num();
        p.arcToPoint(Offset(cx, cy),
            radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
        lcx = null;
        break;
      case 'Z':
        p.close();
        cx = sx;
        cy = sy;
        lcx = null;
        break;
      default:
        return p; // unknown command → stop safely
    }
    prev = cmd;
    if (t.i == at) break; // no progress → malformed data
  }
  return p;
}

class _Tokens {
  final String s;
  int i = 0;
  _Tokens(this.s);

  void _skip() {
    while (i < s.length && ' ,\n\t\r'.contains(s[i])) {
      i++;
    }
  }

  bool get more {
    _skip();
    return i < s.length;
  }

  bool get isCommand {
    _skip();
    return i < s.length && RegExp(r'[MmLlHhVvCcSsQqTtAaZz]').hasMatch(s[i]);
  }

  String command() => s[i++];

  bool flag() {
    _skip();
    final c = s[i++];
    return c == '1';
  }

  double num() {
    _skip();
    final start = i;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    var dot = false;
    while (i < s.length) {
      final c = s[i];
      if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) {
        i++;
      } else if (c == '.' && !dot) {
        dot = true;
        i++;
      } else if ((c == 'e' || c == 'E') && i + 1 < s.length) {
        i++;
        if (s[i] == '-' || s[i] == '+') i++;
      } else {
        break;
      }
    }
    return double.tryParse(s.substring(start, i)) ?? 0;
  }
}
