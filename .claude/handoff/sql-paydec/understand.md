# PAYDEC — understand (read-only map + minimal safe change set for D1–D6)

Date 2026-10-16, branch `claude/moto-go-mobile-conversion-gqg5qo` (HEAD 15673b9b). Paths: PP = `supabase/functions/process-payment/index.ts`,
WR = `supabase/functions/webhook-receiver/index.ts`, PC = `webhook-receiver/payment-confirmers.ts`, GI = `generate-invoice/index.ts`,
app paths relative to `Motogo-app-main/motogo-app-flutter/lib/` (identical in `-ios` except whitelist; `payment_error_mapper.dart` iOS only
adds Google→Apple Pay substitution in `_t`). Live SQL truth = scratchpad `live_schema.sql` (snapshot 2026-10-15).
Field app = **4.1.3 (+116, bump 70a94933, 2026-10-10)**; this branch's payment rework (15673b9b) is NOT released yet.

---------------------------------------------------------------------------------------------------------------
## 0. TL;DR
- Amounts: app sends `amount` (int Kč, `amount.round()`); PP validates per type (booking/sos ≥ `bookings.total_price`−1, extension = server
  dry-run ±1, shop = `shop_orders.total` exactly). Stripe CZK minimum = 15 Kč; PP guards `<15` ONLY for shop (PP:430). Booking/extension
  `<15` → Stripe `amount_too_small` → 500 "Payment processing failed: …" (sheet) or 200 `off_session_charge_failed` (saved card).
- Branch app already BLOCKS 0<amount<15 with "Napiš nám" (`belowCardMinimum`, payment_refusals.dart:54-56) → D1/D2 replace it by rounding.
- Idempotency today: none at Stripe level (no `idempotencyKey`); duplicate guard only `payment_status==='paid'` (PP:370-386, booking only);
  dedup of side-effects is good (confirm_payment / confirm_shop_payment `was_already_paid`, webhook `payment_ref` in modification_history).
- Webhook already commits paid swaps from PI metadata `chg={_swap:{m,d,t}}` (WR:88-111) but a failure is only logged and Stripe gets 200 →
  never retried. App commits client-side 3× then shows "obsluha dokončí" (payment_screen.dart:1347-1361). No persisted retry.
- Restore: app calls RPC `customer_restore_booking` (booking_restore.dart:140-161) which is only a DRAFT
  (`errstates/sql/20261016_customer_restore_booking_DRAFT.sql`) → in prod the branch app falls to "Napiš nám" (byStaff); 4.1.3 does a direct
  UPDATE → cron re-cancels within ≤2 min (live `auto_cancel_expired_pending`: `restored_at IS NULL AND created_at < now()-30min`).
- Documents are built from DB columns, never from app `amount` (GI strips user fields, GI:196-215): booking ZF/DP lines = rental derived from
  `total_price` (GI:573) + extras + delivery + discounts; edit DP = `price_difference` (trigger NEW−OLD total) itemized + "Korekce" (GI:545-550);
  KF = SQL trigger `generate_final_invoice_on_complete` (live_schema.sql:9721-9876) rental brutto from `total_price`; shop = items+shipping−discount.
  ⇒ any rounding must live in DB columns that both GI and KF itemize.
- Recommended core: **signed column `card_rounding` (Kč) on `bookings` and `shop_orders`, FOLDED INTO `total_price`/`total`** (+X = dorovnání
  na 15 Kč, −X = odpuštěno ≤1 Kč), itemized as an explicit line everywhere; rental brutto formulas subtract it. Folding keeps refunds,
  process-refund customer cap (Σreceived−refunded−total_price, process-refund:581-616), storno %, delta-based edits and swaps consistent.

---------------------------------------------------------------------------------------------------------------
## 1. Payment types end-to-end

