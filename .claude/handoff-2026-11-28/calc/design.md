# Calculator with delivery ("přistavení") — implementation design

Companion to `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/calc/delivery_rules.md`
(rule numbers B*, W*, A*, D* refer to it). Path prefixes: `W:` = `motogo-web-php/`,
`A:` = `Motogo-app-main/motogo-app-flutter/lib/` (every app change is made identically in
`Motogo-app-main/motogo-app-flutter-ios/lib/`), `B:` = beautified copies of the minified web cores in
`/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/calc/webjs/`.

## 0. Principle and scope

1. **The calculator never owns a rule or a formula.** On each platform it calls the reservation form's
   own functions for (a) "may this bike be delivered", (b) address → distance, (c) distance → fee,
   (d) total. Where the form's code cannot be called as it is, the smallest piece is extracted into a
   shared function that the form itself then calls too (listed per platform below).
2. **The reservation form stays the judge.** Whatever the calculator hands over is re-validated and
   re-priced by the form with its existing code (self-service lock, route, lead time, availability).
   A stale or invalid hand-over can only fall back to "na pobočce", never to a wrong price.
3. **Each platform mirrors its own form**, including the differences D2 (web: return on the same
   address pre-ticked = 2 × fee; app: sides independent) — otherwise calculator total ≠ form total.
4. **Time is still chosen only in the form** (owner 2026-10-22). The calculator gets the *place*
   (pickup at branch / delivery, return at branch / collection), nothing else. No extras, no codes.
5. **No backend change** (section 3).
6. Not touched: gear-only rental (`/pujceni-obleceni`, app gear order), reservation edit, old app look
   (it has no calculator), v1 web look (it has no calculator), `map_picker.dart` and the other
   `userAgentPackageName` files, app dependencies.

Where the option appears:

| Platform | Calculator | Gets delivery? |
|---|---|---|
| Web | K1 catalog "Spočítat cenu" and K2 detail "Vyber si termín" — one component (`renderKatalogCalc`) | **yes, both** (same code; see open question Q3) |
| Web | K4 card totals of the date filter, K5 v1 calendar | no (not calculators) |
| App | C1 Motorky → "Spočítat cenu" (`CalcBodyV2`), reached also from Home (C2) | **yes** |
| App | C3 detail "Tvoje jízda", C4 card / funnel totals | no (open question Q3) |

---

## 1. Web

### 1.1 Shared sources (what the calculator calls)

| Need | Source of truth (already used by `/rezervace`) | How the calculator gets it |
|---|---|---|
| Fee | `MG._calcDeliveryFee(km)` — `W:js/pages-rezervace-pricing.js` (`B:…-pricing.js:4-6`) | load that file on calculator pages. **Precedent:** `/upravit-rezervaci` already loads it outside the form "pro Mapy.cz helpery" after pre-creating `MG._rez` (`W:pages/upravit-rezervaci.php:264-269, 285`). On load the file only defines `MG.*` functions, touches `MG._rez.appliedCodes`, and starts an observer that looks for `#rez-delivery-address` / `#rez-return-address`, which do not exist on calculator pages → no-op (`B:…-pricing.js:1-3, 139-141, 538-565`). Do the same pre-init as the edit page (`W:pages/upravit-rezervaci.php:267-269`): one inline `<script>` emitted by `renderKatalogCalc()` that creates `window.MG` and `MG._rez` with `appliedCodes: []`, `discountAmt: 0`, `motos: []`, `allBookings: {}` when they do not exist yet |
| "1 000 Kč + 40 Kč/km" in texts | same function: `base = MG._calcDeliveryFee(0)`, `perKm = MG._calcDeliveryFee(1) − base` | no literal in calculator code |
| Address suggestions / geocoding | `MG._mapySuggest(text, n)` (`B:…-pricing.js:415-438`) | call directly |
| Route | `MG._ensureBranchCoords()` + `MG._mapyRouting(lat1, lng1, lat2, lng2)` (`B:…-pricing.js:316-338`) | call directly: `MG._ensureBranchCoords().then(o => o ? MG._mapyRouting(o.lat, o.lng, lat, lng) : null)` (the same two calls `MG._calcRouteFor` makes, `B:…-pricing.js:386-403`) |
| Eligibility | today private in `W:js/pages-rezervace-selfservice.js:167-170, 187` | **smallest extraction**: new `W:js/delivery-rules.js` with `MG.DELIVERY.blocked(branchType, flagEnabled)`; `pages-rezervace-selfservice.js` (not minified) calls it in `applyRez()` and `applyEditLoc()` instead of its inline expression; the calculator calls the same function |
| Flag `self_service_delivery` | form: Supabase client (`selfservice.js:67-79`) | calculator pages have no Supabase SDK → PHP `kcData()` adds `'ssd' => $sb->fetchFeatureFlag('self_service_delivery')` (`W:supabase.php:345-353`, missing row = false = blocked) |
| Lead time + 6 h | `MG._rezValidatePickupTime` reads the form's DOM (`B:…-pricing.js:101-138`) → not callable without a time | calculator only informs (1.4, row "today"); the form enforces |

`W:js/delivery-rules.js` (new, ~20 lines, no dependencies; loaded before `pages-rezervace-selfservice.js`
on `/rezervace` and `/upravit-rezervaci`, and on calculator pages):

```js
(function (w) {
  var MG = w.MG = w.MG || {}, SS = 'samoobslužná';
  MG.DELIVERY = {
    SS_TYPE: SS,
    FLAG_KEY: 'self_service_delivery',
    // true = přistavení na adresu ani odvoz z adresy se u této pobočky nenabízí
    blocked: function (branchType, flagEnabled) { return branchType === SS && !flagEnabled; }
  };
})(window);
```

