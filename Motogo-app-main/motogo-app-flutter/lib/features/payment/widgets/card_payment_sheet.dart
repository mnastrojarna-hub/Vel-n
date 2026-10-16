import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/theme.dart';
import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';

/// Výsledek vlastního platebního sheetu s kartou.
enum CardSheetStatus { paid, processing, cancelled, failed }

class CardSheetResult {
  final CardSheetStatus status;

  /// Stripe chyba (declined / expired / 3DS selhalo) — caller ji namapuje přes
  /// PaymentErrorMapper.fromStripeException a zachová počítadlo pokusů.
  final StripeException? stripeError;

  /// Jiná chyba (neočekávaný stav PaymentIntentu, gateway error).
  final Object? otherError;

  /// true = selhala platba peněženkou (Google Pay / Apple Pay) → rada nesmí
  /// posílat zpět do peněženky.
  final bool wallet;

  const CardSheetResult(this.status,
      {this.stripeError, this.otherError, this.wallet = false});
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
///
/// Zavřít jde vždy křížkem vpravo nahoře (nebo stažením / „zpět") — KROMĚ
/// chvíle, kdy běží platba: tehdy by se výsledek ztratil a zákazník mohl
/// zaplatit podruhé. Kdyby se sheet přesto zavřel během platby, vrací se
/// `processing` (ověří se na serveru), nikdy „zrušeno".
class CardPaymentSheet {
  CardPaymentSheet._();

  static Future<CardSheetResult> show(
    BuildContext context, {
    required String clientSecret,
    required double amount,
    bool allowGooglePay = true,
    /// Volá se těsně před odesláním platby bance (značka proti dvojí platbě).
    Future<void> Function()? onSubmitting,
  }) async {
    final guard = _SubmitGuard();
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
          guard: guard,
          onSubmitting: onSubmitting,
        ),
      ),
    );
    if (result == null && guard.submitting) {
      return const CardSheetResult(CardSheetStatus.processing);
    }
    return result ?? const CardSheetResult(CardSheetStatus.cancelled);
  }
}

/// Běží odeslaná platba, jejíž výsledek ještě neznáme.
class _SubmitGuard {
  bool submitting = false;
}

class _CardSheetBody extends StatefulWidget {
  final String clientSecret;
  final double amount;
  final bool allowGooglePay;
  final _SubmitGuard guard;
  final Future<void> Function()? onSubmitting;

  const _CardSheetBody({
    required this.clientSecret,
    required this.amount,
    required this.allowGooglePay,
    required this.guard,
    this.onSubmitting,
  });

  @override
  State<_CardSheetBody> createState() => _CardSheetBodyState();
}

