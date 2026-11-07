import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/widgets/pickup_location_link.dart';
import 'pay_parts_v2.dart';

/// One "CO BUDE DÁL" step: its text and an optional block under it (a T3
/// banner, the map button).
class PayStep {
  final String text;
  final List<Widget> extra;
  const PayStep(this.text, [this.extra = const []]);
}

/// "CO BUDE DÁL" card (Stavy 1.1): eyebrow with a neon dot, numbered
/// 34 px dark discs with neon numbers (the `MgStateSteps` look) and the
/// step's own block under the text.
class PayStepsCardV2 extends StatelessWidget {
  final String title;
  final List<PayStep> steps;
  const PayStepsCardV2({super.key, required this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    return PayCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: MgColors.neonLo, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(child: PayEyebrowV2(title)),
        ]),
        const SizedBox(height: MgSpace.s12),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : MgSpace.s12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: MgColors.panel, shape: BoxShape.circle),
                child: Text('${i + 1}',
                    style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: MgWordFit(child: Text(steps[i].text, style: MgType.body.copyWith(color: MgColors.body2))),
                  ),
                  for (final e in steps[i].extra) ...[const SizedBox(height: MgSpace.s10), e],
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// "Otevřít v mapě" (the SAME `openPickupMap` as `PickupLocationLink`) and
/// the gate arrival notice where the branch has a gate (same provider,
/// same texts) — the v2 look of the pickup actions.
class PayPickupActionsV2 extends ConsumerWidget {
  final PickupInfo info;
  const PayPickupActionsV2({super.key, required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final id = info.branchId;
    final gate = id != null && (ref.watch(branchHasGateProvider(id)).valueOrNull ?? false);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      MgBtnGhostLight(label: tr.tr('openInMap'), icon: MgIcons.map, height: 44, onTap: () => openPickupMap(info)),
      if (gate) ...[
        const SizedBox(height: MgSpace.s10),
        MgStateBanner(tone: MgTone.warn, icon: MgIcons.lock, title: tr.tr('gateNoticeTitle'), text: tr.tr('gateNotice')),
      ],
    ]);
  }
}

/// A fact row of a summary card: icon, small caps label, value 14/800.
class PayFactRowV2 extends StatelessWidget {
  final String label;
  final String value;
  final String? icon;
  const PayFactRowV2({super.key, required this.label, required this.value, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: MgColors.line))),
        child: Row(children: [
          if (icon != null) ...[MgIcon(icon!, size: 16, color: MgColors.meta), const SizedBox(width: 8)],
          Expanded(child: MgWordFit(child: Text(label, style: MgType.meta.copyWith(color: MgColors.meta)))),
          const SizedBox(width: 10),
          Text(value, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
        ]),
      );
}
