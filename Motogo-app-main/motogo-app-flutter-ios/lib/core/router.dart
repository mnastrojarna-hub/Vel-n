import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart' show rootNavigatorKey;
import 'app_shell.dart';
import 'booking_form_widget.dart';
import 'widgets/mg_back.dart';
import 'widgets/route_error_page.dart';
import 'supabase_client.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/catalog/moto_detail_screen.dart';
import '../features/catalog/moto_search_screen.dart';
import '../features/home/home_screen.dart';
import '../features/payment/payment_screen.dart';
import '../features/payment/payment_confirmation_screen.dart';
import '../features/payment/payment_result_screen.dart';
import '../features/reservations/reservations_screen.dart';
import '../features/reservations/reservation_detail_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/documents/document_scanner_screen.dart';
import '../features/documents/invoices_screen.dart';
import '../features/documents/contracts_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/messages/thread_detail_screen.dart';
import '../features/messages/ai_agent_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/permissions_screen.dart';
import '../features/reservations/reservation_edit_screen.dart';
import '../features/shop/shop_checkout_screen.dart';
import '../features/shop/shop_screen.dart';
import '../features/branches/branches_info_screen.dart';
import '../features/branches/branch_detail_screen.dart';
import '../features/shop/product_detail_screen.dart';
import '../features/shop/cart_screen.dart';
import '../features/shop/voucher_screen.dart';
import '../features/sos/sos_report_screen.dart';
import '../features/sos/sos_detail_screen.dart';
import '../features/sos/sos_replacement_screen.dart';
import '../features/sos/sos_immobile_screen.dart';
import '../features/sos/sos_theft_screen.dart';
import '../features/sos/sos_breakdown_immobile_screen.dart';
import '../features/sos/sos_service_screen.dart';
import '../features/loyalty/loyalty_ranks_screen.dart';
import '../features/routes/routes_screen.dart';
import '../features/routes/route_detail_screen.dart';
import '../features/routes/route_navigation_screen.dart';
import '../features/routes/all_pois_screen.dart';
import '../features/routes/places_map_screen.dart';
import '../features/routes/routes_map_screen.dart';
import '../features/routes/route_builder_screen.dart';
import '../features/routes/routes_model.dart' show RouteItem;
import '../features/routes/routes_provider.dart' show CustomNavArgs;
import '../features/routes/my_experiences_provider.dart' show RouteBuilderArgs;
import '../features/routes/my_experiences_screen.dart';
import '../features/routes/ride_detail_screen.dart';

/// All route paths — mirrors router.js screen IDs.
class Routes {
  Routes._();

  static const String login = '/login';
  static const String register = '/register';
  static const String resetPassword = '/reset-password';
  static const String home = '/';
  static const String search = '/search';
  static const String detail = '/moto/:id';
  static const String booking = '/booking';
  static const String payment = '/payment';
  static const String success = '/success';
  static const String paymentResult = '/payment-result';
  static const String reservations = '/reservations';
  static const String reservationDetail = '/reservations/:id';
  static const String editReservation = '/reservations/:id/edit';
  static const String doneDetail = '/reservations/:id/done';
  static const String profile = '/profile';
  static const String messages = '/messages';
  static const String messageThread = '/messages/:id';
  static const String invoices = '/invoices';
  static const String contracts = '/contracts';
  static const String branchesInfo = '/pobocky';
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
  static const String sosService = '/sos/service';
  static const String sosReplacement = '/sos/replacement';
  static const String sosPayment = '/sos/payment';
  static const String sosDone = '/sos/done';
  static const String aiAgent = '/ai-agent';
  static const String permissions = '/permissions';
  static const String loyalty = '/loyalty';
  /// PRIMÁRNÍ obrazovka sekce — od 2026-09-16 zobrazuje MÍSTA (dřív seznam
  /// tras). Spodní lišta na ni odkazuje beze změny.
  static const String routes = '/routes';
  /// Seznam doporučených tras — nově sekundární, dostupný z rozcestníku Míst.
  static const String routesList = '/routes-list';
  /// Mapa všech míst.
  static const String placesMap = '/places-map';
  static const String routesMap = '/routes-map';
  static const String routeDetail = '/routes/:id';
  static const String routeNav = '/route-nav/:id';
}

