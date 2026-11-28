# Fio bank / QR payment — current state (Part 1)

Read from the working tree of `/home/user/Vel-n` on 2026-11-27 ~21:00 UTC (branch with the unfinished
operator change; uncommitted files included). Database facts come from the schema dump taken the same day
(`scratchpad/operator/work/schema_public.sql`) and from the migrations. Web JS is minified to one line per
file, so positions there are given as function names (+ character offsets where useful).

**One-paragraph summary.** The whole incoming-payment pipeline exists and is deployed (edge `fio-sync`,
pg_cron every 5 minutes, table `fio_transactions`, automatic confirmation of a motorcycle / gear booking
and of a Velín-created surcharge, automatic refund by payment order). It is **dormant on live** as long as
`app_settings.company_info` still points to the old mBank account (operator inventory, Part 3.2) — the QR
codes then pay to mBank, which has no API. Only web bookings (motorcycle; technically also gear-only) can
be *offered* QR today, and only the motorcycle booking form shows the option. Vouchers, e-shop orders, the
web reservation edit and the gear-only page are card-only. Nothing in Velín shows bank movements;
exceptions reach staff only as e-mails to info@. A dead token is only visible as rows in `debug_log`.

---

## a) Web motorcycle booking paid by QR — end to end

| Step | What happens | Evidence |
|---|---|---|
| Offer | Step 2 of `/rezervace` renders a two-radio chooser „Platba online“ (default) / „Platba QR kódem / převodem“. Always offered — no condition on pickup time, amount or branch. | `MG._rezPayMethodHtml` in `motogo-web-php/js/pages-rezervace-scan.js` (offset ≈36 690); rendered from `js/pages-rezervace-steps.js` (≈41 970) and `pages-rezervace-scan.js` (≈19 230); keys whitelisted in `pages/rezervace.php:129-130`; texts `lang/cs.php:676-690` (+ `en,de,es,fr,nl,pl,uk.php`) |
| Booking | Created earlier, on step 1, by RPC `create_web_booking` → `bookings` row `pending` / `unpaid`, `booking_source='web'`. The row blocks the dates like any booking. | live schema `create_web_booking` (dump line 11708) |
| Choosing QR | Submit handler stores the choice (`set_web_booking_chosen_method`), then for QR calls `MG._rezStartQrPayment` → `POST /functions/v1/qr-payment {booking_id, locale}` with the anon key only. **The upsell e-shop items of step 2 are skipped in the QR branch** (the `create_web_shop_order` call sits after the early `return`). | `pages-rezervace-scan.js` ≈32 600–32 830 and ≈37 400 |
| Edge `qr-payment` | (1) RPC `set_booking_qr_payment`: VS = `nextval('booking_vs_seq')` (8 digits from 10000001), `pay_channel='qr'`, `payment_method='bank_transfer'`, suppresses the „unfinished booking“ mail; idempotent. (2) account/IBAN/bank from `company_info` through the new `_shared/company.ts` + `qr-payment/spd.ts` (operator change, already in the working tree). (3) SPD string `SPD*1.0*ACC:<IBAN>*AM:*CC:CZK*X-VS:*MSG:`; the QR picture is rendered by the third party `api.qrserver.com`. (4) advance invoice (ZF) through `generate-invoice` with the VS and „due in 4 hours“. (5) customer mail from template `booking_qr_payment` (fallback inline HTML, 8 languages) with the ZF attached. (6) ops mail to info@ „check the account and confirm in Velín“. A repeated anonymous call returns the same data silently (`quiet`). | `supabase/functions/qr-payment/index.ts:48-49,69,74-77,86,93-94,102-124,133-189,191-201,205`; `supabase/migrations/20260705_qr_bank_payment.sql`; `20260705_qr_payment_email_template.sql`; `supabase/config.toml:42-43` (`verify_jwt=false`) |
| Customer sees | QR box (amount, account, IBAN, bank, VS, 4-hour warning) with „Hotovo“ → `/rezervace?resume=<id>` = document step → `/potvrzeni?booking_id=…&flow=qrdocs`: „waiting for payment“ card, polls `get_web_booking_confirmation` 6 × 5 s and switches to the normal confirmation if paid meanwhile. | `MG._rezRenderQrScreen`, `MG._rezFinishDocs` in `pages-rezervace-scan.js`; `js/pages-potvrzeni.js` (offset ≈3 885); texts `lang/cs.php:1795-1802` |
| Waiting state | `bookings.status='pending'`, `payment_status='unpaid'`, `pay_channel='qr'`, `payment_vs` set. Velín booking detail shows a badge „QR/PŘEVOD — ČEKÁ · VS“. | `velin/src/pages/BookingDetail.jsx:756-760` |
| Hold / expiry | pg_cron `auto-cancel-pending-bookings` (every 2 min) → `auto_cancel_expired_pending()` cancels web bookings **4 hours after `created_at`** — not after the QR was chosen. A customer who chooses QR three hours after starting the booking has one hour, while web and mail promise four. The cancelled web booking gets **no e-mail** (web rows are skipped because they normally got the „unfinished booking“ mail — which the QR choice suppressed). | live `auto_cancel_expired_pending` (dump line 8601 ff.; source `20261112a02_customer_restore.sql`); `SUPABASE_BACKEND_STATE_5.md:421` |
| Confirmation | `fio-sync` (below) or the manual Velín button. | |
| After payment | Mail `booking_reserved` (documents complete) or `invoice_payment_receipt` (documents missing), ZF + DP generated with the real VS and payment date, in-app message, audit row, ops mail „✅ confirmed automatically“. Door codes etc. come from the usual DB triggers of `confirm_payment`. | `fio-sync/index.ts:315-427` |

