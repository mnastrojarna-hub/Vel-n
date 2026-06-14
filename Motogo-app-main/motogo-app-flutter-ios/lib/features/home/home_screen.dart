import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../catalog/catalog_provider.dart';
import '../catalog/widgets/moto_card.dart';
import '../reservations/reservation_models.dart';
import '../reservations/reservation_provider.dart';
import 'widgets/home_filter_section.dart';
import 'widgets/home_header.dart';
import 'widgets/home_reservations_section.dart';

/// Home screen — 1:1 replica of Capacitor MotoGo24 home page.
/// Shows header, search bar, active reservations, filters, and motorcycle listing.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _maxPowerValue = 1.0; // 0.0 to 1.0 slider
  bool _showAvailableToday = false;
  String _sortOption = 'default';
  final ScrollController _scrollCtrl = ScrollController();
  bool _showScrollToTop = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 600;
      if (show != _showScrollToTop) setState(() => _showScrollToTop = show);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<dynamic> _sortMotorcycles(List<dynamic> motos) {
    final list = List.of(motos);
    switch (_sortOption) {
      case 'price_asc':
        list.sort((a, b) => (a.prices?.cheapest ?? 0).compareTo(b.prices?.cheapest ?? 0));
      case 'price_desc':
        list.sort((a, b) => (b.prices?.cheapest ?? 0).compareTo(a.prices?.cheapest ?? 0));
      case 'power_asc':
        list.sort((a, b) => (a.powerKw ?? 0).compareTo(b.powerKw ?? 0));
      case 'power_desc':
        list.sort((a, b) => (b.powerKw ?? 0).compareTo(a.powerKw ?? 0));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final motosAsync = ref.watch(filteredMotorcyclesProvider);
    final filter = ref.watch(catalogFilterProvider);
    final reservations = ref.watch(reservationsProvider);

    // Get active/upcoming reservations — only paid (mirrors apiGetActiveLoan)
    final activeReservations = reservations.valueOrNull?.where((r) {
          final status = r.displayStatus;
          return (status == ResStatus.aktivni || status == ResStatus.nadchazejici) &&
              r.paymentStatus == 'paid';
        }).toList() ??
        [];

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          RefreshIndicator(
            color: MotoGoColors.green,
            onRefresh: () async {
              ref.invalidate(motorcyclesProvider);
              ref.invalidate(filteredMotorcyclesProvider);
              ref.invalidate(reservationsProvider);
              await ref.read(motorcyclesProvider.future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              controller: _scrollCtrl,
            slivers: [
              // ===== HEADER =====
              const SliverToBoxAdapter(child: HomeHeader()),

              // ===== RESERVATIONS + SOS =====
              SliverToBoxAdapter(
                child: HomeReservationsSection(activeReservations: activeReservations),
              ),

              // ===== FILTER SECTION =====
              SliverToBoxAdapter(
                child: HomeFilterSection(
                  maxPowerValue: _maxPowerValue,
                  showAvailableToday: _showAvailableToday,
                  sortOption: _sortOption,
                  onMaxPowerChanged: (v) => setState(() => _maxPowerValue = v),
                  onAvailableTodayChanged: (v) => setState(() => _showAvailableToday = v),
                  onSortChanged: (v) => setState(() => _sortOption = v),
                  onReset: () {
                    ref.read(catalogFilterProvider.notifier).state = const CatalogFilter();
                    setState(() {
                      _maxPowerValue = 1.0;
                      _showAvailableToday = false;
                      _sortOption = 'default';
                    });
                  },
                ),
              ),

              // ===== MOTORCYCLE COUNT =====
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: motosAsync.when(
                    data: (motos) => Text(
                      t(context).tr('homeMotorcycleCount').replaceAll('{n}', '${motos.length}'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MotoGoColors.g400,
                      ),
                    ),
                    loading: () => Text(
                      t(context).tr('homeLoadingMotorcycles'),
                      style: const TextStyle(fontSize: 13, color: MotoGoColors.g400),
                    ),
                    error: (_, __) => Text(
                      t(context).tr('homeLoadingError'),
                      style: const TextStyle(fontSize: 13, color: MotoGoColors.red),
                    ),
                  ),
                ),
              ),

              // ===== MOTORCYCLE LISTING =====
              motosAsync.when(
                data: (motos) {
                  final sorted = _sortMotorcycles(motos);
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: MotoCard(
                            moto: sorted[index],
                            onTap: () {
                              ref.read(filteredMotoIdsProvider.notifier).state =
                                  sorted.map((m) => m.id as String).toList();
                              context.push('/moto/${sorted[index].id}');
                            },
                          ),
                        ),
                        childCount: sorted.length,
                      ),
                    ),
                  );
                },
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: MotoGoColors.green),
                  ),
                ),
                error: (e, _) => SliverFillRemaining(
                  child: Center(
                    child: Text(
                      '${t(context).tr('homeErrorPrefix')}$e',
                      style: const TextStyle(color: MotoGoColors.red),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ), // RefreshIndicator

          // Scroll to top FAB
          if (_showScrollToTop)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                onPressed: () => _scrollCtrl.animateTo(
                  0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                ),
                backgroundColor: MotoGoColors.green,
                child: const Icon(Icons.arrow_upward, color: Colors.black),
              ),
            ),
        ],
      ),
    );
  }
}
