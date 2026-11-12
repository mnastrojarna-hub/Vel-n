# Functional audit of app 4.2.0 against 4.1.3 — judge decisions

Date: 2026-11-12. Branch claude/moto-go-mobile-conversion-gqg5qo, HEAD 88c77d04 (the audited app code is unchanged since 20a4c358).
Base for both app trees: 70a94933 (app 4.1.3). Base for edge functions, Velín and the website: origin/main.

## How I decided

For every candidate that carries a risk, a proposed change or a question I read the code myself, at the base and at HEAD,
together with the documents it refers to (SUPABASE_BACKEND_STATE_6.md changelog, the ride spec, the payment design notes, the
new SQL files the app depends on). For the low-risk candidates that repeat a documented request (app-core-15, 16, 18,
app-pay-9, app-res-3, 4, app-rest-6, 12) I checked that the changelog entry and the code location exist and otherwise relied on
the area report. I ran two probes in the Android tree from a scratch test file, without changing the repository:

- app-routes-1: the 4.1.3 navigation call (push from Moje zážitky to a route detail) fails with Flutter's duplicate page key assertion.
- app-core-1: delivery to Jihlava, collection copied, collection changed to Brno. The delivery address and its fee changed to Brno too.

I did not run the full test suite and I did not edit any file in the repository. The probe files are in
/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/funcaudit/judge (probe_push_shell_test.dart, probe_addr_test.dart).

Rule for changes that are not in the Q1–Q7 list but are already in origin/main: I looked each one up in the changelog. All of
them (handover protocol only on the kiosk display, self-service sizes, documents gate, languages, App funnel, ride GPS fixes)
have a dated owner request there, the live backend or kiosk already depends on them, and I kept them.

## Result

80 candidates: 63 KEEP, 10 ADD_TEST, 1 REVERT, 6 ASK_OWNER.

ADD_TEST is used in two ways and the plan says which: "TEST only" (the code stays as it is) and "FIX + TEST" (I confirmed a
defect in a requested feature; the plan gives the fix and the test that proves it).

### Must be done before the release (confirmed defects)

1. **app-core-2 — the cache cleanup erases the new safeguards.** The cleanup that runs at every start and every time the app goes
   to the background deletes the "payment sent" marker, the queue of paid changes and the stored kill-switch value. The
   double-charge protection, the retry of a paid swap or edit and the switched-off look therefore do not survive a visit to the
   bank app. Several other safeguards (app-pay-2, app-pay-3, app-res-10) rely on these records.
2. **app-core-1 — delivery and collection cannot have two different addresses.** Proven by the probe; it affects both looks.
3. **app-flagoff-1 — the kill-switch cannot be pressed.** No migration creates the feature_flags row app_v2_ui and Velín can only
   switch rows that exist. The Velín text about iOS is out of date.
4. **app-res-8 — an SOS report from a place with weak GPS is sent without coordinates**, where 4.1.3 sent the last known position.
5. **app-res-12 — an edit that adds days but costs less is reported as saved although the new SQL guard kept the old booking.**
   No money leaves (process-refund caps the refund), but the customer is misinformed and part of the row is written.
6. **app-routes-3 — a second tap on Uložit after a partial photo upload stores the uploaded photos twice.**
7. **app-routes-2 — a rider who stands still for 20 seconds is told that the GPS signal is weak.**
8. **app-core-5 (SQL follow-up, not app code) — the push sent at the locker still says the protocol can be signed „v aplikaci
   nebo na displeji pobočky“**, but app 4.2.0 has no protocol screen. The text change proposed on 2026-10-10 was never committed.

### Tests to add (code unchanged)

- app-core-4: the Continue button of the booking form while the bike's occupancy is loading or failed.
- app-core-6: the self-service size rule (it can disable the Continue button).
- app-rest-11: system back in the registration form in the old look.

### One revert

- app-core-17: with the kill-switch OFF the tab pages get their 4.1.3 form back (no page key).

### Questions for the owner (the code stays until he answers)

1. app-routes-4 — ride recording stops after 48 hours of standing without the app being opened.
2. app-core-3 and app-pay-7 — should "never fill twice" also apply when the new look is switched off.
3. app-core-12 — should the app offer "Dokončit rezervaci" for an unpaid booking created on the website.
4. app-pay-2 — should the app itself cancel the booking when the 30 minutes for payment run out.
5. backend-1 — should the server refuse a payment that is higher than the booking price.

The exact Czech wording of each question is in the plan of the candidate.

### Release order (conditions of several KEEP decisions)

- The SQL bundle (rides 20261112b01–b08, restore 20261112a02, the others) must be in the merge and the deploy-sql run must be
  green before the 4.2.0 build is published (app-routes-5, app-res-7).
- The merge deploys the edge functions; the deploy-functions run must be green before the build is published, and the edge
  functions must not be rolled back while 4.2.0 is in the stores (app-pay-1). The app relies on complete_extension, card_min
  and attempt_id, which exist only on this branch.
- backend-1 starts to apply to app 4.1.3 at the moment of the merge.

### Manual checks on real phones before the release (code that cannot be tested on the host)

- Android (app-rest-1, app-pay-4, app-core-10): cold start; opening from a push notification and from an App Link; Back on a tab
  root; ride recording, swipe the app away, reopen; card payment with 3-D Secure approved and cancelled; attempts to close the
  card sheet while the payment runs; Google Pay cancelled; fresh install, allow notifications, sign in, receive a push.
- iPhone (app-ios-6, app-ios-5, app-ios-4): Apple Pay paid, cancelled and declined; card with 3-D Secure; edge swipe on the
  booking form with the new look ON and OFF; push after a fresh install.
- Either phone (app-rest-10): forgotten password, code, new password, login.

### Notes for the other jobs

- SQL job: add the app_v2_ui row (app-flagoff-1). Change the handover push text that still says the protocol can be signed
  in the app (app-core-5). Consider keeping the whole old row when the pricing guard refuses a customer
  write (app-res-12), so that no half-written booking remains; this also concerns app 4.1.3 after the merge.
- Known limitation accepted for this release: a dialog or sheet that is open on a tab root at the moment the kill-switch is
  applied (app-flagoff-2).

