# Audit · shell + Home + global states (v2, flag ON) — 2026-11-07

Evidence: boards rendered at 390 (Main S0/S2/S3/S6/S7/S8, Prihlaseni Úvod/Jazyk/Oprávnění/Hotovo, iOS permission variant), app rendered with test/v2/render (cs 360×780 + 320×690, de/uk 320×690, all Home states + sheets, core states) and scratch renders of the onboarding overlays / welcome / legacy dialog. Probes: toast width with action, sheet drag-to-dismiss with scrollable content. PNGs: `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/uxp/sh/*.png`.

## Coverage (LC)

| Item | v2 look | File |
|---|---|---|
| AppShellV2 (nav, AI FAB, status strips, top banner) | yes |  |
| Home tab S0–S10, loading, errors, review card | yes |  |
| Home date sheet / club rules sheet / nickname dialog / banner full-text sheet | yes |  |
| RouteErrorPage (unknown link 19.7) | yes |  |
| Legacy MgErrorView / loading / stale note / error dialog / progress dialog / error snack | yes (v2 looks via seams) |  |
| AI chat /ai-agent (target of the FAB) | yes (seam in ai_agent_screen.dart) |  |
| LanguageOverlay (first launch) | NO | lib/core/overlays/onboarding_overlays.dart:18 (outside MgV2Gate, main.dart:484) |
| PermissionOverlay (Android + iOS 5.1.1(iv) variant) | NO | lib/core/overlays/onboarding_overlays.dart:135, main.dart:487 |
| MotoIntroOverlay (first launch intro) | NO (close to board, but no skip pill / reduced-motion path) | lib/core/widgets/moto_fx.dart:450, main.dart:499 |
| MotoWelcomeOverlay (after registration) | NO | lib/core/widgets/moto_fx.dart:620 (caller features/auth/register_screen.dart:370 — auth group) |
| OfflineGuard full-screen overlay + Wi-Fi-without-internet strip | NO | lib/core/offline_guard.dart:207-381 (platform file) |
| Force update dialog (19.2) | NO | lib/core/update_check_provider.dart:99 (platform file) |
| Optional update dialog (19.3, Android in-app update) | NO | lib/core/in_app_update_service.dart:152 |
| ErrorWidget.builder crash screen (19.1) | NO | lib/main.dart:90-125 (platform file, shared hunk) |
| Shell pending-booking cancel confirm (strip ✕) | NO (raw AlertDialog; in the real theme the TextButtons are neon text on white) | lib/core/shell_fabs.dart:44-59 |
| Payment-running confirm on tab tap | NO | lib/features/payment/payment_ui_helpers.dart:17 (pay_shop group only) |
| paidAfterRestart snackbar | themed snackbar only | lib/core/shell_paid_listener.dart:23 |

## Improvements (prioritized)

### SH-01 · P1 · LC/L0/L2 · First launch: language + permission overlays
- **Where:** `lib/core/overlays/onboarding_overlays.dart:18,135; lib/main.dart:484-500`
- **Now:** Old black (97 %) overlays outside MgV2Gate, so they never get the v2 look; emoji icons; vykání ("Vítejte v MotoGo24", "potřebujeme váš souhlas", "Vyberte jazyk"); at 360 dp the language tiles break words mid-word ("Nederland|s", "Українськ|а").
- **Change:** New shared views lib/core/overlays/v2/onboarding_lang_v2.dart + onboarding_perm_v2.dart per Prihlaseni board: dark gDark page; Jazyk = logo tile 64 + "MOTO GO 24" 22/900 + "Vyber si jazyk" 20/800, 2-col grid of 52-tall glass tiles (white@.06, 1 px white@.14, r14, flag 28 + name 15/800, MgWordFit minScale .8, never mid-word), footnote 12.5/600 #9FC4B1 "Jazyk změníš kdykoli v Profil → Nastavení."; Oprávnění = ‹ dark disc 44 at (16,55) + logo tile 40 top-right, "Vítej v MotoGo24" 22/800 + "Pro plnou funkčnost potřebujeme tvůj souhlas" 14/600 #CFE7DA, white sheet r22 overlapping −24 with rows (iconTileDark 40 + title 15/800 + sub 12.5/600 #55705F, line dividers), dark dock: rank-less brand CTA "POVOLIT VŠE A POKRAČOVAT" 56 + btnText "Přeskočit – nastavím později"; iOS: same view with onSkip/onBack null → single "POKRAČOVAT" (5.1.1(iv)). Seam in each overlay build: `appV2On ? V2View(callbacks) : old`, flag read from AppV2UiNotifier applied value (overlays sit outside MgV2Scope). Enter MgMotion.enter 450 one-shot; reduced = static.
- **Why (king / conversion):** First 10 seconds of the app are still the old look and vykání; broken words on the most common phone width look cheap.
- **Risk:** Low functional (same callbacks/permission requests); platform file: edit both trees by hand, iOS keeps one button; new i18n keys ×8 (tykání title/subtitle/footnote).
- **Shared primitives:** MgSurfaces gDark page, MgBtnText, MgCta brand variant, MgIconTile

