import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Countdown chip in the dark payment header (PS-18, board 10.1 / 10.2):
/// night glass r14 + 1 px neon @ .22, a static live dot, clock icon and
/// "Zbývá {mm:ss} na zaplacení" (tabular) + "termín ti zatím držíme";
/// the last 5 minutes amber "Zbývá {mm:ss} — dokonči platbu"; while
/// paying "Platba probíhá…"; expired "Čas vypršel". It only SHOWS the
/// screen's existing remaining time — the timer and the expiry stay in
/// the screen. No own animation (the 1 Hz rebuild repaints only this).
class PayCountdownChipV2 extends StatelessWidget {
  /// The screen's existing "M:SS" text.
  final String time;
  final bool expired;
  final bool processing;

  /// Less than 5 minutes left.
  final bool warn;

  /// "termín ti zatím držíme" (booking flows only).
  final bool holdNote;

  const PayCountdownChipV2({
    super.key,
    required this.time,
    required this.expired,
    required this.processing,
    required this.warn,
    this.holdNote = false,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final String label;
    String? sub;
    var fg = MgColors.onDark;
    var dot = MgColors.neon;
    if (processing) {
      label = tr.tr('v2UxPsPaying');
    } else if (expired) {
      label = tr.tr('timeExpired');
      fg = MgColors.warnDark;
      dot = MgColors.warnDark;
    } else if (warn) {
      label = tr.trArgs('v2UxPsLastMinutes', {'time': time});
      fg = MgColors.warnDark;
      dot = MgColors.warnDark;
      if (holdNote) sub = tr.tr('v2UxPsHold');
    } else {
      label = tr.tr('timeRemainingLabel').replaceAll('{time}', time);
      if (holdNote) sub = tr.tr('v2UxPsHold');
    }
    return Semantics(
      container: true,
      label: sub == null ? label : '$label, $sub',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('pay-countdown-chip'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: MgColors.nightA(0.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MgColors.neonA(0.22)),
        ),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          MgIcon(MgIcons.clock, size: 16, color: fg),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              MgWordFit(
                minScale: 0.85,
                child: Text(label, style: MgType.tab(MgType.body.copyWith(fontSize: 13.5, fontWeight: FontWeight.w800, color: fg))),
              ),
              if (sub != null) Text(sub, style: MgType.small.copyWith(fontSize: 12, color: MgColors.onDarkLead)),
            ]),
          ),
        ]),
      ),
    );
  }
}
