import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/error_feedback.dart';
import 'booking_doc_viewer.dart' show DocWanted;
import 'doc_webview_screen.dart';
import 'document_models.dart';
import 'invoice_html_builder.dart';

/// Pojistka proti dvojímu klepnutí — otevírá se jeden dokument naráz.
bool _docOpening = false;

/// Otevření dokumentu (smlouva, protokol, faktura) s průběhem, který nikdy
/// nezasekne: po 15 s „trvá to déle" + „Zrušit" (pozdní výsledek se zahodí
/// — [op] dostane `wanted` a před `push` ho MUSÍ zkontrolovat), celkový
/// limit 60 s. Chyba = CO ([what]) + PROČ + JAK a „Zkusit znovu"
/// (`showErrorSnack`, nikdy syrový text výjimky).
Future<void> runDocOpen(
  BuildContext context, {
  required String what,
  required String where,
  required Future<void> Function(DocWanted wanted) op,
}) async {
  if (_docOpening || !context.mounted) return;
  _docOpening = true;
  var finished = false;
  final progress = MgProgress.show(context, t(context).tr('eoOpeningDoc'),
      cancelAfter: const Duration(seconds: 15));
  bool wanted() => !finished && !progress.cancelled && context.mounted;
  try {
    await progress.guard(op(wanted)).timeout(const Duration(seconds: 60));
  } on MgCancelled {
    // Zákazník přestal čekat — nic dalšího neukazovat.
  } catch (e) {
    finished = true;
    progress.close();
    if (context.mounted) {
      showErrorSnack(context, what, e,
          where: where,
          onRetry: () => runDocOpen(context, what: what, where: where, op: op));
    }
  } finally {
    finished = true;
    progress.close();
    _docOpening = false;
  }
}

/// Faktura / doklad s odběratelem z profilu. Bez profilu (výpadek spojení)
/// se doklad NEvykreslí bez odběratele — výjimka jde volajícímu, který řekne
/// proč + „Zkusit znovu". Sdílené Fakturami a detailem rezervace.
Future<void> openInvoiceDocument(
  BuildContext context,
  UserInvoice invoice, {
  DocWanted? wanted,
}) async {
  String? name, address, email, phone, company, companyAddress, ico, dic;
  final user = MotoGoSupabase.currentUser;
  if (user != null) {
    final profile = await MotoGoSupabase.client
        .from('profiles')
        .select('full_name, email, phone, street, city, zip, country, ico, dic, company_name, company_address')
        .eq('id', user.id)
        .maybeSingle();
    if (profile != null) {
      name = profile['full_name'] as String?;
      email = profile['email'] as String?;
      phone = profile['phone'] as String?;
      company = profile['company_name'] as String?;
      companyAddress = profile['company_address'] as String?;
      ico = profile['ico'] as String?;
      dic = profile['dic'] as String?;
      final parts = [profile['street'], profile['city'], profile['zip'], profile['country']]
          .where((s) => s != null && (s as String).isNotEmpty)
          .join(', ');
      if (parts.isNotEmpty) address = parts;
    }
  }
  final html = InvoiceHtmlBuilder.build(
    invoice,
    customerName: name,
    customerAddress: address,
    customerEmail: email,
    customerPhone: phone,
    customerCompany: company,
    customerCompanyAddress: companyAddress,
    customerIco: ico,
    customerDic: dic,
  );
  if (!context.mounted || !(wanted?.call() ?? true)) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => DocWebViewScreen(
      htmlContent: html,
      title: invoice.number ?? t(context).tr(invoice.typeKey),
    ),
  ));
}
