# Audit pay_shop — payment step, results, e-shop, vouchers (v2 flag ON)

Date 2026-11-07. Method: code walk (router, screens, widgets, both trees), boards rendered with Playwright at 390 (Booking: step 3, payment modes, wallet sheets Android/iOS, Rozpis, T2, 3DS, upsell, success/pending/fail3; Stavy groups 1/2/3/6/13; Profil S11 E-shop + product/checkout sheets + Platební metody), app screens rendered with the v2 render harness (scratch copy, flag ON) at 360×780 cs and 320×690 de/uk. Owner rules applied: functionality unchanged, design lock, D1–D7 payment decisions (paydec/DESIGN.md), disclosure rule.

**Verdict:** NONE of the 9 routed screens and none of the 5 sheets/dialogs of this area has the v2 look today (the shop has only a v2 back disc). The v2 booking form hands the customer to an old mint/neon payment screen and an all-dark arcade thank-you page — the biggest premium/trust break of the app. Almost everything needed already exists as v2 primitives; only a few small shared parts are new (see "Shared core/v2 primitives").

## LC — Coverage

| Surface | Kind | File | v2 today | Board / spec | Item |
|---|---|---|---|---|---|
| /payment PaymentScreen — new booking | route (shell, nav hidden) | features/payment/payment_screen.dart:1492-1628 | NO (old mint body, neon square back, emoji, white pay bar) | Booking board step 3 "Kontrola a platba" + dock | PS-01 |
| /payment + /sos/payment — resume, restore, edit/swap surcharge, SOS, shop order | route | payment_screen.dart:1570 PaymentContextCard; widgets/payment_header_widgets.dart:108-236 | NO | Booking board prop rezimPlatby (Doplatek úpravy / Dokončit nedokončenou / SOS platba) | PS-02 |
| /success PaymentConfirmationScreen (verified / docs missing / child bike / unknown / load fail / restored / late-gate) | route (no shell) | features/payment/payment_confirmation_screen.dart:236-620 | NO (all-dark, flying moto, 4 loops, vykání) | Stavy 1.1–1.5 + Booking res=ok | PS-03 |
| /payment-result PaymentResultScreen (success / pending / attention / failed / notPaid) | route (no shell) | features/payment/payment_result_screen.dart:175-384 | NO (all-dark, emoji badges) | Stavy T1: 1.7–1.16, 2.1, 2.7, 2.9, 1.12, 10.5 | PS-04 |
| CardPaymentSheet (card + Google Pay / Apple Pay) | modal sheet (platform file) | features/payment/widgets/card_payment_sheet.dart:57-80, 284-445 (Android); iOS :65, :216 dialog, :388-570 | NO (only the global bottomSheetTheme overlay, overridden by its own shape) | Booking sheet "wallet" (Android + iOS) | PS-05 |
| PaymentErrorSheet.show (payment, checkout, booking restore, reservation edit) | modal sheet | features/payment/widgets/payment_error_sheet.dart:17-190 | NO | Stavy T2 (groups 3, 4, 5, 7, 8, 10, 13) + Booking sheet "t2" | PS-06 |
| UpsellSection (flag reservation_upsell OFF, D7) | section of /payment | features/payment/widgets/upsell_section.dart:32-110 | NO | Booking prop upsell (collapsed card + carousel) | PS-07 |
| MotoGalleryCard / PriceSummaryCard / SavedCardPreview / CardRoundingNote / PaymentCountdown / PaymentHeader / PaymentPayButton | parts of /payment | widgets/moto_gallery_card.dart:45-77; booking/widgets/price_summary.dart; widgets/saved_card_preview.dart; widgets/card_rounding_note.dart:43-68; widgets/payment_header_widgets.dart:12-330 | NO | Booking board recap ticket, Rozpis sheet "rcpt", "ZPŮSOB PLATBY", Stavy 6.2 T3, header chip 10.1, dock | PS-01/PS-18 |
| confirmLeaveRunningPayment dialog | dialog | features/payment/payment_ui_helpers.dart:15-37 | PARTIAL (MgThemeV2 dialog shape; M3 TextButton + neon ElevatedButton) | T6 dialog | PS-14 |
| /shop ShopScreen (grid / loading / empty / error) | route (shell, NoTransitionPage) | features/shop/shop_screen.dart:20-198 | PARTIAL (only v2 back disc + status bar via mg_v1_pass) | Profil board obrazovka "E-shop (zapne Velín)" (S11) | PS-08 |
| /shop/:id ProductDetailScreen (+ loading / error / gone via MgStateScaffold) | route | features/shop/product_detail_screen.dart:74-252 (states :39-71 are already v2 via state_views seams) | PARTIAL (states v2; main body old, neon 36 px back) | Profil S11 product sheet (stavAkce "produkt bez velikosti", "produkt už v obchodě není") | PS-09 |
| /cart CartScreen (items / empty) | route (nav visible) | features/shop/cart_screen.dart:31-163 | NO | Profil S11 "Košík (2)" card + Stavy 13.1/13.14 cart context | PS-10 |
| /checkout ShopCheckoutScreen (+ shipping, payment card, promo, summary sections) | route (nav hidden) | features/shop/shop_checkout_screen.dart:665-982; widgets/checkout_*.dart | NO | Profil S11 sheet "Doručovací údaje" (13.16, 13.17) + Stavy 13.2–13.9 | PS-11 |
| /voucher VoucherScreen | route (nav visible) | features/shop/voucher_screen.dart:51-246 | NO | Profil S11 "Dárkový poukaz" card | PS-12 |
| PaymentMethodsScreen (+ delete dialog, Android add-card sheet, toasts) | Navigator.push from Profil (platform file) | features/payment/payment_methods_screen.dart:31-215 (Android) / iOS :20-175 | NO | Profil board obrazovka "Platební metody" + stavAkce 3.12/3.13 | PS-13 |
| Toasts showMotoGoToast in the area (payment 5×, result 2×, product 2×, cart, voucher, methods 6×) | snackbar | features/auth/widgets/toast_helper.dart:9-71 | PARTIAL (explicit dark bg + emoji + bnav margin override the v2 snackbar theme) | T5 toast | PS-14 |
| iOS Apple Pay "stay" info dialog (hard-coded "OK") | dialog (iOS only) | motogo-app-flutter-ios/lib/features/payment/widgets/card_payment_sheet.dart:216-228 | PARTIAL (theme only) | Stavy 5.5 | PS-05 |
| Cart status strip (shell) | T4 strip | core/shell_fab_layer.dart:130-215 (v2: MgStatusStrip) | YES — keep | Stavy T4 | — |
| 3-D Secure web view, Google Pay / Apple Pay system sheets, PlatformPayButton, Stripe CardField internals | native | — | EXCEPTION (not ours / brand rules) | — | — |

