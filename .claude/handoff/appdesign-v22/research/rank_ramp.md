# Rank colours v2.2 — one growing ramp for all 20 levels

Owner, 2026-10-16: *„aby ten člověk měl pocit, že roste … na začátku ty zelený jsou dobrý, prostřední, když budou modrý … stříbro, bronz, platina to nevadí … aby žádný ty barvy těch ranků se nepodobaly úplně, takže 13. bude stejný jako 20.“* Plus 2026-10-15: no pink or purple. The fiery gold at the top stays (he likes it).

This replaces `research/rank_colors.md` (v2.1, which only recoloured 13–16) and its SQL draft `sql/20261015_loyalty_colors_no_purple.sql` (now banner-marked „NAHRAZENO“, do not commit).

## 0. Result in one paragraph

All 20 `loyalty_levels.color_hex` values are recoloured into one ladder: **Silnice 1–5 greens** (muted sage → pale mint → vivid green → emerald → jade-teal) → **Kovy 6–9 by name** (bronze, silver, pale yellow gold, cool platinum) → **Drahokamy 10–16 blues that get deeper** (ice → aquamarine → azure → cerulean → cobalt → deep petrol → royal sapphire) → **VIP 17–19** (racing crimson, rich 24k gold, platinum pearl) → **Legenda 20 fiery gold**, the only fiery rank. Level 3 Motorkář (`#4ADE80`, the sample customer) is unchanged.

- **CIEDE2000:** every pair ≥ **12.38** (6↔20), every pair of neighbours ≥ **15.60** (2↔3). Today the minimum is 0.0 (8 = 20 = `#FFD700`), and 13 pairs are under 12.
- **No pink, purple, violet or magenta:** no rank has an HSL hue of 232–345°. A scan of every colour in the generated `rank-theme.css` (311 colours, including effects) found none. Reds are never lightened into salmon.
- **On-accent text** (text drawn on the rank colour) is picked by contrast and reaches ≥ **4.89:1** on every level.
- **Logo ring** on the dark header (`#0A1A10`) is ≥ **3.28:1** on every level.
- **Redesign tokens** (`rank-theme.css`): 0 contrast failures, all solved.
- **Prestige rises strictly** through the tier effect, the colour family and the depth inside the tier. The argument for each tier is in §3.
- **SQL:** `sql/20261016_loyalty_colors_ramp.sql`. It is guarded and idempotent, and was tested on PostgreSQL 16.
- **App code:** `_onColor` must pick by contrast, and rank-coloured text on dark must be lifted. Both are needed in **both** app trees before or with the SQL (§6). The level-up overlay is described only; it needs the owner's OK.

Images:
- `research/rank_ramp_strip.png`: today vs the new ramp, with tier bands.
- `research/rank_ramp_board.png`: all 20 levels in the redesign (hero, ring, chip, CTA, emblem, tier bar), rendered from the regenerated `shared/rank-theme.css`.
- `research/rank_ramp_live.png`: the raw hex painted the way the live app paints it today (ring, pill text, medallion, bar on a white card), old vs new.

## 1. Inputs

**Live `loyalty_levels` (anon read, 2026-10-16):**
- level = discount %;
- `min_booking_order` 1, 3, 5 … 39;
- 13–16 are still the purples, so the v2.1 SQL was never applied;
- levels 8 and 20 are both `#FFD700`.

The DB stores ONE `color_hex`. Every rank effect is app-side, by tier.

How the app paints the raw `color_hex` today (identical code in both trees; `diff -q` on `features/loyalty` is clean):

| Surface (file) | What the colour does | WCAG need |
|---|---|---|
| `core/widgets/logo_header.dart` LogoRow | 5 px ring + glow (α .55, blur 18) around the 1:1 logo; Legenda = `legendGradientColors` `#FFD700→#FF6B00`, glow `#FF8C00` | ring ≥ 3:1 vs header `#0A1A10` |
| `loyalty_rank_card.dart` `_rankNameText` | rank name 14 px w900 and „N %“ 18 px w900, in colour on the dark pill `#1A2E22` | 4.5:1 (normal text) |
| `loyalty_rank_card.dart` progress bar | fill on `g200 #D4E8E0` inside a white card | 3:1 non-text (fails today for light colours; see §6 E) |
| `loyalty_ranks_screen.dart` | ring + GlowPulse, `_rankName` 22/40 px on `gradientTop #0A1A10`, medallion number and „Ty“ chip via `_onColor`, `_percentPill` 16 px | large text 3:1, otherwise 4.5:1 |
| `loyalty_leaderboard_section.dart:342` | avatar filled with the colour, initial via an inline luminance > 0.5 rule | 4.5:1 |
| `loyalty_levelup_overlay.dart` (protected) | ring morph old→new, title 30 px w900 in the colour, „Pokračovat“ filled with the colour + `_onColor`, „+N“ badge gradient `[c, c·75 %]` + `_onColor`; prefs `mg_loyalty_last_color_<uid>` | title 3:1, button and badge 4.5:1 |
| `profile_screen.dart:478`, `home_header.dart` | rank chip: colour at α .18 bg, border, glow; edit icon in the colour | icon 3:1 |

In the redesign (`shared/rank-theme.*`), nothing paints the raw hex as text: every text and mark uses a solved token (`--rk-acc`, `--rk-acc-g`, `--rk-accl`, `--rk-chip-tx`, `--rk-on`).

## 2. How the ramp was built

1. **Story first.** The colour family follows the tier: greens = road, metals = the names 6–9, blues = gems, VIP = crimson / gold / pearl, Legend = fire. Inside a tier, the colour **deepens or gets richer** with the level.
2. **Hard constraints**, solved by a target-anchored annealing search over sRGB (scripts in `ramp_work/opt*.js`, configs `cfg*.js`):
   - CIEDE2000 ≥ 12 for all pairs and ≥ 15 for neighbours, searched with a 4 % margin;
   - HSL hue outside 232–345° for any chromatic colour, plus a no-light-desaturated-red rule;
   - relative luminance ≤ 0.175 (white text ≥ 4.67) or ≥ 0.228 (dark text ≥ 4.67), so the on-accent text always reaches 4.5 one way or the other;
   - ring ≥ 3:1 on night;
   - L\* bands per role;
   - monotonic depth and richness inside Silnice and Drahokamy.
3. **Variants rejected:**

