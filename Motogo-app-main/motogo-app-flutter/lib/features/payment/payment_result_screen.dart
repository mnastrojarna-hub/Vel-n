import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import 'payment_provider.dart';

/// Univerzální potvrzovací obrazovka pro platební flow, která nemají vlastní
/// bohatou děkovací stránku (prodloužení/úprava rezervace, SOS, e-shop).
///
/// Zajišťuje, že zákazník po KAŽDÉ úspěšné platbě uvidí jednoznačné potvrzení
/// (zelený check + co bylo zaplaceno + co se stane dál + CTA), místo jen
/// mizejícího toastu. Data čte z [paymentOutcomeProvider].
class PaymentResultScreen extends ConsumerStatefulWidget {
  const PaymentResultScreen({super.key});

  @override
  ConsumerState<PaymentResultScreen> createState() =>
      _PaymentResultScreenState();
}

class _PaymentResultScreenState extends ConsumerState<PaymentResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _goNext(String route) {
    // Vyčisti outcome, ať se obrazovka nedá omylem zobrazit znovu prázdná.
    ref.read(paymentOutcomeProvider.notifier).state = null;
    if (mounted) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final outcome = ref.watch(paymentOutcomeProvider);

    // Fallback, kdyby se sem uživatel dostal bez dat (např. po hot-restartu) —
    // ukaž alespoň obecné potvrzení a pošli ho na rezervace, ať nikde neuvízne.
    final title = outcome?.title ?? tr.tr('paid');
    final subtitle = outcome?.subtitle ?? tr.tr('paymentCompleted');
    final lines = outcome?.lines ?? const [];
    final nextStep = outcome?.nextStepNote;
    final ctaLabel = outcome?.ctaLabel ?? tr.tr('successCta');
    final ctaRoute = outcome?.ctaRoute ?? Routes.reservations;

    return PopScope(
      // Hardwarové „zpět" nesmí vrátit na platební obrazovku — vede na CTA cíl.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goNext(ctaRoute);
      },
      child: Scaffold(
        backgroundColor: MotoGoColors.dark,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: MotoGoColors.green, width: 4),
                      ),
                      child: const Center(
                        child: Text(
                          '✓',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: MotoGoColors.green,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  if (lines.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(MotoGoTheme.radiusSm),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < lines.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(lines[i].icon,
                                    style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    lines[i].text,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white
                                          .withValues(alpha: 0.85),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (lines.isNotEmpty) const SizedBox(height: 16),

                  if (nextStep != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: MotoGoColors.greenPale.withValues(alpha: 0.15),
                        borderRadius:
                            BorderRadius.circular(MotoGoTheme.radiusSm),
                      ),
                      child: Row(
                        children: [
                          const Text('📧', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              nextStep,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Jistota pro zákazníka, že platba je potvrzená serverem.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      '🔒 ${tr.tr('successSynced')}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: MotoGoColors.g400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  ElevatedButton(
                    onPressed: () => _goNext(ctaRoute),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text('$ctaLabel →'),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
