import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/theme.dart';
import '../../core/currency.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/i18n/app_lang.dart';
import '../../core/debug_logger.dart';
import '../../core/supabase_client.dart';
import '../../core/pending_booking_fab_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../auth/auth_provider.dart' show profileProvider;
import '../booking/booking_provider.dart';
import '../booking/booking_models.dart';
import '../booking/widgets/price_summary.dart';
import '../reservations/reservation_provider.dart' show releaseDoorCodes, reservationsProvider, reservationByIdProvider;
import 'booking_upsell_provider.dart';
import '../../core/feature_flags.dart';
import '../../core/booking_rules.dart';
import '../../core/widgets/pickup_location_link.dart';
import 'stripe_service.dart';
import 'payment_provider.dart';
import 'payment_error_mapper.dart';
import 'email_service.dart';
import 'invoice_service.dart';
import 'widgets/moto_gallery_card.dart';
import 'widgets/upsell_section.dart';
import 'widgets/saved_card_preview.dart';
import 'widgets/payment_header_widgets.dart';
import 'widgets/payment_error_sheet.dart';
import 'widgets/card_payment_sheet.dart';
import '../../core/payment_pending_marker.dart';
import '../../core/paid_change_queue.dart';
import '../../core/paid_change_apply.dart' show applyExtrasOnce, applyGearOnce, gearColumnsOf;
import '../../core/offline_guard.dart' show OfflineGuard;
import 'card_minimum.dart';
import 'net_error.dart';
import 'paid_change_api.dart' show piIdFromClientSecret;
import 'paid_change_outcomes.dart';
import 'payment_refusals.dart';
import 'payment_ui_helpers.dart';
import 'payment_verify.dart';
import 'widgets/card_rounding_note.dart';

part 'payment_screen_problems.dart';
part 'payment_screen_changes.dart';

/// Proč se nepodařilo založit koncept rezervace (určuje hlášku a akci).
enum _DraftKind { motoTaken, trailerTaken, network, auth, input, unknown }

