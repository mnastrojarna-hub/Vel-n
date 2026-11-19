import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/rank/mg_logo_ring.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../gear_order_state.dart';
import '../gear_order_ui.dart';
import 'gear_branch_v2.dart';
import 'gear_contact_v2.dart';
import 'gear_dates_v2.dart';
import 'gear_items_v2.dart';
import 'gear_summary_v2.dart';

/// v2 vzhled objednávky výbavy (`/gear-rental`): tmavá hlavička jako
/// rezervační formulář, pod ní 4 kroky webu (pobočka, termín, výbava
/// a velikosti, kontakt), souhrn a dok s „Pokračovat k platbě“.
class GearOrderViewV2 extends StatelessWidget {
  final GearOrderState state;
  final GearOrderController ctrl;
  final GearOrderFields fields;
  final GearOrderActions actions;
  final bool loading;
  final String? message;

  const GearOrderViewV2({
    super.key,
    required this.state,
    required this.ctrl,
    required this.fields,
    required this.actions,
    required this.loading,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final header = GearHeaderV2(onBack: actions.back);
    if (message != null) {
      return ColoredBox(
        color: MgColors.canvas,
        child: MgStateScreen(
          key: const ValueKey('gear-order-message'),
          tone: MgTone.info,
          title: tr.tr('groTitle'),
          why: message,
          primary: MgStateAction(tr.tr('groRetry'), actions.retry),
          onClose: actions.back,
          closeIsBack: true,
          support: true,
        ),
      );
    }
    if (loading || state.data == null) {
      return MgPage(
        overlapHero: false,
        pinnedBack: actions.back,
        sections: [
          header,
          for (var i = 0; i < 3; i++)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: MgSkeleton(height: 120, radius: 18),
            ),
        ],
      );
    }
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return MgPage(
      key: const ValueKey('gear-order-v2'),
      overlapHero: false,
      pinnedBack: actions.back,
      pinnedTitle: tr.tr('groTitle'),
      sections: [
        header,
        Transform.translate(
          offset: const Offset(0, -24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GearBranchV2(state: state, ctrl: ctrl),
            GearDatesV2(state: state, ctrl: ctrl),
            GearItemsV2(state: state, ctrl: ctrl, onToggleItem: actions.toggleItem, onToggleSet: actions.toggleSet),
            GearContactV2(state: state, ctrl: ctrl, fields: fields),
            GearSummaryV2(state: state),
          ]),
        ),
      ],
      dock: keyboard ? null : GearDockV2(state: state, onSubmit: actions.submit),
    );
  }
}

/// Tmavá hlavička (jako `BookingHeaderV2`): zpět, nadpis webu a úvod.
class GearHeaderV2 extends StatelessWidget {
  final VoidCallback onBack;
  const GearHeaderV2({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgRankHero(
      ambientKey: 'gear-rental',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgV2Back(onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('groTitle'), style: MgType.section.copyWith(color: MgColors.onDark)),
                const SizedBox(height: 4),
                Text(tr.tr('groLead'), style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          const MgLogoRing(size: 48),
        ]),
      ]),
    );
  }
}
