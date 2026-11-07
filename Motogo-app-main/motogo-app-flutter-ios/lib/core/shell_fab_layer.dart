import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'router.dart';
import 'i18n/i18n_provider.dart';
import 'pending_booking_fab_provider.dart';
import 'pending_sos_fab_provider.dart';
import 'shell_fabs.dart';
import 'shell_fabs_b.dart';
import 'v2/chrome/mg_chrome_metrics.dart' show MgSizeReporter;
import 'v2/chrome/mg_status_strip.dart';
import 'widgets/moto_fx.dart';
import '../features/documents/docs_gate_provider.dart';
import '../features/reservations/reservation_models.dart';
import '../features/reservations/reservation_provider.dart';
import '../features/routes/active_ride_provider.dart';
import '../features/shop/shop_provider.dart';

/// Dismiss state for docs FAB — resets when docs become verified.
final _docsFabDismissedProvider = StateProvider<bool>((_) => false);

/// Plovoucí panely shellu (košík, rozdělaná rezervace / platba, SOS,
/// doklady, rozjetá trasa) — PŘESUNUTO beze změny z `AppShell.build` (PM-2):
/// stejné podmínky viditelnosti i pozice. Vrací `Stack` přes celé tělo
/// shellu. [v2] = tytéž panely jako v2 stavové proužky nad sebou (8 px
/// mezera) od [bottomBase] nahoru; výšku hlásí [onStripsHeight].
class ShellFabLayer extends ConsumerWidget {
  final String location;
  final double bottomBase;
  final bool v2;
  final ValueChanged<double>? onStripsHeight;

