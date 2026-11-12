# Group a (payments) — live regression check

Live truth: database `base` of the sqlb rig = snapshot `origin/supabase-live-snapshot` e5d5b0f7 (2026-11-12 11:01 UTC).
Method: the seven final files were applied to `sqlb_a` (fresh copy of live). For each replaced object the live definition
(`defn.sh base <fn>`) and the new definition (`defn.sh sqlb_a <fn>`) were dumped with CR removed and diffed
(files in `objdiff/<fn>.live.sql`, `.new.sql`, `.diff`). Full function/view diff: `fndiff_final.txt`
(`FNDIFF_OPTS=--strip-trailing-cr fndiff.sh base sqlb_a`). Full schema signature diff: `sig_vs_live.txt`.

Line-ending note: live `restore_vouchers_on_cancel` (20 lines) and `apply_paid_gear_change` (9 lines) have CRLF bodies; the new
bodies are LF. Cosmetic only; the diffs below ignore CR.

## Replaced functions (CREATE OR REPLACE / DROP+CREATE of existing objects)

| Object | Diff vs live (+/−) | Every removed line explained by the purpose? | Verdict |
|---|---|---|---|
| `generate_final_invoice_on_complete()` (trigger fn of `trg_generate_final_invoice`) | +14 / −2 | Yes. The 2 removed lines are the `v_base_rental` expression and the `debug_log` item list, both re-emitted with `- v_rounding` / `'card_rounding'` added (D1). The live gear-only branch from `20261023db` (GEAR lines, `SET search_path`, no VRACENI code for gear) is fully present — the draft had already mirrored it; confirmed by diff and by test „KF výbavy“. Owner, ACL, SECURITY DEFINER, search_path identical. | OK — live body + D1 only |
| `auto_cancel_expired_pending()` | +15 / −5 | Yes. Only the WHERE clause and the reason CASE (D3: app-restored window, checkout grace). Mail loop identical to live. ACL (postgres, service_role) and empty search_path config identical to live. | OK |
| `restore_vouchers_on_cancel()` (trigger fn of `trg_restore_vouchers_on_cancel`) | +4 / −2 | Yes. The two voucher UPDATE WHERE clauses get `AND (booking_id = NEW.id OR booking_id IS NULL)` (D3). | OK |
| `split_booking_moto_swap(...)` | +91 / −10 | Yes. Removed lines: old 6-arg header, unlocked `SELECT`, REPLACE `total_price`/history/return, SPLIT history/INSERT/return — each re-emitted with rev.12 additions (`v_round`, `card_rounding`, `payment_ref`, `FOR UPDATE`). All rev.11 logic (admin/service_role exemption of `trailer_staffed_only` from 20260922a, licence, late pickup, loyalty, refund cap, refund dispatch, B mail) unchanged. Signature extended by three defaulted args; old 6-arg overload dropped (named calls keep resolving). ACL = live (authenticated, service_role). | OK |
| `apply_paid_gear_change(...)` | +90 / −6 | Yes. Live was a 6-line wrapper (`SELECT update_booking_gear(...)`); rev.2 keeps the same identity switch (`request.jwt.claim.sub`, `request.jwt.claims`) and the same `update_booking_gear(p_booking_id, p_sizes, false)` call, adds lock, payment_ref dedup, rounding and history. Old 2-arg overload dropped; ACL = live (service_role only). | OK |
| `update_booking_gear(...)` | +23 / −2 | Yes. Removed: `total_price = v_new_total` and the return `new_total` line, re-emitted with `+ v_round`; added GUC read block and `card_rounding` column/return key. Everything from live (free gear from rank 3, `_booking_extra_is_gear`, `own_gear` logic of 2026-10-05, refund after commit) unchanged. Signature and ACL unchanged. | OK |
| `trg_send_booking_modified_email()` | +27 / −20 | Yes. The 20 removed lines are the dedup block, re-emitted verbatim one indentation level deeper inside `IF NEW.total_price IS NOT DISTINCT FROM OLD.total_price THEN`. Rest (deferred surcharge, steps 1–3, outer EXCEPTION) identical. | OK |
| `get_web_booking_confirmation(text, uuid)` | +22 / −1 | Yes. Removed `RETURN jsonb_build_object(` → `RETURN v_extra || jsonb_build_object(`; added DECLAREs and the cancelled-booking block. 2026-10-11 access rules (`_web_booking_full_access`, `_web_booking_is_live`, docs masking) and `has_gate` unchanged. STABLE, SECURITY DEFINER, search_path `public, auth`, ACL identical. | OK |

