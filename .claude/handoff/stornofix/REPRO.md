# Storno / refund reproduction on LIVE code (main 9299a38a), 2026-10-22

Scope: edge functions `send-cancellation-email` (SCE), `process-refund` (PR), `webhook-receiver` (WH) exactly as on
`origin/main` 9299a38a (identical to `paydec/vrf/main/supabase/functions`, verified with `diff -rq`). The live DB schema
comes from `origin/supabase-live-snapshot` df555c93 (2026-10-22 08:35). Nothing was written to the live DB and no live API
was called.

## 0. Bottom line

1. **The reported trigger bug is real in the code, but whether it is live depends on one DB setting that nobody has
   verified.** `notify_booking_cancelled_email()` builds its URL from `current_setting('supabase.url', true)` and its key from
   `current_setting('supabase.service_role_key', true)`. When that GUC is unset, `v_url || '/functions/v1/…'` is NULL,
   so `net.http_post` raises (pg_net's `net.http_request_queue.url` is NOT NULL and `_encode_url_with_params_array` is strict; this is from the pg_net source, because the snapshot does not contain the `net` schema). The function then hits `EXCEPTION WHEN OTHERS`,
   which makes the trigger a no-op. The repo's own analysis (STATE_4 §LEGACY EMAIL triggery and STATE_6 2026-06-04) says
   this GUC "usually isn't set on managed Supabase" and calls the trigger "de facto inactive". Several other functions were
   rewritten to read `app_settings` for exactly this reason. Neither the snapshot (`roles.sql` has no
   `supabase.*` setting) nor any migration sets it, but a database-level `ALTER DATABASE … SET` would not show up in either
   place. The read-only check in §5 settles the question.
   - **If the GUC is set (trigger live)**, Velín stornos do not honour the admin's chosen amount. 50 % becomes 100 % at
     7 days or more before start. "Bez vratky" (0 %) becomes 100 % at 7 days or more, or 50 % at 2–7 days. 100 % can end
     up as 50 % at 2–7 days. Velín bulk cancel and the AI-copilot status change refund by the storno table. QR/transfer
     bookings get a credit note and, with Fio configured, a Fio payment order. Customer self-cancellations stay correct
     except for moved bookings (the move cap is ignored) and the 168 h / 48 h second boundary.
   - **If the GUC is unset**, none of the above happens. Section 3 has the full results.
2. **Three over-refund mechanisms reproduce on live code without the trigger.** All of them come from the
   "second dispatch is not exactly-once" design.
   - **(P) Pending Stripe refund.** This happens when the Stripe balance is too low. Velín partial storno 50 % ends up as
     100 %.
   - **(W) `charge.refunded` processed more than 30 minutes after the storno.** This covers a Stripe retry or a dashboard
     "resend", or any later refund on the same charge. A 50 % storno, from Velín or from a customer self-cancel at 2–7 days,
     ends up as 100 %. A manual 500 Kč refund in the Stripe dashboard adds another automatic 1000 Kč.
   - **(K) process-refund dies between `refunds.create` and its status write.** A 50 % storno ends up as 100 %.

## 1. Every path that cancels a booking or refunds a cancellation (main)

| Path | Status change | Who calls process-refund (amount) | Who calls SCE (refund fields?) | Notes |
|---|---|---|---|---|
| Velín BookingDetail "Zrušit" / Bookings list → `cancelBookingFromVelin` (`velin/src/pages/booking/bookingMessageHelpers.js:51`) | PostgREST UPDATE `status=cancelled`, `payment_status=refund_pending` unless 0 % (`:90`), committed immediately | Velín: `process-refund {reason:'cancellation'}` without amount for 100 %, `amount` for partial, **not called** for 0 % (`:112`), awaited (PR includes the PDF render) | Velín, after PR returns: SCE with `refund_amount` + `refund_percent` (0 for "bez vratky") (`:128`) | SCE → PR again with the same amount (PR "idempotent"). **Trigger (if GUC) fires on the UPDATE commit, roughly 0.1–1 s later, and reaches the claim first for 50 %/100 % because Velín's SCE comes only after its PR returns, an estimated 2–5 s including the PDFShift render.** For 0 % the two SCE calls race. |
| Velín BookingDetail "Potvrdit vrácení" → `confirmCancelledRefund` (`BookingDetail.jsx:414`) | none (already cancelled) → no trigger | Velín: PR `amount` (partial) or without amount (≥ total); skipped when a CN for exactly that amount exists | SCE with `skip_refund:true, force:true` (no refund, bypasses the claim) | Adjacent: on a `partial_refund` booking a "100 %" confirm is a silent no-op (PR without amount → already_refunded). That is harness test V1, unrelated to the trigger. |
| Velín bulk "Zrušit" (`BookingsBulkActionsModal.jsx:43`), AI copilot `update_booking_status` (`ai-copilot/tools-write-core.ts:26`) | plain UPDATE to `cancelled` (payment untouched) | nobody | nobody | No refund and no e-mail by design, **unless the trigger is live**. Then the storno table is applied (row B-bulk-10d-T). |
| Customer app (`reservation_provider.dart:330`, both trees incl. iOS 4.1.3) and web (`pages-upravit-rezervaci.js` `_submitCancel` / `_cancelPending`) → RPC `cancel_booking_tracked` | in the RPC: UPDATE (payment unchanged) + INSERT `booking_cancellations` | SCE (from the RPC dispatch) → `process-refund {amount: refund_amount, reason:'cancellation'}` | **The RPC itself**: `net.http_post` SCE with `refund_amount` + `refund_percent` (pct `>= 168 h → 100`, `>= 48 h → 50`, else 0, `LEAST(_storno_cap_after_move)`), URL/key from `app_settings` | This is exactly who refunds a self-cancellation today: the RPC's pg_net POST to SCE, then SCE calls PR. Neither app nor web calls SCE or PR for cancellations. `EmailService.sendCancellationEmail` in the app is dead code and would get 403 `trusted_caller_only`. If the GUC is set, the trigger's POST is queued first, in the same transaction, without refund fields. Both requests leave in the same pg_net batch after commit and race for `claim_email_send`. The trigger request does one extra DB round trip (profile lookup, SCE:166-178) before claiming, so the RPC request usually but not always wins. |
| `auto_cancel_expired_pending` (cron), `cancel_pending_web_booking`, Velín `bookingsAutoFix` | UPDATE of `pending`+`unpaid` only | nobody (unpaid) | cron: SCE for app bookings; others: nobody | No money involved. If the trigger is live it only adds or races a mail. |
| Stripe portal/dashboard refund → WH `charge.refunded` (`webhook-receiver/index.ts:686-870`) | external full refund on a live booking: WH UPDATE `status=cancelled` (would fire the trigger, which then computes `refund_amount` from the table, while PR sees `refunded` and does nothing) | WH: PR **without amount** (`:825`), which is the idempotent / CN-recovery path | WH: SCE with `refund_amount = charge.amount_refunded` (**cumulative, from the event snapshot**) + `refund_percent`, whenever the booking is cancelled (`:840-866`) | "Internal" means *any* refund on the charge carries `mg_source` (`:773`). After the 30-min claim window, the WH's SCE wins the claim again and calls PR with `amount = cumulative`. On `partial_refund` that is `wantsNewPartial`, and a fresh-CN dedup only matches the same total within 15 min, so a NEW refund is issued. That is mechanism (W). |
| Kiosk (motogo-box), other cron jobs | none of them cancel bookings or call PR/SCE | – | – | `kiosk_process_returns` completes bookings and never cancels them. |

`claim_email_send(booking,'booking_cancelled',30)` is the only serialisation between dispatches, and it decides **who
computes the money**. The first SCE inside 30 minutes wins and every later one returns `skipped:'claim_held'` before
touching money. `force:true` (Velín confirm) bypasses the claim. PR idempotency is not exactly-once:

- PR goes into the already-refunded path only when `payment_status='refunded'`, or `'partial_refund'` without amount (`:1017-1041`).
- With an amount on `partial_refund`, PR dedups only against a credit note of the **same total** issued within 15 min (`:1046-1075`).
- `refund_pending`, which Velín sets before the refund and PR sets for Stripe `pending`, passes the gate (`:1081`).
- The Stripe idempotency key is `refund:<booking>:<effective>:<refundable>` (`:1327`), and `refundable` counts succeeded and pending refunds (`:1222`). Any dispatch that runs after the first refund exists therefore gets a new key and creates a real second refund. When `effective == refundable`, the amount is omitted, which means "refund the rest" (`:1305`).

## 2. Method

- Harness `paydec/vrf/harness.ts` loads the real handlers from main. It uses a fake Stripe (idempotency keys, pending
  refunds, `charge.refunded` events) and an in-memory supabase-js with the live `claim_email_send` semantics, including
  a 30-min window controlled by a virtual clock in `repro.ts`, and the `_cap_refund_to_paid` BEFORE INSERT on invoices.
- `stornofix/repro/repro.ts` contains the scenario matrix. `keys.ts` prints the Stripe create calls and idempotency keys.
  The raw output is in `run_main.log` and `results.json`.
- Run:
  `SP=<scratchpad>; DENO_DIR=$SP/denocache FN_DIR=$SP/paydec/vrf/main/supabase/functions $SP/denobin/deno run --no-check -A --import-map=$SP/paydec/vrf/import_map.json $SP/stornofix/repro/repro.ts`
- Every scenario uses a card booking, one PaymentIntent and 3000 Kč total. "refunded" is the sum of all Stripe refunds on
  the PI, including dashboard refunds. "trigger" means the GUC is set and the trigger's SCE request is sent.
  "before/after/concurrent" describes where the trigger SCE runs relative to Velín's own PR.

## 3. Results (real refunded Kč on main)

### 3.1 Velín storno (`cancelBookingFromVelin`)

| start | admin choice | GUC unset (no trigger) | trigger after Velín PR | trigger before Velín PR | trigger concurrent | note |
|---|---|---|---|---|---|---|
| +10 d | 100 % (3000) | 3000 OK | 3000 | 3000 | 3000 | |
| +10 d | 50 % (1500) | 1500 OK | **3000 (+1500)** | **3000 (+1500)** | **3000 (+1500)** | deterministic once the trigger fires |
| +10 d | 0 % | 0 OK | **3000 (+3000)** | **3000 (+3000)** | **3000 (+3000)** | 0 only if Velín's SCE claims first (row V-10d-0%-b) |
| +4 d | 100 % (3000) | 3000 OK | 3000 | **1500 (−1500)** | 3000 | trigger's 50 % lands first, then Velín's PR without amount sees `partial_refund` and returns already_refunded |
| +4 d | 50 % (1500) | 1500 OK | 1500 | 1500 | **3000 (+1500)** | same amount but overlapping, so a new idempotency key and a 2nd refund (row V-4d-50%-overlap reproduces it deterministically) |
| +4 d | 0 % | 0 OK | **1500 (+1500)** | **1500 (+1500)** | **1500 (+1500)** | 0 only if Velín's SCE claims first |
| +1 d | 100 / 50 / 0 % | OK | OK | OK | OK | trigger computes 0 %, so it is harmless |

Other Velín-side paths:

- Velín bulk / AI copilot cancel of a paid booking at +10 d: 0 without the trigger, **3000 with it** (row B-bulk-10d-T).
- QR-paid booking, Velín 0 %, trigger wins: a **manual credit note of 3000** and `refund_pending`. With
  `FIO_PAYMENT_TOKEN` and a Fio company account, that also creates a real Fio payment order (row Q-Velín-0%-qr-T).

### 3.2 Customer self-cancel (`cancel_booking_tracked`)

| case | RPC computes | GUC unset | trigger, RPC wins claim | trigger, trigger wins claim | concurrent |
|---|---|---|---|---|---|
| +10 d | 100 % = 3000 | 3000 OK | 3000 | 3000 | 3000 |
| +4 d | 50 % = 1500 | 1500 OK | 1500 | 1500 | 1500 |
| +1 d | 0 % | 0 OK | 0 | 0 | 0 |
| +10 d, booking moved (cap 50 %) | 50 % = 1500 | 1500 OK | 1500 | **3000 (+1500)** | 1500 |
| 168 h + 0.4 s, pg_net 0.6 s later | 100 % = 3000 | 3000 OK | 3000 | **1500 (−1500)** | – |

Today's self-cancellations are correct whenever the RPC dispatch is the one that wins the claim, which is always the
case when the GUC is unset.

### 3.3 Exactly-once failures that do NOT need the trigger (live today, whatever the GUC)

| id | scenario | expected | refunded | mechanism |
|---|---|---|---|---|
| P-Velín-50% | Stripe refund `pending` (low balance), Velín 50 %, Velín's SCE runs before the WH has processed `charge.refunded` | 1500 | **3000** | PR #1 refunds 1500 (pending), so `payment_status='refund_pending'` (`PR:1357`). Velín's SCE then calls PR(1500). That call passes the gate (`:1081`) with refundable = 3000 − 1500 pending, so the key is `…:150000:150000` instead of `…:150000:300000`. Result: a 2nd refund. |
| P-Velín-50%-whFirst | same, but the WH processes `charge.refunded` first | 1500 | 1500 | WH sets `partial_refund`, so PR goes to `wantsNewPartial` and the fresh CN −1500 dedups. Whether money is lost depends on timing. |
| P-Velín-100%, P-cust-10d, P-cust-4d | pending + full storno / customer self-cancel | ok | ok | Full: the 2nd PR has refundable 0, so no_op. It does set `refunded` while Stripe is still pending. Customer: only one PR dispatch; the attach loop uses `cancellation_retry`, which is recovery-only. |
| W-Velín-50% | Velín 50 %, then the same `charge.refunded` delivered again 40 min later | 1500 | **3000** | WH (`alreadyCancelled`) → SCE: the claim has expired and `refund_amount=1500` (cumulative). SCE → PR(1500) on `partial_refund` → `wantsNewPartial` with no CN in the last 15 min → new refund of the "rest" (key `…:150000:150000`). |
| W-cust-4d | customer self-cancel at +4 d (50 %), redelivered 40 min later | 1500 | **3000** | same as above |
| W-Velín-100% | Velín 100 %, redelivered | 3000 | 3000 | only a 2nd storno mail goes to the customer |
| W-dash-500 | Velín 50 %, 1 h later the owner refunds 500 Kč by hand in the Stripe dashboard | 2000 | **3000** | The new event counts as "internal" because of the earlier `mg_source` refund on the same charge. SCE gets `refund_amount=2000` (cumulative), so PR(2000) adds min(2000, 1000 left) = 1000. |
| K-Velín-50% | Velín 50 %, Velín's PR is killed after `refunds.create` but before the status write. Velín catches the invoke error and calls SCE immediately | 1500 | **3000** (CN 1500) | status is still `refund_pending`, so SCE → PR(1500) runs with refundable 1500 and a new key, creating a 2nd refund |

Stripe create log on main (`keys.ts`) for the trigger case (+10 d, 50 %), the pending case and the replay case. All three are identical:
`[{amount:150000, key:"refund:<id>:150000:300000", created re_1}, {amount:rest, key:"refund:<id>:150000:150000", created re_2}]`.

The earlier harness suite agrees with these results: c_trigger T1/T1b/T2 fail on main, T3 passes because the RPC wins the
claim, and d_more V1/CN1/R1 fail. The b/h multi-payment tests fail on main because main's PR is the single-PI version
from before #2212. They are not part of this bug.

## 4. Exact mechanism of the trigger bug (if the GUC is set)

1. Any `bookings.status → cancelled` fires `trg_notify_booking_cancelled_email` (AFTER UPDATE OF status, live schema line
   26650). `notify_booking_cancelled_email` (line 14166) skips only when `message_log` already has a sent `booking_cancelled`
   row. Otherwise it queues a pg_net POST to SCE with `{booking_id, cancellation_reason, cancelled_by_source, source}` and
   **no refund fields**. The request is sent after commit, typically within 0.1–1 s.
2. SCE (`index.ts:166-178`) looks up the e-mail, wins `claim_email_send` (`:198-218`) because it is first, and reads the
   booking. `wasPaid` is true for `paid` and `refund_pending` (`:275`). Because `refund_percent == null`, SCE recomputes it
   from the storno table (`:297-303`): strict `> 168 h` → 100, `> 48 h` → 50, else 0, with **no `_storno_cap_after_move`
   and no knowledge of the admin's choice**. It then calls `process-refund {amount: total*pct, reason:'cancellation'}` for
   real (`:315-321`).
3. The caller that knows the correct amount arrives later and gets `skipped:'claim_held'`. That caller is Velín's SCE, or
   the RPC's SCE if it loses the race. Its amount is never used for money, and for 0 % Velín never calls PR at all.
4. Velín's own PR call runs concurrently with the trigger's PR. PR's guards make the outcome depend on order:
   - `partial_refund` with amount: a new refund unless a CN of the *same* amount exists within 15 min. That produces 50 % → 100 %.
   - `partial_refund` without amount: no-op. That produces 100 % → 50 %.
   - Both seeing `refund_pending`: the idempotency key depends on `refundable`, so the 2nd dispatch creates a 2nd refund.

## 5. Decisive read-only checks (owner / with permission; nothing here writes)

```sql
-- A) Is the trigger able to dispatch at all?  (NULL/NULL = trigger is a no-op → §3.1/§3.2 trigger columns are NOT live)
select current_setting('supabase.url', true) as guc_url,
       current_setting('supabase.service_role_key', true) is not null as guc_key_set;
select coalesce(d.datname,'*') db, coalesce(r.rolname,'*') role, s.setconfig
  from pg_db_role_setting s left join pg_database d on d.oid = s.setdatabase left join pg_roles r on r.oid = s.setrole
 where array_to_string(s.setconfig, ',') ilike '%supabase.%';
-- B) Did a trigger-originated SCE ever compute money? (only the trigger sends a paid booking without refund_percent)
select created_at, request_data from debug_log
 where source = 'send-cancellation-email' and action = 'cancel_started'
   and (request_data->>'wasPaid')::boolean and request_data->'body_refund_percent' is null
 order by created_at desc limit 50;
-- C) Money check over all cancelled bookings: chosen/computed refund vs credit-noted refund
--    (credit notes from earlier edits (shortening / moto swap) also count, so inspect hits by hand)
select b.id, b.cancelled_at, b.cancelled_by_source, bc.refund_amount as chosen, coalesce(-sum(i.total),0) as credit_noted, b.payment_status
  from bookings b
  join lateral (select refund_amount from booking_cancellations c where c.booking_id = b.id order by c.created_at desc limit 1) bc on true
  left join invoices i on i.booking_id = b.id and i.type = 'credit_note' and i.status <> 'cancelled'
 where b.status = 'cancelled' and b.cancelled_at > now() - interval '180 days'
 group by b.id, b.cancelled_at, b.cancelled_by_source, bc.refund_amount, b.payment_status
having coalesce(-sum(i.total),0) <> coalesce(bc.refund_amount,0)
 order by b.cancelled_at desc;
```

## 6. Constraints for the fix (measured)

- `deno check` ERROR baselines on main: send-cancellation-email **1** (TS2454 `manualRefund` used before assigned, `:527`),
  process-refund 0, webhook-receiver 85, process-payment 49. Raw files: `repro/dcheck_main_*.txt`.
- Customers only reach refunds through `cancel_booking_tracked`, which is SQL and unchanged by an edge-only fix. iOS 4.1.3
  and Android 4.2.0 call PR only for `edit_shortening` / `moto_swap` (customer gate in PR:914-922). An edge-only fix
  therefore cannot change app behaviour, but it must keep SCE semantics for the RPC body
  (`refund_amount` + `refund_percent` → PR `cancellation`).
- Deploy window: the deploy-functions workflow deploys SCE, PR and WH separately. During the window, a new SCE can run
  against an old PR and the reverse. Any new body flag must therefore be ignored safely by the old counterpart. A fix that
  only stops SCE from computing money when `refund_percent` is missing (trigger and other "bare" callers) is safe in both
  directions. Exactly-once fixes in PR (P/W/K) change PR on its own.
- An optional SQL hardening, given as text only and not part of this hotfix, would drop `trg_notify_booking_cancelled_email`
  or limit it to unpaid bookings. Check A tells whether that changes anything live.
