# ANALÝZA CTA - ZRUŠENÁ REZERVACE + CELKOVÝ SOUHRN

---

## ČÁST A: ZRUŠENÁ REZERVACE

> Stav: cancelled = rezervace zrušena zákazníkem, adminem nebo systémem.
> Supabase status: `cancelled`
> Vzniká: manuálně přes `cancel_booking_tracked()` RPC, nebo automaticky cronem `auto_cancel_expired_pending()` (10 min app / 4h web pro nezaplacené pending).

---

### PŘEHLED CTA V DETAILU ZRUŠENÉ REZERVACE

| # | CTA | Typ tlačítka | Barva | Ikona | Akce |
|---|-----|-------------|-------|-------|------|
| 1 | **Obnovit rezervaci** | primary (zelené) | `#74FB71` | 🔄 | Navigace na `/search` |

+ speciální sekce **Storno poplatky** (pouze zobrazení, žádná akce).

---

### SEKCE: STORNO POPLATKY

Karta zobrazující finanční dopad zrušení:

| Řádek | Hodnota | Odkud |
|-------|---------|-------|
| **Storno poplatek** | `X Kč` | `bookings.storno_fee` |
| **Vrácená částka** | `X Kč` (zelený text) | `bookings.refund_amount` |

Pokud `storno_fee` nebo `refund_amount` je null, zobrazí se `0 Kč`.

#### Jak se storno poplatek počítá (backend):
```
hodin_do_startu = start_date - cancelled_at

168+ h (7+ dní)  → refund 100% → storno_fee = 0 Kč
48–168 h (2–7 d) → refund 50%  → storno_fee = 50% z total_price
< 48 h (< 2 d)  → refund 0%   → storno_fee = 100% z total_price
```

Záznam v `booking_cancellations`:
- `refund_percent`: 0 / 50 / 100
- `refund_amount`: vypočtená částka
- `reason`: důvod od zákazníka nebo "Auto-cancelled expired pending"

---

### CTA 1: OBNOVIT REZERVACI (🔄)

#### Co to dělá
Přesměruje uživatele na **vyhledávání** (`/search`), kde může vytvořit novou rezervaci.

#### Aktuální implementace:
```dart
onTap: () => context.go(Routes.search)
```

#### Co to znamená pro uživatele:
- **NEOBNOVUJE** původní rezervaci přímo
- Přesměruje na stránku vyhledávání motorek
- Uživatel musí projít celý booking flow znovu (výběr moto → termín → platba)
- Původní motorka nemusí být dostupná v původním termínu

#### Originální frontend (reference):
V originální Capacitor appce existuje plnohodnotný `restoreBooking()`:
1. Změní status zpět na `pending`
2. Přesměruje na platební bránu
3. Po zaplacení: `apiConfirmRestoreBooking()` → status `reserved`/`active`

**Poznámka**: Flutter verze má zjednodušenou implementaci — jen redirect na search. Originál měl skutečné obnovení se zachováním původních parametrů.

---

### CO SE NEZOBRAZUJE U ZRUŠENÉ REZERVACE

- Žádné editační možnosti
- Žádné SOS
- Žádné přístupové kódy (deaktivovány)
- Žádné hodnocení
- Žádné dokumenty (faktury/smlouvy)
- Žádný protokol

---

## ČÁST B: CELKOVÝ SOUHRN VŠECH CTA NAPŘÍČ STAVY

### MATICE: STAV × CTA

| CTA | Nadcházející | Aktivní | Dokončená | Zrušená |
|-----|:---:|:---:|:---:|:---:|
| Upravit/Prodloužit/Zkrátit | ✅ plný edit | ✅ omezený | — | — |
| Zrušit rezervaci | ✅ dialog | — | — | — |
| SOS | — | ✅ | — | — |
| Předávací protokol | — | ✅ | — | — |
| Přístupové kódy | — | ✅ zobrazení | — | — |
| Konečná faktura | — | — | ✅ | — |
| Nájemní smlouva | — | — | ✅ | — |
| Hodnocení (hvězdy) | — | — | ✅ | — |
| Google recenze | — | — | ✅ | — |
| Rezervovat znovu | — | — | ✅ | — |
| Obnovit rezervaci | — | — | — | ✅ |
| Storno info | — | — | — | ✅ zobrazení |

