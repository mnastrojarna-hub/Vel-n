import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../payment/stripe_service.dart';
import '../payment/payment_provider.dart';
import 'shop_models.dart';
import 'shop_provider.dart';

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
    _nameCtrl.dispose(); _streetCtrl.dispose();
    _zipCtrl.dispose(); _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _finalize() async {
    final cart = ref.read(cartProvider);
    final shipMode = ref.read(shipModeProvider);
    final discount = ref.read(shopDiscountProvider);
    final digitalOnly = isCartDigitalOnly(cart);

    if (cart.isEmpty) {
      showMotoGoToast(context, icon: '⚠️', title: 'Košík', message: 'Košík je prázdný');
      return;
    }

    // Validate address for physical orders
    if (!digitalOnly && shipMode == ShipMode.post) {
      if (_nameCtrl.text.trim().isEmpty || _streetCtrl.text.trim().isEmpty || _cityCtrl.text.trim().isEmpty) {
        showMotoGoToast(context, icon: '⚠️', title: 'Adresa', message: 'Vyplňte doručovací adresu');
        return;
      }
    }

    setState(() => _processing = true);

    // Create order via RPC
    final address = digitalOnly ? null : {
      'name': _nameCtrl.text.trim(),
      'street': _streetCtrl.text.trim(),
      'zip': _zipCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
    };

    final orderId = await createShopOrder(
      items: cart,
      shipping: digitalOnly ? ShipMode.digital : shipMode,
      address: address,
    );

    if (orderId == null) {
      if (mounted) showMotoGoToast(context, icon: '✗', title: 'Chyba', message: 'Nepodařilo se vytvořit objednávku');
      setState(() => _processing = false);
      return;
    }

    // Calculate total
    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final shipping = digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0.0);
    final total = (subtotal + shipping - discount).clamp(0.0, double.infinity);

    if (total <= 0) {
      // 100% discount — confirm without payment
      try {
        await MotoGoSupabase.client.rpc('confirm_shop_payment', params: {'p_order_id': orderId, 'p_method': 'voucher'});
      } catch (_) {}
      _onSuccess();
      return;
    }

    // Stripe payment
    final result = await StripeService.createCheckoutSession(
      amount: total.round(),
      type: 'shop',
      orderId: orderId,
    );

    if (!mounted) return;

    if (result.type == PaymentResultType.checkout && result.checkoutUrl != null) {
      await StripeService.openCheckout(result.checkoutUrl!);
      // Poll for payment
      final paid = await StripeService.pollOrderPaymentStatus(orderId);
      if (paid) {
        _onSuccess();
      } else {
        showMotoGoToast(context, icon: 'ℹ️', title: 'Platba', message: 'Stav bude aktualizován');
        context.go(Routes.shop);
      }
    } else if (result.type == PaymentResultType.free) {
      _onSuccess();
    } else {
      showMotoGoToast(context, icon: '✗', title: 'Chyba', message: result.errorMessage ?? 'Platba selhala');
    }

    if (mounted) setState(() => _processing = false);
  }

  void _onSuccess() {
    ref.read(cartProvider.notifier).clear();
    ref.read(shopDiscountProvider.notifier).state = 0;
    showMotoGoToast(context, icon: '✅', title: 'Objednávka přijata', message: 'Potvrzení na email');
    context.go(Routes.shop);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final shipMode = ref.watch(shipModeProvider);
    final discount = ref.watch(shopDiscountProvider);
    final digitalOnly = isCartDigitalOnly(cart);
    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final shipping = digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0.0);
    final total = (subtotal + shipping - discount).clamp(0.0, double.infinity);
    final defaultCard = ref.watch(defaultCardProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(title: const Text('Pokladna'), backgroundColor: MotoGoColors.dark),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Shipping method (hide for digital)
                if (!digitalOnly) ...[
                  const Text('Způsob doručení', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                  const SizedBox(height: 8),
                  _ShipOption(label: '📦 Poštou', sublabel: '99 Kč · 2-4 dny', active: shipMode == ShipMode.post,
                    onTap: () => ref.read(shipModeProvider.notifier).state = ShipMode.post),
                  const SizedBox(height: 6),
                  _ShipOption(label: '🏪 Osobní odběr', sublabel: 'Zdarma · Mezná 9', active: shipMode == ShipMode.pickup,
                    onTap: () => ref.read(shipModeProvider.notifier).state = ShipMode.pickup),
                  const SizedBox(height: 16),
                ],

                // Address (only for post)
                if (!digitalOnly && shipMode == ShipMode.post) ...[
                  const Text('Doručovací adresa', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                  const SizedBox(height: 8),
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Jméno a příjmení')),
                  const SizedBox(height: 8),
                  TextField(controller: _streetCtrl, decoration: const InputDecoration(labelText: 'Ulice a č.p.')),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(flex: 2, child: TextField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'Město'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _zipCtrl, decoration: const InputDecoration(labelText: 'PSČ'), keyboardType: TextInputType.number)),
                  ]),
                  const SizedBox(height: 16),
                ],

                // Saved card preview
                if (defaultCard != null)
                  Container(
                    padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm), border: Border.all(color: MotoGoColors.green)),
                    child: Row(children: [
                      const Text('💳', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Text('•••• ${defaultCard.last4}  ${defaultCard.displayBrand}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    ]),
                  ),

                // Summary
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Položky', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                      Text('${subtotal.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                    if (shipping > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Doprava', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                      Text('${shipping.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ])),
                    if (discount > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Sleva', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                      Text('−${discount.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
                    ])),
                    const Divider(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Celkem', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                      Text('${total.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),

          // Pay button
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            color: Colors.white,
            child: ElevatedButton(
              onPressed: _processing ? null : _finalize,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _processing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(total <= 0 ? 'Potvrdit objednávku (zdarma) →' : 'Zaplatit ${total.toStringAsFixed(0)} Kč →'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipOption extends StatelessWidget {
  final String label; final String sublabel; final bool active; final VoidCallback onTap;
  const _ShipOption({required this.label, required this.sublabel, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? MotoGoColors.greenPale : Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g200, width: active ? 2 : 1),
      ),
      child: Row(children: [
        Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g400, width: 2)),
          child: active ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: MotoGoColors.green))) : null),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
          Text(sublabel, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
        ])),
      ]),
    ),
  );
}
