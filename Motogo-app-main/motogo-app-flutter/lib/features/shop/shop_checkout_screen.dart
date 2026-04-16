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
  final _streetCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  bool _processing = false;
  bool _promoExpanded = false;
  bool _promoLoading = false;
  String? _promoMsg;
  bool? _promoOk;

  @override
  void initState() {
    super.initState();
    _autofill();
  }

  Future<void> _autofill() async {
    try {
      final profile = await ref.read(profileProvider.future);
      if (!mounted || profile == null) return;
      _nameCtrl.text = profile['full_name'] ?? '';
      _streetCtrl.text = profile['street'] ?? '';
      _zipCtrl.text = profile['zip'] ?? '';
      _cityCtrl.text = profile['city'] ?? '';
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _streetCtrl.dispose();
    _zipCtrl.dispose();
    _cityCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  /// Apply promo / voucher code inline.
  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;

    final appliedCodes = ref.read(shopAppliedCodesProvider);

    // Already applied?
    if (appliedCodes.any((d) => d.code == code.toUpperCase())) {
      setState(() {
        _promoMsg = t(context).tr('promoAlreadyUsed').replaceAll('{code}', code.toUpperCase());
        _promoOk = false;
      });
      return;
    }

    setState(() { _promoLoading = true; _promoMsg = null; });

    final result = await validateAndApplyCode(code);
    if (!mounted) return;
    setState(() => _promoLoading = false);

    if (result.success && result.discount != null) {
      final d = result.discount!;
      // Can't combine two percentage codes
      if (d.type == DiscountType.percent &&
          appliedCodes.any((c) => c.type == DiscountType.percent)) {
        setState(() {
          _promoMsg = t(context).tr('promoNoCombinePercent');
          _promoOk = false;
        });
        return;
      }
      _promoCtrl.clear();
      ref.read(shopAppliedCodesProvider.notifier).state = [...appliedCodes, d];
      _recalcShopDiscount();
      setState(() { _promoMsg = result.message(t(context).tr); _promoOk = true; });
    } else {
      setState(() { _promoMsg = result.message(t(context).tr); _promoOk = false; });
    }
  }

  /// Remove an applied code.
  void _removeCode(String code) {
    final updated = ref
        .read(shopAppliedCodesProvider)
        .where((c) => c.code != code)
        .toList();
    ref.read(shopAppliedCodesProvider.notifier).state = updated;
    _recalcShopDiscount();
    setState(() {});
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
    // Mark applied voucher codes as redeemed
    final codes = ref.read(shopAppliedCodesProvider);
    if (codes.isNotEmpty) {
      markVouchersRedeemed(codes);
    }
    ref.read(cartProvider.notifier).clear();
    ref.read(shopAppliedCodesProvider.notifier).state = [];
    ref.read(shopDiscountProvider.notifier).state = 0;
    showMotoGoToast(context,
        icon: '✅',
        title: t(context).tr('orderReceived'),
        message: t(context).tr('confirmOnEmail'));
    context.go(Routes.shop);
  }

  Future<void> _finalize() async {
    final cart = ref.read(cartProvider);
    final shipMode = ref.read(shipModeProvider);
    final discount = ref.read(shopDiscountProvider);
    final digitalOnly = isCartDigitalOnly(cart);

    if (cart.isEmpty) {
      showMotoGoToast(context,
          icon: '⚠️',
          title: t(context).tr('cart'),
          message: t(context).tr('cartEmpty'));
      return;
    }

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

    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final shipping =
        digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0.0);
    final total = (subtotal + shipping - discount).clamp(0.0, double.infinity);

    if (total <= 0) {
      try {
        await MotoGoSupabase.client.rpc('confirm_shop_payment',
            params: {'p_order_id': orderId, 'p_method': 'voucher'});
      } catch (_) {}
      _onSuccess();
      return;
    }

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
          await confirmShopPayment(orderId, 'card');
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
      } catch (e) {
        if (!mounted) return;
        setState(() => _processing = false);
        showMotoGoToast(context,
            icon: '✗',
            title: t(context).tr('paymentGatewayError'),
            message: t(context).tr('paymentGatewayErrorDesc'));
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

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final shipMode = ref.watch(shipModeProvider);
    final discount = ref.watch(shopDiscountProvider);
    final appliedCodes = ref.watch(shopAppliedCodesProvider);
    final digitalOnly = isCartDigitalOnly(cart);
    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final shipping =
        digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0.0);
    final total = (subtotal + shipping - discount).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(context).tr('checkout'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900)),
            Text(t(context).tr('completeOrder'),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70)),
          ],
        ),
        backgroundColor: MotoGoColors.dark,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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

                    // ── Promo / voucher code card ──
                    _buildPromoCard(appliedCodes),

                    // Summary
                    CheckoutSummarySection(
                      cart: cart,
                      digitalOnly: digitalOnly,
                      shipMode: shipMode,
                      shipping: shipping,
                      discount: discount,
                      total: total,
                    ),

                    const SizedBox(height: 80),
                  ]),
            ),
          ),

          // Sticky pay button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50)),
                    elevation: 0,
                  ),
                  child: _processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
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

  /// Promo code card — inline expandable (no bottom sheet).
  Widget _buildPromoCard(List<AppliedDiscount> appliedCodes) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [
          BoxShadow(
              color: MotoGoColors.black.withValues(alpha: 0.1),
              blurRadius: 20)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '🏷️ ${t(context).tr('discountCode').toUpperCase()} / ${t(context).tr('giftVoucher').toUpperCase()}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.g400,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),

        // Tap to expand inline input
        if (!_promoExpanded)
          GestureDetector(
            onTap: () => setState(() => _promoExpanded = true),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                border: Border.all(color: MotoGoColors.g200, width: 1.5),
              ),
              child: Row(children: [
                Icon(Icons.add_circle_outline,
                    size: 16, color: MotoGoColors.g400),
                const SizedBox(width: 8),
                Text(t(context).tr('discountCode'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MotoGoColors.g400)),
                const Spacer(),
                const Text('›',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: MotoGoColors.g400)),
              ]),
            ),
          ),

        // Expanded: inline input + apply button
        if (_promoExpanded) ...[
          Row(children: [
            Expanded(
              child: TextField(
                controller: _promoCtrl,
                autofocus: false,
                textCapitalization: TextCapitalization.characters,
                onSubmitted: (_) => _applyPromo(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.black),
                decoration: InputDecoration(
                  hintText: t(context).tr('enterCodeHint'),
                  hintStyle: const TextStyle(fontSize: 13, color: MotoGoColors.g400),
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: MotoGoColors.g200, width: 2)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: MotoGoColors.green, width: 2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _promoLoading ? null : _applyPromo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.dark,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(80, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _promoLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(t(context).tr('apply').toUpperCase(),
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
          ]),

          // Result message
          if (_promoMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _promoOk == true ? '✓ $_promoMsg' : _promoMsg!,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _promoOk == true
                        ? MotoGoColors.greenDarker
                        : MotoGoColors.red),
              ),
            ),
        ],

        // Applied codes list
        if (appliedCodes.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final d in appliedCodes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  borderRadius:
                      BorderRadius.circular(MotoGoTheme.radiusSm),
                  border: Border.all(
                      color: MotoGoColors.green.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Text(
                    d.type == DiscountType.percent
                        ? '🏷️ ${d.code} (−${d.value.toStringAsFixed(0)}%)'
                        : '🎁 ${d.code} (−${d.value.toStringAsFixed(0)} Kč)',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MotoGoColors.greenDarker),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _removeCode(d.code),
                    child: const Text('✕',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: MotoGoColors.red)),
                  ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }
}
