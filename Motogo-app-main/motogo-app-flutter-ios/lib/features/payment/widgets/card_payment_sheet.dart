import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../payment_error_mapper.dart';

/// Výsledek vlastního platebního sheetu s kartou.
enum CardSheetStatus { paid, processing, cancelled, failed }

class CardSheetResult {
  final CardSheetStatus status;

  /// Stripe chyba (declined / expired / 3DS selhalo) — caller ji namapuje přes
  /// PaymentErrorMapper.fromStripeException a zachová počítadlo pokusů.
  final StripeException? stripeError;

  /// Jiná chyba (neočekávaný stav PaymentIntentu, gateway error).
  final Object? otherError;

  const CardSheetResult(this.status, {this.stripeError, this.otherError});
}

/// Vlastní in-app sheet pro zadání karty + Apple Pay (iOS) / Google Pay (Android).
///
/// Nahrazuje nativní Stripe Payment Sheet, jehož pole „Číslo karty" mělo malý
/// klikací rámeček a nešlo do něj vložit číslo ze schránky. Tady kreslíme pole
/// sami přes `CardField` (nativní text field — celý rámeček je klikací a vkládání
/// ze schránky funguje) a platbu potvrdíme přes `Stripe.instance.confirmPayment`
/// proti stejnému PaymentIntentu (client_secret z edge fn `process-payment`).
///
/// iOS varianta: místo Google Pay se nabízí Apple Pay přes nativní
/// `PlatformPayButton` (PKPaymentButton — vyžaduje Apple Pay merchant ID
/// `merchant.cz.motogo24.rental`, nastavené v main.dart + Runner.entitlements).
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
          // Parametr se historicky jmenuje allowGooglePay (volá ho payment_screen),
          // na iOS ovládá Apple Pay — význam je „povolit platformní peněženku".
          allowPlatformPay: allowGooglePay,
        ),
      ),
    );
    return result ?? const CardSheetResult(CardSheetStatus.cancelled);
  }
}

class _CardSheetBody extends StatefulWidget {
  final String clientSecret;
  final double amount;
  final bool allowPlatformPay;

  const _CardSheetBody({
    required this.clientSecret,
    required this.amount,
    required this.allowPlatformPay,
  });

  @override
  State<_CardSheetBody> createState() => _CardSheetBodyState();
}

