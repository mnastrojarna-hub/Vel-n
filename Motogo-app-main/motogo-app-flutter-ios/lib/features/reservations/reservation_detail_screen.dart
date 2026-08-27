import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/net_image.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import '../catalog/catalog_provider.dart';
import '../documents/booking_doc_viewer.dart';
import '../documents/document_models.dart';
import '../documents/doc_webview_screen.dart';
import '../documents/invoice_html_builder.dart';
import '../payment/payment_provider.dart';
import 'reservation_models.dart';
import 'reservation_provider.dart';
import 'widgets/res_detail_tab_btn.dart';
import 'widgets/res_detail_tab_content.dart';
import 'widgets/res_cancel_dialog.dart';

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
  int _rating = 0;
  String _activeTab = 'detail'; // 'detail' or 'card'
  Timer? _refreshTimer;
  bool _protocolWindowKicked = false;

  // Samoobslužná pobočka: jakmile zákazník otevře aktivní/rezervovanou rezervaci
  // (na tabletu po zadání kódu ke dveřím), spustí se 1h okno pro samovyplnění
  // předávacího protokolu. Idempotentní (server nastaví start jen poprvé), proto
  // stačí jediný „kick" za zobrazení detailu.
  void _maybeStartProtocolWindow(Reservation res) {
    if (_protocolWindowKicked) return;
    if (res.branchType != 'samoobslužná') return;
    if (res.status != 'active' && res.status != 'reserved') return;
    _protocolWindowKicked = true;
    unawaited(MotoGoSupabase.client
        .rpc('start_handover_protocol_window', params: {'p_booking_id': res.id})
        .catchError((_) => null));
  }

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(reservationByIdProvider(widget.bookingId));
      ref.invalidate(doorCodesProvider(widget.bookingId));
      ref.invalidate(handoverProtocolStateProvider(widget.bookingId));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Výrazné upozornění na detailu aktivní samoobslužné rezervace — dokud zákazník
  // protokol nevyplní (can_fill). Po vyplnění/auto-fillu zmizí. Odpočet se obnovuje
  // přes 5s refresh timer (invaliduje handoverProtocolStateProvider).
  Widget _protocolBanner(BuildContext context, Reservation res) {
    final async = ref.watch(handoverProtocolStateProvider(res.id));
    final s = async.asData?.value ?? const <String, dynamic>{};
    if (s['can_fill'] != true) return const SizedBox.shrink();
    String remaining = '';
    final deadline = DateTime.tryParse('${s['deadline'] ?? ''}')?.toLocal();
    if (deadline != null) {
      final d = deadline.difference(DateTime.now());
      if (d.inMinutes >= 1) {
        remaining = '${d.inMinutes} min';
      } else if (d.inSeconds > 0) {
        remaining = '<1 min';
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        onTap: () => context.push(Routes.protocol, extra: res),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg)),
          child: Row(children: [
            const Text('📝', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Vyplňte předávací protokol',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black)),
                const SizedBox(height: 2),
                Text(
                  remaining.isNotEmpty
                      ? 'Zbývá $remaining — jinak ho vyplníme automaticky.'
                      : 'Klepněte pro vyplnění protokolu o převzetí.',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.black),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resAsync = ref.watch(reservationByIdProvider(widget.bookingId));
    final doorCodesAsync = ref.watch(doorCodesProvider(widget.bookingId));

    return resAsync.when(
      data: (res) {
        if (res == null) return _error(t(context).tr('reservationNotFound'));
        _maybeStartProtocolWindow(res);
        return _buildDetail(context, res, doorCodesAsync);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: MotoGoColors.green))),
      error: (e, _) => _error('${t(context).error}: $e'),
    );
  }

  Widget _error(String msg) => Scaffold(
    backgroundColor: MotoGoColors.bg,
    appBar: AppBar(title: const Text('Detail')),
    body: Center(child: Text(msg)),
  );

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

  Widget _buildDetail(BuildContext context, Reservation res, AsyncValue<List<DoorCode>> doorCodesAsync) {
    final st = res.displayStatus;
    _rating = res.rating ?? 0;

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
                      GestureDetector(
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
                        label: t(context).tr('paymentCardTab'),
                        active: _activeTab == 'card',
                        onTap: () => setState(() => _activeTab = 'card'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ===== UPOZORNĚNÍ: vyplnit předávací protokol (samoobslužná) =====
          if (res.branchType == 'samoobslužná' && st == ResStatus.aktivni)
            SliverToBoxAdapter(child: _protocolBanner(context, res)),

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
              rating: _rating,
              doorCodesAsync: doorCodesAsync,
              statusColor: _statusColor(st),
              statusTitle: _statusTitle(st),
              branchFullAddress: _branchFullAddress(res),
              onShowCancelDialog: () => _showCancelDialog(context, res),
              onOpenFinalInvoice: _openFinalInvoice,
              onOpenContract: _openContract,
              onRestoreBooking: _restoreBooking,
              onRatingChanged: (v) => setState(() => _rating = v),
            ),
          ],

          // ===== PAYMENT CARD TAB =====
          if (_activeTab == 'card')
            ResPaymentCardTabContent(res: res),
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

  /// Restore cancelled booking — check moto availability first.
  /// If original dates are in the future and moto is free → restore to pending + payment.
  /// Otherwise → redirect to search.
  Future<void> _restoreBooking(BuildContext context, Reservation res) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(res.startDate.year, res.startDate.month, res.startDate.day);

    // Check if dates are still in the future
    if (!startDay.isAfter(today)) {
      if (!mounted) return;
      showMotoGoToast(context, icon: '📅', title: t(context).tr('cannotRestore'), message: t(context).tr('restoreDatePassed'));
      context.go(Routes.search);
      return;
    }

    // Check if moto is available for original dates
    if (res.motoId != null) {
      final available = await checkMotoAvailability(
        res.motoId!, res.startDate, res.endDate,
        excludeBookingId: res.id,
      );
      if (available) {
        // Moto is free + dates in future → restore booking
        try {
          await MotoGoSupabase.client.from('bookings').update({
            'status': 'pending',
            'payment_status': 'unpaid',
            'cancelled_at': null,
            'cancellation_reason': null,
          }).eq('id', res.id);

          if (!mounted) return;
          ref.invalidate(reservationsProvider);
          ref.invalidate(reservationByIdProvider(res.id));
          ref.read(paymentContextProvider.notifier).state = PaymentContext(
            flowType: PaymentFlowType.booking,
            bookingId: res.id,
            amount: res.totalPrice,
            label: t(context).tr('restorePaymentLabel'),
          );
          context.push(Routes.payment);
          return;
        } catch (e) {
          debugPrint('[RESTORE] Error restoring booking: $e');
        }
      }
    }

    // Moto occupied or no motoId → redirect to search
    if (!mounted) return;
    showMotoGoToast(context, icon: '🏍️', title: t(context).tr('motoOccupiedTitle'), message: t(context).tr('restoreMotoOccupied'));
    context.go(Routes.search);
  }

  /// Open rental contract for this specific booking — reálný dokument 1:1
  /// (podepsané HTML z generated_documents / soubor z bucketu documents).
  Future<void> _openContract(BuildContext context, String bookingId) async {
    try {
      final opened = await openBookingDocument(context,
          bookingId: bookingId, type: 'contract', title: t(context).tr('rentalContract'));
      if (opened || !mounted) return;
      showMotoGoToast(context, icon: '📄', title: t(context).tr('contractLabel'), message: t(context).tr('contractNotReady'));
    } catch (e) {
      debugPrint('[CONTRACT] Error opening contract: $e');
      if (!mounted) return;
      showMotoGoToast(context, icon: '⚠️', title: t(context).error, message: t(context).tr('contractLoadError'));
    }
  }

  /// Open final invoice directly for this booking — mirrors showInvoice(bookingId, 'final').
  Future<void> _openFinalInvoice(BuildContext context, String bookingId) async {
    try {
      final res = await MotoGoSupabase.client
          .from('invoices')
          .select()
          .eq('booking_id', bookingId)
          .inFilter('type', ['final', 'issued'])
          .order('created_at', ascending: false)
          .limit(1);

      final invoices = (res as List);
      if (invoices.isEmpty) {
        if (!mounted) return;
        showMotoGoToast(context, icon: '📄', title: t(context).tr('invoiceLabel'), message: t(context).tr('invoiceNotReady'));
        return;
      }

      final invoice = UserInvoice.fromJson(invoices.first as Map<String, dynamic>);

      String? customerName;
      String? customerAddress;
      String? customerEmail;
      String? customerPhone;
      String? customerCompany;
      String? customerCompanyAddress;
      String? customerIco;
      String? customerDic;
      final user = MotoGoSupabase.currentUser;
      if (user != null) {
        try {
          final profile = await MotoGoSupabase.client
              .from('profiles')
              .select('full_name, email, phone, street, city, zip, country, ico, dic, company_name, company_address')
              .eq('id', user.id)
              .maybeSingle();
          if (profile != null) {
            customerName = profile['full_name'] as String?;
            customerEmail = profile['email'] as String?;
            customerPhone = profile['phone'] as String?;
            customerCompany = profile['company_name'] as String?;
            customerCompanyAddress = profile['company_address'] as String?;
            customerIco = profile['ico'] as String?;
            customerDic = profile['dic'] as String?;
            final parts = [profile['street'], profile['city'], profile['zip'], profile['country']]
                .where((s) => s != null && (s as String).isNotEmpty)
                .join(', ');
            if (parts.isNotEmpty) customerAddress = parts;
          }
        } catch (e) {
          debugPrint('[INVOICE] Profile fetch error: $e');
        }
      }

      final html = InvoiceHtmlBuilder.build(
        invoice,
        customerName: customerName,
        customerAddress: customerAddress,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
        customerCompany: customerCompany,
        customerCompanyAddress: customerCompanyAddress,
        customerIco: customerIco,
        customerDic: customerDic,
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DocWebViewScreen(
          htmlContent: html,
          title: invoice.number ?? invoice.typeLabel,
        ),
      ));
    } catch (e) {
      debugPrint('[INVOICE] Error opening final invoice: $e');
      if (!mounted) return;
      showMotoGoToast(context, icon: '⚠️', title: t(context).error, message: t(context).tr('invoiceLoadError'));
    }
  }
}
