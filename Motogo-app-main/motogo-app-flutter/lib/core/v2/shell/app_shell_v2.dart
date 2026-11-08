import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../banner_provider.dart';
import '../../feature_flags.dart' show appV2UiProvider;
import '../../pending_booking_fab_provider.dart';
import '../../shell_fab_layer.dart';
import '../../shell_paid_listener.dart';
import '../../shell_tab_action.dart';
import '../../widgets/mg_back.dart';
import '../../../features/documents/docs_gate_provider.dart';
import '../../../features/messages/messages_provider.dart';
import '../../../features/reservations/reservation_models.dart';
import '../../../features/reservations/reservation_provider.dart';
import '../chrome/mg_ai_fab.dart';
import '../chrome/mg_chrome_metrics.dart';
import '../chrome/mg_hide_on_scroll.dart';
import '../chrome/mg_nav_band.dart';
import '../chrome/mg_status_bar.dart';
import '../chrome/mg_top_banner.dart';
import '../chrome/v2_nav_bar.dart';
import '../motion/mg_motion.dart';
import '../motion/mg_sticky_slide.dart';
import '../tokens/mg_colors.dart';
import 'shell_nav_map.dart';

/// The v2 app shell (PLAN §1.10): same body handling as `AppShell`
/// (`MgBackGuard(shell: true)`, banner, keyboard), the SAME floating panels
/// (`ShellFabLayer`, as v2 status strips) and paid-after-restart notice
/// (`ShellPaidListener`), plus the 5-tab [V2NavBar] (on every shell route,
/// hidden only with the keyboard — as the old shell) and the floating AI
/// button (Domů only, as the old app). Tab taps go
/// through the shared `onShellTabTap` (payment-running confirm, Home reset).
/// Location is read from the router delegate, so pushed routes count too.
/// Status bar (fix:statusbar): the shell declares its canvas (dark icons)
/// for whatever has no region of its own (a v1 screen kept inside the v2
/// look); v2 pages, their dark headers and the banner band declare
/// themselves and win while they lie under the status bar.
/// Hide-on-scroll (owner 2026-11-08, `MgBarsController`): scrolling the
/// content down folds the nav to its safe-area band (`MgNavBand`) and the
/// banner band's line; scrolling up, a route change or a tab switch brings
/// them back. Docks, strips and the AI button keep sitting on the body's
/// bottom edge (the band keeps the safe area), so nothing re-insets.
class AppShellV2 extends ConsumerStatefulWidget {
  final Widget child;
  const AppShellV2({super.key, required this.child});

  @override
  ConsumerState<AppShellV2> createState() => _AppShellV2State();
}

class _AppShellV2State extends ConsumerState<AppShellV2> {
  final MgShellChrome _chrome = MgShellChrome();
  final MgBarsController _bars = MgBarsController();

  /// The nav as last shown — kept while it slides out (no tab jump).
  Widget? _lastNav;
  GoRouter? _router;
  String _location = '/';

  @override
  void initState() {
    super.initState();
    _bars.addListener(_onBars);
  }

