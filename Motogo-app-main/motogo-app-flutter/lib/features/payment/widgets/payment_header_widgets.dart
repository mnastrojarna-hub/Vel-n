import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/router.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/moto_fx.dart';
import '../payment_provider.dart';
import '../../../core/currency.dart';
import '../card_minimum.dart' show cardMinCzk, kcExact;

/// Top header bar for the payment screen.
class PaymentHeader extends StatelessWidget {
  /// Zpět řídí PaymentScreen (potvrzení během platby, cíl podle druhu platby).
  final VoidCallback? onBack;
  const PaymentHeader({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(children: [
        Semantics(
          button: true,
          label: t(context).back,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onBack ?? () => context.backOr(Routes.booking),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: MotoGoColors.green,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('\u2190',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
            ),
          ),
        ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t(context).tr('paymentTitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              Text(t(context).tr('securePaymentDesc'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.5))),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Countdown timer widget showing remaining payment time.
class PaymentCountdown extends StatelessWidget {
  final String timeRemaining;
  const PaymentCountdown({super.key, required this.timeRemaining});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('\u23f1 ', style: TextStyle(fontSize: 14)),
          Text(
            t(context).tr('timeRemainingLabel').replaceAll('{time}', timeRemaining),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.black),
          ),
        ],
      ),
    );
  }
}

/// Card shown for non-booking flows (extension, SOS, shop).
/// For SOS flow, displays price breakdown (moto, delivery, deposit).
class PaymentContextCard extends StatelessWidget {
  final String displayLabel;
  final double amount;
  final bool isFree;
  final List<SosPriceItem>? sosBreakdown;
  final String? sosDepositNote;

  const PaymentContextCard({
    super.key,
    required this.displayLabel,
    required this.amount,
    required this.isFree,
    this.sosBreakdown,
    this.sosDepositNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: MotoGoShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Text('\ud83d\udcb3', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(displayLabel,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.black)),
          ),
        ]),
        const SizedBox(height: 12),

        // SOS breakdown items
        if (sosBreakdown != null && sosBreakdown!.isNotEmpty) ...[
          ...sosBreakdown!.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text('${item.icon} ${item.label}',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600, color: MotoGoColors.g600))),
                Text('${Money.czk(item.amount)}',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w700, color: MotoGoColors.black)),
              ],
            ),
          )),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t(context).tr('totalLabel'),
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w900, color: MotoGoColors.black)),
              Text('${Money.czk(amount)}',
                  style: const TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
            ],
          ),
          if (sosDepositNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: MotoGoColors.amberBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('ℹ️ $sosDepositNote',
                  style: const TextStyle(fontSize: 10,
                      fontWeight: FontWeight.w600, color: Color(0xFF78350F))),
            ),
          ],
        ],

        // Simple amount (non-SOS flows)
        if (sosBreakdown == null || sosBreakdown!.isEmpty) ...[
          if (!isFree)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MotoGoColors.bg,
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Haléřová částka pod minimem karty (např. 0,60 Kč) přesně —
                  // zaokrouhlené „1 Kč" by neodpovídalo poznámce o minimu (D1).
                  Text(Money.code == 'CZK' && amount < cardMinCzk && amount != amount.roundToDouble()
                          ? kcExact(amount)
                          : '${Money.czk(amount)}',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: MotoGoColors.black)),
                ],
              ),
            ),
          if (isFree)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
                border: Border.all(
                    color: MotoGoColors.green.withValues(alpha: 0.3)),
              ),
              child: Text(
                '✓ ${t(context).tr('discountCoversAll')}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.greenDarker),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ]),
    );
  }
}

/// Sticky bottom pay button.
class PaymentPayButton extends StatelessWidget {
  final double amount;
  final bool isFree;
  final bool processing;
  /// Vypršel čas na zaplacení → tlačítko zamčené s popiskem „Čas vypršel".
  final bool expired;
  final VoidCallback? onPay;
  /// Během ověřování výsledku: popisek tlačítka („Ověřujeme platbu…")
  /// místo obecného „Načítám…" …
  final String? statusLabel;
  /// … a trvalý řádek pod tlačítkem (proč se čeká, neplatit znovu).
  final String? statusNote;
  /// Popisek tlačítka bez platby (zbytek do 1 Kč: „Potvrdit bez platby").
  final String? freeLabel;

  const PaymentPayButton({
    super.key,
    required this.amount,
    required this.isFree,
    required this.processing,
    this.expired = false,
    required this.onPay,
    this.statusLabel,
    this.statusNote,
    this.freeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: MotoGoShadows.stickyBar,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
      PressableScale(
        enabled: !processing && !expired,
        child: ShimmerSweep(
        borderRadius: BorderRadius.circular(50),
        child: ElevatedButton(
        onPressed: (processing || expired) ? null : onPay,
        style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52)),
        child: processing
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(statusLabel ?? t(context).loading,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              )
            : expired
            ? Text('⏱ ${t(context).tr('timeExpired')}')
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isFree ? Icons.check_circle : Icons.payment,
                      size: 18),
                  const SizedBox(width: 8),
                  Text(isFree
                      ? '${freeLabel ?? t(context).tr('confirmOrderFree')} →'
                      : '${t(context).tr('payBtn')} ${Money.czk(amount)} →'),
                ],
              ),
        ),
        ),
      ),
      if (processing && statusNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('⏳ $statusNote',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: MotoGoColors.g600)),
        ),
      ]),
    );
  }
}
