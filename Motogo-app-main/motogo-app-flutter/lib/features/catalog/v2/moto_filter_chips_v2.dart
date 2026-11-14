import 'package:flutter/widgets.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_branch_chip.dart' show mgBranchShortName;
import '../../../core/v2/widgets/mg_word_fit.dart';
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
/// panel's own setter); [live] reads it at tap time, so two ✕ taps before a
/// rebuild both stick (without it the chips edit [f]). Count of non-place
/// chips == [CatalogFilter.filterCount].
List<MotoFilterChipItem> motoFilterChips(
  AppTranslations tr,
  CatalogFilter f, {
  required ValueChanged<CatalogFilter> set,
  CatalogFilter Function()? live,
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

  VoidCallback drop(CatalogFilter Function(CatalogFilter) edit) => () => set(edit(live?.call() ?? f));

  final lic = f.licenseGroup;
  return [
    if (f.category case final c?)
      MotoFilterChipItem(tr.tr(MotoCategory.labelKey(c)), drop((x) => x.copyWith(category: () => null))),
    if (lic != null)
      MotoFilterChipItem(
        lic == 'N' ? tr.tr('homeFilterLicenseN') : tr.trArgs('motoFltLic', {'g': lic}),
        drop((x) => x.copyWith(licenseGroup: () => null)),
      ),
    if (f.minPowerKw != null || f.maxPowerKw != null)
      MotoFilterChipItem(range('motoFltPower', f.minPowerKw, f.maxPowerKw, 'kW'),
          drop((x) => x.copyWith(minPowerKw: () => null, maxPowerKw: () => null))),
    if (f.minSeatMm != null || f.maxSeatMm != null)
      MotoFilterChipItem(range('motoFltSeat', f.minSeatMm, f.maxSeatMm, 'mm'),
          drop((x) => x.copyWith(minSeatMm: () => null, maxSeatMm: () => null))),
    if (f.minTorqueNm != null || f.maxTorqueNm != null)
      MotoFilterChipItem(range('motoFltTorque', f.minTorqueNm, f.maxTorqueNm, 'Nm'),
          drop((x) => x.copyWith(minTorqueNm: () => null, maxTorqueNm: () => null))),
    if (f.minWeightKg != null || f.maxWeightKg != null)
      MotoFilterChipItem(range('motoFltWeight', f.minWeightKg, f.maxWeightKg, 'kg'),
          drop((x) => x.copyWith(minWeightKg: () => null, maxWeightKg: () => null))),
    if (f.availableTodayOnly)
      MotoFilterChipItem(tr.tr('motoFltToday'), drop((x) => x.copyWith(availableTodayOnly: false))),
    if (f.branch != null && branchName != null)
      MotoFilterChipItem(mgBranchShortName(branchName, null) ?? branchName, drop((x) => x.copyWith(branch: () => null)),
          place: true),
  ];
}

/// A filter chip: ink pill + white text (the branch: a light pin chip).
/// A tap on the label opens the panel ([onOpen]); only the ✕ disc (a 40 px
/// target) drops the filter.
class MotoFilterChipV2 extends StatelessWidget {
  final MotoFilterChipItem item;
  final String removeLabel;
  final VoidCallback onOpen;
  const MotoFilterChipV2({super.key, required this.item, required this.removeLabel, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final place = item.place;
    return Container(
      height: 40,
      padding: const EdgeInsetsDirectional.only(start: 2),
      decoration: BoxDecoration(
        color: place ? MgColors.surface : MgColors.ink,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: place ? MgColors.tintOkBorder : MgColors.ink, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: MgPress(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 2, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (place) ...[MgIcon(MgIcons.pin, size: 15, color: MgColors.link), const SizedBox(width: 4)],
                Flexible(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.small
                          .copyWith(fontWeight: FontWeight.w800, color: place ? MgColors.onTintOk : MgColors.onDark)),
                ),
              ]),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: removeLabel,
          excludeSemantics: true,
          onTap: item.onRemove,
          child: MgPress(
            key: ValueKey('moto-filter-x-${item.label}'),
            onTap: item.onRemove,
            child: SizedBox(
              width: 36,
              height: 40,
              child: Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: place ? MgColors.well : MgColors.neon),
                  child: Center(
                      child:
                          MgIcon(MgIcons.close, size: 13, stroke: 2.6, color: place ? MgColors.ink : MgColors.onNeon)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// "Zrušit vše": a clear text action with ✕ in the brand green.
class MotoFilterClearAllV2 extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final String keyName;

  /// Only the ✕ in a 40 px circle ([label] stays the semantics): a narrow
  /// strip keeps its title big (FV-07).
  final bool iconOnly;
  const MotoFilterClearAllV2(
      {super.key, required this.label, required this.onTap, this.keyName = 'moto-filter-clear', this.iconOnly = false});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          key: ValueKey(keyName),
          onTap: onTap,
          child: iconOnly
              ? Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MgColors.link, width: 1.5)),
                  child: Center(child: MgIcon(MgIcons.close, size: 18, color: MgColors.link)),
                )
              : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                MgIcon(MgIcons.close, size: 16, color: MgColors.link),
                const SizedBox(width: 4),
                // Long labels (pl "Wyczyść wszystko") shrink, then wrap.
                Flexible(
                  child: MgWordFit(
                    minScale: 0.75,
                    fitLines: 1,
                    child: Text(label,
                        maxLines: 2,
                        style: MgType.small.copyWith(
                            fontWeight: FontWeight.w800,
                            color: MgColors.link,
                            decoration: TextDecoration.underline,
                            decorationColor: MgColors.link)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}