## Decisions

### app-routes

**app-routes-1 — KEEP**

- Reason: It serves Q3 (a way back that works). I ran a probe of the 4.1.3 call: a plain push from Moje zážitky (outside the shell) to /routes/:id (inside the shell) trips Flutter's duplicate page key assertion and leaves no usable screen, so the old navigation was broken, not just different. With pushOrGo the detail opens and Back leads to the routes list; test/refix_states_test.dart asserts exactly that.
- Plan: No change. Known trade-off: Back from this detail returns to the routes list, not to Moje zážitky.

**app-routes-2 — ADD_TEST**

- Reason: The banner serves Q3, but its rule is wrong for a standing rider. I read the code: the navigation GPS stream uses distanceFilter 4 m (same as 4.1.3), so no fixes arrive while the bike stands, and the 5 s timer raises 'weak GPS' after 20 s without a fix. A customer waiting at traffic lights or refuelling is told that the GPS signal is weak. No test covers the rule.
- Plan: FIX + TEST. Add a pure helper navGpsWeak({required Duration? sinceFix, required double lastSpeedKmh}) in a new shared file lib/features/routes/nav_gps_health.dart (identical in both trees): true only when sinceFix is longer than 20 s AND lastSpeedKmh is above 5 (the existing _moveThreshold). Call it from the timer in _watchGpsHealth in route_navigation_screen.dart, passing _speedKmh; that screen is one of the 19 platform files, so make the same small edit by hand in each tree. Add test/rides/nav_gps_health_test.dart: 25 s without a fix at 0 km/h is not weak; 25 s at 40 km/h is weak; 10 s at 40 km/h is not weak; no fix yet (null) is not weak. Run test/rides and test/v2/ux/road_line_test.dart; diff -rq of both lib trees must still print the 20 expected lines.

**app-routes-3 — ADD_TEST**

- Reason: The change serves Q3, but I confirmed a defect in the code: after a partial upload the uploaded URLs are added to _photos while _newPhotos keeps the whole batch (uploadRidePhotos returns only the successful URLs, so the sheet cannot tell which file failed). The stop is already saved with the partial set, and a second tap on Uložit uploads every file again, so photos that already uploaded are stored twice and the total can pass the 8-photo limit.
- Plan: FIX + TEST. In lib/features/routes/ride_provider.dart add uploadRidePhotosEach(uid, photos) that returns a List<String?> aligned with the input (null = that photo failed) and make uploadRidePhotos a thin wrapper over it. In ride_point_sheet.dart _save use the aligned result through a pure helper mergeUploadedPhotos(photos, batch, results) that returns the new URL list, the files still pending and the number that failed, and remove every uploaded file from _newPhotos. Both files are shared: copy them to the iOS tree. Add test/rides/ride_point_photos_test.dart: three files with results [url1, null, url3] give two URLs added, one pending file (the second) and failed = 1; a second round with [url2] gives three distinct URLs and nothing pending; the helper never returns more than 8 photos.

**app-routes-4 — ASK_OWNER**

- Reason: The three guards are design defaults of the Q6 recorder, not owner requests: the ride spec (.claude/handoff/rides/SPEC.md §18, D2 and D3) lists them as defaults the owner may change and marks the 48-hour choice as still pending. They are covered by test/rides/ride_pause_guard_test.dart and can be tuned or switched off from Velín (feature_flags.ride_autopause.conditions: long_h, idle_h, home_h) without a release. Removing them would leave GPS running for days after a forgotten Stop, so the code stays.
- Plan: Keep the code. Question for the owner: „Když půjčená motorka 48 hodin stojí a zákazník mezitím neotevře appku, záznam jízdy se vypne a znovu se zapne až po otevření appky (u vlastní cesty navíc připomínka po 20 hodinách a upozornění „doma“ po 3 hodinách) — má to tak zůstat? Hodnoty jdou změnit ve Velínu bez nové verze.“

**app-routes-5 — KEEP**

- Reason: Serves Q6. The fallback to the old server exists and is tested for the start and for taking over a running legacy ride (test/rides/ride_recorder_test.dart, ride_r5_fix_test.dart with trips: false). The risk named by the auditor exists only if the app is published before the ride SQL (supabase/migrations/20261112b01–b08, on this branch as work in progress) is deployed.
- Plan: No code change. Release condition: the ride SQL must be part of the merge and the deploy-sql run must be green before the 4.2.0 build is published.

**app-routes-6 — KEEP**

- Reason: Serves Q6 (sane statistics). I compared the 4.1.3 card with RideStatsGrid: every customer figure is still there, the 'without signal' cell and the gap notice remain, pauses and days were added. The two dropped cells (number of GPS points, number of breaks) were diagnostic counters shown only for a track with gaps; no flow depends on them.
- Plan: No change.

**app-routes-7 — KEEP**

- Reason: Q7 asks for exactly this (GPS gaps as a grey dotted estimated road route with a label). I read the code: the call volume is bounded to 25 gaps per ride and 3 retries per segment, results are cached for the app run, and a ride without gaps makes no routing call.
- Plan: No change. If the Mapy.com quota ever becomes a concern, the small preview cards can skip the estimate; that is not needed for this release.

**app-routes-8 — KEEP**

