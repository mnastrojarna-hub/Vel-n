# MotoGo24 – Plán práce na překladech

## Současný stav

- **Překladový systém:** Vlastní Dart mapy v `lib/core/i18n/` (7 souborů)
- **Podporované jazyky:** cs (výchozí), en, de, es, fr, nl, pl
- **Existující klíče:** ~350+ (base + extended soubory)
- **Hardcoded české texty:** ~200+ stringů ve ~127 souborech
- **Použití:** `t(context).klíč` nebo `t(context).tr('klíč')`

### Soubory překladového systému

| Soubor | Obsah |
|--------|-------|
| `translations.dart` | Merger – kombinuje všechny části |
| `translations_cs_pl.dart` | Čeština + Polština (base) |
| `translations_en_de_nl.dart` | Angličtina + Němčina + Holandština (base) |
| `translations_es_fr.dart` | Španělština + Francouzština (base) |
| `translations_ext_1_cs_pl.dart` | Čeština + Polština (extended) |
| `translations_ext_1_en_de_nl.dart` | EN + DE + NL (extended) |
| `translations_ext_1_es_fr.dart` | ES + FR (extended) |
| `i18n_provider.dart` | Provider, locale management, AppTranslations |

---

## Bloky práce (10 bloků)

### BLOK 1 – Auth modul (~35 stringů)
**Soubory:**
- `lib/features/auth/login_screen.dart` – toast zprávy, validace
- `lib/features/auth/register_screen.dart` – kroky 1-3, labely, validace
- `lib/features/auth/reset_password_screen.dart` – reset hesla
- `lib/features/auth/biometric_service.dart` – biometrické ověření
- `lib/features/auth/auth_provider.dart` – error messages

**Příklady hardcoded textů:**
- 'Přihlášení', 'Vítejte zpět!', 'Vyplňte email a heslo'
- 'Registrace pilota', 'Krok 1 / 3 – Základní údaje'
- 'Jméno', 'Příjmení', 'Telefon', 'Datum narození'
- 'POKRAČOVAT', 'DOKONČIT REGISTRACI'

---

### BLOK 2 – Profile + nastavení (~40 stringů)
**Soubory:**
- `lib/features/profile/profile_screen.dart` – menu položky, osobní údaje
- `lib/features/profile/widgets/consent_sheet.dart` – souhlasy
- `lib/features/profile/widgets/settings_sheets.dart` – nastavení
- Případné další widgety v profile/widgets/

**Příklady:**
- 'Můj účet', 'Osobní údaje', 'Zprávy z Moto Go'
- 'Faktury a vyúčtování', 'Platební metody', 'Nastavení'
- 'Odhlásit se', 'Smazat účet a všechna data'
- 'Jméno a příjmení', 'Telefon', 'Obec / město'

---

### BLOK 3 – Reservations hlavní screeny (~25 stringů)
**Soubory:**
- `lib/features/reservations/reservations_screen.dart` – seznam rezervací
- `lib/features/reservations/reservation_detail_screen.dart` – detail
- `lib/features/reservations/reservation_edit_screen.dart` – editace
- `lib/features/reservations/done_detail_screen.dart` (pokud existuje)

**Příklady:**
- 'Přehled všech rezervací', 'Žádné rezervace'
- 'Zrušit rezervaci?', 'Důvod storna (volitelné)'
- 'Neplatný rozsah dat', 'Obsazeno', 'Změny uloženy'
- 'Storno podmínky: 7+ dní = 100% · 2–7 dní = 50% · <2 dny = 0%'

---

### BLOK 4 – Reservations widgety (~30 stringů)
**Soubory:**
- `lib/features/reservations/widgets/res_detail_tab_content.dart`
- `lib/features/reservations/widgets/reservation_card.dart`
- `lib/features/reservations/widgets/reservation_edit_calendar_section.dart`
- `lib/features/reservations/widgets/reservation_edit_extras_section.dart`
- Případné další widgety

**Příklady:**
- 'Motorka', 'Termín', 'Délka', 'den/dny/dní'
- 'Finanční souhrn', 'Celková cena', 'Přistavení'
- 'TERMÍN', 'VYZVEDNUTÍ', 'VRÁCENÍ', 'Obsazené', 'Volné'
- 'DOPLŇKY', 'Výbava spolujezdce', 'Helma, rukavice, vesta'

---

### BLOK 5 – Protocol + Contracts (~15 stringů)
**Soubory:**
- `lib/features/reservations/protocol_screen.dart`
- `lib/features/reservations/contracts_screen.dart` (pokud existuje)
- `lib/features/documents/contracts_screen.dart`

**Příklady:**
- 'Biometrické ověření...', 'PIN', 'Podpis potvrzen'
- 'Předávací protokol odeslán MotoGo24'
- 'Výbava a vybavení', 'Poznámky ke stavu'
- 'Digitální podpis', 'Podepsáno'