| Flow (app entry) | PP request | PP branch / amount check | Completion today |
|---|---|---|---|
| New booking (`/payment`, ctx null) | `type booking`, booking_id of draft inserted by app (payment_screen.dart:526-852, `total_price = breakdown.total` client-computed), amount = `_amount` (breakdown.total + upsell, :362-374) | owner check + `amt>0 && round(amt) < total_price−1 → 409 amount_mismatch(server_total)` (PP:451-491); higher amount allowed (upsell) | webhook PI succeeded → `confirm_payment` (PC:83-274) → mail + ZF/DP via send-booking-email; app polls `payment_status` 8 s (`_serverConfirmed` :1146) |
| Resume (FAB "Dokončit", app_shell.dart:594-604) | same, ctx `amount = booking.totalPrice`, `bookingCreatedAt = created_at` | same | same |
| Restore ("Obnovit a zaplatit", booking_restore.dart:40-137) | RPC `customer_restore_booking` then ctx booking, `isRestore`, window from `restored_at` | same | same + `confirm_payment` revives cancelled (STATE_3) |
| Free (≤0 after discount) | `_confirmFree` (:1196-1242) amount 0 | PP:812-892: requires `total_price==0` AND true 100 % (promo percent≥100 / fixed≥orig / voucher≥orig; orig = total+discount_amount) → `confirm_payment('free')`; errors w/o code | sync |
| Edit surcharge (reservation_edit_screen.dart:1058-1121) | `type extension`, `change` = compact app-format payload incl. `total_price` (new absolute, old+effDiff) and `_base` (:1096-1102), amount = effDiff | PP:540-808: owner, wrong_status, `_base` stale→409 stale_booking, app-format `expected = c.total_price − cur.total_price` (:686), place guard, availability, trailer; `|amount−expected|>1 → 400 amount_mismatch(expected)` (:803-808). Payload → `metadata.chg[..chg_8]`, `metadata.srv` | webhook `applyExtensionChange` (WR:62-386) writes columns/total/history (payment_ref dedupe :217-226); app ALSO applies client-side after success (payment_screen.dart:1379-1415) incl. booking_extras rows (not in metadata) and verifies `total_price == expected` (:1416-1425) |
| Moto swap (reservation_swap_section.dart:252-340) | dry-run RPC → net; `net>0.5` → extension with `pendingEditChanges={_swap_commit:{…}}` → `change={_swap:{m,d,t}}` (payment_screen.dart:325-334) | PP dry-run `split_booking_moto_swap(p_dry_run)` under caller JWT, `expected = net` (PP:646-653) | app `_commitSwap` (:1247-1281) 3× + dry-run check; webhook commit (WR:88-111). net≤0.5 → direct commit `p_settle_refund:true` (:303-339) |
| E-shop (shop_checkout_screen.dart:397-613) | RPC `create_shop_order` (server price, auto-confirm only total=0 with discount) then PP `type shop`, `order_id`, amount `total.round()` (:497-500) | PP:407-437: owner, already_paid/wrong_status/no_payment_needed(≤0)/`below_minimum` (<15)/amount_mismatch(server_total) | webhook `confirm_shop_payment`; app polls 8 s |
| SOS replacement | app: free (`sos_replacement_screen` p_daily_price 0); `PaymentFlowType.sos` unused. Velín: `action:create_sos_payment_link` (payment-flows.ts:257-350, amount from operator, only `<=0` checked) | — | webhook `confirmSosPayment` (PC:277-373) |
| Voucher purchase | web only (`handleWebShopCheckout`, payment-flows.ts:507+); app voucher = e-shop item | Checkout session | webhook / verify_shop_session |
| Web booking / web edit / web shop | `source web` → `handleWebBookingCheckout` (payment-flows.ts:9-255, amount = total_price, no min check), web edit = PP `mode checkout` (PP:1086-1169, no min check) | — | webhook checkout.session.completed (WR:447-552) |

