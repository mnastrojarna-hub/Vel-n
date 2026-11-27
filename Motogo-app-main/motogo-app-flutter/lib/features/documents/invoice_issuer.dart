import 'dart:convert';

import '../../core/operator_info.dart';

/// Vystavitel (dodavatel) KONKRÉTNÍHO dokladu.
///
/// Pořadí je závazné (1:1 s Velínem `lib/company.js` → `resolveIssuer` a edge
/// `_shared/company.ts` → `issuerOf`):
///   1) `invoices.issuer_snapshot` řádku — kopie `company_info` v okamžiku
///      vystavení (doklad vystavený dřív si nese původního provozovatele),
///   2) jinak dnešní provozovatel z [OperatorInfo] (snapshot chybí, sloupec
///      v DB ještě není, nebo má nečitelný tvar).
/// Chybějící klíče se z [OperatorInfo] doplňují JEN témuž subjektu (stejné
/// IČO) — doklad jiného vystavitele nikdy nedostane cizí rejstřík, účet,
/// IBAN ani název banky. Kontakty (telefon, e-mail) se s provozovatelem
/// nemění, proto se doplňují vždy.
class InvoiceIssuer {
  final String name;
  final String ico;
  final String address;
  final String dic;
  final bool vatPayer;

  /// „zapsaná v obchodním rejstříku vedeném …, oddíl C, vložka N"
  final String register;
  final String registerShort;

  /// Soud v 1. pádě + spisová značka („C N") — odvozeno z [register].
  final String registerCourt;
  final String registerFile;
  final String account;
  final String iban;
  final String bank;
  final String bic;
  final String phone;
  final String email;

  const InvoiceIssuer({
    required this.name,
    required this.ico,
    required this.address,
    this.dic = '',
    this.vatPayer = false,
    this.register = '',
    this.registerShort = '',
    this.registerCourt = '',
    this.registerFile = '',
    this.account = '',
    this.iban = '',
    this.bank = '',
    this.bic = '',
    this.phone = OperatorInfo.phone,
    this.email = OperatorInfo.email,
  });

  /// Dnešní provozovatel (doklad bez uloženého vystavitele).
  static final InvoiceIssuer operator = fromSnapshot(OperatorInfo.snapshot)!;

  /// Vystavitel dokladu: snapshot řádku, jinak dnešní provozovatel.
  static InvoiceIssuer resolve(Object? snapshot) => fromSnapshot(snapshot) ?? operator;

  /// `issuer_snapshot` (jsonb — mapa, případně JSON text) → vystavitel.
  /// Bez názvu / nečitelný tvar = null. Nikdy nevyhodí.
  static InvoiceIssuer? fromSnapshot(Object? snapshot) {
    try {
      return _parse(snapshot);
    } catch (_) {
      return null;
    }
  }

  static InvoiceIssuer? _parse(Object? snapshot) {
    var raw = snapshot;
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    if (raw is! Map) return null;
    final s = raw;
    final rawName = s['name'];
    final name = rawName is String ? rawName.trim() : '';
    if (name.isEmpty) return null;
    final ico = _str(s['ico']);
    final same = ico.isNotEmpty && ico == OperatorInfo.ico;
    String pick(String key) {
      final v = _str(s[key]);
      if (v.isNotEmpty || !same) return v;
      return _str(OperatorInfo.snapshot[key]);
    }

    final account = pick('bank_account');
    final sameBank = same &&
        _bankCode(account).isNotEmpty &&
        _bankCode(account) == _bankCode(OperatorInfo.account);
    final register = pick('register');
    final reg = _parseRegister(register);
    final iban = _str(s['bank_iban']).replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final short = _str(s['register_short']);
    return InvoiceIssuer(
      name: name,
      ico: ico,
      address: pick('address'),
      dic: _str(s['dic']),
      vatPayer: s['vat_payer'] == true,
      register: register,
      registerShort: short.isNotEmpty
          ? short
          : (same && register == OperatorInfo.register ? OperatorInfo.registerShort : ''),
      registerCourt: _or(_str(s['register_court']), reg.$1),
      registerFile: _or(_str(s['register_file']), reg.$2),
      account: account,
      iban: iban.isNotEmpty ? iban : czIban(account),
      bank: _or(_str(s['bank_name']), sameBank ? OperatorInfo.bankName : ''),
      bic: _or(_str(s['bank_bic']), sameBank ? OperatorInfo.bic : ''),
      phone: _or(_str(s['phone']), OperatorInfo.phone),
      email: _or(_str(s['email']), OperatorInfo.email),
    );
  }

  /// Má vystavitel zápis v obchodním rejstříku? Ne = doklad dřívějšího
  /// provozovatele → tiskne se v původní podobě (bez „Zápis", bez poznámky
  /// o DPH, bez banky a IBAN).
  bool get hasRegister => registerFile.isNotEmpty || register.isNotEmpty;

  /// Řádek „Zápis": „obchodní rejstřík, Krajský soud v …, oddíl C, vložka N".
  String get registerInvoiceLine {
    final m = RegExp(r'^(\S+)\s+(\S+)$').firstMatch(registerFile);
    if (m != null && registerCourt.isNotEmpty) {
      return 'obchodní rejstřík, $registerCourt, oddíl ${m[1]}, vložka ${m[2]}';
    }
    return register.isNotEmpty ? register : registerShort;
  }

  String get ibanFormatted => OperatorInfo.formatIban(iban);

  /// Český IBAN z čísla účtu „[předčíslí-]číslo/kód banky"; nečitelný vstup = ''.
  static String czIban(String account) {
    final m = RegExp(r'^(?:(\d{1,6})-)?(\d{2,10})/(\d{4})$')
        .firstMatch(account.replaceAll(RegExp(r'\s+'), ''));
    if (m == null) return '';
    final bban = m[3]! + (m[1] ?? '').padLeft(6, '0') + m[2]!.padLeft(10, '0');
    var rem = 0;
    for (final d in '${bban}123500'.codeUnits) {
      rem = (rem * 10 + (d - 0x30)) % 97; // „CZ00" = 123500
    }
    return 'CZ${(98 - rem).toString().padLeft(2, '0')}$bban';
  }

  static String _or(String a, String b) => a.isNotEmpty ? a : b;

  static String _str(Object? v) {
    if (v is String) return v.trim();
    if (v is int) return '$v';
    if (v is double && v.isFinite) return v == v.truncateToDouble() ? '${v.toInt()}' : '$v';
    return '';
  }

  static String _bankCode(String account) =>
      RegExp(r'/(\d{4})\s*$').firstMatch(account)?[1] ?? '';

  /// „…vedeném Krajským soudem v X, oddíl C, vložka N" → (soud v 1. pádě, „C N").
  static (String, String) _parseRegister(String register) {
    final m = RegExp(r'(Krajsk|Městsk)\S*\s+soud\S*\s+(.+?),\s*oddíl\s+(\S+?),\s*vložka\s+(\d+)',
            caseSensitive: false, unicode: true)
        .firstMatch(register);
    if (m == null) return ('', '');
    final kind = m[1]!.toLowerCase().startsWith('k') ? 'Krajský' : 'Městský';
    return ('$kind soud ${m[2]!.trim()}', '${m[3]} ${m[4]}');
  }
}
