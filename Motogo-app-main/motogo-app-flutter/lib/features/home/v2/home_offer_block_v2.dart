import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../booking/booking_quote.dart';
import '../../loyalty/loyalty_provider.dart';
import 'funnel_provider.dart';
import 'home_links.dart';
import 'home_reveal.dart';

/// Light block under the funnel (V22 §2.4 #5): the ½ offer (the screen's one
/// tint) with the centred bike's real 12:00 price, then a white card with
/// "Spočítat přesnou cenu" (→ calculator, prefilled) and "Všechny motorky"
/// (→ Motorky with the funnel dates).
class HomeOfferBlockV2 extends ConsumerWidget {
  const HomeOfferBlockV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final range = ref.watch(funnelSelectionProvider).range(DateTime.now());
    final list = ref.watch(funnelCandidatesProvider(range)).valueOrNull ?? const [];
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    final i = ref.watch(funnelCenterProvider);
    final moto = list.isEmpty ? null : list[i.clamp(0, list.length - 1)];
    String sub = tr.tr('v2HomeOfferSub');
    if (moto != null && range.days >= 2) {
      final late = quoteFor(moto, range.start, range.end, pickupTime: '12:00', loyalty: loyalty).total;
      sub = tr.trArgs('v2HomeOfferPrice', {'bike': moto.model, 'amount': Money.czk(late)});
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        HomeReveal(
          index: 1,
          sessionKey: 'home-offer',
          child: MgTintFeature(
            offer: true,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Text('½', style: MgType.section.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr.tr('v2HomeOfferTitle'), style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
                  const SizedBox(height: 2),
                  Text(sub, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onTintOk))),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        HomeReveal(
          index: 2,
          sessionKey: 'home-offer',
          child: MgCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              HomeLinkRow(
                icon: MgIcons.calc,
                title: tr.tr('v2HomeRowCalcTitle'),
                sub: tr.tr('v2HomeRowCalcSub'),
                onTap: () => homeOpenCalculator(context, ref, motoId: moto?.id, range: range),
              ),
              const Divider(height: 1, thickness: 1, color: MgColors.line),
              HomeLinkRow(
                icon: MgIcons.moto,
                title: tr.tr('v2HomeRowAllTitle'),
                sub: tr.tr('v2HomeRowAllSub'),
                onTap: () => homeOpenBikes(context, ref, range: range),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// White row: dark icon tile + title + sub + chevron (min 64).
class HomeLinkRow extends StatelessWidget {
  final String icon;
  final String title;
  final String? sub;
  final VoidCallback onTap;
  final Widget? leading;
  const HomeLinkRow({super.key, required this.icon, required this.title, this.sub, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: sub == null ? title : '$title, $sub',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.99,
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            leading ?? MgIconTileDark(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink, height: 1.3)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: MgType.small.copyWith(color: MgColors.meta)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
          ]),
        ),
      ),
    );
  }
}
