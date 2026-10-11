import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/i18n/app_lang.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';

/// Odkud je zobrazený text smluvního dokumentu.
enum LegalDocKind {
  /// Česká verze pro českou appku.
  czech,

  /// Aktuální překlad (právně závazné je české znění).
  translation,

  /// Překlad chybí nebo je zastaralý → závazná česká verze.
  czechFallback,
}

class LegalDocText {
  final String html;
  final LegalDocKind kind;
  const LegalDocText(this.html, this.kind);
}

/// Načte šablonu smluvního dokumentu (`document_templates.type` = [slug]:
/// vop, gdpr, rental_contract, damage_protocol…) v jazyce [lang] přes RPC
/// `get_document_translation`. RPC vrací NULL, když překlad chybí nebo je
/// ZASTARALÝ (česká verze se od překladu změnila — migrace 20261011
/// `translation_src`), takže se zákazníkovi nikdy neukáže stará verze
/// podmínek: místo ní dostane závaznou češtinu s poznámkou. Před migrací
/// (sloupec `translation_src` v DB chybí) RPC vrací i zastaralý překlad —
/// pak platí totéž co pro web, edge i Velín: překlad nelze ověřit = zastaralý.
/// `null` = dokument se nepodařilo načíst (offline / chyba serveru).
Future<LegalDocText?> loadLegalDoc(String slug, String lang) async {
  final l = normalizeAppLang(lang);
  try {
    if (l != 'cs') {
      final tr = await _fetch(slug, l);
      if (tr != null && await _freshnessTracked()) {
        return LegalDocText(tr, LegalDocKind.translation);
      }
    }
    final cs = await _fetch(slug, 'cs');
    if (cs == null) return null;
    return LegalDocText(cs, l == 'cs' ? LegalDocKind.czech : LegalDocKind.czechFallback);
  } catch (e) {
    debugPrint('[LEGAL] $slug/$l load failed: $e');
    return null;
  }
}

/// true = DB eviduje čerstvost překladů (`document_templates.translation_src`,
/// migrace 20261011) a RPC vrací jen aktuální překlad. Kladný výsledek se
/// pamatuje do konce běhu appky; záporný se ověří znovu (migrace mohla doběhnout).
bool _freshnessColumn = false;

Future<bool> _freshnessTracked() async {
  if (_freshnessColumn) return true;
  try {
    await MotoGoSupabase.client
        .from('document_templates')
        .select('translation_src')
        .limit(1);
    return _freshnessColumn = true;
  } on PostgrestException catch (e) {
    // 42703 = sloupec neexistuje → migrace ještě neproběhla.
    if (e.code == '42703' || e.message.contains('translation_src')) return false;
    return true; // jiná chyba — rozhodne RPC (jeho chyba = „nenačteno")
  }
}

Future<String?> _fetch(String slug, String lang) async {
  final res = await MotoGoSupabase.client.rpc('get_document_translation',
      params: {'p_template_slug': slug, 'p_language': lang});
  final s = res is String ? res.trim() : '';
  return s.isEmpty ? null : s;
}

/// Lokalizovaná poznámka nad textem dokumentu (prázdná u češtiny).
String legalNoticeHtml(AppTranslations tr, LegalDocKind kind) {
  final key = switch (kind) {
    LegalDocKind.czech => null,
    LegalDocKind.translation => 'legalTranslationNote',
    LegalDocKind.czechFallback => 'legalCzechOnlyNote',
  };
  if (key == null) return '';
  return '<div style="margin:0 0 14px;padding:10px 12px;background:#fff7e6;'
      'border:1px solid #f5c26b;border-radius:8px;font-size:12px;color:#7a4b00;'
      'font-weight:600;">${htmlEscapeText(tr.tr(key))}</div>';
}

/// Lokalizovaná hláška místo dokumentu (nenačteno / zatím nevystaveno).
String legalMessageHtml(String text) =>
    '<p style="padding:12px;background:#f3f6f4;border-radius:8px">${htmlEscapeText(text)}</p>';

String htmlEscapeText(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\n', '<br/>');

/// Celý HTML dokument pro WebView. [consentNote] = patička „souhlas udělen při
/// rezervaci" — JEN u VOP/GDPR (u protokolů/smluv neplatí: podpis je
/// elektronický na kiosku / ve Velíně / v appce; zadání majitele 2026-09-29).
String wrapDocHtml(String title, String body, {String? consentNote}) => '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{font-family:system-ui,-apple-system,sans-serif;padding:16px;color:#1A2E22;font-size:13px;line-height:1.6}
h3{font-size:16px;font-weight:900;margin:0 0 12px}
h4{font-size:13px;font-weight:800;margin:16px 0 6px}
p{margin:4px 0}
</style></head><body>$body${consentNote == null ? '' : '''
<div style="margin-top:14px;padding:10px;background:#f0fdf4;border-radius:8px;font-size:11px;color:#1a8a18;font-weight:700;">
&#10003; ${htmlEscapeText(consentNote)}</div>'''}
</body></html>''';
