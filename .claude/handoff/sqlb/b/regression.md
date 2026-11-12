# Group b (ride recording) — live regression check, 2026-11-12

Live reference: rig database `base` = snapshot origin/supabase-live-snapshot e5d5b0f7 (2026-11-12). The public schema of that snapshot is byte-identical to the previous snapshot 1e7cf403 (2026-11-06); the drafts were last verified on the 2026-11-05 live state.

## Step 1 — did live change under the drafts?
For every existing object the bundle replaces, the live body (`defn.sh base <fn>`) was compared (comments and whitespace normalised) with the body in the newest repo migration that defines it:

| Object | Newest defining migration | Live body equal to it? |
|---|---|---|
| _ride_finalize | 20261015_user_rides_finalize_no_gap_km.sql | identical |
| _ride_json | 20260921g_user_rides_real_track.sql | identical |
| _ride_stats | 20261015b_user_rides_stats_jump.sql | identical |
| _ride_track_cap | 20260922b_user_rides_gap_threshold.sql | identical |
| admin_booking_live_ride | 20260921g_user_rides_real_track.sql | identical |
| append_ride_track | 20260922b_user_rides_gap_threshold.sql | identical |
| close_stale_user_rides | 20260922b_user_rides_gap_threshold.sql | identical |
| finish_user_ride | 20260922b_user_rides_gap_threshold.sql | identical |
| get_public_rides | 20260916d_user_rides_rpc.sql | identical |
| start_user_ride | 20260922b_user_rides_gap_threshold.sql | identical |

None of the gear (20261022*/20261023*), refund (20261023e_*), storno-hotfix or kiosk migrations touches these functions, and there is no dashboard drift. The drafts were written after 2026-10-15, so their starting point is today's live body. No rebase was needed. None of the live bodies has CRLF line endings.

The bundle does not re-create any trigger, policy, view or existing index or constraint. The only trigger on user_rides (trg_user_rides_updated -> set_updated_at) is not touched. The 15 new function names did not exist live before (sig.sh base). The feature flag ride_autopause does not exist live (REST read of feature_flags: 12 rows, none of them is ride_autopause).

## Step 2 — live vs final, object by object (diff --strip-trailing-cr, lines removed / added)
| Object | -/+ | Verdict |
|---|---|---|
| get_public_rides | 2/3 | Intended: only closed rides (`and not r.is_recording`); also strips trip_id, last_fix_at, pause_aware and is_recording. Signature, ACL, limit and offset logic are unchanged. |
| _ride_json | 0/3 | Intended: adds pause_sec, pause_aware, stats_v2, trip_id, trip_name and stages. Every old key is kept. |
| admin_booking_live_ride | 6/10 | Intended: adds is_standing, pause_aware and pause_sec, and adds a jsonb_typeof guard on the last point's coordinates. The removed lines are 3 comments plus the 3 rewritten lines. Guard, keys and the 1200-point preview are unchanged. |
| finish_user_ride | 17/20 | Intended: the last batch goes through _ride_append_core, _ride_reopen or _ride_append_late. The end is capped by _ride_booking_end (return or kiosk parking) instead of returned_at only. The ride is closed through _ride_close(...,'user'). Rename and response keys are kept, and an already closed ride still returns the already_finished answer. |
| start_user_ride | 19/44 | Intended: rides of gear-only bookings are refused with booking_inactive (a code 4.1.3 already treats as "do not record"). Resume rules now depend on booking/own ride. Date pairing only with a running moto booking. Reopen after kiosk parking. Signature, keys, P0 point, motorcycle name and insert are unchanged. |
| close_stale_user_rides (+comment) | 15/31 | Intended: new closing rules (moto booking only by its end, pause-aware own trip 72 h / 30 d, legacy 3 h / 36 h unchanged), closes via _ride_close(...,'cron'). The 500-row limit, the per-ride exception handler and the return shape are kept. The cron job is not touched. |
| append_ride_track | 102/18 | Intended rewrite: the body moved into _ride_append_core (b03). Every live behaviour is still there: auth check, points_required, FOR UPDATE ownership lock, ride_finished for a closed ride, the stale-batch filter and the fix-time clamp. The error codes are unchanged; `reason` and `reopened` are only additional keys. p_max_speed_kmh is accepted and ignored on purpose (the maximum is computed from the points). |
| _ride_finalize | 100/2 | Intended rewrite: delegates to _ride_close(id, end, NULL, false). Checked in _ride_close: already_finished answer, under 1 km -> delete + discarded, _ride_track_km fallback, avg cap 200.1, Prague date name, start/end points in user_ride_points, same response keys. admin_finish_user_ride (live, unchanged) keeps working through it. |
| _ride_stats | 109/8 | Intended rewrite: a wrapper over _ride_stats_v2 with the same keys. Now STABLE SECURITY DEFINER (needed to call the internal v2; pure computation, no table access). ACL unchanged (authenticated, postgres, service_role). |
| _ride_track_cap | 28/54 | Intended rewrite: distance-based thinning, same signature and default 4000, ACL unchanged, sql -> plpgsql, still IMMUTABLE. |

Signature check (`proname(args) -> result` for every public function named like ride or user_trip): before 21 lines, after 36 lines. The diff has 0 removed and 15 added lines, with no overloads. The public RPCs called by app 4.1.3 (start_user_ride, append_ride_track, finish_user_ride, get_my_rides, get_booking_rides, create_manual_ride, update_user_ride, delete_user_ride, save_ride_point, delete_ride_point) keep their signatures. The new public RPCs (start_user_trip, start_user_trip_from, set_user_rides_trip) have the same ACL as their live siblings: authenticated + service_role, no anon and no PUBLIC. The internal helpers have postgres + service_role, like the live _ride_finalize.

Full function diff against live: /tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/sqlb/b/fndiff_base_vs_bundle.txt

## Changes against the drafts
- The header of every file now carries the owner request (2026-10-22) and the new file names (03c -> b05, 06 -> b08). The only body change is one comment inside _ride_close.
- b06: the header states that the cron job is not touched.
- b08 (backfill) was rewritten for bounded work. The same CTE now runs in a temporary function (pg_temp) and is applied in batches of 200 rides ordered by id, for at most about 45 s, with `FOR UPDATE SKIP LOCKED`. A batch that errors is retried ride by ride: a broken ride is skipped with a WARNING, and if more than 10 rides fail and every ride tried failed, the file raises an exception, because that points to a programming error. Rides left over produce a WARNING telling to re-run the file by hand. The results are identical to the draft: 337/337 tests pass and all 16 stats vectors are equal.
