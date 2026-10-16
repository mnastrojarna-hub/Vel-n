import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/widgets/state_views.dart';
import 'profile_attention_v2.dart';
import 'profile_groups_v2.dart';
import 'profile_header_v2.dart';
import 'profile_personal_v2.dart';
import 'profile_tiles_v2.dart';
import 'profile_v2_parts.dart';

/// PROFIL tab root in the v2 look (PLAN §2.5.1, seam view of
/// `ProfileScreen._buildProfile`). Dumb: every value and action comes from
/// the old State (same controllers, same closures). Like today the menu is
/// visible while loading and on error; the personal form opens only when
/// the profile is loaded (`ready`). No back control — the nav is the way out.
class ProfileHubV2View extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final bool loading;
  final Object? error;
  final bool ready;
  final bool personalExpanded;
  final VoidCallback onRetry;
  final VoidCallback onTogglePersonal;
  final VoidCallback onPaymentMethods;
  final PfFormData form;
  final PfGroupActions actions;
  final String version;

  const ProfileHubV2View({
    super.key,
    required this.profile,
    required this.loading,
    required this.error,
    required this.ready,
    required this.personalExpanded,
    required this.onRetry,
    required this.onTogglePersonal,
    required this.onPaymentMethods,
    required this.form,
    required this.actions,
    required this.version,
  });

  @override
  State<ProfileHubV2View> createState() => _ProfileHubV2ViewState();
}

class _ProfileHubV2ViewState extends State<ProfileHubV2View> {
  final _settingsKey = GlobalKey();

  void _toSettings() {
    final c = _settingsKey.currentContext;
    if (c == null) return;
    Scrollable.ensureVisible(
      c,
      duration: MgMotion.reduced(context) ? Duration.zero : MgMotion.sheet,
      curve: MgMotion.out,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final w = widget;
    return MgPage(
      tabIndex: 4,
      overlapHero: false,
      header: ProfileHeaderV2(profile: w.profile, onSettings: _toSettings),
      sections: [
        if (w.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: MgErrorView(compact: true, error: w.error, what: tr.tr('eoProfileLoadFail'), onRetry: w.onRetry),
          ),
        const ProfileAttentionV2(),
        PfSectionLabel(tr.tr('myAccount'), icon: MgIcons.person),
        ProfileTilesV2(onPaymentMethods: w.onPaymentMethods),
        const SizedBox(height: 24),
        ProfilePersonalV2(
          profile: w.loading ? null : w.profile,
          ready: w.ready,
          expanded: w.personalExpanded,
          onToggle: w.onTogglePersonal,
          form: w.form,
        ),
        ProfileGroupsV2(actions: w.actions, settingsKey: _settingsKey, version: w.version),
      ],
    );
  }
}
