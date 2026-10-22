import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/v2/shell/shell_nav_map.dart';
import '../../catalog/catalog_provider.dart';
import '../../catalog/v2/calc/calc_state.dart';
import '../../catalog/v2/catalog_mode.dart';
import 'funnel_provider.dart';

/// Opens Motorky from Domů: the tab shows "‹ Domů" until a tab switch.
void _goSearch(BuildContext context, WidgetRef ref) {
  v2SetTabOrigin(ref, const V2TabOrigin(tab: 1, route: Routes.home, labelKey: 'v2TabHome'));
  GoRouter.maybeOf(context)?.go(Routes.search);
}

/// "Spočítat přesnou cenu ›" (PLAN §2.1 / §2.2.4): prefill the in-memory
/// calculator with the bike and / or range, switch Motorky to the
/// calculator and open the tab. Nothing else is written.
void homeOpenCalculator(BuildContext context, WidgetRef ref, {String? motoId, FunnelRange? range}) {
  if (motoId != null || range != null) {
    ref.read(calcStateProvider.notifier).prefill(motoId: motoId, start: range?.start, end: range?.end);
  }
  ref.read(catalogModeProvider.notifier).state = CatalogMode.calc;
  ref.read(catalogCalcRequestProvider.notifier).state = true;
  _goSearch(context, ref);
}

/// "Všechny motorky ›" / "Kdy jedeš příště?": Motorky in find mode; a range
/// is written exactly like the catalogue date picker does
/// (`catalogFilterProvider.copyWith(startDate, endDate)`).
void homeOpenBikes(BuildContext context, WidgetRef ref, {FunnelRange? range}) {
  ref.read(catalogModeProvider.notifier).state = CatalogMode.find;
  ref.read(catalogCalcRequestProvider.notifier).state = false;
  if (range != null) {
    final f = ref.read(catalogFilterProvider);
    ref.read(catalogFilterProvider.notifier).state =
        f.copyWith(startDate: () => range.start, endDate: () => range.end);
  }
  _goSearch(context, ref);
}