Change in `W:js/pages-rezervace-selfservice.js` (behaviour identical):
`var lock = rezIsSelfService() && !ruleOff();` → `var m = rezSelectedMoto(); var lock = MG.DELIVERY.blocked(m && m.branches && m.branches.type, flag.enabled);`
and the same for `lockAll` in `applyEditLoc()` (`:261`) with `editBooking().motorcycles.branches.type`.
Keep the old expression as fallback when `MG.DELIVERY` is undefined (stale cached page).

### 1.2 Files

| File | Change |
|---|---|
| `W:js/delivery-rules.js` | **new** (above) |
| `W:js/pages-rezervace-selfservice.js` | use `MG.DELIVERY.blocked` (2 expressions) |
| `W:pages/rezervace.php` | script tag for `delivery-rules.js` before `pages-rezervace-selfservice.js` (`:198`); read `$_GET['return_delivery']` and add `returnDelivery` to `REZERVACE_PARAMS` (`:21, :172-179`); script tag `js/rezervace-delivery-carry.js` after `rezervace-dates.js` (`:202`) |
| `W:pages/upravit-rezervaci.php` | script tag for `delivery-rules.js` before the selfservice wrapper |
| `W:js/rezervace-delivery-carry.js` | **new** wrapper (1.5); the minified cores are not edited |
| `W:pages/katalog-calc.php` | `kcDefaults()`: new text keys (1.6); `kcPageMeta()` (`:82-84`): scripts in this order `landing-calc-core.js`, `landing-calc-view.js`, `delivery-rules.js`, `pages-rezervace-pricing.js`, `landing-calc-delivery.js`, `landing-calc.js` + style `/css/landing-calc-delivery.css`; `kcData()` (`:94-150`): branch entry gets raw type `'ty' => safeStr($br['type'] ?? '')` next to `'k'` (`:113-114`), top level gets `'ssd' => (bool)$sb->fetchFeatureFlag(...)` (pass `$sb` in); `renderKatalogCalc()` (`:157-197`): the inline `MG._rez` pre-init (1.1), container `<div class="kc-dv" data-kc-dv hidden></div>` at the end of the `.kc-cal` column (under legend + note — after the calendar on mobile, middle column on desktop, no grid change) and one more `<li data-kc-step="4">` in `.kc-steps` |
| `W:js/landing-calc-delivery.js` | **new** (≤ ~9 kB): state, step HTML, autocomplete, route, fees, storage (1.3–1.5) |
| `W:css/landing-calc-delivery.css` | **new**: step, toggle rows, address input + dropdown, route line, lock note (dark `.kc-card` palette of `landing-calc.css`) |
| `W:js/landing-calc.js` | 5 small hooks: `E.dv = q('[data-kc-dv]')`; `changed()`/`setMoto()`/`setBranch()` call `K.dvCheck(X)`; `render()` calls `K.dvRender(X, E.dv)` and `K.dvSave(X)`; `X.href()` appends `K.dvQuery(X)`; `sticky()` shows `bd.total + K.dvFees(X).total` |
| `W:js/landing-calc-view.js` | `K.sumHtml` (`:97-123`): two rows after the day rows, total = `bd.total + fees.total`, `data-kc-total` = that sum, `late_text` total = sum − late, label `total_all` instead of `total` when fees > 0; average per day stays rental ÷ days |
| `W:lang/v2/{en,de,es,fr,nl,pl,uk}/katalog.php` | translations of the new keys (7 files) |

No change: `pages-rezervace.js`, `pages-rezervace-pricing.js`, `pages-rezervace-steps.js`, SQL.

### 1.3 Calculator state and functions (`MGKC` namespace, file `landing-calc-delivery.js`)

```js
S.dv = { on: false,                      // přistavení na adresu
         a: '', lat: null, lng: null, km: null, min: null, st: '',      // st: '' | 'wait' | 'ok' | 'err'
         same: true,                     // vrátit na stejné adrese — výchozí jako #rez-return-same-as-delivery
         ro: false,                      // vrácení jinde
         ra: '', rlat: null, rlng: null, rkm: null, rst: '' };

K.dvBlocked(X)  // the chosen bike's branch decides (the calculator offers delivery only with a chosen bike)
  = (function(){ var m = S.moto ? X.by[S.moto] : null, b = m ? X.branch(m.b) : null;
                 return !!b && MG.DELIVERY.blocked(b.ty, X.C.ssd); })()
K.dvActive(X)   = !!S.moto && !K.dvBlocked(X)          // fees and hand-over only with a chosen, eligible bike
K.dvFees(X)     // EXACTLY the form's rule, B:pages-rezervace-pricing.js:38-47
  = !K.dvActive(X) ? {p:0, r:0, total:0}
  : (p = S.dv.on ? MG._calcDeliveryFee(S.dv.km) : 0,
     r = S.dv.ro ? MG._calcDeliveryFee(S.dv.rkm) : (S.dv.on && S.dv.same ? p : 0),
     {p:p, r:r, total:p+r})
K.dvCheck(X)    // after every bike/branch change: blocked → on=false, ro=false, same=true (typed addresses stay in memory)
K.dvRoute(side, lat, lng)   // st='wait' → MG._ensureBranchCoords → MG._mapyRouting → km/min, st='ok' | 'err' → render()
K.dvGeocode(side, text)     // MG._mapySuggest(text, 1) → first hit → K.dvRoute   (as B:…-pricing.js:406-413)
K.dvQuery(X)    // '' | '&delivery=1' | '&return_delivery=1' | both   (only when K.dvActive)
K.dvSave(X)     // sessionStorage 'mg_calc_delivery' (1.5) or removeItem when nothing is on
K.dvRender(X, el), K.dvHtml(X)   // step markup + listeners (delegated on el)
```

