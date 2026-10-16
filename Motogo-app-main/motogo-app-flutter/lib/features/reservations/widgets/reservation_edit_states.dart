import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/payment_pending_marker.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/mg_nav_controls.dart';
import '../../payment/net_error.dart';
import '../../payment/payment_refusals.dart';
import '../../payment/payment_ui_helpers.dart';
import '../../payment/widgets/payment_error_sheet.dart';

/// Načítání / chyba úpravy rezervace — VŽDY s hlavičkou a šipkou zpět
/// (dřív holý spinner bez cesty zpět, při výpadku sítě navždy).
class EditStateScaffold extends StatelessWidget {
  final VoidCallback onBack;
  /// null = načítá se; jinak text chyby.
  final String? error;
  final VoidCallback? onRetry;
  const EditStateScaffold(
      {super.key, required this.onBack, this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Column(children: [
        Container(
          padding: EdgeInsets.fromLTRB(
              16, MediaQuery.of(context).padding.top + 12, 16, 14),
          decoration: const BoxDecoration(
              color: MotoGoColors.dark,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
          child: Row(children: [
            MgBackTap(
              onTap: onBack,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: MotoGoColors.green,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_back, size: 18, color: Colors.black),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr.tr('editReservation'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ),
          ]),
        ),
        Expanded(
          child: Center(
            child: error == null
                ? const CircularProgressIndicator(color: MotoGoColors.green)
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('⚠️', style: TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      Text(error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: MotoGoColors.g600,
                              height: 1.45)),
                      const SizedBox(height: 20),
                      if (onRetry != null)
                        ElevatedButton(
                            onPressed: onRetry,
                            style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48)),
                            child: Text(tr.tr('retry'))),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: onBack,
                          child: Text(tr.tr('psBackToRes'))),
                    ]),
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Srozumitelný text chyby uložení úpravy / posunu (nikdy `'$e'`).
String editFailureText(BuildContext context, Object e, {bool move = false}) {
  final tr = t(context);
  final raw = '$e';
  if (raw.contains('obslužné pobočky')) return tr.tr('fxTrailerStaffedOnly');
  if (raw.contains('trailer_unavailable')) return tr.tr('swap.trailerOccupied');
  if (raw.contains('Překrývající se rezervace') || raw.contains('přiřazen jako vozík')) {
    return tr.tr('fxMotoOccupied');
  }
  if (isNetworkError(e) || e is TimeoutException) return tr.tr('psEditNet');
  return tr.tr(move ? 'psMoveFail' : 'psEditFail');
}

/// Chyba uložení úpravy v sheetu s nápravou ([onRetry] zkusí znovu).
void showEditFailure(BuildContext context, Object e,
    {required VoidCallback onRetry, bool move = false}) {
  final tr = t(context);
  PaymentErrorSheet.show(
    context,
    title: tr.tr('psEditFailTitle'),
    message: editFailureText(context, e, move: move),
    buttonLabel: tr.tr('retry'),
    onButton: onRetry,
    secondaryLabel: tr.tr('psWriteUs'),
    onSecondary: () => openContactUs(context),
  );
}

/// Odpověď na uložení se ztratila a stav nejde ověřit (pořád bez spojení) —
/// změna se možná uložila. Žádné „nic se nezměnilo" ani slepé opakování:
/// nejdřív načíst aktuální stav rezervace ([onReload]).
void showEditUncertain(BuildContext context, {required VoidCallback onReload}) {
  final tr = t(context);
  PaymentErrorSheet.show(
    context,
    title: tr.tr('psUncertainTitle'),
    message: tr.tr('fxEditUncertain'),
    buttonLabel: tr.tr('psReload'),
    onButton: onReload,
    secondaryLabel: tr.tr('psWriteUs'),
    onSecondary: () => openContactUs(context),
  );
}

/// Předchozí doplatek této rezervace se ještě ověřuje (značka „platba
/// odeslána") → DRUHÝ doplatek nenabízet (dvojí platba; server `stale_booking`
/// chrání až po zápisu první změny). true = zablokováno, hláška ukázaná.
Future<bool> blockIfSurchargePending(BuildContext context, String bookingId) async {
  if (!await PaymentPendingMarker.isPending(bookingId)) return false;
  if (!context.mounted) return true;
  final tr = t(context);
  PaymentErrorSheet.show(
    context,
    title: tr.tr('psPendingTitle'),
    message: tr.tr('fxEditPendingBody'),
    buttonLabel: tr.tr('psOpenReservation'),
    onButton: () => context.go('/reservations/$bookingId'),
    secondaryLabel: tr.tr('psWriteUs'),
    onSecondary: () => openContactUs(context),
  );
  return true;
}

/// Doplatek pod minimem karty (1–14 Kč) — PŘED platbou: co dál (D1).
void showBelowMinimum(BuildContext context, PayFlow flow, num amount) {
  final tr = t(context);
  final p = PaymentRefusals.belowMinimum(tr.lang, flow, amount);
  PaymentErrorSheet.show(
    context,
    title: p.title,
    message: p.message,
    buttonLabel: tr.tr('psEditChange'),
    secondaryLabel: tr.tr('psWriteUs'),
    onSecondary: () => openContactUs(context),
  );
}
