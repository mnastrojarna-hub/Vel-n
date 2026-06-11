import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../catalog_provider.dart';

/// Filter panel: branches, category, power, license group, available-today
/// checkbox, and usage tags.
class SearchFiltersSection extends ConsumerStatefulWidget {
  const SearchFiltersSection({super.key});

  @override
  ConsumerState<SearchFiltersSection> createState() => _SearchFiltersSectionState();
}

class _SearchFiltersSectionState extends ConsumerState<SearchFiltersSection> {
  bool _showAvailableToday = false;

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(catalogFilterProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(context).tr('filtersTitle'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: MotoGoColors.black,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),

          // Pobočky dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MotoGoColors.g200, width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: filter.branch,
                isExpanded: true,
                dropdownColor: Colors.white,
                icon: const Icon(Icons.keyboard_arrow_down, color: MotoGoColors.g400),
                hint: Row(
                  children: [
                    Icon(Icons.store_outlined, size: 18, color: MotoGoColors.g400),
                    const SizedBox(width: 8),
                    Text(
                      t(context).tr('filtersAllBranches'),
                      style: const TextStyle(fontSize: 14, color: MotoGoColors.black),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 14, color: MotoGoColors.black),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Row(
                      children: [
                        Icon(Icons.store_outlined, size: 18, color: MotoGoColors.g400),
                        const SizedBox(width: 8),
                        Text(t(context).tr('filtersAllBranches')),
                      ],
                    ),
                  ),
                  ...ref.watch(branchesProvider).map((b) => DropdownMenuItem(
                    value: b['id'] as String,
                    child: Text(b['name'] as String),
                  )),
                ],
                onChanged: (v) {
                  ref.read(catalogFilterProvider.notifier).state =
                      filter.copyWith(branch: () => v);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Kategorie + Výkon labels
          Row(
            children: [
              Expanded(
                child: Text(
                  t(context).tr('filtersCategoryHint').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.g400,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(context).tr('filtersPowerHint').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.g400,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),

          // Kategorie + Výkon row
          Row(
            children: [
              // Kategorie dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MotoGoColors.g200, width: 1.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: filter.category,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: MotoGoColors.g400),
                      hint: Text(t(context).tr('filtersCategoryHint'), style: const TextStyle(fontSize: 13, color: MotoGoColors.black)),
                      style: const TextStyle(fontSize: 13, color: MotoGoColors.black),
                      items: MotoCategory.labels.entries.map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, style: const TextStyle(fontSize: 13)),
                      )).toList(),
                      onChanged: (v) {
                        ref.read(catalogFilterProvider.notifier).state =
                            filter.copyWith(category: () => v);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Výkon dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MotoGoColors.g200, width: 1.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: filter.maxPowerKw,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: MotoGoColors.g400),
                      hint: Text(t(context).tr('filtersPowerHint'), style: const TextStyle(fontSize: 13, color: MotoGoColors.black)),
                      style: const TextStyle(fontSize: 13, color: MotoGoColors.black),
                      items: [
                        DropdownMenuItem(value: null, child: Text(t(context).tr('homeFilterLicenseAll'), style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 35, child: Text(t(context).tr('filtersPower35'), style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 70, child: Text(t(context).tr('filtersPower70'), style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 100, child: Text(t(context).tr('filtersPower100'), style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 200, child: Text(t(context).tr('filtersPower200'), style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) {
                        ref.read(catalogFilterProvider.notifier).state =
                            filter.copyWith(maxPowerKw: () => v);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Skupina ŘP + Dnes volné labels
          Row(
            children: [
              Expanded(
                child: Text(
                  t(context).tr('filtersLicenseGroupHint').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.g400,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t(context).tr('filtersAvailableToday').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.g400,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),

          // Skupina ŘP + Dnes volné row
          Row(
            children: [
              // Skupina ŘP dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MotoGoColors.g200, width: 1.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: filter.licenseGroup,
                      isExpanded: true,
                      isDense: true,
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: MotoGoColors.g400),
                      hint: Text(t(context).tr('filtersLicenseGroupHint'), style: const TextStyle(fontSize: 13, color: MotoGoColors.black)),
                      style: const TextStyle(fontSize: 13, color: MotoGoColors.black),
                      items: [
                        DropdownMenuItem(value: null, child: Text(t(context).tr('homeFilterLicenseAll'), style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'A2', child: Text(t(context).tr('homeFilterLicenseA2'), style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'A', child: Text(t(context).tr('homeFilterLicenseA'), style: const TextStyle(fontSize: 13))),
                        const DropdownMenuItem(value: 'A1', child: Text('A1', style: TextStyle(fontSize: 13))),
                        const DropdownMenuItem(value: 'AM', child: Text('AM', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'N', child: Text(t(context).tr('homeFilterLicenseN'), style: const TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) {
                        ref.read(catalogFilterProvider.notifier).state =
                            filter.copyWith(licenseGroup: () => v);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Dnes volné checkbox
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _showAvailableToday = !_showAvailableToday),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MotoGoColors.g200, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: _showAvailableToday ? MotoGoColors.green : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _showAvailableToday ? MotoGoColors.green : MotoGoColors.g200,
                              width: 1.5,
                            ),
                          ),
                          child: _showAvailableToday
                              ? const Icon(Icons.check, size: 12, color: Colors.black)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t(context).tr('filtersAvailableToday'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Usage tags removed — ideal_usage data not populated in DB yet.
          // Will be re-added once backend provides consistent usage data.
        ],
      ),
    );
  }
}
