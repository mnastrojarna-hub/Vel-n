# understand:personal: what the app knows about one customer, and how Home and express booking can use it

Scope: the Android master tree `Motogo-app-main/motogo-app-flutter/lib`. The iOS tree mirrors it apart from the intentional per-platform differences listed in CLAUDE.md.
Backend: SUPABASE_BACKEND_STATE_1..6 plus migrations. Live anon reads were checked on 2026-10-15.
Paths below are relative to `lib/` unless they say otherwise.
Labels:
- **[EXISTS]**: the data and the RPC are already there and the app can show it today.
- **[CLIENT]**: the data is already loaded by the app; it only needs a client-side calculation or parsing.
- **[NEW-BE]**: needs new backend work. Per CLAUDE.md rule 3, any SQL goes to the owner as text first.

---

## 0. Key facts (TL;DR)

1. **Home today has nothing personal except the rank card and paid reservations.** `features/home/home_screen.dart` renders, in order:
   - `HomeHeader` (logo, PILOT badge with nickname glowing in the rank colour, fake search pill → `/search`, hamburger → `/profile` with unread badge)
   - `LoyaltyRankCard`
   - `HomeReservationsSection`: paid aktivní/nadcházející only, max 2; a red SOS bar when `sosAllowed`
   - the full bike list with `MotoFilterPanel`
   - AI FAB **bottom-left**, scroll-to-top FAB bottom-right

   Rides, routes, places, savings and stats all live two levels deep: TRASY tab → `/my-experiences`, opened from `routes_screen.dart:478` and `all_pois_screen.dart:517`.

2. **"Rides with MotoGo" vs "private rides" is a real data split.** Both come from `UserRide.bookingId` (`user_rides.booking_id`):
   - Non-null = a ride recorded automatically during a rental.
   - Null = a manual recording on the customer's own bike (`rideManualStart`, "Zaznamenat vlastní jízdu"), or a hand-built ride (`source='manual'`).
   - Both come back from one RPC: `get_my_rides`.

   Per-ride stats are computed on the server and are trustworthy: `distance_km`, `duration_min`, `moving_sec`, `idle_sec`, `gap_sec`, `avg_speed_kmh`, `max_speed_kmh`, `elevation_gain_m`, plus the points/photos counts.
   **There is no per-ride country stat.** `user_rides` has no country column; only `routes.countries` and `points_of_interest.country` have one.

3. **The guaranteed level-up already exists and the server is the source of truth.** `LoyaltyLevelUpWatcher` sits in `MaterialApp.builder`, so it runs on every screen. It works like this:
   - The baseline is `profiles.loyalty_celebrated_level`, read via RPC `loyalty_get_celebrated` and written via `loyalty_advance_celebrated` (GREATEST semantics; a guard trigger stops the customer writing it directly). A SharedPreferences copy is the fallback.
   - It checks on every pointer-down (throttled to 45 s), on resume (forced), every 3 min in the foreground, on any change to the realtime `bookings` stream (forced), and on `profileProvider` refresh.
   - Several levels gained → **one** celebration with `gained = N` ("MEGA POSTUP" when N ≥ 2).
   - It defers, without writing anything, while an onboarding overlay or the payment screen is up.
   - It writes "celebrated" only after the ~67 s montage, so killing the app mid-video replays it.
   - **Gaps** (details in §8):
     - `profiles` is not in the realtime publication, so an admin +1 rank or a monthly-winner bonus is only seen on the next tap after the 45 s throttle, or on resume.
     - No route-change trigger.
     - No reduced-motion variant.
     - No step-through of intermediate ranks.

4. **Routes near Velké Němčice cannot be found by `branch_id`.** On the live DB:
   - 1 174 approved routes; 384 have a `branch_id`, and all 384 point to **Mezná** (`1111…`); none point to VN (`2222…`).
   - **`geometry` is NULL on all 1 174 routes.** The app computes road lines live via Mapy.com. Home sketches must be drawn from `waypoints` (7–9 points per route).

   Use distance from the pickup branch instead: `pickupOriginProvider` already exists in `features/routes/routes_provider.dart:639`.
   - From VN: 18 routes start within 30 km, 41 within 50 km.
   - From Mezná: 30 within 30 km, 40 within 50 km.

5. **Express booking needs no new backend.** Everything a returning customer gave us is already stored and partly pre-filled:
   - Sizes: `profiles.gear_sizes {rider{helmet,gloves,jacket,pants,boots}, passenger{…}, rider_own}`
   - Saved cards: `payment_methods`; the default card is charged off-session without a sheet.
   - Profile and licence: a gate that blocks only when something is missing or the licence expires before the rental ends.

   The friction left is UI only: a 6-section scroll, **two consent checkboxes that start unticked on every booking** (`BookingDraft.consentVop/consentGdpr = false`), then a second `/payment` screen. Skipping the re-tick on every booking is an **owner/legal decision**. Today there is no VOP version to compare against; the option is in §5 (NEW-BE).

6. **The AI assistant is reachable today only from the Home FAB (bottom-left) and from a link on the SOS report screen.** It is **not** in the Profil menu.
   - The live flag `feature_flags.ai_assistant = true` exists, but the app never reads it.
   - The agent (`ai-moto-agent`) already receives the active booking id (else the latest), the language, the chat history and photos.

7. **SOS is only meaningful during a rental.** The condition is `Reservation.sosAllowed = !endedBySos && (status=='active' || (inRentalTerm && paid))`. Profil shows SOS only when `hasActiveRentalProvider` is true.
   - Pending SOS replacement (`sos_incidents.replacement_status` = selecting/pending_payment) → shell `_SosFab`.
   - SOS history per booking: `sosIncidentsProvider(bookingId)`.

---

## 1. Inventory of personal data and features (real fields, where they live, which screen opens)

### 1.1 Reservations (upcoming, active, history)

- **Source:** `reservationsProvider` (`features/reservations/reservation_provider.dart:34`). It is a `StreamProvider` with an initial fetch plus a realtime `bookings` stream filtered `user_id = uid`.
  - Select: `*, motorcycles!moto_id(*, branches(name,address,city,gps_lat,gps_lng,type))`.
  - Because it selects `*`, **every bookings column and every motorcycle column arrives**, including ones the model does not parse yet, such as `motorcycles.box_number` and `bookings.mileage_start/mileage_end`.