---

### SOUHRN FLOW: PRODLOUŽENÍ REZERVACE

```
NADCHÁZEJÍCÍ                          AKTIVNÍ
─────────────                         ──────
✏️ Upravit → Edit screen              ✏️ Prodloužit → Edit screen
Tab "Prodloužit"                      Tab "Prodloužit"
Kalendář: klik PŘED start             Kalendář: klik POUZE PO end
         NEBO PO end                  (start nelze měnit)
    ↓                                     ↓
Cenový přehled: +X Kč                 Cenový přehled: +X Kč
    ↓                                     ↓
"Pokračovat k platbě"                "Pokračovat k platbě"
    ↓                                     ↓
PaymentScreen (Stripe)                PaymentScreen (Stripe)
    ↓                                     ↓
Booking aktualizován                  Booking aktualizován
modification_history záznam           modification_history záznam
```

---

### SOUHRN FLOW: ZKRÁCENÍ REZERVACE

```
NADCHÁZEJÍCÍ                          AKTIVNÍ
─────────────                         ──────
✏️ Upravit → Edit screen              ✏️ Prodloužit → Edit screen
Tab "Zkrácení"                        Tab "Zkrácení"
Výběr směru:                          Automaticky: zkrátit konec
  "Zkrátit začátek"                   (začátek nelze měnit)
  "Zkrátit konec"                         ↓
    ↓                                 Kalendář: klik na nový konec
Kalendář: klik na nové datum              ↓
    ↓                                 Storno výpočet:
Storno výpočet:                         newEnd → kolik hodin zbývá
  newEnd → kolik hodin zbývá              ↓
    ↓                                 7+ dní = 100% zpět
7+ dní = 100% zpět                    2–7 dní = 50% zpět
2–7 dní = 50% zpět                    < 2 dny = 0% zpět
< 2 dny = 0% zpět                        ↓
    ↓                                 "Uložit změny"
"Uložit změny"                            ↓
    ↓                                 Potvrzovací stránka
Potvrzovací stránka                   "Vrácení: X Kč (Y%)"
"Vrácení: X Kč (Y%)"                 Stripe refund na pozadí
Stripe refund na pozadí
```

**Klíčový rozdíl**: U aktivní rezervace uživatel typicky dostane **méně zpět** (nebo nic), protože nový konec je blíž → méně hodin → nižší storno procento.

---

### SOUHRN FLOW: ZMĚNY V REZERVACI (jen nadcházející)

```
✏️ Upravit → Edit screen
    │
    ├── Změna motorky
    │   Rozbalit seznam → Vybrat (validace ŘP) → Cenový rozdíl
    │
    ├── Změna místa vyzvednutí
    │   Pobočka ↔ Doručení → Adresa → Poplatek (1000 + km×2×20)
    │
    ├── Změna místa vrácení
    │   Pobočka ↔ Doručení → Adresa → Poplatek
    │
    ├── Změna doplňků
    │   Spolujezdec outfit (400 Kč) / Boty řidič (300) / Boty spolujezdec (300)
    │
    └── Změna velikostí
        Helma, bunda, kalhoty, boty, rukavice (XS–XXL)
        + spolujezdec (pokud outfit zaškrtnut)

Všechny změny → Cenový přehled (automatický přepočet)
    ↓
Doplatek > 0 → Stripe platba
Doplatek ≤ 0 → Uložit přímo
```

---

### SOUHRN FLOW: ZRUŠENÍ

