# Výpůjčka výbavy bez motorky — zadání pro appku (Android + iOS), část 1/2

Stav k 2026-10-23: backend je hotový (migrace `20261023a`–`e`, edge funkce, Velín, web `/pujceni-obleceni`, kiosek 1.3.0).
Appka výpůjčku výbavy zatím neumí. Tento soubor je zadání pro agenta appky: co a kde změnit v obou stromech.
**Část 2/2** (úpravy rezervace, sjednocená vratka §1.11, objednání v appce, AI agent, testy): `GEAR_RENTAL_APP_EDIT.md`.
Zdroj pravdy kontraktů: `SUPABASE_BACKEND_STATE_*`. Pravidla majitele: viz §1.

## 0. Pravidla práce
- Každou změnu udělej v **obou stromech** (`motogo-app-flutter` = Android master, `motogo-app-flutter-ios`) a na konci
  ověř `diff -rq` obou `lib/` (CLAUDE.md).
- **Než začneš portovat, spusť** `diff -rq motogo-app-flutter/lib motogo-app-flutter-ios/lib`. Každý soubor z výstupu,
  na který sáhneš, portuj **ručně** (změnu přenes, soubor nikdy nekopíruj přes druhý strom — přepsal bys iOS/Android
  specifika). Rozdílů je hodně (k 2026-10-22 cca 120 souborů), mimo jiné v `features/reservations/`:
  `reservation_detail_screen.dart`, `reservation_edit_screen.dart` a ve `widgets/`: `cancel_result_dialog`,
  `edit_reservation_calendar`, `res_access_codes_card`, `res_cancel_dialog`, `res_detail_card`, `res_detail_row`,
  `res_detail_tab_content`, `res_location_row`, `res_modification_history`, `res_payment_details_tab`,
  `res_pickup_procedure`, `res_rating_card`, `reservation_edit_calendar_section`, `reservation_edit_confirm_page`,
  `reservation_edit_extras_section`, `reservation_edit_states`, `reservation_edit_widgets`; dále `core/app_shell.dart`,
  `core/router.dart`, `core/booking_form_*`, `features/documents/*` (vč. `contracts_screen`, `documents_screen`,
  `docs_gate_widgets`), `features/home/home_screen.dart`, `features/messages/*` (vč. `ai_agent_screen`) a hlavní
  soubory `translations_*`. Jen v Androidu: `features/*/v2`, `core/v2`, `core/shell_*.dart`,
  `features/reservations/res_actions.dart`, `features/home/home_actions.dart`. Seznam ber jen jako orientaci —
  platí aktuální výstup `diff -rq`.
- `features/reservations/booking_restore.dart` (obnova zrušené rezervace) je v **obou** stromech stejný; volá se
  z `reservations_screen.dart`, `reservation_detail_screen.dart`, `widgets/res_detail_tab_content.dart`
  a v Androidu navíc z `v2/reservations_screen_v2.dart` a `v2/res_coted_v2.dart`.
- **Android má navíc UI v2** (`features/*/v2`, přepínač `app_v2_ui` → `V2Switch` v `core/router.dart`). Výpůjčka výbavy
  musí fungovat v v1 (oba stromy) i v v2 (jen Android). Logiku proto drž v modelu a providerech, ne ve widgetech.
- iOS má ve `pubspec` starší balíčky — používej jen API, které s nimi funguje.
- Nové texty patří do NOVÉHO souboru `core/i18n/translations_ext_59_gear.dart`, a to v obou stromech, v 8 jazycích
  a s tykáním. Soubor zaregistruj v `_mergeAll` v `translations.dart`. Hlavní soubory `translations_*` (iOS má navíc
  `cardsSavedAtCheckout`) měň jen kvůli textům `refund*` (část 2, §6).

## 1. Pravidla majitele (závazná)
- Výpůjčka výbavy je řádek `bookings` s `booking_kind='gear'`, `moto_id=NULL` a pobočkou v `branch_id`. Má stejné
  stavy jako motorka: pending → reserved → active → completed/cancelled.
  **Rozlišuj podle `booking_kind`**, nikdy podle `moto_id == null`: FK `ON DELETE SET NULL` dává `moto_id NULL`
  i staré rezervaci motorky.
