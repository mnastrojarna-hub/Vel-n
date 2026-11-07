import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../auth/auth_provider.dart';
import '../../booking/booking_provider.dart';

/// Profil opened from the booking form to complete the data the booking
/// needs (v2 only; booking r3 / profile r3): the booking form pushes
/// `/profile?edit=personal` ("Doplnit v profilu"). The Profil then has a
/// back, opens the personal form at the missing fields, marks them and,
/// once the SAVED profile satisfies the booking, offers "Zpět k rezervaci".
/// Read-only over the existing providers — save, validation and the booking
/// itself are unchanged.
const String kPfBookingFixQuery = 'edit';
const String kPfBookingFixValue = 'personal';

/// `/profile?edit=personal` (pushed by the booking form). False outside a
/// GoRouter page (widget tests) and on the Profil tab root.
bool pfBookingFixRequested(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.queryParameters[kPfBookingFixQuery] == kPfBookingFixValue;
  } catch (_) {
    return false;
  }
}

/// Back of a Profil that was PUSHED on top of another screen (the booking
/// form). Null on the tab root (the nav is the way out there).
VoidCallback? pfPushedBack(BuildContext context) {
  final route = ModalRoute.of(context);
  if (route == null || route.isFirst) return null;
  return () => context.backOr(Routes.profile);
}

/// The bike being booked needs a licence (the SAME rule as
/// `profileCompletenessValidationProvider`): licence number and expiry are
/// required for it.
bool pfNeedsLicence(WidgetRef ref) {
  final moto = ref.watch(bookingMotoProvider);
  return !(moto?.licenseGroupsOrFallback.map((g) => g.toUpperCase()).contains('N') ?? true);
}

/// The booking still can't go on with the SAVED profile — decided by the
/// booking form's own validations (nothing re-implemented here).
bool pfBookingFixOpen(WidgetRef ref) =>
    ref.watch(profileCompletenessValidationProvider) != null || ref.watch(licenseValidationProvider) != null;

/// [pfBookingFixOpen] outside build (scroll target).
bool pfBookingFixOpenNow(WidgetRef ref) =>
    ref.read(profileCompletenessValidationProvider) != null || ref.read(licenseValidationProvider) != null;

enum PfFixKind { missing, expired, group }

/// What to tell the customer (tykání, v2): the missing fields by name, an
/// expired licence, or the licence category the bike needs; null = done.
({PfFixKind kind, String text})? pfBookingFix(BuildContext context, WidgetRef ref) {
  final tr = t(context);
  if (ref.watch(profileCompletenessValidationProvider) != null) {
    final p = ref.watch(profileProvider).valueOrNull ?? const <String, dynamic>{};
    bool empty(String k) => '${p[k] ?? ''}'.trim().isEmpty;
    final lic = pfNeedsLicence(ref);
    final missing = [
      if (empty('street')) tr.tr('streetShort'),
      if (empty('zip')) tr.tr('zip'),
      if (empty('city')) tr.tr('city'),
      if (lic && empty('license_number')) tr.tr('licenseNumber'),
      if (lic && empty('license_expiry')) tr.tr('licenseExpiry'),
    ];
    // Everything filled in → the remaining gate reason is the expiry date.
    if (missing.isEmpty) return (kind: PfFixKind.expired, text: tr.tr('v2PfFixExpired'));
    return (kind: PfFixKind.missing, text: tr.tr('v2PfFixMissing').replaceAll('{fields}', missing.join(', ')));
  }
  if (ref.watch(licenseValidationProvider) != null) {
    final groups = ref.watch(bookingMotoProvider)?.licenseGroupsOrFallback.map((g) => g.toUpperCase()).where((g) => g.isNotEmpty) ?? const <String>[];
    return (kind: PfFixKind.group, text: tr.tr('v2PfFixGroup').replaceAll('{license}', groups.join(' / ')));
  }
  return null;
}

/// Top of the personal card: amber = what the booking still needs + "save
/// and go back"; green = done + the way back to the booking.
class PfBookingFixBannerV2 extends ConsumerWidget {
  final VoidCallback onBack;
  const PfBookingFixBannerV2({super.key, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final msg = pfBookingFix(context, ref)?.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MgEnter(
        key: ValueKey(msg == null),
        child: msg != null
            ? MgStateBanner(
                tone: MgTone.warn,
                icon: MgIcons.idCard,
                title: tr.tr('v2PfFixTitle'),
                text: '$msg\n${tr.tr('v2PfFixHint')}',
              )
            : MgStateBanner(
                tone: MgTone.ok,
                icon: MgIcons.checkCircle,
                title: tr.tr('v2PfFixDone'),
                actions: [PfBookingFixReturnV2(onBack: onBack, inBanner: true)],
              ),
      ),
    );
  }
}

/// "Zpět k rezervaci" — under Save (and in the green banner) once the saved
/// profile satisfies the booking; nothing while something is still missing.
class PfBookingFixReturnV2 extends ConsumerWidget {
  final VoidCallback onBack;
  final bool inBanner;
  const PfBookingFixReturnV2({super.key, required this.onBack, this.inBanner = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    if (pfBookingFixOpen(ref)) return const SizedBox.shrink();
    if (inBanner) {
      return MgBtnInk(label: tr.tr('v2PfFixBack'), icon: MgIcons.chevronLeft, onTap: onBack, height: 44, expand: false);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: MgEnter(
        child: MgBtnGhostLight(label: tr.tr('v2PfFixBack'), icon: MgIcons.chevronLeft, onTap: onBack),
      ),
    );
  }
}
