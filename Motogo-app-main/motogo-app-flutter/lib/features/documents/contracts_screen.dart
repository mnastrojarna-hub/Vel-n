import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'doc_webview_screen.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/data/legal_texts.dart';
import 'document_models.dart';
import 'document_provider.dart';

/// Company constant — mirrors COMPANY from documents.js.
const _company = (
  name: 'Bc. Petra Semorádová',
  ic: '21874263',
  sidlo: 'Mezná 9, 393 01 Mezná',
  email: 'info@motogo24.cz',
);

/// Contracts & documents screen — mirrors s-contracts from templates-done-pages.js.
/// Shows rental contracts, handover protocols, VOP.
class ContractsScreen extends ConsumerWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(contractsProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: Row(children: [ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/logo.png', width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 24, height: 24, decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.motorcycle, size: 14, color: Colors.black)))), const SizedBox(width: 8), Text(t(context).tr('documentsAndContracts'))]), backgroundColor: MotoGoColors.dark),
      body: docsAsync.when(
        data: (docs) {
          final contracts = docs.where((d) => ['contract', 'protocol', 'vop'].contains(d.type)).toList();
          debugPrint('[CONTRACTS_SCREEN] Total docs: ${docs.length}, filtered contracts: ${contracts.length}');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DocTile(
                icon: '📋',
                title: t(context).tr('termsOfService'),
                subtitle: t(context).tr('vopSubtitle'),
                onTap: () => _showVop(context),
              ),
              _DocTile(
                icon: '🔒',
                title: t(context).tr('dataProcessing'),
                subtitle: t(context).tr('gdprSubtitle'),
                onTap: () => _showGdpr(context),
              ),
              if (contracts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: Text(t(context).tr('noOtherDocs'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400))),
                ),
              ...contracts.map((d) => _DocTile(
                icon: d.type == 'contract' ? '📄' : '📝',
                title: d.name ?? d.typeLabel,
                subtitle: '${d.createdAt.day}. ${d.createdAt.month}. ${d.createdAt.year}',
                onTap: () => _openDoc(context, d),
              )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
        error: (e, st) {
          debugPrint('[CONTRACTS_SCREEN] Provider error: $e\n$st');
          return Center(child: Text('Chyba: $e', style: const TextStyle(color: MotoGoColors.red, fontSize: 12)));
        },
      ),
    );
  }

  Future<void> _showVop(BuildContext context) async {
    await _showLegalFromSupabase(context, 'vop', 'Všeobecné obchodní podmínky');
  }

  Future<void> _showGdpr(BuildContext context) async {
    await _showLegalFromSupabase(context, 'gdpr', 'Zpracování osobních údajů');
  }

  /// Load legal text from document_templates table in Supabase and open in WebView.
  /// Falls back to local LegalTexts if fetch fails.
  Future<void> _showLegalFromSupabase(BuildContext ctx, String type, String fallbackTitle) async {
    String title = fallbackTitle;
    String? contentHtml;
    try {
      final res = await MotoGoSupabase.client
          .from('document_templates')
          .select('name, content_html')
          .eq('type', type)
          .eq('active', true)
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();
      if (res != null) {
        title = res['name'] as String? ?? fallbackTitle;
        final raw = (res['content_html'] as String? ?? '').trim();
        if (raw.isNotEmpty) contentHtml = raw;
      }
    } catch (e) {
      debugPrint('[CONTRACTS] Legal text fetch failed ($type): $e');
    }

    // Build HTML body — use DB content or fallback plain text wrapped in <p>
    final String bodyHtml;
    if (contentHtml != null) {
      bodyHtml = contentHtml;
    } else {
      final plainText = type == 'vop' ? LegalTexts.vopSummary : LegalTexts.gdprSummary;
      bodyHtml = '<p>${plainText.replaceAll('\n\n', '</p><p>').replaceAll('\n', '<br/>')}</p>';
    }

    if (!ctx.mounted) return;

    final html = _wrapHtml(title, bodyHtml);
    final dataUri = 'data:text/html;charset=utf-8;base64,${base64Encode(utf8.encode(html))}';
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => DocWebViewScreen(url: dataUri, title: title),
    ));
  }

  /// Open contract/protocol — render from document_templates + booking data.
  /// Mirrors showRentalContract / showDigitalProtocol from documents-booking.js.
  Future<void> _openDoc(BuildContext context, UserDocument doc) async {
    final title = doc.name ?? doc.typeLabel;
    debugPrint('[CONTRACTS] Opening doc: id=${doc.id}, type=${doc.type}, bookingId=${doc.bookingId}');

    // Fetch template from document_templates
    final dbType = _docTypeToTemplateType(doc.type);
    String? templateHtml;
    try {
      final tplRes = await MotoGoSupabase.client
          .from('document_templates')
          .select('content_html')
          .eq('type', dbType)
          .eq('active', true)
          .order('version', ascending: false)
          .limit(1)
          .maybeSingle();
      templateHtml = tplRes?['content_html'] as String?;
    } catch (e) {
      debugPrint('[CONTRACTS] Template fetch failed: $e');
    }

    // Fetch booking data if available
    Map<String, String> vars = _companyVars();
    if (doc.bookingId != null) {
      try {
        final bRes = await MotoGoSupabase.client
            .from('bookings')
            .select('*, motorcycles(*), profiles(*)')
            .eq('id', doc.bookingId!)
            .maybeSingle();
        if (bRes != null) {
          vars = _buildVars(bRes);
        }
      } catch (e) {
        debugPrint('[CONTRACTS] Booking data fetch failed: $e');
      }
    }

    // Build HTML body
    String bodyHtml;
    if (templateHtml != null && templateHtml.isNotEmpty) {
      bodyHtml = _replacePlaceholders(templateHtml, vars);
    } else {
      bodyHtml = _fallbackHtml(doc.type, vars);
    }

    if (!context.mounted) return;

    // Render HTML in WebView via data URI
    final html = _wrapHtml(title, bodyHtml);
    final dataUri = 'data:text/html;charset=utf-8;base64,${base64Encode(utf8.encode(html))}';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DocWebViewScreen(url: dataUri, title: title),
    ));
  }

  /// Map document type to template type in document_templates table.
  String _docTypeToTemplateType(String type) => switch (type) {
    'contract' => 'rental_contract',
    'protocol' => 'handover_protocol',
    _ => type,
  };

  /// Company-only vars (when no booking data).
  Map<String, String> _companyVars() => {
    'company_name': _company.name,
    'company_address': _company.sidlo,
    'company_ico': _company.ic,
    'company_dic': '',
    'company_email': _company.email,
  };

  /// Build all placeholder vars from booking + moto + profile data.
  Map<String, String> _buildVars(Map<String, dynamic> b) {
    final m = b['motorcycles'] as Map<String, dynamic>?;
    final p = b['profiles'] as Map<String, dynamic>?;

    final motoName = m?['model'] as String? ?? 'Motorka';
    final pName = p?['full_name'] as String? ?? '—';
    final pStreet = p?['street'] as String? ?? '';
    final pCity = p?['city'] as String? ?? '';
    final pZip = p?['zip'] as String? ?? '';
    final pAddr = '$pStreet, $pCity $pZip'.trim();
    final resNum = '#${(b['id'] as String).substring((b['id'] as String).length - 8).toUpperCase()}';

    final startDate = DateTime.tryParse(b['start_date'] as String? ?? '');
    final endDate = DateTime.tryParse(b['end_date'] as String? ?? '');
    final days = (startDate != null && endDate != null)
        ? (endDate.difference(startDate).inDays + 1).clamp(1, 9999)
        : 1;
    final totalPrice = (b['total_price'] as num?)?.toDouble() ?? 0;
    final dailyRate = (totalPrice / days).round();

    String fmtDate(DateTime? d) => d != null ? '${d.day}.${d.month}.${d.year}' : '—';
    final now = DateTime.now();

    return {
      ..._companyVars(),
      'customer_name': pName,
      'customer_address': pAddr,
      'customer_phone': p?['phone'] as String? ?? '—',
      'customer_email': p?['email'] as String? ?? '—',
      'customer_license': p?['license_number'] as String? ?? '—',
      'customer_license_expiry': p?['license_expiry'] as String? ?? '',
      'customer_ico': p?['ico'] as String? ?? '',
      'customer_dic': p?['dic'] as String? ?? '',
      'customer_id_number': p?['id_number'] as String? ?? '',
      'moto_model': motoName,
      'moto_name': motoName,
      'moto_spz': m?['spz'] as String? ?? '—',
      'moto_vin': m?['vin'] as String? ?? '—',
      'moto_year': '${m?['year'] ?? ''}',
      'start_date': fmtDate(startDate),
      'end_date': fmtDate(endDate),
      'date_from': fmtDate(startDate),
      'date_to': fmtDate(endDate),
      'start_time': b['pickup_time'] as String? ?? '',
      'end_time': '24:00',
      'days': '$days',
      'rental_period': '${fmtDate(startDate)} — ${fmtDate(endDate)} ($days dní)',
      'total_price': '${totalPrice.round()}',
      'total_price_words': '',
      'daily_rate': '$dailyRate',
      'extras_price': '${(b['extras_price'] as num?)?.round() ?? 0}',
      'delivery_fee': '${(b['delivery_fee'] as num?)?.round() ?? 0}',
      'discount': '${(b['discount_amount'] as num?)?.round() ?? 0}',
      'res_number': resNum,
      'booking_number': resNum,
      'booking_id': resNum,
      'today': fmtDate(now),
      'today_time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'pickup_location': b['pickup_address'] as String? ?? 'Mezná 9, 393 01 Mezná',
      'return_location': b['return_address'] as String? ?? 'Mezná 9, 393 01 Mezná',
      'mileage': '${b['mileage_start'] ?? ''}',
      'fuel_state': '',
      'technical_state': '',
    };
  }

  /// Replace both {{key}} and {key} placeholders in template HTML.
  String _replacePlaceholders(String html, Map<String, String> vars) {
    var result = html;
    for (final entry in vars.entries) {
      result = result
          .replaceAll('{{${entry.key}}}', entry.value)
          .replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  /// Fallback HTML when no template available.
  String _fallbackHtml(String type, Map<String, String> v) {
    if (type == 'protocol') {
      return '<h3>Předávací protokol</h3>'
          '<p><strong>${v['company_name']}</strong></p>'
          '<p><strong>${v['customer_name']}</strong></p>'
          '<p>Motorka: ${v['moto_model']}</p>'
          '<p>SPZ: ${v['moto_spz']}</p>'
          '<p>Datum převzetí: ${v['start_date']}</p>'
          '<p>Datum vrácení: ${v['end_date']}</p>';
    }
    return '<h3>Nájemní smlouva</h3>'
        '<p><strong>Pronajímatel:</strong> ${v['company_name']}, ${v['company_address']}, IČ: ${v['company_ico']}</p>'
        '<p><strong>Nájemce:</strong> ${v['customer_name']}, ${v['customer_address']}, ŘP: ${v['customer_license']}</p>'
        '<h4>Předmět nájmu</h4>'
        '<p>${v['moto_model']}, SPZ: ${v['moto_spz']}, VIN: ${v['moto_vin']}</p>'
        '<p>Období: ${v['rental_period']}</p>'
        '<h4>Cena</h4>'
        '<p>Celkem: ${v['total_price']} Kč</p>';
  }

  /// Wrap body HTML in a full HTML document with basic styling.
  String _wrapHtml(String title, String body) => '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:system-ui,-apple-system,sans-serif;padding:16px;color:#1A2E22;font-size:13px;line-height:1.6}
h3{font-size:16px;font-weight:900;margin:0 0 12px}
h4{font-size:13px;font-weight:800;margin:16px 0 6px}
p{margin:4px 0}
</style></head><body>$body
<div style="margin-top:14px;padding:10px;background:#f0fdf4;border-radius:8px;font-size:11px;color:#1a8a18;font-weight:700;">
&#10003; Souhlas udělen při rezervaci (zaškrtnutím podmínek)</div>
</body></html>''';
}

class _DocTile extends StatelessWidget {
  final String icon; final String title; final String subtitle; final VoidCallback onTap;
  const _DocTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
        ])),
        const Text('›', style: TextStyle(fontSize: 16, color: MotoGoColors.g400)),
      ]),
    ),
  );
}