## New objects (no live counterpart — checked that none existed live)
Functions `_protect_card_rounding`, `_reset_card_rounding_on_reprice`, `_customer_restore_check`, `_customer_restore_redeem`,
`customer_restore_booking`, `_customer_restore_guard`, `_guard_customer_booking_pricing`; triggers `trg_protect_card_rounding`,
`trg_reset_card_rounding_on_reprice`, `trg_a_customer_restore_guard`, `_trg_guard_customer_booking_pricing`; index
`uq_invoices_credit_note_refund`; columns `bookings.card_rounding`, `bookings.restored_by_source`, `bookings.restore_count`,
`shop_orders.card_rounding`. None of these names exists in `base` (`sig.sh base` grep: no hit). No existing trigger, policy,
index or constraint is dropped or re-created by group a.

## Trigger order on bookings (BEFORE, alphabetical) — checked against live trigger list
`_trg_guard_customer_booking_pricing` < `_trg_guard_customer_booking_status` < `trg_a_customer_restore_guard` < `trg_booking_*` <
`trg_check_*` < … < `trg_protect_booking_mileage` < `trg_protect_card_rounding` < `trg_protect_handover_columns` <
`trg_reset_card_rounding_on_reprice` < `trg_set_booking_branch` < `trg_track_booking_content_changes` <
`trg_validate_late_pickup_update` < `trg_zz_gear_booking_guard` < `trg_zzzz_booking_refund_pickup_time`. Matches the order the
headers rely on.

## Changes made to the drafts during this rebase (beyond renaming and Czech headers)
1. a02 `_customer_restore_check`: gear-only bookings (`booking_kind='gear'`, live since 20261023a — after the draft) return
   `not_restorable`; the price floor uses motorbike day prices and cannot validate gear prices.
2. a02 `_customer_restore_check`: `date_passed` carries `reason` `today`/`past` (the app on this branch maps `reason == 'today'`
   to `pdRestoreStartsToday`; the draft never sent it).
3. a03: the commented, disabled „S3b“ block removed (separate owner decision; not part of this migration).
4. a05: duplicate check now runs under `LOCK TABLE invoices IN SHARE MODE` and the CREATE INDEX is wrapped in an
   `EXCEPTION WHEN unique_violation` → WARNING, so the file can never fail on live data.
5. a06, a07: the feature-detection DO/EXECUTE wrappers replaced by plain statements (the function and all columns exist live).
6. a07: trigger function gets `REVOKE … FROM PUBLIC` (ACL = sibling `_guard_customer_booking_status`), and the rule was
   narrowed: date shifts / moto changes that do not add days, do not raise the list value (`_moto_dayprice_sum`) and do not add
   a trailer now pass. Reason: both app 4.1.3 (70a94933) and the app on this branch write such edits of PAID bookings by direct
   UPDATE (`reservation_edit_screen.dart`, branch `effDiff <= 0`) and then call `process-refund`; the draft would have silently
   dropped them. Money stays protected by `process-refund` (Stripe cap + price floor). Live motorcycles: all 27 have prices for all
   seven weekdays (anon REST read 2026-11-12), so the list-value check is meaningful on live data.
7. Comments: draft markers `20261016p4` renamed to `20261112a04` inside a01/a04 comments.