| Variant | Why it was dropped |
|---|---|
| Keep every colour light (L\* ≥ 60, so the raw hex is ≥ 4.5 as text on the dark pill) | Only feasible with neon cyan, lavender-grey and periwinkle (`#687AED`, hue ≈ 231–233°), at a 1.00 margin. Seven distinct light blues do not exist in that band. |
| Keep 13–16 from v2.1 (orange / olive / coyote / petrol) | 13's orange→amber CTA reads as the Legend fire; this is the owner's complaint. Olive and coyote break „modré uprostřed“. |
| Black or carbon DB hex for an „černobílý“ rank | A black ring disappears on the dark header and in the leaderboard avatars, and every neutral slot is already used (silver, platinum, pearl). Black and white remain possible as an app-side two-tone effect, not as a DB colour. |
| Warm (beige) platinum + cool pearl | Platinum read as greige or taupe. Cool platinum + cool pearl, with the pearl much lighter, looks like real platinum. |
| Vivid cobalt at 14 | It out-shines the deeper petrol at 15, so a reviewer could rank 14 above 15. A medium cobalt keeps depth + saturation strictly rising. |
| Lighter bronze `#C2844A` vs deeper `#B97332` | Kept `#C2844A`. The rank name stays readable in today's app (4.59:1 on the pill) at the cost of the smallest margin pair (6↔20 = 12.38; the two differ in chroma, 44 vs 80, and in tier). |

## 3. Why no lower level can look more valuable (argued per tier)

Prestige has three cues, in this order: **(1) tier effect** (§4: flat → metallic → glow → animated foil + crown → fire + laurel), **(2) colour family** (green < metal < gem blue < VIP crimson/gold/pearl < fire), and **(3) depth/richness inside the tier** plus the explicit step marks (lane dashes 1–5, rivets 1–4, facets 1–7, crowns 1–3) and the glow growing +0–12 px.

- **Silnice 1–5 (flat).** The colour comes alive, then deepens.
  - Chroma rises: 1 sage C\* 12 → 2 mint 28 → 3 green 69.
  - Depth rises: 3 L\* 79 → 4 emerald 63 → 5 jade-teal 60.
  - 5 is the coolest green and bridges to the gem blues.
  - All road CTAs are the brand neon with a rank-tinted end stop (brand stays primary for beginners).
- **Silnice → Kovy.** Any metal outranks any green: conic metal ring, brushed CTA with a 4.8 s sheen, medal icon, first halo.
- **Kovy 6–9.** Bronze < silver < gold < platinum is the universal card and airline ladder, and the names say so.
  - Bronze `#C2844A` is muted caramel (C\* 44).
  - Silver `#929496` is a neutral metal (L\* 61).
  - **Zlatý `#E5D376` is a pale, brushed yellow gold.** It is deliberately softer than VIP Gold (C\* 48 vs 71) and has no orange (hue 97° vs 83° / 62°).
  - Platinum `#B9BEC6` is the cool blue-white of a platinum card (L\* 77).
- **Kovy → Drahokamy.** Platinum < diamond is the convention. The tier adds a faceted ring, a prismatic CTA with glints, a stronger halo and the gem icon.
- **Drahokamy 10–16, „čím hlubší, tím vzácnější“.**
  - L\* falls strictly: 89 → 77 → 70 → 61 → 56 → 47 → 45.
  - Hue alternates cyan / blue only to keep neighbours ≥ 15 apart.
  - Depth + richness score P = (100 − L\*) + C\*/2 rises strictly: 21.6 → 43.7 → 52.7 → 56.8 → 66.8 → 67.8 → 97.2.
  - CTA style: light gems 10–14 have an ice CTA with a navy label; **15–16 switch to deep CTAs with a white label**, so the top of the league visibly darkens. 16 royal sapphire is the most saturated colour in the tier (C\* 83).
- **Drahokamy → VIP.**
  - Crown on the ring and in the CTA, double ring (rank colour + gold), a light running around the foil frame (4 s), aurora ambient.
  - None of crimson, rich gold or pearl appears in any lower tier.
- **VIP 17–19.** The names give the order (VIP < VIP Gold < VIP Platinum); crowns 1–3.
  - 17 = racing crimson `#D42020`, deliberately not the SOS red `#EF4444`. The CTA is ivory with a crimson label (a red primary would read as SOS or destructive), with a red–gold frame and champagne rank text.
  - 18 = rich 24k gold `#EDB42D` + gold foil CTA.
  - 19 = brilliant platinum pearl `#F5F8FB` (L\* 97 vs Platinový 77) with an iridescent ice–mint–champagne edge.
- **VIP → Legenda 20.** It is the only animated fire:
  - molten gradient `#FFE27A→#FFD700→#FF9A1F→#FF6B00`, embers, laurel, the strongest glow (α .66, blur 34, halo .24);
  - the DB hex is the fiery orange-gold `#FF8C1A`, and the app keeps drawing its gradient;
  - no other rank is orange: the v2.1 orange 13 is gone and bronze is muted.

**Pairs a reviewer might confuse (ΔE00):**

| Pair | ΔE00 | Why they read differently |
|---|---|---|
| 8 ↔ 18 ↔ 20 | 12.5 / 16.9 / 27.2 | pale brushed metal → crowned rich gold foil → animated fire |
| 9 ↔ 19 | 13.5 | grey platinum metal vs brilliant crowned pearl |
| 6 ↔ 20 | 12.4 | muted caramel metal vs vivid animated fire |
| **13 ↔ 20** | **50.7** | the owner's complaint is gone |
| 9 ↔ 10 | 16.5 | |
| 1 ↔ 7 | 15.4 | was 10.2 |
| 2 ↔ 19 | 21.1 | |
| 14 ↔ 15 | 15.7 | deeper, and the CTA turns deep |
| 5 ↔ 11 / 5 ↔ 13 | 12.9 / 12.7 | teal road vs gem: the gem has the faceted ring and glints |

## 4. Effect tiers (app-side, by level; unchanged structure, verified monotonic)

| Tier | Levels | Ring | Primary CTA | Loop fx (same slot, never extra) | Glow α / blur / halo | One-shot ambient | Step marks |
|---|---|---|---|---|---|---|---|
| T0 Silnice | 1–5 | solid 3 px | brand neon, rank-tinted end stop | brand shine (also for guests) + extra streaks at steps 3 and 5 | .50 / 22 / — | headlight sweep, strength by step | lane dashes 1–5 |
| T1 Kovy | 6–9 | conic metal 3 px | brushed 4-stop metal, 1 px edge | metal sheen 4.8 s | .55 / 26 / .12 | sheen once | rivets 1–4 |
| T2 Drahokamy | 10–16 | 12-facet conic 3.5 px | prismatic (luminance-matched partner stop), 1.5 px edge | glints 3.6 s | .58 / 28 / .16 | prism once | facets 1–7 |
| T3 VIP | 17–19 | double ring (colour + gold / cream) + crown notch, 3.5 px | foil + crown glyph | light orbiting the frame 4 s | .62 / 30 / .20 | aurora once | crowns 1–3 |
| T4 Legenda | 20 | legend conic + laurel, 4 px | molten 4-stop + laurel glyph | embers 4.4 s | .66 / 34 / .24 | aurora + embers once | — (single level) |

