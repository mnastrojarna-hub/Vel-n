import 'package:flutter/widgets.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_svg_path.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../booking/booking_quote.dart';
import '../../loyalty/loyalty_provider.dart';
import '../moto_model.dart';
import 'catalog_text.dart';

/// What a catalog card shows as its price (display only). With a date range
/// the total comes from `quoteFor` — the SAME `PriceCalculator` call the
/// booking form makes for a fresh draft (no extras / fees / codes, pickup as
/// the form defaults), so the card never promises another amount than
/// `/booking`. Without dates: "od" per day = cheapest day − rank %.
class CatCardPrice {
  final String label;
  final String value;
  final String? unit;
  final String? struck;
  final String sub;

  /// Grid one-liner ("od 2 727 Kč/den" / "12 027 Kč / 3 dny").
  final String grid;
  final double? total;

  const CatCardPrice({
    required this.label,
    required this.value,
    required this.sub,
    required this.grid,
    this.unit,
    this.struck,
    this.total,
  });
}

CatCardPrice catCardPrice(
  AppTranslations tr,
  Motorcycle m,
  DateTime? start,
  DateTime? end,
  LoyaltyStatus? loyalty,
) {
  final pct = loyalty?.percent ?? 0;
  final cheapest = m.prices?.cheapest ?? 0;
  if (start != null && end != null && m.prices != null && cheapest > 0) {
    final q = quoteFor(m, start, end, loyalty: loyalty);
    final list = quoteFor(m, start, end);
    final days = q.days < 1 ? 1 : q.days;
    final gearFree = (loyalty?.level ?? 0) >= 3 && !m.isTrailer && m.category != 'detske';
    final avg = tr.trArgs('v2AvgPerDay', {'amount': catMoney((q.total / days).roundToDouble())});
    return CatCardPrice(
      label: tr.trArgs('v2CatPriceFor', {'days': catDays(tr, days)}),
      value: catMoney(q.total),
      struck: list.total > q.total ? catMoney(list.total) : null,
      sub: gearFree ? '$avg · ${tr.tr('v2CatGearFree')}' : avg,
      // No break inside "3 dny" (the grid column is narrow).
      grid: tr.trArgs('v2CatGridFor', {'amount': catMoney(q.total), 'days': catDays(tr, days).replaceAll(' ', '\u00A0')}),
      total: q.total,
    );
  }
  if (cheapest <= 0) {
    return CatCardPrice(
      label: tr.tr('v2CatPriceFrom'),
      value: '–',
      sub: tr.tr('v2CatPickDatesHint'),
      grid: '–',
    );
  }
  final from = catFromPerDay(m, pct);
  return CatCardPrice(
    label: tr.tr('v2CatPriceFrom'),
    value: catMoney(from),
    unit: tr.tr('pricePerDay'),
    struck: pct > 0 && from < cheapest ? catMoney(cheapest) : null,
    sub: tr.tr('v2CatPickDatesHint'),
    grid: tr.trArgs('v2CatGridFrom', {'amount': catMoney(from)}),
  );
}

/// Small line glyph from board path data (24 grid) for the two view
/// toggles the shared icon set does not have (big photos / grid).
class CatPathIcon extends StatelessWidget {
  final String d;
  final double size;
  final Color color;
  const CatPathIcon(this.d, {super.key, this.size = 20, required this.color});

  static const fullCards = 'M6 3h12a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z';
  static const grid = 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z';

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _PathPainter(d, color)),
        ),
      );
}

class _PathPainter extends CustomPainter {
  final String d;
  final Color color;
  _PathPainter(this.d, this.color);

  static final Map<String, Path> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final p = _cache.putIfAbsent(d, () => parseSvgPath(d));
    final k = size.shortestSide / 24;
    canvas.save();
    canvas.scale(k, k);
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PathPainter o) => o.d != d || o.color != color;
}

/// `AnimatedSize` 300 ms — or the plain child under reduced motion (a
/// zero-duration AnimatedSize re-dirties itself during layout).
Widget catAnimatedSize(BuildContext context, Widget child) => MgMotion.reduced(context)
    ? child
    : AnimatedSize(duration: MgMotion.sheet, alignment: Alignment.topCenter, child: child);
