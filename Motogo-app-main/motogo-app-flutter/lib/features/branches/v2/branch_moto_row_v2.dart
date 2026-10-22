import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/widgets/net_image.dart';
import '../../catalog/moto_model.dart';

/// v2 look of one "Motorky na pobočce" row: photo thumb, model, specs
/// (cc · kW · ŘP), chevron. [onTap] = the section's existing open action.
class BranchMotoRowV2 extends StatelessWidget {
  final Motorcycle moto;
  final VoidCallback onTap;
  const BranchMotoRowV2({super.key, required this.moto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = moto;
    final img = m.displayImage;
    final lic = m.licenseGroupsOrFallback.where((g) => g != 'N').join(' / ');
    final spec = [
      if (m.engineCc != null) '${m.engineCc} cc',
      if (m.powerKw != null) '${m.powerKw} kW',
      if (lic.isNotEmpty) '${t(context).tr('licenseShort')} $lic',
    ].join(' · ');
    final ph = Container(
      width: 72,
      height: 52,
      color: MgColors.well,
      child: const Center(child: MgIcon(MgIcons.moto, size: 22, color: MgColors.meta)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        child: MgPress(
          scale: 0.985,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MgColors.well,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MgColors.line),
            ),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: img.isEmpty ? ph : MgImage(img, thumbWidth: 200, width: 72, height: 52, fit: BoxFit.cover, error: ph),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.model, style: MgType.title.copyWith(color: MgColors.ink)),
                  if (spec.isNotEmpty) Text(spec, style: MgType.tab(MgType.small.copyWith(color: MgColors.lead))),
                ]),
              ),
              const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.meta),
            ]),
          ),
        ),
      ),
    );
  }
}
