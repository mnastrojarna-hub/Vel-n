/// Legal texts — extracted from data/legal-texts.js.
/// VOP, GDPR, privacy policy for MotoGo24.
class LegalTexts {
  LegalTexts._();

  static const companyName = 'Bc. Petra Semorádová';
  static const companyIco = '21874263';
  static const companyAddress = 'Mezná 9, 393 01 Mezná';
  static const companyPhone = '+420 774 256 271';
  static const companyEmail = 'info@motogo24.cz';
  static const companyWeb = 'https://motogo24.cz';
  static const companyBank = '670100-2225851630/6210';

  static const vopTitle = 'Všeobecné obchodní podmínky';
  static const vopSummary = '''
VOP služby MotoGo24 — půjčovna motorek

1. Předmět smlouvy
Pronajímatel (Bc. Petra Semorádová, IČO: 21874263) pronajímá nájemci motorové vozidlo na dobu určitou dle rezervace.

2. Podmínky pronájmu
- Minimální věk: 18 let
- Platný řidičský průkaz odpovídající kategorie
- Složení kauce není vyžadováno
- Pojištění (povinné ručení + havarijní) je zahrnuto v ceně

3. Povinnosti nájemce
- Dodržovat pravidla silničního provozu
- Nepůjčovat motorku třetí osobě
- Vrátit motorku ve stanoveném termínu a stavu
- Nikdy nenechávat klíče v zapalování bez dozoru
- Vždy zamykat řídítka zámkem

4. Odpovědnost za škodu
- Spoluúčast max. 30 000 Kč (při dodržení bezpečnostních podmínek)
- Při nedodržení podmínek (klíče v zapalování, nezamčeno) plná odpovědnost

5. Storno podmínky
- 7+ dní před termínem: 100% vrácení
- 2-7 dní: 50% vrácení
- Méně než 2 dny: bez vrácení

6. Ceny
- Denní sazby dle dne v týdnu (Po-Ne)
- Ceny bez DPH (nejsme plátci DPH)
- Přistavení: 1 000 Kč + 40 Kč/km od provozovny
''';

  static const gdprTitle = 'Zpracování osobních údajů (GDPR)';
  static const gdprSummary = '''
Informace o zpracování osobních údajů dle GDPR

Správce údajů: Bc. Petra Semorádová, IČO: 21874263
Kontakt: info@motogo24.cz, +420 774 256 271

Zpracovávané údaje:
- Jméno, e-mail, telefon, adresa
- Datum narození, číslo ŘP, skupina ŘP
- Číslo dokladu totožnosti (OP/pas)
- GPS poloha (pouze při SOS)
- Platební údaje (zpracovává Stripe)

Účel zpracování:
- Plnění smlouvy (pronájem motorky)
- Ověření identity a oprávnění k řízení
- Komunikace se zákazníkem
- Vystavování faktur a dokladů
- SOS asistence (GPS, fotodokumentace)

Doba uchování: Po dobu trvání smluvního vztahu + 3 roky.
Předání třetím stranám: Stripe (platby), Twilio (SMS/WhatsApp), Resend (email), Mindee (OCR).

Práva subjektu: Přístup, oprava, výmaz, omezení zpracování, přenositelnost, námitka.
''';
}
