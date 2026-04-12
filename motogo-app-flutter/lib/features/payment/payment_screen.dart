import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_provider.dart';
import '../booking/booking_models.dart';
import '../booking/widgets/price_summary.dart';
import 'stripe_service.dart';
import 'payment_provider.dart';
import 'email_service.dart';
import 'invoice_service.dart';
import 'widgets/moto_gallery_card.dart';
import 'widgets/upsell_section.dart';
import 'widgets/saved_card_preview.dart';
import 'widgets/payment_header_widgets.dart';

/// Payment screen — rich summary with motorcycle gallery, price breakdown,
/// upsells, and native Stripe Payment Sheet (no browser redirect).
///
/// Supports all flow types: booking, edit surcharge, SOS, shop.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _processing = false;
  String? _pendingBookingId;
  String? _pendingOrderId;
  int _attempts = 0;
  Timer? _countdownTimer;
  late DateTime _deadline;
  String _timeRemaining = '10:00';
  bool _insuranceSelected = false;

  PaymentContext? _ctx;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(paymentTimeoutDuration);
    _startCountdown();
    _ctx = ref.read(paymentContextProvider);
    if (_ctx != null) {
      _pendingBookingId = _ctx!.bookingId;
      _pendingOrderId = _ctx!.orderId;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // -- Helpers --

  bool get _isNewBooking => _ctx == null;
  String get _stripeType => _ctx?.flowType.name ?? 'booking';

  double get _amount {
    final base = _ctx != null
        ? _ctx!.amount
        : ref.read(priceBreakdownProvider).total;
    if (_insuranceSelected && _isNewBooking) {
      final moto = ref.read(bookingMotoProvider);
      return base + (moto?.insurancePrice ?? 0);
    }
    return base;
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
    showMotoGoToast(context,
        icon: '\u2717',
        title: t(context).tr('timeExpired'),
        message: 'Platba automaticky zrušena');
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) context.go(Routes.reservations);
  }

  // -- Draft booking (new booking only) --

  Future<String?> _createDraftBooking() async {
    final draft = ref.read(bookingDraftProvider);
    final moto = ref.read(bookingMotoProvider);
    final breakdown = ref.read(priceBreakdownProvider);
    final user = MotoGoSupabase.currentUser;
    if (user == null || moto == null) return null;

    try {
      final res = await MotoGoSupabase.client.rpc(
        'create_web_booking',
        params: {
          'p_moto_id': moto.id,
          'p_start_date': draft.startDate != null
              ? '${draft.startDate!.year}-${draft.startDate!.month.toString().padLeft(2, "0")}-${draft.startDate!.day.toString().padLeft(2, "0")}'
              : '',
          'p_end_date': draft.endDate != null
              ? '${draft.endDate!.year}-${draft.endDate!.month.toString().padLeft(2, "0")}-${draft.endDate!.day.toString().padLeft(2, "0")}'
              : '',
          'p_name': user.userMetadata?['full_name'] as String? ?? user.email?.split('@').first ?? '',
          'p_email': user.email ?? '',
          'p_phone': user.userMetadata?['phone'] as String? ?? '',
          'p_pickup_time': draft.pickupTime ?? '09:00',
          'p_delivery_address': draft.pickupMethod == 'delivery'
              ? draft.pickupAddress
              : null,
          'p_return_address': draft.returnMethod == 'delivery'
              ? draft.returnAddress
              : null,
          'p_extras': draft.extras
              .map((e) => {
                    'name': e.name,
                    'quantity': e.quantity,
                    'unit_price': e.price,
                    if (e.size != null) 'size': e.size,
                  })
              .toList(),
          'p_helmet_size': draft.helmetSize,
          'p_jacket_size': draft.jacketSize,
          'p_pants_size': draft.pantsSize,
          'p_boots_size': draft.bootsSize,
          'p_gloves_size': draft.glovesSize,
          'p_discount_amount': breakdown.discountTotal,
          'p_discount_code': draft.discounts.isNotEmpty
              ? draft.discounts.first.code
              : null,
          'p_promo_code': draft.discounts
              .where((d) =>
                  d.type == DiscountType.percent ||
                  d.type == DiscountType.fixed)
              .map((d) => d.code)
              .firstOrNull,
        },
      );
      if (res is Map && res['booking_id'] != null) {
        return res['booking_id'] as String;
      }
      return null;
    } catch (_) {
      return null;
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
      _pendingBookingId ??= await _createDraftBooking();
      if (_pendingBookingId == null && mounted) {
        setState(() => _processing = false);
        showMotoGoToast(context,
            icon: '\u2717',
            title: 'Chyba',
            message: 'Nepodařilo se vytvořit rezervaci');
        return;
      }
    }

    // Create PaymentIntent (mode: intent)
    final result = await StripeService.createPaymentIntent(
      bookingId: _pendingBookingId,
      amount: amount.round(),
      type: _stripeType,
      orderId: _pendingOrderId,
      incidentId: _ctx?.incidentId,
    );

    if (!mounted) return;

    if (result.type == PaymentResultType.intent &&
        result.clientSecret != null) {
      _pendingBookingId ??= result.bookingId;

      // Present native Stripe Payment Sheet (with saved cards support)
      try {
        final paid = await StripeService.presentPaymentSheet(
          clientSecret: result.clientSecret!,
          customerId: result.customerId,
          ephemeralKey: result.ephemeralKey,
        );

        if (!mounted) return;

        if (paid) {
          // Verify payment status on backend
          await _verifyAndComplete();
        } else {
          // User cancelled Payment Sheet
          setState(() => _processing = false);
        }
      } on StripeException catch (e) {
        if (!mounted) return;
        setState(() => _processing = false);
        _attempts++;
        final msg = e.error.localizedMessage ?? 'Platba zamítnuta';
        if (_attempts >= maxPaymentAttempts) {
          showMotoGoToast(context,
              icon: '\u2717',
              title: 'Platba zamítnuta',
              message: 'Překročen max. počet pokusů');
          context.go(Routes.reservations);
        } else {
          showMotoGoToast(context,
              icon: '\u2717',
              title: 'Platba zamítnuta',
              message: '$msg ($_attempts/$maxPaymentAttempts)');
        }
      }
    } else if (result.type == PaymentResultType.free) {
      _onPaymentSuccess();
    } else {
      setState(() => _processing = false);
      _attempts++;
      if (_attempts >= maxPaymentAttempts) {
        showMotoGoToast(context,
            icon: '\u2717',
            title: 'Platba zamítnuta',
            message: 'Překročen max. počet pokusů');
        context.go(Routes.reservations);
      } else {
        showMotoGoToast(context,
            icon: '\u2717',
            title: 'Chyba',
            message: result.errorMessage ??
                'Zkuste to znovu ($_attempts/$maxPaymentAttempts)');
      }
    }
  }

  Future<void> _verifyAndComplete() async {
    showMotoGoToast(context,
        icon: '\u231b', title: t(context).tr('verifyingPayment'), message: t(context).tr('waitingConfirmation'));

    bool paid = false;
    if (_pendingOrderId != null) {
      paid = await StripeService.pollOrderPaymentStatus(_pendingOrderId!);
    } else if (_pendingBookingId != null) {
      paid = await StripeService.pollBookingPaymentStatus(_pendingBookingId!);
    } else {
      paid = true; // No ID to poll — trust Payment Sheet success
    }

    if (!mounted) return;

    if (paid) {
      _onPaymentSuccess();
    } else {
      // Payment Sheet succeeded but DB not yet updated — trust it
      _onPaymentSuccess();
    }
  }

  Future<void> _confirmFree() async {
    setState(() => _processing = true);
    if (_isNewBooking) {
      _pendingBookingId ??= await _createDraftBooking();
      if (_pendingBookingId != null) {
        await StripeService.confirmFreeBooking(_pendingBookingId!);
      }
    }
    showMotoGoToast(context,
        icon: '\u2713',
        title: 'Potvrzeno',
        message: 'Sleva pokrývá celou cenu');
    await Future.delayed(const Duration(milliseconds: 500));
    _onPaymentSuccess();
  }

  void _onPaymentSuccess() {
    _countdownTimer?.cancel();
    ref.read(paymentContextProvider.notifier).state = null;

    if (_isNewBooking) {
      if (_pendingBookingId != null) {
        EmailService.sendBookingReserved(_pendingBookingId!);
        InvoiceService.generateAdvanceInvoice(
            _pendingBookingId!, ref.read(priceBreakdownProvider).total);
        InvoiceService.generateBookingDocs(_pendingBookingId!);
      }
      showMotoGoToast(context,
          icon: '\u2713', title: 'Zaplaceno', message: 'Rezervace potvrzena');
      context.go(Routes.success);
    } else {
      switch (_ctx!.flowType) {
        case PaymentFlowType.extension:
          showMotoGoToast(context,
              icon: '\u2713',
              title: 'Zaplaceno',
              message: 'Změny v rezervaci potvrzeny');
          if (_pendingBookingId != null) {
            EmailService.sendBookingModified(_pendingBookingId!);
            InvoiceService.generateAdvanceInvoice(
                _pendingBookingId!, _ctx!.amount);
            InvoiceService.generateBookingDocs(_pendingBookingId!);
          }
          context.go(Routes.reservations);
        case PaymentFlowType.sos:
          // Invoice generation handled by backend (Supabase trigger/edge function)
          showMotoGoToast(context,
              icon: '\u2713',
              title: 'Zaplaceno',
              message: 'Náhradní motorka objednána');
          context.go(Routes.sosDone);
        case PaymentFlowType.shop:
          showMotoGoToast(context,
              icon: '\u2713',
              title: 'Zaplaceno',
              message: 'Objednávka potvrzena');
          context.go(Routes.shop);
        case PaymentFlowType.booking:
          showMotoGoToast(context,
              icon: '\u2713', title: 'Zaplaceno', message: 'Platba proběhla');
          context.go(Routes.reservations);
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
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '\ud83d\udd12 \u0160ifrovan\u00e1 platba \u00b7 Stripe PCI DSS Level 1',
                          style: TextStyle(fontSize: 10, color: MotoGoColors.g400),
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
