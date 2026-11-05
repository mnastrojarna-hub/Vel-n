import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../reservations/reservation_provider.dart' show hasActiveReservationProvider;
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
/// Values come from existing providers (language, currency, rental lock).
class ProfileGroupsV2 extends ConsumerWidget {
  final PfGroupActions actions;
  final GlobalKey settingsKey;
  final String version;
  const ProfileGroupsV2({super.key, required this.actions, required this.settingsKey, required this.version});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final a = actions;
    final locked = ref.watch(hasActiveReservationProvider);
    final sos = ref.watch(hasActiveRentalProvider);
    final lang = ref.watch(localeProvider).languageCode;
    final cur = ref.watch(currencyProvider);
    final curInfo = supportedCurrencies.firstWhere((c) => c.code == cur, orElse: () => supportedCurrencies.first);
    final lockText = tr.tr('v2PfLockedRental');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PfSectionLabel(tr.tr('settings'), icon: MgIcons.gear, key: settingsKey),
      MgReveal(
        sessionKey: 'pf-set',
        child: PfGroup(rows: [
          PfRow(
            icon: MgIcons.shield,
            title: tr.tr('permissions'),
            value: locked ? tr.tr('requiredLabel') : null,
            valueIcon: locked ? MgIcons.lock : null,
            onTap: a.onPermissions,
          ),
          PfRow(
            icon: MgIcons.bell,
            title: tr.tr('notifications'),
            value: locked ? lockText : null,
            valueIcon: locked ? MgIcons.lock : null,
            onTap: a.onNotif,
          ),
          PfRow(
            icon: MgIcons.lock,
            title: tr.tr('privacy'),
            value: locked ? lockText : null,
            valueIcon: locked ? MgIcons.lock : null,
            onTap: a.onPrivacy,
          ),
          PfRow(icon: MgIcons.key, title: tr.tr('changePassword'), onTap: a.onPassword),
          PfRow(icon: MgIcons.globe, title: tr.tr('language'), value: kPfLanguageNames[lang] ?? lang, onTap: a.onLanguage),
          PfRow(icon: MgIcons.cash, title: tr.tr('currency'), value: '${curInfo.code} — ${curInfo.symbol}', onTap: a.onCurrency),
        ]),
      ),
      PfSectionLabel(tr.tr('helpAndSupport'), icon: MgIcons.help),
      MgReveal(
        sessionKey: 'pf-help',
        child: PfGroup(rows: [
          if (sos) PfRow(icon: MgIcons.sos, title: tr.sosTitle, tone: PfRowTone.sos, onTap: () => context.push(Routes.sos)),
          PfRow(
            icon: MgIcons.ai,
            title: tr.tr('aiServiceAgent'),
            value: tr.tr('v2PfAiSub'),
            onTap: () => context.push(Routes.aiAgent),
          ),
          PfRow(
            icon: MgIcons.help,
            title: tr.tr('helpFaq'),
            value: 'motogo24.cz',
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