class _CardSheetBodyState extends State<_CardSheetBody>
    with WidgetsBindingObserver {
  bool _cardComplete = false;
  bool _processing = false;
  bool _googlePayReady = false;
  /// Hláška pod tlačítkem (platbu jsi nedokončil(a) …), jinak null.
  String? _note;

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
    if (widget.allowGooglePay) _checkGooglePay();
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

  Future<void> _checkGooglePay() async {
    try {
      final ok = await Stripe.instance.isPlatformPaySupported();
      if (mounted) setState(() => _googlePayReady = ok);
    } catch (_) {
      // Google Pay nedostupné na tomto zařízení — zaplatí se kartou.
    }
  }

  /// Mapuje finální stav PaymentIntentu na výsledek sheetu.
  ///
  /// POZOR (finanční korektnost): `Processing` znamená, že Stripe platbu zatím
  /// NEPOTVRDIL — nesmí se brát jako zaplaceno. Dřív se Processing počítal jako
  /// `paid`, takže appka vystavila doklad (DP) / aplikovala úpravu i pro platbu,
  /// kterou Stripe nepotvrdil (a mohla ještě selhat). Nově je `Processing` =
  /// `processing` → appka počká na serverové potvrzení (webhook) a teprve pak
  /// vystaví doklady. Potvrzeno je JEN `Succeeded` / `RequiresCapture`.
  CardSheetResult _resultFor(PaymentIntentsStatus status, String label,
      {bool wallet = false}) {
    if (status == PaymentIntentsStatus.Succeeded ||
        status == PaymentIntentsStatus.RequiresCapture) {
      return const CardSheetResult(CardSheetStatus.paid);
    }
    if (status == PaymentIntentsStatus.Processing) {
      return const CardSheetResult(CardSheetStatus.processing);
    }
    return CardSheetResult(CardSheetStatus.failed,
        otherError: '$label status: $status', wallet: wallet);
  }

  /// Začátek odeslání: zamkne sheet (nejde zavřít) a nastaví značku.
  Future<void> _beginSubmit() async {
    setState(() {
      _processing = true;
      _note = null;
    });
    widget.guard.submitting = true;
    try {
      await widget.onSubmitting?.call();
    } catch (_) {/* značka je jen pojistka */}
  }

  /// Výsledek známý → sheet se smí zavřít.
  void _finish(CardSheetResult r) {
    widget.guard.submitting = false;
    if (mounted) Navigator.of(context).pop(r);
  }

  /// Zákazník 3DS / peněženku zavřel — nic se nestrhlo, zůstává v sheetu.
  void _notCompleted() {
    widget.guard.submitting = false;
    setState(() {
      _processing = false;
      _note = t(context).tr('psSheetNotCompleted');
    });
  }

  Future<void> _payWithCard() async {
    if (_processing || !_cardComplete) return;
    // Zavřít klávesnici a pustit fokus z CardFieldu PŘED confirmem — 3DS
    // otevírá externí aktivitu (pauza/resume) a obnovení fokusu na mezitím
    // zahozený nativní view by spadlo na MissingPluginException.
    FocusManager.instance.primaryFocus?.unfocus();
    await _beginSubmit();
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
      _finish(_resultFor(intent.status, 'intent'));
    } on StripeException catch (e) {
      if (!mounted) return;
      // Zákazník zavřel 3DS / zrušil — zůstaň v sheetu, ať může zkusit znovu.
      if (e.error.code == FailureCode.Canceled) {
        _notCompleted();
        return;
      }
      _finish(CardSheetResult(CardSheetStatus.failed, stripeError: e));
    } catch (e) {
      if (!mounted) return;
      _finish(CardSheetResult(CardSheetStatus.failed, otherError: e));
    }
  }

  Future<void> _payWithGooglePay() async {
    if (_processing) return;
    // Stejně jako u karty — Google Pay překryje appku nativním sheetem,
    // fokus na CardFieldu by se po návratu obnovoval na mrtvém kanálu.
    FocusManager.instance.primaryFocus?.unfocus();
    await _beginSubmit();
    try {
      final intent = await Stripe.instance.confirmPlatformPayPaymentIntent(
        clientSecret: widget.clientSecret,
        confirmParams: const PlatformPayConfirmParams.googlePay(
          googlePay: GooglePayParams(
            merchantCountryCode: 'CZ',
            currencyCode: 'CZK',
            testEnv: false,
          ),
        ),
      );
      if (!mounted) return;
      _finish(_resultFor(intent.status, 'gpay', wallet: true));
    } on StripeException catch (e) {
      if (!mounted) return;
      if (e.error.code == FailureCode.Canceled) {
        _notCompleted();
        return;
      }
      _finish(CardSheetResult(CardSheetStatus.failed,
          stripeError: e, wallet: true));
    } catch (e) {
      if (!mounted) return;
      _finish(CardSheetResult(CardSheetStatus.failed,
          otherError: e, wallet: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = t(context);
    final sheet = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 4, right: 12),
                decoration: BoxDecoration(
                  color: MotoGoColors.g300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(children: [
              Expanded(
                child: Text(
                  tt.tr('payByCardTitle'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: MotoGoColors.black,
                  ),
                ),
              ),
              // Viditelné zavření — během platby zamčené (výsledek by se ztratil).
              IconButton(
                onPressed: _processing ? null : () => Navigator.of(context).maybePop(),
                tooltip: tt.tr('close'),
                icon: const Icon(Icons.close),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            const SizedBox(height: 8),

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
                  controller: _cardController,
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
                      '${tt.tr('payBtn')} ${Money.czk(widget.amount)} →'),
            ),
            if (_processing || _note != null) ...[
              const SizedBox(height: 8),
              Text(
                _processing ? tt.tr('psSheetProcessing') : _note!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _processing ? MotoGoColors.g600 : const Color(0xFFB45309),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              '🔒 ${tt.tr('encryptedPayment')} · Stripe PCI DSS Level 1',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: MotoGoColors.g400),
            ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // Během platby: „zpět" / klepnutí vedle nezavře (PopScope) a stažení
    // dolů nic nedělá (vlastní pohlcení svislého tahu před BottomSheetem).
    // Struktura stromu se NEmění (jinak by se znovu vytvořil nativní
    // CardField uprostřed potvrzování) — mění se jen callbacky.
    void absorb(dynamic _) {}
    return PopScope(
      canPop: !_processing,
      child: GestureDetector(
        onVerticalDragStart: _processing ? absorb : null,
        onVerticalDragUpdate: _processing ? absorb : null,
        onVerticalDragEnd: _processing ? absorb : null,
        child: sheet,
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
        borderRadius: MotoGoTheme.radiusSm.round(),
        onPressed: onPressed ?? () {},
      ),
    );
  }
}
