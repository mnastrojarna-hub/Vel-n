# Bank / QR payments — interface contract (backend B1 + B2)

Owner of this file: backend agent. Readers: Velín agent (screen „Banka“), web agent (edit page, voucher
page, gear page). **Changes are appended at the top as dated „ZMĚNA“ entries.**

Status legend used below: **[SQL]** = exists only after the SQL drafts `sql_final/20261130*.sql` are applied;
**[EDGE]** = exists after the edge functions of this branch are deployed. Until both are live every new
endpoint answers with the documented „not available“ error and callers must fall back (web → card payment,
Velín → show „funkce se nasazuje“).

## ZMĚNY

* 2026-11-27 23:10 — ZMĚNA: (1) `fio_sync_state.needs_reconcile` (bool) is replaced by `reconcile_since`
  (timestamptz, NULL = no recovery download pending) + internal `reconcile_tries`, `reconcile_try_on`;
  (2) reason code `booking_closed` renamed to **`target_closed`** (used for bookings and shop orders);
  (3) everything marked [SQL] is switched on by the SQL, not by deploying the edge code: with today's
  database `fio-sync` behaves exactly as before (old statuses, no `reason_code`, no order matching) and the
  new endpoints answer `bank_unavailable`.
* 2026-11-27 22:30 — first version.

---

## 1. Tables Velín may read (admin RLS: `is_admin()` → SELECT only; no INSERT/UPDATE/DELETE from the client)

Customers and anon see nothing in these tables. All writes go through the RPCs / edge actions in §2–§3.

### 1.1 `fio_transactions` (one row per bank movement; PK `fio_id bigint`)

| Column | Type | Meaning |
|---|---|---|
| `fio_id` | bigint PK | Fio movement ID |
| `tx_date` | date | booking date of the movement (Prague) |
| `amount` | numeric | > 0 incoming, < 0 outgoing |
| `currency` | text | `CZK`, … |
| `vs` | text null | variable symbol as sent by the payer |
| `counter_account`, `counter_bank`, `counter_name` | text null | payer account / bank code / account name |
| `message` | text null | message for the recipient |
| `tx_type` | text null | Fio movement type (text) |
| `status` | text | see 1.2 |
| `booking_id` | uuid null | matched booking (booking / surcharge / change) |
| `order_id` | uuid null **[SQL]** | matched `shop_orders.id` |
| `request_id` | uuid null **[SQL]** | matched `bank_payment_requests.id` |
| `target_type` | text null **[SQL]** | what the movement was matched to: `booking` \| `surcharge` \| `order` \| `request` |
| `reason_code` | text null **[SQL]** | machine reason of the automatic decision, see 1.3 |
| `expected_amount` | numeric null **[SQL]** | amount the target expected (for under/over-payment display) |
| `note` | text null | Czech sentence of the automatic decision |
| `raw` | jsonb null **[SQL]** | the whole Fio movement (`column0`…`column27`, each `{value,name,id}`) |
| `manual_target_type`, `manual_target_id`, `manual_accept_amount` | text / uuid / bool **[SQL]** | what staff paired by hand |
| `followup` | text null **[SQL]** | open task on a CONFIRMED movement: `overpaid` (return the difference). NULL = none |
| `followup_done_at` | timestamptz null **[SQL]** | set by `admin_fio_ack_followup` |
| `resolved_by`, `resolved_at`, `resolution_note` | uuid / timestamptz / text **[SQL]** | last staff action (pair / ignore / reopen / ack) |
| `attempts`, `first_error_at`, `claimed_until` | int / timestamptz / timestamptz **[SQL]** | internal (retry of processing errors, per-row lock) — display only |
| `created_at`, `processed_at` | timestamptz | stored / last decision |

„K vyřízení“ (needs staff) =
`status IN ('no_match','amount_mismatch','needs_review','error') OR (followup IS NOT NULL AND followup_done_at IS NULL)`.

### 1.2 `fio_transactions.status`