- Reason: The code is in origin/main (PR #2208, 2026-10-15) and answers a documented owner report (SUPABASE_BACKEND_STATE_6.md, entry 2026-10-15: the bad ride reported from Velín). The Q6 recorder is built on these files, so going back would break Q6.
- Plan: No change.

### app-core

**app-core-1 — ADD_TEST**

- Reason: The prefill serves Q5 (2026-10-22, never fill twice), but the save rule removes a 4.1.3 function. I reproduced it with my own probe that makes the same calls as the form: delivery to Jihlava; collection switched to an address is prefilled with Jihlava; changing the collection to Brno silently changed the delivery to Brno with the Brno fee; setting the delivery back moved the collection back too. A customer cannot book delivery and collection at two different addresses, in either look, and the kill-switch does not help.
- Plan: FIX + TEST (must be done before the release). In lib/core/booking_address_carry.dart, handoverSaveAddress: let the other side follow only while it has no address of its own, i.e. follow = otherDelivery && !_filled(otherCity); remove the 'same address' branch and its unused locals and correct the doc comment. The file is shared: copy it to the iOS tree. In test/v2/screens/booking_prefill_logic_test.dart, group 'handover address carry': (1) rewrite 'pickup address change: a linked return follows…' so that with both sides at Jihlava a new pickup address leaves the return address and returnDelivFee unchanged; (2) add 'A, copied, B': pickup Jihlava with fee 1200, handoverToDelivery(pickup: false) copies it, then handoverSaveAddress(pickup: false, Brno) keeps pickup Jihlava with fee 1200 and sets return Brno, and saving the pickup again leaves return Brno; (3) add the mirrored case with the return address entered first; (4) add: the other side on delivery with an empty address still takes the new address and the fee. Run that file, test/v2/screens/booking_prefill_*_test.dart, booking_r2_address_test.dart and test/v2/ux/cb_booking_sheets_test.dart in the Android tree and in the iOS scratch copy.

**app-core-2 — ADD_TEST**

- Reason: The records serve Q4 (double-charge marker, queue of paid changes) and Q5 (kill-switch value at start), but I confirmed in the code that they do not survive. CacheCleanupService.run() is called at every start (lib/main.dart line 219, before AppV2UiNotifier.preload) and at every paused or detached state (line 336) and removes every SharedPreferences key that is not in its keep-list. mg_payment_submitted_v2, mg_paid_change_queue_v1, mg_app_v2_ui, mg_engage_token, mg_engage_sent, mg_v2_ai_coach_seen and the prefix mg_v2_home_review_hidden_ are not in the list. Opening the bank app for 3-D Secure pauses the app, so the 'payment sent' marker and the queue entry are erased exactly when they are needed, and a switched-off new look comes back at every cold start. The safeguards of app-pay-2, app-pay-3 and app-res-10 rely on these records.
- Plan: FIX + TEST (must be done before the release). In lib/core/cache_cleanup_service.dart add to _preserveKeys: 'mg_payment_submitted_v2', 'mg_paid_change_queue_v1', 'mg_app_v2_ui', 'mg_engage_token', 'mg_engage_sent', 'mg_v2_ai_coach_seen'; add 'mg_v2_home_review_hidden_' to _preservePrefixes; expose @visibleForTesting static bool keeps(String key) and @visibleForTesting static Future<void> clearTransientPrefs() (a wrapper of _clearTransientPrefs). The file is shared: copy it to the iOS tree. Add test/cache_keep_keys_test.dart: (a) keeps() is true for PaidChangeQueue.storeKey, AppV2UiNotifier.prefKey, MgAiCoach.prefKey, HomeHiddenReviews.prefix + 'b1', the literal marker key and both engagement keys, and false for an unknown key; (b) behaviour: set mock preferences with a pending payment marker, one paid-change queue entry and mg_app_v2_ui = false, call clearTransientPrefs() (never run(), it deletes temp directories), then PaymentPendingMarker.isPending is still true, the queue still holds the entry and AppV2UiNotifier.preload() gives bootValue false. Run it with test/rides/ride_cache_keys_test.dart, test/refix_states_test.dart, test/paid_change_queue_test.dart, test/paid_change_queue_fix_test.dart and test/v2/flag_test.dart, in the Android tree and in the iOS scratch copy.

**app-core-3 — ASK_OWNER**

- Reason: The helpers serve the 2026-10-22 request, but that request is recorded under the new look and the code also changes the old look: prefilled passenger sizes, the customer's own vouchers as chips, quick address options, the e-mail carried between login and registration, and a tap on an already chosen passenger-gear or boots row now opens its sheet with 'Odebrat' instead of removing the row at once (I compared the 4.1.3 tap handler). Each item is low risk and, once app-core-1 is fixed, nothing a customer could do in 4.1.3 is lost. Limiting them to the new look would create two behaviours in shared, tested code shortly before the release, so the code stays and the owner decides.
- Plan: Keep the code. Question for the owner: „Má pravidlo „zákazník nic nevyplňuje dvakrát“ (předvyplněné adresy a velikosti, vlastní poukazy na výběr, úprava už zvolené výbavy v listu s tlačítkem Odebrat) platit i při vypnutém novém vzhledu, nebo se má starý vzhled chovat přesně jako verze 4.1.3?“

**app-core-4 — ADD_TEST**

- Reason: Serves Q3: the Continue button no longer lets a customer go on to pay for dates whose occupancy is unknown. I read canProceedNow and the retry row; the rule is shared by both looks. Every booking now passes through this gate, and no test pumps the form with the occupancy request still loading or failed (the existing fakes always return a value).
- Plan: TEST only. Add test/booking_dates_gate_test.dart using test/v2/support/fakes_booking.dart, with the form otherwise complete (dates, sizes, consents): (1) bookedDatesProvider still pending: the CTA is disabled and no red row is shown; (2) the provider fails: the CTA is disabled, the red row with the text fxBookedDatesWait and the retry button (eoRetry) is shown and the calendar shows fxBookedDatesFail; (3) tap retry with the provider now returning an empty list: the CTA is enabled. Run the three cases once with the flag OFF (old look) and once with the new look ON.

**app-core-5 — KEEP**

- Reason: A documented owner request outside the Q list: SUPABASE_BACKEND_STATE_6.md, entry 2026-10-10 („protokol převzetí se v telefonu duplicitně neukazuje — platí podpis na displeji pobočky“), commit 3e872afe in origin/main. The kiosk code in the repo is at 1.3.0 and signs the protocol on its display, so bringing the screen back would contradict the live kiosk flow. One loose end: the push the database sends at that moment still says „Podepište prosím předávací protokol — v aplikaci nebo na displeji pobočky“ (latest definition in migration 20261023c, and the live schema snapshot of 2026-11-08); the text change proposed on 2026-10-10 (20261010_handover_push_kiosk_only.sql) was never committed. With app 4.2.0 that push sends the customer into an app that has no protocol to sign.
- Plan: No app change. Follow-up for the SQL job (I did not touch supabase/migrations): change the push text in _handover_from_door_event() to „Podepište prosím předávací protokol na displeji pobočky.“, as the changelog entry of 2026-10-10 describes, and ship it with this merge.

**app-core-6 — ADD_TEST**

- Reason: A documented owner request of 2026-10-10 (self-service branch: helmet S–3XL, jacket, trousers and gloves up to 4XL), in origin/main and enforced by the kiosk and the edge function too, so it stays. The rule decides whether the Continue button of a self-service booking is enabled and whether a prefilled size is cleared, and the pure function selfServiceSizeAllowed has no test.
- Plan: TEST only. Add test/self_service_gear_test.dart: helmet XS and 4XL are refused, S and 3XL allowed; jacket, pants and gloves 4XL allowed, 5XL and 6XL refused, XXS allowed; XXL counts as 2XL; ' xxl ' is trimmed and case-insensitive; boots '43', a kids label and an empty or null size are allowed; gearSizesFor(type, kids: false, selfService: false) equals the 4.1.3 lists for helmet, jacket, pants, gloves and boots (copy them from booking_models.dart at 70a94933); with selfService: true the result is a subset in the same order; kids: true ignores selfService.

**app-core-7 — KEEP**

- Reason: A documented owner request (SUPABASE_BACKEND_STATE_6.md, entry 2026-10-11 D: the customer's language for the app, contracts and e-mails), in origin/main. I read LocaleNotifier._load: a language tapped in the 4.1.3 welcome overlay is applied only when no language was chosen in Settings. The display currency by language already existed in 4.1.3 (Money.init(defaultLang) at the base commit).
- Plan: No change. Worth one line in the release notes: a customer who tapped a foreign language at the first start and never changed it will now see the app in that language.

**app-core-8 — KEEP**

- Reason: Part of the same documented i18n request. The built-in Czech summary was an outdated legal text (the changelog entry 2026-10-11 D mentions the old version with the 30 000 Kč excess); without a connection the customer now gets a clear 'could not load' message instead of an outdated summary.
- Plan: No change.

**app-core-9 — KEEP**

- Reason: A documented owner request (SUPABASE_BACKEND_STATE_6.md, entry 2026-10-15, App funnel: „to samé pak i app“), in origin/main. The service swallows every error and does nothing in debug builds.
- Plan: No change here. The two engagement keys are added to the cleanup keep-list in the app-core-2 fix; without it the same visitor is counted again after every pause.

**app-core-10 — KEEP**

- Reason: Comes from the Q3 round of 2026-10-16 (PR #2212, in origin/main). I read PushService.initialize: it never asks for permission, registers its listeners once and writes the token only when the pair user and token changed, so calling it on resume and after sign-in is safe. It repairs door-code and SOS notifications on a fresh install.
- Plan: No change. Include in the manual device check: fresh install, allow notifications, sign in, receive a push without restarting the app; tap a push while the app is closed.

**app-core-11 — KEEP**

- Reason: Follows the documented documents-gate request of 2026-10-10 (door codes only with complete documents): the pill now uses the same rule that releases the door codes, with a fallback to the profile when the RPC gives no answer.
- Plan: No change.

**app-core-12 — ASK_OWNER**

- Reason: The filter serves the aim of Q4 (a booking made on the website may be waiting for a bank transfer, so a card payment in the app would be a second payment), but it also removes something 4.1.3 did: within 30 minutes of creating a booking on the website the app offered to pay it by card or to cancel it. I checked that the reservation detail has no other pay button. Removing the filter would bring the double-payment risk back, so the code stays until the owner decides.
- Plan: Keep the code. Question for the owner: „Má appka nabízet tlačítko „Dokončit rezervaci“ (zaplatit kartou nebo zrušit) i u nezaplacené rezervace vytvořené na webu, jak to dělala verze 4.1.3, nebo jen u rezervací z appky (teď — aby zákazník, který čeká na bankovní převod, nezaplatil podruhé kartou)?“

**app-core-13 — KEEP**

- Reason: An explicit owner request (Q3, „nikde se to nesmí zaseknout“). I read the limits and the calls the app makes: the e-mail functions are fire-and-forget, process-payment uses its own client, SOS photos are at most 2048 px JPEG and document photos 1600 px, so the 60 s and 120 s limits are reached only on a very weak signal, where the customer now gets a retry text instead of an endless spinner. The limit table and the stalled-request mechanics are tested in test/error_states_other_test.dart.
- Plan: No change.

**app-core-14 — KEEP**

- Reason: A correction that protects the price. I read the 4.1.3 dialog: its Enter path skipped the 'code already applied' check that the button had, so the same fixed discount could be added twice. Going back would restore that defect.
- Plan: No change.

**app-core-15 — KEEP**

- Reason: A correction of an empty date field when the stored year lies outside the offered range; the v2 date row uses the same year list and test/fix_dates_test.dart covers both looks.
- Plan: No change.

**app-core-16 — KEEP**

- Reason: It only affects phones with animations switched off, where the final state is shown at once; the normal sequence equals 4.1.3 according to the area report and test/v2/fix_shared_r3_test.dart covers it.
- Plan: No change.

**app-core-17 — REVERT**

- Reason: No request asks for it in the old look and nothing requested depends on it: the page key is needed only by the v2 fade-through page. At 70a94933 the tab roots were keyless NoTransitionPage, so a tab switch updated the same route in place; with a key every switch replaces the route. With the kill-switch OFF the tab pages should be exactly the 4.1.3 pages.
- Plan: In lib/core/router.dart (identical in both trees: edit once and copy to the iOS tree) change only the flag-off branch of routerTabPage to NoTransitionPage<void>(child: child) without a key, as the tab routes were at 70a94933; keep the v2 branch (mgTabPage(key: state.pageKey, …)) unchanged. Tests that must still pass: test/v2/wiring_test.dart, test/v2/flag_test.dart, test/v2/flag_off_test.dart, test/v2/ux/fnd_flag_motion_test.dart, test/v2/ux/shell_home_strips_test.dart, test/v2/shared_carry_test.dart, test/navigation_back_test.dart, test/refix_states_test.dart, then the full suite; the analyze counts must not change.

**app-core-18 — KEEP**

- Reason: Supports the ride recording work that is in origin/main (PR #2208); the category column of app_debug_logs is free text according to the backend state file.
- Plan: No change.

### app-pay

**app-pay-1 — KEEP**

- Reason: Serves Q4 (the server writes a paid change; retry; refund when the bike was taken meanwhile). The queue outcomes done, retry, failed, not paid, extras-only retry and the legacy client write are covered by test/paid_change_queue_test.dart, test/paid_change_queue_fix_test.dart and test/payments_restart_taken_test.dart. I confirmed that complete_extension exists only on this branch and not in origin/main (removed by hotfix 31cf5293), so the app and the edge functions must ship together.
- Plan: No code change. Release conditions: (1) the merge deploys the edge functions and the deploy-functions run is green before the 4.2.0 build is published; (2) the edge functions are not rolled back while 4.2.0 is in the stores; (3) the queue key survives the cache cleanup (app-core-2 fix).

**app-pay-2 — ASK_OWNER**

- Reason: Q3 asked for a truthful 'time expired' state, not for the app cancelling the booking; 4.1.3 only showed the sheet and the server cron cancelled. I read the code: the cancel is skipped for edits and swaps, skipped while a payment marker is pending, and only touches a row that is still unpaid; the new text („Rezervaci jsme zrušili a motorku uvolnili“) is true only because of it. For a resumed booking the deadline compares server time with the phone clock, so a phone that runs fast cancels that many minutes early. Taking the cancel out would make the new text untrue until the cron runs, so the code stays until the owner decides.
- Plan: Keep the code; it relies on the payment marker surviving a pause (app-core-2 fix). Question for the owner: „Když zákazníkovi v appce vyprší 30 minut na zaplacení, má appka rezervaci sama hned zrušit a uvolnit motorku (teď), nebo to má jako ve verzi 4.1.3 nechat na serveru?“

**app-pay-3 — KEEP**

- Reason: Serves Q3 (in 4.1.3 a customer whose own abandoned draft blocked the dates saw an unknown error for up to 30 minutes). I read the branch: it looks only at the customer's own pending, unpaid app booking of the same bike with overlapping dates, shows 'payment is being verified' when a marker is pending, and otherwise cancels that draft and creates a new one. A payment that still lands on the cancelled draft is refunded by the Q4 'cancelled meanwhile' path.
- Plan: No change in this file. Its safety depends on the payment marker surviving a pause, which the app-core-2 fix and its test provide.

**app-pay-4 — KEEP**

- Reason: Serves Q4 (no second charge because the sheet was closed while a payment was running). I read the Android sheet: the lock is released on every result path (paid, processing, failed, cancelled 3-D Secure or wallet), and a sheet that is closed anyway returns 'processing', never 'cancelled'. A permanent hang would need Stripe never to answer, which I could not show; a killed app starts again without the sheet. The sheet embeds Stripe's native card field, so it cannot be widget-tested on the host.
- Plan: No change. Manual check on an Android phone before the release: pay by card with 3-D Secure approved; cancel 3-D Secure (the sheet must stay usable with the note „Platbu jsi nedokončil(a)“); try Back, a tap outside and a drag while „Platba se zpracovává“ is shown; cancel Google Pay.

**app-pay-5 — KEEP**

- Reason: Part of the documented i18n request (SUPABASE_BACKEND_STATE_6.md, entry 2026-10-11 D: contracts in the customer's language also from the app; commit cf824b36). I confirmed that the 4.1.3 call did nothing: it sent {types: […]} and generate-document answers 400 without template_slug. The new call waits 45 s and generates only what generated_documents does not show; the edge function forces the booking language and replaces an older document of the same template, so a late server document is replaced, not doubled.
- Plan: No change.

**app-pay-6 — KEEP**

- Reason: A price-correctness fix in shared code. I read the 4.1.3 sheet: typing after picking a suggestion kept the picked address and its distance, so POTVRDIT could save a delivery price that did not belong to the typed text. In the new code typed text without a pick is still accepted, parsed and geocoded on POTVRDIT. Going back would restore the stale price. The logic is covered by test/v2/screens/booking_r2_address_test.dart and the sheet body is the same class in both looks.
- Plan: No change.

**app-pay-7 — ASK_OWNER**

- Reason: The same topic and the same decision as app-core-3: additive 'never fill twice' helpers that are active in the old look too (the saved address shown in the reservation edit, quick address options, the customer's own vouchers in the promo dialog). Nothing that 4.1.3 offered is removed; the area report checked that confirming an unchanged address adds no delivery surcharge.
- Plan: Keep the code. It is covered by the question asked under app-core-3 (should 'never fill twice' also apply with the new look switched off).

**app-pay-8 — KEEP**

- Reason: The documented owner request of 2026-10-10 (self-service sizes), in origin/main and matched by the kiosk and edge limits.
- Plan: No change; the missing unit test is added under app-core-6.

**app-pay-9 — KEEP**

- Reason: Small corrections from the documented i18n request: the booking insert retries once with 'en' only when the database CHECK rejects the language, and the pickup/return title no longer depends on the Czech label 'Vyzvednutí', which was wrong in other languages.
- Plan: No change.

**app-pay-10 — KEEP**

- Reason: Serves Q4 (no duplicate shop orders, no second payment, card minimum D2). I read _finalize: the reused order is dropped when the server refuses because the price or the order changed, and the server decides the charged total. The e-shop is hidden by default (feature flag eshop_visible, off since 2026-10-01), so the exposure is low.
- Plan: No change.

### app-res

**app-res-1 — KEEP**

- Reason: The same documented owner request as app-core-5 (2026-10-10: the handover protocol is signed only on the branch display; the app shows the signed document). It is in origin/main and the kiosk and the edge function already work that way.
- Plan: No app change; the push text that still mentions signing in the app is the SQL follow-up described under app-core-5.

**app-res-2 — KEEP**

- Reason: The documented owner request of 2026-10-10 (self-service sizes). I read the block: saving is refused only when a stored size lies outside the self-service range and that gear was touched or the bike moved to a self-service branch.
- Plan: No change; the unit test for selfServiceSizeAllowed is added under app-core-6.

**app-res-3 — KEEP**

- Reason: The app side of the documented documents-gate request of 2026-10-10 that is already live on the backend (codes only with both sides of the identity document and of the licence, real files only). Going back would break compatibility with the live backend: withheld codes would be invisible and marker rows without a file no longer count.
- Plan: No change.

**app-res-4 — KEEP**

- Reason: Part of the documented i18n request of 2026-10-11 (legal texts in the customer's language, never an outdated translation); the RPC get_document_translation is live.
- Plan: No change.

**app-res-5 — KEEP**

- Reason: A correction of day arithmetic across a daylight-saving change (calendar days instead of 24-hour differences). It removes no function, and going back would bring back a one-day shift of the extension end or of the history label.
- Plan: No change.

**app-res-6 — KEEP**

- Reason: Required by the live gear-only rental backend (Q8; CLAUDE.md: a gear booking is recognised only by booking_kind). The field defaults to 'moto' and it only prevents ride recording for a booking without a bike.
- Plan: No change.

**app-res-7 — KEEP**

- Reason: Serves Q4 D3 (restore and pay through the server, owner decision 2026-10-16). I checked that supabase/migrations/20261112a02_customer_restore.sql defines customer_restore_booking(p_booking_id uuid) with EXECUTE for authenticated, returns the error codes the app maps, and adds a guard that keeps the direct restore of app 4.1.3 working. The refusal texts are tested (test/payments_paydec_test.dart, test/payments_payfix_test.dart).
- Plan: No code change. Release condition: this migration must be in the merge and deployed before the 4.2.0 build is published; until then the app answers every restore with the 'restore is being deployed' text.

**app-res-8 — ADD_TEST**

- Reason: The 20 s limit serves Q3, but it removes a 4.1.3 fallback in a safety function. I read GpsService: high accuracy for 15 s, then low accuracy for 15 s, then the last known position. The 20 s cap ends the wait 5 s into the second attempt and returns no position, so the last known position is never tried; 4.1.3 sent the report with it. An accident or theft report from a place with weak GPS now goes out without coordinates.
- Plan: FIX + TEST. In lib/features/sos/sos_location.dart (shared file: copy to the iOS tree) make sosLocate fall back to Geolocator.getLastKnownPosition() (2–3 s limit, errors ignored) whenever the limited GpsService.locate() ends without a position with status noFix, the timeout included, and return that position with status ok; leave serviceOff and denied as they are (the customer is told how to switch location on). Add optional test parameters for the two calls. Add test/sos_location_test.dart: a locate call that never completes plus a last known position gives that position once the limit passes; locate returning noFix plus a last known position gives the position; no last known position gives no position with noFix; serviceOff stays serviceOff. Then confirm by reading that the report screens show 'sent without location' only when the position is null.

**app-res-9 — KEEP**

- Reason: Serves Q3 (no false success): 4.1.3 created a location incident with empty coordinates and told the customer the location was shared. Now the customer is told why it failed and how to fix it. With the last-known fallback of app-res-8 the share succeeds in more weak-GPS cases.
- Plan: No change.

**app-res-10 — KEEP**

- Reason: Serves Q4: while a paid change is still being completed, a second payment or a direct save could overwrite it. I read the queue: unpaid safety entries expire after 24 hours, and a paid entry the server never confirms is shown once as handled by staff after 7 days. Covered by test/refix2_states_test.dart and the queue tests.
- Plan: No change; it depends on the queue key surviving the cleanup (app-core-2 fix).

**app-res-11 — KEEP**

- Reason: Serves Q3 and Q4: 4.1.3 ignored {error} from cancel_booking_tracked and closed the dialog as if the booking were cancelled. I checked the live RPC texts (migration 20261023e): „Rezervace je již stornována“, „Nemáte oprávnění“ and „Rezervace nenalezena“ match the mapping, and the new SQL bundle states that it does not change this RPC. 'wrong_status' can only come from a race, because the app offers cancellation only before the handover; the customer then sees the general failure with Retry.
- Plan: No change. Optional later polish, not needed for this release: give 'wrong_status' its own text without Retry.

**app-res-12 — ADD_TEST**

- Reason: The save path equals 4.1.3 and serves Q3 and Q4, but together with the approved SQL guard (supabase/migrations/20261112a07_guard_customer_booking_pricing.sql) it can report a change that was not saved. I read both: for a paid booking the guard silently keeps the old dates, bike and price whenever the direct write has more days (or a higher price-list value), also when the total goes down, for example one more day together with a removed delivery. The UPDATE succeeds, the app says 'saved' and calls process-refund. I checked process-refund: a customer refund is capped at the overpayment against the current total_price, so no money leaves, but the customer is told the booking was changed (or that staff will refund) while nothing changed, and columns the guard does not pin (pickup method, address) are written.
- Plan: FIX + TEST. In lib/features/reservations/reservation_edit_screen.dart (shared file: copy to the iOS tree), branch effDiff <= 0: after the UPDATE returns without an error, re-read the booking with the existing check (_editAppliedAfterNetError, extended by moto_id) and treat it as 'not saved' only when every field the edit wanted to change still holds its ORIGINAL value. In that case do not call process-refund and do not replace the extras; show the failure sheet (title psEditFailTitle) with a new text key in all 8 languages (file translations_ext_40_refix_a.dart, both trees) saying that the booking stayed unchanged, nothing was charged or refunded, and the customer should change the dates first and the rest separately; then reload the booking. Move the comparison into a pure function editWriteApplied(row, changes, original) and add test/edit_write_check_test.dart: the row equals the wanted values → true; the row still holds the original dates and total while the edit wanted more days and a lower total → false; a pinned bike → false; nothing distinguishing → null. For the SQL job (outside my area, a suggestion only): when the guard refuses a change it should keep the whole old row (RETURN OLD), so that no half-written booking remains.

### app-rest

**app-rest-1 — KEEP**

- Reason: In origin/main since PR #2208 (2026-10-15) and documented in SUPABASE_BACKEND_STATE_6.md as part of the fix for the bad ride the owner reported from Velín („Android záznam po zavření okna“); the Q6 recorder uses its channel (RideKeepAlive). I read MainActivity: without a running recording the engine is created and destroyed as before. It is native code on the start path of every Android launch and cannot be tested on the host.
- Plan: No change. Mandatory manual check on a real Android phone before the release: cold start; opening from a push notification and from an App Link; Back on a tab root closes the app; start a ride recording, swipe the app away and reopen it (the recording continues, Back and deep links still work); pay by card with 3-D Secure after such a reopen.

**app-rest-2 — KEEP**

- Reason: The same code and decision as app-core-13: an explicit owner request (Q3, nothing hangs); the limits are generous for the calls the app makes and the limit table is tested.
- Plan: No change.

**app-rest-3 — KEEP**

- Reason: The same documented owner request as app-core-5 (2026-10-10, the protocol is signed only on the branch display); it matches the live kiosk flow and the deleted screen and route are gone in origin/main too.
- Plan: No change.

**app-rest-4 — KEEP**

- Reason: The same code and decision as app-core-10 (Q3 round of 2026-10-16, in origin/main): PushService.initialize is safe to call repeatedly and a notification tapped on a cold start is no longer lost.
- Plan: No change; part of the manual device check listed under app-core-10.

**app-rest-5 — KEEP**

- Reason: The same documented owner request as app-core-9 (App funnel, 2026-10-15), in origin/main; Velín already shows this data.
- Plan: No change; the engagement keys are added to the keep-list in the app-core-2 fix.

**app-rest-6 — KEEP**

- Reason: Part of the documented i18n request (2026-10-11 D: Ukrainian added, English fallback before Czech). On the registration path only the stored profile language changes, and a value the database rejects falls back to 'en' without blocking the registration; Czech output is unchanged according to the area report.
- Plan: No change.

**app-rest-7 — KEEP**

- Reason: Text only, no functional risk. Informal address is a rule of the owner-approved v2.2 design for state texts (DESIGN_V22.md, row R2), and these keys are shared by both looks, so going back to the formal form would break the approved tone in the default look. The cost is a mix of formal and informal sentences in the fallback look.
- Plan: No change.

**app-rest-8 — KEEP**

- Reason: A correction: local time was sent without a zone, so Postgres stored it one or two hours off. No function is removed; according to the area report the order of conversations becomes correct in the app and in Velín.
- Plan: No change.

**app-rest-9 — KEEP**

- Reason: Follows the documented 18+ documents gate of 2026-10-10 (the backend refuses door codes to a customer under 18); a stored younger year stays in the list.
- Plan: No change.

**app-rest-10 — KEEP**

- Reason: Serves Q3 (a flow that never finished). I read the 4.1.3 flow: verifying the recovery code signs the customer in, and the router then sent every signed-in user away from /reset-password, so the new-password step was never reached. The flag is set only around the code verification and cleared when the screen is left and after the password change; a stuck flag could only keep a signed-in user on /reset-password, never block another route.
- Plan: No change. Manual check before the release on one device: forgotten password, code from the e-mail, new password, login with the new password.

**app-rest-11 — ADD_TEST**

- Reason: Serves Q3 (a way back that loses nothing). I read the two handlers: the BackButtonListener consumes the system back and the PopScope handles other pop attempts, so I expect one step per press, but registration is the first thing a new customer does and no test runs the system back on this screen in the old look (the existing test covers only the v2 edge swipe on iOS).
- Plan: TEST only. Add test/register_back_test.dart with the flag OFF: RegisterScreen in a GoRouter with /login and /register wrapped as in the app (use the _systemBack helper of test/refix_states_test.dart): (1) system back on an untouched step 1 shows the login screen and does not close the app; (2) after typing a first name, system back shows the discard confirmation; 'stay' keeps the typed text, 'discard' leads to the login screen; (3) if step 2 can be reached in the harness, one system back returns to step 1 with the fields kept and a second press is needed to leave. Run the same cases with the new look ON.

**app-rest-12 — KEEP**

- Reason: Serves Q3 (the reason and a retry instead of a silent failure). A second conversation needs a successful insert whose answer was lost; the customer would only see two threads with the same subject.
- Plan: No change.

### app-ios

**app-ios-1 — KEEP**

- Reason: The same documented owner request as app-core-5 (2026-10-10, protocol only on the branch display). The kiosk code in the repo is at version 1.3.0 and shows the protocol on its display, so a customer with app 4.2.0 is not left without a way to sign.
- Plan: No change.

**app-ios-2 — KEEP**

- Reason: I checked the base: in 4.1.3 the pay button of the payment screen (payment_header_widgets.dart) already showed the amount in the customer's display currency, and only the button inside the card sheet had a hard-coded 'Kč'. The change makes the two buttons agree; the display currency itself existed in 4.1.3 and the currency picker states that card payments are always in CZK. It comes from the documented i18n round in origin/main.
- Plan: No change. A possible later improvement, not for this release: show the charged Kč amount next to the converted one for customers who see prices in EUR or PLN.

**app-ios-3 — KEEP**

- Reason: The same code and decision as app-core-7 (documented i18n request of 2026-10-11): the language chosen at first start is applied, and the display currency by language already existed in 4.1.3.
- Plan: No change.

**app-ios-4 — KEEP**

- Reason: The same code and decisions as app-core-9 (App funnel, documented request of 2026-10-15) and app-core-10 (push registration without a restart, Q3 round); both are in origin/main and the same lines are in the iOS main.dart.
- Plan: No change; part of the manual device check on an iPhone (fresh install, allow notifications, sign in, receive and tap a push).

**app-ios-5 — KEEP**

- Reason: Serves Q3 (owner 2026-10-16: every screen must offer a way back; on an iPhone the edge swipe is the system way back). I read the booking form: its back arrow already pops without a confirmation, so the swipe does exactly what the arrow does. It is in origin/main since PR #2212.
- Plan: No change. Manual check on an iPhone with the new look ON and OFF: an edge swipe on the booking form returns to the bike and the app stays usable.

**app-ios-6 — KEEP**

- Reason: Serves Q4 (protection against double charges). I read the iOS sheet: the 'uncertain' guard is set when a payment starts and reset on every path (result known, 3-D Secure or wallet closed, Apple Pay failure verified as not charged), so a closed sheet returns 'processing' only while the result is really unknown. The Apple Pay branch runs only on an iPhone and cannot be tested on the host.
- Plan: No change. Mandatory manual check on an iPhone before the release: Apple Pay paid; Apple Pay cancelled (the sheet stays usable); a declined card in Apple Pay; pay by card with 3-D Secure approved and cancelled; try to close the sheet while the payment runs.

### app-flagoff

**app-flagoff-1 — ADD_TEST**

- Reason: The kill-switch is a Q5 requirement, and I confirmed that the owner cannot use it today: no migration in the repo inserts the feature_flags row app_v2_ui, and the Velín tab only lists existing rows and updates them by id (FeatureFlagsTab.jsx load and toggle). The Velín description also still says that iOS has only the old look, which has been untrue since 2026-11-05. If 4.2.0 misbehaves, there is no switch to press.
- Plan: FIX + CHECK (must be done before the release; no app code changes). (1) SQL job (I did not touch supabase/migrations): add to the SQL bundle an idempotent insert of the row, modelled on the ride_autopause insert in 20261112b01_rides_columns.sql: insert into public.feature_flags (key, enabled, description) values ('app_v2_ui', true, …) on conflict (key) do nothing; record it in the backend state files. Check on a local database: after the bundle the row exists with enabled = true and a second run changes nothing. (2) velin/src/pages/cms/FeatureFlagsTab.jsx, KNOWN_FLAGS.app_v2_ui.controls: say that the switch covers Android and iOS from version 4.2.0 and drop „iOS zatím jen starý vzhled“; run the Velín build. (3) The app side is already tested (test/v2/flag_test.dart: a missing row means ON); together with the app-core-2 fix a switched-off look then also survives a restart.

**app-flagoff-2 — KEEP**

- Reason: Serves Q5 (switch only at a safe moment). I read the gate: it applies a pending value only on a tab root that is the only page of the stack, without a query and with no payment running, so a booking, an edit or a payment is never interrupted. The remaining gap, a dialog or sheet open on a tab root at the moment the customer returns to the app, can only occur in the short time after the owner flips the switch and costs at most the choice made in that sheet.
- Plan: No change. Known limitation, accepted for this release.

**app-flagoff-3 — KEEP**

- Reason: A consequence of allowed v2 exceptions: the new look carries dates into the form from the price calculator and from Home, so carried dates can overlap a day the bike's calendar shows as busy. The guard blocks only such ranges before payment, which is what Q3 asks for (the date collision is explained instead of a refusal at payment); according to the area report it spares the customer's own unpaid draft and is tested in test/v2/screens/booking_r2_test.dart. The old look is unchanged: there the database refuses the booking at payment, as in 4.1.3.
- Plan: No change.

**app-flagoff-4 — KEEP**

- Reason: The same code and decision as app-ios-5: on an iPhone the edge swipe is the system way back that Q3 asks for, and it does what the form's back arrow already does without a confirmation.
- Plan: No change.

**app-flagoff-5 — KEEP**

- Reason: The same documented owner request as app-core-5 (2026-10-10, protocol only on the branch display), in both looks.
- Plan: No change.

**app-flagoff-6 — KEEP**

- Reason: The same code and decision as app-core-11: the pill follows the documents gate that releases the door codes (documented request of 2026-10-10).
- Plan: No change.

**app-flagoff-7 — KEEP**

- Reason: The same code and decision as app-core-7 (documented i18n request of 2026-10-11).
- Plan: No change.

**app-flagoff-8 — KEEP**

- Reason: The recovery exception serves Q3 (see app-rest-10). The /app prefix is what the Android manifest registers for App Links (pathPrefix /app on motogo24.cz); I read the redirect: it only strips that prefix and keeps the query, so no existing route changes. Both came with PR #2212, which is in origin/main.
- Plan: No change.

**app-flagoff-9 — KEEP**

- Reason: The same documented owner request as app-core-9 (App funnel, 2026-10-15); the writes are fire-and-forget in both looks.
- Plan: No change.

### backend

**backend-1 — ASK_OWNER**

- Reason: Edge-function money logic without a named request. I compared the live code and the branch: live refuses only an amount lower than the booking price; the branch also refuses an amount more than 1 Kč higher when the feature flag reservation_upsell is off or missing. That protects the customer from paying more than the documents show, but it contradicts the design note for owner decision D7 (paydec/DESIGN.md: 'PP keeps amount higher than due allowed for compatibility'), and it starts to apply to app 4.1.3 the moment the merge deploys the edge functions. The case is covered by pp_charges_flow_test.ts.
- Plan: Keep the code. Question for the owner: „Když appka pošle k zaplacení víc, než je cena rezervace v systému (rozdíl přes 1 Kč), má server platbu odmítnout s hláškou o správné ceně (tak je to připravené), nebo ji má jako dnes strhnout?“ My recommendation is to keep the refusal.

**backend-2 — KEEP**

- Reason: Serves Q4 D3 (a booking restored in the app cannot be paid at an outdated price). I read floor-check.ts: the floor is enforced only for bookings restored by the customer in the app (and for the waived or rounded card minimum); ordinary payments are only logged. A booking whose price staff lowered by hand and that then expired unpaid is refused on restore with 'create the booking again'; that is rare and staff can restore it in Velín. Covered by checkout_floor_test.ts.
- Plan: No change.

**backend-3 — KEEP**

- Reason: Serves Q4 D3 and D4 (a voucher cannot be used twice or after its expiry). I read voucherProblem: it refuses only a voucher that is expired or neither active nor redeemed by this booking, and a failed lookup never blocks the payment. Covered by payments_test.ts.
- Plan: No change.

**backend-4 — KEEP**

- Reason: Serves Q4 i3 (money is decided in Velín, never by the storno table on its own). I read the branch: it applies only to an admin call without any refund choice and writes a warning to debug_log. According to the area report the current Velín always sends the amount and customer cancellations arrive as service calls, so they are not affected. Covered by storno_i3_flow_test.ts.
- Plan: No change.

**backend-5 — KEEP**

- Reason: Admin-only. The road-route and gap parts are Q7, which names Velín, and the standing, waiting and trip states follow from Q6: the server now keeps rides open across pauses, so Velín has to read them the same way or staff would see wrong states and end rides by mistake. No customer flow can break. Velín has no test runner in the repo.
- Plan: No change.

