# Přistavení / odvoz — complete rule map + calculators as they are today

Research date 2026-11-27, repo `/home/user/Vel-n` at HEAD `33ac9917` (other agents are editing web
texts — line numbers in `pages/katalog-calc.php`, `pages/katalog.php`, `lang/cs.php` may be off by 1–8).
Nothing in the repo was changed.

**Path prefixes used below**

| Prefix | Meaning |
|---|---|
| `S:` | live schema snapshot `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/codes/schema_public.sql` (fetched 2026-11-27 19:16 — authoritative for what is live) |
| `FF:` | live `feature_flags` dump `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/codes/ff.json` (19:44) |
| `W:` | `/home/user/Vel-n/motogo-web-php/` |
| `B:` | prettier-formatted copies of the web's one-line (minified) JS, `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/calc/webjs/` — the repo files are a single line, so evidence is given as `W:js/<file>.js (function)` + the line in the `B:` copy |
| `A:` | `/home/user/Vel-n/Motogo-app-main/motogo-app-flutter/lib/` (Android master; the iOS tree `motogo-app-flutter-ios/lib/` is byte-identical for every file named here — `diff -rq` shows only the intentional platform files) |
| `F:` | `/home/user/Vel-n/supabase/functions/` |
| `ST1..6` | `/home/user/Vel-n/SUPABASE_BACKEND_STATE_<n>.md` |

Terms: **přistavení** = bike brought to the customer's address at pickup; **odvoz / vrácení jinde** =
bike collected at an address at the end. Each side is priced separately.

---

# PART 1 — Rule map

## 1a) Backend (live)

### Columns and where delivery lives

| # | Rule / fact | Evidence |
|---|---|---|
| B1 | `bookings.pickup_method text DEFAULT 'store'`, `pickup_address text`, `return_method text DEFAULT 'store'`, `return_address text`, `delivery_fee numeric(10,2) DEFAULT 0`, `pickup_lat/lng`, `return_lat/lng double precision`, `pickup_time time DEFAULT 09:00`, `return_time text`, `extras_price`, `late_pickup_discount_amount`. There is **no km column** and **no CHECK on the method values**. | `S:1562-1569, 1609-1612, 1624, 1645` |
| B2 | **Two storage conventions.** App: `pickup_method='delivery'` (else `'branch'`), fee in `delivery_fee`, address in `pickup_address`. Web/AI (`create_web_booking`): methods are NOT written (stay `'store'`), fee is a `booking_extras` row named "Přistavení motorky (…)" / "Vrácení motorky (…)", `delivery_fee` stays 0, address in `pickup_address` / `return_address`. Every server rule therefore treats "delivery" as `method='delivery' OR address non-empty`. | `A:features/payment/payment_screen.dart:618-621, 691, 710-721`; `S:11859-11888` (create_web_booking INSERT/UPDATE has no method, no delivery_fee); `ST2:42`; `S:1071-1087` (`_booking_extras_delivery` sums extras by name in 8 languages) |
| B3 | No delivery attribute on `branches` or `motorcycles`. The only discriminator is `branches.type ∈ {'samoobslužná','obslužná'}` (DEFAULT `'samoobslužná'`, CHECK). Helpers: `branch_is_self_service(branch)`, `moto_is_self_service(moto)`, `_is_self_service_booking(booking)`. | `S:25696-25718` (branches), `S:10999-11076` (motorcycles), `S:9435-9449`, `S:17789-17802`, `S:4250-4264` |
| B4 | No delivery rate in `app_settings` / pricing tables. The rate **1 000 Kč + 40 Kč/km** is hard-coded in four places: web `MG._calcDeliveryFee`, app `PriceCalculator.deliveryBase/deliveryPerKm`, app i18n text `deliveryPriceInfo`, SQL `_delivery_fee_floor`. Origin of the route is hard-coded to **Mezná** in all of them. | `B:pages-rezervace-pricing.js:4-6, 314`; `A:features/booking/price_calculator.dart:15-16, 178-186`; `A:core/i18n/translations_cs_pl.dart:375`; `S:2072-2084`; `ST3:126` ("Při změně sazeb na webu/v appce upravit i zde") |

### Price of a NEW booking — who computes, who validates

