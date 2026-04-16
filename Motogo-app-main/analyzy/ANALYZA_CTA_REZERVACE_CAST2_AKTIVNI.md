# ANALÝZA CTA - AKTIVNÍ REZERVACE

> Stav: aktivni = motorka je právě u zákazníka. `start_date <= today <= end_date`, status `active` nebo `reserved` s `picked_up_at` nastaveným.
> Supabase status: `active` + `payment_status = paid`
> Automatická aktivace: cron `auto_activate_reserved_bookings()` denně v 00:01 UTC změní `reserved → active` když `start_date <= today`.

---

## PŘEHLED VŠECH CTA V DETAILU AKTIVNÍ REZERVACE

Na obrazovce detailu aktivní rezervace se zobrazují **3 tlačítka** + speciální sekce **přístupové kódy**:

| # | CTA | Typ tlačítka | Barva | Ikona | Navigace |
|---|-----|-------------|-------|-------|----------|
| 1 | **Prodloužit / Zkrátit** | primary (zelené) | `#74FB71` | ✏️ | `/reservations/{id}/edit` |
| 2 | **SOS** | sos (světle červené) | `#EF4444` bg light | 🆘 | `/sos` |
| 3 | **Předávací protokol** | outlined (bílé se zeleným okrajem) | white + `#3DBA3A` border | 📝 | `/protocol` |

---

## SPECIÁLNÍ SEKCE: PŘÍSTUPOVÉ KÓDY (🔑)

### Co to je
Karta zobrazující **dveřní kódy** pro přístup k motorce a příslušenství na pobočce. Kódy se generují automaticky při aktivaci rezervace.

### Jak to funguje (Supabase):
1. Trigger `trg_auto_generate_door_codes_update` se spustí při `status → active`
2. Funkce `auto_generate_door_codes()` vygeneruje 2 kódy:
   - **motorcycle** - kód pro přístup k motorce
   - **accessories** - kód pro přístup k příslušenství (helma, bunda, atd.)
3. Každý kód je **6místné číslo**
4. Kódy se uloží do `branch_door_codes` tabulky

### Validace dokumentů před odesláním kódů:
- Systém **ověří dokumenty zákazníka** (občanský průkaz/pas + řidičský průkaz)
- Pokud dokumenty **JSOU ověřeny**: `sent_to_customer = true`, kód se zobrazí
- Pokud dokumenty **NEJSOU ověřeny**: `sent_to_customer = false`, zobrazí se `withheld_reason` (např. "Čekáme na ověření dokumentů")

### Co uživatel vidí:
- Karta s nadpisem "🔑 Přístupové kódy"
- Dva řádky:
  - **Motorka**: `123456` (pokud ověřeno) nebo "Čekáme na ověření dokumentů" (pokud neověřeno)
  - **Příslušenství**: `654321` (pokud ověřeno) nebo důvod zadržení

### Stavy zobrazení:
- **Loading**: Spinner vedle nadpisu "Přístupové kódy"
- **Error**: Text "Přístupové kódy nejsou dostupné"
- **Prázdné**: Nic se nezobrazí (žádné kódy v DB)
- **Data**: Zobrazí kódy nebo důvod zadržení

### Supabase dotaz:
```sql
SELECT * FROM branch_door_codes
WHERE booking_id = '{id}' AND is_active = true
```

---

## CTA 1: PRODLOUŽIT / ZKRÁTIT (✏️)

### Co to dělá
Otevře **stejnou** obrazovku `ReservationEditScreen` jako u nadcházející, ALE s **omezeními** pro aktivní rezervaci.

### KLÍČOVÉ ROZDÍLY oproti nadcházející:

| Funkce | Nadcházející | Aktivní |
|--------|-------------|---------|
| Změna start_date | ANO (posun dříve/později) | **NE** (start se nedá změnit - motorka už je u zákazníka) |
| Změna end_date - prodloužení | ANO | **ANO** (přidání dnů za konec) |
| Změna end_date - zkrácení | ANO (obě směry) | **ANO** (pouze zkrácení konce, ne začátku) |
| Změna pickup method | ANO | **NE** (sekce se nezobrazí) |
| Změna return method | ANO | **ANO** |
| Změna motorky | ANO | **NE** (sekce se nezobrazí) |
| Změna doplňků | ANO | **NE** (sekce se nezobrazí) |
| Změna velikostí | ANO | **NE** |

### FLOW: PRODLOUŽENÍ AKTIVNÍ REZERVACE

#### Krok za krokem:
1. Uživatel klikne "Prodloužit / Zkrátit"
2. Otevře se edit screen s `_isActive = true`
3. Záložka "Prodloužit" je výchozí
4. Kalendářní instrukce: *"Klikněte na den PO {end_date} pro prodloužení"*
   - **NELZE** kliknout na den PŘED start_date (u aktivní je to zakázáno)
   - Lze kliknout POUZE na dny ZA stávajícím koncem