- **Model `Reservation`** (`reservation_models.dart:31–114`) fields:
  - id, motoId, motoName, motoImage, category, branchName, status (pending/reserved/active/completed/cancelled), paymentStatus (unpaid/paid/refunded/partial_refund)
  - startDate, endDate, pickupTime, returnTime, pickupMethod/pickupAddress, returnMethod/returnAddress
  - totalPrice, deliveryFee, extrasPrice, discountAmount, **latePickupDiscount**, **loyaltyDiscountAmount**, bookingSource, discountCode
  - sosReplacement, endedBySos, sosIncidentId, **rating/ratedAt**
  - createdAt, confirmedAt, pickedUpAt, returnedAt, cancelledAt, cancellationReason, contractUrl, paymentMethod
  - pickup/return lat/lng, branchAddress/City/Lat/Lng, **branchType** (`samoobslužná`/`obslužná`), trailerMotoId, stornoFee, refundAmount, motoLicenseRequired
  - 10 gear sizes (rider + passenger), ownGear, handoverProtocolStarted/Filled/PromptedAt, gearCollectedAt
  - originalStart/EndDate, modificationHistory, cancelledBySource, replacementForBookingId, actualReturnDate
- **Getters the ticket needs:** `displayStatus` (aktivni/nadchazejici/dokoncene/cancelled), `isSelfService`, `selfServiceLateGate`, `kioskReleaseAt`, `kioskReleasePending`, `protocolSigned`, `issuedAt`, `isHandedOver`, `ownGearEffective`, `inRentalTerm`, `sosAllowed`, `startDateInPast`, `dayCount`, `shortId`, `dateRange`.
- **Related providers:**
  - `doorCodesProvider(bookingId)`: RPC `get_my_door_codes`, which also returns withheld codes. Fields `codeType` (motorcycle/accessories), `doorCode`, `sentToCustomer`, `withheldReason`.
  - `bookingGateInfoProvider`: RPC `get_booking_gate_info` → `{has_gate, gate_code, locker_door}`.
  - `bookingRidesProvider(bookingId)`
  - `sosIncidentsProvider(bookingId)`
  - `pendingBookingFabProvider`: unpaid, 30-min window, re-checked every 5 s.
  - `googleReviewUrlProvider`
- **Actions:**
  - `rateBooking(id, stars)` writes `bookings.rating`; the inline stars are in reservation detail.
  - "Znovu rezervovat" (`bookAgain`) → `/moto/:motoId`.
  - "Obnovit" for a cancelled booking (`restoreBooking`).
  - Edit → `/reservations/:id/edit`.
  - Storno dialog.
- **Screens:** `/reservations` (list with filter `resFilterProvider`) and `/reservations/:id` (detail: tabs, codes card, pickup procedure, payment details, modification history, documents, rides of this booking).
- **Not yet in the model [CLIENT]:**
  - `motorcycles.box_number`. Live check: Husqvarna 701 SM at VN = **kóje 4**. All 7 VN bikes have boxes 1–7; the šatna is door 8.
  - `bookings.mileage_start/mileage_end`, for km per rental. `mileage_end` is optional, so there are gaps.

### 1.2 Moje jízdy: rides with MotoGo vs private rides

- **Tables:** `user_rides` and `user_ride_points` (STATE_1 lines 113–114). RLS is owner ALL and admin ALL; the public only sees rides through `get_public_rides`, which carries no identity. The anon key gets *permission denied* on it.
- **RPCs** (all SECURITY DEFINER):
  - `get_my_rides` (newest first, cap 300), `get_booking_rides`
  - `start_user_ride`, `append_ride_track`, `finish_user_ride`, `create_manual_ride`, `update_user_ride`, `delete_user_ride`
  - `save_ride_point`, `delete_ride_point`
- **Model `UserRide`** (`features/routes/ride_model.dart`):
  - id, **bookingId**, motoId, **motoName** (snapshot), name, description, **source** (auto/manual)
  - track `[[lat,lng,ts,kmh,alt]]` (≤ 4 000 points) and segments/gaps
  - startedAt, endedAt, **distanceKm**, durationMin, **movingSec**, idleSec, gapSec, lastFixAt, avgSpeedKmh, **maxSpeedKmh**, **elevationGainM**
  - **isRecording**, visibility (private by default, or public), status (approved/hidden), **coverImage**, points (start/end/stop with photos and a note)
  - Getters: `photoCount`, `stops`, `allPhotos`, `mapPoints`, `longestSegment`, `avgOverallKmh`.
- **The split:**
  - **S MotoGo** = `bookingId != null`. Recorded automatically when there is a running rental, location permission is granted, and the switch `mg_ride_autorecord` is on (it is on by default).
  - **Soukromá jízda** = `bookingId == null`. Started by hand via `rideRecorderProvider.startManual` ("Zaznamenat vlastní jízdu · Nemáš půjčenou motorku? Spusť si záznam trasy ručně…"), or built by hand with `create_manual_ride`.
  - Rides under 1 km are discarded.
- **Where it shows today:**
  - `/my-experiences`, tab "Vytvořené trasy" (`myExpRoutesTab`), as `RideCard`s with a map sketch, date, km, time, moving time, average speed, stops, photos and motoName.
  - `/ride/:id` (`RideDetailScreen`): 12 stats, edit name and description, public/private, stops with photos, share via `ride_share.dart`, delete.
  - Reservation detail section "PROJETÉ JÍZDY" (`BookingRidesSection`).
- **Live state:** `rideRecorderProvider` → `{enabled, recording, rideId, bookingId, points, manual}`. Shell has `RideRecorderWatcher`.
- **Home-ready aggregates [CLIENT]:**
  - Σ km, Σ moving time, ride count, longest ride, top speed, total climb, photo count
  - The same split into "s MotoGo" and "soukromé"
  - Last ride with a sketch from `mapPoints`
- **Not available:** countries ridden **[NEW-BE]**, or an approximation **[CLIENT]** from the `country` of visited catalogue POIs.

### 1.3 Moje zážitky: created routes, my places, local history

- **`user_saved_routes`** ("Moje trasy", max 200): RPCs `get_my_saved_routes`, `save_user_route`, `delete_user_route`. Model `SavedRoute`:
  - name, description, sourceRouteId, waypoints and their names
  - pois (snapshot of route/user/catalogue POIs), profile (recommended/fastest/shortest), distanceKm, durationMin, createdAt
  - Actions: navigate (`/route-nav-custom`) and edit (`/route-build` with `RouteBuilderArgs`).
