import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_section.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/auth_provider.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/moto_model.dart';
import '../../loyalty/loyalty_provider.dart';
import '../../reservations/reservation_models.dart';
import '../../reservations/reservation_provider.dart';
import 'funnel_provider.dart';
import 'home_funnel_parts.dart';
import 'home_links.dart';
import 'home_ticket_parts.dart';
import 'home_reveal.dart';

/// "Motorky pro tebe" (S1–S9; in S0 / S10 the funnel holds them): 3 white
/// photo cards of bikes your licence allows (available today first), your
/// price from X Kč/day; the whole card opens the bike detail exactly like
/// today's Home list (sibling ids for swiping).
class HomeBikesForYouV2 extends ConsumerWidget {
  const HomeBikesForYouV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final async = ref.watch(motorcyclesProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final res = ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[];
    final pct = ref.watch(loyaltyStatusProvider).valueOrNull?.percent ?? 0;
    final all = homeEligibleMotos(async.valueOrNull ?? const <Motorcycle>[], profile, res);
    final ordered = [...all.where((m) => m.availableToday == true), ...all.where((m) => m.availableToday != true)];
    final pick = ordered.take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgSectionHeader(
          title: tr.tr('v2HomeBikesTitle'),
          trailingLabel: tr.tr('v2HomeAll'),
          onTrailing: () => homeOpenBikes(context, ref),
        ),
        if (async.hasError && !async.hasValue)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MgErrorView(
              error: async.error,
              what: tr.tr('eoMotosLoadFail'),
              compact: true,
              onRetry: () => ref.invalidate(motorcyclesProvider),
            ),
          )
        else if (pick.isNotEmpty)
          SizedBox(
            height: 336,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: pick.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => HomeReveal(
                index: i,
                sessionKey: 'home-bikes',
                child: _BikeCard(
                  moto: pick[i],
                  pct: pct,
                  onTap: () {
                    ref.read(filteredMotoIdsProvider.notifier).state = [for (final m in ordered) m.id];
                    homePushMoto(context, pick[i].id);
                  },
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _BikeCard extends StatelessWidget {
  final Motorcycle moto;
  final int pct;
  final VoidCallback onTap;
  const _BikeCard({required this.moto, required this.pct, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final cheapest = moto.prices?.cheapest ?? 0;
    final yours = (cheapest * (100 - pct) / 100).roundToDouble();
    final cat = homeCategoryKey(moto.category);
    final meta = [
      if ((moto.branchName ?? '').trim().isNotEmpty) moto.branchName!.trim(),
      if (cat.isNotEmpty) tr.tr(cat),
    ].join(' · ');
    return Semantics(
      button: true,
      label: '${moto.model}, $meta',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: onTap,
        child: Container(
          width: 280,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
            boxShadow: MgShadows.card,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(height: 150, child: HomePhoto(url: moto.displayImage, thumbWidth: 600)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(moto.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MgType.title.copyWith(color: MgColors.ink)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const MgIcon(MgIcons.pin, size: 16, color: MgColors.link),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MgType.small.copyWith(color: MgColors.lead)),
                    ),
                  ]),
                ],
                if (cheapest > 0) ...[
                  const SizedBox(height: 8),
                  Text(tr.tr('v2YourPrice'), style: MgType.meta.copyWith(color: MgColors.lead)),
                  Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
                    Text(tr.trArgs('v2HomeFromPerDay', {'amount': Money.czk(yours)}),
                        style: MgType.tab(MgType.section.copyWith(color: MgColors.link))),
                    if (pct > 0)
                      Text(Money.czk(cheapest),
                          style: MgType.tab(MgType.small.copyWith(
                              color: MgColors.meta,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: MgColors.meta))),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