Saved card (default card) = PP creates+confirms PI (`confirm:true`, PP:916-1009); response `off_session:true` + status; errors returned as
200 `{success:false, off_session:true, error:'off_session_charge_failed', error_code, decline_code, message}`. Sheet = PP creates PI
(`['card','link']`, PP:1032-1084) and client confirms in `CardPaymentSheet`.

## 2. PP refusal/return inventory (codes today; ✗ = no `code`)
- PP:37,53,150,167,179,194 web verify actions ✗. PP:351 `invalid_type`. PP:365 "Missing booking_id…" ✗. PP:381 already paid (booking) ✗ **409**.
  PP:389 missing order_id ✗. PP:395 missing amount ✗. Shop: `auth_required` 401, `order_not_found` 404, `forbidden` 403, `already_paid` 409,
  `wrong_status` 409, `no_payment_needed` 409, `below_minimum` 400, `amount_mismatch` 409+server_total.
- Booking/sos/extension: `validation_unavailable`, `invalid_amount`, `booking_not_found`, `auth_required`, `forbidden`, `not_sos_replacement`,
  `amount_mismatch`+server_total; extension dry-run codes (PP:785-801) + generic `Změnu nelze aplikovat (${dryErr})` (raw code in text);
  `stale_booking`; `amount_mismatch`+expected (400).
- Free path PP:818-878: already paid ✗, total>0 ✗, not 100 % ✗, confirm failed ✗ (prior D4 patch draft adds `already_paid`/`free_mismatch`/
  `free_confirm_failed` — `errstates/payments/edge/process-payment_D4.patch`, NOT applied; index.ts == index.orig.ts).
- Off-session: `off_session_unexpected_status` (200), `off_session_charge_failed` (200, Stripe code/decline in fields).
- Outer catch PP:1170-1188: 500 `'Payment processing failed: ' + Stripe message` ✗ (amount_too_small, idempotency, API errors all here).
- **4.1.3 shows the server `error` text verbatim** for unknown codes (git 70a94933 payment_screen.dart `_handleIntentError`: `serverRefusal(code) ??
  errorMessage`) → every new/changed refusal needs a good Czech `error` WITHOUT contact details (D5) and keep HTTP shapes.

## 3. webhook-receiver
- Events handled: `checkout.session.completed`, `payment_intent.succeeded`, `charge.refunded`, `payout.paid` (WR:447-885). **No
  `payment_intent.payment_failed`** (nothing to do; app learns failure from SDK).
- PI succeeded (WR:553-589): type from metadata (fallback lookup by `stripe_payment_intent_id`) → `confirmBookingPayment(suppressMail for
  extension)` → `applyExtensionChange(chg, paidCzk = pi.amount/100, srv, payRef = pi.id)` wrapped in try/catch that only warns (WR:577-580)
  → card brand, PM attach, `ingestFinancialEvent(amount = pi.amount)` (idempotent by PI id). Any throw → 500 → Stripe retries (all steps idempotent).
- `confirmBookingPayment` overwrites `bookings.stripe_payment_intent_id/stripe_session_id` with the CURRENT PI (PC:151-160) — for extension
  that is the surcharge PI (process-refund copes via `paymentIntents.search` metadata booking_id, process-refund:591).
- `applyExtensionChange` swap branch (WR:88-111): RPC commit as service_role, ok = success|already_split|invalid_new_moto; else log
  `swap_commit_failed` and RETURN (no retry, no alert).
- App-format/web branch (WR:140-385): absolute total from `srv.t` → `new_total` → `a.total_price`; **stale baseline** (`_base` ≠ current row,
  WR:204-281) → `total = cur.total + paidCzk`.
- **F1 (pre-existing money bug):** when the APP applies the edit client-side first (it does after 8 s without webhook confirmation,
  payment_screen.dart:1128-1132 → :1379-1415), the late webhook sees dates/total ≠ `_base` → "stale" → `total = (old+diff) + diff` → double
  surcharge on `total_price` (KF later asks the customer to pay it again). Fix belongs to D4/D6 (see §9 E2).

