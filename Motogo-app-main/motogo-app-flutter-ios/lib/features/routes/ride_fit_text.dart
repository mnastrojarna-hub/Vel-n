import 'package:flutter/material.dart';

/// Popisky jízd ve starém vzhledu (oba stromy appky): text se NIKDY
/// nerozdělí uprostřed slova („nastoupán|o") a neusekne výpustkou. Když se
/// nejdelší slovo nevejde do šířky (nebo text do [lines] řádků), celý text
/// se zmenší — po 5 %, nejvýš na [minScale]. Stejné pravidlo jako v2
/// `MgWordFit`, jen přes velikost písma (v2 widgety tu nejsou).
class RideFitText extends StatelessWidget {
  const RideFitText(
    this.text, {
    super.key,
    required this.style,
    this.lines,
    this.minScale = 0.7,
    this.textAlign,
    this.ellipsis = false,
  });

  final String text;
  final TextStyle style;

  /// Kolik řádků se smí použít (null = libovolně, hlídá se jen slovo).
  final int? lines;
  final double minScale;
  final TextAlign? textAlign;

  /// Jen pro data jezdce (vlastní název jízdy): když se ani na [minScale]
  /// nevejde do [lines] řádků, zbytek se usekne „…". Texty appky nikdy.
  final bool ellipsis;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final s = rideFitScale(context, text, style, c.maxWidth, lines: lines, minScale: minScale) ?? minScale;
        return Text(
          text,
          textAlign: textAlign,
          maxLines: ellipsis ? lines : null,
          overflow: ellipsis ? TextOverflow.ellipsis : null,
          style: s >= 1 ? style : style.copyWith(fontSize: rideFitBaseSize(context, style) * s),
        );
      });
}

/// Velikost písma, ze které se zmenšuje (styl widgetu nebo zděděný).
double rideFitBaseSize(BuildContext context, TextStyle style) =>
    style.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14;

final _space = RegExp(r'[ \t\n]+'); // NBSP (U+00A0) slova záměrně spojuje

/// Největší měřítko v [minScale, 1], při kterém se nejdelší slovo [text]
/// vejde do [width] (a celý text do [lines] řádků); null = nevejde se ani
/// na [minScale]. Měří stejně jako `Text` (zděděný styl, `textScaler`).
double? rideFitScale(BuildContext context, String text, TextStyle style, double width,
    {int? lines, double minScale = 0.7}) {
  if (!width.isFinite || width <= 0 || text.trim().isEmpty) return 1;
  final base = DefaultTextStyle.of(context).style.merge(style);
  final size = rideFitBaseSize(context, style);
  final scaler = MediaQuery.textScalerOf(context);
  final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
  final words = text.split(_space).where((w) => w.isNotEmpty).toList();
  final tp = TextPainter(textDirection: dir, textScaler: scaler);
  try {
    for (var s = 1.0; s >= minScale - 0.001; s -= 0.05) {
      final st = base.copyWith(fontSize: size * s);
      var ok = true;
      for (final w in words) {
        tp
          ..text = TextSpan(text: w, style: st)
          ..maxLines = 1
          ..layout();
        if (tp.width > width + 0.01) {
          ok = false;
          break;
        }
      }
      if (ok && lines != null) {
        tp
          ..text = TextSpan(text: text, style: st)
          ..maxLines = lines
          ..layout(maxWidth: width);
        ok = !tp.didExceedMaxLines;
      }
      if (ok) return s;
    }
    return null;
  } finally {
    tp.dispose();
  }
}

/// Popisek tlačítka na jeden řádek: na úzkém telefonu / velkém písmu se
/// zmenší, místo aby se zalomil uprostřed slova („Speiche|rn").
Widget rideFitLabel(String label, {TextStyle? style}) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, maxLines: 1, softWrap: false, style: style),
    );
