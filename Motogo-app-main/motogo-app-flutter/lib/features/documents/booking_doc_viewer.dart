import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_client.dart';
import 'doc_webview_screen.dart';
import 'pdf_pages_screen.dart';

/// Otevírání REÁLNÝCH dokumentů rezervace 1:1 — stejný vzor jako ve Velíně
/// a na webu (úprava rezervace). Detail rezervace = AKTUÁLNÍ (nejnovější)
/// verze, historie všech verzí je v Dokumenty a smlouvy (`contractsProvider`).
/// Zdroje:
///  1. `generated_documents` — `_signed_html` = přesné podepsané HTML
///     elektronického protokolu (kiosk / appka / Velín), jinak `pdf_path`.
///     Typ z `filled_data._doc_type`, u smlouvy/VOP z šablony (`template_id`).
///  2. `documents.file_path` (sync řádky, ručně nahrané skeny) — jen když
///     soubor nepatří generovanému dokumentu jiného typu / šabloně protokolu.
/// Protokol se ukáže JEN elektronický (má `_doc_type`, bez šablony) nebo
/// nahraný sken — šablona předvyplněná jen daty rezervace (Velín ji generuje
/// při ručním přepnutí na „aktivní“) není reálný protokol (zadání majitele
/// 2026-09-29: „vždycky jenom ten reálný, co jsem vyplnil“).

/// `filled_data._doc_type` / `document_templates.type` → `documents.type`.
const _typeMap = <String, String>{
  'handover_protocol': 'protocol',
  'damage_protocol': 'protocol_damage',
  'rental_contract': 'contract',
  'contract': 'contract',
  'vop': 'vop',
};

/// Reálný dokument daného typu: podepsané HTML nebo soubor v bucketu.
class BookingDocSource {
  final String? signedHtml;
  final String? path;
  const BookingDocSource({this.signedHtml, this.path});
}

/// Nejnovější reálný dokument rezervace pro každý typ (contract, protocol,
/// protocol_damage, vop).
Future<Map<String, BookingDocSource>> resolveBookingDocs(String bookingId) async {
  final out = <String, BookingDocSource>{};
  // soubor generovaného dokumentu → (typ, reálný?) — hlídá fallback na documents
  final genPaths = <String, (String?, bool)>{};
  try {
    final rows = ((await MotoGoSupabase.client
            .from('generated_documents')
            .select('id, template_id, filled_data, pdf_path, created_at')
            .eq('booking_id', bookingId)
            .order('created_at', ascending: false)) as List)
        .cast<Map<String, dynamic>>();
    final tplType = await _templateTypes(rows);
    for (final r in rows) {
      final fd = r['filled_data'] is Map ? r['filled_data'] as Map : const {};
      final electronic = r['template_id'] == null && fd['_doc_type'] is String;
      final type = _typeMap[electronic ? fd['_doc_type'] : tplType[r['template_id']]];
      final real = type != null && (electronic || (type != 'protocol' && type != 'protocol_damage'));
      final path = r['pdf_path'] as String?;
      for (final p in [path, 'generated/${r['id']}.html'].whereType<String>()) {
        genPaths[p] = (type, real);
      }
      if (!real || out.containsKey(type)) continue;
      final html = fd['_signed_html'];
      out[type] = BookingDocSource(signedHtml: html is String && html.isNotEmpty ? html : null, path: path);
    }
  } catch (e) {
    debugPrint('[BOOKING_DOC] generated_documents fetch failed: $e');
  }
  try {
    final docs = await MotoGoSupabase.client
        .from('documents')
        .select('type, file_path, created_at')
        .eq('booking_id', bookingId)
        .inFilter('type', ['contract', 'protocol', 'protocol_damage', 'vop'])
        .order('created_at', ascending: false);
    for (final d in (docs as List).cast<Map<String, dynamic>>()) {
      final type = d['type'] as String?;
      final path = d['file_path'] as String?;
      if (type == null || out.containsKey(type) || path == null || path.isEmpty) continue;
      if (path.startsWith('mindee_verified/')) continue; // marker, ne soubor
      final gen = genPaths[path];
      if (gen != null && (gen.$1 != type || !gen.$2)) continue; // VOP pod „contract“ / šablona protokolu
      out[type] = BookingDocSource(path: path);
    }
  } catch (e) {
    debugPrint('[BOOKING_DOC] documents fetch failed: $e');
  }
  return out;
}