/// Bezpečná navigace „zpět" — sdílená pro všechny obrazovky.
extension MotoGoBackNav on BuildContext {
  /// Když je v zásobníku co popnout, popne (běžné „zpět"). Když ne (na
  /// obrazovku se přišlo přes `context.go`, deep link, FAB nebo děkovací
  /// stránku), přejde o úroveň výš na [fallback] — šipka tak nikdy neuvízne
  /// na prázdném zásobníku ani neskončí na „Restartujte aplikaci".
  void backOr(String fallback) {
    if (canPop()) {
      pop();
    } else {
      go(fallback);
    }
  }

  /// Otevře obrazovku ze SPODNÍ LIŠTY (AppShell). Leží-li navrchu obrazovka
  /// MIMO shell (Moje zážitky, navigace, doklady, děkovačka…), push by v
  /// go_routeru 13 zdvojil shell (duplicitní klíč stránky → rozbitá obrazovka
  /// bez cesty zpět). Pak `go` — zpět vede přes MgBackGuard na rodiče.
  void pushOrGo(String location, {Object? extra}) {
    var topInShell = true;
    try {
      topInShell = GoRouter.of(this).routerDelegate.currentConfiguration.matches.last
          is ShellRouteMatch;
    } catch (_) {}
    if (topInShell) {
      push(location, extra: extra);
    } else {
      go(location, extra: extra);
    }
  }
}

/// Stránka otevíraná push: na iPhonu běžná (MaterialPage → funguje swipe zpět
/// od levého okraje), na Androidu beze změny okamžitý přechod (systémové zpět
/// tam funguje vždy). Dřív NoTransitionPage všude → na iPhonu jen šipka.
Page<void> _swipeBackPage(LocalKey key, Widget child) =>
    defaultTargetPlatform == TargetPlatform.iOS
        ? MaterialPage<void>(key: key, child: child)
        : NoTransitionPage<void>(key: key, child: child);

/// Screens that do NOT show bottom navigation — matches noNav in router.js.
const _noNavRoutes = {
  Routes.login,
  Routes.register,
  Routes.resetPassword,
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
  Routes.sosAccident,
  Routes.sosBreakdown,
  Routes.sosTheft,
  Routes.sosService,
  Routes.sosReplacement,
  Routes.sosPayment,
  Routes.sosDone,
  Routes.checkout,
};