/// Payment screen — rich summary with motorcycle gallery, price breakdown,
/// upsells, and native Stripe Payment Sheet (no browser redirect).
///
/// Supports all flow types: booking, edit surcharge, SOS, shop.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> with WidgetsBindingObserver {
  bool _processing = false;
  /// Vypršel čas na zaplacení → tlačítko „Zaplatit" je zamčené.
  bool _expired = false;
  /// Částka potvrzená serverem („Cena se změnila" / zbytek po slevě).
  double? _serverAmount;
  /// PaymentIntent právě běžícího POKUSU (ověření stavu po nejasné chybě).
  /// Každý pokus ho nuluje — intent opuštěného pokusu nesmí rozhodovat.
  String? _activeClientSecret;
  /// Id PaymentIntentu běžícího pokusu (klíč trvalé fronty doplatků, D6).
  String? _activePiId;
  /// Doplatek do 1 Kč: server změnu zapsal bez platby (D1).
  bool _waivedApplied = false;
  /// Zbytek do 1 Kč server odpustit nemůže (`waiver_unverified`) → platí se
  /// 15 Kč s dorovnáním (D1); zákazník to potvrdil tlačítkem „Zaplatit 15 Kč".
  bool _forceMinCharge = false;
  /// Platba mohla odejít bance (stržení uložené karty, odeslaný kartový
  /// sheet, ověřování nejistého výsledku). Jen pak „zpět" nastaví značku a
  /// vede na „Platba se ověřuje"; dokud se zakládá koncept / intent, odchod
  /// nic nestrhne.
  bool _submitted = false;
  /// Ověřuje se výsledek platby → tlačítko říká „Ověřujeme platbu…".
  bool _verifying = false;
  /// Během ověřování selhalo spojení → „Platba se ověřuje" řekne pravý
  /// důvod (spojení), ne „banka potvrzuje".
  bool _netTrouble = false;
  String? _pendingBookingId;
  String? _pendingOrderId;
  int _attempts = 0;
  Timer? _countdownTimer;
  late DateTime _deadline;
  String _timeRemaining = '';
  // Idempotentní pojistka — flow se smí dokončit (děkovací stránka) jen jednou,
  // i kdyby se sešel úspěch z Payment Sheetu a recovery po app-resume zároveň.
  bool _completed = false;

  PaymentContext? _ctx;

  // Notifiery zachycené PŘEDEM (v initState), aby je šlo bezpečně použít v
  // dispose. `ref.read` v dispose Riverpod zakazuje → dřív padalo
  // „Cannot use ref after the widget was disposed" → rozbitý strom widgetů →
  // „Restartujte aplikaci" po odchodu z platby (typicky 100% sleva / děkovačka).
  StateController<bool>? _fabNotifier;
  StateController<PaymentContext?>? _ctxNotifier;
  StateController<bool>? _processingNotifier;

  /// setState pro rozšíření v `payment_screen_problems.dart` (part).
  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  /// Běží platba → zamkne tlačítko i odchod (šipka, záložky AppShellu).
  void _setProcessing(bool v) {
    _set(() {
      _processing = v;
      if (!v) {
        _submitted = false;
        _verifying = false;
      }
    });
    // Záložky AppShellu se ptají jen tehdy, když platba mohla odejít (nebo
    // se dopisuje zaplacená změna) — zakládání konceptu nic nestrhne.
    _processingNotifier?.state = v && (_submitted || _completed);
  }

  /// Platba mohla odejít bance → odchod jen s potvrzením (šipka i záložky).
  void _markSubmitted() {
    _submitted = true;
    if (_processing) _processingNotifier?.state = true;
  }

  /// Výsledek platby se ověřuje (tlačítko + trvalý řádek „neplať znovu").
  void _markVerifying() {
    _markSubmitted();
    _set(() => _verifying = true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fabNotifier = ref.read(paymentScreenActiveProvider.notifier);
    _ctxNotifier = ref.read(paymentContextProvider.notifier);
    _processingNotifier = ref.read(paymentProcessingProvider.notifier);
    _ctx = ref.read(paymentContextProvider);
    // Návrat k ROZDĚLANÉ rezervaci musí dopočítat zbytek serverového okna,
    // ne spustit nových 30 minut — jinak appka slibuje čas, který server
    // už nedrží, a rezervaci mezitím zruší cron.
    final createdAt = _ctx?.bookingCreatedAt;
    _deadline = createdAt != null
        ? createdAt.add(paymentTimeoutDuration)
        : DateTime.now().add(paymentTimeoutDuration);
    _timeRemaining = _fmtRemaining(_deadline.difference(DateTime.now()));
    _startCountdown();
    if (_ctx != null) {
      _pendingBookingId = _ctx!.bookingId;
      _pendingOrderId = _ctx!.orderId;
    }
    // Signalizuj AppShellu, že jsme na platbě → skryje plovoucí FAB panely.
    // (Route-string check nestačí — na /payment se naviguje přes push, viz
    // paymentScreenActiveProvider.) Nastavujeme po prvním frame, aby se
    // nemodifikoval provider během buildu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(paymentScreenActiveProvider.notifier).state = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    // Platbu opouštíme → FAB panely se zase smí zobrazit + vyčisti kontext
    // platby. POZOR: v dispose se NESMÍ použít `ref` (Riverpod hodí
    // „Cannot use ref after the widget was disposed" → rozbitý strom widgetů →
    // „Restartujte aplikaci"). Proto používáme notifiery zachycené v initState
    // a zápis odkládáme až po framu (mimo build/finalize fázi).
    final fabNotifier = _fabNotifier;
    final ctxNotifier = _ctxNotifier;
    final processingNotifier = _processingNotifier;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fabNotifier?.state = false;
      ctxNotifier?.state = null;
      processingNotifier?.state = false;
    });
    super.dispose();
  }

  /// Pojistka proti uvíznutí mimo nativní Payment Sheet.
  ///
  /// Některé platební metody otevřou externí prohlížeč/okno (typicky Stripe
  /// Link → `checkout.link.com`, Google Pay, 3DS). Pokud tam zákazník uvízne
  /// nebo se redirect zpět do appky nepovede, appka se po návratu do popředí
  /// jen probudí — bez výsledku z Payment Sheetu. Platba přitom mohla na straně
  /// Stripe reálně proběhnout (webhook označí rezervaci jako `paid`).
  ///
  /// Při každém návratu appky do popředí proto ověříme stav rezervace/objednávky
  /// v DB. Když je už zaplaceno, dotáhneme flow na děkovací stránku, aby zákazník
  /// nikdy nezůstal v nejistotě „zaplaceno / nezaplaceno" ani bez potvrzení.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recoverPaymentOnResume();
    }
  }

  Future<void> _recoverPaymentOnResume() async {
    if (_completed) return;
    final bookingId = _pendingBookingId;
    final orderId = _pendingOrderId;
    if (bookingId == null && orderId == null) return;

    bool paid = false;
    if (orderId != null) {
      paid = await StripeService.pollOrderPaymentStatus(
        orderId,
        maxAttempts: 2,
        interval: const Duration(seconds: 1),
      );
    } else if (_ctx?.flowType == PaymentFlowType.extension) {
      // DOPLATEK na ÚPRAVĚ rezervace běží nad UŽ ZAPLACENOU rezervací, takže
      // `bookings.payment_status` je 'paid' už z původní platby — NELZE ji použít
      // jako důkaz, že doplatek prošel (jinak appka po „zpět"/nepotvrzené G Pay
      // ukáže falešný úspěch). Realitu ověříme tím, že se doplatková ZMĚNA reálně
      // promítla do rezervace (webhook applyExtensionChange zapíše nový
      // total_price). Dokud se total_price nezměnil na očekávaný, doplatek
      // NEPROBĚHL → žádný úspěch.
      // Doplatek do 1 Kč se neplatí (nová cena = stará) → podle ceny nic nepoznáš.
      final expected = _expectedEditTotal;
      if (expected != null && bookingId != null && !_cardFor(_ctx!.amount).isWaive) {
        paid = await StripeService.pollBookingTotal(bookingId, expected,
            maxAttempts: 1);
      }
    } else if (bookingId != null) {
      paid = await StripeService.pollBookingPaymentStatus(
        bookingId,
        maxAttempts: 2,
        interval: const Duration(seconds: 1),
      );
    }

    if (!mounted || _completed) return;
    if (paid) {
      debugPrint('[Payment] resume recovery — platba potvrzena v DB, dokončuji flow');
      _onPaymentSuccess();
    }
  }

  // -- Helpers --

  bool get _isNewBooking => _ctx == null;
  String get _stripeType => _ctx?.flowType.name ?? 'booking';

  /// Druh platby pro texty a akce chybových stavů.
  PayFlow get _flow {
    final c = _ctx;
    if (c == null) return PayFlow.booking;
    switch (c.flowType) {
      case PaymentFlowType.extension:
        return c.pendingEditChanges?['_swap_commit'] is Map
            ? PayFlow.swap
            : PayFlow.edit;
      case PaymentFlowType.shop:
        return PayFlow.shop;
      default:
        return PayFlow.resume;
    }
  }

  /// Id pro lokální značku „platba odeslána" (objednávka / rezervace).
  String? get _markerId => _pendingOrderId ?? _pendingBookingId;

  /// Druh platby pro značku: doplatek úpravy / výměny běží nad UŽ zaplacenou
  /// rezervací → po restartu appky se nesmí ověřit podle `payment_status`.
  String get _markerKind {
    if (_pendingOrderId != null) return PaymentMarkerKind.order;
    switch (_ctx?.flowType) {
      case PaymentFlowType.extension:
        return _flow == PayFlow.swap ? PaymentMarkerKind.swap : PaymentMarkerKind.edit;
      case PaymentFlowType.sos:
        return PaymentMarkerKind.sos;
      default:
        return PaymentMarkerKind.booking;
    }
  }

  /// Značka „platba odeslána" i s druhem platby a (u úpravy) novou cenou.
  Future<void> _setMarker({String? clientSecret, bool fresh = false}) =>
      PaymentPendingMarker.set(_markerId,
          clientSecret: clientSecret,
          fresh: fresh,
          kind: _markerKind,
          expectedTotal: _expectedEditTotal);

  /// Nová cena rezervace po zaplaceném doplatku úpravy (důkaz zaplacení) —
  /// i s dorovnáním na minimální platbu kartou, které zapisuje server (D1).
  double? get _expectedEditTotal {
    final t = (_ctx?.pendingEditChanges?['total_price'] as num?)?.toDouble();
    if (t == null) return null;
    return t + _cardFor(_ctx?.amount ?? 0).rounding;
  }

  /// Minimum karty pro tuhle platbu (D1) — i s vynucenými 15 Kč u zbytku do
  /// 1 Kč, který server odpustit nemůže ([_forceMinCharge]).
  CardCharge _cardFor(num due) => cardCharge(due, forceMin: _forceMinCharge);

  /// Kolik se strhne kartou (minimum 15 Kč, do 1 Kč nic — D1).
  double get _charge => _cardFor(_amount).charge.toDouble();

  /// Úprava rezervace (návrat „Načíst znovu" / „Upravit adresu").
  String get _editRoute => _pendingBookingId != null
      ? '/reservations/$_pendingBookingId/edit'
      : Routes.reservations;

  /// Kam vede „zpět", když není kam popnout (deep link, FAB, obnovení):
  /// úprava → detail rezervace, rozdělaná/obnovená rezervace → Rezervace,
  /// nová rezervace → formulář.
  String get _backFallback {
    switch (_ctx?.flowType) {
      case null:
        return Routes.booking;
      case PaymentFlowType.extension:
        return _pendingBookingId != null
            ? '/reservations/$_pendingBookingId'
            : Routes.reservations;
      case PaymentFlowType.shop:
        return Routes.cart;
      case PaymentFlowType.sos:
        return Routes.sos;
      case PaymentFlowType.booking:
        return Routes.reservations;
    }
  }

  /// Kompaktní payload doplatkové změny pro Stripe metadata (server-side apply
  /// ve webhook-receiveru — změna se uloží, i když je appka po platbě zabita).
  /// Vynechává objemná pole (modification_history, original_*), aby se vešel
  /// do 500znakového limitu Stripe metadat; ta si server odvodí/zapíše sám.
  Map<String, dynamic>? get _extensionChangePayload {
    if (_ctx?.flowType != PaymentFlowType.extension) return null;
    final src = _ctx?.pendingEditChanges;
    if (src == null || src.isEmpty) return null;
    // Výměna motorky: kompaktní `_swap` metadata → webhook provede COMMIT
    // server-side, i když je appka po platbě zabita (pojistka k `_swap_commit`).
    final swapCommit = src['_swap_commit'];
    if (swapCommit is Map) {
      return {
        '_swap': {
          'm': swapCommit['p_new_moto_id'],
          'd': swapCommit['p_swap_date'],
          't': swapCommit['p_swap_time'],
        },
      };
    }
    const keep = {
      'start_date', 'end_date', 'moto_id', 'pickup_method', 'pickup_address',
      'return_method', 'return_address', 'pickup_time', 'return_time',
      'total_price', 'discount_amount', 'delivery_fee', 'extras_price',
      'loyalty_discount_amount',
      'pickup_lat', 'pickup_lng', 'return_lat', 'return_lng',
      // přiznaná late sleva (storno krátí získanou slevu, 20261001h) — webhook
      // ji použije jako strop přepočtu, jinak by zapsal plnou slevu
      'late_pickup_discount_amount',
    };
    // Místo smí nést i explicitní NULL (přepnutí na pobočku maže adresu, nová
    // adresa bez GPS maže staré souřadnice) — webhook ho po platbě zapíše.
    const nullable = {
      'pickup_address', 'return_address',
      'pickup_lat', 'pickup_lng', 'return_lat', 'return_lng',
    };
    final out = <String, dynamic>{};
    for (final e in src.entries) {
      if (keep.contains(e.key) && (e.value != null || nullable.contains(e.key))) out[e.key] = e.value;
    }
    // Výchozí stav změny (`_base`, kompaktní klíče) — server kontrola
    // zastaralého stavu + historie úpravy pro rozdílový doklad.
    final base = src['_base'];
    if (base is Map && base.isNotEmpty) out['_base'] = base;
    return out.isEmpty ? null : out;
  }

  /// Částka za REZERVACI / doplatek podle serveru (bez doprodeje z e-shopu).
  /// Cena ověřená serverem má přednost (zákazník ji výslovně potvrdil).
  double get _bookingDue {
    final server = _serverAmount;
    if (server != null) return server;
    return _ctx != null ? _ctx!.amount : ref.read(priceBreakdownProvider).total;
  }

  /// Doprodej z e-shopu se k platbě nové rezervace přibalí, jen když rezervace
  /// sama minimum karty splňuje (≥ 15 Kč): server ho bere jako částku NAVÍC nad
  /// cenou rezervace a minimum posuzuje jen na rezervaci. Zdarma / do 1 Kč /
  /// pod 15 Kč by se odpuštění či dorovnání rezervace smíchalo s doprodejem
  /// (strhlo by se jiné, než ukazují doklady) → doprodej se nepřibalí ani
  /// neobjedná (D1; doprodej je zatím vypnutý, D7).
  bool get _upsellBundled =>
      _isNewBooking &&
      ref.read(bookingUpsellProvider).isNotEmpty &&
      cardCharge(_bookingDue).kind == CardChargeKind.normal;

  /// Celkem k zaplacení: rezervace + přibalený doprodej.
  double get _amount =>
      _bookingDue + (_upsellBundled ? ref.read(bookingUpsellProvider.notifier).total : 0);

  String get _displayLabel {
    if (_ctx != null) return _ctx!.label;
    return t(context).tr('bookingReservation');
  }

  /// „M:SS“ ze zbývajícího času (záporný = 0:00).
  static String _fmtRemaining(Duration d) {
    if (d.isNegative) return '0:00';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        // Běžící platbu (karta, 3DS, ověření) časovač nepřeruší — výsledek
        // doběhne; vypršení se vyhodnotí až potom.
        if (_processing || _completed) return;
        _countdownTimer?.cancel();
        setState(() {
          _timeRemaining = t(context).tr('timeExpired');
          _expired = true;
        });
        _onTimeout();
        return;
      }
      setState(() => _timeRemaining = _fmtRemaining(remaining));
    });
  }

  // -- Draft booking (new booking only) --

  String? _draftError;
  _DraftKind _draftKind = _DraftKind.unknown;

  /// Vytvoří koncept rezervace. Narazí-li na vlastní nezaplacený koncept téže
  /// motorky (zákazník se vrátil z platby a jde znovu), starý zruší a zkusí to
  /// ještě jednou — dřív to končilo „neznámou chybou" až 30 minut. Když na
  /// starý koncept právě běží platba, ukáže „Platba se ověřuje" (žádná druhá).
  Future<String?> _createDraftWithRecovery() async {
    _draftError = null;
    _draftKind = _DraftKind.unknown;
    final id = await _createDraftBooking();
    if (id != null || !mounted) return id;
    if (_draftKind == _DraftKind.auth && MotoGoSupabase.currentUser != null) {
      // Prošlý přístupový token: zkus přihlášení obnovit a zápis jednou
      // zopakovat — zákazník nemusí kvůli tomu nic dělat.
      try {
        await MotoGoSupabase.client.auth
            .refreshSession()
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        // Obnovu shodila síť (slabé LTE, offline) → „zkontroluj připojení",
        // ne „Přihlásit" (to by zákazníka zbytečně odhlásilo).
        if (authRefreshNetworkFailure(e) &&
            MotoGoSupabase.currentSession != null) {
          _draftKind = _DraftKind.network;
        }
        return null;
      }
      if (!mounted) return null;
      _draftError = null;
      _draftKind = _DraftKind.unknown;
      return _createDraftBooking();
    }
    if (_draftKind != _DraftKind.motoTaken && _draftKind != _DraftKind.trailerTaken) {
      return null;
    }
    final own = await _ownOverlappingDraft();
    if (own == null || !mounted) return null;
    if (await PaymentPendingMarker.isPending(own)) {
      _pendingBookingId = own;
      await _goPending();
      return null;
    }
    try {
      await cancelPendingBooking(own,
          reason: 'Nahrazeno novým pokusem o platbu v appce');
    } catch (_) {
      return null;
    }
    if (!mounted) return null;
    _draftError = null;
    _draftKind = _DraftKind.unknown;
    return _createDraftBooking();
  }

  /// Vlastní nezaplacený app koncept téže motorky v překrývajícím se termínu.
  Future<String?> _ownOverlappingDraft() async {
    final user = MotoGoSupabase.currentUser;
    final moto = ref.read(bookingMotoProvider);
    final d = ref.read(bookingDraftProvider);
    if (user == null || moto == null || d.startDate == null || d.endDate == null) {
      return null;
    }
    String day(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    try {
      final rows = await MotoGoSupabase.client
          .from('bookings')
          .select('id')
          .eq('user_id', user.id)
          .eq('moto_id', moto.id)
          .eq('status', 'pending')
          .eq('payment_status', 'unpaid')
          .eq('booking_source', 'app')
          .lte('start_date', day(d.endDate!))
          .gte('end_date', day(d.startDate!))
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(const Duration(seconds: 10));
      final list = rows as List;
      return list.isEmpty ? null : (list.first as Map)['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// INSERT bookings. Sloupec `own_gear` (migrace 20260925a) nemusí být na
  /// živé DB ještě nasazený (deploy-sql může zablokovat starší migrace) —
  /// PostgREST pak celý INSERT odmítne (PGRST204 neznámý sloupec). Rezervace
  /// nesmí kvůli tomu spadnout: zopakovat bez `own_gear` (NULL → DB si nárok
  /// na šatnu odvodí z prázdných velikostí řidiče, stejný výsledek).
  ///
  /// Totéž pro jazyk: živá DB před migrací 20261011 nezná 'uk'
  /// (`bookings_language_check`, 23514) → zopakovat s 'en', ať ukrajinský
  /// zákazník rezervaci dokončí (dokumenty a e-maily pak dostane anglicky).
  Future<Map<String, dynamic>> _insertBooking(Map<String, dynamic> row) async {
    try {
      return await MotoGoSupabase.client
          .from('bookings')
          .insert(row)
          .select()
          .single()
          .timeout(const Duration(seconds: 20));
    } on PostgrestException catch (e) {
      final unknownOwnGear = e.code == 'PGRST204' && row.containsKey('own_gear') && e.message.contains('own_gear');
      final badLanguage = isLanguageCheckViolation(e) && row['language'] != 'en';
      if (!unknownOwnGear && !badLanguage) rethrow;
      if (unknownOwnGear) row.remove('own_gear');
      if (badLanguage) {
        AppDebugLogger.instance.log(LogCategory.booking, 'booking_language_fallback',
            data: {'language': row['language']});
        row['language'] = 'en';
      }
      return _insertBooking(row);
    }
  }

  Future<String?> _createDraftBooking() async {
    final draft = ref.read(bookingDraftProvider);
    final moto = ref.read(bookingMotoProvider);
    final breakdown = ref.read(priceBreakdownProvider);
    // JEDEN snapshot doplňků pro CELÝ insert — `breakdown.extrasTotal` a řádky
    // v `booking_extras` MUSÍ pocházet ze stejného stavu. Kdyby se rank změnil
    // mezi čtením breakdownu a zápisem řádků (insert je await), rozešly by se
    // `bookings.extras_price` a SUM(`booking_extras.unit_price`) a faktury by
    // vykázaly jinou cenu pronájmu.
    final pricedExtrasAll = ref.read(effectiveExtrasProvider);
    final user = MotoGoSupabase.currentUser;
    if (user == null) {
      _draftError = t(context).tr('notLoggedIn');
      _draftKind = _DraftKind.auth;
      return null;
    }
    if (moto == null) {
      _draftError = t(context).tr('noMotoSelected');
      _draftKind = _DraftKind.input;
      return null;
    }
    // Samoobslužná pobočka vozík nevydává → do rezervace se nesmí dostat, ani
    // kdyby zbyl v draftu (formulář ho maže, dlaždice se nenabízí). Bez téhle
    // pojistky by DB trigger `trg_check_trailer_overlap` odmítl CELOU rezervaci.
    final selfService = moto.branchType == 'samoobslužná';
    // Vozík je v appce vždy za 0 Kč, takže jeho vynechání nemění `extras_price`
    // ani součet řádků v `booking_extras` (musí si odpovídat — viz výše).
    final pricedExtras = selfService
        ? pricedExtrasAll.where((e) => e.id != 'extra-vozik').toList()
        : pricedExtrasAll;
    if (draft.startDate == null || draft.endDate == null) {
      // Bez termínu nesmí vzniknout rezervace s prázdnými daty (insert by
      // spadl na invalid date). Stane se jen při otevření platby s
      // vyprázdněným draftem — pošli uživatele vybrat termín.
      _draftError = t(context).tr('selectDatesFirst');
      _draftKind = _DraftKind.input;
      return null;
    }
    // Pojistka (2026-08-22): bez povinných údajů profilu (adresa; číslo a
    // platnost ŘP u motorek s ŘP) rezervace NEVZNIKNE — primárně to hlídá
    // rezervační formulář, tohle kryje starý draft / přímý vstup na platbu.
    final profileGate = ref.read(profileCompletenessValidationProvider);
    if (profileGate != null) {
      _draftError = profileGate;
      _draftKind = _DraftKind.input;
      return null;
    }

    String _fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

    final pickupMethod =
        draft.pickupMethod == 'delivery' ? 'delivery' : 'branch';
    final returnMethod =
        draft.returnMethod == 'delivery' ? 'delivery' : 'branch';

    // ─────────────────────────────────────────────────────────────────
    // Gear sizes — 5 driver + 5 passenger columns on `bookings`
    // Driver sizes come from BookingDraft fields (set in form_body).
    // Passenger sizes are stored as a single string inside
    // SelectedExtra.size of `extra-spolujezdec` (format
    //   "Helma: M, Rukavice: L, Bunda: M, Kalhoty: M")
    // and SelectedExtra.size of `extra-boty-spolu` for passenger boots.
    // We parse them here and write to dedicated columns so Velín
    // detail rezervace zobrazuje kompletní rozpis.
    // ─────────────────────────────────────────────────────────────────
    String? _findExtraSize(String id) {
      for (final e in draft.extras) {
        if (e.id == id) return e.size;
      }
      return null;
    }
    Map<String, String> _parsePassengerGearSizes() {
      final raw = _findExtraSize('extra-spolujezdec');
      if (raw == null || raw.trim().isEmpty) return {};
      final map = <String, String>{};
      for (final part in raw.split(',')) {
        final ix = part.indexOf(':');
        if (ix <= 0) continue;
        final k = part.substring(0, ix).trim().toLowerCase();
        final v = part.substring(ix + 1).trim();
        if (v.isEmpty) continue;
        if (k.startsWith('helm')) map['helmet'] = v;
        else if (k.startsWith('rukav')) map['gloves'] = v;
        else if (k.startsWith('bund')) map['jacket'] = v;
        else if (k.startsWith('kalh')) map['pants'] = v;
      }
      return map;
    }
    final pg = _parsePassengerGearSizes();
    // Boty řidiče JEN když je zvolený placený doplněk (dřív `draft.bootsSize ??`
    // z předvyplnění profilu → boots_size se zapsal i bez objednaných bot).
    final driverBoots = _findExtraSize('extra-boty-ridic');
    final passengerBoots = _findExtraSize('extra-boty-spolu');

    // Sleva: kromě textového kódu zapiš i FK na promo_codes / vouchers —
    // parita s webovou create_web_booking. Bez promo_code_id/voucher_id
    // process-payment ZAMÍTNE potvrzení 100% slevy (free booking) a
    // rezervace by zůstala unpaid → auto-storno za 30 minut.
    final firstDiscount = draft.discounts.isNotEmpty ? draft.discounts.first : null;
    final promoCodeId =
        (firstDiscount != null && !firstDiscount.isVoucher) ? firstDiscount.promoId : null;
    final voucherId =
        (firstDiscount != null && firstDiscount.isVoucher) ? firstDiscount.promoId : null;

    try {
      // Direct insert into bookings table (matches original Capacitor app)
      final row = <String, dynamic>{
        'user_id': user.id,
        'moto_id': moto.id,
        'start_date': draft.startDate != null ? _fmtDate(draft.startDate!) : '',
        'end_date': draft.endDate != null ? _fmtDate(draft.endDate!) : '',
        // Čas vyzvednutí volí zákazník u všech poboček (samoobsluha: řídí
        // slevu za vyzvednutí od 12:00 a výdej kiosku, zadání 2026-10-01 večer).
        'pickup_time': draft.pickupTime ?? '09:00',
        // Předpokládaný čas návratu (povinné pole, parita s webem). Default 19:00.
        // Samoobslužná pobočka + vrácení na pobočce → vždy 23:59 (pojistka,
        // formulář draft normalizuje; do smlouvy jde konec dne).
        'return_time': selfServiceHidesReturnTime(
                branchType: moto.branchType, returnMethod: draft.returnMethod)
            ? selfServiceReturnTime
            : (draft.returnTime ?? '19:00'),
        'total_price': breakdown.total,
        'extras_price': breakdown.extrasTotal,
        'delivery_fee': breakdown.deliveryFee,
        'discount_amount': breakdown.discountTotal,
        'discount_code': firstDiscount?.code,
        if (promoCodeId != null) 'promo_code_id': promoCodeId,
        if (voucherId != null) 'voucher_id': voucherId,
        // Věrnostní sleva (ranky) — platí JEN pro app rezervace. Sloupce se
        // posílají pouze když sleva reálně padla (= backend s loyalty_* už
        // nasazen, RPC vrátila rank) — jinak by insert na starém schématu
        // spadl na neznámém sloupci. Server-side trigger slevu validuje.
        if (breakdown.loyaltyDiscount > 0) ...{
          'loyalty_level': breakdown.loyaltyLevel,
          'loyalty_percent': breakdown.loyaltyPercent,
          'loyalty_discount_amount': breakdown.loyaltyDiscount,
        },
        // Sleva 50 % na 1. den při pozdním vyzvednutí (>=12:00, >=2 dny) —
        // posílá se jen když reálně padla (backend se sloupcem nasazen);
        // server-side ji clamp-down trigger trg_validate_late_pickup validuje.
        if (breakdown.latePickupDiscount > 0)
          'late_pickup_discount_amount': breakdown.latePickupDiscount,
        'pickup_method': pickupMethod,
        'pickup_address': pickupMethod == 'delivery'
            ? draft.pickupAddress
            : null,
        'return_method': returnMethod,
        'return_address': returnMethod == 'delivery'
            ? draft.returnAddress
            : null,
        'pickup_lat': draft.pickupLat,
        'pickup_lng': draft.pickupLng,
        'return_lat': draft.returnLat,
        'return_lng': draft.returnLng,
        'status': 'pending',
        'payment_status': 'unpaid',
        // Zdroj rezervace = app (web hardcoduje 'web'). Řídí výběr e-mailových
        // šablon (app/sdílené, ne web_*), auto-cancel okno (app=30 min) a
        // vyloučení z webových abandoned/missing-docs cronů.
        'booking_source': 'app',
        // i18n: jazyk zákazníka (z aktuálního locale appky) → maily/SMS/push
        // dorazí přeložené do příslušného jazyka (detect_customer_language).
        'language': normalizeAppLang(ref.read(localeProvider).languageCode),
        // Poznámka zákazníka z rezervačního formuláře → Velín (BookingDetail).
        if ((draft.notes ?? '').trim().isNotEmpty)
          'notes': draft.notes!.trim(),
        // „Mám vlastní výbavu“ — explicitně (true/false). Rozhoduje o kódu
        // šatny: bez šatny, pokud řidič nic nepůjčuje a nemá boty ani výbavu
        // spolujezdce (`_booking_needs_locker`, 2026-09-25).
        'own_gear': draft.ownGear,
        // Driver gear sizes (5 columns). Při „Mám vlastní výbavu“ se základní
        // výbava řidiče NEukládá — draft ji může mít předvyplněnou z profilu
        // (moto_detail_page) i když jsou řádky velikostí skryté; jinak by se
        // own-gear zákazníkovi ukázala v protokolu výbava, kterou nechtěl (2026-10-05).
        'helmet_size': draft.ownGear ? null : draft.helmetSize,
        'jacket_size': draft.ownGear ? null : draft.jacketSize,
        'pants_size': draft.ownGear ? null : draft.pantsSize,
        'boots_size': driverBoots,
        'gloves_size': draft.ownGear ? null : draft.glovesSize,
        // Passenger gear sizes (5 columns)
        'passenger_helmet_size':
            draft.passengerHelmetSize ?? pg['helmet'],
        'passenger_jacket_size':
            draft.passengerJacketSize ?? pg['jacket'],
        'passenger_pants_size':
            draft.passengerPantsSize ?? pg['pants'],
        'passenger_gloves_size': pg['gloves'],
        'passenger_boots_size': passengerBoots,
        // Vozík (příslušenství) — přiřazený volný kus blokuje kalendář vozíku.
        // BEFORE INSERT trigger check_trailer_overlap odmítne už obsazený kus.
        'trailer_moto_id': selfService ? null : draft.trailerMotoId,
      };
      final res = await _insertBooking(row);

      final bookingId = res['id'] as String?;
      if (bookingId == null) {
        _draftKind = _DraftKind.unknown;
        return null;
      }

      // Save extras to booking_extras table (fire-and-forget, like original).
      // Ceny ze SNAPSHOTU z začátku téhle metody (od [loyaltyFreeGearLevel]
      // je gear za 0 Kč) — stejný stav, z jakého vyšel `extras_price` výše.
      _saveBookingExtras(bookingId, pricedExtras);

      // Multi-sleva: zapiš VŠECHNY slevy do booking_discounts (zdroj pravdy pro
      // rozpad na fakturách ZF/DP/KF + uplatnění voucherů/promo po platbě).
      // promo_code_id/voucher_id na bookingu drží jen PRVNÍ (parita s webem).
      // AWAIT (2.1.0): zápis dokončíme PŘED platbou, aby trigger
      // redeem_booking_discounts_on_paid měl co uplatnit (used_count / voucher
      // redeemed) — jinak by při race/výpadku sleva u rezervace nezapočetla.
      // Chyba je nefatální (jen log) — nesmí shodit potvrzení rezervace.
      if (draft.discounts.isNotEmpty) {
        try {
          await MotoGoSupabase.client.from('booking_discounts').insert(
            draft.discounts
                .map((d) => {
                      'booking_id': bookingId,
                      'kind': d.isVoucher ? 'voucher' : 'promo_code',
                      'code': d.code,
                      'promo_code_id': d.isVoucher ? null : d.promoId,
                      'voucher_id': d.isVoucher ? d.promoId : null,
                      'discount_type': d.type.name == 'percent' ? 'percent' : 'fixed',
                      'value': d.value,
                      'amount': d.calculatedAmount,
                    })
                .toList(),
          ).timeout(const Duration(seconds: 15));
        } catch (e) {
          debugPrint('[Payment] booking_discounts insert failed: $e');
        }
      }

      // Souhlasy z rezervačního formuláře propíšeme do profilu (parita s webem).
      // + ZAPAMATUJ velikosti výbavy do profiles.gear_sizes (struktura
      //   {rider:{helmet,gloves,jacket,pants,boots}, passenger:{...}}) — web i
      //   appka je pak při příští rezervaci předvyplní. Slučujeme s existujícími,
      //   ať se dřív uložené velikosti nepřepíšou prázdnem.
      // Fire-and-forget — nesmí blokovat ani shodit potvrzení rezervace.
      // Zákazník mezitím odešel (zpět během zakládání nic nestrhne) → bez
      // `ref` (po dispose hází); koncept už stojí a FAB ho najde sám.
      if (!mounted) return bookingId;
      final existingGear =
          (ref.read(profileProvider).valueOrNull?['gear_sizes'] as Map?) ?? const {};
      final riderGear = Map<String, dynamic>.from((existingGear['rider'] as Map?) ?? const {});
      final passGear = Map<String, dynamic>.from((existingGear['passenger'] as Map?) ?? const {});
      void _putGear(Map<String, dynamic> m, String k, String? v) {
        if (v != null && v.trim().isNotEmpty) m[k] = v.trim();
      }
      _putGear(riderGear, 'helmet', draft.helmetSize);
      _putGear(riderGear, 'gloves', draft.glovesSize);
      _putGear(riderGear, 'jacket', draft.jacketSize);
      _putGear(riderGear, 'pants', draft.pantsSize);
      _putGear(riderGear, 'boots', driverBoots);
      _putGear(passGear, 'helmet', draft.passengerHelmetSize ?? pg['helmet']);
      _putGear(passGear, 'gloves', pg['gloves']);
      _putGear(passGear, 'jacket', draft.passengerJacketSize ?? pg['jacket']);
      _putGear(passGear, 'pants', draft.passengerPantsSize ?? pg['pants']);
      _putGear(passGear, 'boots', passengerBoots);
      final gearSizes = <String, dynamic>{
        if (riderGear.isNotEmpty) 'rider': riderGear,
        if (passGear.isNotEmpty) 'passenger': passGear,
        // Zapamatuj i volbu „mám vlastní výbavu" → příště se předzaškrtne.
        'rider_own': draft.ownGear,
      };
      () async {
        try {
          // Souhlasy jen POTVRZUJEME (true z checkboxů formuláře) — nikdy je
          // nepřepisujeme na false: dřív formulář checkboxy neměl a každá app
          // rezervace tu smazala souhlasy z registrace (consent_vop/gdpr=false).
          await MotoGoSupabase.client.from('profiles').update({
            if (draft.consentVop) 'consent_vop': true,
            if (draft.consentGdpr) 'consent_gdpr': true,
            // Zpracování osobních údajů = tentýž souhlas jako GDPR checkbox
            // (povinné pole ve Velíně).
            if (draft.consentGdpr) 'consent_data_processing': true,
            'gear_sizes': gearSizes,
          }).eq('id', user.id);
        } catch (_) {/* ignore */}
      }();

      // Invalidate FAB provider so it detects the new pending booking
      ref.invalidate(pendingBookingFabProvider);

      return bookingId;
    } catch (e) {
      final msg = e.toString();
      // Syrový text výjimky z PostgREST/PostgreSQL zákazníkovi nic neřekne
      // (a může prozradit vnitřnosti) — do UI jde srozumitelná hláška,
      // podrobnosti zůstanou v logu.
      debugPrint('[Payment] createDraftBooking failed: $e');
      if (msg.contains('Překrývající se rezervace') ||
          msg.contains('přiřazen jako vozík') ||
          msg.contains('Booking overlap') ||
          msg.contains('overlapping booking') ||
          msg.contains('exclusion constraint') ||
          msg.contains('check_booking_overlap')) {
        // trg_check_booking_overlap (20260911): motorku mezitím zarezervoval
        // někdo jiný — nebo vlastní starší koncept (řeší _createDraftWithRecovery).
        _draftKind = _DraftKind.motoTaken;
      } else if (msg.contains('obslužné pobočky')) {
        // trg_check_trailer_overlap (23514): vozík k motorce ze samoobslužné
        // pobočky — sem dojde jen starý build bez `p_moto_id` nebo závod
        // (přesun motorky mezi výběrem a zápisem).
        _draftError = mounted ? t(context).tr('fxTrailerStaffedOnly') : null;
        _draftKind = _DraftKind.input;
      } else if (msg.contains('trailer_unavailable')) {
        // trg_check_trailer_overlap (23505): kus vozíku mezitím obsadil jiný.
        _draftKind = _DraftKind.trailerTaken;
      } else if (msg.contains('self_service_no_delivery')) {
        // DB trigger (2026-09-28): samoobslužná pobočka bez přistavení / odvozu
        // na adresu (feature flag `self_service_delivery` vypnutý) — sem dojde
        // jen starý build bez zabalených voleb nebo závod s přepnutím flagu.
        _draftError = mounted ? t(context).tr('ssNoDeliveryError') : null;
        _draftKind = _DraftKind.input;
      } else if (isAuthExpiredError(e)) {
        _draftKind = _DraftKind.auth;
      } else if (isNetworkError(e)) {
        _draftKind = _DraftKind.network;
      } else {
        _draftError = null;
        _draftKind = _DraftKind.unknown;
      }
      return null;
    }
  }

  /// Saves selected extras to the booking_extras table.
  Future<void> _saveBookingExtras(
      String bookingId, List<SelectedExtra> extras) async {
    if (extras.isEmpty) return;
    try {
      final rows = extras.map((e) {
        return {
          'booking_id': bookingId,
          'extra_id': e.id.startsWith('extra-') ? null : e.id,
          'name': e.name,
          'unit_price': e.price,
          'quantity': e.quantity,
        };
      }).toList();
      await MotoGoSupabase.client.from('booking_extras').insert(rows);
    } catch (e) {
      debugPrint('[Payment] Extras save error: $e');
    }
  }

  // -- Payment logic (native Payment Sheet) --

  Future<void> _doPayment() async {
    if (_processing || _expired || _completed) return;

    // D1 (2026-10-16): do 1 Kč se neúčtuje (potvrdí se bez platby), 1–15 Kč
    // se platí 15 Kč (dorovnání zapíše server, na dokladu samostatný řádek).
    final cc = _cardFor(_amount);
    if (cc.kind == CardChargeKind.free) {
      await _confirmFree();
      return;
    }
    if (cc.isWaive) {
      if (_ctx?.flowType == PaymentFlowType.extension) {
        await _applyWaivedChange();
      } else {
        await _confirmFree(waived: true);
      }
      return;
    }
    final amount = cc.charge.toDouble();

    _setProcessing(true);

    // For new bookings: create draft first
    if (_isNewBooking) {
      _pendingBookingId ??= await _createDraftWithRecovery();
      if (_pendingBookingId == null) {
        // Return MUSÍ platit vždy — dřív byl podmíněný `mounted`, takže při
        // selhání s odpojeným widgetem kód propadl dál a pokusil se strhnout
        // kartu bez existující rezervace.
        if (!mounted) return;
        _setProcessing(false);
        if (!_completed) _showDraftFailure();
        return;
      }
      if (!mounted) return;
    }

    // -- Saved card auto-charge (off-session) --
    // Když má uživatel uloženou (default) kartu, strhneme ji rovnou — BEZ
    // Payment Sheetu. Parita s „1 klik na zaplatit" na webu: zákazník vidí jen
    // spinner („šrotuji"), pak buď děkovací stránku, nebo chybu se „Zkusit
    // znovu". Stripe Payment Sheet (zadávání karty) se uloženou kartou už
    // NEOTVÍRÁ — ten zůstává jen pro zákazníky bez uložené karty.
    final defaultCard = ref.read(defaultCardProvider);
    if (defaultCard != null && defaultCard.stripeId.isNotEmpty) {
      await _chargeSavedCard(amount, defaultCard);
      return;
    }

    await _runPaymentSheetFlow(amount);
  }

  /// Strhne částku z uložené karty bez interakce (off-session). Pokud Stripe
  /// vyžaduje SCA (3DS), zobrazí se nativní overlay přímo v appce. Při selhání
  /// se NEpřechází na Payment Sheet — ukáže se chybová hláška se „Zkusit znovu".
  Future<void> _chargeSavedCard(double amount, SavedCard card) async {
    debugPrint('[Payment] saved-card charge: amount=${amount.round()}');
    // Telefon je offline → požadavek by vůbec neodešel. Bez značky a bez
    // „ověřování" rovnou řekni proč a nabídni „Zkusit znovu" (dřív 15 minut
    // „Platba se ověřuje" za platbu, která nikdy neopustila telefon).
    if (!await _deviceOnline()) {
      if (!mounted) return;
      _setProcessing(false);
      final n = PaymentErrorMapper.network(t(context).lang);
      _showProblem(PayProblem(n.title, n.message, PayAction.retry));
      return;
    }
    if (!mounted) return;
    // NOVÝ pokus: intent z dřívějšího (opuštěného) pokusu sem nepatří —
    // ověření by podle něj tvrdilo „nic nestrženo" (dvojí platba).
    _activeClientSecret = null;
    _netTrouble = false;
    // Server kartu strhne hned — kdyby appka během čekání spadla / ztratila
    // spojení, značka zabrání další platbě, dokud se výsledek neověří.
    _markSubmitted();
    await _setMarker(fresh: true);
    _activePiId = null;
    final result = await StripeService.createPaymentIntent(
      bookingId: _pendingBookingId,
      amount: amount.round(),
      type: _stripeType,
      orderId: _pendingOrderId,
      incidentId: _ctx?.incidentId,
      paymentMethodId: card.stripeId,
      change: _extensionChangePayload,
      attemptId: newAttemptId(),
    );

    if (!mounted) return;
    _pendingBookingId ??= result.bookingId;
    _activePiId = result.paymentIntentId ?? piIdFromClientSecret(result.clientSecret);

    switch (result.type) {
      case PaymentResultType.offSessionSucceeded:
        // Client secret (server ho vrací od D4) → ověření stavu po restartu.
        final okCs = result.clientSecret;
        if (okCs != null) {
          _activeClientSecret = okCs;
          await _setMarker(clientSecret: okCs);
        }
        await _verifyAndComplete();
        return;

      case PaymentResultType.free:
        // Bez platby (zbytek do 1 Kč / 100% sleva) — server už potvrdil.
        _handleFreeResult(result);
        return;

      case PaymentResultType.offSessionRequiresAction:
        // SCA (3DS) prompt — Stripe SDK ukáže overlay přímo v appce.
        final cs = result.clientSecret!;
        _activeClientSecret = cs;
        await _setMarker(clientSecret: cs);
        final na = await StripeService.handleNextActionDetailed(cs);
        if (!mounted) return;
        switch (na.outcome) {
          case NextActionOutcome.succeeded:
            await _verifyAndComplete();
          case NextActionOutcome.processing:
            await _awaitProcessingConfirmation();
          case NextActionOutcome.unknown:
            await _verifyUncertain();
          case NextActionOutcome.notCompleted:
          case NextActionOutcome.failed:
            // Banka platbu zamítla i po ověření (nedostatek prostředků,
            // propadlá / blokovaná karta, limit…) → pravý důvod (D5), ne
            // „dokonči 3D Secure" (zákazník by ověřoval znovu a znovu).
            final decline = na.declineError;
            final declined = decline == null
                ? null
                : PaymentErrorMapper.fromStripeException(decline, t(context).lang);
            if (declined != null && declined.needsVerification) {
              await _verifyUncertain();
              return;
            }
            // Ověření (3DS) neproběhlo / banka zamítla — nic nestrženo.
            await PaymentPendingMarker.clear(_markerId);
            if (!mounted) return;
            _setProcessing(false);
            if (declined != null) {
              _handleSavedCardFailure(result, declined: declined);
              return;
            }
            _attempts++;
            _handleSavedCardFailure(result,
                authNotDone: na.outcome == NextActionOutcome.notCompleted,
                authFailed: na.outcome == NextActionOutcome.failed);
        }
        return;

      case PaymentResultType.offSessionFailed:
        debugPrint('[Payment] saved-card failed: ${result.stripeCode} '
            '(decline=${result.declineCode}, status=${result.intentStatus})');
        // PI skončil v `processing` → nejde o chybu, čekat na banku.
        if (result.intentStatus == 'processing') {
          await _awaitProcessingConfirmation();
          return;
        }
        // Bez kódu Stripe a bez stavu PI (výpadek spojení server↔Stripe,
        // chyba API) mohla karta být stržena → značku NEmazat, ověřit
        // (zaplaceno / „Platba se ověřuje"), nikdy „nic nestrženo" + znovu.
        if (PaymentErrorMapper.fromEdge(
                errorCode: result.stripeCode,
                declineCode: result.declineCode,
                intentStatus: result.intentStatus,
                lang: t(context).lang)
            .needsVerification) {
          await _verifyUncertain();
          return;
        }
        await PaymentPendingMarker.clear(_markerId);
        if (!mounted) return;
        _setProcessing(false);
        _handleSavedCardFailure(result);
        return;

      case PaymentResultType.error:
        if (!result.uncertain) await PaymentPendingMarker.clear(_markerId);
        if (!mounted) return;
        _setProcessing(false);
        _handleIntentError(result);
        return;

      default:
        // Neočekávaný stav (např. backend vrátil běžný intent místo off-session)
        // — místo Payment Sheetu raději ukážeme chybu, aby zákazník s uloženou
        // kartou neviděl zadávání karty.
        await PaymentPendingMarker.clear(_markerId);
        if (!mounted) return;
        _setProcessing(false);
        // Server kartu nestrhával (vrátil nepotvrzený intent) → „nic nestrženo".
        _handleSavedCardFailure(result, notCharged: true);
        return;
    }
  }

  /// Má telefon vůbec síť? (Wi-Fi / data zapnutá.) Chyba pluginu = nevíme
  /// → poslední známý stav, platba pak rozhodne sama.
  Future<bool> _deviceOnline() async {
    try {
      return await OfflineGuard.isOnline().timeout(const Duration(seconds: 3));
    } catch (_) {
      return !OfflineGuard.offlineNow;
    }
  }

  /// Klasický flow s Payment Sheetem (zachová původní chování).
  Future<void> _runPaymentSheetFlow(double amount) async {
    _setProcessing(true);
    // Nový pokus — intent předchozího pokusu už nerozhoduje.
    _activeClientSecret = null;
    _netTrouble = false;

    _activePiId = null;
    debugPrint('[Payment] createPaymentIntent: amount=${amount.round()}, type=$_stripeType');
    final result = await StripeService.createPaymentIntent(
      bookingId: _pendingBookingId,
      amount: amount.round(),
      type: _stripeType,
      orderId: _pendingOrderId,
      incidentId: _ctx?.incidentId,
      change: _extensionChangePayload,
      attemptId: newAttemptId(),
    );

    if (!mounted) return;

    if (result.type == PaymentResultType.intent &&
        result.clientSecret != null) {
      _pendingBookingId ??= result.bookingId;
      final cs = result.clientSecret!;
      _activeClientSecret = cs;
      _activePiId = result.paymentIntentId ?? piIdFromClientSecret(cs);

      // Vlastní in-app sheet (CardField + Google Pay) místo nativního Payment
      // Sheetu — pole „Číslo karty" je celé klikací a jde do něj vložit číslo
      // ze schránky. Uloženou kartu sem flow nepustí (řeší _chargeSavedCard).
      final sheetResult = await CardPaymentSheet.show(
        context,
        clientSecret: cs,
        amount: amount,
        // Platba odeslána bance → značka proti dvojí platbě (pád appky,
        // ztracený výsledek). Smaže se, jakmile je výsledek známý.
        onSubmitting: () async {
          _markSubmitted();
          await _setMarker(clientSecret: cs, fresh: true);
          // Doplatek změny: pojistka ve frontě (přežije zabití appky během
          // platby); první dotaz na server až po 90 s, ať nepřekáží 3D Secure.
          await _enqueuePaidChange(paid: false, delay: const Duration(seconds: 90));
        },
      );

      if (!mounted) return;

      switch (sheetResult.status) {
        case CardSheetStatus.paid:
          await _verifyAndComplete();
        case CardSheetStatus.processing:
          // Stripe platbu zatím NEPOTVRDIL (PaymentIntent = Processing). Doklady
          // se NESMÍ vystavit dokud potvrzení nepřijde ze serveru (webhook).
          await _awaitProcessingConfirmation();
        case CardSheetStatus.cancelled:
          // Zákazník zavřel sheet před odesláním platby — žádná chyba, jen reset.
          await PaymentPendingMarker.clear(_markerId);
          await PaidChangeQueue.discard(_activePiId);
          _setProcessing(false);
        case CardSheetStatus.failed:
          if (sheetResult.stripeError != null) {
            await _handleStripeError(sheetResult.stripeError!,
                wallet: sheetResult.wallet);
          } else {
            await _resolveAfterSheetError(sheetResult.otherError ?? 'card payment failed',
                wallet: sheetResult.wallet);
          }
      }
    } else if (result.type == PaymentResultType.free) {
      _handleFreeResult(result);
    } else {
      _setProcessing(false);
      _handleIntentError(result);
    }
  }

  Future<void> _verifyAndComplete() async {
    _markVerifying();
    showMotoGoToast(context,
        icon: '⌛', title: t(context).tr('verifyingPayment'), message: t(context).tr('waitingConfirmation'));

    if (_ctx?.flowType == PaymentFlowType.extension) {
      // Doplatek změny prošel (Stripe Succeeded) → NEJDŘÍV do trvalé fronty
      // (D6: dokončí se i po zabití appky / bez sítě), pak zápis přes server.
      await _enqueuePaidChange(paid: true);
      if (!mounted) return;
      _onPaymentSuccess();
      return;
    }
    final confirmed = await _serverConfirmed();
    if (!mounted) return;

    if (confirmed) {
      _onPaymentSuccess();
    } else {
      // Webhook ještě nepotvrdil → NEvystavuj doklady; ukaž „Platba se ověřuje".
      await _goPending();
    }
  }

  /// Striktní serverové potvrzení platby PŘED vystavením dokladů. Vrací true JEN
  /// když platbu reálně potvrdil server (Stripe webhook):
  ///  • objednávka  → `shop_orders.payment_status = 'paid'`
  ///  • doplatek úpravy (extension) → webhook aplikoval změnu
  ///    (`bookings.total_price` == očekávaná nová cena); booking je už `paid`
  ///    z původní platby, takže `payment_status` NELZE použít jako důkaz
  ///  • nová / dokončovaná rezervace → `bookings.payment_status = 'paid'`
  Future<bool> _serverConfirmed({int maxAttempts = 8}) async {
    const interval = Duration(seconds: 1);
    if (_pendingOrderId != null) {
      return StripeService.pollOrderPaymentStatus(_pendingOrderId!,
          maxAttempts: maxAttempts, interval: interval);
    }
    if (_ctx?.flowType == PaymentFlowType.extension) {
      final expected = _expectedEditTotal;
      final bid = _pendingBookingId;
      if (expected == null || bid == null) return false;
      return StripeService.pollBookingTotal(bid, expected,
          maxAttempts: maxAttempts, interval: interval);
    }
    if (_pendingBookingId != null) {
      return StripeService.pollBookingPaymentStatus(_pendingBookingId!,
          maxAttempts: maxAttempts, interval: interval);
    }
    return false;
  }

  /// PaymentIntent je ve stavu `Processing` — Stripe platbu NEPOTVRDIL. Nikdy
  /// nevystavuj doklady optimisticky; počkej na serverové potvrzení a když
  /// nedorazí v okně, ukaž obrazovku „Platba se ověřuje" (sama se přepne, až
  /// potvrzení dorazí) BEZ vystavení dokladu / aplikace úpravy.
  Future<void> _awaitProcessingConfirmation() async {
    _markVerifying();
    await _setMarker(clientSecret: _activeClientSecret);
    // Banka doplatek změny ještě zpracovává → fronta ho dokončí, až projde.
    await _enqueuePaidChange(paid: false);
    if (!mounted) return;
    showMotoGoToast(context,
        icon: '⌛',
        title: t(context).tr('verifyingPayment'),
        message: t(context).tr('waitingConfirmation'));

    final confirmed = _flow == PayFlow.swap
        ? false
        : await _serverConfirmed(maxAttempts: 10);
    if (!mounted) return;

    if (confirmed) {
      _onPaymentSuccess();
    } else {
      await _goPending();
    }
  }

  /// Potvrzení rezervace plně pokryté slevou (0 Kč). KRITICKÉ: úspěch se
  /// NESMÍ předstírat — dřív se výsledek confirm_free ignoroval, zákazník
  /// viděl děkovací stránku, ale rezervace zůstala `unpaid` a za 30 minut
  /// přišel storno mail. Teď flow pokračuje na úspěch JEN když backend
  /// rezervaci reálně označil jako zaplacenou.
  Future<void> _confirmFree({bool waived = false}) async {
    _setProcessing(true);

    if (_isNewBooking) {
      _pendingBookingId ??= await _createDraftWithRecovery();
      if (_pendingBookingId == null) {
        if (!mounted) return;
        _setProcessing(false);
        if (!_completed) _showDraftFailure();
        return;
      }
    }

    final bookingId = _pendingBookingId;
    if (bookingId == null) {
      // Nemělo by nastat (free flow je vždy booking) — bez ID není co potvrdit.
      if (!mounted) return;
      _setProcessing(false);
      _showProblem(PayProblem(t(context).tr('pdServerTitle'),
          t(context).tr('pdUnknownBody'), PayAction.retry));
      return;
    }

    // Od teď se rezervace potvrzuje — odchod už jen s potvrzením.
    _markSubmitted();
    // SOS náhrada jako SOS (server ji neodpouští podle ceníku rezervace).
    final result = await StripeService.confirmFreeBooking(bookingId,
        type: _ctx?.flowType == PaymentFlowType.sos ? 'sos' : 'booking');
    if (!mounted) return;

    // Fallback poll pokrývá i případ „již zaplaceno" (409 z duplicate guardu).
    final confirmed = result.type == PaymentResultType.free ||
        await StripeService.pollBookingPaymentStatus(bookingId, maxAttempts: 3);
    if (!mounted) return;

    if (!confirmed) {
      _setProcessing(false);
      _handleIntentError(result);
      return;
    }

    showMotoGoToast(context,
        icon: '✓',
        title: t(context).tr('confirmed'),
        message: t(context).tr(waived ? 'pdWaivedSub' : 'discountCoversAll'));
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _onPaymentSuccess();
  }

  Future<void> _onPaymentSuccess() async {
    if (_completed || !mounted) return;
    _completed = true;
    _countdownTimer?.cancel();
    // Až do přechodu na výsledek „běží platba" (zápis výměny / úpravy může
    // trvat desítky sekund) — záložky i šipka se zeptají; vypne se v dispose.
    _setProcessing(true);
    ref.read(paymentContextProvider.notifier).state = null;
    // Výsledek je známý → značka „platba odeslána" už nepatří (FAB, restart).
    PaymentPendingMarker.clear(_pendingBookingId);
    PaymentPendingMarker.clear(_pendingOrderId);

    // Force refresh reservation data so UI shows updated state immediately
    ref.invalidate(reservationsProvider);
    if (_pendingBookingId != null) {
      ref.invalidate(reservationByIdProvider(_pendingBookingId!));
    }
    // Rezervace je zaplacená → FAB „Dokončit rezervaci" nesmí dál ukazovat
    // stav z paměti (viz pendingBookingFabProvider, incident 2026-09-28).
    ref.invalidate(pendingBookingFabProvider);

    // Try to release withheld door codes (fire-and-forget safety net).
    // Backend triggers should handle this, but RPC serves as a fallback
    // in case documents were uploaded before payment and trigger missed them.
    final bookingId = _pendingBookingId;
    if (bookingId != null) {
      Future.delayed(const Duration(seconds: 2), () => releaseDoorCodes(bookingId));
    }

    if (_isNewBooking) {
      if (_pendingBookingId != null) {
        EmailService.sendBookingReserved(_pendingBookingId!);
        _advanceInvoiceBackup(_pendingBookingId!);
        InvoiceService.generateBookingDocs(_pendingBookingId!);
      }
      // Create shop order for upsell items (fire-and-forget) — jen když byl
      // doprodej v platbě opravdu přibalený (viz _upsellBundled).
      final upsellItems = ref.read(bookingUpsellProvider);
      if (upsellItems.isNotEmpty) {
        if (_upsellBundled) createBookingUpsellOrder(upsellItems);
        ref.read(bookingUpsellProvider.notifier).clear();
      }
      showMotoGoToast(context,
          icon: '✓', title: t(context).tr('paid'), message: t(context).tr('bookingConfirmed'));
      // Děkovací stránka si načte stav dokladů + typ motorky podle tohoto ID.
      ref.read(lastConfirmedBookingProvider.notifier).state = _pendingBookingId;
      ref.read(lastConfirmedRestoreProvider.notifier).state = false;
      ref.read(lastConfirmedFromDraftProvider.notifier).state = true;
      context.go(Routes.success);
    } else {
      final tr = t(context);
      // Co se opravdu strhlo (minimum karty 15 Kč, D1) — z částky potvrzené
      // serverem (po „Cena se změnila" už není ta z kontextu) + řádek dorovnání.
      final paidCc = _cardFor(_amount);
      final amountStr = Money.czk(paidCc.charge);
      final roundLine = roundingLine(tr, paidCc);
      void goResult(PaymentOutcome outcome) {
        ref.read(paymentOutcomeProvider.notifier).state = outcome;
        context.go(Routes.paymentResult);
      }

      switch (_ctx!.flowType) {
        case PaymentFlowType.extension:
          // VÝMĚNA MOTORKY / ÚPRAVA — doplatek zaplacen (nebo do 1 Kč odpuštěn).
          // Zápis změny dělá server (webhook + complete_extension, idempotentně)
          // přes trvalou frontu; zákazník vidí „hotovo", nebo „se dokončuje" (D6).
          await _finishPaidChange();
        case PaymentFlowType.sos:
          // Invoice generation handled by backend (Supabase trigger/edge function)
          goResult(
            PaymentOutcome(
              title: tr.tr('paid'),
              subtitle: tr.tr('replacementMotoOrdered'),
              lines: [PaymentOutcomeLine('💳', '${_ctx!.label}: $amountStr'), if (roundLine != null) roundLine],
              nextStepNote: tr.tr('successEmailSent'),
              ctaLabel: tr.tr('successCta'),
              ctaRoute: Routes.sosDone,
            ),
          );
        case PaymentFlowType.shop:
          goResult(
            PaymentOutcome(
              title: tr.tr('paid'),
              subtitle: tr.tr('orderConfirmed'),
              lines: [PaymentOutcomeLine('💳', '${_ctx!.label}: $amountStr'), if (roundLine != null) roundLine],
              nextStepNote: tr.tr('successEmailSent'),
              ctaLabel: tr.tr('successCta'),
              ctaRoute: Routes.shop,
            ),
          );
        case PaymentFlowType.booking:
          // Resume rozdělané rezervace (FAB „Dokončit rezervaci") / obnovená
          // rezervace = plnohodnotná rezervace, jen s částkou z DB místo draftu
          // — stejné dokončení jako u draft flow: mail, záloha, dokumenty,
          // /success (ta si údaje načte z DB podle ID, ne z draftu v paměti).
          if (_pendingBookingId != null) {
            EmailService.sendBookingReserved(_pendingBookingId!);
            _advanceInvoiceBackup(_pendingBookingId!);
            InvoiceService.generateBookingDocs(_pendingBookingId!);
            showMotoGoToast(context,
                icon: '✓',
                title: tr.tr('paid'),
                message: tr.tr('bookingConfirmed'));
            ref.read(lastConfirmedBookingProvider.notifier).state =
                _pendingBookingId;
            ref.read(lastConfirmedRestoreProvider.notifier).state =
                _ctx!.isRestore;
            ref.read(lastConfirmedFromDraftProvider.notifier).state = false;
            context.go(Routes.success);
            return;
          }
          goResult(
            PaymentOutcome(
              title: tr.tr('paid'),
              subtitle: tr.tr('paymentCompleted'),
              lines: [PaymentOutcomeLine('💳', '${_ctx!.label}: $amountStr'), if (roundLine != null) roundLine],
              nextStepNote: tr.tr('successEmailSent'),
              ctaLabel: tr.tr('successCta'),
              ctaRoute: Routes.reservations,
            ),
          );
      }
    }
  }

  /// Záložní ZF z appky (primárně ji vystaví `send-booking-email`). Dorovnání
  /// na 15 Kč / odpuštění do 1 Kč (D1) zapisuje server až s platbou — ZF
  /// z appky by mohla předběhnout webhook, zachytit cenu bez dorovnání a
  /// dedup by ji držel navždy (ZF 10 Kč vedle DP 15 Kč). S dorovnáním ji
  /// proto vystaví jen server; jinak až po ověřeném `paid` (cena je finální).
  /// Totéž u ceny s haléři (strhly se celé Kč, rozdíl zapisuje server) a bez
  /// platby (doklad na 0 Kč se nevystavuje).
  void _advanceInvoiceBackup(String bookingId) {
    final due = _bookingDue;
    final cc = _cardFor(due);
    if (cc.rounding != 0 || cc.noCharge || cc.charge != cc.due) return;
    () async {
      if (await StripeService.pollBookingPaymentStatus(bookingId, maxAttempts: 3)) {
        await InvoiceService.generateAdvanceInvoice(bookingId, due);
      }
    }();
  }

  /// Úspěch zaplacené úpravy / výměny (i po „Platba se ověřuje" / „dokončuje
  /// se" → ověřeno). Řádek s tím, co se strhlo, a s dorovnáním (D1).
  PaymentOutcome _editSuccessOutcome(AppTranslations tr, {PickupInfo? pickup}) {
    final cc = _cardFor(_ctx?.amount ?? 0);
    final extra = roundingLine(tr, cc);
    return PaymentOutcome(
      pickup: pickup,
      title: tr.tr(cc.isWaive ? 'confirmed' : 'paid'),
      subtitle: _flow == PayFlow.swap
          ? tr.tr('swap.successTitle')
          : tr.tr('bookingChangesConfirmed'),
      lines: [
        if (cc.charge > 0)
          PaymentOutcomeLine('💳', '${_ctx?.label ?? ''}: ${Money.czk(cc.charge)}'),
        if (extra != null) extra,
      ],
      nextStepNote: tr.tr('successEmailSent'),
      ctaLabel: tr.tr('successCta'),
      ctaRoute: Routes.reservations,
    );
  }

  @override
  Widget build(BuildContext context) {
    final moto = ref.watch(bookingMotoProvider);
    final breakdown = ref.watch(priceBreakdownProvider);
    final defaultCard = ref.watch(defaultCardProvider);
    final upsellItems = ref.watch(bookingUpsellProvider);
    final amount = _amount;
    final isFree = amount <= 0;
    // Minimum karty (D1): kolik se opravdu strhne — 15 Kč / nic do 1 Kč.
    final charge = _cardFor(amount);

    return BackButtonListener(
      // Systémové „zpět": během platby jen s potvrzením; bez historie (FAB,
      // deep link) na rozumného rodiče místo zavření appky. Nad obrazovkou
      // otevřený sheet / dialog / jiná trasa → ať se zavře ten.
      onBackButtonPressed: () async {
        if (!isTopmostRoute(context)) return false;
        if (_processing || !GoRouter.of(context).canPop()) {
          _onBack();
          return true;
        }
        return false;
      },
      child: PopScope(
        canPop: !_processing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBack();
        },
        child: Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            PaymentHeader(onBack: _onBack),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Countdown
                    PaymentCountdown(timeRemaining: _timeRemaining),
                    const SizedBox(height: 12),

                    // Motorcycle gallery (new booking only)
                    if (_isNewBooking && moto != null)
                      MotoGalleryCard(
                        images: moto.images.isNotEmpty
                            ? moto.images
                            : [moto.displayImage],
                        model: moto.model,
                        branchName: moto.branchName,
                        branchCity: moto.branchCity,
                      ),
                    if (_isNewBooking && moto != null)
                      const SizedBox(height: 12),

                    // Price summary
                    if (_isNewBooking)
                      PriceSummaryCard(
                        breakdown: breakdown,
                        extras: ref.watch(effectiveExtrasProvider),
                        upsellItems: _upsellBundled ? upsellItems : const [],
                      ),
                    // Cena ověřená serverem (po „Cena se změnila") — platí se ta.
                    if (_isNewBooking && _serverAmount != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '✓ ${t(context).tr('psServerPriceNote').replaceAll('{amount}', Money.czk(amount))}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: MotoGoColors.greenDarker),
                        ),
                      ),
                    if (!_isNewBooking)
                      PaymentContextCard(
                        displayLabel: _displayLabel,
                        amount: amount,
                        isFree: isFree,
                        sosBreakdown: _ctx?.sosBreakdown,
                        sosDepositNote: _ctx?.sosDepositNote,
                      ),
                    // „Minimální platba kartou je 15 Kč – zaplatíš 15 Kč" /
                    // „Částky do 1 Kč neúčtujeme" — PŘED platbou (D1).
                    CardRoundingNote(due: amount, forceMin: _forceMinCharge),
                    const SizedBox(height: 12),

                    // Upsell section (new booking only)
                    if (_isNewBooking && moto != null)
                      UpsellSection(
                        // Doprodej jen k rezervaci, která minimum karty splňuje sama.
                        showProducts: cardCharge(_bookingDue).kind == CardChargeKind.normal &&
                            ref.watch(reservationUpsellEnabledProvider).maybeWhen(data: (v) => v, orElse: () => false),
                      ),
                    if (_isNewBooking && moto != null)
                      const SizedBox(height: 12),

                    // Saved card info
                    if (defaultCard != null && !charge.noCharge)
                      SavedCardPreview(card: defaultCard),

                    if (!charge.noCharge)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '\ud83d\udd12 ${t(context).tr('encryptedPayment')} \u00b7 Stripe PCI DSS Level 1',
                          style: const TextStyle(fontSize: 10, color: MotoGoColors.g400),
                        ),
                      ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // Pay button
            PaymentPayButton(
              amount: charge.charge.toDouble(),
              isFree: charge.noCharge,
              freeLabel: charge.isWaive ? t(context).tr('pdConfirmFree') : null,
              processing: _processing,
              expired: _expired,
              onPay: _doPayment,
              statusLabel: _verifying ? t(context).tr('fxVerifyingBtn') : null,
              statusNote: _verifying ? t(context).tr('fxVerifyingNote') : null,
            ),
          ],
        ),
      ),
    ),
      ),
    );
  }
}
