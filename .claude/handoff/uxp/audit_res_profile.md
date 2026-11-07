# Audit · Rezervace + Profil (v2, flag ON) — 2026-11-07

Evidence
- Boards rendered with Playwright at 390 (EXPAND = whole scroll): Reservation (Detail · Kódy připravené, Probíhá, Dokončeno, Čeká na platbu, Mezná s obsluhou, Seznam, Úprava · Prodloužit, Úprava · potvrzení), Profil (Profil, Osobní údaje · úpravy, Moje doklady, Faktury, Dokumenty a smlouvy, Zprávy, vlákno, Oprávnění, Pobočky, Pobočka VN, Věrnostní ranky, Notifikace). PNGs: `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/uxp/rp/b/`.
- App rendered with test/v2/render (render_res / render_profile / render_profile_sub): cs 360×780 with scroll shots (124 cases, all green) + cs/de/uk 320×690 (372 cases, all green). Contact sheets: `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/uxp/rp/v/`.
- Caveat: the edit render fixtures (test/v2/screens/reservations_cases.dart:170,251) hard-code Czech strings ("Klikni na den…", "POKRAČOVAT K PLATBĚ (+4 997 Kč)"), so de/uk edit renders show Czech; the real app strings were read in code (reservation_edit_screen.dart:524-541, 1539-1545).

## LC · Coverage (flag ON)