Note on `K.dvFees`: like the form's live price, a ticked delivery with no routed address already counts
the base fee (`MG._calcDeliveryFee(undefined)` = 1 000 Kč, and again for "same address") — the summary row
then says "od {price}" until a route exists. This keeps calculator total = form total in every state.

### 1.4 Step UI and states

Step "Přistavení" (number 4 in the catalog, 3 in the detail). Elements mirror the form's three controls
(W-UI1) with the calculator's own markup; **input + Mapy.cz autocomplete only** — the form's GPS and map
buttons are not duplicated (they need geolocation texts, Leaflet and `MG.t`; the address can still be
changed with them in the form). Autocomplete = small dropdown fed by `MG._mapySuggest(text, 8)`, 220 ms
debounce, keyboard ↑ ↓ Enter Esc, as the form's (`B:…-pricing.js:453-536`).

| State | What the step shows | Summary / CTA |
|---|---|---|
| No bike chosen | one hint line `dv_need_moto`; no controls | unchanged (free-bike list, `cta_any`) — no delivery params |
| Bike of a self-service branch and flag off | both toggles visible but locked + collapsed note `dv_locked` → `dv_locked_text` (same behaviour as `.mg-ss-note` of the form) | no fee rows; href without delivery params; storage removed |
| Eligible bike, nothing ticked | toggle "Přivézt motorku na adresu" (sub `{base} + {perKm}/km`), toggle "Vrátit motorku jinde" | unchanged |
| Delivery ticked, no address | address input (focus), checkbox "Vrátit motorku na stejné adrese" (ticked) | rows "Přistavení motorky — od {base}", "Vrácení motorky — od {base}"; total includes them; `delivery=1` |
| Address picked / typed, routing | line `dv_loading` | rows keep "od …" until done |
| Route ok | line `dv_route` "{km} km z Mezné · {price}" (km with 1 decimal like the form) | rows with exact fees; total; sticky bar total |
| Route failed | line `dv_error` (wording of `rez.route.error`: base fee now, exact price confirmed later) | fee = base, as the form |
| "Same address" unticked | — | return row disappears |
| "Vrátit motorku jinde" ticked | second address input + its route line; unticks "same address" (as the form) | return row from the second route; `return_delivery=1` |
| Start day = today (Prague) and Prague hour ≥ 18 while delivery is ticked | amber `dv_today` (a delivery needs 6 h, no time left today) | CTA stays — the form refuses the time (W6) |
| Always while delivery is ticked | info `dv_lead` ("aspoň 6 hodin předem, čas zvolíš v rezervaci") | — |
| Bike changed after an address was entered | eligible bike: everything kept (fee does not depend on the bike — origin is always Mezná); blocked bike: `K.dvCheck` switches both off and shows the lock | fees recomputed / removed |
| Currency ≠ CZK | fees through `X.money` like every other amount, "Platíš v Kč" line uses the Kč sum | — |

### 1.5 Hand-over to `/rezervace` and pre-fill

**URL** (existing mechanism): `X.href()` = today's `?moto=&start=&end=` + `&delivery=1` when delivery is
ticked + `&return_delivery=1` when "return elsewhere" is ticked. `delivery=1` is already understood by the
core (W3). `return_delivery=1` is today a dead link parameter (D16) and gets its meaning here.

**Address** — not in the URL (page URLs go to analytics/GTM after consent; an address is personal data):
`sessionStorage['mg_calc_delivery']`, written on every calculator render (the CTA is a plain link):

```json
{ "v": 1, "ts": 1764270000000, "moto": "<uuid>", "start": "2026-12-05", "end": "2026-12-07",
  "d": { "a": "Vodičkova 12, Praha 1", "lat": 50.0807, "lng": 14.4254 },
  "ret": "same",
  "r": null }
```
`d` = null when only return collection is chosen; `ret` ∈ `"same"` | `"branch"` | `"other"`; `r` like `d` for
`"other"`. **No km, no fee** — the form computes them itself.

**`W:js/rezervace-delivery-carry.js`** (new wrapper, same technique as `rezervace-dates.js`):

1. Run only when `REZERVACE_PARAMS.delivery === '1'` or `.returnDelivery === '1'`, and not `resume`.
2. Read and validate the storage record: `v === 1`, `ts` younger than 2 h, `moto/start/end` equal to the
   URL parameters. Anything else → do nothing (the core's existing `?delivery=1` behaviour remains: box
   ticked, address empty).
3. Wait for the end of the core's init: wrap `MG._rezBindNav` (called once with `'form'` as the last
   statement of `MG._rezInit`, `B:pages-rezervace.js:1043`) and act on the next tick — by then the core
   has ticked `#rez-delivery` and the self-service wrapper has applied its lock.
