import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/currency.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
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
  String? _pendingBookingId;
  String? _pendingOrderId;
  int _attempts = 0;
  Timer? _countdownTimer;
  late DateTime _deadline;
  String _timeRemaining = '10:00';
  bool _insuranceSelected = false;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deadline = DateTime.now().add(paymentTimeoutDuration);
    _startCountdown();
    _fabNotifier = ref.read(paymentScreenActiveProvider.notifier);
    _ctxNotifier = ref.read(paymentContextProvider.notifier);
    _ctx = ref.read(paymentContextProvider);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fabNotifier?.state = false;
      ctxNotifier?.state = null;
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
      final expected = (_ctx?.pendingEditChanges?['total_price'] as num?)?.toDouble();
      if (expected != null && bookingId != null) {
        try {
          final row = await MotoGoSupabase.client
              .from('bookings')
              .select('total_price')
              .eq('id', bookingId)
              .maybeSingle();
          final cur = (row?['total_price'] as num?)?.toDouble();
          paid = cur != null && (cur - expected).abs() < 0.5;
        } catch (_) {
          paid = false;
        }
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
    };
    final out = <String, dynamic>{};
    for (final e in src.entries) {
      if (keep.contains(e.key) && e.value != null) out[e.key] = e.value;
    }
    return out.isEmpty ? null : out;
  }

  double get _amount {
    final base = _ctx != null
        ? _ctx!.amount
        : ref.read(priceBreakdownProvider).total;
    double total = base;
    if (_insuranceSelected && _isNewBooking) {
      final moto = ref.read(bookingMotoProvider);
      total += moto?.insurancePrice ?? 0;
    }
    if (_isNewBooking) {
      total += ref.read(bookingUpsellProvider.notifier).total;
    }
    return total;
  }

  String get _displayLabel {
    if (_ctx != null) return _ctx!.label;
    return t(context).tr('bookingReservation');
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        _countdownTimer?.cancel();
        setState(() => _timeRemaining = t(context).tr('timeExpired'));
        _onTimeout();
        return;
      }
      final min = remaining.inMinutes;
      final sec = remaining.inSeconds % 60;
      setState(() {
        _timeRemaining = '$min:${sec.toString().padLeft(2, '0')}';
      });
    });
  }

  Future<void> _onTimeout() async {
    if (!mounted) return;
    _showError(
      title: t(context).tr('paymentExpired'),
      message: t(context).tr('paymentExpiredDesc'),
      buttonLabel: t(context).tr('confirm'),
      onButton: () {
        if (mounted) context.go(Routes.reservations);
      },
    );
  }

  // -- Draft booking (new booking only) --

  String? _draftError;

  Future<String?> _createDraftBooking() async {
    final draft = ref.read(bookingDraftProvider);
    final moto = ref.read(bookingMotoProvider);
    final breakdown = ref.read(priceBreakdownProvider);
    final user = MotoGoSupabase.currentUser;
    if (user == null) {
      _draftError = t(context).tr('notLoggedIn');
      return null;
    }
    if (moto == null) {
      _draftError = t(context).tr('noMotoSelected');
      return null;
    }
    if (draft.startDate == null || draft.endDate == null) {
      // Bez termínu nesmí vzniknout rezervace s prázdnými daty (insert by
      // spadl na invalid date). Stane se jen při otevření platby s
      // vyprázdněným draftem — pošli uživatele vybrat termín.
      _draftError = t(context).tr('selectDatesFirst');
      return null;
    }
    // Pojistka (2026-08-22): bez povinných údajů profilu (adresa; číslo a
    // platnost ŘP u motorek s ŘP) rezervace NEVZNIKNE — primárně to hlídá
    // rezervační formulář, tohle kryje starý draft / přímý vstup na platbu.
    final profileGate = ref.read(profileCompletenessValidationProvider);
    if (profileGate != null) {
      _draftError = profileGate;
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
    final driverBoots = draft.bootsSize ?? _findExtraSize('extra-boty-ridic');
    final passengerBoots = _findExtraSize('extra-boty-spolu');

    // Sleva: kromě textového kódu zapiš i FK na promo_codes / vouchers —
    // parita s webovou create_web_booking. Bez promo_code_id/voucher_id
    // process-payment ZAMÍTNE potvrzení 100% slevy (free booking) a
    // rezervace by zůstala unpaid → auto-storno za 10 minut.
    final firstDiscount = draft.discounts.isNotEmpty ? draft.discounts.first : null;
    final promoCodeId =
        (firstDiscount != null && !firstDiscount.isVoucher) ? firstDiscount.promoId : null;
    final voucherId =
        (firstDiscount != null && firstDiscount.isVoucher) ? firstDiscount.promoId : null;

    try {
      // Direct insert into bookings table (matches original Capacitor app)
      final res = await MotoGoSupabase.client.from('bookings').insert({
        'user_id': user.id,
        'moto_id': moto.id,
        'start_date': draft.startDate != null ? _fmtDate(draft.startDate!) : '',
        'end_date': draft.endDate != null ? _fmtDate(draft.endDate!) : '',
        'pickup_time': draft.pickupTime ?? '09:00',
        // Předpokládaný čas návratu (povinné pole, parita s webem). Default 19:00.
        'return_time': draft.returnTime ?? '19:00',
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
        // šablon (app/sdílené, ne web_*), auto-cancel okno (app=10 min) a
        // vyloučení z webových abandoned/missing-docs cronů.
        'booking_source': 'app',
        // i18n: jazyk zákazníka (z aktuálního locale appky) → maily/SMS/push
        // dorazí přeložené do příslušného jazyka (detect_customer_language).
        'language': ref.read(localeProvider).languageCode,
        // Poznámka zákazníka z rezervačního formuláře → Velín (BookingDetail).
        if ((draft.notes ?? '').trim().isNotEmpty)
          'notes': draft.notes!.trim(),
        // Driver gear sizes (5 columns)
        'helmet_size': draft.helmetSize,
        'jacket_size': draft.jacketSize,
        'pants_size': draft.pantsSize,
        'boots_size': driverBoots,
        'gloves_size': draft.glovesSize,
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
        'trailer_moto_id': draft.trailerMotoId,
      }).select().single();

      final bookingId = res['id'] as String?;
      if (bookingId == null) {
        _draftError = t(context).tr('noBookingId');
        return null;
      }

      // Save extras to booking_extras table (fire-and-forget, like original)
      _saveBookingExtras(bookingId, draft.extras);

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
          );
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
      if (msg.contains('Booking overlap') ||
          msg.contains('overlapping booking')) {
        _draftError = t(context).tr('bookingOverlapError');
      } else {
        _draftError = '$e';
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
    if (_processing) return;

    final amount = _amount;
    if (amount <= 0) {
      await _confirmFree();
      return;
    }

    setState(() => _processing = true);

    // For new bookings: create draft first
    if (_isNewBooking) {
      _draftError = null;
      _pendingBookingId ??= await _createDraftBooking();
      if (_pendingBookingId == null && mounted) {
        setState(() => _processing = false);
        _showError(
          title: t(context).tr('bookingCreateFailed'),
          message: _draftError != null
              ? '$_draftError\n\n${t(context).tr('tryAgainPlease')}'
              : t(context).tr('bookingCreateUnknownError'),
          buttonLabel: t(context).tr('retry'),
        );
        return;
      }
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
    debugPrint('[Payment] saved-card charge: pm=${card.stripeId}, amount=${amount.round()}');
    final result = await StripeService.createPaymentIntent(
      bookingId: _pendingBookingId,
      amount: amount.round(),
      type: _stripeType,
      orderId: _pendingOrderId,
      incidentId: _ctx?.incidentId,
      paymentMethodId: card.stripeId,
      change: _extensionChangePayload,
    );

    if (!mounted) return;
    _pendingBookingId ??= result.bookingId;

    switch (result.type) {
      case PaymentResultType.offSessionSucceeded:
        await _verifyAndComplete();
        return;

      case PaymentResultType.offSessionRequiresAction:
        // SCA (3DS) prompt — Stripe SDK ukáže overlay přímo v appce.
        if (result.clientSecret != null) {
          bool ok = false;
          try {
            ok = await StripeService.handleNextAction(result.clientSecret!);
          } catch (e) {
            debugPrint('[Payment] handleNextAction err: $e');
          }
          if (!mounted) return;
          if (ok) {
            await _verifyAndComplete();
            return;
          }
        }
        // Ověření kartou (3DS) neproběhlo — chyba se „Zkusit znovu".
        setState(() => _processing = false);
        _attempts++;
        _handleSavedCardFailure(result);
        return;

      case PaymentResultType.offSessionFailed:
        debugPrint('[Payment] saved-card failed: ${result.errorMessage} '
            '(decline=${result.declineCode})');
        setState(() => _processing = false);
        _attempts++;
        _handleSavedCardFailure(result);
        return;

      case PaymentResultType.error:
        setState(() => _processing = false);
        _attempts++;
        _handleIntentError(result);
        return;

      default:
        // Neočekávaný stav (např. backend vrátil běžný intent místo off-session)
        // — místo Payment Sheetu raději ukážeme chybu, aby zákazník s uloženou
        // kartou neviděl zadávání karty.
        setState(() => _processing = false);
        _attempts++;
        _handleSavedCardFailure(result);
        return;
    }
  }

  /// Chybová hláška pro selhání stržení uložené karty (declined / expired /
  /// SCA zrušeno). Ukážeme konkrétní příčinu (nedostatek prostředků, blokace,
  /// expirace, banka zamítla…) přes `PaymentErrorMapper`.
  ///
  /// DŮLEŽITÉ (požadavek zákazníka): tlačítko „Zkusit znovu" znovu strhne
  /// ULOŽENOU kartu — NIKDY samo neotevře Stripe Payment Sheet (zadávání karty).
  /// Po vyčerpání pokusů (maxPaymentAttempts) jde uživatel do Rezervací, kde si
  /// může kartu změnit v profilu. Payment Sheet se na platbě s uloženou kartou
  /// už nezobrazí.
  void _handleSavedCardFailure(PaymentResult result) {
    if (_attempts >= maxPaymentAttempts) {
      _handleMaxAttempts();
      return;
    }
    if (result.errorCode == PaymentErrorCode.authExpired) {
      _showError(
        title: t(context).tr('sessionExpired'),
        message: '${result.errorMessage ?? ''}\n${t(context).tr('bookingSaved')}',
        buttonLabel: t(context).tr('login'),
        onButton: () {
          if (mounted) context.go(Routes.login);
        },
      );
      return;
    }
    final info = PaymentErrorMapper.fromEdge(
      declineCode: result.declineCode,
      rawMessage: result.errorMessage,
      lang: t(context).lang,
    );
    final counter =
        '\n\n(${t(context).tr('attempt')} $_attempts ${t(context).tr('of')} $maxPaymentAttempts)';
    _showError(
      title: info.title,
      message: info.message + counter,
      buttonLabel: t(context).tr('retry'),
      onButton: () {
        // Znovu strhni ULOŽENOU kartu (žádný Payment Sheet).
        final card = ref.read(defaultCardProvider);
        if (!mounted) return;
        if (card != null && card.stripeId.isNotEmpty) {
          setState(() => _processing = true);
          _chargeSavedCard(_amount, card);
        } else {
          // Uložená karta zmizela (smazaná v profilu) → klasický flow.
          _runPaymentSheetFlow(_amount);
        }
      },
    );
  }

  /// Klasický flow s Payment Sheetem (zachová původní chování).
  Future<void> _runPaymentSheetFlow(double amount) async {
    if (mounted) setState(() => _processing = true);

    debugPrint('[Payment] createPaymentIntent: amount=${amount.round()}, type=$_stripeType');
    final result = await StripeService.createPaymentIntent(
      bookingId: _pendingBookingId,
      amount: amount.round(),
      type: _stripeType,
      orderId: _pendingOrderId,
      incidentId: _ctx?.incidentId,
      change: _extensionChangePayload,
    );

    if (!mounted) return;

    debugPrint('[Payment] createPaymentIntent result: type=${result.type}, '
        'hasSecret=${result.clientSecret != null}, '
        'customerId=${result.customerId}, '
        'hasEphemeral=${result.ephemeralKey != null}, '
        'error=${result.errorMessage}');

    if (result.type == PaymentResultType.intent &&
        result.clientSecret != null) {
      _pendingBookingId ??= result.bookingId;

      // Vlastní in-app sheet (CardField + Google Pay) místo nativního Payment
      // Sheetu — pole „Číslo karty" je celé klikací a jde do něj vložit číslo
      // ze schránky. Uloženou kartu sem flow nepustí (řeší _chargeSavedCard).
      final sheetResult = await CardPaymentSheet.show(
        context,
        clientSecret: result.clientSecret!,
        amount: amount,
      );

      if (!mounted) return;

      switch (sheetResult.status) {
        case CardSheetStatus.paid:
          await _verifyAndComplete();
          break;
        case CardSheetStatus.processing:
          // Stripe platbu zatím NEPOTVRDIL (PaymentIntent = Processing). Doklady
          // se NESMÍ vystavit dokud potvrzení nepřijde ze serveru (webhook).
          await _awaitProcessingConfirmation();
          break;
        case CardSheetStatus.cancelled:
          // Zákazník zavřel sheet — žádná chyba, jen reset.
          setState(() => _processing = false);
          break;
        case CardSheetStatus.failed:
          setState(() => _processing = false);
          _attempts++;
          if (sheetResult.stripeError != null) {
            _handleStripeError(sheetResult.stripeError!);
          } else {
            _handleGatewayError(
                sheetResult.otherError ?? 'card payment failed');
          }
          break;
      }
    } else if (result.type == PaymentResultType.free) {
      _onPaymentSuccess();
    } else {
      setState(() => _processing = false);
      _attempts++;
      _handleIntentError(result);
    }
  }

  // -- Error display helpers --

  void _showError({
    required String title,
    required String message,
    required String buttonLabel,
    VoidCallback? onButton,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    PaymentErrorSheet.show(
      context,
      title: title,
      message: message,
      buttonLabel: buttonLabel,
      onButton: onButton,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
    );
  }

  void _handleMaxAttempts() {
    _showError(
      title: t(context).tr('paymentFailed'),
      message: '${t(context).tr('paymentFailedAfterAttempts')} $_attempts ${t(context).tr('paymentFailedAttemptsRest')}',
      buttonLabel: t(context).tr('goToReservations'),
      onButton: () {
        if (mounted) context.go(Routes.reservations);
      },
    );
  }

  void _handleStripeError(StripeException e) {
    final lang = t(context).lang;
    final info = PaymentErrorMapper.fromStripeException(e, lang);
    // Uživatel jen zavřel Payment Sheet — není to chyba, jen reset.
    if (info.userCancelled) {
      setState(() => _processing = false);
      return;
    }
    if (_attempts >= maxPaymentAttempts) {
      _handleMaxAttempts();
      return;
    }
    final counter =
        '\n\n(${t(context).tr('attempt')} $_attempts ${t(context).tr('of')} $maxPaymentAttempts)';
    _showError(
      title: info.title,
      message: info.message + counter,
      buttonLabel: t(context).tr('retry'),
    );
  }

  void _handleGatewayError(Object error) {
    debugPrint('[Payment] GATEWAY ERROR: $error');
    debugPrint('[Payment] Error type: ${error.runtimeType}');
    if (_attempts >= maxPaymentAttempts) {
      _handleMaxAttempts();
      return;
    }
    final lang = t(context).lang;
    final raw = error.toString();
    // Google Pay / Apple Pay selhání (typicky OR_BIBED_11) — navedeme zákazníka
    // na zaplacení kartou, která funguje vždy, místo nicneříkajícího dumpu.
    final isWallet = raw.contains('OR_BIBED') ||
        raw.toLowerCase().contains('google pay') ||
        raw.toLowerCase().contains('googlepay') ||
        raw.toLowerCase().contains('wallet') ||
        raw.toLowerCase().contains('apple pay');
    final info = isWallet
        ? PaymentErrorMapper.wallet(lang,
            rawCode: raw.contains('OR_BIBED') ? 'OR_BIBED_11' : null)
        : PaymentErrorMapper.generic(lang);
    final counter =
        '\n\n(${t(context).tr('attempt')} $_attempts ${t(context).tr('of')} $maxPaymentAttempts)';
    _showError(
      title: info.title,
      message: info.message + counter,
      buttonLabel: t(context).tr('retry'),
    );
  }

  void _handleIntentError(PaymentResult result) {
    if (_attempts >= maxPaymentAttempts) {
      _handleMaxAttempts();
      return;
    }

    final code = result.errorCode;
    final msg = result.errorMessage ?? '';

    if (code == PaymentErrorCode.authExpired) {
      _showError(
        title: t(context).tr('sessionExpired'),
        message: '$msg\n${t(context).tr('bookingSaved')}',
        buttonLabel: t(context).tr('login'),
        onButton: () {
          if (mounted) context.go(Routes.login);
        },
      );
      return;
    }

    final String title;
    if (code == PaymentErrorCode.timeout) {
      title = t(context).tr('serverNotResponding');
    } else if (code == PaymentErrorCode.networkError) {
      title = t(context).tr('connectionError');
    } else {
      title = t(context).tr('paymentCannotProcess');
    }

    _showError(
      title: title,
      message: '$msg\n\n(${t(context).tr('attempt')} $_attempts ${t(context).tr('of')} $maxPaymentAttempts)',
      buttonLabel: t(context).tr('retry'),
    );
  }

  Future<void> _verifyAndComplete() async {
    showMotoGoToast(context,
        icon: '\u231b', title: t(context).tr('verifyingPayment'), message: t(context).tr('waitingConfirmation'));

    final confirmed = await _serverConfirmed();
    if (!mounted) return;

    if (confirmed) {
      _onPaymentSuccess();
    } else if (_ctx?.flowType == PaymentFlowType.extension) {
      // Succeeded PI = Stripe doplatek potvrdil; serverový signál pro velký
      // payload (změna se nevejde do Stripe metadat) neexistuje → dokonči na
      // základě potvrzeného PI, jinak by zaplacená úprava nešla nikdy uložit.
      _onPaymentSuccess();
    } else {
      // Webhook ještě nepotvrdil → NEvystavuj doklady; ukaž průběžný stav.
      _showProcessingPending();
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
      final expected =
          (_ctx?.pendingEditChanges?['total_price'] as num?)?.toDouble();
      final bid = _pendingBookingId;
      if (expected == null || bid == null) return false;
      for (var i = 0; i < maxAttempts; i++) {
        try {
          final row = await MotoGoSupabase.client
              .from('bookings')
              .select('total_price')
              .eq('id', bid)
              .maybeSingle();
          final cur = (row?['total_price'] as num?)?.toDouble();
          if (cur != null && (cur - expected).abs() < 0.5) return true;
        } catch (_) {/* keep polling */}
        await Future.delayed(interval);
      }
      return false;
    }
    if (_pendingBookingId != null) {
      return StripeService.pollBookingPaymentStatus(_pendingBookingId!,
          maxAttempts: maxAttempts, interval: interval);
    }
    return false;
  }

  /// PaymentIntent je ve stavu `Processing` — Stripe platbu NEPOTVRDIL. Nikdy
  /// nevystavuj doklady optimisticky; počkej na serverové potvrzení a když
  /// nedorazí v okně, ukaž „platba se zpracovává" (potvrzení + doklady dorazí
  /// e-mailem) BEZ vystavení dokladu / aplikace úpravy.
  Future<void> _awaitProcessingConfirmation() async {
    showMotoGoToast(context,
        icon: '⌛',
        title: t(context).tr('verifyingPayment'),
        message: t(context).tr('waitingConfirmation'));

    final confirmed = await _serverConfirmed(maxAttempts: 10);
    if (!mounted) return;

    if (confirmed) {
      _onPaymentSuccess();
    } else {
      _showProcessingPending();
    }
  }

  /// Průběžný stav: platba běží, ale server ji zatím nepotvrdil. Žádné doklady
  /// se nevystavují — potvrzení i doklady dorazí e-mailem po potvrzení webhookem.
  void _showProcessingPending() {
    if (_completed) return;
    _completed = true;
    _countdownTimer?.cancel();
    ref.read(paymentContextProvider.notifier).state = null;
    final tr = t(context);
    showMotoGoToast(context,
        icon: '⏳',
        title: tr.tr('verifyingPayment'),
        message: '${tr.tr('waitingConfirmation')} ${tr.tr('successEmailSent')}');
    context.go(Routes.reservations);
  }

  /// Potvrzen\u00ed rezervace pln\u011b pokryt\u00e9 slevou (0 K\u010d). KRITICK\u00c9: \u00fasp\u011bch se
  /// NESM\u00cd p\u0159edst\u00edrat \u2014 d\u0159\u00edv se v\u00fdsledek confirm_free ignoroval, z\u00e1kazn\u00edk
  /// vid\u011bl d\u011bkovac\u00ed str\u00e1nku, ale rezervace z\u016fstala `unpaid` a za 10 minut
  /// p\u0159i\u0161el storno mail. Te\u010f flow pokra\u010duje na \u00fasp\u011bch JEN kdy\u017e backend
  /// rezervaci re\u00e1ln\u011b ozna\u010dil jako zaplacenou.
  Future<void> _confirmFree() async {
    setState(() => _processing = true);

    if (_isNewBooking) {
      _draftError = null;
      _pendingBookingId ??= await _createDraftBooking();
      if (_pendingBookingId == null) {
        if (!mounted) return;
        setState(() => _processing = false);
        _showError(
          title: t(context).tr('bookingCreateFailed'),
          message: _draftError != null
              ? '$_draftError\n\n${t(context).tr('tryAgainPlease')}'
              : t(context).tr('bookingCreateUnknownError'),
          buttonLabel: t(context).tr('retry'),
        );
        return;
      }
    }

    final bookingId = _pendingBookingId;
    if (bookingId == null) {
      // Nem\u011blo by nastat (free flow je v\u017edy booking) \u2014 bez ID nen\u00ed co potvrdit.
      if (!mounted) return;
      setState(() => _processing = false);
      _handleGatewayError('missing booking id for free confirm');
      return;
    }

    final result = await StripeService.confirmFreeBooking(bookingId);
    if (!mounted) return;

    // Fallback poll pokr\u00fdv\u00e1 i p\u0159\u00edpad \u201eji\u017e zaplaceno" (409 z duplicate guardu).
    final confirmed = result.type == PaymentResultType.free ||
        await StripeService.pollBookingPaymentStatus(bookingId, maxAttempts: 3);
    if (!mounted) return;

    if (!confirmed) {
      setState(() => _processing = false);
      _attempts++;
      _handleIntentError(result);
      return;
    }

    showMotoGoToast(context,
        icon: '\u2713',
        title: t(context).tr('confirmed'),
        message: t(context).tr('discountCoversAll'));
    await Future.delayed(const Duration(milliseconds: 500));
    _onPaymentSuccess();
  }

  Future<void> _onPaymentSuccess() async {
    if (_completed) return;
    _completed = true;
    _countdownTimer?.cancel();
    ref.read(paymentContextProvider.notifier).state = null;

    // Force refresh reservation data so UI shows updated state immediately
    ref.invalidate(reservationsProvider);
    if (_pendingBookingId != null) {
      ref.invalidate(reservationByIdProvider(_pendingBookingId!));
    }

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
        InvoiceService.generateAdvanceInvoice(
            _pendingBookingId!, ref.read(priceBreakdownProvider).total);
        InvoiceService.generateBookingDocs(_pendingBookingId!);
      }
      // Create shop order for upsell items (fire-and-forget)
      final upsellItems = ref.read(bookingUpsellProvider);
      if (upsellItems.isNotEmpty) {
        createBookingUpsellOrder(upsellItems);
        ref.read(bookingUpsellProvider.notifier).clear();
      }
      showMotoGoToast(context,
          icon: '\u2713', title: t(context).tr('paid'), message: t(context).tr('bookingConfirmed'));
      // D\u011bkovac\u00ed str\u00e1nka si na\u010dte stav doklad\u016f + typ motorky podle tohoto ID.
      ref.read(lastConfirmedBookingProvider.notifier).state = _pendingBookingId;
      context.go(Routes.success);
    } else {
      final tr = t(context);
      final amountStr = Money.czk(_ctx!.amount);
      void goResult(PaymentOutcome outcome) {
        ref.read(paymentOutcomeProvider.notifier).state = outcome;
        context.go(Routes.paymentResult);
      }

      switch (_ctx!.flowType) {
        case PaymentFlowType.extension:
          // VÝMĚNA MOTORKY — doplatek (net>0) byl právě zaplacen → teprve TEĎ se smí
          // provést server-side COMMIT výměny (RPC split_booking_moto_swap dry_run:false),
          // který zkrátí původní rezervaci, vytvoří druhou (paid) a sám rozešle její
          // „reserved" mail + smlouvu. COMMIT se NIKDY nevolá před vypořádáním platby.
          final swapCommit = _ctx!.pendingEditChanges?['_swap_commit'];
          if (swapCommit is Map) {
            // Commit s kontrolou VÝSLEDKU + retry. `already_split` /
            // `invalid_new_moto` = commit už provedl webhook (`_swap` metadata)
            // → v pořádku. Když selžou všechny pokusy, webhook je pojistka —
            // definitivní selhání obou cest loguje server (swap_commit_failed).
            var committed = false;
            for (var attempt = 0; attempt < 3 && !committed; attempt++) {
              if (attempt > 0) await Future.delayed(const Duration(seconds: 2));
              try {
                final res = await MotoGoSupabase.client.rpc('split_booking_moto_swap', params: {
                  'p_booking_id': swapCommit['p_booking_id'],
                  'p_new_moto_id': swapCommit['p_new_moto_id'],
                  'p_swap_date': swapCommit['p_swap_date'],
                  'p_swap_time': swapCommit['p_swap_time'],
                  'p_dry_run': false,
                });
                final code = res is Map ? res['error']?.toString() : null;
                committed = (res is Map && res['success'] == true) ||
                    code == 'already_split' ||
                    code == 'invalid_new_moto';
                if (!committed) debugPrint('[Payment] swap commit failed: $code');
              } catch (e) {
                debugPrint('[Payment] swap commit err: $e');
              }
            }
            ref.invalidate(reservationsProvider);
            if (_pendingBookingId != null) {
              ref.invalidate(reservationByIdProvider(_pendingBookingId!));
            }
            if (!mounted) return;
            goResult(
              PaymentOutcome(
                title: tr.tr('paid'),
                subtitle: tr.tr('swap.successTitle'),
                lines: [PaymentOutcomeLine('💳', '${_ctx!.label}: $amountStr')],
                nextStepNote: tr.tr('successEmailSent'),
                ctaLabel: tr.tr('successCta'),
                ctaRoute: Routes.reservations,
              ),
            );
            return;
          }
          // Apply pending edit changes ONLY after Stripe payment is confirmed.
          // Mirrors _onInlinePaymentSuccess from Capacitor payment-ui-3.js.
          if (_pendingBookingId != null && _ctx!.pendingEditChanges != null) {
            try {
              // `_extras_rows` / `_extras_replace` jsou interní klíče (nový stav
              // doplňků) — do bookings UPDATE nepatří. Při `_extras_replace`
              // nejdřív smažeme modelované řádky (i odebrání) a pak vložíme nové.
              final pending =
                  Map<String, dynamic>.from(_ctx!.pendingEditChanges!);
              final extrasRows = pending.remove('_extras_rows');
              final extrasReplace = pending.remove('_extras_replace') == true;
              await MotoGoSupabase.client
                  .from('bookings')
                  .update(pending)
                  .eq('id', _pendingBookingId!);
              if (extrasReplace) {
                try {
                  await MotoGoSupabase.client
                      .from('booking_extras')
                      .delete()
                      .eq('booking_id', _pendingBookingId!)
                      .inFilter('name', const [
                    'Výbava spolujezdce', 'Boty řidiče', 'Boty spolujezdce',
                  ]);
                } catch (_) {/* ignore */}
              }
              if (extrasRows is List && extrasRows.isNotEmpty) {
                await MotoGoSupabase.client
                    .from('booking_extras')
                    .insert(extrasRows);
              }
            } catch (e) {
              debugPrint('[Payment] Edit apply err: $e');
            }
          }
          if (_pendingBookingId != null) {
            EmailService.sendBookingModified(_pendingBookingId!);
            InvoiceService.generateAdvanceInvoice(
                _pendingBookingId!, _ctx!.amount);
            InvoiceService.generateBookingDocs(_pendingBookingId!);
          }
          if (!mounted) return;
          goResult(
            PaymentOutcome(
              title: tr.tr('paid'),
              subtitle: tr.tr('bookingChangesConfirmed'),
              lines: [PaymentOutcomeLine('\ud83d\udcb3', '${_ctx!.label}: $amountStr')],
              nextStepNote: tr.tr('successEmailSent'),
              ctaLabel: tr.tr('successCta'),
              ctaRoute: Routes.reservations,
            ),
          );
        case PaymentFlowType.sos:
          // Invoice generation handled by backend (Supabase trigger/edge function)
          goResult(
            PaymentOutcome(
              title: tr.tr('paid'),
              subtitle: tr.tr('replacementMotoOrdered'),
              lines: [PaymentOutcomeLine('\ud83d\udcb3', '${_ctx!.label}: $amountStr')],
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
              lines: [PaymentOutcomeLine('\ud83d\udcb3', '${_ctx!.label}: $amountStr')],
              nextStepNote: tr.tr('successEmailSent'),
              ctaLabel: tr.tr('successCta'),
              ctaRoute: Routes.shop,
            ),
          );
        case PaymentFlowType.booking:
          // Resume rozd\u011blan\u00e9 rezervace (FAB \u201eDokon\u010dit rezervaci") = plnohodnotn\u00e1
          // nov\u00e1 rezervace, jen s \u010d\u00e1stkou z DB m\u00edsto draftu \u2014 stejn\u00e9 dokon\u010den\u00ed
          // jako u draft flow: mail, z\u00e1lohov\u00e1 faktura, dokumenty, /success.
          if (_pendingBookingId != null) {
            EmailService.sendBookingReserved(_pendingBookingId!);
            InvoiceService.generateAdvanceInvoice(
                _pendingBookingId!, _ctx!.amount);
            InvoiceService.generateBookingDocs(_pendingBookingId!);
            showMotoGoToast(context,
                icon: '\u2713',
                title: tr.tr('paid'),
                message: tr.tr('bookingConfirmed'));
            ref.read(lastConfirmedBookingProvider.notifier).state =
                _pendingBookingId;
            context.go(Routes.success);
            return;
          }
          goResult(
            PaymentOutcome(
              title: tr.tr('paid'),
              subtitle: tr.tr('paymentCompleted'),
              lines: [PaymentOutcomeLine('\ud83d\udcb3', '${_ctx!.label}: $amountStr')],
              nextStepNote: tr.tr('successEmailSent'),
              ctaLabel: tr.tr('successCta'),
              ctaRoute: Routes.reservations,
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final moto = ref.watch(bookingMotoProvider);
    final breakdown = ref.watch(priceBreakdownProvider);
    final defaultCard = ref.watch(defaultCardProvider);
    final amount = _amount;
    final isFree = amount <= 0;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            const PaymentHeader(),

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
                        extras: ref.read(bookingDraftProvider).extras,
                        upsellItems: ref.watch(bookingUpsellProvider),
                      ),
                    if (!_isNewBooking)
                      PaymentContextCard(
                        displayLabel: _displayLabel,
                        amount: amount,
                        isFree: isFree,
                        sosBreakdown: _ctx?.sosBreakdown,
                        sosDepositNote: _ctx?.sosDepositNote,
                      ),
                    const SizedBox(height: 12),

                    // Upsell section (new booking only)
                    if (_isNewBooking && moto != null)
                      UpsellSection(
                        insurancePrice: moto.insurancePrice,
                        showProducts: ref.watch(reservationUpsellEnabledProvider).maybeWhen(data: (v) => v, orElse: () => false),
                        insuranceSelected: _insuranceSelected,
                        onInsuranceChanged: (v) =>
                            setState(() => _insuranceSelected = v),
                      ),
                    if (_isNewBooking && moto != null)
                      const SizedBox(height: 12),

                    // Saved card info
                    if (defaultCard != null && !isFree)
                      SavedCardPreview(card: defaultCard),

                    if (!isFree)
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
              amount: amount,
              isFree: isFree,
              processing: _processing,
              onPay: _doPayment,
            ),
          ],
        ),
      ),
    );
  }
}
