import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/auth_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_models.dart';
import '../booking/price_calculator.dart';
import '../payment/stripe_service.dart';
import '../payment/payment_provider.dart';
import '../payment/payment_error_mapper.dart';
import '../payment/widgets/payment_error_sheet.dart';
import '../payment/widgets/card_payment_sheet.dart';
import '../payment/payment_refusals.dart';
import '../payment/payment_ui_helpers.dart';
import '../../core/payment_pending_marker.dart';
import 'shop_models.dart';
import 'shop_provider.dart';
import 'widgets/checkout_payment_card.dart';
import 'widgets/checkout_shipping_section.dart';
import 'widgets/checkout_summary_section.dart';
import '../../core/currency.dart';
import '../../core/widgets/mg_nav_controls.dart';

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
  // Založená, zatím nezaplacená objednávka — další pokus o platbu ji použije
  // znovu, dokud se košík / kódy / doprava nezmění (dřív každý pokus = nová
  // čekající objednávka).
  String? _orderId;
  double? _orderTotal;
  String? _orderSig;
  String? _clientSecret;

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

  /// Apply promo code inline. V e-shopu platí JEN promo kódy (2026-09-24):
  /// dárkový poukaz / poukaz ze Slevomatu ne, a na nákup poukazu žádný kód.
  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final appliedCodes = ref.read(shopAppliedCodesProvider);

    // Already applied?
    if (appliedCodes.any((d) => d.code == code)) {
      setState(() {
        _promoMsg = t(context).tr('promoAlreadyUsed').replaceAll('{code}', code);
        _promoOk = false;
      });
      return;
    }
    if (ref.read(cartProvider).any((i) => i.id.startsWith('voucher'))) {
      setState(() {
        _promoMsg = t(context).tr('shopCodeNotForVoucher');
        _promoOk = false;
      });
      return;
    }

    setState(() { _promoLoading = true; _promoMsg = null; });

    final check = await validateShopPromoCode(code);
    if (!mounted) return;
    setState(() => _promoLoading = false);

    final d = check.discount;
    if (d == null) {
      // Konkrétní důvod (vypršel / vyčerpaný / bez internetu…), ne jen „neplatný".
      setState(() {
        _promoMsg = t(context).tr(check.reasonKey).replaceAll('{code}', code);
        _promoOk = false;
      });
      return;
    }
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
    setState(() {
      _promoMsg = t(context).tr('discountApplied').replaceAll('{value}',
          d.type == DiscountType.percent ? '${d.value}%' : Money.czk(d.value));
      _promoOk = true;
    });
  }

  /// Srozumitelná hláška k chybě ze serveru při založení objednávky.
  String _orderErrorText(ShopOrderResult o) {
    final tr = t(context);
    switch (o.error) {
      case 'voucher_not_allowed':
        return tr.tr('shopVoucherNotAllowed');
      case 'code_not_allowed_for_voucher':
        return tr.tr('shopCodeNotForVoucher');
      case 'code_invalid':
        return tr.tr('shopCodeInvalid').replaceAll('{code}', o.code ?? '');
      case 'out_of_stock':
        return tr.tr('shopOutOfStock');
      case 'product_not_found':
      case 'bad_size':
        return tr.tr('shopProductUnavailable');
      case 'bad_shipping':
        return tr.tr('psOrderBadShipping');
      case 'multiple_percent':
        return tr.tr('promoNoCombinePercent');
      case 'network':
        return tr.tr('psOrderNet');
    }
    return tr.tr('psOrderFail');
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

  /// Košík a kódy pryč, objednávka hotová (nebo se platba ověřuje).
  void _clearCheckout() {
    ref.read(cartProvider.notifier).clear();
    ref.read(shopAppliedCodesProvider.notifier).state = [];
    ref.read(shopDiscountProvider.notifier).state = 0;
    _orderId = null;
    _orderSig = null;
    _orderTotal = null;
  }

  Future<void> _onSuccess(String orderId, {bool free = false}) async {
    PaymentPendingMarker.clear(orderId);
    _clearCheckout();

    // Potvrzení odráží reálný stav objednávky z DB (číslo, stav platby, částka),
    // ne jen obecný toast. Při chybě fetche fallback na původní toast.
    Map<String, dynamic>? order;
    try {
      order = await MotoGoSupabase.client
          .from('shop_orders')
          .select('order_number, total, payment_status')
          .eq('id', orderId)
          .maybeSingle();
    } catch (_) {/* fallback níže */}
    if (!mounted) return;

    // Jednotná potvrzovací obrazovka jako u ostatních platebních flow — zákazník
    // po objednávce vždy uvidí plné potvrzení (zaplaceno + číslo + částka + co dál),
    // ne jen mizící toast nebo dialog.
    final tr = t(context);
    final orderNumber = order?['order_number']?.toString();
    final total = (order?['total'] as num?)?.toDouble() ?? 0;
    final paid = order != null && order['payment_status'] == 'paid';

    ref.read(paymentOutcomeProvider.notifier).state = PaymentOutcome(
      // Objednávka za 0 Kč (sleva pokryla vše) — nic se neplatilo.
      title: free ? tr.tr('psOrderFreeTitle') : tr.tr('paid'),
      subtitle: free
          ? tr.tr('psOrderFreeSub')
          : (paid ? tr.tr('orderConfirmed') : tr.tr('paymentProcessed')),
      lines: [
        if (orderNumber != null) PaymentOutcomeLine('🧾', '#$orderNumber'),
        if (total > 0)
          PaymentOutcomeLine('💳', '${tr.tr('totalPrice')}: ${Money.czk(total)}'),
      ],
      nextStepNote: tr.tr('confirmOnEmail'),
      ctaLabel: tr.tr('close'),
      ctaRoute: Routes.shop,
    );
    context.go(Routes.paymentResult);
  }

  /// Otisk košíku + kódů + dopravy + adresy: dokud se nezmění, další pokus
  /// o platbu použije už založenou objednávku.
  String _signature(Map<String, String>? address, ShipMode ship) => jsonEncode({
        'c': ref.read(cartProvider).map((i) => '${i.id}x${i.qty}').toList(),
        'p': ref.read(shopAppliedCodesProvider).map((d) => d.code).toList(),
        's': ship.name,
        'a': address,
      });

  void _showOrderError(String message) {
    PaymentErrorSheet.show(
      context,
      title: t(context).tr('psOrderFailTitle'),
      message: message,
      buttonLabel: t(context).tr('retry'),
      onButton: _finalize,
      secondaryLabel: t(context).tr('psWriteUs'),
      onSecondary: () => openContactUs(context),
    );
  }

  /// Platba se ověřuje (banka ji zatím nepotvrdila) — košík pryč, aby
  /// zákazník nezaplatil podruhé; výsledek ověří obrazovka „Platba se ověřuje".
  Future<void> _goPending(String orderId) async {
    await PaymentPendingMarker.set(orderId, clientSecret: _clientSecret);
    if (!mounted) return;
    final tr = t(context);
    final verified = PaymentOutcome(
      title: tr.tr('paid'),
      subtitle: tr.tr('orderConfirmed'),
      nextStepNote: tr.tr('confirmOnEmail'),
      ctaLabel: tr.tr('close'),
      ctaRoute: Routes.shop,
    );
    _clearCheckout();
    ref.read(paymentOutcomeProvider.notifier).state =
        pendingOrderOutcome(tr, orderId: orderId, verified: verified);
    context.go(Routes.paymentResult);
  }

  /// Nejasná chyba po odeslání platby — rozhodne stav PaymentIntentu.
  Future<void> _resolveUnclear(String orderId, Object error,
      {bool wallet = false}) async {
    final cs = _clientSecret;
    final st = cs == null ? null : await StripeService.fetchIntentStatus(cs);
    if (!mounted) return;
    switch (StripeService.outcomeForStatus(st)) {
      case NextActionOutcome.succeeded:
        await StripeService.pollOrderPaymentStatus(orderId,
            maxAttempts: 8, interval: const Duration(seconds: 1));
        if (mounted) _onSuccess(orderId);
      case NextActionOutcome.processing:
      case NextActionOutcome.unknown:
        await _goPending(orderId);
      case NextActionOutcome.notCompleted:
      case NextActionOutcome.failed:
        await PaymentPendingMarker.clear(orderId);
        if (!mounted) return;
        final lang = t(context).lang;
        final info = wallet
            ? PaymentErrorMapper.walletFailed(lang)
            : PaymentErrorMapper.generic(lang);
        PaymentErrorSheet.show(context,
            title: info.title,
            message: info.message,
            buttonLabel: t(context).tr('retry'),
            onButton: _finalize);
    }
  }

  Future<void> _finalize() async {
    if (_processing) return;
    final cart = ref.read(cartProvider);
    final shipMode = ref.read(shipModeProvider);
    final discount = ref.read(shopDiscountProvider);
    final digitalOnly = isCartDigitalOnly(cart);
    final lang = t(context).lang;

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

    // Kartou jde zaplatit nejméně 15 Kč — řekni to PŘED založením objednávky.
    final subtotal = ref.read(cartProvider.notifier).subtotal;
    final shipping =
        digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0.0);
    final clientTotal =
        (subtotal + shipping - discount).clamp(0.0, double.infinity);
    if (belowCardMinimum(clientTotal)) {
      _showBelowMinimum(clientTotal);
      return;
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
    final ship = digitalOnly ? ShipMode.digital : shipMode;
    final sig = _signature(address, ship);

    String orderId;
    double total;
    if (_orderId != null && _orderSig == sig) {
      // Stejný obsah jako minulý pokus → stejná objednávka (žádné duplicity).
      orderId = _orderId!;
      total = _orderTotal ?? clientTotal;
    } else {
      final order = await createShopOrder(
        items: cart,
        shipping: ship,
        address: address,
        promoCode: ref.read(shopAppliedCodesProvider).isNotEmpty
            ? ref
                .read(shopAppliedCodesProvider)
                .map((d) => d.code)
                .join(',')
            : null,
        language: ref.read(localeProvider).languageCode,
      );
      if (!mounted) return;
      final id = order.orderId;
      if (id == null) {
        setState(() => _processing = false);
        _showOrderError(_orderErrorText(order));
        return;
      }
      orderId = id;
      // Cenu počítá SERVER (create_shop_order v2) — platí se jeho částka;
      // objednávku za 0 Kč server rovnou potvrdil.
      total = order.total ?? clientTotal;
      if (order.autoConfirmed || total <= 0) {
        setState(() => _processing = false);
        _onSuccess(orderId, free: true);
        return;
      }
      _orderId = orderId;
      _orderTotal = total;
      _orderSig = sig;
    }

    if (belowCardMinimum(total)) {
      setState(() => _processing = false);
      _showBelowMinimum(total);
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
      final cs = result.clientSecret!;
      _clientSecret = cs;
      // Vlastní in-app sheet (CardField + Google Pay) místo nativního Payment
      // Sheetu — celé pole karty klikací + vkládání ze schránky.
      final sheetResult = await CardPaymentSheet.show(
        context,
        clientSecret: cs,
        amount: total,
        onSubmitting: () => PaymentPendingMarker.set(orderId, clientSecret: cs),
      );
      if (!mounted) return;
      switch (sheetResult.status) {
        case CardSheetStatus.paid:
          // Stripe platbu potvrdil; objednávku označí jako zaplacenou webhook
          // (service role) — klient ji sám potvrdit nesmí (confirm_shop_payment
          // je od 2026-09-24 jen pro server/admina). Krátce počkej na webhook,
          // ať děkovací stránka ukáže „potvrzeno"; když nestihne, ukáže
          // „platba zpracována" a potvrzení dorazí e-mailem.
          await StripeService.pollOrderPaymentStatus(orderId,
              maxAttempts: 8, interval: const Duration(seconds: 1));
          if (!mounted) break;
          _onSuccess(orderId);
        case CardSheetStatus.processing:
          // Stripe platbu zatím NEPOTVRDIL (PaymentIntent = Processing).
          // Nepotvrzuj objednávku optimisticky — počkej na serverové potvrzení
          // (webhook). Když nedorazí v okně, obrazovka „Platba se ověřuje"
          // (košík pryč — žádná druhá platba).
          final ok = await StripeService.pollOrderPaymentStatus(orderId,
              maxAttempts: 10, interval: const Duration(seconds: 1));
          if (!mounted) break;
          if (ok) {
            _onSuccess(orderId);
          } else {
            await _goPending(orderId);
          }
        case CardSheetStatus.cancelled:
          await PaymentPendingMarker.clear(orderId);
        case CardSheetStatus.failed:
          final e = sheetResult.stripeError;
          final info = e != null
              ? PaymentErrorMapper.fromStripeException(e, lang,
                  wallet: sheetResult.wallet)
              : null;
          if (info != null && info.userCancelled) {
            await PaymentPendingMarker.clear(orderId);
            break; // jen zavřel sheet — není chyba
          }
          if (info == null || info.needsVerification) {
            // Bez kódu karty — nevíme, jestli platba prošla → ověřit.
            await _resolveUnclear(orderId, e ?? sheetResult.otherError ?? 'failed',
                wallet: sheetResult.wallet);
            break;
          }
          await PaymentPendingMarker.clear(orderId);
          if (!mounted) break;
          if (info.cause == 'amount_too_small') {
            _showBelowMinimum(total);
            break;
          }
          PaymentErrorSheet.show(context,
              title: info.title,
              message: info.message,
              buttonLabel: t(context).tr('retry'),
              onButton: _finalize);
      }
    } else if (result.type == PaymentResultType.free) {
      _onSuccess(orderId);
    } else {
      // Odmítnutí serverem / síť — přeložená hláška s akcí, nikdy text serveru.
      final p = PaymentRefusals.resolve(lang, result, PayFlow.shop, amount: total);
      setState(() => _processing = false);
      switch (p.action) {
        case PayAction.success:
          _onSuccess(orderId);
        case PayAction.pending:
        case PayAction.verify:
          await _goPending(orderId);
        case PayAction.belowMinimum:
          _showBelowMinimum(total);
        default:
          final toCart = p.action == PayAction.toCart;
          if (toCart) {
            // Objednávka už neplatí / cena se změnila → příště založit novou.
            _orderId = null;
            _orderSig = null;
          }
          PaymentErrorSheet.show(context,
              title: p.title,
              message: p.message,
              buttonLabel: p.action == PayAction.signIn
                  ? t(context).tr('login')
                  : toCart
                      ? t(context).tr('psSendAgain')
                      : t(context).tr('retry'),
              onButton: p.action == PayAction.signIn
                  ? () => context.go(Routes.login)
                  : _finalize,
              secondaryLabel: p.contact ? t(context).tr('psWriteUs') : null,
              onSecondary: p.contact ? () => openContactUs(context) : null);
      }
    }

    if (mounted) setState(() => _processing = false);
  }

  /// Objednávka pod minimem karty (1–14 Kč) — co s tím (D2).
  void _showBelowMinimum(double total) {
    final tr = t(context);
    final p = PaymentRefusals.belowMinimum(tr.lang, PayFlow.shop, total);
    final hasCodes = ref.read(shopAppliedCodesProvider).isNotEmpty;
    PaymentErrorSheet.show(
      context,
      title: p.title,
      message: p.message,
      buttonLabel: tr.tr('psEditCart'),
      onButton: () => context.backOr(Routes.cart),
      secondaryLabel: hasCodes ? tr.tr('psRemoveCode') : tr.tr('psWriteUs'),
      onSecondary: hasCodes
          ? () {
              for (final c in List.of(ref.read(shopAppliedCodesProvider))) {
                _removeCode(c.code);
              }
            }
          : () => openContactUs(context),
    );
  }

  /// Zpět: během platby jen po potvrzení; bez historie → košík (ne zavření appky).
  Future<void> _onBack() async {
    if (_processing) {
      if (!await confirmLeaveRunningPayment(context)) return;
      if (!mounted) return;
      final id = _orderId;
      if (id != null) {
        // Platba mohla odejít → „Platba se ověřuje" (košík pryč, aby nevznikla
        // druhá objednávka a druhá platba).
        await _goPending(id);
        return;
      }
    }
    if (mounted) context.backOr(Routes.cart);
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

    return BackButtonListener(
      // Bez historie (deep link) → košík; během platby jen s potvrzením.
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
        leading: MgBackTap(
          onTap: _onBack,
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
                child: PressableScale(
                  enabled: !_processing,
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
          ),
        ],
      ),
    ),
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
            '🏷️ ${t(context).tr('discountCode').toUpperCase()}',
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
                        : '🎁 ${d.code} (−${Money.czk(d.value)})',
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
