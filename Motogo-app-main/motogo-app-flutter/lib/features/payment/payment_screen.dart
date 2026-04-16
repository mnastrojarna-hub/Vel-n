import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/pending_booking_fab_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_provider.dart';
import '../booking/booking_models.dart';
import '../booking/widgets/price_summary.dart';
import '../reservations/reservation_provider.dart' show releaseDoorCodes, reservationsProvider, reservationByIdProvider;
import 'booking_upsell_provider.dart';
import 'stripe_service.dart';
import 'payment_provider.dart';
import 'email_service.dart';
import 'invoice_service.dart';
import 'widgets/moto_gallery_card.dart';
import 'widgets/upsell_section.dart';
import 'widgets/saved_card_preview.dart';
import 'widgets/payment_header_widgets.dart';
import 'widgets/payment_error_sheet.dart';

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

    String _fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

    final pickupMethod =
        draft.pickupMethod == 'delivery' ? 'delivery' : 'branch';
    final returnMethod =
        draft.returnMethod == 'delivery' ? 'delivery' : 'branch';

    try {
      // Direct insert into bookings table (matches original Capacitor app)
      final res = await MotoGoSupabase.client.from('bookings').insert({
        'user_id': user.id,
        'moto_id': moto.id,
        'start_date': draft.startDate != null ? _fmtDate(draft.startDate!) : '',
        'end_date': draft.endDate != null ? _fmtDate(draft.endDate!) : '',
        'pickup_time': draft.pickupTime ?? '09:00',
        'total_price': breakdown.total,
        'extras_price': breakdown.extrasTotal,
        'delivery_fee': breakdown.deliveryFee,
        'discount_amount': breakdown.discountTotal,
        'discount_code': draft.discounts.isNotEmpty
            ? draft.discounts.first.code
            : null,
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
      }).select().single();

      final bookingId = res['id'] as String?;
      if (bookingId == null) {
        _draftError = t(context).tr('noBookingId');
        return null;
      }

      // Save extras to booking_extras table (fire-and-forget, like original)
      _saveBookingExtras(bookingId, draft.extras);

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

    // Create PaymentIntent (mode: intent)
    debugPrint('[Payment] createPaymentIntent: amount=${amount.round()}, type=$_stripeType');
    final result = await StripeService.createPaymentIntent(
      bookingId: _pendingBookingId,
      amount: amount.round(),
      type: _stripeType,
      orderId: _pendingOrderId,
      incidentId: _ctx?.incidentId,
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

      // Present native Stripe Payment Sheet (with saved cards support)
      try {
        final paid = await StripeService.presentPaymentSheet(
          clientSecret: result.clientSecret!,
          customerId: result.customerId,
          ephemeralKey: result.ephemeralKey,
        );

        if (!mounted) return;

        if (paid) {
          await _verifyAndComplete();
        } else {
          // User cancelled Payment Sheet — no error, just reset
          setState(() => _processing = false);
        }
      } on StripeException catch (e) {
        if (!mounted) return;
        setState(() => _processing = false);
        _attempts++;
        _handleStripeError(e);
      } catch (e) {
        if (!mounted) return;
        setState(() => _processing = false);
        _attempts++;
        _handleGatewayError(e);
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
    if (_attempts >= maxPaymentAttempts) {
      _handleMaxAttempts();
      return;
    }
    final stripeMsg = e.error.localizedMessage ?? '';
    _showError(
      title: t(context).tr('paymentCardDeclined'),
      message: stripeMsg.isNotEmpty
          ? '$stripeMsg\n\n'
              '${t(context).tr('tryDifferentCard')} '
              '(${t(context).tr('attempt')} $_attempts ${t(context).tr('of')} $maxPaymentAttempts)'
          : '${t(context).tr('bankDeclined')} '
              '${t(context).tr('tryDifferentCard')} '
              '(${t(context).tr('attempt')} $_attempts ${t(context).tr('of')} $maxPaymentAttempts)',
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
    _showError(
      title: t(context).tr('paymentGatewayError'),
      message: '${t(context).tr('paymentGatewayErrorDesc')}\n\n'
          'DEBUG INFO:\n'
          'Typ: ${error.runtimeType}\n'
          'Detail: $error\n\n'
          '(${t(context).tr('attempt')} $_attempts ${t(context).tr('of')} $maxPaymentAttempts)',
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
        title: t(context).tr('confirmed'),
        message: t(context).tr('discountCoversAll'));
    await Future.delayed(const Duration(milliseconds: 500));
    _onPaymentSuccess();
  }

  Future<void> _onPaymentSuccess() async {
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
      context.go(Routes.success);
    } else {
      switch (_ctx!.flowType) {
        case PaymentFlowType.extension:
          // Apply pending edit changes ONLY after Stripe payment is confirmed.
          // Mirrors _onInlinePaymentSuccess from Capacitor payment-ui-3.js.
          if (_pendingBookingId != null && _ctx!.pendingEditChanges != null) {
            try {
              await MotoGoSupabase.client
                  .from('bookings')
                  .update(_ctx!.pendingEditChanges!)
                  .eq('id', _pendingBookingId!);
            } catch (e) {
              debugPrint('[Payment] Edit apply err: $e');
            }
          }
          showMotoGoToast(context,
              icon: '\u2713',
              title: t(context).tr('paid'),
              message: t(context).tr('bookingChangesConfirmed'));
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
              title: t(context).tr('paid'),
              message: t(context).tr('replacementMotoOrdered'));
          context.go(Routes.sosDone);
        case PaymentFlowType.shop:
          showMotoGoToast(context,
              icon: '\u2713',
              title: t(context).tr('paid'),
              message: t(context).tr('orderConfirmed'));
          context.go(Routes.shop);
        case PaymentFlowType.booking:
          showMotoGoToast(context,
              icon: '\u2713', title: t(context).tr('paid'), message: t(context).tr('paymentCompleted'));
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
