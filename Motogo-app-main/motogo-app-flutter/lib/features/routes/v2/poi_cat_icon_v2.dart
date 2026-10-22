import 'package:flutter/widgets.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/icons/mg_svg_path.dart';
import '../poi_categories.dart';
import '../routes_model.dart';

/// Line icons of the place categories (board TrasyHub `.cats`, 24 grid,
/// stroke 2, round caps) — v2 replaces the category emoji with these.
const Map<String, String> _kCatPaths = {
  'food': 'M7 3v8M5 3v4a2 2 0 0 0 4 0V3M7 11v10M16 3c-1.7 1-3 3-3 6v3h3v9',
  'castle': 'M4 21V9l2 1V7h2v2h2V7h4v2h2V7h2v3l2-1v12zM10 21v-4a2 2 0 0 1 4 0v4',
  'lookout': 'M9 21l1.5-12h3L15 21M8 9h8M12 3v6M9.5 5h5M7 21h10M10 15h4',
  'water': 'M3 9c2 0 2-1.5 4.5-1.5S9.5 9 12 9s2.5-1.5 4.5-1.5S19 9 21 9M3 14c2 0 2-1.5 4.5-1.5S9.5 14 12 14'
      's2.5-1.5 4.5-1.5S19 14 21 14M3 19c2 0 2-1.5 4.5-1.5S9.5 19 12 19s2.5-1.5 4.5-1.5S19 19 21 19',
  'spring': 'M12 3s6 6.6 6 11a6 6 0 0 1-12 0c0-4.4 6-11 6-11z',
  'sights': 'M3 21h18M5 21v-8M9.5 21v-8M14.5 21v-8M19 21v-8M2.5 10L12 4l9.5 6z',
  'nature': 'M12 22v-6M12 3l6 8h-3l4 5H5l4-5H6z',
  'military': 'M12 3l7 3v5c0 4.5-3 8.2-7 10-4-1.8-7-5.5-7-10V6zM12 8.5l1.2 2.4 2.6.4-1.9 1.8.5 2.6L12 14.5'
      'l-2.4 1.2.5-2.6-1.9-1.8 2.6-.4z',
  'aviation': 'M21 15v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V8l-8 5v2l8-2.5V18l-2 1.5V21l3.5-1 3.5 1v-1.5L13 18v-5.5z',
  'tech': 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19 12h2M3 12h2M12 3v2M12 19v2M17 7l1.5-1.5M5.5 18.5L7 17'
      'M17 17l1.5 1.5M5.5 5.5L7 7',
  'moto': 'M5 21V4M5 4h13l-2 4 2 4H5',
};

/// Category icon of [catKey] (`other` / unknown → the place pin).
class PoiCatIconV2 extends StatelessWidget {
  final String catKey;
  final double size;
  final Color color;
  const PoiCatIconV2(this.catKey, {super.key, this.size = 16, required this.color});

  /// Icon of a place (category resolved the same way as the old list).
  factory PoiCatIconV2.of(RoutePoi p, {double size = 16, required Color color}) =>
      PoiCatIconV2(poiCategoryOf(p), size: size, color: color);

  @override
  Widget build(BuildContext context) {
    final d = _kCatPaths[catKey];
    if (d == null) return MgIcon(MgIcons.pin, size: size, color: color);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CatPainter(d, color)),
      ),
    );
  }
}

class _CatPainter extends CustomPainter {
  final String d;
  final Color color;
  _CatPainter(this.d, this.color);

  static final Map<String, Path> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final path = _cache.putIfAbsent(d, () => parseSvgPath(d));
    final k = size.shortestSide / 24;
    canvas.save();
    canvas.scale(k, k);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CatPainter old) => old.d != d || old.color != color;
}

/// Localised category label (same lookup as the old `_catLabel`).
String poiCatLabelKey(RoutePoi p) {
  final k = poiCategoryOf(p);
  for (final c in kPoiCats) {
    if (c.key == k) return c.i18nKey;
  }
  return 'poiCatOther';
}
