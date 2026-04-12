import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';
import 'booking_form_widget.dart';
import 'supabase_client.dart';
import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_ui_helpers.dart';
import '../features/booking/map_launcher.dart';
import '../features/catalog/catalog_provider.dart';
import '../features/catalog/widgets/availability_calendar.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/catalog/moto_detail_screen.dart';
import '../features/catalog/moto_search_screen.dart';
import '../features/home/home_screen.dart';
import '../features/payment/payment_screen.dart';
import '../features/payment/payment_confirmation_screen.dart';
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
import '../features/reservations/reservation_edit_screen.dart';
import '../features/reservations/protocol_screen.dart';
import '../features/shop/shop_checkout_screen.dart';
import '../features/shop/shop_screen.dart';
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
  static const String sosService = '/sos/service';
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

  return GoRouter(
    initialLocation: Routes.login,
    debugLogDiagnostics: false,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      // Use synchronous session check — avoids null during stream transitions
      final isLoggedIn = MotoGoSupabase.currentSession != null;
      final isAuthRoute = state.matchedLocation == Routes.login ||
          state.matchedLocation == Routes.register ||
          state.matchedLocation == Routes.resetPassword;

      // Logged in user trying to access login → redirect to home
      if (isLoggedIn && isAuthRoute) return Routes.home;

      // Not logged in trying to access protected route → redirect to login
      final isProtected = _authRequired.any(
        (r) => state.matchedLocation.startsWith(r.split(':').first),
      );
      if (!isLoggedIn && isProtected && !isAuthRoute) return Routes.login;

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
        path: Routes.resetPassword,
        builder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return ResetPasswordScreen(initialEmail: email);
        },
      ),
      GoRoute(
        path: Routes.success,
        builder: (context, state) => const PaymentConfirmationScreen(),
      ),
      GoRoute(
        path: Routes.docs,
        builder: (context, state) => const DocumentsScreen(),
      ),
      GoRoute(
        path: Routes.docScan,
        builder: (context, state) => const DocumentScannerScreen(),
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
            pageBuilder: (context, state) {
              return const NoTransitionPage(
                key: ValueKey('booking-debug'),
                child: BookingDebugWrapper(),
              );
            },
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
            builder: (context, state) => const MessagesScreen(),
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
            path: Routes.protocol,
            builder: (context, state) => const ProtocolScreen(),
          ),
        ],
      ),
    ],
  );
});

// ═══════════════════════════════════════════════════════════════════
// INLINE BOOKING FORM — everything in ONE file, per-section try-catch
// ═══════════════════════════════════════════════════════════════════

class _BookingDebugWrapper extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BookingDebugWrapper> createState() => _BDWState();
}

class _BDWState extends ConsumerState<_BookingDebugWrapper> {
  bool _calOpen = false;

  void _upd(BookingDraft Function(BookingDraft) fn) {
    final d = ref.read(bookingDraftProvider);
    ref.read(bookingDraftProvider.notifier).state = fn(d);
  }