| Value | Czech label | Meaning |
|---|---|---|
| `new` | Čeká na zpracování | stored, the next run decides (also after pair / reopen; also while a processing error is retried) |
| `outgoing` | Odchozí | outgoing movement (only stored) |
| `confirmed_booking` | Spárováno — rezervace | booking / gear rental paid |
| `confirmed_surcharge` | Spárováno — doplatek (Velín) | `mod_surcharge_due` of a booking paid |
| `confirmed_order` | Spárováno — objednávka / poukaz **[SQL]** | shop order paid (voucher issued) |
| `confirmed_change` | Spárováno — úprava rezervace **[SQL]** | web edit surcharge paid and the change written |
| `already_paid` | Už bylo potvrzeno ručně | target was confirmed by hand as bank transfer before the movement arrived |
| `no_match` | Nespárováno | no / unknown VS, or foreign currency → staff pair (suggestions §3.4) or ignore |
| `amount_mismatch` | Nižší částka | less than expected; a later payment with the same target is added up |
| `needs_review` | Ke kontrole | matched, but must not be confirmed automatically (see `reason_code`) |
| `error` | Chyba zpracování | legacy / pre-SQL final error |
| `ignored` | Ignorováno **[SQL]** | staff decision with a note |

### 1.3 `fio_transactions.reason_code` **[SQL]**

| Value | Czech label (what staff should do) |
|---|---|
| `no_vs` | Platba bez variabilního symbolu — spárujte ručně |
| `vs_not_found` | Variabilní symbol neodpovídá žádné čekající platbě — spárujte ručně |
| `foreign_currency` | Platba v cizí měně — spárujte ručně |
| `underpaid` | Přišlo méně, než se čekalo — počkejte na doplatek, nebo přijměte nižší částku |
| `overpaid` | Přeplatek — rozdíl vraťte zákazníkovi (`followup='overpaid'`) |
| `partial_sum` | Dřívější částečná platba, dorovnaná dalším pohybem |
| `accepted_lower` | Obsluha přijala nižší částku |
| `duplicate` | Duplicitní platba (cíl už je zaplacený) — vraťte ji |
| `late_cancelled` | Platba po zrušení rezervace a termín už není volný — vraťte ji |
| `late_revived` | Pozdní platba — rezervace byla automaticky obnovena (informace) |
| `target_closed` | Rezervace / objednávka je zrušená nebo ukončená — vraťte platbu nebo rozhodněte ručně |
| `request_expired` | Doplatek úpravy přišel po lhůtě 60 min — „Přesto provést“ (spárovat s požadavkem) nebo vrátit |
| `request_cancelled` | Doplatek úpravy, kterou zákazník mezitím zrušil — provést, nebo vrátit |
| `change_failed` | Zaplacenou úpravu už nešlo provést (termín/motorka obsazena…) — rezervace beze změny, vraťte doplatek |
| `processing_error` | Zpracování opakovaně selhalo (30 min) — zkontrolujte a spárujte ručně |
| `manual` | Spárováno ručně obsluhou |

### 1.4 `fio_sync_state` **[SQL]** (single row `id = 1`)

`last_run_at`, `last_ok_at`, `last_error` (`missing_fio_token` \| `fio_http_<n>` \| `bad_response` \|
`insert_failed` \| `account_mismatch` \| `exception`), `last_error_at`, `last_http_status`,
`consecutive_failures`, `failure_alert_at`, `stale_alert_at`, `lease_until`, `account_iban` (IBAN the token
reads), `id_last_download`, `last_reconcile_on`, `reconcile_since`, `token_valid_until` (date),
`pay_token_valid_until` (date), `token_auto_prolong` (bool), `token_warned_threshold`,
`pay_token_warned_threshold`, `updated_at`. Not in realtime (changes every minute) — poll it, or use
`admin_fio_overview()`.

### 1.5 `bank_payment_requests` **[SQL]**

`id`, `kind` (`shop_order` \| `booking_change`), `vs`, `amount`, `booking_id`, `order_id`, `chg`, `srv`,
`chg_hash`, `change_kind` (`edit` \| `swap` \| `moto` \| `gear`), `status`, `expires_at`, `language`,
`created_by`, `created_at`, `paid_at`, `fio_id`, `result` (jsonb), `note`.

| `status` | Czech label |
|---|---|
| `pending` | Čeká na platbu |
| `paid` | Zaplaceno |
| `failed` | Zaplaceno — úpravu nešlo provést (vrátit doplatek) |
| `expired` | Vypršelo (voucher: pozdější platba se přesto uzná; úprava: ke kontrole) |
| `cancelled` | Zrušeno |

### 1.6 `fio_payment_orders` (existing, refunds by payment order) — unchanged, now SELECT-only for admins.

### 1.7 Realtime **[SQL]**
`fio_transactions` and `bank_payment_requests` are in publication `supabase_realtime`
(`postgres_changes`, RLS applies → admins only). `fio_sync_state` is not.

