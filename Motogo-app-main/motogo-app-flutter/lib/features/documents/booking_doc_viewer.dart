import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import 'doc_webview_screen.dart';

/// Otevírání REÁLNÝCH dokumentů rezervace 1:1 — stejný vzor jako ve Velíně
/// a na webu (úprava rezervace). Priorita zdrojů:
///  1. `generated_documents.filled_data._signed_html` — přesné podepsané HTML
///     elektronického protokolu (Velín ElectronicProtocolModal /
///     edge submit-handover-protocol) — obsahuje checklisty i podpis.
///  2. `documents.file_path` / `generated_documents.pdf_path` — vyrenderovaný
///     soubor v bucketu `documents` přes signed URL (.html ve WebView,
///     .pdf na Androidu externě — WebView tam PDF neumí).
/// Vrací false, když žádný reálný dokument neexistuje — volající pak může
/// zobrazit fallback (šablonu) nebo hlášku.

/// Mapování `documents.type` → `filled_data._doc_type` v generated_documents.
const _generatedDocTypes = <String, List<String>>{
  'protocol': ['handover_protocol'],
  'protocol_damage': ['damage_protocol'],
  'contract': ['rental_contract', 'contract'],
  'vop': ['vop'],
};

/// Dokumenty (smlouva/protokoly) k rezervaci — pro sekci v detailu rezervace.
final bookingDocsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, bookingId) async {
  final user = MotoGoSupabase.currentUser;
  if (user == null) return const [];
  try {
    final res = await MotoGoSupabase.client
        .from('documents')
        .select('id, type, file_name, file_path, created_at')
        .eq('booking_id', bookingId)
        .inFilter('type', ['contract', 'protocol', 'protocol_damage'])
        .order('created_at', ascending: false);
    return (res as List).cast<Map<String, dynamic>>();
  } catch (e) {
    debugPrint('[BOOKING_DOCS] fetch failed: $e');
    return const [];
  }
});

Future<bool> openBookingDocument(
  BuildContext context, {
  required String bookingId,
  required String type,
  required String title,
}) async {
  final wanted = _generatedDocTypes[type] ?? [type];

  // 1) Přesné podepsané HTML z generated_documents (1:1 s Velínem).
  String? signedHtml;
  String? generatedPath;
  try {
    final rows = await MotoGoSupabase.client
        .from('generated_documents')
        .select('filled_data, pdf_path, created_at')
        .eq('booking_id', bookingId)
        .order('created_at', ascending: false);
    for (final r in (rows as List)) {
      final fd = r['filled_data'];
      if (fd is! Map) continue;
      final docType = fd['_doc_type'] as String?;
      if (docType == null || !wanted.contains(docType)) continue;
      generatedPath ??= r['pdf_path'] as String?;
      final html = fd['_signed_html'] as String?;
      if (html != null && html.isNotEmpty) {
        signedHtml = html;
        break;
      }
    }
  } catch (e) {
    debugPrint('[BOOKING_DOC] generated_documents fetch failed: $e');
  }

  if (signedHtml != null) {
    if (!context.mounted) return false;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DocWebViewScreen(htmlContent: signedHtml!, title: title),
    ));
    return true;
  }

  // 2) Reálný soubor z bucketu `documents` (smlouva z generate-document = .html,
  //    protokol renderovaný do PDF bez _signed_html apod.).
  String? filePath = generatedPath;
  if (filePath == null || filePath.isEmpty) {
    try {
      final res = await MotoGoSupabase.client
          .from('documents')
          .select('file_path')
          .eq('booking_id', bookingId)
          .eq('type', type)
          .order('created_at', ascending: false)
          .limit(1);
      if ((res as List).isNotEmpty) filePath = res.first['file_path'] as String?;
    } catch (e) {
      debugPrint('[BOOKING_DOC] documents fetch failed: $e');
    }
  }
  return _openStoragePath(context, filePath, title);
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
    return _openStoragePath(context, row['pdf_path'] as String?, title);
  } catch (e) {
    debugPrint('[BOOKING_DOC] generated doc open failed ($generatedDocId): $e');
    return false;
  }
}

/// Soubor z bucketu `documents` přes signed URL — .html ve WebView,
/// .pdf na Androidu externě (WebView tam PDF nevyrenderuje).
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
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
