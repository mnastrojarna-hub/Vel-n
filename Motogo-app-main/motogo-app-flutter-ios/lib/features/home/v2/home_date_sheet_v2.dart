import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_calendar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/moto_model.dart';
import '../../catalog/widgets/availability_calendar.dart';
import 'funnel_dates.dart';
import 'funnel_provider.dart';
import 'home_offer_provider.dart';

/// Light date sheet of Home (DESIGN_V22 §3, uniform band): the EXISTING
/// `AvailabilityCalendar` (same tap rules as the catalogue date picker —
/// past days off, single day = tap twice, third tap resets) in its v2 look,
/// a summary row and one apply button. Returns the picked range, or null
/// when closed. [onClear] adds "Zrušit termín" (caller decides what it does).
/// [moto] = the calendar of that bike: its booked days (the same
/// `bookedDatesProvider` as the bike detail) and day prices.
Future<FunnelRange?> showHomeDateSheet(
  BuildContext context, {
  FunnelRange? initial,
  required String applyLabel,
  VoidCallback? onClear,
  Motorcycle? moto,
}) {
  final tr = t(context);
  return showMgSheet<FunnelRange>(
    context,
    title: tr.tr('v2HomeDateTitle'),
    maxHeightFactor: 0.92,
    builder: (_) => _DateSheetBody(initial: initial, applyLabel: applyLabel, onClear: onClear, moto: moto),
  );
}

class _DateSheetBody extends StatefulWidget {
  final FunnelRange? initial;
  final String applyLabel;
  final VoidCallback? onClear;
  final Motorcycle? moto;
  const _DateSheetBody({this.initial, required this.applyLabel, this.onClear, this.moto});

  @override
  State<_DateSheetBody> createState() => _DateSheetBodyState();
}

class _DateSheetBodyState extends State<_DateSheetBody> {
  DateTime? _start;
  DateTime? _end;

  /// "Přejít na 26. 3.": the calendar rebuilt on the bike's first free day.
  DateTime? _jump;

  /// "Použít termín": scrolled into view once it can be used (after
  /// "Přejít na" / a finished range) — on a short phone it sits below.
  final _apply = GlobalKey();

  void _showApply() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _apply.currentContext;
        if (c == null || !c.mounted) return;
        Scrollable.ensureVisible(c,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd, duration: const Duration(milliseconds: 250));
      });

  @override
  void initState() {
    super.initState();
    _start = widget.initial?.start;
    _end = widget.initial?.end;
  }

  @override
  Widget build(BuildContext context) => Consumer(builder: (context, ref, _) {
        final tr = t(context);
        final m = widget.moto;
        final booked =
            m == null ? const <BookedDateRange>[] : ref.watch(bookedDatesProvider(m.id)).valueOrNull ?? const [];
        final s = _start, e = _end;
        // Vybraný úsek přes obsazený / zavřený den se nepoužije (v5.0.1).
        final ready = s != null && e != null && !homeRangeHitsBooked(booked, FunnelRange(s, e));
        // Motorka volná až v jiném měsíci (zima, vše obsazené): řádek
        // „Volná od 26. 3." se skokem na ten den — ne měsíce přeškrtnutých dnů.
        final now = DateTime.now();
        final next = m == null ? null : ref.watch(homeNextFreeProvider).valueOrNull?[m.id];
        final far = next != null && (next.year != now.year || next.month != now.month) && _jump == null;
        final selStart = _jump ?? widget.initial?.start;
        final selEnd = _jump ?? widget.initial?.end;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(tr.tr('v2HomeDateSub'), style: MgType.small.copyWith(color: MgColors.lead)),
          const SizedBox(height: 12),
          if (s != null) ...[
            TripSummaryRow(start: s, end: e, days: e == null ? null : FunnelRange(s, e).days),
            const SizedBox(height: 12),
          ],
          if (m != null) ...[
            Text(m.model, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
            const SizedBox(height: 8),
          ],
          if (far) ...[
            Row(key: const ValueKey('home-sheet-next-free'), children: [
              const MgIcon(MgIcons.calendarCheck, size: 18, color: MgColors.neonLo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr.trArgs('homeOfferFreeFrom', {'date': funnelDate(tr, next)}),
                    style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
              ),
              MgBtnText(
                label: tr.trArgs('homeSheetJumpTo', {'date': funnelDate(tr, next)}),
                onTap: () {
                  setState(() {
                    _jump = next;
                    _start = next;
                    _end = next;
                  });
                  _showApply();
                },
              ),
            ]),
            const SizedBox(height: 8),
          ],
          AvailabilityCalendar(
            key: ValueKey(_jump),
            bookedDates: booked,
            dayPrices: m?.prices,
            selectedStart: selStart,
            selectedEnd: selEnd,
            // Kalendář motorky: legenda řekne, co znamená přeškrtnutý den.
            showLegend: m != null,
            onStartSelected: (d) => setState(() {
              _start = d;
              _end = null;
            }),
            onRangeSelected: (a, b) {
              setState(() {
                _start = a;
                _end = b;
              });
              _showApply();
            },
            onReset: () => setState(() {
              _start = null;
              _end = null;
            }),
          ),
          const SizedBox(height: 16),
          MgBtnInk(
            key: _apply,
            label: widget.applyLabel,
            neonLabel: true,
            onTap: ready ? () => Navigator.of(context).pop(FunnelRange(s, e)) : null,
          ),
          if (widget.onClear != null) ...[
            const SizedBox(height: 4),
            Center(
              child: MgBtnText(
                label: tr.tr('v2HomeDateClear'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onClear!();
                },
              ),
            ),
          ],
        ]);
      });
}

/// A day of [r] lies in a booked / closed block of the bike.
bool homeRangeHitsBooked(List<BookedDateRange> booked, FunnelRange r) {
  for (var d = r.start; !d.isAfter(r.end); d = DateTime(d.year, d.month, d.day + 1)) {
    if (booked.any((b) => b.containsDate(d))) return true;
  }
  return false;
}
