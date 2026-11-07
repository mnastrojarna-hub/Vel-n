# 2 · DEDUPE AND JUDGEMENT

Order of judgement: (1) fidelity deviations from the boards / spec → fix; (2) gestures / motion / display the spec prescribes or that are platform standard → build; (3) anything beyond the design → owner decision; (4) design vs owner rule → owner rule wins (§6c). Filters: no functional change (a gesture or button only calls an action that already exists on that screen), V22 budgets (one dark block per window, rank only on dark carriers, ≤ 2 loops), gesture conflicts (maps, pagers, scroll, iOS edge-back), performance, value for the "king" feeling and conversion. All safe P1 kept; best P2 kept; gimmicks dropped.

**Merged duplicates (one owner each):**
- Toast look + emoji bridge: RP-01 + PS-14 (toast part) + ASM-08 + SH-11 → FND-7.
- Error dialog hierarchy + emoji in labels: SH-28 + ASM-29 (core part) → FND-6.
- Predictive back / consistent push: SH-14 + CB-31 + RP-24 + F-29 (transition part) → FND-4 (theme) + SH-14 (router).
- Tab fade-through: SH-13 → FND-4 `mgTabPage` + SH router.
- Shared-element photos: SH-18 + CB-14 + RP-23 → FND-10 `MgHeroPhoto` + tags placed by SH / CB / RP.
- Photo viewer: CB-02 + F-03 → FND-10 `MgPhotoViewer`.
- Swipe segments + directional switch: RP-10 + F-15 + F-08 + CB-09 (month) → FND-8 / FND-9.
- In-screen step back: RP-18 + ASM-28 → FND-8 `MgEdgeBack` / `MgStepFade`.
- Sheet drag-to-dismiss + motion: SH-16 + SH-35 (+ drag claims of CB-03 / CB-04 / ASM-16) → FND-5 / FND-6.
- Pull-to-refresh + iOS dark overscroll: SH-17 + CB-18 + RP-19 + PS-23 → FND-14 + call sites.
- Skeleton shapes: SH-23 + CB-08 + RP-13 + F-18 + F-19 + PS-08 → FND-13 + call sites.
- Loops off-screen / loop budget: SH-08 + SH-42 + F-34 → FND-17 (+ F-34 in RR).
- Tone motion ✓ draw / morph: SH-36 + PS-16 + ASM-24 (done morph) → FND-18.
- Count-up: SH-30 + F-17 → FND-11 `MgCountUp`.
- Logo ring / SOS pill / club emblem: CB-29 + F-14 + F-17 + ASM-07 + ASM-09 + SH-38 → FND-19 extractions.
- Choice cards: ASM-03 + ASM-13 + PS-11 + PS-12 → FND-20 `MgChoiceCard`.
- Number / date display: SH-37 + F-21 + RP-12 + RP-22 + PS-21 → FND-12 helpers.
- Nav hidden on /sos*, /cart, /voucher, /shop/:id: ASM-10 + PS-15 → FND-15.
- Calendar copy: SH-29 (calendar part) → CB-24 (the calendar file is catalog's); offline line → FND-7.
- Scanner: RP-02 + ASM-22 / 23 / 24 → ASM (one package owns the scanner file).
- CTA leading glyph: F-05 → FND-20 `MgCta.leadingIcon`.

**Judgement highlights:**
- Kept as board / spec fidelity (not "new ideas"): Home S2 cancel link + countdown ring, S6 "PŘIPRAVENO", S7 "VÝDEJ OD", club disclosure "Výhody a ligy", tier preview sheet (Main board + V2 §2.5), catalog compact bar, booking express "Máme to připravené" (V2 §8, MEDIUM risk with blocker auto-expand tests), reservation action tiles + CO TEĎ labels (Reservation board), SOS nonstop-line dock (V22 §2.4 SOS; calls the existing `callMotoGo()`), status strip "+n" (v1 C2), nav slide 110 % (V2 §4.1), AI FAB lift + first-run coach (V2 §4.2), push banner (V22 §6.4 — missing from all audits, added as SH-43).
- Changed from the audit: F-09 draggable sheet → map-height clamp; ASM-20 global flip → additive param; RP-20 keeps the v1 §0.8 protected texts; SH-27 keeps only the spec'd S8 line + day ring.
- Gesture conflicts resolved centrally (G4): maps own their drags; inner horizontal scrollables win; calendar beats the bike pager inside its box; iOS left edge = back; zoomed photos never close or page.
- Performance: marquee + loops paused off-screen, RepaintBoundary on every loop, payment page without own timers, Moje list per-card slivers, scanner thumbnails decoded at 192 px.

**Build order:** FND-0 … FND-20 (one step, reviewed) → the 6 packages in parallel (disjoint files) → integration pass: Hero pairs (Home ↔ Reservation detail, catalog ↔ bike detail), toast bridge everywhere, render matrix 320 / 360 / 412 × 8 languages, board vs app PNG review, iOS scratch analyze + tests.