| # | Rule / fact | Evidence |
|---|---|---|
| B5 | **The delivery fee of a new booking is computed by the CLIENT and trusted by the server.** Web: `create_web_booking` adds `Σ p_extras.unit_price × quantity` to the total without looking at names or distances. App: direct `INSERT INTO bookings` under RLS `user_id = auth.uid()` with client `total_price` / `delivery_fee`. | `S:11812-11817`; `S:33047` (`bookings_user_insert`), `A:features/payment/payment_screen.dart:545-565, 674-760` |
| B6 | `process-payment` floor check deliberately ignores delivery: floor = day prices − provable discounts; "Výbava a doprava se do spodní meze NEpočítají". So a missing/too-low delivery fee is never rejected at payment of a new booking. | `F:process-payment/due-verify.ts:6-15, 30-38, 107-109` |
| B7 | Distance is **never** computed on the server. The route (Mapy.cz `routing/route?routeType=car_fast`) is called from the browser / the app with a hard-coded public key. The server only knows an air-distance **floor** `ROUND(1000 + 40 × max(0, haversine_km_from_Mezná(49.3464, 15.2119) − tolerance))`, without GPS 1000, coordinates > 2000 km away 1000 — and uses it only for EDITS of paid bookings. | `B:pages-rezervace-pricing.js:323-338`; `A:features/booking/price_calculator.dart:30-102`; `S:2072-2084` |
| B8 | DB guard `trg_guard_booking_delivery` (`_guard_booking_delivery` → `_delivery_guard_violation`) is `BEFORE UPDATE` only, and only for customer writes on paid `reserved`/`active` bookings: added side ≥ its floor, removed side refunds at most its share, moved side ≥ floor, active booking → pickup place locked, fee ≥ 0. **Not involved in creating a booking** (INSERT, and web draft `pending` is exempt). | `S:30794`, `S:3852-3900`, `S:2090-2198`; `ST4:73`; `ST3:127` |
| B9 | **No server rule forbids delivery for a self-service bike.** The trigger `trg_check_self_service_delivery` (error `self_service_no_delivery`) and the flag row `self_service_delivery` were proposed on 2026-09-28 ("SQL v chatu, zatím NEaplikováno") and are **not live**: no such trigger/function in the snapshot, no such row in `feature_flags`, no migration file. The rule is enforced only by the clients (which read a missing row as OFF = blocked). | `S:` full trigger list on `bookings` (lines 30422-31154) has no such trigger; `grep self_service_no_delivery S:` = 0 hits; `FF:` has no `self_service_delivery` key; `ST5:102`; `grep -l self_service_delivery supabase/migrations` = none |
| B10 | Flag `feature_flags.delivery_service` ("Přistavení motorky", enabled=true) exists but **nothing reads it** (dead flag). | `FF:`; `grep -rn delivery_service` over web, app, velin, supabase = 0 hits |
| B11 | Other server create paths (`public-api`, `mcp-server`, `ai-public-agent`) pass `delivery_address` / `return_address` to `create_web_booking` with no fee and no branch-type check. (*inferred from the call sites; the agent prompt tells the model not to price delivery itself*) | `F:public-api/index.ts:317-318`, `F:mcp-server/index.ts:316-317`, `F:ai-public-agent/index.ts:1144-1145`, `F:_shared/agent-knowledge/hard-rules.ts:65, 230` |

### Date / time / branch conditions enforced by the server (independent of delivery)

| # | Rule / fact | Evidence |
|---|---|---|
| B12 | Branch closure: a booking whose dates overlap a closure of the **bike's** branch is refused (23514) — delivery does not bypass it. | `S:9885-9945` (`check_booking_branch_open`), trigger `S:30682` |
| B13 | Late-pickup discount = `ROUND(50 % of 1st-day price)` when `pickup_time ≥ 12:00` and ≥ 2 days. It does **not** look at the pickup method → a delivery at ≥ 12:00 gets it too. Client claim is clamped on INSERT/UPDATE. | `S:4909-4934`, `S:24292-24321`, triggers `S:31118, 31122`; `create_web_booking S:11818-11819` |
| B14 | The kiosk 12:00 release gate applies only to pickup AT a self-service branch (`pickup_method <> 'delivery'` and empty address). Gate code is NULL for delivery. | `S:4593-4608` (`_kiosk_release_at`), `S:1114-1122` (`_booking_gate_code`) |
| B15 | Lead time (+6 h for delivery, +1 h staffed branch) is **not** enforced by any DB object — clients only (see W6, A6). | no reference in `S:`; `ST6:95` |
| B16 | No geographic limit, no maximum distance, no country check on the server. | `S:2072-2084` only (floor), nothing else |

### Customer conditions on the server (none is delivery-specific)

| # | Rule / fact | Evidence |
|---|---|---|
| B17 | Web: licence group must cover the bike (`'N'` = kids' bike, no licence), known e-mail must log in, one own overlapping rental (kids' bikes exempt), DOB passed. App: RLS own row only; overlap triggers; loyalty/late triggers. Nothing differs for delivery. | `S:11731-11751, 11796-11800`; triggers `S:30686, 30694, 31114, 31118` |
| B18 | Kids' bikes (`license_required='N'`) and trailers (`is_trailer`) have **no** delivery restriction anywhere. Trailer as an accessory is refused for self-service bikes (`moto_is_self_service`), unrelated to delivery. | `S:10403`, `S:14938` |
| B19 | Gear-only rental (`booking_kind='gear'`) can never have delivery: CHECK `bookings_gear_shape` (`pickup_method/return_method <> 'delivery'`), core returns `gear_no_delivery`. | `S:1678`; `ST3:63` |

### Discounts, VAT, rounding

| # | Rule / fact | Evidence |
|---|---|---|
| B20 | **Loyalty discount (app only) excludes delivery**: trigger base = `total + discount + loyalty − delivery_fee`, cap `ROUND(base × pct/100)`. | `S:24255-24286` |
| B21 | **Percent promo code applies to the whole amount including delivery** (web: `ROUND(v_total × pct/100)` where `v_total` already contains extras = delivery, after the late discount; payment floor: "procento počítané z ceny vč. výbavy a dopravy"). Fixed codes / gift vouchers reduce the remainder, also covering delivery. Max one percent code. | `S:11841-11858`; `F:process-payment/due-verify.ts:10-11, 82` |
| B22 | VAT: operator is not a VAT payer → all prices final, no VAT line. Invoice line "Přistavení / odvoz motorky" from `delivery_fee` (app) or the extras rows (web). | `A:core/i18n/translations_ext_52_v2_catalog_c.dart:99` ("nous ne sommes pas assujettis à la TVA"), `F:generate-invoice/index.ts:619, 671` |
| B23 | Rounding: server floor `ROUND()` to whole Kč; web rounds the fee to whole Kč; app does not round (see D4). | `S:2079`; `B:pages-rezervace-pricing.js:5`; `A:features/booking/price_calculator.dart:184-186` |

