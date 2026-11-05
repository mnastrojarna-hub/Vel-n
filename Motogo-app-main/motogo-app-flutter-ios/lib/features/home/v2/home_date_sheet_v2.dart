import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_calendar.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../catalog/widgets/availability_calendar.dart';
import 'funnel_provider.dart';

/// Light date sheet of Home (DESIGN_V22 §3, uniform band): the EXISTING
/// `AvailabilityCalendar` (same tap rules as the catalogue date picker —
/// past days off, single day = tap twice, third tap resets) in its v2 look,
/// a summary row and one apply button. Returns the picked range, or null
/// when closed. [onClear] adds "Zrušit termín" (caller decides what it does).
Future<FunnelRange?> showHomeDateSheet(
  BuildContext context, {
  FunnelRange? initial,
  required String applyLabel,
  VoidCallback? onClear,
}) {
  final tr = t(context);
  return showMgSheet<FunnelRange>(
    context,
    title: tr.tr('v2HomeDateTitle'),
    maxHeightFactor: 0.92,
    builder: (_) => _DateSheetBody(initial: initial, applyLabel: applyLabel, onClear: onClear),
  );
}

class _DateSheetBody extends StatefulWidget {
  final FunnelRange? initial;
  final String applyLabel;
  final VoidCallback? onClear;
  const _DateSheetBody({this.initial, required this.applyLabel, this.onClear});

  @override
  State<_DateSheetBody> createState() => _DateSheetBodyState();
}

class _DateSheetBodyState extends State<_DateSheetBody> {
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initial?.start;
    _end = widget.initial?.end;
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = _start, e = _end;
    final ready = s != null && e != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(tr.tr('v2HomeDateSub'), style: MgType.small.copyWith(color: MgColors.lead)),
      const SizedBox(height: 12),
      if (s != null) ...[
        TripSummaryRow(start: s, end: e, days: e == null ? null : FunnelRange(s, e).days),
        const SizedBox(height: 12),
      ],
      AvailabilityCalendar(
        selectedStart: widget.initial?.start,
        selectedEnd: widget.initial?.end,
        showLegend: false,
        onStartSelected: (d) => setState(() {
          _start = d;
          _end = null;
        }),
        onRangeSelected: (a, b) => setState(() {
          _start = a;
          _end = b;
        }),
        onReset: () => setState(() {
          _start = null;
          _end = null;
        }),
      ),
      const SizedBox(height: 16),
      MgBtnInk(
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
  }
}
