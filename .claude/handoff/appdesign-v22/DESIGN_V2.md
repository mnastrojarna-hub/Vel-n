# MotoGo24 app · design iteration 2 (DESIGN_V2)

Final spec for the v2 boards (Main, MotoKatalog, MotoDetail, Booking, Reservation, new RankStyly) and for the later Flutter port.
It **extends** `appdesign_spec.md` (v1 spec): everything there stays valid unless a section below replaces it. Mockup "today" = **neděle 11. 10. 2026, 9:41**, Czech UI, tykání.
Sample customer: rank **3 Motorkář**, 5 points (1 to Stálý jezdec), R1 = Husqvarna 701 SM, Velké Němčice, pá 16. 10. 12:00 → ne 18. 10. 23:59, **12 027 Kč**, paid, documents verified, codes ready. R2 (new booking) = BMW R 1200 GS Adventure, Mezná, pá 23.–ne 25. 10., **10 189 Kč**.

Shared, paste-ready code (validated with `dclint/lint.py` + `dclint/fuzz.js`, harness `appdesign/gen/Harness.dc.html`):

| File | What | Paste where |
|---|---|---|
| `shared/rank-theme.css` | `@property` registrations (theme morph), 5 tier blocks (glow geometry, ambient length, header texture), **20 level blocks** `.rk-1…rk-20` (generated, contrast-solved), components: `.rk-cta` (+ tier loop fx), `.rk-chip`, `.rk-hero` (+ `.rk-amb`), `.rk-frame` / `.rk-arc` / `.rk-lv` / crown / laurel, `.rk-emb`, `.rk-sw`, `.rk-bar`, landing classes, reduced motion | helmet style block, right after the board base CSS |
| `shared/rank-theme.js` | `rankTheme(level, points?)` → `{cls, name, pct, tier, tierCs, chip, chipShort, levelLine, nextLine, gearLine, gearValue, arcSt, tierBar[], tierBarLabel, tierBarNext, tiers[5], ringBg, btnBg, hex, acc, accLight, on, glow, icon, glyph, rule, …}` | first lines inside `renderVals()` |
| `shared/logo.html` | REAL logo tile (assets/logo.webp redrawn from `gfx/logo-icon.svg` paths) + LogoRow (frame ring + arc + level badge + "MOTO GO 24 / Půjčovna motorek") + bare tile | CSS → style block; markup → header |
| `shared/cta.html` | canonical primary CTA: hero (in-card), **sticky bar** "REZERVOVAT · 10 189 Kč", catalogue card action | CSS → style block; markup where used |
| `shared/nav.html` + `nav.js` | bottom nav, 5 tabs incl. PROFIL avatar (rank ring + arc), 8 languages, no-overlap guard, liquid pill | CSS → style block; markup = last child before FAB; `nav: navVals({...})` |
| `shared/ai-fab.html` + `ai-fab.js` | global AI button (full / mini / peek / hidden), one-time coach bubble, expand-into-chat panel with context chips | CSS → style block; markup after nav / sticky bar; `ai: aiFabVals({...})` |
| `shared/levelup.html` + `levelup.js` | guaranteed level-up celebration (sequence, tier title card, burst per tier, reason line, theme morph, blocked/safe moments) | CSS → style block; markup = LAST child of root; root `onClick="{{ lu.tap }}"` |

Generator (do not hand-edit generated parts): `appdesign/gen/gen.js` (source `research/rankTheme.js`) → `shared/rank-theme.css` level blocks, `shared/rank-theme.js` table, `gen/contrast.md`.

---

## 0. Owner feedback → where it is answered

| # | Owner (meaning) | Answer in v2 |
|---|---|---|
| 1 | Glow + buttons customised by rank; rank everywhere, also Home | §2 rank theming: 5 material tiers drive CTA fill/edge/glow/loop, logo ring + arc + level badge, chip, header aura/texture/minted edge, nav pill, PROFIL avatar, AI ring, club card, level-up; Home §5 weaves it into 9 places |
| 2 | AI reachable any time, bottom-right | §4.2 global AI FAB on every shell screen, mini above sticky bars, expand-into-chat |
| 3 | PROFIL tab, labels fit all 8 languages | §4.1 Title-case labels measured in Montserrat; runtime gap guard + short forms; golden tests |
| 4 | Home: SOS + "moje trasy / zážitky / jízdy s MotoGo / soukromé jízdy"; Sultan feeling | §5 Home = concierge: "Tým pro tebe" ticket checklist, concierge note, Moje zážitky hub, "Tvoje linka MotoGo24"; SOS §4.3 |
| 5 | Keep the full-screen catalogue; calculator stays | §7 light touch only |
| 6 | Detail uncluttered | §6 explicit visible / collapsed / moved list (nothing lost) |
| 8 | Reserve button prominent | §6.6 sticky 60 px rank CTA **"REZERVOVAT · 10 189 Kč"** always visible; same principle on catalogue card and Booking pay |
| 9 | Clarity first, no information lost, top graphics + motion | §1 visual language + motion system; §9 preservation additions |
| 10 | Premium, simple, unique by rank (graphics first) | §1, §2 |
| 11 | Level-up animation can never be missed | §3 mechanism + `levelup.js` demo on every board (`levelUpDemo` prop) |
| 12 | Returning customer: booking optically minimal | §8 "Máme to připravené" express booking, one pay button |
| 13 | Use the plan MD | PLAN.md phases kept: this doc = phase 2 output; boards + RankStyly = phase 3 |
| 14 | Bottom nav: no overlap, great animation | §4.1 |
| Fuel | Never promise a full tank; reserve light must not be on (VN must not); washing only VN | §5.3 S9 copy, Reservation §10 |
| Fidelity | "chybí logo, chybí všechno" | §1.1: real logo, real LogoRow, real texts, real photos, every screen fully composed |

---

## 1. Visual language (all boards)

### 1.1 Fidelity rules (production mockups, not wireframes)
1. **Real logo** from `shared/logo.html`; the logo is **never recoloured** — rank = wide ring + glow + progress arc around it (as `logo_header.dart`). LogoRow subtitle rises from white@.38 to **white@.62** (10 px text, AA).
2. **Status-bar-safe header** on every screen: 47 px status bar (9:41, signal, Wi-Fi, battery in white) inside the dark header; home indicator 34 px inside the nav / sticky bar.
3. **Real data only**: bike photos `…/media/motos/…` (URLs in v1 boards), route covers `…/media/routes-mirror/…` (§5.6), real prices from the price engine (v1 spec §6), real branch addresses, real rank table. Unknown customer data is drawn `[like this]`; example user content is marked "ukázka". The Velké Němčice branch photos exist only on `https://www.motogo24.cz/gfx/pobocky/velke-nemcice/*-640.webp` (the app loads them from there); boards may load only the Supabase media bucket, so branch photos stay `[fotka pobočky]` unless the canvas allows that host.
4. **Real texts** from `lib/core/i18n` where they exist (keys named in the sections); new copy is listed verbatim here (cs), needs all 8 languages in the port.
5. **Icons**: 24-grid line icons (stroke 2, round) as in v1 boards; tab icons in `nav.js`; tier icons in `rank-theme.js`.
6. Every screen fully composed: header, content, nav (tab screens), FAB, toasts. Nothing grey except genuinely unknown data.

### 1.2 Web v2 family carried into the app
| Web v2 (motogo-web-php) | App v2 equivalent |
|---|---|
| `.lp-panel-card` radial `#24563B → #0E2A1C → #0A1F14` | `gDark` hero / header, first stop = **rank aura** (`--rk-aura`, white text ≥ 4.6:1) |
| `.lp-btn-primary` neon + `lpGlow` 2.2 s + `lpShine` 3.2 s | `.rk-cta` + `rkGlow` + tier fx in the shine slot (shine / sheen / glint / edge / ember) |
| `lpScan` 3.6 s top line on live cards | ticket scan only in live states (S1, S2, S7–S9) |
| `.lp-reveal` 16 px / 550 ms / 70 ms stagger on scroll | `reveal` token on section entry (first build per session) |
| `lpDot` ping | live indicator (one per screen) |
| `lpRtDraw` route draw + `lpRtPin` | route sketches draw once (900 ms) when they enter |
| count-ups on stats | count-up **only for personal non-price stats** (rides, km, places, "ušetřil"), 700 ms once; prices never count, they `bump` |
| `pbKen` Ken Burns on photos | one-shot 8 s slow zoom on the hero photo (never infinite) |
| `.lp-chip` / `.lp-chip--hot` | rank chip, choice chips, filter chips (v1 C4) |

### 1.3 Motion system
- Tokens = v1 spec §2.7 (press .97 + haptic, color 180, sheet 300, pop 300, enter 450, reveal 550/70, bump 450, connector 700, strike 300, tab 210 fade-through, push 300).
- **Max 2 infinite loops per screen**: (1) the one primary CTA (`rkGlow` + tier fx in the same slot), (2) one live indicator (ping / scan / recording dot). Everything else one-shot; loops pause off-screen (`TickerMode`).
- **Default style = end state.** Every animation only animates *from* (fill `both`); with reduced motion (`.rm` on root + `prefers-reduced-motion`) all `animation`/`transition` are off and the end state is shown. Shared CSS already follows this.
- Every tappable: press scale .92–.97 + `selectionClick` haptic; selection changes `pop`; state changes cross-fade (`enter`).
- Theme changes (level-up) **morph** over 600 ms via registered custom properties (`@property`); instant where unsupported.