### Side effects of a delivery booking (for completeness)

| # | Rule / fact | Evidence |
|---|---|---|
| B24 | Gear stock demand ignores bookings with `pickup_method='delivery'` (gear travels with the bike) — only the app convention matches; web delivery bookings (`'store'` + address) are still counted. | `S:3005-3025` (`_gear_demand`) |
| B25 | Missing-documents reminder is skipped for `pickup_method='delivery'` and for staffed branches. | `S:19632-19641` |
| B26 | Self-service activation gate does not hold a delivered booking (`pickup_method='delivery'` or address) — irrelevant while B9/W1/A1 block delivery there. | `S:2728-2749` |

---

## 1b) Web reservation flow (`/rezervace`)

Files: `W:pages/rezervace.php`, minified cores `W:js/pages-rezervace.js`, `-pricing.js`, `-steps.js`,
wrappers `W:js/pages-rezervace-selfservice.js`, `rezervace-next.js`, `rezervace-dates.js`, `rezervace-v2.js`.

### How the customer enters delivery (step 4 "Místo a čas")

| # | Rule / fact | Evidence |
|---|---|---|
| W-UI1 | Fixed info card "Vyzvednutí v motopůjčovně" (no input), then three independent controls: (1) checkbox card **`#rez-delivery`** "Přistavení motorky jinam" (sub "1 000 Kč + 40 Kč/km od pobočky") → panel `#rez-delivery-panel` with input `#rez-delivery-address`, buttons "Moje poloha" (`.rez-gps-btn[data-rez-gps=delivery]`) and "Mapa" (`MG._openWebMapPicker('delivery')`), route box `#rez-delivery-route-info`, and checkbox **`#rez-return-same-as-delivery`** "Vrátit motorku na stejné adrese" — **checked by default**; (2) checkbox card **`#rez-return-other`** "Vrácení motorky jinde, než kde bylo vyzvednuto" → panel with `#rez-return-address` + GPS + Mapa + `#rez-return-route-info`. Checking (2) unchecks "same as delivery" and vice versa. Return elsewhere is possible **without** delivery. | `B:pages-rezervace.js:172-200` (HTML), `391-426` (handlers); texts `W:lang/cs.php:429-440` |
| W-UI2 | Address autocomplete: Mapy.cz Suggest `GET /v1/suggest?query=…&limit=8&lang=cs` (no country filter), debounce 220 ms, dropdown name + location; picking a row calls `MG._calcRouteFor(type, lat, lng)`; a typed address without picking is geocoded on `change` by `MG._mapySuggest(text, 1)` (first hit). | `B:pages-rezervace-pricing.js:415-438, 439-537, 405-413` |
| W-UI3 | GPS: `navigator.geolocation` → Mapy.cz `rgeocode` → fills the input → route. Map: Leaflet (unpkg) + Mapy.cz tiles full-screen overlay, confirm = centre of the map → rgeocode → route. | `B:pages-rezervace-pricing.js:254-313, 566-694` |
| W-UI4 | With delivery the time field is "Čas převzetí nebo přistavení"; the expected-return-time rule and the self-service 23:59 rule follow `MG._rezApplySelfServiceTimes`. Checking delivery also opens/ticks the rider-gear card (gear is brought along) and refreshes accessory availability with method `delivery`. | `B:pages-rezervace.js:293-332, 393-404, 728-737`; `W:lang/cs.php:425` |

### Eligibility / when the option is disabled

| # | Rule / fact | Evidence |
|---|---|---|
| W1 | **Self-service branch → no delivery, no collection.** `lock = rezIsSelfService() && !flag.enabled`; the bike is `MG._rez.motoId` or `selectedMotoId`; with no bike but a chosen branch (`#rez-branch-dropdown` / `?pobocka=`) the branch type decides; with nothing chosen the option is enabled. When locked: both checkboxes are unchecked (with a `change` event so price/times recalc), disabled, cards get `.mg-ss-locked`, panels hidden, and a collapsed note "ⓘ <title> — Na samoobslužné pobočce zatím není k dispozici" expands to the explanation. Options stay visible. | `W:js/pages-rezervace-selfservice.js:154-208` (rule 187), `108-141` (note), `171-182` (lock) |
| W2 | Flag `feature_flags.self_service_delivery` (anon read through the Supabase client) lifts W1; missing row / read error = OFF. Live: row missing → always blocked. | `W:js/pages-rezervace-selfservice.js:40, 63-86`; `FF:` |
| W3 | URL `?delivery=1` pre-ticks `#rez-delivery` (address empty). A self-service bike then immediately unticks it again via W1 (the core calls `MG._rezApplySelfServiceTimes()` right after, which the wrapper hooks). `?return_delivery=1` is linked from the NL/PL how-to pages but **no code reads it**. | `W:pages/rezervace.php:21, 176`; `B:pages-rezervace.js:758, 1039-1042`; `W:js/pages-rezervace-selfservice.js:229-242`; `W:lang/pages_nl.php:254, 393, 409, 555`, `W:lang/pages_pl.php:254, 393, 409, 555` |
| W4 | No other eligibility rule: kids' bike, trailer-as-bike, guest vs logged-in, category — all may take delivery. | `B:pages-rezervace.js:688-727` (trailer rule only about the trailer accessory); no `isChildMoto` reference near delivery (`grep`) |