### 1.8 Existing booking columns used by the waiting list
`bookings.pay_channel = 'qr'`, `payment_vs`, `payment_status`, `qr_requested_at` **[SQL]** (start of the
4-hour limit), `mod_surcharge_due`, `mod_surcharge_vs`.

---

## 2. RPCs

### 2.1 Velín (role `authenticated`, must be admin; every call writes `admin_audit_log`)

All return `jsonb`: `{success:true,…}` or `{success:false,error:<code>,…}`.

| RPC | Parameters | Errors |
|---|---|---|
| `admin_fio_pair_transaction` | `p_fio_id bigint, p_target_type text, p_target_id uuid, p_accept_amount boolean = false, p_note text = null` | `forbidden`, `bad_target`, `not_found`, `wrong_status` (+`status`), `target_not_found` |
| `admin_fio_ignore_transaction` | `p_fio_id bigint, p_note text` (note mandatory) | `forbidden`, `note_required`, `not_found`, `wrong_status` |
| `admin_fio_reopen_transaction` | `p_fio_id bigint` | `forbidden`, `not_found`, `wrong_status` |
| `admin_fio_ack_followup` | `p_fio_id bigint, p_note text = null` — ticks off `followup` (overpayment returned) | `forbidden`, `not_found`, `nothing_to_ack` |
| `admin_fio_set_token_expiry` | `p_valid_until date, p_pay_valid_until date = null, p_auto_prolong boolean = null` | `forbidden` |
| `admin_fio_overview` | none → `{success, state:{…fio_sync_state row…}, sync:'never'\|'ok'\|'failing'\|'stale', todo_count, waiting_requests, token_days_left, pay_token_days_left, company_iban, account_match}` | `forbidden` |

`p_target_type`: `booking` (whole booking price, `p_target_id` = `bookings.id`) · `surcharge`
(`mod_surcharge_due`, `bookings.id`) · `order` (`shop_orders.id`) · `request`
(`bank_payment_requests.id`, used for a web edit surcharge; „Přesto provést“ for an expired/cancelled one).
Pairing is allowed from `no_match`, `amount_mismatch`, `needs_review`, `error`, `ignored`; ignore from the
first four; reopen from all five. `pair` only writes the target and puts the movement back to `new` — the
confirmation is done by the edge function (§3, action `pair` does both in one call).

### 2.2 Web

| RPC | Who | Parameters → result |
|---|---|---|
| `get_bank_payment_request` | anon / authenticated | `p_request_id uuid = null, p_booking_id uuid = null, p_order_id uuid = null` → `{status:'none'}` or `{request_id, kind, booking_id, order_id, status, vs, amount, expires_at, change_kind, created_at, paid_at, reason}`; errors `{error:'login_required'}` (by booking: owner or admin only), `{error:'missing_identifier'}`. `status` already reports `expired` when the time is over. `reason` (only for `failed`): `moto_unavailable`, `new_moto_unavailable`, `booking_cancelled`, `booking_completed`, `stale_booking`, … |
| `cancel_bank_payment_request` | authenticated owner of the booking / admin | `p_request_id uuid` → `{success}`; errors `not_found`, `forbidden`, `wrong_status` |

Cheap to poll (every 5 s is fine). The QR picture / account data come from the edge call in §4.4.

---

## 3. Edge function `fio-sync` (Velín)

`POST /functions/v1/fio-sync`, `Authorization: Bearer <admin session JWT>`, JSON body. HTTP 403
`{success:false,error:'forbidden'}` for a non-admin.

### 3.1 `{}` or `{action:'sync'}` — „Synchronizovat teď“
→ `{success:true, mode:'last'|'periods', fetched, processed, confirmed, surcharge, orders, changes,
no_match, mismatch, review, errors}`; `{success:true, skipped:'busy'}` (another run holds the lease) ·
`{success:true, skipped:'rate_limited'}` (bank: one call per 30 s — „zkuste to za 30 s“) ·
`{success:false, error:'missing_fio_token'|'fio_http_<n>'|'bad_response'|'insert_failed'}`.

### 3.2 `{action:'pair', fio_id, target_type, target_id, accept_amount?, note?}` — one-click pairing
Calls `admin_fio_pair_transaction` **as the calling admin** (audit carries his id) and immediately
processes the movement with the same confirmation routine as automatic matching.
→ `{success:true, result:{fio_id, status, reason_code, note, target_type, booking_id, order_id,
request_id, expected_amount}}` · `{success:false, error:<RPC error code>}` ·
`{success:false, error:'bank_unavailable'}` (SQL not deployed).
If the HTTP call is lost after the RPC, the next cron run finishes the confirmation.