### 1.4 Board base rules (repeat of DC format + new)
- Root: `class="{{ rootCls }}"` with `rootCls = 'mg ' + rk.cls + (LU.landCls ? ' ' + LU.landCls : '') + (rm ? ' rm' : '')` and `onClick="{{ lu.tap }}"`. The root MUST carry `rk.cls` (`rk rk-N t-tier`): shared button styles are scoped `.rk …` so they beat the base reset `.mg button{background:none}`.
- Never put `{{ … }}` inside CSS or HTML comments. Never write the literal style tag inside comments (it breaks extraction).
- Rank preview inside a board (tier rail sheet, RankStyly): put `rk rk-N t-tier` on a **wrapper**, never on the button itself.
- Props on every board: `rank` (int 1–20, default 3), `reducedMotion` (boolean), `levelUpDemo` (enum `Vypnuto` · `+1 rank (jízda dokončena)` · `+2 ranky (výhra měsíce)`; default `Vypnuto`, Main default `+1 rank (jízda dokončena)`), boards with nav also `jazyk` (enum `cs, en, de, es, fr, nl, pl, uk`).
- Inner scroll container (as MotoKatalog v1 `.pg`) so expanded sections never get clipped; pinned chrome (nav, sticky bar, FAB) at the artboard bottom.

---

## 2. Rank theming system

### 2.1 Principles
1. Rank is an **accent layered on the brand**. Layout and sizes never change by rank — only material, light, the one-shot effects and the **step marks**; the only rank-specific copy is the chip/club texts and the one Home motto line (§2.2a).
2. Rank drives: primary CTA (fill, label, edge, glow, loop fx), logo/avatar ring + progress arc + level badge, rank chip, header aura + static texture + minted bottom edge + one-shot ambient, nav active pill, PROFIL avatar, AI-FAB ring, tier emblem/rail, tier progress bar, level-up burst.
3. Rank **never** touches: prices (`#0D6E0D` on light, neon on dark), ✓ (neon/green), ⚠ (amber), errors, **SOS** (`#D92D20` fills, `#EF4444` dots/icons), focus rings (neon), links, **Apple Pay / Google Pay** buttons.
4. Tier is decided by the **level number**; colours come from `loyalty_levels.color_hex` (editable in Velín) and every contrast-sensitive token is **solved** (Flutter port: run the solver at runtime, `research/rankTheme.js` → `core/rank_theme.dart`).
5. The look of a new rank waits for the reveal; **the discount never waits** (§3.6).

### 2.2 Tiers
| Tier (cs) | Levels | Material | CTA label | Ring | Loop fx (CTA slot) | Header ambient (once/session) | Texture (static) | Level-up burst |
|---|---|---|---|---|---|---|---|---|
| **Silnice** | 1–5 | brand neon; rank green tints the low stop | `#08230F` | solid rank colour | `shine` 3.2 → 2.6 s, 1–3 streaks by step (§2.2a) | `headlightOnce` 900 ms, α by step | topographic contours | confetti |
| **Kovová liga** | 6–9 | brushed metal, 4 stops @115°, specular top, hairlines | `#1A1405` warm / `#0B1512` cool | conic metal | `sheen` 4.8 s (wide soft band) | `sheenOnce` 900 ms | brushed hairlines | sparks |
| **Liga drahokamů** | 10–16 | cut gem, prismatic 2 stops, facet planes, 1.5 px bright edge | navy `#0A1F33` (10–11) / white (12–16) | 12-facet conic | `glint` 3.6 s (3 star sparkles) | `prismOnce` 1.1 s | low-poly facets | shards |
| **VIP klub** | 17–19 | pearl / foil card, framed foil edge, **crown glyph**; VIP red never a fill | ruby `#881337` (17) / onyx `#14100A` | double ring + gold, crown on top | `edge` 4 s (light runs round the frame) | `auroraOnce` 2.4 s (α ≤ .22) | guilloché | crown drop |
| **Legenda** | 20 | molten gold → orange, **laurel glyph** | `#241A06` | gold-orange conic + laurel | `ember` 4.4 s (sweep + 2 embers) | `auroraEmbersOnce` 2.8 s | guilloché + laurel watermark | laurel + embers |

Glow per tier: alpha .50/.55/.58/.62/.66, blur 22/26/28/30/34 px, halo from Kovy up (α .12–.24), pulse ring 7–10 px. Glow colour = rank colour except Startér (brand neon), grey metals 7/9/19 (cool-tinted), VIP 17 (rose `#F43F5E`, not SOS red), Legenda (`#FF8C00`).

### 2.2a Step inside the tier (owner 2026-10-15: "ranks 3, 4 and 5 look almost identical")
Most customers stay in Silnice for years (rank 6 = 10 points), so **every level must look different inside its tier**, not only the ring/glow hue. One step `st` of `sn` per tier (Silnice 1–5, Kovy 1–4, Drahokamy 1–7, VIP 1–3, Legenda single), all generated per level in `shared/rank-theme.css` (`--rk-st/--rk-sn/--rk-gx/--rk-shb/--rk-sh/--rk-amba/--rk-shd`, `@property`-registered → a level-up inside a tier slides the next mark in):
| Where | What changes with the step | Notes |
|---|---|---|
| Primary CTA | **marks under the label** (`::before` dim slots = tier size, `::after` lit = step, label colour 62 % / 20 %): Silnice lane dashes, Kovy rivets, Drahokamy facets, VIP crowns, Legenda none; glow blur +0–12 px and a step halo (α 0 → .32, 10 → 24 px) | fill + label untouched (contrast-solver values); hidden on ghost/disabled; marks draw in once (700 ms), redraw on the level-up landing |
| Logo ring (LogoRow, previews) | the same marks **on the ring's bottom edge** (row ≤ 26 px, label colour 85 % / 24 %); ring glow 16 → 28 px | level badge stays on top |
| Silnice loop | shine 3,2 → 2,6 s; step 3–4 add a 2nd streak, step 5 a 3rd (same pass, not an extra loop) | gated by `--rk-rs` so nested previews of other tiers keep their own fx |
| Header ambient | Silnice now has one too: headlight sweep 0,9 s once per session, strength α .10 → .26 by step (other tiers unchanged) | off with reduced motion |
| Home header | **motto line under the greeting**: marks (rank accent) + one line per level (`rk.motto`, ≤ 256 px → one line at 360 dp), e.g. 3 "Výbava spolujezdce i boty zdarma", 4 "Patříš ke stálé partě MotoGo24", 5 "Příští rank tě pustí do Kovové ligy" | `role="note"` + `rk.mottoAria` ("Motorkář · Silnice, stupeň 3 z 5. …") |
Copy for other places: `rk.stepLabel` "Silnice 3/5", `rk.marksLine` "3 pruhy z 5", `rk.stepLine`. Flutter: `RankTheme.step/steps` + `MgStepMarks` painter (CTA, ring, header); reduced motion = marks shown static, no draw-in, no sweep.

### 2.3 Per-level tokens
CSS custom properties on `.rk-N` (all generated; see `shared/rank-theme.css`):
`--rk` color_hex · `--rk-acc` accent text on dark · `--rk-accl` accent text on light · `--rk-uid` / `--rk-uil` marks on dark / light · `--rk-chip-bg/-tx/-bd` · `--rk-aura` · `--rk-glow`, `--rk-glow-a` (rest), `--rk-glow-s` (peak), `--rk-glow-0`, `--rk-halo` · `--rk-b1…b4` + `--rk-ang` CTA fill · `--rk-on` CTA label · `--rk-e1…e4` edge · `--rk-ring` (paint) + `--rk-ring2` (VIP gold outline) · `--rk-arc` progress arc. Tier class adds `--rk-gb/--rk-hb/--rk-pulse/--rk-ambd/--rk-tex`.
JS (`rankTheme`) returns the same values as strings for inline use (`ringSt`, `btnSt`, `swSt`) plus copy (`chip`, `levelLine`, `nextLine`, `gearLine`, `rule`, `tierBarLabel`).

### 2.4 Contrast (WCAG 2.x, computed by `gen/gen.js`; 0 failures)
Targets: CTA label ≥ 4.5:1 on **every** fill stop; chip text ≥ 4.5; accent text ≥ 4.5 on `#0E2A1C` and on `#DFF0EC`/`#FFF`; marks ≥ 3 (uiLight on white, ring on night); white on header aura ≥ 4.5. Deep gems 12–16 have fills only 2.2–3.5:1 against the night bar (unavoidable with a readable white label) → their boundary is the 1.5 px facet edge (≥ 3.86:1) + glow.