### SH-02 · P1 · LC/L3 · Offline overlay + 'Wi-Fi bez internetu' strip
- **Where:** `lib/core/offline_guard.dart:207-381`
- **Now:** Old 95 % black full-screen overlay with Material buttons and grey text; amber 11 px strip for captive Wi-Fi.
- **Change:** Keep behaviour (overlay still shows/hides exactly as today), swap the look under v2: overlay body = MgStateScreen tone info (light canvas, tone disc 72 wifi-off, title "Jsi offline", why "Telefon teď nemá internet. Co máš načtené, funguje dál.", steps = Stavy 8.2 list (SOS 155·158·112, nonstop linka, kódy, navigace, záznam jízdy), primary btnInk "Zkusit znovu" (existing _retry with in-button spinner), secondary btnGhostLight "Pokračovat bez internetu" (existing _continueOffline), MgSupportRow with Zavolat MotoGo24 / 112 (existing callMotoGo/call112)); captive strip = T4 night strip (MgStatusStrip look, wifi icon, "Wi-Fi nemá internet") under the status bar sliding down 300 ms (MgMotion.sticky, emphasized).
- **Why (king / conversion):** The harshest screen of the app (no signal at a branch) is the least premium; v2 gives what/why/how + a working action.
- **Risk:** Platform file (iOS connectivity_plus 5): edit both by hand, keep platform hunks; overlay is an OverlayEntry outside the router → read the flag from AppV2UiNotifier.
- **Shared primitives:** MgStateScreen, MgStatusStrip (top variant), MgSupportRow

### SH-03 · P1 · LC · Update dialogs (force 19.2 / optional 19.3)
- **Where:** `lib/core/update_check_provider.dart:99; lib/core/in_app_update_service.dart:152`
- **Now:** AlertDialog with Material icon, neon pill on white (banned on light, R5.8), grey 12 px emergency line.
- **Change:** Optional: MgDialogFrame T6 (title 20/800 "Je tu nová verze", body 14/600, safe btnGhostLight "Později", action btnInk "Aktualizovat"; same callbacks). Force: same frame, non-dismissible, primary btnInk "Aktualizovat", eoStoreOpenFail as MgStateBanner err, emergency as MgSupportRow + red MgBtnSos "SOS a nonstop linka" (existing call actions) — never blocked.
- **Why (king / conversion):** A blocking dialog is the moment trust is tested; it must look like the product.
- **Risk:** update_check_provider is a platform file (store URL differs) — seam only; dialog logic/PopScope unchanged.
- **Shared primitives:** MgDialogFrame, MgSupportRow

