# MotoGo24 app · design iteration 2.2 (DESIGN_V22)

Spec for the v2.2 boards and for the Flutter port (Android first, see §8). It **extends** `DESIGN_V21.md`, which extends `DESIGN_V2.md`, which extends `appdesign_spec.md` (v1). Everything there stays valid unless a section below says **replaces** or **withdrawn**.

- Mockup "today" = **neděle 11. 10. 2026, 9:41**, Czech UI, tykání.
- Sample customer (unchanged): rank **3 Motorkář** (`#4ADE80`, unchanged by the new ramp), 5 points, licence A. R1 = Husqvarna 701 SM, Velké Němčice, pá 16. 10. 12:00 → ne 18. 10. 23:59, **12 027 Kč**. R2 = BMW R 1200 GS Adventure, Mezná, pá 23.–ne 25. 10., **10 189 Kč**. Default Home state = S0 funnel (no booking).
- Brand unchanged: neon `#74FB71`, gradient `#8DFF86 → #37CF63`, darks `#0A1F14 / #0E2A1C / #1A2E22`, Montserrat.

Inputs read for this spec (all facts traced to them):
- `DESIGN_V21.md`, `DESIGN_V2.md`, `appdesign_spec.md` §0–2, §6, `V21_FEEDBACK.md`, `.claude/handoff/PLAN.md`.
- Research 2026-10-16: `research/rank_ramp.md` (+ `sql/20261016_loyalty_colors_ramp.sql`, regenerated `shared/rank-theme.*`), `research/states_inventory.md` (≈ 150 states, IDs B-, C-, D-, E-, F-, G-, H-, J-, L-, M-, N-, O-, P-, Q-, R-, S-), `research/surface_balance.md`.
- All 12 boards in `appdesign/project/` (props, markup outline, CSS greps with `scratchpad/v22/outline.py`): Main, MotoKatalog, MotoDetail, Booking, Reservation, Kalkulacka, Profil, TrasyHub, Zazitky, TrasaDetail, SOS, RankStyly.
- App code, read-only: `features/payment/widgets/card_payment_sheet.dart` (both trees), `core/i18n/translations_*` (register of existing strings in 8 languages).

---

## 0. v2.2 at a glance

### 0.1 Owner feedback 2026-10-16 → where it is answered

| Owner (verbatim gist) | Answer |
|---|---|
| R1 "aby ten člověk měl pocit, že roste … zelené, modré uprostřed, kovy … aby se žádné barvy ranků nepodobaly … 13. stejný jako 20." | §1: one growing 20-level ramp (greens → metals → deepening blues → VIP crimson / gold / pearl → fiery Legenda), ΔE00 ≥ 12.38 for every pair, ≥ 15.60 for neighbours, no pink or purple, prestige of effects rising strictly (flat → metallic → glow → animated foil → fire). Guarded SQL as text. |
| R2 "děkovacích stránek je strašně moc druhů … vždycky musí appka ukázat smysluplnou hlášku, co se pokazilo, proč to nejde, jak to opravit … nikde se to nesmí zaseknout" | §5: new **Stavy** board, ≈ 290 rows in 19 groups (≈ 270 drawn variants, the rest point to a shared one), one template (what · why · how to fix · working action · never hangs), 5 tones, tykání, 8-language rules, hang guards per await (§5.6). |
| "Opravujeme jenom vzhled, ale funkčnost je brutálně odladěná" | The look cannot fix a false message: §5.5–5.6 and §8 list the code requirements that each state needs (error-code mapping, timeouts, idempotent retries, the 15 Kč minimum, honest SOS location). |
| R3 "Nikde jsem tam nenašel zaznamenat moji jízdu, tlačítko." | §4: **ZAZNAMENAT JÍZDU** = primary action of the Trasy tab (record dock on all 3 segments) + first row of Home "Moje zážitky" + full-screen recorder with 18 states. |
| R4 "svítí zeleně jenom první a poslední den, ale měly by být zvýrazněny všechny dny … v jednotné barvě" | §3: one continuous solid `#74FB71` band for start, every day between and end, in every calendar of the app. |
| R5 "aby to nebylo příliš zelený a černý … až moc tmavý, anebo jednolitý … místama bílý pozadí … chybí tam trošku kontrast" | §2: white / canvas pages, one dark hero per phone window, light forms and lists, dark only for photos, live states and the money moment; meta text and input borders raised to AA. |
| R6 "aby tam vždycky bylo dobře viditelné tlačítko zpět a z každé obrazovky se dalo jít zpět" | §6: one back/close standard (44 px, three surface styles, fixed positions, per screen type, system back rules) + per-board audit. |
| "verze 2 nebo 3 asi OK, ale furt je tam ještě hodně co zlepšovat" | §7: concrete detail fixes per board. |
| Earlier points (V2 1–14, V21 2026-10-15) | Unchanged. Level-up celebration stays exactly as shipped ("pozor lvl up video neměň"). |

### 0.2 What v2.2 replaces

