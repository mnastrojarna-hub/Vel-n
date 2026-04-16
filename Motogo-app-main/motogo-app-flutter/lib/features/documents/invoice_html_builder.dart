import 'document_models.dart';

/// Builds invoice HTML from DB data — same template as the original
/// Capacitor app (documents-booking-2.js showInvoice overlay).
class InvoiceHtmlBuilder {
  InvoiceHtmlBuilder._();

  // Supplier info (matches COMPANY object from original app)
  static const _company = 'Bc. Petra Semorádová';
  static const _ic = '21874263';
  static const _address = 'Mezná 9, 393 01 Mezná';
  static const _bank = '670100-2225851630/6210';
  static const _note = 'Nejsme plátci DPH dle §6 zákona č. 235/2004 Sb.';

  static String build(UserInvoice inv, {String? customerName, String? customerAddress}) {
    final issueDate = inv.issuedAt ?? inv.createdAt;
    final issueDateStr = _fmtDate(issueDate);
    final dueDateStr = inv.dueDate != null ? _fmtDate(inv.dueDate!) : '—';
    final number = inv.number ?? '';
    final vs = inv.variableSymbol ?? number;

    final statusHtml = inv.isPaid
        ? '<div style="color:#1a8a18;font-weight:800;font-size:12px;margin:6px 0;">✓ ZAPLACENO</div>'
        : (inv.status == 'issued'
            ? '<div style="color:#b45309;font-weight:800;font-size:12px;margin:6px 0;">⏳ VYSTAVENO</div>'
            : '');

    final itemsHtml = _buildItemsTable(inv.items);
    final taxHtml = (inv.taxAmount != null && inv.taxAmount! > 0)
        ? '''<div style="background:#f1faf7;border-radius:12px;padding:10px;margin:10px 0;">
            <div style="font-size:12px;padding:3px 0;"><span style="font-weight:700;color:#0f1a14;">Základ:</span> ${_fmtAmount(inv.subtotal ?? 0)}</div>
            <div style="font-size:12px;padding:3px 0;"><span style="font-weight:700;color:#0f1a14;">DPH 21%:</span> ${_fmtAmount(inv.taxAmount!)}</div>
          </div>'''
        : '';

    return '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#fff;color:#4a6357;font-size:12px;line-height:1.7;padding:16px 20px 40px}
.inv-header{font-size:16px;font-weight:900;color:#0f1a14;margin-bottom:12px}
.parties{display:flex;gap:12px;margin:12px 0}
.party{flex:1;background:#f1faf7;border-radius:12px;padding:10px;font-size:11px;line-height:1.6}
.party strong{color:#0f1a14}
.meta{background:#f1faf7;border-radius:12px;padding:10px;margin:10px 0}
.field{font-size:12px;padding:3px 0}
.lbl{font-weight:700;color:#0f1a14}
table{width:100%;border-collapse:collapse;margin:12px 0;font-size:11px}
th{background:#1a2e22;color:#fff;padding:8px;text-align:left;font-weight:700}
td{padding:8px;border-bottom:1px solid #d4e8e0}
.section-hdr{font-weight:800;font-size:12px;padding:10px 0 4px;border-bottom:2px solid #1a8a18;color:#0f1a14}
.neg{color:#b91c1c}
.total{text-align:right;font-size:15px;padding:10px 0;border-top:2px solid #1a2e22;font-weight:900;color:#0f1a14}
.note{font-size:10px;color:#8aab99;margin-top:8px}
</style></head><body>

<div class="inv-header"><strong>${inv.typeLabel}</strong> $number</div>
$statusHtml

<div class="parties">
  <div class="party"><strong>Prodávající:</strong><br>$_company<br>$_address<br>IČ: $_ic</div>
  <div class="party"><strong>Kupující:</strong><br>${customerName ?? '—'}<br>${customerAddress ?? ''}</div>
</div>

<div class="meta">
  <div class="field"><span class="lbl">Datum vystavení:</span> $issueDateStr</div>
  <div class="field"><span class="lbl">Splatnost:</span> $dueDateStr</div>
  <div class="field"><span class="lbl">VS:</span> $vs</div>
  <div class="field"><span class="lbl">Způsob platby:</span> Kartou</div>
  <div class="field"><span class="lbl">Bankovní účet:</span> $_bank</div>
</div>

$itemsHtml
$taxHtml

<div class="total">Celkem k úhradě: ${_fmtAmount(inv.total ?? 0)}</div>
<p class="note">$_note</p>

</body></html>''';
  }

  static String _buildItemsTable(List<InvoiceItem> items) {
    if (items.isEmpty) return '';
    final rows = StringBuffer();
    for (final it in items) {
      if (it.isSectionHeader) {
        rows.write('<tr><td colspan="4" class="section-hdr">${_esc(it.description.replaceAll('──', '').trim())}</td></tr>');
      } else {
        final neg = it.isNegative ? ' class="neg"' : '';
        final qtyLabel = it.qty > 1 ? '${it.qty} dní' : '${it.qty} ks';
        rows.write('<tr><td>${_esc(it.description)}</td><td>$qtyLabel</td>'
            '<td$neg>${_fmtAmount(it.unitPrice)}</td>'
            '<td$neg>${_fmtAmount(it.lineTotal)}</td></tr>');
      }
    }
    return '''<table><thead><tr><th>Položka</th><th>Počet</th><th>Jednotková cena</th><th>Celkem</th></tr></thead>
<tbody>$rows</tbody></table>''';
  }

  static String _fmtDate(DateTime d) => '${d.day}.${d.month}.${d.year}';

  static String _fmtAmount(double v) => '${v.toStringAsFixed(0)} Kč';

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