### Fee, distance, display

| # | Rule / fact | Evidence |
|---|---|---|
| W5 | `MG._calcDeliveryFee(km) = km is a number > 0 ? Math.round(1000 + 40 × km) : 1000`. Per side. Pickup fee `l` when `#rez-delivery` checked; return fee `c = fee(returnKm)` when `#rez-return-other` checked, else `c = l` when "same as delivery" checked and delivery on. **Default delivery therefore costs 2 × fee.** | `B:pages-rezervace-pricing.js:4-6, 38-47` |
| W5b | Route: origin = `MG._ensureBranchCoords()` = first Suggest hit for the literal "Mezná 9, 393 01 Pelhřimov" (cached); `MG._mapyRouting` = Mapy.cz `routing/route … routeType=car_fast`, km = length / 1000 (one way). No fallback: on failure the red box "Trasu se nepodařilo spočítat. Cena … bude upřesněna ručně (1 000 Kč + 40 Kč/km)" is shown and the fee stays **1 000 Kč** (km unknown). | `B:pages-rezervace-pricing.js:314-338, 350-357, 383-414` |
| W5c | Route box: "Cena přistavení: X", "Nejrychlejší trasa od pobočky Mezná 9, 393 01 Pelhřimov: 12,3 km (~N min jízdy)", "Výpočet: 1 000 Kč + 40 Kč × 12,3 km = X". The page total (`#rez-price-preview`) = `max(0, rental + gear extras + trailer + l + c − late)` − codes. | `B:pages-rezervace-pricing.js:358-379, 16-85` |
| W6 | Lead time `MG._rezValidatePickupTime`: pickup date+time (Prague wall clock) must be ≥ now + **6 h with delivery**, + 1 h for a staffed branch without delivery, + 0 h self-service. Checked at submit (`alert`) and by the v2 "Pokračovat" guide. | `B:pages-rezervace-pricing.js:101-138`; `B:pages-rezervace-steps.js:72-74`; `W:js/rezervace-next.js:58-65`; texts `W:lang/cs.php:547-549` |
| W7 | Late-pickup discount `MG._latePickupDiscount` (≥ 12:00, ≥ 2 days, round(50 % of day 1)) is independent of delivery; subtracted before the percent code. | `B:pages-rezervace-pricing.js:7-15, 48-52` |
| W8 | Percent promo code = `round(u × pct / 100)` where `u` already includes both delivery fees → delivery is discounted. Voucher is capped by the rental only on the client (`l − v`), the server recomputes. | `B:pages-rezervace-pricing.js:52-61, 193-204` |
| W8b | The live price counts delivery as soon as the box is ticked, before any address: `MG._calcDeliveryFee(undefined)` = 1 000 Kč, and another 1 000 Kč for the pre-ticked "same address" return → ticking shows +2 000 Kč until a route replaces it. | `B:pages-rezervace-pricing.js:4-6, 38-47` |
| W9 | Address is required only softly: v2 look's guide refuses to continue while delivery is ticked and the address empty (`rez.pickup.deliveryAddr`); the core submit itself treats "ticked + empty address" as **no delivery** (no fee, no address). | `W:js/rezervace-next.js:62-63`; `B:pages-rezervace-steps.js:94-98, 107` |

### What is sent to the backend

| # | Rule / fact | Evidence |
|---|---|---|
| W10 | `create_web_booking(… p_delivery_address = text of #rez-delivery-address or null, p_return_address = return address / same address / null, p_pickup_time, p_return_time, p_extras = […, {name: "Přistavení motorky (1 000 Kč + 40 Kč × 12,3 km)", unit_price: fee}, {name: "Vrácení motorky (…)", unit_price: fee}] …)`. No coordinates, no km field, no method. The extras' names are localized (`rez.gear.item.delivery/return`) and are matched by `_booking_extras_delivery` — **the wording of those two keys must not change**. | `B:pages-rezervace-steps.js:94-124, 171-229, 245`; `S:1071-1087`; `W:lang/cs.php:502-503` |
| W10b | `/upravit-rezervaci` loads the same `pages-rezervace-pricing.js` for its Mapy.cz helpers (after pre-creating `MG._rez`) — the core is already used outside the booking form. | `W:pages/upravit-rezervaci.php:264-269, 285` |
| W11 | Form state survives step changes in `sessionStorage['mg_rez_form']` (logged-in only); it stores `deliveryAddr/returnAddr` for the recap but the form does not restore the delivery controls from it. | `B:pages-rezervace-steps.js:362-381, 1299-1310`; `B:pages-rezervace.js:885-913` |

### Info page / FAQ texts (owner-facing promises)

