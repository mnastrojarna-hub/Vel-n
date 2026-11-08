import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/gestures/mg_zone_snap.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../loyalty/loyalty_provider.dart';
import '../catalog_provider.dart';
import '../moto_model.dart';
import 'bike_screen_list_v2.dart';
import 'calc/calc_body_v2.dart';
import 'calc/calc_sticky_v2.dart';
import 'catalog_mode.dart';
import 'catalog_mode_sync.dart';
import 'catalog_price.dart';
import 'catalog_text.dart';
import 'moto_card_full_v2.dart';
import '../widgets/moto_filter_panel.dart';
import 'motorky_dates_card_v2.dart';
import 'motorky_error_v2.dart';
import 'motorky_header_v2.dart';
import 'motorky_loading_v2.dart';

/// v2 Motorky tab (`/search`, PLAN §2.2.1, technique R): the SAME providers
/// as `MotoSearchScreen` — `filteredMotorcyclesProvider` (filter + date
/// availability), `catalogFilterProvider` (single source of the dates),
/// `catalogSortProvider` — and the same card tap (sibling ids for the
/// detail pager + `context.push('/moto/:id')`). Calculator mode =
/// `CalcBodyV2` (+ its sticky REZERVOVAT dock). A trip that already started
/// in the past (app alive across days) is dropped on mount and on resume.
/// The old screen stays for the kill-switch OFF.
class MotorkyScreenV2 extends ConsumerStatefulWidget {
  const MotorkyScreenV2({super.key});

  @override
  ConsumerState<MotorkyScreenV2> createState() => _MotorkyScreenV2State();
}