Inside every tier the glow blur grows +0–12 px and the step halo grows with the step (`--rk-gx`, `--rk-shb`, `--rk-sh`).

**Reduced motion** (`.rm` / `prefers-reduced-motion`): every loop and one-shot is off and the end states are shown. Colours and marks still carry the rank.

### v2.2 engine changes (`research/rankTheme.js` → `gen/gen.js`)

- `SEED` holds the new ramp, with a Czech comment per tier.
- **Jewel CTA label by contrast on the rank colour.** The partner stop is luminance-matched (`matchLum`), so the CTA is a hue shift, not a light/dark jump. Result: 10–14 navy label, 15–16 white label.
- **Deep colours glow in a lifted tone.** For luminance < 0.2 (petrol, sapphire, crimson) the glow is mixed 30 % toward `#9FD0FF`, or toward `#FF7A45` for red, so the halo does not die on the dark header.
- **Reds are never lifted into salmon or pink.**
  - Non-text marks lift a few % toward apricot `#FFCF99`.
  - Rank TEXT on dark for the crimson VIP uses the champagne trim `TRIM = #F3D27E` (10.5:1).
- The hand tables in `gen.js` (`ACC_G`, `JBO`, `PRS`, `ARC`, written for the old colours) are replaced by solved values:
  - glass-safe accent ≥ 4.6;
  - jewel band .5 and press .95 for every white-label CTA;
  - progress arc ≥ 3.2 vs its track.
- **New report checks:**
  - arc contrast is added to the failure check;
  - a hue scan of the full CSS output reports violet / pink offenders („none“).

## 5. Numbers

CIEDE2000 = Sharma 2005 implementation (`ramp_work/color.js`, same as v2.1, checked against the reference pairs). Contrast = WCAG 2.x relative luminance. Decimal commas as in the Czech UI.

### T1 · Ramp: old → new
| L | Rank | old `color_hex` | **new `color_hex`** | colour | tier | effect tier | on-accent text (by contrast) |
|---|---|---|---|---|---|---|---|
| 1 | Startér | `#9CA3AF` | **`#A3B8A8`** | šalvějová (tlumená šedozelená) | Silnice | T0 plochý | tmavý #0F1A14 · 8,47 : 1 |
| 2 | Jezdec | `#86EFAC` | **`#BDF6D1`** | mátová (světlá) | Silnice | T0 plochý | tmavý #0F1A14 · 14,66 : 1 |
| 3 | Motorkář | `#4ADE80` | **`#4ADE80`** | svěží zelená (beze změny) | Silnice | T0 plochý | tmavý #0F1A14 · 10,23 : 1 |
| 4 | Stálý jezdec | `#22C55E` | **`#00AC7F`** | smaragdová | Silnice | T0 plochý | tmavý #0F1A14 · 6,12 : 1 |
| 5 | Věrný zákazník | `#14B8A6` | **`#0AA2A4`** | nefritová tyrkys | Silnice | T0 plochý | tmavý #0F1A14 · 5,70 : 1 |
| 6 | Bronzový jezdec | `#CD7F32` | **`#C2844A`** | bronz | Kovy | T1 kovový lesk | tmavý #0F1A14 · 5,68 : 1 |
| 7 | Stříbrný jezdec | `#C0C0C0` | **`#929496`** | stříbro (neutrální) | Kovy | T1 kovový lesk | tmavý #0F1A14 · 5,86 : 1 |
| 8 | Zlatý jezdec | `#FFD700` | **`#E5D376`** | žluté zlato (světlé, kartáčované) | Kovy | T1 kovový lesk | tmavý #0F1A14 · 11,81 : 1 |
| 9 | Platinový jezdec | `#E5E4E2` | **`#B9BEC6`** | platina (studená šedobílá) | Kovy | T1 kovový lesk | tmavý #0F1A14 · 9,54 : 1 |
| 10 | Diamantový jezdec | `#7DD3FC` | **`#AEE9FF`** | led / diamant | Drahokamy | T2 záře + jiskry | tmavý #0F1A14 · 13,49 : 1 |
| 11 | Prémiový zákazník | `#38BDF8` | **`#2CD1D4`** | akvamarín | Drahokamy | T2 záře + jiskry | tmavý #0F1A14 · 9,49 : 1 |
| 12 | Mistr silnic | `#3B82F6` | **`#6EAFFF`** | azurová | Drahokamy | T2 záře + jiskry | tmavý #0F1A14 · 7,84 : 1 |
| 13 | Šampion | `#6366F1` | **`#00A1C7`** | blankytná (cerulean) | Drahokamy | T2 záře + jiskry | tmavý #0F1A14 · 5,88 : 1 |
| 14 | Veterán MotoGo | `#8B5CF6` | **`#5087D4`** | kobaltová | Drahokamy | T2 záře + jiskry | tmavý #0F1A14 · 4,89 : 1 |
| 15 | Elitní jezdec | `#A855F7` | **`#117897`** | hlubinná petrolejová | Drahokamy | T2 záře + jiskry | bílý #FFFFFF · 5,05 : 1 |
| 16 | Ambasador | `#D946EF` | **`#165EEB`** | královský safír | Drahokamy | T2 záře + jiskry | bílý #FFFFFF · 5,48 : 1 |
| 17 | VIP | `#EF4444` | **`#D42020`** | závodní karmín | VIP | T3 animovaná fólie + koruna | bílý #FFFFFF · 5,21 : 1 |
| 18 | VIP Gold | `#D4AF37` | **`#EDB42D`** | sytě zlatá (24 k) | VIP | T3 animovaná fólie + koruna | tmavý #0F1A14 · 9,48 : 1 |
| 19 | VIP Platinum | `#F1F5F9` | **`#F5F8FB`** | platinová perla | VIP | T3 animovaná fólie + koruna | tmavý #0F1A14 · 16,72 : 1 |
| 20 | Legenda MotoGo | `#FFD700` | **`#FF8C1A`** | ohnivé (roztavené) zlato | Legenda | T4 oheň + vavřín | tmavý #0F1A14 · 7,65 : 1 |