/// Reálné dokumenty rezervace — tlačítka v sekci Dokumenty detailu rezervace.
/// autoDispose: po návratu do detailu (a invalidaci při změně rezervace, např.
/// podpisu na kiosku) se načtou znovu.
final bookingDocsProvider =
    FutureProvider.autoDispose.family<Map<String, BookingDocSource>, String>((ref, bookingId) async {
  if (MotoGoSupabase.currentUser == null) return const {};
  return resolveBookingDocs(bookingId);
});

/// Otevře AKTUÁLNÍ reálný dokument rezervace daného typu. Vrací false, když
/// neexistuje — volající zobrazí hlášku.
Future<bool> openBookingDocument(
  BuildContext context, {
  required String bookingId,
  required String type,
  required String title,
}) async {
  final src = (await resolveBookingDocs(bookingId))[type];
  if (src == null || !context.mounted) return false;
  if (src.signedHtml != null) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DocWebViewScreen(htmlContent: src.signedHtml!, title: title),
    ));
    return true;
  }
  return _openStoragePath(context, src.path, title);
}

/// Konkrétní soubor z bucketu `documents` (řádek historie bez generated dvojčete).
Future<bool> openStorageDocument(BuildContext context, String? filePath, String title) =>
    _openStoragePath(context, filePath, title);

/// `template_id` → `document_templates.type` (rental_contract, vop, …) druhým
/// dotazem, stejně jako `contractsProvider` (RLS: jen aktivní šablony).
Future<Map<String, String>> _templateTypes(List<Map<String, dynamic>> rows) async {
  final ids = rows.map((r) => r['template_id']).whereType<String>().toSet().toList();
  if (ids.isEmpty) return const {};
  try {
    final tpls = await MotoGoSupabase.client.from('document_templates').select('id, type').inFilter('id', ids);
    return {
      for (final t in (tpls as List).cast<Map<String, dynamic>>())
        if (t['type'] is String) t['id'] as String: t['type'] as String,
    };
  } catch (e) {
    debugPrint('[BOOKING_DOC] templates fetch failed: $e');
    return const {};
  }
}

/// Otevře KONKRÉTNÍ dokument z `generated_documents` (historická verze) —
/// podepsané HTML 1:1, jinak soubor z bucketu přes signed URL.
Future<bool> openGeneratedDocument(
  BuildContext context, {
  required String generatedDocId,
  required String title,
}) async {
  try {
    final row = await MotoGoSupabase.client
        .from('generated_documents')
        .select('filled_data, pdf_path')
        .eq('id', generatedDocId)
        .maybeSingle();
    if (row == null) return false;
    final fd = row['filled_data'];
    final html = fd is Map ? fd['_signed_html'] as String? : null;
    if (html != null && html.isNotEmpty) {
      if (!context.mounted) return false;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DocWebViewScreen(htmlContent: html, title: title),
      ));
      return true;
    }
    return await _openStoragePath(context, row['pdf_path'] as String?, title);
  } catch (e) {
    debugPrint('[BOOKING_DOC] generated doc open failed ($generatedDocId): $e');
    return false;
  }
}

/// Soubor z bucketu `documents` přes signed URL — .html ve WebView, .pdf na
/// Androidu v appce přes nativní PdfRenderer (`PdfPagesScreen`; WebView tam PDF
/// nevyrenderuje a externí prohlížeč zákazník bral jako „odkaz na web“), iOS
/// WKWebView PDF zobrazí sám.
Future<bool> _openStoragePath(BuildContext context, String? filePath, String title) async {
  // marker řádky (mindee_verified/...) nejsou reálné soubory
  if (filePath == null || filePath.isEmpty || filePath.startsWith('mindee_verified/')) {
    return false;
  }

  try {
    final url = await MotoGoSupabase.client.storage
        .from('documents')
        .createSignedUrl(filePath, 600);
    if (!context.mounted) return false;
    final isPdf = filePath.toLowerCase().endsWith('.pdf');
    if (isPdf && defaultTargetPlatform == TargetPlatform.android) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfPagesScreen(url: url, title: title),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DocWebViewScreen(url: url, title: title),
      ));
    }
    return true;
  } catch (e) {
    debugPrint('[BOOKING_DOC] signed URL failed ($filePath): $e');
    return false;
  }
}
