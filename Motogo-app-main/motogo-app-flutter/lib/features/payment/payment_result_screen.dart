import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/pending_booking_fab_provider.dart';
import '../../core/widgets/moto_fx.dart';
import '../../core/widgets/pickup_location_link.dart';
import '../auth/widgets/toast_helper.dart';
import '../reservations/reservation_provider.dart' show reservationsProvider;
import 'payment_provider.dart';
import 'payment_ui_helpers.dart';
import 'payment_verify.dart';

/// Univerzální výsledková obrazovka pro platební flow, která nemají vlastní
/// bohatou děkovací stránku (prodloužení/úprava rezervace, SOS, e-shop), a pro
/// stav „Platba se ověřuje" (Stripe platbu přijal, server ji ještě nepotvrdil).
///
/// Zajišťuje, že zákazník po KAŽDÉ platbě uvidí jednoznačný výsledek (co bylo
/// zaplaceno / že se platba ověřuje + co se stane dál + CTA), místo jen
/// mizejícího toastu. Data čte z [paymentOutcomeProvider]. Zavřít jde vždy
/// (✕ vpravo nahoře, CTA i systémové „zpět" → cíl CTA).
class PaymentResultScreen extends ConsumerStatefulWidget {
  const PaymentResultScreen({super.key});

  @override
  ConsumerState<PaymentResultScreen> createState() =>
      _PaymentResultScreenState();
}

class _PaymentResultScreenState extends ConsumerState<PaymentResultScreen> {
  Timer? _autoVerify;
  int _autoRuns = 0;
  bool _verifying = false;
  /// Ověření prokázalo, že platba neproběhla.
  bool _notPaid = false;

  @override
  void initState() {
    super.initState();
    // „Platba se ověřuje": každých 10 s se zeptej DB (max 3 min) — jakmile
    // webhook platbu potvrdí, obrazovka se sama přepne na úspěch.
    final o = ref.read(paymentOutcomeProvider);
    if (o?.kind == PaymentOutcomeKind.pending) {
      _autoVerify = Timer.periodic(const Duration(seconds: 10), (_) {
        if (++_autoRuns > 18) {
          _autoVerify?.cancel();
          return;
        }
        _verify(silent: true);
      });
    }
  }

  @override
  void dispose() {
    _autoVerify?.cancel();
    super.dispose();
  }

  void _goNext(String route) {
    // Vyčisti outcome, ať se obrazovka nedá omylem zobrazit znovu prázdná.
    ref.read(paymentOutcomeProvider.notifier).state = null;
    if (mounted) context.go(route);
  }

