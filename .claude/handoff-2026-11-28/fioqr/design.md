# Fio bank / QR payment — design (Part 2)

Builds on `current_state.md` (same directory) and on the operator change that is being written in parallel:
bank account, IBAN and bank name always come from `app_settings.company_info` through
`supabase/functions/_shared/company.ts` (`loadCompany`) and `supabase/functions/qr-payment/spd.ts`
(`buildSpd`, `qrBankDetails`); Velín reads them through `velin/src/lib/company.js`. Nothing below contains
an account number.

SQL drafts (not in the repo) are next to this file: `20261130a1 … 20261130f`. All of them were applied
twice to a local copy of the live schema brought up to the repo's newest migration (rig database
`q_fioqr`); the second run changed nothing; a smoke test of every new function passed (section 5).

## 0. Principles

* **Reuse first.** Motorcycle and gear-only bookings keep the existing QR flow (`qr-payment`,
  `bookings.payment_vs`). Only two things are new on the server: a small registry of payment requests for
  what cannot live on a booking row (a shop order; a priced change that waits for its money), and one
  dispatcher in `fio-sync`.
* **Same confirmation code as the card.** Shop order → `confirmShopPayment(…, 'bank_transfer')`
  (webhook's routine, already has the `method` argument). Paid change → `applyPaidExtension`
  (shared by webhook and `complete_extension`). Booking → the existing block of `fio-sync`
  (1:1 with the Velín button), moved into its own function so automatic matching and manual pairing run
  the very same code.
* **No UX change outside the request.** The only customer-visible additions are the payment-method
  chooser (the existing two-radio block of the booking form) on three more pages, the QR box (the existing
  one) and a „waiting for payment“ card.
* **The app is not touched.**

---

## 1. QR payment on the web

### 1.1 Shared pieces

**Variable symbols.** One sequence for everything: `booking_vs_seq` (8 digits from 10000001, at most 10
digits allowed by the QR standard). `bookings.payment_vs`, `bookings.mod_surcharge_vs` and the new
`bank_payment_requests.vs` all draw from it, so two payment requests can never share a VS. The new helper
`_next_bank_vs()` additionally skips a number that already exists anywhere, including invoice VS
(a ZF number `ZF-2026-0204` becomes VS `20260204`; the sequence would reach that range after 10 million
requests). Draft `20261130b`.

**Registry `bank_payment_requests`** (draft `20261130b`): `kind` (`shop_order` | `booking_change`), `vs`
(unique), `amount`, `order_id` | `booking_id`, for a change the payload `chg` + `srv` (exactly the strings
the card path puts into Stripe metadata — without the 8 × 500 character limit), `status`
(`pending → paid | failed | expired | cancelled`), `expires_at`, `fio_id`, `result`. At most one pending
request per booking / order (partial unique indexes). Admins read; only the server writes.

**Shared server routine „create bank payment request“** — new `supabase/functions/_shared/bank-request.ts`:

```
createBankRequest(sb, { kind, orderId?, bookingId?, amount, chg?, srv?, changeKind?, lang, holdMinutes,
                        customer: {email, name}, number, createdBy? })
  1. RPC create_bank_payment_request  → { request_id, vs, amount, expires_at, reused }
  2. loadCompany(sb) → qrBankDetails → buildSpd(iban, amount, vs, message)   (operator change modules)
  3. unless reused: customer e-mail from template shop_qr_payment / booking_change_qr_payment
     (fallback inline HTML in 8 languages, same look as booking_qr_payment), ZF attached for a shop order
  4. returns { request_id, vs, amount, account, iban, bank, spd, expires_at }
```

A repeated call for the same order / the same change returns the same request (same VS, no second mail) —
the anti-spam rule `qr-payment` already has. No ops mail „please check the account“: the payment is
confirmed by the machine and waiting requests are visible in Velín (section 2).

**Texts of the routine** (subject, lead, deadline sentence, bank-statement message) in 8 languages go into
a new `_shared/bank-request-texts.ts`, built like `qr-payment/texts.ts` + `fallback-texts.ts`. The two
e-mail templates are Czech rows in `email_templates` (draft `20261130e`); `send-email` translates and
caches the other seven languages on first use, exactly as it does for `booking_qr_payment`.

**Dispatcher in `fio-sync`** — one function decides what an incoming movement pays and calls the right
confirmer:

```
dispatch(tx):
  not CZK                         → no_match + mail                         (as today)
  target = manual target written by an admin (section 2), otherwise by VS, in this order:
     1 bank_payment_requests.vs   2 bookings.payment_vs   3 bookings.mod_surcharge_vs
     4 invoices.variable_symbol of a ZF  → its booking  — or, new, its shop order
  no target                       → no_match (+ mail when it has a VS or is ≥ 50 Kč)       (as today)
  expected = price of the target; received = this movement + earlier movements with the same VS
             that ended as amount_mismatch
  received < expected (and the admin did not accept the lower amount) → amount_mismatch + mail
  booking          → confirmBookingBank      (today's block, extracted)
  surcharge        → confirmSurchargeBank    (today's block, extracted; RPC confirm_booking_surcharge)
  order / request(shop_order)   → confirmOrderBank  = confirmShopPayment(sb, orderId, 'FIO <id>', null, 'bank_transfer')
  request(booking_change)       → confirmChangeBank = applyPaidExtension(...) + markPaidAfterChange
```

`fio-sync` is split into files (repo rule: about 5 000 tokens per file): `index.ts` (auth, actions, lease,
download, loop), `fio-api.ts` (`last`, `periods`, `set-last-date`, row mapping incl. the raw movement),
`dispatch.ts`, `confirm-booking.ts`, `confirm-change.ts`, `confirm-order.ts`, `ops-mail.ts`, existing
`gear-msg.ts`.

### 1.2 Reservation edit — surcharge by QR

**Model: the change is written when the money arrives** — the same rule as with a card. (The Velín model
„write now, owe later“ is not used: an unpaid extension would have to be rolled back.)

| | |
|---|---|
| Where the choice appears | After the customer confirms a change that costs money, before leaving for Stripe: a small dialog with the two radios of the booking form („Platba online…“ / „Platba QR kódem / převodem…“). One dialog for all four call sites. |
| Server | `process-payment` `type:'extension', mode:'checkout'` gets one more field: `pay_method:'bank'` (web only, signed-in owner; the same field name as for the voucher). **All existing checks run unchanged** (owner, stale base, dry run, trailer, amount). Where the card path would create the Checkout Session, the bank path calls `createBankRequest(kind:'booking_change', amount = exact surcharge, chg = JSON.stringify(change), srv = metadata.srv)`. No card minimum: 1–15 Kč is paid exactly; up to 1 Kč is waived as today. Starting a card payment for the same booking cancels a pending bank request. |
| State while waiting | Booking unchanged. Request `pending`, valid **60 minutes** (question 1). The new dates / motorcycle are **not blocked** for others (question 2). |
| Customer sees | The edit page shows a card „Čekáme na platbu doplatku“ with the QR box (amount, account, IBAN, bank, VS, time limit), a „Zrušit a zvolit jinak“ button (RPC `cancel_bank_payment_request`) and polls the request every 5 s. The card is driven by server state (RPC `get_bank_payment_request(p_booking_id)`), so it is there after a reload or on another device. The same data arrives by e-mail. |
| Money arrives in time | `confirmChangeBank`: optional stale-base check (payload `_base` against the booking), then `applyPaidExtension({ bookingId, chg, srv, paidCzk: request.amount, payRef: 'FIO <id>', rounding: 0, since: request.created_at, via: 'webhook' })`. `applied` / `already_applied` → `markPaidAfterChange`, request `paid`, movement `confirmed_change`. The customer mail „rezervace upravena“ with the difference receipt and the new contract is sent by the existing DB trigger, as after a card. The page switches to the usual success box. |
| Change can no longer be written | (`failed`: bike taken meanwhile, booking cancelled / finished, base changed) → `handlePaidChangeFailure(…, autoRefund:false)` — the existing log + staff mail —, request `failed` with the reason, movement `needs_review` „vraťte doplatek“. The page says the change could not be made, the booking is unchanged and the money is being returned. Staff send it back (section 2; automatic payment order is question 6). |
| Transient error | (`retry`) movement stays `new`, next run tries again; after 30 minutes → `needs_review`. |
| Not paid | After 60 minutes the request becomes `expired` (SQL, every minute). Nothing else happens — the booking was never changed. The page offers the change again. |
| Paid late / after cancelling | `needs_review` + staff mail. Staff choose „Přesto provést“ (manual pairing runs the same routine, which re-checks availability) or return the money. |

Files: `process-payment/index.ts` (read `pay_method`, branch after the validation block, before the
Stripe session — into a new `process-payment/bank-change.ts`), `_shared/bank-request.ts`,
`fio-sync/confirm-change.ts`; web: new `js/pages-upravit-rezervaci-qrpay.js` loaded last in
`pages/upravit-rezervaci.php` (after `-status.js`), the four `fetch(…/process-payment…)` call sites
(`pages-upravit-rezervaci.js` ×2 by a one-token patch of the minified core, `-gear.js`, `-swap.js`)
routed through `MG._editRez._payFetch(url, opts)`. `_payFetch` shows the dialog; for a card it is a plain
`fetch`; for QR it adds `pay_method:'bank'` and answers the caller with a `checkout_url` that points back to
`/upravit-rezervaci?edit_booking=<id>&qr=1`, so the existing callers need no other change. The stale-base
comparison (`process-payment/index.ts:627-646`) moves into a small shared helper used by both places.

### 1.3 Gift voucher by QR

| | |
|---|---|
| Where | `pages/poukazy-objednat.php`: the two-radio chooser above the „Pokračovat k platbě“ button. |
| Server | Same request as today plus `pay_method:'bank'`. `handleWebShopCheckout` computes the price with `quote_web_voucher_order` and creates the order and its items exactly as today (`payment_method:'bank_transfer'`), skips the Stripe customer / session, calls `createBankRequest(kind:'shop_order', holdMinutes: 7 days)` and generates the ZF with the request's VS (`generate-invoice` already accepts `variable_symbol` and `due_note`). |
| State while waiting | `shop_orders.status='new'`, `payment_status='pending'` — the same state an abandoned card order has. **No voucher exists yet.** Nothing is held. |
| Customer sees | The form is replaced by the QR box (as on the booking form) with „Hotovo“ → `/potvrzeni?order_id=<id>&flow=qr`: the existing „waiting“ card, polling until paid, then the existing voucher confirmation with the codes. E-mail with QR and ZF immediately; e-mail with the voucher after payment. |
| Money arrives | `confirmShopPayment(…, 'bank_transfer')` — voucher codes by the DB trigger, discount-code usage by the DB trigger, invoice, mail `voucher_purchased` with the PDF. Identical to the card. |
| Discount codes | Checked and priced when the order is created (as with a card); the QR carries the discounted amount; usage is counted when the money arrives. A code that expires or runs out meanwhile is still honoured for this order (question 4). |
| Not paid | The request shows as `expired` after 7 days (question 3); the order stays unpaid like any abandoned order. |
| Paid late | Confirmed normally — a voucher holds no capacity and the customer has paid the agreed price. |

Files: `process-payment/payment-flows.ts` (`handleWebShopCheckout`: early `pay_method` branch after the
price is known), `pages/poukazy-objednat.php` (chooser, QR box, texts), `js/pages-potvrzeni.js` +
`pages/potvrzeni.php` (`flow=qr` for an order: reuse the pending card, poll
`get_bank_payment_request(p_order_id)` / `get_web_shop_order_confirmation`).

### 1.4 Gear-only rental by QR

The existing motorcycle flow is reused as it is — a gear rental is a web booking.

| | |
|---|---|
| Where | `pages/pujceni-obleceni.php`: the chooser above the submit button; also in the „unpaid → pay“ view of `js/gear-rental-done.js`. |
| Server | After `create_web_gear_booking`, instead of `G.pay` the page calls the existing `qr-payment {booking_id, locale}`. No server change is needed for the flow itself. Wording only: the mail and the QR message say „rezervace“; the lead for a gear booking should say „výpůjčka výbavy“ (one extra text per language in `qr-payment/texts.ts`, chosen by `booking_kind`). |
| Hold / expiry | As for motorcycles: the pending booking holds the stock; cancelled 4 hours after the QR was chosen (draft `20261130c`). |
| Customer sees | QR box in place of the form → „Hotovo“ → the page's own status view (`?resume=<id>`), which already polls `get_web_gear_booking` and shows the confirmation and the document upload when paid. |
| After payment | Unchanged: `fio-sync` already has the gear branch (documents rule, message in the customer's language); locker code and self-service gating follow from the same triggers as after a card. |
| Differences from a motorcycle | Documents: identity + 18 only. No motorcycle door code, only the locker (and gate) code. No loyalty / upsell. All already handled by the existing gear branches. |

Files: `js/gear-rental-submit.js`, `js/gear-rental-api.js` (`G.payQr`), `js/gear-rental-done.js`,
`pages/pujceni-obleceni.php`, `data/gear-rental-flow-texts.php` + `lang/v2/<lang>/gear-flow.php`,
`qr-payment/texts.ts`.

### 1.5 E-shop goods (nearly free)

* **Matching** comes with the dispatcher: VS of the order's ZF (rule 4) or of a bank request (rule 1) →
  `confirmShopPayment`. From then on a customer who simply transfers the money for a ZF is matched too.
* **QR at checkout**: `handleWebProductCheckout` gets the same `pay_method:'bank'` branch
  (`createBankRequest(kind:'shop_order')`, about 15 lines); `pages/checkout.php` + `js/checkout.js` get the
  chooser and the QR box. Recommended as a separate small package, switched on with the e-shop (question 5).
* Known gap, left as it is: goods added as upsell inside the booking form are not ordered when the booking
  is paid by QR. To be solved when the e-shop is switched on (simplest: the upsell block says it is
  available with card payment only).

### 1.6 Existing motorcycle booking — two corrections

1. **Time limit from the QR choice** (draft `20261130c`): `bookings.qr_requested_at`, set once by
   `set_booking_qr_payment`; the cancel job counts the 4 hours from it. An expired QR booking gets the
   normal cancellation e-mail (question 8).
2. **Texts that are no longer true**: `rez.pay.qrNote`, `confirm.qrdocs.payInfo` (8 languages) and the
   staff mail of `qr-payment` („potvrďte ve Velíně“ → „potvrdí se automaticky; ručně jen když do hodiny
   nepřijde“). The confirmation page polls for 30 s only; raise to about 3 minutes.

### 1.7 What happens in every failure case

| Case | Booking / gear rental | Edit surcharge (web) | Voucher / shop order |
|---|---|---|---|
| Underpaid | `amount_mismatch`, staff mail, shown in Velín. A second payment with the same VS is **added** to it; when the sum is enough, it is confirmed. | same | same |
| Overpaid | confirmed; note + staff mail „vraťte přeplatek“; shown in Velín until staff tick it off | same | same |
| Late (after the time limit) | cancelled by then → today `needs_review`. Proposed: try to revive like the card path — if the bike is still free it is confirmed, otherwise `needs_review` (question 7) | `needs_review`; staff apply or return | confirmed normally |
| Duplicate (same VS paid twice) | **new:** `needs_review` „duplicitní platba — vraťte“ + staff mail (today silent). A booking confirmed by hand before the movement arrived stays `already_paid`. | same | same |
| Wrong / no VS | `no_match` + staff mail; staff pair it by hand in Velín | same | same |
| Order / request expired | — | `needs_review` | confirmed (nothing was held) |
| Discount code no longer valid at payment | not applicable (price fixed on the booking) | not applicable | honoured as priced |
| Change no longer possible | — | request `failed`, booking unchanged, money returned by staff | — |
| Foreign currency | `no_match` + staff mail | same | same |
| Processing error | **new:** retried on the next runs for 30 minutes, then `needs_review` + staff mail (today final and silent) | same | same |

### 1.8 Texts in 8 languages — where the keys live

| Page | Keys | Files |
|---|---|---|
| Booking form (existing) | `rez.pay.*`, `rez.qrpay.*` — change `rez.pay.qrNote`; `confirm.qrdocs.payInfo` | `motogo-web-php/lang/{cs,en,de,es,fr,nl,pl,uk}.php`; whitelist `pages/rezervace.php:129-130` |
| Reservation edit | new `editRez.qr.*`: `choose`, `card`, `cardNote`, `qr`, `qrNote`, `waitTitle`, `waitText` („Úpravu provedeme, jakmile platbu připíšeme…“), `deadline` („Zaplaťte do {time}“), `cancel`, `expired`, `failed`, `paid`; QR table labels reuse `rez.qrpay.amount/account/bank/vs` | same eight `lang/*.php`; passed to JS in `pages/upravit-rezervaci.php` |
| Voucher | new `voucher.pay.*` (`choose`, `card`, `cardNote`, `qr`, `qrNote`), `voucher.qr.*` (`title`, `sub`, `deadline`, `note`, `done`); pending card on `/potvrzeni` reuses `confirm.*` | same eight `lang/*.php` (flat `voucher.*` keys); `pages/poukazy-objednat.php` `GV_I18N` |
| Gear rental | new `pay_choose`, `pay_card`, `pay_card_note`, `pay_qr`, `pay_qr_note`, `qr_title`, `qr_sub`, `qr_deadline`, `qr_note`, `qr_done` | `data/gear-rental-flow-texts.php` (cs) + `lang/v2/{en,de,es,fr,nl,pl,uk}/gear-flow.php` |
| E-mails | templates `shop_qr_payment`, `booking_change_qr_payment` (cs, auto-translated); fallback + subject + lead + deadline sentence in 8 languages | DB `email_templates` (draft `20261130e`); `supabase/functions/_shared/bank-request-texts.ts` |
| Gear wording in the QR mail | `thanksGear` / subject for a gear booking | `supabase/functions/qr-payment/texts.ts`, `fallback-texts.ts` |

Proposed Czech wording of the method notes: card — „Okamžité potvrzení“; QR — „Potvrdíme automaticky,
obvykle do pár minut po připsání platby“.

---

## 2. Velín — screen „Banka“

**Place:** a new tab **„Banka“** in Finance (`velin/src/pages/Finance.jsx`, `FINANCE_TABS` after
„Platby“; lazy `accounting/BankTab.jsx`). No new menu section, so the existing per-user section permission
„Finance“ covers it. A badge on the Finance menu item (`badgeKey:'bank'` in `lib/velinSections.js`,
counted in `components/Sidebar.jsx`): number of movements waiting for staff; red when the sync is failing
or a token expires within 14 days.

**Layout** (four blocks, each its own file under `velin/src/pages/accounting/bank/`):

1. **Status strip** (`BankStatus.jsx`) — from `fio_sync_state`: last successful sync („před 40 s“), error
   state in words, account the token reads vs. the account in company settings, token validity with days
   left and an „Upravit“ dialog (two dates + „automatické prodlužování“ → RPC
   `admin_fio_set_token_expiry`), button „Synchronizovat teď“ (invokes `fio-sync`; a 409 from the bank is
   shown as „zkuste to za 30 s“). Superadmin only: „Nastavit zarážku na dnešek“ (`fio-sync
   {action:'set_marker'}` → Fio `set-last-date`) for the first start with a new token.
2. **Pohyby** (`BankMovements.jsx`) — list of `fio_transactions`, newest first, pagination. Filters:
   „K vyřízení“ (`no_match`, `amount_mismatch`, `needs_review`, `error` — the default view),
   „Spárované“, „Ignorované“, „Odchozí“, „Vše“; search by VS / name / amount; date range. Columns: date,
   amount (green in / grey out), VS, counter-account and name, message, status badge, target link (booking
   / order). Realtime on `fio_transactions` + 60 s polling (pattern `hooks/useKioskAlerts.js`).
3. **Detail** (`BankMovementDetail.jsx`, modal) — all stored fields, the raw Fio movement (`raw`), the
   note of the automatic decision, history from `admin_audit_log`, and the actions:
   * **Spárovat** — pick the target: booking (search by number / name / VS), surcharge of a booking, shop
     order, waiting change request; the dialog shows expected vs. received amount and, if lower, a checkbox
     „přijmout nižší částku“. → RPC `admin_fio_pair_transaction` (audited) → `fio-sync {action:'process',
     fio_id}` runs **the same confirmation routine** as automatic matching and returns the result. If the
     call is lost, the next cron run finishes it.
   * **Ignorovat** with a mandatory note (interest, own transfer, returned by hand) → RPC
     `admin_fio_ignore_transaction`.
   * **Vrátit ke zpracování** → RPC `admin_fio_reopen_transaction` (matches again by VS on the next run).
4. **Čekající platby** and **Platební příkazy** (`BankWaiting.jsx`, `BankOrders.jsx`) — what the machine
   is waiting for: unpaid QR bookings (`pay_channel='qr'`), booking surcharges due (`mod_surcharge_due`),
   pending `bank_payment_requests` — each with VS, amount, time left and a link; and the list of
   `fio_payment_orders` (refunds) with amount, target account, state `pending / submitted / failed`, batch
   number, error text, link to the credit note and booking, and — where it can be found — the outgoing
   movement that carried it (same VS, amount and account).

**Copy the patterns from:** `accounting/PaymentsTab.jsx` (filters, stat tiles, `Table`),
`accounting/CreditNotesTab.jsx` (pagination, detail modal, search), `hooks/useKioskAlerts.js` (realtime),
`lib/debugLog.js` `debugAction` (action logging), `pages/booking/PaymentConfirmModal.jsx` (wording of
amounts / VS).

**RLS / RPC design** (drafts `20261130a1`, `a2`, `b`):

* `fio_transactions`, `fio_payment_orders`, `fio_sync_state`, `bank_payment_requests`: admin **SELECT
  only** (`is_admin()`); the old `FOR ALL` policies on the first two are replaced — Velín never wrote
  there. Customers and anonymous visitors see nothing.
* Every change goes through a `SECURITY DEFINER` RPC that checks `is_admin()`, validates the state and
  writes `admin_audit_log` (who, what, old → new): `admin_fio_pair_transaction`,
  `admin_fio_ignore_transaction`, `admin_fio_reopen_transaction`, `admin_fio_set_token_expiry`.
* Confirmation itself is done by the edge function with the service key; `fio-sync` already accepts an
  admin JWT (`index.ts:126-135`). New actions: `process` (one movement), `sync` (default), `set_marker`
  (superadmin check inside).
* `fio_transactions` and `bank_payment_requests` are added to the realtime publication;
  `fio_sync_state` is not (it changes every minute; the status strip polls it).

---

## 3. Token expiry warning

**Fact** (Fio documentation, version 16. 10. 2025, checked): a token is valid at most 180 days; with
„automatické prodlužování“ every login to internet banking moves it to 180 days from that day; the API
has **no call that returns the validity**; a dead token answers HTTP 500.

**Design**

* The validity dates (read token, payment token) and the „automatic prolongation“ flag are kept in
  `fio_sync_state` and edited in the status strip of the „Banka“ tab. They are not in `app_settings`,
  because that table is readable by anonymous visitors.
* **Warnings 30 / 14 / 7 / 3 / 1 / 0 days before**, each threshold once, only between 8 and 20 o'clock:
  e-mail to info@ + the tab's badge and status strip (orange ≤ 30 days, red ≤ 14). The text says what to
  do (with prolongation on: „log in to internet banking and move the date“; otherwise how to issue a new
  token and where to put it). Changing the date resets the thresholds.
* **Immediate alarms**, independent of the stored date:
  * the bank answers with an error three runs in a row (three minutes at a one-minute interval) → e-mail
    „synchronizace selhává“; for HTTP 500 the text says the token is most likely invalid or expired; one
    mail per outage, a reminder after 24 hours, a „znovu běží“ mail on recovery;
  * no successful sync for 20 minutes although the cron runs (edge function broken / not starting) →
    e-mail „synchronizace neběží“;
  * the token reads a different account than customers pay to (`company_info.bank_iban` vs. the IBAN in
    Fio's answer) → e-mail once a day. This closes the open point „does the token belong to account
    2303580494?“ automatically.
* **Where the check runs:** in SQL, inside the existing cron tick — `fio_health_alerts()` called by
  `fio_sync_tick()` (draft `20261130d`), plus `fio_sync_end()` called by the edge function at the end of
  each run (draft `20261130a1`). No extra cron job. Because the date and „not running“ checks are pure
  SQL, they work even when the edge function is down. Nothing is alarmed before the sync has succeeded
  once or a validity date was entered, so there is no noise before go-live.

---

## 4. Sync every minute or every five?

**Verdict: one minute is safe — do it**, together with three small protections that are part of the
backend package anyway.

| Question | 5 min | 1 min | Comment |
|---|---|---|---|
| Edge-function calls | 288 / day, 8 640 / 30 days | 1 440 / day, 43 200 / 30 days | +34 560 a month. The plan's quota is **not documented in the repo**; with Supabase's published figures (500 000 a month on Free, 2 million on Pro, then about 2 USD per million) that is 8.6 % / 2.2 % of the quota. Two other jobs already call an edge function every minute (`backfill-poi-photos`, `backfill-route-translations` = 86 400 a month). |
| Rows in `debug_log` per empty run | 0 | 0 | Unchanged. But today a **failing** run writes a row every time (missing or dead token): 288 a day now, 1 440 at one minute → the new code logs only the change of state (first failure, recovery). |
| Other writes per run | — | 1 update of the single row `fio_sync_state` | negligible |
| pg_cron history | 288 rows / day | 1 440 rows / day | `cron.job_run_details` is never cleaned in this project; optional daily clean-up in draft `20261130f`. Not a condition. |
| Staff e-mails | per movement only | per movement only | No e-mail per run, before and after. |
| Bank limit (1 call / 30 s / token) | fine | fine | One call a minute. A 409 is skipped silently. |
| Collision with refunds | 10 % of refund orders hit the 30 s window | 50 % | Only when refunds use the **same** token. The order then waits 31 s and retries once (existing code) — the person who triggered the refund waits half a minute longer; the sync loses one run. With a separate `FIO_PAYMENT_TOKEN` (recommended since 2026-08-30) there is no collision at all. |
| Overlapping runs | needs a 5-minute run | needs a 1-minute run — possible with a burst of payments | New lease in `fio_sync_begin()`: a second run exits at once. Batch reduced from 50 to 10 movements per run. |
| Customer waits for confirmation | 2.5 min on average, 5 max | 30 s on average, 1 min max | The real gain; the web's „waiting“ pages poll long enough to show it. |
| Cost | 0 | 0 | within quota |

Exact SQL (in draft `20261130d`, together with the tick function):

```sql
DO $$
BEGIN
  BEGIN PERFORM cron.unschedule('fio-bank-sync'); EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule('fio-bank-sync', '* * * * *', $cron$ SELECT public.fio_sync_tick(); $cron$);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cron.schedule selhalo (pg_cron nedostupné?): %', SQLERRM;
END $$;
```

Rollback (any time, nothing else depends on the interval):

```sql
SELECT cron.unschedule('fio-bank-sync');
SELECT cron.schedule('fio-bank-sync', '*/5 * * * *', $cron$ SELECT public.fio_sync_tick(); $cron$);
```

The tick also sets `timeout_milliseconds := 55000` on the call. Today the default pg_net timeout applies
and the answer of any longer run is discarded; whether the platform also stops the function when the
caller hangs up could not be verified (see „Not verified“).

**Robustness changes that go with it** (all in `fio-sync`, backend package B1):

1. Lease (`fio_sync_begin` / `fio_sync_end`), batch of 10.
2. Failure logging by state, alarms (section 3).
3. **No lost movements:** an answer that is not valid JSON, or a failed insert, is a failed run (today it
   is treated as „no movements“); and once a day the run reads the last five days through `periods`
   instead of `last` and inserts whatever is missing (duplicates are ignored by the primary key).
4. The raw movement is stored (`raw`).
5. `error` rows are retried; duplicates are reported (1.7).

---

## 5. SQL drafts

All in this directory, named to sort after `20261129*`. Idempotent; no data deleted; no secrets.

| File | Content | STATE files to update |
|---|---|---|
| `20261130a1_fio_state_and_sync_rpcs.sql` | `fio_transactions` + 9 columns, statuses `confirmed_order`, `confirmed_change`, `ignored`; RLS of `fio_transactions` / `fio_payment_orders` → admin SELECT only; table `fio_sync_state`; `_fio_ops_mail`, `fio_sync_begin`, `fio_sync_end` | 1, 2, 3, 5, 6 |
| `20261130a2_fio_admin_rpcs.sql` | `admin_fio_set_token_expiry`, `admin_fio_ignore_transaction`, `admin_fio_reopen_transaction`, `admin_fio_pair_transaction` (audited); indexes on `bookings.payment_vs` / `mod_surcharge_vs`; realtime for `fio_transactions` | 3, 5, 6 |
| `20261130b_bank_payment_requests.sql` | table `bank_payment_requests` + RLS; `_next_bank_vs`, `create_bank_payment_request` (service only), `get_bank_payment_request` (web polling), `cancel_bank_payment_request` (owner / admin), `expire_bank_payment_requests`; realtime | 1, 2, 3, 5, 6 |
| `20261130c_qr_hold_from_request.sql` | `bookings.qr_requested_at`; `set_booking_qr_payment`; `auto_cancel_expired_pending` (4 h from the QR choice; cancellation mail for QR bookings). **Replaces a core function** — the body is today's live body plus two marked changes; diff it against the then-current body before committing. | 2, 3, 5, 6 |
| `20261130d_fio_tick_health_and_schedule.sql` | `fio_health_alerts`; `fio_sync_tick` (expiry of requests, alarms, 55 s timeout); cron `* * * * *`; rollback in the header | 3, 5, 6 |
| `20261130e_bank_qr_email_templates.sql` | templates `shop_qr_payment`, `booking_change_qr_payment` | 6 (and the template list, if kept) |
| `20261130f_OPTIONAL_cron_run_details_retention.sql` | optional daily clean-up of pg_cron history | 5, 6 |

**Tested on the local rig** (PostgreSQL 16 copy of the live schema + all repo migrations up to
`20261128c5`): every file applied twice, schema signature identical after the second run. Smoke test
(`_dl/smoke.sql`, `_dl/thr.sql`): request created / reused / superseded / expired; anonymous role cannot
create or read; owner can poll and cancel, a stranger cannot; customer cannot call admin RPCs or read the
bank tables; admin cannot update a movement directly; ignore needs a note; outgoing movement cannot be
paired; four audit rows written; lease refuses a second run; three failures → one alarm mail, recovery →
one mail, 409 is not a failure; token thresholds 30 / 14 / 7 / 0 each sent once and not at night; a
booking whose QR was chosen 5 minutes ago survives the cancel job although it was created 4.5 hours ago,
one chosen 4 h 05 min ago is cancelled and gets the mail.

Not covered by the rig: real pg_cron / pg_net behaviour, the realtime publication's current members,
data-dependent effects (the rig has no rows), PostgreSQL 17 specifics (none used).

Per the repo rule, SQL goes to the owner as text first; `a1` (16 kB) and `b` (15 kB) are at the upper edge
of the 5 000-token file limit and may need one more split when committed.

---

## 6. Work packages

Order: B1 → B2 → (W1, W2, W3 in any order; V1 in parallel after B1) → W4. Each package can be merged on
its own; nothing customer-visible changes until a web package is merged.

**B1 — backend: sync hardening, dispatcher, Velín actions, one-minute cron**
SQL `a1`, `a2`, `d` (+ `f`). `fio-sync` split into modules; lease; state reporting; `raw`; daily
`periods` reconciliation; dispatcher with manual targets, summed partial payments, duplicate and error
handling; shop-order matching by ZF VS; actions `process` / `set_marker`.
*Tests:* new `supabase/functions/_tests/fio_dispatch_test.ts` and `fio_sync_flow_test.ts` on the existing
`fake-supabase.ts` harness with a stubbed `fetch` returning recorded Fio JSON (empty statement, one
payment per target type, 409, 500, non-JSON body, insert failure, duplicate, partial + remainder,
overpayment, late payment, manual target with a lower amount). Assertions: statuses, exactly one
confirmation call, no confirmation on failures, `fio_sync_end` arguments. SQL: rig run as in section 5 +
`fndiff.sh` for `fio_sync_tick`.

**B2 — backend: bank requests for shop orders and paid changes**
SQL `b`, `c`, `e`. `_shared/bank-request.ts` + texts; `process-payment` (`pay_method:'bank'` in both shop
branches and for extensions — `bank-change.ts`); `fio-sync/confirm-order.ts`,
`confirm-change.ts`; `qr-payment` wording (gear lead, staff mail).
*Tests:* `_tests/bank_request_test.ts` (request reused, superseded, texts in 8 languages, SPD string uses
the IBAN from `company_info` — extend the existing `operator_flow_test.ts` pattern);
`_tests/pp_bank_change_flow_test.ts` (all existing refusals still fire in bank mode; no Stripe call is
made; amount 1–15 Kč is not rounded; ≤ 1 Kč waived); `_tests/fio_change_flow_test.ts`
(`applyPaidExtension` called once with `payRef 'FIO …'`; `failed` → request failed + no refund call;
`retry` keeps the movement `new`); `_tests/fio_order_flow_test.ts` (voucher order confirmed with
`bank_transfer`, second movement = duplicate). SQL on the rig: `c` with the fake clock (`t_shim`), `b` as
in section 5.

**W1 — web: voucher by QR** (`pages/poukazy-objednat.php`, `pages/potvrzeni.php`,
`js/pages-potvrzeni.js`, eight `lang/*.php`).
*Tests:* local PHP server + Playwright with `process-payment` and the RPCs mocked by route interception:
card path unchanged (redirect URL identical to today), QR path shows the box with the mocked account /
IBAN / VS, „Hotovo“ → pending card → flips to the voucher confirmation when the mocked status becomes
paid; all 8 languages render without missing keys; phone width.

**W2 — web: gear rental by QR** (`js/gear-rental-*.js`, `pages/pujceni-obleceni.php`, gear texts ×8).
*Tests:* Playwright as above (mock `create_web_gear_booking`, `qr-payment`, `get_web_gear_booking`):
QR box, resume view of an unpaid booking offers both methods, paid → confirmation + document card.

**W3 — web: edit surcharge by QR** (`js/pages-upravit-rezervaci-qrpay.js`, call sites, PHP, texts ×8).
*Tests:* Playwright with a mocked signed-in session: for each of the four entry points (extend, location
/ generic change, gear, swap) the dialog appears, card path posts the unchanged body, QR path posts
`pay_method:'bank'` and lands on the waiting card; reload keeps the card; cancel removes it; mocked `paid` →
success box; mocked `failed` → „změnu nešlo provést“; mocked `expired` → offer again.

**V1 — Velín: tab „Banka“** (`Finance.jsx`, `accounting/BankTab.jsx`, `accounting/bank/*.jsx`,
`Sidebar.jsx`, `velinSections.js`).
*Tests:* `npm run build` in `velin/` (compare with the saved baseline log; the project has no lint script); a pure-function unit
file for the status helpers (days left, state text, filter predicates) runnable in Node like
`lib/company.js`; manual check list: filters, pair dialog with lower amount, ignore without note is
refused, realtime row update, status strip in the four states (never ran / ok / failing / token ≤ 14 days).

**W4 — optional: e-shop checkout by QR** (`pages/checkout.php`, `js/checkout.js`,
`handleWebProductCheckout`). Same tests as W1.

**After each package:** update `SUPABASE_BACKEND_STATE_1/2/3/5/6.md` for its SQL; `CLAUDE.md` gets one
line about the bank tab and the one-minute sync when everything is in.

---

## 7. Questions for the owner (each with the default the design assumes)

1. **How long does a QR surcharge for a reservation edit wait?** Default **60 minutes**. Typical payment
   by QR is instant; a longer wait only raises the chance that the days are taken meanwhile.
2. **Should the new dates / motorcycle be blocked for others while the surcharge is unpaid?** Default
   **no** — the change is made when the money arrives; if it is no longer possible, the booking stays as
   it was and the money goes back. (Blocking means changing three core availability functions.)
3. **How long is an unpaid voucher order kept as „waiting“?** Default **7 days**; a later payment is
   still accepted and the voucher issued.
4. **Voucher bought with a discount code and paid later — is the discount honoured even if the code
   expired or ran out in the meantime?** Default **yes** (the customer received a QR for that amount).
   The voucher itself is **issued only after the money arrives** — never before.
5. **QR also for e-shop goods at checkout?** Default **yes, as a separate small step when the e-shop is
   switched on**; matching of e-shop transfers works from the first backend package either way.
6. **May Velín send money back by itself for a bank payment that cannot be used** (surcharge for a change
   that is no longer possible, duplicate, late payment)? Default **no for now** — staff get the e-mail and
   the row in „Banka“ with the sender's account and return it in internet banking. Automatic return by
   payment order can be added later; it needs the payment token.
7. **Booking paid by QR after the 4-hour limit:** default **confirm it if the motorcycle is still free**
   (the same as a late card payment), otherwise staff return the money. Today it always waits for staff.
8. **Keep 4 hours for a QR booking, counted from the moment QR was chosen, and send the cancellation
   e-mail when it expires?** Default **yes to both**. (A shorter limit, e.g. 2 hours, frees motorcycles
   sooner but fails transfers from banks without instant payments.)
9. **Offer QR even when the pickup is only a few hours away?** Default **yes, no change** — the option is
   offered always today. Alternative: hide it when the rental starts within 2 hours.

Owner actions outside the code (unchanged from the operator plan): tokens for account 2303580494 in
Supabase secrets (`FIO_API_TOKEN`; separate `FIO_PAYMENT_TOKEN` recommended), automatic prolongation
switched on in Fio, validity dates entered in the „Banka“ tab, marker set to today before the first run.

---

## Not verified

* Live state: whether the cron job exists and runs, whether the tokens are set and for which account,
  whether `company_info` already points to the Fio account, the content of live `email_templates`
  (admin-only table), the Supabase plan and its quota.
* Whether the edge platform stops a running function when pg_net gives up waiting; whether a call the
  bank refused with 409 restarts its 30-second window; how fast the bank lists an instant payment in the
  API (assumed minutes).
* Whether role `postgres` may delete from `cron.job_run_details` on live (optional draft `f`).
* Nothing was run against the live database or the bank. No edge or web code was written or tested —
  only the SQL drafts were executed, on the local rig. The operator-change files this design builds on
  (`_shared/company.ts`, `qr-payment/spd.ts`, `velin/src/lib/company.js`) were still uncommitted and
  changing while this was written.
