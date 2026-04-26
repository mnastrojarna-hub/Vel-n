import 'document_models.dart';

/// Builds invoice HTML from DB data — unified design (1:1 with
/// supabase/functions/generate-invoice/template.ts and velin/src/lib/invoiceTemplate.js).
class InvoiceHtmlBuilder {
  InvoiceHtmlBuilder._();

  static const _logoUrl = 'https://motogo24.cz/gfx/logo-icon.png';

  // Supplier info (matches COMPANY object from app_settings.company_info)
  static const _company = 'Bc. Petra Semorádová';
  static const _ic = '21874263';
  static const _address = 'Mezná 9, 393 01 Mezná';
  static const _email = 'info@motogo24.cz';
  static const _phone = '+420 774 256 271';
  static const _web = 'www.motogo24.cz';
  static const _bank = 'mBank';
  static const _account = '670100-2225851630/6210';

  static String build(
    UserInvoice inv, {
    String? customerName,
    String? customerAddress,
    String? customerEmail,
    String? customerPhone,
  }) {
    final issueDate = inv.issuedAt ?? inv.createdAt;
    final issueDateStr = _fmtDate(issueDate);
    final dueDateStr = inv.dueDate != null ? _fmtDate(inv.dueDate!) : '—';
    final paidDateStr = issueDateStr; // KF/DP uhrazeno okamžitě (kartová platba)
    final number = inv.number ?? '—';
    final vs = inv.variableSymbol ?? number;
    final bookingRef = (inv.bookingId ?? '').length > 8
        ? inv.bookingId!.substring(inv.bookingId!.length - 8).toUpperCase()
        : (inv.bookingId ?? '').toUpperCase();

    final isProforma = inv.type == 'proforma' || inv.type == 'shop_proforma' || inv.type == 'advance';
    final isPaymentReceipt = inv.type == 'payment_receipt';
    final isCreditNote = inv.isCreditNote;
    final isShopFinal = inv.type == 'shop_final';

    final titleBase = isCreditNote
        ? 'Dobropis'
        : isPaymentReceipt
            ? 'Daňový doklad'
            : isProforma
                ? 'Zálohová faktura'
                : 'Faktura';

    final tcode = isCreditNote
        ? 'DOBROPIS'
        : isPaymentReceipt
            ? 'DAŇOVÝ DOKLAD'
            : isProforma
                ? 'ZF'
                : 'FAKTURA';

    final badgeLabel = isCreditNote
        ? 'VRÁCENO'
        : isProforma
            ? 'K ÚHRADĚ'
            : 'UHRAZENO';
    final badgeBg = isCreditNote
        ? '#fca5a5'
        : isProforma
            ? '#fbbf24'
            : '#74FB71';
    final isPaidLike = !isProforma && !isCreditNote;
    final statusText = isCreditNote ? 'Vráceno' : isProforma ? 'K úhradě' : 'Uhrazena';

    final subtotal = inv.subtotal ?? inv.items.fold<double>(0, (s, it) => s + it.lineTotal);
    final total = inv.total ?? subtotal;

    final itemsHtml = _buildItemsRows(inv.items);
    final paymentBlock = _buildPaymentBlock(statusText, total, inv);
    final docNote = _buildDocNote(isProforma: isProforma, isPaymentReceipt: isPaymentReceipt, isCreditNote: isCreditNote, isShopFinal: isShopFinal);

    return '''<!DOCTYPE html>
<html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_esc(titleBase)} ${_esc(number)}</title>
<style>body{margin:0;padding:0;background:#d9dee2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#0f1a14;-webkit-font-smoothing:antialiased}</style>
</head>
<body>
<div style="max-width:780px;margin:0 auto;background:#ffffff">

  <!-- HEADER -->
  <div style="background:#0a1f15;padding:24px 32px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse">
      <tr>
        <td style="vertical-align:top;width:50%">
          <table role="presentation" cellpadding="0" cellspacing="0"><tr>
            <td style="vertical-align:middle;padding-right:14px"><img src="$_logoUrl" alt="MotoGo24" width="52" height="52" style="display:block;border:0"/></td>
            <td style="vertical-align:middle">
              <div style="color:#74FB71;font-size:20px;font-weight:900;letter-spacing:1px;line-height:1">MOTO GO 24</div>
              <div style="color:#74FB71;font-size:9px;font-weight:700;letter-spacing:2px;margin-top:4px">PŮJČOVNA MOTOREK</div>
            </td>
          </tr></table>
        </td>
        <td style="vertical-align:top;text-align:right">
          <div style="display:inline-block;border-radius:3px;overflow:hidden;font-size:0;margin-bottom:12px">
            <span style="display:inline-block;background:#0f3320;color:#74FB71;font-size:10px;font-weight:800;letter-spacing:1px;padding:5px 9px">$tcode</span><span style="display:inline-block;background:$badgeBg;color:#0a1f15;font-size:10px;font-weight:800;letter-spacing:1px;padding:5px 9px">$badgeLabel</span>
          </div>
          <div style="color:#ffffff;font-size:20px;font-weight:600;line-height:1.2">${_esc(titleBase)} č. ${_esc(number)}</div>
          ${bookingRef.isNotEmpty ? '<div style="color:#9ca3af;font-size:12px;margin-top:4px">Rezervace č. $bookingRef</div>' : ''}
        </td>
      </tr>
    </table>
  </div>

  <!-- DODAVATEL / ODBĚRATEL -->
  <div style="padding:24px 32px 8px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:separate;border-spacing:24px 0">
      <tr>
        <td style="vertical-align:top;width:50%">
          <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">DODAVATEL</div>
          <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:12px;line-height:1.7">
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Název</td><td style="color:#0f1a14;font-weight:700">$_company</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Adresa</td><td style="color:#0f1a14;font-weight:700">$_address</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">IČO</td><td style="color:#0f1a14;font-weight:700">$_ic</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">E-mail</td><td style="color:#0f1a14;font-weight:700">$_email</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Telefon</td><td style="color:#0f1a14;font-weight:700">$_phone</td></tr>
          </table>
        </td>
        <td style="vertical-align:top;width:50%">
          <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">ODBĚRATEL</div>
          <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:12px;line-height:1.7">
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Jméno</td><td style="color:#0f1a14;font-weight:700">${_esc(customerName ?? '—')}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Adresa</td><td style="color:#0f1a14;font-weight:700">${_esc((customerAddress ?? '').isEmpty ? '—' : customerAddress!)}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">E-mail</td><td style="color:#0f1a14;font-weight:700">${_esc((customerEmail ?? '').isEmpty ? '—' : customerEmail!)}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Telefon</td><td style="color:#0f1a14;font-weight:700">${_esc((customerPhone ?? '').isEmpty ? '—' : customerPhone!)}</td></tr>
          </table>
        </td>
      </tr>
    </table>
  </div>

  <!-- FAKTURAČNÍ ÚDAJE / PLATBA -->
  <div style="padding:16px 32px 8px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:separate;border-spacing:24px 0">
      <tr>
        <td style="vertical-align:top;width:50%">
          <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">FAKTURAČNÍ ÚDAJE</div>
          <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:12px;line-height:1.7">
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Číslo faktury</td><td style="color:#0f1a14;font-weight:700">${_esc(number)}</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Variabilní symbol</td><td style="color:#0f1a14;font-weight:700">${_esc(vs)}</td></tr>
            ${bookingRef.isNotEmpty ? '<tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Číslo rezervace</td><td style="color:#0f1a14;font-weight:700">$bookingRef</td></tr>' : ''}
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Datum vystavení</td><td style="color:#0f1a14;font-weight:700">$issueDateStr</td></tr>
            <tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Datum splatnosti</td><td style="color:#0f1a14;font-weight:700">$dueDateStr</td></tr>
            ${isPaidLike ? '<tr><td style="color:#16a34a;padding-right:18px;vertical-align:top">Datum úhrady</td><td style="color:#0f1a14;font-weight:700">$paidDateStr</td></tr>' : ''}
          </table>
        </td>
        <td style="vertical-align:top;width:50%">
          <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">PLATBA</div>
          $paymentBlock
        </td>
      </tr>
    </table>
  </div>

  <!-- POLOŽKY -->
  <div style="padding:16px 32px 0">
    <div style="font-size:11px;font-weight:800;color:#16a34a;letter-spacing:1.5px;margin-bottom:10px">POLOŽKY</div>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;border:1px solid #e5e7eb">
      <thead>
        <tr style="background:#0a1f15">
          <th style="padding:12px 16px;color:#ffffff;font-size:11px;font-weight:700;text-align:left;letter-spacing:.5px">Položka</th>
          <th style="padding:12px 16px;color:#ffffff;font-size:11px;font-weight:700;text-align:left;letter-spacing:.5px">Popis</th>
          <th style="padding:12px 16px;color:#ffffff;font-size:11px;font-weight:700;text-align:right;letter-spacing:.5px">Ks</th>
          <th style="padding:12px 16px;color:#ffffff;font-size:11px;font-weight:700;text-align:right;letter-spacing:.5px">Cena</th>
        </tr>
      </thead>
      <tbody>$itemsHtml</tbody>
    </table>
  </div>

  <!-- SOUHRN -->
  <div style="padding:16px 32px 24px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr>
        <td style="width:55%">&nbsp;</td>
        <td style="width:45%">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;border:1px solid #e5e7eb">
            <tr style="background:#f3f4f6">
              <td style="padding:12px 16px;font-size:13px;color:#0f1a14;border-bottom:1px solid #e5e7eb">Mezisoučet</td>
              <td style="padding:12px 16px;font-size:13px;color:#0f1a14;text-align:right;border-bottom:1px solid #e5e7eb;font-variant-numeric:tabular-nums">${_fmtAmount(subtotal)}</td>
            </tr>
            <tr style="background:#f3f4f6">
              <td style="padding:12px 16px;font-size:13px;color:#0f1a14">DPH</td>
              <td style="padding:12px 16px;font-size:13px;color:#0f1a14;text-align:right;font-variant-numeric:tabular-nums">0 Kč</td>
            </tr>
            <tr style="background:#dcfce7">
              <td style="padding:14px 16px;font-size:15px;color:#0f1a14;font-weight:800;border-top:1px solid #86efac">Celkem</td>
              <td style="padding:14px 16px;font-size:15px;color:#0f1a14;font-weight:800;text-align:right;border-top:1px solid #86efac;font-variant-numeric:tabular-nums">${_fmtAmount(total.abs())}</td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </div>

  $docNote

  <!-- FOOTER -->
  <div style="background:#0a1f15;padding:14px 32px;color:#ffffff;font-size:11px;line-height:1.6">
    <strong style="color:#ffffff">$_company</strong>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>$_address
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span>IČO: $_ic
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">$_phone</span>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">$_email</span>
    <span style="color:#9ca3af"> &nbsp;|&nbsp; </span><span style="color:#74FB71">$_web</span>
  </div>

</div>
</body></html>''';
  }