## Prioritized improvements

### PS-01 · P1 · LC+L0+L5 · /payment new booking — PaymentScreen
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/payment_screen.dart:1519 (Scaffold seam), :1525-1626; widgets/payment_header_widgets.dart:12-104,239-330; widgets/moto_gallery_card.dart:45-77`
- **Now:** With the flag ON the v2 booking form (dark rank header, 3-step bar, rank dock "Pokračovat k platbě") pushes /payment, which is the OLD screen: mint #DFF0EC page, dark rounded header with a 40 px neon square "←" text glyph, white pill "⏱ Zbývá 29:59 na zaplacení", 200 px gallery that auto-swipes every 3 s, old price card, green-bordered "💳 •••• 4242 Uložená karta", 10 px grey "🔒 Šifrovaná platba" line, white sticky bar with a neon-on-white ElevatedButton + ShimmerSweep loop "Zaplatit 11 893 Kč →". The customer drops out of the premium look exactly at the money moment.
- **Change:** New features/payment/v2/payment_view_v2.dart (+ payment_parts_v2.dart, each < 5k tokens); seam `MgV2.on(context) ? PaymentViewV2(...) : Scaffold(...)` at :1519 INSIDE the existing BackButtonListener/PopScope, same fields and callbacks (_onBack, _doPayment, _processing, _expired, _verifying, charge, amount, _serverAmount, _forceMinCharge, defaultCard, upsell). Layout = Booking board step 3: (1) BookingHeaderV2(currentStep: 2, bikeName, onBack: _onBack) + countdown chip in the header (PS-18); (2) recap ticket overlapping −24 (BookingRecapV2 look: photo 88×64 r12, model 15/800, "pá 23. 10. → ne 25. 10." + dark "3 dny" pill, "12:00 → 19:00 · pobočka Mezná" 12.5/700) — replaces MotoGalleryCard (no auto-swipe); (3) "✓ Cena ověřená serverem: {amount}" tintOk line when _serverAmount != null; (4) CardRoundingNote → T3 info banner (MgStateBanner tone info, same texts/line); (5) card "ZPŮSOB PLATBY" (eyebrow 11.5/800 #55705F, MgIconTileLight card, "{Brand} •••• {last4}" 15/800 + "výchozí" meta; no saved card → "{Google Pay|Apple Pay} · nebo karta") — no "Změnit" (no such action today); (6) upsell (PS-07); (7) trust lines with lock / clock icons 12.5/600 #55705F: "Platba přes Stripe · PCI DSS Level 1 · bez kauce" and "Po klepnutí na Zaplatit máš na dokončení platby 30 minut."; (8) dock = BookingDockV2 pattern: context "Tvoje cena · {n} dny" (+ " · ušetříš {x}" when the existing breakdown has loyalty/discount > 0), price 18/900 neon with MgBump on change, trailing "Rozpis ▴" opening the receipt sheet (showMgSheet + BookingPriceV2 = same rows as PriceSummaryCard, dark total box), MgCta 60 "ZAPLATIT · {charge}" / free label / locked "Čas vypršel" / busy spinner inside with statusLabel + statusNote line under it (#CFE7DA 12.5/600). No ShimmerSweep: the MgCta rank loop is the screen's one CTA fx.
- **Why (king / conversion):** One premium surface from "Rezervovat" to "Zaplaceno"; one price, one obvious CTA with the rank; savings line makes the king feel rewarded; trust facts (no deposit, Stripe) at the decision point.
- **Risk:** View only. Keep charge/amount computation, `_doPayment`, timers and guards in the State; BackButtonListener/PopScope stay outside the seam; nav already hidden on /payment (shell_nav_map.dart:44). Old look untouched. Coordinate with the payments workflow (git diff HEAD -- payment_screen.dart first).
- **Shared primitives:** BookingHeaderV2/BookingStepsV2/BookingDockV2/BookingRecapV2/BookingPriceV2 reused cross-feature; NEW core/v2/chrome/mg_countdown_chip.dart; MgStateBanner; MgSheetFrame

### PS-02 · P1 · LC+L0+L3 · /payment + /sos/payment — resume, restore, edit / swap surcharge, SOS, shop
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/widgets/payment_header_widgets.dart:108-236; payment_screen.dart:1570`
- **Now:** Same old screen; PaymentContextCard = "💳 Doplatek za prodloužení" + amount in a mint well; SOS breakdown rows with emoji; deposit note amber with ℹ️; generic header "Platba · Bezpečná platba přímo v aplikaci".
- **Change:** Same PaymentViewV2 in context mode (Booking board rezimPlatby): dark compact MgRankHero header, ‹ dark 44, title = ctx.label (17/800 white), sub = moto name and/or the reservation number in the app's existing shortId format (#XXXXXXXX) when ctx.bookingId is known; no stepper; countdown chip as PS-18; white receipt card: rows label 14/600 ink / value 14/800, SOS items with MgIconTileLight (moto, truck…), divider, "K zaplacení" 15/800 + amount 26/900 ink, tintOk "Sleva pokryla celou cenu" when free; deposit note → T3 info; "ZPŮSOB PLATBY" card + trust line as PS-01; dock "{label} · {amount}" + MgCta "ZAPLATIT · {charge}".
- **Why (king / conversion):** The customer sees what he pays for (not a generic "Platba"), consistent with the reservation detail he came from.
- **Risk:** None functional. Deviation from the board: rows "Termín teď / Nový termín / Cena teď / Nová cena" need data PaymentContext does not carry → owner decision OD-04.
- **Shared primitives:** same as PS-01

