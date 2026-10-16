import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// Filter values of the list — the SAME values and order as the old screen
/// (`resFilterProvider`: all / aktivni / nadchazejici / dokoncene /
/// cancelled) and the same i18n words.
const kResFilterKeys = ['all', 'aktivni', 'nadchazejici', 'dokoncene', 'cancelled'];
const kResFilterI18n = ['all', 'active', 'upcoming', 'completed', 'cancelled'];

/// Filter track (V22 `.ls-seg` on a `well` track): one segment per filter
/// with its count; the selected one is ink with white text. Scrolls
/// sideways when the 8-language labels do not fit. Under it the swipe hint
/// with ‹ › (= the same filter step as the horizontal swipe).
class ResFilterTabsV2 extends StatefulWidget {
  final String value;
  final Map<String, int> counts;
  final ValueChanged<String> onSelect;
  final ValueChanged<int> onStep;

  const ResFilterTabsV2({
    super.key,
    required this.value,
    required this.counts,
    required this.onSelect,
    required this.onStep,
  });

  @override
  State<ResFilterTabsV2> createState() => _ResFilterTabsV2State();
}

class _ResFilterTabsV2State extends State<ResFilterTabsV2> {
  final _keys = {for (final k in kResFilterKeys) k: GlobalKey()};

  @override
  void didUpdateWidget(ResFilterTabsV2 old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _keys[widget.value]?.currentContext;
        if (c == null || !mounted) return;
        Scrollable.ensureVisible(c,
            alignment: 0.5,
            duration: MgMotion.of(context, MgMotion.tab),
            curve: MgMotion.out);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final idx = kResFilterKeys.indexOf(widget.value);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MgColors.line),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < kResFilterKeys.length; i++)
              _Tab(
                key: _keys[kResFilterKeys[i]],
                label: tr.tr(kResFilterI18n[i]),
                count: widget.counts[kResFilterKeys[i]] ?? 0,
                selected: kResFilterKeys[i] == widget.value,
                onTap: () => widget.onSelect(kResFilterKeys[i]),
              ),
          ]),
        ),
      ),
      SizedBox(
        height: 44,
        child: Row(children: [
          _Step(
            icon: MgIcons.chevronLeft,
            label: tr.tr('v2ResPrevFilter'),
            onTap: idx > 0 ? () => widget.onStep(-1) : null,
          ),
          Expanded(
            child: Text(tr.tr('v2ResSwipeHint'),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: MgType.meta.copyWith(color: MgColors.meta)),
          ),
          _Step(
            icon: MgIcons.chevronRight,
            label: tr.tr('v2ResNextFilter'),
            onTap: idx < kResFilterKeys.length - 1 ? () => widget.onStep(1) : null,
          ),
        ]),
      ),
    ]);
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({super.key, required this.label, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dur = MgMotion.of(context, MgMotion.tab);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: dur,
          curve: MgMotion.out,
          constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? MgColors.panel : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [BoxShadow(color: MgColors.panel.withValues(alpha: 0.5), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: MgType.small.copyWith(
                    fontWeight: FontWeight.w800, color: selected ? MgColors.onDark : MgColors.meta)),
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? MgColors.neonA(0.18) : MgColors.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$count',
                  style: MgType.tab(MgType.micro.copyWith(
                      fontWeight: FontWeight.w800, height: 1, color: selected ? MgColors.neon : MgColors.body2))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback? onTap;
  const _Step({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Opacity(
              opacity: onTap == null ? 0.3 : 1,
              child: MgIcon(icon, size: 22, color: MgColors.link),
            ),
          ),
        ),
      ),
    );
  }
}
