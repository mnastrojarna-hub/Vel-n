# Výpůjčka výbavy bez motorky — zadání pro appku (Android + iOS), část 2/2

Úpravy rezervace, sjednocená vratka §1.11 (pro VŠECHNY rezervace), objednání v appce, AI agent a testy.
Část 1/2 (pravidla práce, pravidla majitele, `app_visible`, RPC kontrakty, model, UI): `GEAR_RENTAL_APP.md` —
platí i tady, hlavně §0 (`diff -rq` obou `lib/` PŘED portováním, rozdílné soubory ručně) a §3 (RPC).
Hvězdička (*) = soubor se mezi stromy k 2026-10-22 liší.

## 5b. Nové texty k UI (část 1, §5)
Soubor `core/i18n/translations_ext_59_gear.dart` (oba stromy, 8 jazyků, tykání; níže cs):
- `gearBookingTitle` „Výpůjčka výbavy“
- `gearItems` „Výbava“
- `gearPerDay` „{price} Kč / den“
- `lockerCode` „Kód šatny“
- `gearProtocolFirst` „Po zavření šatny na displeji uprav velikosti a podepiš protokol — potvrdíš ho kódem šatny.“
- `gearProcStep2` „Na displeji zadej kód šatny, vezmi si výbavu a zavři dveře šatny.“
- `gearProcStep3` „Na displeji uprav velikosti podle toho, co sis vzal, a podepiš předávací protokol kódem šatny.“
- `gearProcReturn` „Vrácení: tentýž kód šatny, výbavu vrať do šatny, zavři dveře a na displeji potvrď, že vracíš všechno — výpůjčka se tím hned ukončí.“
- `gearStaffedPickup` „Výbavu ti předá obsluha v čase vyzvednutí, doklad totožnosti zkontroluje na místě.“
- `gearAddItemContact` „Přidat kus do zaplacené výpůjčky zatím nejde online — ozvi se nám a přidáme ho.“
- `gearDocsIdOnly` „K výpůjčce výbavy stačí doklad totožnosti — řidičák nepotřebuješ.“
- `gearRentCta` „Půjčit jen výbavu“

## 6. Úpravy rezervace + sjednocená vratka (§1.11, VŠECHNY rezervace)
**Gear záložky** (`reservation_edit_screen.dart`*, v2 `res_edit_*_v2.dart`). Gear řádek se nikdy neukládá přímým
`update` (část 1, §3):
- Posun (stejná délka): `reschedule_booking_free(p_booking_id, p_new_start, p_new_end, p_source:'app')`.
- Prodloužení: náhled `apply_booking_changes(p_dry_run:true)` → doplatek `net_diff` (a `new_total`) ze serveru, ne
  z `EditPriceCalc`. Zaplacení stávajícím extension flow (`PaymentFlowType.extension` → `process-payment` → webhook
  zapíše nový termín; `gear_lines` přepočítá trigger `_gear_lines_follow_days`). U gear je `change` JEN
  `{p_new_start, p_new_end[, p_new_pickup_time], new_total, _base}` — klíče DB sloupců (dnešní `start_date`/`end_date`
  z `reservation_edit_screen.dart`) → `process-payment` 409 `change_not_applicable`, `reason:'gear_app_format'`
  (text dle `reason`, část 1 §3). **Ověř na stagingu, že webhook
  u `booking_kind='gear'` změnu aplikuje** — EDGE-B ověřoval jen web. `extend_booking` nevolat (jen service_role).
- Zkrácení: `shorten_booking_with_refund(p_booking_id, p_new_start, p_new_end, p_reason)`; náhled vratky
  `apply_booking_changes(p_dry_run:true)` (`refund_amount`, `storno_pct`).
- Velikosti: `customer_update_gear_sizes`. Na samoobslužné pobočce platí limity kiosku z `booking/self_service_gear.dart`
  (pobočka rezervace).
- Odebrat kus: `customer_remove_gear_item(p_booking_id, p_key, p_dry_run)` — nejdřív `p_dry_run:true` (náhled vratky),
  pak `false`.
- Storno: `cancel_booking_tracked`.
- Přidat kus: jen text `gearAddItemContact`.

Výměna motorky, místo vyzvednutí a doplňky motorky se u gear skryjí.

**Vratka pro všechny rezervace** — dnes se počítá k NOVÉMU startu (edit) / ke dni začátku (storno), nově vždy
k AKTUÁLNÍMU startu (před změnou) v čase vyzvednutí, Praha:
- `reservation_models.dart` `StornoCalc`: přidej
  ```dart
  /// §1.11: storno % = hodiny od TEĎ do AKTUÁLNÍHO začátku (před změnou) v čase vyzvednutí, Europe/Prague
  /// (bez času 09:00) — zrcadlo SQL shorten_booking_with_refund / _apply_booking_changes_core / cancel_booking_tracked.
  static DateTime startInstant(Reservation r) {
    final d = pragueWallClock(r.startDate);                       // core/booking_rules.dart
    final hm = (r.pickupTime ?? '09:00').split(':');
    return pragueToUtc(d.year, d.month, d.day, int.tryParse(hm[0]) ?? 9, int.tryParse(hm.length > 1 ? hm[1] : '0') ?? 0);
  }
  static int bookingRefundPercent(Reservation r) {
    final h = startInstant(r).difference(DateTime.now().toUtc()).inHours;
    final base = h >= 168 ? 100 : h >= 48 ? 50 : 0;
    final cap = capAfterMove(r);
    return base < cap ? base : cap;
  }
  ```