---

### BLOK 6 – Booking form widgety (~20 stringů)
**Soubory:**
- `lib/core/booking_form_header_widget.dart`
- `lib/core/booking_form_price_section.dart`
- `lib/features/booking/booking_validator.dart`
- `lib/features/booking/widgets/address_picker.dart`
- `lib/features/booking/booking_ui_helpers.dart`
- `lib/features/booking/booking_address_widgets.dart`
- Případné další booking widgety

**Příklady:**
- 'Rezervace: ${moto.model}', 'Vyplňte formulář'
- 'Motorka × $dc den/dny/dní' (pluralizace!)
- 'Zjišťuji polohu...', 'GPS není dostupné'
- Validační hlášky pro ŘP a překrývající se rezervace

---

### BLOK 7 – SOS modul (~15 stringů)
**Soubory:**
- `lib/features/sos/sos_detail_screen.dart`
- `lib/features/sos/sos_replacement_screen.dart`
- `lib/features/sos/sos_service_screen.dart`
- `lib/features/sos/sos_theft_screen.dart`
- `lib/features/sos/sos_breakdown_screen.dart`
- `lib/features/sos/sos_immobile_screen.dart`

**Příklady:**
- 'CO BUDE DÁL?'
- SOS kategorie a pokyny
- Tlačítka a stavy

---

### BLOK 8 – Shop + Checkout (~15 stringů)
**Soubory:**
- `lib/features/shop/shop_screen.dart`
- `lib/features/shop/widgets/checkout_*.dart` (více souborů)
- `lib/features/shop/voucher_screen.dart` (pokud existuje)
- `lib/features/shop/cart_screen.dart` (pokud existuje)

**Příklady:**
- 'Oblečení, výbava a dárkové poukazy'
- Checkout flow texty
- Košík a platba

---

### BLOK 9 – Core / Shared (~15 stringů)
**Soubory:**
- `lib/core/app_shell.dart` – bottom nav labels
- `lib/core/router.dart` – route titles
- `lib/core/data/legal_texts.dart` – právní texty
- Toast messages sdílené napříč app
- Další core widgety

**Příklady:**
- 'DOMŮ', 'REZERVOVAT', 'REZERVACE', 'SHOP'
- 'Košík ($cartCount) · ${cartTotal} Kč'
- 'Pojištění (povinné ručení + havarijní) je zahrnuto v ceně'

---

### BLOK 10 – Messages + Documents + Home (~15 stringů)
**Soubory:**
- `lib/features/messages/messages_screen.dart`
- `lib/features/documents/documents_screen.dart`
- `lib/features/documents/document_models.dart`
- `lib/features/home/widgets/home_reservation_card.dart`
- Případné message thread widgety

**Příklady:**
- 'Zprávy', 'Oznámení', 'Konverzace', 'Žádná oznámení'
- 'Moje doklady', 'NASKENOVAT DOKLADY KAMEROU'
- '📄 Smlouva'

---

## Postup pro každý blok

1. **Přidat nové klíče** do příslušného `translations_*.dart` souboru
2. **Přidat překlady** pro všech 7 jazyků (cs, en, de, es, fr, nl, pl)
3. **Přidat getter** do `AppTranslations` v `i18n_provider.dart` (nebo použít `tr()`)
4. **Nahradit hardcoded text** voláním `t(context).tr('klíč')`
5. **Otestovat** že se text správně zobrazuje
6. **Commit** s popisem `feat: [Modul] – externalize i18n strings`

## Priorita bloků

| Priorita | Blok | Důvod |
|----------|------|-------|
| 🔴 Vysoká | 1 (Auth) | První co uživatel vidí |
| 🔴 Vysoká | 9 (Core/shared) | Bottom nav viditelný na každém screenu |
| 🟡 Střední | 2 (Profile) | Často používaný |
| 🟡 Střední | 3+4 (Reservations) | Hlavní funkce app |
| 🟡 Střední | 6 (Booking) | Hlavní flow |
| 🟢 Nižší | 5 (Protocol) | Méně častý use case |
| 🟢 Nižší | 7 (SOS) | Nouzový stav |
| 🟢 Nižší | 8 (Shop) | Doplňková funkce |
| 🟢 Nižší | 10 (Messages+Docs) | Podpůrné funkce |

## Poznámky

- **Pluralizace:** České tvary (den/dny/dní) vyžadují speciální handling
- **Interpolace:** Některé texty obsahují proměnné (${moto.model}, $dc, atd.)
- **Nové translation soubory:** Pokud přesáhnou 5000 tokenů → rozdělit na ext_2
- **Fallback:** Systém padá zpět na češtinu pokud překlad chybí