| # | Text | Evidence |
|---|---|---|
| W-T1 | "Motorku přivezeme kamkoliv v České republice – přímo z naší provozovny v Mezné u Pelhřimova. Přistavení nabízíme u motorek z obslužné pobočky v Mezné; motorky ze samoobslužné pobočky ve Velkých Němčicích se přebírají jen přímo na pobočce." | `W:data/pristaveni-content-1.php:7` |
| W-T2 | Price list: 500 Kč loading + 500 Kč unloading + 20 Kč per km there **and back** (= 1 000 + 40 × one-way km). Example 30 km → 2 200 Kč. | `W:data/pristaveni-content-2.php:62-70` |
| W-T3 | FAQ: "Nad 100 km cenu kalkulujeme individuálně." — **not implemented anywhere** (forms price any distance automatically). FAQ: "Přistavíte i motorku z Velkých Němčic? Ne." FAQ: return elsewhere = "svoz dle vzdálenosti od Pelhřimova". | `W:data/pristaveni-content-2.php:80-89` |
| W-T4 | CTA of the info page → `/rezervace` (CS) or `/rezervace?delivery=1` (NL, PL overlays). Other-language page texts come from `lang/pages_<lang>.php` and DB overlays `app_settings pages_overlay.*`. | `W:data/pristaveni-content-2.php:103`; `W:lang/pages_nl.php:254`; `supabase/migrations/20261112t16_owner_texts_overlay_pristaveni_vyzvednuti.sql:12` |
| W-T5 | AI knowledge: a Mezná bike is never "delivered" to the Velké Němčice branch; staffed-branch handover happens 1–6 h after payment. | `F:_shared/agent-knowledge/branch-gate.ts:28`; `F:_shared/agent-knowledge/company-brain.ts:31` |

---

## 1c) App reservation flow (both looks; route `/booking`)

Live form = `A:core/booking_form_widget.dart` (state + normalizations, both looks), sections
`booking_form_pickup_section.dart`, `booking_form_return_section.dart`, v2 view
`A:features/booking/v2/booking_form_view_v2.dart` + `sections/handover_v2.dart`.

### How the customer enters delivery

| # | Rule / fact | Evidence |
|---|---|---|
| A-UI1 | Two independent sections "Vyzvednutí motorky" and "Vrácení motorky", each with two radio rows: "Na pobočce" (sub = "Mezná 9, Pelhřimov" or the self-service branch address from DB; "zdarma") and "Přistavení na tvoji adresu" / "Odvoz z tvojí adresy" (sub "1 000 Kč + 40 Kč/km", trailing "od 1 000 Kč"). Draft fields `pickupMethod`/`returnMethod` ∈ `'store'`/`'delivery'`, default `'store'` for both → **one side only unless the customer picks both**. | `A:core/booking_form_pickup_section.dart:44-88, 90-131`; `A:core/booking_form_return_section.dart:44-89`; `A:features/booking/v2/sections/handover_v2.dart:32-92`; `A:features/booking/booking_models.dart:16-27, 59-60`; `A:core/i18n/translations_cs_pl.dart:372-376`, `translations_ext_53_v2_booking_a.dart:20-23` |
| A-UI2 | With "na adresu" selected an address row opens the shared bottom sheet `showAddrBottomSheet`: text field with Mapy.cz Suggest (`locality=cz`, limit 8; fallback Nominatim `countrycodes=cz`), quick options (address of the other side, address from profile), GPS (`GpsService` → rgeocode), map picker (`launchMapPicker` → `MapPickerScreen`), a status line "~N km · price", POTVRDIT. The sheet reports `onDistCalc(km, fee)` then `onSave(city, street)`. | `A:features/booking/booking_ui_helpers.dart:252-279` (entry), `338-472` (suggest), `474-550` (pick), `552-656` (GPS), `660-683` (map), `685-694` (`_showDist`), `697-761` (confirm); `A:features/booking/map_launcher.dart:16-102` |
| A-UI3 | "Nothing typed twice" (owner 2026-10-22): choosing "na adresu" on a side without its own address copies the other side's address **and fee**; saving an address also fills the other side while that side has none; afterwards the sides are independent (two different addresses possible). Note "Stejná jako u přistavení". | `A:core/booking_address_carry.dart:26-93, 124-152` |
| A-UI4 | Under the address: "~N km · fee" from `pickupDistKmProvider` / `pickupDelivFeeProvider` (return likewise) — four global `StateProvider`s. | `A:features/booking/booking_provider.dart:25-35`; `A:features/booking/v2/sections/handover_v2.dart:155-176` |

### Eligibility

