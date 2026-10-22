# Výpůjčka výbavy bez motorky — zadání pro appku (Android + iOS)

Stav k 2026-10-23: backend je hotový (migrace `20261023a`–`e`, edge funkce, Velín, web `/pujceni-obleceni`, kiosek 1.3.0).
Appka výpůjčku výbavy zatím neumí. Tento soubor je zadání pro agenta appky: co a kde změnit v obou stromech.
Zdroj pravdy kontraktů: `SUPABASE_BACKEND_STATE_*`. Pravidla majitele: viz „Pravidla“ níže.

## 0. Pravidla práce
- Každou změnu udělej v **obou stromech** (`motogo-app-flutter` = Android master, `motogo-app-flutter-ios`) a ověř je
  přes `diff -rq lib/` (CLAUDE.md). Soubory, které se mezi stromy **už teď liší**, portuj ručně:
  `reservation_detail_screen.dart`, `reservation_edit_screen.dart`, `widgets/res_detail_tab_content.dart`,
  `widgets/res_access_codes_card.dart`, `widgets/res_pickup_procedure.dart`, `widgets/res_cancel_dialog.dart`,
  `messages/ai_agent_screen.dart`, `documents/contracts_screen.dart`, `core/app_shell.dart`. Android navíc obsahuje
  `booking_restore.dart`; iOS má obnovu přímo v detailu.
- **Android má navíc UI v2** (`features/*/v2`, přepínač `app_v2_ui` → `V2Switch` v `core/router.dart`). Výpůjčka výbavy
  musí fungovat v v1 (oba stromy) i v v2 (jen Android). Logiku proto drž v modelu a providerech, ne ve widgetech.
- iOS má ve `pubspec` starší balíčky — používej jen API, které s nimi funguje.
- Nové texty patří do NOVÉHO souboru `core/i18n/translations_ext_59_gear.dart`, a to v obou stromech, v 8 jazycích
  a s tykáním. Soubor zaregistruj v `_mergeAll` v `translations.dart`. Hlavní soubory `translations_*` (iOS má navíc
  `cardsSavedAtCheckout`) měň jen kvůli textům `refund*` (§6).

## 1. Pravidla majitele (závazná)
- Výpůjčka výbavy je řádek `bookings` s `booking_kind='gear'`, `moto_id=NULL` a pobočkou v `branch_id`. Má stejné
  stavy jako motorka: pending → reserved → active → completed/cancelled.
  **Rozlišuj podle `booking_kind`**, nikdy podle `moto_id == null`: FK `ON DELETE SET NULL` dává `moto_id NULL`
  i staré rezervaci motorky.
- Doklady: **jen doklad totožnosti** (OP líc + rub, nebo pas) a datum narození (18+). ŘP se nevyžaduje.
- Samoobslužná pobočka (Velké Němčice): po zaplacení a schváleném dokladu dostane zákazník **jen kód šatny**
  (`code_type='accessories'`) a kód schránky s klíčem od brány. Kód motorky ani kóje neexistují.
  Postup: šatna → zavřít dveře → protokol na displeji, kde se upraví velikosti a připojí podpis. Identitou je
  kód šatny.
  Vrácení: zavřít šatnu → otázka „Vracíš všechnu výbavu?“ → Ano = rezervace se hned dokončí.
- Obslužná pobočka (Mezná): výbavu předává a přebírá obsluha.
- Výpůjčka výbavy se smí krýt s jinou rezervací téhož zákazníka. Neplatí na ni věrnostní body ani sleva, promo kódy
  ani kód VRACENI. Dárkový poukaz platí.
- Vratka při zkrácení (pro **všechny** rezervace, §6) se počítá z hodin od teď do **aktuálního** začátku rezervace,
  tedy do času vyzvednutí v Praze před změnou:
  - ≥ 168 h → 100 %
  - ≥ 48 h → 50 %
  - jinak 0 % z ceny odebraných dní
  - strop po posunu (`capAfterMove`) zůstává.

## 2. Viditelnost: `app_visible` a staré verze
- RESTRICTIVE RLS skrývá gear řádky před přímým `select`/realtime zákazníka, dokud Velín nezapne
  `app_settings.gear_rental.app_visible`. Přepínač je ve Velíně: Flotila → Půjčení oblečení → „Zobrazit v aplikaci“.
  Dokud je vypnutý, staré verze appky výpůjčku výbavy nevidí, a proto ji ani špatně nevykreslí.
