import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_models.dart';
import '../booking/booking_provider.dart';
import '../booking/price_calculator.dart';
import '../payment/stripe_service.dart';
import '../payment/payment_provider.dart';
import 'shop_models.dart';
import 'shop_provider.dart';
import 'widgets/checkout_payment_card.dart';
import 'widgets/checkout_promo_card.dart';
import 'widgets/checkout_shipping_section.dart';
import 'widgets/checkout_summary_section.dart';

/// Shop checkout — mirrors s-checkout from cart-checkout.js.
/// Address, shipping method, promo code, stock validation, payment.
class ShopCheckoutScreen extends ConsumerStatefulWidget {
  const ShopCheckoutScreen({super.key});

  @override
  ConsumerState<ShopCheckoutScreen> createState() => _CheckoutState();
}

class _CheckoutState extends ConsumerState<ShopCheckoutScreen> {
  final _nameCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  bool _promoLoading = false;
  String? _promoError;
  String? _promoSuccess;
  final _streetCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _autofill();
  }

  Future<void> _autofill() async {
    final profile = await ref.read(profileProvider.future);
    if (profile == null) return;
    _nameCtrl.text = profile['full_name'] ?? '';
    _streetCtrl.text = profile['street'] ?? '';
    _zipCtrl.text = profile['zip'] ?? '';
    _cityCtrl.text = profile['city'] ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promoCtrl.dispose();
    _streetCtrl.dispose();
    _zipCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _finalize() async {
    final cart = ref.read(cartProvider);
    final shipMode = ref.read(shipModeProvider);
    final discount = ref.read(shopDiscountProvider);
    final digitalOnly = isCartDigitalOnly(cart);

    if (cart.isEmpty) {
      showMotoGoToast(context,
          icon: '⚠️', title: t(context).tr('cart'), message: t(context).tr('cartEmpty'));
      return;
    }

    // Validate address for physical orders
    if (!digitalOnly && shipMode == ShipMode.post) {
      if (_nameCtrl.text.trim().isEmpty ||
          _streetCtrl.text.trim().isEmpty ||
          _cityCtrl.text.trim().isEmpty ||
          _zipCtrl.text.trim().isEmpty) {
        showMotoGoToast(context,
            icon: '⚠️',
            title: t(context).tr('deliveryDetails'),
            message: t(context).tr('deliveryDetails'));
        return;
      }
    }

    setState(() => _processing = true);

    // Create order via RPC
    final address = digitalOnly
        ? null
        : {
            'name': _nameCtrl.text.trim(),
            'street': _streetCtrl.text.trim(),
            'zip': _zipCtrl.text.trim(),
            'city': _cityCtrl.text.trim(),
          };

    final orderId = await createShopOrder(
      items: cart,
      shipping: digitalOnly ? ShipMode.digital : shipMode,
      address: address,
      promoCode: ref.read(shopAppliedCodesProvider).isNotEmpty
          ? ref
              .read(shopAppliedCodesProvider)
              .map((d) => d.code)
              .join(',')
          : null,
    );

    if (orderId == null) {
      if (mounted) {
        showMotoGoToast(context,
            icon: '✗',
            title: t(context).tr('error'),
            message: t(context).tr('error'));
      }
      setState(() => _processing = false);
      return;
    }

    // Calculate total
    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final shipping =
        digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0.0);
    final total = (subtotal + shipping - discount).clamp(0.0, double.infinity);

    if (total <= 0) {
      // 100% discount — confirm without payment
      try {
        await MotoGoSupabase.client.rpc('confirm_shop_payment',
            params: {'p_order_id': orderId, 'p_method': 'voucher'});
      } catch (_) {}
      _onSuccess();
      return;
    }

    // Stripe payment — native Payment Sheet (in-app)
    final result = await StripeService.createPaymentIntent(
      amount: total.round(),
      type: 'shop',
      orderId: orderId,
    );

    if (!mounted) return;

    if (result.type == PaymentResultType.intent &&
        result.clientSecret != null) {
      try {
        final paid = await StripeService.presentPaymentSheet(
          clientSecret: result.clientSecret!,
          customerId: result.customerId,
          ephemeralKey: result.ephemeralKey,
        );
        if (!mounted) return;
        if (paid) {
          // Verify on backend
          await StripeService.pollOrderPaymentStatus(orderId);
          _onSuccess();
        } else {
          setState(() => _processing = false);
        }
      } on StripeException catch (e) {
        if (!mounted) return;
        setState(() => _processing = false);
        showMotoGoToast(context,
            icon: '✗',
            title: t(context).tr('error'),
            message: e.error.localizedMessage ?? t(context).tr('error'));
      }
    } else if (result.type == PaymentResultType.free) {
      _onSuccess();
    } else {
      showMotoGoToast(context,
          icon: '✗',
          title: t(context).tr('error'),
          message: result.errorMessage ?? t(context).tr('error'));
    }

    if (mounted) setState(() => _processing = false);
  }

  /// Recalculate shop discount total from applied codes.
  void _recalcShopDiscount() {
    final codes = ref.read(shopAppliedCodesProvider);
    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final shipMode = ref.read(shipModeProvider);
    final cart = ref.read(cartProvider);
    final digitalOnly = isCartDigitalOnly(cart);
    final shipping =
        digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0.0);
    final fullBase = subtotal + shipping;
    final total = PriceCalculator.calcDiscounts(codes, fullBase);
    ref.read(shopDiscountProvider.notifier).state = total;
  }

  void _onSuccess() {
    ref.read(cartProvider.notifier).clear();
    ref.read(shopAppliedCodesProvider.notifier).state = [];
    ref.read(shopDiscountProvider.notifier).state = 0;
    showMotoGoToast(context,
        icon: '✅', title: t(context).tr('orderReceived'), message: t(context).tr('confirmOnEmail'));
    context.go(Routes.shop);
  }

  Future<void> _applyShopCode() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;

    final appliedCodes = ref.read(shopAppliedCodesProvider);

    // Check if already applied
    if (appliedCodes.any((d) => d.code == code.toUpperCase())) {
      setState(() {
        _promoError = 'Kód "${code.toUpperCase()}" je již použit';
        _promoSuccess = null;
      });
      return;
    }

    setState(
        () {
      _promoLoading = true;
      _promoError = null;
      _promoSuccess = null;
    });

    // Uses shared validation — tries promo code AND voucher code
    final result = await validateAndApplyCode(code);

    if (!mounted) return;
    setState(() => _promoLoading = false);

    if (result.success && result.discount != null) {
      final newDiscount = result.discount!;
      // Can't combine two percentage codes
      if (newDiscount.type == DiscountType.percent &&
          appliedCodes.any((d) => d.type == DiscountType.percent)) {
        setState(() {
          _promoError = 'Nelze kombinovat dva procentuální kódy';
          _promoSuccess = null;
        });
        return;
      }
      setState(() {
        _promoSuccess = result.message;
        _promoError = null;
      });
      _promoCtrl.clear();
      ref.read(shopAppliedCodesProvider.notifier).state = [
        ...appliedCodes,
        newDiscount
      ];
      _recalcShopDiscount();
    } else {
      setState(() {
        _promoError = result.message;
        _promoSuccess = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final shipMode = ref.watch(shipModeProvider);
    final discount = ref.watch(shopDiscountProvider);
    final digitalOnly = isCartDigitalOnly(cart);
    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final shipping =
        digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0.0);
    final total = (subtotal + shipping - discount).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(context).tr('checkout'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text(t(context).tr('completeOrder'),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70)),
          ],
        ),
        backgroundColor: MotoGoColors.dark,
        leading: IconButton(
          icon: const Text('←',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Shipping method card (hide for digital)
                if (!digitalOnly)
                  CheckoutShippingSection(
                    nameCtrl: _nameCtrl,
                    streetCtrl: _streetCtrl,
                    zipCtrl: _zipCtrl,
                    cityCtrl: _cityCtrl,
                  ),

                // Payment method card
                const CheckoutPaymentCard(),

                // Promo code card — supports multiple codes, % + fixed, promo + voucher
                CheckoutPromoCard(
                  promoCtrl: _promoCtrl,
                  promoLoading: _promoLoading,
                  promoError: _promoError,
                  promoSuccess: _promoSuccess,
                  onApply: _applyShopCode,
                  onRemoveCode: () {
                    _recalcShopDiscount();
                    setState(() {});
                  },
                ),

                // Summary — full breakdown
                CheckoutSummarySection(
                  cart: cart,
                  digitalOnly: digitalOnly,
                  shipMode: shipMode,
                  shipping: shipping,
                  discount: discount,
                  total: total,
                ),

                // Spacer for sticky button
                const SizedBox(height: 80),
              ]),
            ),
          ),

          // Pay button — sticky at bottom matching original
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: MotoGoColors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4))
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _processing ? null : _finalize,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MotoGoColors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50)),
                    elevation: 0,
                  ),
                  child: _processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(
                          total <= 0
                              ? '✅ ${t(context).tr('confirmOrderFree')}'
                              : '✅ ${t(context).tr('confirm')} & ${t(context).tr('payBtn')} →',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