### T2 · CIEDE2000 matrix (new ramp; bold = neighbours; minimum per column at the bottom)
| L | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **1** | · | **16** | 21 | 19 | 20 | 30 | 15 | 23 | 14 | 20 | 19 | 30 | 25 | 33 | 31 | 45 | 49 | 29 | 20 | 35 |
| **2** | **16** | · | **16** | 23 | 28 | 41 | 30 | 23 | 25 | 22 | 20 | 39 | 36 | 45 | 44 | 57 | 66 | 34 | 21 | 46 |
| **3** | 21 | **16** | · | **16** | 28 | 46 | 31 | 26 | 31 | 35 | 25 | 49 | 42 | 52 | 47 | 62 | 78 | 38 | 31 | 54 |
| **4** | 19 | 23 | **16** | · | **16** | 42 | 25 | 33 | 29 | 32 | 19 | 39 | 29 | 39 | 32 | 49 | 70 | 40 | 35 | 52 |
| **5** | 20 | 28 | 28 | **16** | · | **41** | 22 | 39 | 26 | 24 | 13 | 26 | 13 | 26 | 19 | 37 | 59 | 44 | 34 | 49 |
| **6** | 30 | 41 | 46 | 42 | **41** | · | **24** | 25 | 30 | 43 | 44 | 45 | 44 | 44 | 43 | 52 | 26 | 18 | 36 | 12 |
| **7** | 15 | 30 | 31 | 25 | 22 | **24** | · | **30** | 13 | 26 | 26 | 22 | 20 | 21 | 23 | 29 | 34 | 32 | 25 | 31 |
| **8** | 23 | 23 | 26 | 33 | 39 | 25 | **30** | · | **30** | 38 | 36 | 57 | 48 | 55 | 53 | 71 | 52 | 13 | 27 | 27 |
| **9** | 14 | 25 | 31 | 29 | 26 | 30 | 13 | **30** | · | **17** | 23 | 19 | 23 | 25 | 31 | 35 | 42 | 32 | 14 | 33 |
| **10** | 20 | 22 | 35 | 32 | 24 | 43 | 26 | 38 | **17** | · | **16** | 19 | 21 | 29 | 34 | 40 | 63 | 43 | 16 | 46 |
| **11** | 19 | 20 | 25 | 19 | 13 | 44 | 26 | 36 | 23 | **16** | · | **26** | 18 | 32 | 29 | 45 | 65 | 43 | 27 | 50 |
| **12** | 30 | 39 | 49 | 39 | 26 | 45 | 22 | 57 | 19 | 19 | **26** | · | **16** | 12 | 24 | 26 | 53 | 53 | 27 | 50 |
| **13** | 25 | 36 | 42 | 29 | 13 | 44 | 20 | 48 | 23 | 21 | 18 | **16** | · | **17** | 14 | 27 | 64 | 51 | 32 | 51 |
| **14** | 33 | 45 | 52 | 39 | 26 | 44 | 21 | 55 | 25 | 29 | 32 | 12 | **17** | · | **16** | 14 | 47 | 55 | 36 | 51 |
| **15** | 31 | 44 | 47 | 32 | 19 | 43 | 23 | 53 | 31 | 34 | 29 | 24 | 14 | **16** | · | **18** | 56 | 54 | 42 | 52 |
| **16** | 45 | 57 | 62 | 49 | 37 | 52 | 29 | 71 | 35 | 40 | 45 | 26 | 27 | 14 | **18** | · | **46** | 69 | 47 | 60 |
| **17** | 49 | 66 | 78 | 70 | 59 | 26 | 34 | 52 | 42 | 63 | 65 | 53 | 64 | 47 | 56 | **46** | · | **44** | 50 | 30 |
| **18** | 29 | 34 | 38 | 40 | 44 | 18 | 32 | 13 | 32 | 43 | 43 | 53 | 51 | 55 | 54 | 69 | **44** | · | **33** | 17 |
| **19** | 20 | 21 | 31 | 35 | 34 | 36 | 25 | 27 | 14 | 16 | 27 | 27 | 32 | 36 | 42 | 47 | 50 | **33** | · | **36** |
| **20** | 35 | 46 | 54 | 52 | 49 | 12 | 31 | 27 | 33 | 46 | 50 | 50 | 51 | 51 | 52 | 60 | 30 | 17 | **36** | · |
| min | 14,4 | 15,6 | 15,6 | 15,6 | 12,7 | 12,4 | 12,6 | 12,5 | 12,6 | 15,6 | 12,9 | 12,5 | 12,7 | 12,5 | 14,4 | 14,0 | 25,9 | 12,5 | 13,5 | 12,4 |

Global minimum: **non-neighbours 12,38 (6↔20)**, **neighbours 15,60 (2↔3)** — limits 12 / 15.
Live ramp today for comparison: non-neighbours 0,00 (8↔20), neighbours 4,99 (14↔15); pairs under 12 today: 1↔7 10,2 · 2↔3 7,3 · 3↔4 6,8 · 7↔9 8,6 · 8↔18 11,4 · 8↔20 0,0 · 9↔19 4,9 · 10↔11 7,3 · 12↔13 12,0 · 13↔14 7,2 · 14↔15 5,0 · 15↔16 8,5 · 18↔20 11,4

### T3 · Per level: CIELAB L\*C\*h, HSL hue, nearest other level
| L | new | L\* | C\* | h° (LCh) | HSL hue | nearest (ΔE00) | ΔE to L−1 | ΔE to L+1 |
|---|---|---|---|---|---|---|---|---|
| 1 | `#A3B8A8` | 72,8 | 11,8 | 151 | 134° | 9 (14,4) | — | 16,3 |
| 2 | `#BDF6D1` | 92,3 | 27,9 | 155 | 141° | 3 (15,6) | 16,3 | 15,6 |
| 3 | `#4ADE80` | 79,2 | 68,9 | 150 | 142° | 2 (15,6) | 15,6 | 15,6 |
| 4 | `#00AC7F` | 62,5 | 50,0 | 165 | 164° | 3 (15,6) | 15,6 | 15,7 |
| 5 | `#0AA2A4` | 60,4 | 35,0 | 198 | 181° | 13 (12,7) | 15,7 | 40,9 |
| 6 | `#C2844A` | 60,3 | 44,2 | 66 | 29° | 20 (12,4) | 40,9 | 24,0 |
| 7 | `#929496` | 61,2 | 1,3 | 256 | — (neutrální) | 9 (12,6) | 24,0 | 30,4 |
| 8 | `#E5D376` | 84,3 | 48,4 | 97 | 50° | 18 (12,5) | 30,4 | 29,8 |
| 9 | `#B9BEC6` | 76,8 | 4,6 | 268 | 217° | 7 (12,6) | 29,8 | 16,5 |
| 10 | `#AEE9FF` | 89,2 | 21,5 | 231 | 196° | 11 (15,6) | 16,5 | 15,6 |
| 11 | `#2CD1D4` | 76,6 | 40,5 | 199 | 181° | 5 (12,9) | 15,6 | 26,0 |
| 12 | `#6EAFFF` | 70,3 | 45,9 | 273 | 213° | 14 (12,5) | 26,0 | 15,8 |
| 13 | `#00A1C7` | 61,3 | 36,3 | 234 | 191° | 5 (12,7) | 15,8 | 16,6 |
| 14 | `#5087D4` | 55,9 | 45,4 | 277 | 215° | 12 (12,5) | 16,6 | 15,7 |
| 15 | `#117897` | 46,7 | 29,0 | 237 | 194° | 13 (14,4) | 15,7 | 17,7 |
| 16 | `#165EEB` | 44,5 | 83,4 | 294 | 220° | 14 (14,0) | 17,7 | 46,0 |
| 17 | `#D42020` | 45,8 | 81,2 | 36 | 0° | 6 (25,9) | 46,0 | 44,4 |
| 18 | `#EDB42D` | 76,6 | 71,3 | 83 | 42° | 8 (12,5) | 44,4 | 32,7 |
| 19 | `#F5F8FB` | 97,4 | 1,8 | 256 | — (neutrální) | 9 (13,5) | 32,7 | 35,7 |
| 20 | `#FF8C1A` | 69,5 | 80,3 | 62 | 30° | 6 (12,4) | 35,7 | — |