## 4. Auto-cancel + restore (D3)
- Cron `auto-cancel-pending-bookings` every 2 min → `auto_cancel_expired_pending()` (live_schema.sql:5805+, = repo 20260904b): cancels
  `pending+unpaid+restored_at IS NULL` by `created_at` (app 30 min, web 4 h); mail for app.
- Velín restore sets `restored_at` (never auto-cancelled). App 4.1.3 restore = direct customer UPDATE cancelled→pending (allowed by
  `_guard_customer_booking_status`, STATE_4:25) with `restored_at` NULL → re-cancelled ≤2 min + storno mail while the customer pays;
  payment later revives via `confirm_payment` unless the bike was taken (overlap → webhook fallback direct UPDATE; customer charged).
- Branch app: RPC only; missing RPC (PGRST202) → `fxRestoreByStaff` + "Napsat nám" (booking_restore.dart:40-62,151-160).
- FAB countdown = `created_at`+30 min (pending_booking_fab_provider.dart:56-61,84,100) → a restored booking shows as expired at once.
- Existing draft RPC (errstates/sql/…DRAFT.sql) is sound: owner, cancelled, unpaid, not picked up, start>today(Prague), vouchers still
  `active`, overlap exceptions → `moto_unavailable`, sets `restored_at`, `restored_by_source='app'`; cron 30 min from `restored_at` for app-restored.
  Gaps: no promo-code re-validation (active/valid_to/max_uses); old apps' direct UPDATE path not covered; a payment in flight at minute 30
  can still be cancelled (no "paying" grace).

## 5. Swap (D6)
- RPC `split_booking_moto_swap(uuid,uuid,date,text,bool,bool)` latest = `20260922a_swap_rev11_admin_exempt_trailer_guard.sql` (= live
  17584). Customer/owner may COMMIT without any payment check (validates paid booking only) — **F2 (pre-existing): a customer can commit a
  net>0 swap without paying by calling the RPC directly**. REPLACE (from first day, reserved) `total_price += net` (fires
  `trg_booking_modified_email` → rozdílový DP = net); SPLIT shortens A by `a_credit`, inserts B `reserved/paid` with full B price (accounting of
  net vs B docs is a known gap, STATE_3 "účetní rozpad … NENÍ v RPC řešen").
- Idempotency: second commit → `already_split` (split) / `invalid_new_moto` (replace) — both treated as done by app and webhook.
- Failure modes today: client commit fails (network/app killed) and webhook commit fails (race: new moto booked between dry-run and commit,
  transient DB error) → paid, not swapped, only `debug_log`. Marker kind `swap` verifies only PI status (payment_verify.dart:47-60) and is
  CLEARED in `_onPaymentSuccess` before the commit (:1292-1293) → app restart after kill = no retry at all.
- Saved-card succeeded swap: marker has no client secret (PP returns no `client_secret` for succeeded off-session) → cannot verify PI after restart.

## 6. Financial documents (where numbers come from)
- Booking ZF/DP standard (GI:563-654): rental = `total_price − extras − delivery + discount + loyalty + late` (GI:573), per-day breakdown +
  "Korekce ceny pronájmu"; extras from `booking_extras`; delivery; discounts from `booking_discounts` (fallback discount_amount); loyalty;
  late. Zero guard: `total_price <= 0` → no ZF/DP (GI:671-679). Total = Σ items (GI:822). Dedup per booking/type (GI:684-731).
- Edit DP (GI:432-560): `priceDiff = price_difference` (from `trg_booking_modified_email` NEW−OLD total) else last history `price_diff`;
  itemized added/removed days + late lines if fresh history, else single line; mismatch → "Korekce ceny úpravy". Dedup fresh same total (GI:457-462).