**Which confirmation code runs.** All three paths call the same RPC `confirm_payment`
(atomic `UPDATE … WHERE payment_status <> 'paid'`, `was_already_paid`), but the steps around it exist in
**three separate copies**: Stripe webhook `confirmBookingPayment`
(`webhook-receiver/payment-confirmers.ts:85-339`), the Velín button `confirmManualPayment`
(`velin/src/pages/BookingDetail.jsx:554-657`, runs in the browser) and `fio-sync` inline
(`fio-sync/index.ts:315-427`, written as a 1:1 copy of the Velín button).

**Exceptions today**

| Case | Behaviour | Where |
|---|---|---|
| Lower amount | `amount_mismatch`, ops mail, nothing confirmed. A second partial payment is judged alone — partial payments are never added up. The customer is not told; the booking is cancelled after 4 h. | `fio-sync/index.ts:308-313` |
| Higher amount | confirmed, note „přeplatek“, ops mail asks staff to send the difference back by hand | `:424-427,469` |
| Wrong / missing VS | `no_match`; ops mail unless the amount is under 50 Kč and has no VS | `:282-291` |
| Foreign currency | `no_match` + ops mail | `:204-209` |
| Payment after the 4-hour cancellation | `needs_review` + ops mail; **no revive** (unlike the card path, where `confirm_payment` revives a cancelled booking if the bike is still free and refunds otherwise) | `:300-307`; card: `payment-confirmers.ts:160-175`, `webhook-receiver/late-payment.ts` |
| Second payment with the same VS | status `already_paid` — **silently**: no ops mail, no refund, visible only in the table | `:296-299` (booking), `:228-231` (surcharge) |
| Processing error | status `error` + `debug_log`; **never retried** (only `new` rows are processed) and **no mail** | `:428-436` |

**Idempotence.** `fio_transactions.fio_id` (Fio movement ID) is the primary key and rows are upserted with
`ignoreDuplicates`; every run re-scans all rows in status `new` (crash-safe); `confirm_payment` /
`confirm_booking_surcharge` refuse a second confirmation.

---

## b) Booking EDIT with a surcharge on the web

* Page `pages/upravit-rezervaci.php`, core `js/pages-upravit-rezervaci.js` (minified, 173 kB, patched from
  outside by `-guard.js`, `-swap.js`, `-gear.js`, `-gearbk*.js`, `-paid.js`, … — list in the PHP at
  lines 289-304). Only **paid** bookings can be edited (`apply_booking_changes` → `not_paid`).
* The price is computed by a server dry run (`apply_booking_changes`, `split_booking_moto_swap`,
  `update_booking_gear`). If money is due, the browser posts
  `process-payment {type:'extension', mode:'checkout', booking_id, amount, change, success_url, cancel_url}`
  from four places: core `_submitChange` (offset ≈88 300; extension, move, location, motorcycle change go
  through it), core `_submitExtend` (≈151 800, replaced by `-guard.js`), `-gear.js` (≈10 900) and
  `-swap.js` (≈20 000).
