# MotoGo24 — Věrnostní ranky a motivační slevy v mobilní appce (NÁVRH)

> **Stav:** NÁVRH ke schválení — zatím NIC neimplementováno (žádné SQL, žádný kód).
> Vizuální náhled barev a obrazovek: `loyalty_ranky_nahled.html` (otevřít v prohlížeči).

## 1. Princip

- Platí **POUZE pro rezervace vytvořené v mobilní appce** (`bookings.booking_source = 'app'`). Web ranky nezná a slevu nedává.
- Sleva roste podle pořadí rezervace zákazníka v appce: **1 % na 1. rezervaci, 2 % od 3., 3 % od 5., … max 20 % od 39. rezervace**.
- Vzorec: `sleva_% = min(20, ceil(pořadí / 2))`, kde pořadí = počet kvalifikačních app rezervací + 1 (aktuální).
- **Kvalifikační rezervace** (doporučení): `booking_source='app' AND status='completed'` — storna a nedokončené se nepočítají.
- Level = procento slevy → **20 levelů**, každý má název a barvu MG loga v hlavičce appky.

## 2. Ranky — názvy, prahy, barvy

| Lvl | Od rezervace | Sleva | Název | Barva loga (hex) |
|----|----|----|----|----|
| 1 | 1. | 1 % | Startér | `#9CA3AF` šedá |
| 2 | 3. | 2 % | Jezdec | `#86EFAC` sv. zelená |
| 3 | 5. | 3 % | Motorkář | `#4ADE80` zelená |
| 4 | 7. | 4 % | Stálý jezdec | `#22C55E` tm. zelená |
| 5 | 9. | 5 % | Věrný zákazník | `#14B8A6` tyrkys |
| 6 | 11. | 6 % | Bronzový jezdec | `#CD7F32` bronz |
| 7 | 13. | 7 % | Stříbrný jezdec | `#C0C0C0` stříbro |
| 8 | 15. | 8 % | Zlatý jezdec | `#FFD700` zlato |
| 9 | 17. | 9 % | Platinový jezdec | `#E5E4E2` platina |
| 10 | 19. | 10 % | Diamantový jezdec | `#7DD3FC` diamant |
| 11 | 21. | 11 % | Prémiový zákazník | `#38BDF8` azur |
| 12 | 23. | 12 % | Mistr silnic | `#3B82F6` modrá |
| 13 | 25. | 13 % | Šampion | `#6366F1` indigo |
| 14 | 27. | 14 % | Veterán MotoGo | `#8B5CF6` fialová |
| 15 | 29. | 15 % | Elitní jezdec | `#A855F7` purpur |
| 16 | 31. | 16 % | Ambasador | `#D946EF` magenta |
| 17 | 33. | 17 % | VIP | `#EF4444` červená |
| 18 | 35. | 18 % | VIP Gold | `#D4AF37` tm. zlato |
| 19 | 37. | 19 % | VIP Platinum | `#F1F5F9` perleť |
| 20 | 39. | 20 % | Legenda MotoGo | gradient `#FFD700→#FF6B00` + záře |

Barvy jdou v rodinách (zelené → kovy → modrofialové → VIP), velké vizuální skoky jsou na hranicích rodin. Odstíny lze při realizaci doladit.

## 3. Zobrazení v appce

1. **Hlavička (MG logo):** `lib/core/widgets/logo_header.dart` (`LogoRow`) + `home_header.dart` — **logo MotoGo24 (`assets/logo.png`) zůstává VŽDY 100% originál 1:1, nikdy se nepřebarvuje ani nedeformuje.** Barva ranku se projeví výhradně **barevným rámečkem/ringem + jemnou září OKOLO loga** (tmavé barvy na tmavé hlavičce `#1A2E22` nefungují, proto světlé/metalické tóny). Level 20 = animovaná zlato-oranžová záře.
2. **Profil:** `profile_screen.dart` — nová **rank karta hned pod headerem** (za ř. 177): název ranku v barvě, % slevy, progress „level X/20", text „Ještě N rezervací do …(Y %)".
3. **Sumarizace rezervace:** `booking/widgets/price_summary.dart` — nový zelený řádek `Věrnostní sleva (Věrný zákazník · 5 %)  −258 Kč` nad CELKEM.
4. **Platba:** `payment_screen.dart` — do insertu rezervace přidat `loyalty_level`, `loyalty_percent`, `loyalty_discount_amount`.

## 4. Doklady (ZF, DP, KF)

Věrnostní sleva = **samostatný záporný řádek** na všech dokladech:
- **ZF + DP**: edge fn `generate-invoice` — řádek „Věrnostní sleva — {název ranku} ({X} %)  −{částka} Kč".
- **KF**: DB trigger `generate_final_invoice_on_complete()` — stejný řádek; matematika Σslužby − ΣDP + Σ|dobropis| = 0 zůstává (sleva snižuje brutto pronájmu stejně jako dnešní `discount_amount`, jen odděleně).

## 5. Backend (návrh — SQL až při realizaci, jen do chatu dle pravidel)

1. **Tabulka `loyalty_levels`** (20 řádků): `level PK, discount_percent, min_booking_order, name, color_hex, translations jsonb`. RLS: public read, admin write. → názvy/barvy laditelné z Velína bez release appky.
2. **Sloupce `bookings`**: `loyalty_level INT`, `loyalty_percent INT`, `loyalty_discount_amount NUMERIC DEFAULT 0` — historicky stabilní pro doklady (rank se časem mění).
3. **RPC `get_loyalty_status()`** (authenticated, SECURITY DEFINER): spočte kvalifikační rezervace → vrátí `{qualifying_count, level, discount_percent, rank_name, color_hex, next_level_at, bookings_to_next}`. Volá appka po loginu + pull-to-refresh profilu.
4. **Server-side validace**: appka dnes insertuje do `bookings` přímo → BEFORE INSERT trigger pro `booking_source='app'` přepočte/ořízne `loyalty_*` proti skutečnému stavu (klientovi se nevěří).
5. **Základ slevy**: pronájem + příslušenství (bez přistavení, bez kauce).

## 6. Velín

- Detail zákazníka (`CustomerProfileTab.jsx`): badge ranku + počet kvalifikačních rezervací.
- Detail rezervace (`BookingDetail.jsx` / `BookingSummary.jsx`): řádek věrnostní slevy.
- Volitelně: správa `loyalty_levels` (názvy/barvy) v CMS sekci.

## 7. Rozhodnutí k potvrzení (s doporučením)

| # | Otázka | Doporučení |
|---|---|---|
| 1 | Co je kvalifikační rezervace? | `completed` app rezervace (storna ne) |
| 2 | Kombinace s promo kódem? | **NE** — použije se výhodnější z obou (ochrana marže) |
| 3 | Kombinace s dárkovým voucherem? | **ANO** — voucher jsou peníze, ne sleva |
| 4 | Základ výpočtu | pronájem + příslušenství, bez přistavení a kauce |
| 5 | Počítají se i app rezervace před spuštěním? | **ANO** — stávající věrní zákazníci startují s rankem |