5. Uživatel klikne na nový konec
6. Cenový přehled zobrazí doplatek
7. CTA: "Pokračovat k platbě (+X Kč)"

#### Validace při uložení (aktivní):
```dart
if (_isActive) {
  final origS = DateTime(booking.startDate...);
  final newS = DateTime(_newStart...);
  if (origS != newS) {
    toast: "U aktivní rezervace nelze měnit datum vyzvednutí"
    return;
  }
}
```

#### Co se stane po uložení:
1. Kontrola dostupnosti motorky na prodloužené období
2. **Doplatek > 0** (vždy u prodloužení):
   - UPDATE `bookings` SET `end_date = nový_konec`, `total_price = nový_total`
   - Redirect na `PaymentScreen` s `PaymentFlowType.extension`
   - Stripe checkout na doplatek
   - Po úspěšné platbě: booking je aktualizovaný
3. `modification_history` se aktualizuje na backendu

### FLOW: ZKRÁCENÍ AKTIVNÍ REZERVACE

#### Krok za krokem:
1. Uživatel přepne na záložku "Zkrácení"
2. Žlutý banner se storno podmínkami
3. U aktivní rezervace se **NEZOBRAZUJÍ** tlačítka "Zkrátit začátek"/"Zkrátit konec"
   - Důvod: začátek nelze měnit u aktivní, takže automaticky se zkracuje konec
4. Instrukce: *"Klikněte na nový den vrácení před {end_date}"*
5. Uživatel klikne na datum **uvnitř** stávajícího rozsahu
6. Storno procento se vypočítá podle vzdálenosti od nového konce:

#### Příklad zkrácení aktivní:
- Aktivní rezervace: 5.–15. dubna (11 dní), celkem 16 500 Kč
- Dnes: 12. dubna
- Uživatel chce vrátit motorku 13. dubna (místo 15.)
- Odebrané 2 dny: cca 3 000 Kč
- Hodin do 13. dubna: cca 24h → **MÉNĚ NEŽ 48h → 0% vrácení!**
- Vráceno: 0 Kč

**To znamená**: Při zkrácení aktivní rezervace o pár dní dopředu uživatel často nedostane NIC zpět, protože nový konec je příliš blízko.

#### Po uložení zkrácení:
1. UPDATE `bookings` SET `end_date = nový_konec`, `total_price = nový_total`
2. Zobrazí `EditConfirmPage`:
   - Ikona: oranžová (currency_exchange)
   - "Rezervace byla zkrácena. Vrácení: X Kč (Y%)"
   - "Částka bude vrácena na původní platební metodu."
3. Nebo pokud 0%: potvrzení bez vrácení

### ZMĚNA VRÁCENÍ (jediná non-date změna u aktivní)
- Toggle: Pobočka / Doručení na adresu
- Adresa + výpočet poplatku
- Čas vrácení (hodiny:minuty picker)
- **To je jediná další věc co uživatel může změnit** u aktivní rezervace mimo datum

---

## CTA 2: SOS (🆘)

### Co to dělá
Naviguje na hlavní **SOS help screen** (`/sos`) kde uživatel najde pomoc v nouzové situaci.

### Flow po kliknutí:
Otevře se obrazovka `SOS` s těmito možnostmi:

| Možnost | Popis | Navigace |
|---------|-------|----------|
| **AI Asistent** | Diagnostický chatbot | AI agent screen |
| **Nehoda / Krádež** | Nahlášení nehody | s-sos-nehoda |
| **Nepojízdná motorka** | Porucha, závada | s-sos-nepojizda |
| **Sdílení polohy** | GPS lokace pro podporu | Odešle GPS |
| **Telefon na podporu** | Přímý hovor | tel: odkaz |

### SOS REPLACEMENT FLOW (náhradní motorka):
Pokud uživatel nahlásí problém (nehoda/porucha) a motorka je nepojízdná:

1. **Vytvoření SOS incidentu** v `sos_incidents`:
   - `type`: theft/accident_minor/accident_major/breakdown_minor/breakdown_major
   - `status`: reported
   - `booking_id`: aktuální rezervace
   - `moto_id`: aktuální motorka
   - `customer_fault`: true/false (ovlivňuje cenu)

2. **Výběr náhradní motorky**:
   - Zobrazí se seznam dostupných motorek
   - **Pokud NENÍ vina zákazníka** → náhrada ZDARMA
   - **Pokud JE vina zákazníka** → zákazník platí rozdíl + zálohu

3. **Cenový výpočet SOS**:
   - Zbývající dny = end_date - today + 1
   - Cena náhrady = per-day pricing nové motorky × zbývající dny
   - Doručení náhrady na adresu zákazníka
   - Záloha (deposit) pokud je vina zákazníka