  static String _buildItemsRows(List<InvoiceItem> items) {
    if (items.isEmpty) return '';
    final rows = StringBuffer();
    for (final it in items) {
      if (it.isSectionHeader) {
        final label = _esc(it.description.replaceAll('──', '').trim());
        rows.write('<tr><td colspan="4" style="padding:14px 16px 6px;font-weight:700;font-size:11px;color:#16a34a;text-transform:uppercase;letter-spacing:.5px">$label</td></tr>');
      } else {
        final split = _splitItem(it.description);
        final neg = it.isNegative ? 'color:#b91c1c;' : 'color:#0f1a14;';
        rows.write('<tr>'
            '<td style="padding:14px 16px;border-top:1px solid #e5e7eb;font-size:13px;font-weight:700;color:#0f1a14;vertical-align:top;width:30%">${split[0]}</td>'
            '<td style="padding:14px 16px;border-top:1px solid #e5e7eb;font-size:12px;color:#6b7280;vertical-align:top">${split[1]}</td>'
            '<td style="padding:14px 16px;border-top:1px solid #e5e7eb;font-size:13px;color:#0f1a14;text-align:right;vertical-align:top;white-space:nowrap;width:60px">${it.qty}</td>'
            '<td style="padding:14px 16px;border-top:1px solid #e5e7eb;font-size:13px;text-align:right;vertical-align:top;white-space:nowrap;width:110px;font-variant-numeric:tabular-nums;$neg">${_fmtAmount(it.lineTotal)}</td>'
            '</tr>');
      }
    }
    return rows.toString();
  }