- Doklady: **jen doklad totožnosti** (OP líc + rub, nebo pas) a datum narození (18+). ŘP se nevyžaduje.
- Samoobslužná pobočka (Velké Němčice): po zaplacení a schváleném dokladu dostane zákazník **jen kód šatny**
  (`code_type='accessories'`) a kód schránky s klíčem od brány. Kód motorky ani kóje neexistují.
  Postup: šatna → zavřít dveře → protokol na displeji (úprava velikostí + podpis). Identitou je kód šatny.
  Vrácení: zavřít šatnu → otázka „Vracíš všechnu výbavu?“ → Ano = rezervace se hned dokončí.
- Obslužná pobočka (Mezná): výbavu předává a přebírá obsluha.
- Výpůjčka výbavy se smí krýt s jinou rezervací téhož zákazníka. Neplatí na ni věrnostní body ani sleva, promo kódy
  ani kód VRACENI. Dárkový poukaz platí.
- Vratka při zkrácení (pro **všechny** rezervace) se počítá z hodin od teď do **aktuálního** začátku rezervace
  (čas vyzvednutí v Praze, před změnou): ≥ 168 h → 100 %, ≥ 48 h → 50 %, jinak 0 % z ceny odebraných dní; strop po
  posunu (`capAfterMove`) zůstává. Implementace: část 2, §6.

## 2. Viditelnost: `app_visible` a staré verze
- RESTRICTIVE RLS skrývá gear řádky před přímým `select`/realtime zákazníka, dokud Velín nezapne
  `app_settings.gear_rental.app_visible` (Flotila → Půjčení oblečení → „Zobrazit v aplikaci“). Dokud je vypnutý,
  staré verze appky výpůjčku výbavy nevidí, a proto ji ani špatně nevykreslí.
- **Nová appka nesmí na `app_visible` záviset.** Gear rezervace načítá RPC `get_my_gear_bookings()` (authenticated;
  jen vlastní, nejnovější první). Výsledek se sloučí s tabulkovým selectem a deduplikuje podle `id`. Když RPC chybí
  (starý backend), použije se prázdný seznam.
- Realtime nad `bookings` gear změny při vypnutém `app_visible` nedoručí → seznam znovu načti po návratu do popředí,
  po pull-to-refresh, po pushi `door_codes`/`message` a po každé akci nad gear rezervací.
- Pořadí vydání: 1) appka v obou obchodech; 2) zvýšit minimální verzi (`update_check_provider`); 3) teprve potom
  zapnout `app_visible`. Týž přepínač řídí, jestli AI agenti tvrdí, že výbavu jde objednat i v appce
  (`get_gear_rental_offer.app_available`); vypnutý → „objednej na webu, brzy i v aplikaci“.
- **Objednání v appce (vstup `gearRentCta`, část 2 §7) zobrazuj JEN při `app_settings.gear_rental.app_visible=true`**
  (a `enabled`; veřejné čtení) — appka i AI se řídí týmž přepínačem. Zobrazení vlastních gear rezervací (RPC) na něm nezávisí.