### 3.3 `{action:'process', fio_id}` — process one movement now (after `admin_fio_reopen_transaction` or a plain RPC pair)
→ `{success:true, result:{…as above…}}` · `{success:false, error:'not_found'|'not_pending'|'busy'}`.

### 3.4 `{action:'suggest', fio_id, limit?}` — candidates for an unmatched incoming movement
Never confirms anything. Candidates = everything that waits for a bank payment of **exactly the same
amount** (no fuzzy amounts), ranked by similarity. `limit` default 8.
→ `{success:true, movement:{fio_id, amount, vs, counter_name, counter_account, message, tx_date},
candidates:[Candidate…]}`

```
Candidate = {
  target_type: 'booking'|'surcharge'|'order'|'request',   // pass to pair
  target_id:   uuid,                                       // pass to pair
  kind:  'booking'|'gear'|'surcharge'|'booking_change'|'voucher'|'shop_order',
  label: 'Rezervace #ABCD1234' | 'Doplatek rezervace #ABCD1234' | 'Úprava rezervace #ABCD1234'
         | 'Dárkový poukaz MG-…' | 'Objednávka MG-…',
  number: 'ABCD1234' | 'MG-2026-0012',
  booking_id: uuid|null, order_id: uuid|null, request_id: uuid|null,
  amount: number, vs: string|null,
  customer_name: string|null, customer_email: string|null,
  state: 'waiting' | 'expired' | 'cancelled',   // expired = request after its limit; cancelled = auto-cancelled QR booking (late payment)
  created_at: iso, expires_at: iso|null,
  score: 0–100, confidence: 'high'|'medium'|'low',
  reasons: [ 'Stejná částka 1 500,00 Kč', 'Jméno plátce „NOVAK JAN“ odpovídá zákazníkovi Jan Novák',
             'VS se liší v jedné číslici (10000128 × 10000123)', 'Zpráva obsahuje číslo rezervace', … ]
}
```
`confidence`: `high` ≥ 60, `medium` ≥ 30, `low` = only the amount matches. Sorted by `score` desc, then
newest first. An empty list is a normal answer.

### 3.5 `{action:'waiting'}` — everything the machine is waiting for (block „Čekající platby“)
→ `{success:true, items:[Candidate without score/confidence/reasons]}` — unpaid QR bookings and gear
rentals, booking surcharges due (Velín), pending web edit surcharges, unpaid voucher / shop orders with a
bank request (pending, or expired within 60 days).

### 3.6 `{action:'set_marker', date:'YYYY-MM-DD'}` (or `{id:<fio movement id>}`) — superadmin only
Moves the bank's „last download“ marker (first start with a new token). → `{success:true}` ·
`forbidden` · `rate_limited` · `fio_http_<n>` · `missing_fio_token`.

---

## 4. Web — what the pages send and get

All answers are JSON. „Bank details“ block returned by every QR answer:

```
vs: '10000123', amount: 1500.00, currency: 'czk',
account: '2303580494/2010', iban: 'CZ8320100000002303580494', bank: 'Fio banka',
spd: 'SPD*1.0*ACC:…*AM:1500.00*CC:CZK*X-VS:10000123*MSG:…',
qr_url: 'https://api.qrserver.com/v1/create-qr-code/?size=280x280&data=<urlencoded spd>',
expires_at: '2026-12-01T10:00:00+00:00' | null
```
Account, IBAN and bank always come from `app_settings.company_info` (never hard-coded on the page).

### 4.1 Reservation edit — surcharge by QR  **[EDGE][SQL]**

`POST /functions/v1/process-payment` with the customer's session JWT — the same body as the card payment
plus one field:

```
{ type:'extension', mode:'checkout', pay_method:'bank', booking_id, amount, change, locale?, success_url?, cancel_url? }
```
All existing validations run and answer with the existing codes (401 `auth_required`, 403 `forbidden`,
409 `stale_booking`, 409 `<dry-run code>` / `change_not_applicable`, 400 `amount_mismatch`,
409 `payment_in_progress`, …). No card minimum: 1–15 Kč is paid exactly. Surcharge ≤ 1 Kč is waived
exactly as today (same answer as the card path: `{success:true, free:true, waived:true, …}`).

