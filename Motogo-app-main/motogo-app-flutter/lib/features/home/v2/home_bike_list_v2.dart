import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/widgets/state_views.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/moto_model.dart';
import '../../catalog/v2/catalog_mode_sync.dart' show catBeforeToday;
import '../../catalog/v2/catalog_price.dart';
import '../../catalog/v2/moto_card_full_v2.dart';
import '../../catalog/v2/motorky_loading_v2.dart';
import '../../loyalty/loyalty_provider.dart';

/// Full card height on Domů (the Motorky list geometry).
double homeBikeCardHeight(BuildContext context) => (MediaQuery.sizeOf(context).height * 0.72).clamp(460.0, 600.0);

/// "Zobrazeno: n motorek" under the filter (old Domů count line, same
/// loading / error texts).
class HomeBikeCountV2 extends ConsumerWidget {
  const HomeBikeCountV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final motosAsync = ref.watch(filteredMotorcyclesProvider);
    final style = MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: motosAsync.when(
        // Při změně filtru se výpis jen přepočítá — nesmí zmizet.
        skipLoadingOnReload: true,
        data: (motos) => Text(tr.tr('homeMotorcycleCount').replaceAll('{n}', '${motos.length}'),
            key: const ValueKey('home-bike-count'), style: style),
        loading: () => Text(tr.tr('homeLoadingMotorcycles'), style: style),
        error: (_, __) => Text(tr.tr('homeLoadingError'), style: style.copyWith(color: MgColors.err)),
      ),
    );
  }
}

/// The FULL sorted bike list of the old Domů (filter + dates + sort of the
/// panel above), each card → the bike detail with the shown order for its
/// pager — the old `MotoCard` tap. The card is the Motorky v2 card; its CTA
/// opens the same detail (the old card had only "Detail"). [heroes] off
/// while the funnel shows: its centred bike already carries the photo's
/// Hero tag (one tagged source per route, design M1).
class HomeBikeListV2 extends ConsumerWidget {
  final bool heroes;
  const HomeBikeListV2({super.key, this.heroes = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final motosAsync = ref.watch(filteredMotorcyclesProvider);
    final sort = ref.watch(catalogSortProvider);
    final f = ref.watch(catalogFilterProvider);
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    final h = homeBikeCardHeight(context);
    return motosAsync.when(
      skipLoadingOnReload: true,
      data: (all) {
        final motos = sortMotorcycles(all, sort);
        final s = f.startDate, e = f.endDate;
        final hasDates = s != null && e != null && !catBeforeToday(s);
        void open(Motorcycle m) {
          ref.read(filteredMotoIdsProvider.notifier).state = motos.map((m) => m.id).toList();
          context.push('/moto/${m.id}');
        }

        return SliverPadding(
          padding: const EdgeInsets.only(bottom: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final m = motos[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HeroMode(
                    enabled: heroes,
                    child: MotoCardFullV2(
                    key: ValueKey('home-mc-${m.id}'),
                    moto: m,
                    price: catCardPrice(tr, m, hasDates ? s : null, hasDates ? e : null, loyalty),
                    availability:
                        hasDates ? tr.tr('v2CatFreeInRange') : (m.availableToday == true ? tr.tr('v2CatFreeToday') : null),
                    ctaLabel: tr.tr('motoCardDetail'),
                    height: h,
                    onOpen: () => open(m),
                  ),
                  ),
                );
              },
              childCount: motos.length,
            ),
          ),
        );
      },
      loading: () => SliverToBoxAdapter(
        child: MotorkyLoadingV2(
          grid: false,
          cardHeight: h,
          onRetry: () => ref.invalidate(motorcyclesProvider),
        ),
      ),
      // Důvod + Zkusit znovu, nikdy syrová výjimka (jako stará Domů).
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MgErrorView(
            error: e,
            what: tr.tr('eoMotosLoadFail'),
            onRetry: () => ref.invalidate(motorcyclesProvider),
          ),
        ),
      ),
    );
  }
}