- **Nová appka nesmí na `app_visible` záviset.** Gear rezervace načítá RPC `get_my_gear_bookings()` (authenticated;
  vrací jen vlastní rezervace, nejnovější první). Výsledek se sloučí s tabulkovým selectem a deduplikuje podle `id`.
  Když RPC chybí (starý backend), použije se prázdný seznam.
- Realtime stream nad `bookings` gear změny při vypnutém `app_visible` nedoručí. Seznam se proto musí znovu načíst:
  - po návratu appky do popředí,
  - po pull-to-refresh,
  - po pushi `door_codes`/`message`,
  - po každé akci nad gear rezervací.
- Pořadí vydání:
  1. vydat appku v obou obchodech;
  2. zvýšit minimální verzi (`update_check_provider`);
  3. teprve potom zapnout `app_visible`.
  Stejný přepínač řídí, jestli AI agenti tvrdí, že výbavu jde objednat i v appce (`get_gear_rental_offer.app_available`).

## 3. RPC a edge kontrakty (vše už existuje)
| Účel | Volání |
|---|---|
| Moje výpůjčky výbavy | `get_my_gear_bookings()` → `[{id, booking_number, status, payment_status, start_date, end_date, days, pickup_time, return_time, branch:{id,name,address,city,type}, lines:[{key,kind,label,includes,sizes,price_per_day,total}], per_day, total, voucher_amount, docs:{required,ok,missing[]}, codes_released, can_pay, customer_name, customer_email, restricted, created_at}]` |
| Detail jedné | `get_web_gear_booking(p_booking_id, p_session_id)` (stejný tvar; `{error:'not_found'}`) |
| Ceník | `gear_rental_prices` (veřejný SELECT aktivních; `translations[lang].label`), nastavení `app_settings.gear_rental` (`enabled`, `max_days`, `max_ahead_days`) |
| Volné kusy | `get_gear_rental_availability(p_branch_id, p_start, p_end)` → `{enabled:false}` / `{enabled:true, sizes:{helmet:{"M":2}}}` |
| Živá cena | `quote_gear_booking(p_branch_id, p_start, p_end, p_items:[{key,size}], p_voucher_code)` |
| Založení | `create_web_gear_booking(p_branch_id, p_start, p_end, p_items, p_customer, p_pickup_time, p_return_time, p_lang, p_note, p_voucher_code, p_existing_booking_id, p_password, p_consents)`. Přihlášený uživatel: `p_customer.email` = e-mail účtu, jinak `email_mismatch`. `p_consents` = `{vop:true, gdpr:true}`. Chyby: `disabled, bad_branch, branch_closed, bad_dates, too_long, too_many, no_items, bad_item, duplicate_item, bad_size, out_of_stock, below_minimum, bad_voucher, consents_required` |
| Platba | `process-payment` `{booking_id, amount, type:'booking', mode:'intent'}` jako u motorky (`stripe_service.createPaymentIntent`) — **ověř na stagingu, že intent pro `booking_kind='gear'` projde** (EDGE-B řešil checkout pro web) |
| Doklady | `check_booking_docs_status_for(p_booking_id)` (NULL = OK, jinak důvod); upload jako dnes, jen doklad totožnosti |
| Kódy / brána | `branch_door_codes` (u gear jen `accessories`), `release_my_door_codes(p_booking_id)`, `get_booking_gate_info(p_booking_id)` (gear: pobočka z rezervace, `released` = jakýkoli odeslaný kód) |
| Velikosti | `customer_update_gear_sizes(p_booking_id, p_sizes:{helmet:'L',…})` — zdarma, stejné kusy, jen pending/reserved a do začátku |
| Odebrat kus | `customer_remove_gear_item(p_booking_id, p_key)` — vratka dle §1 |
| Termín | `reschedule_booking_free(…, p_source:'app')`, `apply_booking_changes(…, p_dry_run)`, `extend_booking`, `shorten_booking_with_refund` — gear-aware: cena = `gear_per_day` × dny, kontrola skladu a zavřené pobočky (`out_of_stock`, `branch_closed`), jakákoli změna motorky = `gear_no_moto` |
| Storno | `cancel_booking_tracked(p_booking_id, p_reason)` |

**Gear řádek nikdy neměň přímým `update`.** Guard trigger takovou změnu odmítne (`gear_booking_rpc_only`) a RLS ji
zablokuje. Pozor na `reservation_edit_screen.dart`: dnes ukládá změny bez doplatku přes `from('bookings').update()`
(Android ř. ~1161) — pro gear použij RPC výše.