| Item | v2 look | Where |
|---|---|---|
| Rezervace list (5 filters, empty, filter-empty, stale, loading, error, unpaid, SOS) | yes | reservations/v2/reservations_screen_v2.dart |
| Detail (all statuses, codes ready/withheld/error, late gate, delivery, SOS, stale) | yes | v2/res_detail_view_v2.dart |
| Pickup procedure sheet | yes (showMgSheet) | v2/res_procedure_v2.dart:23 |
| Payment details expander, history expander, docs rows | yes | v2/res_payment_details_v2.dart, res_docs_v2.dart |
| Rating card (detail, Dokončeno) | yes (Home light card) | widgets/res_rating_card.dart:117 |
| **Ride feedback sheet "Napiš nám přímo, co máme zlepšit"** | **NO** (emoji ✍️ 🔒, greenPale, old type) | widgets/ride_feedback_sheet.dart:18-160 |
| Edit chooser + 8 intents + calendar + price + dock + confirm/refund page + load states | yes | v2/res_edit_*_v2.dart |
| Edit size pickers (extras) | yes (seams) | widgets/reservation_edit_extras_section.dart:93,133 |
| Cancel confirm / done / fail dialogs | yes (T6) | v2/res_cancel_v2.dart |
| Profil hub (all states), personal form, nickname, settings sheets (notif, privacy, password, language, currency), delete dialog | yes | profile/v2/** |
| Permissions + "Povolit vše znovu" result | yes (dialog via showErrorDialog seam; toast legacy) | v2/permissions_view_v2.dart, widgets/perm_result.dart |
| Moje doklady, doc-kind sheet, delete dialog | yes | documents/v2/** |
| **Skenování dokladů /docs/scan** (choice, camera error, result overlay, contact fallback, progress dots, loading, done) | **NO** — only the back disc is v2 | documents/document_scanner_screen.dart:731-1238 (seam only at :1173) |
| Camera screen (gallery-free capture) | partly (back disc only; camera = exempt dark) | documents/document_camera_screen.dart:171 |
| Faktury, Dokumenty a smlouvy | yes | documents/v2/invoices_view_v2.dart, contracts_view_v2.dart |
| **Document viewers DocWebView / PdfPages** (contract, protocol, invoice HTML, VOP, GDPR) | **NO** (Material AppBar, MotoGoColors.dark, 15 px title, g200 page) | documents/doc_webview_screen.dart:111-120, pdf_pages_screen.dart:72-81 |
| Zprávy (notes/threads), vlákno, new-thread sheet, AI chat + photo sheet | yes | messages/v2/** |
| Pobočky, Pobočka detail | yes | branches/v2/** |
| **"Motorky na pobočkách" sheet** (opened from v2 Pobočky) | **NO** (MotoGoColors.bg sheet, BranchDetailCard/BranchMotoList old) | profile/widgets/branches_sheet.dart:53, branch_detail_card.dart, branch_moto_list.dart |
| Věrnostní ranky + O programu sheet | yes | loyalty/v2/** |
| Level-up celebration | exception (unchanged by owner rule) | loyalty/loyalty_levelup_overlay.dart |
| **Toasts of the whole area** (`showMotoGoToast`: 62 calls in the area, 131 app-wide) | **NO** — old dark snackbar with emoji glyphs (✓ ✗ ⚠️ ⭐ 💬) | features/auth/widgets/toast_helper.dart:9 |
| Payment methods (Profil tile) | belongs to pay_shop group | features/payment/payment_methods_screen.dart |
| Native camera / gallery / share / system settings | exception (system) | — |

## Findings (most important first)

### RP-01 · P1 · LC · Toasts (area + app-wide)
- Where: features/auth/widgets/toast_helper.dart:9-70 (62 call sites in the area: reservation_edit_screen ×13, settings_sheets ×5, profile_screen ×5, documents_screen ×5, document_scanner_screen ×5, res_rating_card ×4, …).
- Now: with the flag ON every save / copy / error confirmation is the OLD toast: emoji icon text (19 px), old margins, white@.5 message — the most frequent feedback in the area breaks the v2 look.
- Change: seam at the top of `showMotoGoToast`: `if (MgV2.peek(context)) return showMgToast(context, message.isEmpty ? title : '$title · $message', icon: _v2IconFor(icon));` with map ✓/✅ → MgIcons.checkCircle, ✗/❌ → MgIcons.xCircle (tone err), ⚠️ → MgIcons.warn, 💬 → MgIcons.chat, ⭐ → MgIcons.starFilled, 📋 → MgIcons.copy, else MgIcons.info; keep `duration` (2.8 s default per token, 6 s where passed). Haptic stays.
- Why: one consistent premium feedback language; no emoji (V22 §5.3).
- Risk: none functional (same calls, same timing). Follow-up P2: errors that need action become T3/T2 per Stavy §5.1 rule 5.
- Shared: "legacy toast bridge" (core, both trees).

### RP-02 · P1 · LC · Document scanner /docs/scan
- Where: documents/document_scanner_screen.dart:731-766 (choice: emoji 🪪 📕 🏍️, badges 9 px white@.5 incl. literal English "🇪🇺 EU GDPR compliant"), :804-850 (camera error: Material Elevated/Outlined buttons, 📷 emoji), :970 result overlay, :1044 contact fallback, :1161 dots, :1193/:1203 loading/done.
- Change: new views under features/documents/v2/scan_*_v2.dart, seams `MgV2.on(context) ? … : old` with the SAME callbacks:
  - Choice: dark page (exempt, R5.4) + `MgEyebrowDark('DOKLAD')` + title 20/800 white + 3 glass rows (white@.06, 1 px white@.12, r16, min-h 64, `MgIconTileDark` with MgIcons.idCard / passport / licence, label 15/800 white, neon chevron, MgPress .97 + selectionClick); badges = dark chips 11/700 `#9FC4B1` with line icons (lock, phone, shield) — text via i18n (no English literal).
  - Camera error: `MgStateScreen` dark tone ✕ (Stavy 11.6/11.7): "Otevřít nastavení" (existing openFixSettings) · "Zkusit znovu" (existing) · "Zpět".
  - Result + help-after-N-attempts: light `showMgSheet` T2 with `MgSupportRow` (existing Zavolat / Napsat actions).
  - Progress dots: current 20×6 neon pill, others 6×6 white@.3, width animates MgMotion.thumb 300 / MgMotion.out.
  - Done: `MgStateScreen` success T1 (check draw + pop, reduced = static).
- Why: document upload is the #1 blocker before the first ride — it must feel as safe and premium as payment.
- Risk: camera lifecycle untouched (view only). No new dependency.
- Shared: none new (MgStateScreen, MgSheet, MgIconTileDark exist).

### RP-03 · P1 · LC · Document viewers (contract, protocol, invoice, VOP)
- Where: documents/doc_webview_screen.dart:111-120; pdf_pages_screen.dart:72-81, :137.
- Change: `MgAppBar` dark compact (title 17/800, 2 lines → 15/800, never ellipsis) with ✕ 44 close (V22 §6.2 "Viewer = ✕"); page `canvas` behind PDF pages, page cards white r12 + `MgShadows.card`; "Otevřít mimo aplikaci" = `MgBtnGhostLight` in a light bottom bar; loading = MgSkeleton page block (A4 ratio) instead of spinner. Pinch-zoom (existing InteractiveViewer) stays.
- Why: every document the king opens is currently an old Material screen.
- Risk: none (chrome only).

### RP-04 · P1 · LC · Ride feedback sheet
- Where: reservations/widgets/ride_feedback_sheet.dart:18-160.
- Change (V21 §5.5): `showMgSheet` light r22 (grabber, ✕ 44, drag-down); header `MgIconTileLight(MgIcons.messageEdit)` + title `rfImproveBtn` 20/800 + "{bike} · #{shortId}" meta 12.5/700 `#55705F`; lock note as T3 info banner (`MgStateBanner`, MgIcons.lock) with `rfSheetInfo`; textarea with `lineInput` 1.5 px, counter "0/2000" right 11/700; "Odeslat" `MgBtnInk` 52 stuck to the sheet bottom above the keyboard (busy spinner inside). Same `onSending` future / result handling.
- Why: the moment after a ride is the loyalty moment; today it drops into the old look with emoji.
- Risk: keep the "closed while sending" logic at :25-33 byte-for-byte.

### RP-05 · P1 · LC · "Motorky na pobočkách" sheet
- Where: profile/widgets/branches_sheet.dart:53-95 (+ branch_detail_card.dart, branch_moto_list.dart); opened from branches/v2/branches_view_v2.dart:83.
- Change: `showMgSheet` (light, 86 % max, title 20/800 `branchesTitle`); per branch white `MgCard`: type pill = `MgEyebrowDark` (OBSLUŽNÁ / SAMOOBSLUŽNÁ), open/closed chip (`tintOk` / err tint), address + hours rows with `MgIconTileLight`, phone row + `MgBtnText` "Zavolat" (existing), code / capacity rows (`MgRow`), motorcycles via the existing `BranchMotoRowV2`; expand/collapse with `MgAnimatedSize` 300. Load failure → `showMgToast` (via RP-01) or T3 inside the sheet with "Zkusit znovu".
- Why: a v2 screen opens a legacy sheet — visible seam.
- Risk: same fetch code (lines 19-37 unchanged).

### RP-06 · P1 · L3/L5 · Detail action row puts "Zrušit" first
- Where: reservations/v2/res_detail_view_v2.dart:70-74, 104-125.
- Now: for a paid upcoming booking the only tile is a full-width red-outlined "Zrušit rezervaci" right under CO TEĎ (render rdready_0) — the most prominent thing after the hero is destructive. Board: 4 equal tiles.
- Change: tile row (4 × flex, min-h 72, r16 white + `line`, 36 px `iconTileLight`, label 12.5/800 ink, 2 lines allowed; 2×2 grid when a label does not fit at 0.85 — de/fr 320) per state, ONLY existing actions:
  - upcoming: Upravit (edit route) · Navigovat (the pickup `ResLocationRow` navigation) · Dokumenty (`Scrollable.ensureVisible` of ResDocsV2, MgMotion.sheet / MgMotion.out) · Zrušit (red tile `#FDECEC` disc + `#B42318` icon, onShowCancelDialog).
  - active: Upravit · Navigovat (return) · Dokumenty · (SOS stays in CO TEĎ).
  - done: Hodnotit (ensureVisible rating card) · Znovu (`rebookSameMoto`) · Faktura (`onOpenFinalInvoice`) · Jízdy (ensureVisible BookingRidesSection).
- Why: one obvious next step; storno stays reachable but never shouts; conversion actions (Znovu) surface.
- Risk: none functional (taps reuse existing callbacks). Shared: "action tile row" (could live in core/v2/widgets as MgActionTiles).

### RP-07 · P1 · L3 · CO TEĎ primary CTA is "Upravit rezervaci" in every live state; two CTAs when docs are missing
- Where: reservations/v2/res_coted_v2.dart:79-81, 111-114; v2/res_codes_v2.dart:137.
- Now: upcoming + active loop "UPRAVIT REZERVACI"; with missing docs the hero holds TWO neon CTAs ("NAHRÁT DOKLADY A UVOLNIT KÓDY" sm48 + looping "UPRAVIT REZERVACI", render rddocs_0).
- Change (board): exactly one `MgCta` per hero:
  - docs missing → "NAHRÁT DOKLADY A UVOLNIT KÓDY" becomes the looping md56 CTA (same onRelease); Upravit moves to the RP-06 row.
  - self-service, codes visible → "POSTUP NA POBOČCE →" (opens the existing ResProcedureV2 sheet); the text link "Postup při vyzvednutí ›" disappears (no duplicate).
  - staffed upcoming → "NAVIGOVAT NA POBOČKU →" (existing pickup navigation) + "Jak to probíhá ›" text link (existing procedure).
  - active → keep SOS red button; primary = "POSTUP PŘI VRÁCENÍ" if the procedure covers return, else Navigovat (return place).
  - unpaid / verifying / done / cancelled unchanged.
- Why: on pickup day the king needs the procedure, not an edit form.
- Risk: label/target choice only; Upravit remains one tap away.

### RP-08 · P1 · L3 disclosure · branch type, return deadline and return rules missing
- Where: v2/res_detail_hero_v2.dart:71-74 (meta = category · branch); v2/res_sections_v2.dart:43-45 (return "po 9. 11." without time); v2/res_coted_v2.dart:80 (active: heading only); v2/reservation_card_v2.dart:170 (list: "#ID" only).
- Change: title meta "Supermoto · MotoGo24 Velké Němčice · samoobsluha|s obsluhou" (`res.branchType`, category capitalised); list card sub "#ID · {branch}"; return row "ne 18. 10. do {returnHm|23:59}" (`res.returnTime`); in CO TEĎ active and in the return row (self-service) the existing key `v2HomeChkReturnSelf` + a new key `v2uxResKioskReturn` "Vrácením na kiosku poslední den se rezervace dokončí sama." (8 languages).
- Why: owner disclosure rule — branch type and what to do next always visible.
- Risk: none (existing fields).

### RP-09 · P1 · L5 · Rank saving invisible in the reservation
- Where: v2/res_money_v2.dart:53-58 (no loyalty row; `Reservation.loyaltyDiscountAmount`, reservation_models.dart:52, is loaded); v2/res_sections_v2.dart:85-101 (Výbava without rank benefit).
- Change: money row "Věrnostní sleva · {rankName} {pct} %" `−{Money.czk}` (label ink 14/600 + 8 px rank dot, value `#0D6E0D`, V22 §1.4); Výbava card: header chip "Šatna · dveře č. {n}" when a locker code exists + `tintOk` line "Jako {rank} máš výbavu spolujezdce a boty zdarma — přidáš je přes Upravit." for level ≥ 3 and `bookingSource == 'app'` (existing rule).
- Why: "customer must feel like a king" — the saving is the visible proof of the rank.
- Risk: display only; pct from the rank provider already used by the list header chip.

### RP-10 · P1 · L1 · Filter swipe is blind (list) and absent (Zprávy)
- Where: reservations_screen_v2.dart:134-139 (onHorizontalDragEnd, 200 px/s), res_filter_tabs_v2.dart:176-186 (each tab fades its own fill — no sliding thumb); messages/v2/messages_view_v2.dart:66-81 (2 segments, no swipe).
- Now: the board promises "Přejetím prstem přepneš filtr"; in the app nothing follows the finger, no haptic, content jumps; the 200 px/s threshold can flip filters on diagonal scrolls.
- Change: shared `MgSwipeSegments` wrapper: during a horizontal drag the list content translates with the finger (dx × 0.35, rubber band at first/last), the segment thumb (one pill under the labels, moves by drag progress) follows; commit at |dx| ≥ 72 or v ≥ 450 px/s → `HapticFeedback.selectionClick` + new content slides in 16 px from the swipe side with fade (MgMotion.tab 210, MgMotion.emphasized); otherwise springs back (MgMotion.thumb 300, MgMotion.spring). Tap on a tab: thumb slides (AnimatedPositioned, MgMotion.thumb). Reduced motion: instant. Same `_swipeFilter` / `onTab`.
- Why: the #1 instinctive gesture on a segmented list; premium feel = the UI tracks the thumb.
- Risk: gesture conflict with the horizontal tab track (track keeps priority, as today) and vertical scroll (axis lock by slop + higher threshold reduces accidents). Shared: "swipeable segmented pages".

### RP-11 · P1 · L2 · Money CTA in the edit dock
- Where: reservation_edit_screen.dart:1539-1545 (label = `'${proceedToPayment} (+${Money.czk(..)})'`), v2/res_edit_view_v2.dart:204-212 (MgCta uppercases the whole label).
- Now: "POKRAČOVAT K PLATBĚ (+4 997 KČ)" — "KČ" capitalised and the amount breaks "(+4 / 997 KČ)" at 360/320.
- Change: seam passes `saveLabel` and `savePrice` separately → `MgCta(label: 'Zaplatit doplatek', price: '4 296 Kč')` = "ZAPLATIT DOPLATEK · 4 296 Kč" (board; MgCta keeps the amount unbreakable, :94-101); above the CTA in the dock one line "Původně 12 027 Kč → nově 16 323 Kč" 12.5/700 `#CFE7DA` (values from `calc`, already shown in ResEditPriceV2). New key `v2uxResPayDiff` (8 languages).
- Risk: label only; `saveAction` untouched.

### RP-12 · P1 · L2 · Dates wrap and repeat
- Where: v2/reservation_card_v2.dart:81 (list "13. 11. – 15. 11.\n2026" at 360 cs), v2/res_detail_hero_v2.dart:88 + v2/res_timeline_v2.dart:58 (same range twice), v2/res_edit_header_v2.dart (summary pill wraps to 3–4 lines in cs/uk 320/360).
- Change: one formatter `resRangeShort` = "pá 16. 10. – ne 18. 10." (weekday via `tripShortDate`, year only when ≠ current year); list card and timeline header use it; the title block drops the date row (timeline header "pá 16. 10. – ne 18. 10. · 3 dny" like the board); edit summary = one line "TEĎ pá 16. 10. – ne 18. 10. · 3 dny" + price right (status word removed — the header eyebrow says it).
- Why: first-glance clarity, weekday matters for planning.
- Risk: display only; verify 8 languages with the fit matrix.

### RP-13 · P1 · L2 · Loading = bare spinner, counts "0"
- Where: reservations_screen_v2.dart:78-81, 121; edit loading (render reservations__edit__loading); profile hub loading shows fallback "Pilot / PILOT: Pilot" then jumps (profile_header_v2).
- Change: `MgSkeleton` shaped like the result — list: 2 cards (156 photo block, 3 info bars, 48 action bar); edit: summary pill + 2×4 chooser tiles; hub: name bar 160×22 + chip 110×28. One shimmer pass 1.2 s (MgMotion.shimmerLoop, repeats only while loading); reduced: static @.55. Filter count pills hidden until data.
- Why: no layout jump, no false "0 rezervací".
- Shared: "skeleton cards" (MgSkeleton exists).

### RP-14 · P2 · L0 · Branch list without the board's conversion block
- Where: branches/v2/branches_view_v2.dart:91+ (`_BranchCard`: badge, address, hours, "Detail pobočky").
- Change: per card `MgBtnInk` "Rezervovat zde" (→ existing `onBook`, same as the CTA box) above the ghost "Detail pobočky"; trust chips row under the intro (`well` chips with ✓ disc: "Bez kauce", "Výbava v ceně" — texts exist in web CMS? if not → owner decision). Stat tiles (90 min z Prahy, 6XL, 24/7, n motorek) need new copy/data → owner decision.
- Why: Pobočky is a shop window; today it ends in "Detail".

### RP-15 · P2 · L0/L5 · CO TEĎ without rank identity; status pill without countdown
- Where: v2/res_coted_v2.dart:93-96; v2/res_status_v2.dart (ResStatusPill), res_detail_hero_v2.dart:31.
- Change: CO TEĎ top row = `RankFrame` 52 (logo ring + level badge) + eyebrow + rank chip dark pill + dot "Motorkář · −3 %" (board); status pill "NADCHÁZEJÍCÍ · ZA 5 DNÍ" / "AKTIVNÍ · DEN 2/3" (calendarDaysInclusive, plural helper; keys `v2uxResInDays`, `v2uxResDayOf`).
- Why: recognition + anticipation.

### RP-16 · P2 · L0 · Timeline 4 nodes vs board 6/5
- Where: v2/res_timeline_v2.dart:31-52.
- Change: self-service with gear: Zaplaceno · Doklady · Šatna (`gearCollectedAt`) · Protokol (`handoverProtocolFilledAt`) · Motorka (`isHandedOver`) · Vrácení; own gear: drop Šatna; staffed: Zaplaceno · Doklady · Převzetí · Jízda · Vrácení. "Doklady" only if the docs-gate state is already on this screen (codes card withheld reason) — otherwise owner decision (no new fetch). Fit fallback to the vertical layout exists.

### RP-17 · P2 · L0 · Rating card placement (Dokončeno)
- Where: v2/res_detail_view_v2.dart:129-132.
- Change: V21 §5.3 dark variant inside CO TEĎ above "ZNOVU REZERVOVAT" (stars 40 `#F59E0B`, tiles white@.08) — a dark sibling of `HomeReviewLightView` with the same callbacks.

### RP-18 · P2 · L1 · Edit intent: iOS edge-back dead, no transition
- Where: v2/res_edit_view_v2.dart:216-221 (PopScope canPop false while an intent is open → Cupertino swipe-back disabled), :112-117 (`_go` swaps instantly).
- Change: left-edge drag (start x ≤ 24, |dx| ≥ 80 or v ≥ 500) → `_go(null)` with the body following the finger (dx × 0.5) — the same action as the back disc; intent ↔ chooser = fade 0→1 + slide 12 px via an AnimationController around the (non-keyed) body so section state survives (MgMotion.tab 210, MgMotion.emphasized; reduced instant).
- Risk: Visibility(maintainState) kept; no keyed switcher. Shared: "edge back for in-screen steps".

### RP-19 · P2 · L1 · Pull-to-refresh where a refresh exists
- Where: profile/v2/profile_hub_v2.dart:133 (V21 §1.2 prescribes it; onRetry exists), reservations_screen_v2.dart:140 (retry at :76), messages/v2/messages_view_v2.dart (onRetryAdmin / onRetryThreads).
- Change: `MgPage(onRefresh: () async => <existing retry>)`; brand indicator (neon disc, onNeon arc — MgPage :156).

### RP-20 · P2 · L3 copy · Formal register and 3rd person in the area
- Keys: `gateCodeHint` ("…potřebujete ho…"), `protocolFirst` ("podepište"), `procStep*` (ext_30_gate_a.dart:18 "zadejte…vezměte"), calendar `clickDay*`, `moveInstruction`, `selectShortenDirection` ("Klikněte"), `permsChangeHint`, `deleteAccountDesc` ("vaše"), `conversationTopic` ("Napište"), `docsVerifiedDesc` ("zákazník může dostat kódy"), `psCancelRefund` ("platil(a)").
- Change: new v2 keys in `translations_ext_60_v2_ux_res_profile.dart` (tykání / du / tu…, gender-neutral), used only on the v2 side: e.g. "Klepni na den před {start} nebo po {end} — tím rezervaci prodloužíš.", "Doklady ověřeny — kódy k vyzvednutí dostaneš" (board), "Vrátíme ti {amount} ({pct} %) na kartu, kterou se platilo…".

### RP-21 · P2 · L0 copy · Cancel flow vs Stavy 12.21–12.23
- Where: v2/res_cancel_v2.dart:48-82, 114-125.
- Change: safe "Nechat rezervaci" (instead of "Zpět"); rules "víc než 7 dní předem 100 % · 2–7 dní 50 % · méně než 2 dny 0 %"; refund "6 014 Kč" (Money.czk, not "6014"); fail adds `MgSupportRow` (Zavolat); done: "Moje rezervace" primary + "Rezervovat jiný termín" (→ existing `Routes.search`) — navigation addition = owner OK.

### RP-22 · P2 · L2 · Invoices
- Where: documents/invoices_screen.dart:125 (`toStringAsFixed(0)` → "12027 Kč"), :131 (title = number).
- Change: CZK grouping "12 027 Kč" (intl NumberFormat cs NBSP, no currency conversion); title = type name (`typeKey`), sub "ZF-2026-0142 · 30. 9. 2026" (board).

### RP-23 · P2 · L4 · No shared-element photo transition
- Where: v2/reservation_card_v2.dart:72 → v2/res_detail_hero_v2.dart:28.
- Change: `Hero(tag: 'res-photo-{id}')` around `ResBikePhoto` in card, Home ticket and detail hero; flight = rect tween MgMotion.hero 350 / MgMotion.emphasized; reduced: no Hero (MgV2 reduced check).
- Shared: "photo hero transition".

### RP-24 · P2 · L1 · Android predictive back
- Where: core/v2/tokens/mg_theme_v2.dart (no pageTransitionsTheme); AndroidManifest has enableOnBackInvokedCallback.
- Change: `pageTransitionsTheme: {android: PredictiveBackPageTransitionsBuilder(), iOS: CupertinoPageTransitionsBuilder()}` in MgThemeV2.overlay (flag ON only).
- Shared: "predictive back".

### RP-25 · P2 · L0 · Profile settings rows without status
- Where: profile/v2/profile_groups_v2.dart:68-91.
- Change: values from data already on the hub: Notifikace "Push · E-mail · SMS" (enabled consents in the loaded profile map), Soukromí lock "Během pronájmu povinné" when consents are locked; Oprávnění status only if it needs no new query (else owner decision).

### RP-26 · P2 · L3 · Detail hero height on short phones
- Where: v2/res_detail_hero_v2.dart:25 (300 fixed).
- Change: `clamp(220, 0.34 × screenH, 300)` → at 320×690 the CO TEĎ title is in the first viewport.

### RP-27 · P2 · L0 · Edit OK page
- Where: v2/res_edit_states_v2.dart:67 (`PickupLocationLink`, emoji 📍 / 🗺️ on canvas).
- Change: white summary card overlapping the hero −24 (Stavy T1): `MgIconTileLight(pin)` + "K vyzvednutí" meta + branch / address + `MgBtnText` "Otevřít v mapě" (same link action).

### RP-28 · P2 · L2 · Personal form DOB month truncated
- Where: profile/v2/profile_personal_form_v2.dart (render: "05 — ..." at 360).
- Change: month column flex 1.6 vs day/year 1, or short labels "05 · kvě".

### RP-29 · P3 · L4 · Copy code micro-interaction
- Where: v2/res_codes_v2.dart:198-200.
- Change: `HapticFeedback.lightImpact` + copy icon morphs to ✓ for 1.5 s (MgMotion.pop) besides the toast.

### RP-30 · P3 · L0 · List card secondary actions
- Where: v2/res_card_actions_v2.dart:112-175.
- Change: primary CTA label by state like the board ("KÓDY A POSTUP" when codes are out, same onTap); secondary actions into a 44 px "⋯" button opening a light action sheet with the same actions.

## Owner decisions (not implemented)
- OD-1 Codes full-screen ("Kódy na celou obrazovku", board CO TEĎ Probíhá) — new route showing existing codes; recommended.
- OD-2 Filter set "Aktuální · Dokončené · Zrušené · Vše" (board) vs today's 5 filters — changes filter semantics.
- OD-3 Branch stat tiles / feature chips (90 min z Prahy, 6XL, 24/7, n motorek, Bez kauce…) — not in the CMS keys of branchesInfoDefaults.
- OD-4 Branch preselection on "Rezervovat zde" from the list (detail already does `_bookHere`).
- OD-5 Profile tile statuses "3 doklady", "Visa •••• 4242" — need invoices/cards loaded on the hub (new fetch).
- OD-6 CMS branch texts in tykání (board "CMS · tykání [návrh]").
- OD-7 "Omezit animace" switch and "Kontakt" row on Profil (board [návrh]).
- OD-8 Deep link from Výbava "Upravit" straight into the gear intent (`initialIntent` exists, no route param).
- OD-9 Dirty-form guard "Zahodit rozdělané změny?" when leaving edit (V22 §6.2) — new logic.
- OD-10 Scanner badge "Data uložena v telefonu" is inaccurate (V21 P4).

## Already excellent (keep)
- Pinned back + collapsing title bar on the detail; photo-style back over the hero (R6).
- One-shot reveal of the first 6 list cards per session; single dark primary card in the list.
- Codes: big tabular neon codes with copy; withheld = lock + "Čeká na doklady"; error with retry · Zprávy · Zavolat.
- Uniform calendar band with "+" marks in edit (R4); chooser "Otevře se jen to, co měníš".
- Empty list = one dark hero with one CTA.
- Profil hub close to the board (rank strip, attention chip, tiles, grouped lists, red danger rows, version, gear button scrolling to Nastavení).
- Docs hero with two document cards, gate banner, tips collapsed.
- Messages / thread / AI chat, loyalty ladder per tier, permissions with status chips.
- Robust fit logic (word fit, vertical fallbacks) — 372 renders at 320 dp in cs/de/uk without overflow.
