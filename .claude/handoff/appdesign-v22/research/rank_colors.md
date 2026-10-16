# Rank colours v2.1: no pink or purple

Owner, 2026-10-15: "V barvách ranků by neměla být růžová ani fialová, je to pro chlapy." This covers (a) the new colours, (b) the cleanup in `appdesign/shared`, (c) the SQL draft and (d) every place in the repo that hard-codes rank colours.

## 1. Decision (a)

| L | Rank | old `color_hex` | **new** | Name / meaning | Gem story (Liga drahokamů) |
|---|---|---|---|---|---|
| 13 | Šampion | `#6366F1` indigo | **`#FF5A0C`** | závodní oranžová (racing / KTM orange, podium flame) | ohnivý opál |
| 14 | Veterán MotoGo | `#8B5CF6` violet | **`#8A9A3B`** | olivová (olive drab, the army "veteran") | olivín (peridot) |
| 15 | Elitní jezdec | `#A855F7` purple | **`#B39E7E`** | coyote / pouštní khaki (special-forces tan) | tygří oko |
| 16 | Ambasador | `#D946EF` magenta | **`#19A2B4`** | petrolejová (deep petrol, diplomatic) | petrolejový turmalín |

The ladder after the change: 10 ice blue → 11 sky → 12 blue → **13 orange → 14 olive → 15 coyote → 16 petrol** → 17 VIP red → 18 VIP gold → 19 VIP platinum → 20 Legend. Every hue sits outside 235–345° (no violet, magenta or pink).

