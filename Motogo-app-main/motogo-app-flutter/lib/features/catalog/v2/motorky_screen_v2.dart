import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/widgets/state_views.dart';
import '../../loyalty/loyalty_provider.dart';
import '../catalog_provider.dart';
import '../moto_model.dart';
import 'calc/calc_body_v2.dart';
import 'catalog_date_sheet_v2.dart';
import 'catalog_filter_sheet_v2.dart';
import 'catalog_mode.dart';
import 'catalog_price.dart';
import 'catalog_text.dart';
import 'moto_card_full_v2.dart';
import 'moto_card_grid_v2.dart';
import 'motorky_header_v2.dart';

/// v2 Motorky tab (`/search`, PLAN §2.2.1, technique R): the SAME providers
/// as `MotoSearchScreen` — `filteredMotorcyclesProvider` (filter + date
/// availability), `catalogFilterProvider` (single source of the dates),
/// `catalogSortProvider` — and the same card tap (sibling ids for the
/// detail pager + `context.push('/moto/:id')`). Calculator mode =
/// `CalcBodyV2`. The old screen stays for the kill-switch OFF.
class MotorkyScreenV2 extends ConsumerStatefulWidget {
  const MotorkyScreenV2({super.key});

  @override
  ConsumerState<MotorkyScreenV2> createState() => _MotorkyScreenV2State();
}

class _MotorkyScreenV2State extends ConsumerState<MotorkyScreenV2> {
  bool _grid = false;

  /// Načíst katalog znovu (zdroj i odvozený filtrovaný seznam) — jako dřív.
  void _reloadMotos() {
    ref.invalidate(motorcyclesProvider);
    ref.invalidate(filteredMotorcyclesProvider);
  }

  /// Same as the old card `onTap`: order for swiping in the detail pager =
  /// the shown (sorted) list, then open the detail.
  void _open(List<Motorcycle> motos, Motorcycle m) {
    ref.read(filteredMotoIdsProvider.notifier).state = motos.map((m) => m.id).toList();
    context.push('/moto/${m.id}');
  }

  /// Same write as the branch dropdown of `MotoFilterPanel`.
  void _setBranch(String? id) {
    final f = ref.read(catalogFilterProvider);
    ref.read(catalogFilterProvider.notifier).state = f.copyWith(branch: () => id);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final mode = ref.watch(catalogModeProvider);
    final motosAsync = ref.watch(filteredMotorcyclesProvider);
    final filter = ref.watch(catalogFilterProvider);
    final sort = ref.watch(catalogSortProvider);
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    final count = motosAsync.hasValue ? motosAsync.value!.length : null;

    final header = MotorkyHeaderV2(
      mode: mode,
      onMode: (m) => ref.read(catalogModeProvider.notifier).state = m,
      count: mode == CatalogMode.find ? count : null,
      grid: _grid,
      onGrid: (g) => setState(() => _grid = g),
      onOpenDates: () => showCatalogDateSheet(context),
      onClearDates: () => catClearDates(ref),
      onOpenFilters: () => showCatalogFilterSheet(context),
      onBranch: _setBranch,
    );

    final List<Widget> slivers;
    if (mode == CatalogMode.calc) {
      slivers = const [SliverToBoxAdapter(child: CalcBodyV2())];
    } else {
      slivers = [
        motosAsync.when(
          // Při změně filtru se výpis jen přepočítá — nesmí zmizet.
          skipLoadingOnReload: true,
          data: (all) => _list(tr, sortMotorcycles(all, sort), filter, loyalty),
          // Nikdy holý spinner: po 15 s „trvá to déle" + Zkusit znovu.
          loading: () => SliverFillRemaining(hasScrollBody: false, child: MgLoadingView(onRetry: _reloadMotos)),
          // Co se stalo, proč a jak to opravit + akce.
          error: (e, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: MgErrorView(error: e, what: tr.tr('fxMotosLoadFail'), onRetry: _reloadMotos),
          ),
        ),
      ];
    }
    return MgPage(header: header, slivers: slivers, overlapHero: false, tabIndex: 1);
  }

  Widget _list(AppTranslations tr, List<Motorcycle> motos, CatalogFilter f, LoyaltyStatus? loyalty) {
    final s = f.startDate, e = f.endDate;
    final hasDates = s != null && e != null;
    if (motos.isEmpty) return SliverToBoxAdapter(child: _empty(tr, hasDates));
    final days = hasDates ? catDayCount(s, e) : 0;
    final countLine = hasDates
        ? '${tr.tr('searchAvailableMotorcycles').replaceAll('{n}', '${motos.length}')} · ${catDays(tr, days)}'
        : tr.tr('searchShownMotorcycles').replaceAll('{n}', '${motos.length}');
    String? avail(Motorcycle m) =>
        hasDates ? tr.tr('v2CatFreeInRange') : (m.availableToday == true ? tr.tr('v2CatFreeToday') : null);
    final cta = tr.tr(hasDates ? 'v2CatCtaBook' : 'v2CatCtaPick');
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Text(countLine.toUpperCase(), style: MgType.tab(MgType.eyebrow.copyWith(color: MgColors.meta))),
    );
    final foot = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(tr.tr('v2CatVatNote'), textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta)),
    );
    if (_grid) {
      Widget card(int i) => MotoCardGridV2(
            moto: motos[i],
            price: catCardPrice(tr, motos[i], s, e, loyalty),
            availability: avail(motos[i]),
            onOpen: () => _open(motos, motos[i]),
          );
      return SliverMainAxisGroup(slivers: [
        SliverToBoxAdapter(child: head),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              // Two cards per row, both as tall as the taller one.
              (context, r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: card(r * 2)),
                    const SizedBox(width: 12),
                    Expanded(child: r * 2 + 1 < motos.length ? card(r * 2 + 1) : const SizedBox.shrink()),
                  ]),
                ),
              ),
              childCount: (motos.length + 1) ~/ 2,
            ),
          ),
        ),
        SliverToBoxAdapter(child: foot),
      ]);
    }
    final h = (MediaQuery.sizeOf(context).height * 0.72).clamp(460.0, 600.0);
    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(child: head),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MotoCardFullV2(
              key: ValueKey('mc-${motos[i].id}'),
              moto: motos[i],
              price: catCardPrice(tr, motos[i], s, e, loyalty),
              availability: avail(motos[i]),
              live: i == 0,
              ctaLabel: cta,
              height: h,
              onOpen: () => _open(motos, motos[i]),
            ),
          ),
          childCount: motos.length,
        ),
      ),
      SliverToBoxAdapter(child: foot),
    ]);
  }

  Widget _empty(AppTranslations tr, bool hasDates) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: MgCard(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MgColors.well,
                shape: BoxShape.circle,
                border: Border.all(color: MgColors.line),
              ),
              child: Center(child: MgIcon(MgIcons.search, size: 32, color: MgColors.ink)),
            ),
            const SizedBox(height: 16),
            Text(
              tr.tr(hasDates ? 'searchNoMotorcycles' : 'v2CatEmptyTitle'),
              textAlign: TextAlign.center,
              style: MgType.h3.copyWith(color: MgColors.ink),
            ),
            const SizedBox(height: 8),
            Text(tr.tr('v2CatEmptyText'), textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
            const SizedBox(height: 20),
            MgBtnInk(label: tr.tr('v2CatEditFilters'), icon: MgIcons.filter, onTap: () => showCatalogFilterSheet(context)),
            if (hasDates) ...[
              const SizedBox(height: 8),
              MgBtnGhostLight(label: tr.tr('v2CatDateClear'), onTap: () => catClearDates(ref)),
            ],
          ]),
        ),
      );
}
