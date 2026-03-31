import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/supabase_client.dart';
import 'document_models.dart';
import 'document_provider.dart';

/// Invoices list — mirrors s-invoices from templates-done-pages.js.
/// Shows advance invoices, payment receipts, final invoices, credit notes.
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(title: const Text('🧾 Faktury a vyúčtování'), backgroundColor: MotoGoColors.dark),
      body: invoicesAsync.when(
        data: (invoices) {
          if (invoices.isEmpty) {
            return const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🧾', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text('Žádné faktury', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                Text('Faktury se generují automaticky', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
              ],
            ));
          }

          // Group by year
          final grouped = <int, List<UserInvoice>>{};
          for (final inv in invoices) {
            final year = inv.createdAt.year;
            grouped.putIfAbsent(year, () => []).add(inv);
          }
          final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final year in years) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 8),
                  child: Text('$year', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.g400)),
                ),
                ...grouped[year]!.map((inv) => _InvoiceTile(invoice: inv)),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
        error: (_, __) => const Center(child: Text('Chyba načítání', style: TextStyle(color: MotoGoColors.red))),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final UserInvoice invoice;
  const _InvoiceTile({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final isCN = invoice.isCreditNote;
    final date = '${invoice.createdAt.day}. ${invoice.createdAt.month}. ${invoice.createdAt.year}';

    return GestureDetector(
      onTap: () => _openInvoice(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: isCN ? Border.all(color: MotoGoColors.red.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          children: [
            Text(_typeIcon(invoice.type), style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.number ?? invoice.typeLabel,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: isCN ? MotoGoColors.red : MotoGoColors.black)),
                Text(date, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
              ],
            )),
            if (invoice.total != null)
              Text(
                '${isCN ? "−" : ""}${invoice.total!.toStringAsFixed(0)} Kč',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: isCN ? MotoGoColors.red : MotoGoColors.black),
              ),
          ],
        ),
      ),
    );
  }

  String _typeIcon(String type) => switch (type) {
    'proforma' || 'advance' => '🧾',
    'final' => '💰',
    'payment_receipt' => '✅',
    'shop_final' => '🛒',
    'credit_note' => '📕',
    _ => '📄',
  };

  Future<void> _openInvoice(BuildContext context) async {
    if (invoice.pdfPath != null && invoice.pdfPath!.isNotEmpty) {
      final url = MotoGoSupabase.client.storage.from('documents').getPublicUrl(invoice.pdfPath!);
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
