import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../../home/widgets/license_chip.dart';
import '../catalog_provider.dart';
import 'availability_calendar.dart';

/// Filtr motorek — JEDEN panel sdílený obrazovkami Domů a Rezervovat.
///
/// Zadání uživatele: panel je ve výchozím stavu SBALENÝ (rozbalí se klepnutím
/// na hlavičku), každá změna se projeví OKAMŽITĚ (žádné potvrzovací tlačítko)
/// a kromě výkonu se filtruje i podle výšky sedla, točivého momentu
/// a hmotnosti. Na Domů je součástí i kalendář („Vyberte datum"); na
/// Rezervovat je kalendář nahoře nad filtrem, takže se tu vynechá
/// ([showDates] = false).
class MotoFilterPanel extends ConsumerStatefulWidget {
  /// Zobrazit uvnitř filtru i výběr termínu (jen Domů).
  final bool showDates;

  const MotoFilterPanel({super.key, this.showDates = false});

  @override
  ConsumerState<MotoFilterPanel> createState() => _MotoFilterPanelState();
}

class _MotoFilterPanelState extends ConsumerState<MotoFilterPanel> {
  bool _open = false;

  CatalogFilter get _f => ref.read(catalogFilterProvider);
  void _set(CatalogFilter next) =>
      ref.read(catalogFilterProvider.notifier).state = next;

  void _reset() {
    _set(const CatalogFilter());
    ref.read(catalogSortProvider.notifier).state = 'default';
  }

  // ── popisky rozsahů ──
  String _rangeLabel(BuildContext context, int? lo, int? hi, String unit) {
    final tr = t(context);
    if (lo == null && hi == null) return tr.tr('homeFilterAllPower');
    if (lo != null && hi != null) {
      return tr
          .tr('homeFilterRange')
          .replaceAll('{a}', '$lo')
          .replaceAll('{b}', '$hi')
          .replaceAll('{u}', unit);
    }
    if (lo != null) {
      return tr.tr('homeFilterRangeFrom').replaceAll('{n}', '$lo').replaceAll('{u}', unit);
    }
    return tr.tr('homeFilterRangeTo').replaceAll('{n}', '$hi').replaceAll('{u}', unit);
  }

