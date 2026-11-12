# Groups c + d — live regression check (2026-11-12, snapshot e5d5b0f7, rig database `base`)

## Method
`sig.sh base` grep for every object name the drafts create or replace; `defn.sh base` for live bodies of
functions the new code calls; `pg_get_triggerdef` of all triggers on bookings / messages / message_threads.
Final files applied twice to `sqlb_c` (seeded with the 20 live loyalty_levels rows); `sig.sh` run1 = run2,
`datasig.sh` run1 = run2; `fndiff.sh base sqlb_c` shows only added functions.

## Objects, one by one
| Object | Live today | Draft action | Verdict |
|---|---|---|---|
| table `booking_rating_reviews` (+ PK, 2 FK, CHECK, policy, RLS, grants, publication member) | does not exist | CREATE TABLE IF NOT EXISTS … | new object, nothing to rebase |
| function `_booking_rating_reviews_stamp()` | does not exist | CREATE OR REPLACE | new |
| trigger `trg_booking_rating_reviews_stamp` | does not exist | DROP IF EXISTS + CREATE on the new table | new |
| function `_bookings_rating_guard()` | does not exist | CREATE OR REPLACE | new |
| trigger `trg_bookings_rating_guard` on bookings | does not exist | DROP IF EXISTS + CREATE (BEFORE UPDATE OF rating, rated_at) | new; no live trigger is touched |
| function `_messages_bump_thread()` | does not exist | CREATE OR REPLACE | new |
| trigger `trg_messages_bump_thread` on messages | does not exist | DROP IF EXISTS + CREATE (AFTER INSERT) | new; live `trg_bridge_admin_message` untouched |
| table data `loyalty_levels.color_hex` (d01) | 20 rows read via REST = exactly the old seed the draft expects (1 #9CA3AF … 20 #FFD700) | guarded UPDATE of 19 rows | guards match live 1:1; nothing live is overwritten |

No function, view, trigger or policy that exists live is replaced by groups c/d, so no draft body could
revert a live change (no rebase was needed).

## Interaction with live objects (read, not changed)
- `is_admin()` (live: `admin_users.id = auth.uid() AND active`), `auth.uid()` — called by the new code; unchanged.
- BEFORE triggers on bookings fire alphabetically; `trg_bookings_rating_guard` runs after
  `_trg_guard_customer_booking_status` and `bookings_updated_at`, before `trg_check_*`, `trg_protect_handover_columns`,
  `trg_track_booking_content_changes`, `trg_zz_gear_booking_guard`, `trg_zzzz_booking_refund_pickup_time`.
  None of them reads or writes `rating`/`rated_at` (checked in live bodies: `track_booking_content_changes`,
  `trg_send_booking_modified_email`, `_gear_booking_guard`); the guard only resets rating/rated_at to OLD.
- Live `update_test_booking_fields` (admin RPC) writes rating/rated_at — passes because `is_admin()`.
- `message_threads` has no triggers live; the bump UPDATE only fires realtime (table is a publication member per STATE_5).
- Customer UPDATE on message_threads: live has no customer UPDATE policy (confirmed: policies are admin ALL x2,
  customer SELECT x2, customer INSERT) — the reason for c03.

## Changes against the drafts (all intentional)
- c01: `REVOKE ALL … FROM PUBLIC, anon, authenticated` then `GRANT SELECT, INSERT, UPDATE, DELETE` to authenticated
  (draft revoked only PUBLIC/anon, so authenticated kept TRUNCATE/REFERENCES/TRIGGER from default privileges);
  `REVOKE ALL ON FUNCTION _booking_rating_reviews_stamp() FROM PUBLIC, anon, authenticated` like live sibling trigger
  functions (`_gear_booking_guard`, `_booking_refund_pickup_time`: acl postgres + service_role only).
- c02: same function REVOKE added. Logic unchanged.
- c03: bump target clamped to `LEAST(COALESCE(NEW.created_at, now()), now())` — the draft used the client-supplied
  `created_at`, so a customer could pin a thread to the top of Velín forever with a future `created_at`. NULL thread_id
  short-circuit added. Still forward-only, status untouched, exceptions → WARNING.
- d01: 19 single UPDATEs folded into one UPDATE … FROM (VALUES level, old, new) with the same per-row guard; the
  notice block compares with IS DISTINCT FROM (NULL-safe). Values identical to the draft.

## Signature diff base → after bundle (c01–c03 + d01), identical after second run
New: 5 columns, 4 constraints, 1 index, 1 policy, 1 publication member, 1 relation, RLS flag, 3 functions
(acl postgres + service_role), 2 comments, 3 triggers. Data: `loyalty_levels` hash changes (19 rows) only when d01 is applied.

## Contrast check for d01 (WCAG 2.x), who reads color_hex
Readers: app old look (`loyalty_ranks_screen.dart`, `loyalty_leaderboard_section.dart`, `profile_screen.dart`,
`core/widgets/logo_header.dart`), `loyalty_levelup_overlay.dart` (used by BOTH looks, unchanged in v2), v2 look
(`core/v2/rank/*` — maps any old or new value to the same v2.2 ramp via `resolveRankHex`, so v2 does not change).
Velín, web, kiosk, edge functions: no reader (grep `color_hex|colorHex`).
Old look text uses `_onColor(c) = luminance > 0.5 ? #0F1A14 : white` (unchanged on this branch and in 4.1.3) and
rank colour as text on dark (#1A2E22 / #0A1A10).
| lv | old | on-colour text | colour on #1A2E22 | new | on-colour text | colour on #1A2E22 |
|---|---|---|---|---|---|---|
| 1 | #9CA3AF | 2.54 | 5.67 | #A3B8A8 | **2.10** | 6.85 |
| 7 | #C0C0C0 | 9.80 | 7.92 | #929496 | 3.04 | 4.73 |
| 12 | #3B82F6 | 3.68 | 3.92 | #6EAFFF | **2.27** | 6.34 |
| 13 | #6366F1 | 4.47 | 3.22 | #00A1C7 | 3.03 | 4.75 |
| 15 | #A855F7 | 3.96 | 3.64 | #117897 | 5.05 | **2.85** |
| 16 | #D946EF | 3.46 | 4.17 | #165EEB | 5.48 | **2.63** |
| 17 | #EF4444 | 3.76 | 3.83 | #D42020 | 5.21 | **2.76** |
| 20 | #FFD700 | 12.71 | 10.27 | #FF8C1A | 2.33 (never drawn: level-up uses fixed legend colours, ranks list shows 🏅 for the current top rank) | 6.19 |
Full table: `contrast.py`. Without the `_onColor`/light-text fix the draft itself names as a precondition, the new
values make rank colour text on dark fall below 3:1 for ranks 15–17 (today ≥ 3.22) and the level-up button text
of rank 12 drop from 3.68 to 2.27. That fix is not on this branch (old look must stay unchanged) and not in 4.1.3.
Verdict: d01 is NOT placed in supabase/migrations; the tested final file is in `c/ready/`.
