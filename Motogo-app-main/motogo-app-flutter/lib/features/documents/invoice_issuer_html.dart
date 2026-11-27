import '../../core/operator_info.dart';
import 'invoice_issuer.dart';

/// Části dokladu, které závisí na vystaviteli (blok DODAVATEL, platební údaje,
/// patička) — vzhled 1:1 s `InvoiceHtmlBuilder`, obsah z [InvoiceIssuer].
///
/// Vystavitel se zápisem v obchodním rejstříku: „Sídlo", řádek „Zápis",
/// poznámka o DPH, banka a IBAN (stejně jako edge `generate-invoice` a Velín).
/// Vystavitel bez zápisu (doklad dřívějšího provozovatele) = původní podoba
/// dokladu, jak ji appka tiskla při vystavení.
extension InvoiceIssuerHtml on InvoiceIssuer {
  static const _label = 'color:#16a34a;padding-right:18px;vertical-align:top';
  static const _value = 'color:#0f1a14;font-weight:700';

  /// Řádky tabulky DODAVATEL.
  String get supplierRowsHtml {
    String row(String label, String value) =>
        '<tr><td style="$_label">$label</td><td style="$_value">${_esc(value)}</td></tr>';
    return [
      row('Název', name),
      row(hasRegister ? 'Sídlo' : 'Adresa', address),
      row('IČO', ico),
      if (hasRegister) row('Zápis', registerInvoiceLine),
      if (vatPayer && dic.isNotEmpty) row('DIČ', dic),
      if (hasRegister && !vatPayer)
        '<tr><td colspan="2" style="$_value">${_esc(OperatorInfo.vatNote)}</td></tr>',
      row('E-mail', email),
      row('Telefon', phone),
    ].join('\n            ');
  }

  /// Řádky platebních údajů: účet (+ banka a IBAN u vystavitele se zápisem).
  String get bankRowsHtml {
    String row(String label, String value) => '''
    <div style="display:flex;justify-content:space-between;font-size:13px;padding:6px 0">
      <span style="color:#16a34a;font-weight:600">$label</span>
      <span style="color:#0f1a14;font-weight:700">${_esc(value)}</span>
    </div>''';
    return [
      row('Bankovní účet', account),
      if (hasRegister && bank.isNotEmpty) row('Banka', bank),
      if (hasRegister && iban.isNotEmpty) row('IBAN', ibanFormatted),
    ].join('\n');
  }

  /// Obsah tmavé patičky dokladu.
  String get footerHtml {
    const sep = '<span style="color:#9ca3af"> &nbsp;|&nbsp; </span>';
    String green(String v) => '<span style="color:#74FB71">${_esc(v)}</span>';
    return '''
    <strong style="color:#ffffff">${_esc(name)}</strong>
    $sep${_esc(address)}
    ${sep}IČO: ${_esc(ico)}
    $sep${green(phone)}
    $sep${green(email)}
    $sep${green(OperatorInfo.web)}''';
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
