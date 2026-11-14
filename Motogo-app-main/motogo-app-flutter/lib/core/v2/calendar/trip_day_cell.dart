import 'package:flutter/material.dart';

import '../motion/mg_anim.dart';
import '../motion/mg_anim_loops.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import 'trip_day_state.dart';

/// One calendar day (46 h). Paints its own segment of the range band so the
/// selected range reads as ONE continuous `#74FB71` band per week row:
/// identical fill, number colour and weight for start, every middle day and
/// end — they differ only by the r11 cap; a wrapping row ends / starts r6.
/// Unselected days draw a 2 px inset box so the grid still looks spaced.
///
/// Owner 2026-11-14 (5.0.1 step H): only three looks — free (white box;
/// weekend a subtle green tone of it), "Obsazeno" (ONE hatched box with a
/// struck number for EVERY not-free kind; a past day's number is muted)
/// and, in the reservation edit only, red for days taken off the booking.
/// Added days are just the band. The owners' tap rules are unchanged.
class TripDayCell extends StatelessWidget {
  final TripDayState state;
  final bool rowStart;
  final bool rowEnd;
  final TripSkin skin;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Order of this day inside the band (grow-in delay, 20 ms each, ≤ 200 —
  /// DESIGN_V22 §3.6: the band grows 300 ms ease from start to end).
  final int bandOrder;

  const TripDayCell({
    super.key,
    required this.state,
    this.rowStart = false,
    this.rowEnd = false,
    this.skin = TripSkin.light,
    this.onTap,
    this.semanticLabel,
    this.bandOrder = 0,
  });

  static const double height = 46;

  /// Grow-in delay of the [order]-th band day: 20 ms per cell, capped 200.
  static Duration bandDelay(int order) {
    final d = MgMotion.bandCell * order;
    return d > MgMotion.bandCap ? MgMotion.bandCap : d;
  }

  bool get _dark => skin == TripSkin.dark;

  /// Red "Ubereš" day of the reservation edit (never on a band day).
  bool get _removed => !state.isSelected && state.editMark == TripEditMark.removed;

  Color get _numberColor {
    if (state.isSelected) return MgColors.onNeon;
    if (_removed) return _dark ? MgColors.errDark : MgColors.err;
    if (tripKindFree(state.kind)) return _dark ? MgColors.onDark : MgColors.ink;
    // "Obsazeno": the taken day's number; a past day the muted one.
    if (state.kind == TripDayKind.past) return _dark ? MgColors.white(0.36) : MgColors.disabled;
    return _dark ? MgColors.white(0.38) : MgColors.lead;
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final struck = !s.isSelected && (_removed || !tripKindFree(s.kind));
    final number = Text(
      '${s.date.day}',
      style: MgType.tab(MgType.calDay.copyWith(
        fontWeight: s.isSelected ? FontWeight.w900 : FontWeight.w800,
        color: _numberColor,
        decoration: struck ? TextDecoration.lineThrough : null,
        decorationColor: _numberColor,
      )),
    );
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        number,
        if (s.showsPrice)
          // 320 dp / large text: the price shrinks to the cell, never spills
          // into the neighbour day.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              s.price!,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: MgType.tab(MgType.calPrice.copyWith(
                color: s.isSelected ? MgColors.priceOnNeon : (_dark ? MgColors.neonText : MgColors.link),
              )),
            ),
            ),
          )
        else if (s.today)
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.isSelected ? MgColors.onNeon : (_dark ? MgColors.neon : MgColors.meta),
            ),
          ),
      ],
    );
    final reduced = MgMotion.reduced(context);
    // Added days of an edit are just the band (no extra mark, step H).
    Widget painted(double grow) => CustomPaint(
          painter: _DayPainter(s, rowStart, rowEnd, _dark, grow),
          child: Center(child: content),
        );
    Widget cell;
    if (s.isSelected && !reduced) {
      cell = MgProgressOnce(
        key: ValueKey('band-${s.selected}-${s.date.millisecondsSinceEpoch}'),
        duration: MgMotion.sheet,
        delay: bandDelay(bandOrder),
        curve: Curves.ease,
        builder: (_, t) => painted(t),
      );
    } else {
      cell = painted(1);
    }
    if (s.selected == TripSel.start || s.selected == TripSel.single) {
      cell = MgPop(trigger: s.selected, playOnMount: true, child: cell);
    }
    if (s.pendingStart && s.isSelected) {
      cell = MgPing(
        color: MgColors.link.withValues(alpha: 0.5),
        size: height,
        spread: 4,
        child: cell,
      );
    }
    return Semantics(
      button: s.enabled && onTap != null,
      selected: s.isSelected,
      enabled: s.enabled,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      onTap: s.enabled ? onTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(height: height, child: cell),
      ),
    );
  }
}

class _DayPainter extends CustomPainter {
  final TripDayState s;
  final bool rowStart, rowEnd, dark;
  final double grow;
  _DayPainter(this.s, this.rowStart, this.rowEnd, this.dark, this.grow);

