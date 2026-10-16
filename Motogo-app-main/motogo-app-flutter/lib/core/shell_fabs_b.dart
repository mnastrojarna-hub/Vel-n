import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme.dart';
import 'i18n/i18n_provider.dart';
import 'shell_fabs.dart' show kShellFabShadow;
import 'v2/chrome/mg_status_strip.dart';
import 'widgets/moto_fx.dart';
import '../features/routes/active_ride_provider.dart';

// Plovoucí panely shellu, část 2 — PŘESUNUTO beze změny z app_shell.dart
// (PM-2): `_RouteFab` → [ShellRouteFab], `_DocsFab` → [ShellDocsFab].
// `v2: true` = tytéž closures ve v2 stavovém proužku.

/// Route FAB — „Pokračovat v trase" pro rozjetou navigaci. Stejný vzor jako
/// booking FAB (zelená pilulka + červený křížek). Křížek trasu UKONČÍ
/// (přesune do historie v Mých zážitcích) — jediná cesta, jak trasu zavřít.
class ShellRouteFab extends ConsumerWidget {
  final ActiveRide ride;
  final bool v2;
  const ShellRouteFab({super.key, required this.ride, this.v2 = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (v2) {
      return MgStatusStrip(
        kind: MgStripKind.route,
        title: t(context).tr('routeFabContinue'),
        sub: ride.name.isNotEmpty ? ride.name : null,
        onTap: () => openRide(context, ride),
        onDismiss: () => ref.read(activeRideProvider.notifier).endRide(),
        dismissLabel: t(context).tr('routeEndBtn'),
      );
    }
    final maxW = MediaQuery.of(context).size.width - 120;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main green button (left pill)
        PressableScale(
          pressedScale: 0.93,
          onTap: () => openRide(context, ride),
          child: Container(
            padding: const EdgeInsets.only(left: 24, right: 16, top: 14, bottom: 14),
            constraints: BoxConstraints(maxWidth: maxW),
            decoration: const BoxDecoration(
              color: MotoGoColors.green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(MotoGoRadius.pill),
                bottomLeft: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: kShellFabShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🧭', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    ride.name.isNotEmpty
                        ? '${t(context).tr('routeFabContinue')} · ${ride.name}'
                        : t(context).tr('routeFabContinue'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: MotoGoTypo.w800,
                      color: MotoGoColors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Red dismiss button (right pill) — ukončí trasu
        GestureDetector(
          onTap: () => ref.read(activeRideProvider.notifier).endRide(),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            decoration: const BoxDecoration(
              color: Color(0xFFB91C1C),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(MotoGoRadius.pill),
                bottomRight: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: kShellFabShadow,
            ),
            child: const Text(
              '✕',
              style: TextStyle(
                fontSize: 16,
                fontWeight: MotoGoTypo.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Docs FAB — green pill "Nahrajte doklady" + red X dismiss.
/// Same visual pattern as ShellBookingFab / ShellSosFab / cart FAB.
class ShellDocsFab extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final bool v2;
  const ShellDocsFab({super.key, required this.onTap, required this.onDismiss, this.v2 = false});

  @override
  Widget build(BuildContext context) {
    if (v2) {
      return MgStatusStrip(
        kind: MgStripKind.docs,
        title: t(context).tr('docsBlockingBtn'),
        sub: t(context).tr('v2StripDocsSub'),
        onTap: onTap,
        onDismiss: onDismiss,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main green button (left pill)
        PressableScale(
          pressedScale: 0.93,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.only(left: 24, right: 16, top: 14, bottom: 14),
            decoration: const BoxDecoration(
              color: MotoGoColors.green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(MotoGoRadius.pill),
                bottomLeft: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: kShellFabShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📋', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  t(context).tr('docsBlockingBtn'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: MotoGoTypo.w800,
                    color: MotoGoColors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Red dismiss button (right pill)
        GestureDetector(
          onTap: onDismiss,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            decoration: const BoxDecoration(
              color: Color(0xFFB91C1C),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(MotoGoRadius.pill),
                bottomRight: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: kShellFabShadow,
            ),
            child: const Text(
              '✕',
              style: TextStyle(
                fontSize: 16,
                fontWeight: MotoGoTypo.w900,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
