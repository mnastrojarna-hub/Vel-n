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
import '../chrome/mg_top_banner.dart';
import '../chrome/v2_nav_bar.dart';
import '../tokens/mg_colors.dart';
import 'shell_nav_map.dart';

/// The v2 app shell (PLAN §1.10): same body handling as `AppShell`
/// (`MgBackGuard(shell: true)`, banner, keyboard), the SAME floating panels
/// (`ShellFabLayer`, as v2 status strips) and paid-after-restart notice
/// (`ShellPaidListener`), plus the 5-tab [V2NavBar] (hidden in focused
/// flows / with the keyboard) and the floating AI button. Tab taps go
/// through the shared `onShellTabTap` (payment-running confirm, Home reset).
/// Location is read from the router delegate, so pushed routes count too.
class AppShellV2 extends ConsumerStatefulWidget {
  final Widget child;
  const AppShellV2({super.key, required this.child});

  @override
  ConsumerState<AppShellV2> createState() => _AppShellV2State();
}

class _AppShellV2State extends ConsumerState<AppShellV2> {
  final MgShellChrome _chrome = MgShellChrome();
  GoRouter? _router;
  String _location = '/';

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
    if (loc != _location) setState(() => _location = loc);
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
    final navHidden = keyboardOpen || v2NavHiddenFor(path);
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

    return ShellPaidListener(
      child: Scaffold(
        backgroundColor: MgColors.canvas,
        resizeToAvoidBottomInset: false,
        body: MgChromeScope(
          chrome: _chrome,
          navVisible: !navHidden,
          fabVisible: !fabHidden,
          child: Stack(children: [
            Column(children: [
              // v2 jednořádkový banner (marquee; při omezení pohybu statický
              // řádek, klepnutí = celý text) — stejný jako v hlavičce Domů.
              if (topBanner) MgTopBanner(text: banner.valueOrNull!.text, band: true),
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: topBanner,
                  child: NotificationListener<ScrollEndNotification>(
                    onNotification: _onScroll,
                    child: MgBackGuard(shell: true, child: widget.child),
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
                  bottomBase: 8 + _chrome.dockHeight,
                  onStripsHeight: (h) => _chrome.reportStrips(h > 0 ? h + 8 : 0),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: _chrome,
              // Above a visible dock AND the strips (strips sit on the dock).
              builder: (_, __) => Positioned(
                right: 16,
                bottom: 12 + _chrome.dockHeight + _chrome.stripsHeight,
                child: MgAiFab(hidden: fabHidden),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: navHidden
            ? null
            : V2NavBar(
                activeIndex: v2TabIndexFor(path),
                onTap: _onTab,
                profileBadge: unread,
                bookingsNeedAction: needsAction,
              ),
      ),
    );
  }
}