## 3. RPC a edge kontrakty (vše už existuje; volá přihlášený zákazník)
| Účel | Volání |
|---|---|
| Moje výpůjčky výbavy | `get_my_gear_bookings()` → `[{id, booking_number, status, payment_status, start_date, end_date, days, pickup_time, return_time, branch:{id,name,address,city,type}, lines:[{key,kind,label,includes,sizes,price_per_day,total}], per_day, total, voucher_amount, docs:{required,ok,missing[]}, codes_released, can_pay, customer_name, customer_email, restricted, created_at}]` |
| Detail jedné | `get_web_gear_booking(p_booking_id, p_session_id)` (stejný tvar; `{error:'not_found'}`) |
| Ceník | `gear_rental_prices` (veřejný SELECT aktivních; `translations[lang].label`), nastavení `app_settings.gear_rental` (`enabled`, `max_days` — výchozí 30, `max_ahead_days` — výchozí 400) |
| Volné kusy | `get_gear_rental_availability(p_branch_id, p_start, p_end)` → `{enabled:false}` / `{enabled:true, sizes:{helmet:{"M":2}}}` |
| Živá cena | `quote_gear_booking(p_branch_id, p_start, p_end, p_items:[{key,size}], p_voucher_code)` |
| Založení | `create_web_gear_booking(p_branch_id, p_start, p_end, p_items, p_customer, p_pickup_time, p_return_time, p_lang, p_note, p_voucher_code, p_existing_booking_id, p_password, p_consents)`. Přihlášený: `p_customer.email` = e-mail účtu, jinak `email_mismatch`. `p_consents` = `{vop:true, gdpr:true}`. Chyby: `disabled, bad_branch, branch_closed, bad_dates, too_long, too_many, no_items, too_many_items, bad_item, duplicate_item, bad_size, out_of_stock, below_minimum, bad_voucher, consents_required` |
| Platba | `process-payment` `{booking_id, amount, type:'booking', mode:'intent'}` jako u motorky (`stripe_service.createPaymentIntent`) — **ověř na stagingu, že intent pro `booking_kind='gear'` projde** (EDGE-B řešil checkout pro web) |
| Doklady | `check_booking_docs_status_for(p_booking_id)` (NULL = OK, jinak důvod); upload jako dnes, jen doklad totožnosti |
| Kódy / brána | `branch_door_codes` (u gear jen `accessories`), `release_my_door_codes(p_booking_id)`, `get_booking_gate_info(p_booking_id)` (gear: pobočka z rezervace, `released` = jakýkoli odeslaný kód) |
| Velikosti | `customer_update_gear_sizes(p_booking_id, p_sizes:{helmet:'L',…})` — zdarma, stejné kusy, jen pending/reserved a do začátku |
| Odebrat kus | `customer_remove_gear_item(p_booking_id, p_key, p_dry_run)` — `p_dry_run:true` = náhled vratky; vratka dle §1 |
| Termín | `reschedule_booking_free(p_booking_id, p_new_start, p_new_end, p_source:'app')`, `apply_booking_changes(…, p_dry_run)` (náhled doplatku/vratky), `shorten_booking_with_refund(p_booking_id, p_new_start, p_new_end, p_reason)` — gear-aware: cena = `gear_per_day` × dny, kontrola skladu a zavřené pobočky (`out_of_stock`, `branch_closed`), jakákoli změna motorky = `gear_no_moto`. **`extend_booking` appka volat NESMÍ** (jen service_role — prodloužení s doplatkem jde přes platbu, viz část 2 §6) |
| Storno | `cancel_booking_tracked(p_booking_id, p_reason)` |

**Gear řádek nikdy neměň přímým `update`.** Guard trigger takovou změnu odmítne (`gear_booking_rpc_only`) a RLS ji
zablokuje. Pozor na `reservation_edit_screen.dart`: dnes ukládá změny bez doplatku přes `from('bookings').update()`
(Android ř. ~1161, iOS ~1159) — pro gear použij RPC výše.

**Doplatek úpravy gear** (`process-payment` `type:'extension'`, `change`): jen klíče `p_new_*` jako parametry
`apply_booking_changes` (`p_new_start`, `p_new_end`, `p_new_pickup_time`) + `_base` / `new_total`. Klíč s názvem DB
sloupce (`start_date`, `total_price`… — dnešní app formát) i smíšený payload → HTTP 409 `{code:'change_not_applicable',
reason:'gear_app_format'}`. Další `reason`: `gear_no_moto`, `gear_sizes_free` (velikosti zdarma přes RPC), `out_of_stock`,
`branch_closed`, `too_long`, `gear_no_delivery`. `PaymentErrorMapper`: `change_not_applicable` + známý `reason` → gear
hláška podle `reason`, bez `reason` beze změny (motorky). Web: `ER._payErr` v `pages-upravit-rezervaci-gearbk.js`.
**Platí i pro „stávající extension flow“ z části 2 §6:** dnešní `reservation_edit_screen.dart` posílá v `change`
`start_date`/`end_date` → u gear by platba vždy skončila `gear_app_format`; pro gear sestav `change` jen z `p_new_*`.

## 4. Model a načítání
- `reservation_provider.dart` `_bookingSelect`: přidat `booking_kind, gear_lines, gear_per_day` a
  `booking_branch:branches!branch_id(name, address, city, gps_lat, gps_lng, type)`. Do `_fetchBookings` přidat sloučení
  s `get_my_gear_bookings()` (§2).
