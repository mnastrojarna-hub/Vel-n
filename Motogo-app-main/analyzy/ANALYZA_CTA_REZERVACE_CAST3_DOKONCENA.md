# ANALÝZA CTA - DOKONČENÁ REZERVACE

> Stav: dokoncene = motorka vrácena, konec proběhl. `status = completed` NEBO `end_date < today` NEBO `ended_by_sos = true`.
> Supabase status: `completed` + `payment_status = paid`
> Automatické dokončení: cron `auto_complete_expired_bookings()` denně v 00:01 UTC změní `active/reserved → completed` když `end_date < today` a `payment_status = paid`.
> Trigger: `trg_generate_final_invoice` automaticky vygeneruje konečnou fakturu při přechodu na completed.

---

## PŘEHLED VŠECH CTA V DETAILU DOKONČENÉ REZERVACE

Na obrazovce detailu dokončené rezervace se zobrazují:

**Speciální sekce**: HODNOCENÍ (hvězdičky)

**Sekce "Dokumenty"** (nadpis: malý šedý text):
| # | CTA | Typ tlačítka | Barva | Ikona | Akce |
|---|-----|-------------|-------|-------|------|
| 1 | **Konečná faktura** | outlined (bílé) | white + green border | 💰 | Otevře fakturu v WebView |
| 2 | **Nájemní smlouva** | outlined (bílé) | white + green border | 📄 | Navigace na `/contracts` |

**Sekce "Hodnocení"** (nadpis: malý šedý text):
| # | CTA | Typ tlačítka | Barva | Ikona | Akce |
|---|-----|-------------|-------|-------|------|
| 3 | **Ohodnotit na Google** | primary (zelené) | `#74FB71` | ⭐ | Otevře Google Review URL |
| 4 | **Rezervovat znovu** | primary (zelené) | `#74FB71` | 🔁 | Navigace na detail motorky |

---

## SPECIÁLNÍ SEKCE: HODNOCENÍ (⭐)

### Co to je
Interaktivní karta s **5 hvězdičkami** pro ohodnocení proběhlé jízdy.

### Co uživatel vidí:
- Karta s nadpisem "⭐ Hodnocení"
- **5 hvězdiček** (hvězdy v řadě, centrované)
  - Neohodnoceno: všechny šedé (`#D1D5DB`)
  - Po kliknutí: vybrané hvězdy zlaté (`#F59E0B`) s animací zvětšení (scale 1.25x, 200ms, easeOutBack)
- Pod hvězdičkami:
  - Pokud nehodnoceno: "Klepněte pro hodnocení" (šedý text)
  - Pokud hodnoceno: "X z 5 hvězd" (zelený text)

### Flow hodnocení:
1. Uživatel klikne na hvězdu (1–5)
2. Hvězdy se **animují** (scale up na 1.25x s easeOutBack curve)
3. **Okamžitě** se volá `rateBooking(bookingId, star)`:
   ```sql
   UPDATE bookings 
   SET rating = {star}, rated_at = now()
   WHERE id = '{bookingId}'
   ```
4. Po úspěchu: toast "⭐ Díky! X z 5 hvězd"
5. Po chybě: toast "⚠️ Chyba – Hodnocení se nepodařilo uložit"
6. Uživatel může **změnit hodnocení** opakovaným kliknutím (přepíše se)

### Supabase:
- Pole `bookings.rating` (int 1–5)
- Pole `bookings.rated_at` (timestamptz)
- Žádná separátní tabulka - rating je přímo na bookingu

---

## CTA 1: KONEČNÁ FAKTURA (💰)

### Co to dělá
Načte a zobrazí **konečnou fakturu** (final invoice) pro dokončenou rezervaci v in-app WebView.

### Flow krok za krokem:
1. Uživatel klikne "Konečná faktura"
2. **Dotaz do Supabase**:
   ```sql
   SELECT * FROM invoices
   WHERE booking_id = '{bookingId}'
     AND type IN ('final', 'issued')
   ORDER BY created_at DESC
   LIMIT 1
   ```
3. **Pokud faktura neexistuje**:
   - Toast: "📄 Faktura – Faktura zatím není k dispozici"
   - (Může se stát pokud systém ještě nevygeneroval - trigger delay)
4. **Pokud faktura existuje**:
   - Načte **profil zákazníka** pro adresu:
     ```sql
     SELECT full_name, street, city, zip, country 
     FROM profiles WHERE id = '{user_id}'
     ```
   - Sestaví HTML faktury pomocí `InvoiceHtmlBuilder.build()`
   - Otevře `DocWebViewScreen` s HTML obsahem
   - Titulek = číslo faktury (např. "FV-2026-0042") nebo typ

### Jak vypadá konečná faktura:
- **Číslo faktury**: FV-YYYY-NNNN (konečná faktura)
- **Dodavatel**: MotoGo24 s.r.o.
- **Odběratel**: jméno + adresa z profilu
- **Položky**: 
  - Pronájem motorky (X dní × Y Kč/den)
  - Doručení (pokud bylo)
  - Doplňky (pokud byly)
  - Sleva (pokud byla)
- **Celkem**: total_price Kč
- **Zaplaceno**: zálohou (advance invoice)