* `process-payment/index.ts` validates everything again (owner `:578-599`, stale base `:627-646`, dry run
  under the customer's JWT `:648-770`, trailer `:772-796`, amount `:889-893`), stores the change in the
  Stripe metadata (`chg`…`chg_8`, `srv`) and returns a Checkout URL. **The change is not written until the
  money arrives**: the webhook (`webhook-receiver/index.ts:93-158` `finishPaidChange`) or the return page
  (`action:'complete_extension'`) calls the shared `applyPaidExtension`
  (`_shared/extension-apply.ts:25`). If the change can no longer be written (bike taken meanwhile…),
  `_shared/paid-change-failure.ts` refunds the card automatically and mails staff.
* Card minimum: a surcharge of 1–15 Kč is charged as 15 Kč, up to 1 Kč is waived
  (`process-payment/index.ts:882-945`).

**The existing „surcharge“ matching in `fio-sync` is a different thing.** `bookings.mod_surcharge_due /
mod_surcharge_vs` (`20260727_booking_edit_surcharge_flow.sql`) were built for **Velín**: staff edit a paid
booking, the change is written **immediately**, the debt is stored, `qr-payment {surcharge:true}` (trusted
callers only, `qr-payment/index.ts:48-49`) mails a QR, the „booking modified“ mail is deferred until staff
click „Potvrdit doplatek“ (`BookingDetail.jsx:529-548` → RPC `confirm_booking_surcharge`) or `fio-sync`
matches the VS (`fio-sync/index.ts:220-264`). Nothing expires and nothing is rolled back if the customer
never pays. The web self-edit never sets these columns.

**Missing for a web customer to pay an edit by QR:** a place to keep the priced change while the money is
on its way (today it lives only in Stripe metadata), a VS for it, a „waiting for payment“ state the
customer can see and cancel, an expiry, matching in `fio-sync`, and a failure path for a change that can
no longer be written after the money arrived (the card path refunds through Stripe; a bank payment has no
such automatic path).

---

## c) Gift voucher purchase on the web

* `pages/poukazy-objednat.php` (inline script, lines 124-262) + `js/voucher-codes.js`. One form, one button
  „Pokračovat k platbě“ → `process-payment {type:'shop', source:'web', mode:'checkout', voucher_amount,
  is_print, codes, …}`. **Card only.**
* `handleWebShopCheckout` (`process-payment/payment-flows.ts:657-870`): price and discount codes from RPC
  `quote_web_voucher_order` (`20261127a3_…sql`, minimum 15 Kč after discount), inserts `shop_orders`
  (`status='new'`, `payment_status='pending'`, `payment_method='stripe'`) + items „Dárkový poukaz“
  (+ „Tisk a poštovné“ 180 Kč), creates the Stripe session, generates a ZF (`shop_proforma`) without mail.
  The voucher branch always creates its own order (an `order_id` from the client is routed to the product
  branch — security fix 2026-10-11).
* On payment the webhook calls `confirmShopPayment(orderId, …, method)`
  (`webhook-receiver/payment-confirmers.ts:443-610`): RPC `confirm_shop_payment` (atomic), DB trigger
  `trg_auto_process_voucher_order` creates the voucher codes (only while the order is `new`/`pending`),
  trigger `trg_shop_promo_usage_on_paid` records discount-code usage (**at payment time, no reservation of
  the code, no limit check**), FV for electronic vouchers, mail `voucher_purchased` with the voucher PDF/HTML.
  The function already takes a `method` argument — it can be called for a bank payment unchanged.
* Nothing ever cancels an unpaid shop order; abandoned card orders stay `new`/`pending` for ever.
* The live CMS text of the e-shop page already promises „QR code or bank transfer“ (operator inventory 3.2).

## d) Gear-only rental on the web

* `pages/pujceni-obleceni.php`, `js/gear-rental*.js`; texts `data/gear-rental-flow-texts.php` (cs) and
  `lang/v2/<lang>/gear-flow.php`.
* `create_web_gear_booking` (`20261127a2_…sql`) creates an ordinary booking: `booking_kind='gear'`,
  `moto_id` NULL, `booking_source='web'`, `pending`/`unpaid`; the pending row holds the stock.
  Payment: `G.pay` → `process-payment {type:'booking', source:'web', mode:'checkout'}`
  (`js/gear-rental-api.js`). **Card only on the page.**
* The server side of QR is already complete for it: `qr-payment` accepts any unpaid web booking,
  `generate-invoice` builds gear documents from `gear_lines`, `fio-sync` has the gear branch (document
  rule „identity + 18“, message in the customer's language: `fio-sync/index.ts:363-371,394-399`,
  `fio-sync/gear-msg.ts`), `auto_cancel_expired_pending` treats it like any web booking (4 h).
  Locker code / self-service gating happen after payment in the same triggers as for a card.
  What is missing is only the page: the chooser, the QR box and the „waiting“ view
  (`js/gear-rental-done.js` already has an „unpaid → summary + pay“ view and polls
  `get_web_gear_booking`).

## e) E-shop orders (goods)

`pages/checkout.php` + `js/checkout.js`: RPC `create_web_shop_order` (server prices) →
`process-payment {type:'shop', kind:'products', order_id}` → `handleWebProductCheckout`
(`payment-flows.ts:478-654`), ZF e-mailed to the customer, confirmation by the same `confirmShopPayment`.
Card only. The ZF carries a numeric VS (digits of its number, `generate-invoice/index.ts:797-802`), but
`fio-sync` only follows invoice VS that belong to a **booking** (`fio-sync/index.ts:266-280`), so a
transfer for an e-shop order ends as `no_match`. In Velín an order can be marked paid by a plain UPDATE
(`velin/src/pages/purchases/ShopOrderModals.jsx:211`, `ShopOrdersTab.jsx:63`) — that fires the DB triggers
but not the mail routine of `confirmShopPayment`. Whether the e-shop is visible on the web is a feature
flag (`eshop_visible_web`, `20261127b_eshop_visible_web.sql`).

---

## f) `fio-sync` internals

* **Trigger.** `20260829_fio_bank_sync.sql:88-101`: pg_cron job `fio-bank-sync` `*/5 * * * *` →
  `fio_sync_tick()` → `net.http_post` to `/functions/v1/fio-sync` with URL and key from `app_settings`
  (default pg_net timeout). Auth inside the function: service key, signed service-role JWT, the key from
  `app_settings`, or an admin JWT (`fio-sync/index.ts:116-136`) — so Velín can already call it.
* **One run** (`index.ts:138-190`): `GET https://fioapi.fio.cz/v1/rest/last/{FIO_API_TOKEN}/transactions.json`
  („since the last download“; Fio moves its marker itself) → upsert into `fio_transactions`
  (incoming → `new`, outgoing → `outgoing`) → process up to 50 rows in status `new`.
* **Stored per movement:** `fio_id, tx_date, amount, currency, vs, counter_account, counter_bank,
  counter_name, message, tx_type, status, booking_id, note, created_at, processed_at`. Not stored: KS/SS,
  bank name, comment, instruction ID, BIC — the raw answer is thrown away.
* **Statuses:** `new, outgoing, confirmed_booking, confirmed_surcharge, already_paid, no_match,
  amount_mismatch, needs_review, error`. Outgoing movements are only stored; they are not linked to
  `fio_payment_orders`.
* **Matching order:** `bookings.payment_vs` → `bookings.mod_surcharge_vs` → `invoices.variable_symbol`
  (advance/proforma of a booking). No shop orders. `bookings.payment_vs` / `mod_surcharge_vs` have no index.
* **Re-processing:** none. `no_match`, `amount_mismatch`, `needs_review`, `error` are final; staff confirm
  by hand in the booking detail and the movement keeps its status.
* **Errors:**
  * missing secret → one `debug_log` row `missing_fio_token` **on every run**, no mail (`:138-141`);
  * HTTP error from Fio → one row `fio_fetch_failed` **on every run**, no mail (`:150-154`). According to
    the bank's documentation HTTP **500** means „token does not exist or is inactive“, i.e. also an
    expired token;
  * HTTP 409 (two calls within 30 s on one token) → silently skipped (`:146-149`);
  * **movements can be lost**: Fio advances its marker when it answers. If the answer is not valid JSON
    (`resp.json().catch(() => null)` → treated as an empty statement, `:155-156`) or the insert fails
    (`:179-182`), those movements never come again through `last`. Nothing detects this.
  * two runs can overlap (the tick does not wait for the function); the second would re-read rows the first
    is still processing. With a 5-minute interval this needs a 5-minute run; no lock exists.
* **`debug_log` rows per run:** empty successful run **0**; 409 **0**; failing run **1** (every run);
  per confirmed payment 1–2 (+ rows written by `generate-invoice` / `send-booking-email` themselves).
* **Ops mails:** only per movement (confirmed / mismatch / unmatched). None per run, none for a dead token.
* **Token and the 30-second rule.** One GET per run. `process-refund` uses `FIO_PAYMENT_TOKEN`, falling
  back to `FIO_API_TOKEN` (`process-refund/index.ts:444`); if both use one token and the order lands within
  30 s of a sync, the import gets 409, waits 31 s and retries once (`:614-617`).
* **Refunds by payment order:** `tryFioRefund` (`process-refund/index.ts:514-657`; bank-code condition `:532`), table
  `fio_payment_orders` (`pending / submitted / failed`, UNIQUE `credit_note_id`); works only when
  `company_info.bank_account` has bank code 2010 and the incoming payment is found in `fio_transactions`.
* **RLS:** `fio_transactions` and `fio_payment_orders` have `FOR ALL USING (is_admin())` — an admin could
  update or delete rows directly; Velín does not use the tables at all.
* **Fio API facts** (documentation „API Bankovnictví“, version 16. 10. 2025, read on 2026-11-27): a token
  belongs to one account; validity is at most 180 days, with „automatic prolongation“ every login to
  internet banking / Smartbanking moves it to 180 days from that day; one call per token per 30 s for
  reading **or** writing, otherwise 409; there is **no endpoint that returns the token's validity**; the
  answer of every statement call contains the account's IBAN; `set-last-date` / `set-last-id` move the
  marker; `periods/{from}/{to}` reads a date range without moving it.

## g) Velín today

* No page or tab for bank movements, waiting QR payments or payment orders. `fio_transactions`,
  `fio_payment_orders` are referenced nowhere in `velin/src` (only the `fio_sent` alerts in
  `pages/booking/BookingModifyModal.jsx:387` and `GearModifyModal.jsx:96`).
* Manual confirmation lives in the booking detail: action „Potvrdit platbu“ / „Potvrdit doplatek“ →
  `pages/booking/PaymentConfirmModal.jsx` → `confirmManualPayment` / `confirmSurchargePayment`
  (`pages/BookingDetail.jsx:529-657`). Resending the QR mail: `pages/documents/ResendMailTab.jsx:151-165`.
* Finance: `pages/Finance.jsx` — tabs `Přehled, Faktury, Dobropisy, Dodací listy, Smlouvy, Účetnictví,
  Faktury přijaté, Platby, Pokladna, Sklad` (array `FINANCE_TABS`, `Finance.jsx:31`; lazy-loaded tab components from
  `pages/accounting/`). „Platby“ = payments **to suppliers** (`accounting/PaymentsTab.jsx`).
* Patterns to copy: list + filters + stat tiles `accounting/PaymentsTab.jsx`; list + detail modal +
  pagination + search `accounting/CreditNotesTab.jsx`; realtime + 60 s polling + acknowledge
  `hooks/useKioskAlerts.js`, `components/KioskAlertsBanner.jsx`; menu badge `components/Sidebar.jsx:35-74`
  with `badgeKey` in `lib/velinSections.js`; company data `lib/company.js` and
  `pages/government/CompanyTab.jsx` (operator change).
* Permissions: database access is `is_admin()` for every Velín account; the per-user restriction
  (`admin_users.permissions.sections`) only hides menu sections (`lib/velinSections.js`,
  `components/SectionGuard.jsx`). The Finance section is one unit.

## h) App

No bank / QR flow. The app only **displays** payment details of a reservation, including a VS and the
label „QR“ when `pay_channel='qr'`
(`Motogo-app-main/motogo-app-flutter/lib/features/reservations/widgets/res_payment_details_tab.dart:66,137,221`,
`…/v2/res_payment_details_v2.dart:69`; same files in the iOS tree). Nothing is to be designed there.

---

## Defects found on the way (all relevant once „everything can be paid by QR“)

1. QR hold counted from booking creation, not from the QR choice; expired QR booking gets no e-mail (a).
2. Duplicate payment is silent (a). 3. `error` rows are never retried and never reported (a, f).
4. A failed download can lose movements for good (f). 5. Dead / missing token is logged every run and
mailed never (f). 6. No lock against overlapping runs (f). 7. Web and e-mail texts say the payment is
confirmed „manually“ / „usually within 4 hours in working hours“ (`lang/cs.php:680,1800` + 7 languages);
the ops mail of `qr-payment` still tells staff to confirm by hand (`qr-payment/index.ts`, `opsEmailHtml`).
8. Upsell items of the booking form are dropped when QR is chosen (a). 9. Admins can edit bank movements
directly, without audit (f).
