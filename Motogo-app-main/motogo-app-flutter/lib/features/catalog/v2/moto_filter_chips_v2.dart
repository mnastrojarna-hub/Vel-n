import 'package:flutter/widgets.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/widgets/mg_branch_chip.dart' show mgBranchShortName;
import '../catalog_provider.dart';

/// One removable chip of the folded filter card (5.0.1): what it says and
/// how a tap on its ✕ drops exactly that filter. [place] = the branch
/// ("kam vyrážím"): shown with a pin, NOT counted as a filter.
class MotoFilterChipItem {
  final String label;
  final VoidCallback onRemove;
  final bool place;
  const MotoFilterChipItem(this.label, this.onRemove, {this.place = false});
}

/// The active filters of [f] as chips, in the panel's order (category, ŘP,
/// ranges, today), then the branch. [set] writes the shared filter (the
/// panel's own setter). Count of non-place chips == [CatalogFilter.filterCount].
List<MotoFilterChipItem> motoFilterChips(
  AppTranslations tr,
  CatalogFilter f, {
  required ValueChanged<CatalogFilter> set,
  String? branchName,
}) {
  String range(String key, int? lo, int? hi, String unit) {
    final v = lo != null && hi != null
        ? tr.tr('homeFilterRange').replaceAll('{a}', '$lo').replaceAll('{b}', '$hi')
        : lo != null
            ? tr.tr('homeFilterRangeFrom').replaceAll('{n}', '$lo')
            : tr.tr('homeFilterRangeTo').replaceAll('{n}', '$hi');
    return '${tr.tr(key)} ${v.replaceAll('{u}', unit)}';
  }

  final lic = f.licenseGroup;
  return [
    if (f.category case final c?)
      MotoFilterChipItem(tr.tr(MotoCategory.labelKey(c)), () => set(f.copyWith(category: () => null))),
    if (lic != null)
      MotoFilterChipItem(
        lic == 'N' ? tr.tr('homeFilterLicenseN') : tr.trArgs('motoFltLic', {'g': lic}),
        () => set(f.copyWith(licenseGroup: () => null)),
      ),
    if (f.minPowerKw != null || f.maxPowerKw != null)
      MotoFilterChipItem(range('motoFltPower', f.minPowerKw, f.maxPowerKw, 'kW'),
          () => set(f.copyWith(minPowerKw: () => null, maxPowerKw: () => null))),
    if (f.minSeatMm != null || f.maxSeatMm != null)
      MotoFilterChipItem(range('motoFltSeat', f.minSeatMm, f.maxSeatMm, 'mm'),
          () => set(f.copyWith(minSeatMm: () => null, maxSeatMm: () => null))),
    if (f.minTorqueNm != null || f.maxTorqueNm != null)
      MotoFilterChipItem(range('motoFltTorque', f.minTorqueNm, f.maxTorqueNm, 'Nm'),
          () => set(f.copyWith(minTorqueNm: () => null, maxTorqueNm: () => null))),
    if (f.minWeightKg != null || f.maxWeightKg != null)
      MotoFilterChipItem(range('motoFltWeight', f.minWeightKg, f.maxWeightKg, 'kg'),
          () => set(f.copyWith(minWeightKg: () => null, maxWeightKg: () => null))),
    if (f.availableTodayOnly)
      MotoFilterChipItem(tr.tr('motoFltToday'), () => set(f.copyWith(availableTodayOnly: false))),
    if (f.branch != null && branchName != null)
      MotoFilterChipItem(mgBranchShortName(branchName, null) ?? branchName,
          () => set(f.copyWith(branch: () => null)),
          place: true),
  ];
}
