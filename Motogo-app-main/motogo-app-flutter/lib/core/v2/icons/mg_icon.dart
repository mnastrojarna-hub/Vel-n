import 'package:flutter/widgets.dart';

import 'mg_icons.dart';
import 'mg_svg_path.dart';

export 'mg_icons.dart' show MgIcons;

/// A v2 line icon (24 grid, round caps) painted synchronously. [name] is a
/// key of [MgIcons]; unknown names paint nothing (never throw). Decorative
/// by default — icon-only controls add their own `Semantics` label.
class MgIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  /// Stroke width on the 24 grid (2 for UI icons, 1.8 for feature icons).
  final double stroke;
  final String? semanticLabel;

  const MgIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color,
    this.stroke = 2,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF1A2E22);
    final icon = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: MgIconPainter(name, c, stroke)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: icon);
    return Semantics(label: semanticLabel, image: true, child: icon);
  }
}

/// Painter behind [MgIcon] (usable directly inside other painters).
class MgIconPainter extends CustomPainter {
  final String name;
  final Color color;
  final double stroke;
  MgIconPainter(this.name, this.color, [this.stroke = 2]);

  static final Map<String, (List<Path>, List<Path>)> _cache = {};

  static (List<Path>, List<Path>)? _paths(String name) {
    final d = kMgIcons[name];
    if (d == null) return null;
    return _cache.putIfAbsent(name, () {
      return (
        d.stroke.where((s) => s.isNotEmpty).map(parseSvgPath).toList(),
        d.fill.where((s) => s.isNotEmpty).map(parseSvgPath).toList(),
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = _paths(name);
    if (p == null) return;
    final k = size.shortestSide / 24;
    canvas.save();
    canvas.scale(k, k);
    final sp = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    for (final path in p.$1) {
      canvas.drawPath(path, sp);
    }
    final fp = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (final path in p.$2) {
      canvas.drawPath(path, fp);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MgIconPainter o) =>
      o.name != name || o.color != color || o.stroke != stroke;
}
