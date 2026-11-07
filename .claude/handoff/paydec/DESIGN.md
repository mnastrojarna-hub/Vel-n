# PAYDEC — DESIGN for owner decisions D1–D6 (2026-10-16)

Input: `paydec/understand.md` (code map, file:line refs), `errstates/audit_payments.md`, owner decisions 2026-10-16.
Branch `claude/moto-go-mobile-conversion-gqg5qo` (HEAD 2d4d3d58 — v2 WIP, no payment code touched since 15673b9b).
Abbrev.: PP = `supabase/functions/process-payment/index.ts`, WR = `webhook-receiver/index.ts`, PC = `webhook-receiver/payment-confirmers.ts`,
GI = `generate-invoice/index.ts`, PF = `process-payment/payment-flows.ts`. App paths are relative to `lib/` and apply to BOTH trees
(`motogo-app-flutter`, `motogo-app-flutter-ios`) unless marked. Field app = 4.1.3 (+116). Live SQL truth = scratchpad `live_schema.sql`.

Hard constraints carried into every step: no live DB writes; SQL only as drafts in `paydec/sql/` (Czech header, guarded, idempotent,
no BEGIN/COMMIT) and owner-approved before commit; edge deploys on merge → every edge change must degrade safely when the SQL
is not applied yet; no git writes; do not touch `lib/core/v2/**`, `lib/features/*/v2/**`, `booking_v2_*`, `translations_ext_5X_*`,
`router.dart`, `app_shell.dart`, `shell_*.dart` (v2 workflow); re-read each app file right before editing; 8 languages for
every new string; ≤ 5000 tokens per new file (split modules).

---------------------------------------------------------------------------------------------------------------------------------
## 0. Summary of decisions

| # | Owner text | Design decision (short) |
|---|---|---|
| D1 | „více než 1 Kč → zaokrouhlovat nahoru na 15" | `due ≤ 0` free (existing) · `0 < due ≤ 1` **waived** (nothing charged) · `1 < due < 15` **charge 15** · `≥ 15` unchanged. Applies to new booking, FAB resume, restore, edit surcharge, moto swap. Rounding is stored in a new signed column `card_rounding` that is **folded into the total** and printed as an explicit line on every document. |
| D2 | „Stejně tak D2" | Same rule for e-shop orders (`shop_orders.card_rounding`, folded into `shop_orders.total`). |
| D3 | „obnovit a zaplatit má být možnost" | New SECURITY DEFINER RPC `customer_restore_booking(uuid)` + shared check function + a stamping trigger that also fixes app 4.1.3's direct UPDATE + cron `auto_cancel_expired_pending()` that counts the 30-min window from `restored_at` and never cancels while a payment is in flight. |
| D4 | „udělej" | PP hardening: one live PaymentIntent per booking/order (refuse / reuse / cancel), Stripe idempotency keys, 15-Kč minimum + rounding for all types server-side, stable machine `code` on every refusal (+ Czech `error` text without contacts for old apps), `already_paid` = success-like, Stripe errors mapped, new action `complete_extension`. F1 (double surcharge) fixed. |
| D5 | „žádný kontakt; jasně co je špatně" | No e-mail/phone/„Napiš nám" in any payment error state (app + server texts). Full code → text table §10; every Stripe decline code mapped; lost/stolen/pickup → generic safe wording; offline/timeout/server separated. |
| D6 | „musí se povést uložit; zkusit znovu za chvíli / po obnovení internetu" | Server completes a paid swap/edit idempotently (webhook + `complete_extension`), transient failures return 500 so Stripe retries; app keeps a persisted `PaidChangeQueue` retried on start, on reconnect and with backoff; customer sees „Výměna se dokončuje", never an error. Permanent impossibility (bike taken meanwhile) → automatic refund + staff alert (owner Q4). |
| D7 | „zatím nezapínat" | Nothing. `reservation_upsell` stays off; PP keeps „amount higher than due allowed" for compatibility. |

Defaults chosen where the owner has not answered (§15): S3 accepted; rounding is part of the price (refunded pro rata on storno);
web keeps refusing 1–14 Kč with a clear code/text (no web rounding yet); permanent paid-change failure = automatic refund + staff alert.

---------------------------------------------------------------------------------------------------------------------------------
## 1. Rounding rule (D1/D2) — exact

Definitions (all amounts in CZK, 2 decimals; Stripe charges whole haléře, the app always sends whole crowns):
- `due` = the SERVER amount the customer owes for this payment:
  - booking / resume / restore / sos: `bookings.total_price` (unpaid booking);
  - edit surcharge (app format): `expected = round(change.total_price − bookings.total_price)` (PP:686);
  - web-format edit / gear / swap: server dry-run `net_diff` / `net` (may be fractional, e.g. 7.50);
  - e-shop: `shop_orders.total`.
- `MIN = 15.00`, `WAIVE_MAX = 1.00`.

| due | kind | charged by card | `card_rounding` recorded | folded total after |
|---|---|---|---|---|
| ≤ 0 | free (existing paths) | 0 | 0 | unchanged |
| 0 < due ≤ 1.00 | **waive** | 0 (no Stripe call) | `−due` | `total − due` (booking → 0, edit → old total, shop → 0) |
| 1.00 < due < 15.00 | **round** | 15.00 | `15 − due` | `+ (15 − due)` |
| ≥ 15.00 | normal | `round(due)` (today) | 0 | unchanged |

Examples: due 0.60 → waive, rounding −0.60 · due 1.00 → waive · due 1.01 → charge 15, rounding +13.99 · due 7.50 (swap) → charge 15,
rounding +7.50 · due 14.60 → charge 15, rounding +0.40 (today 4.1.3 charges 15 silently, unrecorded) · due 15.40 → charge 15 (existing
±1 tolerance, unrecorded — unchanged behaviour).

Rules:
1. The server never charges an amount different from the request `amount` (rounded to whole Kč). Rounding to 15 happens ONLY when the
   request carries `card_min: true` AND `round(amount) === 15`. A waiver happens ONLY with `card_min: true` AND `amount ≤ 1`.
   Old apps (no `card_min`) with a charge `< 15` get `400 below_minimum` — never a different charge (backward-compat rule §11).
2. Rounding/waiver is classified on the server `due`, never on the client amount.
3. Rounding is recorded on the row the money belongs to: the booking (new/resume/restore, edit-replace, swap-replace), the NEW booking B
   (swap split), the shop order.
4. Rounding is repeat-safe: a second request for the same unpaid booking sees `total_price = 15` (already rounded) → normal path.

---------------------------------------------------------------------------------------------------------------------------------
## 2. Data model (SQL draft S1 — `paydec/sql/20261016p1_card_rounding.sql`)

```
ALTER TABLE public.bookings    ADD COLUMN IF NOT EXISTS card_rounding numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.shop_orders ADD COLUMN IF NOT EXISTS card_rounding numeric(10,2) NOT NULL DEFAULT 0;
COMMENT … 'Dorovnání na minimální platbu kartou (+) / odpuštěná částka do 1 Kč (−); JE ZAHRNUTO v total_price / total.'
```
Semantics — **folded**: `bookings.total_price` / `shop_orders.total` = amount payable INCLUDING the rounding. `card_rounding` is the
cumulative signed sum of all roundings applied to the row (initial payment + later surcharges). Consequences (all intentional):
- storno / process-refund customer cap (`Σreceived − refunded − total_price`, process-refund:581-616) stay correct with no change;
  the rounding is refunded pro rata like the rest of the price (owner Q2 default);
- delta-based edits (`newTotal = oldTotal + diff`, `reservation_edit_price_calc.dart:451-457`) keep it; swap REPLACE keeps it;
- documents derive the rental line as `total − extras − delivery + discount + loyalty + late − card_rounding` and print the rounding as
  its own line → every document sums to exactly what was charged.
  (After a later shortening with pro-rata refund the rental line absorbs the refunded share of the rounding; documents still balance.)

