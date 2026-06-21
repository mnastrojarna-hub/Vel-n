import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'router.dart';
import 'i18n/i18n_provider.dart';
import 'banner_provider.dart';
import 'pending_booking_fab_provider.dart';
import 'pending_sos_fab_provider.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_models.dart';
import '../features/catalog/catalog_provider.dart';
import '../features/documents/document_provider.dart';
import '../features/loyalty/loyalty_levelup_overlay.dart';
import '../features/messages/messages_provider.dart';
import '../features/payment/payment_provider.dart';
import 'widgets/moto_fx.dart';
import '../features/reservations/reservation_models.dart';
import '../features/reservations/reservation_provider.dart';
import '../features/shop/shop_provider.dart';

/// Main app shell — bottom nav bar + optional header banner.
/// Mirrors the .phone + .bnav + .header-banner from index.html.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabDefs = [
    _TabItem(route: Routes.home, i18nKey: 'navHome', icon: Icons.home_outlined, activeIcon: Icons.home),
    _TabItem(route: Routes.search, i18nKey: 'navBook', icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today),
    _TabItem(route: Routes.reservations, i18nKey: 'navReservations', icon: Icons.check_box_outlined, activeIcon: Icons.check_box),
    _TabItem(route: Routes.routes, i18nKey: 'navRoutes', icon: Icons.map_outlined, activeIcon: Icons.map),
  ];

  int _currentIndex(String location) {
    if (location.startsWith('/routes')) return 3;
    if (location.startsWith('/reservations') || location.startsWith('/sos') ||
        location == Routes.aiAgent) return 2;
    if (location == Routes.search || location.startsWith('/moto') ||
        location == Routes.booking || location == Routes.payment) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _currentIndex(location);
    final banner = ref.watch(bannerProvider);

    // Na platební obrazovce (rezervace i SOS) nesmí překážet žádný plovoucí
    // panel — jen by zakrýval tlačítko „Zaplatit". FAB se vrátí, až zákazník
    // platbu opustí. Primárně se řídíme `paymentScreenActiveProvider`, který je
    // navázaný na lifecycle PaymentScreen (spolehlivé i při push navigaci, kdy
    // se matchedLocation neaktualizuje); route-string check necháváme jako
    // pojistku.
    final onPaymentScreen = ref.watch(paymentScreenActiveProvider) ||
        location == Routes.payment ||
        location == Routes.sosPayment;

    final bannerVisible = banner.valueOrNull != null && banner.valueOrNull!.enabled;

    // Unread messages badge count
    final unreadAsync = ref.watch(unreadCountProvider);
    final unreadCount = unreadAsync.valueOrNull ?? 0;

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
    final docsVerified = ref.watch(docsVerifiedProvider);
    final reservations = ref.watch(reservationsProvider);
    final hasActiveBooking = reservations.valueOrNull?.any((r) {
          final s = r.displayStatus;
          return (s == ResStatus.aktivni || s == ResStatus.nadchazejici) &&
              r.paymentStatus == 'paid';
        }) ?? false;
    final docsComplete = docsVerified.valueOrNull?.isComplete ?? true;
    final docsFabDismissed = ref.watch(_docsFabDismissedProvider);
    final showDocsFab = hasActiveBooking && !docsComplete &&
        !docsScreens.contains(location) && !docsFabDismissed &&
        !onPaymentScreen;

    // Calculate bottom offset for stacking.
    // Original CSS: cart-fab-bar bottom:90px, #booking-fab bottom:145px,
    // .bnav height:120px → booking FAB is 25px above bnav top.
    const double fabBottomCart = 8;
    const double fabBottomUpper = 25;

    // When the keyboard is open we must NOT let this outer shell Scaffold
    // resize for the bottom inset — the inner screen Scaffolds (chat, profile,
    // SOS…) already do that. Two Scaffolds both reacting to the same keyboard
    // inset is what produced the empty gap above the keyboard and the
    // "bottom overflowed" / untappable send button. We let the inner screen
    // own the resize and hide the bottom nav while typing.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            children: [
              // Header banner (dynamic from app_settings)
              banner.when(
                data: (b) => b != null && b.enabled
                    ? _HeaderBanner(text: b.text, bg: b.bg, color: b.color)
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              // Main content — always wrap in MediaQuery.removePadding
              // to keep widget tree stable (prevents state loss when
              // bannerVisible changes). removeTop only when banner covers
              // the status-bar area.
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: bannerVisible,
                  child: child,
                ),
              ),
            ],
          ),
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
                        boxShadow: _fabShadow,
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
                        boxShadow: _fabShadow,
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
          // Booking FAB — pending reservation with 10-min countdown
          if (showBookingFabZone)
            pendingBooking.when(
              data: (booking) {
                if (booking == null || booking.isExpired) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left: 0, right: 0, bottom: fabBottomUpper,
                  child: _BookingFab(booking: booking),
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
                  child: _SosFab(incident: sos),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          // Docs FAB — active booking + missing docs
          if (showDocsFab)
            Positioned(
              left: 0, right: 0, bottom: fabBottomUpper,
              child: _DocsFab(
                onTap: () => context.push(Routes.docs),
                onDismiss: () =>
                    ref.read(_docsFabDismissedProvider.notifier).state = true,
              ),
            ),
          // Věrnostní ranky — neviditelný hlídač postupu na vyšší level.
          // Při level-upu přehraje celoobrazovkovou animaci (barva nového
          // ranku proletí obrazovkou a změní ring MG loga).
          const LoyaltyLevelUpWatcher(),
        ],
      ),
      bottomNavigationBar: keyboardOpen ? null : Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(
            color: MotoGoColors.g200,
            width: MotoGoDimens.bnavBorderWidth,
          )),
        ),
        child: SafeArea(
          child: SizedBox(
            height: MotoGoDimens.bnavHeight,
            child: Row(
              children: List.generate(_tabDefs.length, (i) {
                final tab = _tabDefs[i];
                final active = i == index;
                return Expanded(
                  child: PressableScale(
                    pressedScale: 0.9,
                    onTap: () {
                      if (i != index) {
                        // Reset booking flow when navigating to home tab
                        if (i == 0) {
                          ref.read(bookingDraftProvider.notifier).state = BookingDraft();
                          ref.read(bookingMotoProvider.notifier).state = null;
                          ref.read(catalogFilterProvider.notifier).state = const CatalogFilter();
                        }
                        context.go(tab.route);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      margin: const EdgeInsets.symmetric(
                        horizontal: MotoGoDimens.bnavTabMarginH,
                        vertical: MotoGoDimens.bnavTabMarginV,
                      ),
                      decoration: BoxDecoration(
                        // Aktivní tab = výrazný zelený gradient pill se září,
                        // ať spodní lišta nepůsobí „jak z roku 95".
                        gradient: active
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [MotoGoColors.green, MotoGoColors.greenDark],
                              )
                            : null,
                        color: active ? null : Colors.transparent,
                        borderRadius: BorderRadius.circular(MotoGoRadius.xxl),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: MotoGoColors.green.withValues(alpha: 0.5),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Elastický pop ikony při přepnutí na tab
                              NavBounceIcon(
                                active: active,
                                child: Icon(
                                  active ? tab.activeIcon : tab.icon,
                                  size: MotoGoDimens.bnavIconSize,
                                  color: active ? MotoGoColors.black : MotoGoColors.g400,
                                ),
                              ),
                              // Unread messages badge on Home tab (messages accessible via profile/hamburger)
                              if (i == 0 && unreadCount > 0)
                                Positioned(
                                  right: -6,
                                  top: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                    decoration: BoxDecoration(
                                      // Tmavý badge je čitelný i na zeleném
                                      // aktivním pilulkovém pozadí.
                                      color: MotoGoColors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        unreadCount > 9 ? '9+' : '$unreadCount',
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: MotoGoSpacing.xs),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              t(context).tr(tab.i18nKey),
                              style: TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: active ? MotoGoTypo.w900 : MotoGoTypo.w700,
                                letterSpacing: MotoGoTypo.lsNormal,
                                color: active ? MotoGoColors.black : MotoGoColors.g400,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String route;
  final String i18nKey;
  final IconData icon;
  final IconData activeIcon;
  const _TabItem({
    required this.route,
    required this.i18nKey,
    required this.icon,
    required this.activeIcon,
  });
}

/// Scrolling promo banner — matches .header-banner from CSS.
/// Height: 28px. Sits below status bar with bg color extending into safe area.
class _HeaderBanner extends StatelessWidget {
  final String text;
  final Color bg;
  final Color color;
  const _HeaderBanner({required this.text, required this.bg, required this.color});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: bg,
      padding: EdgeInsets.only(top: topPad),
      height: MotoGoDimens.bannerHeight + topPad,
      child: _MarqueeText(text: text, color: color),
    );
  }
}

/// Simple scrolling marquee — mirrors banner-scroll CSS @keyframes animation.
/// Duration: 18 seconds per full cycle (matches MotoGoDimens.marqueeSpeed).
class _MarqueeText extends StatefulWidget {
  final String text;
  final Color color;
  const _MarqueeText({required this.text, required this.color});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: MotoGoDimens.marqueeSpeed,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MotoGoDimens.bannerHeight,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final width = MediaQuery.of(context).size.width;
              final offset = _ctrl.value * width * 2;
              return Transform.translate(
                offset: Offset(width - offset, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildText(),
                    const SizedBox(width: 60),
                    _buildText(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildText() {
    return Text(
      widget.text,
      style: TextStyle(
        fontSize: MotoGoDimens.bannerFontSize,
        fontWeight: MotoGoTypo.w700,
        color: widget.color,
        letterSpacing: MotoGoTypo.lsNormal,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FAB Bars — shared UI pattern: green main btn (left pill) + red X (right pill)
// Mirrors .cart-fab-bar / .cart-fab-btn / .cart-fab-clear from elements.css
// ═══════════════════════════════════════════════════════════════════════

const _fabShadow = [
  BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 6)),
];

/// Booking FAB — "Dokončit rezervaci · M:SS" with countdown.
class _BookingFab extends ConsumerWidget {
  final PendingBooking booking;
  const _BookingFab({required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main green button (left pill)
        PressableScale(
          pressedScale: 0.93,
          onTap: () {
            // Resume rozdělané platby: PaymentScreen NESMÍ spoléhat na booking
            // draft (po restartu/úklidu je prázdný → „Motorka × 0 dny, 0 Kč
            // zdarma" a vznikaly nesmyslné rezervace). Předáme kontext s ID a
            // částkou přímo z DB řádku rezervace.
            ref.read(paymentContextProvider.notifier).state = PaymentContext(
              flowType: PaymentFlowType.booking,
              bookingId: booking.id,
              amount: booking.totalPrice,
              label: t(context).tr('bookingReservation'),
            );
            context.push(Routes.payment);
          },
          child: Container(
            padding: const EdgeInsets.only(left: 24, right: 16, top: 14, bottom: 14),
            decoration: const BoxDecoration(
              color: MotoGoColors.green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(MotoGoRadius.pill),
                bottomLeft: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: _fabShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('💳', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  '${t(context).tr('completeBookingFab')} · ${booking.timeLabel}',
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
          onTap: () async {
            await cancelPendingBooking(booking.id);
            ref.invalidate(pendingBookingFabProvider);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            decoration: const BoxDecoration(
              color: Color(0xFFB91C1C),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(MotoGoRadius.pill),
                bottomRight: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: _fabShadow,
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

/// SOS FAB — "SOS dokončit" for pending replacement selection.
class _SosFab extends ConsumerWidget {
  final PendingSosReplacement incident;
  const _SosFab({required this.incident});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main green button (left pill)
        PressableScale(
          pressedScale: 0.93,
          onTap: () => context.push(Routes.sosReplacement),
          child: Container(
            padding: const EdgeInsets.only(left: 24, right: 16, top: 14, bottom: 14),
            decoration: const BoxDecoration(
              color: MotoGoColors.green,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(MotoGoRadius.pill),
                bottomLeft: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: _fabShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🆘', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text(
                  t(context).tr('sosCompleteFab'),
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
          onTap: () async {
            await dismissSosFab(incident.id);
            ref.invalidate(pendingSosFabProvider);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            decoration: const BoxDecoration(
              color: Color(0xFFB91C1C),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(MotoGoRadius.pill),
                bottomRight: Radius.circular(MotoGoRadius.pill),
              ),
              boxShadow: _fabShadow,
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

/// Dismiss state for docs FAB — resets when docs become verified.
final _docsFabDismissedProvider = StateProvider<bool>((_) => false);

/// Docs FAB — green pill "Nahrajte doklady" + red X dismiss.
/// Same visual pattern as _BookingFab / _SosFab / cart FAB.
class _DocsFab extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _DocsFab({required this.onTap, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
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
              boxShadow: _fabShadow,
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
              boxShadow: _fabShadow,
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
