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
import 'widgets/search_filters_section.dart';

/// Search screen — 1:1 replica of Capacitor "Vyhledávání" screen.
/// Shows date tabs (VYZVEDNUTÍ/VRÁCENÍ), calendar, filters, and results.
class MotoSearchScreen extends ConsumerStatefulWidget {
  const MotoSearchScreen({super.key});

  @override
  ConsumerState<MotoSearchScreen> createState() => _MotoSearchScreenState();
}

class _MotoSearchScreenState extends ConsumerState<MotoSearchScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _pickingStart = true; // true = picking start date, false = picking end

  @override
  void initState() {
    super.initState();
    // Sync local date state from catalog filter (e.g. when coming from booking form)
    final filter = ref.read(catalogFilterProvider);
    _startDate = filter.startDate;
    _endDate = filter.endDate;
  }

  void _onRangeSelected(DateTime start, DateTime end) {
    setState(() {
      _startDate = start;
      _endDate = end;
      _pickingStart = true;
    });
    final filter = ref.read(catalogFilterProvider);
    ref.read(catalogFilterProvider.notifier).state = filter.copyWith(
      startDate: () => start,
      endDate: () => end,
    );
  }

  int get _dayCount {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
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
                      setState(() {
                        _startDate = null;
                        _endDate = null;
                        _pickingStart = true;
                      });
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
            child: const SearchFiltersSection(),
          ),
        ),

        // ===== RESULTS HEADER =====
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: motosAsync.when(
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
          data: (motos) => motos.isEmpty
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
                          onTap: () => context.push('/moto/${motos[index].id}'),
                        ),
                      ),
                      childCount: motos.length,
                    ),
                  ),
                ),
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