  String _dateLabel(BuildContext context, CatalogFilter f) {
    final s = f.startDate, e = f.endDate;
    if (s == null || e == null) return t(context).tr('homeFilterDatesAny');
    String d(DateTime x) => '${x.day}. ${x.month}.';
    return s == e ? d(s) : '${d(s)} – ${d(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(catalogFilterProvider);
    final active = filter.activeCount;

    return Container(
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
          // ── Hlavička = tlačítko rozbalení ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                const Icon(Icons.tune, size: 18, color: MotoGoColors.greenDark),
                const SizedBox(width: 8),
                Text(
                  t(context).tr('homeFilterTitle'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.black,
                  ),
                ),
                if (active > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: MotoGoColors.greenPale,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      '$active',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: MotoGoColors.greenDark,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (active > 0)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _reset,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        t(context).tr('homeFilterReset'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: MotoGoColors.red,
                        ),
                      ),
                    ),
                  ),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 22, color: MotoGoColors.g400),
              ],
            ),
          ),
          // ── Obsah ──
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open
                ? _body(context, filter)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, CatalogFilter filter) {
    final ranges = ref.watch(motoRangesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // ── TERMÍN (jen Domů) ──
        if (widget.showDates) ...[
          _label(context, 'homeFilterDates', value: _dateLabel(context, filter)),
          const SizedBox(height: 8),
          AvailabilityCalendar(
            selectedStart: filter.startDate,
            selectedEnd: filter.endDate,
            onRangeSelected: (start, end) => _set(
              _f.copyWith(startDate: () => start, endDate: () => end),
            ),
            onReset: () =>
                _set(_f.copyWith(startDate: () => null, endDate: () => null)),
          ),
          const SizedBox(height: 16),
        ],

        // ── KATEGORIE ──
        _label(context, 'homeFilterCategory'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: MotoCategory.labels.entries.map((e) {
            final on = filter.category == e.key;
            return GestureDetector(
              onTap: () => _set(_f.copyWith(category: () => on ? null : e.key)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? MotoGoColors.green : Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: on ? MotoGoColors.green : MotoGoColors.g200,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.black : MotoGoColors.black,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // ── SKUPINA ŘP ──
        _label(context, 'homeFilterLicenseGroup'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final g in const [
              (null, 'homeFilterLicenseAll'),
              ('A1', 'homeFilterLicenseA1'),
              ('A2', 'homeFilterLicenseA2'),
              ('A', 'homeFilterLicenseA'),
              ('B', 'homeFilterLicenseB'),
              ('N', 'homeFilterLicenseN'),
            ])
              LicenseChip(
                label: t(context).tr(g.$2),
                active: filter.licenseGroup == g.$1,
                onTap: () => _set(_f.copyWith(
                    licenseGroup: () =>
                        filter.licenseGroup == g.$1 ? null : g.$1)),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── POBOČKA ──
        _label(context, 'homeFilterBranch'),
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
              dropdownColor: Colors.white,
              icon: const Icon(Icons.keyboard_arrow_down, color: MotoGoColors.g400),
              hint: Row(
                children: [
                  const Icon(Icons.store_outlined, size: 18, color: MotoGoColors.g400),
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
                      const Icon(Icons.store_outlined, size: 18, color: MotoGoColors.g400),
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
              onChanged: (v) => _set(_f.copyWith(branch: () => v)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── VÝKON / VÝŠKA SEDLA / TOČIVÝ MOMENT / HMOTNOST ──
        _rangeSlider(
          context,
          labelKey: 'homeFilterPower',
          unit: 'kW',
          bounds: ranges.power,
          lo: filter.minPowerKw,
          hi: filter.maxPowerKw,
          onChanged: (lo, hi) =>
              _set(_f.copyWith(minPowerKw: () => lo, maxPowerKw: () => hi)),
        ),
        _rangeSlider(
          context,
          labelKey: 'homeFilterSeatHeight',
          unit: 'mm',
          bounds: ranges.seat,
          lo: filter.minSeatMm,
          hi: filter.maxSeatMm,
          onChanged: (lo, hi) =>
              _set(_f.copyWith(minSeatMm: () => lo, maxSeatMm: () => hi)),
        ),
        _rangeSlider(
          context,
          labelKey: 'homeFilterTorque',
          unit: 'Nm',
          bounds: ranges.torque,
          lo: filter.minTorqueNm,
          hi: filter.maxTorqueNm,
          onChanged: (lo, hi) =>
              _set(_f.copyWith(minTorqueNm: () => lo, maxTorqueNm: () => hi)),
        ),
        _rangeSlider(
          context,
          labelKey: 'homeFilterWeight',
          unit: 'kg',
          bounds: ranges.weight,
          lo: filter.minWeightKg,
          hi: filter.maxWeightKg,
          onChanged: (lo, hi) =>
              _set(_f.copyWith(minWeightKg: () => lo, maxWeightKg: () => hi)),
        ),

        // ── Dnes volné + řazení ──
        Row(
          children: [
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _set(
                    _f.copyWith(availableTodayOnly: !filter.availableTodayOnly)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: filter.availableTodayOnly
                            ? MotoGoColors.green
                            : Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: filter.availableTodayOnly
                              ? MotoGoColors.green
                              : MotoGoColors.g200,
                          width: 1.5,
                        ),
                      ),
                      child: filter.availableTodayOnly
                          ? const Icon(Icons.check, size: 14, color: Colors.black)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        t(context).tr('homeFilterShowAvailableToday'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MotoGoColors.black,
                        ),
                      ),
                    ),
                  ],
                ),
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
                  value: ref.watch(catalogSortProvider),
                  isDense: true,
                  dropdownColor: Colors.white,
                  style: const TextStyle(fontSize: 12, color: MotoGoColors.black),
                  items: [
                    for (final o in const [
                      ('default', 'homeFilterSortDefault'),
                      ('price_asc', 'homeFilterSortPriceAsc'),
                      ('price_desc', 'homeFilterSortPriceDesc'),
                      ('power_asc', 'homeFilterSortPowerAsc'),
                      ('power_desc', 'homeFilterSortPowerDesc'),
                    ])
                      DropdownMenuItem(
                          value: o.$1, child: Text(t(context).tr(o.$2))),
                  ],
                  onChanged: (v) => ref.read(catalogSortProvider.notifier).state =
                      v ?? 'default',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String key, {String? value}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            t(context).tr(key),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: MotoGoColors.g400,
              letterSpacing: 0.5,
            ),
          ),
          if (value != null)
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.black,
              ),
            ),
        ],
      );

  /// Posuvník od–do. Krajní polohy = BEZ omezení (null), takže motorky
  /// s nevyplněným údajem zůstávají ve výpisu.
  Widget _rangeSlider(
    BuildContext context, {
    required String labelKey,
    required String unit,
    required MotoRange bounds,
    required int? lo,
    required int? hi,
    required void Function(int? lo, int? hi) onChanged,
  }) {
    if (!bounds.valid) return const SizedBox.shrink();
    final min = bounds.min.toDouble();
    final max = bounds.max.toDouble();
    final start = (lo ?? bounds.min).toDouble().clamp(min, max);
    final end = (hi ?? bounds.max).toDouble().clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, labelKey, value: _rangeLabel(context, lo, hi, unit)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: MotoGoColors.green,
            inactiveTrackColor: MotoGoColors.g200,
            thumbColor: MotoGoColors.green,
            overlayColor: MotoGoColors.green.withValues(alpha: 0.2),
            trackHeight: 4,
            rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: RangeSlider(
            values: RangeValues(start, end),
            min: min,
            max: max,
            onChanged: (v) => onChanged(
              v.start <= min ? null : v.start.round(),
              v.end >= max ? null : v.end.round(),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
