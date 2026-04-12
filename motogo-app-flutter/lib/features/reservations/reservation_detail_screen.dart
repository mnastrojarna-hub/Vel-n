import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../auth/widgets/toast_helper.dart';
import '../documents/document_models.dart';
import '../documents/doc_webview_screen.dart';
import '../documents/invoice_html_builder.dart';
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

  @override
  Widget build(BuildContext context) {
    final resAsync = ref.watch(reservationByIdProvider(widget.bookingId));
    final doorCodesAsync = ref.watch(doorCodesProvider(widget.bookingId));

    return resAsync.when(
      data: (res) => res == null
          ? _error(t(context).tr('reservationNotFound'))
          : _buildDetail(context, res, doorCodesAsync),
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
                        onTap: () => context.pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: MotoGoColors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
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
                      child: CachedNetworkImage(
                        imageUrl: res.motoImage ?? '',
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: MotoGoColors.g200,
                          child: const Icon(Icons.motorcycle, size: 48, color: MotoGoColors.g400),
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
      final user = MotoGoSupabase.currentUser;
      if (user != null) {
        try {
          final profile = await MotoGoSupabase.client
              .from('profiles')
              .select('full_name, street, city, zip, country')
              .eq('id', user.id)
              .maybeSingle();
          if (profile != null) {
            customerName = profile['full_name'] as String?;
            final parts = [profile['street'], profile['city'], profile['zip'], profile['country']]
                .where((s) => s != null && (s as String).isNotEmpty)
                .join(', ');
            if (parts.isNotEmpty) customerAddress = parts;
          }
        } catch (e) {
          debugPrint('[INVOICE] Profile fetch error: $e');
        }
      }

      final html = InvoiceHtmlBuilder.build(invoice, customerName: customerName, customerAddress: customerAddress);
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
