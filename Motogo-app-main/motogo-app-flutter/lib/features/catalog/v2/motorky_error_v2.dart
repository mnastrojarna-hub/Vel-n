import 'package:flutter/material.dart';

import '../../../core/friendly_error.dart';
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
import '../../../core/widgets/error_feedback.dart' show openFixSettings;

/// Motorky list could not load (Stavy 8.6, CB-21): white card under the
/// header — err disc, "Motorky se nepodařilo načíst", why + hint = the
/// REAL reason and fix of the error (FriendlyError, as the old MgErrorView:
/// offline, session, rate limit, permission…), "ZKUSIT ZNOVU" (= the
/// screen's existing reload), "Otevřít nastavení" when the fix is there,
/// "Technické detaily ▾" (the raw error only there) and the support row.
class MotorkyErrorV2 extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const MotorkyErrorV2({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final fe = FriendlyError.of(error);
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
          Text(friendlyWhy(tr, fe), textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
          const SizedBox(height: MgSpace.s8),
          Text(fe.body(tr), textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta)),
          const SizedBox(height: MgSpace.s16),
          MgBtnInk(label: tr.tr('eoRetry').toUpperCase(), icon: MgIcons.refresh, onTap: onRetry),
          if (fe.needsSettings) ...[
            const SizedBox(height: MgSpace.s8),
            MgBtnGhostLight(label: tr.tr('eoOpenSettings'), onTap: () => openFixSettings(fe)),
          ],
          const SizedBox(height: MgSpace.s4),
          MgTechDetails(details: '$error'),
          const Divider(height: 24, thickness: 1, color: MgColors.line),
          const MgSupportRow(),
        ]),
      ),
    );
  }
}

/// "Bez připojení k internetu." — the error's own reason, capitalised (as
/// the old MgErrorView's `what` body).
String friendlyWhy(AppTranslations tr, FriendlyError fe) {
  final r = fe.reason(tr).trim();
  if (r.isEmpty) return r;
  final c = r[0].toUpperCase() + r.substring(1);
  return c.endsWith('.') ? c : '$c.';
}