  const ShellFabLayer({
    super.key,
    required this.location,
    this.bottomBase = 0,
    this.v2 = false,
    this.onStripsHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Na platební obrazovce (rezervace i SOS) nesmí překážet žádný plovoucí
    // panel — jen by zakrýval tlačítko „Zaplatit". FAB se vrátí, až zákazník
    // platbu opustí. Primárně se řídíme `paymentScreenActiveProvider`, který je
    // navázaný na lifecycle PaymentScreen (spolehlivé i při push navigaci, kdy
    // se matchedLocation neaktualizuje); route-string check necháváme jako
    // pojistku.
    final onPaymentScreen = ref.watch(paymentScreenActiveProvider) ||
        location == Routes.payment ||
        location == Routes.sosPayment;

    // Cart FAB: show on screens outside cart/checkout flow when cart has items
    final cart = ref.watch(cartProvider);
    final cartCount = cart.fold<int>(0, (sum, item) => sum + item.qty);
    final cartTotal = cart.fold<double>(0, (sum, item) => sum + item.price * item.qty);
    // E-shop už není tab — košíkový FAB skrýváme přímo na shop/cart/checkout
    // obrazovkách (dostupné z hamburger menu), ne podle indexu tabu.
    final onShopFlow = location.startsWith('/shop') ||
        location == Routes.cart || location == Routes.checkout ||
        location == Routes.voucher;
    final hideCartFab = onShopFlow || onPaymentScreen;
    final fabDismissed = ref.watch(cartFabDismissedProvider);
    final showCartFab = cartCount > 0 && !hideCartFab && !fabDismissed;

    // Booking FAB: hide on payment flow & auth screens
    const hideBookingFabOn = [
      Routes.login, Routes.register, Routes.docScan,
      Routes.payment, Routes.success,
    ];
    final showBookingFabZone =
        !hideBookingFabOn.contains(location) && !onPaymentScreen;
    final pendingBooking = ref.watch(pendingBookingFabProvider);
    final bookingFabVisible = showBookingFabZone &&
        pendingBooking.valueOrNull != null &&
        !pendingBooking.valueOrNull!.isExpired;

    // Route FAB — rozjetá trasa (navigace opuštěná šipkou zpět / zavřením
    // appky). Stejný vizuál jako booking FAB; křížek trasu definitivně ukončí.
    final activeRide = ref.watch(activeRideProvider).active;
    final showRouteFab = activeRide != null && !onPaymentScreen &&
        !hideBookingFabOn.contains(location);

    // SOS FAB: hide on SOS flow & auth screens
    final hideSosFabOn = [
      Routes.login, Routes.register, Routes.docs,
      Routes.sos, Routes.sosAccident, Routes.sosBreakdown,
      Routes.sosTheft, Routes.sosService,
      Routes.sosReplacement, Routes.sosPayment, Routes.sosDone,
    ];
    final showSosFabZone = !hideSosFabOn.contains(location) && !onPaymentScreen;
    final pendingSos = ref.watch(pendingSosFabProvider);

    // Docs FAB: active/upcoming booking + docs not verified
    // Don't show on docs/scan screens (user is already uploading)
    final docsScreens = [Routes.docs, Routes.docScan];
    final reservations = ref.watch(reservationsProvider);
    final hasActiveBooking = reservations.valueOrNull?.any((r) {
          final s = r.displayStatus;
          return (s == ResStatus.aktivni || s == ResStatus.nadchazejici) &&
              r.paymentStatus == 'paid';
        }) ?? false;
    // Kompletnost OP/pasu + ŘP podle brány dokladů (obě strany, stejně jako
    // Moje doklady); bez odpovědi RPC zpět na profilové `*_verified_at`.
    final docsComplete =
        ref.watch(docsFabStatusProvider).valueOrNull?.isComplete ?? true;
    final docsFabDismissed = ref.watch(_docsFabDismissedProvider);
    final showDocsFab = hasActiveBooking && !docsComplete &&
        !docsScreens.contains(location) && !docsFabDismissed &&
        !onPaymentScreen;

    // Calculate bottom offset for stacking.
    // Original CSS: cart-fab-bar bottom:90px, #booking-fab bottom:145px,
    // .bnav height:120px → booking FAB is 25px above bnav top.
    const double fabBottomCart = 8;
    const double fabBottomUpper = 25;

    if (v2) {
      final booking = showBookingFabZone
          ? pendingBooking.when(
              data: (b) => (b == null || b.isExpired) ? null : b,
              loading: () => null,
              error: (_, __) => null,
            )
          : null;
      final sos = showSosFabZone
          ? pendingSos.when(data: (s) => s, loading: () => null, error: (_, __) => null)
          : null;
      // Priorita: SOS > platba > doklady > trasa > košík (V22 T4).
      final strips = <Widget>[
        if (sos != null) ShellSosFab(incident: sos, v2: true),
        if (booking != null) ShellBookingFab(booking: booking, v2: true),
        if (showDocsFab)
          ShellDocsFab(
            v2: true,
            onTap: () => context.push(Routes.docs),
            onDismiss: () => ref.read(_docsFabDismissedProvider.notifier).state = true,
          ),
        if (showRouteFab) ShellRouteFab(ride: activeRide, v2: true),
        if (showCartFab)
          MgStatusStrip(
            kind: MgStripKind.cart,
            title: t(context).tr('cartFab').replaceAll('{count}', '$cartCount').replaceAll('{total}', cartTotal.toStringAsFixed(0)),
            sub: t(context).tr('v2StripCartSub'),
            onTap: () => context.push(Routes.cart),
            onDismiss: () => ref.read(cartFabDismissedProvider.notifier).state = true,
          ),
      ];
      return Stack(children: [
        Positioned(
          left: 16,
          right: 16,
          bottom: bottomBase,
          child: MgSizeReporter(
            onSize: (s) => onStripsHeight?.call(s.height),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < strips.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                strips[i],
              ],
            ]),
          ),
        ),
      ]);
    }

    return Stack(
      children: [
        // Cart FAB bar — green left pill + red right pill (matches original)
        if (showCartFab)
          Positioned(
            left: 0, right: 0, bottom: fabBottomCart,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Green main button (left pill)
                PressableScale(
                  pressedScale: 0.93,
                  onTap: () => context.push(Routes.cart),
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
                        const Text('🛒', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Text(
                          t(context).tr('cartFab').replaceAll('{count}', '$cartCount').replaceAll('{total}', cartTotal.toStringAsFixed(0)),
                          style: const TextStyle(fontSize: 14, fontWeight: MotoGoTypo.w800, color: MotoGoColors.black),
                        ),
                      ],
                    ),
                  ),
                ),
                // Red dismiss button (right pill)
                GestureDetector(
                  onTap: () => ref.read(cartFabDismissedProvider.notifier).state = true,
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
                      style: TextStyle(fontSize: 16, fontWeight: MotoGoTypo.w900, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Booking FAB — pending reservation with 30-min countdown (provider
        // re-checks the DB every 5 s, so a paid/cancelled booking drops it)
        if (showBookingFabZone)
          pendingBooking.when(
            data: (booking) {
              if (booking == null || booking.isExpired) {
                return const SizedBox.shrink();
              }
              return Positioned(
                left: 0, right: 0, bottom: fabBottomUpper,
                child: ShellBookingFab(booking: booking),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        // SOS FAB — incident reported, replacement not selected
        if (showSosFabZone)
          pendingSos.when(
            data: (sos) {
              if (sos == null) return const SizedBox.shrink();
              return Positioned(
                left: 0, right: 0,
                bottom: showCartFab ? fabBottomUpper : fabBottomCart,
                child: ShellSosFab(incident: sos),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        // Docs FAB — active booking + missing docs
        if (showDocsFab)
          Positioned(
            left: 0, right: 0, bottom: fabBottomUpper,
            child: ShellDocsFab(
              onTap: () => context.push(Routes.docs),
              onDismiss: () =>
                  ref.read(_docsFabDismissedProvider.notifier).state = true,
            ),
          ),
        // Route FAB — pokračovat v rozjeté trase (nad ostatními FABy,
        // pokud horní pozici zrovna drží booking/docs FAB).
        if (showRouteFab && activeRide != null)
          Positioned(
            left: 0, right: 0,
            bottom: (bookingFabVisible || showDocsFab)
                ? fabBottomUpper + 58
                : fabBottomUpper,
            child: ShellRouteFab(ride: activeRide),
          ),
      ],
    );
  }
}