### PS-03 · P1 · LC+L0+L4+L5 · /success — PaymentConfirmationScreen
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/payment_confirmation_screen.dart:296 (Scaffold seam), :312 MotoSuccessHero, :330 successSubtitle, :465 docs card, :513 safety tips, :548 sync badge, :563/:581 _AnimatedCta, :606-614 ✕ top-right; core/widgets/moto_fx.dart:742,805`
- **Now:** All-dark page: flying motorbike + sparks + pulsing hero, "Rezervace potvrzena!" / "Vaše rezervace je aktivní" (vykání), glass card with 🏍️📅⏰ emoji rows, docs card, 📧 row, amber safety tips ALWAYS expanded (long text), 📡 sync badge, CTA with GlowPulse + ShimmerSweep + breathing gradient (GlowPulse/ShimmerSweep ignore reduced motion: moto_fx.dart:742,805) → 4 simultaneous loops; ✕ 26 px top-RIGHT; no booking number.
- **Change:** Seam → MgStateScreen(tone: ok) (Stavy 1.1): dark hero with rank aura one-shot, ✕ TOP-LEFT dark style (= existing close()), tone disc 88, title "Rezervace je potvrzená" (restored: "Rezervace je znovu potvrzená"), why "{bike} · {range}. Motorku ti držíme." 14/600 #CFE7DA; summary card −24: eyebrow "REZERVACE #XXXXXXXX" (existing shortId format of lastConfirmedBookingProvider) + tintOk chip "Potvrzeno", bike 15/800 + dates, pickup row (pin icon, branch 14/800, address 12.5/600, btnGhostLight 44 "Otevřít v mapě" = PickupLocationLink action), rows ČAS VYZVEDNUTÍ / ČAS NÁVRATU (same conditions incl. selfServiceHidesReturnTime); children: "CO BUDE DÁL" MgStateSteps 1 "Potvrzení máš v e-mailu." 2 "Doklady" + T3 banner (verified ok / missing warn with localizeServerReason + docsMissingBody / child bike ok; unknown → nothing) 3 "Vyzvednutí {date} v {time} · {branch}" + late-gate T3 info (tykání key); "Bezpečnostní pokyny ▾" collapsed (MgDisclosure, MgAnimatedSize 300); meta "Potvrzení ti posíláme e-mailem · Rezervaci uvidíš i na webu MotoGo24." (replaces 📡 badge); noDetails → T3 info "Údaje rezervace se nepodařilo načíst" + btnText "Zkusit znovu" (_retryLoad) / loading = skeleton lines; dock: MgCta "MOJE REZERVACE" (existing successCta + close()), docs missing → MgCta "NAHRÁT DOKLADY" (existing push(Routes.docs)) + btnText "Moje rezervace"; support: false. Motion: aura + ✓ disc (PS-16) + MgEnter of the card, one CTA loop.
- **Why (king / conversion):** The king moment: calm, premium, complete (number, when, where, what next) instead of an arcade animation with 4 loops and formal Czech; documents blocker stays the primary action.
- **Risk:** View only; data from the same _bk / draft / _info / _pickup / lateGate; BackButtonListener + PopScope stay outside the seam. Amount chip "Zaplaceno {amount}" only when the draft is the source (useDraft) — the DB path selects no price and must not get a new query (PS-27).
- **Shared primitives:** MgStateScreen, MgStateSteps, MgStateBanner, NEW MgDisclosure (collapsible text, generalised MgTechDetails), PS-16 tone motion

### PS-04 · P1 · LC+L0+L4 · /payment-result — PaymentResultScreen
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/payment_result_screen.dart:215 (Scaffold seam), :226-237 badges, :265-288 lines/pickup/note, :292-313 sync badge, :316-357 buttons, :364-378 ✕ top-right`
- **Now:** All-dark page, 88 px emoji badges (⏳ ! ✓) or the flying-moto hero, glass card with emoji lines, M3 ElevatedButton + outlined white buttons, ✕ top-right; nl/fr 320 title breaks words (PLAN known minor).
- **Change:** Seam → MgStateScreen per kind: success → tone ok (dark hero, aura); pending (not _notPaid) → tone pending (ring sweep = the live loop), primary MgCta ctaLabel, secondary btnText "Ověřit znovu" disabled + spinner inside while _verifying; attention → tone warn (light, btnInk); failed / _notPaid → tone err (light, MgShake once). Title/subtitle = existing outcome texts (MgWordFit, no mid-word breaks); lines → summary card rows with MgIcon mapped from the line emoji (💳 card, 🧾 receipt, 🏍️ moto, 📅 calendar, 📍 pin, ↩️ refresh, else dot) 14/600 ink; pickup → PickupLocationLink v2 look; nextStepNote → "CO BUDE DÁL" step 1; successSynced → meta line with lock icon; secondaryLabel → btnText; ✕ TOP-LEFT = _goNext(closeRoute); support: false (owner D5). Toasts → T5 (PS-14).
- **Why (king / conversion):** Every payment ends on one honest template (what / why / next); pending stays alive and switches itself.
- **Risk:** Emoji → icon map must be total (fallback icon), texts unchanged; timers, PaidChangeQueue subscription untouched.
- **Shared primitives:** MgStateScreen, PS-16 pending→ok morph