- Kde se `StornoCalc.effectiveRefundPercent(…)` nahradí `StornoCalc.bookingRefundPercent(booking)` (a částka
  `effectiveRefundAmount(…)` = `totalPrice * pct / 100`):
  - `reservation_edit_price_calc.dart:169-170` (`stornoPercent`; oba stromy);
  - `reservation_edit_screen.dart`* `_buildStornoWarning` (Android ~474-477, iOS ~472-475) a `stornoPct`
    (jen Android ~1549-1551);
  - kvůli shodě s `cancel_booking_tracked` (počítá k času vyzvednutí) také `widgets/res_cancel_dialog.dart`*
    (Android :26-27, iOS :24-25) a `reservations_screen.dart:249-250` (oba stromy).

  Ověř grepem `StornoCalc\.` v obou `lib/`, že jiné volání nezbylo. Android v2 se opraví samo:
  `res_edit_view_v2.dart` dostává `stornoPct` z edit screenu a `res_edit_price_v2.dart` bere `calc.stornoPercent`.
- **Texty `refund100/50/0`** — dnes v nich stojí „nový konec je za …“ (`translations_cs_pl.dart`* ř. ~779-781
  a pl ~1409, `translations_en_de_nl.dart`* ~482, `translations_ext_7_fill.dart` (de/es/fr/nl),
  `translations_uk_main.dart`* ~778-780), v obou stromech. Nové znění:
  - cs: „Vrácení 100 % – do začátku rezervace zbývá 7 a více dní“ / „Vrácení jen 50 % – do začátku rezervace zbývá 2–7 dní“ / „Vrácení 0 % – do začátku rezervace zbývá méně než 2 dny“
  - en: „100% refund – the booking starts in 7+ days“ / „50% refund only – the booking starts in 2–7 days“ / „0% refund – the booking starts in less than 2 days“
  - de: „100 % Erstattung – bis zum Mietbeginn sind es 7+ Tage“ / „Nur 50 % Erstattung – bis zum Mietbeginn sind es 2–7 Tage“ / „0 % Erstattung – bis zum Mietbeginn sind es weniger als 2 Tage“
  - es: „Reembolso del 100 % – faltan 7+ días para el inicio de la reserva“ / „Solo reembolso del 50 % – faltan 2–7 días para el inicio de la reserva“ / „Reembolso del 0 % – faltan menos de 2 días para el inicio de la reserva“
  - fr: „Remboursement de 100 % – la réservation commence dans 7 jours ou plus“ / „Remboursement de 50 % seulement – la réservation commence dans 2 à 7 jours“ / „Remboursement de 0 % – la réservation commence dans moins de 2 jours“
  - nl: „100% restitutie – de reservering begint over 7+ dagen“ / „Slechts 50% restitutie – de reservering begint over 2–7 dagen“ / „0% restitutie – de reservering begint over minder dan 2 dagen“
  - pl: „Zwrot 100% – do rozpoczęcia rezerwacji zostało 7+ dni“ / „Zwrot tylko 50% – do rozpoczęcia rezerwacji zostało 2–7 dni“ / „Zwrot 0% – do rozpoczęcia rezerwacji zostało mniej niż 2 dni“
  - uk: „Повернення 100% – до початку бронювання 7+ днів“ / „Повернення лише 50% – до початку бронювання 2–7 днів“ / „Повернення 0% – до початку бронювання менше ніж 2 дні“

## 7. Objednání v appce (nový flow)
Vstup `gearRentCta` „Půjčit jen výbavu“: umístění (home / katalog / pobočka) **rozhodne majitel**, nevymýšlet bez něj.

Kroky:
1. Pobočka (aktivní a `is_open`).
2. Termín od–do (`max_days` — výchozí 30, `max_ahead_days` — výchozí 400, zavření pobočky).
3. Kusy a velikosti: samoobslužná pobočka jen limity kiosku (`self_service_gear.dart`); volné kusy
   z `get_gear_rental_availability`.
4. Živá cena (`quote_gear_booking`).
5. Dárkový poukaz (ne promo, ne věrnost).
6. Souhlasy VOP a GDPR.
7. `create_web_gear_booking` s údaji z profilu (pozor: RPC dnes zapisuje `booking_source='web'` — appku od webu
   nerozliší; případný parametr zdroje je otevřený bod backendu).
8. Platba (část 1, §3).
9. Doklad totožnosti (pokud `docs.required && !docs.ok`).
10. Potvrzení a detail rezervace.

Nezaplacený koncept se znovu použije přes `p_existing_booking_id`. Žádný přímý INSERT do `bookings` — RLS ho zakáže.

## 8. AI agent v appce (`messages/ai_agent_screen.dart`*)
- V těle požadavku na `ai-moto-agent` posílej `supports_gear: true` (vedle `supports_images`). Podle toho agent ví,
  že tahle verze výpůjčku výbavy zobrazuje. Bez příznaku posílá zákazníka na web.
- `_fetchActiveBooking`: jako `booking_id` přednostně posílej aktivní nebo nejbližší rezervaci **motorky**
  (do selectu přidej `booking_kind`). Výpůjčku výbavy posílej, jen když jinou rezervaci zákazník nemá. Server stejně
  dá přednost motorce, gear rezervaci popíše bez motorky a u kontextu jen s výbavou SOS tlačítko nenabídne
  (`suggest_sos` vždy false).

## 9. Testy (oba stromy)
- Model: `fromJson` gear s `booking_branch` → `isSelfService`, `motoName`; `fromGearRpc`; `sosAllowed == false`.
- `booking_validator`: gear neblokuje motorku.
- `StornoCalc.bookingRefundPercent`: hranice 168 h a 48 h; čas vyzvednutí v Praze přes přechod letního času;
  výchozí čas 09:00; strop po posunu.
- Widget testy: karta a detail gear (titulek, kód šatny, žádné SOS ani výměna).
- `flutter analyze` v obou stromech a `diff -rq lib/` jen se záměrnými rozdíly.
