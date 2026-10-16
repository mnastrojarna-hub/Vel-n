import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'router.dart';
import 'i18n/i18n_provider.dart';
import 'banner_provider.dart';
import 'shell_banner.dart';
import 'shell_fab_layer.dart';
import 'shell_paid_listener.dart';
import 'shell_tab_action.dart';
import '../features/messages/messages_provider.dart';
import 'widgets/mg_back.dart';
import 'widgets/moto_fx.dart';

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
    // Celá sekce Místa/Trasy drží 4. tab: /routes (Místa), /routes-list
    // (seznam tras), /places-map (mapa míst), /pois (výběr bodů z editoru).
    if (location.startsWith('/routes') ||
        location.startsWith('/places-map') ||
        location.startsWith('/pois')) {
      return 3;
    }
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

    final bannerVisible = banner.valueOrNull != null && banner.valueOrNull!.enabled;

    // Unread messages badge count — nepřečtená oznámení (admin_messages.read);
    // dřívější počet vláken se nikdy neobnovil a přečtení nešlo „odkliknout“.
    final unreadCount = ref.watch(adminUnreadCountProvider);

    // When the keyboard is open we must NOT let this outer shell Scaffold
    // resize for the bottom inset — the inner screen Scaffolds (chat, profile,
    // SOS…) already do that. Two Scaffolds both reacting to the same keyboard
    // inset is what produced the empty gap above the keyboard and the
    // "bottom overflowed" / untappable send button. We let the inner screen
    // own the resize and hide the bottom nav while typing.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // Oznámení „zaplaceno po restartu" — ShellPaidListener (PM-2).
    return ShellPaidListener(child: Scaffold(
      backgroundColor: MotoGoColors.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            children: [
              // Header banner (dynamic from app_settings)
              banner.when(
                data: (b) => b != null && b.enabled
                    ? ShellHeaderBanner(text: b.text, bg: b.bg, color: b.color)
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
                  // Systémové zpět bez historie (go / záložka / deep link) →
                  // rodič obrazovky (Domů, Menu…), ne zavření appky.
                  child: MgBackGuard(shell: true, child: child),
                ),
              ),
            ],
          ),
          // Plovoucí panely (košík, rozdělaná rezervace, SOS, doklady,
          // rozjetá trasa) — stejné podmínky i pozice, viz ShellFabLayer (PM-2).
          Positioned.fill(child: ShellFabLayer(location: location)),
          // Pozn.: hlídač postupu na vyšší rank (LoyaltyLevelUpWatcher) už
          // nesedí zde, ale v MaterialApp.builder (main.dart) — je tak
          // přítomný na KAŽDÉ obrazovce, i mimo tento shell.
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
                    onTap: () => onShellTabTap(
                      context,
                      ref,
                      route: tab.route,
                      isActive: i == index,
                      isHome: i == 0,
                      location: location,
                    ),
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
    ));
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
