import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../sos/sos_provider.dart' show hasActiveRentalProvider;
import 'profile_v2_parts.dart';

/// Native names of the app languages (same list as the language sheet).
const Map<String, String> kPfLanguageNames = {
  'cs': 'Čeština',
  'en': 'English',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
  'nl': 'Nederlands',
  'pl': 'Polski',
  'uk': 'Українська',
};

/// Callbacks of the Profil groups — the SAME actions as today's menu rows.
class PfGroupActions {
  final VoidCallback onPermissions, onNotif, onPrivacy, onPassword, onLanguage, onCurrency;
  final VoidCallback onFaq, onLogout, onDelete;
  const PfGroupActions({
    required this.onPermissions,
    required this.onNotif,
    required this.onPrivacy,
    required this.onPassword,
    required this.onLanguage,
    required this.onCurrency,
    required this.onFaq,
    required this.onLogout,
    required this.onDelete,
  });
}

/// Nastavení · Pomoc a podpora · Ostatní (V21 §1.2) + version footer.
/// Rows without values on the right, like the old menu items (look only).
class ProfileGroupsV2 extends ConsumerWidget {
  final PfGroupActions actions;
  final GlobalKey settingsKey;
  final String version;
  const ProfileGroupsV2({super.key, required this.actions, required this.settingsKey, required this.version});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final a = actions;
    final sos = ref.watch(hasActiveRentalProvider);
    // „jen vzhled“ (majitel 2026-11-07): řádky nastavení BEZ hodnot vpravo —
    // jako položky menu v původní appce (jazyk, měna, kanály i zámek
    // souhlasů ukazují až otevřené listy, stejně jako dřív).
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PfSectionLabel(tr.tr('settings'), icon: MgIcons.gear, key: settingsKey),
      MgReveal(
        sessionKey: 'pf-set',
        child: PfGroup(rows: [
          PfRow(icon: MgIcons.shield, title: tr.tr('permissions'), onTap: a.onPermissions),
          PfRow(icon: MgIcons.bell, title: tr.tr('notifications'), onTap: a.onNotif),
          PfRow(icon: MgIcons.lock, title: tr.tr('privacy'), onTap: a.onPrivacy),
          PfRow(icon: MgIcons.key, title: tr.tr('changePassword'), onTap: a.onPassword),
          PfRow(icon: MgIcons.globe, title: tr.tr('language'), onTap: a.onLanguage),
          PfRow(icon: MgIcons.cash, title: tr.tr('currency'), onTap: a.onCurrency),
        ]),
      ),
      PfSectionLabel(tr.tr('helpAndSupport'), icon: MgIcons.help),
      MgReveal(
        sessionKey: 'pf-help',
        child: PfGroup(rows: [
          if (sos) PfRow(icon: MgIcons.sos, title: tr.sosTitle, tone: PfRowTone.sos, onTap: () => context.push(Routes.sos)),
          PfRow(
            icon: MgIcons.help,
            title: tr.tr('helpFaq'),
            trail: PfTrail.external,
            onTap: a.onFaq,
          ),
        ]),
      ),
      PfSectionLabel(tr.tr('otherSection'), icon: MgIcons.more),
      MgReveal(
        sessionKey: 'pf-other',
        child: PfGroup(rows: [
          PfRow(icon: MgIcons.logout, title: tr.logout, tone: PfRowTone.danger, trail: PfTrail.none, onTap: a.onLogout),
          PfRow(
            icon: MgIcons.trash,
            title: tr.tr('deleteAccountBtn'),
            tone: PfRowTone.danger,
            trail: PfTrail.none,
            onTap: a.onDelete,
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text('MotoGo24 $version',
            textAlign: TextAlign.center,
            style: MgType.tab(MgType.micro.copyWith(letterSpacing: 0.4, color: MgColors.meta))),
      ),
    ]);
  }
}
