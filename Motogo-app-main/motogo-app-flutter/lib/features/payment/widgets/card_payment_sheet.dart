import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';

/// Výsledek vlastního platebního sheetu s kartou.
enum CardSheetStatus { paid, cancelled, failed }

class CardSheetResult {
  final CardSheetStatus status;

  /// Stripe chyba (declined / expired / 3DS selhalo) — caller ji namapuje přes
  /// PaymentErrorMapper.fromStripeException a zachová počítadlo pokusů.
  final StripeException? stripeError;

  /// Jiná chyba (neočekávaný stav PaymentIntentu, gateway error).
  final Object? otherError;

  const CardSheetResult(this.status, {this.stripeError, this.otherError});
}

/// Vlastní in-app sheet pro zadání karty + Google Pay.
///
/// Nahrazuje nativní Stripe Payment Sheet, jehož pole „Číslo karty" mělo malý
/// klikací rámeček a nešlo do něj vložit číslo ze schránky. Tady kreslíme pole
/// sami přes `CardField` (nativní EditText — celý rámeček je klikací a vkládání
/// ze schránky funguje) a platbu potvrdíme přes `Stripe.instance.confirmPayment`
/// proti stejnému PaymentIntentu (client_secret z edge fn `process-payment`).
///
/// POZOR: tento sheet se otevírá JEN když zákazník nemá uloženou kartu. Uloženou
/// (default) kartu strhne `_chargeSavedCard` off-session úplně bez sheetu —
/// zákazník vidí jen „pracuji" a pak výsledek (chyba / děkovací obrazovka).
class CardPaymentSheet {
  CardPaymentSheet._();

  static Future<CardSheetResult> show(
    BuildContext context, {
    required String clientSecret,
    required double amount,
    bool allowGooglePay = true,
  }) async {
    final result = await showModalBottomSheet<CardSheetResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _CardSheetBody(
          clientSecret: clientSecret,
          amount: amount,
          allowGooglePay: allowGooglePay,
        ),
      ),
    );
    return result ?? const CardSheetResult(CardSheetStatus.cancelled);
  }
}

class _CardSheetBody extends StatefulWidget {
  final String clientSecret;
  final double amount;
  final bool allowGooglePay;

  const _CardSheetBody({
    required this.clientSecret,
    required this.amount,
    required this.allowGooglePay,
  });

  @override
  State<_CardSheetBody> createState() => _CardSheetBodyState();
}

class _CardSheetBodyState extends State<_CardSheetBody> {
  bool _cardComplete = false;
  bool _processing = false;
  bool _googlePayReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.allowGooglePay) _checkGooglePay();
  }

  Future<void> _checkGooglePay() async {
    try {
      final ok = await Stripe.instance.isPlatformPaySupported();
      if (mounted) setState(() => _googlePayReady = ok);
    } catch (_) {
      // Google Pay nedostupné na tomto zařízení — zaplatí se kartou.
    }
  }

  bool _isPaid(PaymentIntentsStatus status) =>
      status == PaymentIntentsStatus.Succeeded ||
      status == PaymentIntentsStatus.RequiresCapture ||
      status == PaymentIntentsStatus.Processing;

  Future<void> _payWithCard() async {
    if (_processing || !_cardComplete) return;
    setState(() => _processing = true);
    try {
      // confirmPayment použije kartu z vykresleného CardFieldu a sám dotáhne
      // případné 3DS (SCA) — vrací finální stav PaymentIntentu.
      final intent = await Stripe.instance.confirmPayment(
        paymentIntentClientSecret: widget.clientSecret,
        data: PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _isPaid(intent.status)
            ? const CardSheetResult(CardSheetStatus.paid)
            : CardSheetResult(CardSheetStatus.failed,
                otherError: 'intent status: ${intent.status}'),
      );
    } on StripeException catch (e) {
      if (!mounted) return;
      // Zákazník zavřel 3DS / zrušil — zůstaň v sheetu, ať může zkusit znovu.
      if (e.error.code == FailureCode.Canceled) {
        setState(() => _processing = false);
        return;
      }
      Navigator.of(context)
          .pop(CardSheetResult(CardSheetStatus.failed, stripeError: e));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context)
          .pop(CardSheetResult(CardSheetStatus.failed, otherError: e));
    }
  }

  Future<void> _payWithGooglePay() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final intent = await Stripe.instance.confirmPlatformPayPaymentIntent(
        clientSecret: widget.clientSecret,
        confirmParams: PlatformPayConfirmParams.googlePay(
          googlePay: GooglePayParams(
            merchantCountryCode: 'CZ',
            currencyCode: 'CZK',
            testEnv: false,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _isPaid(intent.status)
            ? const CardSheetResult(CardSheetStatus.paid)
            : CardSheetResult(CardSheetStatus.failed,
                otherError: 'gpay status: ${intent.status}'),
      );
    } on StripeException catch (e) {
      if (!mounted) return;
      if (e.error.code == FailureCode.Canceled) {
        setState(() => _processing = false);
        return;
      }
      Navigator.of(context)
          .pop(CardSheetResult(CardSheetStatus.failed, stripeError: e));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context)
          .pop(CardSheetResult(CardSheetStatus.failed, otherError: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = t(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: MotoGoColors.g300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              tt.tr('payByCardTitle'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: MotoGoColors.black,
              ),
            ),
            const SizedBox(height: 16),

            // Google Pay (jen na podporovaných zařízeních)
            if (_googlePayReady) ...[
              _GooglePayButton(
                onPressed: _processing ? null : _payWithGooglePay,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      tt.tr('orPayByCardDivider'),
                      style: const TextStyle(
                          fontSize: 12, color: MotoGoColors.g500),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Nativní pole karty — celý rámeček klikací, vkládání ze schránky OK
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1FAF7),
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                border: Border.all(color: const Color(0xFFD4E8E0)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 56,
                child: CardField(
                  autofocus: true,
                  // Sheet má bílé pozadí — text karty MUSÍ být tmavý (jinak
                  // bílá na bílé = neviditelné). Placeholder zešedlý, kurzor zelený.
                  style: const TextStyle(
                    color: Color(0xFF0F1A14),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: MotoGoColors.greenDark,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Color(0xFF8AAB99)),
                  ),
                  onCardChanged: (card) {
                    setState(() => _cardComplete = card?.complete ?? false);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              onPressed:
                  (_processing || !_cardComplete) ? null : _payWithCard,
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      '${tt.tr('payBtn')} ${widget.amount.toStringAsFixed(0)} Kč →'),
            ),
            const SizedBox(height: 10),
            Text(
              '🔒 ${tt.tr('encryptedPayment')} · Stripe PCI DSS Level 1',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: MotoGoColors.g400),
            ),
          ],
        ),
      ),
    );
  }
}

/// Oficiální Google Pay tlačítko (1:1 brand vizuál z flutter_stripe).
/// Žádné vlastní „GPay" logo — to vypadalo pochybně. PlatformPayButton vykreslí
/// nativní Google Pay tlačítko dle Google brand guidelines.
class _GooglePayButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _GooglePayButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: PlatformPayButton(
        type: PlatformButtonType.plain,
        appearance: PlatformButtonStyle.black,
        borderRadius: MotoGoTheme.radiusSm,
        onPressed: onPressed ?? () {},
      ),
    );
  }
}