  @override
  Widget build(BuildContext context) {
    final moto = ref.watch(bookingMotoProvider);
    if (moto == null) {
      return Container(color: const Color(0xFFDFF0EC),
        child: SafeArea(child: Center(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.motorcycle, size: 48,
            color: Color(0xFF8AAB99)),
          const SizedBox(height: 12),
          const Text('Nejprve vyberte motorku',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
              color: Color(0xFF0F1A14),
              decoration: TextDecoration.none)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => GoRouter.of(context).go('/search'),
            child: const Text('VYBRAT MOTORKU')),
        ]))));
    }

    final draft = ref.watch(bookingDraftProvider);
    final bd = ref.watch(priceBreakdownProvider);
    final err = ref.watch(bookingValidationErrorProvider);
    final hasDates = draft.startDate != null && draft.endDate != null;
    final dc = hasDates ? draft.dayCount : 0;
    final isKids = moto.licenseRequired == 'N';
    String f(DateTime d) => '${d.day}.${d.month}.${d.year}';

    final secs = <Widget>[];

    // HEADER
    secs.add(Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(color: Color(0xFF1A2E22),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(24))),
      child: Row(children: [
        GestureDetector(
          onTap: () => GoRouter.of(context).go(
            draft.motoId != null
                ? '/moto/${draft.motoId}' : '/search'),
          child: Container(width: 38, height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF74FB71),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back,
              size: 20, color: Colors.white))),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text('Rezervace: ${moto.model}',
            style: const TextStyle(fontSize: 15,
              fontWeight: FontWeight.w900, color: Colors.white,
              decoration: TextDecoration.none)),
          const Text('Vyplňte formulář',
            style: TextStyle(fontSize: 11, color: Colors.white54,
              decoration: TextDecoration.none)),
        ])),
      ]),
    ));

    // 1. MOTORKA
    secs.add(bookingCard(1, 'MOTORKA',
      Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(8),
          child: Image.network(moto.displayImage,
            width: 56, height: 42, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 56, height: 42,
              color: const Color(0xFFD4E8E0),
              child: const Icon(Icons.motorcycle,
                size: 20, color: Color(0xFF8AAB99))))),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(moto.model, style: const TextStyle(fontSize: 13,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.none)),
          Text('od ${moto.priceLabel}/den · záloha neúčtována',
            style: const TextStyle(fontSize: 11,
              color: Color(0xFF8AAB99),
              decoration: TextDecoration.none)),
          if (moto.branchName != null)
            Row(children: [
              const Icon(Icons.location_on, size: 12,
                color: Color(0xFFEF4444)),
              const SizedBox(width: 2),
              Flexible(child: Text(
                'Pobočka: ${moto.branchName}'
                '${moto.branchCity != null ? ", ${moto.branchCity}" : ""}',
                style: const TextStyle(fontSize: 10,
                  color: Color(0xFF8AAB99),
                  decoration: TextDecoration.none))),
            ]),
        ])),
      ])));

    // 2. DATUM
    secs.add(bookingCard(2, 'DATUM',
      Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        if (!_calOpen && hasDates)
          GestureDetector(
            onTap: () => setState(() => _calOpen = true),
            child: Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 14,
                  color: Color(0xFF1A8A18)),
                const SizedBox(width: 6),
                Text('${f(draft.startDate!)} – ${f(draft.endDate!)}',
                  style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A8A18),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    '$dc ${dc == 1 ? "den" : dc < 5 ? "dny" : "dní"}',
                    style: const TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      decoration: TextDecoration.none))),
                const Spacer(),
                const Text('UPRAVIT',
                  style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3DBA3A),
                    decoration: TextDecoration.none)),
              ]))),
        if (_calOpen || !hasDates) ...[
          const Text('Pro výběr jednoho dne klikněte dvakrát',
            style: TextStyle(fontSize: 11,
              color: Color(0xFF8AAB99),
              decoration: TextDecoration.none)),
          const SizedBox(height: 8),
          Consumer(builder: (context, ref, _) {
            final booked = ref.watch(
              bookedDatesProvider(draft.motoId ?? ''));
            return AvailabilityCalendar(
              bookedDates: booked.valueOrNull ?? [],
              selectedStart: draft.startDate,
              selectedEnd: draft.endDate,
              onRangeSelected: (s, e) {
                _upd((d) => d.copyWith(
                  startDate: () => s, endDate: () => e));
                setState(() => _calOpen = false);
              });
          }),
        ],
        if (hasDates)
          Padding(padding: const EdgeInsets.only(top: 10),
            child: Container(padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF74FB71), width: 1.5)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                const Text('Celkem za pronájem',
                  style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A6357),
                    decoration: TextDecoration.none)),
                Text('${bd.basePrice.toStringAsFixed(0)} Kč',
                  style: const TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A8A18),
                    decoration: TextDecoration.none)),
              ]))),
      ])));

    // 3. ČAS VYZVEDNUTÍ — dropdown hodiny:minuty
    { final curH = draft.pickupTime != null
          ? int.parse(draft.pickupTime!.split(':')[0]) : 9;
      final curM = draft.pickupTime != null
          ? int.parse(draft.pickupTime!.split(':')[1]) : 0;
      secs.add(bookingCard(3, 'ČAS VYZVEDNUTÍ',
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: [
          // Hours dropdown
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE8FFE8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF74FB71), width: 1.5)),
            child: DropdownButton<int>(
              value: curH,
              underline: const SizedBox(),
              dropdownColor: Colors.white,
              iconEnabledColor: const Color(0xFF1A8A18),
              iconSize: 16,
              isDense: true,
              style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F1A14)),
              items: List.generate(24, (h) => DropdownMenuItem(
                value: h,
                child: Text(h.toString().padLeft(2, '0')))),
              onChanged: (h) {
                if (h == null) return;
                final mm = curM.toString().padLeft(2, '0');
                _upd((d) => d.copyWith(
                  pickupTime: () =>
                    '${h.toString().padLeft(2, "0")}:$mm'));
              })),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(':', style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F1A14),
              decoration: TextDecoration.none))),
          // Minutes dropdown
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE8FFE8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF74FB71), width: 1.5)),
            child: DropdownButton<int>(
              value: curM,
              underline: const SizedBox(),
              dropdownColor: Colors.white,
              iconEnabledColor: const Color(0xFF1A8A18),
              iconSize: 16,
              isDense: true,
              style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F1A14)),
              items: [0, 15, 30, 45].map((m) => DropdownMenuItem(
                value: m,
                child: Text(m.toString().padLeft(2, '0')))).toList(),
              onChanged: (m) {
                if (m == null) return;
                final hh = curH.toString().padLeft(2, '0');
                _upd((d) => d.copyWith(
                  pickupTime: () =>
                    '$hh:${m.toString().padLeft(2, "0")}'));
              })),
          const SizedBox(width: 8),
          const Text('hod', style: TextStyle(fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8AAB99),
            decoration: TextDecoration.none)),
        ])));
    }

    // 4. VYZVEDNUTÍ MOTORKY
    secs.add(bookingCard(4, 'VYZVEDNUTÍ MOTORKY',
      Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        bookingRadio('Na pobočce', 'Mezná 9, Mezná', 'Zdarma',
          draft.pickupMethod == 'store',
          () => _upd((d) => d.copyWith(pickupMethod: 'store'))),
        const SizedBox(height: 6),
        bookingRadio('Přistavení na vaši adresu',
          '1 000 Kč + 40 Kč/km', 'od 1 000 Kč',
          draft.pickupMethod == 'delivery',
          () => _upd((d) => d.copyWith(pickupMethod: 'delivery'))),
        if (draft.pickupMethod == 'delivery') ...[
          const SizedBox(height: 10),
          bookingAddrTile(draft.pickupCity, draft.pickupAddress,
            () => showAddrBottomSheet(context, 'Adresa vyzvednutí',
              draft.pickupCity, draft.pickupAddress,
              (city, addr) => _upd((d) => d.copyWith(
                pickupCity: () => city, pickupAddress: () => addr)),
              onDistCalc: (km, fee) =>
                ref.read(pickupDelivFeeProvider.notifier).state = fee,
              onMapTap: (ctx) async {
                final r = await launchMapPicker(ctx);
                if (r == null) return;
                _upd((d) => d.copyWith(
                  pickupCity: () => r.city,
                  pickupAddress: () => r.address));
                ref.read(pickupDelivFeeProvider.notifier).state = r.fee;
              }),
            delivFee: ref.watch(pickupDelivFeeProvider)),
        ],
      ])));

    // 6. VRÁCENÍ MOTORKY
    secs.add(bookingCard(5, 'VRÁCENÍ MOTORKY',
      Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        bookingRadio('Na pobočce', 'Mezná 9, Mezná', 'Zdarma',
          draft.returnMethod == 'store',
          () => _upd((d) => d.copyWith(returnMethod: 'store'))),
        const SizedBox(height: 6),
        bookingRadio('Odvoz z vaší adresy',
          '1 000 Kč + 40 Kč/km', 'od 1 000 Kč',
          draft.returnMethod == 'delivery',
          () => _upd((d) => d.copyWith(returnMethod: 'delivery'))),
        if (draft.returnMethod == 'delivery') ...[
          const SizedBox(height: 10),
          bookingAddrTile(draft.returnCity, draft.returnAddress,
            () => showAddrBottomSheet(context, 'Adresa vrácení',
              draft.returnCity, draft.returnAddress,
              (city, addr) => _upd((d) => d.copyWith(
                returnCity: () => city, returnAddress: () => addr)),
              onDistCalc: (km, fee) =>
                ref.read(returnDelivFeeProvider.notifier).state = fee,
              onMapTap: (ctx) async {
                final r = await launchMapPicker(ctx);
                if (r == null) return;
                _upd((d) => d.copyWith(
                  returnCity: () => r.city,
                  returnAddress: () => r.address));
                ref.read(returnDelivFeeProvider.notifier).state = r.fee;
              }),
            delivFee: ref.watch(returnDelivFeeProvider)),
        ],
      ])));

    // 7. VÝBAVA A DOPLŇKY
    secs.add(bookingCard(6, 'VÝBAVA A DOPLŇKY',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // Free base gear
        Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8FFE8),
            borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.shield, size: 20, color: Color(0xFF1A8A18)),
            SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text('Základní výbava zdarma',
                style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A8A18),
                  decoration: TextDecoration.none)),
              Text('Helma, rukavice, bunda, kalhoty',
                style: TextStyle(fontSize: 11,
                  color: Color(0xFF4A6357),
                  decoration: TextDecoration.none)),
            ])),
            Icon(Icons.check_circle, size: 18,
              color: Color(0xFF74FB71)),
          ])),
        // Gear sizes (helmet/gloves/jacket/pants) when delivery
        if (draft.pickupMethod == 'delivery') ...[
          const SizedBox(height: 8),
          bookingGearRow('Helma', draft.helmetSize,
            (s) => _upd((d) => d.copyWith(helmetSize: () => s))),
          bookingGearRow('Rukavice', draft.glovesSize,
            (s) => _upd((d) => d.copyWith(glovesSize: () => s))),
          bookingGearRow('Bunda', draft.jacketSize,
            (s) => _upd((d) => d.copyWith(jacketSize: () => s))),
          bookingGearRow('Kalhoty', draft.pantsSize,
            (s) => _upd((d) => d.copyWith(pantsSize: () => s))),
        ],
        const SizedBox(height: 10),
        // Paid extras
        ...defaultExtras.map((item) {
          final sel = draft.extras.any((e) => e.id == item.id);
          final selExtra = sel
              ? draft.extras.firstWhere((e) => e.id == item.id)
              : null;
          final needSize = sel && item.sizes.isNotEmpty && selExtra?.size == null;
          final isDelivery = draft.pickupMethod == 'delivery';
          final isSpolujezdec = item.id == 'extra-spolujezdec';
          return GestureDetector(
            onTap: () {
              if (sel) {
                // Deselect
                final ne = List<SelectedExtra>.from(draft.extras);
                ne.removeWhere((e) => e.id == item.id);
                _upd((d) => d.copyWith(extras: ne));
              } else if (isSpolujezdec && isDelivery) {
                // Spolujezdec + delivery → multi-gear picker
                _showPassengerGearSheet(context, item);
              } else if (isDelivery && item.sizes.isNotEmpty) {
                // Boots + delivery → shoe size picker
                _showSizeDialog(context, item);
              } else {
                // Just toggle
                final ne = List<SelectedExtra>.from(draft.extras);
                ne.add(SelectedExtra(
                  id: item.id, name: item.name, price: item.price));
                _upd((d) => d.copyWith(extras: ne));
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFFE8FFE8)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? const Color(0xFF74FB71)
                      : const Color(0xFFD4E8E0),
                  width: sel ? 2 : 1)),
              child: Row(children: [
                Container(width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF74FB71)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: sel ? const Color(0xFF74FB71)
                          : const Color(0xFFD4E8E0), width: 2)),
                  child: sel ? const Icon(Icons.check,
                    size: 14, color: Colors.white) : null),
                const SizedBox(width: 10),
                Text('${item.icon ?? ""} ',
                  style: const TextStyle(fontSize: 18)),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(item.name, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none)),
                  Text(
                    sel && selExtra?.size != null
                      ? 'Velikost: ${selExtra!.size}'
                      : needSize
                        ? '⚠ Klikněte pro výběr velikosti'
                        : item.description ?? '',
                    style: TextStyle(fontSize: 10,
                      color: needSize
                        ? const Color(0xFFD97706)
                        : const Color(0xFF8AAB99),
                      decoration: TextDecoration.none)),
                ])),
                Text('+${item.price.toStringAsFixed(0)} Kč',
                  style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3DBA3A),
                    decoration: TextDecoration.none)),
              ])));
        }),
      ])));

    // CENA
    secs.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12)]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          const Text('Shrnutí ceny', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800,
            decoration: TextDecoration.none)),
          const SizedBox(height: 10),
          bookingPriceRow(
            'Motorka × $dc ${dc == 1 ? "den" : dc < 5 ? "dny" : "dní"}',
            '${bd.basePrice.toStringAsFixed(0)} Kč'),
          for (final e in draft.extras)
            bookingPriceRow(e.name,
              '+${(e.price * e.quantity).toStringAsFixed(0)} Kč'),
          if (bd.pickupDeliveryFee > 0)
            bookingPriceRow('Přistavení',
              '+${bd.pickupDeliveryFee.toStringAsFixed(0)} Kč'),
          if (bd.returnDeliveryFee > 0)
            bookingPriceRow('Odvoz',
              '+${bd.returnDeliveryFee.toStringAsFixed(0)} Kč'),
          if (bd.discountTotal > 0)
            bookingPriceRow('Sleva',
              '−${bd.discountTotal.toStringAsFixed(0)} Kč',
              color: const Color(0xFF1A8A18)),
          bookingPriceRow('✓ Záloha se neúčtuje', '0 Kč',
            subtle: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Color(0xFFD4E8E0), height: 1)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
            const Text('Celkem (cena konečná)',
              style: TextStyle(fontSize: 14,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.none)),
            Text('${bd.total.toStringAsFixed(0)} Kč',
              style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A8A18),
                decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 4),
          const Text('Cena bez DPH, nejsme plátci',
            style: TextStyle(fontSize: 9,
              color: Color(0xFF8AAB99),
              decoration: TextDecoration.none)),
        ])),
    ));

    // PROMO KÓD
    secs.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12)]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          const Row(children: [
            Icon(Icons.local_offer, size: 16,
              color: Color(0xFF1A2E22)),
            SizedBox(width: 6),
            Text('SLEVOVÝ KÓD', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A2E22),
              decoration: TextDecoration.none)),
          ]),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => showPromoBottomSheet(context,
              draft.discounts,
              (d) => _upd((dr) => dr.copyWith(
                discounts: [...dr.discounts, d])),
              (code) => _upd((dr) => dr.copyWith(
                discounts: dr.discounts.where(
                  (x) => x.code != code).toList()))),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFD4E8E0), width: 1.5)),
              child: const Row(children: [
                Icon(Icons.add_circle_outline, size: 16,
                  color: Color(0xFF8AAB99)),
                SizedBox(width: 8),
                Text('Klikněte pro zadání kódu',
                  style: TextStyle(fontSize: 12,
                    color: Color(0xFF8AAB99),
                    decoration: TextDecoration.none)),
              ]))),
          if (draft.discounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...draft.discounts.map((d) => Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.check_circle, size: 14,
                  color: Color(0xFF1A8A18)),
                const SizedBox(width: 6),
                Expanded(child: Text(d.code,
                  style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A8A18),
                    decoration: TextDecoration.none))),
                GestureDetector(
                  onTap: () => _upd((dr) => dr.copyWith(
                    discounts: dr.discounts.where(
                      (x) => x.code != d.code).toList())),
                  child: const Icon(Icons.close, size: 16,
                    color: Color(0xFF8AAB99))),
              ]))),
          ],
        ])),
    ));

    // SOUHLASY — only kids consent needed for children's bikes
    if (isKids)
      secs.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: bookingCheckbox(
          'Potvrzuji, že jsem zákonný zástupce a dětský '
          'motocykl bude provozován pod mým dohledem',
          draft.consentKids,
          (v) => _upd((d) => d.copyWith(consentKids: v)))));

    // CTA — always enabled
    secs.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(height: 52, child: ElevatedButton(
        onPressed: () => GoRouter.of(context).go('/payment'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF74FB71),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50))),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Text('POKRAČOVAT K PLATBĚ',
            style: TextStyle(fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5)),
          SizedBox(width: 8),
          Icon(Icons.arrow_forward, size: 18),
        ]))),
    ));

    secs.add(const SizedBox(height: 100));

    return Material(color: const Color(0xFFDFF0EC),
      child: SafeArea(child: Column(children: [
        Expanded(child: SingleChildScrollView(
          child: Column(children: secs))),
      ])),
    );
  }

  /// Passenger gear picker — helma, rukavice, bunda, kalhoty, boty.
  void _showPassengerGearSheet(BuildContext ctx,
      ExtraCatalogItem item) {
    final sizes = <String, String?>{
      'Helma': null, 'Rukavice': null, 'Bunda': null,
      'Kalhoty': null, 'Boty': null,
    };
    final bootSizes = ['36','37','38','39','40','41','42','43','44','45','46'];
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20,
            MediaQuery.of(c).padding.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: const Color(0xFFD4E8E0),
              borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text('Velikosti – ${item.name}',
              style: const TextStyle(fontSize: 15,
                fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ...sizes.entries.map((e) {
              final isBoot = e.key == 'Boty';
              final opts = isBoot ? bootSizes : gearSizes;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(e.key, style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6,
                    children: opts.map((s) {
                      final a = sizes[e.key] == s;
                      return GestureDetector(
                        onTap: () => ss(() =>
                          sizes[e.key] = a ? null : s),
                        child: Container(
                          width: isBoot ? 42 : 40, height: 32,
                          decoration: BoxDecoration(
                            color: a ? const Color(0xFF1A8A18)
                                : const Color(0xFFE8FFE8),
                            borderRadius: BorderRadius.circular(6)),
                          child: Center(child: Text(s,
                            style: TextStyle(fontSize: 11,
                              fontWeight: a ? FontWeight.w900
                                  : FontWeight.w600,
                              color: a ? Colors.white
                                  : const Color(0xFF0F1A14))))));
                    }).toList()),
                ]));
            }),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final sizeStr = sizes.entries
                      .where((e) => e.value != null)
                      .map((e) => '${e.key}: ${e.value}')
                      .join(', ');
                  final ne = List<SelectedExtra>.from(
                    ref.read(bookingDraftProvider).extras);
                  ne.removeWhere((e) => e.id == item.id);
                  ne.add(SelectedExtra(id: item.id,
                    name: item.name, price: item.price,
                    size: sizeStr.isNotEmpty ? sizeStr : null));
                  _upd((d) => d.copyWith(extras: ne));
                  Navigator.pop(c);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF74FB71),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50))),
                child: const Text('POTVRDIT',
                  style: TextStyle(fontWeight: FontWeight.w800)))),
          ]))),
    );
  }

  void _showSizeDialog(BuildContext ctx, ExtraCatalogItem item) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20))),
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(c).padding.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: const Color(0xFFD4E8E0),
            borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Text('Vyberte velikost – ${item.name}',
            style: const TextStyle(fontSize: 15,
              fontWeight: FontWeight.w800)),
          if (item.description != null) ...[
            const SizedBox(height: 4),
            Text(item.description!,
              style: const TextStyle(fontSize: 12,
                color: Color(0xFF8AAB99))),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8,
            children: item.sizes.map((size) =>
              GestureDetector(
                onTap: () {
                  final ne = List<SelectedExtra>.from(
                    ref.read(bookingDraftProvider).extras);
                  ne.removeWhere((e) => e.id == item.id);
                  ne.add(SelectedExtra(id: item.id,
                    name: item.name, price: item.price,
                    size: size));
                  _upd((d) => d.copyWith(extras: ne));
                  Navigator.pop(c);
                },
                child: Container(width: 52, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8FFE8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF74FB71),
                      width: 1.5)),
                  child: Center(child: Text(size,
                    style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800)))),
              )).toList()),
        ])),
    );
  }


}
// END of _BDWState
// OLD HELPERS BELOW REMOVED — now in booking_ui_helpers.dart
// KEEP THIS LINE AS EOF MARKER