**Why not titanium or gunmetal (the brief's suggestion):** a cool grey only reads as text on the app's dark pill `#1A2E22` at ≥ 4.5:1 when it is light (L* ≥ ~60). At that lightness it collides with Startér `#9CA3AF`: the best candidate, `#6399AB`, scores ΔE 14.4 vs Startér and 14.2 vs level 11, and it turns into steel-blue (petrol's neighbour). A real dark gunmetal such as `#4B5563` reaches only 2.1:1 on the dark header, so the logo ring would disappear. "Carbon" fails for the same reason. Coyote tan gives "elite" (special-forces gear) without these problems.

Other options I scored and dropped:

| Option | Best hex | min ΔE vs others | Why dropped |
|---|---|---|---|
| amber / whisky | `#FFA305` | 13.5 | wedged between bronze 6 and gold 8/18 |
| acid lime (Kawasaki) | `#C3FF1F` | 20.3 | reads as the brand neon `#74FB71`, confuses the brand |
| sand / taupe | `#A9947E` | 16.5 | low-saturation red-brown reads dusty-pink, which is risky for this owner |
| electric cyan | `#14FFFF` | 18.1 | not "petrol", looks toy-like |

## 2. Distinctness (CIEDE2000; implementation checked against the Sharma 2005 test pairs)

- Each new colour vs all 19 other levels: minimum **14.5**. Nearest pairs: 13↔17 VIP 14.5 · 13↔6 Bronz 14.6 · 16↔5 and 16↔11 14.7 · 15↔18 16.2 · 14↔18 17.8.
- The 13–16 cluster before was 13↔14 7.2 · 14↔15 5.0 · 15↔16 8.5, almost indistinguishable. Now: 13↔14 45.6 · 14↔15 18.0 · 15↔16 31.8 · 16↔17 68.4 · 12↔13 51.1.
- Minimum ΔE per level, before → after: 5: 19.0→14.7 · 6: 19.0→14.6 · 12: 12.0→20.6 · 13: 7.2→14.5 · 14: 5.0→17.8 · 15: 5.0→16.2 · 16: 8.5→14.7 · 17: 24.3→14.5. Other levels are unchanged.
- **Pre-existing near-duplicates, out of scope, owner FYI:** 2↔3 7.3 · 3↔4 6.8 · 10↔11 7.3 · 7↔1 8.6 · 9↔19 4.9 · 8↔18 11.4 · 8 = 20 identical `#FFD700` (Legenda is told apart by its gradient and laurel). ΔE > 12 between all neighbours is not reachable without recolouring the road greens and the metals too.

## 3. WCAG contrast of the new colours (raw `color_hex`, as the live app uses it today)

| L | old → new | hue | text in colour on `#1A2E22` (app pill) | on `#0E2A1C` | on `#0A1A10` (header) | dark `#0F1A14` text on colour | white text on colour | app today `_onColor` (threshold 0.5) |
|---|---|---|---|---|---|---|---|---|
| 13 | `#6366F1` → **`#FF5A0C`** | 19° | 4.61 | 4.92 | 5.75 | **5.70** | 3.13 | white 3.13 ✗ |
| 14 | `#8B5CF6` → **`#8A9A3B`** | 70° | 4.64 | 4.95 | 5.79 | **5.74** | 3.10 | white 3.10 ✗ |
| 15 | `#A855F7` → **`#B39E7E`** | 36° | 5.56 | 5.93 | 6.94 | **6.88** | 2.59 | white 2.59 ✗ |
| 16 | `#D946EF` → **`#19A2B4`** | 187° | 4.71 | 5.03 | 5.88 | **5.83** | 3.06 | white 3.06 ✗ |

- The old purples as text on `#1A2E22`: 3.22 / 3.40 / 3.64 / 4.17, all failing 4.5. The new colours **all pass**: the rank name in the rank colour (`loyalty_rank_card._rankNameText`, ranks screen) becomes readable, and the logo ring on the header is ≥ 5.7:1.
- **On-accent text must be dark:** white on these mid-tones is only 2.6–3.1:1. The app's `_onColor` picks white below luminance 0.5, which already fails today for 12 of 20 levels (for example 4 `#22C55E` 2.28, 11 `#38BDF8` 2.14, 18 `#D4AF37` 2.10, 17 `#EF4444` 3.76). The companion fix is in §6 (pick the higher-contrast of ink or white). With it, all 20 levels get ≥ 4.5; the only two that would not, 13 and 14 *old* at 4.47 / 4.23, go away with this change.
- On light surfaces (Velín, web) the rank colours are not used at all. In the design boards, light surfaces use the solved `accentLight` / `uiLight` tokens, 4.6–5.5 / ≥ 3.0.
- Engine-solved tokens (from `gen/contrast.md`; **0 contrast failures** across all 20 levels):

| L | CTA fill · label | label min | edge vs night | chip text / bg | accent on dark | accent on light (page / white) |
|---|---|---|---|---|---|---|
| 12 | `#245097`→`#247E97` · white | 4.66 | 5.72 | `#629BF8` / `#15383F` 4.53 | 4.83 | 4.56 / 5.37 |
| 13 | `#FF5A0C`→`#FFBB0C` · `#1A1405` | 5.86 | 8.89 | `#FF6B22` / `#353219` 4.55 | 4.92 | 4.69 / 5.53 |
| 14 | `#8A9A3B`→`#9A843B` · `#1A1405` | 5.01 | 6.87 | `#98A653` / `#223C21` 4.56 | 4.95 | 4.64 / 5.47 |
| 15 | `#B39E7E`→`#B3B37E` · `#1A1405` | 7.07 | 9.82 | `#B39E7E` / `#283D2C` 4.52 | 5.93 | 4.60 / 5.42 |
| 16 | `#52B9C7`→`#528AC7` · `#0A1F33` | 4.63 | 6.86 | `#35ADBD` / `#103D34` 4.52 | 5.03 | 4.58 / 5.39 |
| 17 | ivory `#FFFBF2`→`#F3DEC0` · crimson `#7F1D1D` | 7.64 | fill 13.14 vs night | `#F36C63` / `#322E22` 4.61 | 4.89 | 4.69 / 5.53 |
| 19 | `#FFFFFF`→`#DCE3EC` · `#14100A` | 14.66 | 12.98 | 8.77 | 14.03 | 4.82 / 5.68 |

## 4. What changed in `appdesign/shared` (b)

Source of truth: `research/rankTheme.js`, then `node gen/gen.js` (regenerates `shared/rank-theme.css`, `shared/rank-theme.js` and `gen/contrast.md`). I checked that regenerating the old sources reproduces the old shared files byte-for-byte, so nothing was hand-edited away. Backup of every touched file: `appdesign/bak-rankcolors/`.

| Where | Before | After |
|---|---|---|
| `SEED` 13–16 | `#6366F1 #8B5CF6 #A855F7 #D946EF` | `#FF5A0C #8A9A3B #B39E7E #19A2B4` |
| jewel effect stops | `spin(c, ±24/18°)`, so 12 produced indigo `#3F3BF6` / `#3835DA` and 13–16 produced violet→magenta | `spinSafe`: an `offHue` guard rejects hue 235–345°, light muted reds (dusty pink) and derived stops in the brand greens 85–160°. L12 is now blue→teal `#245097→#247E97`; rings are blue/cyan/warm only |
| jewel label | white below lum 0.30 | dark below lum 0.25 (warm ink `#1A1405` on warm hues, navy on cool). Only 12 keeps white, so levels 10–12 are unchanged |
| VIP 17 CTA | pale **pink** foil `#FFF5F6→#FECDD6`, label rose-900 `#881337`, edge `#FB7185 / #E11D48`, glow rose `#F43F5E` | **ivory foil** `#FFFBF2→#F3DEC0`, **crimson** label `#7F1D1D` (7.64), **red–gold–red** frame `#EF4444 / #FDE68A / #B91C1C`, glow `#EF4444` |
| VIP 17 ring, text, arc | white-lightened reds `#F47C7C` / `#F26262` / `#F26969` (salmon-pink) | lightened toward warm cream, not white: ring highlight `#F47359` (gold), accent `#F2625C`, chip `#F36C63`, arc `#F2655E` |
| VIP 19 edge | iridescent `#FBCFE8` (pink-200) → ice → mint → champagne | pearl `#E2E8F0` → ice → mint → champagne |
| `.t-jewel` ambient sweep (`gen/rank-head.css`) | sky + **fuchsia** `rgba(232,121,249,.20)` | rank-tinted `var(--rk-amba)` + white + warm `rgba(255,226,170,.18)` |
| headers | none | v2.1 note in `rank-theme.css` and `rank-theme.js` |

- **Scan:** every colour literal in `shared/*` (rank-theme, levelup, logo, nav, cta, ai-fab) was checked. Nothing sits at hue 235–345°, and there is no light low-saturation red. What remains is true red `#EF4444` (VIP 17 colour, also SOS / errors).
- `levelup.html` / `levelup.js` were not touched. They take colours from `rankTheme()`, and the owner said the level-up stays as it is.
- Sanity check: `rank-theme.js` parses and `rankTheme(1..20)` runs. CSS braces balance (236/236). Board render of RankStyly for ranks 13–17 is in `research/rank_colors_board_13-17.png` and `research/rank_colors_board_list.png`; swatches are in `research/rank_colors_swatches.png`.

### Boards (orchestrator, not edited by me)

All 6 boards (`project/{Main,MotoKatalog,MotoDetail,Booking,Reservation,RankStyly}.dc.html`) embed the **old** CSS and JS verbatim. Each has 14× `#6366F1` / `#8B5CF6` / `#A855F7` / `#D946EF`, plus `#881337`, `#F43F5E`, `#FB7185`, `#FBCFE8`, `#FECDD6` and `rgba(232,121,249)`. To re-embed:

```
cd appdesign && python3 gen/reembed_rank.py --old bak-rankcolors project/*.dc.html          # dry run: all 6 "css: swapped · js: swapped (indent 4)"
cd appdesign && python3 gen/reembed_rank.py --old bak-rankcolors --write project/*.dc.html  # apply
```

After the swap, a test copy contains 0 old values. Remaining hand-written copy:

- **RankStyly** `project/RankStyly.dc.html:1631` jewel `cr: 'kontrast 4,6–6,6 : 1'` → `'kontrast 4,6–7,1 : 1'`.
- **RankStyly** `:1632` note `'Tmavé drahokamy 12–16: bílý text a jasná hrana 1,5 px (≥ 3,9 : 1).'` → `'Modrý Mistr silnic (12) nese bílý text a jasnou hranu 1,5 px; ostatní drahokamy tmavé písmo (≥ 4,6 : 1).'`
- **RankStyly** `:1634` VIP note "…tlačítko je perleťové." → "…tlačítko je slonovinové s karmínovým písmem a červeno-zlatým rámem."
- **`DESIGN_V2.md`:**
  - line 99: VIP label "ruby `#881337`" → "crimson `#7F1D1D`, ivory foil, red–gold frame".
  - line 102: "VIP 17 (rose `#F43F5E`…)" → "VIP 17 = its own red `#EF4444`".
  - lines 137–141 (contrast table rows 12–17, 19): replace with the current `gen/contrast.md`.
  - add the 13–16 recolour to the tier table.

## 5. SQL draft (c)

`appdesign/sql/20261015_loyalty_colors_no_purple.sql` is in the scratchpad, **not in the repo**:

- Four guarded `UPDATE public.loyalty_levels SET color_hex = '<new>' WHERE level = N AND upper(color_hex) = '<old>'`.
- A `DO` block that prints a NOTICE if a level ended up with something else (a manual Velín change); it does not fail the deploy.
- A verification query and a rollback, both commented.
- No BEGIN/COMMIT, because `deploy-sql.yml` runs files with `--single-transaction`.

Test on a throwaway local PostgreSQL 16 with a `loyalty_levels` copy, run twice:

- run 1 recoloured 13/14/15, including the lower-case `#8b5cf6` case, and **left a manually changed 16 untouched**, with a NOTICE;
- run 2 changed nothing (idempotent);
- both runs exited 0.

Only the colour changes: discounts, thresholds, names, translations and points stay the same. `get_loyalty_status`, `admin_loyalty_status`, the leaderboard RPC and the app's `loyaltyLevelsProvider` read the table, so the app recolours on its next fetch.

**After approval (CLAUDE.md rule 4):** commit to `supabase/migrations/` and add a STATE_6 changelog row. In STATE_2, under "loyalty_levels: color_hex", add a note that 13–16 were recoloured on 2026-10-15. The STATE_1 row does not list hex values.

## 6. Repo places with hard-coded rank colours (d)

| # | File:line | What | Change needed |
|---|---|---|---|
| 1 | `Motogo-app-main/motogo-app-flutter/lib/features/loyalty/loyalty_levels_provider.dart:58-61` | `_fallbackLevels` colorHex 13–16 (offline / RPC-fail fallback) | → `#FF5A0C`, `#8A9A3B`, `#B39E7E`, `#19A2B4` |
| 2 | `Motogo-app-main/motogo-app-flutter-ios/lib/features/loyalty/loyalty_levels_provider.dart:58-61` | same, iOS tree | same, in the **same commit** (two-tree rule) |
| 3 | `…/motogo-app-flutter{,-ios}/lib/features/loyalty/loyalty_ranks_screen.dart:576-577` | `_onColor`: `computeLuminance() > 0.5 ? ink : white`. Used for the level number on the rank disc (529) and the "Ty" chip (570) | **Required with the SQL.** Pick whichever of ink `#0F1A14` / white gives the higher WCAG contrast (equivalent to a luminance threshold of about 0.20 instead of 0.5). Otherwise white on the new 13–16 colours is 2.6–3.1:1. This also fixes today's failures on 1, 4, 5, 6, 11, 12, 17, 18 |
| 4 | `…/loyalty_leaderboard_section.dart:342` (both trees) | same rule inline (avatar initial on the rank colour) | same threshold fix |
| 5 | `…/loyalty_levelup_overlay.dart:718-719` (both trees) | `_onColor` for the "Pokračovat" text (617) and the "+N" badge (659) | Same threshold fix. **Needs explicit owner OK** ("lvl up video neměň"). It changes only these two text colours, not the montage or the timing. Without it, white on orange is 3.1:1 |
| 6 | `…/loyalty_levelup_overlay.dart:83, 120, 198` (both trees) | prefs `mg_loyalty_last_color_<uid>` stores the **old hex**. The next level-up starts its logo-colour switch FROM that value | Customers who are on 13–16 when the SQL lands see one last purple→new flash at their next level-up (one-off). Optional, owner-gated: map the legacy hexes `#6366F1`, `#8B5CF6`, `#A855F7`, `#D946EF` to the new ones (or the colour of the stored `_lvlKey` level) where `lastColorHex` is read. Otherwise accept it |
| 7 | `supabase/functions/migrations/20260611_loyalty_ranks.sql:26-28` | original seed (13–16 purples) | **No change.** It is a historical file, `ON CONFLICT (level) DO NOTHING`, and not in the deploy path (`supabase/migrations/` only) |
| 8 | `supabase/migrations/20260917_loyalty_points_rank_floor_leaderboard.sql:217` | `COALESCE(color_hex, '#9CA3AF')` | none (Startér grey) |
| 9 | `.claude/handoff/workflows/app-design-v2-rank.js:29,112` | old hexes inside a past workflow prompt | historical; no change needed |
| 10 | design: `appdesign/project/*.dc.html` (6 boards), `appdesign/DESIGN_V2.md:99,102,137-141`, `appdesign/V21_FEEDBACK.md:2` (only quotes the task) | embedded copies and documentation | see §4 (re-embed script and copy lines) |

Verified to have **no rank colours**:

- **Velín:** the rank chip `CustomerProfileTab.jsx` `LoyaltyChip` uses fixed green/red, and there is no `loyalty_levels` UI.
- **Web** (`motogo-web-php`): only text mentions of loyalty.
- **Kiosk** (`raspberry/motogo-box`): nothing.
- **Edge functions:** `ai-copilot` only reads the table.
- **E-mails:** `#7dd3fc` in `send-booking-email` is an info-box border, not a rank.

**Non-rank purple, owner FYI and optional** (not covered by the request, which is about rank colours):

- Velín uses `#8b5cf6` / `#7c3aed` / `#6366f1` as UI accents: messages, e-shop invoices, routes POI, `StatusBadge` pending_service, Logistika, Branches.
- The app has `#7C3AED` in `features/routes/routes_map_picker.dart:22` (route colour "fialová") and `features/reservations/widgets/res_modification_history.dart:204,264`, in both trees.

## 7. Files

- Changed:
  - `appdesign/research/rankTheme.js` (SEED, `offHue` / `spinSafe`, jewel label, VIP 17/19, red lightening, arc)
  - `appdesign/gen/rank-head.css` (jewel ambient, header note)
  - `appdesign/gen/gen.js` (VIP red ring highlight in gold)
  - `appdesign/gen/rank-theme.tpl.js` (header note)
  - regenerated: `appdesign/shared/rank-theme.css`, `appdesign/shared/rank-theme.js`, `appdesign/gen/contrast.md`
- New:
  - `appdesign/sql/20261015_loyalty_colors_no_purple.sql`
  - `appdesign/gen/reembed_rank.py`
  - `appdesign/bak-rankcolors/` (pre-change copies)
  - `research/rank_colors_*.png`
  - working scripts in `research/rc_tmp/`: `color.js` (CIEDE2000 + WCAG), `search.js`, `joint.js`, `refine.js`, `eval.js`, `table.js`, `preview.js`

## 8. Short text for the owner (Czech, for chat)

> Ranky 13–16 už nejsou fialové ani růžové: **Šampion = závodní oranžová `#FF5A0C`**, **Veterán MotoGo = olivová `#8A9A3B`**, **Elitní jezdec = coyote khaki `#B39E7E`**, **Ambasador = petrolejová `#19A2B4`**. Každá je od všech ostatních ranků jasně odlišná (barevný rozdíl ΔE ≥ 14,5, dřív se fialové lišily jen o 5–8) a na tmavé hlavičce appky jsou čitelné i jako text (dřív fialové neprošly). Z efektů zmizela i růžová u VIP (tlačítko je teď slonovinové s karmínovým písmem a červeno-zlatým rámem) a u VIP Platinum. Změna v databázi je jen přebarvení těchto 4 řádků, SQL je připravené ke schválení.
