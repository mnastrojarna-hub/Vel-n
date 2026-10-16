import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/net_image.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/state_views.dart';
import '../../core/offline_guard.dart';
import '../auth/widgets/toast_helper.dart';
import '../documents/booking_doc_viewer.dart';
import '../documents/document_models.dart';
import '../documents/doc_open_runner.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';
import 'booking_restore.dart';
import 'widgets/res_detail_tab_btn.dart';
import 'widgets/res_detail_tab_content.dart';
import 'widgets/res_payment_details_tab.dart';
import 'widgets/res_cancel_dialog.dart';
import '../../core/widgets/mg_nav_controls.dart';

/// Reservation detail — mirrors s-res-detail from templates-res.js.
/// Shows image header, status badge, dates, pricing, actions.
/// Status-specific sections: door codes (active), rating (completed),
/// refund info (cancelled), edit (upcoming).
class ReservationDetailScreen extends ConsumerStatefulWidget {
  final String bookingId;
  const ReservationDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<ReservationDetailScreen> createState() => _DetailState();
}

class _DetailState extends ConsumerState<ReservationDetailScreen> {
  String _activeTab = 'detail'; // 'detail' or 'card'
  Timer? _refreshTimer;
  // Předávací protokol samoobslužné pobočky se od 2026-10-10 vyplňuje
  // a podepisuje JEN na displeji pobočky (kiosk) — appka ho nevyplňuje, ukáže
  // až podepsané PDF v dokumentech rezervace (bookingDocsProvider).

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Offline obnova jen selže — načtené údaje (i kódy) necháme být.
      if (OfflineGuard.offlineNow) return;
      ref.invalidate(reservationByIdProvider(widget.bookingId));
      ref.invalidate(doorCodesProvider(widget.bookingId));
      // podpis na kiosku / ve Velíně → tlačítko podepsaného protokolu bez restartu
      ref.invalidate(bookingDocsProvider(widget.bookingId));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Real-time: změna řádku bookings (podpis protokolu na kiosku, aktivace
    // kódem) → detail hned znovu (5s timer je jen záloha).
    ref.listen(reservationsProvider, (prev, next) {
      if (!next.hasValue || prev?.valueOrNull == next.valueOrNull) return;
      ref.invalidate(reservationByIdProvider(widget.bookingId));
      ref.invalidate(bookingDocsProvider(widget.bookingId));
    });
    final resAsync = ref.watch(reservationByIdProvider(widget.bookingId));
    final doorCodesAsync = ref.watch(doorCodesProvider(widget.bookingId));

    // Načítání i chyba mají šipku zpět, důvod a „Zkusit znovu" (cíl push
    // notifikací — dřív holý spinner bez zpět a syrová výjimka „Chyba: …").
    void back() => context.backOr(Routes.reservations);
    void retry() {
      ref.invalidate(reservationByIdProvider(widget.bookingId));
      ref.invalidate(doorCodesProvider(widget.bookingId));
    }
    // skipError: neúspěšná obnova (offline, slabé LTE na samoobslužné
    // pobočce) NESMÍ schovat už načtenou rezervaci ani kódy — jen pruh.
    final stale = (resAsync.hasError && resAsync.hasValue) ||
        (doorCodesAsync.hasError && doorCodesAsync.hasValue);
    return resAsync.when(
      skipError: true,
      data: (res) {
        if (res == null) {
          return MgStateScaffold(
            title: t(context).tr('detail'),
            onBack: back,
            child: MgErrorView(
              what: t(context).tr('reservationNotFound'),
              message: t(context).tr('eoReservationGoneBody'),
              contact: false,
              onBack: () => context.go(Routes.reservations),
              backLabel: t(context).tr('myReservations'),
            ),
          );
        }
        return _buildDetail(context, res, doorCodesAsync,
            stale: stale ? retry : null);
      },
      loading: () => MgStateScaffold(
        title: t(context).tr('detail'),
        onBack: back,
        child: MgLoadingView(onRetry: retry, onBack: back),
      ),
      error: (e, _) => MgStateScaffold(
        title: t(context).tr('detail'),
        onBack: back,
        child: MgErrorView(
          error: e,
          what: t(context).tr('eoReservationLoadFail'),
          onRetry: retry,
          onBack: back,
        ),
      ),
    );
  }

  String _statusTitle(ResStatus st) {
    switch (st) {
      case ResStatus.aktivni: return t(context).active;
      case ResStatus.nadchazejici: return t(context).upcoming;
      case ResStatus.dokoncene: return t(context).completed;
      case ResStatus.cancelled: return t(context).cancelled;
    }
  }

  Color _statusColor(ResStatus st) {
    switch (st) {
      case ResStatus.aktivni: return MotoGoColors.green;
      case ResStatus.nadchazejici: return MotoGoColors.amber;
      case ResStatus.dokoncene: return MotoGoColors.g400;
      case ResStatus.cancelled: return MotoGoColors.red;
    }
  }

  String? _branchFullAddress(Reservation res) {
    final parts = <String>[];
    if (res.branchAddress != null && res.branchAddress!.isNotEmpty) parts.add(res.branchAddress!);
    if (res.branchCity != null && res.branchCity!.isNotEmpty) parts.add(res.branchCity!);
    if (parts.isEmpty && res.branchName != null) return res.branchName;
    return parts.isNotEmpty ? parts.join(', ') : res.branchName;
  }

