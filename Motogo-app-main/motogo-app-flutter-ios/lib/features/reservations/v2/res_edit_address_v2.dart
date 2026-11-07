import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../booking/widgets/address_picker.dart' show AddressRowData;

/// v2 look of the address row of `AddressPickerWidget` (Upravit rezervaci
/// → Místo): an address the booking already has, or one the customer gave,
/// is an answered section — the address over the full width and "Změnit"
/// that reopens the same address sheet (2026-10-22, nothing is typed
/// twice). Without an address: "Zadej adresu ›". Same look as the booking
/// form's address row.
class ResEditAddressRowV2 extends StatelessWidget {
  final AddressRowData data;
  const ResEditAddressRowV2({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final address = data.address ?? '';
    final has = address.isNotEmpty;
    final fee = data.fee;
    final change = Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      MgIcon(MgIcons.edit, size: 16, color: MgColors.link),
      const SizedBox(width: 4),
      Flexible(
        child: Text(tr.tr('v2BkChange'),
            style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
      ),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        label: has ? tr.trArgs('v2BkAddressA11y', {'address': address}) : tr.tr('v2BkEnterAddress'),
        excludeSemantics: true,
        onTap: data.onTap,
        child: MgPress(
          onTap: data.onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(MgRadius.button),
              border: Border.all(color: has ? MgColors.lineInput : MgColors.link, width: 1.5),
            ),
            child: Row(children: [
              MgIcon(MgIcons.pin, size: 20, color: MgColors.link),
              const SizedBox(width: 10),
              Expanded(
                child: has
                    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(address, style: MgType.body.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink)),
                        const SizedBox(height: 4),
                        change,
                      ])
                    : Text(tr.tr('v2BkEnterAddress'),
                        style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
              ),
              if (!has) ...[
                const SizedBox(width: 8),
                MgIcon(MgIcons.chevronRight, size: 18, color: MgColors.link),
              ],
            ]),
          ),
        ),
      ),
      if (fee != null && fee > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MgColors.well,
              borderRadius: BorderRadius.circular(MgRadius.action),
              border: Border.all(color: MgColors.line),
            ),
            child: Row(children: [
              MgIcon(MgIcons.route, size: 16, color: MgColors.link),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.distKm != null ? '~${data.distKm!.toStringAsFixed(0)} km · ${Money.czk(fee)}' : Money.czk(fee),
                  style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}