Success (HTTP 200):
```
{ success:true, pay_method:'bank', status:'pending', reused:false|true,
  request_id, booking_id, booking_number:'ABCD1234', hold_minutes:60,
  …bank details…, deadline_text:'Zaplaťte do 14:35 …' (customer language) }
```
No `checkout_url`. The same data go to the customer by e-mail (not when `reused`).
New errors: 503 `{success:false, code:'bank_unavailable'}` (SQL not deployed / request could not be
created — offer the card) · 400 `{code:'bank_not_allowed'}` (`pay_method:'bank'` outside `mode:'checkout'`).

While waiting the booking is unchanged; the new dates are not blocked. The request is valid 60 minutes.
Starting a card payment for the same booking cancels the pending request.
State for the page: `get_bank_payment_request(p_booking_id)` (poll), QR data after a reload: §4.4,
cancel: `cancel_bank_payment_request(p_request_id)`.
Final states: `paid` (change written; the usual „rezervace upravena“ e-mail arrives) · `failed` (+`reason`;
booking unchanged, staff return the money) · `expired` · `cancelled`.

### 4.2 Gift voucher by QR  **[EDGE][SQL]**

`POST /functions/v1/process-payment` (anon key) — today's body plus `pay_method:'bank'`:
```
{ type:'shop', source:'web', mode:'checkout', pay_method:'bank', voucher_amount, is_print, codes?, amount,
  customer_email, customer_name, customer_phone?, shipping_address?, billing_address?, customer_company?,
  customer_ico?, customer_dic?, locale?, origin? }
```
Success (HTTP 200):
```
{ success:true, pay_method:'bank', status:'pending', order_id, order_number, request_id, hold_days:7,
  …bank details…, invoice_number:'ZF-2026-0123'|null,
  confirm_url:'<origin>/potvrzeni?order_id=<id>&flow=qr[&lang=…]', deadline_text }
```
Errors as today (409 discount code `{error, code, discount_code}`, 503 `validation_unavailable`,
400 `below_minimum`, 500 order creation) + 503 `{success:false, code:'bank_unavailable'}` (nothing created).
Order: `shop_orders.status='new'`, `payment_status='pending'`, `payment_method='bank_transfer'`. No voucher
exists until the money arrives; then the page's existing poll (`get_web_shop_order_confirmation`) flips to
paid and the voucher e-mail goes out. After 7 days the request shows `expired`; a later payment is still
confirmed. Discount codes are priced at order time and honoured.

### 4.3 Gear-only rental / motorcycle booking by QR — existing endpoint  **[EDGE]**

`POST /functions/v1/qr-payment {booking_id, locale}` (anon key) → as today
`{success, vs, amount, account, iban, bank, spd, qr_url, booking_number, invoice_number, due_hours:4}`
plus new `expires_at` (ISO; 4 h from the first QR choice — null until the SQL is deployed) and
`booking_kind:'moto'|'gear'`. Errors unchanged (`missing_booking_id`, `not_found`, `not_web_booking`,
`already_paid`). A repeated call returns the same VS and sends nothing.

### 4.4 QR data of an existing request (after reload / other device)  **[EDGE][SQL]**

`POST /functions/v1/qr-payment {action:'request', request_id | order_id | booking_id, locale?}`
(by `booking_id`: customer JWT of the owner in `Authorization`; otherwise the anon key is enough).
→ `{success:true, status:'none'}` or
`{success:true, request_id, kind, status, booking_id, order_id, change_kind, reason, paid_at, created_at,
  …bank details…, deadline_text}`; errors 401 `login_required`, 400 `missing_identifier`,
503 `bank_unavailable`.

`POST /functions/v1/qr-payment {action:'request_cancel', request_id}` (customer JWT) → `{success:true}` ·
`not_found` · `forbidden` · `wrong_status` — same as the RPC, for pages that prefer one endpoint.

---

## 5. Time limits

| What | Limit | On expiry |
|---|---|---|
| QR booking / gear rental | 4 h from the first QR choice (`bookings.qr_requested_at`) | booking cancelled + cancellation e-mail; a later payment revives it automatically if still free |
| Web edit surcharge | 60 min (`bank_payment_requests.expires_at`) | request `expired`, booking untouched; a later payment → „Ke kontrole“ |
| Voucher order | 7 days | request `expired`, order stays unpaid; a later payment is confirmed normally |
| Bank sync | every minute | — |

## 6. Not part of this package
QR at e-shop checkout (goods) — later step (matching of e-shop transfers by the VS of the advance invoice
is included). Automatic refunds from Velín — no (staff return money by hand).