/// Notifier that triggers GoRouter redirect re-evaluation on auth changes.
/// Unlike ref.watch, this does NOT recreate the GoRouter instance —
/// it only re-runs the redirect function, preserving navigation state.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authNotifier = _AuthNotifier(ref);

  // Import rootNavigatorKey from main.dart for push notification deep links
  final navKey = rootNavigatorKey;

  return GoRouter(
    navigatorKey: navKey,
    initialLocation: Routes.login,
    debugLogDiagnostics: false,
    refreshListenable: authNotifier,
    // Neznámý / zastaralý odkaz → srozumitelná stránka s cestou Domů (dřív
    // anglická stránka go_routeru se syrovou výjimkou a bez zpět).
    errorBuilder: (context, state) => RouteErrorPage(state: state),
    redirect: (context, state) {
      // App Link https://motogo24.cz/app/… → stejná obrazovka bez prefixu.
      final p = state.uri.path;
      if (p == '/app' || p.startsWith('/app/')) {
        final rest = p.substring(4);
        final q = state.uri.hasQuery ? '?${state.uri.query}' : '';
        return '${rest.isEmpty ? Routes.home : rest}$q';
      }
      // Use synchronous session check — avoids null during stream transitions
      final isLoggedIn = MotoGoSupabase.currentSession != null;
      final isAuthRoute = state.matchedLocation == Routes.login ||
          state.matchedLocation == Routes.register ||
          state.matchedLocation == Routes.resetPassword;

      // Logged in user trying to access login → redirect to home.
      // Výjimka: obnova hesla — ověřený kód zákazníka přihlásí („recovery"
      // session), ale krok 3 (nové heslo) musí ještě proběhnout.
      if (isLoggedIn &&
          isAuthRoute &&
          !(state.matchedLocation == Routes.resetPassword &&
              AuthService.recoveryInProgress)) {
        return Routes.home;
      }

      // Not logged in trying to access protected route → redirect to login
      final isProtected = _authRequired.any((r) {
        if (r == '/') return state.matchedLocation == '/';
        final prefix = r.split(':').first;
        return state.matchedLocation.startsWith(prefix);
      });
      if (!isLoggedIn && isProtected && !isAuthRoute) return Routes.login;

      return null;
    },
    routes: [
      // Auth routes (no shell)
      GoRoute(
        path: Routes.login,
        builder: (context, state) => LoginScreen(initialEmail: state.uri.queryParameters['email']),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) =>
            MgBackGuard(child: RegisterScreen(initialEmail: state.uri.queryParameters['email'])),
      ),
      GoRoute(
        path: Routes.resetPassword,
        builder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return MgBackGuard(child: ResetPasswordScreen(initialEmail: email));
        },
      ),
      GoRoute(
        path: Routes.success,
        builder: (context, state) =>
            const MgBackGuard(child: PaymentConfirmationScreen()),
      ),
      GoRoute(
        path: Routes.paymentResult,
        builder: (context, state) => const MgBackGuard(child: PaymentResultScreen()),
      ),
      GoRoute(
        path: Routes.docs,
        builder: (context, state) => const MgBackGuard(child: DocumentsScreen()),
      ),
      GoRoute(
        path: Routes.docScan,
        builder: (context, state) => MgBackGuard(
          child: DocumentScannerScreen(
            scanMode: state.uri.queryParameters['mode'],
          ),
        ),
      ),

      // Navigace trasy — fullscreen, BEZ spodní lišty
      GoRoute(
        path: '/route-nav/:id',
        builder: (context, state) => MgBackGuard(
            child: RouteNavigationScreen(routeId: state.pathParameters['id']!)),
      ),

      // Katalog všech bodů zájmu napříč trasami — vlastní vyjížďka
      GoRoute(
        path: '/pois',
        builder: (context, state) {
          final ids = state.extra is Set<String> ? state.extra as Set<String> : null;
          return MgBackGuard(child: AllPoisScreen(initialSelected: ids));
        },
      ),

      // Editor trasy — přidat/přehazovat zastávky, profil, živý náhled.
      // Extra: RouteItem (z detailu trasy) NEBO RouteBuilderArgs (uložená
      // trasa z Mých zážitků — nese explicitní zastávky vč. bodů zájmu).
      GoRoute(
        path: '/route-build',
        builder: (context, state) {
          final e = state.extra;
          // Bez extra (obnova procesu / deep link) → Místa, ne pád na cast.
          if (e is RouteBuilderArgs) {
            return MgBackGuard(
                child: RouteBuilderScreen(route: e.route, initialStops: e.stops));
          }
          if (e is! RouteItem) return RouteErrorPage(state: state);
          return MgBackGuard(child: RouteBuilderScreen(route: e));
        },
      ),

      // Moje zážitky — uložené trasy + objevená místa (osobní deník jezdce)
      GoRoute(
        path: '/my-experiences',
        builder: (context, state) => const MgBackGuard(child: MyExperiencesScreen()),
      ),

      // Detail projeté jízdy (stopa na mapě, zastávky s fotkami, sdílení)
      GoRoute(
        path: '/ride/:id',
        builder: (context, state) => MgBackGuard(
          child: RideDetailScreen(
            rideId: state.pathParameters['id'] ?? '',
            siblingIds:
                state.extra is List<String> ? state.extra as List<String> : const [],
          ),
        ),
      ),

      // Navigace přes vlastní (zákazníkem složenou) trasu z vybraných POI
      GoRoute(
        path: '/route-nav-custom',
        builder: (context, state) {
          final e = state.extra;
          if (e is CustomNavArgs) {
            return MgBackGuard(
                child: RouteNavigationScreen.custom(route: e.route, profile: e.profile));
          }
          if (e is! RouteItem) return RouteErrorPage(state: state);
          return MgBackGuard(child: RouteNavigationScreen.custom(route: e));
        },
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
              child: MotoSearchScreen(),
            ),
          ),
          GoRoute(
            path: Routes.reservations,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReservationsScreen(),
            ),
          ),
          GoRoute(
            path: Routes.shop,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ShopScreen(),
            ),
          ),
          GoRoute(
            path: Routes.profile,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),
          // Sub-routes inside shell
          GoRoute(
            path: '/moto/:id',
            builder: (context, state) =>
                MotoDetailScreen(motoId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.booking,
            pageBuilder: (context, state) => _swipeBackPage(
              const ValueKey('booking-debug'),
              const BookingDebugWrapper(),
            ),
          ),
          GoRoute(
            path: Routes.payment,
            builder: (context, state) => const PaymentScreen(),
          ),
          GoRoute(
            path: '/reservations/:id',
            builder: (context, state) =>
                ReservationDetailScreen(bookingId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/reservations/:id/edit',
            builder: (context, state) =>
                ReservationEditScreen(bookingId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.messages,
            // ?n=<admin_messages.id> z push notifikace → zprávu rozbalit a označit přečtenou
            builder: (context, state) => MessagesScreen(focusId: state.uri.queryParameters['n']),
          ),
          GoRoute(
            path: '/messages/:id',
            builder: (context, state) =>
                ThreadDetailScreen(threadId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.invoices,
            builder: (context, state) => const InvoicesScreen(),
          ),
          GoRoute(
            path: Routes.contracts,
            builder: (context, state) => const ContractsScreen(),
          ),
          GoRoute(
            path: Routes.branchesInfo,
            builder: (context, state) => const BranchesInfoScreen(),
          ),
          GoRoute(
            path: '/pobocky/:index',
            builder: (context, state) => BranchDetailScreen(
                index: int.tryParse(state.pathParameters['index'] ?? '') ?? 0),
          ),
          GoRoute(
            path: '/shop/:id',
            builder: (context, state) =>
                ProductDetailScreen(productId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.cart,
            builder: (context, state) => const CartScreen(),
          ),
          GoRoute(
            path: Routes.checkout,
            builder: (context, state) => const ShopCheckoutScreen(),
          ),
          GoRoute(
            path: Routes.voucher,
            builder: (context, state) => const VoucherScreen(),
          ),
          GoRoute(
            path: Routes.sos,
            builder: (context, state) => const SosReportScreen(),
          ),
          GoRoute(
            path: Routes.sosAccident,
            builder: (context, state) => const SosImmobileScreen(),
          ),
          GoRoute(
            path: Routes.sosBreakdown,
            builder: (context, state) => const SosBreakdownImmobileScreen(),
          ),
          GoRoute(
            path: Routes.sosTheft,
            builder: (context, state) => const SosTheftScreen(),
          ),
          GoRoute(
            path: Routes.sosService,
            builder: (context, state) => const SosServiceScreen(),
          ),
          GoRoute(
            path: Routes.sosReplacement,
            builder: (context, state) => const SosReplacementScreen(),
          ),
          GoRoute(
            path: Routes.sosPayment,
            builder: (context, state) => const PaymentScreen(),
          ),
          GoRoute(
            path: Routes.sosDone,
            builder: (context, state) => const SosDetailScreen(),
          ),
          GoRoute(
            path: Routes.aiAgent,
            builder: (context, state) => const AiAgentScreen(),
          ),
          GoRoute(
            path: Routes.permissions,
            builder: (context, state) => const PermissionsScreen(),
          ),
          GoRoute(
            path: Routes.loyalty,
            builder: (context, state) => const LoyaltyRanksScreen(),
          ),
          // PROHOZENO 2026-09-16 (zadání uživatele): tab v hlavním menu
          // otevírá MÍSTA jako primární obsah; seznam tras se přesunul na
          // /routes-list, tedy tam, kde byl dřív vstup do bodů zájmu.
          // Obě obrazovky jsou UVNITŘ shellu, takže si drží spodní lištu —
          // dřív byl katalog bodů zájmu mimo shell a lišta na něm mizela.
          GoRoute(
            path: Routes.routes,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AllPoisScreen(asTab: true),
            ),
          ),
          GoRoute(
            path: Routes.routesList,
            pageBuilder: (context, state) =>
                _swipeBackPage(state.pageKey, const RoutesScreen()),
          ),
          GoRoute(
            path: Routes.placesMap,
            builder: (context, state) => const PlacesMapScreen(),
          ),
          GoRoute(
            path: Routes.routesMap,
            builder: (context, state) => const RoutesMapScreen(),
          ),
          GoRoute(
            path: '/routes/:id',
            builder: (context, state) =>
                RouteDetailScreen(
              routeId: state.pathParameters['id']!,
              // Sousedi pro listování swipem — seznam je posílá přes extra,
              // takže odpovídá tomu, co měl uživatel zrovna vyfiltrované.
              siblingIds:
                  state.extra is List<String> ? state.extra as List<String> : const [],
            ),
          ),
        ],
      ),
    ],
  );
});