| L | Rank | Tier | color_hex | CTA fill (4 stops) · label | label min cr | fill vs night | edge vs night | chip text / bg · cr | accent on dark (vs #0E2A1C) | accent on light (vs #DFF0EC / #FFF) | uiLight vs #FFF | ring/uiDark vs #0A1F14 | white on aura |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Startér | road | `#9CA3AF` | `#8DFF86` → `#70EF7A` → `#54DF6F` → `#37CF63` · `#08230F` | 8.16 | 8.42 | 8.42 | `#9CA3AF` / `#253D34` · 4.61 | `#9CA3AF` 6.05 | `#646870` 4.74 / 5.59 | `#8C939E` 3.10 | `#9CA3AF` 6.79 | `#387F49` 4.88 |
| 2 | Jezdec | road | `#86EFAC` | `#8DFF86` → `#7EF487` → `#6EEA87` → `#5FDF88` · `#08230F` | 9.86 | 10.17 | 10.17 | `#86EFAC` / `#214A33` · 7.15 | `#86EFAC` 10.94 | `#407353` 4.69 / 5.53 | `#5BA375` 3.03 | `#86EFAC` 12.27 | `#3D7C57` 4.98 |
| 3 | Motorkář | road | `#4ADE80` | `#8DFF86` → `#74F27F` → `#5AE479` → `#41D772` · `#08230F` | 8.90 | 9.18 | 9.18 | `#4ADE80` / `#18472C` · 6.10 | `#4ADE80` 8.82 | `#287845` 4.61 / 5.44 | `#37A45F` 3.16 | `#4ADE80` 9.89 | `#2E784C` 5.37 |
| 4 | Stálý jezdec | road | `#22C55E` | `#8DFF86` → `#6DED7A` → `#4DDC6D` → `#2DCA61` · `#08230F` | 7.74 | 7.98 | 7.98 | `#22C55E` / `#114327` · 4.97 | `#22C55E` 6.74 | `#157A3A` 4.59 / 5.42 | `#1DA951` 3.07 | `#22C55E` 7.56 | `#247244` 5.89 |
| 5 | Věrný zákazník | road | `#14B8A6` | `#8DFF86` → `#6BEB86` → `#48D885` → `#26C485` · `#08230F` | 7.41 | 7.64 | 7.64 | `#14B8A6` / `#0F4132` · 4.63 | `#14B8A6` 6.17 | `#0D766A` 4.67 / 5.50 | `#12A695` 3.04 | `#14B8A6` 6.92 | `#206F56` 6.05 |
| 6 | Bronzový jezdec | metal | `#CD7F32` | `#E9C5A3` → `#D69657` → `#CD7F32` → `#B9722D` · `#1A1405` | 4.81 | 4.52 | 3.70 | `#D38E4B` / `#2D3820` · 4.56 | `#CD7F32` 4.89 | `#945B24` 4.71 / 5.55 | `#CD7F32` 3.14 | `#CD7F32` 5.48 | `#5A6338` 6.41 |
| 7 | Stříbrný jezdec | metal | `#C0C0C0` | `#E3E3E3` → `#CBCBCB` → `#C0C0C0` → `#ADADAD` · `#0B1512` | 8.28 | 7.68 | 6.12 | `#C0C0C0` / `#2A4236` · 5.98 | `#C0C0C0` 8.45 | `#686868` 4.73 / 5.57 | `#929292` 3.11 | `#C0C0C0` 9.47 | `#567B6D` 4.72 |
| 8 | Zlatý jezdec | metal | `#FFD700` | `#FFED8C` → `#FFDE2E` → `#FFD700` → `#E6C200` · `#1A1405` | 10.54 | 9.91 | 7.77 | `#FFD700` / `#354618` · 7.34 | `#FFD700` 10.96 | `#7A6700` 4.73 / 5.57 | `#AD9200` 3.05 | `#FFD700` 12.28 | `#687D28` 4.61 |
| 9 | Platinový jezdec | metal | `#E5E4E2` | `#F3F3F2` → `#EAE9E7` → `#E5E4E2` → `#CECDCB` · `#0B1512` | 11.70 | 10.84 | 8.51 | `#E5E4E2` / `#30483C` · 7.80 | `#E5E4E2` 12.09 | `#696968` 4.66 / 5.50 | `#939291` 3.11 | `#E5E4E2` 13.56 | `#597C6E` 4.63 |
| 10 | Diamantový jezdec | jewel | `#7DD3FC` | `#7DD3FC` → `#7DC2FC` → `#7DB1FC` → `#7DA0FC` · `#0A1F33` | 6.61 | 6.81 | 8.80 | `#7DD3FC` / `#204540` · 6.34 | `#7DD3FC` 9.22 | `#416E83` 4.71 / 5.55 | `#5D9CBA` 3.03 | `#7DD3FC` 10.33 | `#417E7B` 4.67 |
| 11 | Prémiový zákazník | jewel | `#38BDF8` | `#4FC5F8` → `#4FAEF8` → `#4F97F8` → `#4F80F8` · `#0A1F33` | 4.60 | 4.74 | 6.77 | `#38BDF8` / `#15423F` · 5.21 | `#38BDF8` 7.17 | `#227195` 4.61 / 5.43 | `#2F9FD0` 3.00 | `#38BDF8` 8.04 | `#2C7D83` 4.81 |
| 12 | Mistr silnic | jewel | `#3B82F6` | `#3573DA` → `#365EDA` → `#374ADA` → `#3835DA` · `#FFFFFF` | 4.55 | 2.21 | 3.86 | `#629BF8` / `#15383F` · 4.53 | `#4F8FF7` 4.83 | `#2F68C5` 4.56 / 5.37 | `#3B82F6` 3.68 | `#3B82F6` 4.68 | `#2D6782` 6.22 |
| 13 | Šampion | jewel | `#6366F1` | `#575AD5` → `#6759D5` → `#7758D5` → `#8757D5` · `#FFFFFF` | 4.82 | 3.14 | 5.59 | `#8C8EF5` / `#1C343E` · 4.54 | `#8285F4` 4.84 | `#575AD4` 4.66 / 5.50 | `#6366F1` 4.47 | `#6366F1` 3.86 | `#3C5C80` 6.92 |
| 14 | Veterán MotoGo | jewel | `#8B5CF6` | `#714BC9` → `#824BC9` → `#934BC9` → `#A44BC9` · `#FFFFFF` | 4.74 | 2.91 | 5.56 | `#A783F8` / `#22323F` · 4.54 | `#A079F8` 4.82 | `#784FD4` 4.61 / 5.43 | `#8B5CF6` 4.23 | `#8B5CF6` 4.07 | `#4B5882` 6.96 |
| 15 | Elitní jezdec | jewel | `#A855F7` | `#8443C2` → `#9543C2` → `#A543C2` → `#B643C2` · `#FFFFFF` | 4.59 | 2.92 | 5.56 | `#BB7AF9` / `#27313F` · 4.55 | `#B670F8` 4.87 | `#8A46CB` 4.66 / 5.50 | `#A855F7` 3.96 | `#A855F7` 4.35 | `#565682` 6.89 |
| 16 | Ambasador | jewel | `#D946EF` | `#B139C3` → `#B739B6` → `#BD39AA` → `#C3399D` · `#FFFFFF` | 4.78 | 3.48 | 5.35 | `#DF64F2` / `#2E2E3E` · 4.59 | `#DC55F0` 4.83 | `#A535B6` 4.71 / 5.55 | `#D946EF` 3.46 | `#D946EF` 4.98 | `#69507F` 6.87 |
| 17 | VIP | vip | `#EF4444` | `#FFF5F6` → `#FFEAED` → `#FFDCE2` → `#FECDD6` · `#881337` | 6.80 | 12.24 | 3.67 | `#F26969` / `#322E22` · 4.52 | `#F26262` 4.90 | `#BF3636` 4.69 / 5.53 | `#EF4444` 3.76 | `#EF4444` 4.58 | `#7B4C4A` 7.06 |
| 18 | VIP Gold | vip | `#D4AF37` | `#F7E9B8` → `#E6C869` → `#D4AF37` → `#B8932A` · `#14100A` | 6.54 | 5.94 | 3.43 | `#D4AF37` / `#2E3F20` · 5.40 | `#D4AF37` 7.31 | `#7B6520` 4.78 / 5.64 | `#AE902D` 3.08 | `#D4AF37` 8.19 | `#6E7B39` 4.61 |
| 19 | VIP Platinum | vip | `#F1F5F9` | `#FFFFFF` → `#F6F8FB` → `#EAEFF5` → `#DCE3EC` · `#14100A` | 14.66 | 13.32 | 12.46 | `#F1F5F9` / `#324A3F` · 8.77 | `#F1F5F9` 14.03 | `#656769` 4.82 / 5.68 | `#919395` 3.08 | `#F1F5F9` 15.73 | `#5C7B72` 4.63 |
| 20 | Legenda MotoGo | legend | `#FFD700` | `#FFE27A` → `#FFD700` → `#FF9A1F` → `#FF6B00` · `#241A06` | 6.00 | 6.03 | 9.40 | `#FFD700` / `#354618` · 7.34 | `#FFD700` 10.96 | `#7A6700` 4.73 / 5.57 | `#AD9200` 3.05 | `#FFD700` 12.28 | `#8F6F1E` 4.71 |

Nav chrome on `#0A1F14`: inactive label `#B8D4C6` 10.89:1, inactive icon `#9FC4B1` 9.03:1, active label `#FFFFFF`. SOS pill `#D92D20`/white 4.83:1 (`#EF4444`/white 3.76:1 → dots/icons only).

### 2.5 Where rank shows (per screen)
| Surface | Rank expression |
|---|---|
| Header (Home, Profil, Katalog) | aura + texture + minted 2 px bottom edge (`e1 → uid → e3`) + one-shot ambient; LogoRow frame ring + arc + level badge (+ crown VIP / laurel Legenda); rank chip |
| One primary CTA per screen | `.rk-cta` material + glow + tier loop |
| Other buttons | neutral (ghost-dark / secondary); a second rank-material button on the same screen only as `.still` and never next to the primary |
| Nav | active pill in CTA material (no loop), PROFIL avatar ring + arc |
| AI FAB | ring in tier material, soft glow; never brighter than the CTA |
| Home club card | emblem, tier bar, tier rail (5 swatches) + preview sheet |
| Lists / prices / statuses | none (meaning colours stay) |
| Level-up | per-tier burst, tier title card, morph |

### 2.6 Reduced motion
`MgMotion.reduced()` (OS setting or Profil → Nastavení "Omezit animace"): no loops, no ambient, no burst, no ring stepping (final ring shown), no morph (instant), static celebration card with "Pokračovat" immediately and **no music**; textures and materials stay (they are static).

---

## 3. Guaranteed level-up (owner point 11)

### 3.1 Facts (live DB, migrations 20260917 / 20260916)
Points = completed non-test bookings from app **and** web: 1–6 days = 1 b., 7+ days = 2 b.; `level = min(20, ceil((points+1)/2))` (level L from 2L−2 b.). Effective points = max(raw, floor) − penalty + bonus. Rank never drops on its own (admin demotion only). Discount L % on **app** bookings only; free passenger gear (690) + rider boots (290) + passenger boots (290) from rank 3, app only. Monthly winner +4 b. (+2 ranks) runs although `loyalty_leaderboard` is off (1. 10. 2026 = first award). Celebrated baseline already exists: `profiles.loyalty_celebrated_level`, RPCs `loyalty_get_celebrated` / `loyalty_advance_celebrated` (GREATEST) — **missing in STATE_2/3** (document when the port touches them).

### 3.2 Guarantee
Shown **exactly once per account per new level**, at the **first safe moment** after detection, never over a blocked screen, counted as seen only after the reveal (≥ 2.6 s) or "Pokračovat"; several level-ups merge into **one** sequence.

### 3.3 Detection triggers → one `LevelUpGate.check(source)` (dedupes in-flight)
T1 cold start · T2 resume · **T3 every route push/pop and tab switch (new)** · T4 any tap (throttle 45 → **20 s**) · T5 bookings realtime (staff completion, kiosk auto-return) · T6 optional `loyalty_events` realtime · T7 optional push "Nový rank" · T8 3-min foreground poll · **T9 blocker cleared → immediate replay of the stored pending item (new)**.
Baseline = `max(server celebrated, local mirror)`; if local > server → re-advance server (self-heal). First run with server 0 and level ≥ 2 → short "Vítej v klubu MotoGo24 — jsi {rank}" welcome variant.

### 3.4 Safe moments
Allowed: shell tabs, reservation detail (codes not enlarged), `/success`, `/loyalty`, `/booking` with keyboard closed and no sheet.
**Blocked (wait, keep pending, persisted `mg_loyalty_pending_<uid>`)**: `/payment` + charging, `/sos/*`, route navigation / riding, document scanner / camera, handover signature, full-screen door codes (and the 15 min after a kiosk return while codes stay valid), keyboard, input sheets/dialogs, onboarding/language/permission overlays, app not resumed. Worst case = the next screen he opens.

### 3.5 Sequence (shared `levelup.html`)
1. Card opens where he tapped (scrim with new-rank glow). Crossing a tier (5→6, 9→10, 16→17, 19→20) first shows a 1.3 s title card: "Vstupuješ do kovové ligy" / "Vstupuješ do ligy drahokamů" / "Vítej ve VIP klubu" / "Jsi Legenda MotoGo".
2. Emblem = real logo in the **old** ring → steps through every intermediate rank colour (220 ms/step) → locks on the new ring with the tier burst (+ crown drop VIP / laurel Legenda) and "+N" when N ≥ 2.
3. Kicker "NOVÝ RANK" (`loyaltyLevelUpKicker`) or "MIMOŘÁDNÝ POSTUP" (`loyaltyMegaLevelUpTitle`, N ≥ 2); name 30/900; "Sleva {pct} % · platí hned na každou jízdu v appce"; gear unlock line "Nově: výbava spolujezdce a boty zdarma" when crossing to 3.
4. **Reason line** (no backend needed): "Za jízdu na {bike}" (a reservation became completed since the last check) · "Vyhrál jsi měsíc {září} · +2 ranky" (bonus +4) · none for admin restore.
5. "Pokračovat" (`loyaltyContinue`, new-rank CTA) appears at max(2.6 s, reveal + 0.9 s); a back press before 2.6 s does not mark it seen (once; the second time it does).
6. Speaker toggle "Zvuk oslav" (music only when not reduced and the setting is on; volume .7, fade-in 600 ms; boards show the toggle only).
7. Reduced motion: static final card, no music.

### 3.6 Theme hold and landing
`rankThemeLevel = pending ? from : status.level` — CTA, glow, ring, chip, pill keep the old look until the reveal; at the reveal the theme **morphs behind the dialog** (600 ms). Prices use `status.level` immediately. After "Pokračovat": ring arc fills from 0, chip/frame/emblem pop, header ambient replays once (`rk-lA`/`rk-lB`), concierge note "Gratulujeme, jsi {rank} · sleva {pct} % platí hned", a deník entry "Nový rank: {rank} ({pct} %) · {reason}" appears in Moje zážitky. Demotion: no celebration, quiet 300 ms morph down.

### 3.7 Board demo contract (`levelup.js`)
`const LU = levelUpVals({ P, S, set, reduced: rm, blocked, bike, boardH })`; `rk = rankTheme(LU.level)` for the look; prices from `rankTheme(LU.priceLevel).pct`. With `levelUpDemo` on, a level-up "happened in the background": **the next tap anywhere** plays it (unless `blocked`; the blocker's close handler calls `LU.check()`). Reservation demonstrates the kiosk-return case: codes full-screen open = blocked; closing them plays the celebration.

### 3.8 Optional backend (owner decision, SQL as text only — CLAUDE.md rule 3)
`loyalty_events` (realtime, own-read RLS) + push "Nový rank" from booking completion / monthly award / admin adjust; fold `celebrated_level` into `get_loyalty_status()`. Sketch in `research/rank.md` §5.10. Not needed for the boards.

---

## 4. Global chrome

### 4.1 Bottom nav (shared `nav.html` + `nav.js`)
- **Tabs**: Domů · Motorky · Rezervace · Trasy · **Profil** (replaces the hamburger). Paths `/`, `/motorky`, `/reservations`, `/routes`, `/profile` (v1 spec §4.1 mapping; `/ai-agent` no longer highlights Rezervace — the chat is a focused flow).
- **Look**: full-width night glass `#0A1F14`@.96 + 20 px blur, top r20, neon hairline, 64 + 34 px. Icons 24 line; inactive icon `#9FC4B1`, label `#B8D4C6` 11/700; active label white 11/800, icon in `--rk-on` on the **rank pill** 52×30 (CTA material + edge, static glow). PROFIL = 30 px avatar (person glyph on `#0E2A1C`) in the **rank ring** + progress arc (same `arcSt` as the logo).
- **Badges**: Rezervace = 10 px `#EF4444` dot when a booking needs action (unpaid, documents missing), one ping on appear. Profil = `#D92D20` count pill (unread messages; mockup `[n]`).
- **Labels (Title case, Montserrat 11/800, widths px)**; second word = short fallback:

| | Domů | Motorky | Rezervace | Trasy | Profil |
|---|---|---|---|---|---|
| cs | Domů 35.5 | Motorky 48.8 | Rezervace 60.5 | Trasy 31.1 | Profil 31.6 |
| en | Home 34.8 | Bikes 32.2 | Bookings 55.5 | Routes 40.9 | Profile 38.7 |
| de | Home 34.8 | Bikes 32.2 | Buchungen 68.2 | Routen 42.5 | Profil 31.6 |
| es | Inicio 32.2 | Motos 35.9 | Reservas 52.8 | Rutas 33.4 | Perfil 31.5 |
| fr | Accueil 43.4 | Motos 35.9 | Locations 56.9 | Itinéraires 59.6 / **Balades** 46.6 | Profil 31.6 |
| nl | Home 34.8 | Motoren 49.4 | Boekingen 64.0 | Routes 40.9 | Profiel 38.7 |
| pl | Start 28.7 | Motory 41.6 | Rezerwacje 67.8 / **Wynajmy** 56.2 | Trasy 31.1 | Profil 31.6 |
| uk | Головна 48.7 | Мото 30.9 | Оренда 46.5 | Маршрути 64.5 / **Траси** 35.9 | Профіль 51.3 |

  Measured result: at 390 dp every label fits its column − 8; at 360 dp the smallest real gap is 13.7 px (no overlap); at 320 dp fr needs "Balades". New i18n keys `tabHome/tabBikes/tabBookings/tabRoutes/tabProfile` (+ `tabRoutesShort` fr/uk, `tabBookingsShort` pl) in all 8 languages, both trees; old `nav*` keys stay until the old nav is deleted.
- **No-overlap guarantee (code)**: labels never ellipsis / wrap / `FittedBox`; `TextPainter` measures at w800 and computes real gaps `col − (wᵢ+wᵢ₊₁)/2` (≥ 6 px) and edge gaps `(col − w)/2` (≥ 4 px, both ends). Label size = `textScaler.scale(11)` capped at **12.65 px (1.15)**, then a **fit ladder for the whole row** — the first rung where every gap passes wins: ① user size, a short form only for a label in a failing spot → ② row clamped to **11 px (scale 1.0)**, short forms again only where needed → ③ row **10 px** (safety net, never reached at 320–430 dp). `nav.js` contains the same algorithm (`fit` = rung, px, gaps). Verified (Chromium + Montserrat 800, `scratchpad/navfit/verify_navjs.js`): 8 locales × 320/360/375/390/412/430 dp × scale 1.0/1.15/1.3 all pass, worst real gap 6.1 px / edge 6.4 px (uk 320 dp); at 320 dp × 1.15 cs, de, nl, uk and fr take rung ② (nl Motoren|Boekingen would overlap by 1.2 px at 12.65 px), en, es and pl (Wynajmy) keep 12.65 px. Whenever the row is drawn smaller than the user's size (rung ②/③ or scale > 1.15), long-press shows the large-content bubble (icon + label 2×); `Semantics` always the full word. Golden tests: 8 locales × 320/360/390/430 dp × scale 1.0/1.15 (assert gap ≥ 6, edge ≥ 4, rung per the table above).
- **Motion** (all one-shot): press scale .92 + selectionClick; pill moves with a spring (~300 ms, overshoot) and a **liquid stretch** (scaleX 1.45 at mid-flight); active icon fills + `pop`; label colour 180 ms; content fade-through 210 ms; re-tap active tab = scroll to top + 3 px icon nudge; level-up landing cross-fades pill + avatar ring. Hidden with keyboard and on focused flows (slide out 110 %).

### 4.2 AI floating button (shared `ai-fab.html` + `ai-fab.js`)
- One global button in the shell `Stack`, **bottom-right**, above content/status strip, below sheets and global overlays. Replaces the Home bottom-left FAB (hard-coded "AI"), the v1 header bot and the scroll-to-top FAB. Respects `feature_flags.ai_assistant` (live, app never read it).
- **Look**: 56 px dark glass disc (`#24563B → #0A1F14`), 2 px **rank ring** (tier material) + soft rank glow, neon chat-spark glyph, **no text, no idle loop**. Label/tooltip = `aiServiceAgent` (cs "AI Servisní agent", de "KI-Serviceagent", es/fr "… IA", uk "AI Сервісний агент").
- **Placement** (`bottom` = lowest obstruction + 12, animated 300 ms):

| Screen state | Obstruction | FAB |
|---|---|---|
| Tab screens (Domů, Motorky, Rezervace, Trasy, Profil) | nav 98 | 56 px, bottom 110, right 16 |
| + status strip | nav + 8 + strip 52 = 158 | 56 px, bottom 170 |
| Detail `/moto/:id` | sticky bar 136 | **mini 44 px, no glow**, bottom 148 (≥ 12 px above the bar, ≥ 29 px from REZERVOVAT) |
| `/booking` | sticky summary (~136) | mini 44 px, bottom 148 |
| `/routes/:id`, places multi-select, edit intents | their sticky bar | mini above it |
| `/payment`, charging, `/success`, `/payment-result`, chat itself, `/messages/:id`, keyboard, `/docs/scan`, `/route-nav*`, login/register/onboarding, any sheet | — | **hidden** (fade + scale .8, 150 ms) |

- **FabAvoid v2** (owner 2026-10-15: never cover a primary CTA or SOS, not even by peeking). Screens wrap controls in `FabAvoid(kind:)` — `cta` (card REZERVOVAT / VYBRAT / JINÝ TERMÍN, ticket CTA, CO TEĎ CTA, Zaplatit doplatek), `sos` (header SOS pill, ticket `.sosc` circle, S1 red CTA, Rezervace SOS button + SOS tile), `tap` (small / secondary tappables: hearts, copy buttons, secondary rows), `keep` (text the button must not be lifted onto: card name lines, Rozpis breakdown, ticket checklist, code tiles). Slot = the 56 px disc inflated by 8 px. On scroll-idle (120 ms) the first free option wins: **rest** → **lift** (bottom = zone top + 12, max +56 px, lifted slot clear of every zone; 300 ms spring) → **off** whenever a `cta`/`sos` is under the rest or the peek slot (fade + scale .8 in 150 ms, `IgnorePointer` + `ExcludeSemantics`, springs back when the slot is free) → **peek** (translateX +26, opacity .85) only when nothing but `tap` zones are in the way. While the finger drags: never lift (no chasing) → peek, or off as soon as a `cta`/`sos` crosses the peek slot. Same function in the boards (`fabAvoid` in Main / MotoKatalog / Reservation; board prop „Ukázka · AI tlačítko“ shows the scrolled phone viewport). Consequence (estimated from the CSS + Montserrat widths): on the first 390 × 844 screen the ticket CTA sits under the slot in Domů S3–S6 and S9 and the CO TEĎ CTA in Rezervace „Čeká na platbu“ / „Zrušeno“ → the button yields until ~40–60 px of scroll (S7 / S10 / „Kódy připravené“: peek over secondary buttons; „Dokončeno“: lift 33 px; S0–S2 / S8: rest). Scroll bottom padding = obstruction + 56 + 24.
- **Opening**: container transform — the disc expands into the chat panel (350 ms `Cubic(.2,0,0,1)`; reduced: 150 ms fade). Header = real logo tile + "AI asistent MotoGo24" + "Odpovídá hned · 24/7". Greeting "Ahoj, [přezdívka]! S čím ti pomůžu? Odpovídám hned, kdykoli." Context chips per screen:
  - Domů / Rezervace: "Kódy a postup na pobočce", "Kam o víkendu?" / "Prodloužit rezervaci", "Jak vrátit motorku"
  - Motorky: "Poraď mi motorku", "Jaký potřebuju řidičák?", "Jak funguje samoobsluha?"
  - Detail: "Zeptej se na {motorka}", "Hodí se pro spolujezdce?", "Kolik stojí přistavení?"
  - Booking: "Jak funguje vyzvednutí od 12:00?", "Můžu termín později změnit?", "Platba a storno"
  - red "SOS · nehoda nebo porucha" first while `sosAllowed` (existing `aiSuggestSos`).
  The conversation is kept in a provider for the session (today it is lost on pop). Boards show the question + typing dots + a note (no invented answers).
- **First run**: one coach bubble "Zeptej se kdykoli. Jsme tu pro tebe." (8 languages), dismissed on tap, never repeated.

### 4.3 SOS access
- Rule unchanged: SOS visible only while `sosAllowed` (`!endedBySos && (active || (inRentalTerm && paid))`). Outside a rental Home shows no SOS; help = "Tvoje linka MotoGo24" (§5.10), AI chat, Profil → Pomoc & podpora.
- While `sosAllowed`: **header pill "SOS"** (76×44, `#D92D20`, white 13/800, alert icon) left of the bell; red 48 px SOS circle in ticket S8/S9 (≥ 16 px from the CTA); status strip priority 1 for an unfinished report; Rezervace list badge + detail action row + CO TEĎ; Profil → Pomoc; AI SOS chip. Recommended addition (owner): static 44 px SOS chip on `/route-nav*`.
- Never in the nav, never next to the AI FAB, never in the bottom 120 px. Plain tap (no hold) + heavy haptic: it only opens `/sos`; calling and sending stay explicit steps there.

### 4.4 Status strip
v1 C2 unchanged (SOS · payment · documents · route · cart, one item, "+n"). The AI FAB rides above it (bottom 170).

---

## 5. Screen 1 · Domů v2 "Tým pro tebe" (concierge + grafts)

**Artboard 390 × 2820**, nav pinned (DOMŮ active), AI FAB full at bottom 110 with coach bubble, content in an inner scroll. First viewport on a 390 × 844 phone = header + marquee + the whole ticket (CTA bottom at y 653, FAB top at 678). Props: `rank`, `ticketState` (S0, S1, S2, S3, S6, S7, S8, S9, S10; default S6), `levelUpDemo` (default `+1 rank (jízda dokončena)`), `jazyk`, `unread` (boolean, default true), `rozjetaTrasa` (boolean, default false), `reducedMotion`.

| # | y | Block |
|---|---|---|
| 1 | 0–225 | Header (rank hero) |
| 2 | 235–267 | Marquee (only if set in Velín) |
| 3 | 279–669 | Ticket (the one dark hero) |
| 4 | 681–729 | "Kdy jedeš příště?" date pill |
| 5 | 741–793 | "MotoGo ti píše" (only with unread) |
| 6 | 817–1081 | Tvůj klub (rank card) |
| 7 | 1105–1561 | Moje zážitky (personal hub) |
| 8 | 1585–1901 | Vybrali jsme ti (routes near the next branch) |
| 9 | 1925–2285 | Motorky pro tebe |
| 10 | 2309–2489 | Pobočky |
| 11 | 2513–2617 | Tvoje linka MotoGo24 |
| — | 2654–2710 / 2722–2820 | AI FAB / nav (scroll padding = 98 + 56 + 24) |

### 5.1 Header (`.rk-hero`, bottom r24, minted edge)
- 0–47 status bar (white).
- 55–117 **LogoRow** (`shared/logo.html`): frame 62 (logo 52 + 5 px tier ring) + progress arc (`rk.arcSt`, 5 of 6 b. → half of the level) + level badge "3" + crown/laurel by tier → tap `/loyalty` (as today). "MOTO GO 24" 22/900 · "PŮJČOVNA MOTOREK" (`logoSubtitle`). Right: **bell** 44 px (white@.08, border neon@.22) with count "[n]" → `/messages`; while `sosAllowed` the red **SOS** pill sits 8 px left of the bell.
- 129–153 **Greeting** 20/800 by time of day: "Dobré ráno / Dobré dopoledne / Dobré odpoledne / Dobrý večer, [přezdívka]" (nickname → first name initcap; none: "Ahoj, jezdče" + link "Nastav si přezdívku") → nickname dialog.
- 155–173 **Motto line** (§2.2a): step marks + `rk.motto` 12.5/700 `--rk-acc`, rank-specific, one line (all following rows move down 21 px; header min-height 246).
- 178–196 **Concierge note** (MG glyph in `--rk-acc` + 13.5/600 `#CFE7DA`, max 2 lines, never ellipsis). Priority:
  1. just levelled up: "Gratulujeme, jsi {rank} · sleva {pct} % platí hned"
  2. birthday (`date_of_birth`): "Všechno nejlepší, [přezdívka]! Celý tým MotoGo24 ti přeje šťastné kilometry."
  3. S7: "Dnes od 12:00 je Husqvarna tvoje." · 4. S9: "Dnes vracíš · postup máš níž."
  5. unread (if the §5.5 row is off-screen): "Máš od nás vzkaz: [titulek] ›"
  6. anniversary of the first completed booking: "Je to rok, co jsi s námi poprvé vyrazil na [motorka]."
  7. by state: S6 "Na pátek máme všechno připravené." · S3 "Chybí nám jen tvoje doklady." · S0 "Kam vyrazíš? Rádi poradíme." · otherwise season line "Sezóna 2026 · [km] km · [n] jízd · [n] míst".
- 206–234 **Rank chip** "Motorkář · sleva 3 %" → `/loyalty`.
- Motion: header ambient once per session (tier — Silnice included since 2026-10-15); greeting/motto/note `enter` 450 ms (motto marks draw in 700 ms); note text change cross-fades.

### 5.2 Marquee
16 px side inset, h32 r999, `#0E2A1C`, neon 12.5/700, `bannerProvider`; sample "» V zimním období od 1.11.2026 do 25.3.2027 zavřeno." Static under reduced motion.

### 5.3 Ticket (dark hero r20, Hero `res-img-{id}`)
States, priority and S0–S10 bodies = v1 spec §7 with these v2 changes. **S6 (artboard)**:
- **Photo 128** (cover + bottom scrim): top-left eyebrow pill "ZA 5 DNÍ"; top-right 40 px glass "⋯" → Více sheet (Detail rezervace · Dokumenty · Zrušit rezervaci); bottom-left "Husqvarna 701 SM" 20/800 + "MotoGo24 Velké Němčice · samoobsluha" 12.5/600; bottom-right ok pill "✓ PŘIPRAVENO".
- **Dates row** (44): calendar icon + "pá 16. 10. 12:00 → ne 18. 10. 23:59 · 3 dny" 13/700 + trailing ghost link "Upravit" (pencil) → edit chooser.
- **"TÝM PRO TEBE"** eyebrow (11.5/800, `--rk-acc`) + vertical checklist (rows 25 px, 2 px connector `gProgress`, nodes 18 px):
  - ✓ "Platbu máme · 12 027 Kč"
  - ✓ "Doklady máš ověřené"
  - ✓ "Kódy máš připravené · brána, šatna, motorka" — only when `doorCodes.sentToCustomer`; "šatna" only when the booking needs the locker (`_booking_needs_locker`, rented gear; own gear → "brána, motorka")
  - ◉ "V pá od 12:00 tě čeká v kóji č. [4] · výbava za dveřmi č. 8" + ½ badge (ⓘ = late-pickup gate text) + trailing 40 px "Navigovat" circle → maps Boudky. Box from `motorcycles.box_number` (drawn `[4]`, the bike can move), door from `get_booking_gate_info.locker_door`, line hidden for own gear.
- **CTA** (rank, 56) "KÓDY A POSTUP NA POBOČCE" → `/reservations/:id` scrolled to CO TEĎ.
- Other state copy (v2 deltas): S3 ⚠ "Chybí nám tvoje doklady, bez nich ti kódy neuvolníme" → "NAHRÁT DOKLADY"; S4 Mezná ◉ "Čekáme tě v pá ve 12:00 · Mezná 9, Pelhřimov · nonstop" ("Motorku máš připravenou" only after B2 `prepared_at`); S5 ◉ "Přivezeme ti ji · [adresa] · [čas]"; **S9 VN** "Vrať do 23:59 · nádrž plnit netřeba, jen nesmí svítit rezerva · vrať ji umytou · vrácení na kiosku rezervaci dokončí samo"; **S9 Mezná** "Tankovat ani mýt netřeba, jen ať nesvítí rezerva"; S8/S9 red SOS circle; S10 stars → "Díky, [přezdívka]! Tvoje hodnocení si přečteme." + "Jízda je v deníku · [km] km ›" → `/ride/:id`. Never promise a full tank at pick-up.
- Motion: newly ✓ node `pop` + haptic while the connector draws (700 ms); state change `enter`; loops = CTA glow/fx + (live states only) ping/scan.
- "Další rezervace ([n]) ›" light row under the ticket only with 2+ bookings.

### 5.4 "Kdy jedeš příště?" (moved under the ticket; in S0 the ticket itself is the date entry)
h48 r999 light pill (white, border 1.5 `#CFE3DA`): calendar icon `#0D6E0D` + "Kdy jedeš příště?" 14/800 + "Vyber termín" 13/600 `#4A6B5A` + chevron → C9 date sheet → Motorky filtered. With draft dates "pá 23. 10. → ne 25. 10. · 3 dny ✕".

### 5.5 "MotoGo ti píše" (only with unread)
Light row 52: envelope icon tile + "MotoGo ti píše: [titulek zprávy]" + chevron → `/messages?n=<id>`. Type `voucher` adds eyebrow "Dárek od MotoGo24" (the only "just for you" offer, and it is real).

### 5.6 Tvůj klub (light card r16, the rank card)
- Row: tier **emblem** 40 (`.rk-emb`, tier icon) + "Motorkář" 17/800 `--rk-accl` + "Level 3 z 20 · sleva 3 % na každou jízdu v appce" 12.5/600 `#4A6B5A`; right ⓘ → rule sheet (`rk.rule`, corrected D1: "Každá dokončená výpůjčka (appka i web): 1–6 dní = 1 bod, 7 a víc dní = 2 body. 2 body = 1 rank a +1 % slevy (max 20 %). Rank ti časem nepropadá. Sleva platí jen na rezervace v aplikaci a sčítá se s promo kódy i poukazy. Od Motorkáře (3) máš výbavu spolujezdce a boty zdarma.").
- **Tier bar** (`rk.tierBar`, 1 segment = 1 point inside the tier, gap between levels, next point striped; segments fill in sequence 45 ms) + "Silnice · 5 z 10 bodů" left, "Kovová liga od 10 b." right; line "Ještě 1 bod → Stálý jezdec (4 %)" 13/800 `--rk-accl`.
- Privileges (real Kč only): "−3 % na každou jízdu v appce" · "S rankem jsi zatím ušetřil [n] Kč" (Σ `loyaltyDiscountAmount`, hidden at 0, count-up once); "Výbava spolujezdce a boty zdarma" · "až 1 270 Kč na každé výpůjčce" (ranks 1–2: locked "Od Motorkáře: výbava spolujezdce + boty zdarma").
- **Tier rail**: 5 swatches (`rk.tiers`: Silnice "Tady jsi" / Kovová liga "od 10 b." / Liga drahokamů "od 18 b." / VIP klub "od 32 b." / Legenda "od 38 b."; passed = "Máš za sebou", locked 50 % + lock). Tap → light sheet **"Takhle bude vypadat tvoje appka"**: inside a wrapper with `tiers[i].scope` a live mini LogoRow frame, rank chip, CTA ("REZERVOVAT · ukázka", looping) and nav pill of that tier + "od Bronzového jezdce · 10 bodů". (Grafted from Club; the full "Cesta jezdce" road lives on `/loyalty`.)
- "Jezdíš s námi od [měsíc rok]" 11.5/600 `#6C8A7B`.
- No leaderboard on Home (flag off; it stays on `/loyalty` behind the flag).

### 5.7 Moje zážitky (personal hub; "Vše ›" → `/my-experiences`)
- "Pokračuj v trase: [název] · [3] z [7] míst" row (only while `activeRideProvider` is active; prop `rozjetaTrasa`) → `openRide()`.
- 2×2 tiles 171×92 (light, icon tile + label 12/800 + value 18/900 count-up):
  - **Jízdy s MotoGo** "[n] · [km] km" (`get_my_rides`, `booking_id` set) → list filtered "S MotoGo"
  - **Soukromé jízdy** "[n] · [km] km" + "● Nahrát jízdu" (start in place; while recording "● Nahrávám · [km] km · Ukončit", red dot = live loop)
  - **Moje trasy** "[n] uložených · Vytvořit" (`get_my_saved_routes`) → list / `/route-build`
  - **Objevená místa** "[n] míst" (`get_my_places`) → tab Moje místa
- **Poslední zápisy** (timeline, 2 entries): sketch 64×48 from `mapPoints`, badge "S MOTOGO · [motorka]" (neon on dark pill) or "SOUKROMÁ" (neutral), "[název jízdy]" 14/800, "[datum] · [km] km · [čas] · [n] fotek" → `/ride/:id`. After a level-up the newest entry is "Nový rank: Stálý jezdec (4 %) · Za jízdu na Husqvarna 701 SM · dnes" (`LU.entry`, emblem instead of a sketch).
- Empty: "Jízdy s MotoGo se nahrají samy, když povolíš polohu. Soukromou nahraješ jedním klepnutím."
- Mockup values are unknown → `[n]`, `[km]`; entries marked "ukázka".

### 5.8 Vybrali jsme ti — "Trasy kousek od Velkých Němčic"
Sorted by distance from the next booking's branch (`pickupOriginProvider`; `routes.branch_id` is unusable — all point to Mezná or NULL). 3 cards in a `PageView(.76)` (296 wide): real cover photo 296×120 with the waypoint sketch drawn over a dark scrim (draw once 900 ms, start/end pin pop), title 15/800, chips km · čas · obtížnost:
| Route (id) | km · čas · obtížnost | Cover (`…/storage/v1/object/public/media/routes-mirror/`) | Sketch `d` (box 296×120, loop routes) |
|---|---|---|---|
| Rajhrad a Židlochovicko (`760de205…`) · "10,6 km od pobočky" | 40 km · 55 min · Lehká | `5955e514a6557713724037e3172adc708f0e4d41.jpg` | `M137.8,14.0 C140.7,17.8 152.7,31.3 154.9,37.0 C157.1,42.7 150.6,43.1 151.2,48.3 C151.8,53.5 158.1,58.5 158.2,68.1 C158.3,77.7 154.2,109.3 151.6,106.0 C149.0,102.7 144.7,63.5 142.4,48.2 C140.1,32.9 138.6,19.7 137.8,14.0` |
| Vodní krásy: Věstonická nádrž a okolí (`2281c259…`) | 170 km · 4 h 50 min · Střední | `88cf0867c83db0b88ec60112c86feb4bd01ed3d2.jpg` | `M111.6,71.3 C117.9,75.4 140.2,90.0 149.5,95.8 C158.8,101.6 149.2,108.5 167.7,106.0 C186.2,103.5 257.6,90.0 260.7,80.6 C263.8,71.2 224.2,60.5 186.6,49.4 C149.0,38.3 47.6,10.7 35.3,14.0 C23.0,17.3 100.2,59.9 112.9,69.4 C125.6,79.0 111.8,71.0 111.6,71.3` |
| Za historií: Synagoga v Dolních Kounicích a okolí (`b75ed442…`) | 122 km · 2 h 54 min · Lehká | `57abf096e4807ec0cd48ec3bc8429cf7242df8f8.jpg` | `M124.9,106.0 C130.2,90.7 149.2,24.0 156.9,14.0 C164.6,4.0 171.9,36.2 171.1,46.0 C170.3,55.8 155.4,68.1 152.2,72.7 C149.0,77.3 152.0,68.8 151.9,73.4 C151.8,78.1 155.7,95.4 151.8,100.6 C147.9,105.8 133.1,103.9 128.6,104.8 C124.1,105.7 125.5,105.8 124.9,106.0` |
Chip under the row: "U Velkých Němčic je [466] míst · objevil jsi [n]" → Trasy, segment Místa. "Všechny trasy ›" → Trasy.

### 5.9 Motorky pro tebe
Chip "Znovu: [poslední motorka]" (most-rented completed bike; remembered pickup/return methods; dates empty; boots never pre-filled) + v1 C15b cards (licence-filtered), prices "Tvoje cena" (rank 3: BMW od 2 727 ~~2 811~~ · pá–ne 11 893; Shotgun 1 778 ~~1 833~~ · 7 336; Husqvarna 3 437 ~~3 543~~ · 14 176). The whole card is the target (no second CTA on Home — the ticket CTA stays the only primary). "Všechny ›" → Motorky.

### 5.10 Pobočky + Tvoje linka MotoGo24
- Pobočky = v1 (Mezná "S obsluhou · nonstop", Velké Němčice "Samoobsluha · kód z appky"; photos `[fotka pobočky]`, see §1.1).
- **Tvoje linka MotoGo24** (light card): "Za každou tvojí jízdou stojí celý tým MotoGo24." 15/800 + two ghost buttons "Zavolat · +420 774 256 271" (`tel:`) and "Napsat" (`/messages`); small "Pomoc na cestě najdeš v rezervaci během jízdy (SOS)". (Graft from Journal/Club: Home's help touchpoint outside a rental.)

### 5.11 Home motion
Sections `reveal` (first build per session) · ticket checklist connector draw + ✓ pops · tier bar segments fill · count-ups (tiles, "ušetřil") once · sketches draw on enter · Hero into reservation / bike detail · loops: ticket CTA + (live states) ping/scan or the recording dot · level-up landing (§3.6) · reduced motion: all static.

---

## 6. Screen 2 · Detail motorky v2 (declutter, `/moto/:id`)

**Artboard 390 × 2000**, nav hidden (focused flow), sticky bar pinned (136), AI FAB **mini** at bottom 148. Props: `rank`, `photoFit` (v1), `stav` (`Termín vybraný` / `Bez termínu` / `Obsazená v termínu` / `Přes limit dní` / `Věrnost nedostupná`), `levelUpDemo`, `reducedMotion`.

### 6.1 Layout
1. **Full-screen photo hero 390 × 560** (keep the owner-loved full-bleed look; contain + blurred backdrop or cover per `photoFit`; one-shot 8 s slow zoom). Overlays: story segments bar (photos), back 40 px glass circle, bike pager pill "‹ 1 / [n] ›" (arrows only), count pill "1 / [n]" + "▶ Video" pill. Bottom scrim: status pill "● Volná v tvém termínu" (ping = live loop), tags "CESTOVNÍ" + "ŘP A", **H1 28/800 "BMW R 1200 GS Adventure"**, meta "MotoGo24 Mezná · s obsluhou · nonstop ›" (self-service: "MotoGo24 Velké Němčice · samoobsluha · kód z appky").
2. **Content sheet** slides up over the photo (r24, overlaps 24 px, page `#DFF0EC`):
   - **4 key spec tiles** (Výkon 92 kW · Motor 1 254 cm³ · Výška sedla [mm] · Hmotnost [kg]).
   - **"Tvoje jízda"** dark calculator card (r22, `scanOnce` on recalculation), header eyebrow + rank chip "Motorkář · −3 %":
     - ① **Termín** tiles "VYZVEDNUTÍ pá 23. 10." → "VRÁCENÍ ne 25. 10." + "3 dny" pill (no dates: "Vyber" + presets "Nejbližší víkend · 16.–18. 10.", "Další víkend · 23.–25. 10.") → C9.
     - ② **Předání** — one summary row "Na pobočce Mezná · vyzvednutí 12:00 ½ · vrácení 19:00" + "Změnit ▾".
     - ③ **Výbava navíc** — one summary row "Spolujezdec + boty řidiče + boty spolujezdce · 0 Kč s rankem" (rank < 3: "… · 1 270 Kč") + "Změnit ▾".
     - **Total**: "TVOJE CENA" + **10 189 Kč** 32/900 neon + delta chip; "Díky ranku Motorkář ušetříš 1 585 Kč"; "Bez kauce · konečná cena"; "Rozpis ▾".
     - **No in-card CTA** (the sticky bar is the single primary).
   - **V kostce** chips (all `short_desc_fields`, one horizontal row).
   - **Popis** 3 lines + fade + "Celý popis".
   - **Víc o motorce** (C14 rows): "Všechny parametry (8) ▾" · "Ceník podle dne ▾" · "Video ([n]) ›" · "Návod k obsluze ›" (dimmed "Návod zatím není k dispozici" when missing) · "Pobočka Mezná · Mezná 9, 393 01 Pelhřimov ›" (+ navigate).
3. **Sticky bar** (`shared/cta.html` PART 3, always visible): context "pá 23. 10. → ne 25. 10. · 3 dny" + "Rozpis ▴" (dark receipt sheet); **60 px full-width rank CTA "REZERVOVAT · 10 189 Kč"** (crown/laurel glyph VIP/Legenda). States: no dates → "VYBRAT TERMÍN · od 2 727 Kč/den" → C9; busy → amber "V tomhle termínu je obsazená" + ghost "ZMĚNIT TERMÍN"; over limit → amber "Nejdéle na [max] dní" + "ZMĚNIT TERMÍN"; loyalty failed → list price + receipt row "Věrnostní slevu teď nevidíme · Zkusit znovu". Tap → `/booking` (Hero thumbnail flies to the recap).

### 6.2 Visible / collapsed / moved (nothing is lost)
| Content (v1 detail) | v2 |
|---|---|
| Gallery, pager, dots/segments, count, video pill, fullscreen gallery | **visible** (hero) |
| Status pill, category, ŘP, H1, branch meta | **visible** (hero overlay) |
| 4 spec tiles | **visible** |
| Všechny parametry (8) | **collapsed** → Víc o motorce row |
| V kostce (all fields) | **visible** (one chip row) |
| Ceník podle dne (7 bars + note "1 den = kalendářní den…") | **moved** → Víc o motorce row (day prices stay visible in the C9 calendar cells) |
| Calculator ① dates + presets | **visible** |
| Calculator ② segmented, time chips, ½ tags, late-pickup line, self-service locks + ⓘ texts, delivery address sheet + map picker | **collapsed** into the Předání summary row (Změnit ▾ expands in place) |
| Calculator ③ rider-gear info, paid tiles with strike, trailer, kids/self-service rules, "Velikosti vybereš v dalším kroku." | **collapsed** into the Výbava navíc summary row |
| Receipt (bars, rows, total, savings, footer) | total + savings + "Bez kauce · konečná cena" **visible**; bars/rows/"nejsme plátci DPH" **collapsed** ("Rozpis ▾", also "Rozpis ▴" in the sticky bar) |
| In-card CTA "REZERVOVAT ZA 10 189 KČ" | **moved** → sticky bar (one primary, always visible) |
| Popis (full HTML) | 3 lines **visible**, rest behind "Celý popis" |
| Video, návod, pobočka | Víc o motorce rows (unchanged) |
| Min/max banner, busy days | C9 disabled days + sticky blocker (unchanged) |

### 6.3 Motion
Card → detail Hero (350 ms) · sheet slides up 450 ms after the photo settles · spec tiles `reveal` · summary rows expand `AnimatedSize` 300 + chevron 200 · any input: total `bump`, delta chip, `scanOnce` · extras at rank ≥ 3: `strike` → "0 Kč" `pop` · sticky bar slides in (300) and its CTA label cross-fades on state change · loops: sticky CTA + "Volná" ping only.

---

## 7. Screen 3 · Motorky (catalogue) — light touch, keep full-screen cards

- Keep v1: sticky night-glass header (title "Motorky" + count, view toggle full/grid, date pill, chips incl. branches), 600 px full-bleed cards with blurred backdrop, photo segments, favourites heart, availability pill, category/ŘP/branch, name 28/800, price block ("Tvoje cena za 3 dny od" / "Tvoje cena od … Kč/den" + struck list + "≈ … Kč/den · výbava zdarma"), grid view, empty state, date presets panel.
- **Changes**: header gets the rank chip (`.rk-chip`, replaces the pulsing `.rkc` — no loop) and the rank hero aura; the round `.go` arrow becomes the **card action** (`cta.html` PART 4, `.rk-cta.md.auto`, 48 px, right of the price): "VYBRAT" (no dates) · "REZERVOVAT" (dates + free; opens Detail with the dates and the sticky REZERVOVAT ready) · ghost "JINÝ TERMÍN" (busy). The loop runs only on the first card in view; all others `still`. Ken Burns becomes one-shot (8 s) on the card in view (loop budget). Dark nav (Motorky active) + AI FAB full at 110 (peeks while scrolling; board: toggles on the first card swipe). Card entrance stagger (v1) kept.

## 8. Screen 4 · Booking v2 "Máme to připravené" (express for a returning customer)

**Artboard 390 × 1500**, page `pageWash`, nav hidden, sticky bar 136, AI FAB mini at 148 (hidden while charging). Props: `rank`, `stav` (`Vše připravené` default · `Chybí velikost bot` · `Bez uložené karty` · `Chybí údaje pro smlouvu`), `levelUpDemo` (blocked while charging), `reducedMotion`.
1. App bar: back 40 + "Rezervace" 22/800 + "BMW R 1200 GS Adventure" 12.5/700; after insert a "⏱ [mm:ss]" warn chip.
2. Step progress C18 (three dots; express arrives with 1 and 2 ✓, 3 current).
3. Recap card (Hero target): thumb 64×48, name, "MotoGo24 Mezná · pá 23. 10. → ne 25. 10.".
4. **Termín a předání** (done, compact): "pá 23. 10. 12:00 → ne 25. 10. 19:00 · 3 dny" + "Vyzvednutí i vrácení na pobočce Mezná" + "Změnit" (expands the light-tone calculator blocks). Entered without the calculator → expanded and current.
5. **"Máme to připravené"** card (the express summary; light, ✓ = `checkedBg` circles, each row "Změnit"):
   - ✓ "Ty: [jméno] · ŘP [A] platný do [datum]" (blocker only when `profileCompletenessValidationProvider` fails, e.g. licence expires before the rental ends → amber row "Chybí ti [údaj] pro smlouvu · Doplnit" → sheet with only the missing fields)
   - ✓ "Výbava: helma [M] · rukavice [L] · bunda [L] · kalhoty [M]" (or "Vlastní výbava"; from `profiles.gear_sizes`)
   - ✓ "Navíc: výbava spolujezdce + boty řidiče + boty spolujezdce · zdarma s rankem" + sizes "spolujezdec [L · M · L · L] · boty [43] · [40]". **Boots are never pre-filled**: state `Chybí velikost bot` turns this row amber with inline size chips 39–48 (the single blocker).
   - ✓ "Platba: [Visa] •••• [XXXX]" (default card; Změnit → methods; iOS no manual card entry; Apple Pay / Google Pay official buttons only there or when no card)
   - ✓ "Doklady ověřené" (missing → quiet note "Kódy ti uvolníme po nahrání dokladů" / staffed "Doklady potřebujeme před převzetím" — not a blocker)
6. Collapsed rows "+ Mám slevový kód nebo poukaz" (inline field + POUŽÍT, `min_order_amount` enforced) and "+ Poznámka k rezervaci".
7. **One consent line** (until B7): checkbox "Souhlasím s [obchodními podmínkami] a [zpracováním osobních údajů]" (links open the documents); kids' bike adds the guardian line. Under it: lock "Platba přes Stripe · PCI DSS Level 1" · "Po klepnutí na Zaplatit máš 30 minut na dokončení platby."
8. **Sticky bar**: "Tvoje cena · 3 dny" + "Rozpis ▴"; **60 px rank CTA "ZAPLATIT · 10 189 Kč"**. Consent unticked → the button stays visible but `still` (no loop); tap pops the consent row + toast "Potvrď souhlas s podmínkami"; ticking it **brings the button to life** (glow + fx start, `pop`). Other blockers → ghost "DOPLNIT ↓" + amber single reason ("Chybí: velikost bot řidiče"). Total 0 → "POTVRDIT OBJEDNÁVKU (ZDARMA)". Charging → spinner, back blocked, level-up blocked.
Result: dates (2) + Rezervovat + consent + Zaplatit ≈ **5 taps, no scrolling** (4 with B7). `/success` unchanged (root route, no Hero).

## 9. Screen 5 · Správa rezervace — light touch
- Keep v1 board content (photo, title, Tvoje cesta timeline, CO TEĎ states, action row, Kdy a kde, Výbava, Peníze + Rozpis + Platební údaje, Dokumenty, Historie úprav, bezpečnostní pokyny, help line, procedure sheet, edit chooser, storno sheet, full-screen codes).
- **Changes**: CO TEĎ primary = rank CTA; timeline current node ping = live loop; dark nav (Rezervace active, needs-action dot for `Čeká na platbu`/`Chybí doklady`); AI FAB full at 110; help line "AI asistent" opens the same chat panel (chips "Kódy a postup na pobočce", "Prodloužit rezervaci", "Jak vrátit motorku"; SOS chip in `Probíhá`); loyalty row in the receipt keeps its text, its star takes `--rk-accl`; storno stays neutral/red (never rank).
- Return copy (VN): "Vrať do 23:59 · nádrž plnit netřeba, jen nesmí svítit rezerva · vrať ji umytou · vrácení na kiosku poslední den rezervaci dokončí samo".
- **Level-up demo** = the textbook case: stav `Probíhá`/`Dokončeno` + `levelUpDemo` "+1": while "Kódy na celou obrazovku" is open the celebration is **blocked**; closing it calls `LU.check()` and the celebration plays ("Za jízdu na Husqvarna 701 SM").

## 10. New board · RankStyly (PLAN phase 3)
390 × ~2600, light page. Header (rank hero for the `rank` prop) "Tvůj rank, tvůj vzhled". Five tier sections (Silnice, Kovová liga, Liga drahokamů, VIP klub, Legenda) with the 20 levels as rows: mini frame (logo + ring + badge), name + "od [2L−2] b. · sleva L %", rank chip, `.rk-cta.sm` (`still`; the selected row loops), contrast numbers (label min cr, edge vs night). Tap a row → selected + "Přehrát povýšení sem" plays the shared level-up from the previous level (tier cards on boundaries). Footer: what rank never changes. Props: `rank`, `levelUpDemo`, `reducedMotion`. Each row is a wrapper with `rk rk-N t-tier` (local scope).

## 11. Content-preservation additions (v1 spec §11 still applies)
| Today / v1 | v2 location |
|---|---|
| Home hamburger + unread badge on it | Profil tab (+ count badge) + bell in the Home header |
| Home AI FAB (bottom-left, "AI") + v1 header bot + scroll-to-top FAB | global AI FAB bottom-right; re-tap tab = top |
| `LoyaltyRankCard` + "O programu" | Tvůj klub card (+ ⓘ corrected rule) · `/loyalty` (ladder by tiers, thresholds 2L−2 fixed, leaderboard behind flag) |
| "PILOT: {nick}" badge | greeting (tap → nickname dialog) + rank chip |
| Fake search on Home | "Kdy jedeš příště?" pill under the ticket + ticket S0 |
| Moje jízdy / trasy / místa two levels deep | Moje zážitky hub on Home (+ full `/my-experiences`) |
| Branch photo gallery, procedure | unchanged (branch detail, procedure sheet) |
| Detail: everything in §6.2 | visible / collapsed / moved, none removed |
| Booking: 6 sections, two consents, separate payment screen | express summary + one consent line + pay block in the sticky bar; every field still reachable via "Změnit" |
| Level-up overlay (67 s montage) | shared sequence (§3.5), music optional, never over blocked screens; montage photo/video may follow as optional "Tvůj stroj" slide after "Pokračovat" |

## 12. Flutter mapping (port, both trees, each file < 5 000 tokens)
`core/rank_theme.dart` (solver port of `rankTheme.js`, `ThemeExtension` with `lerp` for the morph) · `core/widgets/v2/rank_cta.dart` (+ tier fx painters) · `rank_frame.dart` (ring, arc, badge, crown/laurel) · `rank_hero.dart` (aura, texture, minted edge, ambient) · `v2_nav_bar.dart` (labels + `TextPainter` guard + golden tests) · `mg_ai_fab.dart` + `bottom_obstruction.dart` · `features/loyalty/levelup_gate.dart` (triggers T1–T9, safe moments, pending persistence) + `levelup_sequence.dart` · `features/home/home_v2/*` · `features/booking/express_summary.dart`. No new packages. i18n for every new string in 8 languages.

## 13. Board build checklist
1. Skeleton = DC format (v1 boards). Helmet style block order: board base CSS → `rank-theme.css` → logo CSS → `cta.html` CSS → nav CSS → ai-fab CSS → levelup CSS → board CSS.
2. Script: inside `renderVals()` paste `rank-theme.js`, `nav.js`, `ai-fab.js`, `levelup.js` verbatim, then:
   `const LU = levelUpVals({ P, S, set, reduced: rm, blocked, bike, boardH: H }); const rk = rankTheme(LU.level); rk.open = () => say('…/loyalty');`
   return `rootCls: 'mg ' + rk.cls + (LU.landCls ? ' ' + LU.landCls : '') + (rm ? ' rm' : '')`, `rk`, `lu: LU`, `nav: navVals({ S, set, active, lang: P.jazyk, rk, unread: '[n]', needs, say, width: 390 })`, `ai: aiFabVals({ S, set, say, screen, mode, bottom, lang: P.jazyk, nick: '[přezdívka]', sos, coach })`.
3. Root `onClick="{{ lu.tap }}"`; levelup markup last; FAB after nav/sticky; toasts above FAB (z 50), level-up z 60.
4. Prices: `rankTheme(LU.priceLevel).pct` in the price engine (v1 §6); never colour prices by rank.
5. One looping primary per screen; other rank buttons `still`; ≤ 2 loops; default style = end state.
6. Validate: `python3 dclint/lint.py <file>` → LINT OK; `node dclint/fuzz.js <file> '<props>'` → "fuzz ok" for `{}`, rank 1, 6, 10, 17, 19, 20 and `{"reducedMotion":true}` (+ `levelUpDemo` "+2 ranky (výhra měsíce)").

## 14. Owner decisions (carried + new)
1. Title-case tab labels + new nouns (en Bikes/Bookings, de Bikes, fr Locations, nl Boekingen, pl Motory, uk Мото/Оренда); dark nav.
2. VIP 17 colour = SOS red `#EF4444`: keep pearl-and-ruby styling (red only as ring/glow), or recolour VIP in Velín? Legenda shares `#FFD700` with Zlatý jezdec (keep or recolour).
3. Monthly award keeps running while the leaderboard is hidden? (it explains itself now via the reason line).
4. Celebration music on by default? ("Zvuk oslav" setting).
5. Optional `loyalty_events` + push "Nový rank" (SQL as text first).
6. Conditional nudge "Po dokončení této jízdy: Stálý jezdec (4 %)" on the ticket?
7. B2 "Motorka připravena" flag for Mezná (`bookings.prepared_at`).
8. Birthday and anniversary lines in the concierge note.
9. One combined consent line now; B7 (accepted VOP version) later to drop the tick for returning customers.
10. SOS chip on the route-navigation screen.
11. AI chat as full-screen container transform (spec) vs a 92 % sheet.
12. Canvas: allow `www.motogo24.cz` images so the Velké Němčice branch photos can be real.