### Jak se konečná faktura generuje (backend):
1. Trigger `trg_generate_final_invoice` na tabulce `bookings`
2. Spouští se při UPDATE kdy `status` se změní na `completed`
3. Funkce `generate_final_invoice_on_complete()` (SECURITY DEFINER):
   - Typ: `final`
   - Zdroj: `booking`
   - Číslo: FV-YYYY-NNNN
   - Automaticky odečte zálohy (advance payments)
   - Itemizovaný rozpis + daň

### DŮLEŽITÉ:
- Faktura může **chvíli trvat** po dokončení (trigger je async)
- Pokud uživatel klikne příliš brzy, vidí "Faktura zatím není k dispozici"
- Faktura je **definitivní** - nelze ji upravit

---

## CTA 2: NÁJEMNÍ SMLOUVA (📄)

### Co to dělá
Naviguje na obrazovku **Smlouvy** (`/contracts`) kde uživatel najde svou nájemní smlouvu.

### Flow:
1. Uživatel klikne "Nájemní smlouva"
2. Redirect na Routes.contracts
3. Na obrazovce smluv se zobrazí dokumenty typu `contract` a `vop` (všeobecné obchodní podmínky)

### Supabase:
- Tabulka `documents` s `type = 'contract'` a `booking_id`
- Tabulka `contracts` pro obecné smlouvy
- Smlouva se generuje automaticky při potvrzení rezervace nebo při editaci
- `document_templates` obsahuje HTML šablonu smlouvy

### Co smlouva obsahuje:
- Identifikace pronajímatele (MotoGo24)
- Identifikace nájemce (zákazník)
- Popis motorky (model, SPZ, VIN)
- Období pronájmu (start_date – end_date)
- Cena a platební podmínky
- Pojistné podmínky
- Odpovědnost za škody
- Storno podmínky

---

## CTA 3: OHODNOTIT NA GOOGLE (⭐)

### Co to dělá
Otevře **externí odkaz** na Google Reviews pro MotoGo24 v defaultním prohlížeči.

### Flow:
1. Uživatel klikne "Ohodnotit na Google"
2. `launchUrl(Uri.parse('https://g.page/r/motogo24/review'))`
3. Otevře se prohlížeč/Google Maps s review formulářem
4. Uživatel může napsat recenzi a dát hvězdy na Google

### DŮLEŽITÉ:
- Toto je **externí** akce - opouští aplikaci
- Nelze sledovat, zda uživatel skutečně zanechal recenzi
- Žádná zpětná vazba v appce po návratu

---

## CTA 4: REZERVOVAT ZNOVU (🔁)

### Co to dělá
Resetuje booking draft a přesměruje na **detail motorky** pro vytvoření nové rezervace se stejnou motorkou.

### Flow krok za krokem:
1. Uživatel klikne "Rezervovat znovu"
2. **Reset stavu**:
   ```dart
   ref.read(bookingDraftProvider.notifier).state = BookingDraft(); // prázdný draft
   ref.read(bookingMotoProvider.notifier).state = null;            // žádná vybraná moto
   ref.read(catalogFilterProvider.notifier).state = CatalogFilter(); // reset filtrů
   ```
3. **Pokud je motoId dostupné** (většina případů):
   - Navigace na `/moto/{motoId}` (detail motorky)
   - Toast: "🏍️ Rezervace – Vyberte nový termín pro stejnou motorku"
   - Uživatel se ocitne na detailu motorky → může vybrat nové datumy → standardní booking flow
4. **Pokud motoId NENÍ dostupné** (vzácné - motorka smazána/retired):
   - Navigace na domovskou stránku (`Routes.home`)
   - Toast: "🏍️ Rezervace – Vyberte motorku"
   - Uživatel musí vybrat jinou motorku

### Co se stane dál (standardní booking flow):
1. Detail motorky → výběr datumů v kalendáři
2. Booking form → adresa, čas, doplňky
3. Payment → Stripe checkout
4. Success → nová rezervace vytvořena

---

## CO SE NEZOBRAZUJE U DOKONČENÉ REZERVACE

- **Žádné editační možnosti** (nelze měnit termín, motorku, atd.)
- **Žádné zrušení** (už je dokončená)
- **Žádné SOS** (motorka vrácena)
- **Žádné přístupové kódy** (deaktivovány triggerem `trg_auto_deactivate_door_codes`)
- **Žádný předávací protokol** (jen u aktivní)

---

## SPECIÁLNÍ PŘÍPAD: DOKONČENÁ KVŮLI SOS

Pokud `ended_by_sos = true`:
- Rezervace se zobrazí jako dokončená (ResStatus.dokoncene)
- V seznamu rezervací se zobrazí badge "🆘 Ukončeno – SOS incident"
- V detailu: stejné CTA jako normální dokončená
- Ale fakticky motorka byla vrácena dříve kvůli SOS incidentu
- Pokud existuje `replacement_for_booking_id`, uživatel má novou aktivní rezervaci s náhradní motorkou

---

## SUPABASE DATA V DETAILU DOKONČENÉ REZERVACE

### Zobrazená data:
| Zdroj | Data |
|-------|------|
| `bookings` | Všechna pole jako u aktivní + rating, rated_at |
| `motorcycles` | model, image_url, category |
| `branches` | name, address, city |
| `invoices` | type=final, number, items, total |
| `documents` | type=contract, file_url |
| `profiles` | full_name, street, city, zip (pro fakturu) |

### Vizuální rozdíly:
- Obrázek motorky je v **grayscale** (šedotón) na kartě v seznamu
- Status badge: **šedý** (#9CA3AF)
- Status text: "Dokončená"