  static String _buildPaymentBlock(String statusText, double total, UserInvoice inv) {
    // Mobile app: bookings are paid via Stripe — show "Uhrazeno online" + total.
    return '''
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">Stav</span>
      <span style="color:#0f1a14;font-weight:700">$statusText</span>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">Uhrazeno online</span>
      <span style="color:#0f1a14;font-weight:700;font-variant-numeric:tabular-nums">${_fmtAmount(total)}</span>
    </div>
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">Bankovní účet</span>
      <span style="color:#0f1a14;font-weight:700">$_account</span>
    </div>
    ''';
  }

  static String _buildDocNote({
    required bool isProforma,
    required bool isPaymentReceipt,
    required bool isCreditNote,
    required bool isShopFinal,
  }) {
    if (isProforma) {
      return '<div style="margin:0 32px 16px;padding:10px 14px;background:#fef3c7;border-left:3px solid #f59e0b;font-size:11px;color:#78350f">Tento doklad není daňovým dokladem. Po přijetí platby Vám bude vystavena konečná faktura.</div>';
    }
    if (isPaymentReceipt) {
      return '<div style="margin:0 32px 16px;padding:10px 14px;background:#ecfdf5;border-left:3px solid #16a34a;font-size:11px;color:#065f46">Tento doklad potvrzuje přijetí platby dle zákona č. 235/2004 Sb., o dani z přidané hodnoty.</div>';
    }
    if (isCreditNote) {
      return '<div style="margin:0 32px 16px;padding:10px 14px;background:#fef2f2;border-left:3px solid #dc2626;font-size:11px;color:#991b1b"><strong>DOBROPIS</strong> — Tento doklad je opravným daňovým dokladem. Částka byla vrácena na platební kartu zákazníka prostřednictvím Stripe.</div>';
    }
    if (isShopFinal) {
      return '<div style="margin:0 32px 16px;padding:10px 14px;background:#ecfdf5;border-left:3px solid #16a34a;font-size:11px;color:#065f46">Konečná faktura — platba byla již provedena. K úhradě: 0 Kč.</div>';
    }
    return '';
  }

  static List<String> _splitItem(String desc) {
    if (desc.isEmpty) return ['—', ''];
    final idx = desc.indexOf(' — ');
    if (idx > 0) return [_esc(desc.substring(0, idx).trim()), _esc(desc.substring(idx + 3).trim())];
    return [_esc(desc.trim()), ''];
  }

  static String _fmtDate(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

  static String _fmtAmount(double v) {
    final n = v.round();
    final neg = n < 0;
    final abs = n.abs().toString();
    final sb = StringBuffer();
    for (int i = 0; i < abs.length; i++) {
      if (i > 0 && (abs.length - i) % 3 == 0) sb.write(' ');
      sb.write(abs[i]);
    }
    return '${neg ? '−' : ''}${sb.toString()} Kč';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