class _MotorkyScreenV2State extends ConsumerState<MotorkyScreenV2>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// CB-27: the content under the mode switch fades in over `enter` 450
  /// when the mode changes (V21 §3.1); full at once under reduced motion.
  late final AnimationController _modeFade = AnimationController(vsync: this, duration: MgMotion.enter, value: 1);

  void _fadeMode() {
    if (MgMotion.reduced(context)) {
      _modeFade.value = 1;
    } else {
      _modeFade.forward(from: 0);
    }
  }

  /// Mode of THIS mount: the calculator only on an explicit request (Home
  /// funnel), otherwise the bike list — a once-used calculator must not
  /// hijack later "find a bike" entries (Pobočka, empty Rezervace…).
  late CatalogMode _mode;

  /// One bike per screen: the list's cards the page scroll settles on.
  final MgSnapZone _zone = MgSnapZone();

  @override
  void initState() {
    super.initState();
    _mode = ref.read(catalogCalcRequestProvider) ? CatalogMode.calc : CatalogMode.find;
    WidgetsBinding.instance.addObserver(this);
    // Consume the request and align the shared mode (never during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(catalogCalcRequestProvider.notifier).state = false;
      catDropPastDates(ref);
      // Any tab tap remounts the tab in "Najít motorku": the calculator's
      // range of the previous mount is not picked again.
      if (ref.read(catalogModeProvider) == CatalogMode.calc && _mode == CatalogMode.find) {
        catCarryCalcDatesOnRemount(ref);
      }
      if (ref.read(catalogModeProvider) != _mode) ref.read(catalogModeProvider.notifier).state = _mode;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _modeFade.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) catDropPastDates(ref);
  }

  void _setMode(CatalogMode m) {
    if (m != _mode) {
      // One trip for both modes: carry the dates / branch of the mode the
      // customer is leaving (owner 2026-10-22, nothing picked twice).
      if (m == CatalogMode.calc) {
        catCarryListToCalc(ref);
      } else {
        catCarryCalcToList(ref);
      }
      setState(() => _mode = m);
      _fadeMode();
    }
    if (ref.read(catalogModeProvider) != m) ref.read(catalogModeProvider.notifier).state = m;
  }

  /// Načíst katalog znovu (zdroj i odvozený filtrovaný seznam) — jako dřív.
  void _reloadMotos() {
    ref.invalidate(motorcyclesProvider);
    ref.invalidate(filteredMotorcyclesProvider);
  }

  /// Pull-to-refresh (CB-18): the SAME reload as "Zkusit znovu", waiting
  /// for the new list so the spinner ends with it.
  Future<void> _refresh() async {
    _reloadMotos();
    try {
      await ref.read(filteredMotorcyclesProvider.future);
    } catch (_) {
      // The error state of the list says what happened.
    }
  }

  /// Full card height = one bike per screen (the skeleton uses the same
  /// geometry).
  double _cardHeight(BuildContext context) => bikeScreenHeight(context);

  /// Same as the old card `onTap`: order for swiping in the detail pager =
  /// the shown (sorted) list, then open the detail.
  void _open(List<Motorcycle> motos, Motorcycle m) {
    ref.read(filteredMotoIdsProvider.notifier).state = motos.map((m) => m.id).toList();
    context.push('/moto/${m.id}');
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    // Switches from inside the tab (calculator "show free") write the
    // shared mode — follow them.
    ref.listen<CatalogMode>(catalogModeProvider, (_, next) {
      if (next != _mode) {
        setState(() => _mode = next);
        _fadeMode();
      }
    });
    // Dates picked elsewhere while the calculator is shown (its "Detail ›")
    // are already answered there too.
    ref.listen<CatalogFilter>(catalogFilterProvider, (prev, next) {
      if (_mode == CatalogMode.calc) catCalcFollowFilter(ref, prev, next);
    });
    final mode = _mode;
    final motosAsync = ref.watch(filteredMotorcyclesProvider);
    final filter = ref.watch(catalogFilterProvider);
    final sort = ref.watch(catalogSortProvider);
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    final sticky = mode == CatalogMode.calc ? ref.watch(calcStickyProvider) : null;

    final header = MotorkyHeaderV2(
      mode: mode,
      onMode: _setMode,
      // The old search header: back → Domů (tab root), menu → Profil.
      onBack: () => context.go(Routes.home),
      onMenu: () => context.go(Routes.profile),
    );

    final List<Widget> slivers;
    if (mode == CatalogMode.calc) {
      slivers = const [SliverToBoxAdapter(child: CalcBodyV2())];
    } else {
      // The old search screen's order: dates (inline, open) → filter panel
      // → count line → the list.
      slivers = [
        const SliverToBoxAdapter(child: MotorkyDatesCardV2()),
        const SliverToBoxAdapter(child: MotoFilterPanel()),
        SliverToBoxAdapter(child: _countLine(tr, motosAsync, filter)),
        motosAsync.when(
          // Při změně filtru se výpis jen přepočítá — nesmí zmizet.
          skipLoadingOnReload: true,
          data: (all) => _list(tr, sortMotorcycles(all, sort), filter, loyalty),
          // Kostry ve tvaru karet (CB-08); po 15 s „trvá to déle" + Zkusit znovu.
          loading: () => SliverToBoxAdapter(
            child: MotorkyLoadingV2(grid: false, cardHeight: _cardHeight(context), onRetry: _reloadMotos),
          ),
          // Co se stalo, proč a jak to opravit + akce.
          error: (e, _) => SliverToBoxAdapter(child: MotorkyErrorV2(error: e, onRetry: _reloadMotos)),
        ),
      ];
    }
    return MgPage(
      header: header,
      slivers: [
        SliverFadeTransition(
          opacity: CurvedAnimation(parent: _modeFade, curve: MgMotion.out),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
      overlapHero: false,
      tabIndex: 1,
      snap: _zone,
      dock: sticky == null ? null : CalcStickyV2(data: sticky),
      // CB-18: pull-to-refresh only where "Zkusit znovu" exists (the list).
      onRefresh: mode == CatalogMode.find ? _refresh : null,
      overscrollColor: MgColors.night,
    );
  }

  /// The old results header: "Dostupné motorky: n · d dní" with dates,
  /// "Zobrazeno motorek: n" without; "Hledám…" while loading.
  Widget _countLine(AppTranslations tr, AsyncValue<List<Motorcycle>> motosAsync, CatalogFilter f) {
    final s = f.startDate, e = f.endDate;
    final days = s != null && e != null ? catDayCount(s, e) : 0;
    final motos = motosAsync.valueOrNull;
    final String text;
    if (motos != null) {
      text = days > 0
          ? '${tr.tr('searchAvailableMotorcycles').replaceAll('{n}', '${motos.length}')} · ${catDays(tr, days)}'
          : tr.tr('searchShownMotorcycles').replaceAll('{n}', '${motos.length}');
    } else if (motosAsync.isLoading) {
      text = tr.tr('searchSearching');
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      key: const ValueKey('motorky-count'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(text, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
    );
  }

  Widget _list(AppTranslations tr, List<Motorcycle> motos, CatalogFilter f, LoyaltyStatus? loyalty) {
    final s = f.startDate, e = f.endDate;
    final hasDates = s != null && e != null && !catBeforeToday(s);
    if (motos.isEmpty) return SliverToBoxAdapter(child: _empty(tr));
    String? avail(Motorcycle m) =>
        hasDates ? tr.tr('v2CatFreeInRange') : (m.availableToday == true ? tr.tr('v2CatFreeToday') : null);
    final h = _cardHeight(context);
    final top = MediaQuery.paddingOf(context).top;
    // Same card tap as before; the card's button is the old "Detail".
    return SliverMainAxisGroup(slivers: [
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
      BikeScreenList(
        ids: [for (final m in motos) m.id],
        zone: _zone,
        height: h,
        onOpen: (i) => _open(motos, motos[i]),
        card: (context, i, open) {
          final card = MotoCardFullV2(
            key: ValueKey('mc-${motos[i].id}'),
            moto: motos[i],
            price: catCardPrice(tr, motos[i], s, e, loyalty),
            availability: avail(motos[i]),
            live: i == 0,
            ctaLabel: tr.tr('motoCardDetail'),
            height: h,
            topInset: top,
            onOpen: open,
          );
          // CB-28: the first three cards reveal once per session.
          return i < 3 ? MgReveal(index: i, sessionKey: 'motorky-cards', child: card) : card;
        },
      ),
    ]);
  }

  /// The old empty result: icon, "searchNoMotorcycles" + "zkus jiné
  /// filtry" (the dates and the filter panel are right above it).
  Widget _empty(AppTranslations tr) => Padding(
        key: const ValueKey('motorky-empty'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: MgCard(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MgColors.well,
                shape: BoxShape.circle,
                border: Border.all(color: MgColors.line),
              ),
              child: Center(child: MgIcon(MgIcons.moto, size: 32, color: MgColors.ink)),
            ),
            const SizedBox(height: 16),
            Text(tr.tr('searchNoMotorcycles'), textAlign: TextAlign.center, style: MgType.h3.copyWith(color: MgColors.ink)),
            const SizedBox(height: 8),
            Text(tr.tr('searchTryDifferentFilters'),
                textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
          ]),
        ),
      );
}
