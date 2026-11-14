import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_format.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../catalog/catalog_provider.dart';
import 'funnel_provider.dart';
import 'home_links.dart';
import 'home_offer_block_v2.dart' show HomeLinkRow;

/// "Spočítat přesnou cenu" on Domů — the price calculator entry the owner
/// asked for (V21 #2 "from Home and Motorky"), one row in every Home state.
/// With the funnel shown ([funnel]) it prefills the funnel's centred bike
/// and range (as the former offer block did); otherwise the dates the
/// customer gave in the catalogue (as the former pill did) — nothing is
/// ever picked twice (owner 2026-10-22).
class HomeCalcRowV2 extends ConsumerWidget {
  final bool funnel;
  const HomeCalcRowV2({super.key, required this.funnel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final lang = Localizations.localeOf(context).languageCode;
    String sub = tr.tr('v2HomeRowCalcSub');
    VoidCallback onTap;
    if (funnel) {
      final range = ref.watch(funnelRangeProvider);
      final list = ref.watch(funnelCandidatesProvider(range)).valueOrNull ?? const [];
      final i = ref.watch(funnelCenterProvider);
      final moto = list.isEmpty ? null : list[i.clamp(0, list.length - 1)];
      if (moto != null) sub = '${moto.model} · ${mgRange(range.start, range.end, lang)}';
      onTap = () => homeOpenCalculator(context, ref, motoId: moto?.id, range: range);
    } else {
      final f = ref.watch(catalogFilterProvider);
      final s = f.startDate, e = f.endDate;
      final current = s != null && e != null ? FunnelRange(s, e) : null;
      onTap = () => homeOpenCalculator(context, ref, range: current);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: MgCard(
        key: const ValueKey('home-calc-row'),
        padding: EdgeInsets.zero,
        child: HomeLinkRow(icon: MgIcons.calc, title: tr.tr('v2HomeRowCalcTitle'), sub: sub, onTap: onTap),
      ),
    );
  }
}