### SH-04 · P1 · LC · Crash screen (ErrorWidget.builder, Stavy 19.1)
- **Where:** `lib/main.dart:90-125`
- **Now:** Mint #DFF0EC page, 🔄 emoji, #6B8F7B 12 px text (fails AA), Outlined + neon Elevated buttons.
- **Change:** When the v2 flag is applied: MgStateScreen tone err (✕ close at (16,55) → go('/')), title "Tahle obrazovka spadla", why "Omlouváme se, při zobrazení se něco pokazilo. Tvoje data jsou v bezpečí.", primary btnInk "Zpět na Domů" (existing go('/')), secondary btnGhostLight "Zpět" (existing maybePop). No new Nahlásit action (report already sent by CrashReportService).
- **Why (king / conversion):** Even failure must feel looked-after; today it is the last old-look screen a customer can hit anywhere.
- **Risk:** No BuildContext/Localizations → use AppTranslations.of(lastKnownAppLang) as today and a static flag read; must not throw (wrap in try → fall back to today's widget).
- **Shared primitives:** MgStateScreen (context-light variant)

### SH-05 · P1 · LC/L2 · Status strip ✕ → 'Zrušit rezervaci?' confirm
- **Where:** `lib/core/shell_fabs.dart:44-59`
- **Now:** Raw AlertDialog + TextButtons: under the real app theme the labels are neon #74FB71 on white (≈1.4:1), destructive in raw red.
- **Change:** v2: `showMgConfirm(context, title: tr('cancelReservationQ'), safeLabel: tr('back'), actionLabel: tr('cancelReservationBtn'), destructive: true)` → same bool result into the unchanged doCancel().
- **Why (king / conversion):** Irreversible action needs the T6 standard (safe left, red right) and readable labels.
- **Risk:** None functional (same result bool).
- **Shared primitives:** showMgConfirm

### SH-06 · P1 · L0/L3 · Home S1 / S2 / S3 + status strip
- **Where:** `lib/core/shell_fab_layer.dart:120-160; lib/features/home/v2/home_screen_v2.dart:75-81`
- **Now:** On Domů the SOS / payment / documents strip floats over the page while the ticket above shows the SAME item and action ("Dokončit hlášení" + "SOS dokončit"; "ZAPLATIT · 12 027 Kč" + "Dokončit rezervaci · Zbývá 24:56"); countdown shown twice. Board Main S1/S2/S3 has no strip.
- **Change:** v2 only: on location '/' hide the strip whose item the Home ticket already shows (sos ↔ s1, pending ↔ s2, docs ↔ s3). Move the strip's only extra action (pending cancel ✕) into the S2 ticket as the board's btnText link "Zrušit nedokončenou rezervaci" under the CTA (same onCancel closure incl. SH-05 confirm). Route / cart strips unchanged.
- **Why (king / conversion):** One obvious next step; a duplicated urgent bar reads as nagging and pushes content under the FAB.
- **Risk:** Cancel must stay reachable on Home (moved, not removed); strips keep showing on every other route.

### SH-07 · P1 · L3 · Status strips (all tabs)
- **Where:** `lib/core/shell_fab_layer.dart:130-158`
- **Now:** All active strips are stacked (SOS + platba + doklady + trasa + košík → up to 5 bars, 8 px apart) above the nav.
- **Change:** Spec C2 (appdesign_spec §C2, DESIGN_V2 §4.4): show only the most urgent strip (existing priority order) + a "+n" chip (neon@.16, #A8FF9F 12/800, 32 h) left of the chevron; tapping "+n" opens a light MgSheet listing the other strips as MgStatusStrip rows with their existing onTap/onDismiss. Strip enter/exit: slide-up + fade 300 ms (MgMotion.sticky, emphasized); reduced = instant.
- **Why (king / conversion):** Several dark bars stacked bottom-right bury the page and the AI button; one strip = calm, premium.
- **Risk:** No action lost (all reachable via +n); FAB bottom follows the single strip height.
- **Shared primitives:** MgStatusStrip '+n' chip, strip list sheet

### SH-08 · P1 · L2 perf · Home header banner marquee (and every tab with MgTopBanner band)
- **Where:** `lib/core/v2/chrome/mg_top_banner.dart:68-138 (repeat at :95/:97, AnimatedBuilder :129); lib/core/v2/chrome/mg_page.dart:131-149`
- **Now:** The marquee loop has no RepaintBoundary; Home is one SliverToBoxAdapter Column, and the nearest boundary is the viewport → the whole Home content (header, funnel, all sections incl. off-screen ones) is repainted every frame while the banner runs. It also keeps ticking when scrolled away. With the CTA glow + 'Volná v termínu' ping it is a 3rd infinite loop on S0 (rule: max one CTA fx + one live indicator).
- **Change:** Wrap _Marquee in RepaintBoundary; drive it with MgLoopClock-style visibility (pause when the header is scrolled out: VisibilityDetector-free check via the page ScrollController offset > header height, or TickerMode false). Loop-budget conflict → owner decision OD-6.
- **Why (king / conversion):** Battery + jank on low-end Android during the most important scroll (Home); premium = smooth.
- **Risk:** None visual.
- **Shared primitives:** MgLoopClock reuse, visibility pause for loops

### SH-09 · P1 · L0/L3 (disclosure) · Home ticket S3–S9 photo header
- **Where:** `lib/features/home/v2/home_ticket_v2.dart:57`
- **Now:** Meta line = "Velké Němčice · #55556666" — branch type (samoobsluha / s obsluhou) missing; the booking number takes its place.
- **Change:** Meta = "{branch} · {type}" with existing keys v2CalcBranchSelf / v2CalcBranchStaffed (from r.isSelfService / branchType; delivery keeps the address) exactly like the board ("MotoGo24 Velké Němčice · samoobsluha"); booking number moves to the semantics label only (it stays in reservation detail).
- **Why (king / conversion):** Disclosure rule: branch + type are key info at first glance (self-service = codes, no staff).
- **Risk:** None (existing fields/keys).

### SH-10 · P1 · L0/L3 (disclosure) · Home 'Tvůj klub' card
- **Where:** `lib/features/home/v2/home_club_card_v2.dart:28-175`
- **Now:** Always fully expanded (~560 px at 360 dp): level + discount repeated 3× ("Level 3 z 20 · sleva 3 % na každou jízdu v appce", "Level 3 / 20 · 5 b. · rezervace z appky i webu", perk tile "−3 % na každou jízdu v appce"), two big perk tiles, league rail, rules note, 'Všechny ranky'.
- **Change:** Board layout: header row (emblem 44 · eyebrow "TVŮJ KLUB · LEVEL 3 Z 20" · name 20/800 ink · ⓘ 44), tier bar on well (unchanged), next-rank line 14/800 ink, then ONE summary row "−3 % · výbava a boty zdarma" (13/800 #0D6E0D) + btnText "Výhody a ligy ▾" toggling an MgAnimatedSize (300, emphasized) section with the existing perk tiles, savings line, league rail, rules note and 'Všechny ranky ›'; collapsed by default; chevron rotates 180° (MgMotion.color). Drop the duplicate level line (keep it in the expanded part).
- **Why (king / conversion):** Rank recognition stays visible, details one tap away; ~300 px less scroll before routes/branches.
- **Risk:** None functional (pure disclosure); new key for the toggle label ×8 if not existing.
- **Shared primitives:** MgDisclosure (btnText + chevron + MgAnimatedSize)

### SH-11 · P1 · L2 · Toasts / error snackbars with an action (app-wide)
- **Where:** `lib/core/v2/widgets/mg_toast.dart:28-51; lib/core/widgets/error_feedback.dart:77-83`
- **Now:** With a SnackBarAction the message is laid out in a ~150 px column (probe: 150.8 px in a 360 px snack, height 216 px vs 116 px without action) → 4–6 line slabs with empty space beside them.
- **Change:** v2 toast content = Column(text full width (MgWordFit), Align(end, MgBtnText(actionLabel) 44 tall, onTap: hideCurrentSnackBar + onAction)) and no SnackBarAction; same for the v2 look of showErrorSnack (seam inside error_feedback.dart). Keep durations (2.8 s / 4 s / 7 s).
- **Why (king / conversion):** Confirmations should read in one glance (2 lines), not a narrow column.
- **Risk:** Low; tests that tap SnackBarAction by type need the text finder.
- **Shared primitives:** MgSnackContent (shared toast layout)

### SH-12 · P1 · L1/L3 · AI FAB over the ½ offer (Home S0/S10)
- **Where:** `lib/features/home/v2/home_offer_block_v2.dart:41-66; lib/core/v2/chrome/mg_fab_avoid.dart:77-89`
- **Now:** The offer box is not an avoid zone → at rest (360x780, uk 320x690) the 56 px disc sits on the offer text ("ušetříš 1 [FAB] Kč").
- **Change:** Wrap the MgTintFeature offer box in MgFabAvoid(kind: tap) → peek (+26 px, .85) as for the rows; same for the club perk tiles and branch 'Detail' buttons (tap) so the disc never covers money facts.
- **Why (king / conversion):** The key sales offer must be readable at first glance (disclosure rule).
- **Risk:** None.

### SH-13 · P2 · L4 · Tab switching
- **Where:** `lib/core/router.dart:364-393`
- **Now:** Tab roots are NoTransitionPage → instant swap (spec: fade-through 210 ms).
- **Change:** When v2 is applied: CustomTransitionPage for the 5 tab roots, FadeTransition (incoming 0→1 over MgMotion.tab 210 ms, Curves.easeOut; outgoing fade 0→ in the first 90 ms) ; reduced motion → Duration.zero. Read the flag in the pageBuilder via ref.read(appV2UiProvider).
- **Why (king / conversion):** Instant swaps feel cheap; a short fade-through is the platform-premium norm.
- **Risk:** Low; keep NoTransition when v2 is off.
- **Shared primitives:** mgTabPage (fade-through page)

### SH-14 · P2 · L1/L4 · Push into /booking and /routes-list on Android
- **Where:** `lib/core/router.dart:156-160,400-405,522-524`
- **Now:** _swipeBackPage = NoTransitionPage on Android → these two pushes are instant and have no predictive-back preview, while every other push uses PredictiveBackPageTransitionsBuilder (Flutter 3.47 default).
- **Change:** v2: MaterialPage on Android too (same as iOS) → consistent 300 push + predictive back (manifest already enableOnBackInvokedCallback=true). Flag-OFF keeps NoTransition.
- **Why (king / conversion):** Consistent push/pop motion everywhere; system back preview works into the booking flow.
- **Risk:** Booking has PopScope/discard guards — predictive back respects canPop=false (no preview, existing confirm). Verify with a widget test.

### SH-15 · P2 · L4/L1 · Nav hide/show on focused flows (detail, booking, messages thread…)
- **Where:** `lib/core/v2/shell/app_shell_v2.dart:210-217`
- **Now:** bottomNavigationBar becomes null → nav vanishes instantly, the body jumps 98 px; on iOS edge-swipe back from /moto/:id the Home/catalog underneath shows without nav and the nav pops in at the end.
- **Change:** Keep the slot and animate: AnimatedSlide(offset 0 → 1.1, MgMotion.sticky 300, emphasized) + AnimatedSize/ClipRect height 98 → 0 (spec 'slide out 110 %'); reduced → instant. FAB Positioned → AnimatedPositioned (300) so it follows strips/dock instead of jumping.
- **Why (king / conversion):** No jumps during the most frequent transitions.
- **Risk:** Medium: bottom padding consumers (MgChrome.bottomObstruction) must follow the animated value; widget test on hidden/visible.
- **Shared primitives:** animated nav slot, AnimatedPositioned FAB

### SH-16 · P2 · L1 · All v2 bottom sheets
- **Where:** `lib/core/v2/widgets/mg_sheet.dart:81-83`
- **Now:** Body is a SingleChildScrollView: when content scrolls (club rules on small phones, date sheet at 320x690, long lists) a downward drag on the content never dismisses (probe: 40 rows → not dismissed on Android and iOS; 3 rows → dismissed).
- **Change:** Shared 'sheet drag-to-dismiss': when the body is at offset 0 and the drag goes down, hand the drag to the sheet (NotificationListener<OverscrollNotification> on the body → drive the route's AnimationController; release > 25 % height or velocity > 700 → maybePop, else spring back 300). Respect enableDrag:false / dirty forms (they keep their confirm). Also pass sheetAnimationStyle(duration: MgMotion.sheet, reverseDuration: 250) and AnimationStyle.noAnimation under reduced motion.
- **Why (king / conversion):** Platform instinct: pull a sheet down to close it from anywhere.
- **Risk:** Gesture conflict with inner scroll (only at top); never auto-dismiss sheets that use PopScope (call maybePop).
- **Shared primitives:** sheet drag-to-dismiss

### SH-17 · P2 · L4 · iOS pull-down on Home (and other dark-header tab roots)
- **Where:** `lib/core/v2/chrome/mg_page.dart:150-168`
- **Now:** Bouncing overscroll reveals the light canvas above the dark rank header; the light status-bar icons then sit on a light band; Material spinner on iOS.
- **Change:** When the header is dark, paint a dark backdrop behind the scroll's top (Stack: Positioned(top 0, height = headerH/2) ColoredBox(MgColors.night)) so overscroll extends the header colour; RefreshIndicator.adaptive-style: Cupertino activity indicator in neon on iOS, current neon disc on Android.
- **Why (king / conversion):** Rubber-band on the hero must look continuous — classic premium detail.
- **Risk:** None functional.
- **Shared primitives:** brand pull-to-refresh, dark overscroll backdrop in MgPage

### SH-18 · P2 · L4 · Home ticket → reservation detail; funnel card → bike detail
- **Where:** `lib/features/home/v2/home_ticket_v2.dart:84; lib/features/home/v2/funnel_carousel_v2.dart:51`
- **Now:** No Hero anywhere in v2 (spec DESIGN_V2 §5.3 Hero `res-img-{id}`, §5.11).
- **Change:** Hero(tag: 'res-img-${r.id}') around HomePhoto in the ticket and the photo of ResDetailHeroV2 (MgPhotoHero); Hero(tag: 'moto-img-${m.id}') funnel photo ↔ detail first page; flightShuttleBuilder = the destination's image (same thumb URL/memCacheWidth to avoid a re-decode flash); reduced motion → HeroMode(enabled: false).
- **Why (king / conversion):** Shared-element continuity is the signature of a premium app and makes the tap feel instant.
- **Risk:** Medium (image decode mismatch flicker; works only with animated pushes — depends on SH-14 on Android).
- **Shared primitives:** MgHeroPhoto

### SH-19 · P2 · L1 · Home 'Vybrali jsme ti' routes carousel
- **Where:** `lib/features/home/v2/home_routes_v2.dart:75`
- **Now:** Free-scrolling ListView: no snap, card stops anywhere.
- **Change:** Snap to cards like spec (PageView .76 ≈ 296 wide): keep ListView but physics = custom snap physics (item extent card + 12, MgMotion.out), padding 16 so the next card peeks 40–48 px; haptic selectionClick on settle.
- **Why (king / conversion):** Carousels must land cleanly on a card.
- **Risk:** Low (item width already fixed).
- **Shared primitives:** MgSnapPhysics (item-extent snap)

### SH-20 · P2 · L4 · Funnel bike pager Ken Burns
- **Where:** `lib/features/home/v2/funnel_carousel_v2.dart:52-61`
- **Now:** Ken Burns exists only while `center`; when the page index flips mid-swipe the outgoing, still visible card snaps from scale 1.06 to 1.0.
- **Change:** Keep the scale on the page and ease it back over MgMotion.sticky (300, out) when it stops being centred (TweenAnimationBuilder always present, end = center ? 1.06 : 1.0, duration center ? kenBurns : 300).
- **Why (king / conversion):** No visible pop during the main swipe gesture of Home.
- **Risk:** None.

### SH-21 · P2 · L0/L2 · Funnel top row eyebrow
- **Where:** `lib/features/home/v2/home_funnel_parts.dart:78`
- **Now:** At 360 dp cs the eyebrow 'TVOJE PŘÍŠTÍ JÍZDA' is dropped to a bare route icon (fit check uses 0.85 scale although MgWordFit allows 0.7).
- **Change:** Use the real minScale 0.7 in the need computation; only drop to the icon when 0.7 does not fit (cs/en/de fit at 360).
- **Why (king / conversion):** Board shows the eyebrow; a lone glyph explains nothing.
- **Risk:** None.

### SH-22 · P2 · L5 · Home offer block rows
- **Where:** `lib/features/home/v2/home_offer_block_v2.dart:81,88`
- **Now:** 'Spočítat přesnou cenu' sub = generic "Vyber motorku a termín, cenu uvidíš hned" although the calculator opens prefilled with the centred bike + dates; 'Všechny motorky' sub = "Filtry, pobočky a dostupnost".
- **Change:** Board copy: calc sub = "{bike} · {start} → {end}" (existing tripShortDate, no new key) when moto != null; all-bikes sub = "Celá nabídka s tvým termínem" (new key ×8) when dates are given.
- **Why (king / conversion):** Shows we remember the customer's choice (king, nothing twice).
- **Risk:** None.

### SH-23 · P2 · L2 · Home bookings loading
- **Where:** `lib/features/home/v2/home_screen_v2.dart:157-183`
- **Now:** Hero skeleton is 360 px; the funnel that follows is ~590 px and the ticket ~520 px → page jumps when data arrives.
- **Change:** Skeleton = funnel shape: photo 200 (MgSkeleton dark) + eyebrow pill + title bar + 2 preset chips 56 + CTA 60 → ~560 px; one shimmer pass.
- **Why (king / conversion):** Skeletons must match the final layout (no jump).
- **Risk:** None.

### SH-24 · P2 · L0/L2 · Home 'Zaznamenat jízdu' row
- **Where:** `lib/features/home/v2/home_record_row_v2.dart:148`
- **Now:** Fixed threshold 300 px → on every 360 dp phone the row uses the narrow layout (36 icon, subline under the icon) instead of the board row (44 tile + title/sub column + chevron).
- **Change:** Decide narrow by measurement (mgWordsFit of title + sub in width − 44 − 12 − 28), not by a fixed 300.
- **Why (king / conversion):** Board fidelity on the most common width; §4.2 B is the R3 answer the owner asked for.
- **Risk:** None.

### SH-25 · P2 · L0 · Home ticket S2 (unpaid)
- **Where:** `lib/features/home/v2/home_ticket_v2.dart:221-227 (+ checklist home_ticket_checklist.dart)`
- **Now:** Checklist rows "Rezervace čeká na platbu" + "Na zaplacení zbývá 24:56"; no cancel link (see SH-06).
- **Change:** Board S2: 72 px countdown ring (neon arc draining, mm:ss 15/900 tabular — the screen's one live indicator via MgLoopClock, static under reduced motion) + "Zbývá na zaplacení" 15/800 + "Motorku ti držíme. Platební okno je 30 minut." ; CTA ZAPLATIT · price; btnText "Zrušit nedokončenou rezervaci".
- **Why (king / conversion):** Urgency shown calmly and visually; honest hold message.
- **Risk:** Uses the existing countdown value only.
- **Shared primitives:** MgCountdownRing

### SH-26 · P2 · L0 · Home ticket status pills
- **Where:** `lib/features/home/v2/home_ticket_v2.dart:175-189`
- **Now:** S4–S7 always "NADCHÁZEJÍCÍ" (also on pickup day S7); board S6 shows "✓ PŘIPRAVENO" when paid + docs OK; S7 eyebrow "DNES · VÝDEJ OD 12:00".
- **Change:** docsOk && paid → ok pill "PŘIPRAVENO" (new key ×8), else "NADCHÁZEJÍCÍ"; S7 eyebrow "DNES · VÝDEJ OD {time}" (new key) instead of bare "DNES"; add the board's "{n} ze {m} hotovo" counter (11/800 #9FC4B1) right of "TÝM PRO TEBE" from the existing checklist states.
- **Why (king / conversion):** Concierge tone: tell the king everything is ready.
- **Risk:** None (existing fields).

### SH-27 · P2 · L0 · Home ticket S8 (riding)
- **Where:** `lib/features/home/v2/home_ticket_v2.dart:233-269`
- **Now:** CTA DETAIL REZERVACE + SOS circle only.
- **Change:** Board S8: day ring "2/3 den" (static, from existing dates), line "● Záznam jízdy z výpůjčky běží · {km} km" (existing recorder value), and the 3 ghost buttons row 44 ("Prodloužit" → existing /reservations/:id/edit, "Navigovat" → existing navigate(), "Kódy" → existing detail) under the CTA.
- **Why (king / conversion):** During the ride the essentials are one tap away.
- **Risk:** Only existing actions; check owner OK for 'Prodloužit' entry on Home (OD-3).

### SH-28 · P2 · L3/L2 · Shared error dialog look
- **Where:** `lib/core/v2/states/legacy_dialog_looks.dart:16-48`
- **Now:** Two equal btnInk buttons stacked ("Zkusit znovu", "Zavolat MotoGo24") + ghost "Zavřít" → two primaries.
- **Change:** Primary btnInk (first action), secondary btnGhostLight, close = btnText (T2/T6 hierarchy).
- **Why (king / conversion):** One obvious next step.
- **Risk:** None.

### SH-29 · P2 · L3 copy · Home date sheet hint; legacy offline snack
- **Where:** `lib/features/catalog/v2/availability_calendar_v2.dart:113-117; i18n calSelectPickup/calSelectReturn; FriendlyError offline text`
- **Now:** "Vyberte datum vyzvednutí" (vykání; es/fr formal) in the Home date sheet; offline snack "…nejsi připojený k internetu" (gendered).
- **Change:** New tykání keys v2CalPickStart/v2CalPickEnd: cs "Vyber datum vyzvednutí" / "Vyber datum vrácení", en "Pick your pick-up date" / "Pick your return date", de "Wähle das Abholdatum" / "Wähle das Rückgabedatum", es "Elige la fecha de recogida" / "Elige la fecha de devolución", fr "Choisis la date de retrait" / "Choisis la date de retour", nl "Kies de ophaaldatum" / "Kies de inleverdatum", pl "Wybierz datę odbioru" / "Wybierz datę zwrotu", uk "Обери дату отримання" / "Обери дату повернення"; offline line → "Telefon je offline. Zapni data nebo Wi-Fi a zkus to znovu." (§5.3).
- **Why (king / conversion):** Tykání + gender-neutral everywhere (owner rule).
- **Risk:** Calendar file is shared with catalog (coordinate).

### SH-30 · P2 · L4 · Home counts (Moje zážitky tiles, 'ušetřil jsi')
- **Where:** `lib/features/home/v2/home_experiences_band_v2.dart:82-118; home_club_card_v2.dart:138+`
- **Now:** Static numbers (spec: count-up once).
- **Change:** Shared MgCountUp(value, duration MgMotion.reveal 550, MgMotion.out, once per session key, tabular figures, reduced → final value) for tile values and the savings line.
- **Why (king / conversion):** Small reward moment; makes progress feel alive.
- **Risk:** None.
- **Shared primitives:** count-up

### SH-31 · P2 · L2/L4 · Home section building
- **Where:** `lib/features/home/v2/home_screen_v2.dart:115-134`
- **Now:** All sections in one eager Column inside one SliverToBoxAdapter: everything (routes covers, branch photos, bikes) is built/decoded at start and all reveals play at once off-screen.
- **Change:** Keep header + hero in HomeHeroStack (overlap), pass the rest via MgPage.slivers as a SliverList (lazy, RepaintBoundary per section) so each HomeReveal plays when the section first enters the viewport.
- **Why (king / conversion):** Faster first frame, entrance motion the customer actually sees.
- **Risk:** Low-medium (FabAvoid zones register lazily; tests that find off-screen sections need scrolling).

### SH-32 · P2 · L0 · Home routes section
- **Where:** `lib/features/home/v2/home_routes_v2.dart:46-95`
- **Now:** Board has the chip row under the carousel "U {pobočky} je {n} míst · objevil jsi {n} · otevřít mapu ›" (→ Trasy · Místa); app has none.
- **Change:** Add the white row (iconTileDark pin 40 + 14/800 + 12.5/600 + chevron) only when the places list is already cached by the routes warm-up (no new request); tap → existing Trasy tab (origin chip).
- **Why (king / conversion):** Board fidelity; invites discovery.
- **Risk:** Must not add a backend call; hide when no cached data.

### SH-33 · P3 · L4 · Nav bar micro-motion
- **Where:** `lib/core/v2/chrome/v2_nav_bar.dart:204-288`
- **Now:** Pill spring + liquid stretch only; label colour/weight swap instantly; no active-icon pop; re-tap only scrolls.
- **Change:** AnimatedDefaultTextStyle 180 ms (MgMotion.color) for label; MgPop on the newly active icon; re-tap → 3 px upward nudge of the icon (MgMotion.pop) + existing scroll-to-top.
- **Why (king / conversion):** Spec §4.1 completeness; tactile.
- **Risk:** None.

### SH-34 · P3 · L4/L5 · AI FAB
- **Where:** `lib/core/v2/chrome/mg_ai_fab.dart (MgAiFab state machine)`
- **Now:** No 'lift' state (rest/peek/off only); no first-run coach bubble; opening = plain route push.
- **Change:** Add lift (bottom = zone top + 12, max +56, 300 spring) per spec; first-run coach bubble "Zeptej se kdykoli. Jsme tu pro tebe." (night glass, ✕, once, new key ×8); OpenContainer-style expand is optional (owner).
- **Why (king / conversion):** Concierge introduces itself once.
- **Risk:** Low.
- **Shared primitives:** MgCoachBubble

### SH-35 · P3 · L4 · Dialogs / sheets motion
- **Where:** `lib/core/v2/widgets/mg_dialog.dart:22; mg_sheet.dart:28`
- **Now:** Default Material timings (dialog fade 150, sheet 250/200).
- **Change:** Dialog: showGeneralDialog transition fade + scale .96→1, 180 ms (MgMotion.color), barrier night@.55; sheet: 300 ms emphasized; reduced → 0.
- **Why (king / conversion):** Spec §5.2 interactions.
- **Risk:** None.
- **Shared primitives:** mgDialogRoute

### SH-36 · P3 · L4 · Success tone disc
- **Where:** `lib/core/v2/states/mg_tone.dart:87-120`
- **Now:** Pop + ripple, check glyph static.
- **Change:** Check path draws 300 ms (PathMetric extract) before the pop; pending ring closes into ✓ (450 morph) when a pending state turns success.
- **Why (king / conversion):** Spec §5.2 success motion.
- **Risk:** None.
- **Shared primitives:** check draw

### SH-37 · P3 · L2 · Money / dates line breaks
- **Where:** `lib/core/currency.dart:65; home_ticket_v2.dart _DatesRow`
- **Now:** "1 851 / Kč" and "· 3 / dny" split across lines (360 cs offer box, ticket dates row).
- **Change:** v2 display helper mgNbsp(): NBSP before currency symbol and inside "· {n} {den}" (do NOT change Money.czk used by logic).
- **Why (king / conversion):** Typographic polish on prices.
- **Risk:** None if limited to v2 Text.
- **Shared primitives:** mgNbsp

### SH-38 · P3 · L1 · Header SOS pill
- **Where:** `lib/features/home/v2/home_header_v2.dart:285`
- **Now:** selectionClick haptic.
- **Change:** HapticFeedback.heavyImpact (spec §4.3), still plain tap, opens /sos.
- **Why (king / conversion):** Emergency affordance feels different.
- **Risk:** None.

### SH-39 · P3 · L0 · Club league rail
- **Where:** `lib/features/home/v2/home_club_parts.dart:163`
- **Now:** Swatches are not tappable.
- **Change:** Board 'LIGY · KLEPNI A UKÁŽEME TI VZHLED': tap → light sheet "Takhle bude vypadat tvoje appka" with a mini LogoRow frame, rank chip, sample CTA and nav pill of that tier (RankTokens of the tier's first level; purely visual).
- **Why (king / conversion):** Aspiration — the king sees his next crown.
- **Risk:** None (no data).
- **Shared primitives:** tier preview sheet

### SH-40 · P3 · L2 · Funnel card meta
- **Where:** `lib/features/home/v2/funnel_carousel_v2.dart:112`
- **Now:** "Mezná · Cestovní/End…" ellipsized at 360 (de/uk 320 too).
- **Change:** If meta does not fit, drop the category, never truncate the branch.
- **Why (king / conversion):** Branch is key info.
- **Risk:** None.

### SH-41 · P3 · L4 · Intro overlay
- **Where:** `lib/core/widgets/moto_fx.dart:450-560`
- **Now:** 2.4 s animation with 🏍️ emoji ride-by; tap anywhere skips; no visible skip; reduced motion not checked.
- **Change:** Board Úvod: drop the emoji, add ghost pill "Přeskočit" 44 at the bottom (existing _finish), reduced motion → show end frame 600 ms then onDone.
- **Why (king / conversion):** Calm, branded first impression; accessibility.
- **Risk:** None.

### SH-42 · P3 · L2 perf · Loops off-screen
- **Where:** `lib/core/v2/motion/mg_anim_loops.dart:5-60`
- **Now:** MgLoopClock pauses only via TickerMode (covered route) — CTA glow / ping keep ticking when scrolled out of view.
- **Change:** Optional visibility gate (ScrollPosition listener of the nearest Scrollable → active false when the box is outside the viewport).
- **Why (king / conversion):** Battery.
- **Risk:** Low.
- **Shared primitives:** loop visibility pause

## Owner decisions (not implemented)

- **OD-1** Offline full-screen overlay → T4 banner + 'Co funguje bez signálu' sheet (DESIGN_V22 §9 #10, Stavy 8.1/8.2) — Behaviour change (non-blocking); SH-02 only re-skins today's overlay.
- **OD-2** Door codes block in the Home ticket on pickup day (board S7: Brána/Šatna/Motorka masked + 'Zobrazit kódy', 'Kódy na celou obrazovku') — Disclosure rule says codes on pickup day are always visible, but Home would fetch codes (existing RPC) on a new screen — needs owner OK.
- **OD-3** Ticket '⋯' Více sheet (Detail · Dokumenty · Zrušit) and 'Upravit' pill on the photo (board S6), S8 'Prodloužit' — New Home entry points to existing destructive/edit actions.
- **OD-4** Keep tab state (scroll position, nested stack) per tab — StatefulShellRoute or a v2-only scroll memory — Navigation semantics change.
- **OD-5** Board 12:00 offer shows a toggle; owner decision 2026-10-22 = information only — Owner rule wins — keep info (app is right).
- **OD-6** Header marquee = 3rd infinite loop on Home S0 (spec max 2): run one pass on first view then rest static (tap = full text)? — Spec prescribes the marquee; loop budget conflicts.
- **OD-7** AI FAB container-transform into the chat panel (spec §4.2) — Changes navigation (route push → overlay).
- **OD-8** Trust facts on Home (bez kauce, výbava v ceně, nonstop) as on the web — Not in the Main board.

## Exceptions (stay as they are)

- Level-up celebration lib/features/loyalty/loyalty_levelup_overlay.dart (owner 2026-10-15) — untouched.
- Native system permission dialogs, Stripe / Apple Pay / Google Pay sheets, Play in-app update UI — not ours.
- iOS PermissionOverlay keeps its single 'Pokračovat' button set (App Store 5.1.1(iv)); only its look may follow v2 (SH-01).
- Payment-running confirm on tab tap (features/payment/payment_ui_helpers.dart:17) — pay_shop group only.
- MotoWelcomeOverlay (register success) — listed here, owned by the auth group (Prihlaseni 'Hotovo').

## Already excellent (keep)

- Nav label no-overlap fit ladder + full-word semantics + long-press bubble (v2_nav_fit.dart), rank pill spring with liquid stretch (v2_nav_bar.dart:98-169).
- MgFabAvoid zones for CTA/SOS: the AI disc never covers REZERVOVAT / ZAPLATIT / SOS (verified in renders).
- Funnel: real availability + licence badge + 'Znovu' badge, real rank price with struck list price, MgBump on price change, CTA above the fold at 320x690 and 360x780, 12:00 as information with the real saving.
- Header: greeting by time + nickname (dialog in v2), concierge note by state, rank chip, motto marks, banner as last header line, static under reduced motion with tap-for-full.
- Ticket checklist from real fields, SOS circle + explanation, one primary per state, Další rezervace row, 'Kdy jedeš příště?' pill + calculator disc.
- Date sheet: uniform neon band, today ring + dot, light skin.
- State templates T1/T2/T3, support row, tech details — match the Stavy board closely.
- Image loading: placeholder gradient + glyph, 150 ms fade, memCacheWidth, thumb URLs (net_image.dart).
- Reduced motion honoured everywhere (MgMotion.of / reduced), one-shot reveals per session (HomeReveal), loops in RepaintBoundary via MgLoopClock.
- Back standard (MgV2Back, MgBackGuard, cross-tab origin chip), predictive back enabled in the manifest.
