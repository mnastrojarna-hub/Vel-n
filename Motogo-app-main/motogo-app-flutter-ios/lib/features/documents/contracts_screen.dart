import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'doc_webview_screen.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/offline_guard.dart';
import '../../core/widgets/error_feedback.dart';
import '../../core/widgets/state_views.dart';
import 'legal_doc_loader.dart';
import 'booking_doc_viewer.dart';
import '../auth/widgets/toast_helper.dart';
import 'document_models.dart';
import 'document_provider.dart';
import '../../core/date_days.dart';
import '../../core/booking_rules.dart';

/// Company constant — mirrors COMPANY from documents.js.
const _company = (
  name: 'Bc. Petra Semorádová',
  ic: '21874263',
  sidlo: 'Mezná 9, 393 01 Pelhřimov',
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
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(Routes.profile);
            }
          },
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: Row(children: [ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/logo.webp', width: 24, height: 24, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 24, height: 24, decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.motorcycle, size: 14, color: Colors.black)))), const SizedBox(width: 8), Text(t(context).tr('documentsAndContracts'))]), backgroundColor: MotoGoColors.dark),
      // Statické dokumenty (VOP, GDPR, vzor protokolu) nepotřebují načtený
      // seznam → jsou vidět vždy, i při chybě (dřív holé „Chyba načítání").
      body: ListView(
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
          // Vzor protokolu o poškození (přeložená šablona z document_templates).
          // Nevyplněný vzor PŘEDÁVACÍHO protokolu je pryč (zadání majitele
          // 2026-09-29): předávací protokol je vždy elektronický (kiosk /
          // Velín / appka) a v seznamu níž je jen ten reálně podepsaný.
          _DocTile(
            icon: '⚠️',
            title: t(context).tr('damageProtocol'),
            subtitle: t(context).tr('damageProtocolSubtitle'),
            onTap: () => _showTemplateSample(context, 'damage_protocol', t(context).tr('damageProtocol')),
          ),
          ...docsAsync.when(
            data: (docs) {
              final contracts = docs.where((d) => ['contract', 'protocol', 'protocol_damage', 'vop'].contains(d.type)).toList();
              debugPrint('[CONTRACTS_SCREEN] Total docs: ${docs.length}, filtered contracts: ${contracts.length}');
              return [
                if (contracts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text(t(context).tr('noOtherDocs'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400))),
                  ),
                ...contracts.map((d) => _DocTile(
                  icon: switch (d.type) { 'contract' => '📄', 'protocol_damage' => '⚠️', _ => '📝' },
                  title: docDisplayTitle(t(context), d),
                  subtitle: '${d.createdAt.day}. ${d.createdAt.month}. ${d.createdAt.year}',
                  onTap: () => _openDoc(context, d),
                )),
              ];
            },
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
              ),
            ],
            error: (e, st) {
              debugPrint('[CONTRACTS_SCREEN] Provider error: $e\n$st');
              return [
                const SizedBox(height: 8),
                MgErrorView(
                  compact: true,
                  error: e,
                  what: t(context).tr('eoContractsLoadFail'),
                  onRetry: () => ref.invalidate(contractsProvider),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showVop(BuildContext context) async {
    await showLegalDocument(context, 'vop');
  }

  Future<void> _showGdpr(BuildContext context) async {
    await showLegalDocument(context, 'gdpr');
  }

  /// Show a translated document-template *sample* (vzor) — damage protocol.
  /// Text přes [loadLegalDoc]: čerstvý překlad, jinak závazná čeština s
  /// poznámkou; nadpis vždy z lokalizovaného UI (DB názvy bývají česky).
  Future<void> _showTemplateSample(BuildContext ctx, String type, String title) async {
    final lang = Localizations.localeOf(ctx).languageCode;
    final tr = t(ctx);
    final doc = await loadLegalDoc(type, lang);
    final bodyHtml = doc == null
        ? legalMessageHtml(tr.tr('legalLoadFailed'))
        // Nevyplněné {{placeholdery}} (vzor nemá data rezervace) nahraď
        // prázdným polem — ať se nezobrazují syrové značky „{{customer_name}}".
        : legalNoticeHtml(tr, doc.kind) + _stripPlaceholders(doc.html);

    if (!ctx.mounted) return;
    final html = wrapDocHtml(title, bodyHtml);
    final dataUri = 'data:text/html;charset=utf-8;base64,${base64Encode(utf8.encode(html))}';
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => DocWebViewScreen(url: dataUri, title: title),
    ));
  }

  /// Open contract/protocol — REÁLNÝ dokument 1:1 (podepsané HTML z
  /// generated_documents / soubor z bucketu). Položka historie otevře PŘESNĚ
  /// svou verzi. Když neexistuje: smlouva/VOP fallback na render šablony +
  /// dat rezervace; protokol NIKDY (šablona není vyplněný protokol — zadání
  /// majitele 2026-09-29) → hláška.
  static bool _opening = false;

  /// Otevření s průběhem a pojistkou proti dvojímu klepnutí; bez internetu
  /// řekne „nejsi připojený" (dřív mylně „Dokument zatím není k dispozici").
  Future<void> _openDoc(BuildContext context, UserDocument doc) async {
    if (_opening) return;
    _opening = true;
    final progress = MgProgress.show(context, t(context).tr('eoOpeningDoc'));
    try {
      await _openDocInner(context, doc);
    } catch (e) {
      progress.close();
      if (context.mounted) {
        showErrorSnack(context, t(context).tr('eoDocLoadFail'), e, where: 'contract_open');
      }
    } finally {
      progress.close();
      _opening = false;
    }
  }

  Future<void> _openDocInner(BuildContext context, UserDocument doc) async {
    final tr = t(context);
    final title = docDisplayTitle(tr, doc);
    debugPrint('[CONTRACTS] Opening doc: id=${doc.id}, type=${doc.type}, bookingId=${doc.bookingId}');

    // Historický záznam přímo z generated_documents → otevři PŘESNĚ tento
    // dokument (ne poslední daného typu).
    if (doc.generatedDocId != null) {
      final opened = await openGeneratedDocument(context,
          generatedDocId: doc.generatedDocId!, title: title);
      if (opened) return;
      if (!context.mounted) return;
    } else if (doc.filePath != null) {
      // Řádek `documents` bez generated dvojčete (např. nahraný sken) → jeho soubor.
      final opened = await openStorageDocument(context, doc.filePath, title);
      if (opened) return;
      if (!context.mounted) return;
    }

    if (doc.bookingId != null) {
      final opened = await openBookingDocument(context,
          bookingId: doc.bookingId!, type: doc.type, title: title);
      if (opened) return;
      if (!context.mounted) return;
    }

    if (doc.type == 'protocol' || doc.type == 'protocol_damage') {
      if (!await OfflineGuard.pingSupabase()) throw const SocketException('offline');
      if (!context.mounted) return;
      showMotoGoToast(context, icon: '📄', title: title, message: t(context).tr('docNotAvailableYet'));
      return;
    }

    // Šablona v jazyce appky: čerstvý překlad, jinak závazná čeština s
    // poznámkou (nikdy zastaralý překlad) — viz [loadLegalDoc].
    final dbType = _docTypeToTemplateType(doc.type);
    final tpl = await loadLegalDoc(dbType, tr.lang);

    // Fetch booking data if available
    Map<String, String> vars = _companyVars();
    if (doc.bookingId != null) {
      try {
        final bRes = await MotoGoSupabase.client
            .from('bookings')
            .select('*, motorcycles!moto_id(*, branches(type, address, zip, city)), profiles(*)')
            .eq('id', doc.bookingId!)
            .maybeSingle();
        if (bRes != null) {
          vars = _buildVars(bRes, tr);
        }
      } catch (e) {
        debugPrint('[CONTRACTS] Booking data fetch failed: $e');
      }
    }

    // Bez šablony kvůli síti → důvod (nejsi připojený / server neodpovídá).
    if (tpl == null && !await OfflineGuard.pingSupabase()) {
      throw const SocketException('offline');
    }
    // Bez šablony (chyba) žádná improvizovaná česká smlouva —
    // lokalizovaná hláška, že dokument zatím není k dispozici.
    final bodyHtml = tpl == null
        ? legalMessageHtml(tr.tr('docNotAvailableYet'))
        : legalNoticeHtml(tr, tpl.kind) + _replacePlaceholders(tpl.html, vars);

    if (!context.mounted) return;

    // Render HTML in WebView via data URI
    final html = wrapDocHtml(title, bodyHtml);
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
  Map<String, String> _buildVars(Map<String, dynamic> b, AppTranslations tr) {
    final m = b['motorcycles'] as Map<String, dynamic>?;
    final p = b['profiles'] as Map<String, dynamic>?;

    final motoName = m?['model'] as String? ?? tr.motorcycle;
    final pName = p?['full_name'] as String? ?? '—';
    final pStreet = p?['street'] as String? ?? '';
    final pCity = p?['city'] as String? ?? '';
    final pZip = p?['zip'] as String? ?? '';
    final pAddr = '$pStreet, $pCity $pZip'.trim();
    final resNum = '#${(b['id'] as String).substring((b['id'] as String).length - 8).toUpperCase()}';

    final startDate = DateTime.tryParse(b['start_date'] as String? ?? '');
    final endDate = DateTime.tryParse(b['end_date'] as String? ?? '');
    final days = (startDate != null && endDate != null)
        ? calendarDaysInclusive(startDate, endDate).clamp(1, 9999)
        : 1;
    final totalPrice = (b['total_price'] as num?)?.toDouble() ?? 0;
    final dailyRate = (totalPrice / days).round();

    String fmtDate(DateTime? d) => d != null ? '${d.day}.${d.month}.${d.year}' : '—';
    final now = DateTime.now();
    // Samoobsluha, převzetí NA pobočce (shodně s edge generate-document,
    // zadání 2026-10-01 večer): začátek smlouvy = 12:00, má-li rezervace slevu
    // za vyzvednutí od 12:00 (dřív ji kiosk nevydá), jinak 00:01 (výdej od
    // půlnoci, i starší rezervace „bez času“); konec 24:00.
    final br = m?['branches'] as Map<String, dynamic>?;
    final brType = br?['type'] as String?;
    // Místo na pobočce = pobočka motorky (Brno Velké Němčice ≠ Mezná).
    final brAddr = [
      br?['address'] as String?,
      [br?['zip'] as String?, br?['city'] as String?]
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .join(' '),
    ].whereType<String>().where((e) => e.isNotEmpty).join(', ');
    final ssPickup = brType == selfServiceBranchType &&
        bookingMethodWithAddress(
                b['pickup_method'] as String?, b['pickup_address'] as String?) !=
            'delivery';
    final lateDiscount =
        (b['late_pickup_discount_amount'] as num?)?.toDouble() ?? 0;
    final storedPickup = b['pickup_time'] as String? ?? '';

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
      'start_time': ssPickup
          ? (lateDiscount > 0 ? '12:00' : selfServicePickupTime)
          // 00:01 u obslužné = zbytek po výměně ze samoobsluhy → bez času.
          : (isLegacyAllDayPickupTime(storedPickup) ? '' : storedPickup),
      'end_time': '24:00',
      'days': '$days',
      'rental_period': '${fmtDate(startDate)} — ${fmtDate(endDate)} ($days ${tr.daysWord(days)})',
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
      'pickup_location': b['pickup_address'] as String? ??
          (brAddr.isNotEmpty ? brAddr : 'Mezná 9, 393 01 Pelhřimov'),
      'return_location': b['return_address'] as String? ??
          (brAddr.isNotEmpty ? brAddr : 'Mezná 9, 393 01 Pelhřimov'),
      'mileage': '${b['mileage_start'] ?? ''}',
      'fuel_state': '',
      'technical_state': '',
    };
  }

  /// Pro „vzor" (bez rezervace) nahradí nevyplněné `{{placeholdery}}` prázdným
  /// polem, ať se v náhledu nezobrazují syrové značky. Bezpečně bere jen
  /// dvojité složené závorky (`{{key}}`), takže se nedotkne případného CSS
  /// `{ }` ve `<style>` šablony.
  String _stripPlaceholders(String html) => html.replaceAll(
        RegExp(r'\{\{\s*[\w.]+\s*\}\}'),
        '<span style="color:#9aa6a0">—</span>',
      );

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
}

/// Otevře VOP / GDPR ([slug] = `vop` | `gdpr`) v jazyce appky: čerstvý překlad
/// s poznámkou, že závazné je české znění, jinak závazná čeština s poznámkou,
/// že překlad zatím není. Offline → lokalizovaná hláška (dřív zastaralé české
/// shrnutí se špatnými údaji o spoluúčasti a pojištění).
Future<void> showLegalDocument(BuildContext ctx, String slug) async {
  final tr = t(ctx);
  final title = tr.tr(slug == 'gdpr' ? 'dataProcessing' : 'termsOfService');
  final doc = await loadLegalDoc(slug, tr.lang);
  final bodyHtml = doc == null
      ? legalMessageHtml(tr.tr('legalLoadFailed'))
      : legalNoticeHtml(tr, doc.kind) + doc.html;
  if (!ctx.mounted) return;
  final html = wrapDocHtml(title, bodyHtml,
      consentNote: doc == null ? null : tr.tr('consentGivenAtBooking'));
  final dataUri = 'data:text/html;charset=utf-8;base64,${base64Encode(utf8.encode(html))}';
  Navigator.of(ctx).push(MaterialPageRoute(
    builder: (_) => DocWebViewScreen(url: dataUri, title: title),
  ));
}

/// Nadpis dokumentu podle TYPU v jazyce appky. České názvy z DB
/// (`generated_documents.doc_name`, `documents.file_name`) slouží jen jako
/// název souboru — v cizojazyčné appce byly nadpisy česky.
String docDisplayTitle(AppTranslations tr, UserDocument d) {
  // Česká appka beze změny (pravidlo 1): český název z DB, jako dosud.
  final dbName = d.name?.trim() ?? '';
  if (tr.lang == 'cs' && dbName.isNotEmpty) return dbName;
  final key = d.typeKey;
  if (key != null) return tr.tr(key);
  return d.name ?? d.type;
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
