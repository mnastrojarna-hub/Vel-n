import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_provider.dart';
import 'stripe_service.dart';
import 'payment_provider.dart';

/// Payment screen — mirrors s-payment from templates-screens-booking.js +
/// payment-ui.js + payment-ui-2.js.
///
/// Shows price summary, saved card preview, pay button, countdown timer.
/// Payment goes through Stripe Checkout redirect.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with WidgetsBindingObserver {
  bool _processing = false;
  bool _stripeOpened = false;
  String? _pendingBookingId;
  int _attempts = 0;
  Timer? _countdownTimer;
  late DateTime _deadline;
  String _timeRemaining = '10:00';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deadline = DateTime.now().add(paymentTimeoutDuration);
    _startCountdown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Detect app resume after Stripe redirect.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stripeOpened) {
      _checkPaymentAfterStripe();
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        _countdownTimer?.cancel();
        setState(() => _timeRemaining = 'Čas vypršel');
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
    showMotoGoToast(context, icon: '✗', title: 'Čas vypršel',
        message: 'Rezervace automaticky zrušena');
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) context.go(Routes.reservations);
  }

  Future<void> _doPayment() async {
    if (_processing || _stripeOpened) return;
    final breakdown = ref.read(priceBreakdownProvider);
    final draft = ref.read(bookingDraftProvider);

    if (breakdown.total <= 0) {
      await _confirmFree();
      return;
    }

    setState(() => _processing = true);

    final result = await StripeService.createCheckoutSession(
      bookingId: draft.motoId, // Will be set by proceedToPayment in booking flow
      amount: breakdown.total.round(),
      type: 'booking',
    );

    if (!mounted) return;

    if (result.type == PaymentResultType.checkout && result.checkoutUrl != null) {
      _pendingBookingId = result.bookingId;
      setState(() { _stripeOpened = true; _processing = false; });
      await StripeService.openCheckout(result.checkoutUrl!);
    } else if (result.type == PaymentResultType.free) {
      _onPaymentSuccess();
    } else {
      setState(() => _processing = false);
      _attempts++;
      if (_attempts >= maxPaymentAttempts) {
        showMotoGoToast(context, icon: '✗', title: 'Platba zamítnuta',
            message: 'Překročen max. počet pokusů');
        context.go(Routes.reservations);
      } else {
        showMotoGoToast(context, icon: '✗', title: 'Platba zamítnuta',
            message: 'Zkuste to znovu ($_attempts/$maxPaymentAttempts)');
      }
    }
  }

  Future<void> _confirmFree() async {
    setState(() => _processing = true);
    showMotoGoToast(context, icon: '✓', title: 'Potvrzeno',
        message: 'Sleva pokrývá celou cenu');
    await Future.delayed(const Duration(milliseconds: 500));
    _onPaymentSuccess();
  }

  Future<void> _checkPaymentAfterStripe() async {
    if (_pendingBookingId == null) return;
    showMotoGoToast(context, icon: '⏳', title: 'Ověřuji platbu...',
        message: 'Čekám na potvrzení');

    final paid = await StripeService.pollBookingPaymentStatus(
      _pendingBookingId!,
    );

    if (!mounted) return;
    setState(() => _stripeOpened = false);

    if (paid) {
      _onPaymentSuccess();
    } else {
      showMotoGoToast(context, icon: 'ℹ️', title: 'Platba se ověřuje',
          message: 'Zkontrolujte v Moje rezervace');
      context.go(Routes.reservations);
    }
  }

  void _onPaymentSuccess() {
    _countdownTimer?.cancel();
    showMotoGoToast(context, icon: '✓', title: 'Zaplaceno',
        message: 'Rezervace potvrzena');
    context.go(Routes.success);
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = ref.watch(priceBreakdownProvider);
    final defaultCard = ref.watch(defaultCardProvider);
    final isFree = breakdown.total <= 0;

    return PopScope(
      canPop: !_stripeOpened,
      child: Scaffold(
        backgroundColor: MotoGoColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                decoration: const BoxDecoration(
                  color: MotoGoColors.dark,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    if (!_stripeOpened)
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                          child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))),
                        ),
                      ),
                    if (!_stripeOpened) const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Platba', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                        Text('Bezpečná platba přes Stripe', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5))),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Countdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('⏱ ', style: TextStyle(fontSize: 14)),
                            Text(
                              'Zbývá $_timeRemaining na zaplacení',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Payment card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                          boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Text('💳', style: TextStyle(fontSize: 20)),
                                SizedBox(width: 8),
                                Text('Platební karta', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Saved card preview
                            if (defaultCard != null && !isFree)
                              _SavedCardPreview(card: defaultCard),

                            if (!isFree)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Po kliknutí na tlačítko budete přesměrováni na bezpečnou platební bránu Stripe.',
                                  style: TextStyle(fontSize: 11, color: MotoGoColors.g400, height: 1.5),
                                  textAlign: TextAlign.center,
                                ),
                              ),

                            if (isFree)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: MotoGoColors.greenPale,
                                  borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                                  border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
                                ),
                                child: const Text(
                                  '✓ Sleva pokrývá celou cenu — platba kartou není potřeba',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Encryption badge
                      const Text(
                        '🔒 Šifrovaná platba · Stripe PCI DSS Level 1',
                        style: TextStyle(fontSize: 10, color: MotoGoColors.g400),
                      ),
                    ],
                  ),
                ),
              ),

              // Pay button
              Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))],
                ),
                child: ElevatedButton(
                  onPressed: (_processing || _stripeOpened) ? null : _doPayment,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: _processing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            SizedBox(width: 10),
                            Text('Zpracovávám platbu...'),
                          ],
                        )
                      : _stripeOpened
                          ? const Text('⏳ Čekám na potvrzení platby...')
                          : Text(isFree
                              ? 'Potvrdit rezervaci zdarma →'
                              : 'Zaplatit ${breakdown.total.toStringAsFixed(0)} Kč →'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedCardPreview extends StatelessWidget {
  final SavedCard card;
  const _SavedCardPreview({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MotoGoColors.greenPale,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: MotoGoColors.green, width: 2),
      ),
      child: Row(
        children: [
          const Text('💳', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•••• ${card.last4}  ${card.displayBrand}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black),
                ),
                Text(
                  '${card.displayExpiry}${card.holderName != null ? ' · ${card.holderName}' : ''}',
                  style: const TextStyle(fontSize: 11, color: MotoGoColors.g400),
                ),
              ],
            ),
          ),
          const Text('Předvyplněno', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
        ],
      ),
    );
  }
}