4. Pickup side: if `#rez-delivery` is missing, disabled or not ticked → drop the record (self-service bike
   or changed rules; the form's own note explains). Otherwise set `#rez-delivery-address.value = d.a`,
   `MG._rez._deliveryRouteAddr = d.a`, and call the form's `MG._calcRouteFor('delivery', d.lat, d.lng)`
   (without coordinates `MG._calcRouteFor('delivery')`, which geocodes the text).
5. Return side: `"same"` → nothing (default ticked); `"branch"` → untick `#rez-return-same-as-delivery`
   and dispatch `change`; `"other"` (also with `return_delivery=1` alone) → if `#rez-return-other` is not
   disabled: tick it, dispatch `change` (the core unticks "same" and opens the panel), set
   `#rez-return-address`, `MG._rez._returnRouteAddr`, call `MG._calcRouteFor('return', r.lat, r.lng)`.
6. Never write prices; never touch the pickup time. The record is kept (a reload re-applies it) and is
   overwritten/removed by the next calculator render.

**When the carried data is no longer valid in the form** — nothing new is needed:
self-service bike → existing lock + note (W1); route fails → existing red box, base fee (W5b); pickup too
soon → existing alert / v2 guide (W6); dates taken meanwhile → `rezervace-dates.js` leaves step 2 open;
storage unavailable or link opened in a new tab → box ticked, address typed again in the form.

### 1.6 Texts

Calculator texts live in `kcDefaults()` (CS, `W:pages/katalog-calc.php:13-72`) ← `W:lang/v2/<lang>/katalog.php`
(en, de, es, fr, nl, pl, uk) ← Velín CMS `web.landing_katalog.<key>` (automatic, no SQL). The calculator
uses "tykání"; the form's `rez.pickup.*` keys use "vykání", so they are not reused verbatim. New keys
(CS defaults; `{base}`, `{perKm}`, `{km}`, `{price}` are filled by JS):

| Key | CS default |
|---|---|
| `step_delivery` | Přistavení |
| `dv_need_moto` | Vyber motorku — spočítáme ti i přistavení na adresu. |
| `dv_toggle` | Přivézt motorku na adresu |
| `dv_sub` | {base} + {perKm}/km z pobočky Mezná |
| `dv_addr` | Adresa přistavení (ulice, město) |
| `dv_same` | Vrátit motorku na stejné adrese |
| `dv_ro` | Vrátit motorku jinde |
| `dv_raddr` | Adresa vrácení (ulice, město) |
| `dv_loading` | Počítám trasu z Mezné… |
| `dv_route` | {km} km z Mezné · {price} |
| `dv_error` | Trasu se nepodařilo spočítat. Počítáme zatím {base}, přesnou cenu potvrdíme v rezervaci. |
| `dv_locked` | Na samoobslužné pobočce zatím není k dispozici |
| `dv_locked_text` | Motorky ze samoobslužné pobočky se přebírají i vracejí jen na pobočce — nonstop pomocí kódu. Přistavení na adresu ani odvoz z adresy u nich zatím nenabízíme. |
| `dv_lead` | Přistavení objednej aspoň 6 hodin předem. Čas zvolíš v rezervaci. |
| `dv_today` | Na dnešek už přistavení nestihneme — vyber pozdější den, nebo vyzvednutí na pobočce. |
| `dv_row_pick` | Přistavení motorky |
| `dv_row_ret` | Vrácení motorky |
| `dv_from` | od {price} |
| `total_all` | Celkem s přistavením |

19 keys × 8 languages. `rezervace-delivery-carry.js` shows no text of its own. The extras names sent to
the server (`rez.gear.item.delivery` / `rez.gear.item.return`) are **not** touched (W10).

### 1.7 Order of work and checks (web)

1. `delivery-rules.js` + selfservice wrapper change + script tags → `/rezervace` and
   `/upravit-rezervaci` behave exactly as before (Mezná bike: options free; Velké Němčice bike: locked + note).
2. `kcData()` (`ty`, `ssd`), scripts in `kcPageMeta()`; confirm no console error and no behaviour change
   on `/katalog` and `/katalog/<id>` with `pages-rezervace-pricing.js` loaded.
3. `landing-calc-delivery.js` + CSS + hooks in `landing-calc.js` / `landing-calc-view.js`; texts.
4. `rezervace.php` (`return_delivery`) + `rezervace-delivery-carry.js`.
5. Checks (local server as usual; there is no automated web test suite in the repo):
   - pure functions in Node: `K.dvFees` for all toggle combinations equals the expression of
     `MG._rezUpdatePrice` with the same km (load `pages-rezervace-pricing.js` + stubs);
   - the same address in calculator and form gives the same km line and the same total (CZK and EUR);
   - every row of the edge-case table (section 4) in 8 languages, 360 px and desktop;
   - `?landing=v1` unchanged; `/pujceni-obleceni` unchanged.

---

## 2. App (v2 look, both trees identical)

### 2.1 Shared sources

| Need | Source of truth (booking form) | Calculator |
|---|---|---|
| Eligibility | `selfServiceDeliveryBlocked(branchType, flagEnabled)` (`A:core/booking_rules.dart:141-143`) + `selfServiceDeliveryEnabledProvider` (`A:core/feature_flags.dart:31-42`), combined inline at `A:core/booking_form_widget.dart:445-448` | **smallest extraction**: `bool handoverDeliveryBlocked(WidgetRef ref, Motorcycle moto)` in `A:features/booking/booking_provider.dart` containing exactly that expression; the form's line 445 and the calculator both call it |
| Option rows, locked tile, address row | `BookingFormPickupSection` / `BookingFormReturnSection` (`A:core/booking_form_pickup_section.dart`, `…_return_section.dart`), v2 body `BookingHandoverV2`, `BookingLockedOptionTile` | **the same two widgets**, with two additive parameters (2.3) |
| Address entry, suggestions, GPS, map, geocode, route, fee | `showAddrBottomSheet` + `launchMapPicker` + `routeKmFromBranch` + `PriceCalculator.calcDeliveryFee` | unchanged — reached through the section widgets |
| "Same address on the other side" rules | `handoverToDelivery`, `handoverSaveAddress`, `handoverQuickOptions`, `handoverSameAddress` (`A:core/booking_address_carry.dart`) | unchanged logic; **smallest extraction**: where they copy the fee they use an injectable `HandoverFees` instead of touching the four global providers directly (2.3) |
| Total | `PriceCalculator.calculate` through `quoteFor` (`A:features/booking/booking_quote.dart:12-31`) | `quoteFor` gets two optional fee arguments (default 0) |
| Lead time | `BookingValidator.checkPickupLeadTime` (`A:features/booking/booking_validator.dart:116-157`) | called with `pickupTime: '23:59'`, `isDelivery: true` → non-null = no delivery possible on that start day → warning |
| Fee label "(N km × 40 + 1 000)" | `BookingPriceV2.deliveryLabel` (`A:features/booking/v2/sections/price_v2.dart:49-55`) | reused in the receipt |

Why the fee providers cannot simply be shared: `pickupDelivFeeProvider`, `pickupDistKmProvider`,
`returnDelivFeeProvider`, `returnDistKmProvider` (`A:features/booking/booking_provider.dart:25-35`) belong to
the booking draft in progress (possibly of another bike). A calculator writing into them would change the
price of that draft. The calculator therefore keeps its own numbers and hands them over only at REZERVOVAT.

### 2.2 Data shapes

`A:features/catalog/v2/calc/calc_state.dart`:

```dart
/// Handover chosen in the calculator. [draft] carries ONLY pickup*/return* fields
/// (method, street, city, zip, lat, lng) — the shape the shared handover helpers work on.
class CalcHandover {
  final BookingDraft draft;
  final String? branchId;                 // branch of the bike it was entered for (rule A4)
  final double pickupFee, pickupKm, returnFee, returnKm;
  const CalcHandover({required this.draft, this.branchId,
      this.pickupFee = 0, this.pickupKm = 0, this.returnFee = 0, this.returnKm = 0});
  double get pickupDue => draft.pickupMethod == 'delivery' ? pickupFee : 0;   // = priceBreakdownProvider, booking_provider.dart:62-63
  double get returnDue => draft.returnMethod == 'delivery' ? returnFee : 0;
  bool get any => draft.pickupMethod == 'delivery' || draft.returnMethod == 'delivery';
  CalcHandover copyWith({...});
}

class CalcState { ...; final CalcHandover? handover; }     // null = never touched = both sides at the branch
class CalcStateNotifier {
  void updateHandover(CalcHandover Function(CalcHandover current) fn, {String? branchId});  // reads the CURRENT state
  void clearHandover();
  // resetTrip() and a bike dropped by setBranch() also clear it
}
```

`A:core/booking_address_carry.dart`:

```dart
/// Where the handover sections read / write distance and fee.
/// Booking form = the booking providers (default); calculator = its own state.
class HandoverFees {
  final double Function() pickupFee, pickupKm, returnFee, returnKm;
  final void Function(double fee, double km) setPickup, setReturn;
  const HandoverFees({...});
  factory HandoverFees.form(WidgetRef ref) => HandoverFees(
        pickupFee: () => ref.read(pickupDelivFeeProvider), pickupKm: () => ref.read(pickupDistKmProvider),
        returnFee: () => ref.read(returnDelivFeeProvider), returnKm: () => ref.read(returnDistKmProvider),
        setPickup: (f, k) { ref.read(pickupDelivFeeProvider.notifier).state = f; ref.read(pickupDistKmProvider.notifier).state = k; },
        setReturn: (f, k) { ref.read(returnDelivFeeProvider.notifier).state = f; ref.read(returnDistKmProvider.notifier).state = k; });
}
void handoverToDelivery(WidgetRef ref, BookingDraftUpd onUpd, BookingDraft draft, {required bool pickup, HandoverFees? fees});
void handoverSaveAddress(WidgetRef ref, BookingDraftUpd onUpd, BookingDraft draft,
    {required bool pickup, required String city, required String addr, HandoverFees? fees});
// _copyFee(HandoverFees f, {required bool toReturn}) — body unchanged, reads/writes through f
```
`fees == null` → `HandoverFees.form(ref)` → every existing call site and test behaves as today.

### 2.3 Files

| File (both trees) | Change |
|---|---|
| `A:core/booking_address_carry.dart` | `HandoverFees` + optional `fees` on the two functions (above) |
| `A:core/booking_form_pickup_section.dart`, `A:core/booking_form_return_section.dart` | two optional constructor params: `HandoverFees? fees` and `bool bare = false`. `fees` is passed to `handoverToDelivery` / `handoverSaveAddress`, used in `onDistCalc`, and for the displayed km/fee (`fees != null ? fees!.pickupKm() : ref.watch(pickupDistKmProvider)`). `bare` is passed to `BookingHandoverV2`. Defaults = today's behaviour in both looks |
| `A:features/booking/v2/sections/handover_v2.dart` | `BookingHandoverV2.bare` (default false): true → the same column (two option rows / locked tile / address row) under a `BkLabel(title)` without the `BkCard` frame, so it can sit inside a calculator step card |
| `A:features/booking/booking_provider.dart` | `handoverDeliveryBlocked(ref, moto)` |
| `A:core/booking_form_widget.dart` | line 445-448: `final deliveryBlocked = handoverDeliveryBlocked(ref, moto);` — nothing else |
| `A:features/booking/booking_quote.dart` | `quoteFor(..., double pickupDeliveryFee = 0, double returnDeliveryFee = 0)` forwarded to `PriceCalculator.calculate`; `listQuoteFor` unchanged |
| `A:features/booking/booking_entry.dart` | `startBookingFromSelection(ctx, ref, moto, start, end, {CalcHandover? handover})`; in the v2 branch, after `next` is computed and after the existing "zero the four providers" block (`:77-84`): when `handover != null`, `next = next.copyWith(pickupMethod, returnMethod, pickupAddress/City/Zip/Lat/Lng, returnAddress/City/Zip/Lat/Lng from handover.draft)` and the four providers are set from `handover` (fee and km of each side). `handover == null` → today's behaviour to the byte. Old look branch untouched |
| `A:features/catalog/v2/calc/calc_state.dart` | `CalcHandover`, `CalcState.handover`, notifier methods (2.2) |
| `A:features/catalog/v2/calc/calc_step_handover_v2.dart` | **new** (≈ 110 lines): step ④ body (2.4) |
| `A:features/catalog/v2/calc/calc_body_v2.dart` | step ④ uses the new widget and a numbered badge (`info: false`, `done: true`); `q` / `q12` get `pickupDeliveryFee: h.pickupDue, returnDeliveryFee: h.returnDue`; `book()` passes `handover: st.handover`; normalization after the frame: a handover exists and (the bike is blocked or `st.handover!.branchId != moto.branchId`) → `clearHandover()` (the calculator's counterpart of A3/A4) |
| `A:features/catalog/v2/calc/calc_receipt_v2.dart` | rows after the rental row: `if (q.pickupDeliveryFee > 0) _row(BookingPriceV2.deliveryLabel(tr.tr('deliveryFee'), q.pickupDeliveryFee), '+…')`, same for `returnFee` |
| `A:features/catalog/v2/calc/calc_total_v2.dart` | "průměrně … / den" from `q.total − q.pickupDeliveryFee − q.returnDeliveryFee` (rental average, not inflated by delivery); `save12` is unaffected because `q12` gets the same fees |
| `A:core/i18n/translations_ext_68_calc_delivery.dart` | **new**, 8 languages (2.5), registered in `A:core/i18n/translations.dart` (another agent has an open edit there — merge) |
| `Motogo-app-main/motogo-app-flutter/DESIGN_V22.md` | short section "rozhodnutí majitele 2026-11-27": the calculator's step ④ lets the customer choose the place (explicit exception to "v2 = jen vzhled", like the calculator itself); the time stays in the form |

Not touched: `map_picker.dart`, `main.dart`, `pubspec.yaml`, payment, old-look-only files.

### 2.4 Step ④ (`CalcStepHandoverV2`)

```dart
class CalcStepHandoverV2 extends ConsumerWidget {
  final Motorcycle? moto; final CalcState st;
  Widget build(context, ref) {
    final tr = t(context);
    if (moto == null) return Column([CalcHint(tr.tr('cdHandoverNoMoto')), CalcHint(tr.tr('cdHandoverInfo'))]);
    final n = ref.read(calcStateProvider.notifier);
    final blocked = handoverDeliveryBlocked(ref, moto);
    final h = st.handover ?? CalcHandover(draft: BookingDraft(), branchId: moto.branchId);
    void upd(BookingDraft Function(BookingDraft) fn) =>
        n.updateHandover((c) => c.copyWith(draft: fn(c.draft)), branchId: moto.branchId);
    final fees = HandoverFees(
        pickupFee: () => cur().pickupFee, pickupKm: () => cur().pickupKm,      // cur() = ref.read(calcStateProvider).handover ?? h
        returnFee: () => cur().returnFee, returnKm: () => cur().returnKm,
        setPickup: (f, k) => n.updateHandover((c) => c.copyWith(pickupFee: f, pickupKm: k), branchId: moto.branchId),
        setReturn: (f, k) => n.updateHandover((c) => c.copyWith(returnFee: f, returnKm: k), branchId: moto.branchId));
    final branchLabel = selfServiceBranchLabel(branchType: moto.branchType, name: moto.branchName,
        address: moto.branchAddress, city: moto.branchCity);               // as booking_form_widget.dart:520-524
    final today = h.draft.pickupMethod == 'delivery' && st.start != null &&
        BookingValidator.checkPickupLeadTime(startDate: st.start, pickupTime: '23:59', isDelivery: true,
            branchType: moto.branchType) != null;
    return Column([
      BookingFormPickupSection(draft: h.draft, onUpd: upd, branchLabel: branchLabel, deliveryBlocked: blocked, fees: fees, bare: true),
      const SizedBox(height: 14),
      BookingFormReturnSection(draft: h.draft, onUpd: upd, branchLabel: branchLabel, deliveryBlocked: blocked, fees: fees, bare: true),
      if (today) CalcHint(tr.tr('cdLeadToday'), warn: true),
      CalcHint(tr.tr('cdHandoverInfo')),
    ]);
  }
}
```

Important detail: the address sheet calls `onDistCalc(km, fee)` and then `onSave(city, street)`
(`A:features/booking/booking_ui_helpers.dart:757-760`), and `handoverSaveAddress` may copy the fee to the
other side right after — so every `HandoverFees` closure and `upd` must read the **current** calculator
state (`updateHandover` with a function), never a value captured at build time.

States: no bike → hints only; self-service bike → both "na adresu" rows are the locked tile with the
existing texts `ssNoDeliveryShort` / `ssNoDeliveryInfo`; eligible → the form's rows, address row, "~N km ·
fee", quick options from the profile and the other side, GPS and map exactly as in the form. Delivery
chosen without an address = fee 0 and the address row asks for it (as the form, A11).

Hand-over on REZERVOVAT: `startBookingFromSelection(..., handover: st.handover)`.
- Handover never touched (`null`) → today's behaviour, including "an in-progress draft of the same bike
  keeps its own delivery" (A4).
- Touched → it wins over the carried draft for both sides (it is the customer's latest explicit choice,
  including an explicit "na pobočce"); fees and km go to the four providers, so the form shows the same
  rows and the same total. The form then applies its own normalization A3, lead-time validation A6 and
  availability check; a handover that became invalid (flag flipped) falls back to "na pobočce".
- Optional refinement (recommended, small): when `st.handover == null` and the in-progress draft belongs
  to this bike and this account and has a side on `'delivery'`, show that draft's handover and its
  provider fees in step ④ and in the total (display only, still pass `null`) — the calculator then never
  shows a lower price than the form will.

### 2.5 Texts

Existing keys reused (8 languages already there): `v2CalcStepHandover` (step title), `v2BkPickupTitle`,
`v2BkReturnTitle`, `atBranch`, `v2BkDeliveryTo`, `v2BkReturnFrom`, `deliveryPriceInfo`, `deliveryFrom`,
`ssNoDeliveryShort`, `ssNoDeliveryInfo`, `efoDelivAddrTitle`, `efoCollectAddrTitle`, `v2BkEnterAddress`,
`v2BkChange`, `bkAddrSamePickup`, `bkAddrSameReturn`, `bkAddrMine`, `deliveryFee`, `returnFee`.

New keys — file `translations_ext_68_calc_delivery.dart` (prefix `cd`, not `v2…`: the test
`test/v2/i18n_v2_test.dart` allows `v2`-prefixed keys only in the `ext_5x` / `ext_60_v2` files; recent
additions do the same, e.g. `efo…` in `ext_63`):

| Key | CS |
|---|---|
| `cdHandoverInfo` | Čas vyzvednutí, výbavu i velikosti zvolíš až v rezervaci. Při vyzvednutí od 12:00 máš 1. den za polovinu (výpůjčka na 2 a více dní). |
| `cdHandoverNoMoto` | Vyber motorku — pak tu zvolíš vyzvednutí na pobočce, nebo přistavení na adresu. |
| `cdLeadToday` | Přistavení stihneme nejdřív za 6 hodin — na dnešek už to nevyjde. Vyber pozdější den, nebo vyzvednutí na pobočce. |

`v2LpCalcHandover` ("Čas a místo vyzvednutí … zvolíš až v rezervaci") is no longer shown by the
calculator; leave the key in place (it is asserted by an existing test that must be updated, 2.6).

### 2.6 Tests (Android tree `motogo-app-flutter/test/`; iOS verified on a temporary copy as CLAUDE.md prescribes)

New:
1. `test/v2/screens/calc_delivery_logic_test.dart` — `quoteFor` with fees equals `priceBreakdownProvider`
   for a draft with the same handover (ProviderContainer, bike `kBmw`, ranks 0 / 3 / 20): totals equal;
   loyalty amount identical with and without delivery (delivery excluded from its base); `q.total −
   q12.total` identical with and without delivery; default arguments reproduce today's `quoteFor`.
2. `test/v2/screens/calc_delivery_state_test.dart` — `CalcStateNotifier`: `updateHandover` sequences
   (fee then address; follow-the-other-side copy carries the fee), `clearHandover`, `resetTrip`, bike
   dropped by `setBranch`; `CalcHandover.pickupDue/returnDue` zero when the method is `'store'`.
3. `test/v2/screens/calc_delivery_carry_test.dart` — `startBookingFromSelection(handover: …)`: draft gets
   methods + addresses, four providers set, `priceBreakdownProvider.total` == calculator total; `handover:
   null` leaves every existing carry case unchanged (re-run of `booking_prefill_flow_test` expectations);
   in-progress draft of the same bike with delivery + touched handover "store/store" → store wins;
   handover for a staffed bike, then the form opened for a self-service bike → form normalizes to store
   and price has no fee.
4. `test/v2/screens/calc_delivery_widget_test.dart` — step ④: no bike → two hints, no option rows;
   `kBmw` → four option rows; self-service bike → two locked tiles with `ssNoDeliveryShort`, tap expands;
   choose delivery → address sheet opens (HTTP `MockClient` as in `booking_r2_address_test.dart`), confirm
   → "~N km · fee" row, receipt rows "Přistavení (…)" and total, sticky dock total; return side copies
   the address and fee; switching to a self-service bike clears the handover and the total; lead-time
   warning deterministic without a clock: start = yesterday → warning shown, start = today + 2 → none
   (the validator uses `DateTime.now()`; the step widget is pumped directly with that state).
5. `test/v2/screens/calc_delivery_fit_test.dart` — step ④ with locked tile / address / warning at 320 dp ×
   text scale 1.3 × 8 languages: no overflow, no word broken (pattern of `catalog_fit_matrix_test.dart`).
6. In the new test file: every `cd*` key present and non-empty in 8 languages with equal placeholders.

To update: `test/v2/screens/late_pickup_info_test.dart:60` (expects `v2LpCalcHandover` in the calculator →
`cdHandoverInfo`), `test/v2/screens/catalog_r2_test.dart:293` (expects one `CalcInfoBadge` for step ④ →
numbered badge). Must stay green untouched: `booking_prefill_logic_test.dart` (handover helpers),
`booking_r2_address_test.dart`, `booking_prefill_flow_test.dart`, `order_booking_carry_test.dart`,
`file_size_test.dart` (new v2 file ≤ 18 500 bytes), `flag_off_test.dart` (old look unchanged).
After the change: `diff -rq` of both `lib/` trees shows only the intentional platform list.

### 2.7 Order of work (app)

1. `HandoverFees` + optional params (carry helpers, two sections, `BookingHandoverV2.bare`),
   `handoverDeliveryBlocked` → run the whole existing suite: nothing may change.
2. `quoteFor` fee params, `CalcHandover` / state, `calc_step_handover_v2.dart`, body / receipt / total.
3. `startBookingFromSelection(handover:)`.
4. Texts, tests, `DESIGN_V22.md` note; copy to the iOS tree; iOS analyze + tests on the temporary copy.
Ships with the next app version in both stores (no minimum-version bump needed: no backend change).

---

## 3. Backend

**No SQL, no edge-function change is needed.** The calculator reads only what the forms already read
(`motorcycles` + `branches.type`, `feature_flags.self_service_delivery`, `get_moto_booked_dates`) and
creates nothing; bookings are still created by the unchanged form paths. A server quote RPC would not
make the price "more correct": the server has no routing and no delivery tariff (B4, B7), new bookings
are priced by the client today (B5, B6). No STATE file changes; optionally add the calculator to the
list of readers of the flag in `SUPABASE_BACKEND_STATE_5.md` (documentation only).

Existing gaps the calculator inherits but does not create (not part of this task): the self-service rule
has no server enforcement and the flag row does not exist (B9); the delivery fee of a new booking is not
verified by the server (B5, B6); D4–D12.

---

## 4. Edge-case checklist (must pass on both platforms unless marked)

| # | Case | Expected |
|---|---|---|
| E1 | Self-service bike selected | Option visible but locked with the form's explanation; no fee in the total; nothing delivery-related handed over |
| E2 | Flag `self_service_delivery` turned on later | Option unlocks in calculator and form alike (same function); web after the page cache refreshes |
| E3 | Calculator without a selected bike | Hint only, no controls, free-bike list unchanged; web CTA without delivery params |
| E4 | Address entered, then bike switched to another eligible bike | Address, km and fee stay (app: only while the branch is the same, rule A4) |
| E5 | Address entered, then bike switched to a self-service bike | Delivery switched off, lock shown, total drops to rental; switching back needs a new tick (as the forms) |
| E6 | Address that cannot be routed / Mapy.cz down | Web: base 1 000 Kč + "upřesníme" line (W5b); app: the sheet's own fallback chain (A7b). Calculator = form |
| E7 | Address outside CZ / very far | No extra rule — same as the form on that platform (D7); see Q1 |
| E8 | Different return address | Web: "Vrátit motorku jinde" + second address; app: return section with its own address; two fee rows |
| E9 | Return collection without delivery | Possible on both; web hands over `return_delivery=1` |
| E10 | Web: "same address" left ticked (default) | Two equal fee rows, total = rental + 2 × fee; form shows the same |
| E11 | Delivery ticked, address not yet entered | Web: "od 1 000 Kč" rows counted (form does the same); app: fee 0 and the address row asks for it (form does the same) |
| E12 | Kids' bike (`license_required = 'N'`), trailer as the bike | Delivery offered if the branch is staffed (no special rule exists, B18); form adds its guardian consent as today |
| E13 | Dates inside a branch closure / busy day | Calendar does not allow them; carried dates are re-checked by the form; delivery does not bypass closures (B12) |
| E14 | Late-pickup discount + delivery | ½ info unchanged (saving = 50 % of day 1, independent of delivery); app loyalty row unchanged by the fee |
| E15 | Start today, less than 6 h left in the day | Warning in the calculator; the form refuses the time |
| E16 | Guest (web) / logged in (web, app) | No difference for delivery; web storage is per tab; app profile address appears as a quick option |
| E17 | App: in-progress booking draft for another bike with its own delivery | Calculator never changes that draft's fees before REZERVOVAT |
| E18 | App: untouched step ④ → REZERVOVAT | Exactly today's carry behaviour |
| E19 | Web: link opened in a new tab / storage blocked | Form opens with delivery ticked and empty address |
| E20 | Web: stored record for another bike/dates or older than 2 h | Ignored |
| E21 | Currency EUR/PLN (web) | Fee rows converted like the rental; "Platíš v Kč" shows the Kč sum |
| E22 | Gear-only rental, reservation edit, old app look, web v1 look | Unchanged |
| E23 | After a paid booking (app) | Calculator bike, dates and handover reset (`resetTrip`) |
| E24 | Long languages, 320 dp, large text | No overflow, no broken word in the new step |

---

## 5. Open questions for the owner (only what code cannot decide)

| # | Question | Recommended default |
|---|---|---|
| Q1 | The how-to page says "Nad 100 km cenu kalkulujeme individuálně" and "kamkoliv v ČR", but both forms price any distance automatically and the web form also offers foreign addresses. Should the calculator (and then the forms) get a limit? | No limit now — calculator = form. If a limit is wanted, it is one rule to add to both forms and it reaches the calculators automatically. |
| Q2 | Web form pre-ticks "Vrátit motorku na stejné adrese" (delivery = 2 × fee by default); the app treats pickup and return separately (1 × fee by default). Keep both? | Keep; each calculator mirrors its own form. |
| Q3 | Besides "Spočítat cenu": should the web detail calculator ("Vyber si termín") and the app detail card ("Tvoje jízda") offer delivery too? | Web detail yes (it is the same component; switching it off is one condition). App detail no. |
| Q4 | Web calculator: address field with suggestions only, or also the form's "Moje poloha" and "Mapa" buttons? | Suggestions only; GPS and map stay in the form (app gets all three for free because it reuses the sheet). |
| Q5 | Start day today with less than 6 h left: warn and let the form refuse (recommended), or disable the calculator's button while delivery is ticked? | Warn only. |

## 6. Not verified

- Live DB **content** (FAQ / policy rows about delivery pricing, `pages_overlay` texts in other
  languages) — only repo defaults and the schema snapshot were read.
- That anon may read `feature_flags` over REST is inferred from the web form doing it through the
  Supabase client; the design reads the flag server-side in PHP instead, so it does not depend on it.
- D8 (app stores only the street in `pickup_address`) is read from code, not confirmed on live rows.
- Mapy.cz behaviour (first Suggest hit for the Mezná text, quota of the shared key with calculator traffic
  added) and browser `sessionStorage` behaviour for links opened in a new tab were not tested.
- Nothing was run: no Flutter, no PHP server, no SQL. Web has no automated tests in the repo.
- Line numbers in `W:pages/katalog-calc.php`, `W:pages/katalog.php`, `W:pages/katalog-detail.php`,
  `W:lang/cs.php` drift while other agents edit those files.
