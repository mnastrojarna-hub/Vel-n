import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/widgets/state_views.dart';
import 'profile_attention_v2.dart';
import 'profile_booking_fix_v2.dart';
import 'profile_groups_v2.dart';
import 'profile_header_v2.dart';
import 'profile_personal_v2.dart';
import 'profile_tiles_v2.dart';
import 'profile_v2_parts.dart';

/// PROFIL tab root in the v2 look (PLAN §2.5.1, seam view of
/// `ProfileScreen._buildProfile`). Dumb: every value and action comes from
/// the old State (same controllers, same closures). Like today the menu is
/// visible while loading and on error; the personal form opens only when
/// the profile is loaded (`ready`). On the tab root there is no back control
/// — the nav is the way out; PUSHED (from the booking form) [onBack] puts a
/// back in the header and pins it, and [bookingFix] (`?edit=personal`) opens
/// the personal form at the fields the booking needs (profile_booking_fix_v2).
class ProfileHubV2View extends ConsumerStatefulWidget {
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
  final VoidCallback? onBack;
  final bool bookingFix;

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
    this.onBack,
    this.bookingFix = false,
  });

  @override
  ConsumerState<ProfileHubV2View> createState() => _ProfileHubV2ViewState();
}

class _ProfileHubV2ViewState extends ConsumerState<ProfileHubV2View> {
  final _settingsKey = GlobalKey();
  final _bannerKey = GlobalKey();
  final _addressKey = GlobalKey();
  final _docsKey = GlobalKey();
  bool _fixStarted = false;
  Timer? _fixTimer;

  bool get _fix => widget.bookingFix && widget.onBack != null;

  @override
  void dispose() {
    _fixTimer?.cancel();
    super.dispose();
  }

  /// Booking fix: once the profile is loaded, open the form (the screen's own
  /// toggle) and, after it has grown, bring the group with the first missing
  /// field (address, else licence) — or, with nothing missing, the green
  /// banner with "Zpět k rezervaci" — under the pinned back.
  void _maybeStartFix() {
    if (!_fix || _fixStarted || !widget.ready) return;
    _fixStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.personalExpanded) widget.onTogglePersonal();
      final wait = MgMotion.reduced(context) ? const Duration(milliseconds: 50) : const Duration(milliseconds: 360);
      _fixTimer = Timer(wait, _toFix);
    });
  }

  GlobalKey _fixTarget() {
    if (!pfBookingFixOpenNow(ref)) return _bannerKey;
    final f = widget.form;
    return [f.street, f.zip, f.city].any((c) => c.text.trim().isEmpty) ? _addressKey : _docsKey;
  }

  Future<void> _toFix([bool again = false]) async {
    if (!mounted) return;
    final c = _fixTarget().currentContext;
    if (c == null) return;
    await Scrollable.ensureVisible(
      c,
      duration: MgMotion.reduced(context) ? Duration.zero : MgMotion.sheet,
      curve: MgMotion.out,
      alignment: MgPinnedBack.revealAlignment(c),
    );
    if (again || !mounted) return;
    // The form may still have been growing (scroll extent too short): once more.
    final box = _fixTarget().currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.localToGlobal(Offset.zero).dy > MediaQuery.sizeOf(context).height / 2) {
      await _toFix(true);
    }
  }

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
    _maybeStartFix();
    return MgPage(
      tabIndex: 4,
      overlapHero: false,
      pinnedBack: w.onBack,
      pinnedTitle: _fix ? tr.tr('v2PfFixTitle') : null,
      header: ProfileHeaderV2(profile: w.profile, onSettings: _toSettings, onBack: w.onBack),
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
          fixBack: _fix ? w.onBack : null,
          bannerKey: _bannerKey,
          addressKey: _addressKey,
          docsKey: _docsKey,
        ),
        ProfileGroupsV2(actions: w.actions, settingsKey: _settingsKey, version: w.version),
      ],
    );
  }
}
