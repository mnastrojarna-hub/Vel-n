/// Provozovatel (firma) — JEDINÉ místo v appce s jeho údaji.
///
/// Zdroj pravdy je `app_settings.company_info` (Velín → Státní správa → Firemní
/// údaje); tady jsou tytéž hodnoty pro texty, které appka skládá sama (karta
/// „Fakturační údaje" v SOS, proměnné `{{company_*}}` smluv, doklad bez
/// uloženého vystavitele). Nikde jinde v appce se název, IČO, sídlo, zápis v
/// rejstříku ani účet provozovatele natvrdo nepíše — hlídá to test
/// `test/operator_guard_test.dart`.
///
/// Už VYSTAVENÉ doklady se nepřepisují: každý řádek `invoices` nese vlastního
/// vystavitele v `issuer_snapshot` a doklad se tiskne z něj
/// (`features/documents/invoice_issuer.dart`).
///
/// Kontakty a adresa pobočky se změnou provozovatele nemění; SÍDLO (dle
/// obchodního rejstříku „… 393 01 Mezná") není adresa pobočky
/// („Mezná 9, 393 01 Pelhřimov").
class OperatorInfo {
  OperatorInfo._();

  static const String name = 'MotoGo24 s.r.o.';
  static const String ico = '29909864';

  /// Není plátce DPH → DIČ se netiskne.
  static const String dic = '';
  static const bool vatPayer = false;
  static const String vatNote = 'Nejsme plátci DPH.';

  /// Sídlo dle obchodního rejstříku.
  static const String seat = 'Mezná 9, 393 01 Mezná';

  /// Věta do smluv / VOP.
  static const String register =
      'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876';

  /// Krátký zápis do patiček dokumentů.
  static const String registerShort =
      'C 36876 vedená u Krajského soudu v Českých Budějovicích';

  static const String account = '2303580494/2010';
  static const String bankName = 'Fio banka';
  static const String iban = 'CZ8320100000002303580494';
  static const String bic = 'FIOBCZPPXXX';

  static const String phone = '+420 774 256 271';
  static const String email = 'info@motogo24.cz';
  static const String web = 'www.motogo24.cz';

  /// Řádek karty „Fakturační údaje" (SOS — servis na vlastní pěst).
  static const String icoVatLine = 'IČO: $ico · neplátce DPH';

  /// Tytéž údaje ve tvaru `company_info` / `invoices.issuer_snapshot`
  /// (snake_case klíče backendu).
  static const Map<String, Object> snapshot = {
    'name': name,
    'ico': ico,
    'vat_payer': vatPayer,
    'address': seat,
    'register': register,
    'register_short': registerShort,
    'bank_account': account,
    'bank_iban': iban,
    'bank_name': bankName,
    'bank_bic': bic,
    'phone': phone,
    'email': email,
  };

  /// IBAN po čtveřicích („CZ83 2010 …").
  static String formatIban(String iban) {
    final s = iban.replaceAll(RegExp(r'\s+'), '');
    final out = StringBuffer();
    for (var i = 0; i < s.length; i += 4) {
      if (i > 0) out.write(' ');
      out.write(s.substring(i, i + 4 > s.length ? s.length : i + 4));
    }
    return out.toString();
  }

  /// Proměnné `{{company_*}}` pro šablony smluv / VOP / protokolů — stejné
  /// názvy jako web (`dokumenty-detail.php`) a edge `generate-document`.
  static Map<String, String> docVars() => {
        'company_name': name,
        'company_address': seat,
        'company_ico': ico,
        'company_dic': dic,
        'company_register': register,
        'company_register_short': registerShort,
        'company_phone': phone,
        'company_email': email,
        'company_web': web,
        'company_bank': bankName,
        'company_account': account,
        'company_iban': formatIban(iban),
        'company_bic': bic,
      };
}
