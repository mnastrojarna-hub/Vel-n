import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/widgets/net_image.dart';
import '../../catalog/moto_model.dart';

/// Recap ticket of the chosen bike (board `.tk`, replaces the old
/// `BookingFormMotoCard`): photo, model, "od X/den · záloha neúčtována",
/// branch. Overlaps the dark header by 24 px (MgPage).
class BookingRecapV2 extends StatelessWidget {
  final Motorcycle moto;
  const BookingRecapV2({super.key, required this.moto});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final branch = moto.branchName == null
        ? null
        : '${tr.tr('branchPrefix')}: ${moto.branchName}${moto.branchCity != null ? ", ${moto.branchCity}" : ""}';
    Widget fallback() => Container(
          color: MgColors.well,
          alignment: Alignment.center,
          child: MgIcon(MgIcons.moto, size: 24, color: MgColors.meta),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.receipt),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(MgRadius.thumb),
          child: SizedBox(
            width: 84,
            height: 63,
            child: MgImage(
              moto.displayImage,
              thumbWidth: 240,
              width: 84,
              height: 63,
              fit: BoxFit.cover,
              placeholder: fallback(),
              error: fallback(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(moto.model, style: MgType.title.copyWith(color: MgColors.ink)),
            const SizedBox(height: 2),
            Text(tr.tr('motoFromPrice').replaceAll('{price}', moto.priceLabel),
                style: MgType.tab(MgType.small.copyWith(color: MgColors.lead))),
            if (branch != null) ...[
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: MgIcon(MgIcons.pin, size: 14, color: MgColors.link),
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(branch, style: MgType.meta.copyWith(color: MgColors.meta))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
