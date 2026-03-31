import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'catalog_provider.dart';
import 'widgets/availability_calendar.dart';
import 'widgets/moto_card.dart';

/// Search screen with calendar date picker + filters.
/// Mirrors s-search from templates-screens.js + booking-search-cal.js.
class MotoSearchScreen extends ConsumerStatefulWidget {
  const MotoSearchScreen({super.key});

  @override
  ConsumerState<MotoSearchScreen> createState() => _MotoSearchScreenState();
}

class _MotoSearchScreenState extends ConsumerState<MotoSearchScreen> {
  DateTime? _startDate;
  DateTime? _endDate;

  void _onRangeSelected(DateTime start, DateTime end) {
    setState(() {
      _startDate = start;
      _endDate = end;
    });
    // Update filter with dates
    final filter = ref.read(catalogFilterProvider);
    ref.read(catalogFilterProvider.notifier).state = filter.copyWith(
      startDate: () => start,
      endDate: () => end,
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Vyberte';
    return '${d.day}. ${d.month}. ${d.year}';
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
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 16, 20, 16,
              ),
              decoration: const BoxDecoration(
                color: MotoGoColors.dark,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kdy jedete?',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vyberte termín a najdeme volné motorky',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),

          // Date selection boxes
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  _DateBox(
                    label: 'Vyzvednutí',
                    value: _formatDate(_startDate),
                    active: _startDate != null,
                  ),
                  const SizedBox(width: 8),
                  const Text('→', style: TextStyle(fontSize: 16, color: MotoGoColors.g400)),
                  const SizedBox(width: 8),
                  _DateBox(
                    label: 'Vrácení',
                    value: _formatDate(_endDate),
                    active: _endDate != null,
                  ),
                ],
              ),
            ),
          ),

          // Calendar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                  boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
                ),
                child: AvailabilityCalendar(
                  onRangeSelected: _onRangeSelected,
                  selectedStart: _startDate,
                  selectedEnd: _endDate,
                ),
              ),
            ),
          ),

          // Day count + results header
          if (_dayCount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: motosAsync.when(
                  data: (motos) => Text(
                    '${motos.length} volných motorek · $_dayCount ${_dayCount == 1 ? 'den' : _dayCount < 5 ? 'dny' : 'dní'}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black),
                  ),
                  loading: () => const Text('Hledám...', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
            ),

          // Results grid
          motosAsync.when(
            data: (motos) => motos.isEmpty
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          'Žádné motorky pro vybraný termín',
                          style: TextStyle(fontSize: 13, color: MotoGoColors.g400),
                        ),
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => MotoCard(
                          moto: motos[index],
                          onTap: () => context.push('/moto/${motos[index].id}'),
                        ),
                        childCount: motos.length,
                      ),
                    ),
                  ),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final String value;
  final bool active;
  const _DateBox({required this.label, required this.value, required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: Border.all(
            color: active ? MotoGoColors.green : MotoGoColors.g200,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.g400),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: active ? MotoGoColors.black : MotoGoColors.g400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