## 4. Model a načítání
- `reservation_provider.dart` `_bookingSelect`: přidat `booking_branch:branches!branch_id(name, address, city, gps_lat, gps_lng, type)`.
  Do `_fetchBookings` přidat sloučení s `get_my_gear_bookings()` (§2).
- `reservation_models.dart`:
  - nová pole `bookingKind`, `gearLines`, `gearPerDay` a getter `isGearOnly` (`bookingKind == 'gear'`);
  - pobočka se bere z motorky, jinak z `booking_branch`. Díky tomu u gear fungují `isSelfService`, `_branchHandover`
    a `issuedAt`;
  - `motoName` pro gear = `tr('gearBookingTitle')` („Výpůjčka výbavy“);
  - nový `Reservation.fromGearRpc(json)` mapuje tvar z §3. Velikosti bere z `lines[].sizes` do `helmetSize`…`bootsSize`.
- `booking_number` = posledních 8 znaků `id` (`shortId`) beze změny.

## 5. UI — co zobrazit a co skrýt u `isGearOnly`
| Místo (soubor) | Změna |
|---|---|
| `widgets/reservation_card.dart`, `home/widgets/home_reservation_card.dart`, `reservations_screen.dart`, v2 `reservation_card_v2.dart` | Titulek „Výpůjčka výbavy“, ikona výbavy (ne motorka ani fotka), souhrn kusů („Komplet bez bot (M, L, L, M) · boty 43“), pobočka |
| `reservation_detail_screen.dart`*, `widgets/res_detail_tab_content.dart`*, v2 `res_detail_view_v2.dart`/`res_detail_hero_v2.dart` | Kusy s velikostmi, cena/den, pobočka a adresa z rezervace. Navigace na GPS pobočky, ne na fallback Mezné (`booking/price_calculator.dart:15-16`). Bez kategorie, SPZ, km, sekce jízd a hodnocení jízdy |
| `widgets/res_access_codes_card.dart`*, v2 `res_codes_v2.dart` | Jediný řádek `accessories` → štítek „Kód šatny“. Hint „protokol nejdřív“ u kódu šatny (`accessories && sent && isSelfService && !protocolSigned`) s gear textem |
| `booking_gate_provider.dart` | Refetch sleduje u gear odeslaný kód `accessories` (dnes `motorcycle`) |
| `widgets/res_pickup_procedure.dart`*, v2 `res_procedure_v2.dart` | Gear kroky: brána (stávající `procStep1*`) → `gearProcStep2` → `gearProcStep3` → `gearProcReturn`, bez kroku motorky. Obslužná pobočka: `gearStaffedPickup` |
| SOS: `reservation_models.dart` `sosAllowed`, `sos/sos_provider.dart` | `sosAllowed` = false pro gear; `_findActiveBookingId` a `_findMotoId` gear ignorují (žádné SOS FAB/tlačítko) |
| `routes/ride_recorder_watcher.dart` `_activeBookingId`, `routes/routes_provider.dart` (pickupOrigin) | Gear přeskočit (žádný záznam jízd) |
| `booking/booking_validator.dart` `checkOverlap` | `if (res.isGearOnly) continue;` (překryv je povolený) |
| `widgets/reservation_swap_section.dart`, `reservation_edit_moto_section.dart`, sekce extras, `bookedDatesProvider` (edit ř. ~1395/1424) | U gear nevolat a nezobrazovat |
| Obnova zrušené (`booking_restore.dart` Android / detail iOS) | U gear skrýt (`customer_restore_booking` gear zatím neumí) |
| `reservation_provider.dart` `hasActiveReservationProvider` (zámek souhlasů/oprávnění) | Doporučení: gear nezamyká, zámek je kvůli GPS a SOS u motorky. **Potvrdit s majitelem** |
| Doklady: `core/app_shell.dart`* (docs FAB, v2 shell), obrazovka dokladů, `res_docs_v2.dart` | U gear jen doklad totožnosti, stav z `check_booking_docs_status_for`; kroky ŘP skrýt |
| `documents/contracts_screen.dart`* | U gear „Smlouva o nájmu výbavy“ (generate-document vybere `gear_rental_contract`), bez polí motorky a bez fallbacku „Mezná 9“ |
| Zprávy/push | Zprávy s kódy ke gear mají `booking_id` a titulek „Výpůjčka výbavy — kódy“. Proklik na detail je volitelný |