- KF (SQL trigger, live_schema.sql:9721-9876): rental brutto as GI:573, extras, delivery, single discount line, loyalty, late, minus all DP,
  plus credit notes; negative → DB credit note `final_overpay`. Assertion warning if ≠0.
- Shop docs (GI:352-404): items + shipping + "Sleva" (discount). shop_final subtracts DPs.
- App never decides document amounts (GI ignores `amount`; InvoiceService.generateAdvanceInvoice(id, amount) = only a trigger).
- `financial_events` = PI amount (correct automatically).

## 7. Shop checkout + 15 Kč
- Client pre-check before creating order (shop_checkout_screen.dart:426-435) and after server total (:490-494) → "Napsat nám/Odebrat kód".
- `create_shop_order` v2 (`20260924d_voucher_nominal_order.sql`; live: total = GREATEST(base−discount,0), auto-confirm only `total=0 AND
  discount>0`). Customers cannot UPDATE `shop_orders` (RLS only admin + customer SELECT) → new column is safe without a guard trigger.
- PP shop: `<=0 → 409 no_payment_needed`, `<15 → 400 below_minimum`.

## 8. Old app versions (4.1.3 and older) — what they send / how they react
- Same request shape (`amount` = shown amount, `type`, ids, optional `payment_method_id`, `change`); no `card_min`/`attempt_id` fields.
- Show server `error` text raw on unknown codes; handle `{success:true, free:true}` as success in sheet flow and shop; in SAVED-CARD flow a
  `free` response lands in `default` → failure dialog (70a94933 payment_screen.dart:740-747) → a server waiver must answer saved-card
  requests in the off-session-succeeded shape (`{success:true, off_session:true, status:'succeeded'}`) so 4.1.3 polls and succeeds.
- Swap: commit client-side via RPC after payment (no rounding; unaffected).
- Restore: direct UPDATE (needs server-side stamping to stop re-cancel, §9 S2).
- Rule for compat: server NEVER charges more than the `amount` sent; rounding only when the client sends `amount = 15` AND `card_min: true`.
  Old client with 1 < due < 15 → clear 400 `below_minimum` (no charge; today they get a 500/decline anyway).

---------------------------------------------------------------------------------------------------------------
## 9. Minimal safe change set

### Policy (D1/D2, applied server-side; app mirrors it for display)
`due` = server amount (booking/sos: `total_price`; extension: dry-run `expected`; shop: `shop_orders.total`).
- `due ≤ 0` → existing free paths.  `0 < due ≤ 1` → **waive**: no Stripe; record `card_rounding = −due` and fold (total − due = 0).
- `1 < due < 15` → **round up**: charge exactly 15 iff request has `amount==15 && card_min===true`; record `card_rounding = 15 − due`
  folded into total; else 400 `below_minimum` (+ `due`, `min:15`).  `due ≥ 15` → unchanged.
- Line texts (documents, cs): `+X` "Dorovnání na minimální platbu kartou (15 Kč)"; `−X` "Zaokrouhlení — částka do 1 Kč se neúčtuje".

### SQL drafts (paydec/sql/, owner approval, guarded/idempotent, Czech header, no BEGIN/COMMIT)
- **S1 `…_card_rounding.sql` (D1/D2):** `ALTER TABLE bookings/shop_orders ADD COLUMN IF NOT EXISTS card_rounding numeric(10,2) NOT NULL
  DEFAULT 0`; bookings guard trigger (pattern `_protect_booking_mileage`, 20260929f): customer JWT (`auth.uid() IS NOT NULL AND NOT
  is_admin()`) cannot change it (UPDATE keeps OLD, INSERT forces 0); `generate_final_invoice_on_complete` body copied 1:1 from live
  (live_schema.sql:9721-9876) + `v_base_rental -= card_rounding` + explicit line when ≠0. STATE_2/3/4/6 updates.
