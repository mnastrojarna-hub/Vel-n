import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../catalog/catalog_provider.dart';
import 'license_chip.dart';

/// Filter card shown on the home screen (category, license group, branch, power, sort).
///
/// The parent [HomeScreen] owns [maxPowerValue], [showAvailableToday] and
/// [sortOption] state and passes them in via callbacks so this widget stays
/// stateless.
class HomeFilterSection extends ConsumerWidget {
  final double maxPowerValue;
  final bool showAvailableToday;
  final String sortOption;
  final ValueChanged<double> onMaxPowerChanged;
  final ValueChanged<bool> onAvailableTodayChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onReset;

  const HomeFilterSection({
    super.key,
    required this.maxPowerValue,
    required this.showAvailableToday,
    required this.sortOption,
    required this.onMaxPowerChanged,
    required this.onAvailableTodayChanged,
    required this.onSortChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(catalogFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: MotoGoColors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Filter header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t(context).tr('homeFilterTitle'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.black,
                  ),
                ),
                GestureDetector(
                  onTap: onReset,
                  child: Text(
                    t(context).tr('homeFilterReset'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MotoGoColors.g400,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // KATEGORIE
            Text(
              t(context).tr('homeFilterCategory'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.g400,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: MotoCategory.labels.entries.map((e) {
                final active = filter.category == e.key;
                return GestureDetector(
                  onTap: () {
                    ref.read(catalogFilterProvider.notifier).state =
                        filter.copyWith(category: () => active ? null : e.key);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? MotoGoColors.green : Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: active ? MotoGoColors.green : MotoGoColors.g200,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : MotoGoColors.black,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // SKUPINA ŘP
            Text(
              t(context).tr('homeFilterLicenseGroup'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.g400,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                LicenseChip(
                  label: t(context).tr('homeFilterLicenseAll'),
                  active: filter.licenseGroup == null,
                  onTap: () => ref.read(catalogFilterProvider.notifier).state =
                      filter.copyWith(licenseGroup: () => null),
                ),
                LicenseChip(
                  label: t(context).tr('homeFilterLicenseA2'),
                  active: filter.licenseGroup == 'A2',
                  onTap: () => ref.read(catalogFilterProvider.notifier).state =
                      filter.copyWith(
                        licenseGroup: () => filter.licenseGroup == 'A2' ? null : 'A2',
                      ),
                ),
                LicenseChip(
                  label: t(context).tr('homeFilterLicenseA'),
                  active: filter.licenseGroup == 'A',
                  onTap: () => ref.read(catalogFilterProvider.notifier).state =
                      filter.copyWith(
                        licenseGroup: () => filter.licenseGroup == 'A' ? null : 'A',
                      ),
                ),
                LicenseChip(
                  label: t(context).tr('homeFilterLicenseN'),
                  active: filter.licenseGroup == 'N',
                  onTap: () => ref.read(catalogFilterProvider.notifier).state =
                      filter.copyWith(
                        licenseGroup: () => filter.licenseGroup == 'N' ? null : 'N',
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // POBOČKA
            Text(
              t(context).tr('homeFilterBranch'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.g400,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
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
                  icon: const Icon(Icons.keyboard_arrow_down, color: MotoGoColors.g400),
                  hint: Row(
                    children: [
                      Icon(Icons.store_outlined, size: 18, color: MotoGoColors.g400),
                      const SizedBox(width: 8),
                      Text(
                        t(context).tr('homeFilterAllBranches'),
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
                          Text(t(context).tr('homeFilterAllBranches')),
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
            const SizedBox(height: 16),

            // MAX. VÝKON slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t(context).tr('homeFilterMaxPower'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.g400,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  maxPowerValue >= 1.0 ? t(context).tr('homeFilterAllPower') : '${(maxPowerValue * 200).round()} kW',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.black,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: MotoGoColors.green,
                inactiveTrackColor: MotoGoColors.g200,
                thumbColor: MotoGoColors.green,
                overlayColor: MotoGoColors.green.withValues(alpha: 0.2),
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: maxPowerValue,
                onChanged: (v) {
                  onMaxPowerChanged(v);
                  if (v >= 1.0) {
                    ref.read(catalogFilterProvider.notifier).state =
                        filter.copyWith(maxPowerKw: () => null);
                  } else {
                    ref.read(catalogFilterProvider.notifier).state =
                        filter.copyWith(maxPowerKw: () => (v * 200).round());
                  }
                },
              ),
            ),

            // Bottom filter row: available today + sort
            Row(
              children: [
                GestureDetector(
                  onTap: () => onAvailableTodayChanged(!showAvailableToday),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: showAvailableToday ? MotoGoColors.green : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: showAvailableToday ? MotoGoColors.green : MotoGoColors.g200,
                            width: 1.5,
                          ),
                        ),
                        child: showAvailableToday
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        t(context).tr('homeFilterShowAvailableToday'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MotoGoColors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MotoGoColors.g200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: sortOption,
                      isDense: true,
                      style: const TextStyle(fontSize: 12, color: MotoGoColors.black),
                      items: [
                        DropdownMenuItem(value: 'default', child: Text(t(context).tr('homeFilterSortDefault'))),
                        DropdownMenuItem(value: 'price_asc', child: Text(t(context).tr('homeFilterSortPriceAsc'))),
                        DropdownMenuItem(value: 'price_desc', child: Text(t(context).tr('homeFilterSortPriceDesc'))),
                        DropdownMenuItem(value: 'power_asc', child: Text(t(context).tr('homeFilterSortPowerAsc'))),
                        DropdownMenuItem(value: 'power_desc', child: Text(t(context).tr('homeFilterSortPowerDesc'))),
                      ],
                      onChanged: (v) => onSortChanged(v ?? 'default'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
