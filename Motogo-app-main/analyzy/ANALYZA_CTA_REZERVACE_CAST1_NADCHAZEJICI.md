# ANALÝZA CTA - NADCHÁZEJÍCÍ (upcoming) REZERVACE

> Stav: nadchazejici = rezervace se statusem `reserved`, platba zaplacena, `start_date` je v budoucnu.
> Supabase status: `reserved` + `payment_status = paid` + `start_date > today`

---

## PŘEHLED VŠECH CTA V DETAILU NADCHÁZEJÍCÍ REZERVACE

Na obrazovce detailu nadcházející rezervace se zobrazují **2 tlačítka**:

| # | CTA | Typ tlačítka | Barva | Ikona | Navigace |
|---|-----|-------------|-------|-------|----------|
| 1 | **Upravit rezervaci** | primary (zelené) | `#74FB71` | ✏️ | `/reservations/{id}/edit` |
| 2 | **Zrušit rezervaci** | danger (červené) | `#EF4444` | 🗑️ | Dialog (modal) |

---

## CTA 1: UPRAVIT REZERVACI (✏️ Editovat)

### Co to dělá
Otevře obrazovku `ReservationEditScreen` kde uživatel může měnit **VŠECHNY** parametry své nadcházející rezervace:

- Termín (prodloužení NEBO zkrácení)
- Místo vyzvednutí (pobočka vs. doručení na adresu)
- Místo vrácení (pobočka vs. doručení na adresu)
- Čas vyzvednutí a vrácení
- Změna motorky (s validací řidičáku)
- Doplňky (spolujezdec outfit, boty řidič, boty spolujezdec)
- Velikosti vybavení (helma, bunda, kalhoty, boty, rukavice + spolujezdec)

### Jak to vypadá
Po kliknutí se otevře `ReservationEditScreen` s těmito sekcemi:

#### HEADER
- Zelený back button
- "Upravit rezervaci"
- Název motorky + zkrácené ID (#ABCD1234)
- Zelený badge s aktuálním termínem
- "Nadcházející · X dní"

#### ZÁLOŽKY (TABY)
Dvě záložky v horní části:
1. **"Prodloužit / Změna místa"** (extend) - výchozí
2. **"Zkrácení / Změna místa"** (shorten)

---

### FLOW: PRODLOUŽENÍ (TAB "Prodloužit")

#### Krok za krokem pro uživatele:
1. Uživatel je na záložce "Prodloužit / Změna místa" (výchozí)
2. Vidí **kalendář** s vyznačeným stávajícím termínem (zelené zvýraznění)
3. Instrukce nad kalendářem: *"Klikněte na den PŘED {start} nebo PO {end} pro prodloužení"*
4. **Uživatel klikne na datum** v kalendáři:
   - Datum PŘED start_date = posune začátek dříve (přidá dny na začátku)
   - Datum PO end_date = posune konec později (přidá dny na konci)
5. Kalendář se aktualizuje - ukazuje nový rozsah
6. Pod kalendářem se zobrazí **informace o změně**: "Původní: X dní → Nový: Y dní (+Z dní)"
7. Cenový přehled se automaticky přepočítá

#### Co se děje s cenou při prodloužení:
- **Výpočet**: Pro každý přidaný den se vezme cena za den z tabulky `motorcycles` (per-day pricing: `price_mon`, `price_tue`, ..., `price_sun`)
- **Pokud má motorka per-day pricing**: `novyCelkem - puvodniCelkem` za dané rozsahy
- **Pokud nemá per-day pricing**: `počet_přidaných_dní × průměrná_denní_cena`
- Průměrná denní cena = `(totalPrice + discountAmount - deliveryFee - extrasPrice) / origDays`
- **Výsledek je VŽDY kladný** = uživatel MUSÍ doplatit

#### Co se stane po kliknutí "Uložit":
1. **Kontrola dostupnosti motorky** na nové datumy (`checkMotoAvailability`)
   - Dotaz do Supabase: existuje jiná rezervace (status IN [reserved, active, pending]) pro stejné moto_id s překrývajícími se daty?
   - Pokud ANO → toast: "Motorka je v tomto termínu obsazená"
   - Pokud NE → pokračuje
2. **Pokud priceDiff > 0** (doplatek):
   - Uloží změny do `bookings` tabulky (nové datumy, pickup/return method, velikosti, atd.)
   - Nastaví `PaymentContext` s flowType: `extension`, částkou doplatku
   - Přesměruje na `PaymentScreen` (Stripe checkout)
   - Po úspěšné platbě se booking aktualizuje
3. **Pokud priceDiff == 0** (nepravděpodobné u prodloužení, ale možné pokud se změní jen method):
   - Uloží změny přímo
   - Zobrazí potvrzovací stránku `EditConfirmPage`

---

### FLOW: ZKRÁCENÍ (TAB "Zkrácení")

#### Krok za krokem pro uživatele:
1. Uživatel přepne na záložku "Zkrácení / Změna místa"
2. Zobrazí se **upozornění** (žlutý banner): 
   > "Storno podmínky: Více než 7 dní = 100% vrácení | 2–7 dní = 50% vrácení | Méně než 2 dny = 0% vrácení"
3. Zobrazí se **dvě tlačítka pro směr zkrácení**:
   - **"Zkrátit začátek"** - posune start_date dopředu (odeberete dny ze začátku)
   - **"Zkrátit konec"** - posune end_date dozadu (odeberete dny z konce)
4. Uživatel **vybere směr** kliknutím na jedno z tlačítek
5. Instrukce se změní:
   - "Zkrátit začátek" → *"Klikněte na nový den začátku rezervace"*
   - "Zkrátit konec" → *"Klikněte na nový den konce rezervace"*
6. **Uživatel klikne na datum** v kalendáři (uvnitř stávajícího rozsahu)
7. Nový rozsah se zobrazí, cenový přehled se přepočítá

#### STORNO PODMÍNKY (KRITICKÉ PRO UŽIVATELE):
Výpočet vrácení peněz závisí na tom, **kolik hodin zbývá do odebraného data**:

| Čas do odebraného data | Vrácení |
|------------------------|---------|
| **7+ dní** (168+ hodin) | **100%** z ceny odebraných dní |
| **2–7 dní** (48–168 hodin) | **50%** z ceny odebraných dní |
| **Méně než 2 dny** (< 48 hodin) | **0%** (nic se nevrací) |

**Konkrétní výpočet**:
```
odebrané_dny = origDays - newDays
cena_odebranych_dni = (per-day pricing rozdíl) NEBO (odebrané_dny × denní_cena)
storno_procent = StornoCalc.refundPercent(newEnd)  // hodin do nového konce
vraceno = cena_odebranych_dni × (storno_procent / 100)
```

**Příklad**:
- Původní rezervace: 1.–10. května (10 dní), celkem 15 000 Kč
- Zkrácení konce na 7. května (7 dní)
- Odebrané 3 dny = cca 4 500 Kč
- Dnes je 12. dubna → do 7. května zbývá 25 dní → 100% vrácení
- Vráceno: 4 500 Kč

#### Co se stane po kliknutí "Uložit" (zkrácení):
1. Kontrola dostupnosti (pro jistotu)
2. **Pokud priceDiff < 0** (vrácení peněz):
   - Uloží změny do `bookings` tabulky
   - Zobrazí `EditConfirmPage` s textem:
     > "Rezervace byla zkrácena. Vrácení: X Kč (Y%). Částka bude vrácena na původní platební metodu."
   - Ikona: oranžová (currency_exchange)
   - Na pozadí: Supabase trigger `process-refund` → Stripe refund → credit note (dobropis)
3. **Pokud priceDiff == 0** (storno 0%):
   - Uloží změny, zobrazí potvrzení
   - Žádné peníze se nevrací

---

### DALŠÍ EDITOVATELNÉ SEKCE (pouze nadcházející)

#### PŘISTAVENÍ MOTORKY (Pickup)
- Toggle: **Pobočka** / **Doručení na adresu**
- Pokud "Doručení": zadání adresy (autocomplete), výpočet poplatku za doručení
- Poplatek: `1000 + (km × 2 × 20)` Kč (tam i zpět)
- Časový picker: hodiny (0–23), minuty (00/15/30/45)

#### VRÁCENÍ MOTORKY (Return)
- Stejné jako pickup: pobočka vs. doručení
- Vlastní adresa + poplatek za doručení
- Časový picker pro čas vrácení

#### ZMĚNA MOTORKY
- Rozbalovací sekce (collapsible)
- Zobrazí aktuální motorku (zelené zvýraznění)
- Seznam dostupných motorek filtrovaný podle **řidičského oprávnění uživatele**
- Hierarchie: AM < A1 < A2 < A < N (N = bez řidičáku)
- Pokud uživatel má A2, vidí jen motorky s license_required: AM, A1, A2, N
- Každá motorka zobrazuje: obrázek, model, požadovaný řidičák, cena/den
- **Cenový dopad**: rozdíl cen za nový rozsah dní (nová moto cena - původní moto cena)

#### DOPLŇKY (Extras)
- Checkboxy:
  - **Outfit spolujezdce** - 400 Kč
  - **Boty řidič** - 300 Kč
  - **Boty spolujezdec** - 300 Kč
- Po zaškrtnutí "Outfit spolujezdce" se zobrazí pickery velikostí pro spolujezdce
- **Velikosti vybavení**:
  - Řidič: helma, bunda, kalhoty, boty, rukavice (XS–XXL nebo čísla bot)
  - Spolujezdec: helma, bunda, kalhoty (jen pokud je zaškrtnut outfit)
- Žluté upozornění pokud je vybrán doručení: "Při doručení musí být zadány velikosti"

---

### CENOVÝ PŘEHLED (zobrazí se když hasChanges == true)

Automaticky se zobrazí karta s rozpisem:

| Řádek | Příklad |
|-------|---------|
| Původní cena | 15 000 Kč |
| Původní trvání | 10 dní |
| Nové trvání | 13 dní |
| Prodloužení (+3 dny) | +4 500 Kč |
| Doručení vyzvednutí | +1 500 Kč |
| Doručení vrácení | +1 200 Kč |
| Doplňky | +700 Kč |
| **DOPLATEK** | **+7 900 Kč** |

Nebo při zkrácení:

| Řádek | Příklad |
|-------|---------|
| Původní cena | 15 000 Kč |
| Zkrácení (3 dny) | -4 500 Kč |
| **VRÁCENÍ** | **-4 500 Kč** |

Pod souhrnem: "Storno: vrácení X%"

---

### CTA TLAČÍTKO ULOŽIT

Dynamický text podle situace:
- **Doplatek > 0**: `"Pokračovat k platbě (+X Kč)"` → naviguje na PaymentScreen
- **Doplatek == 0 nebo vrácení**: `"Uložit změny"` → uloží přímo
- **Žádné změny**: tlačítko je **disabled** (šedé)

---

## CTA 2: ZRUŠIT REZERVACI (🗑️ Danger button)

### Co to dělá
Otevře **modální dialog** (`ResCancelDialog`) pro potvrzení zrušení celé rezervace.

### Flow krok za krokem:

1. Uživatel klikne na červené tlačítko "Zrušit rezervaci"
2. Otevře se **AlertDialog** s:
   - **Titulek**: "Opravdu chcete zrušit rezervaci?"
   - **Název motorky** (tučně)
   - **Termín rezervace** (šedě)
   - **Storno podmínky** (barevný box):
     - Zelený box (100%): více než 7 dní do začátku
     - Žlutý box (50%): 2–7 dní do začátku
     - Červený box (0%): méně než 2 dny do začátku
   - Text: "Storno podmínky: 7+ dní = 100% | 2-7 dní = 50% | <2 dny = 0%"
   - **Aktuální vrácení**: "Aktuálně: X% (Y Kč)"
   - **Textové pole**: "Důvod zrušení (nepovinné)"
3. **Dvě tlačítka**:
   - "Zpět" (šedé) → zavře dialog
   - "Zrušit rezervaci" (červené) → provede storno

### Co se stane po potvrzení:
1. Volá se Supabase RPC: `cancel_booking_tracked(p_booking_id, p_reason)`
2. **Na backendu (Supabase)**:
   - `status` → `cancelled`
   - `cancelled_at` → now()
   - `cancellation_reason` → zadaný důvod (nebo "Zrušeno zákazníkem")
   - Vytvoří záznam v `booking_cancellations` (refund_amount, refund_percent)
   - Spustí Edge Function `process-refund` → Stripe API refund
   - Automaticky vygeneruje **credit note** (dobropis, invoice type: `credit_note`)
   - `payment_status` → `refunded` nebo `partial_refund`
3. Dialog se zavře
4. Provider se invaliduje → detail se refreshne → zobrazí se jako "Zrušená"
5. Pokud chyba → SnackBar s chybovou zprávou

### Výpočet vrácení při zrušení:
```
hodin_do_zacatku = startDate - now()
pokud hodin >= 168 (7 dní): 100% z totalPrice
pokud hodin >= 48 (2 dny): 50% z totalPrice
pokud hodin < 48: 0% z totalPrice
```

**Důležité**: Počítá se od `startDate` (začátek rezervace), NE od `endDate`.

---

## SUPABASE TABULKY DOTČENÉ PŘI EDITACI NADCHÁZEJÍCÍ REZERVACE

| Tabulka | Operace | Kdy |
|---------|---------|-----|
| `bookings` | UPDATE (start_date, end_date, total_price, pickup/return_method, moto_id, velikosti) | Vždy při uložení |
| `bookings.modification_history` | APPEND jsonb | Při změně datumů |
| `payment_methods` | READ | Při platbě doplatku |
| `invoices` | INSERT (type: advance) | Po úspěšné platbě doplatku |
| `invoices` | INSERT (type: credit_note) | Při zkrácení s vrácením |
| `booking_cancellations` | INSERT | Při zrušení |
| `invoices` | INSERT (type: credit_note) | Při zrušení |

---

## EDGE CASES A VALIDACE

1. **Motorka obsazená v novém termínu** → toast "Motorka je v tomto termínu obsazená", neuloží se
2. **Konec před začátkem** → toast "Neplatný rozsah datumů"
3. **Minulé datum** → kalendář blokuje kliknutí na minulé dny
4. **Stejné datum jako stávající** → tlačítko Uložit je disabled (hasChanges = false)
5. **Řidičák neodpovídá** → motorka se nezobrazí v seznamu dostupných
6. **Platba selže** → booking zůstane s původními daty (changes se uloží předem, ale payment_status zůstane)