```
NADCHÁZEJÍCÍ
─────────────
🗑️ Zru��it → AlertDialog
    │
    ├── Zobrazí: motorku, termín, storno podmínky
    ├── Barevný box (zelený/žlutý/červený dle %)
    ├── "Aktuálně: X% (Y Kč)"
    ├── Textové pole: důvod (nepovinné)
    │
    └── "Zrušit rezervaci" (červené)
            ↓
        RPC: cancel_booking_tracked()
            ↓
        Backend:
          status → cancelled
          booking_cancellations záznam
          Stripe refund (process-refund edge fn)
          Credit note (dobropis) automaticky
            ↓
        Detail se refreshne → zobrazí jako Zrušená
```

---

### CENOVÉ VZORCE (reference)

#### Per-day pricing (primární):
Každá motorka má 7 cen: `price_mon` – `price_sun`.
```
totalForRange(start, end) = suma cen pro každý den v rozsahu (inclusive)
```

#### Fallback (průměrná denní cena):
```
origDailyPrice = (totalPrice + discountAmount - deliveryFee - extrasPrice) / origDays
```

#### Doplatek za prodloužení:
```
newRange - origRange  (per-day) NEBO diffDays × origDailyPrice (fallback)
```

#### Vrácení za zkrácení:
```
surová_částka = origRange - newRange
storno_% = StornoCalc(newEnd)  // 100/50/0 dle hodin
vráceno = surová_částka × storno_% / 100
```

#### Doručení:
```
poplatek = 1000 + (vzdálenost_km × 2 × 20) Kč
```

#### Změna motorky:
```
rozdíl = newMoto.totalForRange(start,end) - origMoto.totalForRange(start,end)
```

---

### SUPABASE FUNKCE POUŽITÉ V CTA

| RPC / Trigger | Kdy se volá | Co dělá |
|--------------|-------------|---------|
| `cancel_booking_tracked(id, reason)` | Zrušení | Storno + refund + credit note |
| `confirm_payment(id, method)` | Po Stripe platbě | pending→reserved/active |
| `auto_activate_reserved_bookings()` | Cron denně 00:01 | reserved→active |
| `auto_complete_expired_bookings()` | Cron denně 00:01 | active→completed + faktura |
| `auto_cancel_expired_pending()` | Cron každé 2 min | Nezaplacené→cancelled |
| `auto_generate_door_codes()` | Trigger status→active | 2 kódy (moto + accessories) |
| `auto_deactivate_door_codes()` | Trigger status→completed/cancelled | Deaktivace kódů |
| `generate_final_invoice_on_complete()` | Trigger status→completed | Konečná faktura |
| `process-refund` (Edge Function) | Storno/zkrácení | Stripe refund API |
| `sos_swap_bookings(incident, moto)` | SOS náhrada | Ukončí původní + nový booking |

---

### IDENTIFIKOVANÉ PROBLÉMY / NESROVNALOSTI

1. **Obnovit rezervaci** — Flutter verze jen redirectuje na `/search`, originál měl skutečné obnovení (`restoreBooking()` + re-payment). Chybí zachování parametrů původní rezervace.

2. **Změna start_date u aktivní** — kód správně blokuje, ale chybová hláška by mohla být jasnější pro uživatele ("Motorka je u vás, začátek nelze posunout").

3. **Storno u zkrácení aktivní** — uživatel může být překvapen, že za zkrácení o 1 den (< 48h) nedostane NIC zpět. Chybí vizuální varování PŘED kliknutím na datum.

4. **Platba při prodloužení** — changes se uloží do bookings PŘED úspěšnou platbou. Pokud platba selže, booking má nové datumy ale nezaplaceno. Měl by být rollback nebo jiný mechanismus.

5. **Konečná faktura** — může být nedostupná hned po dokončení (trigger latence). Uživatel vidí "Faktura zatím není k dispozici" bez vysvětlení kdy bude.

6. **Protocol** — aktuálně jen UI demo (toast "Odesláno"), chybí reálné ukládání do `documents` tabulky v Supabase.

7. **Nájemní smlouva** — CTA naviguje na `/contracts` obecně, ale nefiltruje konkrétní smlouvu pro daný booking.