  Future<void> _verify({bool silent = false}) async {
    final o = ref.read(paymentOutcomeProvider);
    if (o == null || o.kind != PaymentOutcomeKind.pending || _verifying) return;
    setState(() => _verifying = true);
    final state = await verifyPayment(
      bookingId: o.verifyBookingId,
      orderId: o.verifyOrderId,
      expectedTotal: o.verifyExpectedTotal,
      intentOnly: o.verifyIntentOnly,
    );
    if (!mounted) return;
    setState(() => _verifying = false);
    switch (state) {
      case VerifyState.paid:
        _autoVerify?.cancel();
        ref.invalidate(pendingBookingFabProvider);
        ref.invalidate(reservationsProvider);
        if (o.verifiedRoute != null) {
          ref.read(lastConfirmedBookingProvider.notifier).state = o.verifyBookingId;
          _goNext(o.verifiedRoute!);
        } else if (o.verifiedOutcome != null) {
          ref.read(paymentOutcomeProvider.notifier).state = o.verifiedOutcome;
        }
      case VerifyState.notPaid:
        _autoVerify?.cancel();
        ref.invalidate(pendingBookingFabProvider);
        setState(() => _notPaid = true);
      case VerifyState.pending:
        if (!silent) {
          showMotoGoToast(context,
              icon: '⏳',
              title: t(context).tr('psPendingTitle'),
              message: t(context).tr('psVerifyStillPending'));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final outcome = ref.watch(paymentOutcomeProvider);

    // Fallback, kdyby se sem uživatel dostal bez dat (např. po hot-restartu) —
    // ukaž alespoň obecné potvrzení a pošli ho na rezervace, ať nikde neuvízne.
    final kind = outcome?.kind ?? PaymentOutcomeKind.success;
    final pending = kind == PaymentOutcomeKind.pending && !_notPaid;
    final title = _notPaid
        ? tr.tr('psNotPaidTitle')
        : (outcome?.title ?? tr.tr('paid'));
    final subtitle = _notPaid
        ? (outcome?.notPaidMessage ?? tr.tr('psNotPaidBooking'))
        : (outcome?.subtitle ?? tr.tr('paymentCompleted'));
    final lines = _notPaid ? const <PaymentOutcomeLine>[] : (outcome?.lines ?? const []);
    final nextStep = _notPaid ? null : outcome?.nextStepNote;
    final ctaLabel = outcome?.ctaLabel ?? tr.tr('successCta');
    final ctaRoute = outcome?.ctaRoute ?? Routes.reservations;

    return BackButtonListener(
      // Systémové „zpět" vede vždy na cíl CTA — i když je obrazovka jediná v
      // zásobníku (sem se chodí přes `go`; PopScope by se pak nezavolal a
      // Android by appku zavřel).
      onBackButtonPressed: () async {
        // Nad obrazovkou je jiná trasa (dialog, Zprávy) → ať se zavře ona.
        if (!isTopmostRoute(context)) return false;
        _goNext(ctaRoute);
        return true;
      },
      child: PopScope(
        // Hardwarové „zpět" nesmí vrátit na platební obrazovku — vede na CTA cíl.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goNext(ctaRoute);
        },
        child: Scaffold(
          backgroundColor: MotoGoColors.dark,
          body: SafeArea(
            child: Stack(children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      if (_notPaid)
                        const _StatusBadge(icon: '!', color: MotoGoColors.red)
                      else if (pending)
                        const _StatusBadge(icon: '⏳', color: Color(0xFFF59E0B))
                      else if (kind == PaymentOutcomeKind.attention)
                        const _StatusBadge(icon: '✓', color: Color(0xFFF59E0B))
                      else
                        // Mototematická oslava úspěšné platby (motorka + jiskry +
                        // elastický check) — sdílená s děkovací stránkou rezervace.
                        const MotoSuccessHero(),
                      const SizedBox(height: 8),
                      StaggeredReveal(
                        index: 0,
                        child: Column(children: [
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
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 20),

                      if (lines.isNotEmpty)
                        StaggeredReveal(
                          index: 1,
                          child: _LinesCard(lines: lines),
                        ),
                      if (lines.isNotEmpty) const SizedBox(height: 16),

                      // „K vyzvednutí“ — pobočka motorky po zaplacené úpravě.
                      if (outcome?.pickup != null && !_notPaid) ...[
                        SizedBox(
                          width: double.infinity,
                          child: PickupLocationLink(info: outcome!.pickup!),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (nextStep != null) ...[
                        StaggeredReveal(
                          index: 2,
                          child: _NoteRow(
                              icon: pending ? 'ℹ️' : '📧', text: nextStep),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Jistota pro zákazníka, že platba je potvrzená serverem
                      // (jen u skutečně potvrzeného úspěchu).
                      if (kind == PaymentOutcomeKind.success && !_notPaid)
                        StaggeredReveal(
                          index: 3,
                          child: Container(
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
                        ),
                      const SizedBox(height: 32),

                      StaggeredReveal(
                        index: 4,
                        child: PressableScale(
                          child: ElevatedButton(
                            onPressed: () => _goNext(ctaRoute),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: Text('$ctaLabel →'),
                          ),
                        ),
                      ),
                      if (pending) ...[
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _verifying ? null : () => _verify(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          child: _verifying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(tr.tr('psVerifyAgain')),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
              // Vždy viditelné zavření (požadavek majitele: z každé obrazovky zpět).
              Positioned(
                top: 4,
                right: 4,
                child: Semantics(
                  button: true,
                  label: tr.tr('close'),
                  child: IconButton(
                    onPressed: () => _goNext(ctaRoute),
                    iconSize: 26,
                    color: Colors.white70,
                    tooltip: tr.tr('close'),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String icon;
  final Color color;
  const _StatusBadge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2.5),
      ),
      alignment: Alignment.center,
      child: Text(icon,
          style: TextStyle(
              fontSize: 38, fontWeight: FontWeight.w900, color: color)),
    );
  }
}

class _LinesCard extends StatelessWidget {
  final List<PaymentOutcomeLine> lines;
  const _LinesCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lines[i].icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    lines[i].text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  final String icon;
  final String text;
  const _NoteRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MotoGoColors.greenPale.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