- `reservation_models.dart`: nová pole `bookingKind`, `gearLines`, `gearPerDay` a getter `isGearOnly`
  (`bookingKind == 'gear'`); pobočka z motorky, jinak z `booking_branch` (pak u gear fungují `isSelfService`,
  `_branchHandover` a `issuedAt`); `motoName` pro gear = `tr('gearBookingTitle')` („Výpůjčka výbavy“); nový
  `Reservation.fromGearRpc(json)` mapuje tvar z §3 (velikosti z `lines[].sizes` do `helmetSize`…`bootsSize`).
- `booking_number` = posledních 8 znaků `id` (`shortId`) beze změny.

## 5. UI — co zobrazit a co skrýt u `isGearOnly`
| Místo (soubor) | Změna |
|---|---|
| `widgets/reservation_card.dart`, `home/widgets/home_reservation_card.dart`, `reservations_screen.dart`, v2 `reservation_card_v2.dart` | Titulek „Výpůjčka výbavy“, ikona výbavy (ne motorka ani fotka), souhrn kusů („Komplet bez bot (M, L, L, M) · boty 43“), pobočka |
| `reservation_detail_screen.dart`*, `widgets/res_detail_tab_content.dart`*, `widgets/res_detail_card.dart`*, v2 `res_detail_view_v2.dart`/`res_detail_hero_v2.dart` | Kusy s velikostmi, cena/den, pobočka a adresa z rezervace. Navigace na GPS pobočky, ne na fallback Mezné (`booking/price_calculator.dart:15-16`). Bez kategorie, SPZ, km, sekce jízd a hodnocení jízdy (`res_rating_card.dart`*) |
| `widgets/res_access_codes_card.dart`*, v2 `res_codes_v2.dart` | Jediný řádek `accessories` → štítek „Kód šatny“. Hint „protokol nejdřív“ u kódu šatny (`accessories && sent && isSelfService && !protocolSigned`) s gear textem |
| `booking_gate_provider.dart` | Refetch sleduje u gear odeslaný kód `accessories` (dnes `motorcycle`) |
| `widgets/res_pickup_procedure.dart`*, v2 `res_procedure_v2.dart` | Gear kroky: brána (stávající `procStep1*`) → `gearProcStep2` → `gearProcStep3` → `gearProcReturn`, bez kroku motorky. Obslužná pobočka: `gearStaffedPickup` |
| SOS: `reservation_models.dart` `sosAllowed`, `sos/sos_provider.dart` | `sosAllowed` = false pro gear; `_findActiveBookingId` a `_findMotoId` gear ignorují (žádné SOS FAB/tlačítko) |
| `routes/ride_recorder_watcher.dart` `_activeBookingId`, `routes/routes_provider.dart` (pickupOrigin) | Gear přeskočit (žádný záznam jízd) |
| `booking/booking_validator.dart` `checkOverlap` | `if (res.isGearOnly) continue;` (překryv je povolený) |
| `widgets/reservation_swap_section.dart`, `reservation_edit_moto_section.dart`, sekce extras (`reservation_edit_extras_section.dart`*), `bookedDatesProvider` (edit ř. ~1395/1424) | U gear nevolat a nezobrazovat |
| Obnova zrušené (`booking_restore.dart`, oba stromy; volání viz §0) | U gear skrýt (`customer_restore_booking` gear zatím neumí) |
| `reservation_provider.dart` `hasActiveReservationProvider` (zámek souhlasů/oprávnění) | Doporučení: gear nezamyká, zámek je kvůli GPS a SOS u motorky. **Potvrdit s majitelem** |
| Doklady: `core/app_shell.dart`* (docs FAB, v2 shell), `documents/documents_screen.dart`*, `documents/docs_gate_widgets.dart`*, `res_docs_v2.dart` | U gear jen doklad totožnosti, stav z `check_booking_docs_status_for`; kroky ŘP skrýt |
| `documents/contracts_screen.dart`* | U gear „Smlouva o nájmu výbavy“ (generate-document vybere `gear_rental_contract`), bez polí motorky a bez fallbacku „Mezná 9“ |
| Zprávy/push | Zprávy s kódy ke gear mají `booking_id` a titulek „Výpůjčka výbavy — kódy“. Proklik na detail je volitelný |

(* = soubor se mezi stromy k 2026-10-22 liší — portuj ručně; ověř aktuálním `diff -rq`)

Texty (nové klíče `gearBookingTitle`, `lockerCode`, `gearProc*`…): `GEAR_RENTAL_APP_EDIT.md` §5b.

Pokračování: `GEAR_RENTAL_APP_EDIT.md`.