  static const _cap = Radius.circular(11);

  @override
  void paint(Canvas canvas, Size size) {
    if (s.isSelected) {
      _band(canvas, size);
      return;
    }
    final box = RRect.fromRectAndRadius((Offset.zero & size).deflate(2), _cap);
    if (s.editMark == TripEditMark.removed) {
      // Red: the day leaves the booking (reservation edit only).
      canvas.drawRRect(box, Paint()..color = dark ? MgColors.errDarkBg : MgColors.errBg);
      _stroke(canvas, box.deflate(0.75), dark ? MgColors.errDark : MgColors.err, 1.5);
    } else if (tripKindFree(s.kind)) {
      final fill = dark
          ? MgColors.white(0.08)
          : (s.kind == TripDayKind.freeWeekend ? MgColors.weekendCell : MgColors.surface);
      canvas.drawRRect(box, Paint()..color = fill);
      if (!dark) _stroke(canvas, box, MgColors.line, 1);
    } else {
      // "Obsazeno": one look for every not-free kind.
      _hatch(canvas, box);
    }
    if (s.today) {
      // Neutral (not the green of "Tvůj termín"): today is not a picked day.
      _stroke(canvas, box.deflate(0.75), dark ? MgColors.white(0.75) : MgColors.meta, 1.5);
    }
  }

  void _band(Canvas canvas, Size size) {
    final continuesLeft = s.selected == TripSel.mid || s.selected == TripSel.end;
    final continuesRight = s.selected == TripSel.mid || s.selected == TripSel.start;
    final (left, right) = tripBandRadii(s.selected, rowStart: rowStart, rowEnd: rowEnd);
    // Overlap the neighbour by 0.5 px where the band continues, so no
    // anti-aliasing seam shows between days of one row.
    final l = continuesLeft && !rowStart ? -0.5 : 0.0;
    final r = continuesRight && !rowEnd ? size.width + 0.5 : size.width;
    var rect = Rect.fromLTRB(l, 0, r, size.height);
    if (grow < 1) rect = Rect.fromLTWH(l, 0, (r - l) * grow, size.height);
    final rr = RRect.fromRectAndCorners(rect, topLeft: left, bottomLeft: left, topRight: right, bottomRight: right);
    canvas.drawRRect(rr, Paint()..color = MgColors.calBand);
    if (s.pendingStart) {
      _stroke(canvas, rr.deflate(1), dark ? MgColors.onDark : MgColors.link, 2);
      return;
    }
    if (dark || grow < 1) return;
    // 1.5 px contour around the band: open on the sides that continue into
    // the neighbouring day (stroke extended past the cell and clipped).
    const w = 1.5;
    final openL = continuesLeft && !rowStart;
    final openR = continuesRight && !rowEnd;
    final outline = RRect.fromRectAndCorners(
      Rect.fromLTRB(openL ? -4 : w / 2, w / 2, openR ? size.width + 4 : size.width - w / 2, size.height - w / 2),
      topLeft: left, bottomLeft: left, topRight: right, bottomRight: right,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _stroke(canvas, outline, MgColors.calContour, w);
    canvas.restore();
  }

  void _stroke(Canvas canvas, RRect rr, Color c, double w) {
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = c,
    );
  }

  void _hatch(Canvas canvas, RRect box) {
    canvas.save();
    canvas.clipRRect(box);
    canvas.drawRRect(box, Paint()..color = dark ? MgColors.white(0.04) : MgColors.hatchB);
    final p = Paint()
      ..color = dark ? MgColors.white(0.10) : MgColors.hatchA
      ..strokeWidth = 4;
    final r = box.outerRect;
    for (double x = r.left - r.height; x < r.right + r.height; x += 8) {
      canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), p);
    }
    canvas.restore();
    if (!dark) _stroke(canvas, box, MgColors.line, 1);
  }

  @override
  bool shouldRepaint(_DayPainter o) =>
      o.s != s || o.rowStart != rowStart || o.rowEnd != rowEnd || o.dark != dark || o.grow != grow;
}

/// Corner radii (left, right) of a day's band segment: r11 caps only on the
/// range start / end (both for a single day), r6 where the range wraps to
/// the next / previous week row, square in between — so start, middle and
/// end differ ONLY by the cap.
(Radius, Radius) tripBandRadii(TripSel sel, {bool rowStart = false, bool rowEnd = false}) {
  const cap = Radius.circular(11), wrap = Radius.circular(6);
  final continuesLeft = sel == TripSel.mid || sel == TripSel.end;
  final continuesRight = sel == TripSel.mid || sel == TripSel.start;
  final left = continuesLeft ? (rowStart ? wrap : Radius.zero) : cap;
  final right = continuesRight ? (rowEnd ? wrap : Radius.zero) : cap;
  return (left, right);
}