(* = soubor se mezi stromy liší)

**Nové klíče** (`translations_ext_59_gear.dart`, cs, tykání; další jazyky přeložit):
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
**Gear záložky** (`reservation_edit_screen.dart`*, v2 `res_edit_*_v2.dart`):
- Posun: `reschedule_booking_free`.
- Prodloužení: náhled přes `apply_booking_changes(p_dry_run:true)` → `net_diff`. Doplatek platí stávajícím
  extension flow; částku a `change` ber ze serveru, ne z `EditPriceCalc`.
- Zkrácení: `shorten_booking_with_refund`.
- Velikosti: `customer_update_gear_sizes`. Na samoobslužné pobočce platí limity kiosku z `booking/self_service_gear.dart`
  (pobočka rezervace).
- Odebrat kus: `customer_remove_gear_item`.
- Storno.
- Přidat kus: jen `gearAddItemContact`.

Výměna motorky, místo vyzvednutí a doplňky motorky se u gear skryjí.

**Vratka pro všechny rezervace** — dnes se počítá k NOVÉMU startu, nově k AKTUÁLNÍMU startu v čase vyzvednutí
(Praha):
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
- Kde se `StornoCalc.effectiveRefundPercent(newStart ?? booking.startDate, …)` nahradí `StornoCalc.bookingRefundPercent(booking)`:
  - `reservation_edit_price_calc.dart:169-170` (`stornoPercent`);
  - `reservation_edit_screen.dart` `_buildStornoWarning` (Android ~474-477, iOS ~472-475) a `stornoPct` (Android ~1549-1551);
  - kvůli shodě s `cancel_booking_tracked`, který počítá k času vyzvednutí, také `res_cancel_dialog.dart:26-27`
    a `reservations_screen.dart:249-250` (částka = `totalPrice * pct / 100`).

  Android v2 se opraví samo: `res_edit_view_v2.dart` dostává `stornoPct` z edit screenu
  a `res_edit_price_v2.dart` bere `calc.stornoPercent`.
- **Texty `refund100/50/0`**. Dnes v nich stojí „nový konec je za …“ (např. `translations_cs_pl.dart:779-781`,
  `translations_en_de_nl.dart:482`, `translations_ext_7_fill.dart`, `translations_uk_main.dart`), v obou stromech.
  Nové znění:
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
2. Termín od–do (`max_days`, `max_ahead_days`, zavření pobočky).
3. Kusy a velikosti:
   - samoobslužná pobočka: jen limity kiosku (`self_service_gear.dart`);
   - volné kusy z `get_gear_rental_availability`.
4. Živá cena (`quote_gear_booking`).
5. Dárkový poukaz (ne promo, ne věrnost).
6. Souhlasy VOP a GDPR.
7. `create_web_gear_booking` s údaji z profilu.
8. Platba (§3).
9. Doklad totožnosti (pokud `docs.required && !docs.ok`).
10. Potvrzení a detail rezervace.

Nezaplacený koncept se znovu použije přes `p_existing_booking_id`. Žádný přímý INSERT do `bookings` — RLS ho zakáže.

## 8. AI agent v appce (`messages/ai_agent_screen.dart`*)
- V těle požadavku na `ai-moto-agent` posílej `supports_gear: true` (vedle `supports_images`). Podle toho agent ví,
  že tahle verze výpůjčku výbavy zobrazuje. Bez příznaku posílá zákazníka na web.
- `_fetchActiveBooking`: jako `booking_id` přednostně posílej aktivní nebo nejbližší rezervaci **motorky**
  (do selectu přidej `booking_kind`). Výpůjčku výbavy posílej, jen když jinou rezervaci zákazník nemá. Server stejně
  dá přednost motorce a gear rezervaci popíše bez motorky a bez SOS.

## 9. Testy (oba stromy)
- Model: `fromJson` gear s `booking_branch` → `isSelfService`, `motoName`; `fromGearRpc`; `sosAllowed == false`.
- `booking_validator`: gear neblokuje motorku.
- `StornoCalc.bookingRefundPercent`:
  - hranice 168 h a 48 h;
  - čas vyzvednutí v Praze přes přechod letního času;
  - výchozí čas 09:00;
  - strop po posunu.
- Widget testy: karta a detail gear (titulek, kód šatny, žádné SOS ani výměna).
- `flutter analyze` v obou stromech a `diff -rq lib/` jen se záměrnými rozdíly.