| # | Rule / fact | Evidence |
|---|---|---|
| A1 | **Self-service branch → no delivery, no collection**: `selfServiceDeliveryBlocked(branchType, flagEnabled) = branchType == 'samoobslužná' && !flagEnabled`. `NULL`/unknown branch type = treated as staffed (allowed). The option is replaced by `BookingLockedOptionTile` (lock, "Na samoobslužné pobočce zatím není k dispozici", tap expands the explanation); it stays visible. | `A:core/booking_rules.dart:20-22, 136-143`; `A:core/booking_form_widget.dart:445-448`; `A:core/booking_form_locked_option.dart:6-48`; texts `A:core/i18n/translations_ext_24_selfservice.dart:6-7` |
| A2 | Flag `self_service_delivery` via `selfServiceDeliveryEnabledProvider` (missing row / error = false). | `A:core/feature_flags.dart:27-42` |
| A3 | Normalization: while blocked, a draft that still says `'delivery'` (carried from another bike, flag flipped) is reset to `'store'` for **both** sides after the frame. | `A:core/booking_form_widget.dart:449-457` |
| A4 | A draft carried to **another bike** keeps the handover (methods + addresses) only when both bikes are on the same branch; otherwise both sides go back to `'store'` and the four fee providers are zeroed. Same bike → whole draft kept. | `A:features/booking/v2/booking_carry_v2.dart:58-60, 71-82, 93-96`; `A:features/booking/booking_entry.dart:77-84` |
| A5 | No other eligibility rule (kids' bike, trailer-as-bike, rank) — delivery is offered for every bike of a staffed/unknown-type branch. Customer gates of the form are not delivery-specific: logged-in only; profile address always + licence number/expiry unless the bike is `'N'`; licence expiry ≥ end of rental; licence group covers the bike; no own overlapping rental (kids' bikes exempt); min/max rental days; consents (guardian for kids' bikes). | `A:features/booking/booking_provider.dart:212-352`; `A:features/booking/booking_validator.dart:9-103`; `A:core/booking_form_widget.dart:537-557` |

### Fee, distance, display

| # | Rule / fact | Evidence |
|---|---|---|
| A6 | Lead time `BookingValidator.checkPickupLeadTime`: pickup date+time (device local clock; default 09:00) must be after now + **6 h for delivery**, + 1 h staffed branch, + 0 otherwise. Error `validationDeliveryLeadTime` blocks the CTA. | `A:features/booking/booking_validator.dart:105-157`; `A:features/booking/booking_provider.dart:280-304`; text `A:core/i18n/translations_ext_5_validation.dart:10` |
| A7 | `PriceCalculator.calcDeliveryFee(km) = 1000 + km × 40` — **not rounded**, per side. | `A:features/booking/price_calculator.dart:177-186` |
| A7b | Distance `routeKmFromBranch(lat, lng)` from the constant Mezná point (49.3464, 15.2119): 1) Mapy.cz `routing/route car_fast` (8 s), 2) OSRM `router.project-osrm.org` (10 s), 3) straight line without coefficient (or 50 km). Address → coordinates: `geocodeNearestToBranch` (Mapy.cz geocode `locality=cz`, 8 candidates, nearest to Mezná); with no coordinates at all `estimateKm(city)` (table of ~30 towns, default 50 km). | `A:features/booking/price_calculator.dart:10-16, 30-102, 116-158, 326-347` |
| A8 | Price = `PriceCalculator.calculate`: `fullBase = (rental − late) + extras + pickupFee + returnFee`; **loyalty base = (rental − late) + extras (no delivery)**; promo percent = `round((fullBase − loyalty) × pct/100)` (delivery included); fixed codes capped at the remainder; total clamped ≥ 0. Fees enter only when the method is `'delivery'`. | `A:features/booking/price_calculator.dart:197-280, 297-323`; `A:features/booking/booking_provider.dart:49-70` |
| A9 | Late-pickup discount = round(50 % of day 1) when `pickupTime ≥ 12:00` and ≥ 2 days — independent of delivery. | `A:features/booking/price_calculator.dart:234-243, 282-290` |
| A10 | Price section rows "Přistavení (N km × 40 + 1 000) +fee" and "Odvoz (…) +fee" when > 0. | `A:features/booking/v2/sections/price_v2.dart:48-55, 94-97`; `A:core/booking_form_price_section.dart:74-82` |
| A11 | Missing address is **not** a blocker: with "na adresu" and no address the v2 dock only hints "Chybí adresa přistavení – doprava se přičte"; the CTA works, fee 0. | `A:features/booking/v2/booking_form_view_v2.dart:243-254, 389-401`; `A:core/i18n/translations_ext_63_e_fix_order.dart:8-9` |
| A12 | Self-service details that depend on delivery: return time is hidden only for return AT a self-service branch; the kiosk 12:00 gate text applies only without delivery. | `A:core/booking_rules.dart:47-67, 145-148`; `A:core/booking_form_widget.dart:465-483` |

### What is sent to the backend

| # | Rule / fact | Evidence |
|---|---|---|
| A13 | Direct insert: `pickup_method` = `'delivery'` or `'branch'`, `pickup_address = draft.pickupAddress` (**street part only**, see D8), same for return, `delivery_fee = pickupFee + returnFee`, `pickup_lat/lng`, `return_lat/lng` from the draft (**always null for a new booking** — the address sheet never hands coordinates back, see D9), `total_price`, `extras_price`, `discount_amount`, `loyalty_*`, `late_pickup_discount_amount`, `booking_source='app'`. | `A:features/payment/payment_screen.dart:618-621, 674-760`; `grep pickupLat A:` (no writer in the new-booking path) |
| A14 | The app already maps the (non-existent) DB error `self_service_no_delivery` to a readable message. | `A:features/payment/payment_screen.dart:877-882` |

---

## 1d) Differences web × app × backend (risks)