  Widget _buildDetail(BuildContext context, Reservation res,
      AsyncValue<List<DoorCode>> doorCodesAsync, {VoidCallback? stale}) {
    final st = res.displayStatus;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: CustomScrollView(
        slivers: [
          // ===== HEADER with status title =====
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 14),
              decoration: const BoxDecoration(
                color: MotoGoColors.dark,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MgBackTap(
                        onTap: () => context.backOr(Routes.reservations),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: MotoGoColors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${t(context).tr('resDetailTitle')} – ${_statusTitle(st)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ResDetailTabBtn(
                        label: t(context).tr('detailTab'),
                        active: _activeTab == 'detail',
                        onTap: () => setState(() => _activeTab = 'detail'),
                      ),
                      const SizedBox(width: 8),
                      ResDetailTabBtn(
                        label: t(context).tr('paymentDetailsTab'),
                        active: _activeTab == 'card',
                        onTap: () => setState(() => _activeTab = 'card'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (stale != null) SliverToBoxAdapter(child: MgStaleNote(onRetry: stale)),

          if (_activeTab == 'detail') ...[
            // ===== MOTORCYCLE IMAGE =====
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                    boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.08), blurRadius: 16)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      // Guard na prázdnou URL — jinak build spadne na
                      // „No host specified in URI" (ErrorWidget).
                      child: (res.motoImage == null || res.motoImage!.isEmpty)
                          ? Container(
                              color: MotoGoColors.g200,
                              child: const Icon(Icons.motorcycle, size: 48, color: MotoGoColors.g400),
                            )
                          : ColoredBox(
                              color: MotoGoColors.g100,
                              child: MgImage(
                                res.motoImage!,
                                thumbWidth: 800,
                                // contain = celá fotka viditelná (jako ve velíně)
                                fit: BoxFit.contain,
                                error: Container(
                                  color: MotoGoColors.g200,
                                  child: const Icon(Icons.motorcycle, size: 48, color: MotoGoColors.g400),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // ===== DETAIL TAB BODY =====
            ResDetailTabContent(
              res: res,
              doorCodesAsync: doorCodesAsync,
              statusColor: _statusColor(st),
              statusTitle: _statusTitle(st),
              branchFullAddress: _branchFullAddress(res),
              onShowCancelDialog: () => _showCancelDialog(context, res),
              onOpenFinalInvoice: _openFinalInvoice,
              onOpenContract: _openContract,
              onRestoreBooking: _restoreBooking,
            ),
          ],

          // ===== PODROBNOSTI O PLATBĚ (dřív „Platební karta“) =====
          if (_activeTab == 'card')
            ResPaymentDetailsTab(res: res),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context, Reservation res) {
    showDialog(
      context: context,
      builder: (ctx) => ResCancelDialog(reservation: res),
    ).then((_) {
      ref.invalidate(reservationsProvider);
      ref.invalidate(reservationByIdProvider(widget.bookingId));
    });
  }

  /// Restore cancelled booking — check moto availability first (tri-state:
  /// výpadek spojení ≠ obsazená motorka), pak obnova + platba. Logika v
  /// `booking_restore.dart`.
  Future<void> _restoreBooking(BuildContext context, Reservation res) =>
      restoreAndPay(context, ref, res);

  /// Open rental contract for this specific booking — reálný dokument 1:1
  /// (podepsané HTML z generated_documents / soubor z bucketu documents).
  /// Průběh (po 15 s „Zrušit"), pojistka proti dvojímu klepnutí; bez
  /// spojení skutečný důvod + „Zkusit znovu" (ne „Smlouva zatím není").
  Future<void> _openContract(BuildContext context, String bookingId) {
    final tr = t(context);
    return runDocOpen(context,
        what: tr.tr('eoDocLoadFail'),
        where: 'res_contract_open',
        op: (wanted) async {
          final opened = await openBookingDocument(context,
              bookingId: bookingId, type: 'contract', title: tr.tr('rentalContract'), wanted: wanted);
          if (opened) return;
          if (!await OfflineGuard.pingSupabase()) throw const SocketException('offline');
          if (!context.mounted || !wanted()) return;
          showMotoGoToast(context, icon: '📄', title: tr.tr('contractLabel'), message: tr.tr('contractNotReady'));
        });
  }

  /// Konečná faktura rezervace. Bez profilu (výpadek spojení) se NEvykreslí
  /// bez odběratele — důvod + „Zkusit znovu" (sdílené `openInvoiceDocument`).
  Future<void> _openFinalInvoice(BuildContext context, String bookingId) {
    final tr = t(context);
    return runDocOpen(context,
        what: tr.tr('eoInvoiceOpenFail'),
        where: 'res_invoice_open',
        op: (wanted) async {
          final res = await MotoGoSupabase.client
              .from('invoices')
              .select()
              .eq('booking_id', bookingId)
              .inFilter('type', ['final', 'issued'])
              .order('created_at', ascending: false)
              .limit(1);
          final invoices = (res as List);
          if (invoices.isEmpty) {
            if (!context.mounted || !wanted()) return;
            showMotoGoToast(context, icon: '📄', title: tr.tr('invoiceLabel'), message: tr.tr('invoiceNotReady'));
            return;
          }
          final invoice = UserInvoice.fromJson(invoices.first as Map<String, dynamic>);
          if (!context.mounted) return;
          await openInvoiceDocument(context, invoice, wanted: wanted);
        });
  }
}