- **`user_visited_places`** ("Moje místa"): RPCs `get_my_places` and `mark_place_visited`. A place is marked automatically when a navigation arrives within 200 m. Model `VisitedPlace`:
  - name, lat/lng, imageUrl, routeId/routeName, **firstVisitedAt**, **lastVisitedAt**, **visitCount**, and which kind of POI it is.
- **Local navigation history** (`activeRideProvider`, SharedPreferences `mg_active_ride` / `mg_ride_history`): `ActiveRide` holds name, routeId or a custom route, profile, reached stops / total, done, startedAt, updatedAt.
  - Actions: "Pokračovat v trase" and "Jet znovu".
  - Shell has `_RouteFab` while a route is active.
  - Device-only: lost on reinstall.
- **Screen `/my-experiences`:**
  - Dark header "Moje zážitky" with 2 tappable stats: `[n] objevených míst` · `[n] vytvořených tras`
  - 3 swipeable tabs:
    - 0 "Vytvořené trasy": create-route card, ride-recording switch, manual-ride card, ride cards, saved routes
    - 1 "Moje místa"
    - 2 "Moje trasy" (`myExpHistoryTab`, the local history). **Naming collision:** the labels for tabs 0 and 2 are confusing.
- **Saved or favourite catalogue routes: there is no favourites feature.** The only "save" is a copy into `user_saved_routes` from the builder.

### 1.4 Community submissions and reviews

- **Submissions** (`community_submit.dart`, `route_submit_screen.dart`, `poi_suggest.dart`) through the "+" menu in Trasy:
  - "Zaznamenat vlastní jízdu" (manual ride)
  - "Navrhnout trasu" → `routes` insert with `created_by=uid`, `status='pending'`, `is_active=false`
  - "Přidat místo" → `user_pois` insert, pending
  - Moderation happens in Velín.
- **Reviews and ratings:**
  - `route_reviews` (RPCs `submit_route_review`, `delete_route_review`, `get_route_reviews` with `my` and `is_mine`)
  - POI reviews (`submit_poi_review`, `get_poi_reviews`, `delete_poi_review`)
  - `poi_ratings` (`rate_poi`, `poi_rating_summary`)
- **Gaps:**
  - There is no "my submissions and their status" list. `user_pois` RLS lets the owner read their own rows **[CLIENT]**. Pending `routes` are not readable by their author (public read is `is_active=true` or admin) **[NEW-BE]** (an RPC or policy).
  - There is no "my reviews" list **[NEW-BE]**, a small RPC. It is not needed on Home.

### 1.5 Loyalty: rank, progress, leaderboard, level-up

- **`loyaltyStatusProvider`** (`features/loyalty/loyalty_provider.dart`) reads RPC `get_loyalty_status` → `{level, percent, rank_name, color_hex, qualifying_count (=points), next_rank_name, next_percent, next_color_hex, bookings_to_next (= POINTS to next = 2·pct − points), max_level, leaderboard_opt_in, nickname, bonus_points}`.
  - Fail-safe: it keeps the last good status of the same uid.
  - Rank names are localised via `rank_names.dart` / `translations_ext_35_loyalty_ranks.dart`.
- **Rules, verified in `20260917_loyalty_points_rank_floor_leaderboard.sql` and STATE_3:**
  - Points come from **completed** bookings made in the **app AND on the web** (`_loyalty_raw_points` has no `booking_source` filter): 1–6 days = 1 point, 7+ days = 2 points.
  - The rank never drops automatically: `profiles.loyalty_points_floor`.
  - A manual demotion from Velín is possible: `loyalty_points_penalty` via `admin_loyalty_adjust_rank`.
  - Bonus points: the monthly winner gets +4.
  - `level = min(20, ceil((points+1)/2))`: 0–1 points → 1, 2–3 → 2, 4–5 → 3, 6–7 → 4 … So **2 points = 1 rank**.
  - The **discount applies to app bookings only** (`validate_app_loyalty_discount`).
  - **Gear perk:** `loyaltyFreeGearLevel = 3` (`features/booking/booking_models.dart:403`). From rank 3, `extra-spolujezdec`, `extra-boty-ridic` and `extra-boty-spolu` cost 0 Kč, app only. Basic rider gear is free for everyone. **This confirms the brief's "passenger gear + boots free from rank 3".**
- **Live `loyalty_levels` (20 rows)** match the brief exactly: name, colour, `min_booking_order` 1, 3, 5 … 39.
- **Leaderboard:** `get_loyalty_leaderboard` → `{month, entries[{rank_pos, nickname, days, km, rank_gain, level, percent, rank_name, color_hex, is_me}], last_winner}`.
  - **Feature flag `loyalty_leaderboard` = false (live)**, so it is hidden in the app.
  - The nickname is synced to the server with `set_loyalty_nickname` when edited (`nickname_provider.dart`). The local copy is `mg_pilot_nickname`.
  - Opt-in setting: `set_loyalty_leaderboard_optin`.
- **Screens:**
  - `LoyaltyRankCard` (Home and Profil): name, "Level x z 20 · n bodů", next rank, "★ Platí jen pro rezervace v aplikaci", info sheet with rules.
  - `/loyalty` (`LoyaltyRanksScreen`): all 20 ranks, plus the leaderboard behind the flag.
  - Level-up overlay (§8).

### 1.6 Documents

- `docsGateChecklistProvider` reads RPC `get_docs_gate_checklist` → `{ok, id_front, id_back, passport, dl_front, dl_back, identity_ok, license_ok, date_of_birth, age_ok, expiry_ok, groups_ok, license_expiry, license_groups, required_groups, child}`. This is the same rule the server uses to release codes.
- `docsVerifiedProvider` (profile `id/passport/license_verified_at/_until`) is the fallback.
- `docsFabStatusProvider` drives the shell `_DocsFab` when there is a paid active/upcoming booking and docs are incomplete.
- **Screens:** `/docs` (`DocumentsScreen`, no shell), `/docs/scan?mode=` (scanner).
- **Home chip [EXISTS]:** "Doklady ✓ ověřeno" / "Chybí ŘP (rub)". Use the gate fields to say exactly which side is missing.

### 1.7 Messages, unread, notifications

- `adminMessagesProvider` streams `admin_messages` (realtime): `{id, title, message, type (sos_response/info/voucher/replacement/tow/thanks), read, created_at, title/message_translations}`.
  - `adminUnreadCountProvider` = the unread count. It drives the badge on the Home tab, the header hamburger and Profil "Zprávy".
