import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/native/permission_service.dart' show PermissionInfo;
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import 'profile_v2_parts.dart';

/// "Oprávnění aplikace" in the v2 look (PLAN §2.5.2, seam view of
/// `PermissionsScreen`): dark compact app bar, white grouped rows with
/// status chips (Povoleno / Zakázáno + Vyžadováno during a rental), the
/// biometrics switch, "Otevřít nastavení telefonu" and "Povolit vše znovu".
/// Every action is the screen's own closure.
class PermissionsViewV2 extends StatelessWidget {
  /// (permission, required now) — null while loading.
  final List<(PermissionInfo, bool)>? perms;
  final bool requiredActive;
  final bool bioAvailable;
  final bool bioEnabled;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;
  final VoidCallback onBioTap;
  final VoidCallback onAllowAll;

  const PermissionsViewV2({
    super.key,
    required this.perms,
    required this.requiredActive,
    required this.bioAvailable,
    required this.bioEnabled,
    required this.onBack,
    required this.onOpenSettings,
    required this.onBioTap,
    required this.onAllowAll,
  });

  static String iconFor(String key) => switch (key) {
        'location' => MgIcons.pin,
        'camera' => MgIcons.camera,
        'notifications' => MgIcons.bell,
        'photos' => MgIcons.image,
        _ => MgIcons.shield,
      };

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgPage(
      header: MgAppBar(title: tr.tr('permissions'), onBack: onBack),
      overlapHero: false,
      sections: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text('${tr.tr('permsGrantedFirstRun')} ${tr.tr('permsChangeHint')}',
              style: MgType.small.copyWith(color: MgColors.lead)),
        ),
        if (requiredActive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: MgTintOk(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const MgIcon(MgIcons.lock, size: 18, color: MgColors.onTintOk),
                const SizedBox(width: 10),
                Expanded(child: Text(tr.tr('permsRequiredActive'), style: MgType.small.copyWith(color: MgColors.onTintOk))),
              ]),
            ),
          ),
        const SizedBox(height: 16),
        if (perms == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: MgColors.link)),
          )
        else
          MgReveal(
            child: PfGroup(rows: [for (final p in perms!) _row(context, p.$1, p.$2)]),
          ),
        if (bioAvailable) ...[
          PfSectionLabel(tr.tr('biometric'), icon: MgIcons.finger),
          MgCard(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: MgFabAvoid(
              kind: MgAvoidKind.tap,
              child: MgSwitchRow(
                title: tr.tr('fingerprintFaceId'),
                value: bioEnabled,
                onChanged: (_) => onBioTap(),
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MgFabAvoid(
              child: MgBtnInk(label: tr.tr('openPhoneSettings'), icon: MgIcons.gear, onTap: onOpenSettings),
            ),
            const SizedBox(height: 8),
            MgFabAvoid(child: MgBtnGhostLight(label: tr.tr('allowAllAgain'), icon: MgIcons.refresh, onTap: onAllowAll)),
          ]),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, PermissionInfo p, bool required) {
    final tr = t(context);
    final attention = required && !p.granted;
    return PfRow(
      icon: iconFor(p.key),
      title: tr.tr(p.title),
      value: tr.tr(p.desc),
      onTap: onOpenSettings,
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        MgMeaningChip(
          label: p.granted ? tr.tr('allowedLabel') : tr.tr('deniedLabel'),
          tone: p.granted ? MgTone.ok : MgTone.err,
        ),
        if (required) ...[
          const SizedBox(height: 4),
          MgMeaningChip(
            label: tr.tr('requiredLabel'),
            tone: attention ? MgTone.warn : MgTone.info,
            icon: MgIcons.lock,
          ),
        ],
      ]),
    );
  }
}
