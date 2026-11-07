# Audit · catalog + booking (v2, flag ON) — 2026-11-07

Scope: Motorky tab (full / grid cards, header, mode switch, chips, date sheet, filter sheet, calculator), bike detail (pager, photo hero, fullscreen gallery, specs, "Tvoje jízda", calendar, video, manual, dock), booking form `/booking` (lib/features/booking/v2/** + core/booking_form_* seams: header, recap, date card, time, pickup / return + address sheet + map picker, extras + size sheets, price, promo, note, consents, warnings, dock), and the in-area result states (no bike, detail gone / error / loading, list empty / error / loading). `/success` + `/payment*` belong to the pay_shop group (only cross-referenced).

Evidence (scratch `uxp/cb/`): boards rendered with Playwright at 390 (MotoKatalog default / compact header / grid / date presets / calendar sheet / filter sheet / loading / error; MotoDetail Termín vybraný / Bez termínu / Chyba sítě; Kalkulacka default; Booking default, expanded scroll). App rendered with `test/v2/render` (scale 1.0, reduced motion): every catalog + booking case in cs 360×780 with scroll shots, plus de + uk 320×690. Note: the render harness has no network images (photo areas show the fallback) — photo-quality items below come from code reading.

Owner-rule notes (design conflicts where the owner rule wins, NOT to be implemented):
- Board Detail "② Předání / ③ Výbava navíc · Změnit ▾" and Kalkulačka ④ expandable handover/extras → app keeps info-only rows (the detail / calculator do not own handover / extras state; owner 2026-10-22: time and handover are chosen once, in the booking form).
- Board Booking dock "ZAPLATIT · 10 189 Kč" → app keeps "POKRAČOVAT K PLATBĚ" (payment is the next screen; an honest label).
- Board Booking one consent checkbox → app keeps two (consentVop + consentGdpr are two stored consents; legal semantics).
- Board favourites heart (card + detail) and error copy "…i oblíbené ti zůstanou" → the app has no favourites; do not add the heart, drop "oblíbené" from copy.

## Coverage (LC) — flag ON

| Page / sheet / dialog / overlay / state | v2 look | Where |
|---|---|---|
| Motorky tab root (find mode: full cards, grid) | yes | catalog/v2/motorky_screen_v2.dart (router.dart:373 V2Switch) |
| Motorky header (title, count, rank chip, view toggle, mode switch, date pill, chips, CMS line) | yes, scrolls away (no compact bar) | catalog/v2/motorky_header_v2.dart |
| Motorky loading | **legacy look (spinner)** | motorky_screen_v2.dart:166 → MgLoadingView |
| Motorky error | legacy v2 look (centred, generic text) | motorky_screen_v2.dart:168-171 → legacy_state_looks.dart:28 |
| Motorky empty | yes | motorky_screen_v2.dart:261-292 |
| "Kdy jedeš?" date sheet | yes (structure differs from board) | catalog/v2/catalog_date_sheet_v2.dart |
| "Filtry" sheet | **frame v2, CONTENT OLD** (old chips neon-on-light, Material dropdowns for branch + sort, Material RangeSliders, checkbox) | catalog_filter_sheet_v2.dart:19 → widgets/moto_filter_panel.dart:268, 392, 436-475 |
| Calculator mode (steps, receipt, total, sticky) | yes | catalog/v2/calc/** |
| Calculator bike picker sheet | yes | calc/calc_step_moto_v2.dart:73 |
| Calendar day-tap feedback (range over busy) | Material SnackBar (themed) instead of §3.3 shake + note | widgets/availability_calendar.dart:141-146 |
| Bike detail + pager overlay | yes | catalog/v2/detail/** , detail_pager_v2.dart |
| Detail loading / gone / error | yes (skeleton) / legacy-v2 look / legacy-v2 look | detail_states_v2.dart, moto_detail_page.dart:152-195 |
| Fullscreen gallery (detail hero tap; also branch photos) | **NO (old: 38 px r10 ✕, Material icons, neon spinner)** | widgets/fullscreen_gallery.dart:26-141 |
| Video player (detail "Video") | **NO (Material icons, neon spinner, black)** | widgets/moto_video_player.dart:109,123,144 |
| Manual card | yes (seam) | widgets/manual_card.dart:35 |
| Booking form `/booking` | yes (full form, not the board's express card) | booking/v2/booking_form_view_v2.dart |
| Booking: no bike | yes (T1 info) | booking_form_view_v2.dart:310-333 |
| Booking: calendar open, warnings, dock blocker | yes | booking_date_v2.dart, booking_warning_v2.dart, booking_dock_v2.dart |
| Booking: time pickers | input v2, **popup menu = Material DropdownButton menu** | sections/time_v2.dart:84 → core/widgets/time_dropdown_field.dart |
| Booking: address sheet | yes | booking_ui_helpers.dart:252-268 + v2/addr_sheet_v2.dart |
| Booking: full-screen map picker | **NO (MotoGoColors, ElevatedButton, 38 px green square back)** | booking/widgets/map_picker.dart:24-35, 258-350 (platform file: userAgentPackageName) |
| Booking: passenger gear sizes sheet | **NO (old sheet, ElevatedButton, hard-coded text styles)** | core/booking_size_dialogs.dart:40-118 |
| Booking: boots size sheet | **NO** | core/booking_size_dialogs.dart:234-297 |
| Booking: "Odebrat" in size sheets | **NO (TextButton #B91C1C)** | booking_size_dialogs.dart:120-141 |
| Booking: promo code dialog (+ my voucher chips) | **NO (AlertDialog, title 16/800, error #EF4444 = SOS red, TextButtons)** | core/booking_form_promo_section.dart:61-110 |
| Booking: price section, promo row, note, consents | yes | booking_form_price_section.dart, v2/sections/promo_v2.dart, booking_note_v2.dart, booking_consents_v2.dart |
| `/success`, `/payment`, `/payment-result` | pay_shop group | features/payment/** |
| Unused: `showPromoBottomSheet` (old) | dead code, no caller | booking_ui_helpers.dart:889 |

## Improvements (prioritized)

### CB-01 · P1 · LC/L0 · Filter sheet content is the old panel
- **Where:** catalog/v2/catalog_filter_sheet_v2.dart:16-21 → catalog/widgets/moto_filter_panel.dart:93-110 (reset), 268-290 (sort Dropdown), 392-430 (branch Dropdown + checkbox look), 436-475 (RangeSliders), 477-495 (Dnes volné).
- **Now:** v2 sheet frame around the old panel: selected chips = neon fill on white (banned R5.8/R5.9), branch = Material dropdown with a checkbox glyph ("☐ Všechny pobočky ☐"), sort = Material dropdown menu, sliders neon track/thumbs, no "Resetovat" in the head, CTA "Zobrazit motorky · 4" sentence case.
- **Change:** New `catalog/v2/moto_filter_panel_v2.dart` = `MotoFilterPanelV2View` reached by a seam `if (MgV2.on(context) && widget.embedded) return MotoFilterPanelV2View(…)` in moto_filter_panel.dart build, fed by the SAME state fields and the SAME setters (category, licence group, branch, kW / sedlo / Nm / kg ranges, availableTodayOnly, sort, `_reset`). Board `vrstva: Filtr motorek`: sheet title "Filtr motorek" (17/800 → title 20/800 of MgSheet) with "Resetovat" `btnText` in `#B42318` next to ✕ 44; groups KATEGORIE / SKUPINA ŘP / POBOČKA / VÝKON… with 11.5/800 caps `#55705F` labels; chips 40 h r999 on `well` + 1 px `line`, selected = `btnInk` (`#1A2E22` fill, white 12.5/800 label, no neon); branches as chips ("Všechny pobočky", one chip per branch, same write as the dropdown); sort as one chip row (same values as the dropdown); "Jen dnes volné" as a MgSwitch row; range sliders themed ink: active track `#1A2E22` 4 px, inactive `well`, thumbs 24 white + 1.5 px `#1A2E22`, value label right 12.5/800 ("VŠE" → value range). Footer `MgBtnInk` caps "ZOBRAZIT {n} MOTOREK" (cs plural via the existing count helper; new key `v2UxCatShowN` ×8). Chip tap = `MgPress` (scale .97 + selectionClick); selection change `MgPop` 300.
- **Why:** The filter is the second most used control of the tab; today it is the only old-looking surface the customer opens from it.
- **Risk:** Low functional (same setters); the sliders must keep the same divisions / ranges; test every filter write against the old panel (widget test: same `catalogFilterProvider` result after each tap).
- **Shared primitives:** MgChoiceChip ink-selected variant (if not present), MgSwitch row, "ink range slider" theme (core/v2/widgets), sheet drag-to-dismiss (SH-16).

### CB-02 · P1 · LC/L1/L4 · Fullscreen gallery (the premium photo moment)
- **Where:** catalog/widgets/fullscreen_gallery.dart:26-36 (route), 63-73 + 86-92 (drag), 94-118 (pager + InteractiveViewer), 121-141 (✕ 38 r10), 144-169 (counter); opened from detail_hero_v2.dart:102/153 and branches/branch_photos_section.dart:51.
- **Now:** Old look; vertical drag-to-dismiss works but ALSO fires while zoomed (one-finger vertical pan of a zoomed photo dismisses the viewer instead of panning); no double-tap zoom; swiping pages while zoomed jumps the page; fade 200 ms only; spinner neon.
- **Change:** v2 view `catalog/v2/detail/gallery_view_v2.dart` behind a seam in `_FullscreenGalleryState.build` (same controller, `_current`, pop). Look: black page, ✕ = `MgV2Back(close: true, style: photo)` 44 at (16, top+8) per R6 viewer rule, counter = glass pill night@.8 + 1 px white@.22 "3 / 7" 12.5/800 centred top, thin segments row under it (as the hero). Gestures: one `TransformationController` per page; dismiss drag only when scale ≤ 1.01 (else let InteractiveViewer pan); double-tap toggles 1× ↔ 2.5× at the tap point (animate 300 `MgMotion.out`, instant when reduced); `PageView.physics = NeverScrollableScrollPhysics` while zoomed; drag-down scales the photo 1 → .9 and fades the black to 40 % (as today) and springs back 300 `MgMotion.spring` below the 100 px / 800 px·s⁻¹ threshold (unchanged values). Placeholder = `MgSkeleton` dark (no spinner). Route transition: fade 180 (`MgMotion.color`) + the Hero of CB-14 when available.
- **Why:** Customers pinch and double-tap bike photos by instinct; a viewer that closes when you try to look closer feels broken.
- **Risk:** Gesture arena (vertical drag vs scale) — gate by scale; reduced-motion end states; also used by branch photos (same improvement there).
- **Shared primitives:** "photo viewer v2" (core/v2 — used by two features), MgV2Back photo style, MgSkeleton dark, predictive back/pop.

### CB-03 · P1 · LC · Booking size sheets (passenger gear, boots)
- **Where:** core/booking_size_dialogs.dart:28-118 (`showPassengerGearSheet`), 120-141 (`_RemoveExtraButton`), 224-297 (`showSizeDialog`); opened from booking/v2/sections/extras_rows_v2.dart (rows with `opensSheet`).
- **Now:** Old sheet (white r20, own handle, hard-coded 15/800 and 12 px texts, raw Container size tiles, `ElevatedButton` "POTVRDIT" / "Vyber aspoň jednu velikost", red `TextButton` "Odebrat"); no ✕ 44.
- **Change:** Seam at the top of both functions: `if (MgV2.peek(ctx)) return showMgSheet(ctx, title: …, builder: (_) => SizesSheetV2(…), footer: …)` with the SAME `sizes` map, `_prefillPassenger` / `_lastBootsSize` prefill, `onExtrasUpdated` calls and pop. Body: hint line "Velikosti z minula — zkontroluj je" (`bkSizesFromLast`, tint `tintOk` T3 when prefilled), one labelled row per item (Helma / Rukavice / Bunda / Kalhoty or boot sizes) with size chips identical to the in-form size chips (`well` 44 h r12, selected `btnInk` + ✓ 16), footer `MgBtnInk` 52 "Potvrdit velikosti" (disabled look + amber line "Vyber aspoň jednu velikost" when none), tertiary `MgBtnText` red `#B42318` "Odebrat" only when `current != null`.
- **Why:** Sizes are the single most common blocker of the form (V2 §8); the fix path must look like the rest of the flow.
- **Risk:** Low; keep the `isScrollControlled` scroll for 4 rows at 320 + large text; widget test that confirm / remove produce the same `List<SelectedExtra>` as before.
- **Shared primitives:** MgSheet (+ drag-to-dismiss), size chip (already in extras_v2 — move to booking/v2 parts if needed).

### CB-04 · P1 · LC/L3 · Promo code dialog
- **Where:** core/booking_form_promo_section.dart:61-110 (+ `apply` 30-58), opened from v2/sections/promo_v2.dart:52 via `_openPromoDialog`.
- **Now:** Material `AlertDialog`: title 16/800, error text `#EF4444` 12 px (SOS red used as error — V22 §2.2 error on light = `#B42318`), r10 outlined field, `TextButton` actions, vykání-free but off-system.
- **Change:** Seam inside `_openPromoDialog`: under v2 open a light MgSheet (keyboard-safe, `isScrollControlled`) titled "Slevový kód nebo poukaz" with the SAME `ctrl`, `loading`, `error`, `apply(ctx, ss)` and `MyVoucherChips` (restyled as `well` chips with tag icon, tap fills the field as today); field = v2 input (1.5 px `#7C958A`, focus 2 px `#0D6E0D`, caps); error = T3 error banner (`#FDECEC` + 1 px `#F3B5AF`, ✕ icon, `#B42318` 12.5/600) with the existing message; footer `MgBtnInk` "Použít" (spinner inside while `loading`, disabled while running) + `MgBtnText` "Zrušit". Board Booking `kodVysledek` variants map 1:1 to the existing result messages.
- **Why:** A discount moment should feel rewarding, not like a system alert; red-as-SOS reads as danger.
- **Risk:** Low (same apply logic); keyboard + sheet insets; dialog → sheet changes the dismiss gesture (drag down = cancel, same as "Zrušit").
- **Shared primitives:** MgSheet, MgInput v2, MgStateBanner T3 error tone, button spinner.

### CB-05 · P1 · LC · Full-screen address map picker
- **Where:** booking/widgets/map_picker.dart:24-35 (push `fullscreenDialog`), 250-350 (top gradient, 38 px green square back, white search card, `ElevatedButton` confirm); used by pickup / return address (booking_form_pickup_section.dart:59, return_section.dart:59) and other areas.
- **Now:** Old look inside the v2 flow.
- **Change:** v2 chrome per DESIGN_V22 §6.4 `shared/addr-picker`: back/close = `MgV2Back` photo style 44 at (16, top+8); search / result card = white r16 `shCard`, "Hledám adresu…" with a 16 px spinner, resolved address 15/800 ink + city 12.5/600 `#4A6B5A`; "Moje poloha" white disc 48 + `line` + `#0D6E0D` crosshair bottom-right above the card; ONE primary `MgBtnInk` 52 "Potvrdit adresu" (spinner inside while resolving); pin = brand pin (no new colours). Same `_MapPickerState` logic, same `MapPickerResult`. Platform file: edit by hand in both trees, keep only the `userAgentPackageName` hunk different.
- **Why:** Delivery is a paid upsell; the map must feel like part of the premium flow.
- **Risk:** Map gestures unchanged (no new gesture); platform hunk discipline.
- **Shared primitives:** MgV2Back photo style, MgBtnInk with spinner.

### CB-06 · P1 · L3 (disclosure) · Branch type + address are missing where the bike is shown
- **Where:** moto_card_full_v2.dart:199-206 (pin + name only), moto_card_grid_v2.dart:120-123 (meta 1 line ellipsis, cut "Supermoto · Velké N…"), detail_hero_v2.dart:178-188 ("Pobočka: Mezná, Pelhřimov"), detail_more_v2.dart:109 (branch row without street), booking/v2/booking_recap_v2.dart:22-24 ("Pobočka: Velké Němčice, Velké Němčice").
- **Now:** The customer never sees "s obsluhou" vs "samoobsluha nonstop" until deep in the booking form; grid cuts the branch; detail shows city, not address; recap duplicates the city.
- **Change (display only, `Motorcycle.branchType` already loaded, keys exist ×8: `v2CalcBranchStaffed` "s obsluhou", `v2CalcBranchSelf` "samoobsluha nonstop"):** full card tag row "📍 Mezná · s obsluhou" (board); grid meta on 2 lines: line 1 category 11.5/700, line 2 "Mezná · s obsluhou" (no ellipsis; MgWordFit); detail hero line "MotoGo24 Mezná · s obsluhou" 14/700 white@.94 (board `.hero` meta; chevron/tap to the branch = owner decision); "Víc o motorce" branch row title "Pobočka Mezná", sub = `branchAddress` ("Mezná 9, 393 01 Pelhřimov"); booking recap line "Pobočka Mezná · s obsluhou". Helper `catBranchLine(tr, moto)` in catalog/v2/catalog_text.dart.
- **Why:** Owner disclosure rule (branch + type + address always visible); self-service changes how the customer picks up (kiosk codes) — it must not be a surprise.
- **Risk:** None functional; text fit at 320 (de "mit Personal", uk) — render matrix.
- **Shared primitives:** none.

### CB-07 · P1 · L0/L3 · Motorky: compact sticky bar after scroll
- **Where:** catalog/v2/motorky_screen_v2.dart:144-181 (header is a plain sliver, scrolls away).
- **Now:** After the first card the customer has no date pill, filter or calculator entry; changing the dates means scrolling back up through 600 px cards.
- **Change:** Board prop `hlavicka: Po posunutí · kompaktní lišta`: once the header's date pill leaves the viewport, a pinned night-glass bar (`night`@.96 + blur 14 → or solid `#0A1F14` if blur budget, height 64 + status bar) slides down 300 `MgMotion.out` with: date pill (same `_DatePill` look, compact "pá 23.–ne 25. 10." + "3 dny" chip) → `showCatalogDateSheet`; 44 filter disc with badge → `showCatalogFilterSheet`; 44 calculator disc → `_setMode(CatalogMode.calc)`. Find mode only. Reduced motion: appears without slide.
- **Why:** The date is THE input of the catalogue (price per card depends on it); keeping it one tap away all the way down is the shortest path to a dated price.
- **Risk:** Same actions as the header; status-bar icon colour (MgStatusBar dark); AI FAB / origin chip must not overlap (8 px rule).
- **Shared primitives:** "pinned compact bar" slot in MgPage (generalise MgPinnedBack: `pinnedBar` builder shown after header extent).

### CB-08 · P1 · L2 · Motorky list loading = spinner
- **Where:** motorky_screen_v2.dart:166 (`MgLoadingView`).
- **Now:** Bare green spinner on canvas under the dark header (board `stavDat: Načítání` = dark card skeleton).
- **Change:** Full mode: one dark skeleton card of the real card height (`h`) — pill 30×120 top-left, tag row, title bar 60 % width, 3 spec pills, price block + CTA placeholder — plus the moto icon + "Načítám motorky…" 12.5/700 `#9FC4B1` centred; grid mode: 4 grid skeletons (photo 150 + 3 text bars). One shimmer 1.2 s (`MgShimmer`, static @.55 under reduced motion). Keep `MgLoadingView`'s 15 s "trvá to déle" + retry by wrapping (slow → its existing T3 under the skeleton).
- **Why:** Skeleton = the page is already there; spinner = waiting.
- **Risk:** None (loading branch only).
- **Shared primitives:** MgSkeletonCard (dark, full-card variant).

### CB-09 · P1 · L1 · Calendar: swipe to change month (and the hidden bike swipe)
- **Where:** core/v2/calendar/trip_calendar.dart:73-99 (grid, no gesture); detail pager catalog/v2/detail/detail_pager_v2.dart:45-53 (outer horizontal PageView between bikes).
- **Now:** A horizontal swipe on the calendar does nothing in the booking form / date sheet, and on the bike DETAIL it swipes the whole page to the NEXT BIKE (customer loses the bike + dates context while trying to see next month). Month change is an instant swap.
- **Change:** In TripCalendar wrap the weekday row + grid in `GestureDetector(onHorizontalDragEnd: v < -300 → onNextMonth, v > 300 → onPrevMonth)` (only when the callbacks are non-null; this recognizer wins the arena over the outer bike PageView inside the calendar box). Month swap via `AnimatedSwitcher` keyed by month: slide 24 px + fade, 210 ms `MgMotion.tab`, `MgMotion.out`, direction by sign; reduced motion = instant. ‹ › discs unchanged.
- **Why:** Everybody swipes calendars; today the instinct either fails or throws the customer to another bike.
- **Risk:** Gesture conflict resolved in favour of the calendar inside its box only; widget tests with `tester.fling` (next / prev month, detail pager index unchanged), reduced-motion end state.
- **Shared primitives:** "calendar month swipe" in core/v2/calendar (used by detail, date sheets, booking, calculator, reservation edit).

### CB-10 · P1 · L3/L5 (disclosure) · Booking recap = the trip, not the price list
- **Where:** booking/v2/booking_recap_v2.dart:39-75.
- **Now:** Recap card says "od 2 811 Kč/den · záloha neúčtována" + "Pobočka: Mezná, Pelhřimov"; the dates sit in the next card, times / handover further down.
- **Change:** Board ticket `.tk`: photo thumb 96×64 r10 (Hero target, CB-14) · bike 15/800 · line 1 "pá 23. 10. → ne 25. 10." 14/800 + "3 dny" chip `btnInk` 11.5/800 · line 2 "12:00 ½ → 19:00 · pobočka Mezná · s obsluhou" 12.5/600 `#4A6B5A` (pickup/return time + method from the draft; delivery → "přistavení"). Without dates: line 1 "Vyber termín" `#0D6E0D` (tap = existing `_openDates`). Keep "bez kauce" as a trust chip in the dock / price card, not here.
- **Why:** The first card must confirm WHAT the customer is buying (key info always visible at first glance).
- **Risk:** Display only (all values exist in `draft`); text fit 320 de/uk.
- **Shared primitives:** none.

### CB-11 · P1 · L0/L3/L5 · Booking "Máme to připravené" express disclosure
- **Where:** booking/v2/booking_form_view_v2.dart:211-303 (all sections always expanded: date, time, pickup, return, gear sizes grid, extras, price, promo, note, consents ≈ 6 screens at 360).
- **Now:** A returning customer whose sizes come prefilled still scrolls through every input; board = one card with ✓ rows and "Změnit".
- **Change (view only, same section widgets inside):** (a) "Termín a předání" summary row under the recap (✓ disc, "pá 23. 10. 12:00 → ne 25. 10. 19:00 · na pobočce", "Změnit ⌄") expanding in place (`MgAnimatedSize` 300 + chevron 180°) to the existing date / time / pickup / return sections; (b) "Máme to připravené" white card (shield icon tile, rank chip "Motorkář · sleva 3 %") with rows Výbava (size mini-chips "[M] [L] [L] [M]" or "Vlastní výbava") and Navíc ("spolujezdec + 2× boty · zdarma"), each "Změnit ⌄" expanding the existing extras section; (c) promo + note as two chip buttons side by side (board), expanding the existing promo / note cards; (d) price section stays visible (total is key info). Auto-expand rule: any section that has a blocker (no dates, missing sizes, error kind, consent) is expanded and the dock "Doplnit" scrolls to it (existing `_blocker` targets). No new data: no "Ty" / "Platba" / "Doklady" rows (payment method + docs belong to the payment step → owner decision).
- **Why:** V2 §8: ≈ 5 taps, no scrolling for a returning customer — the biggest conversion lever of the flow.
- **Risk:** Medium (hiding a required input) → guarded by the auto-expand rule + tests: every `BookingErrKind` / missing size / consent state renders its section expanded; draft writes unchanged.
- **Shared primitives:** MgAnimatedSize, summary row (✓ disc + value + "Změnit ⌄") — make it a booking/v2 part.

### CB-12 · P2 · L1/L0 · Detail bike pager: arrows in the counter pill
- **Where:** catalog/v2/detail/detail_pager_v2.dart:56-80.
- **Now:** "1 / 3" pill only; on a multi-photo hero the photo pager wins every horizontal swipe, so the next bike is reachable only by swiping below the photo — undiscoverable.
- **Change:** Board pill "‹ 1 / [n] ›": two 44 hit-area chevrons inside the glass pill (night@.8, 1 px white@.22) calling `controller.previousPage / nextPage` (300 `MgMotion.out`; jump when reduced) — the same action as the swipe.
- **Why:** Browsing similar bikes is a conversion path; it needs a visible control.
- **Risk:** None (same controller).
- **Shared primitives:** none.

### CB-13 · P2 · L0/L3 · Detail hero availability pill
- **Where:** detail_hero_v2.dart:146.
- **Now:** "Dnes volná" only when `availableToday`, even when the customer has dates.
- **Change:** With dates, booked loaded and not busy → "● Volná v tvém termínu" (key `v2CatFreeInRange` exists) with the ping (the screen's one live indicator); busy → no pill (the amber warning speaks); no dates → as today.
- **Why:** Confirms the dates fit before the price.
- **Risk:** Display only (needs `busy` + `bookedAsync` passed to the hero).

### CB-14 · P2 · L4 · Shared-element photo flight card → detail → booking
- **Where:** moto_card_full_v2.dart:126-143, moto_card_grid_v2.dart (photo), detail_hero_v2.dart:52-76, booking_recap_v2.dart:40-55.
- **Now:** No Hero anywhere in the app; push is the platform default.
- **Change:** V2 §6.3 / §6.1: `Hero(tag: 'moto-photo-${moto.id}')` on the card's current photo, the detail hero photo (first frame) and the booking recap thumb; `flightShuttleBuilder` = the same `MgImage` cover; 350 ms `MgMotion.hero` `MgMotion.emphasized`; `HeroMode(enabled: !MgMotion.reduced(context))`. Unique tags per visible card (grid + full never both mounted).
- **Why:** The photo the customer tapped "becomes" the page — the premium signature move.
- **Risk:** Detail pager (loop index) → only the initial page carries the tag; Android NoTransitionPage for /booking (SH-14) disables the flight there until fixed.
- **Shared primitives:** "photo Hero" helper (tag + shuttle + reduced motion) in core/v2/motion.

### CB-15 · P2 · L2 · Photo placeholder flash + backdrop swap
- **Where:** moto_card_full_v2.dart:118, detail_hero_v2.dart:93 (cover backdrop `MgImage` without placeholder → default light grey `MotoGoColors.g100`).
- **Now:** On a dark card / hero the blurred backdrop starts as a light-grey block, then pops dark; on every photo swipe the backdrop URL changes and flashes again.
- **Change:** placeholder `ColoredBox(MgColors.panel)` for every image on dark surfaces; backdrop keyed by page inside `AnimatedSwitcher` 180 `MgMotion.color` (instant when reduced); keep `thumbWidth` 400 / 900 / 1000.
- **Why:** No flashes = premium.
- **Risk:** None.
- **Shared primitives:** "photo fade-in on dark" (MgImage `dark: true` default placeholder, or a v2 wrapper).

### CB-16 · P2 · L0/L5 · Booking dock context
- **Where:** booking_form_view_v2.dart:294-307, booking/v2/booking_dock_v2.dart:30-63.
- **Now:** "Tvoje cena · 3 dny" + price.
- **Change:** Board: "Tvoje cena · 3 dny · ušetříš 1 585 Kč" — saving = list rental + list extras − total from the SAME `bd` (display only); hidden when 0; fits 2 lines (blocker keeps priority).
- **Why:** The king sees what his rank earned him right next to the button.
- **Risk:** Display only; the figure must equal the price section's savings line.

### CB-17 · P2 · L0 · Detail dock "Rozpis ▴"
- **Where:** catalog/v2/detail/detail_dock_v2.dart:61-85.
- **Now:** Context line only.
- **Change:** Board: right of the context line `MgBtnText` neon on dark "Rozpis ▴" → scroll to the total box (`MgPinnedBack.reveal`) and open its breakdown (the existing `_breakdown` toggle; lift it to the view as a ValueNotifier). Only when a price is shown.
- **Why:** Trust: the price breakdown is one tap away from the CTA.
- **Risk:** None (existing toggle).

### CB-18 · P2 · L1 · Pull-to-refresh on the Motorky list
- **Where:** motorky_screen_v2.dart:175-181 (MgPage without `onRefresh`), refresh action `_reloadMotos` 105-108.
- **Change:** `onRefresh: () async { _reloadMotos(); await ref.read(filteredMotorcyclesProvider.future).catchError((_) => <Motorcycle>[]); }` in find mode only (list keeps showing, `skipLoadingOnReload`).
- **Why:** The existing reload, reachable by instinct.
- **Risk:** RefreshIndicator over a dark header — use the brand colours of MgPage (already neon / onNeon); iOS pull-down overscroll colour (SH-17).
- **Shared primitives:** brand pull-to-refresh (exists in MgPage).

### CB-19 · P2 · L0 · "Kdy jedeš?" date sheet like the board
- **Where:** catalog/v2/catalog_date_sheet_v2.dart:21-31 (footer "Hotovo"), 63-86 (preset chips, `TripSummaryRow`), core/v2/calendar/trip_calendar_parts.dart:148 (`TripSummaryRow` wraps "3 dny" to its own line at 360).
- **Change:** Summary as the board well box: two labelled tiles "VYZVEDNUTÍ pá 23. 10." → "VRÁCENÍ ne 25. 10." + "3 dny" `btnInk` chip right (bump on change); helper with dot "Klepnutím na jiný den termín změníš" (existing `v2CalTapToChange`); footer `MgBtnInk` caps "POUŽÍT TERMÍN · 3 DNY" (`v2HomeDateUse` + days; "Hotovo" when no range) + `MgBtnText` "Zrušit termín" (= `catClearDates`) when dates; presets keep their writes (board list rows with icon tile + ✓ are optional — keep chips if the 2-step list feels slower).
- **Why:** Board parity and a CTA that states the result.
- **Risk:** None (same writes).
- **Shared primitives:** TripSummaryRow board variant (core/v2/calendar).

### CB-20 · P2 · L0/L5 · Header quick chips (categories with counts)
- **Where:** motorky_header_v2.dart:129-154.
- **Now:** "Filtry · Všechny pobočky · branches".
- **Change:** Board chip row: "Filtry (n)" · "Vše 22" · category chips with counts ("Cestovní/Enduro 11", "Naked 2" … from the loaded, date-filtered list — display only) · branch chips at the end. Category chip tap = the SAME category write as the filter panel; selected = neon on dark (header is dark). "Jen volné" only if it maps 1:1 to `availableTodayOnly` without dates (else owner decision).
- **Why:** One-tap narrowing without a sheet.
- **Risk:** Same writes; long chip row scrolls horizontally inside the header (no conflict: header is not a pager).

### CB-21 · P2 · L0/L3 · Error states of the area (list, detail)
- **Where:** motorky_screen_v2.dart:168-171, moto_detail_page.dart:186-195 → core/v2/states/legacy_state_looks.dart:28-72.
- **Now:** Centred block, generic why "Nastala neočekávaná chyba. Zkus to prosím znovu. Když to nepůjde, napiš nám na info@…", "Zavolat MotoGo24".
- **Change:** Stavy 8.6 (board): list = white card on canvas, title "Motorky se nepodařilo načíst", why "Server teď neodpovídá, nebo je slabý signál. Termín a filtry ti zůstanou." (no "oblíbené"), hint "Zkus to znovu za chvilku.", `MgBtnInk` "ZKUSIT ZNOVU" (refresh icon), "Technické detaily ▾", support row "Pomůžeme ti: Zavolat · Napsat nám"; detail = T1 light page with back (light style), steps card "Jak to vyřešit", dock "Zkusit znovu" + "Zpět na Motorky". New keys ×8 (`v2UxCatErr*`).
- **Why:** Every state says what / why / how (owner R2).
- **Risk:** Coordinate with SH-28 (shared error look) — area texts only here.
- **Shared primitives:** MgErrorView T1/T3 template with steps + tech details + support row.

### CB-22 · P2 · LC/L0 · Booking time pickers
- **Where:** booking/v2/sections/time_v2.dart:84 → core/widgets/time_dropdown_field.dart.
- **Now:** v2-styled field but the opened menu is a Material dropdown popup (old menu, 96 items for 15-min steps).
- **Change:** Under v2 the field opens a light MgSheet "Čas vyzvednutí" with hour chips (one row per allowed hour, 4 minute chips 00/15/30/45; ½ tag on 12:00+) — tap = the same `onChanged('HH:MM')`, sheet closes; the current value preselected; scroll to it on open.
- **Why:** Board shows time chips; menus of 96 rows are fiddly with thumbs.
- **Risk:** Same allowed values as the dropdown (reuse its value list); test that every value maps 1:1.
- **Shared primitives:** MgSheet, MgChoiceChip.

### CB-23 · P2 · LC · Video player controls
- **Where:** catalog/widgets/moto_video_player.dart:109 (spinner), 116-130 (mute), 136-150 (counter).
- **Change:** Seam: v2 controls = glass discs 44 night@.8 + MgIcon volume, counter pill as the hero pills, skeleton instead of the neon spinner; same controller / mute / next logic.
- **Risk:** None.

### CB-24 · P2 · L1/L4 · Calendar feedback per §3.3 / §3.6
- **Where:** catalog/widgets/availability_calendar.dart:110-113 (busy / past tap = silent return), 140-146 (range over busy = Material SnackBar); core/v2/calendar/trip_day_cell.dart:126-133 (band 140 ms).
- **Change:** In the v2 view wrap `onTapDay`: busy cell → `showMgToast("Tento den je motorka půjčená")` (feedback only, then call through so the State still returns); range over busy → `MgShake` 300 on the tapped end cell + inline T3 note "V termínu je obsazený den {date} — vyber jiný den vrácení" above the grid instead of the snackbar (State still refuses as today); band grow 300 ms ease per §3.6 (20 ms per cell, cap 200). Haptic `selectionClick` on start / end.
- **Why:** Feedback instead of silence; one visual language.
- **Risk:** The snackbar lives in the old State — keep it for flag OFF, suppress under v2 via a view callback.
- **Shared primitives:** showMgToast, MgShake (exist).

### CB-25 · P2 · L0/L4 · Calculator detail fidelity
- **Where:** calc/calc_body_v2.dart:199 (branch chips `Wrap` → 2 rows at 360), calc/calc_step_moto_v2.dart:141 (selected bike thumb 96×64), calc head card.
- **Change:** Branch = one-row segmented on a `well` track (.8/1/1.15 fr, min-h 58, selected `btnInk` + neon title), titles may wrap to 2 lines; selected bike = board photo card (full width, photo 16:9 r16, "● Volná ještě dnes" pill on the photo, name 17/800, meta, rank price `#0D6E0D` + struck list, "Detail motorky →" `btnText`); head without a card (eyebrowDark + rank chip on one line, H2, lead on canvas).
- **Why:** The calculator sells the bike — a stamp-size thumb does not.
- **Risk:** None (same state); image placeholder per CB-15.

### CB-26 · P2 · L0/L5 · Detail without dates: weekend presets
- **Where:** detail_trip_card_v2.dart:168-207.
- **Change:** Under the two date tiles a horizontal row of `MgChoiceChip`s "Nejbližší víkend · 16.–18. 10." / "Další víkend · 23.–25. 10." (same `catWeekend` as the date sheet) → `onRangeSelected(s, e)` (existing). The calendar stays one tap away ("Vyber" tiles). The board's amber "už jedeš" variant needs own-booking data → owner decision.
- **Why:** One tap from "how much?" to a dated price.
- **Risk:** Presets must respect busy days (the page's own `detailRangeBusy` warning already handles a carried busy range).

### CB-27 · P3 · L4 · Mode switch motion + drag
- **Where:** motorky_screen_v2.dart:156-174, catalog_mode_switch_v2.dart:53-60.
- **Change:** Content swap through `AnimatedSwitcher` (fade + 12 px rise, 450 `MgMotion.enter`) per V21 §3.1; the thumb follows a horizontal drag on the switch and settles to the nearer side (= `onChanged`).
- **Risk:** Drag only on the switch itself (no content swipe: cards have photo pagers).

### CB-28 · P3 · L4 · Ken Burns once + card entrance
- **Where:** detail_hero_v2.dart:52-76, moto_card_full_v2.dart:126-143, motorky_screen_v2.dart:238-256.
- **Change:** One-shot 8 s slow zoom (1 → 1.06) on the detail hero's first photo and on the first full card in view (V2 §6.1 / §7); one-shot `MgReveal` stagger (70 ms) on the first 3 cards per session. Reduced motion: none.
- **Shared primitives:** extract Ken Burns from MgPhotoHero (mg_photo_hero.dart:49-51) into `MgKenBurns`.

### CB-29 · P3 · L0 · Rank logo in the area headers
- **Where:** motorky_header_v2.dart:64-114, booking/v2/booking_header_v2.dart:35.
- **Change:** Boards show the logo in the rank ring + level badge (Motorky, Kalkulačka, Booking). Extract `_LogoRow` ring from home/v2/home_header_v2.dart:214-262 into core/v2 `MgRankLogo` (52, ring + arc + badge, tap → ranks as on Home) and place it left of the title (Motorky) / right of the title (Booking).
- **Shared primitives:** MgRankLogo.

### CB-30 · P3 · L2 · Small display fixes
- motorky_screen_v2.dart:196-199: the canvas eyebrow "3 VOLNÝCH MOTOREK · 3 DNY" between header and full cards is not on the board and repeats the header count → drop in full view (keep in grid).
- moto_card_grid_v2.dart:135: price "11 893 Kč / 3 dny" wraps → value 17/800 + unit 11.5/700 on one line (MgWordFit).
- calc/calc_free_list_v2.dart:143-151: bike names break into 3 lines at 360 ("Husqvarna / 701 / Supermoto") → price under the name below 360 dp.
- detail_more_v2.dart:66-79: Popis 3 lines + bottom fade + `btnGhostLight` "Celý popis ›" (board) instead of 4-line ellipsis.
- motorky_screen_v2.dart:220: `IntrinsicHeight` per grid row (double layout) → fixed photo height + `Expanded` body.
- de label "Rozpis" = "Aufstellung" in the dock (de 320) → "Aufschlüsselung" if it fits (translation only).

### CB-31 · P3 · L4/L1 · Transitions and back
- `/booking` on Android = `NoTransitionPage` (router.dart:157-160) — see SH-14; `/moto/:id` = platform default. For v2 add `PredictiveBackPageTransitionsBuilder` for Android in `MgThemeV2.overlay` (manifest already has `enableOnBackInvokedCallback`), so pushes into detail / booking preview the way back on Android 14+.
- Shared primitives: predictive back / consistent push.

### CB-32 · P3 · L0 · Card "Rozpis ▴" link (board)
- moto_card_full_v2.dart:218-246: the board card shows "Rozpis ^" under the price → a light receipt sheet with the card's own `catCardPrice` rows (list, rank discount, total). Only if the owner wants it on every card (adds a tap target next to the CTA).

## Owner decisions (beyond the approved design or functional)
1. Favourites heart (board card + detail) — the app has no favourites feature (new data + storage).
2. Branch line chevron "›" in the detail hero → open the branch detail (new navigation from the detail).
3. Branch row "navigate" disc in "Víc o motorce" (board) — new action on the detail.
4. Booking "Máme to připravené" rows Ty / Platba / Doklady (profile, default card, docs status inside the form) — data from other flows, "Změnit" would navigate away from the booking.
5. Detail no-dates preset "už jedeš" amber conflict (own bookings in the detail).
6. One consent checkbox instead of two (legal semantics).

## Already excellent (keep)
- Full-bleed photo cards: contain photo over a darkened cover copy (no blur in lists), photo segments + side tap zones, adaptive price/CTA (CTA goes full width instead of splitting a number), one looping CTA + one ping only on the first card, rank price + struck list + "≈ X Kč/den · výbava zdarma".
- One uniform calendar band (TripCalendar) everywhere with day prices, pending, busy hatch, today ring, pending-start ping and reduced-motion end states.
- Detail: white sheet with grabber over the photo, adaptive 4/2 spec tiles, light "Tvoje jízda" steps + the ONE dark total box (rank savings chip, struck list price, "bez kauce"), dock CTA states (VYBRAT TERMÍN · od X Kč/den → REZERVOVAT · price → ZMĚNIT TERMÍN when busy), pinned light back bar with the bike name.
- Booking: step progress header, reveal entrance, dock blocker "Chybí velikosti výbavy · Doplnit ⌄" that jumps to the fix, v2 address sheet, ½ 12:00 info as information (owner 2026-10-22), support row.
- Calculator: light steps + dark total + bars + receipt; the sticky dock hides while the in-page CTA is visible (one primary at a time); free list without a bike.
- i18n fit: MgWordFit / stacked mode switch / chip line moves — de and uk at 320 render without broken words or overflows (0 failing findings in cs 360, de + uk 320).
- MgPress press-scale + selectionClick on every v2 tappable; MgMotion tokens with reduced-motion snapping; origin chip "‹ Domů".