  void _onBars() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = GoRouter.maybeOf(context);
    if (r != _router) {
      _router?.routerDelegate.removeListener(_onRoute);
      _router = r;
      _router?.routerDelegate.addListener(_onRoute);
    }
    _location = _readLocation();
  }

  String _readLocation() {
    final r = _router;
    if (r != null) {
      try {
        return mgCurrentLocation(r);
      } catch (_) {}
    }
    try {
      return GoRouterState.of(context).matchedLocation;
    } catch (_) {
      return _location;
    }
  }

  void _onRoute() {
    if (!mounted) return;
    final loc = _readLocation();
    if (loc != _location) {
      setState(() => _location = loc);
      // Every route change / tab switch starts with the bars shown.
      _bars.reset();
    }
    // The cross-tab back chip lives only while its tab is on screen.
    final origin = ref.read(v2TabOriginProvider);
    if (origin != null && v2TabIndexFor(loc) != origin.tab) {
      Future.microtask(() {
        if (mounted && ref.read(v2TabOriginProvider) == origin) {
          ref.read(v2TabOriginProvider.notifier).state = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRoute);
    _bars
      ..removeListener(_onBars)
      ..dispose();
    // Docks / avoid zones unregister in post-frame callbacks scheduled by the
    // children (disposed first) → dispose the chrome after them.
    final c = _chrome;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  /// One tick per finished scroll (not per frame): only the AI button
  /// re-checks its slot (`MgShellChrome.scrollTick`).
  bool _onScroll(ScrollEndNotification n) {
    _chrome.scrollIdle();
    return false;
  }

  Future<void> _onTab(int i) async {
    final route = kV2TabRoutes[i];
    final location = _location;
    if ((Uri.tryParse(location)?.path ?? location) == route) {
      // Re-tap on the tab root = scroll to top (MgPage listens).
      final prev = ref.read(v2TabReselectProvider);
      ref.read(v2TabReselectProvider.notifier).state = (i, prev.$2 + 1);
      return;
    }
    // A real tab switch ends a cross-tab jump: `_onRoute` drops the back
    // chip once the location leaves its tab (a cancelled payment confirm
    // keeps it).
    await onShellTabTap(context, ref, route: route, isActive: false, isHome: i == 0, location: location);
    if (mounted) ref.read(appV2UiProvider.notifier).applyPendingIfSafe(route);
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;
    final path = Uri.tryParse(location)?.path ?? location;
    final banner = ref.watch(bannerProvider);
    final bannerVisible = banner.valueOrNull != null && banner.valueOrNull!.enabled;
    // `/` a `/search` mají banner jako poslední řádek své v2 hlavičky.
    final topBanner = bannerVisible && banner.valueOrNull!.text.trim().isNotEmpty && path != '/' && path != '/search';
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // As the old AppShell: the nav on every shell route, hidden only while
    // the keyboard is open.
    final navHidden = keyboardOpen;
    // Hide-on-scroll: folds the nav to its band and the banner line.
    final folded = _bars.hidden;
    final fabHidden = keyboardOpen || v2FabHiddenFor(path) || ref.watch(paymentScreenActiveProvider);

    // Badges: Profil = nepřečtené zprávy; Rezervace = rezervace čeká na akci
    // (nezaplacená rozdělaná, nebo chybí doklady k placené aktivní/nadcházející
    // — stejné podmínky jako plovoucí panely).
    final unread = ref.watch(adminUnreadCountProvider);
    final pb = ref.watch(pendingBookingFabProvider).valueOrNull;
    final unpaid = pb != null && !pb.isExpired && !pb.verifying;
    final hasActiveBooking = ref.watch(reservationsProvider).valueOrNull?.any((r) {
          final s = r.displayStatus;
          return (s == ResStatus.aktivni || s == ResStatus.nadchazejici) && r.paymentStatus == 'paid';
        }) ??
        false;
    final docsComplete = ref.watch(docsFabStatusProvider).valueOrNull?.isComplete ?? true;
    final needsAction = unpaid || (hasActiveBooking && !docsComplete);
    // Same dot on the v2 nav drawn outside the shell (Moje zážitky).
    if (ref.read(v2BookingsNeedActionProvider) != needsAction) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(v2BookingsNeedActionProvider.notifier).state = needsAction;
      });
    }

    if (!navHidden) {
      _lastNav = V2NavBar(
        activeIndex: v2TabIndexFor(path),
        onTap: _onTab,
        profileBadge: unread,
        bookingsNeedAction: needsAction,
      );
    }
    final outer = MediaQuery.of(context);
    final sticky = MgMotion.of(context, MgMotion.sticky);

    return ShellPaidListener(
      child: Scaffold(
        backgroundColor: MgColors.canvas,
        resizeToAvoidBottomInset: false,
        body: MgStatusBar(
          dark: false,
          child: MgChromeScope(
            chrome: _chrome,
            navVisible: !navHidden,
            fabVisible: !fabHidden,
            foldedViewport: outer.size.height - (navHidden ? 0 : outer.padding.bottom) - (topBanner ? outer.padding.top : 0),
            child: Stack(children: [
              Column(children: [
                // v2 jednořádkový banner (marquee; při omezení pohybu statický
                // řádek, klepnutí = celý text) — stejný jako v hlavičce Domů.
                if (topBanner) MgTopBanner(text: banner.valueOrNull!.text, band: true, folded: folded),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: topBanner,
                    child: MgHideOnScroll(
                      controller: _bars,
                      child: NotificationListener<ScrollEndNotification>(
                      onNotification: _onScroll,
                      // The nav slot stays in the Scaffold while the nav
                      // slides out (collapsed to 0), which strips the body's
                      // bottom safe area → give it back while the nav is off.
                      child: _BottomInset(
                        restore: navHidden,
                        padding: outer.padding.bottom,
                        viewPadding: outer.viewPadding.bottom,
                        child: MgBackGuard(shell: true, child: widget.child),
                      ),
                    ),
                    ),
                  ),
                ),
              ]),
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _chrome,
                  builder: (_, __) => ShellFabLayer(
                    location: location,
                    v2: true,
                    // Nav hidden + no dock: the body reaches the screen edge, so
                    // the strips clear the home indicator / gesture bar themselves
                    // (a visible dock already includes the safe area; with the
                    // keyboard open the bottom padding is 0 → unchanged).
                    bottomBase: 8 +
                        (_chrome.dockHeight > 0
                            ? _chrome.dockHeight
                            : (navHidden ? MediaQuery.paddingOf(context).bottom : 0)),
                    onStripsHeight: (h) => _chrome.reportStrips(h > 0 ? h + 8 : 0),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: _chrome,
                // Above a visible dock AND the strips (strips sit on the dock).
                builder: (_, __) => AnimatedPositioned(
                  duration: sticky,
                  curve: MgMotion.emphasized,
                  right: 16,
                  bottom: 12 + _chrome.dockHeight + _chrome.stripsHeight,
                  child: MgAiFab(hidden: fabHidden),
                ),
              ),
            ]),
          ),
        ),
        bottomNavigationBar: _lastNav == null
            ? null
            : MgStickySlide(
                visible: !navHidden,
                collapse: true,
                // The body's bottom edge moved: the AI button re-checks its slot.
                child: MgNavBand(folded: folded, band: outer.padding.bottom, onEnd: _chrome.scrollIdle, child: _lastNav!),
              ),
      ),
    );
  }
}

/// Puts the screen's bottom safe area back into the shell body's
/// MediaQuery while the (collapsed) nav is off.
class _BottomInset extends StatelessWidget {
  final bool restore;
  final double padding;
  final double viewPadding;
  final Widget child;
  const _BottomInset({required this.restore, required this.padding, required this.viewPadding, required this.child});

  /// Always the same widget type above [child] — the shell's navigator
  /// must never be re-parented when the nav comes and goes.
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: restore
          ? mq.copyWith(
              padding: mq.padding.copyWith(bottom: padding),
              viewPadding: mq.viewPadding.copyWith(bottom: viewPadding),
            )
          : mq,
      child: child,
    );
  }
}