- **S2 D3 restore:** take existing draft + (a) promo re-check in `booking_discounts` (promo active, `valid_to`, `max_uses`) → `promo_unavailable`;
  (b) BEFORE UPDATE OF status trigger stamping `restored_at=now(), restored_by_source='app'` on customer-JWT cancelled→pending (fixes 4.1.3
  without release; Velín/admin and SECURITY DEFINER RPC untouched); (c) cron also skips rows with `checkout_started_at > now()-10 min`
  (PP sets it for app intents) so a payment in flight is not cancelled; keep everything else from the draft (30 min from `restored_at`).
- **S3 swap rounding (D1 for swaps, needed for consistent docs):** `split_booking_moto_swap` rev.12 = DROP old 6-arg + CREATE with 7th
  `p_card_rounding numeric DEFAULT 0` (honoured only when `v_admin`, i.e. service_role/admin): REPLACE `total_price += v_net + r`,
  history entry `card_rounding: r`, `card_rounding += r`; SPLIT: B `total_price += r`, `card_rounding = r`. Body otherwise 1:1 from
  20260922a; re-GRANT as now (anon revoked by 20261011d — keep the live grant set). Waiver (0<net≤1) also via service path (`r = −net`).
  If owner rejects S3: swaps with 1<net<15 keep today's block (state it in the app), everything else proceeds.