4. **Platba** (pokud placená):
   - Redirect na PaymentScreen s `PaymentFlowType.sos`
   - SOS breakdown v UI: motorka, doručení, záloha

5. **Po dokončení**:
   - Původní booking: `ended_by_sos = true`, `status → completed`
   - Nový booking: `sos_replacement = true`, `replacement_for_booking_id = původní_id`
   - SOS incident: `replacement_booking_id = nový_id`, `replacement_moto_id = nová_moto`
   - Nové dveřní kódy pro novou motorku

### Supabase tabulky při SOS:
| Tabulka | Operace |
|---------|---------|
| `sos_incidents` | INSERT (incident) |
| `sos_timeline` | INSERT (akce) |
| `bookings` (původní) | UPDATE (ended_by_sos, status) |
| `bookings` (nový) | INSERT (nová rezervace) |
| `branch_door_codes` | INSERT (nové kódy) |
| `branch_door_codes` (staré) | UPDATE (is_active = false) |
| `invoices` | INSERT (pokud platba) |

---

## CTA 3: PŘEDÁVACÍ PROTOKOL (📝)

### Co to dělá
Otevře obrazovku **digitálního předávacího protokolu** (`ProtocolScreen`) — potvrzení o stavu motorky a vybavení při převzetí/vrácení.

### Co uživatel vidí:

#### 1. CHECKLIST VYBAVENÍ
Dvě kategorie položek:

**Povinné (locked, vždy zaškrtnuté, nelze odškrtnout)**:
- 🔑 Klíče od motorky
- 📄 Pojistka
- 📋 Technický průkaz
- 🦺 Reflexní vesta
- 🩹 Lékárnička

**Volitelné (uživatel může zaškrtnout/odškrtnout)**:
- 🪖 Helma
- 🧤 Rukavice
- 🧥 Bunda
- 👖 Kalhoty

#### 2. POZNÁMKY O STAVU
- Textové pole pro popis stavu motorky
- Placeholder: "Škrábance, poškození..."
- Max 3 řádky

#### 3. DIGITÁLNÍ PODPIS
Dva způsoby podpisu:

**Biometrický podpis** (primární):
- Zelené tlačítko "🔐 Podepsat biometricky"
- Simuluje biometrické ověření (1.2s delay)
- Po ověření: toast "Podpis potvrzen"

**PIN podpis** (sekundární):
- Outlined tlačítko "Podepsat PINem"
- Zobrazí PIN input (4–6 číslic, obscured)
- Validace: min. 4 znaky
- Tlačítko "Potvrdit PIN"

**Po podpisu** se zobrazí:
- Zelený box s ✅
- "Podepsáno"
- Datum a čas podpisu

#### 4. ODESLÁNÍ
- Zelené CTA: "📤 Odeslat protokol"
- **Validace**: Pokud nepodepsáno → toast "Nejdříve podepište"
- **Po odeslání**: toast "Protokol odeslán", po 1.5s se vrátí zpět

### Co se stane na backendu:
- Protokol se uloží jako dokument typu `protocol` v tabulce `documents`
- `file_url` + `storage_path` odkazují na uložený protokol
- Slouží jako právní důkaz o stavu motorky při převzetí

### DŮLEŽITÉ PRO UŽIVATELE:
- Protokol je **důkaz o stavu motorky** při převzetí
- Pokud jsou škrábance/poškození, **MUSÍ je zapsat** do poznámek
- Jinak může být později obviněn z poškození, které nezpůsobil
- Podpis je **právně závazný**

---

## TIMELINE AKTIVNÍ REZERVACE

```
[Uživatel má motorku] 
    │
    ├── ✏️ Prodloužit → Kalendář → Doplatek → Stripe → Hotovo
    │
    ├── ✏️ Zkrátit → Kalendář → Vrácení (0-100%) → Hotovo
    │
    ├── 🆘 SOS → Typ problému → Náhradní moto → (Platba) → Nová rezervace
    │
    └── 📝 Protokol → Checklist → Poznámky → Podpis → Odesláno
```

---

## SUPABASE DATA V DETAILU AKTIVNÍ REZERVACE

### Zobrazená data (čtení):
| Zdroj | Data |
|-------|------|
| `bookings` | start_date, end_date, total_price, delivery_fee, extras_price, discount_amount, pickup/return method+address, payment_status |
| `motorcycles` | model, image_url, category, license_required |
| `branches` | name, address, city, gps_lat, gps_lng |
| `branch_door_codes` | code_type, door_code, sent_to_customer, withheld_reason |

### Výpočty na klientu:
- `displayStatus` = aktivni (startDate <= today <= endDate)
- `dayCount` = endDate - startDate + 1
- `dateRange` = "DD.MM. – DD.MM.YYYY"
- `shortId` = posledních 8 znaků UUID velkými písmeny