- Message threads: `threadsProvider` (`message_threads` and `messages`, realtime) plus RPC `get_unread_thread_message_count`. Screens are `/messages` (`?n=<id>` expands a message) and `/messages/:id`.
- **Push** (`core/push/notification_handler.dart`) types: `booking` → `/reservations/:id`, `handover_protocol`, `door_codes` → `/messages?n=`, `sos`, `message`, `shop_order` → `/shop`. **There is no separate notification centre**: Messages is the inbox.

### 1.8 SOS

- **Routes (all inside the shell):**
  - `/sos` (`SosReportScreen`: type sheet → accident `/sos/accident`, theft `/sos/theft`, breakdown `/sos/breakdown`, service `/sos/service`; a link to AI; description)
  - `/sos/replacement`, `/sos/payment` (reuses `PaymentScreen`), `/sos/done` (`SosDetailScreen` with timeline)
- **Entry points today:**
  - Home red bar (only when a paid active/upcoming booking has `sosAllowed`)
  - Reservation card "🆘" button
  - Reservation detail (when active)
  - Profil → Pomoc (only with `hasActiveRentalProvider`)
  - The AI agent suggests SOS
  - Push `sos` (→ `/sos` during a rental, else `/messages`)
  - `_SosFab` for a pending replacement
- **Data:** `sos_incidents` (realtime) and `sos_timeline`.

### 1.9 AI agent

- `/ai-agent` (`features/messages/ai_agent_screen.dart`) calls the edge function `ai-moto-agent` with `booking_id` (active booking first, else the latest), language, history and photos (limited). It can propose SOS when `hasActiveRentalProvider`.
- **Reachable from:**
  - Home FAB **bottom-left** (Home only)
  - SOS report screen link
  - When open, the shell highlights the REZERVACE tab.
- **Not reachable from:** the Profil menu, or any other tab.

### 1.10 Shop, vouchers, invoices, contracts, payment methods

- **Shop** `/shop`, `/shop/:id`, `/cart`, `/checkout` and **gift voucher purchase `/voucher`**, which is only reachable from inside the shop screen.
  - **Live `eshop_visible = false`**, so the whole shop and voucher purchase are hidden from Profil today.
  - The cart FAB lives in the shell.
- **"Moje poukazy"** (vouchers bought by me, `vouchers.buyer_id`) are not shown anywhere in the app **[NEW-BE]**: RLS is unknown and an RPC is probably needed.
- **Invoices** `/invoices` and **contracts** `/contracts`, both from Profil.
- **Payment methods:**
  - `paymentMethodsProvider` / `defaultCardProvider` read `payment_methods (brand, last4, exp_month, exp_year, holder_name, is_default, stripe_payment_method_id)`.
  - Rows are synced from the Stripe customer by `webhook-receiver/stripe-card-sync.ts`.
  - Screen: Profil → Platební metody (`PaymentMethodsScreen`). **iOS has no manual card entry** (App Store rule).

### 1.11 Catalogue personalisation and branches

- Licence groups from `profiles.license_group[]` (`set_my_license_group`) filter "Motorky pro tebe".
- Branches: `/pobocky`, `/pobocky/:index`.
- Banner: `bannerProvider` (app_settings), shown as the shell marquee.

---

## 2. Live sample shapes (anon-readable)

Saved copies: `S/appdesign/research/_routes_0.json` and `_routes_1000.json` (id, name, branch_id, waypoints, km, min, difficulty, cover, status for all 1 174 routes).

| Table (anon) | Rows | Shape and notes |
|---|---|---|
| `branches` | 2 | `1111… MotoGo24 Mezná`, obslužná, Pelhřimov, 49.3464 / 15.2119 · `2222… MotoGo24 Velké Němčice`, samoobslužná, "Brno - Velké Němčice", 49.0043289 / 16.6721237. The column is `active`, not `is_active`. |
| `routes` | 1 174 approved | `{id, branch_id, name, description, route_type loop/poi, distance_km, duration_min, difficulty easy 91 / medium 101 / hard 8 (first 200), waypoints[{lat,lng,label}], geometry NULL everywhere, mapy_url, cover_image (all have one, media/routes-mirror/<sha>.jpg), images[], image_alts[], translations{lang:{name,description}}, countries[]}`. Countries: CZ 286, PL 184, SK 152, AT 115, IT 19 … |
| `route_pois` | 8 456 | `{id, route_id, name, description, lat, lng, image_url, images[], translations{…, surroundings}}` (no `category`) |
| `points_of_interest` (active) | 49 948 | `{id, category, name, country, region, image_url, …}`. Category counts: castle 9 711, water 7 591, lookout 6 551, sights 5 457, nature 4 925, spring 4 643, tech 4 262, aviation 3 722, military 2 067, moto 907, food 112. **≈ 466 within ~25 km of VN** (e.g. Zámek Lednice, Lednická kolonáda), **≈ 365 around Mezná** (e.g. Jindřichův Hradec, vyhlídka Karlov). |
| `motorcycles` at VN | 7 | `box_number` 1–7: Suzuki DL 650 V-strom 1, Kawasaki Z 900 2 (status maintenance), Benelli TRK 502 X 3, **Husqvarna 701 SM 4**, Honda Africa Twin 5, Jawa RVM 500 6, Aprilia SR GT 125 7. Each bike has 2–6 `videos` (Husqvarna has 6). |
| `user_pois` / `route_reviews` / `poi_ratings` | 0 / 2 / 1 | Community features exist but have almost no data yet, so Home should not lean on them. |
| `feature_flags` | live | `ai_assistant` true, `sos_system` true, `loyalty_leaderboard` false, `eshop_visible` false, `reservation_upsell` false. `self_service_delivery` has **no row** (= OFF). |
| `user_rides`, `user_saved_routes`, `user_visited_places`, `profiles`, `bookings` | — | Not readable with anon (correct). Use the schema in §1. |

**Nearest real routes for the VN mockup**, by distance of the route start from the branch. Prefix: `https://vnwnqteskbykeucanlhk.supabase.co/storage/v1/object/public/media/routes-mirror/`.
- **Rajhrad a Židlochovicko**: 10,6 km from the branch · 40 km · 55 min · lehká · 7 points · cover `5955e514a6557713724037e3172adc708f0e4d41.jpg` (id `760de205-b289-47d7-bd06-33acafe5fea7`)
- **Vodní krásy: Věstonická nádrž a okolí**: 12,5 km · 170 km · 290 min (4 h 50 min) · střední · cover `88cf0867c83db0b88ec60112c86feb4bd01ed3d2.jpg` (id `2281c259-897a-4408-994a-998d6a89bcb1`)
- **Za historií: Synagoga v Dolních Kounicích a okolí**: 16,9 km · 122 km · 174 min (2 h 54 min) · lehká · cover `57abf096e4807ec0cd48ec3bc8429cf7242df8f8.jpg` (id `b75ed442-bf58-481f-bcd0-5ffebb30aabd`)