Guard (bookings only; pattern of `_protect_booking_mileage`, 20260929f): trigger `trg_protect_card_rounding`
BEFORE INSERT OR UPDATE OF card_rounding ON bookings, function `_protect_card_rounding()` (same shape as the live mileage guard:
SECURITY DEFINER, `SET search_path = public`; `auth.uid()` still reflects the caller's JWT):
`IF auth.uid() IS NOT NULL AND NOT COALESCE(is_admin(), false)` → INSERT: `NEW.card_rounding := 0`; UPDATE: `NEW.card_rounding :=
OLD.card_rounding`. Service role (PP/WR), admin (Velín) and direct DB unaffected. `shop_orders` needs no guard (customers have only
SELECT RLS; inserts go through SECURITY DEFINER `create_shop_order`, default 0).
(Pre-existing, out of scope, noted for the owner: customers can still UPDATE `bookings.total_price` directly — the app's client-side
edit apply relies on it. The new app no longer writes it (§9 A4); a guard can follow once 4.1.3 is gone.)

KF: `generate_final_invoice_on_complete()` — body copied 1:1 from live (`live_schema.sql:9721-9876`) plus:
`v_rounding := COALESCE(NEW.card_rounding, 0)`; `v_base_rental := … − v_rounding`; after the late-pickup line:
`IF v_rounding <> 0 THEN items += {description: CASE WHEN v_rounding > 0 THEN 'Dorovnání na minimální platbu kartou (15 Kč)'
ELSE 'Zaokrouhlení – částka do 1 Kč se neúčtuje' END, qty 1, unit_price v_rounding}`; `card_rounding` added to the assertion
`request_data`. Nothing else changes (DP deduction, credit notes, overpay credit note).

STATE updates after approval: STATE_2 (both columns), STATE_3 (KF function), STATE_4 (guard trigger), STATE_6 (changelog).

---------------------------------------------------------------------------------------------------------------------------------
## 3. Where the rounding is stored and shown

| Place | What | How |
|---|---|---|
| DB `bookings.card_rounding` | cumulative signed rounding of the booking | written only by service role: PP (booking round/waive), shared extension-apply (edits), swap RPC rev.12 (S3) |
| DB `shop_orders.card_rounding` | signed rounding of the order | PP (shop round/waive) |
| `bookings.modification_history[]` entry | `card_rounding: r` (+ `price_diff` = charged amount incl. r, `payment_ref`) | shared extension-apply / swap RPC |
| Stripe PaymentIntent metadata | `due`, `card_rounding`, `attempt_id`, `chg_hash` | PP; used by WR + `complete_extension` |
| `financial_events` | PI amount (15) | unchanged (correct automatically) |
| Booking ZF/DP (GI standard) | line „Dorovnání na minimální platbu kartou (15 Kč)" `+r` or „Zaokrouhlení – částka do 1 Kč se neúčtuje" `−r`; rental base `−= card_rounding` | E3 |
| Edit DP (GI `source=edit`) | itemized lines for `priceDiff − r` + explicit rounding line `r` (from the fresh last history entry) | E3 |
| KF (SQL trigger) | same line from `NEW.card_rounding` | S1 |
| Shop ZF/DP/FV (GI shop branch) | line after „Sleva" from `shop_orders.card_rounding` | E3 |
| Swap split: booking B docs | B `total_price` includes r, `B.card_rounding = r` → B's ZF/DP/KF show the line | S3 + E3 |
| E-mails | no template change: every mailed amount is `total_price` / `total` / `price_difference` = the charged amount; the explicit line is on the attached ZF/DP | — |
| App: payment screen, shop checkout, edit price box, swap net line | „Minimální platba kartou je 15 Kč – zaplatíš 15 Kč" / „Částky do 1 Kč neúčtujeme" + line + button label „Zaplatit 15 Kč" | §9 |
| App: result / thank-you | „Zaplaceno 15 Kč (z toho dorovnání 8 Kč)" | §9 |
| App: reservation detail → payment tab | line from `card_rounding` | §9 A14 |
| Velín (optional V1) | read-only line in BookingDetail price block and shop order detail | §8 |

Waived payments produce no ZF/DP (GI zero guard `total_price <= 0`, GI:671-679; edit DP skipped for `priceDiff ≤ 0`) — correct, nothing
was paid; the KF shows the negative rounding line.

---------------------------------------------------------------------------------------------------------------------------------
## 4. process-payment (PP) — API and behaviour (D1, D2, D4)

### 4.1 Module split (index.ts is 1190 lines; new logic only in modules, index.ts gets wiring)
- `process-payment/card-minimum.ts` — `CARD_MIN_CZK = 15`, `WAIVE_MAX_CZK = 1`, `classifyDue({due, amount, cardMin})`, CAS writers
  `roundBooking`, `waiveBooking`, `roundShop`, `waiveShop` (compare-and-set via supabase-js filters, see 4.4).
- `process-payment/intent-guard.ts` — `idempotencyKey()`, `chgHash()`, `guardStoredIntent()` (refuse / reuse / cancel), `markCheckoutStarted()`.
- `process-payment/refusals.ts` — `refuse(status, code, extra)` + the Czech server-text table (§10.2) + `declineMessageCs()` for off-session
  `message`.
- `process-payment/stripe-errors.ts` — `mapStripeError(err)` → `{status, code, error, stripe_code}`.
- `process-payment/complete-extension.ts` — handler of `action: 'complete_extension'`.
- `_shared/extension-apply.ts` — moved from WR (`applyExtensionChange`, `placeFingerprint`, `chgFromMetadata`) + rounding + F1 fix +
  result type + swap commit with 7→6-arg fallback (§5). PP and WR both import it.

### 4.2 Request (app → PP), additive, all optional
| field | type | meaning |
|---|---|---|
| `card_min` | `true` | client understands rounding/waiver; `amount` = what the client SHOWS as the card charge (15 for round-up, 0 for waiver). New app always sends it. |
| `attempt_id` | string ≤ 64 `[A-Za-z0-9-]` | one value per customer "Zaplatit" tap; re-used only when the app re-sends the identical request after an uncertain network result. Invalid → ignored. |
| `action: 'complete_extension'` + `payment_intent_id` | | D6 completion (4.8) |
Everything else unchanged (`type`, `booking_id`, `order_id`, `amount`, `payment_method_id`, `change`, `mode`, `source`).

### 4.3 Response additions
- success (intent / off-session): `charge` (Kč actually charged), `due`, `card_rounding` (0 when none), `reused: true` when an existing PI
  was returned; off-session `succeeded` now also returns `client_secret` (lets the app verify the PI after a restart — understand §5).
- waiver: `{success:true, free:true, waived:true, due, card_rounding:-due, charge:0, booking_id|order_id}`; extension waiver additionally
  `applied:true, state:'applied'|'already_applied', total_price`.
- every refusal: `{success:false, code, error, …extras}` — `code` stable snake_case (table 4.9), `error` Czech, no contact data, tells
  what/why/how (shown verbatim by 4.1.3). HTTP statuses kept where they exist today.
- `off_session_charge_failed` keeps its 200 shape (`error:'off_session_charge_failed', error_code, decline_code, message`) + `code:
  'off_session_charge_failed'`, `payment_intent_id` (if Stripe returned one), and `message` becomes the Czech text from
  `declineMessageCs()` (4.1.3 shows `message` in cs; today it is raw English Stripe text).

### 4.4 Order of operations (pseudo-code, new parts **bold**)
```
0  OPTIONS / web verify actions / create_sos_payment_link / web booking & shop checkout  (PF guards, 4.10)
1  **action === 'complete_extension' → handleCompleteExtension (4.8)**
2  type check (invalid_type) · **missing_booking_id / missing_order_id / invalid_amount codes** · amount finite
3  booking | sos:
     load booking (user_id, status, payment_status, total_price, card_rounding?, sos_replacement, stripe_payment_intent_id)
     auth owner (auth_required / forbidden) · not_sos_replacement
     payment_status = paid → 409 already_paid (+already_paid:true)
     **status = cancelled → 409 booking_cancelled** (also before the free path: confirm_payment would revive a staff-cancelled booking)
     **voucher check: every booking_discounts voucher must be status 'active' or ('redeemed' AND booking_id = this) → 409 voucher_unavailable (+code)**
     **guardStoredIntent step A (refuse succeeded/processing/requires_capture → 409 payment_in_progress)**
     due = total_price ; c = classifyDue(due, amount, card_min)
       free  → **cancel live stored PI (step B)** → existing 100 % path (+codes free_mismatch/free_confirm_failed)
       waive → **cancel live PI → waiveBooking CAS → confirm_payment(p_method 'free') → waiver response** (saved-card request:
               same body + off_session:true,status:'succeeded' so any client routing works)
       below → 400 below_minimum {due, min:15, charge:15, update_required: !card_min}
       round → **roundBooking CAS** (column missing → 409 rounding_unavailable) ; charge = 15
       ok    → existing `amount ≥ due − 1` else 409 amount_mismatch(server_total) ; charge = round(amount)
4  shop:
     load order (+card_rounding?) · auth · already_paid · wrong_status · **guard step A**
     due = total ; c = classifyDue
       free (due ≤ 0) → 409 no_payment_needed (existing; app maps to success)
       waive → **cancel live PI → waiveShop CAS → confirmShopPayment(…, method 'free') → waiver response**
       below → 400 below_minimum ; round → **roundShop CAS** ; ok → existing exact check (amount_mismatch)
5  extension:
     existing validation (ownership, wrong_status, _base stale, dry-run / app-format checks) → expected
     **guard step A on stored PI: if it is an `extension` PI that succeeded → ensureApplied(pi) via shared apply first
       (completes a paid-but-unapplied change; transient failure → 409 payment_in_progress {pending_change:true}); processing → 409
       payment_in_progress**
     c = classifyDue(expected, amount, card_min)
       waive → requires metadata.chg present (else 409 change_too_large) and, for `_swap`, S3 (else 409 rounding_unavailable)
               → shared apply NOW (paid 0, rounding −expected, payRef 'waive:'+sha256(booking_id|chg)[0..15]) → waiver response
       below → 400 below_minimum
       round → requires chg present (else change_too_large) and S3 for swaps → metadata.card_rounding = 15 − expected ; charge 15
       ok    → existing |amount − expected| ≤ 1 else 400 amount_mismatch(expected) ; charge = round(amount)
       (expected ≤ 0 keeps today's ±1 check; the app never pays ≤ 0 edits)
6  **guardStoredIntent step B (requires_payment_method | requires_confirmation | requires_action):
       reuse when: sheet request (no payment_method_id) ∧ pi.amount = charge·100 ∧ pi.currency czk ∧ pi.metadata.type = type ∧
       pi.metadata.chg_hash = chgHash → return its client_secret (+ fresh ephemeral key), reused:true
       otherwise stripe.paymentIntents.cancel(pi); cancel fails because the PI moved on → re-retrieve → succeeded/processing → 409
       payment_in_progress**
7  **booking | sos: bookings.checkout_started_at = now()  (cron grace, §6.4)**
8  create PI with **{ idempotencyKey }**, metadata += {attempt_id, chg_hash, due, card_rounding?}; **store PI id AWAITED (1 retry, log on fail)**
9  off-session: existing branches + client_secret on succeeded + Czech `message` on failure
10 outer catch → **mapStripeError** (4.7)
```
CAS writers (atomic without SQL helpers): read `(total_price|total, card_rounding)` = `(t0, c0)`, then
`update({total_price: 15, card_rounding: c0 + (15 − t0)}).eq('id', id).eq('total_price', t0).eq('card_rounding', c0)
 .eq('payment_status', 'unpaid'|'pending').select('id')`; 0 rows → re-read once and re-classify (concurrent request already rounded →
`due = 15` → ok). Waiver: `{total_price: 0, card_rounding: c0 − t0}` with the same filters plus `.gt('total_price', 0).lte('total_price', 1)`.
Booking status filter: `status in (pending, reserved)`. Column missing (`42703` / `PGRST204` / message contains `card_rounding`) →
`rounding_unavailable` (feature detection; old apps never reach this branch).

### 4.5 One live PaymentIntent per booking/order (in-progress guard)
Source of truth: `bookings.stripe_payment_intent_id` / `shop_orders.stripe_payment_intent_id` (PP already overwrites it with every new PI,
including extension PIs, PP:1057-1061). Guard reads it (`pi_…` only), `stripe.paymentIntents.retrieve`, and checks the PI belongs to this
row (`metadata.booking_id` / `order_id`):
| stored PI status | booking / shop | extension request |
|---|---|---|
| succeeded, processing, requires_capture | 409 `payment_in_progress` {payment_intent_id, pi_status} (DB not yet paid = webhook pending) | type `extension`: succeeded → ensureApplied then continue (new request will hit `stale_booking` because `_base` changed — app reloads); processing → 409 `payment_in_progress`. Type `booking` (original payment) → ignored. |
| requires_payment_method / requires_confirmation / requires_action | reuse if identical sheet request, else cancel then create | same |
| canceled / not found / not ours / retrieve error | proceed (guard is a safety net; Stripe outage must not block paying) | proceed |
Guarantee: at most one chargeable PI per booking/order at any time → the FAB / second device / "Zkusit znovu" cannot double charge.

### 4.6 Idempotency keys (Stripe)
`paymentIntents.create(params, { idempotencyKey })`, key = `pp1:{type}:{booking_id|order_id}:{chargeCents}:{payment_method_id|'sheet'}:
{attempt_id || 'm' + floor(now/60000)}:{chgHash||'-'}` (≤ 255 chars). Same key + same params → Stripe returns the original PI (a lost
response on a saved-card charge + automatic resend = no second charge); same key + different params → Stripe `idempotency_error` →
409 `duplicate_request`. Old apps (no attempt_id) get the minute bucket (as the earlier D4 patch draft). Refunds dispatched for failed paid
changes use process-refund's own guards plus a once-per-PI check (§5.4). `chgHash` = first 16 hex of SHA-256 of `JSON.stringify(change)`.

### 4.7 Stripe error mapping (outer catch; replaces `'Payment processing failed: ' + message`)
| Stripe error | HTTP | code | `error` (cs) |
|---|---|---|---|
| `amount_too_small` | 400 | `below_minimum` | §10.2 |
| `idempotency_error`, `idempotency_key_in_use` | 409 | `duplicate_request` | „Stejná platba se právě zpracovává. Nic dalšího neplať – za pár vteřin uvidíš výsledek v Rezervacích." |
| StripeRateLimitError, StripeConnectionError, StripeAPIError (5xx) | 503 | `stripe_unavailable` | „Platební brána teď neodpovídá. Nic jsme nestrhli – zkus to prosím za minutu znovu." |
| other Stripe / non-Stripe | 500 | `server_error` | „Platbu teď nejde dokončit kvůli chybě na našem serveru. Nic jsme nestrhli – zkus to prosím za minutu znovu." |
Raw Stripe text goes only to `debug_log` and to the response field `stripe_code` (never to `error`).

### 4.8 `action: 'complete_extension'` (D6)
Request `{action:'complete_extension', payment_intent_id:'pi_…'}`, owner JWT (or service/admin).
```
auth none → 401 auth_required
pi = retrieve (Stripe error → 503 stripe_unavailable; missing → 404 not_found)
pi.metadata.type ≠ 'extension' → 409 not_extension
booking = pi.metadata.booking_id → owner check (403 forbidden)
pi.status:
  succeeded → r = applyPaidExtension({bookingId, chg: chgFromMetadata, srv, paidCzk: pi.amount/100, payRef: pi.id,
                                      rounding: Number(pi.metadata.card_rounding || 0)})
      applied | already_applied → 200 {success:true, state, booking_id, new_booking_id?, total_price}
      no_payload               → 200 {success:true, state:'client_apply'}   (chg did not fit metadata; legacy client apply)
      retry                    → 503 {success:false, state:'retry', code:'apply_failed'}
      failed                   → 200 {success:false, state:'failed', code:'change_failed', reason, refund:'auto'|'staff', amount}
  processing | requires_capture → 202 {success:false, state:'pending', code:'payment_processing'}
  requires_* | canceled         → 200 {success:false, state:'not_paid', code:'not_paid'}
```
Idempotent by construction (shared apply dedupes on `payment_ref`; swap RPC returns `already_split` / `invalid_new_moto` when done).

### 4.9 PP refusal codes (complete)
`error` texts = §10.2. „New" = no code today.
| code | HTTP | when | extras | new? |
|---|---|---|---|---|
| `invalid_type` | 400 | unknown `type` | | |
| `missing_booking_id` | 400 | booking/extension/sos without booking_id | | new |
| `missing_order_id` | 400 | shop without order_id | | new |
| `invalid_amount` | 400 | amount missing / not finite | | new for missing |
| `auth_required` | 401 | no/invalid JWT | | |
| `forbidden` | 403 | not the owner | | |
| `booking_not_found` / `order_not_found` | 404 | | | |
| `already_paid` | 409 | booking/order already paid | `already_paid:true` | new for booking |
| `booking_cancelled` | 409 | booking cancelled (cron / customer / staff) | | new |
| `wrong_status` | 409 | order not pending; edit of cancelled/completed booking | | |
| `no_payment_needed` | 409 | shop total ≤ 0 | | |
| `not_sos_replacement` | 409 | | | |
| `voucher_unavailable` | 409 | a voucher of the booking was used elsewhere / expired | `voucher_code` | new |
| `below_minimum` | 400 | 0 < charge < 15 without card_min, or card_min with wrong amount | `due, min:15, charge:15, update_required` | new for booking/extension |
| `rounding_unavailable` | 409 | S1/S3 not deployed yet | | new |
| `change_too_large` | 409 | rounding/waiver of a change whose payload does not fit Stripe metadata | | new |
| `amount_mismatch` | 409 / 400 | booking: amount < due − 1 (`server_total`); extension: |amount − expected| > 1 (`expected`); shop: ≠ total (`server_total`) | | |
| `free_mismatch` | 400 | amount 0 but total > 0 / not a true 100 % discount | `server_total` | new |
| `free_confirm_failed` | 500 | confirm_payment failed on free/waiver | | new |
| `payment_in_progress` | 409 | stored PI succeeded/processing (or paid change pending) | `payment_intent_id, pi_status, pending_change?` | new |
| `duplicate_request` | 409 | Stripe idempotency conflict | | new |
| `validation_unavailable` | 409/503 | validation could not run (fail closed) | | |
| `stale_booking` | 409 | edit priced against an old state | | |
| dry-run/app-format: `moto_unavailable`, `trailer_staffed_only`, `trailer_unavailable`, `trailer_check_unavailable`, `delivery_fee_guard`, `location_requires_route`, `active_pickup_time_locked` | 409 | | | |
| swap dry-run: `not_found`, `not_paid`, `invalid_new_moto`, `swap_date_out_of_range`, `already_split`, `license_insufficient`, `new_moto_unavailable`, (`payment_required` if S3b) | 409 | now each with its own Czech text (no raw code in text) | | text new |
| `change_not_applicable` | 409 | any other dry-run code | `reason` (raw code, for logs/app) | new |
| `stripe_unavailable` / `server_error` | 503 / 500 | 4.7 | `stripe_code` | new |
| `off_session_charge_failed` / `off_session_unexpected_status` | 200 | saved-card charge failed / odd status | `error_code, decline_code, message(cs), payment_intent_id` | code added |
| complete_extension: `not_extension`, `not_paid`, `payment_processing`, `apply_failed`, `change_failed` | 409/200/202/503/200 | 4.8 | | new |

### 4.10 Minimum for the other payment entry points (PF)
`handleWebBookingCheckout` (session total), `handleWebShopCheckout`, `handleSosPaymentLink` (Velín operator amount), PP `mode:'checkout'`
web edit: `0 < amount < 15` → 400 `below_minimum` with a web text („Kartou jde zaplatit nejméně 15 Kč – zbývá {due} Kč. Uprav prosím
rezervaci/objednávku, nebo ji dokonči v aplikaci MotoGo24, která drobnou částku dorovná.") — web rounding = owner Q3 (later; would need
a visible Checkout line item). Velín SOS link: „Minimální částka platby kartou je 15 Kč – zadej prosím alespoň 15 Kč."

---------------------------------------------------------------------------------------------------------------------------------
## 5. Shared extension apply + webhook (D6, F1)

### 5.1 `_shared/extension-apply.ts` API
```ts
export type ApplyResult =
  | { state: 'applied' | 'already_applied'; bookingId: string; newBookingId?: string; totalPrice?: number }
  | { state: 'no_payload' }
  | { state: 'retry'; code: string; detail?: string }            // transient: RPC/network/DB 5xx, optimistic-lock lost twice
  | { state: 'failed'; code: string; reason: string }            // permanent
export function chgFromMetadata(md): string | null
export function placeFingerprint(r): string
export async function applyPaidExtension(sb, a: { bookingId; chg; srv; paidCzk; payRef; rounding }): Promise<ApplyResult>
export async function handlePaidChangeFailure(sb, a: { bookingId; payRef; paidCzk; reason; kind }): Promise<'auto'|'staff'>
```
Pure move first (diff-reviewable), then the additions below. `placeFingerprint` is removed from PP and WR and imported.

### 5.2 Additions to the app-format / web branch
1. **Rounding**: `r = rounding` (from `metadata.card_rounding`; waiver = `−due`). Target total `T = (srv.t ?? a.new_total ?? a.total_price) + r`;
   same UPDATE writes `card_rounding = cur.card_rounding + r` (only when `r ≠ 0`, so the path works without S1 when r = 0); history entry
   gets `card_rounding: r`, `price_diff: paidCzk` (= 15 for a rounded edit, 0 for a waiver).
2. **F1 fix (already applied by an old app's client-side UPDATE)**: before stale detection compute `alreadyApplied` = every non-total
   target column in `d` equals `cur` AND `round(cur.total_price) ∈ {round(T − r), round(T)}`. Then: no `cur + paid` arithmetic; if the
   history lacks this `payment_ref` → append the history entry (+ `total_price = T`, `card_rounding += r` when r ≠ 0) → `applied`; else
   `already_applied`. The stale branch stays for genuinely different rows (it already adds `paidCzk`, which includes r; also adds
   `card_rounding += r`).
3. **Optimistic lock**: select `updated_at` with `cur`; `update(d).eq('id').eq('updated_at', cur.updated_at).select('id')`; 0 rows → re-read
   and re-evaluate once (second pass finds `payment_ref` → `already_applied`); still 0 → `retry`. Closes the webhook ↔ complete_extension
   race (both may run within the same second).
4. **Result classification**: PostgREST error code `P0001`/`23505`/`23514`/`23P01` (trigger refusal: overlap, branch closed, delivery
   guard) → `failed` (`change_failed`); network / 5xx / timeout → `retry`.

### 5.3 Swap branch
`commitSwap(sb, {bookingId, swap:{m,d,t}, rounding: r})`: call `split_booking_moto_swap` with `p_card_rounding: r` (S3). `PGRST202` /
`42883` (7-arg missing) → if `r === 0` retry with the 6-arg call, else `retry` (rounding needs S3; PP never creates such PIs without S3,
so this only happens in the deploy window). Outcome: `success` → `applied` (+ `new_booking_id`); `already_split` / `invalid_new_moto` →
`already_applied`; `new_moto_unavailable`, `wrong_status`, `not_paid`, `swap_date_out_of_range`, `not_found`, `forbidden`,
`license_insufficient`, `trailer_staffed_only` → `failed`; RPC error / exception → `retry`. Debug log actions keep their names
(`swap_commit_applied` / `swap_commit_failed`) + `state`.

### 5.4 Webhook (`payment_intent.succeeded`, `checkout.session.completed` extension paths)
- Call `applyPaidExtension` (payRef = PI id, or session id for web checkout as today; `rounding` from metadata).
- `retry` → set `retryNeeded = true`, continue with the remaining idempotent steps (card brand, PM attach, financial event, bundled
  shop), and at the end return **500** (`debug_log` `paid_change_retry`) → Stripe redelivers (exponential backoff, up to 3 days). All steps
  are idempotent (confirm_payment `was_already_paid`, history `payment_ref`, financial event by PI id, swap RPC idempotency).
- `failed` → `handlePaidChangeFailure` (once per `payRef`, dedupe = existing `debug_log` row `paid_change_failed` with
  `request_data->>payment_ref`): default (owner Q4) **automatic refund** of the paid surcharge via process-refund `{booking_id, amount:
  paidCzk, reason:'paid_change_failed', source:'edit'}` (service key; refund cap = Σreceived − refunded − total_price allows exactly the
  unapplied surcharge) + staff alert (`debug_log` status `error` action `paid_change_failed` + internal e-mail through the existing
  internal mail path to the company address — not customer-facing). Return 200.
- `payment_intent.payment_failed`: still not handled (nothing to do; app learns from the SDK).

---------------------------------------------------------------------------------------------------------------------------------
## 6. Restore — „Obnovit a zaplatit" (D3, SQL draft S2 — `paydec/sql/20261016p2_customer_restore.sql`)

### 6.1 Columns
`bookings.restored_by_source text` (NULL = Velín/legacy, `'app'`), `bookings.restore_count smallint NOT NULL DEFAULT 0` (anti-abuse).
`restored_at` and `checkout_started_at` already exist (STATE_2).

### 6.2 `_customer_restore_check(p_b bookings, p_uid uuid) RETURNS jsonb` — internal, SECURITY DEFINER, no GRANT to clients
Returns `NULL` when restorable, else `{error, code?}`:
| check | error |
|---|---|
| `p_uid` NULL or ≠ `user_id` | `forbidden` |
| `status ≠ 'cancelled'` | `not_cancelled` |
| `payment_status ≠ 'unpaid'` or `picked_up_at` NOT NULL or `sos_replacement` | `not_restorable` |
| `cancelled_by_source IN ('admin','velin','stripe_portal')` | `cancelled_by_staff` |
| `start_date ≤ today (Europe/Prague)` | `date_passed` |
| `restore_count ≥ 3` | `restore_limit` |
| a non-Slevomat voucher in `booking_discounts` (kind voucher) or legacy `discount_code` not `active` or `valid_until < start_date` | `voucher_unavailable` (+`code`) |
| a promo code in `booking_discounts`: `active = false`, `valid_to < now()`, or `max_uses` reached (count `promo_code_usage` excluding this booking) | `promo_unavailable` (+`code`) |
Price re-check decision: the rental price, loyalty and late-pickup amounts stay as originally quoted (the customer restores the quote they
had; cancellation was for non-payment, not a price change); only the discounts that can be double-spent or have lapsed are re-validated.
The current `total_price` (incl. any `card_rounding`) is returned to the app as the amount due. (Owner may request a full re-price later.)

### 6.3 `customer_restore_booking(p_booking_id uuid) RETURNS jsonb` — SECURITY DEFINER, `SET search_path = public`
```
v_uid := auth.uid(); NULL → {success:false,error:'forbidden'}
SELECT … FOR UPDATE; NOT FOUND → not_found
v_err := _customer_restore_check(b, v_uid); IF v_err → {success:false} || v_err
re-redeem vouchers (non-Slevomat, status 'active' → 'redeemed', redeemed_at now(), redeemed_by v_uid, booking_id p_booking_id);
  row count ≠ expected → voucher_unavailable (nothing changed: RAISE inside a sub-block → rollback to savepoint)
UPDATE bookings SET status 'pending', payment_status 'unpaid', cancelled_at/by/by_source/cancellation_reason NULL,
  cancellation_notified false, restored_at now(), restored_by_source 'app', restore_count +1, checkout_started_at NULL
EXCEPTION overlap/trailer/branch-closed triggers (SQLSTATE P0001, 23505, 23514, 23P01) → moto_unavailable (savepoint rollback)
RETURN {success:true, restored_at, total_price, card_rounding, window_minutes:30}
REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated, service_role
```
Re-redeeming at restore closes the double-spend window (today vouchers are redeemed only on `paid`, `redeem_booking_discounts_on_paid`
updates `WHERE status='active'` and silently no-ops when the voucher was used meanwhile). If the restored booking is cancelled again,
`restore_vouchers_on_cancel` releases them as today; on payment the redeem trigger no-ops (already redeemed for this booking).

### 6.4 Old apps (4.1.3 restores by direct UPDATE cancelled → pending)
Trigger `trg_customer_restore_stamp` BEFORE UPDATE OF status ON bookings (name sorts after `_trg_guard_customer_booking_status`), function
SECURITY DEFINER: only when `current_user IN ('authenticated','anon') AND NOT is_admin() AND OLD.status = 'cancelled' AND NEW.status =
'pending'` (SECURITY DEFINER RPCs run as owner → skipped; Velín admin → skipped):
- `_customer_restore_check(OLD, auth.uid())` fails → keep the row cancelled (`NEW.status := OLD.status`, `NEW.payment_status`,
  `cancelled_*` := OLD values), `debug_log` `customer_restore_refused`; 4.1.3 then hits PP `booking_cancelled` with a clear Czech text
  (no charge).
- passes → re-redeem vouchers, `NEW.restored_at := now()`, `restored_by_source := 'app'`, `restore_count := OLD.restore_count + 1`,
  `checkout_started_at := NULL`.

### 6.5 Cron `auto_cancel_expired_pending()` (body 1:1 from live `live_schema.sql:5805-5886`, only the WHERE changes)
```
WHERE status = 'pending' AND payment_status = 'unpaid'
  AND (
    (restored_at IS NULL AND ((booking_source = 'app' AND created_at < now() - interval '30 minutes')
                            OR (booking_source = 'web' AND created_at < now() - interval '4 hours')))
    OR (restored_by_source = 'app' AND restored_at < now() - interval '30 minutes')
    -- restored in Velín (restored_by_source NULL) → never auto-cancelled (unchanged)
  )
  -- payment in flight: PP stamped checkout_started_at when it created the PaymentIntent → 10 min grace,
  -- hard cap 60 min from the window start (no endless hold by repeated PP calls)
  AND NOT (checkout_started_at IS NOT NULL AND checkout_started_at > now() - interval '10 minutes'
           AND COALESCE(restored_at, created_at) > now() - interval '60 minutes')
```
cancellation_reason for app-restored rows: „Automaticky zrušeno — nezaplaceno do 30 minut". Web abandoned-mail path unaffected
(`send_abandoned_booking_emails` filters `booking_source = 'web'` and only selects `checkout_started_at`).

### 6.6 Interaction summary
Restore → `restored_at = now()` → app PaymentScreen countdown from `restored_at` (already, booking_restore.dart:160) and FAB from
`max(created_at, restored_at)` (§9 A11) → PP sets `checkout_started_at` → cron cannot cancel during the payment → webhook `confirm_payment`.
If the cron cancelled before the PI was created → PP `booking_cancelled` (no charge, no silent revive). Velín restore unchanged.

---------------------------------------------------------------------------------------------------------------------------------
## 7. Swap RPC rev.12 (SQL draft S3 — `paydec/sql/20261016p3_swap_card_rounding.sql`)
- `DROP FUNCTION IF EXISTS public.split_booking_moto_swap(uuid, uuid, date, text, boolean, boolean);`
  `CREATE OR REPLACE FUNCTION public.split_booking_moto_swap(…same 6…, p_card_rounding numeric DEFAULT 0)` — body 1:1 from
  `20260922a_swap_rev11_admin_exempt_trailer_guard.sql` (= live) plus:
  - `v_round numeric := 0;` after `v_net` is known: `IF v_admin AND NOT p_dry_run AND COALESCE(p_card_rounding,0) <> 0 THEN
    IF p_card_rounding BETWEEN -1 AND 14 AND v_net + p_card_rounding >= 0 THEN v_round := p_card_rounding; ELSE debug_log
    'swap_rounding_ignored'; END IF; END IF;` (customer JWT can never set it);
  - REPLACE: `total_price = GREATEST(total_price + v_net + v_round, 0)`, `card_rounding = card_rounding + v_round`, history entry
    `'price_diff', v_net + v_round` and `'card_rounding', v_round` (when ≠ 0);
  - SPLIT: B insert `total_price = GREATEST(v_b_total − v_b_late − v_b_disc + v_round, 0)`, `card_rounding = v_round`;
  - both return objects add `'card_rounding', v_round`.
- Grants recreated exactly as live (verified `live_schema.sql:31873-31875`: PUBLIC revoked, `authenticated` + `service_role` only):
  `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated, service_role;`
  `NOTIFY pgrst, 'reload schema';` (named-parameter calls from app 4.1.3 / web resolve to the 7-arg function via the default).
- **S3b (optional, owner Q1b — pre-existing F2)**: `IF NOT p_dry_run AND NOT v_admin AND v_net > 1 THEN RETURN {success:false,
  error:'payment_required'}` — closes "commit a paid-size swap without paying". Impact: web's after-return client commit
  (`pages-upravit-rezervaci-swap.js:380`) and 4.1.3's client commit get `payment_required` when the webhook has not committed yet; both
  then rely on the webhook (which now retries). Web would show its generic failure briefly → recommend shipping S3b together with a
  one-line web mapping (`payment_required` → treat as "dokončuje se"). Default: S3b NOT included until the owner confirms.

---------------------------------------------------------------------------------------------------------------------------------
## 8. Other edge / Velín changes
- **E3 generate-invoice**: (a) booking standard: `cardRounding = Number(booking.card_rounding || 0)`; `baseRental −= cardRounding`; after
  discount/loyalty/late lines push the rounding line when `|cardRounding| ≥ 0.01` (labels §3). (b) edit: `r = Number(last.card_rounding
  || 0)` only when the last history entry is fresh (same rule as today) and `price_diff` equals `priceDiff`; itemize `priceDiff − r` as
  today (+ „Korekce ceny úpravy" computed against `priceDiff − r`) and add the rounding line; generic branch: line `priceDiff − r` + rounding
  line. (c) shop (ZF/DP/FV): line after „Sleva" from `order.card_rounding`. Dedup logic untouched (totals already include rounding).
  Missing column → `undefined` → 0 (works before S1).
- **E4 payment-flows.ts**: `below_minimum` guards (4.10); `confirmShopPayment` gets an optional `method = 'card'` parameter (PC) so PP
  can confirm a waived order as `'free'`; PP imports it from `../webhook-receiver/payment-confirmers.ts` (no move).
- **process-refund**: no change (folded rounding keeps the cap right). Accept `reason: 'paid_change_failed'` (free text today — verify).
- **V1 Velín (optional, recommended)**: BookingDetail price block + shop order detail: read-only line when `card_rounding ≠ 0`
  („Dorovnání na min. platbu kartou" / „Zaokrouhlení do 1 Kč"); `debug_log` filter preset `paid_change_failed` (if a log view exists).

---------------------------------------------------------------------------------------------------------------------------------
## 9. App changes (BOTH trees, same content; small targeted edits; re-read before each edit)

| ID | File | Change |
|---|---|---|
| A1 | `features/payment/card_minimum.dart` **NEW** | `cardMinCzk = 15`, `cardWaiveMaxCzk = 1`, `enum CardChargeKind {free, waive, round, normal}`, `class CardCharge {due, charge, rounding, kind}`, `CardCharge cardCharge(num due)` (table §1). `payment_refusals.dart`: remove `belowCardMinimum`/`stripeMinCzk` (callers move to `cardCharge`). |
| A2 | `features/payment/stripe_service.dart` | `createPaymentIntent(…, bool cardMin = true, String? attemptId)` → body `card_min`, `attempt_id`; parse `charge`, `due`, `card_rounding`, `waived`, `applied`, `state`, `reused`, off-session `client_secret` into `PaymentResult` (new fields `waived`, `applied`, `cardRounding`, `charge`); `confirmFreeBooking` sends `card_min:true`; new `static Future<CompleteResult> completeExtension(String piId)` (20 s timeout; network/timeout/5xx → `CompleteState.retry`, 401 → session refresh like createPaymentIntent). Helper `piIdFromClientSecret(cs)` (`pi_x_secret_y` → `pi_x`). |
| A3 | `features/payment/payment_refusals.dart` | remove the `contact` field and every `contact:true`; map all codes of §10.1/§10.2 (new: `booking_cancelled`, `voucher_unavailable`, `rounding_unavailable`, `change_too_large`, `duplicate_request`, `stripe_unavailable`, `server_error`, `change_not_applicable`, swap codes → existing `swap.err.*` keys, `missing_*`, `invalid_amount`); `below_minimum` → new `PayAction.payMin` („Zaplatit 15 Kč": re-run with charge 15 + card_min); `already_paid`/`no_payment_needed` stay success; `payment_in_progress` → pending; `duplicate_request` → verify. |
| A4 | `features/payment/payment_screen.dart` | (a) `_doPayment`: `cc = cardCharge(_amount)`: free → `_confirmFree()`; waive → booking: `_confirmFree(waived:true)` (PP amount 0 + card_min → server waiver), extension: `_applyWaivedChange()` (PP extension amount 0 + card_min → `applied`), then extras rows; round → charge 15; normal → today. Remove the `belowCardMinimum` block (:884-889). (b) amounts: new getter `_charge`; button label „Zaplatit {charge}" / „Potvrdit bez platby"; under the summary a `CardRoundingNote` (new small widget in `widgets/card_rounding_note.dart`) with `pdRoundNote` / `pdWaiveNote` and the line „Dorovnání na minimální platbu kartou +X". (c) `_expectedEditTotal` = `pendingEditChanges['total_price'] + pendingEditChanges['_card_rounding'] ?? 0`. (d) every `createPaymentIntent` call passes `attemptId` (new per tap; kept for automatic resend after uncertain). (e) saved-card `offSessionSucceeded`: store `result.clientSecret` in the marker. (f) extension success: at the start of `_verifyAndComplete()` (PI known succeeded — sheet paid / 3DS succeeded / off-session succeeded) `PaidChangeQueue.enqueue(...)` BEFORE any marker clear; `_onPaymentSuccess` extension branch replaces `_commitSwap` + direct `bookings.update` with `PaidChangeQueue.completeNow(key, timeout: 20 s)` → `applied/already_applied` → success outcome (existing texts + rounding line); `pending/retry/offline` → **„Výměna/Úprava se dokončuje"** outcome (`PaymentOutcomeKind.attention`, CTA „Moje rezervace"); `failed` → failure outcome with precise text (§10.4); `not_paid` → `psNotPaidEdit`; `client_apply` → legacy client UPDATE (kept only for this state; never writes `total_price` when rounding ≠ 0). `_commitSwap` and `_staffOutcome` removed. |
| A5 | `features/payment/payment_screen_problems.dart` | remove all `openContactUs`/`psWriteUs` (:84-91, :119-122, :318-319, :509-510); `PayAction.belowMinimum` for resume → `payMin`; max-attempts sheet: no secondary, texts `pdMaxBookingBody`/`pdMaxEditBody`; draft unknown → `pdDraftServerBody` + „Zkusit znovu". |
| A6 | `features/payment/widgets/payment_error_sheet.dart` | delete the `psHelpLine` footer (:186-196) — sheet is used only by payment/restore/edit/shop flows. |
| A7 | `features/payment/payment_error_mapper.dart` (both; iOS keeps its Apple Pay substitution in `_t`) | decline map changes (§10.3): `lost_card/stolen_card/pickup_card` → generic bank decline; `currency_not_supported` → `pdCurrency*`; `duplicate_transaction` → `needsVerification`; `payment_method_provider_decline` → `pdWalletDeclined*`; `payment_intent_payment_attempt_expired` → `pdAttemptExpiredBody`; `payment_intent_payment_attempt_failed`, `testmode_decline`, `incorrect_zip`, `postal_code_invalid`, `invalid_amount` → generic decline; `amount_too_small` → `pdBelowMin*`; `wallet()`/`walletFailed()` drop the raw-code suffix (log it instead). New keys resolved through `translations` fallback (not in the private maps). |
| A8 | `features/reservations/reservation_edit_screen.dart` (~1058-1121, 1173-1203) | `cc = cardCharge(effDiff)`; waive/round/normal all go to PaymentScreen with `amount: effDiff` (due) and `pendingEditChanges['_card_rounding'] = cc.rounding`; price box: under „Doplatek" show `pdRoundEditHint` / `pdWaiveEditHint`, button „Pokračovat k platbě (+15 Kč)" / „Uložit změnu bez platby"; `showBelowMinimum` removed; `refundSettleManual` → `pdRefundManual`. |
| A9 | `features/reservations/widgets/reservation_edit_states.dart` | drop the four `openContactUs` secondaries (:118-168); texts → `pdEditFail`, `pdMoveFail`, `pdCancelFail`, `pdCancelForbidden`. |
| A10 | `features/reservations/widgets/reservation_swap_section.dart` (~270-300) | `net ≤ 0` → direct commit (unchanged path, threshold `0.5 → 0`); `net > 0` → PaymentScreen with `amount: net` + `_card_rounding`; net line shows `pdRoundSwapHint` / `pdWaiveSwapHint`; server `rounding_unavailable` for `0 < net ≤ 0.5` → fallback to today's direct commit (deploy window only). Remove `belowCardMinimum` block. |
| A11 | `core/pending_booking_fab_provider.dart` | `_fetchPendingBooking` selects `restored_at`; `PendingBooking.createdAt = max(created_at, restored_at)` (so the FAB and the resume ctx built in shell files count from the restore — no shell edit). `paidAfterRestartProvider`: first `await PaidChangeQueue.drain(reason: 'start')`; markers of kind `swap`/`edit` whose PI is succeeded → `PaidChangeQueue.enqueue` (pi id from client secret) before returning; return `PaidAfterRestart(id, kind)` for items completed now. |
| A12 | `core/paid_change_queue.dart` **NEW** | persisted queue — spec 9.1. |
| A13 | `main.dart` (both; whitelisted file, one added call each) | in the existing `OfflineGuard.onBackOnline` lambda add `PaidChangeQueue.drain(reason: 'online')`; in `didChangeAppLifecycleState(resumed)` (if present) the same. |
| A14 | `features/reservations/reservation_models.dart`, `widgets/res_detail_tab_content.dart` | parse `card_rounding`, `restored_at`; payment tab line (`pdMinCardLine` / `pdWaiveLine`); while the queue holds an entry for the booking show a one-line banner „Výměna se dokončuje…" (`pdSwapCompletingShort`); a failed entry shows its §10.4 text once. |
| A15 | `features/shop/shop_checkout_screen.dart` (426-435, 490-500, 343-344, 608-634) | `cc = cardCharge(total)`: waive → PP amount 0 + card_min → `{free, waived}` → success „Objednávka je potvrzená" + `pdWaivedSub`; round → amount 15 + summary line + note; remove all contact buttons (`hasCodes ? Odebrat kód : null`). |
| A16 | `features/reservations/booking_restore.dart` | remove `byStaff()` and `openContactUs`; map RPC errors (§10.5) with actions; RPC missing (`PGRST202`) → `pdRestoreUpdating` + „Zkusit znovu"; success → ctx `amount = r['total_price']` (server due), `bookingCreatedAt = restored_at`. |
| A17 | `core/i18n/translations_ext_43_payments.dart` **NEW** aggregator + `translations_ext_43_payments_{cs,en,de,es,fr,nl,pl,uk}.dart` | all new `pd*` keys (one language per file, each < 5000 tokens); aggregator exports `translationsExt43Payments` (`{'cs': ext43Cs, …}`); `translations.dart`: ONE import + ONE list entry after `translationsExt42Refix3B` (re-read the file right before the edit; Android copy carries v2 lines). Edit the value of `fxSwapPaidNotice` in `translations_ext_41_refix2.dart` (8 langs, no „ozveme se") because the shell listener (v2 file) maps kind `swap` to that key. |
| A18 | tests (both trees) | update `payment_error_states_test.dart` (contact expectations, `belowCardMinimum` → `cardCharge`); new tests §13.3. |

### 9.1 `PaidChangeQueue` (core/paid_change_queue.dart)
- Storage: SharedPreferences key `mg_paid_change_queue_v1` (JSON map key → entry), every access in try/catch.
- Entry: `{key (= PI id), bookingId, piId, clientSecret?, kind: 'swap'|'edit', charge, label, expectedTotal?, extras?: {rows, replace,
  deleteIds, orig}, newMotoId?, createdAt, attempts, nextAt, state: 'pending'|'extras'|'failed', failure?: {code, reason, refund}}`.
- `enqueue(entry)` idempotent by key. `completeNow(key, timeout)` = one attempt in the foreground. `drain({reason})` single-flight (static
  in-flight future), processes entries with `nextAt ≤ now`.
- Per attempt: `StripeService.completeExtension(piId)` →
  `applied/already_applied` → if `extras` → `replaceModeledExtras` (idempotent by row ids; failure → `state:'extras'`, retry only extras) →
  remove entry, invalidate reservation providers, emit `done`;
  `pending` / `retry` / network / timeout / 5xx / auth expired → `attempts++`, `nextAt = now + backoff[attempts]` with backoff
  10 s, 30 s, 1 min, 2 min, 5 min, then every 10 min;
  `not_paid` → remove (nothing charged); `failed` → `state:'failed'` + emit `failed` (UI shows §10.4 once, then removed);
  `client_apply` → legacy client UPDATE path (A4f) then remove.
- Timer: while entries exist and the app is alive, a single `Timer` for the earliest `nextAt`. Drop entries older than 7 days (Stripe
  retries webhooks for 3 days; the server is the primary completer).
- Triggers: enqueue (A4f), app start (A11), back online (A13), app resume (A13), timer.
- No UI coupling: emits a broadcast `Stream<PaidChangeEvent>` read by PaymentResultScreen (live switch from „dokončuje se" to „hotovo")
  and the reservation detail banner.

---------------------------------------------------------------------------------------------------------------------------------
## 10. D5 — complete message catalogue (no contact anywhere; tykání; cs given, 8 languages in implementation)

Rules: every text says (1) what happened, (2) whether money moved, (3) what to do — with a working button. No e-mail, phone, „Napiš nám",
„ozveme se", raw Stripe/English or raw codes. „✓" = existing key reused unchanged; „+" = new key in ext_43; „→" = replacement key
(old key stays defined but unused).

### 10.1 Rounding / D1-D2 (app)
| situation | title | body | action | key |
|---|---|---|---|---|
| 1 < due < 15 (any payment) | — (note under amount) | „Minimální platba kartou je 15 Kč – zaplatíš 15 Kč. Dorovnání {rounding} uvidíš i na dokladu." | „Zaplatit 15 Kč" | + `pdRoundNote`, `pdPayMin`, `pdMinCardLine` = „Dorovnání na minimální platbu kartou" |
| 0 < due ≤ 1 | — | „K zaplacení zbývá jen {amount}. Částky do 1 Kč neúčtujeme – nic neplatíš." | „Potvrdit bez platby" | + `pdWaiveNote`, `pdConfirmFree`, `pdWaiveLine` = „Zaokrouhlení – částka do 1 Kč se neúčtuje" |
| edit price box | — | round: „Doplatek {amount} – kartou zaplatíš 15 Kč (minimální platba kartou)." / waive: „Doplatek {amount} neúčtujeme (do 1 Kč) – změnu uložíme bez platby." | „Pokračovat k platbě (+15 Kč)" / „Uložit změnu bez platby" | + `pdRoundEditHint`, `pdWaiveEditHint`, `pdSaveFree` |
| swap net line | — | „Doplatek za výměnu {amount} – kartou zaplatíš 15 Kč." / „Doplatek {amount} neúčtujeme (do 1 Kč)." | | + `pdRoundSwapHint`, `pdWaiveSwapHint` |
| shop summary | — | „Objednávka vychází na {amount} – kartou zaplatíš 15 Kč (minimální platba kartou)." / „… částky do 1 Kč neúčtujeme, objednávku potvrdíme bez platby." | | + `pdRoundShopHint`, `pdWaiveShopHint` |
| result line | — | „Zaplaceno {charge} (z toho dorovnání {rounding})" / „Částku do 1 Kč jsme neúčtovali." | | + `pdPaidWithRounding`, `pdWaivedSub` |
| server `below_minimum` (stale) | „Minimální platba kartou je 15 Kč" | „K zaplacení je {amount}, kartou ale jde zaplatit nejméně 15 Kč. Zaplať 15 Kč – rozdíl {rounding} uvidíš na dokladu jako dorovnání." | „Zaplatit 15 Kč" | + `pdBelowMinTitle`, `pdBelowMinBody` |
| `rounding_unavailable` | „Platbu pod 15 Kč teď nejde zpracovat" | „Server se právě aktualizuje a platbu pod 15 Kč teď nedokáže dorovnat. Nic jsme nestrhli – zkus to prosím za pár minut znovu." | „Zkusit znovu" | + `pdRoundUnavTitle`, `pdRoundUnavBody` |
| Stripe `amount_too_small` (mapper) | same as `below_minimum` | | | → `pdBelowMin*` (replaces `psBelowMinGeneric`) |

### 10.2 Server refusals — app text and server `error` text (cs, for old apps)
| code | app title / body (cs) | app action | server `error` (cs) |
|---|---|---|---|
| `already_paid` booking | (success) „Tahle rezervace už je zaplacená." ✓`psAlreadyPaid` | → success | „Rezervace je už zaplacená – nic dalšího platit nemusíš. Najdeš ji v Rezervacích." |
| `already_paid` shop / `no_payment_needed` | (success) ✓`psOrderAlreadyPaid` | → success | „Objednávka je už zaplacená – nic dalšího platit nemusíš." / „Objednávka nevyžaduje platbu – je potvrzená." |
| `payment_in_progress` | ✓`psPendingTitle` / ✓`psPendingBody` (edit: ✓`psPendingBodyEdit`, shop ✓`psPendingBodyShop`) | pending screen | „Platba za tohle už proběhla nebo se právě ověřuje. Neplať prosím znovu – výsledek uvidíš za pár minut v Rezervacích." |
| `duplicate_request` | „Platba se právě zpracovává" / „Stejná platba se právě zpracovává. Nic dalšího neplať – za pár vteřin ověříme, jak dopadla." | verify | 4.7 |
| `booking_cancelled` | „Rezervace je zrušená" / „Rezervace byla zrušená (nebyla zaplacená do 30 minut, nebo ji někdo zrušil), takže ji teď zaplatit nejde. Nic jsme nestrhli. Obnov ji v Rezervacích tlačítkem „Obnovit a zaplatit", nebo si vytvoř novou." | „Rezervace" | same text |
| `voucher_unavailable` | „Poukaz už nejde použít" / „Poukaz {code} mezitím vypršel nebo byl použitý jinde, takže rezervaci s ním zaplatit nejde. Nic jsme nestrhli. Vytvoř si prosím rezervaci znovu – bez poukazu, nebo s jiným." | „Upravit rezervaci" | same (code inline) |
| `below_minimum` (old app) | — (new app: 10.1) | — | „Zbývá zaplatit {due} Kč, ale kartou jde zaplatit nejméně 15 Kč. Tahle verze aplikace drobnou částku neumí dorovnat – aktualizuj prosím aplikaci MotoGo24 a zkus to znovu. Nic jsme nestrhli." |
| `amount_mismatch` booking | ✓`psPriceChangedTitle` / ✓`psPriceChangedBody` | „Zaplatit {amount}" | „Cena rezervace je teď {server_total} Kč. Otevři prosím platbu znovu z Rezervací – nic jsme nestrhli." |
| `amount_mismatch` edit/swap | ✓`psPriceChangedTitle` / ✓`psEditPriceChangedBody` | „Načíst znovu" | „Cena úpravy se mezitím změnila na {expected} Kč. Načti prosím rezervaci znovu a úpravu zopakuj – nic jsme nestrhli." |
| `amount_mismatch` shop | ✓`psPriceChangedTitle` / ✓`psShopPriceChangedBody` | „Do košíku" | (existing, no contact) |
| `free_mismatch` | ✓`psFreeRemainderTitle` / ✓`psFreeRemainderBody` (with total) else → `pdFreeCheckFailedBody` „Slevu se nepodařilo ověřit na celou cenu, takže rezervaci zdarma potvrdit nejde. Nic jsme nestrhli – vrať se k rezervaci a zkontroluj slevový kód." | „Zaplatit {amount}" / „Upravit rezervaci" | „Sleva nepokrývá celou cenu (zbývá {server_total} Kč). Vrať se prosím k rezervaci a zaplať zbytek – nic jsme nestrhli." |
| `free_confirm_failed` | ✓`psFreeFailedTitle` / ✓`psFreeFailedBody` | „Zkusit znovu" | „Rezervaci se nepodařilo potvrdit kvůli chybě na serveru. Nic jsme nestrhli – zkus to prosím za minutu znovu." |
| `auth_required` | ✓`authExpiredTitle` + ✓`psAuthBooking/psAuthEdit/psAuthShop` | „Přihlásit se" | existing |
| `forbidden` | ✓`psRefForbiddenBooking/Shop`, ✓`refForbidden` | „Přihlásit se" | existing |
| `booking_not_found` / `order_not_found` / `wrong_status` (shop) | ✓`psRefBookingGone`, ✓`psRefOrderGone` | „Rezervace" / „Do košíku" | existing |
| `wrong_status` (edit) | ✓`refWrongStatus` | „Načíst znovu" | existing |
| `stale_booking`, `moto_unavailable`, `trailer_*`, `active_pickup_time_locked`, `delivery_fee_guard`, `location_requires_route` | ✓ `ref*` / `psRefDelivery` | as today | existing (`dryMsgs`) |
| swap codes `not_found`, `not_paid`, `invalid_new_moto`, `swap_date_out_of_range`, `already_split`, `license_insufficient`, `new_moto_unavailable` | ✓ `swap.err.*` (same keys as the swap section) | „Načíst znovu" | one Czech sentence each (replaces „Změnu nelze aplikovat ({code})") |
| `change_not_applicable` | „Změnu teď nejde uložit" / „Rezervace je mezitím v jiném stavu, než appka ukazuje. Nic jsme nestrhli – načti rezervaci znovu a úpravu zopakuj." | „Načíst znovu" | same |
| `change_too_large` | „Úprava je moc rozsáhlá" / „Tahle úprava je na jednu platbu moc rozsáhlá. Nic jsme nestrhli – rozděl ji prosím na dvě menší (např. nejdřív termín, potom místo)." | „Upravit změnu" | same |
| `validation_unavailable`, `trailer_check_unavailable` | ✓`refValidationUnavailable`, ✓`refCheckUnavailable` | „Zkusit znovu" | existing |
| `stripe_unavailable` | „Platební brána neodpovídá" / „Platební brána teď neodpovídá. Nic jsme nestrhli – zkus to prosím za minutu znovu." | „Zkusit znovu" | 4.7 |
| `server_error`, unknown code, `invalid_type`, `missing_*`, `invalid_amount` | „Platbu teď nejde dokončit" / „Platbu teď nejde dokončit kvůli chybě na našem serveru. Nic jsme nestrhli – zkus to prosím za minutu znovu. Když to nepůjde ani potom, aktualizuj aplikaci." | „Zkusit znovu" | 4.7 / „Chybí rezervace k zaplacení – otevři ji v Rezervacích a zaplať odtud." / „Chybí objednávka k zaplacení – vrať se do košíku a odešli ji znovu." / „Částka k zaplacení chybí – otevři platbu znovu." / „Neznámý typ platby – aktualizuj prosím aplikaci MotoGo24." |

### 10.3 Card / wallet / connectivity (PaymentErrorMapper; decline_code first, then Stripe code)
| Stripe code(s) | title / body (cs) | action | key |
|---|---|---|---|
| `insufficient_funds` | „Nedostatek peněz na kartě" / „Banka platbu zamítla, protože na kartě není dost peněz. Dobij si účet, nebo zaplať jinou kartou." (wallet variant without wallet advice) | Zkusit znovu / Jiná karta | ✓`fundsTitle`, ✓`fundsBody`, ✓`psFundsBodyCard` |
| `expired_card` | „Platnost karty vypršela" / „Karta už není platná. Zaplať prosím jinou kartou." | Jiná karta | ✓`expired*` |
| `incorrect_cvc`, `invalid_cvc` | ✓`cvc*` | Zkusit znovu | ✓ |
| `incorrect_number`, `invalid_number` | ✓`number*` | Zkusit znovu | ✓ |
| `invalid_expiry_month/year` | ✓`psExpiry*` | Zkusit znovu | ✓ |
| `card_not_supported` | ✓`psNotSupported*` | Jiná karta | ✓ |
| `currency_not_supported` | „Karta neumí platit v korunách" / „Tvoje karta neumí zaplatit v českých korunách (CZK). Zaplať prosím jinou kartou – většina karet Visa a Mastercard to umí." | Jiná karta | + `pdCurrencyTitle/Body` (was bank block) |
| `card_velocity_exceeded`, `withdrawal_count_limit_exceeded` | ✓`limit*` | Zkusit později / Jiná karta | ✓ |
| `card_decline_rate_limit_exceeded` | ✓`psRateLimit*` | Jiná karta | ✓ |
| `incorrect_pin`, `invalid_pin`, `pin_try_exceeded`, `offline_pin_required`, `online_or_offline_pin_required` | ✓`psPin*` | Jiná karta | ✓ |
| `issuer_not_available`, `try_again_later`, `reenter_transaction`, `processing_error` | ✓`processing*` („Banka teď platbu nezpracovala – nic jsme nestrhli…") | Zkusit znovu | ✓ |
| `authentication_required`, `payment_intent_authentication_failure`, `setup_intent_authentication_failure` | ✓`auth*` (3DS) / ✓`psAuthNotDone` | Zkusit znovu | ✓ |
| `lost_card`, `stolen_card`, `pickup_card` | **generic, safe**: ✓`bankBlockTitle` / ✓`bankBlockBody` (no „ztracená/odcizená") | Jiná karta | ✓ (stop using `blocked*`) |
| `generic_decline`, `card_declined`, `do_not_honor`, `do_not_try_again`, `transaction_not_allowed`, `service_not_allowed`, `not_permitted`, `restricted_card`, `security_violation`, `call_issuer`, `approve_with_id`, `fraudulent`, `merchant_blacklist`, `invalid_account`, `new_account_information_available`, `revocation_of_authorization`, `revocation_of_all_authorizations`, `stop_payment_order`, `no_action_taken`, `testmode_decline`, `invalid_amount`, `incorrect_zip`, `postal_code_invalid`, any unknown decline | ✓`bankBlockTitle` / ✓`bankBlockBody` („Tvoje banka tuhle platbu neschválila. Kartu obvykle odblokuješ v aplikaci své banky… zkus znovu, nebo jinou kartu.") | Zkusit znovu / Jiná karta | ✓ |
| `duplicate_transaction` | „Banka platbu odmítla jako duplicitní" / „Stejnou částku jsi zřejmě právě zaplatil(a). Ověřujeme, jestli předchozí platba prošla – neplať prosím znovu." | verify | + `pdDuplicateTx*` |
| `resource_missing`, `payment_method_unactivated`, `payment_method_not_available`, `payment_method_customer_decline` | ✓`psCardGone*` | Zaplatit jinou kartou | ✓ |
| `payment_method_provider_decline` | „Peněženka platbu odmítla" / „Google Pay (iOS: Apple Pay) nebo banka karty v ní platbu odmítla. Nic jsme nestrhli – zaplať prosím kartou přímo." | Zaplatit kartou | + `pdWalletDeclined*` |
| `payment_intent_unexpected_state` | ✓`psUncertain*` | verify | ✓ |
| `payment_intent_payment_attempt_expired` | „Platba vypršela" / „Banka platbu nepotvrdila včas, takže vypršela. Nic jsme nestrhli – zkus to prosím znovu." | Zkusit znovu | + `pdAttemptExpired*` |
| `payment_intent_payment_attempt_failed`, `amount_too_large` | ✓`genericTitle/Body` | Zkusit znovu | ✓ |
| `amount_too_small` | 10.1 | Zaplatit 15 Kč | → `pdBelowMin*` |
| user cancelled sheet / wallet (`Canceled`) | ✓`cancelled*` (not an error) | — | ✓ |
| Google Pay not available on device | ✓`walletTitle/Body` (without raw code suffix) | Zaplatit kartou | ✓ |
| Wallet processed but failed (verified not paid) | ✓`walletFailed*` | Zaplatit kartou | ✓ |
| offline (request never sent) | ✓`networkTitle` / ✓`networkBody` („…připoj se k Wi-Fi nebo datům, nic jsme nestrhli") | Zkusit znovu | ✓ |
| connection lost after sending a charge (timeout, socket, 502 HTML on saved card) | ✓`psUncertainTitle/Body` („Nevíme jistě, jestli platba prošla – ověřujeme to. Neplať prosím znovu.") | verify | ✓ |
| server 5xx / non-JSON without charge | ✓`psServerDownTitle/Body` | Zkusit znovu | ✓ (contact flag removed) |
| session expired | ✓`authExpired*` | Přihlásit se | ✓ |
| 3 failed attempts | „Platba se nepodařila" / booking: „Platba se ani na třetí pokus nepodařila a nic jsme nestrhli. Rezervace zůstává uložená – dokončíš ji v Rezervacích tlačítkem Dokončit rezervaci, dokud neuplyne čas na zaplacení. Zkus jinou kartu nebo Google Pay." / edit: „Doplatek se ani na třetí pokus nepodařilo zaplatit. Úpravu jsme neuložili a nic jsme nestrhli – otevři rezervaci a zkus to s jinou kartou." | Rezervace / Zpět na rezervaci | → `pdMaxBookingBody`, `pdMaxEditBody` |
Server-side `declineMessageCs()` (off-session `message` for 4.1.3) uses the same cs bodies, keyed by the same code groups.

### 10.4 Paid change completion (D6)
| state | title / body (cs) | action | key |
|---|---|---|---|
| completing (swap) | „Výměna se dokončuje" / „Doplatek {amount} je zaplacený. Výměnu motorky teď zapisujeme do rezervace – obvykle to trvá pár vteřin. Nemusíš nic dělat ani platit znovu: dokončí se sama, i když appku zavřeš nebo vypadne signál." | Moje rezervace | + `pdSwapCompletingTitle/Body`, `pdSwapCompletingShort` |
| completing (edit) | „Úprava se dokončuje" / same wording for „úpravu" | Moje rezervace | + `pdEditCompleting*` |
| completing + offline | appended „Telefon je teď offline – dokončíme to automaticky, jakmile se připojí k internetu." | | + `pdCompletingOffline` |
| done after restart | „Doplatek za výměnu motorky proběhl. Výměnu dokončujeme automaticky – hotovou ji uvidíš v detailu rezervace během pár minut." | Zobrazit | value change of `fxSwapPaidNotice` (ext_41) |
| failed: bike taken | „Výměnu se nepodařilo dokončit" / „Motorku {moto} si během tvé platby zarezervoval někdo jiný, takže výměnu nešlo zapsat. Tvoje původní rezervace platí beze změny. Doplatek {amount} ti automaticky vracíme na kartu – peníze bývají zpět do 5–10 pracovních dnů, potvrzení přijde e-mailem." | Moje rezervace | + `pdChangeFailedTitle`, `pdSwapFailedTakenBody` |
| failed: booking ended / cancelled | „…Rezervace mezitím skončila nebo byla zrušená, takže změnu nešlo zapsat. Doplatek {amount} ti automaticky vracíme…" | | + `pdChangeFailedStatusBody` |
| failed: swap day passed | „…Den výměny mezitím uplynul…" | | + `pdChangeFailedDateBody` |
| failed: other trigger refusal | „…Rezervace se mezitím změnila tak, že úpravu nešlo zapsat. Doplatek {amount} ti automaticky vracíme…" | | + `pdChangeFailedOtherBody` |
| not paid after all | ✓`psNotPaidEdit` | Otevřít rezervaci | ✓ |
(If the owner chooses staff completion instead of auto-refund (Q4), the four failed bodies end with „Výměnu/úpravu dokončí nebo doplatek vrátí obsluha do 2 pracovních dnů – nemusíš nic dělat." — still no contact.)

### 10.5 Restore (D3)
| RPC error | title / body (cs) | action | key |
|---|---|---|---|
| `forbidden` | ✓`cannotRestore` / „Tuhle rezervaci nejde obnovit z účtu, na kterém jsi přihlášen(a). Přihlas se účtem, kterým jsi ji vytvořil(a)." | Přihlásit se | + `pdRestoreForbidden` |
| `not_found` | „Rezervaci jsme nenašli – seznam rezervací jsme obnovili." | Rezervace | + `pdRestoreNotFound` |
| `not_cancelled` | „Rezervace už zrušená není – mezitím ji někdo obnovil nebo zaplatil. Otevři ji v Rezervacích." | Otevřít rezervaci | + `pdRestoreNotCancelled` |
| `not_restorable` | „Tahle rezervace už byla zaplacená a vrácená (nebo už probíhá), takže ji obnovit nejde. Vytvoř si prosím novou rezervaci." | Vybrat termín | + `pdRestoreNotRestorable` |
| `cancelled_by_staff` | „Tuhle rezervaci zrušila naše obsluha, proto ji v aplikaci obnovit nejde. Vytvoř si prosím novou rezervaci." | Vybrat termín | + `pdRestoreByStaffCancel` |
| `date_passed` | ✓`restoreDatePassed` | Vybrat termín | ✓ |
| `moto_unavailable` | ✓`motoOccupiedTitle` / ✓`restoreMotoOccupied` | Změnit termín / Jiná motorka | ✓ |
| `voucher_unavailable` | „Poukaz {code} z rezervace mezitím vypršel nebo byl použitý jinde, proto ji nejde obnovit se slevou. Vytvoř si prosím novou rezervaci." | Vybrat termín | + `pdRestoreVoucher` |
| `promo_unavailable` | „Slevový kód {code} už neplatí (vypršel nebo je vyčerpaný), proto rezervaci nejde obnovit se slevou. Vytvoř si prosím novou rezervaci." | Vybrat termín | + `pdRestorePromo` |
| `restore_limit` | „Tuhle rezervaci už jsi obnovil(a) třikrát. Aby motorka nezůstávala blokovaná, další obnovení nejde – vytvoř si prosím novou rezervaci." | Vybrat termín | + `pdRestoreLimit` |
| RPC missing (deploy window) | „Obnovení rezervace se teď na serveru aktualizuje. Nic se nezměnilo – zkus to prosím za pár minut znovu." | Zkusit znovu | + `pdRestoreUpdating` (replaces `fxRestoreByStaff`) |
| network | ✓`psRestoreNet` | Zkusit znovu | ✓ |
| other | „Rezervaci se teď nepodařilo obnovit kvůli chybě na serveru. Nic se nezměnilo – zkus to prosím za minutu znovu." | Zkusit znovu | → `pdRestoreServer` |

### 10.6 Other payment-adjacent texts that carry contacts today → replacements
`psRefusalUnknown` → `pdUnknownBody` (10.2 last row) · `psDraftUnknownBody` → `pdDraftServerBody` „Rezervaci se teď nepodařilo uložit
kvůli chybě na serveru. Nic jsme nestrhli – zkus to prosím za minutu znovu." · `psEditFail` → `pdEditFail` „Úpravu se nepodařilo uložit
kvůli chybě na serveru. Nic se nezměnilo – zkus to prosím za minutu znovu." · `psMoveFail` → `pdMoveFail` (same for „Termín") ·
`psOrderFail` → `pdOrderFail` „Objednávku teď nejde odeslat kvůli chybě na serveru. Nic jsme nestrhli – zkus to za minutu znovu." ·
`psCancelFail` → `pdCancelFail` „Rezervaci se teď nepodařilo zrušit kvůli chybě na serveru. Nic se nezměnilo – zkus to prosím za minutu
znovu." · `psCancelForbidden` → `pdCancelForbidden` (without „nebo nám napiš") · `psFreeCheckFailedBody` → `pdFreeCheckFailedBody` ·
`psBelowMin*`, `fxBelowMinResume` → 10.1 · `psEditStaffBody`/`psSwapStaffBody` → 10.4 · `refundSettleManual` → `pdRefundManual`
„Automatická vratka se nepovedla. Vratku dokončí obsluha do 2 pracovních dnů – nemusíš nic dělat, potvrzení a dobropis přijdou
e-mailem." · `psSwapUnknown` → `pdSwapUnknown` „Výměnu teď nejde provést. Zkus jiný den výměny nebo jinou motorku." ·
`psSlevomatUnverified` → `pdSlevomatUnverified` „Poukaz ze Slevomatu se teď nepodařilo ověřit u Slevomatu. Kód zůstává platný – zkus to
prosím za pár minut znovu." · `paymentFailedAttemptsRest` (contains e-mail) → no longer referenced · `psHelpLine`, `psWriteUs` → no
longer referenced in payment UI.

---------------------------------------------------------------------------------------------------------------------------------
## 11. Backward compatibility (app versions in the field, web, Velín)

Invariant: **the server never charges more than, or anything other than, the `amount` an app showed and sent.** New behaviour is enabled
only by new request fields; old apps may get a clear Czech refusal instead of a charge.

| client / flow | today | after this change |
|---|---|---|
| 4.1.3 booking / resume, due ≥ 15 | works | identical (+ in-progress guard, idempotency) |
| 4.1.3, 0 < due < 15 (charge < 15) | Stripe fails: 500 raw English (sheet) / declined (saved card) | 400 `below_minimum`, Czech „aktualizuj aplikaci" text, nothing charged |
| 4.1.3, 14.5 ≤ due < 15 (app rounds amount to 15) | charges 15, unrecorded | identical (amount ≥ 15 → normal path; no rounding recorded) |
| 4.1.3 FAB while webhook pending (PI succeeded) | second PI → double charge possible | 409 `payment_in_progress`, Czech text, no second charge |
| 4.1.3 retry after lost saved-card response within the same minute | possible double charge | same PI returned (idempotency) |
| 4.1.3 stale sheet PI (requires_payment_method) + new pay tap | new PI, old one still payable | old one reused (same amount) or cancelled; at most one chargeable PI |
| 4.1.3 edit surcharge ≥ 15 | webhook + client apply; F1 double surcharge if webhook > 8 s late | webhook detects „already applied" → no double surcharge |
| 4.1.3 edit/swap 0 < diff < 15 | Stripe fails | 400 `below_minimum` Czech text |
| 4.1.3 swap ≥ 15 | client commit + webhook commit | identical (7-arg RPC resolves its named 5-param call via the default); if S3b approved: client commit may get `payment_required` and the webhook commits |
| 4.1.3 restore (direct UPDATE) | re-cancelled within 2 min, storno mail while paying | S2 trigger stamps `restored_at` (fresh 30 min) or keeps it cancelled with PP `booking_cancelled` text |
| 4.1.3 off-session decline | raw English Stripe `message` in cs | Czech `message` |
| 4.1.3 unknown new codes | shows `error` text verbatim | all new `error` texts Czech, precise, contact-free |
| ≤ 4.1.2 / 1.0.1 | same request shape | same as 4.1.3 rows (response shapes unchanged; only additive fields) |
| new app (4.2.x) before SQL is live | — | `rounding_unavailable` for rounding/waiver; restore `pdRestoreUpdating`; everything else works |
| web booking / web shop / web edit checkout | 1–14 Kč → Stripe 500 | 400 `below_minimum` + web text; ≥ 15 unchanged |
| web swap commit after return | client commit + webhook | unchanged (unless S3b) |
| Velín SOS link | amount < 15 → Stripe error | 400 `below_minimum` „zadej alespoň 15 Kč" |
| Velín restore / admin edits | unchanged | unchanged (trigger skips admins; swap rounding param only for admin/service) |

---------------------------------------------------------------------------------------------------------------------------------
## 12. Deployment order, feature detection, rollback
1. Owner approves S1, S2, S3 (S3b separately) — SQL text presented in chat, files in `paydec/sql/` (`20261016p1_…`, `p2_…`, `p3_…`; byte
   order after any `20261016[a-o]_*` file; S1 before S3 because S3 writes `card_rounding`).
2. One merge carries SQL + edge (`deploy-sql.yml` and `deploy-functions.yml` run in parallel). Edge works in every intermediate state:
   missing `card_rounding` → `rounding_unavailable` only for card_min rounding/waiver; missing 7-arg swap RPC → 6-arg fallback when
   rounding = 0; GI reads `card_rounding ?? 0`; restore RPC missing → app message; PP never depends on S2.
3. App release (both stores) only after SQL + edge are live (STATE_6 entry).
Rollback: edge revert is safe (columns default 0, old code ignores them). SQL: columns stay; KF, cron and swap RPC revert by re-applying the
previous definitions (kept verbatim in the drafts' header comments); restore trigger can be dropped (`DROP TRIGGER IF EXISTS`).
STATE docs: STATE_2 (columns), STATE_3 (RPCs, KF, cron, swap rev.12), STATE_4 (two triggers), STATE_5 (PP codes, `complete_extension`,
WR retry semantics), STATE_6 (changelog).

---------------------------------------------------------------------------------------------------------------------------------
## 13. Test plan

### 13.1 Edge (deno; `DENO_DIR=…/denocache …/denobin/deno`)
- `deno check` PP, WR, GI, PF, `_shared/extension-apply.ts` — error count ≤ baseline (record baseline before edits).
- Unit tests (`*_test.ts`, mocked supabase/stripe clients):
  - `classifyDue` table: due ∈ {−5, 0, 0.4, 1, 1.01, 7.5, 14.6, 15, 15.4, 100} × card_min ∈ {true, false} × amount ∈ {0, 1, 7, 15, 16}.
  - CAS writers: concurrent second call re-classifies to ok; missing column → `rounding_unavailable`.
  - `guardStoredIntent`: each PI status × type (booking/extension/shop) × request (sheet/saved) → refuse / reuse / cancel / proceed;
    cancel race (PI became succeeded) → refuse.
  - `idempotencyKey` deterministic; attempt_id vs minute bucket; chg hash.
  - `mapStripeError` for each class; no raw message in `error`.
  - `declineMessageCs` covers every code group of §10.3; regex: no `@`, `+420`, `774`, „napiš", „ozveme".
  - `applyPaidExtension`: (a) fresh apply, (b) replay same payRef → already_applied, (c) **F1**: row already written by client
    (dates + total = old+diff) → no double add, history appended once, (d) rounding r=8 → total +diff+8, card_rounding +8, history
    card_rounding, (e) waiver r=−0.6, (f) optimistic lock lost once → re-read → already_applied, (g) trigger error P0001 → failed,
    network → retry, (h) swap: success / already_split / invalid_new_moto / new_moto_unavailable / RPC 5xx / PGRST202 with r=0 → 6-arg.
  - `complete_extension`: each PI status, not_extension, foreign booking 403.
- Webhook: transient apply → 500 after the other steps ran; permanent → refund dispatched once (second event → no second refund).

### 13.2 SQL (local Postgres with `live_schema.sql` loaded — scratchpad `pgtest`/`pgv` tooling; never the live DB)
- S1: columns; guard (customer JWT simulation via `request.jwt.claims` + `SET ROLE authenticated`: UPDATE keeps OLD, INSERT forces 0;
  service role writes); KF with rounding +8 / −0.6 → items sum = Σ DP, `kf_total_not_zero` not logged; KF unchanged when 0.
- S2: RPC each error code; success sets restored_at/source/count, re-redeems vouchers; voucher used elsewhere → `voucher_unavailable`
  and nothing changed; overlap → `moto_unavailable` rollback; grants (anon cannot execute); trigger: customer direct UPDATE stamped /
  refused (kept cancelled); admin UPDATE untouched; SECURITY DEFINER RPC path skipped; cron: app row 31 min old cancelled; restored 10 min
  ago kept; restored 31 min ago cancelled; `checkout_started_at` 5 min ago keeps it; > 60 min cap cancels; Velín-restored never.
- S3: dry-run unchanged; customer commit ignores `p_card_rounding`; service commit REPLACE (+net+r, card_rounding, history) and SPLIT
  (B total + r); bounds (r = 20 ignored + log); grants recreated; named 5-param call resolves.

### 13.3 App (both trees)
- `flutter analyze` — no new issues vs current baseline (Android in place; iOS in a scratch copy after `pub get --offline` if `.dart_tool`
  is stale); `flutter test` all green; `diff -rq lib` = whitelist + v2 differences only.
- New/updated tests: `cardCharge` table; `PaymentRefusals.resolve` for every §10.2 code → expected action, title, no `contact`;
  mapper: every §10.3 code → expected key; lost/stolen → bankBlock; **contact scan**: for all keys referenced by payment/shop/restore/edit/
  swap code (list in the test) in all 8 languages: no `@`, `+420`, `774 256`, „napiš nám", „write to us", „schreib uns", etc.; ext_43
  key parity across 8 languages; `PaidChangeQueue` (fake prefs + fake completer): enqueue idempotent, backoff schedule, not_paid removes,
  failed emits once, extras-only retry, single-flight drain, 7-day expiry; FAB `createdAt = max(created, restored)`.

### 13.4 End-to-end scenarios (staging: functions served locally with a Stripe **test** key + local DB; production smoke by the owner)
D1/D2: new booking due 7 (sheet, saved card, 3DS card) → 15 charged, ZF/DP show +8 line, KF at completion balances; due 0.6 → confirmed
free, no docs, KF −0.6 line; FAB resume of a rounded booking (total 15) → normal; restore + rounding; edit diff 7 → 15 charged, edit DP
= 7 itemized + 8 rounding; edit diff 0.6 → saved without payment, no DP; swap REPLACE net 7.5 and SPLIT net 7.5 (B total + 7.5); shop
total 9 → 15 charged, shop DP line; shop 0.8 → confirmed free; web booking 9 → `below_minimum` text; 4.1.3 build against new edge: 9 Kč →
update text, ≥ 15 unchanged.
D3: restore → pay within 30 min; pay at 29:30 with 3DS finishing at 33:00 → not cancelled, paid; restore 4× → limit; voucher used
elsewhere → refusal; 4.1.3 direct restore → stamped; staff-cancelled → refused.
D4: double tap; FAB during webhook delay → `payment_in_progress`; saved card with response dropped (proxy) + resend same attempt_id →
one charge; stale sheet PI then saved-card pay → old PI cancelled; Stripe outage (invalid key in staging) → `stripe_unavailable`.
D5: walk every §10 row in cs + one other language; screenshot check that no contact line remains.
D6: kill app right after payment (before/after enqueue), airplane mode at success → „Výměna se dokončuje", reconnect → done notice;
webhook first vs app first (race) → applied once; webhook transient failure (RPC temporarily revoked in staging) → Stripe retry
completes; bike taken during payment → refund dispatched once, failure text shown.

---------------------------------------------------------------------------------------------------------------------------------
## 14. Change inventory (for the implementation steps)
- SQL drafts: `paydec/sql/20261016p1_card_rounding.sql` (S1), `20261016p2_customer_restore.sql` (S2), `20261016p3_swap_card_rounding.sql`
  (S3 + commented S3b block) — owner approval before any commit.
- Edge: PP `index.ts` (wiring only), new `card-minimum.ts`, `intent-guard.ts`, `refusals.ts`, `stripe-errors.ts`,
  `complete-extension.ts`; `payment-flows.ts` (4.10); WR `index.ts` (shared apply, retry flag, failure handling), PC
  (`confirmShopPayment` method param); new `_shared/extension-apply.ts`; GI `index.ts` (3 small insertions).
- App (both trees): A1–A18 files listed in §9; nothing under `core/v2`, `features/*/v2`, `booking_v2_*`, `translations_ext_5X_*`,
  `router.dart`, `app_shell.dart`, `shell_*.dart`. `main.dart` gets one call per tree (whitelisted platform file — edit each tree's own
  copy).
- Velín: optional V1.
- Docs: STATE_2/3/4/5/6 after SQL application.

---------------------------------------------------------------------------------------------------------------------------------
## 15. Open questions for the owner (defaults in force until answered)
1. **S3** — accept the 7th parameter `p_card_rounding` on `split_booking_moto_swap` (needed to record swap rounding/waiver)? *Default:
   yes.* **S3b** — also forbid customers to commit a swap with net > 1 Kč without payment (pre-existing F2; small web follow-up)?
   *Default: not included.*
2. Storno: the rounding is part of the price and is refunded pro rata with it (folded design). *Default: yes.*
3. Web (Stripe Checkout): round to 15 with a visible line item, or keep refusing 1–14 Kč with a clear text? *Default: refuse for now.*
4. Paid change that cannot be saved even after retries (the new bike was booked by someone else during the payment, booking ended, swap
   day passed): automatic refund of the surcharge + staff alert (e-mail + log), or staff completes manually? *Default: automatic refund +
   alert.*
5. Restore anti-abuse limit of 3 restores per booking. *Default: 3.*