| # | Difference | Web | App | Backend | Consequence for the calculator |
|---|---|---|---|---|---|
| D1 | Self-service rule enforcement | client only (W1) | client only (A1) | **nothing live** (B9); flag row missing | Calculator must use each platform's own rule function; a wrong calculator can never be caught by the server. |
| D2 | Default return when delivery is chosen | "same address" ticked → **2 × fee** (W5) | sides independent → **1 × fee** (A-UI1) | — | Each calculator must mirror its own form, otherwise calculator ≠ form total. |
| D3 | Return collection without delivery | possible (`#rez-return-other`) | possible (return section) | — | Calculator needs both sides, not one toggle. |
| D4 | Fee rounding | `Math.round` whole Kč | none (e.g. 12.345 km → 1 493,80 Kč stored, shown rounded) | floor `ROUND` | Same address can differ by < 1 Kč between platforms; app totals can carry haléře. |
| D5 | Route origin | geocoded text "Mezná 9, 393 01 Pelhřimov" (first Suggest hit, at runtime) | constant 49.3464, 15.2119 | constant 49.3464, 15.2119 | Small km differences web × app for the same address. |
| D6 | Routing failure | fee = 1 000 Kč, "upřesníme ručně" | OSRM → straight line → town table / 50 km | — | Different price for the same address when Mapy.cz is down. |
| D7 | Geography | Suggest without country filter (foreign addresses offered); text promises "v ČR" | Suggest + geocode `locality=cz`; GPS/map unrestricted | none; FAQ ">100 km individuálně" not implemented (W-T3) | No hard limit exists to reuse — the calculator can only follow the form. |
| D8 | Stored address | full text "name, location" | street only — `bookings.pickup_address = draft.pickupAddress`, the town (`pickupCity`) is not written anywhere (*read from code, not tested live*) | — | Existing app gap; not caused by the calculator, but carry must hand over city **and** street like the form holds them. |
| D9 | Stored coordinates | none | none for new bookings (always null) | floor without GPS = 1 000 Kč | Edits later use the weakest floor. Not in scope. |
| D10 | Storage convention | method `'store'` + address, fee in `booking_extras`, `delivery_fee = 0` | method `'delivery'`, fee in `delivery_fee` | handles both (B2) but `_gear_demand`, docs reminder, `_gate_obsluzna_activation` partly test the method only (B24–B26) | Not in scope; do not "unify" in this task. |
| D11 | Lead-time clock | Europe/Prague | device local time | none (B15) | Customer abroad can get a different answer in app vs web. |
| D12 | Address required | v2 guide yes, core submit silently drops delivery (W9) | no, proceeds with fee 0 and method `'delivery'` (A11) | no INSERT guard | Calculator should never carry "delivery without an address" as a priced item. |
| D13 | Loyalty | not applicable (app only) | excludes delivery (A8) | trigger excludes delivery (B20) | consistent |
| D14 | Percent code | includes delivery (W8) | includes delivery (A8) | includes delivery (B21) | consistent (calculators have no codes) |
| D15 | Price texts | info page "500 + 500 + 20 Kč/km tam i zpět" | "1 000 Kč + 40 Kč/km" | — | same amount, two wordings |
| D16 | Dead/unused switches | `?return_delivery=1` linked, not read (W3) | — | `feature_flags.delivery_service` unused (B10) | `return_delivery` can be given a meaning by the calculator carry. |
| D17 | Docs vs live | — | — | ST5:102 says the self-service trigger is "navrženo"; ST4/ST3 describe guards as live — matches the snapshot. `ST3:138` RPC `get_accessory_availability` is still called by the web under the (OFF) flag `inventory_v2` although removed. | none |

---

# PART 2 — The calculators today

## 2a) Web

Look switch: `landingV2Enabled()` — v2 for all 8 languages (`LANDING_V2_LANGS`), `?landing=v1` forces the
old look, a language without `lang/v2/<lang>/katalog.php` falls back to v1 (`W:landing.php:17-44`).
**The calculator exists only in the v2 look.**

| Entry point | Where | Inputs | Price | Shows | Hand-over to `/rezervace` |
|---|---|---|---|---|---|
| **K1 Catalog calculator "Spočítat cenu"** | `/katalog` (and category pages), second tab of the `.km` switch "Najít motorku / Spočítat cenu" (`W:pages/katalog.php:18-19, 543`; `W:pages/katalog-v2-ui.php:159-173`); block `renderKatalogCalc` (`W:pages/katalog-calc.php:157-197`) | ① branch radio (All / each branch with "s obsluhou" / "samoobsluha nonstop"), ② bike `<select>` ("Jakákoli volná motorka" allowed), ③ date range in a calendar with per-day list prices and availability from RPC `get_moto_booked_dates` | **Client formula** `K.breakdown` = Σ `price_<dow>` (fallback `price_weekday`) per day incl. both ends; late saving `K.late` = round(50 % day 1) for ≥ 2 days — documented as a mirror of `MG.calcPriceBreakdown` / `MG._latePickupDiscount`, not a call (`W:js/landing-calc-core.js:1-6, 28-38`) | receipt: dates, bars, rows per weekday, "Celkem za pronájem", average/day, ½ info "Vyzvedni od 12:00 … Čas vyzvednutí zvolíš v rezervaci", includes chips, min/max-days warning; without a bike: list of bikes free in the range with totals (`W:js/landing-calc-view.js:97-146`) | `<a href>` built by `X.href()`: `/rezervace?moto=<id>&start=<iso>&end=<iso>`; without a bike `?pobocka=<branch>&start=&end=` (`W:js/landing-calc.js:41-46`); mobile sticky bar uses the same href (`:166-176`). **No delivery, no time, no storage.** |
| **K2 Detail calculator "Vyber si termín"** | `/katalog/<id>` in v2 look: same component with `ctx:'detail'`, bike pre-selected, no branch step (`W:pages/katalog-detail.php:10-11, 393-397`; `W:pages/katalog-detail-v2.php:56`) | date range | same as K1 | same receipt | same `X.href()` |
| K3 Card button "Spočítat cenu" | on catalog cards; sets the bike in K1 and scrolls to it (`W:js/landing-calc.js:211-224`) | — | — | — | via K1 |
| K4 Catalog date filter (not a calculator, but a price view) | v2 catalog cards show "N dní · total" for the filtered range (`K.breakdown`) and the card button links `/rezervace?moto=&start=&end=` (`W:js/landing-catalog-dates.js:89-104`) | date range of the filter | `K.breakdown` | total per card | URL params |
| K5 v1 detail calendar | `/katalog/<id>` in v1 look: availability calendar + button `/rezervace?moto=&start=&end=` — **no price** (`W:pages/katalog-detail.php:≈403-408, ≈585-591`) | date range | — | — | URL params |
| `engage.php` / `js/engage.js` | funnel counter only: `MGEngage.track('calc')` when the calculator shows a total (`W:js/landing-calc.js:147`, `W:js/engage.js:4-5, 49`) — no price logic | | | | |