class _CardSheetBodyState extends State<_CardSheetBody>
    with WidgetsBindingObserver {
  bool _cardComplete = false;
  bool _processing = false;
  bool _platformPayReady = false;

  /// Vlastní controller CardFieldu. Plugin drží zadané údaje v nativním view,
  /// které přežívá zavření sheetu — bez explicitního clear() se po
  /// znovuotevření (po zamítnuté platbě nebo „Obnovit rezervaci") ukáže
  /// staré (chybné) číslo, po dokončení sbalené na „•••• 1234", které laik
  /// nedokáže přepsat → opakovaně platí špatnou kartou. Proto pole při
  /// každém otevření sheetu čistíme.
  final CardEditController _cardController = CardEditController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // clear() potřebuje připojený nativní CardField → až po prvním framu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _cardController.clear();
      } catch (_) {
        // Pole se ještě nepřipojilo — pak je prázdné a není co čistit.
      }
    });
    if (widget.allowPlatformPay) _checkPlatformPay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cardController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // CardField (flutter_stripe) drží fokus na nativním platform view. Když
    // appka odejde na pozadí, systém může nativní view zahodit; po návratu
    // Flutter fokus obnoví a plugin zavolá `focus` na mrtvém kanálu
    // (flutter.stripe/card_field) → MissingPluginException. Proto fokus
    // pustíme ještě před odchodem na pozadí — blur proběhne na živém kanálu
    // a po resume se žádný fokus neobnovuje.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  /// Apple Pay (iOS) / Google Pay (Android) — jen na podporovaných zařízeních.
  Future<void> _checkPlatformPay() async {
    try {
      final ok = await Stripe.instance.isPlatformPaySupported();
      if (mounted) setState(() => _platformPayReady = ok);
    } catch (_) {
      // Platformní peněženka nedostupná — zaplatí se kartou.
    }
  }

  /// App Review 2.1 (build 38): `isPlatformPaySupported()` vrací false na
  /// zařízení bez karty ve Walletu (typicky recenzní zařízení Apple) → tlačítko
  /// se skrylo a recenzent Apple Pay integraci „neviděl". Na iOS proto tlačítko
  /// zobrazujeme VŽDY a nedostupnost řešíme až při tapnutí: živý re-check, a
  /// když peněženka opravdu není k dispozici, srozumitelná hláška (mapper
  /// substituuje Google Pay → Apple Pay) místo prázdné obrazovky.
  Future<void> _tapApplePay() async {
    if (_processing) return;
    if (!_platformPayReady) {
      bool ok = false;
      try {
        ok = await Stripe.instance.isPlatformPaySupported();
      } catch (_) {}
      if (!mounted) return;
      if (!ok) {
        final info = PaymentErrorMapper.wallet(t(context).lang);
        await showDialog<void>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: Text(info.title),
            content: Text(info.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      setState(() => _platformPayReady = true);
    }
    await _payWithPlatformPay();
  }

  /// Mapuje finální stav PaymentIntentu na výsledek sheetu.
  ///
  /// POZOR (finanční korektnost): `Processing` znamená, že Stripe platbu zatím
  /// NEPOTVRDIL — nesmí se brát jako zaplaceno. Dřív se Processing počítal jako
  /// `paid`, takže appka vystavila doklad (DP) / aplikovala úpravu i pro platbu,
  /// kterou Stripe nepotvrdil (a mohla ještě selhat). Nově je `Processing` =
  /// `processing` → appka počká na serverové potvrzení (webhook) a teprve pak
  /// vystaví doklady. Potvrzeno je JEN `Succeeded` / `RequiresCapture`.
  CardSheetResult _resultFor(PaymentIntentsStatus status, String label) {
    if (status == PaymentIntentsStatus.Succeeded ||
        status == PaymentIntentsStatus.RequiresCapture) {
      return const CardSheetResult(CardSheetStatus.paid);
    }
    if (status == PaymentIntentsStatus.Processing) {
      return const CardSheetResult(CardSheetStatus.processing);
    }
    return CardSheetResult(CardSheetStatus.failed,
        otherError: '$label status: $status');
  }

  Future<void> _payWithCard() async {
    if (_processing || !_cardComplete) return;
    setState(() => _processing = true);
    // Zavřít klávesnici a pustit fokus z CardFieldu PŘED confirmem — 3DS
    // otevírá externí okno (pauza/resume) a obnovení fokusu na mezitím
    // zahozený nativní view by spadlo na MissingPluginException.
    FocusManager.instance.primaryFocus?.unfocus();
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
      Navigator.of(context).pop(_resultFor(intent.status, 'intent'));
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

  /// Apple Pay (iOS) / Google Pay (Android) přes stejný PaymentIntent.
  Future<void> _payWithPlatformPay() async {
    if (_processing) return;
    setState(() => _processing = true);
    // Stejně jako u karty — Apple/Google Pay překryje appku nativním sheetem,
    // fokus na CardFieldu by se po návratu obnovoval na mrtvém kanálu.
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      final confirmParams = Platform.isIOS
          ? PlatformPayConfirmParams.applePay(
              applePay: ApplePayParams(
                merchantCountryCode: 'CZ',
                currencyCode: 'CZK',
                // Apple vyžaduje cart items — poslední položka = celková částka
                // s názvem obchodníka (v Apple Pay sheetu „PAY MOTOGO24").
                cartItems: [
                  ApplePayCartSummaryItem.immediate(
                    label: 'MotoGo24',
                    amount: widget.amount.toStringAsFixed(2),
                  ),
                ],
              ),
            )
          : const PlatformPayConfirmParams.googlePay(
              googlePay: GooglePayParams(
                merchantCountryCode: 'CZ',
                currencyCode: 'CZK',
                testEnv: false,
              ),
            );

      final intent = await Stripe.instance.confirmPlatformPayPaymentIntent(
        clientSecret: widget.clientSecret,
        confirmParams: confirmParams,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _resultFor(intent.status, 'platform pay'),
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

            // Apple Pay: na iOS VŽDY viditelné (App Review 2.1 — recenzent bez
            // karty ve Walletu musí integraci vidět; nedostupnost řeší
            // _tapApplePay hláškou). Google Pay (Android) jen na podporovaných.
            if (Platform.isIOS || _platformPayReady) ...[
              if (Platform.isIOS)
                // Nativní PKPaymentButton — vzhled vyžadovaný Apple HIG.
                SizedBox(
                  height: 48,
                  child: PlatformPayButton(
                    type: PlatformButtonType.plain,
                    appearance: PlatformButtonStyle.black,
                    borderRadius: 8,
                    onPressed: () {
                      if (!_processing) _tapApplePay();
                    },
                  ),
                )
              else
                _GooglePayButton(
                  onPressed: _processing ? null : _payWithPlatformPay,
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
                  controller: _cardController,
                  autofocus: true,
                  // Bílé pozadí sheetu → text karty MUSÍ být tmavý (jinak
                  // bílá na bílé = neviditelné).
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

/// Oficiální Google Pay tlačítko (1:1 brand vizuál z flutter_stripe) — Android.
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
        borderRadius: MotoGoTheme.radiusSm.round(),
        onPressed: onPressed ?? () {},
      ),
    );
  }
}
