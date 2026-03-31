import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/home/home_screen.dart';
import 'placeholder_screen.dart';

/// All route paths — mirrors router.js screen IDs.
class Routes {
  Routes._();

  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/';
  static const String search = '/search';
  static const String detail = '/moto/:id';
  static const String booking = '/booking';
  static const String payment = '/payment';
  static const String success = '/success';
  static const String reservations = '/reservations';
  static const String reservationDetail = '/reservations/:id';
  static const String editReservation = '/reservations/:id/edit';
  static const String doneDetail = '/reservations/:id/done';
  static const String profile = '/profile';
  static const String messages = '/messages';
  static const String messageThread = '/messages/:id';
  static const String invoices = '/invoices';
  static const String contracts = '/contracts';
  static const String docs = '/docs';
  static const String docScan = '/docs/scan';
  static const String shop = '/shop';
  static const String shopDetail = '/shop/:id';
  static const String cart = '/cart';
  static const String checkout = '/checkout';
  static const String voucher = '/voucher';
  static const String sos = '/sos';
  static const String sosAccident = '/sos/accident';
  static const String sosBreakdown = '/sos/breakdown';
  static const String sosTheft = '/sos/theft';
  static const String sosReplacement = '/sos/replacement';
  static const String sosPayment = '/sos/payment';
  static const String sosDone = '/sos/done';
  static const String aiAgent = '/ai-agent';
  static const String protocol = '/protocol';
}

/// Screens that do NOT show bottom navigation — matches noNav in router.js.
const _noNavRoutes = {
  Routes.login,
  Routes.register,
  Routes.success,
  Routes.docs,
  Routes.docScan,
};

/// Screens that require authentication — matches _authRequired in router.js.
const _authRequired = {
  Routes.home,
  Routes.reservations,
  Routes.booking,
  Routes.payment,
  Routes.success,
  Routes.profile,
  Routes.messages,
  Routes.invoices,
  Routes.contracts,
  Routes.sos,
  Routes.sosReplacement,
  Routes.sosPayment,
  Routes.sosDone,
};

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: Routes.login,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation == Routes.login ||
          state.matchedLocation == Routes.register;

      // Logged in user trying to access login → redirect to home
      if (isLoggedIn && isAuthRoute) return Routes.home;

      // Not logged in trying to access protected route → redirect to login
      final isProtected = _authRequired.any(
        (r) => state.matchedLocation.startsWith(r.split(':').first),
      );
      if (!isLoggedIn && isProtected) return Routes.login;

      return null;
    },
    routes: [
      // Auth routes (no shell)
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: Routes.success,
        builder: (context, state) =>
            const PlaceholderScreen(title: 'Potvrzení', icon: '✅'),
      ),
      GoRoute(
        path: Routes.docs,
        builder: (context, state) =>
            const PlaceholderScreen(title: 'Doklady', icon: '📋'),
      ),
      GoRoute(
        path: Routes.docScan,
        builder: (context, state) =>
            const PlaceholderScreen(title: 'Sken dokladu', icon: '📷'),
      ),

      // Main app with bottom nav shell
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: Routes.search,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PlaceholderScreen(title: 'Rezervovat', icon: '📅'),
            ),
          ),
          GoRoute(
            path: Routes.reservations,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PlaceholderScreen(title: 'Rezervace', icon: '✅'),
            ),
          ),
          GoRoute(
            path: Routes.shop,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PlaceholderScreen(title: 'Shop', icon: '🛍️'),
            ),
          ),
          GoRoute(
            path: Routes.profile,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PlaceholderScreen(title: 'Profil', icon: '👤'),
            ),
          ),
          // Sub-routes inside shell
          GoRoute(
            path: '/moto/:id',
            builder: (context, state) =>
                PlaceholderScreen(title: 'Motorka ${state.pathParameters["id"]}', icon: '🏍️'),
          ),
          GoRoute(
            path: Routes.booking,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Rezervace', icon: '📋'),
          ),
          GoRoute(
            path: Routes.payment,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Platba', icon: '💳'),
          ),
          GoRoute(
            path: '/reservations/:id',
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Detail rezervace', icon: '📋'),
          ),
          GoRoute(
            path: '/reservations/:id/edit',
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Editace', icon: '✏️'),
          ),
          GoRoute(
            path: Routes.messages,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Zprávy', icon: '📩'),
          ),
          GoRoute(
            path: '/messages/:id',
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Vlákno', icon: '💬'),
          ),
          GoRoute(
            path: Routes.invoices,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Faktury', icon: '🧾'),
          ),
          GoRoute(
            path: Routes.contracts,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Dokumenty', icon: '📄'),
          ),
          GoRoute(
            path: '/shop/:id',
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Produkt', icon: '🛍️'),
          ),
          GoRoute(
            path: Routes.cart,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Košík', icon: '🛒'),
          ),
          GoRoute(
            path: Routes.checkout,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Pokladna', icon: '💳'),
          ),
          GoRoute(
            path: Routes.voucher,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Poukazy', icon: '🎁'),
          ),
          GoRoute(
            path: Routes.sos,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'SOS', icon: '🆘'),
          ),
          GoRoute(
            path: Routes.sosReplacement,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Náhrada', icon: '🏍️'),
          ),
          GoRoute(
            path: Routes.sosPayment,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'SOS Platba', icon: '💳'),
          ),
          GoRoute(
            path: Routes.sosDone,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'SOS hotovo', icon: '✅'),
          ),
          GoRoute(
            path: Routes.aiAgent,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'AI Agent', icon: '🤖'),
          ),
          GoRoute(
            path: Routes.protocol,
            builder: (context, state) =>
                const PlaceholderScreen(title: 'Protokol', icon: '📝'),
          ),
        ],
      ),
    ],
  );
});