### Edge (deploy live on merge — must degrade safely when S1/S3 not yet applied: feature-detect missing column `42703`/`PGRST204`
or missing 7-arg RPC `PGRST202` → behave as today, i.e. `below_minimum`; deploy-sql and deploy-functions run in parallel)
- **E1 PP (D1/D2/D4)** — new small modules, `index.ts` only wiring (file already 1190 lines):
  - `card-minimum.ts`: `classifyDue(due, amount, cardMin)` → `ok|waive|round|below_minimum`; writers:
    booking/sos (unpaid) `UPDATE bookings SET total_price=15, card_rounding=card_rounding+(15−total_price) WHERE id AND payment_status='unpaid'
    AND total_price>1 AND total_price<15` before the PI (idempotent); waive `total_price=0, card_rounding=−total` then `confirm_payment('free')`
    (extend free path PP:812-892 to `due ≤ 1` with the 100 % check tolerance of 1 Kč); shop: same on `shop_orders` (`total`, `card_rounding`),
    waive → `confirm_shop_payment('free')` → `{success:true, free:true}`; extension/swap: put `card_rounding` into PI metadata only
    (applied on success by E2). Saved-card waiver response shape: off-session `succeeded` (4.1.3 compat, §8).
  - `intent-guard.ts`: (1) Stripe `idempotencyKey` on every `paymentIntents.create` = hash(type, booking/order id, amount, pm_id|'sheet',
    `attempt_id` from new app else minute bucket, chg hash); (2) before creating: retrieve stored PI (`bookings/shop_orders.
    stripe_payment_intent_id`, only if `metadata.type` & id match): `succeeded/processing` → 409 `payment_in_progress` (for extension:
    succeeded AND its `payment_ref` not yet in modification_history); `requires_*` → cancel it (stale sheet on another device can't charge),
    then create new; (3) set `bookings.checkout_started_at=now()` for app booking intents (S2 grace).
  - Codes on every refusal (keep HTTP status & `error` Czech text, no contact): `missing_booking_id`, `missing_order_id`, `invalid_amount`,
    `already_paid` (+`already_paid:true`, keep 409 — 4.1.3 shows the text, branch app maps to success), `free_mismatch`+`server_total`,
    `free_confirm_failed`, `below_minimum`+`due`, `payment_in_progress`, `change_not_applicable` (replace raw-code text PP:797);
    outer catch: Stripe `amount_too_small`→400 `below_minimum`, `idempotency_error`→409 `duplicate_request`, rate limit/API connection→503
    `stripe_unavailable`, other→500 `server_error` with Czech text (no raw Stripe English).
  - New action `complete_extension {payment_intent_id}` (D6, owner JWT): retrieve PI; require `succeeded`, `metadata.type==='extension'`,
    booking owned by caller → run shared apply (E2) → `{success, state:'applied'|'already_applied'|'pending'|'failed', code}`.
  - Also return `client_secret` on off-session `succeeded` (marker/queue can verify PI later).
  - payment-flows.ts: web booking checkout / Velín SOS link / web shop → explicit `below_minimum` guard for 1<amount<15 (web rounding = later).
- **E2 webhook-receiver (D1/D4/D6):** move `applyExtensionChange` (+`placeFingerprint`, `chgFromMetadata`) to
  `_shared/extension-apply.ts` returning a result (pure move first); add: `metadata.card_rounding` → total `+= r` and `card_rounding += r`
  in the SAME update + history `card_rounding`; **F1 fix**: if current row already equals the target state (non-total target columns equal)
  treat as applied: total := target absolute (+r), never `cur + paid`; swap commit passes `p_card_rounding` (fallback 6-arg when S3 absent);
  transient swap/apply failure (RPC error/exception) → rethrow → 500 → Stripe retry; permanent codes (`new_moto_unavailable`,
  `wrong_status`, `swap_date_out_of_range`, `license_insufficient`, `not_found`, `forbidden`) → 200 + `debug_log` error `swap_commit_failed`
  (Velín). PI succeeded path stays otherwise identical.
- **E3 generate-invoice:** booking standard: `baseRental −= card_rounding` + line; edit: if fresh last history has `card_rounding` → explicit
  line instead of "Korekce"; shop: line from `shop_orders.card_rounding`; dedup untouched (totals already include rounding).
- process-refund: no change (folding keeps the customer cap right). Velín BookingDetail line display = optional.

### App (both trees, same commit; avoid v2 files, app_shell.dart, router.dart)
- **A1 rounding helper** in `features/payment/payment_refusals.dart` (or new `card_minimum.dart`): `cardCharge(due) → (charge, rounding,
  waived)`; replace every `belowCardMinimum` block: payment_screen.dart:884-889 (`_amount` → 15 + note; `due ≤1` → `_confirmFree`),
  reservation_edit_screen.dart:1059-1068 (`0<effDiff≤1` → apply as free change with `total_price` = old (absorb, no record needed:
  no charge, no DP, KF consistent); `1<effDiff<15` → ctx amount 15, `pendingEditChanges['_card_rounding']`, expected total = new+rounding),
  reservation_swap_section.dart:273-280 (`net≤1` → direct commit path; `1<net<15` → pay 15), shop_checkout_screen.dart:426-435/490-494/497-500
  (`≤1` → PP amount 0; `<15` → pay 15). `StripeService.createPaymentIntent` gains `cardMin`, `attemptId`.
- **A2 transparency UI:** PaymentContextCard / PriceSummaryCard / pay button / shop summary: "Minimální platba kartou je 15 Kč — zaplatíš
  15 Kč (dorovnání +X Kč)"; reservation payment-details tab line from `card_rounding` (model reads it from `select('*')`).
- **A3 D3:** booking_restore.dart: drop `byStaff`/"Napsat nám"; map RPC codes incl. `voucher_unavailable`/`promo_unavailable`/
  `not_restorable`/`date_passed`/`moto_unavailable` to precise texts with actions (Změnit termín / Rezervace / Zkusit znovu);
  pending_booking_fab_provider.dart:84,100 select `restored_at`, countdown from `max(created_at, restored_at)`.
- **A4 D4 client:** `attempt_id` per pay action (reuse only for verify-retry), map new codes in `PaymentRefusals.resolve`
  (`duplicate_request`→verify, `stripe_unavailable/server_error`→serverUnavailable, `below_minimum`→offer "Zaplatit 15 Kč"), keep
  `already_paid`→success, `payment_in_progress`→pending.
- **A5 D5 (no contact anywhere in payment error states):** remove `psHelpLine` footer (payment_error_sheet.dart:186-196); remove all
  "Napsat nám"/`openContactUs` secondaries and `contact:true` (payment_refusals.dart:107,139,153,189,200,203,237,242; payment_screen_problems.dart:
  84-91,119-122,318-319,509-510; payment_screen.dart:1215; shop_checkout_screen.dart:343-344,608-609,627-634; reservation_edit_states.dart:
  118-119,134-135,152-153,167-168; booking_restore.dart:55-62,75-76); replace texts that contain contact/"napiš nám" via NEW keys
  (psMaxBookingBody, psMaxEditBody, psDraftUnknownBody, psBelowMin*, fxBelowMinResume, fxRestoreByStaff, psFreeCheckFailedBody,
  psRefusalUnknown, psEditFail, psMoveFail, psOrderFail, psRestoreFail, psCancelFail, psCancelForbidden, psSwapUnknown, psSlevomatUnverified,
  psSwapStaffBody/psEditStaffBody) — each says exactly what failed and the fix. Mapper (payment_error_mapper.dart:217-315):
  `lost_card/stolen_card/pickup_card` → generic bank decline (don't reveal), `currency_not_supported` → own text (card can't pay in CZK),
  add `duplicate_transaction`→verify, `payment_intent_payment_attempt_expired`/`payment_intent_payment_attempt_failed`→retry text,
  `payment_method_provider_decline`→wallet declined, `invalid_amount`→below-minimum/rounding, `rate_limit`/`api_connection_error`→processing.
- **A6 D6:** new `core/paid_change_queue.dart` (SharedPreferences `mg_paid_change_queue_v1`: {bookingId, piId, kind, expectedTotal?, at});
  enqueue as soon as a swap (and rounded edit) payment is known succeeded, BEFORE `_onPaymentSuccess` clears markers (payment_screen.dart:
  1292-1293); new apps complete via PP `complete_extension` (not the RPC; S3 rounding needs service role), retry with backoff; drain on app
  start (inside `paidAfterRestartProvider`, pending_booking_fab_provider.dart:140-182 — no app_shell edit) and on
  `OfflineGuard.onBackOnline` (main.dart:237, one added call, both trees); result screen "Výměna se dokončuje" (pending outcome with verify =
  complete action) replaces `_staffOutcome(swap)` (payment_screen.dart:1356-1361); permanent failure → precise text, no contact.
  For rounded edits the client fallback must NOT write `total_price` (server owns total+rounding); other columns/extras rows as today.
- **A7 i18n:** all new strings in NEW `core/i18n/translations_ext_43_payments.dart` (43 is the next free number; 8 langs; if >5000 tokens
  split _a/_b), registered with ONE line import + ONE list entry after `translationsExt42Refix3B` in `translations.dart` of BOTH trees
  (Android copy currently has uncommitted v2 lines — re-read right before editing). Mapper texts resolve via `translations` fallback (mapper
  `_t`, payment_error_mapper.dart:334-346) as long as the key is not in its private maps; iOS substitution applies automatically.

### Order / verification
1. Owner approves S1 (+S2, S3) text → commit SQL + STATE_2/3/4/6.  2. Edge E1–E3 (feature-detected) — deno check vs baseline counts.
3. App A1–A7 both trees; flutter analyze (no new issues; iOS in scratch copy), tests, `diff -rq lib` only whitelist + v2 differences.
4. Release app after SQL+edge live. Old apps: below_minimum text, waiver success shapes, restore stamped by trigger.

## 10. Owner questions (only if needed)
- S3 (swap RPC 7th param) acceptable? Without it swap rounding cannot be documented consistently.
- Is `card_rounding` refundable on storno? (Folded design refunds it pro rata with `total_price` — recommended.)
- Web (Checkout) rounding as visible line item later, or keep web blocked with `below_minimum`?
- Permanent swap-commit failure after payment (race): staff completes / refunds — notification channel for Velín (debug_log only today).