| Earlier spec | v2.2 |
|---|---|
| V21 §0.3 recolour of 13–16 (orange `#FF5A0C`, olive, coyote, petrol) + `sql/20261015_loyalty_colors_no_purple.sql` | **Withdrawn.** §1 ramp for all 20 levels + `sql/20261016_loyalty_colors_ramp.sql`. |
| V21 §0.2 tier labels (VIP 17 ivory with `#7F1D1D`; gem labels navy 10–11/16, dark 13–15, white 12) | §1.3: gem CTA label by contrast → navy `#0A1F33` on 10–14, white on 15–16; VIP 17 ivory CTA with crimson label `#7F1D1D`, rank text on dark in champagne `#F3D27E`. |
| v1 §2.1 `page #DFF0EC`, `pageWash`; meta `#6C8A7B`, tertiary `#7C958A`; input border `#CFE3DA` | §2: `canvas #F4F7F5`, white cards, `well #F2F5F3`, meta `#55705F`, input border 1.5 px `#7C958A`. `#DFF0EC` survives only on legacy screens. |
| v1 rule 0.5 "one dark hero per screen" | R5.2: one dark block per phone window (746 px) besides chrome. |
| V2 §6.1 Detail sheet on mint with a dark ~1 000 px "Tvoje jízda" card | §2.5: white sheet, light step rows, dark total box only (owner decision §9 #3). |
| V21 §3.2 Kalkulačka as one dark `.kc-card` | §2.5: light step cards, dark "Tvoje cena" + CTA block (owner decision §9 #2). |
| V21 §2.4 Moje hero card `gDark` | White summary card; the dark "Tvoje stopy" map stays the segment's one dark hero. |
| V21 §2.2 "+" menu as the only "Zaznamenat vlastní jízdu" entry | §4 record dock (the "+" menu keeps the entry as a secondary path). |
| v1 `calRange` `#74FB71`@25 %, in-range `.24`/`.28`, gradient start/end | §3 uniform band. |
| V21 §7.0 "Offline = the app's global `OfflineGuard`" and every board's full-screen "Bez připojení" overlay | **Withdrawn.** §5 group 8: offline banner + "Co funguje bez signálu" sheet; SOS, calls, codes, navigation and the recorder are never covered. |
| V2 §2.5 `--rk-accl` rank-coloured text on light (club card name, next-rank line) | R5.7: on light surfaces rank text is ink; the rank shows as ring, dot, emblem and progress only (VIP 17 crimson text on white would read as an error). |
| V21 §6.8 L2, §10 #13 (on-colour of "Pokračovat") | Restated with the new ramp numbers as decision D1 (§1.7). |
| V21 §10 #16 (VIP glow = SOS red) | Answered: VIP 17 is now crimson `#D42020`, not the SOS `#EF4444`. |

### 0.3 Build order for the boards

0. **Re-embed the ramp** into all 12 boards (they still embed the v2.1 copy: `#FF5A0C` ×19 per board):
   `cd appdesign && python3 gen/reembed_rank.py --old bak-rankramp --write project/*.dc.html`, then the RankStyly copy edits of §1.6.
1. Add the §2.1 surface tokens as CSS custom properties at the top of every board's own CSS (`--canvas --surface --well --line --line-in --meta --tint-ok --tint-feat --dock --ink`); replace `--page`, `--ter`, `--tert`, `--meta` values as §2.2 says.
2. Build the shared calendar (§3) and the back control (§6) once, paste into every board that uses them.
3. Record dock + recorder (§4) into TrasyHub, Zazitky, Main.
4. New board **Stavy.dc.html** (§5.7).
5. Per-board detail fixes (§7).
6. Validation (§10).

Proposed shared snippets for the builders (same pattern as `shared/cta.html`): `shared/surface.css` (§2 tokens + `btnInk`, `btnGhostLight`, `btnText`, `iconTileDark/Light`, `eyebrowDark`, `well`, `dock`), `shared/back.html` (§6), `shared/calendar.css` + `calendar.js` (`calVals({…})`, §3), `shared/states.js` (the §5.4 catalogue as data, used by Stavy and by the in-context state props of other boards), `shared/record-dock.html` + `record.js` (§4).

---

## 1. Rank colours: one growing ramp (R1)

Source: `research/rank_ramp.md` (numbers, method, rejected variants). Generated: `shared/rank-theme.css`, `shared/rank-theme.js` (`rankTheme(1..20)`, 8 languages), `gen/contrast.md`. Backups of the v2.1 shared files: `bak-rankramp/`.

### 1.1 The 20 colours (`loyalty_levels.color_hex`, old → new)

| L | Rank | Old | **New** | Colour | Tier · effect | Text on the colour |
|---|---|---|---|---|---|---|
| 1 | Startér | `#9CA3AF` | **`#A3B8A8`** | šalvějová | Silnice · flat | ink `#0F1A14` 8.47 |
| 2 | Jezdec | `#86EFAC` | **`#BDF6D1`** | mátová | Silnice · flat | ink 14.66 |
| 3 | Motorkář | `#4ADE80` | **`#4ADE80`** | svěží zelená (beze změny) | Silnice · flat | ink 10.23 |
| 4 | Stálý jezdec | `#22C55E` | **`#00AC7F`** | smaragdová | Silnice · flat | ink 6.12 |
| 5 | Věrný zákazník | `#14B8A6` | **`#0AA2A4`** | nefritová tyrkys | Silnice · flat | ink 5.70 |
| 6 | Bronzový jezdec | `#CD7F32` | **`#C2844A`** | bronz | Kovy · metallic sheen | ink 5.68 |
| 7 | Stříbrný jezdec | `#C0C0C0` | **`#929496`** | stříbro | Kovy · metallic sheen | ink 5.86 |
| 8 | Zlatý jezdec | `#FFD700` | **`#E5D376`** | světlé žluté zlato | Kovy · metallic sheen | ink 11.81 |
| 9 | Platinový jezdec | `#E5E4E2` | **`#B9BEC6`** | studená platina | Kovy · metallic sheen | ink 9.54 |
| 10 | Diamantový jezdec | `#7DD3FC` | **`#AEE9FF`** | led / diamant | Drahokamy · glow + glints | ink 13.49 |
| 11 | Prémiový zákazník | `#38BDF8` | **`#2CD1D4`** | akvamarín | Drahokamy · glow + glints | ink 9.49 |
| 12 | Mistr silnic | `#3B82F6` | **`#6EAFFF`** | azurová | Drahokamy · glow + glints | ink 7.84 |
| 13 | Šampion | `#6366F1` | **`#00A1C7`** | blankytná | Drahokamy · glow + glints | ink 5.88 |
| 14 | Veterán MotoGo | `#8B5CF6` | **`#5087D4`** | kobaltová | Drahokamy · glow + glints | ink 4.89 |
| 15 | Elitní jezdec | `#A855F7` | **`#117897`** | hlubinná petrolejová | Drahokamy · glow + glints | white 5.05 |
| 16 | Ambasador | `#D946EF` | **`#165EEB`** | královský safír | Drahokamy · glow + glints | white 5.48 |
| 17 | VIP | `#EF4444` | **`#D42020`** | závodní karmín (≠ SOS `#EF4444`) | VIP · animated foil + crown | white 5.21 |
| 18 | VIP Gold | `#D4AF37` | **`#EDB42D`** | sytě zlatá 24 k | VIP · animated foil + crown | ink 9.48 |
| 19 | VIP Platinum | `#F1F5F9` | **`#F5F8FB`** | platinová perla | VIP · animated foil + crown | ink 16.72 |
| 20 | Legenda MotoGo | `#FFD700` | **`#FF8C1A`** | ohnivé zlato (app keeps `#FFD700 → #FF6B00`) | Legenda · fire + laurel | gradient, `#241A06` |

Names stay. The metals follow their names (Bronzový < Stříbrný < Zlatý < Platinový); Zlatý is a pale brushed gold, deliberately softer than VIP Gold and without orange; only Legenda is orange-fiery.

### 1.2 Checks (all measured, `research/rank_ramp.md` §5)

- **Distinct:** CIEDE2000 ≥ **12.38** for every pair (closest 6 ↔ 20, muted caramel metal vs animated fire), ≥ **15.60** for neighbours (2 ↔ 3). Today: 0.0 (8 = 20 = `#FFD700`) and 13 pairs under 12. **13 ↔ 20 = 50.7.**
- **No pink / purple / violet / magenta:** no HSL hue in 232–345°; a hue scan of all 311 colours in the generated CSS (incl. effects) finds none; reds are never lightened into salmon.
- **Prestige rises strictly:** (1) tier effect, (2) colour family green < metal < gem blue < VIP < fire, (3) inside a tier depth/richness + step marks (lane dashes 1–5, rivets 1–4, facets 1–7, crowns 1–3) + glow +0–12 px. Inside Drahokamy L\* falls strictly 89 → 45 and P = (100 − L\*) + C\*/2 rises strictly; 15–16 switch to deep CTAs with a white label.
- **Contrast:** text on the rank colour ≥ 4.89 (picked by contrast); logo ring on the dark header ≥ 3.28; all redesign tokens (`--rk-acc`, `--rk-acc-g`, `--rk-chip-tx`, `--rk-on`, arc) pass with 0 failures.

### 1.3 Effect tiers (app-side, by level number; the DB stores one colour)

| Tier | Levels | Ring | Primary CTA | Loop fx (same slot, never an extra loop) | Glow α / blur / halo | One-shot ambient | Step marks |
|---|---|---|---|---|---|---|---|
| T0 Silnice | 1–5 | solid 3 px | brand neon tints the first third, then the rank colour (65 → 90 → 100 %, shared fixer r2: fill ΔE neighbours ≥ 12,4), label `#08230F` | brand shine, extra streaks at steps 3 and 5 | .50 / 22 / — | headlight sweep, strength by step | lane dashes 1–5 |
| T1 Kovy | 6–9 | conic metal 3 px | brushed 4-stop metal, 1 px edge, label `#1A1405` / `#0B1512` | metal sheen 4.8 s | .55 / 26 / .12 | sheen once | rivets 1–4 |
| T2 Drahokamy | 10–16 | 12-facet conic 3.5 px | prismatic (luminance-matched partner stop), 1.5 px edge; label navy `#0A1F33` 10–14, white 15–16 | glints 3.6 s | .58 / 28 / .16 (deep colours glow in a lifted tone) | prism once | facets 1–7 |
| T3 VIP | 17–19 | double ring (colour + gold / cream) + crown notch | foil + crown glyph; 17 ivory `#FFFBF2 → #F3DEC0` with crimson label `#7F1D1D` | light orbiting the frame 4 s | .62 / 30 / .20 | aurora once | crowns 1–3 |
| T4 Legenda | 20 | legend conic + laurel 4 px | molten `#FFE27A → #FFD700 → #FF9A1F → #FF6B00`, label `#241A06` | embers 4.4 s | .66 / 34 / .24 | aurora + embers once | — |

Reduced motion: every loop and one-shot off, end states shown; colours, materials and marks still carry the rank.

### 1.4 Rank on surfaces (merges R1 with R5)

- **Dark carriers only** for the rank material: CTA fill + glow + loop fx, rank aura of header heroes, nav active pill, PROFIL avatar ring + arc, AI-FAB ring, success hero aura (Stavy T1).
- **On light surfaces** the rank appears only as: the logo ring / avatar ring (they carry their own dark disc), the emblem disc, the progress bar on a `well` track (`--rk-uil` fill, ≥ 3:1), and the rank chip drawn as a **dark pill with a rank-colour dot**. Rank **text** on light is ink `#1A2E22` (the name) — never `--rk-accl`, so VIP 17 crimson never looks like an error and silver / platinum / pearl never vanish on white.
- A rank CTA that must sit inside a light area goes into a **dark dock** (≥ 8 px night padding, r16).
- **Never** rank-coloured: prices, ✓ / ⚠ / ✕ meaning colours, SOS, focus rings, links, Apple / Google Pay buttons, status icons of the Stavy board.

### 1.5 How each board uses the ramp

| Board | Rank surfaces | On light (§1.4) | Check with `rank` = |
|---|---|---|---|
| Main (Domů) | Header aura + texture + minted edge + one-shot ambient; LogoRow ring + arc + level badge (+ crown / laurel); motto line marks; funnel: ring on the centred bike + **REZERVOVAT · 11 893 Kč**; ticket CTA S1–S9; nav pill + PROFIL avatar; AI ring | Tvůj klub: emblem, tier bar on `well`, name in ink, tier rail swatches as dark mini discs; rank chip = dark pill + dot | 1, 6, 10, 15, 17, 19, 20 |
| MotoKatalog | Header chip + aura; first-in-view card CTA (on the photo scrim); nav | — (photo-led) | 7, 9, 19 over bright photos (CTA edge visible) |
| MotoDetail | Sticky dock CTA **REZERVOVAT · 10 189 Kč**; rank-savings chip inside the dark total box | step rows neutral | 15, 16 (white label), 17 (ivory) |
| Booking | Header aura; **ZAPLATIT · 10 189 Kč** in the dark dock | "zdarma s rankem" is a `tintOk` meaning chip, not rank | 1, 17, 20 |
| Reservation | Header / photo-hero chip; CO TEĎ CTA (dark hero); review card "ZNOVU REZERVOVAT"; nav | loyalty row in the receipt: ink text + rank dot | 3, 17 |
| Kalkulačka | Header chip; CTA inside the dark "Tvoje cena" block; sticky dock CTA | rank chip in the light head = dark pill + dot | 7, 15, 19 |
| Profil | Header aura, avatar frame + arc + badge, rank strip; docs CTA inside the header; P4 ladder: every row is a wrapper `rk rk-N t-tier` with its own colour, grouped by the 5 tiers | tiles and lists neutral | every level in P4 |
| TrasyHub | Header aura; segment thumb outer glow (30 %); record dock CTA **ZAZNAMENAT JÍZDU** | list neutral | 1, 10, 17 |
| Zazitky | Header aura; record dock CTA | summary card: rank row = dark mini disc with ring + ink name | 6, 16 |
| TrasaDetail | Dock **ZVOLIT TRASU – NAVIGOVAT**; builder **NAVIGOVAT** | none; navigation screens have no rank | 3, 15 |
| SOS | LogoRow ring in the compact header only | none (the red system never takes rank) | 17 (crimson ring next to SOS red must not merge: crimson ring is `#D42020` 3 px with gold outline, SOS fills `#D92D20` — keep ≥ 16 px apart) |
| RankStyly | Everything, per wrapper scope | demos on dark docks | all 20 |
| Stavy (new) | Success and pending hero aura + their primary CTA | never on warn / error / offline | 1, 15, 17, 19, 20 |
| Level-up storyboard (RankStyly section 2) | **Unchanged replica** of `loyalty_levelup_overlay.dart`: ring morph old → new, name in the raw colour, "Pokračovat" filled with the raw colour, today's `_onColor` (luminance > .5) | — | see D1 below |

### 1.6 Board edits after the re-embed

- `RankStyly.dc.html:583` `.trk i` gradient start `#9CA3AF` → `#A3B8A8`.
- `RankStyly.dc.html:2111–2119` `TX`: road `cr` "kontrast 6,6–10,6 : 1"; metal `cr` "kontrast 4,8–9,8 : 1"; jewel `cr` "kontrast 4,6–11,5 : 1"; jewel `note` "Světlé drahokamy 10–14 (led → kobalt) nesou tmavé písmo, hluboké 15–16 (petrolej, safír) bílé; vše ≥ 4,6 : 1."; vip `note` "VIP = závodní karmín #D42020 (ne SOS červená): karmínový prstenec a záře, tlačítko slonovinové s karmínovým písmem a červeno-zlatým rámem, text ranku šampaňský."; legend `note` "Legenda má jako jediná ohnivé zlato (#FF8C1A, v appce přechod #FFD700→#FF6B00) — Zlatý jezdec je světlé žluté zlato #E5D376, VIP Gold sytě zlatá #EDB42D."
- `RankStyly.dc.html:2187` `RC` → the full 19-row list of `research/rank_ramp.md` §7 (`[L, old, new, název, text na štítku #1A2E22]`).
- RankStyly tier overview: section note "Nové barvy 13–16" → "Nová škála 1–20: roste od zelené přes kovy a modré drahokamy k VIP a ohnivé Legendě". Add one strip of the 20 swatches in order with tier brackets and the caption "Každé dva ranky se liší (ΔE ≥ 12,4), sousední ještě víc (≥ 15,6)".
- **After the swap, grep every board:** `#FF5A0C`, `#8A9A3B`, `#B39E7E`, `#F43F5E`, `#6366F1`, `#8B5CF6`, `#A855F7`, `#D946EF` must be 0 (rank use). `#EF4444` remains only for SOS dots/icons, `#D4AF37` only for the crown, `#FFD700` only inside the Legenda gradient, `#19A2B4` only for the non-rank modification history in Reservation.

### 1.7 App code, SQL and release order

- **App (both trees, same commit; `research/rank_ramp.md` §6):** A1 `loyalty_ranks_screen.dart:576–577` and A2 `loyalty_leaderboard_section.dart:342` pick ink / white by contrast (`onRankColor`); B1 `loyalty_rank_card.dart:274`, B2 `loyalty_ranks_screen.dart:348/544`, B3 `profile_screen.dart:478` lift rank text on dark (`rankTextOnDark`, crimson → champagne `#F3D27E`); C new fallback colours in `loyalty_levels_provider.dart:46–65`.
- **Protected level-up overlay — needs the owner's explicit OK ("lvl up video neměň"):**
  - **D1** `loyalty_levelup_overlay.dart:718–719` `_onColor` luminance > .5 → pick by contrast. Only the text colour of "Pokračovat" and "+N" changes. With today's rule the new colours give white text at 2.1–3.7:1 on levels 1, 4, 5, 6, 7, 12, 13, 14; with D1 "Pokračovat" is ≥ 4.89 on all 19 non-Legend levels. (Today's colours already fail on 12 levels.)
  - **D2** "+N" badge with D1: ≥ 3.45 everywhere (17 px w900); a full 4.5 would need a different badge gradient → not proposed.
  - **D3** optional: map the stored `mg_loyalty_last_color_<uid>` old hex to the new colour of that level, so the first celebration after the switch does not morph from an old violet.
  - The RankStyly storyboard keeps today's rule (faithful). It gets a board prop `opravaD1` (boolean, default **false**, section "Povýšení · návrh") that shows the same frame with D1 applied, so the owner can compare.
- **SQL:** `appdesign/sql/20261016_loyalty_colors_ramp.sql` — 19 guarded `UPDATE … WHERE level = N AND upper(color_hex) = <live>` (13–16 also accept the unapplied v2.1 draft values), NOTICE on manual edits and duplicates, no BEGIN/COMMIT, verification + rollback commented. Tested on PostgreSQL 16 (run 1: 19 updates; run 2: 0; manual edits left alone; rollback exact). Given to the owner **as text** (CLAUDE.md rule 3); after approval commit to `supabase/migrations/`, add STATE_6 changelog + STATE_2 note under `loyalty_levels.color_hex`.
- **Release order:** the SQL goes live only after **both** app trees with A1–C are in the stores. If the next release is Android only (§8), the iOS app would keep today's `_onColor`, and after the SQL its customers on levels 1, 4, 5, 6, 7, 12, 13, 14 would get white-on-light text and rank names 14–17 at 2.6–3.9:1. So: Android release → iOS release with the same A1–C → SQL.

---
## 2. Surface system: white sections, dark heroes (R5)

Source: `research/surface_balance.md` (measured at 390 px; web v2 reference: white 34–63 % of each page, dark 8–35 %, neon 1–5.5 %). Diagnosis of the boards: 10 of 12 paint the page mint `#DFF0EC`; Main's first screen is 0.7 % white with three dark blocks stacked (header 0–247, banner strip 259–291, funnel 303–895); Kalkulačka is one dark section from y 197 to 2588 with glass nested three deep; Moje zážitky stacks dark header + dark summary; meta text `#6C8A7B` / `#7C958A` fails AA (3.2–3.8 : 1) in ≈ 85 places; input borders ≈ 1.3 : 1.

### 2.1 Tokens (`MotoGoV2`, dark tokens unchanged)

| Token | Value | Role | Replaces |
|---|---|---|---|
| `canvas` | **`#F4F7F5`** | page of every light screen (tab roots, lists, forms, sheets under photo heroes) | `page #DFF0EC`, `pageWash` |
| `surface` | `#FFFFFF` | cards, grouped lists, light sheets, dialogs, receipts | — |
| `band` | `#FFFFFF` full bleed, no radius, 24 px vertical padding | one dense section per long screen turned into a white band | — |
| `well` | `#F2F5F3` + 1 px `line` | tiles, stat tiles, segmented tracks, neutral chips, inputs **inside white cards** | `tile`, `pill #EEF7F2`, `input #FBFDFC` |
| `line` | `#E2EAE5` | card borders, dividers (decorative) | `#E1EFE9`, `#E3EFE9`, `#D4E8E0`, `#E6F2ED` |
| `lineInput` | 1.5 px `#7C958A` (3.22 : 1) | text inputs, selects, date fields; focus 2 px `#0D6E0D` + 4 px neon@.28 ring | `#CFE3DA` |
| `tintOk` | `#E8FCE8` + 1 px `#37CF63` | checked / positive state only ("Zaplaceno", "zdarma s rankem", "½ 1. den za polovinu") | — |
| `tintFeature` | 160° `#EAFBF0 → #D9F5E4`, or the offer box `#E6FAE2 → #F6FFF4` + 1 px dashed `#37CF63` | **at most one per screen** (web `.lp-offer-in`, `.lp-rt-box`) | ad-hoc mint areas |
| `night` / `panel` / `glow` / `gDark` / `gDarkCta` | `#0A1F14` / `#0E2A1C` / `#24563B` / v1 §2.2 | header bands, hero cards, dark sheets, total box | — |
| `dock` | `night`@.96 + blur 14 + `shSticky` | every bottom action bar (REZERVOVAT, ZAPLATIT, NAVIGOVAT, ZAZNAMENAT JÍZDU) | — |
| `scrim` | `night`@.55 (text over photos) … @.8 (badges, back disc) | controls over photos | — |
| `iconTileDark` | 40 px (rows 36) r12 `#0E2A1C`, neon icon (11.55 : 1) | section-leading features on light (web `.lp-rt-ico`) | mint tile + green icon |
| `iconTileLight` | 36 px r10 `well`, `#0D6E0D` icon (6.45 : 1) | list-row icons on light | `#EEF7F2` tile |
| `eyebrowDark` | pill `#0E2A1C`, neon 11.5/800 caps | section eyebrows on light (web `.lp-rt-eyebrow`) | green caps text |
| `btnInk` | `#1A2E22` + white or neon label, 48–52, r14 | primary / secondary actions **on light** (web `.lp-moto-book`) | neon fill on light |
| `btnGhostLight` | white, 1.5 px `#0D6E0D`, label `#0D6E0D` | secondary on light | — |
| `btnText` | `#0D6E0D` text, ≥ 44 px tall hit area | tertiary on light | — |

### 2.2 Text colours per surface

| Role | On `surface` `#FFF` | On `canvas` | On `well` | On dark `#0E2A1C` |
|---|---|---|---|---|
| Title / primary | `#1A2E22` 14.41 | 13.36 | — | `#FFFFFF` 15.37 |
| Body | `#1A2E22` / `#2C4A3A` 9.78 | ✓ | ✓ | `#E8F5EE` 13.70 |
| Lead / secondary | `#4A6B5A` 5.93 | 5.50 | 5.40 | `#CFE7DA` 11.78 / `#B8D4C6` 9.71 |
| **Meta / tertiary (min 11/700)** | **`#55705F` 5.43** | **5.03** | **4.94** | `#9FC4B1` 8.05; floor `#8FB3A1` 6.68 |
| Link, price, ✓ text | `#0D6E0D` 6.45 | 5.98 | ✓ | neon `#74FB71` 11.55 |
| Text on `tintOk` | `#0D4F1C` 9.07 / `#0D6E0D` 6.00 | | | — |
| Warning | `#8A4B00` 6.80 (on `#FFF4E0` 6.24) | | | `#FFD36B` 10.82 |
| Error / destructive | `#B42318` 6.57 (on `#FDECEC` 5.9) | | | `#FFB3B3` |
| Disabled (exempt) | `#9DB3A8` 2.22 | | | white@.36 |
| On neon fill | `#08230F` 12.55; price `#0B3B1A` 9.54 | | | same |
| On `btnInk` | white 14.41 / neon 10.82 | | | — |

**Banned on light:** `#6C8A7B`, `#7C958A`, `#8AA096`, `#8FB3A1` as text; neon as text, edge or lone fill. **Board CSS variables:** Profil `--meta:#6C8A7B` (×20 uses), RankStyly / Reservation / SOS / TrasaDetail / TrasyHub / Zazitky `--ter:#6C8A7B` (6 / 6 / 5 / 10 / 14 / 21 uses), Booking / TrasaDetail / TrasyHub / Zazitky `--meta:#7C958A`, Booking `--tert:#6C8A7B` → all `#55705F` where the text sits on light (keep them on dark only if the element is on a dark carrier — then use `#9FC4B1`).

### 2.3 Rules (add to V21 §7.0)

- **R5.1 Page colour.** Light screens use `canvas`; cards use `surface`. `#DFF0EC` survives only inside legacy (unported) screens.
- **R5.2 One dark block per window.** In any 746 px window (844 − nav 98) at most **one** dark block besides chrome (header band, dock, nav, toast). Dark blocks are separated by ≥ 1 light section of ≥ 160 px.
- **R5.3 Header + hero = one unit.** A dark hero under a dark header overlaps it by **−24 px** (web `.lp-panel` −2.25 rem); nothing sits between them; a CMS banner becomes the header's last line.
- **R5.4 Budgets** (measured with `sbal/comp.py`, nav and dock excluded): dark in the first viewport ≤ 45 % (photo pixels counted separately); white + canvas ≥ 55 % of the scroll; green tints ≤ 20 %; neon ≤ 5 %. **Exempt** (photo-led or immersive): MotoKatalog cards, MotoDetail hero, maps, navigation, recorder, scanner, codes full-screen, level-up, the P4 rank ladder (rank showcase), the SOS red system.
- **R5.5 Depth.** At most 2 levels of dark (dark hero → glass tile `white@.06`). Life inside a dark block comes from a photo, the rank aura (header only), one neon focal point (CTA or total) and white / neon chips — never from more dark cards.
- **R5.6 Light rhythm.** Long light screens alternate `canvas` sections with **one** full-bleed white `band`, use photo thumbnails, and introduce sections with `eyebrowDark` + `iconTileDark` so they never become a grey-green monotone.
- **R5.7 Rank on surfaces:** §1.4.
- **R5.8 Buttons on light:** `btnInk`, `btnGhostLight`, `btnText`. Exception: ✓ discs and small badges (neon fill + ink glyph).
- **R5.9 Accents.** Neon: CTA on dark, icons / eyebrows on dark, the calendar band, ✓ discs, live dot on dark. Mint: `tintOk` + one `tintFeature`. Red: SOS, errors, destructive, and the live **recording** dot. Amber: warnings, pending, "návrh / ukázka" tags.
- **R5.10 Sheets.** Light by default (filters, pickers, calendar, sizes, receipt, consents, edit, confirmations, all Stavy sheets). Dark only for live / immersive: codes full-screen, recorder, navigation overlays, AI chat, level-up.
- **R5.11 Back control:** §6.
- **R5.12 Chrome stays dark:** nav, AI FAB, docks, toasts, status strip.

### 2.4 Per-board section-by-section decisions

Legend: **D** dark, **L** light (canvas / white), **P** photo or map (exempt), **=** unchanged.

**Main (Domů)** — target: first viewport dark ≤ 45 % (plus photo), whole scroll dark ≈ 25 %, white + canvas ≈ 58 %, green ≈ 12 %.

| # | Section (board markup) | Now | v2.2 | Decision |
|---|---|---|---|---|
| 1 | Header `.rk-hero.hd` (status, LogoRow, bell, SOS pill, greeting, motto, concierge note, rank chip) | D 0–246 | **D, compact ≤ 190** | greeting + rank chip on one row; season line "Sezóna 2026 · [km] km · [n] jízd · [n] míst" moves to the Moje zážitky band; concierge note stays (max 2 lines) |
| 2 | Marquee `.mqw` "» V zimním období od 1.11.2026 do 25.3.2027 zavřeno." | D strip | **removed as a block** | becomes the header's last line (11.5/700 neon marquee, static under reduced motion) |
| 3 | Review card `.rvc` (S10) | L | L white on canvas | = wording; ✕ "Skrýt" 44 |
| 4 | Funnel `.fn` (S0, S10) / ticket `.tk` (S1–S9) | D 592 px | **D, overlaps header −24, photo-led** | carousel full card width 358 × 200 r16 (one-shot Ken Burns, "Volná v termínu" / "Pro tvůj ŘP A" badges on scrim); dark only behind eyebrow + title, date presets, rank CTA; card ends ≈ 600; CTA above the fold. Ticket keeps its 128 photo header |
| 5 | "½ od 12:00 jen 10 189 Kč", "Spočítat přesnou cenu ›", "Všechny motorky ›", season note | inside the dark funnel | **L block right under the hero** | `tintFeature` offer box "Vyzvedni od 12:00 · 1. den za polovinu" (the screen's one tint) → white card with 2 rows (`iconTileDark` calculator / motorcycle + title + chevron) → season note 12.5/600 `#55705F`. Nothing lost |
| 6 | "Kdy jedeš příště?" pill `.pw` (S1–S9) | L | L white pill, `lineInput` border | + 44 calculator button as `btnInk` disc |
| 7 | "MotoGo ti píše" `.msg` | L | L white row, `iconTileDark` envelope | = |
| 8 | Tvůj klub `.club` | L card on mint | L white card | emblem + tier bar on `well`; **name and next-rank line in ink** (§1.4); tier rail swatches = dark mini discs; ⓘ → light sheet |
| 9 | Moje zážitky `.sec` | L on mint | **L full-bleed white `band`** | header "Moje zážitky" + season line; **row 1 "Zaznamenat jízdu"** (§4.2 B); 2 × 2 tiles → `well` + `iconTileDark`; deník entries white rows with `line` dividers; the "Nahrát jízdu" mini action leaves the Soukromé jízdy tile |
| 10 | Vybrali jsme ti (routes) | P cards | P photo + white body on canvas | `eyebrowDark` "VYBRALI JSME TI" |
| 11 | Motorky pro tebe (S1–S9) | L | L white photo cards, price `#0D6E0D` | whole card is the target |
| 12 | Pobočky `.br-g` | 2 × D | **Mezná L, Velké Němčice D** | web `.pb-card` / `.pb-card--self`: Mezná photo top + white body + `btnInk` "Detail"; VN dark = the only dark block of the lower page |
| 13 | Tvoje linka `.ln` | L | L white | both buttons `btnGhostLight` (the screen's primary is the funnel CTA) |
| 14 | Strip, nav, AI FAB | D chrome | = | — |

**MotoKatalog** (photo-led, owner OK — exempt)

| Section | v2.2 |
|---|---|
| Sticky header (title + count, `.km` switch, date pill, filter chips) | D = ; winter notice `.ntc` becomes the header's last line |
| Full-screen cards | P = (owner loves it) |
| Grid view | L: canvas, white card bodies under the photos, price `#0D6E0D` |
| Filter sheet `.fsh` | L (already light) — chips `well`, selected `btnInk` |
| Empty / error / offline `.est`, `.off-g` | L white cards on canvas with Stavy templates (§5: 8.6, 8.1); no "Chyba: [technický popis chyby]" in the body |
| Calc mode `.kcs` | → Kalkulačka layout (L steps + D total) |

**MotoDetail**

| Section | Now | v2.2 |
|---|---|---|
| Hero photo 0–560 (status pill, tags, H1, branch meta, pager, fav, back) | P | P = ; glass controls night@.8 (§6) |
| Content sheet | mint `#DFF0EC` | **white** `#FFFFFF`, grabber `#CFE3DA` |
| 4 spec tiles, V kostce chips | mint tiles | `well` + `line`, units `#55705F` |
| "Tvoje jízda" (① termín, ② předání, ③ výbava, total) | D ~1 000 px | **L white card with step rows** (`well` rows, ✓ discs, "Změnit" `btnText`); **total box stays D** (`gDarkCta`: "TVOJE CENA · 3 dny", 32/900 neon, "Díky ranku Motorkář ušetříš 1 585 Kč" chip, "Rozpis ▾") — the one dark block below the photo. Fallback if the owner keeps web parity: dark card, but sheet and tiles still light |
| Popis, Víc o motorce rows | L | L white rows, `iconTileLight` |
| Date / time / address / info sheets | date D, others L | **all L** (calendar light skin §3) |
| Sticky dock | D | D = (REZERVOVAT · 10 189 Kč + docked mini AI) |

**Booking (Rezervace expres)** — already balanced (dark 25 %, white 44 %).

| Section | v2.2 |
|---|---|
| Header `.rk-hero.bh` (back, title, bike, steps, ⏱ chip) | D = compact |
| Page `.wash` | `canvas` |
| Recap "Termín a předání" `.tk`, "Máme to připravené" `.ms`, options, consent row, Stripe line | L white cards; gear / size chips `well`; ✓ discs neon + ink |
| Pay dock `.rk-sticky` | D = |
| Sheets (sizes, date, address, licence, wallet, info, receipt) | L; receipt light with the dark total box |
| Payment error sheet `.perr` | L, Stavy T2 (§5.2) |
| Success screen `.sx` | D hero (rank aura) + white card overlapping −24 (Stavy T1 "1.1") |

**Reservation (Správa rezervace)**

| Section | v2.2 |
|---|---|
| Photo hero `.rph` (status pill, rating, back) | P = |
| Title block "REZERVACE #[ID]", Tvoje cesta timeline | L on canvas; timeline nodes: done = neon disc + ink ✓, current = `#1A2E22` disc + neon ring, future = white disc + `line`; labels `#4A6B5A`, dates `#0D6E0D` |
| CO TEĎ `.heroCls` | **D — the one dark hero** (codes, review card in Dokončeno) |
| Action row | L chips `well` |
| Kdy a kde, Výbava, Peníze (+ Rozpis), Dokumenty, Projeté jízdy | L white cards; chips "Šatna · dveře č. 8" + sizes `well`; `tintOk` only for "Zaplaceno", "½ 1. den za polovinu", "zdarma s rankem"; navigation buttons `btnInk` discs |
| List view `ls` | D compact header; L cards; filter tabs on a `well` track |
| Edit view `ed` | D compact header; L body; calendar light skin with edit marks (§3.4); D dock |
| OK page `okp` | D hero + white card (Stavy T1) |
| Codes full-screen | D (exempt) |

**Kalkulačka** — target dark ≈ 22 % (header + total block + dock), white + canvas ≈ 66 %.

| Section | Now | v2.2 |
|---|---|---|
| Shared Motorky header + `.km` switch | D | D = (≤ 190) |
| `.kc-card` head (eyebrow, H2, lead, rank chip) | D | L on canvas: `eyebrowDark` "KALKULAČKA CENY", H2 ink, lead `#4A6B5A`, rank chip dark pill + dot |
| ① Pobočka segmented | D glass | L white step card; segments on a `well` track, selected `btnInk` (ink + neon text) |
| ② Motorka card + picker | D glass | L white card with photo; price `#0D6E0D`, list price struck `#55705F` |
| ③ Termín calendar | D | L light skin (§3) |
| ④ Předání a výbava | D | L rows with "Změnit" |
| Step badges | neon numbers | web `.rez-step-num`: 34 px dark disc, neon number, ✓ when done (the contrast accent of the light flow) |
| Receipt `.rc` | white | = white; bars `gBar` |
| Total + CTA `.rcf` | inside dark | **D block**: "Tvoje cena", 32/900 neon, average/day, rank-savings chip, rank CTA **REZERVOVAT · 10 189 Kč** |
| Assure, "Zrušit termín", free-list chips, FX note | D | L on canvas, `#4A6B5A` / `#0D6E0D` |
| Sticky `.kst` | D | D dock = (mirrors the total block when it is off-screen) |
| Picker / address / info sheets | mixed | L |

**Profil**

| Section | v2.2 |
|---|---|
| Header `.rk-hero.hh` (LogoRow / avatar frame, name, nickname chip, rank strip) | D = ; when documents are incomplete the rank CTA "NAHRÁT DOKLADY" becomes the header's last row (rank CTA stays on a dark carrier) |
| Attention strip | L white chips with tone icons (SOS red, amber docs, unread) |
| Můj účet tiles | L white + `iconTileLight`; red count badges as now; section label gutter 16 (render showed MŮJ ÚČET / NASTAVENÍ flush at x = 0) |
| Osobní údaje, Pomoc a podpora, Ostatní | L white grouped lists |
| Nastavení | L — the screen's one full-bleed white `band` (optional) |
| Odhlásit se / Smazat účet | `#B42318` on white |
| Sub-screens (Zprávy, vlákno, Doklady, Faktury, Smlouvy, Oprávnění, Pobočky, Pobočka) | D compact app bar + L content |
| Platební metody | default card D ("wallet" r16, brand mark, PRIORITNÍ) = the one dark block; other cards L white |
| Věrnostní ranky P4 | D page (exempt: rank showcase; each row needs a dark carrier); rules card L at the bottom |
| Skenování | D camera (exempt); result / help overlays L sheets |
| AI asistent | D chat (R5.10) |
| Sheets (edit, nickname, consents, password, language, currency) | L |

**TrasyHub (Místa · Trasy · Moje)**

| Section | v2.2 |
|---|---|
| Header (title + AnimatedRouteIcon, stats, map + "+" buttons, search, segments) | D = (collapsing) |
| Místa: location prompt, map preview card, category chips, place list | L: prompt white card; map preview P inside a white card; chips white + `line`, count in a `well` pill; list white cards |
| Trasy: stat line, toolbar, route cards | L: stat line on canvas; toolbar chips white; cards photo top + white body |
| Moje (→ Zazitky board) | — |
| Detail místa sheet | L (photo top P) |
| Mapa míst / Mapa tras | P; the neon round "Přidat místo" → white disc + `line` + `#0D6E0D` pin-plus (neon belongs to the record dock) |
| Live strip `.lvw` (recording) | replaced by the dock live bar on Trasy (§4); navigation "Pokračovat v trase" strip stays L glass |
| **Record dock** (new) | D dock = the tab's primary (§4.2 A) |

**Zazitky (Moje zážitky · deník)**

| Section | v2.2 |
|---|---|
| Header | D = |
| Moje summary `.mj` | **L white card**: 1 284 km 32/900 ink (ukázka); split bar S MotoGo `#37CF63` / Soukromé `#1A2E22` on a `well` track (≥ 6 px each); stat tiles `well` (7 jízd · 3 uložené trasy · 12 objevených míst, ukázka); compact rank row (dark mini disc with ring + ink "Motorkář · Level 3 / 20") |
| "VYTVOŘIT NOVOU TRASU" | `btnInk` (the record dock is the tab's primary) |
| Ghost "Zaznamenat vlastní jízdu" in the card | removed (dock replaces it) |
| "Tvoje stopy" map | D / P — the segment's one dark hero |
| Ride cards, saved routes, places, history | L white; tags "S MotoGo" dark pill + neon, "Soukromá" `well` pill, "Sdíleno" =, "ukázka" amber |
| Live recording card in the list | L white + 1.5 px red border + red "● Nahrávám" chip |
| Ride detail | D header + P map + D stats card overlapping −24 (one dark), rest L |
| "Záznam jízdy · panel" (sheet `sht.rec`) | → full-screen **Recorder** D (exempt, §4.4) |
| Share / stop / place sheets, submit form | L (form with D compact header) |

**TrasaDetail (trasa, navigace, plánovač, návrhy)**

| Section | v2.2 |
|---|---|
| Map hero + dark stats card overlapping | P + D (the one dark) |
| Sheet | canvas |
| Popis, Místa na trase, Galerie, Recenze | L (photo cards with white body) |
| "Půjč si motorku na tuhle trasu" | D card (web `lp-cta-card`), > 1 000 px below the hero (R5.2 OK) |
| Dock "ZVOLIT TRASU – NAVIGOVAT" | D |
| Navigace (all states) | D full-screen map (exempt, no decorative motion) |
| Plánovač | P map + L stats card + L nearby panel + L stop list + D dock |
| Výběr míst, Navrhnout trasu, Přidat místo | D compact header + L content + D dock |
| Photo viewer, map fullscreen | P/D (exempt) |
| Sheets (other app, review, save, suggest) | L |

**SOS**

| Section | v2.2 |
|---|---|
| Compact header | D = |
| Page | canvas |
| Emergency tiles | `#D92D20` + white (4.83) |
| Report / tow / accident sheets | L white |
| Nonstop-line dock | D |
| Hotovo screens | D success hero (neon ✓, **no rank aura** — SOS is never rank) + white cards |
| Offline layer | §5 group 14.20 (calls always reachable) |

**RankStyly**

| Section | v2.2 |
|---|---|
| Header `.rk-hero.ih` | D = |
| Price trial, mini phone, storyboard frames | P/D demos (exempt) |
| Light sections (V appce, Přehled, Pevné body, Pravidla) | canvas / white; `--ter` → `#55705F`; every rank CTA demo on a dark dock |
| Level-up storyboard | **unchanged** |

**Stavy (new, §5)** — success / pending: D hero (+ rank aura) then L body; warn / error / offline: L screen with a tone icon disc; sheets L; global offline banner D glass.

---

## 3. Calendar range: one uniform band (R4)

One component `TripCalendar` everywhere a range is picked: Main funnel date sheet, MotoDetail date sheet, Kalkulačka step ③, Booking "Otevřít celý kalendář s cenami dnů", Reservation edit (prodloužit / zkrátit / posunout). It replaces the inverted app semantics of `availability_calendar.dart` and `edit_reservation_calendar.dart` (free = neon, selected = dark) and the board classes `Main .dc.dr/.dc.ds`, `MotoDetail .cd.rg/.cd.sl`, `Kalkulacka .cd.in/.cd.en`, `Reservation .ed-d.keep/.ed-d.en/.ed-d.old`.

### 3.1 Skins

- **Light (default):** a light sheet or a white card; calendar box `surface` r18 + `line`. All date sheets become light (R5.10).
- **Dark:** only inside a dark sheet (fallback if the owner keeps the dark Detail card). Same states and geometry.

### 3.2 Geometry

- 7 columns, 4 px gap, cell 46 px high (≥ 44), r11; day number 15/800 tabular, day price 10/700 (the only allowed 10 px); weekday header 11.5/800 caps `#55705F`, weekend headers `#0D6E0D`; month title 17/800 with ‹ › 44 px discs.
- **The range is painted as one band per week row behind the cells** (`CustomPainter` under the row, not per-cell fills): the band spans the gaps; range start and end get r11 caps; where the range wraps, the row ends with r6 and the next row starts with r6. Start and end differ **only by the rounded cap** — the fill, number colour and weight are identical for every selected day.

```
Říjen 2026            ‹ ›          (dnes = ne 11.)
PO  ÚT  ST  ČT  PÁ  SO  NE
             1   2   3   4
 5   6   7   8   9  10 (11)•
12  13  14  15  16  17  18
19  20  21  22 ╭23══24══25╮        ← one band, uniform #74FB71, r11 caps
26  27  28  29  30  31             (range 23.–27.: row 1 ends r6, row 2 starts r6)
```

### 3.3 States (light skin)

| State | Fill | Number | Price | Interaction |
|---|---|---|---|---|
| Free weekday | `#FFFFFF` + 1 px `line` | `#1A2E22` | `#0D6E0D` 6.45 | tap |
| Free weekend | `#F3FBF7` + 1 px `line` | `#1A2E22` | `#0D6E0D` | tap |
| **Selected (start, every day between, end)** | **one solid band `#74FB71` + 1.5 px `#1F9A4A` contour around the band** (3.63 : 1 vs white). No gradient, no glow, no alpha. | `#08230F` 15/**900** (12.55) | `#0B3B1A` (9.54) | tap inside = new start |
| Single-day range | same band as one r11 capsule | same | same | — |
| Start chosen, end pending | start capsule + 2 px `#0D6E0D` ring, ping 1.8 s (reduced: static) | ink | ink | helper above grid "Teď klepni na den vrácení (může být i stejný den)" (web text) |
| **Today** (11. 10.) | free fill + 1.5 px `#0D6E0D` ring | ink + 4 px dot `#0D6E0D` | as free | a11y "dnes"; inside the band the dot turns `#08230F`, ring hidden |
| Past | none | `#9DB3A8` | hidden | none |
| Busy / obsazeno | hatch 135° `#EEF2F0` / `#FFF` 4 px | `#4A6B5A` struck | hidden | tap → toast "Tento den je motorka půjčená" (feedback, not silence) |
| Your other booking | 1.5 px dashed `#E9B44C`, `#FFF4E0` | `#8A4B00` | hidden | tap → toast "Tady už jedeš na {bike}" |
| Pending / čeká na potvrzení | none, 1.5 px dashed `#A66A00` | `#8A4B00` | hidden | none (web parity) |
| Out of rental limit (after start; beyond `max_rental_days` or under `min_rental_days`) | none | `#9DB3A8` | hidden | toast "Nejdéle 30 dní · Royal Enfield Shotgun 650" |
| Branch closed (season, from 1. 11.) | hatch like busy | `#9DB3A8` | hidden | banner over the month with the CMS season text |
| Range crosses a busy day | band **not** drawn; the tapped end cell shakes 300 ms (reduced: none) | — | — | inline note "V termínu je obsazený den {date} — vyber jiný den vrácení"; the start stays |
| Loading availability | cells shimmer once 1.2 s (reduced: static @.55) | `#9DB3A8` | hidden | not selectable; pill "Načítám obsazenost…" |
| Availability error | free look, prices hidden | ink | hidden | banner "Obsazenost se nepodařila načíst · Zkusit znovu"; the confirm / REZERVOVAT stays disabled until loaded (never "all free", Stavy 9.9) |

**Summary row above the grid:** "Vyzvednutí pá 23. 10. → Vrácení ne 25. 10. · **3 dny**" (the "3 dny" chip in `btnInk` style); bumps on change. **Legend** under the grid (12.5/600 `#4A6B5A`, 14 px swatches): Volno · **Tvůj termín** (band swatch) · Obsazeno · Čeká na potvrzení (+ "Tvoje jiná jízda" when present). Note line (web): "Cena/den v Kč (ceník) · tvoje sleva se odečte v souhrnu".

### 3.4 Edit mode (Reservation)

- The resulting range is the uniform band.
- Newly **added** days carry a top-right "+" (11/900 `#08230F`).
- Days **removed** by shortening sit outside the band: number `#B42318` struck, 1.5 px dashed `#B42318` outline.
- Legend adds "Přidáš" / "Ubereš"; original days have no extra mark. The summary row reads "Teď pá 16. – ne 18. 10. → nově pá 16. – po 19. 10. · +1 den".

### 3.5 Dark skin

Free `white@.08`; band solid `#74FB71` (11.55 : 1 vs `#0E2A1C`, no contour needed); number / price `#08230F` / `#0B3B1A`; today ring `white@.75` + neon dot; past `white@.36`; busy hatch `white@.38` struck; pending dashed `#FFD36B`@.75. Remove every `.24` / `.28` in-range alpha (1.94–2.21 : 1).

### 3.6 Motion and accessibility

- Start tap: `pop` 300. End tap: the band **grows** from start to end row by row (300 ms ease, 20 ms per cell, capped 200 ms). Summary chip and total `bump`; one `scanOnce` on a calculator total. Reduced motion: everything instant, ping ring static.
- Cell label: "pátek 23. října 2026, 3 514 Kč, vybráno, vyzvednutí" (ends: "vyzvednutí" / "vrácení"; middle: "vybráno"). Selection is never colour-only: band shape + weight 900 + summary row.
- **Web parity (separate task, owner decision §9 #7):** `landing-calc.css .kc-day.is-in` (.24) and `rezervace-v2.css .cal-day.in-range` (.28) have the same defect.

---
## 4. "Zaznamenat jízdu": always one tap away (R3)

### 4.1 Facts (`features/routes/ride_recorder.dart`, both trees)

- **Automatic** recording during a rental: logged in + running booking + location already granted + switch `mg_ride_autorecord` on. It ends with the rental.
- **Manual** recording `startManual()`: requires login; asks for location itself (`GpsService.ensurePermission`); on iOS requires *precise* location (`_ensurePreciseOnIos`).
- Survives an app kill (prefs `mg_ride_rec_id` / `_buf` / `_manual`); rides under 1 km are discarded; a failed stop retries every 2 min; Android shows a foreground notification "MotoGo24 zaznamenává jízdu".
- Today the only entries are the Trasy "+" menu and a card in Moje zážitky (+ the board-only "Nahrát jízdu" mini action on Home). One combined failure message ("přihlas se a povol polohu") covers four causes.
- Existing cs keys: `rideManualStart` "Zaznamenat vlastní jízdu", `rideManualStop` "Ukončit záznam jízdy", `rideManualHint`, `rideManualRunning`, `rideManualStarted` "Záznam jízdy běží 🛰️", `rideManualSaved`, `rideManualTooShort`, `rideManualStopFailed`, `rideManualFailed`, `rideRecordTitle` "Záznam jízdy", `rideRecording` "Nahrávám", `rideRecordHint`, `rideNotifTitle` / `rideNotifText`, `rideGapNotice`.
- Glyph: **green ⏺ while idle, red only while live** — red stays "live or emergency".

### 4.2 Placements

**A. Trasy tab — the record dock (the tab's one primary).** On all three segments (Místa, Trasy, Moje), a `dock` above the nav, the same pattern as the Detail sticky bar with the docked AI:

- Layout: `[ ⏺ ZAZNAMENAT JÍZDU ]` rank CTA 56 h, 294 px wide (the tab's one looping primary) + `[AI]` 56 disc, gap 8. Dock 72 + nav; scroll views get a bottom pad of 98 + 72 + 12. The free-floating AI FAB is hidden on Trasy (it lives in the dock).
- Label fit (14.5/800 caps; icon 20 + gap 8 + padding 2 × 16), new key **`rideRecShort`** [návrh]:

  | cs | en | de | es | fr | nl | pl | uk |
  |---|---|---|---|---|---|---|---|
  | ZAZNAMENAT JÍZDU 155 | RECORD A RIDE 119 | FAHRT AUFZEICHNEN 164 | GRABAR RUTA 110 | **ENREGISTRER LA SORTIE 193** | RIT OPNEMEN 107 | ZAPISZ PRZEJAZD 137 | ЗАПИСАТИ ПОЇЗДКУ 154 |

  Longest content 253 px (fr) in 294 → ≥ 41 px spare. No ellipsis, no wrap.
- **Dock priority** (one dock, never two bars stacked): ① live recording bar (§4.3) → ② Místa selection mode: `[✕ 44 zrušit výběr] [VLASTNÍ VYJÍŽĎKA ([n]) ›` rank CTA] and the record action collapses to a 56 `btnInk` disc with the ⏺ glyph (a11y "Zaznamenat jízdu", long-press tooltip) on the left → ③ idle `ZAZNAMENAT JÍZDU`.
- Consequences: "VYTVOŘIT NOVOU TRASU" (Moje) → `btnInk`; the map "Přidat místo" neon disc → white secondary; the "+" menu keeps "Zaznamenat vlastní jízdu" as a secondary path. TrasaDetail keeps "ZVOLIT TRASU – NAVIGOVAT" as its primary — no record dock on route detail, builder or navigation.

**B. Home shortcut — first row of the white "Moje zážitky" band.**

- `[iconTileDark 44, neon ⏺]` "Zaznamenat jízdu" 15/800 + subline "Jedeš na své? Uložíme ti trasu." [návrh] 12.5/600 `#55705F` + chevron.
- **Tap starts immediately** through the §4.5 flow without navigating; the row turns live ("● Nahrávám · 0,0 km · Ukončit").
- During a rental (ticket S7–S9) the row shows the automatic state (#10); ticket S8 "Jedeš" gets the line "● Záznam jízdy z výpůjčky běží · [km] km".

**C. Live indicator everywhere.**

- **Trasy tab:** the dock **morphs** (300 ms cross-fade + width) into the live bar: 10 px red dot with `ping` (the screen's one live loop; the CTA glow stops while live) · "NAHRÁVÁM · 1:12:05 · 38,2 km" 13.5/800 tabular white · `[Ukončit]` 44 white with `#B42318` label and ■ icon (new key **`rideRecStopShort`** [návrh]: Ukončit / Stop / Beenden / Detener / Arrêter / Stoppen / Zakończ / Зупинити). Tapping the bar (not the button) opens the recorder.
- **Other tabs:** the status strip floats 8 px above the nav "● Nahrávám jízdu · 38,2 km ›" (SOS keeps priority); hidden in focused flows (`/booking`, payment).
- **Navigation screen:** a 32 px chip "● REC" in the top bar next to the stop counter (no extra loop; static red dot) — the navigation is not covered by any bar.
- **Reservation "Probíhá":** in CO TEĎ a line "● Záznam jízdy běží · [km] km › Záznam" (automatic).
- The Android notification stays as is.

**D. Recorder screen** (`/ride-recorder`, full screen, dark — outdoor, night, OLED; exempt from R5.4)

- Top: back chevron disc 44 (§6, dark style; going back keeps recording) · title "Záznam jízdy" · ⓘ 44 (opens `rideRecordHint`).
- Live trace card 358 × 220 r20: neon line on a dark map, start pin, current-position dot.
- Numbers (no count-up or odometer animation): time 48/900 white tabular · distance 32/900 neon · average speed 20/800 · GPS chip "GPS přesný" / amber "GPS slabý".
- Mode chip: "Vlastní jízda" or "Výpůjčka · Husqvarna 701 SM".
- Switch row: `rideRecordTitle` + `rideRecordHint` (automatic recording during a rental).
- Dock: idle `[⏺ ZAČÍT ZÁZNAM]` rank CTA [návrh] · recording `[■ UKONČIT ZÁZNAM]` (`rideManualStop`) white button with `#B42318` label, 56 h — ending is not a money action, so it is never the rank CTA.

### 4.3 Motion

Dock idle ↔ live morph 300 ms · live dot `ping` 1.8 s (the only loop while recording) · saved ✓ `pop` 300 · reduced motion: static dot, instant swaps.

### 4.4 States (each failure says what, why, how; working action; never hangs) — also Stavy group 16

Copy is tykání and gender-neutral (§5.3). [návrh] = new string, 8 languages in the port.

| # | State (code condition) | Dock / Home row / strip | Message (title · why · fix) | Actions |
|---|---|---|---|---|
| 1 | Idle | ⏺ ZAZNAMENAT JÍZDU · row idle | — | — |
| 2 | Not logged in (`currentUser == null`) | idle | Light sheet: **Přihlas se a vyraž** · "Jízdy ukládáme do tvého účtu, ať o ně nepřijdeš." [návrh] | PŘIHLÁSIT SE (`btnInk`) · Zpět |
| 3 | Location services off | idle | **Poloha v telefonu je vypnutá** · "Bez ní trasu nenakreslíme." · "Zapni polohu a záznam se hned spustí." [návrh] | ZAPNOUT POLOHU (`openLocationSettings`) · Zpět |
| 4 | Permission not asked yet | idle | Pre-prompt sheet: **Potřebujeme tvoji polohu** · "Jen během jízdy, abychom ti nakreslili trasu." [návrh] | POKRAČOVAT → system dialog · Teď ne |
| 5 | Denied (can ask again) | idle | **Bez polohy jízdu nezaznamenáme** · "Přístup k poloze je zamítnutý." [návrh] | POVOLIT ZNOVU · Teď ne |
| 6 | Denied forever | idle | **Poloha je pro MotoGo24 zakázaná** · "Změnit to jde jen v nastavení telefonu: Oprávnění → Poloha → Povolit." [návrh] | OTEVŘÍT NASTAVENÍ (`openAppSettings`) · Teď ne |
| 7 | iOS approximate (`_ensurePreciseOnIos` false) | idle | **Zapni přesnou polohu** · "S přibližnou polohou se trasa nakreslit nedá." · "Nastavení → MotoGo24 → Poloha → Přesná poloha." [návrh] | OTEVŘÍT NASTAVENÍ (iOS only) |
| 8 | Starting, waiting for a fix | spinner "Hledám GPS…" + Zrušit · strip "Hledám GPS…" | after **30 s**: **Nemáme signál GPS** · "Telefon nevidí satelity." · "Vyjdi pod širé nebe a zkus to znovu." [návrh] | ZKUSIT ZNOVU · Zrušit |
| 9 | Recording manual | live bar + Ukončit · row live · strip | toast "Záznam jízdy běží" (`rideManualStarted` without the emoji) + notification | — |
| 10 | Recording automatic | live bar "NAHRÁVÁM · jízda z výpůjčky · [km] km" + `[Možnosti]` (no Ukončit — it ends with the rental) | ticket line + strip | Recorder: switch off = stop (`setEnabled(false)`) |
| 11 | Rental running, automatic switch off | ⏺ ZAZNAMENAT JÍZDU (manual possible) | Recorder note: "Automatický záznam výpůjčky je vypnutý · Zapnout" [návrh] | Zapnout |
| 12 | Weak GPS / gap | dot amber, "Slabý GPS signál" [návrh] · strip amber | later in ride detail: `rideGapNotice` (grey dotted segments) | — |
| 13 | Stop tapped | — | Confirm sheet (light): **Ukončit záznam?** · "38,2 km · 1 h 12 min" [návrh] (prevents accidental stops with gloves) | POKRAČOVAT V JÍZDĚ (`btnGhostLight`) · UKONČIT A ULOŽIT (`btnInk`) |
| 14 | Saved (≥ 1 km) | back to idle | Sheet: **Jízda je uložená** (`rideManualSaved`) · "Najdeš ji v Moje zážitky → Jízdy." | ZOBRAZIT JÍZDU (→ ride detail: photos, stops) · Hotovo |
| 15 | Too short (< 1 km) | idle | **Jízda byla kratší než 1 km** · "Takhle krátké jízdy neukládáme." (`rideManualTooShort`) | Rozumím |
| 16 | Save failed offline | idle · ride card badge "Čeká na odeslání" [návrh] | **Jízdu uložíme, až chytíš signál** · "Teď nejsi online; zkoušíme to každé 2 minuty." (`rideManualStopFailed`, rephrased) | OK, rozumím · Zobrazit čekající |
| 17 | Start failed, other | idle | **Záznam se nespustil** · "Něco se pokazilo v telefonu." · "Zkus to znovu; když to nepůjde, restartuj appku." (last resort only — causes 2–8 are told apart) | ZKUSIT ZNOVU |
| 18 | App restarted mid-ride (restore) | live bar resumes · strip | toast "Záznam pokračuje" [návrh] | — |
| 19 | Background location lost mid-ride (new) | strip amber "Záznam nemá polohu na pozadí" | **Trasa se může přerušit** · "Telefon appce vzal polohu na pozadí." · "Povol polohu i na pozadí." [návrh] | OTEVŘÍT NASTAVENÍ |

### 4.5 Board changes

- **TrasyHub:** add the dock to every `obrazovka` of the three segments; prop `nahravani` ("Ne" / "Automaticky (výpůjčka)" / "Ručně") drives dock idle / live bar; the live strip `.lvw` recording variant is removed on Trasy (the dock carries it); add prop `vyber` (boolean, Místa selection mode) to show dock priority ②.
- **Zazitky:** `obrazovka` "Záznam jízdy · panel" → "Záznam jízdy · obrazovka" (full-screen recorder) + new prop `zaznamStav` (enum of §4.4 #1–19, default "9 · Nahrávám ručně"); the summary card loses the ghost record button; the record dock on every Moje sub-screen.
- **Main:** row B in the Moje zážitky band (prop `nahravani` like TrasyHub) + ticket S8 line.
- **TrasaDetail:** "● REC" chip on Navigace screens when a recording runs (prop `nahravani`).
- **Reservation:** CO TEĎ "Probíhá" line.
- **Stavy:** group 16 draws #2–#8, #13–#17, #19 as variants.

---
## 5. Stavy board: every result, thank-you and error state (R2)

Source: `research/states_inventory.md` (IDs in brackets refer to it). Owner rule: every state says **what went wrong, why, how to fix it**, offers a **working next action**, and **nothing ever hangs**. This section is the single source for the copy; the in-context state props of the other boards (§5.8) and the Flutter port use the same templates and strings.

### 5.1 Principles

1. **Title = what happened** (one short sentence, no jargon, no "Chyba"). **Why** = one human sentence. **How** = 1–3 numbered steps (only when the customer can do something). **Primary action always present** and it must actually move the customer forward — never only "OK" / "Zavřít"; "Zkusit znovu" only when a retry can succeed.
2. **Never claim what we do not know.** "Nic jsme nestrhli" only when verified (decline, refusal before charge, 3-D Secure failed / cancelled). A timeout or unexpected status is **pending** ("Platbu ověřujeme"), never "nothing was charged".
3. **Never offer a second payment** while a payment for the same booking / order may still complete (pending state hides the pay buttons; retries reuse the same PaymentIntent / order).
4. **Raw server / Stripe / exception text never in the body** — it goes to "Technické detaily ▾" (code, reference, time, attempt; "Zkopírovat").
5. **Errors that need action are never a 3 s toast.** Toasts only confirm non-blocking things.
6. **SOS, calls and cached essentials (door codes, active navigation, ride recorder) are never covered** by any error, offline or update layer.
7. **Every state has a visible back / close** (§6) and the system back does the same thing.
8. **Rank never colours a state.** Rank shows only in the success / pending hero aura and their primary CTA.

### 5.2 Templates and tones

**Tones** (icon + colour + motion; meaning colours, never rank):

| Tone | Icon (24 grid, stroke 2) | Light: disc / icon | Dark: disc / icon | Text accent | Motion (reduced motion = static end state) |
|---|---|---|---|---|---|
| **✓ hotovo** (success) | check in circle | `#E8FCE8` / `#0D6E0D` | `#0E2A1C` + 3 px neon ring / neon | `#0D6E0D` · neon | check path draws 300 ms + disc `pop` + one neon ring ripple 700 ms (one-shot; not the level-up) |
| **⏳ čeká** (pending) | clock / arc ring | `#FFF4E0` / `#8A4B00` | `rgba(255,200,87,.16)` / `#FFD36B` | `#8A4B00` · `#FFD36B` | ring sweep 1.2 s — the screen's one live loop; on confirmation the ring closes into ✓ (morph 450 ms) |
| **⚠ pozor** (warning, fixable) | triangle | `#FFF4E0` / `#8A4B00` | as pending | `#8A4B00` | one `pop` |
| **✕ chyba** (error) | ✕ in circle | `#FDECEC` / `#B42318` (5.9 : 1) | `rgba(255,120,120,.14)` / `#FFB3B3` | `#B42318` · `#FFB3B3` | one shake 4 px / 300 ms |
| **⌁ info / offline** | info · wifi-off · lock | `well #F2F5F3` / `#1A2E22` | `white@.10` / white | ink · white | none |
| **SOS** (only group 14) | alert | `#D92D20` / white | same | white on `#D92D20` (4.83) | none |

**Templates:**

| | Use | Anatomy |
|---|---|---|
| **T1 Výsledková obrazovka** | end of a flow (success, pending, expired, crash fallback, unknown link, blocking update) | Status bar 47 · close ✕ or back ‹ at (16, 55) per §6 · **success / pending:** dark hero (`gDark` + rank aura) 0–≈ 360: tone disc 88, title 22/800 white, sub 14/600 `#CFE7DA`; a white summary card overlaps −24 (booking, amount, number `#[ID]`); · **warn / error / info:** canvas, tone disc 72 at y 120, title 22/800 ink, why 14/600 `#2C4A3A` · body on canvas: "Co bude dál" / "Jak to vyřešit" numbered list (34 px dark step discs with neon numbers, 14/600 lines) · collapsible "Technické detaily ▾" · support row · **dock**: success / pending = dark dock with the rank CTA; warn / error / info = white dock (top hairline) with `btnInk` primary 52 + `btnText` secondary; destructive = `#B42318` fill; SOS = `#D92D20` fill |
| **T2 Výsledkový sheet** | interruption inside a flow (payment errors, refusals, conflicts, permissions) | Light sheet r22, grabber 42 × 5 `#CFE3DA`, ✕ 44 top-right · tone disc 56 + optional chips ("Pokus 2 ze 3", ✓ "Nic jsme nestrhli") · title 20/800 ink (2 lines max) · why 14/600 `#2C4A3A` · steps (max 3, 12.5/600, 20 px numbers) · buttons stuck to the sheet bottom: primary `btnInk` 52 full width, secondary `btnGhostLight` 48, tertiary `btnText` · support row · "Technické detaily ▾" · max height 86 %, content scrolls, buttons never scroll away |
| **T3 Banner v obrazovce** | gates and notes inside a screen (form blocks, calendar, docs, codes) | White or tone-tinted card r16 (warn `#FFF4E0` + 1 px `#E9B44C`, error `#FDECEC` + 1 px `#F3B5AF`, ok `tintOk`, info `well`), 32 disc + icon 20, title 14/800, text 12.5/600, inline actions (`btnInk` sm 40 / `btnText`); never colour-only |
| **T4 Globální lišta** | offline, active SOS, rozdělaná platba, recording | Night glass r14; offline sits under the status bar (slides down 300), the others 8 px above the nav (status strip); icon 20, text 13.5/700, one action; ✕ only when dismissible |
| **T5 Toast** | non-blocking confirmations only (Uloženo, Zkopírováno, Poukaz je v košíku) | Night glass r14, icon 20, 13.5/700, 2.8 s; with an action ("Zobrazit") 4 s and paused while touched |
| **T6 Dialog** | confirmation of an irreversible step (storno, ukončit záznam, smazat) | r22, title 20/800, body 14/600, two buttons: safe left (`btnGhostLight`), action right (`btnInk` or red); stacked when a label does not fit one line (de, fr) |

**Support row** (every T1 / T2 with ✕ or ⚠): "Pomůžeme ti:" + `Zavolat +420 774 256 271` + `Napsat nám` (opens Zprávy with the booking / order number prefilled). Offline: "Napsat" becomes `info@motogo24.cz`. Replaces the vykání line "Potřebujete pomoc? Napište nám na info@motogo24.cz".

**Interactions:** buttons show their spinner inside (no layout jump); "Zkusit znovu" is disabled while running; a pending screen switches itself to success (live) — no user action needed; "Technické detaily" expands with `AnimatedSize` 300; sheets slide 300; dialogs fade + scale .96 → 1 in 180 ms; offline banner turns green "Jsi zpátky online" for 1.5 s and slides away.

### 5.3 Copy rules (8-language-ready)

- **Czech tykání** everywhere; other languages in the informal register where it exists (de *du*, fr *tu*, es *tú*, nl *je*, pl 2nd person singular, uk *ти*) — the newer keys (`translations_ext_36_ride_feedback.dart`, `ext_18/19_rides`) already do this, the older payment / offline keys are formal and get rewritten (owner decision §9 #13).
- **Gender-neutral:** no past participles or adjectives addressed to the customer (cs "jsi zaplatil/a", "jsi připojený", "sám"; pl "zapłaciłeś/aś"; uk "оплатив/ла"). Use states and "we" forms: "Máš zaplaceno", "Ověření je zrušené", "Telefon je offline", "Nic jsme nestrhli".
- **One key per string, no sentence concatenation** (fixes H-05 "…Rezervace. 3 Nebo nás…"). Placeholders: `{amount}` (locale-formatted, "10 189 Kč"), `{date}`, `{range}`, `{time}`, `{bike}`, `{branch}`, `{n}`, `{max}`, `{last4}`, `{wallet}` (Google Pay / Apple Pay by platform), `{email}`, `{id}`. Plurals through a helper (`den / dny / dní`), never "{n} dní" for 2–4.
- **Length budget (cs):** title ≤ 38 characters (2 lines at 20/800 in 326 px with +40 % expansion), why ≤ 160, step ≤ 80, sheet button ≤ 26 (sentence case), rank CTA ≤ 22 (caps). Buttons never ellipsize; a sheet button may grow to 2 lines (min-h 52 → 64); the Stavy board proves it with `pseudo` (+40 %).
- **No emoji** in titles or bodies (⏳ ❌ 🆘 🛰️ ✅ in existing keys go); icons carry the tone.
- **Keys:** new strings use the prefix `st` + group + state + part, e.g. `stPayFundsTitle`, `stPayFundsWhy`, `stPayFundsFix1`, `stPayFundsCta`. Existing keys are reused where the text already fits the rule (named in the tables). Port files split by group and language so each stays < 5 000 tokens (CLAUDE.md rule 2).

**Shared strings** [návrh unless an existing key is named]:

| Key | cs | Note |
|---|---|---|
| `retry` (existing) | Zkusit znovu | |
| `payWithAnotherCard` (existing) | Zaplatit jinou kartou | |
| `stShowBooking` | Zobrazit rezervaci | |
| `stBackToBooking` | Zpět k rezervaci | |
| `stMyBookings` | Moje rezervace | |
| `stHome` | Domů | |
| `stCall` | Zavolat | + number line `+420 774 256 271` |
| `stWrite` | Napsat nám | opens Zprávy, prefilled `#{id}` |
| `stHelp` | Pomůžeme ti: | support row lead |
| `stNoCharge` | Nic jsme nestrhli | reassurance chip, only when verified |
| `stAttempt` | Pokus {n} ze {max} | chip |
| `stTech` / `stTechCopy` | Technické detaily / Zkopírovat | |
| `stOpenSettings` | Otevřít nastavení | (`openPhoneSettings` "Otevřít nastavení telefonu" for rows) |
| `stNotNow` | Teď ne | |
| `stChangeDates` | Změnit termín | |
| `stShowFree` | Ukázat volné motorky | |

### 5.4 Groups

19 groups (the inventory's §T suggested 18; login is split out of "network"). Each table row is one board variant. **Tón · plocha** uses §5.2 (T1 obrazovka, T2 sheet, T3 banner, T4 lišta, T5 toast, T6 dialog). Actions: **primary** · secondary · tertiary.

#### Group 1 · Hotovo (success, thank-you)

| # | ID | Tón · plocha | Nadpis | Co a proč | Co dál / jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 1.1 | G-01 | ✓ T1 (dark hero, rank aura) | Rezervace je potvrzená | {bike} · {range} · #{id}. Platbu {amount} Kč máme a motorku ti držíme. | 1. Potvrzení máš v e-mailu. 2. Doklady: banner 1.2–1.5. 3. Vyzvednutí {date} {time} · {branch} + "Otevřít v mapě". Self-service ½: `ssLateGateNote` in tykání ("Kiosk ti motorku vydá {date} od 12:00. Chceš ji dřív? Uprav čas vyzvednutí — sleva zanikne a rozdíl doplatíš."). "Bezpečnostní pokyny ▾" (`successSafetyTips`). Meta: "Rezervaci uvidíš i na webu MotoGo24." | **ZOBRAZIT REZERVACI** · Přidat do kalendáře [návrh, §9 #15] · Domů |
| 1.2 | G-01a | ✓ T3 in 1.1 | Doklady máš ověřené | `docsVerifiedBody` (already tykání) | — | — |
| 1.3 | G-01b | ⚠ T3 in 1.1 | Doklady ještě nejsou ověřené | server reason + `docsMissingBody` (tykání) | Nahraj fotky OP / pasu a ŘP. | screen primary becomes **NAHRÁT DOKLADY** · Zobrazit rezervaci |
| 1.4 | G-01c | ✓ T3 in 1.1 | Doklady se nevyžadují | `docsChildBikeBody` | — | — |
| 1.5 | G-01d | ⌁ T3 in 1.1 | Stav dokladů teď nevidíme | Nepodařilo se ho načíst. Najdeš ho v detailu rezervace. | — | Zkusit znovu (`btnText`) |
| 1.6 | G-06 | ✓ T1 | Potvrzeno, platit nic nemusíš | Sleva pokryla celou cenu rezervace. | as 1.1 | **ZOBRAZIT REZERVACI** |
| 1.7 | G-02 | ✓ T1 | Změna je zaplacená a uložená | Doplatek {amount} Kč máme. Rezervace teď platí {range}. | Potvrzení máš v e-mailu. | **ZOBRAZIT REZERVACI** — shown only after the booking reflects the change, else 2.7 |
| 1.8 | G-03 | ✓ T1 | Výměna motorky je potvrzená | Od {date} {time} jedeš na {bike}. Doplatek {amount} Kč máme. | Vyzvednutí: {branch}. | **ZOBRAZIT REZERVACI** (guard as 1.7) |
| 1.9 | G-09 | ✓ T1 | Výměna motorky je potvrzená | Od {date} {time} jedeš na {bike}. | If refund: "Rozdíl {amount} Kč ti vrátíme na kartu, kterou se platilo." | **ZOBRAZIT REZERVACI** |
| 1.10 | G-07 | ✓ T1 | Změny jsou uložené | Rezervace teď platí {range}. | — | **ZOBRAZIT REZERVACI** |
| 1.11 | G-07 zkrácení | ✓ T1 | Rezervace je zkrácená | Nový termín {range}. Vrátíme ti {amount} Kč na kartu, kterou se platilo. | Na účtu je obvykle do [5–10 pracovních dnů · ověřit, §9 #12]. | **ZOBRAZIT REZERVACI** |
| 1.12 | G-07a | ⚠ T1 | Uloženo, peníze vrátíme ručně | Změnu máme, jen automatické vrácení {amount} Kč se nepovedlo. | Obsluha ho pošle ručně a ozve se ti. Nemusíš nic dělat. | **Zobrazit rezervaci** · Napsat nám (raw `process-refund` text → tech) |
| 1.13 | G-07b | ⚠ T3 | Doplňky odebere obsluha | Změnu máme, ale odebrané doplňky se nepodařilo zapsat. | Ty nic dělat nemusíš. | — |
| 1.14 | G-08 | ✓ T1 | Termín je posunutý | Rezervace teď platí {range}. Posun byl zdarma. | Potvrzení a novou smlouvu máš v e-mailu (`moveConfirmed` meaning). | **ZOBRAZIT REZERVACI** |
| 1.15 | F-02 | ✓ T1 | Tahle rezervace už je zaplacená | Platba proběhla už dřív, třeba z webu nebo z jiného telefonu. Podruhé ti nic nestrhneme. | — | **ZOBRAZIT REZERVACI** |
| 1.16 | G-04 | ✓ T1 | Objednávka je zaplacená | Objednávka #{n} · {amount} Kč. Potvrzení máš v e-mailu. | — | **ZPĚT DO E-SHOPU** · Domů (only when confirmed, else 2.11) |
| 1.17 | G-10 | ✓ reference | (registration celebration `MotoWelcomeOverlay`) | unchanged | — | — |

#### Group 2 · Platba se ověřuje (pending)

| # | ID | Tón · plocha | Nadpis | Co a proč | Co dál | Akce |
|---|---|---|---|---|---|---|
| 2.0 | D-01, E-01 | ⏳ inside the pay button | Ověřuju platbu… | Platba prošla, čekáme na potvrzení banky (≤ 8 s). | — | none → 1.1, or 2.1 when not confirmed in 8 s |
| 2.1 | H-01, D-14, E-12 | ⏳ T1 (dark hero, ring sweep) | Platbu ověřujeme | Banka ji ještě nepotvrdila. Většinou to trvá pár vteřin, někdy pár minut. | 1. Neplať znovu — dvakrát ti nic nestrhneme. 2. Jakmile platba dorazí, přepneme tě sem na potvrzení. | **ZOBRAZIT REZERVACI** (card and detail show the badge "Platba se ověřuje", the "Dokončit rezervaci" pay buttons are hidden) · Zůstat tady. Live: realtime + poll every 5 s for [10 min] → 1.1 |
| 2.2 | H-01 after [10 min] | ⚠ T1 | Platbu pořád nevidíme | Banka nám ji zatím nepotvrdila. Pokud ti peníze z účtu odešly, dořešíme to — rezervaci potvrdíme, nebo peníze vrátíme. | 1. Neplať znovu. 2. Napiš nebo zavolej, číslo rezervace pošleme za tebe. | **Napsat nám** · Zavolat |
| 2.3 | E-02 | ⏳ state of the card sheet | Dokončujeme platbu… | Nezavírej aplikaci, trvá to pár vteřin. | — | none (sheet locked); after 20 s → 2.1 |
| 2.4 | E-09 (Android) | ⏳ card sheet | Platba právě probíhá | Sheet se teď nedá zavřít, aby se platba neztratila. | Počkej pár vteřin. | none; swipe / back / scrim tap show this line; a forced close returns `processing` → 2.1 (port the iOS `_WalletGuard`) |
| 2.5 | D-15 | ⏳ T2 | Ověřujeme, jestli platba prošla | Spojení s platební bránou trvalo moc dlouho. Možná platba proběhla, možná ne — hned to zjistíme. | Neplať znovu, dokud to neověříme. | auto-check booking / PaymentIntent → 1.1 or 2.8; button "Zkontrolovat znovu" (disabled while checking) |
| 2.6 | H-02 | ⏳ T1 | Vítej zpátky, ověřujeme platbu | Vracíš se z banky; výsledek platby si teď bereme. | — | auto → 1.1 / 2.1 / 2.8 |
| 2.7 | H-01 edit / swap | ⏳ T1 | Doplatek ověřujeme | Změnu uložíme, jakmile banka platbu potvrdí. | Neplať znovu. | **ZOBRAZIT REZERVACI** (badge "Změna čeká na platbu") → 1.7 / 1.8 |
| 2.8 | check result unpaid | ✕ T2 + `stNoCharge` | Platba neproběhla | Banka ji nepotvrdila. | Zkus to znovu, nebo zvol jinou kartu. | **Zkusit znovu** · Zaplatit jinou kartou |
| 2.9 | L-08, L-09 | ⏳ T1 | Platbu objednávky ověřujeme | Objednávka #{n} čeká na potvrzení banky. | Nic dalšího neplať — pokus o platbu použije stejnou objednávku. | **Zpět do e-shopu** (pay for this order disabled until resolved) |

#### Group 3 · Karta zamítnutá (saved card D-*, card sheet E-04). All T2, ✕, chips `stAttempt` + `stNoCharge`.

| # | ID | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|
| 3.1 | D-04 `stPayFunds` | Na kartě není dost peněz | Banka platbu {amount} Kč zamítla kvůli nedostatku prostředků. | 1. Doplň peníze na účet a zkus to znovu. 2. Nebo zaplať jinou kartou či přes {wallet}. | **Zaplatit jinou kartou** · Zkusit znovu |
| 3.2 | D-05 `stPayBlocked` | Karta je zablokovaná | Banka ji vede jako ztracenou nebo odcizenou, platbu proto nepustí. | Zaplať jinou kartou. Zablokovanou si můžeš rovnou odebrat z účtu. | **Zaplatit jinou kartou** · Odebrat kartu (no retry) |
| 3.3 | D-06 `stPayLimit` | Karta narazila na limit | Překročil se denní limit nebo počet plateb na kartě. | 1. Zvyš si limit v aplikaci banky a zkus to znovu. 2. Nebo zaplať jinou kartou. | **Zaplatit jinou kartou** · Zkusit znovu |
| 3.4 | D-07 `stPayExpired` | Karta už neplatí | Uložené kartě •••• {last4} skončila platnost. | Zaplať jinou kartou — novou si uložíme pro příště. | **Zaplatit jinou kartou** · Odebrat starou kartu |
| 3.5 | D-08 `stPayCvc` | Kód CVC nesedí | Bezpečnostní kód ze zadní strany karty banka nepřijala. | Zadej kartu znovu i s kódem CVC. | **Zadat kartu znovu** (opens the card sheet; no blind re-charge of the saved card) |
| 3.6 | D-09 `stPayBank` | Platbu zastavila tvoje banka | Neschválila ji, nejčastěji kvůli ochraně proti podvodům. | 1. Povol platbu v aplikaci své banky. 2. Zkus to znovu, nebo zaplať jinou kartou. | **Zkusit znovu** · Zaplatit jinou kartou |
| 3.7 | D-10 `stPayDeclined` | Banka platbu zamítla | Přesný důvod nám banka nesdělila. | Zaplať jinou kartou, nebo se zeptej své banky. | **Zaplatit jinou kartou** · Zkusit znovu |
| 3.8 | D-11, D-12 | = 3.7 | = 3.7 (the Stripe message goes to Technické detaily, the same in every language) | | |
| 3.9 | E-04 `incorrect_number` | Číslo karty nesedí | V zadaném čísle je nejspíš překlep. | Zkontroluj číslo a oprav ho — ostatní údaje zůstanou vyplněné. | **Opravit číslo** (focus the field, keep the input) |
| 3.10 | E-04 `processing_error` | Dočasná chyba platební brány | Platbu se teď nepodařilo zpracovat. S tvojí kartou je vše v pořádku. | Počkej chvilku a zkus to znovu. | **Zkusit znovu** |
| 3.11 | D-17 | ⌁ T3 in the card sheet: Uložená karta už v účtu není | Mezitím byla odebraná. | Zadej kartu znovu. | (the card field is focused) |
| 3.12 | E-13 declined (Profil, Android) | Banka kartu nepřijala | Kartu se nepodařilo u banky ověřit. | Zkus jinou kartu, nebo se zeptej banky. | **Zkusit jinou kartu** |
| 3.13 | E-13 other | Kartu se nepovedlo uložit | Něco se pokazilo na naší straně; karta se neuložila. | Zkus to znovu za chvilku. | **Zkusit znovu** (network → 8.3) |

After the 3rd failed attempt of a new booking → 10.4; of an edit → 10.5. A cancelled 3-D Secure never counts as an attempt.

#### Group 4 · Ověření v bance (3-D Secure)

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 4.1 | D-02 | ⏳ T3 under the bank overlay | Potvrď platbu v aplikaci banky | Banka chce platbu {amount} Kč ověřit. | Otevři aplikaci banky nebo opiš kód z SMS. | none; after [120 s] → 4.2 |
| 4.2 | D-02 timeout | ⚠ T2 | Ověření v bance trvá dlouho | Banka zatím nepotvrdila, jestli je platba schválená. | 1. Zkontroluj aplikaci banky nebo SMS. 2. Pak klepni na Zkontrolovat stav. | **Zkontrolovat stav** · Zrušit platbu |
| 4.3 | D-03, E-04 `authentication_required` | ✕ T2 + `stNoCharge` | Banka platbu neověřila | Ověření 3-D Secure se nedokončilo. | Zkus to znovu a potvrď platbu v aplikaci banky nebo kódem z SMS. | **Zkusit znovu** · Zaplatit jinou kartou |
| 4.4 | D-03 / E-03 cancelled | ⌁ T2 + `stNoCharge` | Ověření v bance je zrušené | Platba neproběhla. Do počtu pokusů se to nepočítá. | — | **Zkusit znovu** · Zpět k rezervaci |

#### Group 5 · Google Pay / Apple Pay (`{wallet}` by platform)

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 5.1 | E-05 | ⌁ inline line in the card sheet, 4 s | Platba přes {wallet} je zrušená | Můžeš zaplatit kartou níž. | — | — (not an attempt) |
| 5.2 | E-06 | ✕ T2 + `stNoCharge` | {wallet} teď nejde použít | Platba přes {wallet} neprošla. | 1. Zkontroluj, že máš ve {wallet} platnou kartu. 2. Nebo zaplať kartou přímo — to funguje vždy. | **Zaplatit kartou** · Zkusit {wallet} znovu |
| 5.3 | E-07 | ⌁ T3 in the card sheet [návrh] | {wallet} v tomhle telefonu nemáš nastavené | Proto ho tu nenabízíme. | Zaplať kartou níž — kartu si uložíme pro příště. | — |
| 5.4 | E-10 | group 3 copy with {wallet} = Apple Pay | | | | secondary "Vybrat jinou kartu ve Walletu" |
| 5.5 | E-11 (iOS) | ✕ dialog → T2 | Platba přes Apple Pay neprošla | Nic jsme nestrhli (verified). | Zaplať kartou tady níž, nebo to zkus později znovu. | **Zaplatit kartou** · Zkusit Apple Pay znovu |
| 5.6 | E-08 non-Stripe error / unexpected PaymentIntent status | → 5.2 when a wallet was used; → 2.5 when the status is unknown (never "nic nebylo strženo"); else 3.7 | | | | |

The iOS checkout sheet **has** a card field (`card_payment_sheet.dart` iOS: Apple Pay + `CardField`); only the iOS *profile* payment-methods screen has no manual card entry.

#### Group 6 · Částka pod 15 Kč (Stripe minimum, §S) — decided **before** the payment screen

The board draws variant A as recommended and B / C as alternatives (owner decision §9 #8). Never "Platba kartou zamítnuta", never counted as an attempt.

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 6.1 | S edit, A (doporučeno) | ⌁ T2 in the edit | Doplatek {amount} Kč neplatíš | Kartou jde zaplatit až od 15 Kč, takže tenhle drobný rozdíl ti odpustíme. | — | **ULOŽIT ZMĚNU** · Zpět k úpravě |
| 6.2 | S edit, B | ⌁ T2 | Doplatek zaokrouhlíme na 15 Kč | Kartou jde zaplatit nejméně 15 Kč, doplatek {amount} Kč proto zaplatíš jako 15 Kč. | — | **ZAPLATIT 15 KČ** · Zpět k úpravě |
| 6.3 | S edit, C (Mezná only) | ⌁ T2 | Doplatek {amount} Kč zaplatíš na pobočce | Kartou jde zaplatit až od 15 Kč. Změnu uložíme hned, rozdíl vyrovnáš při převzetí. | — | **ULOŽIT ZMĚNU** |
| 6.4 | S swap | ⌁ T2 | Doplatek za výměnu {amount} Kč neplatíš | as 6.1 (or B / C) | — | **POTVRDIT VÝMĚNU** |
| 6.5 | S new booking (voucher leaves 1–14 Kč) | ⌁ T3 above the pay dock | Zbývá jen {amount} Kč — neplatíš je | Kartou jde zaplatit až od 15 Kč, zbytek po poukazu ti odpustíme. | — | dock **POTVRDIT REZERVACI ZDARMA** (server free-branch must accept a remainder < 15) |
| 6.6 | S shop (`below_minimum`) | ⚠ T3 in the cart | Objednávka musí mít aspoň 15 Kč | Kartou jde zaplatit nejméně 15 Kč, v košíku máš {amount} Kč. | Přidej do košíku ještě něco za {missing} Kč. | **Upravit košík** |
| 6.7 | D-13, F-03 with `amount_too_small` (legacy, reaching the app) | ⌁ T2 | Tuhle malou částku kartou nezaplatíš | Platby kartou pod 15 Kč banky nepouštějí. Změnu jsme neuložili. | Napiš nám, dořešíme to. | **Napsat nám** · Zpět k úpravě |

#### Group 7 · Server platbu odmítl (before any charge; all T2 ✕ + `stNoCharge`)

| # | ID | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|
| 7.1 | F-01a `moto_unavailable` | Motorka v novém termínu není volná | Mezitím ji někdo rezervoval, nebo má pobočka v těch dnech zavřeno. | Vyber jiný termín nebo jinou motorku. | **Změnit termín** · Vybrat jinou motorku |
| 7.2 | F-01b `wrong_status` | Rezervaci už nejde upravit | Je stornovaná nebo už skončila, doplatek jsme proto zrušili. | — | **Otevřít rezervaci** |
| 7.3 | F-01c `trailer_staffed_only` | Vozík jen k motorce z Mezné | Vozík půjčujeme jen na obslužné pobočce Mezná. | Odeber vozík, nebo vyber motorku z Mezné. | **Odebrat vozík** · Zpět k úpravě |
| 7.4 | F-01d `trailer_unavailable` | Vozík je v tom termínu obsazený | Má ho jiná rezervace. | Odeber vozík, nebo zvol jiný termín. | **Odebrat vozík** · Změnit termín |
| 7.5 | F-01e `trailer_check_unavailable`, `validation_unavailable` (⚠) | Teď to nemůžeme ověřit | Kontrola dostupnosti na serveru chvíli neodpovídá. | Zkus to za minutu znovu. | **Zkusit znovu** |
| 7.6 | F-01f `booking_not_found` | Rezervaci jsme nenašli | Mohla se mezitím změnit nebo smazat. | Načti rezervace znovu. | **Načíst znovu** |
| 7.7 | F-01g `forbidden` (edit) | Tuhle rezervaci z tohoto účtu neupravíš | Patří jinému účtu. | Přihlas se účtem, kterým se rezervace dělala. | **Přihlásit jiným účtem** · Zpět |
| 7.8 | F-01g `forbidden` (new booking) | Platbu z tohoto účtu nejde dokončit | Rezervace patří jinému účtu. | Přihlas se správným účtem. | **Přihlásit jiným účtem** · Zpět |
| 7.9 | F-01h `stale_booking` | Rezervace se mezitím změnila | Upravil ji někdo na webu nebo v jiném telefonu. | Načteme aktuální stav, úpravu pak zopakuj. | **Načíst a upravit znovu** |
| 7.10 | F-01i `amount_mismatch` (edit) | Doplatek se přepočítal | Cena se mezitím změnila a částka nesedí. | Načti úpravu znovu, ukážeme ti novou částku. | **Načíst novou cenu** |
| 7.11 | F-01i `amount_mismatch` (new booking) | Cena rezervace se změnila | Teď vychází na {amount} Kč. | — | **Pokračovat za {amount} Kč** · Zpět |
| 7.12 | F-01j `active_pickup_time_locked` (⌁) | Čas vyzvednutí už změnit nejde | Motorku už máš vyzvednutou. | Změnit můžeš vrácení. | **Upravit vrácení** |
| 7.13 | F-01k `delivery_fee_guard` | Cena přistavení se přepočítala | Poplatek podle adresy už nesedí s tím, co vidíš. | Potvrď adresu znovu, cenu ti hned ukážeme. | **Zkontrolovat adresu** |
| 7.14 | F-01k `location_requires_route` | K adrese chybí trasa | Vzdálenost k místu přistavení se nepodařilo spočítat. | Vyber místo na mapě znovu. | **Vybrat na mapě** |
| 7.15 | F-01k `not_sos_replacement` | Tuhle platbu teď nejde dokončit | Rezervace není náhradou po SOS události. | Napiš nám, dořešíme to. | **Napsat nám** |
| 7.16 | F-01k `invalid_amount`, `invalid_type` | Platbu nejde dokončit | Částka nebo typ platby nesedí s rezervací. | Načti rezervaci znovu; když to nepomůže, napiš nám. | **Načíst znovu** · Napsat nám |
| 7.17 | F-03 Stripe 500 / outage | Platební brána teď neodpovídá | Výpadek je na straně platební brány, ne u tvé karty. | Zkus to za pár minut. Nezaplacenou rezervaci ti držíme do {time}. | **Zkusit znovu** |
| 7.18 | F-04 free-branch price check | Cenu je potřeba přepočítat | Sleva nebo poukaz už nepokrývá celou cenu. | Obnov cenu a uvidíš, kolik zbývá. | **Obnovit cenu** |
| 7.19 | C-11 no booking id | Rezervaci se nepovedlo založit | Server nám nevrátil číslo rezervace. | Zkus to znovu — dvakrát ji nezaložíme. | **Zkusit znovu** (idempotency key, §5.6) |

#### Group 8 · Připojení, server, přihlášení

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 8.1 | R-01 | ⌁ T4 offline banner (under the status bar, not a blocker) | Jsi offline | Telefon teď nemá internet. Co máš načtené, funguje dál. | Zkontroluj data nebo Wi‑Fi. | **Zkusit znovu** · Co funguje bez signálu › (8.2) |
| 8.2 | R-01 | ⌁ T2 | Co funguje i bez signálu | SOS a tísňové linky 155 · 158 · 112 (call buttons) · nonstop linka MotoGo24 · kódy k pobočce (naposledy načtené) · rozjetá navigace · záznam jízdy (uloží se, až chytíš signál) · detail rezervace (naposledy načtený) | — | **Zkusit znovu** · Zavolat MotoGo24 |
| 8.3 | R-01 action | ⌁ T2 | Na tohle potřebuješ internet | {action} bez připojení nejde dokončit. Nic se neodeslalo. | Zapni data nebo Wi‑Fi a zkus to znovu. | **Zkusit znovu**. Pay buttons are disabled offline with the inline reason "Bez internetu zaplatit nejde". |
| 8.4 | R-01 at start | ⌁ T4 + cached content | Jsi offline | as 8.1; screens show cached data with "Naposledy načteno {time}", or 8.6 — never a raw error | — | as 8.1 |
| 8.5 | Wi‑Fi without internet | ⌁ T4 | Wi‑Fi nemá internet | Telefon je připojený k Wi‑Fi, ale internet přes ni nejde. | Přihlas se k Wi‑Fi, nebo ji vypni a použij data. | **Zkusit znovu** · Otevřít nastavení Wi‑Fi (needs a real reachability check, `pingSupabase`) |
| 8.6 | R-05/06/07/08/11/13, M-11, P-08 | ✕ T3 or T1 (with back) | {Co} se nepodařilo načíst — Motorky / Rezervaci / Profil / Doklady / Faktury / Karty / Zprávy | Server teď neodpovídá, nebo je slabý signál. | Zkus to znovu za chvilku. | **Zkusit znovu** + back always visible; raw text → tech |
| 8.7 | any await > 10 s | ⏳ inline (in the button / card) | Trvá to déle než obvykle | Slabý signál nebo vytížený server. | — | **Počkat** · Zrušit (only where cancelling is safe); hard timeout → flow state |
| 8.8 | 5xx generic | ✕ T2 | Na našem serveru se něco pokazilo | Není to chyba tvého telefonu. | Zkus to za pár minut; když to nepomůže, napiš nám. | **Zkusit znovu** · Napsat nám |
| 8.9 | D-16 | ⚠ T2 | Přihlas se znovu | Z bezpečnostních důvodů tě appka odhlásila. Rezervace ti zůstává uložená. | Po přihlášení tě vrátíme rovnou k platbě. | **Přihlásit se** (returns to the same payment, edit surcharge included) |
| 8.10 | Q-13 | ⌁ T3 on the login screen | Odhlásili jsme tě | Přihlášení vypršelo z bezpečnostních důvodů. | Po přihlášení se vrátíš na stejné místo. | **Přihlásit se** |
| 8.11 | Q-12 session gone | ⌁ T2 | Přihlas se e-mailem | Otisk prstu ani Face ID tě teď nepřihlásí — uložené přihlášení vypršelo. | Přihlas se jednou e-mailem a heslem, pak to zase půjde otiskem. | **Přihlásit e-mailem** (replaces "Session vypršela") |
| 8.12 | Q-05 | ✕ T2 | Nedaří se spojit se serverem | Telefon je asi offline, nebo internet blokuje VPN. | Zkontroluj připojení, případně vypni VPN, a zkus to znovu. | **Zkusit znovu** (login variant drops "Účet zatím nevznikl") |
| 8.13 | C-12 | ✕ T2 + `stNoCharge` | Rezervaci se nepodařilo dokončit | Spojení se přerušilo. | Zkus to znovu — dvakrát ji nezaložíme. | **Zkusit znovu** |

#### Group 9 · Rezervace: termín, motorka, formulář

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 9.1 | B-01 | ⌁ T3 above the disabled CTA | Vyber termín | Bez termínu cenu nespočítáme. | — | **Vybrat termín** |
| 9.2 | B-02 | ⌁ T3 | Nejdřív vyber motorku | (`selectMotoFirst` tykání) | — | **Vybrat motorku** |
| 9.3 | B-05 | ⚠ T3 | V tom termínu už jednu rezervaci máš | {range} jedeš na {bike}. Dvě rezervace přes sebe mít nejde. | Změň termín, nebo otevři tu první. | **Změnit termín** · Otevřít rezervaci (all 8 languages; today hard-coded cs) |
| 9.4 | B-06 min | ⚠ T3 | Tuhle motorku půjčujeme minimálně na {n} {dny} | Kratší pronájem u ní nejde. | Prodluž termín. | **Změnit termín** |
| 9.5 | B-06 max | ⚠ T3 | Tuhle motorku půjčujeme nejdéle na {n} {dní} | (Shotgun 30) | Zkrať termín, nebo vyber jinou motorku. | **Změnit termín** · Ukázat volné motorky |
| 9.6 | B-07 past | ⚠ T3 | Čas vyzvednutí už je pryč | Rezervaci nejde vytvořit zpětně. | Vyber pozdější čas. | **Nejbližší možný: {time}** (chip) |
| 9.7 | B-07 staffed lead | ⚠ T3 | Tak brzy to nestihneme připravit | Na pobočce s obsluhou potřebujeme aspoň hodinu. | — | **Nejbližší možný: {time}** |
| 9.8 | B-07 delivery lead | ⚠ T3 | Přistavení stihneme nejdřív za 6 hodin | Motorku musíme připravit a dovézt. | — | **Nejbližší možný: {time}** |
| 9.9 | B-12b availability error | ⚠ T3 in the calendar | Obsazenost se nepodařila načíst | Bez ní ti nemůžeme ukázat volné dny. | — | **Zkusit znovu**; confirm / CTA disabled until loaded (no silent "all free") |
| 9.10 | B-12 | ⚠ inline calendar note | V termínu je obsazený den {date} | Motorka je ten den půjčená. | Vyber jiný den vrácení. | (§3.3) |
| 9.11 | B-10 | ⚠ T3 | Doplň velikosti výbavy | Přistavujeme výbavu přesně na tebe. Chybí: {missing}. | — | **Doplnit velikosti** (scrolls to the section) |
| 9.12 | B-11 | ⌁ T3 | Potvrď souhlas s podmínkami | Bez něj rezervaci nemůžeme dokončit. | — | (the consent row pops; V2 §8) |
| 9.13 | C-01 | ⌁ T2 | Přihlas se a dokonči rezervaci | Rezervaci ukládáme do tvého účtu. Výběr ti zůstane. | — | **Přihlásit se** |
| 9.14 | C-02 | ⚠ T2 | Výběr se ztratil | Chybí motorka nebo termín — appka je mohla zapomenout po restartu. | — | **Vybrat znovu** (→ Motorky with known dates) |
| 9.15 | C-04 | ✕ T2 + `stNoCharge` | Motorku si mezitím někdo rezervoval | {bike} je {range} už obsazená. | Vyber jiný termín, nebo podobnou motorku na stejný termín. | **Ukázat volné motorky** (free list for the same dates) · Změnit termín |
| 9.16 | C-05 | ✕ T2 + `stNoCharge` | V tom termínu už máš jinou rezervaci | Na tvoje údaje je ve stejném termínu jiná rezervace, třeba z webu. | Změň termín; když jde o omyl, napiš nám. | **Změnit termín** · Napsat nám |
| 9.17 | C-06 | ⚠ T2 | Pobočka má v těch dnech zavřeno | {branch} je {range} zavřená ({CMS season text, e.g. "zimní období od 1. 11. do 25. 3."}). | Vyber termín v sezóně. | **Změnit termín** |
| 9.18 | C-07 | ✕ T2 + `stNoCharge` | Tenhle kus teď nejde rezervovat | V termínu je přiřazený k jiné rezervaci. | Vyber jiný termín nebo motorku. | **Ukázat volné motorky** |
| 9.19 | C-08, C-09 | → 7.3, 7.4 (pre-check) | | | | |
| 9.20 | C-10 | ⚠ T2 | Ze samoobsluhy nepřistavujeme | Motorky z Velkých Němčic vyzvedneš i vrátíš jen na pobočce. | — | **Nastavit převzetí na pobočce** (one tap fixes it) |
| 9.21 | J-06 | ⚠ T2 | Motorka je v novém termínu obsazená | Ten termín má jiná rezervace. | Vyber jiný termín. | **Změnit termín** (offline → 8.3, never "obsazeno") |
| 9.22 | J-17 occupied | ⚠ T2 | Rezervaci už obnovit nejde | Termín {range} si mezitím rezervoval někdo jiný. | Najdi si jiný termín. | **Najít volný termín** |
| 9.23 | J-17 error | ✕ T2 | Obnovení se nepodařilo ověřit | Spojení selhalo, dostupnost nevíme. | Zkus to znovu. | **Zkusit znovu** |
| 9.24 | J-16 | ⌁ T2 | Termín už uplynul | Rezervaci z minulosti obnovit nejde. | — | **Rezervovat znovu** (→ Detail of the same bike) |

#### Group 10 · Čas na platbu a pokusy

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 10.1 | H-03 | ⌁ chip in the Booking header | Zbývá {mm:ss} na zaplacení | only for a new booking; paused ("Platba probíhá…") while a payment is in flight; never for edit or shop | — | — |
| 10.2 | H-03 last 5 min | ⚠ chip | Zbývá {mm:ss} — dokonči platbu | Pak se termín uvolní. | — | — |
| 10.3 | H-04 | ⚠ T1 | Čas na zaplacení vypršel | Nezaplacenou rezervaci držíme 30 minut, pak termín uvolníme pro ostatní. | Rezervuj znovu — motorka může být pořád volná. | **REZERVOVAT ZNOVU** (Detail with the same bike + dates) · Moje rezervace. Never fires while a payment is in flight. |
| 10.4 | H-05 new booking | ✕ T1 | Platba se nepovedla ani napotřetí | Rezervaci ti držíme do {time}, pak se termín uvolní. | 1. Zkus jinou kartu v Rezervacích (Dokončit rezervaci). 2. Nebo zavolej, pomůžeme. | **Přejít na rezervaci** · Zavolat |
| 10.5 | H-05 edit / swap | ✕ T1 | Doplatek se nepovedlo zaplatit | Změnu jsme neuložili, rezervace platí v původním termínu. | Zkus úpravu znovu s jinou kartou, nebo nám napiš. | **Zkusit úpravu znovu** · Napsat nám |
| 10.6 | H-06 | ⌁ T4 strip | Dokonči rezervaci · {mm:ss} | (status strip, + ✕) | — | tap → payment; ✕ → 10.7 |
| 10.7 | H-06 cancel | T6 | Zrušit nedokončenou rezervaci? | Termín se uvolní pro ostatní. Nic jsme nestrhli. | — | Nechat · **Zrušit rezervaci** (red) |
| 10.8 | H-06 cancel failed | ✕ T2 | Rezervaci se nepodařilo zrušit | Spojení selhalo. Nezaplacená rezervace se sama zruší v {time}. | Zkus to znovu, nebo ji nech propadnout. | **Zkusit znovu** |
| 10.9 | H-07 | ⌁ T3 on the card / detail | Zrušeno — nezaplaceno do 30 minut | Termín jsme uvolnili. | — | **Obnovit rezervaci** (one restore flow → 9.22 / 9.24 / payment) |
| 10.10 | H-08 | ⌁ labels | Zaplaceno · Čeká na platbu · Platba se ověřuje · Částečně vráceno · Vráceno | translated `payStatus*` keys; never "UNPAID" | — | — |

#### Group 11 · Doklady a údaje pro smlouvu

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 11.1 | B-03 | ⚠ T3 | V profilu nemáš řidičák | Na {bike} potřebuješ skupinu {license}. | Doplň řidičák v profilu, nebo si vyber motorku podle svého ŘP. | **Doplnit řidičák** · Motorky pro můj ŘP (8 languages; today cs only) |
| 11.2 | B-04 | ⚠ T3 | Na tuhle motorku tvůj řidičák nestačí | Máš {groups}, {bike} potřebuje {license}. | Vyber motorku, kterou můžeš řídit, nebo oprav skupiny v profilu. | **Motorky pro můj ŘP** · Upravit v profilu |
| 11.3 | B-08, C-03 | ⚠ T3 / T2 | Doplň pár údajů pro smlouvu | Chybí: {fields}. Foto dokladů můžeš nahrát i později. | — | **Doplnit údaje** (sheet with only the missing fields; returns to the form) |
| 11.4 | B-09 expiring | ⚠ T3 | Řidičák ti propadne během jízdy | Platí do {date}, pronájem končí {end}. | Po obnovení ŘP uprav platnost v profilu. | **Upravit platnost ŘP** |
| 11.5 | B-09 expired | ⚠ T3 | Řidičák už neplatí | Platnost skončila {date}. | Po obnovení ŘP uprav platnost v profilu. | **Upravit platnost ŘP** |
| 11.6 | M-01 | ⚠ T1 (scanner, with back) | Kamera není k dispozici | Telefon nám kameru nepůjčil — možná ji používá jiná aplikace. | Zavři jiné aplikace s kamerou, nebo nahraj fotky z galerie. | **Nahrát z galerie** · Zkusit znovu |
| 11.7 | M-02, M-03, (camera part of 15.6) | ⚠ T1 (scanner) | Appka nemá přístup ke kameře | Bez kamery doklady nenaskenujeme. | Povol kameru v nastavení, nebo nahraj fotky z galerie. | **Otevřít nastavení** · Nahrát z galerie (raw `CameraException` → tech) |
| 11.8 | M-04 | ✓ T2 | Fotka je uložená | Údaje jsme nepřečetli automaticky, ale doklad máme. | Kódy uvolníme po nahrání líce i rubu obou dokladů. | **Pokračovat** |
| 11.9 | M-05 | ✕ T2 | Fotku se nepodařilo odeslat | Spojení se při nahrávání přerušilo. | Zkus to znovu na lepším signálu. | **Zkusit znovu** (after 3× → 11.13); diagnostics → tech |
| 11.10 | M-06 network | ✕ T2 | Telefon je offline | Na rozpoznání dokladu potřebujeme internet. | Zapni data nebo Wi‑Fi a zkus to znovu. | **Zkusit znovu** |
| 11.11 | M-06 timeout | ✕ T2 | Rozpoznávání trvá moc dlouho | Server je teď pomalý. | Zkus to za chvilku znovu. | **Zkusit znovu** |
| 11.12 | M-06 server / config / upstream / empty / image prep | ✕ T2 | Rozpoznávání teď nefunguje | Chyba je u nás, ne v tvé fotce. | Zkus to později, nebo fotku pošli a údaje ověříme ručně. | **Zkusit znovu** · Poslat fotku k ruční kontrole |
| 11.13 | M-06 × 3 | ⌁ T2 | Pomůžeme ti osobně | (`scanHelpTitle` meaning) Skenování se několikrát nepovedlo. | Zavolej nebo napiš, doklady vyřešíme spolu. | **Zavolat** · Napsat nám · Zkusit přesto · Zavřít skener |
| 11.14 | M-07 | ⚠ T3 in the scanner | Na téhle straně nic nepřečteme | (`scanMissing*` tykání: e.g. "Na přední straně ŘP chybí číslo nebo platnost.") | Vyfoť ji znovu: celou, ostře a bez odlesků (`scanGuide*`). | **Vyfotit znovu** |
| 11.15 | M-08 | ⚠ T1 | Chybí ještě {missing} | Kódy k pobočce pošleme, až budeme mít líc i rub občanky (nebo pasu) a řidičáku. | — | **Vyfotit {missing}** (jumps to that step, not Home) · Později |
| 11.16 | M-09 age | ✕ T1 | Kódy zatím uvolnit nemůžeme | Z dokladu vychází, že ti ještě není 18 let. | Pokud jde o chybu čtení, vyfoť doklad znovu. Jinak nám napiš. | **Vyfotit znovu** · Napsat nám |
| 11.17 | M-09 expired licence | ✕ T1 | Kódy zatím uvolnit nemůžeme | Řidičák propadl {date}. | Po obnovení ŘP ho vyfoť znovu. | **Vyfotit znovu** · Napsat nám |
| 11.18 | M-09 group | ✕ T1 | Kódy zatím uvolnit nemůžeme | Skupina na řidičáku ({groups}) nestačí na {bike}. | Vyměň motorku za takovou, kterou můžeš řídit, nebo nám napiš. | **Motorky pro můj ŘP** · Napsat nám |
| 11.19 | M-10 | ✓ T5 / ✕ T2 | Doklad je smazaný · nahraj nový / Doklad se nepodařilo smazat | (failure: Spojení selhalo.) | — | failure: **Zkusit znovu** |
| 11.20 | J-19 withheld | ⚠ T3 (never titled "Chyba") | Kódy čekají na doklady | server reason (`awaitingDocs`) | — | **Nahrát doklady a uvolnit kódy** |
| 11.21 | J-19 protocol | ⌁ T3 | Nejdřív podepiš předávací protokol | Podepisuje se na displeji pobočky, pak se kóje motorky otevře. (`protocolFirst`) | — | Jak to probíhá › |
| 11.22 | J-19 released | ✓ T5 | Kódy jsou uvolněné | — | — | Zobrazit kódy |
| 11.23 | J-19 still withheld | ⚠ T3 | Kódy se ještě neuvolnily | `codesStillWithheld` reason | — | **Nahrát doklady** |
| 11.24 | J-19 load error | ✕ T3 | Kódy se nepodařilo načíst | Spojení selhalo. | Zkus to znovu; na pobočce ti pomůžeme i po telefonu. | **Zkusit znovu** · Zavolat |
| 11.25 | G-15 | ✓ T1 | Doklady máš nahrané | Ověřili jsme je; kódy dostaneš před začátkem rezervace. | — | **Zpět na rezervaci** (not blindly Home) |

#### Group 12 · Úpravy rezervace a storno

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 12.1 | J-01 | ⚠ T3 | Konec je před začátkem | Takový termín nejde uložit. | — | **Vybrat termín** |
| 12.2 | J-02 | ⌁ T3 | U probíhající rezervace začátek nezměníš | Motorku už máš. | Prodloužit nebo zkrátit můžeš konec. | **Upravit konec** |
| 12.3 | J-03 | → 9.8 | | | | |
| 12.4 | J-04 | ⚠ T3 | Zadej adresu přistavení | Bez ní nespočítáme cenu ani čas. | — | **Zadat adresu** (jumps to the field) |
| 12.5 | J-05 | → 9.11 | | | | |
| 12.6 | J-07 | ⌁ T2 | Rezervace se mezitím změnila | Upravil ji někdo na webu nebo v jiném telefonu. Načetli jsme aktuální stav. | Zopakuj úpravu. | **Upravit znovu** |
| 12.7 | J-08 | ✕ T2 | Doplňky se nenačetly | Bez nich úpravu bezpečně neuložíme. | Otevři úpravu znovu. | **Načíst znovu** |
| 12.8 | J-09 | → payment groups 2–7; < 15 Kč → group 6 | | | | |
| 12.9 | J-10 | ✕ T2 | Změnu se nepodařilo uložit | Rezervace zůstala beze změny. | Zkus to znovu. | **Zkusit znovu** (after a paid surcharge → 2.7, never this) |
| 12.10 | J-11 occupied | ⚠ T2 | V tom termínu je motorka obsazená | Posun potřebuje volnou celou délku rezervace. | Vyber jiný den. | **Změnit termín** |
| 12.11 | J-11 customer overlap | → 9.16 | | | | |
| 12.12 | J-11 length / past | ⚠ T2 | Takhle posunout nejde | (`moveErrLength` / `cannotSelectPast` meaning, tykání) | Vyber jiný den. | **Změnit termín** |
| 12.13 | J-11 unknown | ✕ T2 | Posun se nepovedl | Server ho odmítl bez udání důvodu. | Zkus jiný termín; když to nepůjde, napiš nám. | **Změnit termín** · Napsat nám (replaces "Chyba / Chyba") |
| 12.14 | J-12 swap: not upcoming | ⚠ T2 | Výměna jde jen u nadcházející nebo probíhající rezervace | — | — | **Otevřít rezervaci** |
| 12.15 | J-12 swap: unpaid | ⚠ T2 | Nejdřív je potřeba rezervaci zaplatit | Výměnu uděláme až po platbě. | — | **Zaplatit** |
| 12.16 | J-12 swap: bike unusable / occupied after swap | ⚠ T2 | Tuhle motorku na výměnu použít nejde | Je v servisu nebo v úseku po výměně obsazená. | Vyber jinou. | **Vybrat jinou motorku** |
| 12.17 | J-12 swap: date outside | ⚠ T2 | Datum výměny musí být v termínu rezervace | — | — | **Změnit datum** |
| 12.18 | J-12 swap: already swapped | ⌁ T2 | Výměna už na rezervaci proběhla | Druhou rezervaci najdeš v přehledu. | — | **Moje rezervace** |
| 12.19 | J-12 swap: licence | → 11.2 | | | | |
| 12.20 | J-12 swap: unknown | ✕ T2 | Výměna se nepovedla | Server ji odmítl bez udání důvodu. | Napiš nám, dořešíme to. | **Napsat nám** |
| 12.21 | J-13 | T6 | Zrušit rezervaci? | Teď ti vrátíme {pct} % · {amount} Kč. Storno podmínky: víc než 7 dní předem 100 % · 2–7 dní 50 % · méně než 2 dny 0 %. (+ optional reason field) | — | Nechat rezervaci · **Stornovat** (red) |
| 12.22 | J-14, G-14 (new) | ✓ T1 (light hero, no rank) | Rezervace je stornovaná | Storno #{id} máme. Podle storno podmínek ti vrátíme {amount} Kč ({pct} %). | Peníze přijdou na kartu, kterou se platilo, obvykle do [5–10 pracovních dnů · ověřit]. | **Moje rezervace** · Rezervovat jiný termín. 0 % variant: "Podle storno podmínek se tentokrát nic nevrací (méně než 2 dny před začátkem)." |
| 12.23 | J-15 | ✕ T2 | Storno se nepovedlo | Rezervace pořád platí, nic se nezměnilo. | Zkus to znovu; když to nepůjde, zavolej nám. | **Zkusit znovu** · Zavolat (no "Chyba storna: Chyba storna: …") |
| 12.24 | J-18 contract | ⌁ T3 | Smlouvu ještě chystáme | Najdeš ji tady, jakmile bude hotová, a pošleme ji i e-mailem. [kdy · ověřit] | — | — |
| 12.25 | J-18 invoice | ⌁ T3 | Konečnou fakturu vystavíme po vrácení motorky | [ověřit] | — | — |
| 12.26 | J-18 load error | → 8.6 ("Smlouvu / Fakturu se nepodařilo načíst") | | | | |

#### Group 13 · E-shop a poukazy (behind `eshop_visible`, live off)

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 13.1 | L-01 | ⌁ T3 | Košík je prázdný | Vyber si zboží nebo dárkový poukaz. | — | **Do e-shopu** |
| 13.2 | L-02 | ⚠ T3 | Doplň doručovací údaje | Chybí: {fields}. | — | **Doplnit** (jumps) |
| 13.3 | L-03 | ⚠ inline | promo texts in tykání ("Kód {code} už je použitý", "Slevový kód na dárkový poukaz použít nejde", …); success "Sleva {value} je uplatněná" | | | |
| 13.4 | L-04 out of stock | ⚠ T2 + `stNoCharge` | Něco už není skladem | {item} teď nemáme v požadovaném množství. | Uprav košík. | **Upravit košík** |
| 13.5 | L-04 unavailable / voucher not allowed | ⚠ T2 + `stNoCharge` | Tohle teď koupit nejde | (`shopProductUnavailable` / `shopVoucherNotAllowed` meaning) | Uprav košík. | **Upravit košík** · Odebrat poukaz |
| 13.6 | L-05 | ✕ T2 + `stNoCharge` | Objednávku se nepodařilo vytvořit | Spojení selhalo. | Zkus to znovu — objednávku nezaložíme dvakrát. | **Zkusit znovu** (same order key) |
| 13.7 | L-06 `amount_mismatch` | ⚠ T2 + `stNoCharge` | Cena objednávky se přepočítala | Teď vychází na {amount} Kč. | — | **Pokračovat za {amount} Kč** · Zpět do košíku |
| 13.8 | L-06 `already_paid` | ✓ T1 | Objednávka už je zaplacená | Podruhé ti nic nestrhneme. | — | **ZPĚT DO E-SHOPU** |
| 13.9 | L-06 `no_payment_needed` | ✓ T1 | Platit nic nemusíš | Sleva nebo poukaz pokryl celou objednávku. | — | **ZPĚT DO E-SHOPU** |
| 13.10 | L-06 `below_minimum` | → 6.6 | | | | |
| 13.11 | L-06 `wrong_status`, `order_not_found`, `forbidden` | → 7.2 / 7.6 / 7.8 with "objednávka" wording | | | | |
| 13.12 | L-07 | → groups 3 / 5 (retry reuses the same order) | | | | |
| 13.13 | L-08, L-09 | → 2.9 | | | | |
| 13.14 | L-10 | ✓ T5 | Poukaz je v košíku | — | — | Do košíku |

#### Group 14 · SOS (red system, never rank, never covered)

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 14.1 | N-01 | ⌁ hint in the form | Popis a fotky nám pomůžou rychle reagovat | (`sosReportRequiredHint` tykání) | — | — |
| 14.2 | N-02 | ⏳ in the send button | Odesílám na centrálu… | — | — | after 10 s → 14.3 |
| 14.3 | N-03 | SOS T2 (red header) | Hlášení se nepodařilo odeslat | Telefon se nespojil se serverem. Hlášení jsme uložili v telefonu a odešle se samo, jakmile chytíš signál. | Zavolej nám hned, jsme tu nonstop. | **Zavolat +420 774 256 271** (red) · Poslat SMS [návrh, prefilled text + GPS] · Zkusit odeslat znovu |
| 14.4 | N-04 | ⚠ T2 | Hlášení máme, fotky ne | Incident je nahlášený, jen se nepodařilo nahrát fotky. | Doplň je v detailu incidentu, až bude lepší signál. | **Doplnit fotky** · Hotovo |
| 14.5 | N-05 | ⚠ T2 | Fotku se nepodařilo pořídit | Kamera ani galerie teď nefungují. | Zkus to znovu. Když to nepůjde, pošli hlášení bez fotek a doplň je později. | **Zkusit znovu** · Poslat bez fotek [owner decision §9 #9] |
| 14.6 | N-06, G-11 | ✓ T1 (SOS done screens) | Incident je nahlášený | (existing done screens, SOS board) | — | — |
| 14.7 | N-07 ok | ✓ T3 | Poloha odeslána · {time} | MotoGo24 ví, kde jsi (přesnost ± {m} m). | — | — |
| 14.8 | N-07 denied | ⚠ T3 | Polohu jsme neposlali | Appka nemá přístup k poloze. | Povol polohu, nebo nám zavolej a místo popiš. | **Povolit polohu** · Zavolat |
| 14.9 | N-07 services off | ⚠ T3 | Poloha je v telefonu vypnutá | Bez ní tvou pozici neuvidíme. | Zapni polohu, nebo zavolej. | **Zapnout polohu** · Zavolat |
| 14.10 | N-07 failed | ✕ T3 | Polohu se nepodařilo odeslat | Telefon je bez internetu. | Zavolej nám a řekni, kde jsi. | **Zavolat** (red) · Zkusit znovu |
| 14.11 | N-08 | ⚠ T3 in the report | Hlášení odejde bez polohy | Bez polohy tě hůř najdeme. | Povol polohu, nebo místo popiš do zprávy. | **Povolit polohu** |
| 14.12 | N-09 | ⚠ T3 | Vyber náhradní motorku / Incident už není aktivní | (second: Mezitím se uzavřel.) | — | **Otevřít SOS znovu** · Zavolat |
| 14.13 | N-10 | ⚠ T3 | Náhradní motorka teď není volná | Na tvém místě a v tvém termínu žádnou k dispozici nemáme. | Zavolej nám, domluvíme jiné řešení. | **Zavolat +420 774 256 271** (tappable, red) |
| 14.14 | N-11 | ✕ T3 | Náhradní motorky se nenačetly | Spojení selhalo. | Zkus to znovu, nebo zavolej. | **Zkusit znovu** · Zavolat |
| 14.15 | N-12 (+ dormant G-05 `PaymentFlowType.sos` result) | ✓ T1 | Náhradní motorka je objednaná | Přivezeme ji zdarma na {address}. | — | **Hotovo** |
| 14.16 | N-13 | ✓ T1 | Odtah je objednaný | MotoGo24 zařídí odtah motorky. Počkej, až se ozve asistent. | — | **Hotovo** |
| 14.17 | N-14 | ✓ T1 | Krádež je nahlášená | Nezapomeň ji ohlásit i policii na lince 158. | — | **Zavolat 158** · Hotovo |
| 14.18 | N-15 ok | ✓ T1 | Fakturu máme | Proplatíme ji do 7 dnů od doručení. | — | **Hotovo** |
| 14.19 | N-15 failed | ✕ T2 | Fakturu se nepodařilo nahrát | Spojení selhalo. | Zkus to znovu, nebo ji pošli na info@motogo24.cz. | **Zkusit znovu** · Poslat e-mailem |
| 14.20 | N-17 | SOS T2 (SOS board `ofl` design) | Jsi offline — volat jde i teď | Hlášení odešleme, až chytíš signál. | — | 155 · 158 · 112 · **MotoGo24 nonstop** (call buttons) |
| 14.21 | N-16 | ⌁ T4 | Máš aktivní SOS incident | — | — | **Otevřít** |

#### Group 15 · Oprávnění

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 15.1 | location pre-prompt | ⌁ T2 | Potřebujeme tvoji polohu | per use: "Jen během jízdy, abychom nakreslili trasu." / "Abychom tě vedli po trase." / "Abychom ti seřadili místa od nejbližších." / "Aby tě MotoGo24 rychle našla." | — | **Pokračovat** (→ system dialog) · Teď ne |
| 15.2 | location denied | ⚠ T2 | Bez polohy to nepůjde | {feature} potřebuje přístup k poloze. | — | **Povolit znovu** · Teď ne |
| 15.3 | location denied forever | ⚠ T2 | Poloha je pro MotoGo24 zakázaná | Změnit to jde jen v nastavení telefonu. | Nastavení → Oprávnění → Poloha → Povolit. | **Otevřít nastavení** · Teď ne |
| 15.4 | services off | ⚠ T2 | Poloha v telefonu je vypnutá | {feature} bez ní nefunguje. | — | **Zapnout polohu** |
| 15.5 | iOS approximate | ⚠ T2 | Zapni přesnou polohu | S přibližnou polohou trasu ani navigaci neuděláme. | Nastavení → MotoGo24 → Poloha → Přesná poloha. | **Otevřít nastavení** |
| 15.6 | O-05 navigation denied | ⚠ T3 over the map | Navigace potřebuje polohu | Bez ní nevíme, kde jsi. | Povol polohu (no silent jump to settings before this explanation). | **Povolit polohu** / **Otevřít nastavení** (forever) |
| 15.7 | camera (M-02, M-03, N-05) | → 11.7 / 14.5 | | | | |
| 15.8 | notifications off | ⌁ T3 | Oznámení máš vypnutá | Nepřijdou ti zprávy od MotoGo24 do telefonu (e-mail a SMS chodí dál). | Povol oznámení v nastavení. | **Otevřít nastavení** · Teď ne |
| 15.9 | background location lost | → §4.4 #19 | | | | |
| 15.10 | R-15 | ⌁ link | Každý stav oprávnění končí odkazem "Všechna oprávnění ›" → `/permissions` | | | |

#### Group 16 · Záznam jízdy a navigace

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 16.1–16.19 | O-01, O-02 (split), O-03, O-04, recorder | §4.4 #1–#19 | | | | |
| 16.20 | O-06 locating | ⏳ chip | Hledám polohu… | (`routeNavLocating`) | — | — |
| 16.21 | O-06 off route | ⌁ chip | Mimo trasu — přepočítávám | (`routeNavOffRoute`) | — | — |
| 16.22 | O-06 GPS lost (new) | ⚠ T3 on the map | Ztratili jsme signál GPS | Trasu ti držíme, jeď dál podle mapy. | — | (auto-recovers) |
| 16.23 | O-06 location turned off mid-ride (new) | ⚠ T3 | Poloha se vypnula | Navigace bez ní nepojede. | — | **Zapnout polohu** |
| 16.24 | offline in navigation | ⌁ chip | Offline · trasa je uložená v telefonu | — | — | (never a full overlay) |
| 16.25 | O-07 saved | ✓ T5 | Uloženo do Mých zážitků | — | — | Zobrazit |
| 16.26 | O-07 save / submit error | ✕ T2 | Trasu se nepodařilo uložit / Návrh se nepodařilo odeslat | Spojení selhalo, rozdělaná práce ti zůstává. | Zkus to znovu. | **Zkusit znovu** |
| 16.27 | O-07 decode | ⚠ T3 | Odkaz se nepodařilo načíst | Odkaz nevede na trasu. | Vlož odkaz na trasu z Mapy.com nebo Google Maps. | **Vložit jiný odkaz** |
| 16.28 | O-07 points | ⚠ T3 | Přidej aspoň 2 body | Trasa potřebuje začátek a konec. | — | — |
| 16.29 | O-07 login | ⌁ T3 | Přihlas se a pošli návrh | (fixes "Přihlas se a ohodnoť") | — | **Přihlásit se** |
| 16.30 | O-08 | ⚠ T2 | Sdílení se nepovedlo | Aplikace pro sdílení se neotevřela. | Zkopíruj odkaz a pošli ho, kam potřebuješ. | **Zkopírovat odkaz** |
| 16.31 | O-09 | ⚠ T3 | Trasu po silnici se nepodařilo spočítat | Mapová služba teď neodpovídá — ukazujeme přímé spojnice. | Zkus to za chvilku. | **Zkusit znovu** |
| 16.32 | O-10 | ✕ T3 | Trasy se nepodařilo načíst | (`routesError` — the good model) | — | **Zkusit znovu** |

#### Group 17 · AI, zprávy a hodnocení

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 17.1 | P-01 | ⏳ typing dots in the chat | Přemýšlím… (no emoji) | after 20 s: "Ještě chvilku…" | — | after 45 s → 17.2 |
| 17.2 | P-01 timeout | ✕ bot bubble | AI teď neodpovídá | Dotaz trvá moc dlouho. | — | **Zkusit znovu** (resends, no retyping) · Napsat lidem (Zprávy with the question) |
| 17.3 | P-02 offline | ✕ bubble | Bez internetu ti AI neodpoví | — | — | **Odeslat znovu** |
| 17.4 | P-02 rate limit | ⚠ bubble | Moc dotazů najednou | Chvilku počkej. | — | **Odeslat znovu** |
| 17.5 | P-02 server | ✕ bubble | AI má výpadek | — | Zkus to později, nebo napiš lidem. | **Napsat lidem** · Odeslat znovu |
| 17.6 | P-03 | ⌁ bubble | Na tohle neumím odpovědět | — | Zkus otázku napsat jinak, nebo se zeptej lidí. | **Napsat lidem** |
| 17.7 | P-04 | SOS card | AI doporučuje nahlásit SOS | (`aiSuggestSos` without emoji) | — | **Nahlásit SOS** (red) |
| 17.8 | P-05 | ⚠ T5 | Nejvýš 3 fotky na zprávu / Fotku se nepodařilo načíst | — | — | — |
| 17.9 | P-06 | ✕ inline under the bubble | Neodesláno | Zpráva zůstala v poli. | — | **Odeslat znovu** |
| 17.10 | P-07 | ⚠ inline | Napiš předmět konverzace | — | — | — |
| 17.11 | P-08 | → 8.6 "Zprávy se nepodařilo načíst" | | | | |
| 17.12 | P-09 | ✕ T3 in the review card | Hodnocení se neuložilo | Spojení selhalo. | — | **Zkusit znovu** |
| 17.13 | P-10 | ⚠ T5 | Odkaz se nepodařilo otevřít | — | — | Zkopírovat odkaz |
| 17.14 | P-11 | ⚠ inline / ✕ T3 | `rfEmpty` / `rfSendFailed` (tykání already) | | | **Odeslat znovu** |
| 17.15 | G-12 | ✓ review card | Díky za tvoje hodnocení! | (`rfThanksSub`) | — | **Napiš nám recenzi** · **Napiš nám přímo, co máme zlepšit** (exact wording, same look and order for 1–5★) |
| 17.16 | G-13 | ✓ T5 + note in the card | Odesláno, díky! | Zprávu máme – odpověď najdeš ve Zprávách. | — | Otevřít konverzaci |

#### Group 18 · Přihlášení a registrace

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 18.1 | Q-01 | ⚠ inline per field | Vyplň e-mail / Vyplň heslo | — | — | — |
| 18.2 | Q-02 | T6 | Účet s tímhle e-mailem nemáme | Zaregistruj se, zabere to pár minut. | — | Zrušit · **Zaregistrovat se** |
| 18.3 | Q-03 | ✕ T2 | E-mail nebo heslo nesedí | Zkontroluj překlepy a velká písmena. | — | **Zkusit znovu** · Poslat nové heslo |
| 18.4 | Q-04 | ⚠ T2 | Potvrď svůj e-mail | Poslali jsme ti odkaz na {email}. Mrkni i do spamu. | — | **Poslat odkaz znovu** [návrh] · Otevřít e-mail |
| 18.5 | Q-05 | → 8.12 | | | | |
| 18.6 | Q-06 login | ⚠ T2 | Moc pokusů za sebou | Z bezpečnostních důvodů chvíli počkej. | Zkus to za pár minut. | **Rozumím** · Poslat nové heslo (registration keeps its own wording) |
| 18.7 | Q-07 | T6 | Tenhle e-mail už účet má | Přihlas se; heslo si můžeš nechat poslat znovu. | — | **Přihlásit se** · Zapomenuté heslo |
| 18.8 | Q-08 | ✕ T2 | Heslo je moc slabé / E-mail nemá správný tvar / Chyba je na naší straně / Registraci se nepodařilo dokončit | (rule texts as today, tykání; raw detail → tech, copyable) | — | the wizard jumps to the faulty step |
| 18.9 | Q-09 | ⚠ inline | per field (`licenseMinValid`, `consentRequiredMsg`, tykání) | | | |
| 18.10 | Q-10 ok | ✓ T5 | Kód je na cestě | Poslali jsme ho na {email}. | — | — |
| 18.11 | Q-10 error | ✕ T2 | Kód se nepodařilo poslat | Server je teď nedostupný. | Zkus to za chvilku. | **Zkusit znovu** |
| 18.12 | Q-11 | ✕ T2 | Kód neplatí | Vypršel, nebo je v něm překlep. | Pošli si nový. | **Poslat nový kód** (mapped GoTrue codes: expired, invalid, weak, same password "Nové heslo musí být jiné než staré"; never raw English) |
| 18.13 | Q-12 cancelled | ⌁ T3 | Ověření je zrušené | — | — | **Přihlásit e-mailem** |
| 18.14 | Q-14 | ✕ T2 | Heslo se nepodařilo změnit | (mapped reason) | — | **Zkusit znovu** |

Registration texts switch from vykání to tykání throughout (Q-08 "jste zkoušeli" etc.).

#### Group 19 · Celá appka

| # | ID | Tón · plocha | Nadpis | Co a proč | Jak to vyřešit | Akce |
|---|---|---|---|---|---|---|
| 19.1 | R-02 | ✕ T1 (with ✕ close) | Tahle obrazovka spadla | Omlouváme se, při zobrazení se něco pokazilo. Tvoje data jsou v bezpečí. | — | **Zpět na Domů** · Zkusit znovu (re-mount) · Nahlásit chybu (log to `app_debug_logs`) |
| 19.2 | R-03 | ⚠ T1 (blocking) | Je potřeba aktualizovat | Verze {version} opravuje věci, bez kterých appka nefunguje správně. | — | **Aktualizovat** · during a rental always also **SOS a nonstop linka** (red) + "Kódy k pobočce" (cached) — never blocked |
| 19.3 | R-04 | ⌁ T6 | Je tu nová verze | — | — | Později · **Aktualizovat**; downloaded: T5 "Aktualizace je stažená" + Restartovat |
| 19.4 | R-05/06/07/08/11/13 | → 8.6 | | | | |
| 19.5 | R-09 | ✕ T1 with back | Profil se nepodařilo načíst | Server teď neodpovídá, nebo je slabý signál. | — | **Zkusit znovu** |
| 19.6 | R-10 | ✕ T1 with back | Produkt se nepodařilo načíst | as 19.5 | — | **Zkusit znovu** · Zpět do e-shopu |
| 19.7 | R-14 | ⌁ T1 | Tahle stránka v appce není | Odkaz je starý nebo neúplný. | — | **Na Domů** · Moje rezervace (GoRouter `errorBuilder`) |
| 19.8 | R-12 save | ✕ T2 | Změny se neuložily | Spojení selhalo. | — | **Zkusit znovu** |
| 19.9 | R-12 delete: active bookings | ⚠ T2 | Účet teď smazat nejde | Máš aktivní nebo nadcházející rezervaci. | Smazat ho půjde po jejím skončení. | **Moje rezervace** |
| 19.10 | R-12 delete failed | ✕ T2 | Účet se nepodařilo smazat | Spojení selhalo. | — | **Zkusit znovu** · Napsat nám |
| 19.11 | R-16 | ✓ T5 / ⌁ T3 | Jazyk je změněný · Uloženo · Během aktivní rezervace souhlasy odebrat nejde | — | — | — |
| 19.12 | G-16 | reference | Level-up celebration | **unchanged** (`loyalty_levelup_overlay.dart`) — never drawn as a state, never blocked by Stavy layers except where today's code blocks it | — | — |

### 5.5 Code requirements behind the states (port; the look alone cannot make them true)

| # | Requirement | Fixes |
|---|---|---|
| C1 | Map the Czech DB trigger texts to codes (`check_booking_overlap` "Překrývající se rezervace…", customer overlap, `check_booking_branch_open`, trailer assignment) — better: raise them with stable SQLSTATE / HINT codes server-side (SQL as text first, CLAUDE.md rule 3) | 9.15–9.18 (C-04…C-07) |
| C2 | Check the amount ≥ 15 Kč **before** the payment screen on every path; server guard `below_minimum` on booking, edit, swap and SOS paths in `process-payment` (today only the shop) | group 6 |
| C3 | Keep `error_code` in `PaymentResult.offSessionFailed`; map `expired_card`, `incorrect_cvc`, `authentication_required`, `amount_too_small`, `processing_error`; do not count a cancelled 3-D Secure as an attempt | 3.4, 3.5, 4.3, 4.4, 6.7 |
| C4 | Timeout / unexpected status / `processing` → pending + server check, never "nic nebylo strženo"; suppress the "Dokončit rezervaci" pay buttons while a payment is pending | 2.1–2.8 |
| C5 | Android card sheet non-dismissible during `confirmPayment` (port the iOS `_WalletGuard`) | 2.4 |
| C6 | Shop retries reuse the same order (idempotent order key) | 2.9, 13.6 |
| C7 | SOS location share returns an honest result (denied / off / failed / ok); incident creation queues offline and offers the call | 14.3, 14.7–14.10 |
| C8 | Replace the full-screen `OfflineGuard` with the banner; real reachability (`pingSupabase`); cached essentials stay usable; no SOS / call / navigation / recorder blocking; force update keeps SOS + codes | 8.1–8.5, 14.20, 19.2 |
| C9 | `ErrorWidget.builder` → 19.1; GoRouter `errorBuilder` → 19.7; profile / product error scaffolds with an app bar | 19.1, 19.5–19.7 |
| C10 | No raw `'$e'` in any customer text (Home, catalogue, detail, edit, swap, cancel, profile, reset, scanner diagnostics) | all "→ tech" notes |
| C11 | `bookedDatesProvider` error ≠ empty list; `checkMotoAvailability` network error ≠ "obsazeno"; `paymentMethodsProvider` error surfaced | 9.9, 9.21, 9.23 |
| C12 | Payment countdown pauses while a payment is in flight; no countdown for edit / shop | 10.1–10.3 |
| C13 | Cancel shows a confirmation with the refund (G-14) | 12.22 |
| C14 | `booking_validator.dart` messages in all 8 languages (today `translations['cs']`) | 9.3, 11.1, 11.2 |
| C15 | Translated payment status labels (`payStatus*`), no `toUpperCase()` raw | 10.10 |
| C16 | Scanner M-08 / M-09 return to the missing step, not Home | 11.15–11.18 |
| C17 | Recorder failure split into causes 2–8, honest background-location loss | §4.4 |
| C18 | Saved cards: `webhook-receiver` attaches the PaymentMethod to the Stripe customer after a successful payment (Android **and** iOS), but `process-payment` creates the PaymentIntent without `setup_future_usage` — attaching a method used once without it can be refused by Stripe, silently (only logged) [ověřit v Stripe logu]. Recommended: `setup_future_usage: 'off_session'` on PaymentIntents of customers who keep cards (edge function; text to the owner first). The iOS card-save copy stays — iOS has the saved-card list too; nothing is iOS-only here | 2.x, Profil › Platební metody |

### 5.6 Hang guards (every await bounded; values [návrh])

| Await (file) | Slow notice | Hard timeout → | Retry safety |
|---|---|---|---|
| `_createDraftBooking` insert (`payment_screen.dart:504`) | 10 s → 8.7 | 20 s → check by draft key → 8.13 or continue | client-generated draft key (UUID) so a retry never creates a second booking |
| `booking_discounts` insert (`:526`) | — | 15 s → log + continue (server validates the price) | — |
| post-payment `bookings.update` + `replaceModeledExtras` (`:1310–1320`) | — | 15 s → 2.7 (webhook is the backstop), never "uloženo" | — |
| `loadMotoPickupInfo` / `loadBookingPickupInfo` | — | 8 s → navigate without the branch block (it lives in the reservation) | — |
| `handleNextAction` / `confirmPayment` / `confirmPlatformPayPaymentIntent` | 4.1 | 120 s → 4.2 (check the PaymentIntent) | PaymentIntent id |
| `ai-moto-agent` invoke | 20 s "Ještě chvilku…" | 45 s → 17.2 | resend the same message |
| `createSosIncident` (+ `uploadSosPhotos` in the background) | 14.2 | 10 s → 14.3 (queued, call offered) | local incident id |
| `create_shop_order` RPC | 10 s → 8.7 | 15 s → 13.6 | order key |
| `cancel_booking_tracked` RPC | 8.7 | 15 s → re-read the booking → 12.22 or 12.23 | — |
| `split_booking_moto_swap` dry-run / commit | 8.7 | 20 s → re-read → 1.8 / 1.9 or 12.20 | — |
| `reschedule_booking_free` | 8.7 | 15 s → re-read → 1.14 or 12.13 | — |
| Payment countdown | — | pauses while `_processing` | — |
| Fire-and-forget (`_saveBookingExtras`, `EmailService`, `InvoiceService`) | — | errors logged to `app_debug_logs`, never silently "done" | — |

### 5.7 The board `Stavy.dc.html` (new)

- **Canvas:** title "13 · Stavy — výsledky, chyby, offline", 390 × **3660** (the orchestrator sets `canvas.json` — `dclint/canvas_sync.py`), x after the last board.
- **Props** (`data-props`):
  - `rank` int 1–20, default 3 (section "Rank");
  - `skupina` enum, default "1 · Hotovo" — options: "1 · Hotovo", "2 · Platba se ověřuje", "3 · Karta zamítnutá", "4 · Ověření v bance (3-D Secure)", "5 · Google Pay / Apple Pay", "6 · Částka pod 15 Kč", "7 · Server platbu odmítl", "8 · Připojení a přihlášení", "9 · Termín a motorka", "10 · Čas na platbu a pokusy", "11 · Doklady", "12 · Úpravy a storno", "13 · E-shop a poukazy", "14 · SOS", "15 · Oprávnění", "16 · Záznam jízdy a navigace", "17 · AI, zprávy, hodnocení", "18 · Přihlášení a registrace", "19 · Celá appka";
  - `varianta` int 1–40, default 1 (clamped to the group's count; label "Stav ve skupině");
  - `platforma` enum Android | iOS (wallet name, iOS card rules);
  - `jazyk` enum cs…uk (chrome and existing keys; new strings stay cs with a "návrh překladu" tag in the annotation);
  - `pseudo` boolean "Délková zkouška (+40 % textu)" — expands every string with accented filler to prove wrapping without clipping;
  - `levelUpDemo` enum (default Vypnuto) — blocked in the in-flight payment variants 2.3, 2.4, 4.1 (as the app blocks over payment);
  - `reducedMotion` boolean.
- **Layout:**
  - 0–844: the live phone. The variant is drawn over its real context (dimmed static mock of the screen it belongs to: Booking express summary for groups 2–7 and 10; Rezervace detail for 11–12; Domů for 8 and 19; SOS start for 14; Trasy for 15–16; AI chat for 17; login for 18; e-shop cart for 13).
  - 860–1260: "Karta stavu" annotation (dashed, "Poznámka k návrhu", clearly not app UI): ID + inventory reference, tone, template, trigger (code condition), keys (existing / new), hang guard, code requirement (§5.5), and "Dnes:" with today's text in grey for comparison.
  - 1280–end: the 19 group chips (horizontal scroll) + the group's variants as mini cards 171 × 128 in 2 columns (4 px tone stripe, 32 icon disc, title 12.5/800 max 2 lines, template tag 11/700, primary label 11.5/800). Tap = select (the phone cross-fades `enter` 450).
- **Interactions inside the phone:** "Zkusit znovu" → in-button spinner 1.2 s → next outcome (alternates success / same error); pending variants switch to success after 4 s (reduced motion: a button "Simulovat potvrzení"); "Technické detaily" expands; offline "Co funguje bez signálu ›" opens 8.2; dialogs confirm into their result; toasts near the tap; every back / close works (§6).
- **Loops:** at most the pending ring (live) + the success CTA glow; everything else one-shot.
- **Validate:** `lint.py` → LINT OK; `fuzz.js` → fuzz ok for `{}`, rank 1, 6, 10, 17, 19, 20, `{"reducedMotion":true}`, `{"platforma":"iOS"}`, `{"pseudo":true}`, and every `skupina` with `varianta` 1 and 32.

### 5.8 Reuse in the other boards (one copy source)

| Board · prop | Variants to draw with the §5 templates and copy |
|---|---|
| Booking `vysledekPlatby` | Projde → 1.1 · Zamítne banka → 3.6 · Nedostatek prostředků → 3.1 · Neprojde Google Pay / Apple Pay → 5.2 / 5.5 · Bez připojení → 8.3 · Vyprší čas → 10.3; **add** "Platba se ověřuje" (2.1), "Ověření v bance zrušené" (4.4), "Motorku mezitím někdo rezervoval" (9.15), "Poukaz nechá 1–14 Kč" (6.5), "Napotřetí neprošla" (10.4) |
| Booking `stavProfilu` | Chybí velikost bot → in-card amber row (V2) · Chybí doklady → note · Bez uložené karty → card sheet · Chybí údaje pro smlouvu → 11.3 sheet · Termín se kryje → 9.3 |
| Booking success `sx` | 1.1 (tykání, number, calendar link) |
| Reservation `upravaChyba` | Rezervace se mezitím změnila → 12.6 · Automatická vratka selhala → 1.12; **add** "Doplatek pod 15 Kč" (6.1), "Storno potvrzeno" (12.22), "Storno se nepovedlo" (12.23) |
| Reservation `obnoveni` | Motorka volná → payment · Termín už uplynul → 9.24 · Motorka obsazená → 9.22; **add** "Chyba ověření" (9.23) |
| Reservation `kodyChyba` | 11.24; codes withheld 11.20 |
| MotoDetail `stav` | Obsazená v termínu / Přes limit dní → calendar states + 9.5 · Překryv s jinou rezervací → 9.3 · Řidičák nestačí → 11.2 |
| Kalkulačka `stav` | Načítání / Chyba obsazenosti → §3.3 + 9.9 · Věrnost nedostupná → V21 §3.4 row |
| Main `nabidka` | Vše rozpůjčené → V21 §4.6 · Věrnost nedostupná · Mimo sezónu → 9.17 copy |
| Every board `stavDat` | Načítání → skeleton (one shimmer) · Chyba sítě → 8.6 · **Bez připojení → 8.1 banner + cached content** (replaces the full-screen overlays `ofl` / `off-g`) |
| `globalniStav` (Katalog, Profil, Reservation, TrasyHub, Zazitky) | Rozdělaná platba → 10.6 · storno selže → 10.8 · SOS náhrada čeká → 14.21-style strip |
| SOS `nahradni` | Žádná dostupná → 14.13 · Chyba načítání → 14.14 |
| Profil `stav` "Chyba načítání" | 19.5 · scanner screens → 11.6–11.18 · payment methods → 3.12 / 3.13 |
| TrasaDetail "Navigace · poloha zakázána" | 15.6; **add** "Navigace · bez signálu GPS" (16.22) |
| Zazitky "Záznam jízdy" | §4.4 |

---
## 6. Back / close standard (R6)

Owner 2026-10-16: "aby tam vždycky bylo dobře viditelné tlačítko zpět a z každé obrazovky se dalo jít zpět." One component `MgBackButton` (Flutter) / `shared/back.html` (boards).

### 6.1 The control

- **Disc 44 × 44** (hit area 48), icon 24 on the 24 grid, stroke 2, round caps: **‹ chevron** (`M15 18l-6-6 6-6`) = go back one step; **✕** = close a modal / viewer / result and leave the flow. Never a text glyph "×".
- **Position:** screens → top-left at **x 16, y 55** (status bar 47 + 8); sheets → top-right, inset 12, next to the title row (+ the grabber). The disc stays pinned when a header collapses; nothing (FAB, chip, sticky bar, SOS pill) may sit within 8 px of it.
- **Styles by surface** (contrast measured):

  | Surface | Disc | Ring / shadow | Icon | Contrast |
  |---|---|---|---|---|
  | Over a photo or map | `night`@.80 (`rgba(10,31,20,.8)`) + blur 12 | 1 px `white@.25` + `0 4px 12px -4px rgba(0,0,0,.5)` | white | icon vs disc ≥ 9.2 : 1 even over a white photo (disc composite `#3B4C43`); the ring keeps the edge visible over dark photos |
  | Dark header / dark sheet | `white@.10` | 1 px `white@.25` | white | ≥ 13 : 1 on `#0E2A1C` |
  | Light screen / light sheet | `#FFFFFF` | 1 px `line #E2EAE5` + `shIcon` | `#1A2E22` | 14.4 : 1 |

- Pressed: scale .92 + disc +8 % white / ink; haptic `selectionClick`. Focus: neon 3 px ring on dark, 2 px `#0D6E0D` on light.
- Semantics label: existing `back` "Zpět" / `close` "Zavřít" (8 languages) + tooltip on long-press.
- Title next to the back disc: 17/800, one line; if it does not fit → 15/800 on two lines (never an ellipsis on a navigation title).

### 6.2 Per screen type

| Screen type | Examples | Control | System back (Android) / iOS edge swipe |
|---|---|---|---|
| Tab root | Domů, Motorky (incl. Kalkulačka mode), Rezervace, Trasy, Profil | none — the nav is the way out. **Exception:** when a tab is opened by a cross-tab jump with context (Domů funnel → Kalkulačka prefilled; Profil → Pobočka → "REZERVOVAT ZDE" → Motorky filtered; Home "Všechny trasy" → Trasy), a back chip "‹ {Domů / Pobočka}" sits top-left in the header until the customer switches tabs | platform default (non-Home tab → Domů; Domů → leave the app) |
| Pushed screen, dark header | Profil sub-screens, Zprávy, vlákno, Moje doklady, Faktury, Smlouvy, Platební metody, Oprávnění, Pobočky, SOS screens, Trasy sub-screens, Moje rezervace list from a push | ‹ dark style | pop |
| Pushed over a photo / map hero | Detail motorky, Detail rezervace, Pobočka detail, Detail trasy, Detail jízdy, Detail místa (full) | ‹ photo style | pop |
| Focused flow | `/booking`, payment, úprava rezervace, výměna, Plánovač, Navrhnout trasu, Přidat místo, Osobní údaje edit | ‹ (surface style). Unsaved input → T6 "Zahodit rozdělané změny?" (Pokračovat v úpravách · Zahodit). **Payment in flight:** the disc stays visible but inactive and a tap shows "Platba právě probíhá — počkej pár vteřin" (the only allowed block) | same as the visible control |
| Live full-screen (dark) | Navigace, Záznam jízdy, Skenování, Kódy na celou obrazovku | ‹ dark style — going back **keeps the process running** (navigation, recording); ending is a separate explicit action (red ✕ "Ukončit trasu?", ■ "Ukončit záznam") | back = keep running + leave |
| Viewer | foto na celou obrazovku, mapa na celou obrazovku, video, DocWebView / PDF | ✕ photo style | close |
| Result screen | `/success`, `/payment-result`, every Stavy T1 | ✕ (dark or light style) → the flow's defined destination (Rezervace, rezervace detail, e-shop, Domů) | = ✕ |
| Bottom sheet | all sheets (filters, calendar, receipt, sizes, address, Stavy T2) | ✕ 44 top-right + grabber + swipe-down + scrim tap; dirty form → T6; payment in flight → locked with the line (Stavy 2.4) | closes the sheet |
| Dialog | confirmations (T6) | the explicit safe button ("Zrušit" / "Nechat") | = safe button |
| AI chat panel | | ✕ 44 icon (today a "×" glyph) top-right | collapses to the FAB |
| Global strips / offline banner | | ✕ only when dismissible | — |
| Level-up celebration | | **unchanged**: "Pokračovat" (+ the system back closes it, as today) | as today |

### 6.3 Audit of the boards (grep 2026-10-16)

| Board | Today | Fix |
|---|---|---|
| MotoDetail | back `.gls.bk` 44 but `rgba(10,31,20,.5)` over the photo; pager + fav glass the same; 7 sheet closes `.xb` **40 px** | photo style @.8 + ring for back, pager arrows and fav; `.xb` → 44 |
| Reservation | photo back `.bk` @.5; light sheet closes `.xb` **40 px**; `.ed-bk` 44 ✓ | photo style; `.xb` → 44 |
| Booking | header back `.bb` 44 with a neon@.28 border; 7 `.xb` **40 px** | dark style (white@.25 ring); `.xb` → 44; success `sx` gets ✕ top-left |
| Profil | app-bar `.bk` 44 (neon@.22 border); scanner back ✓ | dark style; check every `obrazovka` has the app bar (AI asistent, Smazat účet dialog, E-shop) |
| SOS | header `.bk` 44 ✓ | dark style; the SOS root keeps back (it is pushed) |
| TrasaDetail | map discs `.nb` white 44 ✓ (light style); navigation back ✓ | "Detail trasy · fotky v záhlaví" → photo style; photo viewer ✕ photo style |
| TrasyHub | map back `.gb` 44 ✓; place sheet close `.ib.xb` 44 ✓ | styles as §6.1 |
| Zazitky | `.gb` 44 ✓ on ride detail, map, submit | the recorder (now a sheet) becomes a full screen with ‹ |
| Kalkulačka | tab mode, 2 sheet closes | cross-tab back chip when entered from Domů; sheet closes 44 |
| MotoKatalog | tab root; filter sheet close; calc mode "Zpět na nabídku" link ✓ | sheet close 44 |
| Main | tab root; 10 sheet closes (aria "Zavřít") | verify 44 and the light style (sheets turn light) |
| RankStyly | storyboard viewer, rules sheet | ✕ 44 |
| Shared AI chat | `.ai-x` 44 "×" glyph | icon ✕ |

---

### 6.4 Shared parts added by the shared fixer (2026-10-16)

- **AI on focused screens** (`shared/ai-fab.html` PART 3, class `.ai-tb`): route navigation (all 15 states), planner, POI pick, Navrhnout trasu / Přidat místo, ride recorder, ride detail, place / route maps (TrasyHub, Zazitky), the address map picker — a 44 px disc as the LAST item of the top bar; the chat opens inside the same viewport (`bottom` = viewport + 24). Hidden only under modal sheets / dialogs.
- **Address sheet + map picker** (`shared/addr-picker.html` + `.js`, Booking / Reservation · Úprava · Místo / SOS · Náhradní motorka): typing with suggestions (Mapy.cz Suggest), GPS (busy / off / denied / no fix with manual entry), fullscreen map (pin, „Hledám adresu…“, my location 48), confirmed address with „Počítám km…“ → „~[km] km po silnici z … · fee“ (1 000 Kč + 40 Kč/km; SOS without fee), ONE ink primary „Potvrdit adresu“, close / back 44. Prop „Výběr adresy“ on each board.
- **Payment screen modes** (Booking prop „Režim platby“): new · resume (30-min countdown) · restore · edit surcharge · swap surcharge · SOS; every „Otevírám platbu…“ toast (Home ticket, status strip, Reservation) now names this state (board 5).
- **Foreground push banner** (`shared/push-banner.html` + `.js`, Main + Reservation, prop „Push“): door codes = green frame, key, title + 4 lines, 8 s, „Zobrazit“ → Zprávy ?n=; message = night banner, 2 lines, 5 s; rank ring rule + rank-coloured action; ✕ and action 44; layer 52.
- **Akce selhala** (Zazitky + TrasaDetail, Stavy 16.33–16.37): ride delete / save, stop save (text stays), saved-route delete, photo pick (permission → Otevřít nastavení).
- **Language + length test on every board:** prop `jazyk` translates headings, section heads, CTA / dock / chip labels and ticket headlines (exact cs value of an app key → all 8 languages; short hand list → en/de/fr/uk; static markup headings are holes `{{ L.sN }}`); prop `pseudo` = +40 % accented filler on every visible string. Remaining copy = **[překlad v portu]** (DB / CMS content: moto features, branch texts, route and place names stay as data).
- **r2 (shared fixer, second pass 2026-10-16):** Silnice CTA fill 1–5 takes 65 % / 90 % of the rank colour in its first two stops (`research/rankTheme.js` `ROAD_W`, was 30 % / 70 %) → every painted rank token now meets ΔE00 ≥ 10 for every pair and ≥ 12 for neighbours, CTA fill included (4↔5 9.0 → 12.4; `gen/contrast.md`); re-embedded in all 13 boards. i18n: 61 more hand-translated UI labels (`scratchpad/fixshared/r2/i18n/hand2.py`) and static labels next to an icon (missed by r1) now become `L.sN` holes. Full-screen viewers (photo, route map) keep only their ✕ — like modal sheets they hide the AI disc; every navigable full screen has it. Card saving on iOS verified (§7.4 #4).

## 7. Detail fixes per board (from the owner's remarks)

Every board also gets: the re-embed (§0.3 step 0); the §2.1 tokens; meta `#55705F` on light; the R6 controls; `stavDat` "Bez připojení" as the 8.1 banner instead of a full-screen overlay; no raw "Chyba: [technický popis chyby]" in a body.

### 7.1 Main (Domů)
1. Header compact ≤ 190 and the winter banner as its last line; remove the dark `.mqw` strip (R5).
2. Funnel overlaps the header −24 and becomes photo-led (358 × 200 carousel); card ends ≈ 600 with the CTA above the fold (R5).
3. New light block under the hero: ½ offer box (the screen's one `tintFeature`), "Spočítat přesnou cenu" + "Všechny motorky" rows with `iconTileDark`, season note `#55705F`.
4. "Moje zážitky" → full-bleed white band; **row 1 "Zaznamenat jízdu"** (§4.2 B); tiles `well`; remove "Nahrát jízdu" from the Soukromé jízdy tile (R3).
5. Pobočky: Mezná white, Velké Němčice dark (web P5).
6. Tvůj klub: name and next-rank line in ink; tier bar on `well`; tier rail swatches as dark mini discs (§1.4).
7. Date sheet: light skin + uniform band; remove `.dc.dr` (.24) and the `.dc.ds` gradient; today ring + dot; "Tvoje jiná jízda" dashed amber (R4).
8. Colours: `#6C8A7B` ×7 → `#55705F`; `#CFE3DA` ×9 → `lineInput` on input-like controls, `line` elsewhere; `#8FB3A1` (×5) only on dark carriers.
9. S2 "Dokonči platbu": while a payment is pending the ticket shows 2.1 "Platbu ověřujeme" and hides the pay CTA (R2).
10. S8 ticket line "● Záznam jízdy z výpůjčky běží · [km] km"; Home row in automatic state (R3).
11. `stavDat` "Chyba sítě" → 8.6 per section ("Motorky se nepodařilo načíst · Zkusit znovu"); "Bez připojení" → 8.1 banner; the board's full-screen `ofl` overlay goes.
12. New prop `nahravani` (Ne / Automaticky / Ručně) for row B.
13. Check ranks 1, 15, 17, 19, 20 on the header, funnel CTA and nav pill.

### 7.2 MotoKatalog
1. Winter notice `.ntc` → the header's last line.
2. Grid view on canvas with white card bodies; price `#0D6E0D`.
3. Error `.est` → 8.6 ("Motorky se teď nepodařilo načíst · Termín, filtry i oblíbené ti zůstanou" — keep that reassurance as the "why" second sentence); offline `.off-g` → 8.1 banner over cached cards.
4. Filter sheet: chips `well`, selected `btnInk`; sheet close 44.
5. Calc mode `.kcs` → the Kalkulačka light layout.
6. First-card CTA check on bright photos for ranks 7, 9, 19 (edge visible).

### 7.3 MotoDetail
1. Back, pager and fav: photo style @.8 + ring (R6).
2. Sheet white; spec tiles + V kostce `well`; units `#55705F` (R5).
3. "Tvoje jízda": light step rows + dark total box (decision §9 #3).
4. Date sheet `.sheet.shd.dk` → light skin + uniform band; remove `.cd.rg` / `.cd.sl` (R4).
5. Seven `.xb` closes 40 → 44.
6. `stav` "Překryv s jinou rezervací" → 9.3 (with "Otevřít rezervaci"); "Řidičák nestačí" → 11.2 (with "Motorky pro můj ŘP"); "Přes limit dní" → 9.5.
7. `stavDat` error: "Motorku se nepodařilo načíst" + "Zkusit znovu" + "Zpět na Motorky"; the raw line moves to Technické detaily.
8. Sticky dock unchanged (REZERVOVAT · 10 189 Kč); check 15/16 white label, 17 ivory.

### 7.4 Booking (Rezervace expres)
1. Page `.wash` → canvas; gear chips `well`; `--meta #7C958A` / `--tert #6C8A7B` → `#55705F`.
2. Payment error sheet `.perr` → T2 (tone disc, title, why, steps, `stAttempt` + `stNoCharge` chips, primary / secondary, tykání support row, Technické detaily); remove "Potřebujete pomoc? Napište nám na info@motogo24.cz".
3. `vysledekPlatby`: map and extend per §5.8 (+ 2.1, 4.4, 9.15, 6.5, 10.4).
4. **iOS wallet sheet copy is wrong**: "Na iPhonu platíš přes Apple Pay — kartu tu ručně nezadáváš." The iOS checkout sheet has Apple Pay **and** a card field (`card_payment_sheet.dart` iOS); only the profile screen has no manual entry. Draw Apple Pay + "nebo zaplať kartou" + CardField, and keep "Kartu si uložíme pro příště" only on Android if that is what the code does [ověřit] → **ověřeno (shared fixer r2): platí na obou platformách** — `webhook-receiver` po `payment_intent.succeeded` kartu připojí ke Stripe zákazníkovi (`paymentMethods.attach` + `syncCardsForCustomer`) bez ohledu na platformu a iOS appka to sama slibuje (iOS-only klíč `cardsSavedAtCheckout`: „Kartu uložíš přímo při placení rezervace.“ / en „Your card is saved automatically when you pay for a booking.“); věta zůstává i na iOS.
5. Android wallet sheet: locked while confirming (2.4).
6. ⏱ countdown pauses during a payment; not shown for edits.
7. Success `sx` → 1.1: tykání throughout, booking number, "Přidat do kalendáře" (decision), ✕ top-left.
8. Seven `.xb` 40 → 44; header back dark style.
9. Total 0 → "POTVRDIT OBJEDNÁVKU (ZDARMA)" unchanged; remainder 1–14 Kč → 6.5.

### 7.5 Reservation (Správa rezervace)
1. `--page #DFF0EC` → canvas; `--ter` (×6) → `#55705F`; chips `well`.
2. Photo back @.5 → photo style; light `.xb` 40 → 44.
3. Edit calendar: `.ed-d.keep` (mint) + `.ed-d.en` (neon) + `.ed-d.old` → one uniform band with "+" on added days and red dashed removed days; legend "Přidáš / Ubereš" (R4).
4. `upravaChyba`, `obnoveni`, `kodyChyba` per §5.8; add the storno result (12.22) and storno failure (12.23).
5. Payment status labels translated (10.10).
6. "Čeká na platbu": when pending → 2.1 badge, pay hidden.
7. Timeline nodes light (§2.4).
8. Codes withheld title "Kódy čekají na doklady", never "Chyba" (11.20).
9. "Probíhá": CO TEĎ recording line (§4.2 C).
10. Contract / invoice not ready → 12.24 / 12.25.

### 7.6 Kalkulačka
1. Light step cards + dark total block + dark sticky dock (decision §9 #2).
2. Branch segments on a `well` track, selected `btnInk`; step badges dark discs.
3. Calendar light skin; remove `.cd.in` (.24) and `.cd.en` gradient (R4).
4. "Chyba obsazenosti": prices hidden, banner 9.9, REZERVOVAT disabled until loaded (no silent all-free).
5. `#8FB3A1` (×9) stays only on the dark total block; on light → `#55705F`.
6. Cross-tab back chip "‹ Domů" when opened from the funnel (R6).
7. Rank chip in the light head as a dark pill + dot.

### 7.7 Profil
1. Canvas; `--meta` (×20) → `#55705F`; `#7C958A` (×2); input borders `#CFE3DA` (×18) → `lineInput` on inputs, `line` elsewhere.
2. Section label gutter 16 (MŮJ ÚČET / NASTAVENÍ were flush at x = 0).
3. "NAHRÁT DOKLADY" rank CTA moves into the dark header (rank only on dark carriers).
4. Payment methods: default card dark, others white (R5.2); E-13 → 3.12 / 3.13; load error 8.6.
5. "Chyba načítání" → 19.5 with an app bar back and "Zkusit znovu".
6. Scanner: 11.6 / 11.7 with "Otevřít nastavení" + "Nahrát z galerie"; diagnostics hidden in Technické detaily; M-08 / M-09 go to the missing step (11.15–11.18).
7. Zprávy: send failure inline "Neodesláno · Odeslat znovu" (17.9); list error 8.6.
8. P4 ladder: new colours grouped by tier; tier headers; check every level renders with its own `rk rk-N` wrapper.
9. Odhlásit se / Smazat účet `#B42318`; delete-account states 19.9 / 19.10.
10. Permission rows link every state to `/permissions` (15.10).

### 7.8 TrasyHub
1. Canvas; `--ter` (×14) and `--meta #7C958A` (×3) → `#55705F`.
2. Category chips white + `line`, counts in `well` pills.
3. Map "Přidat místo" → white disc (neon reserved for the record dock).
4. **Record dock** on all three segments + docked AI; dock priority (live → selection → idle); props `nahravani`, new `vyber` (R3).
5. Recording no longer in the `.lvw` strip on Trasy (the dock carries it).
6. Login prompt in the "+" sheet: "Přihlas se a pošli návrh" + "Přihlásit se" (16.29).

### 7.9 Zazitky
1. Summary card → white (1 284 km ink, split bar, `well` tiles, compact rank row); "VYTVOŘIT NOVOU TRASU" → `btnInk`; ghost record button removed (R5, R3).
2. `--ter` (×21), `--meta` → `#55705F`.
3. "Záznam jízdy · panel" → full-screen recorder (§4.2 D) with prop `zaznamStav` (§4.4).
4. Record dock on Moje sub-screens.
5. Ride share failure 16.30; save / submit errors 16.26.

### 7.10 TrasaDetail
1. Canvas; `--ter` (×10), `#7C958A` (×5) → `#55705F`.
2. Navigace · poloha zakázána → 15.6 with buttons; add "Navigace · bez signálu GPS" (16.22) and "Poloha se vypnula" (16.23); offline in navigation = chip only (16.24).
3. "● REC" chip on navigation screens while recording (prop `nahravani`).
4. Photo-header back → photo style; photo viewer ✕ photo style.
5. Submit / decode / login copy per 16.26–16.29.

### 7.11 SOS
1. Canvas; `--ter` (×5) → `#55705F`.
2. Honest location share 14.7–14.10 (replaces the always-"Poloha sdílena").
3. Send failure 14.3 with red "Zavolat" + queue; photo failure 14.5 (decision §9 #9); no-replacement number tappable 14.13; load error 14.14.
4. Offline layer keeps the calls (14.20); never covered by the update dialog (19.2).
5. Done screens: neon ✓ hero without rank aura.

### 7.12 RankStyly
1. Re-embed + §1.6 copy edits; tier overview with the 20-swatch ramp strip.
2. Light sections → canvas / white; `--ter` (×6) → `#55705F`; rank CTA demos on dark docks.
3. Storyboard unchanged; new prop `opravaD1` (default false) for the owner to compare D1.

### 7.13 Stavy (new)
Build per §5.7; it is the reference every other board's state props copy from.

---

## 8. Port notes (Flutter; next step = Android)

- **Scope requested by the owner:** "dotáhni do finále a nasaď na android verzi". The v2 UI goes to `motogo-app-flutter` behind the kill-switch `app_v2_ui` (release 4.2.0 prep). **Flag for the orchestrator:** CLAUDE.md requires every shared change in both trees in the same commit (`diff -rq lib/`); an Android-only UI port must either stay behind the flag in both trees or be ported to iOS right after — that decision is not part of this spec. Whatever the order, the rank SQL waits for both trees (§1.7).
- **New / changed Flutter units** (each file < 5 000 tokens):
  - `core/theme_v2.dart`: §2.1 tokens (`canvas`, `well`, `line`, `lineInput`, `meta #55705F`, `tintOk`, `tintFeature`, `dock`, `iconTileDark/Light`, `eyebrowDark`) + `btnInk`, `btnGhostLight`, `btnText` styles; `MotoGoColors.bg` stays for legacy screens; `calRange` removed.
  - `core/rank_theme.dart` (solver port of `research/rankTheme.js`, new SEED) + `features/loyalty` A1–C (§1.7).
  - `core/widgets/v2/mg_back_button.dart` (§6).
  - `core/widgets/v2/trip_calendar.dart` + `trip_range_painter.dart` (§3) replacing `availability_calendar.dart` / `edit_reservation_calendar.dart` behaviour.
  - `features/routes/record_dock.dart`, `features/routes/recorder_screen.dart` (route `/ride-recorder`), Home row in `features/home/home_v2/*` (§4).
  - `core/widgets/v2/state_view.dart` (T1 screen, T2 sheet, T3 banner, T4 strip; tones), `core/states/state_catalog.dart` (ID → tone, template, keys, actions), `core/net/guarded.dart` (timeouts of §5.6), `core/offline_banner.dart` replacing the `OfflineGuard` overlay (C8), `ErrorWidget.builder` and GoRouter `errorBuilder` (C9).
  - `features/payment/payment_error_mapper.dart` extended (C1–C4); `widgets/card_payment_sheet.dart` Android guard (C5).
  - i18n: new `st*`, `rideRecShort`, `rideRecStopShort` and the [návrh] strings in 8 languages, split per group (`translations_ext_37_states_<group>.dart` …), informal register (§5.3).
- **Server / SQL (text to the owner first, CLAUDE.md rule 3):** the rank ramp SQL (§1.7); `below_minimum` guard on all `process-payment` paths (edge function, C2); optionally stable error codes for the booking triggers (C1). Edge deploys and SQL go live on merge to `main`.
- **iOS pins** (connectivity_plus ^5, flutter_stripe ^11, geolocator ^10 …) are untouched by this spec: no new APIs are needed (permission helpers `GpsService.ensurePermission`, `Geolocator.openLocationSettings` / `openAppSettings` already exist).

---

## 9. Owner decisions (v2.2)

1. **Rank colours:** approve `sql/20261016_loyalty_colors_ramp.sql` + the app fixes A1–C in both trees; release order app (Android + iOS) → SQL.
2. **Kalkulačka:** light steps + dark total / CTA (recommended) or keep the web-like all-dark card?
3. **Detail "Tvoje jízda":** light steps + dark total (recommended) or dark card?
4. **Home header:** compact dark rank header (recommended) or a light header like the web?
5. **Level-up D1** ("Pokračovat" / "+N" text colour by contrast; nothing else changes) — and optionally D3 (no violet → new morph on the first celebration after the switch). Without D1 eight levels get white-on-light text. The rank SQL (#1) waits for this decision in **both** trees: it ships only after D1 is decided and, if approved, released in Android and iOS (§1.7 release order).
6. **"Zaznamenat jízdu":** record dock as the Trasy tab's primary + new short key `rideRecShort` (recommended).
7. **Web parity:** the same uniform calendar band on the web (`landing-calc.css`, `rezervace-v2.css`) as a separate task?
8. **Payments under 15 Kč:** A waive the difference (recommended) · B round up to 15 Kč · C settle at the branch (Mezná only).
9. **SOS photo:** allow sending the report without photos when the camera fails ("doplníš později") + an SMS fallback when sending fails (recommended).
10. **Offline:** replace the full-screen block with the banner + "Co funguje bez signálu" (recommended, safety).
11. **Force update during a rental:** keep SOS, the nonstop line and the cached codes reachable (recommended).
12. **Refund timing text:** "obvykle do 5–10 pracovních dnů" — confirm or give the real wording.
13. **Register:** new state strings informal in all 8 languages (de *du*, fr *tu*, …), matching the newer keys.
14. **Contract and invoice timing** texts (12.24 / 12.25): when exactly are they issued?
15. **Success screen:** add "Přidat do kalendáře"?
16. **Payment methods:** default card dark, other cards white (R5.2) — OK?
17. **Pending payment window:** how long the app waits before 2.2 "Platbu pořád nevidíme" ([10 min] proposed).
18. **Level-up timing during SOS (L5, SOS board prop `oslava`):** keep today's trigger — the unchanged celebration plays over SOS on the next touch (board default "Jako dnes") — or add `/sos/*` to `_blockedByOverlay` so it waits and catches up on the first touch after SOS closes. The celebration itself stays untouched either way ("lvl up video neměň").

---

## 10. Validation checklist (boards)

1. Re-embed done; grep every board: `#FF5A0C #8A9A3B #B39E7E #F43F5E #6366F1 #8B5CF6 #A855F7 #D946EF #9CA3AF` = 0 rank uses (§1.6).
2. Grep for `#DFF0EC`, `#6C8A7B`, `#7C958A`, `rgba(116,251,113,.24)`, `rgba(116,251,113,.28)` = 0 outside legacy / focus examples; `--page`, `--ter`, `--tert`, `--meta` values updated.
3. Re-run `sbal/comp.py` on every board: first viewport dark ≤ 45 % (photo separate), white + canvas ≥ 55 %, green ≤ 20 %, neon ≤ 5 % (exempt list R5.4).
4. Every calendar: start, middle and end cells share one fill (`#74FB71`), contour `#1F9A4A` on light, no per-cell alpha.
5. Every screen / sheet / viewer of every `obrazovka` value has a 44 px back or close (§6.3 list).
6. Trasy: record dock on all three segments; live bar with `nahravani`; recorder states reachable by prop.
7. Stavy: every group × variant renders; `pseudo` shows no clipping or overlap; only tone colours on state icons.
8. `python3 dclint/lint.py <file>` → **LINT OK**; `node dclint/fuzz.js <file> '<props>'` → **fuzz ok** for `{}`, `{"rank":1}`, 6, 10, 17, 19, 20, `{"reducedMotion":true}`, every `obrazovka` / `stav` / `skupina` value (Stavy: `varianta` 1 and 32), `{"pseudo":true}`, `{"platforma":"iOS"}`, `levelUpDemo` "+2 ranky (výhra měsíce)" where present, and RankStyly `{"opravaD1":true}`. Do not render or screenshot.
