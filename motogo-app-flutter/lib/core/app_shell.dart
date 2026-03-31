import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'router.dart';
import 'banner_provider.dart';

/// Main app shell — bottom nav bar + optional header banner.
/// Mirrors the .phone + .bnav + .header-banner from index.html.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    _TabItem(route: Routes.home, label: 'Domů', icon: Icons.home_outlined, activeIcon: Icons.home),
    _TabItem(route: Routes.search, label: 'Rezervovat', icon: Icons.calendar_today_outlined, activeIcon: Icons.calendar_today),
    _TabItem(route: Routes.reservations, label: 'Rezervace', icon: Icons.check_box_outlined, activeIcon: Icons.check_box),
    _TabItem(route: Routes.shop, label: 'Shop', icon: Icons.shopping_bag_outlined, activeIcon: Icons.shopping_bag),
  ];

  int _currentIndex(String location) {
    if (location.startsWith('/shop') || location == Routes.cart ||
        location == Routes.checkout || location == Routes.voucher) return 3;
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

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Column(
        children: [
          // Header banner (dynamic from app_settings)
          banner.when(
            data: (b) => b != null && b.enabled
                ? _HeaderBanner(text: b.text, bg: b.bg, color: b.color)
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // Main content
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: MotoGoColors.g200, width: 1)),
        ),
        child: SafeArea(
          child: SizedBox(
            height: 80,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final tab = _tabs[i];
                final active = i == index;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (i != index) context.go(tab.route);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? MotoGoColors.green.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            active ? tab.activeIcon : tab.icon,
                            size: 26,
                            color: active ? MotoGoColors.greenDark : MotoGoColors.g400,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: active ? MotoGoColors.greenDark : MotoGoColors.g400,
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
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabItem({
    required this.route,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

/// Scrolling promo banner — matches .header-banner from CSS.
class _HeaderBanner extends StatelessWidget {
  final String text;
  final Color bg;
  final Color color;
  const _HeaderBanner({required this.text, required this.bg, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      height: 28,
      child: _MarqueeText(text: text, color: color),
    );
  }
}

/// Simple scrolling marquee — mirrors banner-scroll animation from CSS.
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
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final width = MediaQuery.of(context).size.width;
          final offset = _ctrl.value * width * 2;
          return Transform.translate(
            offset: Offset(width - offset, 0),
            child: Row(
              children: [
                _buildText(),
                const SizedBox(width: 40),
                _buildText(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildText() {
    return Text(
      widget.text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: widget.color,
        letterSpacing: 0.3,
      ),
    );
  }
}