How `/rezervace` pre-fills: PHP validates `moto`, `start`, `end` (ISO, end ≥ start), `delivery`, `resume`,
`pobocka` and exposes `window.REZERVACE_PARAMS` (`W:pages/rezervace.php:11-26, 172-179`); the core seeds
`MG._rez` with them, `?delivery=1` ticks `#rez-delivery` (`B:pages-rezervace.js:753-760, 884, 1039-1042`);
`W:js/rezervace-dates.js` re-validates the dates against today/availability/min-max days and collapses step 2
into a summary with "Změnit" — if the range is no longer valid the step simply stays open
(`W:js/rezervace-dates.js:30-39, 54-62, 99-125`); `W:js/rezervace-dayprice.js` only paints day prices into
the form's calendar. Texts of the calculator: CS defaults `kcDefaults()` (`W:pages/katalog-calc.php:13-72`)
← `W:lang/v2/<lang>/katalog.php` (7 files) ← Velín CMS `web.landing_katalog.*`.

## 2b) App

The calculator is an owner-approved **v2 addition** (V21: "v app by měla být i kalkulačka ceny, stejně jako
web"; `DESIGN_V22.md` 5.0.1 "Spočítat přesnou cenu … předvyplní kalkulačku jen motorkou"). **The old look
has no calculator** (no reference to `CalcBodyV2` / `calcStateProvider` outside `features/**/v2`).

| Entry point | Where | Inputs | Price | Shows | Hand-over to `/booking` |
|---|---|---|---|---|---|
| **C1 Motorky tab, mode "Spočítat cenu"** | `MotorkyScreenV2` mode switch (`A:features/catalog/v2/catalog_mode.dart`, `catalog_mode_switch_v2.dart:75-88`, `motorky_screen_v2.dart:111-116, 218`) → `CalcBodyV2` | ① branch chips, ② bike picker sheet, ③ `AvailabilityCalendar` with the bike's booked days, **④ "Předání a výbava" = info only** ("Čas a místo vyzvednutí, výbavu i velikosti zvolíš až v rezervaci…") (`A:features/catalog/v2/calc/calc_body_v2.dart:193-240`; `A:core/i18n/translations_ext_59_v2_late_info.dart:7`) | `quoteFor(moto, start, end, loyalty)` = **the booking form's own `PriceCalculator.calculate`** with the arguments of a fresh draft: no extras, `pickupDeliveryFee: 0`, `returnDeliveryFee: 0`, no codes, rank discount, no pickup time (`A:features/booking/booking_quote.dart:12-31`; `calc_body_v2.dart:136-137`) | receipt (bars, rows per day price, rental, ½ row, loyalty row, total, VAT note) `calc_receipt_v2.dart:49-104`; dark total with average/day, rank saving, ½ info (`q12`), CTA "REZERVOVAT · price" `calc_total_v2.dart:55-134`; sticky dock `calc_sticky_v2.dart`; without a bike the free-bike list `calc_free_list_v2.dart` | `startBookingFromSelection(context, ref, moto, start, end)` (`calc_body_v2.dart:148`) |
| C2 Home row "Spočítat přesnou cenu" | `homeOpenCalculator` pre-fills bike and/or range, opens C1 (`A:features/home/v2/home_links.dart:24-31`, `home_calc_row_v2.dart:38-43`) | — | — | — | via C1 |
| C3 Detail "Tvoje jízda" card | per-bike price for the picked range (`detail_trip_card_v2.dart`, `moto_detail_view_v2.dart:106-110`, `catalog_price.dart:38-60`) | date range | `quoteFor` | total, struck list price, ½ info | detail CTA → `startBookingFromSelection` (`A:features/catalog/moto_detail_page.dart:142`) |
| C4 Catalog cards / Home funnel | totals for the shared date range (`catalog_price.dart:47-60`, `home_funnel_cta.dart:64, 122`) | shared range | `quoteFor` | total | `startBookingFromSelection` |

Calculator state: `CalcState {branchId, motoId, start, end}` in memory, never touches the booking draft
until REZERVOVAT; dates are written through to the catalog filter; a paid booking resets bike and dates
(`A:features/catalog/v2/calc/calc_state.dart:17-83`; `catalog_mode_sync.dart`). "No pickup time here (owner
2026-10-22)".

Hand-over `startBookingFromSelection` (`A:features/booking/booking_entry.dart:27-91`): builds a fresh
`BookingDraft` (bike, dates, gear sizes from profile); old look → the fresh draft replaces everything; v2 →
`carryBookingDraft` keeps the in-progress draft (same bike: everything but codes/consents/trailer; other
bike: times, note, sizes, and the handover only on the same branch — rule A4), zeroes the four delivery fee
providers when the draft is fresh or the handover was dropped, then `ctx.push('/booking')`. **The pickup
time is deliberately not passed; nothing about delivery is passed either** — the form then applies its
normalizations (A3 and friends) to whatever arrived.
