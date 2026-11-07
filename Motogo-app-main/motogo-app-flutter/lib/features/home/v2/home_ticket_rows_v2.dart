import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../reservations/reservation_models.dart';
import 'home_ticket_parts.dart';

// Rows of the Home ticket (moved out of home_ticket_v2.dart unchanged:
// pill row + dates row) and the S8 parts of board Main (day ring row and
// the V22 §4.2 B recording line).

/// Eyebrow left, status right; when both do not fit, each shrinks in
/// proportion to its natural width (never one pill squeezed to nothing);
/// [stacked] = one under the other (see [tkPillsStack]).
class TkPillRow extends StatelessWidget {
  final TkPill left;
  final TkPill? right;
  final bool stacked;
  const TkPillRow({super.key, required this.left, this.right, this.stacked = false});

  @override
  Widget build(BuildContext context) {
    final r = right;
    if (r == null) return Row(children: [Flexible(child: left)]);
    if (stacked) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        left,
        const SizedBox(height: 4),
        r,
      ]);
    }
    return Row(children: [
      Flexible(flex: tkPillWidth(context, left).round(), child: Align(alignment: Alignment.centerLeft, child: left)),
      const SizedBox(width: 8),
      Flexible(flex: tkPillWidth(context, r).round(), child: Align(alignment: Alignment.centerRight, child: r)),
    ]);
  }
}

/// "pá 16. 10. 12:00 → ne 18. 10. · 3 dny".
class TkDatesRow extends StatelessWidget {
  final Reservation res;
  const TkDatesRow({super.key, required this.res});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final pt = res.pickupHm;
    final rt = (res.returnTime ?? '').trim();
    final start = '${tripShortDate(tr, res.startDate)}${pt == null ? '' : ' $pt'}';
    final end = '${tripShortDate(tr, res.endDate)}${rt.length >= 5 ? ' ${rt.substring(0, 5)}' : ''}';
    final days = res.dayCount;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: MgColors.white(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MgColors.white(0.14)),
      ),
      child: Row(children: [
        const MgIcon(MgIcons.calendarCheck, size: 16, color: MgColors.neon),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$start → $end · $days ${tr.daysWord(days)}',
              style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDark))),
        ),
      ]),
    );
  }
}

/// S8 (board Main): day ring "{d}/{n}" + "den", "Vrať do {date time}" and
/// the return place — the booking's existing dates, place and time only.
class TkRideDayRow extends StatelessWidget {
  final Reservation res;
  final DateTime now;
  const TkRideDayRow({super.key, required this.res, required this.now});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final n = res.dayCount;
    final d = (tripDay(now).difference(tripDay(res.startDate)).inDays + 1).clamp(1, n);
    final rt = (res.returnTime ?? '').trim();
    final when = '${tripShortDate(tr, res.endDate)}${rt.length >= 5 ? ' ${rt.substring(0, 5)}' : ''}';
    final place = res.returnMethod == 'delivery' ? (res.returnAddress ?? '').trim() : (res.branchName ?? '').trim();
    return Row(children: [
      SizedBox.square(
        dimension: 60,
        child: CustomPaint(
          key: const ValueKey('tk-day-ring'),
          painter: _DayRingPainter(d / n),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$d/$n',
                  maxLines: 1,
                  softWrap: false,
                  style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, height: 1.1, color: MgColors.onDark))),
              Text(tr.tr('v2UxShDayLabel'), style: MgType.micro.copyWith(height: 1.1, color: MgColors.onDarkMeta)),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mgNbsp(tr.trArgs('v2UxShReturnBy', {'when': when})),
              style: MgType.tab(MgType.title.copyWith(color: MgColors.onDark))),
          if (place.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(place, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
          ],
        ]),
      ),
    ]);
  }
}

class _DayRingPainter extends CustomPainter {
  final double value;
  _DayRingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.5;
    final r = (size.shortestSide - stroke) / 2;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(c, r, p..color = MgColors.white(0.12));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * value.clamp(0.0, 1.0), false,
        p
          ..color = MgColors.neon
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_DayRingPainter old) => old.value != value;
}

/// V22 §4.2 B: "● Záznam jízdy z výpůjčky běží · 12,4 km" (the recorder's
/// live km) or the GPS-lost line — the ticket's one live indicator (ping).
class TkRecLine extends StatelessWidget {
  final bool gpsLost;
  final double km;
  const TkRecLine({super.key, required this.gpsLost, required this.km});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'cs';
    return Row(children: [
      const MgPing(size: 8, color: MgColors.sosDot),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          gpsLost ? tr.tr('v2HomeRecGpsLost') : tr.trArgs('v2UxShRecLine', {'km': mgKm(km, lang)}),
          style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: gpsLost ? MgColors.warnDark : MgColors.onDark),
        ),
      ),
    ]);
  }
}
