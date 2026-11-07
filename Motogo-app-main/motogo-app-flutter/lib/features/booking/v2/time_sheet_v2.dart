import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'booking_v2_parts.dart';

/// v2 look of `TimeDropdownField` (CB-22): one input-like field "09:00 ⌄";
/// a tap opens a light sheet with every time of the old two dropdowns —
/// hours 00–23 × the same minute list — as the form's chips, the current
/// one selected and scrolled into view. A tap calls the SAME [onChanged]
/// with the same "HH:MM" string and closes the sheet; ✕ / swipe-down keep
/// the value. [halfFrom12] marks the 12:00+ times (½ first day, info only).
class TimeFieldV2 extends StatelessWidget {
  final int hour;
  final int minute;
  final List<int> minutes;
  final ValueChanged<String> onChanged;
  final String? sheetTitle;
  final bool halfFrom12;

  const TimeFieldV2({
    super.key,
    required this.hour,
    required this.minute,
    required this.minutes,
    required this.onChanged,
    this.sheetTitle,
    this.halfFrom12 = false,
  });

  static String fmt(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  void _open(BuildContext context) {
    final current = GlobalKey();
    showMgSheet<void>(
      context,
      title: sheetTitle ?? t(context).tr('v2UxCbPickTime'),
      builder: (c) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = current.currentContext;
          if (ctx != null && ctx.mounted) Scrollable.ensureVisible(ctx, alignment: 0.3);
        });
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var h = 0; h <= 23; h++) ...[
            if (halfFrom12 && h == 12)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(children: [
                  const BkHalfDisc(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MgWordFit(
                      minScale: 0.85,
                      child: Text(t(c).tr('v2UxCbHalfFrom12'),
                          style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk)),
                    ),
                  ),
                ]),
              ),
            Padding(
              key: h == hour ? current : null,
              padding: const EdgeInsets.only(bottom: MgSpace.s8),
              child: Wrap(spacing: MgSpace.s8, runSpacing: MgSpace.s8, children: [
                for (final m in minutes)
                  BkSizeChip(
                    label: fmt(h, m),
                    selected: h == hour && m == minute,
                    onTap: () {
                      onChanged(fmt(h, m));
                      Navigator.of(c).pop();
                    },
                  ),
              ]),
            ),
          ],
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = fmt(hour, minute);
    return Semantics(
      button: true,
      label: '${sheetTitle ?? t(context).tr('v2UxCbPickTime')}, $value',
      excludeSemantics: true,
      onTap: () => _open(context),
      child: MgPress(
        onTap: () => _open(context),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(MgRadius.button),
            border: Border.all(color: MgColors.lineInput, width: 1.5),
          ),
          child: Row(children: [
            MgIcon(MgIcons.clock, size: 20, color: MgColors.link),
            const SizedBox(width: 10),
            Text(value, style: MgType.tab(MgType.section.copyWith(color: MgColors.ink))),
            if (halfFrom12 && hour >= 12) ...[const SizedBox(width: 8), const BkHalfDisc()],
            const Spacer(),
            MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.link),
          ]),
        ),
      ),
    );
  }
}
