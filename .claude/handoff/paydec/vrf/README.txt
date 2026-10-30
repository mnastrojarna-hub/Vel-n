verify:refunds — end-to-end refund harness (real process-refund, webhook-receiver, send-cancellation-email
handlers; fake Stripe world + in-memory supabase-js; import map swaps esm.sh modules for fakes/).

Run (branch):  DENO_DIR=<scratchpad>/denocache <scratchpad>/denobin/deno test --no-check -A --import-map=<vrf>/import_map.json <vrf>/t/
Run vs live/main code:      FN_DIR=<vrf>/main/supabase/functions  (git archive origin/main)
Deploy window (mixed):      WH_DIR= / PR_DIR= / SCE_DIR= <dir>  (override one function's version)
Prototype fixes:            FN_DIR=<vrf>/fixtry  (webhook skip_refund + cancellation lock/delta in process-refund)

t/b_storno_test.ts   pending refunds, multi-payment storno with webhook orderings, short remainder, live status, QR part
t/c_trigger_test.ts  DB trigger trg_notify_booking_cancelled_email (send-cancellation-email without refund fields)
t/d_more_test.ts     credit-note race, Velín confirmCancelledRefund, pending status, recovery for 2nd refund
t/e_wh_test.ts       charge.refunded before process-refund writes status (webhook safety-net mail refunds again)
t/f_deploy_test.ts   old/new versions side by side
t/g_paths_test.ts    bundled e-shop, duplicate payment, failed swap + storno, app shortening, replays after windows
t/h_concurrent_test.ts overlapping dispatches (2nd dispatch between main refund and remainder)
t/i_live_status_test.ts live booking marked 'refunded' → later storno returns nothing