---

## 3. What Home can show with existing data, and which screen each card opens

The order follows the owner's "Sultan" brief: he first, his business next, the catalogue last. Every card below is **[EXISTS]** or **[CLIENT]** unless flagged.

| # | Home block | Data (provider / field) | Tap opens |
|---|---|---|---|
| H1 | **Header**: rank ring around MG (colour `color_hex`, progress arc = points toward the next rank), "Ahoj, [přezdívka]", rank chip "Motorkář · sleva 3 %", bell with `[n]` | `nicknameProvider` → `profiles.loyalty_nickname` → first word of `full_name` (needs initcap: some names are stored in CAPITALS from the document scan), `loyaltyStatusProvider`, `adminUnreadCountProvider` | Ring and chip → `/loyalty`; name → nickname dialog; bell → `/messages` |
| H2 | **Ticket (hero)**, one state of S0–S10 from spec §7 | `reservationsProvider` getters, `doorCodesProvider`, `bookingGateInfoProvider` (`locker_door`), `docsFabStatusProvider`, `pendingBookingFabProvider`, `pendingSosFabProvider`, `rideRecorderProvider` | `/reservations/:id`, `/payment`, `/docs`, `/sos…`, maps |
| H3 | **SOS**: (a) a round red 48 px button in the S8/S9 ticket and a red header pill while `sosAllowed`; (b) "SOS · ROZPRACOVÁNO" ticket state S1 for a pending replacement; (c) outside a rental, no SOS on Home: Profil → Pomoc keeps today's rule | `sosAllowed`, `hasActiveRentalProvider`, `pendingSosFabProvider` | `/sos`, `/sos/replacement`, `/sos/done` |
| H4 | **"Tvůj svět" hub**: 2×2 tiles, each with a live number: **Moje jízdy** `[n] jízd · [km] km` · **Moje trasy** `[n]` · **Moje místa** `[n] objevených` · **Soukromá jízda** "Nahrát" (● live while recording) | `myRidesProvider` (Σ `distanceKm`), `mySavedRoutesProvider.length`, `myPlacesProvider.length`, `rideRecorderProvider` | `/my-experiences` (tab 0 / 1), or start/stop a manual recording in place |
| H5 | **"Moje jízdy" strip**: the last 3 rides as cards with a waypoint/track sketch, a "S MotoGo · Husqvarna 701 SM" or "Soukromá jízda" badge, km · time · photos | `UserRide.bookingId`, `motoName`, `mapPoints`, `distanceKm`, `totalMin`, `photoCount`, `coverImage` | `/ride/:id` (siblings passed via `extra`) |
| H6 | **Rank strip with savings**: "Level 3 z 20 · sleva 3 % na každou jízdu v appce" · "Výbava spolujezdce a boty máš zdarma" · bar 5/6 · "Ještě 1 bod → Stálý jezdec (4 %)" · "**S rankem jsi už ušetřil [n] Kč**" | `get_loyalty_status`; savings = Σ `loyaltyDiscountAmount` over own non-cancelled bookings **[CLIENT]** | `/loyalty` |
| H7 | **"Pokračuj v trase"** (only when a route is active) | `activeRideProvider.active` (reached / total) | `openRide()` → `/route-nav/:id` or `/route-nav-custom` |
| H8 | **"Trasy kousek od pobočky [název]"**: 3 sketches drawn from `waypoints`, km · time · difficulty · "[x] km od pobočky" | `routesDataProvider` sorted by distance of the route anchor from `pickupOriginProvider`, falling back to the last booking's branch, then all routes. **Not by `branch_id`** (§0.4) | `/routes/:id`; "Všechny" → `/routes-list` |
| H9 | **"Místa u pobočky"**: "U Velkých Němčic je [466] míst · objevil jsi [n]" plus 3 photo chips (castle / lookout / water) | `catalogPoisProvider` near the pickup origin, minus `myPlacesProvider` | `/routes` (Místa) or `/places-map` |
| H10 | **"Motorky pro tebe"** (filtered by licence) plus a **"Znovu: Husqvarna 701 SM"** chip for the most-rented bike | `motorcyclesProvider`, `profiles.license_group`; completed reservations grouped by `motoId` | `/moto/:id` (rebook opens with C9) |
| H11 | **"Jak se jelo?"** (S10, completed ≤ 14 days ago, `rating == null`) | `Reservation.rating`, `rateBooking` | Inline stars; "Ohodnotit na Google" → `googleReviewUrlProvider` |
| H12 | **Last unread message** (one line): "MotoGo ti píše: [title]" | `adminMessagesProvider` first unread | `/messages?n=<id>` |
| H13 | **Pobočky** (2 cards) | branches | `/pobocky/:i` |
| H14 | **AI FAB bottom-right**, persistent on every shell tab (the owner's ask) | none (edge `ai-moto-agent`) | `/ai-agent` (booking context included) |

**FAB stacking.** The shell already stacks bottom-centre pills: cart (8 px), booking/docs (25 px), route (25+58 px), SOS pending. The new AI FAB at bottom-right must:
- Sit above the bottom nav and stay clear of the centred pills (centre pills max width ≈ 358 − 2×(56+16)).
- Hide on `/payment`, `/sos/*` (SOS screens already link to AI), focused flows and while the keyboard is open, exactly like `hideBookingFabOn`.
- Replace today's scroll-to-top FAB, which the spec already drops in favour of re-tapping the active tab.

**Information that must stay reachable** (owner point 9) and where it lives after the redesign:
- Full bike list and filters → MOTORKY tab (spec §4.2).
- Rank info sheet rules → `/loyalty`.
- Local navigation history (tab "Moje trasy") → `/my-experiences`.
- Ride-recording switch → `/my-experiences` and the H4 "Soukromá jízda" tile.
- Docs FAB, booking FAB and route FAB → unchanged in the shell.

---

## 4. Needs new backend (flagged; none of it blocks the Home or express designs)

| ID | What | Why | Smallest change |
|---|---|---|---|
| B1 | **Instant level-up for profile-only rank changes** (admin +1 rank, monthly-winner +4 bonus, floor refresh) | `profiles` is not in `supabase_realtime`. Booking completion is already instant via the `bookings` stream. | Either add `profiles` to the publication (realtime still respects RLS: own row), or have `admin_loyalty_adjust_rank` / `loyalty_award_monthly_winner` insert an `admin_messages` row (already realtime and a good "VIP" message anyway). Without B1: shown on the next tap after the 45 s throttle, on resume, or by the 3-min poll. |
| B2 | **"Připravujeme ti motorku"** at staffed Mezná | No per-booking preparation flag exists. VN has a proxy: codes issued plus `box_number`. | `bookings.prepared_at` set from Velín (button "Motorka připravena"), plus an optional push. |
| B3 | **Countries ridden** | `user_rides` has no country | `countries text[]` filled in `_ride_finalize` (needs border data), or a client approximation from visited catalogue POIs (`points_of_interest.country`) **[CLIENT]**. |
| B4 | **Lifetime km with MotoGo from protocols** | Customer-side km today = GPS rides only, plus the optional `mileage_end`. `analytics_moto_rental_km()` is admin-only. | `get_my_rental_stats()` → `{rentals, days, km_protocol, bikes, saved_kc}`. Optional; the client can do everything except protocol km. |
| B5 | **"Moje návrhy" status** (pending routes) | `routes` RLS does not let the author read their pending rows | A small RPC `get_my_submissions()`. `user_pois` can already be read by its owner. |
| B6 | **"Moje poukazy"** | `vouchers.buyer_id` exists; no customer read path is documented | RPC `get_my_vouchers()` (code, amount, valid_until, status). |
| B7 | **Consent once per VOP version** (express booking) | Consents start unticked on every booking; `profiles.consent_vop` is a bare boolean with no version or time | `profiles.vop_accepted_version/_at` plus a version in `app_settings`. **Owner/legal decision first**; until then keep one combined checkbox line next to the pay button. |
| B8 | `feature_flags.ai_assistant` | Live flag (true) the app never reads | App-only: read it to hide the AI FAB if switched off. No SQL. |

---

## 5. Returning customer: what is already stored and how booking uses it

### 5.1 Stored once (registration, first booking, documents)

| Data | Where | Filled by |
|---|---|---|
| Name, e-mail, phone, address (street/city/zip/country), date of birth, ID number, licence number, licence expiry, licence group, consents VOP/GDPR/data processing | `profiles` | Registration step 1–3 (`register_screen.dart` → `app_save_full_profile` and a direct profile write); editable in Profil → Osobní údaje |
| Document photos and OCR verification (`id/passport/license_verified_at/_until`, `docs_verification_status`) | Storage + `profiles` + gate RPC | `/docs`, `/docs/scan` (Mindee OCR) |
| **Gear sizes** `gear_sizes = {rider:{helmet,gloves,jacket,pants,boots}, passenger:{helmet,gloves,jacket,pants,boots}, rider_own: bool}` | `profiles.gear_sizes` | Written after every app booking insert by `payment_screen.dart:546–590` (merged, never blanked); the web writes it too |
| **Saved cards** | `payment_methods` (+ `profiles.stripe_customer_id`) | Stripe webhook sync; Profil → Platební metody |
| Nickname | local `mg_pilot_nickname` + `profiles.loyalty_nickname` | Nickname dialog |
| Language, currency, ride auto-record, onboarding | local prefs + `profiles.language` | Settings |
| Preferred branch | `profiles.preferred_branch` | **Never written or read by the app.** Derive it from the last booking instead **[CLIENT]**. |
| Last bike, branch, pickup/return method, times, extras | `bookings` history | `reservationsProvider` **[CLIENT]** |

### 5.2 How the current flow uses it (Detail → `/booking` → `/payment`)

1. **Detail "REZERVOVAT"** (`moto_detail_page.dart:650`) builds a new `BookingDraft` with:
   - dates
   - `ownGear = gear_sizes.rider_own`
   - **rider helmet/gloves/jacket/pants from `gear_sizes.rider`**

   **Boots are never pre-filled** (incident 2026-09-28). The draft is then pushed to `/booking`.
2. **`/booking`** (`core/booking_form_widget.dart`) is one long scroll:
   - Header "Rezervace pro [moto]"
   - Datum (calendar, editable)
   - Čas (pickup time; self-service return is fixed at 23:59 and hidden)
   - Vyzvednutí (store / delivery; at self-service delivery is blocked while `self_service_delivery` is OFF)
   - Vrácení
   - Výbava a doplňky: basic gear free, **at least 1 piece or "Mám vlastní výbavu"**; passenger gear, rider boots and passenger boots are paid extras, **0 Kč from rank 3**; trailer only at staffed Mezná. The passenger sheet pre-fills from `gear_sizes.passenger` (`router.dart:1212`).
   - Cena
   - Promo kód
   - Poznámka
   - **Souhlasy VOP + GDPR (+ guardian consent for a kids' bike), unticked every time**
   - Blockers:
     - missing sizes
     - `profileCompletenessValidationProvider`: street/city/zip; for a licence bike also licence number and expiry, and the **licence must not expire before the rental ends** → button "Doplnit profil" → `/profile`
     - consents hint
   - CTA "POKRAČOVAT K PLATBĚ"
3. **`/payment`**:
   - countdown, bike gallery, price summary, upsell (flag OFF), `SavedCardPreview`, "🔒 Šifrovaná platba · Stripe PCI DSS Level 1", pay button
   - On pay: insert a pending/unpaid booking (`booking_source='app'`), then **off-session charge of the default card with no sheet** (`_chargeSavedCard`; SCA overlay only if 3DS is needed). Otherwise Payment Sheet / Apple Pay / Google Pay.
   - → `/success`
4. **Taps today for a returning customer who has sizes and a card:** dates (2) + Rezervovat + scroll + VOP + GDPR + Pokračovat + Zaplatit ≈ **7 taps over 2 screens**, plus scrolling past 6 sections.

### 5.3 Express booking (owner point 12): show only what is needed

- **Inputs actually needed per booking:**
  - bike and dates (already chosen in the Detail calculator)
  - pickup time (default 09:00; 12:00+ = late-pickup discount; at self-service the kiosk releases at 12:00)
  - pickup/return place (default the branch; delivery only at staffed Mezná)
- **Everything else collapses into ONE confirmed summary card "Máme to připravené" with a single "Změnit" per row:**
  - `✓ Ty: [jméno] · ŘP [A] platný do [datum]` (red blocker only if `profileCompletenessValidationProvider` returns an error, e.g. the licence expires before the rental ends)
  - `✓ Výbava: helma [L] · bunda [XL] · kalhoty [XL] · rukavice [L]`, or `✓ Vlastní výbava`. Source `gear_sizes`; step 2 opens **only if a size is missing or off-list** for this bike or branch (kids' sizes, self-service size range). Boots and passenger stay optional tiles, never pre-ticked; at rank ≥ 3 show them "zdarma" with the strike motion.
  - `✓ Platba: [Visa] •••• [4242]` (`defaultCardProvider`). Without a card: Apple/Google Pay or the card sheet, on the same button.
  - `✓ Doklady ověřené`. If they are not, **do not block booking** (today's rule: docs can be added later); add a quiet note "Kódy ti uvolníme po nahrání dokladů" for self-service, "Doklady potřebujeme před převzetím" for staffed.
- **Below the summary:**
  - Promo code and Poznámka stay as collapsed "+ Mám slevový kód" and "+ Poznámka".
  - Price receipt.
  - One consent line: "Souhlasím s [VOP] a [zpracováním údajů]" (until owner decision B7). A kids' bike adds the guardian line.
  - **One big pay button** "ZAPLATIT 10 189 Kč" in the rank glow.
- **Result:** dates (2) + Rezervovat + consent (1) + Zaplatit = **5 taps on 2 screens with no scrolling**. 4 taps if B7 is approved.
- **No backend change is needed** for this; it is the spec §5 stepper skipping plus merging the `/payment` pay block into step 3.

---

## 6. VIP concierge touches backed by real data (the "Sultán Suleiman" layer)

Copy uses tykání; `[…]` means an unknown value. None of these invents a promotion or a fact.

1. **Personal greeting by time of day.** "Dobré ráno, [přezdívka]" / "Dobrý večer, [přezdívka]". Source: nickname, else first name (initcap), plus the device clock. Header. [EXISTS]
2. **Rank as identity.** The ring, glow and button glow in `color_hex`, plus "Motorkář · sleva 3 % na každou jízdu v appce". Legend (level 20) gets the gold→orange gradient `legendGradientColors`. Header and CTAs. [EXISTS]
3. **Precise progress nudge.** "Ještě 1 bod → Stálý jezdec (4 %)" plus the true rule "Výpůjčka na 7 a víc dní = 2 body (celý rank)". Source: `bookings_to_next`, `_loyalty_raw_points`. Rank strip. [EXISTS]
4. **"Tvoje motorka čeká v kóji č. 4 · výbava za dveřmi č. 8".** Self-service, when codes are issued (`sentToCustomer`). Source: `motorcycles.box_number` from the reservation join (needs parsing) and `get_booking_gate_info.locker_door`. Ticket S6/S7. [CLIENT]
5. **Countdown that knows the rules.** "Za 5 dní · Kiosk ti motorku vydá v pá od 12:00". Source: `kioskReleaseAt`. Ticket. [EXISTS]
6. **"Výbavu máme ve tvých velikostech: helma [L] · bunda [XL]".** Source: booking sizes, else `gear_sizes`. Ticket "Více" sheet and express summary. [EXISTS]
7. **Return-day concierge** with the owner's fuel and wash rules. VN: "Dnes vracíš do 23:59 · plná nádrž netřeba, jen ať nesvítí rezerva · motorku vrať umytou · vrácení na kiosku rezervaci dokončí samo". Mezná: "Dnes vracíš do [čas] · tankovat ani mýt netřeba, jen ať nesvítí rezerva". This follows the 12. 10. fuel fact: the reserve light "should not" be on anywhere and "must not" at self-service. Never promise a full tank at pickup. Source: `displayStatus`, `endDate`, `isSelfService`. Ticket S9. [EXISTS]
8. **"S rankem jsi už ušetřil [n] Kč".** Source: Σ `loyalty_discount_amount` over own bookings; optionally plus `late_pickup_discount_amount` as a separate "výdej od 12:00". Rank strip / `/loyalty`. [CLIENT]
9. **Lifetime card.** "[n] výpůjček · [n] dní na motorce · [n] z [18] motorek vyzkoušeno". Source: completed reservations (`dayCount`, distinct `motoId`) and the active non-trailer fleet count. `/loyalty` or a Home hub tile. [CLIENT]
10. **Km milestones.** "Právě jsi s MotoGo přejel 1 000 km 🎉" (a one-shot toast, not chrome). Source: Σ `user_rides.distance_km` (GPS-recorded only); protocol km is B4. After a ride is saved. [CLIENT]
11. **Anniversary.** "Je to rok, co jsi s námi poprvé vyrazil na [Husqvarna 701 SM]". Source: the earliest completed `start_date` (or `profiles.created_at` for "rok v appce"). Header line on that day. [CLIENT]
12. **Birthday.** "Všechno nejlepší, [přezdívka]! Celý tým MotoGo24 ti přeje šťastné kilometry." Source: `profiles.date_of_birth`. Header on that day. No discount is promised (none exists). [EXISTS]
13. **Personal route picks near your next pickup.** "Na víkend od Velkých Němčic: Rajhrad a Židlochovicko · 40 km · 55 min · lehká". Source: `pickupOriginProvider`, `waypoints` distance, difficulty. H8. [CLIENT]
14. **Places you have not reached yet.** "U Velkých Němčic je [466] míst, objevil jsi [n] · nejbližší hrad: [Zámek Lednice]". Source: `get_pois_catalog` minus `get_my_places`. H9. [CLIENT]
15. **Live ride status.** "● Nahrávám jízdu · [km] km", then after the rental "Tvoje víkendová jízda je uložená · [km] km · [n] fotek · Sdílet". Source: `rideRecorderProvider`, the latest `UserRide`. Ticket S8 / H5. [EXISTS]
16. **"Znovu [Husqvarna 701 SM]?"** for the most-rented bike, plus the remembered pickup and return methods (dates empty, boots never pre-filled). Source: reservations history. S0 ticket link / H10. [CLIENT]
17. **Personal inbox line.** "MotoGo ti píše: [title]". Admin message types include `thanks` and `voucher`. Source: `admin_messages` unread. H12. [EXISTS]
18. **Rating thank-you.** Inline stars, then "Díky, [přezdívka]! Tvoje hodnocení čte celý tým." Source: `rateBooking`. S10. [EXISTS]
19. **Monthly leaderboard.** "Tento měsíc: #[n] · +1 rank". Behind flag `loyalty_leaderboard` (OFF; owner decision). `/loyalty`. [EXISTS, flagged]
20. **Always-on concierge.** AI FAB bottom-right ("Zeptej se, poradíme hned") with booking context, plus SOS one tap away during a rental. [EXISTS]

---

## 7. Mockup-ready Home copy for the sample customer (neděle 11. 10. 2026)

- **Header:**
  - "Dobré dopoledne, [přezdívka]"
  - chip "Motorkář · sleva 3 %"
  - ring #4ADE80 (or neon #74FB71 per spec §1), 5/6 points
  - bell [n]
- **Ticket S6:**
  - "ZA 5 DNÍ" · "✓ PŘIPRAVENO" · "Husqvarna 701 SM" · "MotoGo24 Velké Němčice · samoobsluha"
  - "pá 16. 10. 12:00 → ne 18. 10. 23:59 · 3 dny"
  - timeline Zaplaceno ✓ · Doklady ✓ · Kódy ✓ · Výdej ◉
  - "½ Kiosk ti motorku vydá v pá od 12:00"
  - VIP line "Tvoje Husqvarna stojí v kóji č. [4] · výbava za dveřmi č. 8" (box 4 is live data today; draw it as `[4]`, because the bike can be moved)
  - primary "KÓDY A POSTUP NA POBOČCE"
- **"Tvůj svět":** "Moje jízdy · [n] · [km] km", "Moje trasy · [n]", "Moje místa · [n] objevených", "Soukromá jízda · Nahrát".
- **Rank strip:**
  - "Level 3 z 20 · sleva 3 % na každou jízdu v appce"
  - "Výbava spolujezdce a boty máš zdarma"
  - "Ještě 1 bod → Stálý jezdec (4 %)"
  - "S rankem jsi ušetřil [n] Kč"
- **"Trasy kousek od Velkých Němčic"**, the 3 real routes in §2: Rajhrad a Židlochovicko 40 km · 55 min · lehká; Vodní krásy: Věstonická nádrž a okolí 170 km · 4 h 50 min · střední; Za historií: Synagoga v Dolních Kounicích a okolí 122 km · 2 h 54 min · lehká.
- **Places:** "U Velkých Němčic je [466] míst · objevil jsi [n]".
- **SOS on this date:** none on Home (the rental has not started). From 16. 10. 12:00 a red SOS appears in the ticket and as a header pill.

---

## 8. Guaranteed level-up animation: current mechanism, gaps and recommendations

**Existing** (`features/loyalty/loyalty_levelup_overlay.dart`, `loyalty_provider.dart`, `main.dart:383–398`):
- **Detection:** `loyaltyStatusProvider` re-fetches on:
  - every `onPointerDown`, via a global translucent `Listener`, throttled to 45 s (`loyaltyPollInterval`)
  - app resume (`didChangeAppLifecycleState`, forced)
  - a 3-min periodic timer in the foreground
  - any `reservationsProvider` change (forced; bookings are realtime)
  - `profileProvider` refresh
  - It is paused on the payment screen ("pokladna je zamčená") and while a celebration runs.
- **Baseline:** server `loyalty_get_celebrated` (5 s timeout), else local `mg_loyalty_last_level_<uid>`. The first observation only seeds the baseline and does not celebrate.
- **Show:** `showGeneralDialog` on `rootNavigatorKey`, `barrierDismissible: false`:
  - ~67 s montage (bike videos from `get_loyalty_celebration_motos`, else a photo) with music
  - old→new colour reveal on the MG logo, a "+N" badge, "MEGA POSTUP" when N ≥ 2
  - "Pokračovat" fades in
- **Commit:** only after close: local and server (`loyalty_advance_celebrated`, GREATEST). So the animation plays exactly once across devices and survives a kill or a reinstall.
- **Deferral:** while `onboardingOverlayActiveProvider` or `paymentScreenActiveProvider` is up, it returns without writing, and catches up on the next touch.

**Gaps against the owner's "whenever he taps anything, the animation must play":**
1. **Throttle latency:** a level-up that lands 10 s after the last poll waits up to 45 s of tapping.
   *Recommendation:* add a GoRouter listener (route change → `maybeRefreshLoyalty(force: true)` with a 10 s floor), and drop the pointer throttle to 15 s. That is 1 cheap RPC per 15 s at most.
2. **No realtime for profile-only changes** (admin +1, monthly winner) → B1.
3. **Deep links and push opens** do not involve a pointer-down. Resume covers a cold or warm start; the route listener (1.) covers in-app pushes.
4. **No reduced-motion path:** spec §2.8 asks for a static card (music optional). Add a "Přeskočit" to the dialog after 2 s, so a 67 s montage is never a trap. Keep "celebrated" written only after close.
5. **Multi-level queue:** today it is one dialog with "+N". Keep the single dialog, but make it step through each intermediate rank name and colour (e.g. Jezdec → Motorkář → Stálý jezdec, ~600 ms per step) before the hero. That meets "queue multiple level-ups into one sequence" without N dialogs.
6. **Rank theming must update in the same frame the dialog closes** (ring, CTA glow, nav indicator, cross-faded over 300 ms), so the customer sees the new colour applied app-wide as the payoff.

---

## 9. Inconsistencies found while reading

These matter for "nevypusť žádné informace" (keep all information), but wrong information must not be carried over as it is.

- **The `loyaltyRuleLong` text is stale and contradicts the live rule** (all 8 languages, shown in the `LoyaltyRankCard` info sheet). It says "Rezervace delší než 7 dní = 4 body → postup o 2 ranky najednou", while `loyaltyRulePoints` and the DB (since 2026-09-17) say 7+ days = 2 points = 1 rank. The `LoyaltyStatus` doc comment in `loyalty_provider.dart` is stale the same way. → Drop or fix the string in the redesign.
- **The `bookings_to_next` name is misleading:** the value is **points**, not bookings. Copy should say "bod/body".
- **`/my-experiences` tab labels:** tab 0 is "Vytvořené trasy" (rides, saved routes and the create button); tab 2 is "Moje trasy" (local navigation history). Rename in v2, e.g. "Jízdy & trasy" / "Místa" / "Historie navigace".
- **`MaterialApp.builder` forces `TextScaler.noScaling`** (`main.dart:380`): the OS font size is ignored app-wide. This is relevant for the bottom-nav label-fit work (labels only need to fit at 1.0×) and is an accessibility trade-off to mention to the owner.
- **`profiles.preferred_branch` is never used by the app**, so derive the "home branch" from bookings.
