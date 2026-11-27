// Změna provozovatele (2026-11): kdo je na dokladu dodavatel.
// Pravidlo majitele: nové doklady = MotoGo24 s.r.o.; už VYSTAVENÉ doklady
// drží původního vystavitele (invoices.issuer_snapshot).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/operator_info.dart';
import 'package:motogo_app/features/documents/document_models.dart';
import 'package:motogo_app/features/documents/invoice_issuer.dart';

import 'operator_fixtures.dart';

void main() {
  group('OperatorInfo — dnešní provozovatel', () {
    test('údaje dle obchodního rejstříku a zadání majitele', () {
      expect(OperatorInfo.name, 'MotoGo24 s.r.o.');
      expect(OperatorInfo.ico, '29909864');
      expect(OperatorInfo.seat, 'Mezná 9, 393 01 Mezná');
      expect(OperatorInfo.register,
          'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876');
      expect(OperatorInfo.registerShort, 'C 36876 vedená u Krajského soudu v Českých Budějovicích');
      expect(OperatorInfo.vatPayer, isFalse);
      expect(OperatorInfo.dic, isEmpty);
      expect(OperatorInfo.vatNote, 'Nejsme plátci DPH.');
      expect(OperatorInfo.account, '2303580494/2010');
      expect(OperatorInfo.bankName, 'Fio banka');
      expect(OperatorInfo.iban, 'CZ8320100000002303580494');
      expect(OperatorInfo.bic, 'FIOBCZPPXXX');
      expect(OperatorInfo.phone, '+420 774 256 271');
      expect(OperatorInfo.email, 'info@motogo24.cz');
      expect(OperatorInfo.icoVatLine, 'IČO: 29909864 · neplátce DPH');
    });

    test('IBAN odpovídá číslu účtu (mod 97) a tiskne se po čtveřicích', () {
      expect(InvoiceIssuer.czIban(OperatorInfo.account), OperatorInfo.iban);
      expect(OperatorInfo.formatIban(OperatorInfo.iban), 'CZ83 2010 0000 0023 0358 0494');
      expect(InvoiceIssuer.czIban('19-2000145399/0800'), 'CZ6508000000192000145399');
      expect(InvoiceIssuer.czIban('nesmysl'), '');
    });

    test('proměnné {{company_*}} — stejné názvy jako web a edge', () {
      expect(OperatorInfo.docVars(), {
        'company_name': 'MotoGo24 s.r.o.',
        'company_address': 'Mezná 9, 393 01 Mezná',
        'company_ico': '29909864',
        'company_dic': '',
        'company_register':
            'zapsaná v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876',
        'company_register_short': 'C 36876 vedená u Krajského soudu v Českých Budějovicích',
        'company_phone': '+420 774 256 271',
        'company_email': 'info@motogo24.cz',
        'company_web': 'www.motogo24.cz',
        'company_bank': 'Fio banka',
        'company_account': '2303580494/2010',
        'company_iban': 'CZ83 2010 0000 0023 0358 0494',
        'company_bic': 'FIOBCZPPXXX',
      });
    });
  });

  group('vystavitel dokladu', () {
    test('snapshot dřívějšího provozovatele → původní údaje, nic nového se nedoplní', () {
      final i = InvoiceIssuer.resolve(oldIssuerSnapshot);
      expect(i.name, 'Bc. Petra Semorádová');
      expect(i.ico, '21874263');
      expect(i.address, 'Mezná 9, 393 01 Pelhřimov');
      expect(i.account, '670100-2225851630/6210');
      expect(i.bank, 'mBank');
      expect(i.vatPayer, isFalse);
      // nikdy cizí rejstřík, banka ani BIC
      expect(i.hasRegister, isFalse);
      expect(i.register, isEmpty);
      expect(i.registerShort, isEmpty);
      expect(i.registerCourt, isEmpty);
      expect(i.registerFile, isEmpty);
      expect(i.registerInvoiceLine, isEmpty);
      expect(i.bic, isEmpty);
      expect(i.iban, isNot(OperatorInfo.iban));
      expect(i.iban, InvoiceIssuer.czIban('670100-2225851630/6210'));
    });

    test('starý snapshot bez názvu banky a kontaktů: banka prázdná, kontakty beze změny', () {
      final snap = Map<String, dynamic>.of(oldIssuerSnapshot)
        ..remove('bank_name')
        ..remove('phone')
        ..remove('email')
        ..remove('address');
      final i = InvoiceIssuer.resolve(snap);
      expect(i.name, 'Bc. Petra Semorádová');
      expect(i.bank, isEmpty);
      expect(i.address, isEmpty, reason: 'sídlo nové společnosti se cizímu subjektu nedoplňuje');
      expect(i.phone, OperatorInfo.phone);
      expect(i.email, OperatorInfo.email);
      expect(i.hasRegister, isFalse);
    });

    test('cizí subjekt s účtem u stejné banky nedostane název banky z operator_info', () {
      final i = InvoiceIssuer.resolve({'name': 'Jan Novák', 'ico': '12345678', 'bank_account': '123456789/2010'});
      expect(i.bank, isEmpty);
      expect(i.bic, isEmpty);
      expect(i.hasRegister, isFalse);
    });

    test('bez snapshotu (null / sloupec v DB ještě není) → dnešní provozovatel', () {
      for (final row in [invoiceRow(issuer: null), invoiceRow(withIssuerKey: false)]) {
        final i = UserInvoice.fromJson(row).issuer;
        expect(i.name, OperatorInfo.name);
        expect(i.ico, OperatorInfo.ico);
        expect(i.address, OperatorInfo.seat);
        expect(i.account, OperatorInfo.account);
        expect(i.bank, OperatorInfo.bankName);
        expect(i.iban, OperatorInfo.iban);
        expect(i.bic, OperatorInfo.bic);
        expect(i.hasRegister, isTrue);
        expect(i.registerCourt, 'Krajský soud v Českých Budějovicích');
        expect(i.registerFile, 'C 36876');
        expect(i.registerInvoiceLine,
            'obchodní rejstřík, Krajský soud v Českých Budějovicích, oddíl C, vložka 36876');
      }
    });

    test('snapshot nového provozovatele (vše vyplněno) → údaje ze snapshotu', () {
      final i = UserInvoice.fromJson(invoiceRow(issuer: newIssuerSnapshot)).issuer;
      expect(i.name, 'MotoGo24 s.r.o.');
      expect(i.address, 'Mezná 9, 393 01 Mezná');
      expect(i.registerShort, OperatorInfo.registerShort);
      expect(i.ibanFormatted, 'CZ83 2010 0000 0023 0358 0494');
      expect(i.bank, 'Fio banka');
    });

    test('snapshot s novým IČO a chybějícími klíči → doplní se z operator_info', () {
      final i = InvoiceIssuer.resolve({'name': 'MotoGo24 s.r.o.', 'ico': '29909864'});
      expect(i.address, OperatorInfo.seat);
      expect(i.register, OperatorInfo.register);
      expect(i.registerShort, OperatorInfo.registerShort);
      expect(i.registerFile, 'C 36876');
      expect(i.account, OperatorInfo.account);
      expect(i.iban, OperatorInfo.iban);
      expect(i.bank, OperatorInfo.bankName);
      expect(i.bic, OperatorInfo.bic);
      expect(i.hasRegister, isTrue);
    });

    test('nový provozovatel s JINÝM účtem: banka ani BIC se nehádají', () {
      final i = InvoiceIssuer.resolve({'name': 'MotoGo24 s.r.o.', 'ico': 29909864, 'bank_account': '123456789/0100'});
      expect(i.ico, '29909864', reason: 'IČO jako číslo se čte stejně');
      expect(i.account, '123456789/0100');
      expect(i.bank, isEmpty);
      expect(i.bic, isEmpty);
      expect(i.iban, InvoiceIssuer.czIban('123456789/0100'));
      expect(i.register, OperatorInfo.register);
    });

    test('snapshot jako JSON text (dvojité zakódování) se přečte', () {
      expect(InvoiceIssuer.resolve(jsonEncode(oldIssuerSnapshot)).ico, '21874263');
      expect(InvoiceIssuer.resolve(jsonEncode(newIssuerSnapshot)).ico, '29909864');
    });

    test('nečitelný snapshot → dnešní provozovatel, nikdy výjimka', () {
      final junk = <Object?>[
        '',
        'není json',
        '[1,2]',
        '"text"',
        42,
        3.14,
        true,
        const [1, 2, 3],
        const <String, dynamic>{},
        const {'ico': '21874263'}, // bez názvu
        const {'name': '   '},
        const {'name': 123.5},
        const {'name': ['a']},
        const {1: 'x', 2: 'y'},
        const {
          'name': {'nested': true},
          'ico': [1],
        },
        Object(),
      ];
      for (final j in junk) {
        final i = InvoiceIssuer.resolve(j);
        expect(i.name, OperatorInfo.name, reason: '$j');
        expect(i.ico, OperatorInfo.ico, reason: '$j');
      }
      // podivné hodnoty u jinak platného snapshotu nesmí shodit ani přepsat vystavitele
      final odd = InvoiceIssuer.resolve({
        'name': 'Bc. Petra Semorádová',
        'ico': 21874263,
        'address': null,
        'vat_payer': 'ano',
        'bank_account': {'x': 1},
        'register': ['x'],
        'phone': ['x'],
      });
      expect(odd.name, 'Bc. Petra Semorádová');
      expect(odd.ico, '21874263');
      expect(odd.vatPayer, isFalse);
      expect(odd.account, isEmpty);
      expect(odd.hasRegister, isFalse);
      expect(odd.phone, OperatorInfo.phone);
    });

    test('fromJson: řádek s nečekaným tvarem issuer_snapshot nespadne', () {
      for (final v in <Object?>['x', 5, const [], const {'a': 1}]) {
        final inv = UserInvoice.fromJson(invoiceRow(issuer: v));
        expect(inv.issuer.name, OperatorInfo.name);
      }
    });
  });
}
