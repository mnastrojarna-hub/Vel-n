import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'catalog_provider.dart';
import 'widgets/moto_card.dart';

/// Catalog grid — mirrors s-home motorcycle grid from templates-screens.js.
/// Shows all active motorcycles with category/license/branch filters.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final motosAsync = ref.watch(filteredMotorcyclesProvider);
    final filter = ref.watch(catalogFilterProvider);

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
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Katalog motorek',
                    style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vyberte si svou motorku',
                    style: TextStyle(
                      fontSize: 12, color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Filter chips — category
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: MotoCategory.labels.entries.map((e) {
                    final active = filter.category == e.key;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: active,
                        onSelected: (_) {
                          ref.read(catalogFilterProvider.notifier).state =
                              filter.copyWith(category: () => active ? null : e.key);
                        },
                        selectedColor: MotoGoColors.green,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : MotoGoColors.black,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                          side: BorderSide(
                            color: active ? MotoGoColors.green : MotoGoColors.g200,
                          ),
                        ),
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // Filter row — license group + branch
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  // License group
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                        border: Border.all(color: MotoGoColors.g200),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: filter.licenseGroup,
                          isExpanded: true,
                          hint: const Text('ŘP skupina', style: TextStyle(fontSize: 12)),
                          style: const TextStyle(fontSize: 12, color: MotoGoColors.black),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Vše')),
                            DropdownMenuItem(value: 'A', child: Text('A')),
                            DropdownMenuItem(value: 'A2', child: Text('A2')),
                            DropdownMenuItem(value: 'A1', child: Text('A1')),
                            DropdownMenuItem(value: 'AM', child: Text('AM')),
                            DropdownMenuItem(value: 'B', child: Text('B')),
                            DropdownMenuItem(value: 'N', child: Text('N (bez ŘP)')),
                          ],
                          onChanged: (v) {
                            ref.read(catalogFilterProvider.notifier).state =
                                filter.copyWith(licenseGroup: () => v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Count
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: motosAsync.when(
                data: (motos) => Text(
                  '${motos.length} motorek',
                  style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: MotoGoColors.g400,
                  ),
                ),
                loading: () => const Text('Načítám...', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                error: (_, __) => const Text('Chyba načítání', style: TextStyle(fontSize: 12, color: MotoGoColors.red)),
              ),
            ),
          ),

          // Motorcycle grid
          motosAsync.when(
            data: (motos) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
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
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Text('Chyba: $e', style: const TextStyle(color: MotoGoColors.red)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
