import 'dart:ui' as ui;

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
class TripDayCell extends StatelessWidget {
  final TripDayState state;
  final bool rowStart;
  final bool rowEnd;
  final TripSkin skin;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Order of this day inside the band (grow-in delay, 20 ms each, ≤ 200).
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

  bool get _dark => skin == TripSkin.dark;

  Color get _numberColor {
    if (state.isSelected) return MgColors.onNeon;
    if (state.editMark == TripEditMark.removed) return MgColors.err;
    switch (state.kind) {
      case TripDayKind.past:
      case TripDayKind.outOfLimit:
      case TripDayKind.closed:
      case TripDayKind.loading:
        return _dark ? MgColors.white(0.36) : MgColors.disabled;
      case TripDayKind.busy:
        return _dark ? MgColors.white(0.38) : MgColors.lead;
      case TripDayKind.yourOther:
      case TripDayKind.pending:
        return _dark ? MgColors.warnDark : MgColors.warn;
      case TripDayKind.free:
      case TripDayKind.freeWeekend:
        return _dark ? MgColors.onDark : MgColors.ink;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    final struck = s.kind == TripDayKind.busy || s.editMark == TripEditMark.removed;
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
          FittedBox(
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
          )
        else if (s.today)
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.isSelected ? MgColors.onNeon : (_dark ? MgColors.neon : MgColors.link),
            ),
          ),
      ],
    );
    final reduced = MgMotion.reduced(context);
    Widget painted(double grow) => CustomPaint(
          painter: _DayPainter(s, rowStart, rowEnd, _dark, grow),
          child: Stack(children: [
            Positioned.fill(child: Center(child: content)),
            if (s.editMark == TripEditMark.added)
              Positioned(
                top: 3,
                right: 5,
                child: Text('+',
                    style: MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon)),
              ),
          ]),
        );
    Widget cell;
    if (s.isSelected && !reduced) {
      cell = MgProgressOnce(
        key: ValueKey('band-${s.selected}-${s.date.millisecondsSinceEpoch}'),
        duration: const Duration(milliseconds: 140),
        delay: Duration(milliseconds: (bandOrder * 20).clamp(0, 200)),
        curve: Curves.easeOut,
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
    switch (s.kind) {
      case TripDayKind.free:
      case TripDayKind.freeWeekend:
      case TripDayKind.loading:
        final fill = dark
            ? MgColors.white(0.08)
            : (s.kind == TripDayKind.freeWeekend ? MgColors.weekendCell : MgColors.surface);
        canvas.drawRRect(box, Paint()..color = fill);
        if (!dark) _stroke(canvas, box, MgColors.line, 1);
      case TripDayKind.busy:
      case TripDayKind.closed:
        _hatch(canvas, box);
      case TripDayKind.yourOther:
        canvas.drawRRect(box, Paint()..color = dark ? MgColors.warnDarkBg : MgColors.warnBg);
        _dashed(canvas, box, dark ? MgColors.warnDark.withValues(alpha: 0.75) : MgColors.warnBorder);
      case TripDayKind.pending:
        _dashed(canvas, box, dark ? MgColors.warnDark.withValues(alpha: 0.75) : MgColors.pending);
      case TripDayKind.past:
      case TripDayKind.outOfLimit:
        break;
    }
    if (s.editMark == TripEditMark.removed) _dashed(canvas, box, MgColors.err);
    if (s.today) {
      _stroke(canvas, box.deflate(0.75), dark ? MgColors.white(0.75) : MgColors.link, 1.5);
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

  void _dashed(Canvas canvas, RRect box, Color c) {
    final path = Path()..addRRect(box.deflate(0.75));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = c;
    for (final ui.PathMetric m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), p);
      }
    }
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