### PS-05 · P1 · LC+L0+L1 · Card payment sheet (Android + iOS platform files)
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/widgets/card_payment_sheet.dart:57-80, :284-445 (Android); motogo-app-flutter-ios/lib/features/payment/widgets/card_payment_sheet.dart:65, :216-228, :388-570`
- **Now:** Grabber 40×4 g300, title 18/900, Material IconButton ✕, divider 12 g500, CardField frame #F1FAF7 + 1 px #D4E8E0 (≈1.3:1 border), neon-on-white "Zaplatit X Kč →", 10 px "🔒" line; iOS "stay" AlertDialog with hard-coded "OK".
- **Change:** Shared chrome in features/payment/v2/card_sheet_v2.dart (byte-identical) with slots (wallet button, card field, pay button, note), used from both platform files under MgV2.on (hand-edited, platform hunks kept): grabber 42×5 #CFE3DA, title "Zaplatit kartou" 20/800 + sub "{amount} · bezpečná platba přímo v aplikaci" 12.5/700 #55705F, ✕ disc 44 light top-right (disabled while _processing), official PlatformPayButton unchanged (black, r12, 52), divider label 11.5/800 meta, CardField inside MgInputFrame (white, 1.5 px #7C958A, r12, h56, focus 2 px #0D6E0D + 4 px neon@.28, card icon 20 leading), helper "Celý rámeček je klikací · vložení čísla funguje" 11.5/600 meta, MgBtnInk 52 "Zaplatit {amount} →" (amount neon), processing / _note as inline T3 (pending / info tone), lock line MgIcon 14 + 11.5/600 meta. iOS "stay" dialog → MgDialogFrame with existing "close" label instead of "OK".
- **Why (king / conversion):** Card entry is the most trust-sensitive step; R5.8 bans neon fill on light; the field border must be visible (AA).
- **Risk:** CardField is a platform view: keep the subtree SHAPE constant during confirm (existing comment Android :428-433) — only styles/callbacks change; drag-absorb + PopScope while processing unchanged. Platform files edited by hand in both trees.
- **Shared primitives:** MgSheetFrame chrome, NEW MgInputFrame (lineInput frame for non-InputDecorator fields), MgBtnInk

### PS-06 · P1 · LC+L0+L3 · Payment error sheet (payment, checkout, booking restore, reservation edit)
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/widgets/payment_error_sheet.dart:17-53 (show), :77-190 (body); callers payment_screen_problems.dart:23, shop_checkout_screen.dart:352/402/583/611/633, reservations/booking_restore.dart:73/228, reservations/widgets/reservation_edit_states.dart:115/129/163`
- **Now:** Centered "✗" glyph in a red disc, centered 20/900 title, centered grey message, neon ElevatedButton + grey TextButton; ✕ only in terminal states.
- **Change:** One seam inside show(): MgV2.peek → same showModalBottomSheet (same isDismissible / enableDrag / PopScope semantics, haptic kept) with MgSheetFrame (✕ 44 always; terminal ✕ = onButton as today) + MgStateSheetBody(tone err, title left 20/800 max 2 lines, why = message 14/600 #2C4A3A, support: false — owner D5) + pinned footer: MgBtnInk 52 = buttonLabel, MgBtnGhostLight 48 = secondaryLabel. Chips "Pokus {n} ze {max}" / "✓ Nic jsme nestrhli" NOT added now (callers would have to pass verified facts → OD-06).
- **Why (king / conversion):** Every error says what / why / how calmly in the T2 template; consistent with the rest of v2.
- **Risk:** One seam serves 4 areas (tell res_profile group); pop-then-callback order unchanged; returns Future<void> as today.
- **Shared primitives:** MgStateSheetBody, MgSheetFrame (exist)

### PS-07 · P2 · L0+L1+L3 · Upsell section on /payment (flag reservation_upsell OFF, D7)
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/widgets/upsell_section.dart:32-110, _ProductTile :114-289; uk 320 overflow 6.4 px at :42`
- **Now:** Always-expanded white card, star icon, vertical list of 3 product rows with 1-line ellipsized names.
- **Change:** Board Booking upsell: collapsed card (eyebrow "DOPORUČUJEME K REZERVACI", MgIconTileLight bag, "Z e-shopu MotoGo24" 15/800, "{names} · od {min price}" meta, chevron) → one tap expands (MgAnimatedSize 300) a horizontal ListView of product cards 148 wide (photo 1:1 r12, name 13/800 2 lines, price 14/800 #0D6E0D, size link underlined, MgBtnInk sm "PŘIDAT" / tintOk "Přidáno ✓"), PageScrollPhysics-like snap per card, 24 px peek of the next card; note 12/600 meta.
- **Why (king / conversion):** Disclosure rule (optional extra collapsed), photos sell; no clutter at the money moment.
- **Risk:** Same toggle / size callbacks; horizontal list inside vertical scroll has no conflict. Low priority while the flag is off.
- **Shared primitives:** NEW MgDisclosureCard, snap carousel with peek (reuse home_bikes_for_you_v2 ListView pattern)

### PS-08 · P1 · LC+L0+L5+L2 · /shop — ShopScreen
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/shop/shop_screen.dart:25-198 (header :31-85, voucher :88-143, grid :146-174, states :147-193); uk 320 overflow 30 px at :48`
- **Now:** Old dark rounded header (only the back is v2), voucher = image + small neon pill, grid aspect 0.82 shadow cards, 🛒 40 px button + 18 px green badge, emoji empty/error, CircularProgressIndicator loading.
- **Change:** Profil board S11: dark compact header (MgRankHero ambient "shop": ‹ dark 44, "MotoGo Shop" 17/800, sub 12.5/700 #CFE7DA, right 44 disc with bag icon + neon count badge → push(cart)); voucher hero = MgDarkHero r20 (the one dark block): MgIconTileDark gift 40, "Dárkový poukaz" 22/800, "Libovolná částka · platnost 3 roky · Elektronický nebo tištěný" 14/600, MgCta "KOUPIT POUKAZ" (existing push(voucher)); MgEyebrowDark "MOTOGO SHOP"; grid of white r16 cards (1 px line, photo inset 8 r12 AspectRatio 1, MgImage thumbWidth 500 with well placeholder, name 13/800 2 lines MgWordFit, price 12.5/800 #0D6E0D, MgTag "Vyprodáno" on the photo at 8,8), MgPress .97; loading = MgSkeleton 2×2 cards of the same geometry; error = v2ErrorViewLook (MgErrorView) with the same retry; empty = T3 info.
- **Why (king / conversion):** The shop is a sales surface: the gift voucher (key offer) expanded and premium, products as photos.
- **Risk:** None functional (eshop_visible is OFF live → impact later).
- **Shared primitives:** MgPage header with trailing action, MgDarkHero, MgSkeleton

### PS-09 · P1 · LC+L0+L1+L3 · /shop/:id — ProductDetailScreen
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/shop/product_detail_screen.dart:77-252 (photo :83-114, back :95-101, dots :103-111, description :133-136, sizes :155-175, qty :188-215, add :217-241, size toast :222-224)`
- **Now:** Photo `Expanded` = whatever height is left (≈200 px on 320×690), neon 36 px "←" back without v2 seam (< 44), description cut at 2 lines with NO way to read more, size missing = toast, qty buttons 32 px, neon "Přidat do košíku".
- **Change:** Scrollable v2 page: photo pager 4:3 (same PageView, onPageChanged) with photo-style ‹ disc 44 (night@.8 + blur 12, white ring) and dots (active neon pill 18×6, others white@.6 6×6); name 20/800 + price 20/800 #0D6E0D; attribute tiles in MgWell (eyebrow "BARVA"/"MATERIÁL" 11/800 meta + 13/700 ink) 2-up; description 14/600 max 3 lines + "Více ▾" (MgDisclosure); "Velikost" MgChoiceChip ≥ 44×44 r12; add without size → inline T3 warn "Nejdřív vyber velikost" + chips outlined amber (board) instead of the toast; "Množství" MgQtyStepper 44 + line total 15/800; sold out → T3 error banner; MgDock + MgCta "PŘIDAT DO KOŠÍKU · {price×qty}" → existing add loop, then showMgToast "Přidáno: {qty}× {name}" with action "Do košíku" (= existing cart route, Stavy 13.14).
- **Why (king / conversion):** Full description readable, 44 px targets, the error next to where it is fixed, price in the CTA.
- **Risk:** Inline hint needs one bool set where the toast is raised today (seam line, no new validation). Pager vs iOS edge-back: Cupertino edge region wins at the left 20 px — OK.
- **Shared primitives:** NEW MgQtyStepper, NEW MgDisclosure, photo pager dots (reuse detail pager)

### PS-10 · P1 · LC+L0+L1 · /cart — CartScreen
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/shop/cart_screen.dart:31-163 (AppBar :33-63, "Vyprázdnit" :54-61, empty :65-83, rows :166-200, qty 28 px :203-214, 🗑️ :196, summary :100-157, 10 px note :142-146); uk 320 title truncated :38`
- **Now:** Material AppBar "🛒 Košík" + neon square, one-tap "Vyprázdnit" in the top-right corner, 28 px qty buttons and an emoji trash (≈20 px hit), grey summary panel + neon "K pokladně", 10 px grey note, nav bar stacked under the summary.
- **Change:** Dark compact header ("Košík" 17/800, sub "E-shop MotoGo24"); MgEyebrowDark "V KOŠÍKU"; white grouped list r16: MgIconTileLight (gift for vouchers / tag for goods), name 14/800 2 lines, unit price 12.5/600 meta, MgQtyStepper 44, line total 15/800, MgIconButton trash 44 (error colour) = onRemove; "Vyprázdnit" as red btnText with trash icon in the list header row (board) — away from the top-right corner; summary rows + "Celkem k úhradě" 16/800 / 20/900; note 11.5/600 #55705F; MgDock: context "{n} položky" + MgCta "K POKLADNĚ · {total}" (existing push(checkout)). Empty = Stavy 13.1 T3 info card + MgBtnInk sm "Do e-shopu" (existing go(shop)). Nav hidden (PS-15).
- **Why (king / conversion):** Clear money summary, 44 px targets, lower risk of emptying the cart by accident.
- **Risk:** None functional. Swipe-to-delete NOT proposed (no undo → accidental loss); confirm on "Vyprázdnit" = OD-07.
- **Shared primitives:** MgQtyStepper, MgIconButton, MgDock

### PS-11 · P1 · LC+L0+L5 · /checkout — ShopCheckoutScreen
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/shop/shop_checkout_screen.dart:691-816 (AppBar :694-719, sections :721-760, CTA :762-813), :818-982 promo; widgets/checkout_shipping_section.dart, checkout_payment_card.dart, checkout_summary_section.dart`
- **Now:** Material AppBar + neon square, shadow cards with emoji labels (📦 🏷️ 💳), neon CTA "✅ Potvrdit & Zaplatit →" WITHOUT the amount, promo result "✓ …" in red/green text.
- **Change:** Profil S11 "Doručovací údaje": dark compact header "K platbě" + sub; "Doprava" two option cards (truck / pin tiles, 14/800 + 12.5/600; selected tintOk + 1.5 px #37CF63) — reuse BkOptionRow look; address = MgWell row with pin icon, "Doručení poštou" 14/800 + prefilled address 12.5/600, tap = existing inline edit; "Platba" card as PS-01; "Slevový kód" collapsed row → lineInput + MgBtnGhostLight "Použít" (existing _applyPromo, spinner inside), result line tintOk / #B42318 12.5/700 without emoji, applied codes as MgMeaningChip ok with ✕ 44; summary; CardRoundingNote T3 info; MgDock + MgCta "ZAPLATIT · {total}" with lock icon (free: confirmOrderFree, waive: pdConfirmFree), busy spinner inside; lock line below.
- **Why (king / conversion):** Total inside the CTA = trust + conversion; nothing filled twice (prefill kept).
- **Risk:** resizeToAvoidBottomInset:false stays → v2 must scroll the focused field above the keyboard (Scrollable.ensureVisible on focus; widget test). Order/idempotency logic untouched.
- **Shared primitives:** BkOptionRow (booking v2), MgDock, MgInputFrame

### PS-12 · P1 · LC+L0+L2 · /voucher — VoucherScreen
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/shop/voucher_screen.dart:53-176 (AppBar :55-68, chips :87-117, type :140-148, CTA :152-168, info :193-221); de/uk 320 title truncated :66, uk CTA overflow 9.3 px :163`
- **Now:** Material AppBar "🎁 Dárkový poukaz", wrap of pill chips (2 rows at 320), 📧/📦 type buttons, neon CTA overflowing in uk, 12 px grey info rows with emoji.
- **Change:** Dark compact header "Dárkový poukaz"; voucher image card r16 (asset unchanged, see OD-08); white card: "Hodnota poukazu" 14/800 + 4 equal cells (500 Kč · 1 000 Kč · 2 000 Kč · Jiná; selected ink fill + neon text, 48 h — MgSegmented light), custom amount lineInput with suffix + helper "Částka (min. 100 Kč)" 11.5/700 (amber when < 100); "Typ poukazu" two option cards (mail / gift icons, selected tintOk); "Jak to funguje" ✓ list (check 16 #0D6E0D + 13/600 ink); MgDock + MgCta "KOUPIT POUKAZ · {total}" (disabled < 100 with the blocker in the dock line).
- **Why (king / conversion):** Gift = key sales offer; today cramped and overflowing in uk.
- **Risk:** _normalizeAmount on tap-outside unchanged.
- **Shared primitives:** MgSegmented, MgDock

### PS-13 · P1 · LC+L0 · Platební metody — PaymentMethodsScreen (pushed from Profil)
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/payment_methods_screen.dart:34-128, delete dialog :135, add sheet :186-215 (Android); iOS :20-175 (no add, cardsSavedAtCheckout)`
- **Now:** Material AppBar + neon square, white tiles, 💳 emoji empty state, outlined neon "Přidat novou kartu", 10 px grey Stripe note, AlertDialog delete, toasts.
- **Change:** Shared features/payment/v2/payment_methods_view_v2.dart with allowAdd (Android true / iOS false + cardsSavedAtCheckout note) called from both platform files: dark compact header; cards as card visuals r20 (default = dark gDark with neon "PRIORITNÍ" chip, chip graphic, "•••• 4242" 22/800 tabular, "PLATÍ DO 08/28", holder caps; others white + line), under each btnText "Nastavit jako prioritní" (star) and destructive btnText "Odebrat" (trash) = existing callbacks; delete → MgDialogFrame (safe "Zrušit", destructive "Odebrat", same pop values); empty → T3 info; Android dock MgCta "+ PŘIDAT NOVOU KARTU" + lock line; add-card sheet → PS-05 chrome; loading/error already v2 via state_views seams.
- **Why (king / conversion):** The wallet should feel like a wallet; premium + clear default.
- **Risk:** Platform files by hand in both trees (iOS must never gain manual card entry — App Store 5.1.1).
- **Shared primitives:** MgDialogFrame, MgInputFrame

### PS-14 · P1 · LC+L0 · Leave-payment dialog + toasts in the whole area
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/payment_ui_helpers.dart:15-37; features/auth/widgets/toast_helper.dart:9-71`
- **Now:** AlertDialog with M3 TextButton "Odejít" + neon ElevatedButton "Zůstat a počkat"; showMotoGoToast forces MotoGoColors.dark, an emoji icon and a bottom margin of bnavHeight + 20 even where the v2 nav is hidden.
- **Change:** Dialog → MgDialogFrame(title 20/800, body 14/600, safe = MgBtnGhostLight "Odejít" (true), action = MgBtnInk "Zůstat a počkat" (false); stacked when a label does not fit) — same return values. Toasts: ONE seam in showMotoGoToast: MgV2.peek → showMgToast(title + message, icon from an emoji map ✓→checkCircle, ⚠️/✗→warn/close, ⏳→clock, 🔑→key, 📋→copy, else info) with the v2 margin/lift (T5 night glass, MgMotion.toast).
- **Why (king / conversion):** No old chrome popping over v2 screens; consistent T5.
- **Risk:** showMotoGoToast is app-wide → foundation/shell_home owns it; behaviour (duration, haptic) unchanged.
- **Shared primitives:** NEW "toast seam" in core (foundation)

### PS-15 · P2 · L1+L2 · Shell / router for the shop flow
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/core/v2/shell/shell_nav_map.dart:39-50; core/router.dart:383-386, :157-160`
- **Now:** /cart, /voucher, /shop/:id keep the v2 nav → the screen's own bottom bar sits on top of the nav (two bars ≈ 180 px); /shop is a NoTransitionPage although it is pushed from Profil → no slide and no iOS edge-swipe back.
- **Change:** v2NavHiddenFor += /cart, /voucher, /shop/<id> (not /shop root) once their v2 docks exist; /shop pageBuilder → the existing `_swipeBackPage(state.pageKey, …)` pattern (iOS MaterialPage with edge back, Android unchanged).
- **Why (king / conversion):** One bottom bar, platform-standard back gesture.
- **Risk:** Shared shell/router files (shell_home group); low.
- **Shared primitives:** —

### PS-16 · P2 · L4 · All result states (Stavy T1/T2)
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/core/v2/states/mg_tone.dart:87-120 (_SuccessDisc), :122-145 (_PendingRing); payment_result_screen.dart:86,158 (outcome flips in place)`
- **Now:** ✓ disc = pop + ripple only (no check-path draw); pending → success just swaps the disc.
- **Change:** DESIGN_V22 §5.2: ✓ path draws over 300 ms (PathMetric, MgMotion.pop, MgMotion.out) then pop + one ripple (MgMotion.connector); pending→ok morph: sweep arc grows to 360° in 450 ms (MgMotion.enter, emphasized) then the check draws (AnimatedSwitcher keyed by tone in the T1 hero); one HapticFeedback.lightImpact when an ok disc first appears; reduced motion → end state, no haptic change needed.
- **Why (king / conversion):** The success moment feels crafted and earned; the pending screen visibly "closes" into success.
- **Risk:** Shared primitive; widget tests for reduced-motion end state.
- **Shared primitives:** NEW "tone morph + check draw + success haptic" in core/v2/states

### PS-17 · P2 · L3+L5 · /success and payment texts (copy)
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/core/i18n/translations_cs_pl.dart (successSubtitle, successEmailSent, successSafetyTips, ssLateGateNote) and the de/fr/… equivalents`
- **Now:** Formal register on the thank-you page: "Vaše rezervace je aktivní", "Potvrzení jsme zaslali na váš email", "Nikdy nenechávejte…", late gate "kiosk vám… Chcete… Upravte"; de "Ihre Buchung ist aktiv".
- **Change:** NEW keys only for the v2 views in translations_ext_60_v2_ux_pay_shop_{a,b,…}.dart (8 languages, tykání / informal, gender-neutral), old keys untouched. cs: "Rezervace je potvrzená" · "Rezervace je znovu potvrzená" · "{bike} · {range}. Motorku ti držíme." · "Co bude dál" · "Potvrzení máš v e-mailu." · "Vyzvednutí {date} v {time} · {branch}" · "Kiosk ti motorku vydá {datum} od 12:00. Chceš ji dřív? Uprav čas vyzvednutí — sleva zanikne a rozdíl doplatíš." · "Bezpečnostní pokyny" · "• Nikdy nenechávej klíče v zapalování\n• Vždy zamkni řídítka\n• Při nedodržení podmínek ručíš za škodu" · "Potvrzení ti posíláme e-mailem · Rezervaci uvidíš i na webu MotoGo24." · "Celý rámeček je klikací · vložení čísla funguje" · "Platba přes Stripe · PCI DSS Level 1 · bez kauce" · "Po klepnutí na Zaplatit máš na dokončení platby 30 minut." · "termín ti zatím držíme" · "Zbývá {time} — dokonči platbu" · "Nejdřív vyber velikost" (reuse selectSizeFirst if it fits).
- **Why (king / conversion):** One concierge voice (tykání) across v2; DESIGN_V22 §5.3.
- **Risk:** Text fit at 320 / 360 / 412 in 8 languages (render matrix).
- **Shared primitives:** —

### PS-18 · P2 · L3+L4 · /payment countdown chip
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/payment_screen.dart:421-438, :1534; widgets/payment_header_widgets.dart:77-104`
- **Now:** White pill with ⏱ emoji above the content, same look in the last minutes; ticks for every flow.
- **Change:** MgCountdownChip in the dark header (night glass r14, 1 px neon@.22, live dot + clock icon 16, "Zbývá {mm:ss} na zaplacení" 13.5/800 tabular figures + "termín ti zatím držíme" 12/600 #CFE7DA); last 5 min → warn tone (#FFD36B text, amber dot) "Zbývá {mm:ss} — dokonči platbu" (10.2); while _processing label "Platba probíhá…" (the timer already does not expire then); expired → "Čas vypršel" warn. The dot is the screen's one live indicator (static under reduced motion). Pass `_deadline` read-only to the view. Kept for edit / SOS too (the app logic expires them — honesty over spec 10.1, OD-05).
- **Why (king / conversion):** Urgency without panic; the king is told the slot is held for him.
- **Risk:** Display only.
- **Shared primitives:** NEW MgCountdownChip

### PS-19 · P2 · L2 · /payment performance
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/payment_screen.dart:422-437 (setState every 1 s); widgets/payment_header_widgets.dart:278 (ShimmerSweep); widgets/moto_gallery_card.dart:45 (3 s timer)`
- **Now:** Whole screen rebuilds every second (gallery PageView, price card, upsell list) + a shimmer loop + the gallery timer = 3 tickers on the payment screen.
- **Change:** v2: no gallery timer, no shimmer; heavy parts (recap photo, receipt, upsell) as separate StatelessWidgets with value inputs wrapped in RepaintBoundary so the 1 Hz rebuild repaints only the chip; MgCta loop already in a RepaintBoundary.
- **Why (king / conversion):** Smooth scroll on low-end Androids at the money moment.
- **Risk:** None.
- **Shared primitives:** —

### PS-20 · P2 · L4 · Shop micro-interactions
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/shop/product_detail_screen.dart:228-232; shop_screen.dart:61-81; cart_screen.dart:92-94`
- **Now:** Adding to cart only shows a toast; no feedback on the cart badge; totals jump.
- **Change:** Header cart badge MgBump (MgMotion.bump 450, spring) when the count rises (board cartBump); product cards MgPress .97 + selectionClick; line totals / cart total MgBump on change; reduced motion → none.
- **Why (king / conversion):** Tactile, premium feedback without gimmicks.
- **Risk:** None.
- **Shared primitives:** MgBump, MgPress (exist)

### PS-21 · P2 · L5+L3 · /success summary facts
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/payment/payment_confirmation_screen.dart:238-256 (data selection), reservations/reservation_models.dart:439 (shortId format)`
- **Now:** No booking number; no paid amount; dates as "d. M. yyyy – d. M. yyyy".
- **Change:** Eyebrow "REZERVACE #XXXXXXXX" (same shortId formatting of lastConfirmedBookingProvider); dates in the v2 range format ("pá 23. 10. → ne 25. 10."); glass chip "Zaplaceno {amount}" only when the draft is the source (useDraft; priceBreakdownProvider) — never a new query.
- **Why (king / conversion):** The customer can quote his booking and sees what he paid.
- **Risk:** Formatting only.
- **Shared primitives:** —

### PS-22 · P3 · L4 · Shop grid → product detail
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/shop/shop_screen.dart:167-170; product_detail_screen.dart:87-94`
- **Now:** Plain push.
- **Change:** Shared-element Hero on the first photo (tag "shop-photo-{id}", MgMotion.hero 350 emphasized); reduced motion → plain route.
- **Why (king / conversion):** Continuity, premium feel.
- **Risk:** Hero inside PageView — only for page 0.
- **Shared primitives:** —

### PS-23 · P3 · L1 · Shop grid, Platební metody
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/features/shop/shop_screen.dart:186; payment/payment_methods_screen.dart:57`
- **Now:** Retry only via the error state button.
- **Change:** Brand pull-to-refresh (MgPage refresh) = the existing retry (ref.invalidate(productsProvider) / paymentMethodsProvider). Not on result screens (auto-poll + "Ověřit znovu" exist).
- **Why (king / conversion):** Instinctive refresh where a refresh action exists.
- **Risk:** None.
- **Shared primitives:** MgPage refresh (exists)

### PS-24 · P3 · L2 · All v2 shop / payment images
- **Where:** `Motogo-app-main/motogo-app-flutter/lib/core/widgets/net_image.dart:59`
- **Now:** MgImage default placeholder MotoGoColors.g100 (v1 grey), error = caller emoji box.
- **Change:** v2 views pass placeholder/error = MgColors.well + MgIcon(bag/moto) 24 meta inside fixed AspectRatio boxes (no layout jump; fade 150 ms and memCacheWidth already there).
- **Why (king / conversion):** Clean loading state.
- **Risk:** None.
- **Shared primitives:** —

## Shared core/v2 primitives needed

- **MgCountdownChip** — core/v2/chrome/mg_countdown_chip.dart — header chip: live dot + clock + "Zbývá {mm:ss}" + sub; tones normal / warn (< 5:00) / expired; static under reduced motion; tabular figures.
- **MgQtyStepper** — core/v2/widgets — well pill r999, h44, − n + (44 hit each), disabled min, haptic selectionClick, semantics "Množství {n}"; used by product detail, cart, upsell.
- **MgDisclosure / MgDisclosureCard** — core/v2/widgets — collapsible text / card (generalised MgTechDetails): header row + chevron, MgAnimatedSize 300, closed by default; used by safety tips, product description, upsell.
- **MgInputFrame** — core/v2/widgets — lineInput frame for non-InputDecorator children (Stripe CardField): white, 1.5 px #7C958A, r12, focus 2 px #0D6E0D + 4 px neon@.28, leading icon slot.
- **Tone motion** — core/v2/states/mg_tone.dart — ✓ check-path draw 300 ms, pending→ok morph 450 ms, one lightImpact on ok; reduced motion = end state.
- **Toast seam** — features/auth/widgets/toast_helper.dart showMotoGoToast → showMgToast under MgV2.peek with an emoji→MgIcons map (app-wide; foundation).
- **Card sheet chrome** — features/payment/v2/card_sheet_v2.dart — shared slots used by both platform card_payment_sheet.dart files (and the Android add-card sheet).
- **Snap carousel with peek** — reuse the home_bikes_for_you_v2 horizontal ListView pattern for the upsell carousel.

## Owner decisions / conflicts (not implemented)

- **OD-01** Owner rule D5 (2026-10-16 "žádný kontakt; jasně co je špatně") vs DESIGN_V22 T1/T2 support row "Pomůžeme ti: Zavolat · Napsat nám" on payment errors / pending (Booking board t2, fail3, Stavy 2.2) → owner rule wins: support: false on every payment and shop-payment state. Confirm.
- **OD-02** D1 rounding (pay 15 Kč for 1–15 Kč, waive ≤ 1 Kč) vs Stavy group 6 recommended variant A (waive) → app follows D1 (CardRoundingNote); v2 only restyles it as a T3 info banner.
- **OD-03** /success primary: board "ZOBRAZIT REZERVACI" (detail) vs the app action close() → /reservations list → kept label "MOJE REZERVACE" + existing route (navigation semantics). "Přidat do kalendáře" (§9 #15) not implemented.
- **OD-04** Surcharge payment rows "Termín teď / Nový termín / Cena teď / Nová cena" (Booking rezimPlatby) need data PaymentContext does not carry → not implemented; v2 shows label + amount (+ SOS rows).
- **OD-05** Spec 10.1 / C12 "no countdown for edit / shop" vs app logic that expires every flow after 30 min → chip kept for all flows (honest); a logic change is out of scope.
- **OD-06** T2 chips "Pokus {n} ze {max}" and "✓ Nic jsme nestrhli" need the callers to pass verified facts (new parameters through payment_screen_problems / checkout) → payment logic workflow, not this UI pass.
- **OD-07** Cart "Vyprázdnit" without confirmation (one tap) — a T6 confirm would add a step (flow change) → owner; v2 only moves it away from the top-right corner.
- **OD-08** Voucher asset assets/darkovy-poukaz.webp has Czech text baked in ("Dárkový poukaz · V HODNOTĚ"), shown in all 8 languages → per-language asset or a drawn v2 voucher card.
- **OD-09** Profil board S11 draws product and checkout as SHEETS over the e-shop page; the app has routes (/shop/:id, /checkout) → kept as routes (navigation semantics), drawn with the sheets' content and hierarchy.
- **OD-10** Payment methods: "Změnit" card link on the payment step (board) and choosing another card before paying do not exist today (the default card is charged off-session) → not added.
- **OD-11** Stavy 2.2 "Platbu pořád nevidíme" after [10 min]: the app polls 3 min (18×10 s, payment_result_screen.dart:60-66) then stays pending silently → logic follow-up (§9 #17).
- **OD-12** Register §9 #13: new v2 strings informal in all languages (de du, fr tu…); old keys stay formal in the old look.
- **OD-13** Default card dark / others white on Platební metody (§9 #16).

## Already excellent — keep

- PopScope + BackButtonListener on /payment, /success, /payment-result, /checkout: system back never closes the app or returns to a paid screen; ✕ and back lead to the same destination.
- Card sheet locked while confirming (drag absorbed, PopScope), uncertain close → "processing" → pending result (no double charge); official Google Pay / Apple Pay buttons.
- PaymentResultScreen pending auto-verifies every 10 s and switches itself; PaidChangeQueue results arrive without a tap.
- Terminal error sheets are non-dismissible with ✕ = the main action (never stuck).
- CardRoundingNote shows the 15 Kč rule BEFORE paying (transparency).
- Checkout address prefilled from the profile and collapsed; promo code collapsed (nothing filled twice, disclosure ✓).
- Cart status strip already v2 (MgStatusStrip in ShellFabLayer v2).
- Product detail / payment methods loading + error states already v2 through the state_views seams (MgStateScaffold, MgErrorView, MgLoadingView).
- MgImage: memCacheWidth decode limit + 150 ms fade-in.
- Ready v2 building blocks: MgStateScreen / MgStateSheetBody / MgStateBanner, MgDock, MgCta, BookingHeaderV2 + BookingStepsV2 + BookingDockV2 + BookingRecapV2 + BookingPriceV2, BkOptionRow, MgSegmented, MgSheetFrame, showMgToast, MgV2Back, MgDialogFrame.

## Exceptions (stay as they are)

- Stripe 3-D Secure web view, Google Pay and Apple Pay system sheets (native, not ours).
- PlatformPayButton (official brand buttons — keep exactly).
- Stripe CardField internals (native field; only its frame/text style are ours).
- Level-up celebration (loyalty_levelup_overlay.dart) — unchanged.

## Renders

- **boards:** /tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/uxp/ps/out/bk_default.png, bk_ups.png, bk_wallet.png, bk_wallet_ios.png, bk_res_ok_full.png, bk_res_pend.png, bk_res_fail3.png, bk_modes_v.png (edit / resume / Platební metody / 6.5), bk_sheets.png (Rozpis, T2 offline, 3DS), bk_upO_c.png, bk_nocard.png, pf_shop_sheet.png, pf_sheets3.png (product + checkout sheets), pf_sheets2.png (13.17), st_sheet1-3.png (Stavy 1.16, 2.9, 3.7, 13.1, 13.2, 13.4, 13.14, 6.6)
- **app_today_flag_on:** /tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/uxp/ps/out/app_pay_new_0.png, app_pay2.png, app_res1.png, app_res2.png, app_shop1.png, app_shop2.png, app_misc.png, app_i18n.png (de/uk 320)
- **note:** App renders use the test theme (M3 buttons look purple; in the app old ElevatedButtons are neon green on white) and no emoji font (emoji show as boxes). Real overflows at 320 uk: shop_screen.dart:48 (30 px), voucher_screen.dart:163 (9.3 px), upsell_section.dart:42 (6.4 px), booking/widgets/price_summary.dart:132 (2 px); truncated: cart_screen.dart:38, voucher_screen.dart:66.
