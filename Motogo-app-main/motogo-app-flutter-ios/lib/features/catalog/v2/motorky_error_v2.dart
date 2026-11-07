import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_support_row.dart';
import '../../../core/v2/states/mg_tech_details.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';

/// Motorky list could not load (Stavy 8.6, CB-21): white card under the
/// header — err disc, "Motorky se nepodařilo načíst", why (the dates and
/// filters stay), hint, "ZKUSIT ZNOVU" (= the screen's existing reload),
/// "Technické detaily ▾" (the raw error only there) and the support row.
class MotorkyErrorV2 extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const MotorkyErrorV2({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: MgCard(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(children: [
          const MgToneDisc(tone: MgTone.err),
          const SizedBox(height: MgSpace.s16),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(tr.tr('v2UxCbErrTitle'), textAlign: TextAlign.center, style: MgType.h3.copyWith(color: MgColors.ink)),
          ),
          const SizedBox(height: MgSpace.s8),
          Text(tr.tr('v2UxCbErrWhy'), textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
          const SizedBox(height: MgSpace.s8),
          Text(tr.tr('v2UxCbErrHint'), textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta)),
          const SizedBox(height: MgSpace.s16),
          MgBtnInk(label: tr.tr('eoRetry').toUpperCase(), icon: MgIcons.refresh, onTap: onRetry),
          const SizedBox(height: MgSpace.s4),
          MgTechDetails(details: '$error'),
          const Divider(height: 24, thickness: 1, color: MgColors.line),
          const MgSupportRow(),
        ]),
      ),
    );
  }
}