### T4 · Contrast of the raw `color_hex` (how the live app paints it today) — WCAG 2.x
| L | new | rel. lum. | ring vs header `#0A1A10` (≥3) | rank text on pill `#1A2E22` (≥4.5 / large ≥3) | on-accent ink `#0F1A14` | on-accent white | **best on-accent** | today `_onColor` (lum > 0.5) | level-up „+N“ badge min over [c, c·75 %] best |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `#A3B8A8` | 0,449 | 8,54 | 6,85 | 8,47 | 2,10 | tmavý 8,47 | bílý 2,10 ✗ | tmavý 4,89 |
| 2 | `#BDF6D1` | 0,813 | 14,78 | 11,84 | 14,66 | 1,22 | tmavý 14,66 | tmavý 14,66 | tmavý 8,13 |
| 3 | `#4ADE80` | 0,553 | 10,32 | 8,27 | 10,23 | 1,74 | tmavý 10,23 | tmavý 10,23 | tmavý 5,83 |
| 4 | `#00AC7F` | 0,310 | 6,17 | 4,94 | 6,12 | 2,91 | tmavý 6,12 | bílý 2,91 ✗ | tmavý 3,65 |
| 5 | `#0AA2A4` | 0,286 | 5,75 | 4,61 | 5,70 | 3,13 | tmavý 5,70 | bílý 3,13 ✗ | tmavý 3,46 |
| 6 | `#C2844A` | 0,285 | 5,73 | 4,59 | 5,68 | 3,14 | tmavý 5,68 | bílý 3,14 ✗ | tmavý 3,45 |
| 7 | `#929496` | 0,295 | 5,91 | 4,73 | 5,86 | 3,04 | tmavý 5,86 | bílý 3,04 ✗ | tmavý 3,54 |
| 8 | `#E5D376` | 0,646 | 11,91 | 9,54 | 11,81 | 1,51 | tmavý 11,81 | tmavý 11,81 | tmavý 6,61 |
| 9 | `#B9BEC6` | 0,512 | 9,63 | 7,71 | 9,54 | 1,87 | tmavý 9,54 | tmavý 9,54 | tmavý 5,48 |
| 10 | `#AEE9FF` | 0,745 | 13,61 | 10,91 | 13,49 | 1,32 | tmavý 13,49 | tmavý 13,49 | tmavý 7,51 |
| 11 | `#2CD1D4` | 0,509 | 9,57 | 7,67 | 9,49 | 1,88 | tmavý 9,49 | tmavý 9,49 | tmavý 5,42 |
| 12 | `#6EAFFF` | 0,412 | 7,91 | 6,34 | 7,84 | 2,27 | tmavý 7,84 | bílý 2,27 ✗ | tmavý 4,56 |
| 13 | `#00A1C7` | 0,296 | 5,93 | 4,75 | 5,88 | 3,03 | tmavý 5,88 | bílý 3,03 ✗ | tmavý 3,54 |
| 14 | `#5087D4` | 0,238 | 4,93 | 3,95 (jen velký) | 4,89 | 3,65 | tmavý 4,89 | bílý 3,65 ✗ | bílý 3,65 |
| 15 | `#117897` | 0,158 | 3,56 | 2,85 ✗ | 3,53 | 5,05 | bílý 5,05 | bílý 5,05 | bílý 5,05 |
| 16 | `#165EEB` | 0,142 | 3,28 | 2,63 ✗ | 3,25 | 5,48 | bílý 5,48 | bílý 5,48 | bílý 5,48 |
| 17 | `#D42020` | 0,151 | 3,45 | 2,76 ✗ | 3,42 | 5,21 | bílý 5,21 | bílý 5,21 | bílý 5,21 |
| 18 | `#EDB42D` | 0,508 | 9,56 | 7,66 | 9,48 | 1,88 | tmavý 9,48 | tmavý 9,48 | tmavý 5,42 |
| 19 | `#F5F8FB` | 0,935 | 16,87 | 13,52 | 16,72 | 1,07 | tmavý 16,72 | tmavý 16,72 | tmavý 9,16 |
| 20 | `#FF8C1A` | 0,401 | 7,72 | 6,19 | 7,65 | 2,33 | tmavý 7,65 | bílý 2,33 ✗ | gradient Legendy (pevně tmavý #241A06) |

### T5 · Redesign tokens (rank-theme.css, solved) — every value meets its WCAG target
| L | tier | CTA fill (4 stops) · label | label min | accent on dark `#0E2A1C` | accent on hero glass (`--rk-acc-g`) | accent on light page `#DFF0EC` / white | chip text / bg | ring / marks vs night `#0A1F14` |
|---|---|---|---|---|---|---|---|---|
| 1 | road | `#8DFF86` → `#70EF7A` → `#54DF6F` → `#37CF63` · `#08230F` | 8,16 | `#A3B8A8` 7,30 | `#A3B8A8` 4,66 | `#5F6B61` 4,73 / 5,58 | `#A3B8A8` / `#264132` · 5,30 | `#A3B8A8` 8,19 |
| 2 | road | `#8DFF86` → `#87F68D` → `#80EC93` → `#7AE39A` · `#08230F` | 10,56 | `#BDF6D1` 12,63 | `#BDF6D1` 7,96 | `#536C5C` 4,86 / 5,73 | `#BDF6D1` / `#2A4B39` · 7,98 | `#BDF6D1` 14,16 |
| 3 | road | `#8DFF86` → `#74F27F` → `#5AE479` → `#41D772` · `#08230F` | 8,90 | `#4ADE80` 8,82 | `#4ADE80` 5,72 | `#287845` 4,61 / 5,44 | `#4ADE80` / `#18472C` · 6,10 | `#4ADE80` 9,89 |
| 4 | road | `#8DFF86` → `#67E97F` → `#42D478` → `#1CBE71` · `#08230F` | 6,88 | `#00AC7F` 5,27 | `#42C2A0` 4,70 | `#007859` 4,65 / 5,48 | `#1AB48C` / `#0C3F2C` · 4,51 | `#00AC7F` 5,91 |
| 5 | road | `#8DFF86` → `#69E885` → `#45D085` → `#21B984` · `#08230F` | 6,63 | `#0AA2A4` 4,92 | `#4FBCBD` 4,65 | `#077576` 4,67 / 5,50 | `#2CAFB1` / `#0D3D32` · 4,55 | `#0AA2A4` 5,51 |
| 6 | metal | `#E4C8AE` → `#CD9A6B` → `#C2844A` → `#AF7743` · `#1A1405` | 4,84 | `#C2844A` 4,90 | `#D2A479` 4,64 | `#8C5F35` 4,68 / 5,52 | `#C99360` / `#2B3823` · 4,62 | `#C2844A` 5,49 |
| 7 | metal | `#CECFD0` → `#A6A7A9` → `#929496` → `#838587` · `#0B1512` | 5,02 | `#929496` 5,05 | `#B1B2B3` 4,72 | `#666869` 4,75 / 5,60 | `#9D9FA1` / `#233B30` · 4,55 | `#929496` 5,66 |
| 8 | metal | `#F3EBC1` → `#EADB8F` → `#E5D376` → `#CEBE6A` · `#1A1405` | 9,77 | `#E5D376` 10,18 | `#E5D376` 6,37 | `#72693B` 4,69 / 5,53 | `#E5D376` / `#30452A` · 6,92 | `#E5D376` 11,41 |
| 9 | metal | `#E0E2E5` → `#C6CAD0` → `#B9BEC6` → `#A7ABB2` · `#0B1512` | 8,06 | `#B9BEC6` 8,23 | `#B9BEC6` 5,21 | `#686A6F` 4,59 / 5,41 | `#B9BEC6` / `#294237` · 5,83 | `#B9BEC6` 9,22 |
| 10 | jewel | `#AEE9FF` → `#B5E3FF` → `#BCDDFF` → `#C3D7FF` · `#0A1F33` | 11,53 | `#AEE9FF` 11,63 | `#AEE9FF` 7,28 | `#506B75` 4,81 / 5,67 | `#AEE9FF` / `#284940` · 7,51 | `#AEE9FF` 13,04 |
| 11 | jewel | `#2CD1D4` → `#49CAD9` → `#65C4DF` → `#82BDE4` · `#0A1F33` | 8,23 | `#2CD1D4` 8,18 | `#2CD1D4` 5,22 | `#197577` 4,62 / 5,45 | `#2CD1D4` / `#134539` · 5,77 | `#2CD1D4` 9,17 |
| 12 | jewel | `#6EAFFF` → `#67B4EF` → `#61B9E0` → `#5ABED0` · `#0A1F33` | 7,35 | `#6EAFFF` 6,76 | `#7DB7FF` 4,69 | `#446C9E` 4,59 / 5,41 | `#6EAFFF` / `#1D3F40` · 5,03 | `#6EAFFF` 7,58 |
| 13 | jewel | `#00A1C7` → `#1F9BCE` → `#3D96D5` → `#5C90DC` · `#0A1F33` | 5,15 | `#00A1C7` 5,07 | `#4DBDD8` 4,68 | `#00748F` 4,57 / 5,39 | `#1FACCE` / `#0C3D37` · 4,52 | `#00A1C7` 5,68 |
| 14 | jewel | `#5087D4` → `#4A8BC5` → `#448FB5` → `#3E93A6` · `#0A1F33` | 4,58 | `#6293D8` 4,89 | `#8EB1E3` 4,71 | `#3E69A5` 4,73 / 5,57 | `#739FDD` / `#193939` · 4,59 | `#5087D4` 4,72 |
| 15 | jewel | `#117897` → `#22749F` → `#346FA6` → `#456BAE` · `#FFFFFF` | 5,05 | `#4F9BB2` 4,88 | `#80B7C8` 4,67 | `#107391` 4,59 / 5,41 | `#58A1B6` / `#0E3630` · 4,52 | `#117897` 3,41 |
| 16 | jewel | `#165EEB` → `#1365CF` → `#0F6BB2` → `#0C7296` · `#FFFFFF` | 5,44 | `#5C8EF1` 4,83 | `#8AAEF5` 4,72 | `#165EEB` 4,65 / 5,48 | `#6595F2` / `#0F323D` · 4,62 | `#2468EC` 3,50 |
| 17 | vip | `#FFFBF2` → `#FCF2E3` → `#F8E9D2` → `#F3DEC0` · `#7F1D1D` | 7,64 | `#F3D27E` 10,49 | `#F3D27E` 7,64 | `#D01F1F` 4,57 / 5,39 | `#F3D27E` / `#2E281D` · 9,97 | `#D52422` 3,37 |
| 18 | vip | `#F7E9B8` → `#E6C869` → `#EDB42D` → `#B8932A` · `#14100A` | 6,54 | `#EDB42D` 8,17 | `#EDB42D` 5,14 | `#856519` 4,60 / 5,42 | `#EDB42D` / `#32401F` · 5,91 | `#EDB42D` 9,16 |
| 19 | vip | `#FFFFFF` → `#F6F8FB` → `#EAEFF5` → `#DCE3EC` · `#14100A` | 14,66 | `#F5F8FB` 14,42 | `#F5F8FB` 9,08 | `#676869` 4,74 / 5,58 | `#F5F8FB` / `#334B40` · 8,87 | `#F5F8FB` 16,16 |
| 20 | legend | `#FFE27A` → `#FFD700` → `#FF9A1F` → `#FF6B00` · `#241A06` | 6,00 | `#FF8C1A` 6,60 | `#FF9831` 4,61 | `#9E5710` 4,66 / 5,49 | `#FF8C1A` / `#353A1C` · 5,09 | `#FF8C1A` 7,40 |

## 6. App code changes (both trees, same commit: `motogo-app-flutter` + `motogo-app-flutter-ios`)

The ramp is designed so the **DB change alone never makes on-accent text unreadable once these changes ship**. Ship them **before or with** the SQL. Release order: app update first, then the SQL. Without them, the rank names of 14–17 on the dark pill are 2.6–3.9:1 and 8 levels get white-on-light text. Today the live ramp already fails at 12 levels on `_onColor` and has 12–17 at 3.2–4.2:1 on the pill.

**Shared helpers.** Put them in `features/loyalty/loyalty_provider.dart`, next to `colorFromHex`:

```dart
const _rankInk = Color(0xFF0F1A14);
double _wcag(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}
/// Text ON the rank colour: whichever of ink / white has the higher contrast (≈ luminance > 0.199 → ink).
Color onRankColor(Color c) => _wcag(c, _rankInk) >= _wcag(c, Colors.white) ? _rankInk : Colors.white;
/// Same for a gradient fill: best MIN contrast over all stops.
Color onRankGradient(List<Color> s) {
  double m(Color t) => s.map((x) => _wcag(x, t)).reduce(math.min);
  return m(_rankInk) >= m(Colors.white) ? _rankInk : Colors.white;
}
/// Rank colour used AS TEXT on a dark surface: lifted toward white until ≥ 4.5:1; reds use the champagne trim (never salmon/pink).
Color rankTextOnDark(Color c, {Color bg = const Color(0xFF1A2E22), double target = 4.5}) {
  if (_wcag(c, bg) >= target) return c;
  final h = HSLColor.fromColor(c);
  if ((h.hue < 20 || h.hue > 340) && h.saturation > .25) return const Color(0xFFF3D27E);
  for (var t = .02; t <= 1; t += .02) { final x = Color.lerp(c, Colors.white, t)!; if (_wcag(x, bg) >= target) return x; }
  return Colors.white;
}
```

| # | File:line (identical in both trees) | Change | Owner OK? |
|---|---|---|---|
| A1 | `features/loyalty/loyalty_ranks_screen.dart:576-577` `_onColor` (used :529 medallion number, :570 „Ty“ chip) | body → `onRankColor(c)` | not needed |
| A2 | `features/loyalty/loyalty_leaderboard_section.dart:342` inline `computeLuminance() > 0.5` (avatar initial) | → `onRankColor(color)` | not needed |
| B1 | `features/loyalty/loyalty_rank_card.dart:274` `_rankNameText` (`status.color` on pill `#1A2E22`, 14 / 18 px) | `color: status.isLegend ? Colors.white : rankTextOnDark(status.color)` | not needed |
| B2 | `features/loyalty/loyalty_ranks_screen.dart:348` `_rankName` (22 / 40 px on `#0A1A10`) and `:544` `_percentPill` (16 px) | → `rankTextOnDark(color, bg: MotoGoColors.gradientTop)`; the pill uses the card background as `bg` | not needed |
| B3 | `features/profile/profile_screen.dart:478` edit icon in the rank colour | → `rankTextOnDark(rankColor, target: 3)` | not needed |
| C | `features/loyalty/loyalty_levels_provider.dart:46-65` `_fallbackLevels` (offline / RPC-fail fallback) | colorHex → the 20 new values (T1) | with the SQL |
| D1 | **protected** `features/loyalty/loyalty_levelup_overlay.dart:718-719` `_onColor` (used :617 „Pokračovat“ text, :659 „+N“ badge) | **describe only.** Threshold `computeLuminance() > 0.5` → pick by contrast (`onRankColor`), or simply `> 0.2`. Only the colour of these two labels changes; montage, music, timing and ring morph are untouched. With the old rule, the new ramp gives white text on 1, 4, 5, 6, 7, 12, 13, 14 at 2.1–3.7:1. With the fix, „Pokračovat“ (solid fill) is ≥ 4.89 on all 19 non-Legend levels. | **yes — „lvl up video neměň“** |
| D2 | protected, same file :659 „+N“ badge | With D1 use `onRankGradient([c, Color.lerp(c, Colors.black, .25)!])`. The badge's own darker end limits it to 3.45–3.65:1 on 4, 5, 6, 7, 13, 14 (≥ 3 everywhere, ≈ 4.5 at the badge centre; 17 px w900). A full 4.5 would need a different badge gradient → **not proposed** (protected). | yes (with D1) |
| D3 | protected, :83/:120/:140/:198 `mg_loyalty_last_color_<uid>` | The next level-up morphs the ring FROM the stored OLD hex (one-off, e.g. old violet → new petrol). Optional: when reading `lastColorHex`, map the 18 old hexes to the new colour of the stored `_lvlKey` level; default `'#9CA3AF'` → `'#A3B8A8'`. Otherwise accept the one-off. | yes, optional |
| E | `features/loyalty/loyalty_rank_card.dart:111` progress bar on `g200` in a white card | optional: use a darkened bar colour (`uiLight` logic, ≥ 3:1 vs white). The light ranks 2, 10, 19 (and 9 / 19 today) are near-invisible as a bar fill. | not needed |
| F | defaults `'#9CA3AF'` when JSON lacks `color_hex` (`loyalty_provider.dart:76`, `loyalty_levels_provider.dart:38`, `loyalty_leaderboard_provider.dart:51`) | optional → `'#A3B8A8'` (the column is NOT NULL, so this is cosmetic) | not needed |

**Not affected:**
- Level-up `_rankTitle` (30 px w900, raw colour) stays ≥ 3.28:1 vs `#0A1A10` on every level (large-text AA).
- Legend paths keep `legendGradientColors` and `#241A06` text.
- **Velín, web, kiosk, e-mails:** no rank colours (verified in v2.1, `research/rank_colors.md` §6).
- `20260917…sql:217` `COALESCE(color_hex,'#9CA3AF')` never fires (NOT NULL).
- `ai-copilot` only reads the table.
- The app's non-rank purples (`#7C3AED` in `routes_map_picker.dart:22`, `res_modification_history.dart:204/264`) are on the existing port checklist (`DESIGN_V21.md:837` „Port checklist · no purple“).

## 7. Design files touched / to re-embed

**Changed by me** (backup of every pre-change file: `appdesign/bak-rankramp/`):
- `research/rankTheme.js`: new SEED; red TRIM / apricot lift; deep-glow lift; jewel label by contrast + `matchLum`; exports `lum`, `fit`, `TRIM`.
- `gen/gen.js`: solved acc-g / jbo / prs / arc instead of hand tables; arc check; full-CSS hue scan.
- `gen/rank-head.css` and `gen/rank-theme.tpl.js`: v2.2 header notes.
- Regenerated by `node gen/gen.js`:
  - **`shared/rank-theme.css`** (240 / 240 braces) and **`shared/rank-theme.js`** (`rankTheme(1..20)` × 8 languages runs);
  - `gen/contrast.md`.
- Output: „levels 20 contrast failures: none · hue scan (violet/pink): none“.

**Boards (orchestrator).** All 12 boards embed the previous shared copy verbatim. The dry run says „css: swapped · js: swapped (indent 4)“ for every board:

```
cd appdesign && python3 gen/reembed_rank.py --old bak-rankramp project/*.dc.html           # dry run
cd appdesign && python3 gen/reembed_rank.py --old bak-rankramp --write project/*.dc.html   # apply
```

After the swap, these hand-written leftovers remain. Everything else that still matches an old hex is non-rank: SOS / error `#EF4444`, crown `#D4AF37`, legend gradient `#FFD700`, podium gold / silver / bronze, the `#7DD3FC` visibility ring in Zážitky, and the petrol history `#19A2B4` in Reservation.
- `RankStyly.dc.html:583` `.trk i` gradient starts at the old Startér `#9CA3AF` → `#A3B8A8`.
- `RankStyly.dc.html:2111-2119` `TX` copy:

| Key | Field | New value |
|---|---|---|
| road | `cr` | `'kontrast 6,6–10,6 : 1'` |
| metal | `cr` | `'kontrast 4,8–9,8 : 1'` |
| jewel | `cr` | `'kontrast 4,6–11,5 : 1'` |
| jewel | `note` | `'Světlé drahokamy 10–14 (led → kobalt) nesou tmavé písmo, hluboké 15–16 (petrolej, safír) bílé; vše ≥ 4,6 : 1.'` |
| vip | `note` | `'VIP = závodní karmín #D42020 (ne SOS červená): karmínový prstenec a záře, tlačítko slonovinové s karmínovým písmem a červeno-zlatým rámem, text ranku šampaňský.'` |
| legend | `note` | `'Legenda má jako jediná ohnivé zlato (#FF8C1A, v appce přechod #FFD700→#FF6B00) — Zlatý jezdec je světlé žluté zlato #E5D376, VIP Gold sytě zlatá #EDB42D.'` |

- `RankStyly.dc.html:2187` `RC` (the 13–16 recolour list): replace it with the full ramp as `[L, old, new, název, text na štítku #1A2E22]`:
  `[[1,'#9CA3AF','#A3B8A8','šalvějová','6,85'],[2,'#86EFAC','#BDF6D1','mátová','11,84'],[4,'#22C55E','#00AC7F','smaragdová','4,94'],[5,'#14B8A6','#0AA2A4','nefritová tyrkys','4,61'],[6,'#CD7F32','#C2844A','bronz','4,59'],[7,'#C0C0C0','#929496','stříbro','4,73'],[8,'#FFD700','#E5D376','žluté zlato','9,54'],[9,'#E5E4E2','#B9BEC6','platina','7,71'],[10,'#7DD3FC','#AEE9FF','led','10,91'],[11,'#38BDF8','#2CD1D4','akvamarín','7,67'],[12,'#3B82F6','#6EAFFF','azurová','6,34'],[13,'#6366F1','#00A1C7','blankytná','4,75'],[14,'#8B5CF6','#5087D4','kobaltová','3,95'],[15,'#A855F7','#117897','hlubinná petrolejová','2,85'],[16,'#D946EF','#165EEB','královský safír','2,63'],[17,'#EF4444','#D42020','závodní karmín','2,76'],[18,'#D4AF37','#EDB42D','sytě zlatá','7,66'],[19,'#F1F5F9','#F5F8FB','platinová perla','13,52'],[20,'#FFD700','#FF8C1A','ohnivé zlato','6,19']]`
  - Levels 14–17 under 4.5 are exactly why §6 B1 lifts the text. The redesign tokens are ≥ 4.6 (T5).
- **`DESIGN_V21.md` lines to update:**
  - 12 and 65: SQL → `20261016_loyalty_colors_ramp.sql`;
  - 42: tier table for VIP 17 crimson and champagne text; jewel labels 10–14 navy, 15–16 white;
  - 58–61: replace the 13–16 rows with T1;
  - 74: re-embed with `--old bak-rankramp`;
  - 679: the level-up default `#9CA3AF` (see D3);
  - 1018: approval list;
  - 1033: VIP glow is now crimson `#D42020`, not the SOS `#EF4444`, so the question is answered.
- **Superseded:** `research/rank_colors.md` and `sql/20261015_loyalty_colors_no_purple.sql`.

## 8. SQL — `appdesign/sql/20261016_loyalty_colors_ramp.sql` (scratchpad only, NOT in the repo)

What the file does:
- Czech header.
- 19 guarded `UPDATE public.loyalty_levels SET color_hex = '<new>' WHERE level = N AND upper(color_hex) = '<live>'`. For 13–16 the guard also accepts the unapplied v2.1 values (`IN ('#6366F1','#FF5A0C')` …). Level 3 is unchanged.
- A `DO` block raises a NOTICE for any level that is not the expected colour (a manual Velín edit is left alone) and for any colour shared by two or more ranks. It never fails the deploy.
- No BEGIN / COMMIT (`deploy-sql.yml` uses `--single-transaction`).
- A verification query and a full rollback are included, commented.

**Tested** on a throwaway local PostgreSQL 16 (copy of the live table, `--single-transaction -v ON_ERROR_STOP=1`):

| Test | Result |
|---|---|
| Run 1 on the live values | 19 × `UPDATE 1`, final ramp exact, no NOTICE |
| Run 2 (idempotence) | 19 × `UPDATE 0` |
| Manual edits (7 custom, 13 = v2.1 orange, 1 lower-case, 20 custom) | 13 and 1 recoloured; 7 and 20 left alone, each with a NOTICE |
| 8 pre-set to `#FF8C1A` | NOTICE „sdílí více ranků (8, 20)“ |
| Verification query | 0 rows |
| Rollback | restores the live values exactly |

Only the colour changes. `get_loyalty_status`, `admin_loyalty_status`, the leaderboard RPC and the app's `loyaltyLevelsProvider` read the table, so everything recolours on the next fetch.

**After approval** (CLAUDE.md rules 3–4): commit to `supabase/migrations/` together with or after the app release carrying §6 A–C; add a STATE_6 changelog row; add a STATE_2 note under `loyalty_levels.color_hex` („2026-10-16 nová škála 1–20 …“).

## 9. Text for the owner (Czech, chat)

> Barvy ranků jsou teď jedna stoupající škála, ve které si žádné dvě nejsou podobné (barevný rozdíl ΔE ≥ 12,4, sousední ≥ 15,6; dnes měly Zlatý a Legenda dokonce stejnou barvu a 13–16 byly fialové):
> - **začátek zelený**: šalvěj → máta → svěží zelená (Motorkář beze změny) → smaragd → nefritová tyrkys;
> - **kovy podle názvů**: bronz, stříbro, světlé žluté zlato, studená platina;
> - **uprostřed modré drahokamy, čím hlubší, tím vzácnější**: led → akvamarín → azur → blankyt → kobalt → hlubinný petrolej → královský safír;
> - **VIP**: závodní karmín, sytě zlatá, platinová perla, vždy s korunkou;
> - **nahoře jen Legenda v ohnivém zlatě**, jediná s plamenem a vavřínem.
>
> Žádná růžová ani fialová. Efekty rostou s rankem (plochý → kovový lesk → záře → animovaná fólie s korunkou → oheň). Text na barvě ranku je vždy čitelný. Do databáze jde jen přebarvení 19 řádků, SQL je připravené ke schválení. Spolu s ním je potřeba drobná oprava v appce (výběr tmavého/bílého písma podle kontrastu). U oslavy level-upu by se změnila jen barva písma na tlačítku „Pokračovat“ a v odznaku „+N“, a to jen s tvým souhlasem.

## 10. Working files

`ramp_work/` in the scratchpad holds:
- `color.js` (CIEDE2000 + WCAG);
- the optimizer `opt5.js` with configs `cfgA…cfgK.js`;
- `ev.js` (evaluation), `tables.js` (generates T1–T4), `tok.py` (generates T5), `pv.js` and `pvr.js` (previews), `shot.js` (Playwright screenshots).
