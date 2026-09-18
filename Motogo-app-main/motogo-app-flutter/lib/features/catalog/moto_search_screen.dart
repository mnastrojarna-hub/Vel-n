import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/router.dart';
import 'catalog_provider.dart';
import 'widgets/availability_calendar.dart';
import 'widgets/date_tabs_section.dart';
import 'widgets/menu_line.dart';
import 'widgets/moto_card.dart';
import 'widgets/moto_filter_panel.dart';
import '../../core/date_days.dart';

/// Search screen — 1:1 replica of Capacitor "Vyhledávání" screen.
/// Shows date tabs (VYZVEDNUTÍ/VRÁCENÍ), calendar, filters, and results.
class MotoSearchScreen extends ConsumerStatefulWidget {
  const MotoSearchScreen({super.key});

  @override
  ConsumerState<MotoSearchScreen> createState() => _MotoSearchScreenState();
}

class _MotoSearchScreenState extends ConsumerState<MotoSearchScreen> {
  bool _pickingStart = true; // true = picking start date, false = picking end

  // Termín má JEDEN zdroj pravdy — `catalogFilterProvider`. Dřív si ho
  // obrazovka držela i ve vlastních polích a po resetu filtru (z panelu)
  // nahoře dál svítil termín, podle kterého se už nefiltrovalo.
  DateTime? get _startDate => ref.watch(catalogFilterProvider).startDate;
  DateTime? get _endDate => ref.watch(catalogFilterProvider).endDate;

  void _onRangeSelected(DateTime start, DateTime end) {
    setState(() => _pickingStart = true);
    final filter = ref.read(catalogFilterProvider);
    ref.read(catalogFilterProvider.notifier).state = filter.copyWith(
      startDate: () => start,
      endDate: () => end,
    );
  }

  int get _dayCount {
    final s = _startDate, e = _endDate;
    if (s == null || e == null) return 0;
    return calendarDaysInclusive(s, e);
  }

  @override
  Widget build(BuildContext context) {
    final motosAsync = ref.watch(filteredMotorcyclesProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: _buildContent(context, motosAsync),
    );
  }

  Widget _buildContent(BuildContext context, AsyncValue motosAsync) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      cacheExtent: 800,
      slivers: [
        // ===== DARK HEADER =====
        SliverToBoxAdapter(
          child: Container(
            padding: EdgeInsets.fromLTRB(
              16, MediaQuery.of(context).padding.top + 12, 16, 16,
            ),
            decoration: const BoxDecoration(
              color: MotoGoColors.dark,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + hamburger menu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t(context).tr('searchTitle'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.go(Routes.profile),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: MotoGoColors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            MenuLine(width: 16),
                            SizedBox(height: 4),
                            MenuLine(width: 12),
                            SizedBox(height: 4),
                            MenuLine(width: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // VYZVEDNUTÍ / VRÁCENÍ tabs
                DateTabsSection(
                  pickingStart: _pickingStart,
                  startDate: _startDate,
                  endDate: _endDate,
                  onPickStart: () => setState(() => _pickingStart = true),
                  onPickEnd: () => setState(() => _pickingStart = false),
                ),
              ],
            ),
          ),
        ),

        // ===== CALENDAR SECTION =====
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step indicator
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: MotoGoColors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('1', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _pickingStart
                            ? t(context).tr('searchSelectPickupDate')
                            : t(context).tr('searchSelectReturnDate'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: MotoGoColors.greenDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t(context).tr('searchSingleDayHint'),
                    style: const TextStyle(fontSize: 11, color: MotoGoColors.g400),
                  ),
                  const SizedBox(height: 8),
                  AvailabilityCalendar(
                    onRangeSelected: _onRangeSelected,
                    onReset: () {
                      setState(() => _pickingStart = true);
                      final filter = ref.read(catalogFilterProvider);
                      ref.read(catalogFilterProvider.notifier).state =
                          filter.copyWith(
                        startDate: () => null,
                        endDate: () => null,
                      );
                    },
                    selectedStart: _startDate,
                    selectedEnd: _endDate,
                  ),
                ],
              ),
            ),
          ),
        ),

        // ===== FILTRY SECTION =====
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            // Stejný filtr jako na Domů, jen BEZ kalendáře — ten je na téhle
            // stránce nahoře nad filtrem.
            child: const MotoFilterPanel(),
          ),
        ),

        // ===== RESULTS HEADER =====
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: motosAsync.when(
                    // Při změně filtru se výpis jen přepočítá — nesmí zmizet
                    // pod celoobrazovkový spinner.
                    skipLoadingOnReload: true,
              data: (motos) => Text(
                _dayCount > 0
                  ? '${t(context).tr('searchAvailableMotorcycles').replaceAll('{n}', '${motos.length}')} · $_dayCount ${_dayCount == 1 ? t(context).tr('day1') : _dayCount < 5 ? t(context).tr('days24') : t(context).tr('days5')}'
                  : t(context).tr('searchShownMotorcycles').replaceAll('{n}', '${motos.length}'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black),
              ),
              loading: () => Text(t(context).tr('searchSearching'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ),

        // ===== RESULTS GRID =====
        motosAsync.when(
          skipLoadingOnReload: true,
          // Řazení řídí sdílený panel filtrů (stejně jako na Domů).
          data: (all) {
            final motos = sortMotorcycles(all, ref.watch(catalogSortProvider));
            return motos.isEmpty
              ? SliverFillRemaining(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🏍️', style: TextStyle(fontSize: 36)),
                          const SizedBox(height: 12),
                          Text(
                            t(context).tr('searchNoMotorcycles'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: MotoGoColors.g400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t(context).tr('searchTryDifferentFilters'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: MotoGoColors.g400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: MotoCard(
                          moto: motos[index],
                          onTap: () {
                            // Pořadí pro listování mezi motorkami v detailu —
                            // musí odpovídat právě zobrazenému (seřazenému)
                            // výpisu, jinak swipe jede podle jiného seznamu.
                            ref.read(filteredMotoIdsProvider.notifier).state =
                                motos.map((m) => m.id).toList();
                            context.push('/moto/${motos[index].id}');
                          },
                        ),
                      ),
                      childCount: motos.length,
                    ),
                  ),
                );
          },
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
          ),
          error: (e, __) => SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 12),
                    Text(
                      t(context).tr('loadingError'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: MotoGoColors.red,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(filteredMotorcyclesProvider),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(t(context).tr('retry')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
