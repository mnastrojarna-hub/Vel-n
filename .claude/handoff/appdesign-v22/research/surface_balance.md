# Surface balance: light vs dark, contrast, calendar range, "Zaznamenat jízdu"

Research for owner points **R5** (not too green-and-black, too dark or monotonous; white backgrounds in places; more contrast where there are many graphic elements), **R4** (calendar: every selected day in one uniform green) and **R3** (a clearly visible "Zaznamenat jízdu" button). Written 2026-10-16, read-only research. No repo or board files were edited.

**Evidence.** Everything was measured at 390 px. Paths are relative to the scratchpad folder `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/`.

- **Web v2:** the PHP dev server on :8171, rendered with Playwright as an iPhone viewport in cs. Screenshots are in `sbal/shots/{home,katalog,detail,rezervace,pobocky,postup,prevzeti,kontakt}-full.png`, with contact sheets `sbal/shots/sheet-*.png`.
- **App boards:** all 12 boards in `appdesign/project`, rendered with the board mini-renderer (`sbal/mr.js`, a copy of `appdesign/gen/minirender.js`) with default props and `reducedMotion`. Outputs are `sbal/boards/*.png` and `sbal/sh/*.png`.
  - The mini-renderer is approximate: the giant chevron on Main and the squeezed "U Mezné je [n] míst" are renderer artefacts, not design bugs.
- **Tools:**
  - `sbal/comp.py`: pixel composition by class (dark / white / mint / mid-green / neon / other = photos and other hues).
  - `sbal/lum.py`: bands.
  - `sbal/cr.py`: WCAG contrast.
  - `sbal/measure_rec.js`: label widths in Montserrat.
  - `sbal/blocks.js`: block y-ranges of a rendered board.

---

## 0. Decisions in one screen

1. **The page background stops being mint.** 10 of the 12 boards paint the page `#DFF0EC`. Web v2 landing pages paint it `#FFFFFF` and the reservation form uses a near-white wash. New `canvas` = **`#F4F7F5`** (neutral, faint green-grey) with **white `#FFFFFF` cards and full-bleed white bands**. Mint tints are allowed only for state (checked, positive) and for at most one feature box per screen.
2. **Dark is a hero, not a page.**
   - At most one dark block in any phone-height window, besides the chrome (header band, dock, nav).
   - Dark blocks are separated by at least one light section.
   - Header + hero merge into one unit: the hero overlaps the header by −24 px, as web `.lp-panel` does with `margin-top:-2.25rem`. There is never a dark → dark strip → dark stack (Home today: header 0–247, banner strip 259–291, funnel 303–895).
3. **Forms, lists, steps and settings are light; photos, live states and the one hero are dark.**
   - **Kalkulačka** changes from one continuous dark section (y 197–2588) to light step cards with a dark total + CTA block.
   - **Moje zážitky:** the big dark summary card becomes white.
   - Catalogue and detail photo heroes stay dark. The owner said these are fine.
4. **The rank CTA always sits on a dark carrier** (hero card, dock, dark sheet).
   - On light surfaces only secondary buttons are used: ink `#1A2E22` + neon label (web `.lp-moto-book`), a white ghost with a `#0D6E0D` border, or a text link.
   - This keeps silver, platinum and ivory ranks readable and the glow visible.
5. **Contrast fixes on light surfaces.**
   - Meta/tertiary text `#6C8A7B` / `#7C958A` (3.2–3.8 : 1, below AA) → **`#55705F`** (5.43 on white, 5.03 on canvas).
   - Input borders `#CFE3DA` (≈1.3 : 1) → **1.5 px `#7C958A`** (3.22 : 1).
   - On light surfaces the green for links, prices and ✓ is always `#0D6E0D`, never neon (neon on white = 1.33 : 1).
6. **Calendar (R4):** start, every day in between and end form **one continuous solid band of `#74FB71`**, the same fill for every selected day.
   - On the light skin the band has a 1.5 px `#1F9A4A` contour (3.63 : 1).
   - Ink day numbers.
   - Today = dot + ring.
   - Busy days hatched and struck through, pending days dashed amber, past and out-of-limit days dimmed.
   - The same fix is needed on the web, where in-range days are 1.94 : 1 against the dark calendar while start and end are 11.55 : 1. That is exactly the "only first and last day glow" the owner saw.
7. **"Zaznamenat jízdu" (R3)** has three placements:
   - **Trasy tab:** a bottom **dock** on all three segments, `[⏺ ZAZNAMENAT JÍZDU] + docked AI`, as the tab's primary action.
   - **Home:** the first row of the white "Moje zážitky" band.
   - **Recorder:** a full-screen dark recorder screen.
   - While recording: a live bar in the dock and a global status strip on other tabs.
   - 18 states are specified (§6), including every permission and failure path.

---

## 1. How web v2 balances surfaces (the reference)

### 1.1 Measured composition

Pixel share; the "other" column is mostly photos. The footer is cut off; it is a dark 2 200 px block on every page.

| Page (390 px) | dark | white | mint | mid-green | neon | other |
|---|---|---|---|---|---|---|
| `/` home | 28.9 | 33.9 | 10.0 | 8.3 | 3.2 | 15.8 |
| `/katalog` | 8.0 | 55.5 | 5.3 | 4.8 | 1.4 | 25.0 |
| `/katalog/:id` detail | 15.4 | 58.0 | 8.3 | 4.0 | 1.1 | 13.3 |
| `/rezervace` | 12.2 | 63.4 | 12.8 | 4.2 | 1.6 | 5.8 |
| `/pobocky` | 19.8 | 49.3 | 6.1 | 6.8 | 2.7 | 15.4 |
| `/jak-pujcit/postup` | 35.2 | 36.5 | 3.6 | 9.9 | 3.4 | 11.4 |
| `/kontakt` | 15.3 | 56.9 | 5.4 | 4.7 | 2.2 | 15.5 |

First viewport (0–844) on the web:

| Page | dark | white | mint | mid-green | neon | photo |
|---|---|---|---|---|---|---|
| home | 34 | 10 | 2 | 13 | 5.5 | 35.5 |
| katalog | 16 | 49 | 12 | 10 | 5 | 8 |
| detail | 34 | 12 | 11 | 10 | 4 | 28 |
| rezervace | 31 | 22 | 25 | 12 | 4 | 6 |

**Reading:**

- Web v2 is **white-dominant**: 34–63 % of the scroll is neutral white.
- Dark is 8–35 % of the scroll and at most ~40 % of the first screen.
- Where the first screen is dark, a **photo carries a third of it**.
- Neon stays at 1–5.5 %.
- The page background is pure `#FFFFFF` on landing pages (sampled at the gutter). `/rezervace` uses the wash `#EAF6EF → #F5FAF7` (sampled `#EEF4F0` / `#F3F8F5`).

### 1.2 Patterns to take over

| # | Web pattern (CSS) | What it does | App translation |
|---|---|---|---|
| P1 | Light header bar (white/mint, dark text, neon "Stáhnout" pill) → full-bleed **photo hero** → **dark panel card overlapping by −2.25rem** (`.lp-panel`, `.lp-panel-card` radial `#24563B → #0E2A1C → #0A1F14`, inset neon @.25 ring, 3 px scan line) | The first screen is photo + one dark card. Everything below is white. | Home: dark rank header (kept for rank) + funnel hero overlapping −24, made photo-led; light content right below. |
| P2 | Light **offer box** right under the dark panel (`.lp-offer-in`: gradient `#e6fae2 → #f6fff4`, 1 px **dashed `#37CF63`**, 38 px neon % disc with ink "%") | Positive accent on light, the single tinted box | The "½ Vyzvedni od 12:00" row moves out of the dark funnel into this light box (the one allowed feature tint). |
| P3 | **Full-bleed dark band** once per page (`.lp-reasons`, radial glows, tiles `rgba(255,255,255,.06)`, neon icon tiles) | One deliberate dark rhythm break between white sections | Allowed once lower on long screens, e.g. the Velké Němčice branch card on Home. |
| P4 | **White cards on white** with 1 px `#d4e8e0` border + long soft shadow `0 14px 34px -18px rgba(26,46,34,.45)` (`.pb-card`, `.km`, `.rez-section`) | Separation without tint | `surface` cards with `line` border + `shCard`. |
| P5 | **Alternating light/dark cards** in a list (`.pb-card` white for Mezná, `.pb-card--self` dark for Velké Němčice) | Rhythm and meaning (self-service = "night/kiosk") | Home Pobočky: Mezná white, Velké Němčice dark. |
| P6 | **Dark eyebrow pill on light** (`.lp-rt-eyebrow`: `#0e2a1c` bg, neon text, 0.72 rem 800 caps) and **dark icon tile on light** (`.lp-rt-ico` 40 px r12 `#0e2a1c` + neon icon) | Brand accent on light with 11.5 : 1 contrast, no green wash | Section eyebrows and leading feature icons on light. |
| P7 | **One mint feature box per page** (`.lp-rt-box` 160°: `#eafbf0 → #d9f5e4`) | The "green" moment is contained | `tintFeature`, at most one per screen. |
| P8 | **Dark calculator / total inside light** (`.kc-card` dark, but `.kc-sum-in` receipt `#fff`, `.kc-total` dark radial inside the white receipt) | Money moment = dark, explanation = white | Total box dark, everything else light (§4.4). |
| P9 | On light, the "book" action on fleet cards = **ink pill** `#1a2e22` + neon label (`.lp-moto-book`); neon gradient buttons on light appear only inside CTA cards | Neon is never a lone fill on white | Secondary actions on light = `btnInk`. |
| P10 | Mobile **sticky bar** `rgba(10,31,20,.95)` + blur (`.lp-sticky`: REZERVOVAT \| MOTORKY) | Dark only at the bottom edge | `dock` on light screens. |

The web palette tally (all v2 CSS files) confirms this. Backgrounds are `#fff` ×56, then `#74fb71` ×35 (buttons and chips), `#1a2e22` ×25 (ink buttons), `#0e2a1c` ×14. The mint tiles `#f3fbf7` / `#e6f5ee` / `#eef7f2` / `#f7fcf9` appear only 3–4× each.

---

## 2. The app boards today: where it is too green, too dark, monotonous or low in contrast

### 2.1 Measured composition (default props)

| Board | dark | white | mint | mid-green | neon | other | Page background at the gutter |
|---|---|---|---|---|---|---|---|
| Main (Domů) | 21.0 | 22.2 | **34.2** | 10.4 | 1.7 | 10.6 | `#DFF0EC` |
| MotoKatalog | 33.8 | 0.6 | 0.1 | 11.5 | 3.7 | 50.2 (photos) | dark |
| MotoDetail | 27.2 | 17.7 | **22.1** | 11.4 | 2.3 | 19.3 | sheet `#DFF0EC` |
| Kalkulacka | **57.4** | 15.3 | 2.3 | 14.1 | 2.8 | 8.2 | dark `#091D13` |
| Booking | 25.4 | 44.1 | 4.7 | 10.5 | 6.6 | 8.7 | wash |
| Reservation | 18.2 | 33.0 | 18.9 | 13.1 | 2.8 | 14.0 | `#DFF0EC` |
| Profil | 14.5 | 49.7 | 22.5 | 5.5 | 0.3 | 7.6 | `#DFF0EC` |
| TrasyHub | 12.0 | 43.6 | 15.8 | 5.4 | 0.7 | 22.4 | `#DFF0EC` |
| Zazitky | 30.2 | 31.5 | 13.2 | 14.0 | 2.6 | 8.7 | `#DFF0EC` |
| TrasaDetail | 18.5 | 22.0 | 15.5 | 7.2 | 2.2 | 34.5 | `#DFF0EC` |
| SOS | 11.0 | 25.1 | 17.5 | 2.1 | 0.2 | 44.2 (red, photos) | `#DFF0EC` |
| RankStyly | 23.3 | 15.2 | 26.1 | 11.7 | 1.9 | 21.8 | `#DFF0EC` |

First viewport (0–844), the screen the owner actually looks at:

| Board | dark | white | mint | mid-green | neon | other |
|---|---|---|---|---|---|---|
| **Main** | **47.6** | **0.7** | 8.0 | **28.2** | 5.2 | 10.2 |
| **Kalkulacka** | **59.9** | **0.4** | 0.3 | **30.1** | 2.1 | 7.1 |
| **Zazitky** | **46.5** | 9.3 | 4.1 | **28.1** | 6.7 | 5.2 |
| Reservation | 22.4 | **0.6** | 22.6 | 25.5 | 2.7 | 26.2 |
| Profil | 34.2 | 27.2 | 16.6 | 14.5 | 0.8 | 6.7 |
| MotoDetail | 28.7 | 5.8 | 10.6 | 13.8 | 0.6 | 40.6 |
| TrasaDetail | 26.0 | 20.0 | 16.0 | 14.1 | 1.1 | 22.8 |
| TrasyHub | 20.0 | 39.2 | 17.3 | 10.2 | 1.7 | 11.4 |
| Booking | 27.3 | 40.2 | 5.0 | 11.6 | 6.7 | 9.2 |
| SOS | 16.4 | 41.5 | 8.2 | 3.8 | 0.0 | 30.2 |
| MotoKatalog | 37.4 | 0.7 | 0.1 | 13.2 | 4.0 | 44.6 |

Half-screen profile (D = dark %, W = white %, G = green-tinted %):

- **Web home:** D23 W15 G22 · D40 W03 G19 · D28 W32 G24 · D15 W43 G08 · **D67** · **D78** · D19 W61 · …
  - Dark arrives in blocks and white returns every 1–2 half-screens.
- **App Main:** D49 W00 G38 · D44 W00 G42 · D08 W41 G38 · D05 W51 G29 · … · D00 W06 **G93** · D33 W00 G57.
  - The first screen has no white, and the rest is green-tinted.
- **Kalkulačka:** D54 · D62 · D78 · D69 · D22 · D32 · D71 · D99.
  - Six of eight half-screens are dark.

### 2.2 Diagnosis

**Too green**

1. The mint page `#DFF0EC` covers 30–57 % of the gutters on Main, Profil, TrasyHub, Reservation, Zazitky and TrasaDetail. White cards sit on it, and mint icon tiles (`#EEF7F2`), mint chips and mint tiles sit on the cards. The result is green on green on green.
   - The web avoids this with a white page.
2. Mid-green glass (`rgba(116,251,113,.1–.24)`) and green text are layered inside dark cards. That is 28–30 % of the first viewport on Main, Kalkulačka and Zazitky.

**Too dark or monotonous**

1. **Main:** three dark blocks are stacked in the first 900 px: header 0–247, CMS banner strip 259–291 (`#0E2A1C`), funnel 303–895. Separated by 12 px mint gaps, they read as stripes.
   - The funnel hides the secondary links (½ from 12:00, Spočítat přesnou cenu, Všechny motorky, season note, demo note) inside the dark card, which stretches it to 592 px.
2. **Kalkulačka:** one dark section from 197 to 2588 (2 391 px).
   - Glass cards are nested inside it (`.pk` .07, `.mc` .06, `.cbx` .04, `.sum` .05). That is three levels of dark.
   - Only the receipt is white.
3. **Zazitky (Moje):** the dark header (0–190) is followed immediately by the dark "Moje zážitky" card (≈200–830). The whole first screen is dark.
   - Further down, the dark "Tvoje stopy" map card is a second dark hero.
4. **MotoDetail:** the photo hero (0–560) is followed by the mint sheet, which contains the ~1 000 px dark "Tvoje jízda" card (steps, chips, total).
   - The owner accepts the photo screens, but this card is the "many graphic elements" area.
5. **Main Pobočky:** both branch cards are dark with `[fotka pobočky]` placeholders, so the lower page ends in dark tiles plus the dark nav.

**Low contrast (fails WCAG AA for text under 18.66 px bold)**

| Colour | Where | On white | On canvas | On mint `#DFF0EC` |
|---|---|---|---|---|
| `#6C8A7B` (`--meta` in Profil ×20; `--ter` in Zazitky ×21, TrasyHub ×14, TrasaDetail ×10, RankStyly ×6, Reservation ×6, SOS ×5; hex in Main ×7) | meta lines, captions | 3.78 ✗ | 3.50 ✗ | 3.20 ✗ |
| `#7C958A` (`--meta` in TrasyHub and Zazitky; hex in TrasaDetail ×5, Zazitky ×4, TrasyHub ×3, Profil ×2) | captions, timestamps | 3.22 ✗ | 2.98 ✗ | 2.73 ✗ |
| `#8FB3A1` on light | rare | — | — | 1.95 ✗ |
| Input border `#CFE3DA` | forms | ≈1.3 ✗ (1.4.11 needs 3:1) | | |
| Neon `#74FB71` as text, edge or fill on light | — | 1.33 ✗ | 1.23 ✗ | |
| Calendar in-range `.24` over `#0E2A1C` (= `#265C30`) vs the calendar background | MotoDetail `.cd.rg`, Kalkulačka `.cd.in`, web | 1.94 : 1 ✗ (start/end: 11.55 : 1) | | |

On dark surfaces the text tokens are all fine: `#8FB3A1` is 6.68 on `#0E2A1C` (the lowest), `#9FC4B1` is 8.05 and neon is 11.55, or 6.39 over the `#24563B` aura.

---

## 3. Surface system for the app (`MotoGoV2`, both trees)

### 3.1 Surface tokens (new or changed; dark tokens unchanged)

| Token | Value | Role | Replaces |
|---|---|---|---|
| `canvas` | **`#F4F7F5`** | Page background of every light screen: tab roots, lists, forms, sheets under photo heroes, Profil, Trasy, Reservation, Booking, Kalkulačka | `page` `#DFF0EC`, `pageWash` (`MotoGoColors.bg` today) |
| `surface` | `#FFFFFF` | Cards, grouped lists, light sheets, dialogs, receipts | — |
| `band` | `#FFFFFF`, full bleed, no radius, 24 px vertical padding | A dense section turned into a white band on the canvas: Home "Moje zážitky", Profil settings groups (optional) | — |
| `well` | `#F2F5F3` + 1 px `line` | Tiles, stat tiles, segmented-control track, neutral chips and inputs **inside white cards** | `tile` `#F3FBF7 → #E6F5EE`, `pill` `#EEF7F2` (neutral uses), `input` `#FBFDFC` |
| `line` | `#E2EAE5` | Card border, dividers (decorative) | `#E1EFE9`, `#E3EFE9`, `#D4E8E0`, `#E6F2ED` |
| `lineInput` | 1.5 px `#7C958A` (3.22 : 1) | Text inputs, selects, date fields (identifying boundary). Focus: 2 px `#0D6E0D` + 4 px ring neon @.28 | `#CFE3DA` |
| `tintOk` | `#E8FCE8` (+ `#37CF63` 1 px) | Checked or positive state only (✓ chips, "zdarma s rankem", "Zaplaceno") | — |
| `tintFeature` | 160° `#EAFBF0 → #D9F5E4`, or the offer box `#E6FAE2 → #F6FFF4` + 1 px dashed `#37CF63` | **At most one per screen** (web P2/P7) | ad-hoc mint areas |
| `night` / `panel` / `glow` / `gDark` / `gDarkCta` | `#0A1F14` / `#0E2A1C` / `#24563B` / v1 §2.2 | Header bands, hero cards, dark sheets, total box | — |
| `dock` | `night` @.96 + blur 14 + `shSticky` | Every bottom action bar on light screens (REZERVOVAT, ZAPLATIT, NAVIGOVAT, ZAZNAMENAT JÍZDU) | — |
| `scrim` | `night` @.55 (body) … @.8 (badges, back button disc) | Text and controls over photos | — |
| `iconTileDark` | 40 px (rows 36) r12, `#0E2A1C`, neon icon (11.55 : 1) | Section-leading features on light (web P6) | mint tile + green icon |
| `iconTileLight` | 36 px r10, `well` bg, `#0D6E0D` icon (6.45 : 1 vs white) | List-row icons on light | `#EEF7F2` tile |
| `eyebrowDark` | Pill `#0E2A1C`, neon 11.5/800 caps | Section eyebrows on light (web `.lp-rt-eyebrow`) | green caps text |

### 3.2 Text colours per surface (contrast measured)

| Role | On `surface` `#FFF` | On `canvas` `#F4F7F5` | On `well` `#F2F5F3` | On dark `#0E2A1C` (gDark, `#0A1F14` ≥) |
|---|---|---|---|---|
| Title / primary | `#1A2E22` 14.41 | 13.36 | — | `#FFFFFF` 15.37 |
| Body | `#1A2E22` / `#2C4A3A` 9.78 | ✓ | ✓ | `#E8F5EE` 13.70 |
| Lead / secondary | `#4A6B5A` 5.93 | 5.50 | 5.40 | `#CFE7DA` 11.78 / `#B8D4C6` 9.71 |
| **Meta / tertiary (min 11/700)** | **`#55705F` 5.43** | **5.03** | **4.94** | `#9FC4B1` 8.05; floor `#8FB3A1` 6.68 |
| Link, price, ✓ text | `#0D6E0D` 6.45 | 5.98 | ✓ | neon `#74FB71` 11.55 (6.39 over `#24563B`) |
| Text on `tintOk` | `#0D4F1C` 9.07 / `#0D6E0D` 6.00 | | | — |
| Warning | `#8A4B00` 6.80 (on `#FFF4E0` 6.24) | | | `#FFD36B` 10.82 |
| Error / destructive | `#B42318` 6.57 | | | `#FFB3B3` |
| Disabled (non-essential, exempt) | `#9DB3A8` 2.22 | | | white @.36 |
| On neon fill | `#08230F` 12.55; price `#0B3B1A` 9.54 | | | same |
| On ink button `#1A2E22` | neon 10.82 / white 14.41 | | | — |

- **Banned on light:** `#6C8A7B`, `#7C958A`, `#8AA096`, `#8FB3A1` as text.
- **Banned everywhere:** neon text or a lone neon edge on light.

### 3.3 Rules (add to DESIGN_V21 §7.0)

- **R5.1 Page colour.** Light screens use `canvas`; cards use `surface`. `#DFF0EC` survives only inside the rank ring, focus examples and legacy screens not yet ported.
- **R5.2 One dark block per window.** In any 746 px window (844 − nav 98), show at most **one** dark block besides the chrome (header band, dock, nav, toast).
  - Dark blocks are separated by **≥ 1 light section of ≥ 160 px**.
  - This replaces v1 rule 0.5 ("one dark hero per screen"), which long screens like web pages can satisfy anyway.
- **R5.3 Header + hero = one unit.** If a screen has a dark header band and a dark hero:
  - the hero overlaps the header by **−24 px** (web `.lp-panel`);
  - nothing (strip, gap or banner) sits between them;
  - the CMS banner text sits *inside* the header band as its last line.
- **R5.4 Budgets.** Measured with `sbal/comp.py`, excluding nav and dock.

  | Measure | Budget | Web reference |
  |---|---|---|
  | Dark in the first viewport | ≤ 45 % | max 40 % on `/kontakt` |
  | White + canvas over the whole scroll | ≥ 55 % | 34–63 % white alone |
  | Green-tinted (mint + mid-green), photos excluded | ≤ 20 % of the scroll | 9–17 % |
  | Neon | ≤ 5 % | 1–5.5 % |

  **Exempt (photo-led or immersive):** MotoKatalog, the MotoDetail hero, navigation, the level-up celebration (unchanged), codes full-screen, the recorder screen, and the SOS red system.
- **R5.5 Depth limit.** At most 2 levels of dark: dark hero → glass tile `rgba(255,255,255,.06)`. No glass inside glass. Inside a dark block, life comes from:
  - a **photo**;
  - the **rank aura** (header only);
  - **one neon focal point** (CTA or total);
  - white or neon chips.

  It never comes from more dark cards.
- **R5.6 Light rhythm.** Long light screens alternate `canvas` sections with **one full-bleed white `band`**, use photo thumbnails, and introduce sections with `eyebrowDark` pills and `iconTileDark`. Light screens must not become a grey-green monotone either.
- **R5.7 Rank on surfaces.**
  - **Dark carriers only:** rank CTA fill, glow and loop fx, the rank aura and the nav pill.
  - **On light, rank shows only as:** the logo ring and avatar ring (they carry their own dark disc), the progress bar on a `well` track, and the rank chip as a dark pill with the rank colour dot.
  - A rank CTA that must appear inside a light area goes in a **dark dock** (≥ 8 px night padding around it, r16).
  - Silver (7), Platinum (9), ivory VIP (17) and VIP Platinum (19) are therefore never shown on white.
- **R5.8 Buttons on light.** Light surfaces get no neon gradient fill. Use one of:

  | Style | Spec | Web origin |
  |---|---|---|
  | `btnInk` | `#1A2E22` + neon or white label, 48–52 px, r14 | `.lp-moto-book` |
  | `btnGhostLight` | White, 1.5 `#0D6E0D` border, `#0D6E0D` label | |
  | `btnText` | `#0D6E0D` text | |

  The single exception is ✓ discs and small badges: neon fill with an ink glyph (12.55 : 1). The fill is decorative and the glyph carries the meaning.
- **R5.9 Accent limits.**

  | Accent | Use | Never |
  |---|---|---|
  | Neon | CTA on dark, icons and eyebrows on dark, the calendar band, ✓ discs, the live dot on dark | Page or section tint, text on light |
  | Mint | `tintOk` states + one `tintFeature` | Page background, icon tiles in lists |
  | Red | SOS, errors, destructive actions, and the **recording** live dot (§6) | — |
  | Amber | Warnings, "návrh/ukázka" tags | — |
  | Rank | §R5.7 | — |
- **R5.10 Sheets.**
  - **Light** by default: filters, pickers, the calendar, sizes, receipt, consents, edit, confirmations. Grabber `#CFE3DA`, title 20/800 ink, close 44.
  - **Dark** only for live or immersive states: codes full-screen, the recorder, navigation overlays, AI chat (as today), level-up.
- **R5.11 Photos and back control (R6).** A back or close control on a photo or dark area is a 44 px disc `night` @.8, a white 24 px icon and a white @.25 1 px ring, top-left at (16, 47 + 8). On light it is a 44 px white disc, `line` border and `#1A2E22` icon. Same position everywhere.
- **R5.12 Chrome stays dark:** nav, AI FAB, docks, toasts. This anchors the bottom like the web sticky bar and footer.

---

## 4. Per-board changes (which sections become light)

Each list item states **now → change**. Expected compositions are estimates from the same y-ranges.

### 4.1 Main (Domů): the biggest win

Now: header 0–247 dark, banner strip 259–291 dark, funnel 303–895 dark. 0.7 % white in the first viewport. Page `#DFF0EC`.

1. **Header band (dark, rank aura, keep):** compact to ~190.
   - Status, logo + bell, greeting + rank pill on one row.
   - The stats line "Sezóna 2026 · [km] km · [n] jízd · [n] míst" moves to the "Moje zážitky" band header.
   - The CMS banner ("V zimním období … zavřeno") becomes the header's last line (11.5/700 neon marquee). **The separate dark strip goes.**
2. **Funnel hero:** overlaps the header by −24 (R5.3) and becomes **photo-led**.
   - The bike carousel grows to the full card width (358 × 200, r16, one-shot Ken Burns, "Volná v termínu" / "Pro tvůj ŘP A" badges on a scrim).
   - Dark remains only behind eyebrow + title, date presets and the rank CTA.
   - The card ends at ≈600 instead of 895.
   - The owner loves full-bleed bike photos; this puts one on Home.
3. **New light block right under the hero (y ≈ 616), web P2:**
   - the ½ offer box `tintFeature` ("Vyzvednutí od 12:00 · 1. den za polovinu");
   - a white card with two rows, `iconTileDark` + title + chevron: "Spočítat přesnou cenu" (→ Kalkulačka) and "Všechny motorky" (→ Motorky);
   - the season note (12.5/600 `#55705F`).

   Nothing is lost: the same items move out of the dark card.
4. **First viewport after the change:** dark ≈ 0–600 of 746, of which ~200 px is photo. Measured composition: dark ≈ 50 %, photo ≈ 27 %, white/canvas ≈ 23 %. The funnel CTA still sits above the fold (≈ 540–596).
5. "MotoGo ti píše" and "Tvůj klub": white cards on `canvas` (keep). Klub: rank only on the emblem ring and progress (R5.7). Meta text → `#55705F`.
6. **"Moje zážitky" (1215–1677) → full-bleed white `band`:**
   - First row is **"Zaznamenat jízdu"** (§6.3).
   - The 2 × 2 tiles become `well` tiles with `iconTileDark`.
   - Deník entries become white rows with `line` dividers.
   - Remove the "Nahrát jízdu" mini action from the "Soukromé jízdy" tile; the new row replaces it.
7. "Trasy kousek od …": photo cards with a white body on `canvas` (keep).
8. **Pobočky:** mirror web P5. **Mezná = white card** (photo top, white body, `btnInk` "Detail"); **Velké Němčice = dark card** (`pb-card--self`). This is the only dark block in the lower page (R5.2 satisfied; the nearest dark is ≥ 900 px above).
9. "Tvoje linka": white card (keep). S10 review card: light variant (DESIGN_V21 §5.4, keep).
10. Remove `#5D7B6B`, `#6C8A7B` and `#7C958A` text (→ `#55705F`).

**Target, whole scroll:** dark ≈ 25 %, white + canvas ≈ 58 %, green-tinted ≈ 12 %.

### 4.2 MotoKatalog: keep (owner OK, photo-led, exempt)

- Keep the full-screen photo cards and the dark header with the `.km` switch and filters.
- The winter notice becomes the header's last line.
- Make light: the filter sheet, the empty state ("Žádná motorka neodpovídá …" white card on `canvas`), error and offline states.

### 4.3 MotoDetail: photo stays, sheet turns white

Now: hero 0–560 dark, sheet `#DFF0EC` 536–2328 with the dark "Tvoje jízda" card (~1 000 px).

1. Sheet background `#DFF0EC` → **`#FFFFFF`** (web detail is a white page). Grabber `#CFE3DA`.
2. Spec tiles (kW / cm³ / mm / kg, "V kostce") → `well` + `line`. Units in `#55705F`.
3. **"Tvoje jízda" (recommended):** a white card with the step rows Termín / Předání / Výbava navíc (`well` rows, ✓ discs, "Změnit" as `btnText`). The **total box stays dark** (`gDarkCta`; "Tvoje cena · 3 dny", 32/900 neon, "Díky ranku … ušetříš" chip) as the screen's one dark block below the photo.
   - The calendar opens in a light sheet (§5).
   - The rank CTA stays in the sticky `dock` (REZERVOVAT · 10 189 Kč).
   - *Fallback if the owner wants web parity:* keep the dark card (`kc--detail`) but still apply 1 and 2.
4. The "Víc o motorce" accordion: white rows (keep), icon tiles → `iconTileLight`.

### 4.4 Kalkulačka: from all-dark to light steps

Now: dark section 197–2588 with three levels of glass, white only in the receipt.

1. Keep the shared Motorky header (dark, `.km` switch "Najít motorku | Spočítat cenu") to ~190.
2. **Page = `canvas`.** Steps 1–4 become **white step cards** (r16, `line`, `shCard`):
   - **Pobočka:** segmented on a `well` track; the selected segment is `btnInk` (ink + neon text).
   - **Motorka:** white bike card with photo; price `#0D6E0D`; old price struck through in `#55705F`.
   - **Termín:** the light calendar (§5).
   - **Předání a výbava:** rows with "Změnit".

   Step badges = web `.rez-step-num`: a 34 px dark disc with a neon number, or a ✓ when done. This is the contrast accent of the light flow.
3. Receipt: white (keep). Bars: `gBar` on white (keep).
4. **Dark block = "Tvoje cena" + CTA** (web `.kc-total` + CTA): one dark container holding the total, the average per day, the rank-savings chip and the **rank CTA REZERVOVAT · 10 189 Kč**. The sticky `dock` mirrors it once it scrolls off-screen.
5. Assurance ("Storno zdarma víc než 7 dní předem · Bezpečná platba"), "Zrušit termín" and the free-list chips: on `canvas`, `#4A6B5A` / `#0D6E0D`.

**Expected:** dark ≈ 22 % (header + total block + dock), white + canvas ≈ 66 %.

**Note for the owner:** this deliberately deviates from the web's dark `.kc` card because of R5 (2026-10-16). Mirroring the light version back to the web is optional.

### 4.5 Booking (Rezervace expres): already balanced, small fixes

- Page wash → `canvas`.
- Gear chips → `well`.
- Keep the white "Máme to připravené" card, ✓ discs (neon + ink ✓), the dark header and the dark pay `dock` with consents.
- Meta text → `#55705F`.

### 4.6 Reservation (Správa rezervace)

- Keep the photo hero and the dark **CO TEĎ** card (codes; review card in Dokončeno). It is the one dark hero.
- Sheet `#DFF0EC` → `canvas`.
- Chips "Šatna · dveře č. 8" and gear sizes → `well` chips with ink text.
- Keep `tintOk` only for "Zaplaceno", "½ 1. den za polovinu" and "zdarma s rankem".
- **"Tvoje cesta" timeline on `canvas`:** done = neon disc + ink ✓; current = `#1A2E22` disc with a neon ring; future = white disc with `line` border; labels `#4A6B5A`, dates `#0D6E0D`.
- Cards Kdy a kde / Výbava / Peníze / Dokumenty: white (keep). Navigation buttons = `btnInk` discs (as now).
- `--ter` → `#55705F`.

### 4.7 Profil

- Keep the dark rank header (0–437).
- Page `#DFF0EC` → `canvas`.
- "Můj účet" tiles: white with `iconTileLight` (count badges red as now).
- Osobní údaje, Nastavení, Pomoc & podpora and Ostatní: white grouped lists. Optionally one full-bleed white `band` for Nastavení.
- `--meta` `#6C8A7B` (×20) → `#55705F`.
- "Odhlásit se" / "Smazat účet": `#B42318` on white (6.57).
- Check the section-label gutter: the render shows "MŮJ ÚČET" / "NASTAVENÍ" flush at x = 0; it must be 16.

### 4.8 TrasyHub (Místa / Trasy)

- Keep the dark header (title, stats, map, +, search, segment). Page → `canvas`. List cards stay white.
- Category chips: white + `line`, the count in a `well` pill.
- The neon round "Přidat místo" button on the map → white disc with `line` border and a `#0D6E0D` pin-plus icon. The neon slot belongs to the record dock (§6).
- Add the **record dock** (§6.2).
- `--ter` ×14 → `#55705F`.

### 4.9 Zazitky (Moje): break the double dark

- **"Moje zážitky" summary card → white:**
  - 1 284 km as 32/900 ink;
  - split bar S MotoGo `#37CF63` / Soukromé `#1A2E22` on a `well` track (each at least 6 px high);
  - stat tiles `well` (7 jízd · 3 uložené trasy · 12 objevených míst);
  - a compact rank row (ring + "Motorkář · Level 3 / 20").
- "VYTVOŘIT NOVOU TRASU" → `btnInk`.
- The ghost "Zaznamenat vlastní jízdu" is removed from the card; the record dock replaces it.
- **"Tvoje stopy"** (dark map) = the segment's one dark hero (keep).
- Ride cards: white. Tags: "S MotoGo" dark pill (`#0E2A1C` + neon), "Soukromá" `well` pill, "Sdíleno" (keep), "ukázka" amber.
- Live-recording card in the list: white with a 1.5 px red border and a red "● Nahrávám" chip (as now).
- `--ter` ×21 → `#55705F`.

### 4.10 TrasaDetail

- Keep the map hero and the dark stats card overlapping it.
- Sheet `#DFF0EC` → `canvas`.
- Description, "Místa na trase" (photo cards, white body), "Galerie" and "Recenze" (white cards) stay light.
- "Půjč si motorku na tuhle trasu": keep it dark, as the web's `lp-cta-card`. It sits more than 1 000 px below the hero (R5.2 OK).
- Sticky "ZVOLIT TRASU – NAVIGOVAT" in the `dock`.
- `--ter` ×10 and `#7C958A` ×5 → `#55705F`.

### 4.11 SOS

- Keep red, white and the compact dark header.
- Page → `canvas`.
- Emergency tiles: `#D92D20` with white text (4.83).
- Report sheets: white.
- Nonstop-line `dock`: dark.
- `--ter` → `#55705F`.

### 4.12 RankStyly (showcase) and Oslava

- **RankStyly:** light sections → `canvas` / white. Every rank CTA demo stays on its dark dock; that is the rule being demonstrated. `--ter` → `#55705F`.
- **Oslava / level-up: no change** (owner: "lvl up video neměň").

---

## 5. Calendar range (R4): `TripCalendar`, one component

**Used in:**

- Kalkulačka step Termín
- MotoDetail date sheet
- Home funnel 📅 date sheet
- Booking "Termín a předání → Změnit"
- Reservation edit (extend / shorten / move)

**Code to replace:**

| File | Today | Semantics today |
|---|---|---|
| `features/catalog/widgets/availability_calendar.dart` | free = neon, selected = **dark** | inverted |
| `features/reservations/widgets/edit_reservation_calendar.dart` | free = neon, new days = dark, removed = red | inverted |
| Theme | `MotoGoColors.calRange` `#74FB71` @25 % | — |
| Boards | MotoDetail `.cd.rg` / `.cd.sl`, Kalkulačka `.cd.in` / `.cd.s` / `.cd.en` | — |

### 5.1 Skins

- **Light skin (default):** a white card or light sheet. The calendar box is `surface` r18 with a `line` border.
- **Dark skin:** only if the calendar sits inside a dark sheet (fallback for the dark Detail card).
- Both skins use the same states and geometry.

### 5.2 Geometry

- Grid of 7 columns with a 4 px gap.
- Cell 46 px high (≥ 44 tap target), r11.
- Day number 15/800 tabular; day price 10/700 below it (the only allowed 10 px).
- Weekday header 11.5/800 caps `#55705F`, weekend headers `#0D6E0D`.
- Month title 17/800 with ‹ › 44 px discs.
- The **range is painted as one band per week row**, behind the cells (`CustomPainter` under the row, not per-cell fills):
  - the band spans the gaps;
  - range start and end get **r11 caps**;
  - where the range wraps to the next row, the band ends with r6 and continues at the next row's start with r6.

### 5.3 States (light skin)

| State | Fill | Number | Price | Interaction |
|---|---|---|---|---|
| Free weekday | `#FFFFFF` + 1 px `line` | `#1A2E22` | `#0D6E0D` (6.45) | tap |
| Free weekend | `#F3FBF7` + 1 px `line` | `#1A2E22` | `#0D6E0D` | tap |
| **Selected: start, every day between, end** | **one solid band `#74FB71` + 1.5 px `#1F9A4A` contour around the band (3.63 : 1 vs white, meets 1.4.11)**. No gradient, no glow, same fill for every day. | `#08230F` 15/**900** (12.55) | `#0B3B1A` (9.54) | tap inside = new start |
| Single-day selection | same band as one r11 capsule | same | same | — |
| Start chosen, end pending | start capsule + 2 px `#0D6E0D` ring with a ping loop 1.8 s (reduced: static ring) | ink | ink | helper above grid: "Teď klepni na den vrácení" [návrh] |
| **Today** (11. 10. in mockups) | free fill + 1.5 px `#0D6E0D` ring | `#1A2E22` + 4 px dot `#0D6E0D` under the number | as free | a11y "dnes"; inside the band the dot turns `#08230F` and the ring is hidden |
| Past | none | `#9DB3A8` (disabled) | hidden | none |
| Busy / obsazeno | hatch 135° `#EEF2F0` / `#FFFFFF` 4 px | `#4A6B5A` struck through | hidden | tap → toast "Tento den je motorka půjčená" [návrh] (feedback instead of silence, R2) |
| Pending / čeká na potvrzení | none, 1.5 px dashed `#A66A00` (4.48) | `#8A4B00` | hidden | none (as web) |
| Out of rental limit (after the start is chosen, beyond `max_rental_days`, e.g. 30 for the Shotgun) or under `min_rental_days` | none | `#9DB3A8` | hidden | tap → toast "Nejdéle 30 dní · Royal Enfield Shotgun 650" [návrh] |
| Branch closed (season, from 1. 11.) | none | `#9DB3A8` | hidden | banner over the month: the CMS season text |
| Range crosses a busy day | band **not** drawn; tapped end cell shakes 300 ms (reduced: none) | — | — | toast "V termínu je obsazený den 24. 10. — vyber jiný den vrácení" [návrh]; the start stays |
| Loading availability | cells shimmer once (1.2 s; reduced: static @.55) | `#9DB3A8` | hidden | not selectable |
| Availability error | free look, prices hidden | ink | hidden | inline banner "Obsazenost se nepodařila načíst · Zkusit znovu" (Kalkulačka state "Chyba obsazenosti") |

**Edit (Reservation):** the resulting range is the uniform band.

- Newly **added** days carry a top-right "+" (11/900 `#08230F`).
- Days to be **removed** (shorten) sit outside the band: number `#B42318` struck through, 1.5 px dashed `#B42318` outline.
- Legend: "Přidáš" / "Ubereš".
- The original days have no extra mark.

**Legend** under the grid (12.5/600 `#4A6B5A`, 14 px swatches): Volno · **Tvůj termín** (band swatch) · Obsazeno · Čeká na potvrzení.

**Summary row** above the grid: "Vyzvednutí pá 23. 10. → Vrácení ne 25. 10. · **3 dny**". The `3 dny` chip is `btnInk` style. The row bumps on change.

```
Říjen 2026          ‹ ›        (today = ne 11.)
PO  ÚT  ST  ČT  PÁ  SO  NE
             1   2   3   4
 5   6   7   8   9  10 (11)•
12  13  14  15  16  17  18
19  20  21  22 ╭23══24══25╮   ← one band, uniform #74FB71, r11 caps
26  27  28  29  30  31        (range 23–27: row 1 ends r6, row 2 starts r6)
```

### 5.4 Dark skin (same semantics)

| Element | Spec |
|---|---|
| Free cell | `rgba(255,255,255,.08)` |
| Band | solid `#74FB71`, no contour needed (11.55 : 1 vs `#0E2A1C`) |
| Number / price | `#08230F` / `#0B3B1A` |
| Today | ring white @.75 + neon dot |
| Past | white @.36 |
| Busy | hatch, white @.38 struck through |
| Pending | dashed `#FFD36B` @.75 |

Remove the `.24` / `.28` alpha in-range fill everywhere (1.94–2.21 : 1).

### 5.5 Motion

- Start tap: `pop` 300 ms.
- End tap: the band **grows** from start to end, row by row (300 ms ease, 20 ms per cell, capped at 200 ms).
- Total and `3 dny` chip: `bump`.
- One `scanOnce` on the calculator total.
- Reduced motion: everything instant, the ping ring static.

### 5.6 Accessibility

- Cell label: "pátek 23. října 2026, 3 514 Kč, vybráno, vyzvednutí". Ends say "vyzvednutí" / "vrácení"; middle days say "vybráno".
- Selection is not colour-only: band shape + weight 900 + summary row.

### 5.7 Web parity (not edited; read-only here)

The web has the same defect, which is probably where the owner's eye was trained:

- `landing-calc.css` `.kc-days .kc-day.is-in{background:rgba(116,251,113,.24)}` vs `.is-start/.is-end` neon gradient;
- `rezervace-v2.css` `.cal-day.in-range{rgba(116,251,113,.28)}` vs `.sel-start/.sel-end`.

Recommend the same uniform band there in a separate web task.

---

## 6. "Zaznamenat jízdu" (R3)

### 6.1 Facts from the code (`features/routes/ride_recorder.dart`, both trees)

- **Automatic recording** during a rental: logged in + running booking + location already granted + switch `mg_ride_autorecord` on.
- **Manual recording** via `startManual()`:
  - Requires login.
  - Asks for location itself (`GpsService.ensurePermission`).
  - On iOS it requires *precise* location (`_ensurePreciseOnIos`).
- Survives an app kill (prefs `mg_ride_rec_id` / `_buf` / `_manual`).
- Rides under 1 km are discarded.
- A failed stop retries after 2 min.
- Android shows a foreground notification ("MotoGo24 zaznamenává jízdu").
- While an **automatic** recording runs, the manual card is hidden (`my_experiences_screen.dart`). Today the only entry is the manual card in Moje zážitky, plus a mini "Nahrát jízdu" on the Home board.
- **Existing cs strings:** `rideManualStart` "Zaznamenat vlastní jízdu", `rideManualStop` "Ukončit záznam jízdy", `rideManualHint`, `rideManualRunning`, `rideManualStarted` "Záznam jízdy běží 🛰️", `rideManualSaved`, `rideManualTooShort`, `rideManualStopFailed`, `rideManualFailed`, `rideRecordTitle` "Záznam jízdy", `rideRecording` "Nahrávám", `rideRecordHint`, `rideNotifTitle` / `Text`, `rideGapNotice`.
- **Idle glyph** today: `Icons.fiber_manual_record` in green. Recording: red. Keep that: **green ⏺ idle, red only while live**, so red stays "live or emergency".

### 6.2 Placements

**A. Trasy tab, primary action: the record dock.** On all three segments (Místa, Trasy, Moje), a bottom `dock` above the nav, the same pattern as the Detail sticky bar with the docked AI:

- **Layout:** `[ ⏺ ZAZNAMENAT JÍZDU ]` rank CTA (56 h, the tab's one looping primary, 294 px wide) + `[AI]` 56 disc, gap 8. The dock is 72 px plus the nav; the scroll view gets a bottom pad of nav 98 + 72 + 12.
- **Label width check** (14.5/800 caps, icon 20 + gap 8 + padding 2 × 16):

  | Language | Label | Label width | Button content |
  |---|---|---|---|
  | cs | ZAZNAMENAT JÍZDU | 155 | 215 |
  | en | RECORD A RIDE | 119 | — |
  | de | FAHRT AUFZEICHNEN | 164 | — |
  | es | GRABAR RUTA | 110 | — |
  | **fr** | **ENREGISTRER LA SORTIE** | **193** | **253** (longest) |
  | nl | RIT OPNEMEN | 107 | — |
  | pl | ZAPISZ PRZEJAZD | 137 | — |
  | uk | ЗАПИСАТИ ПОЇЗДКУ | 154 | — |

  Every language fits in 294 with ≥ 41 px to spare. No ellipsis, no wrap.
- **New key `rideRecShort` [návrh]**, 8 languages as in the table. The existing long `rideManualStart` stays as the recorder-screen title or helper.
- **Consequences:**
  - "VYTVOŘIT NOVOU TRASU" (Moje) → `btnInk`.
  - The map "Přidat místo" neon disc → white secondary.
  - TrasaDetail keeps "ZVOLIT TRASU – NAVIGOVAT" as its primary; there is no record dock on detail or navigation screens.

**B. Home shortcut.** The first row of the white "Moje zážitky" band:

- `[iconTileDark 44 with a neon ⏺]` "Zaznamenat jízdu" 15/800, subline "Jedeš na své? Uložíme ti trasu." [návrh, short form of `rideManualHint`] 12.5/600 `#55705F`, chevron.
- **Tap = start immediately** through the §6.4 flow, without navigating. The row then turns live.
- **During a rental** (ticket S7–S9) the row shows the automatic state instead (§6.4 #10). The ticket S8 "Jedeš" gets a line "● Záznam jízdy z výpůjčky běží · [km] km".
- Remove the duplicate "Nahrát jízdu" mini action from the "Soukromé jízdy" tile.

**C. Global live indicator.**

- **Trasy tab:** while recording, the dock **morphs** (300 ms crossfade + width) into the live bar:
  - left: 10 px red dot with a `ping` loop (the screen's one live indicator);
  - text "NAHRÁVÁM · 1:12:05 · 38,2 km" 13.5/800 tabular white;
  - right: `[Ukončit]` 44 px, white with `#B42318` label and ■ icon.
  - Tapping the bar (not the button) opens the recorder screen.
- **Other tabs (Domů, Motorky, Rezervace, Profil):** the existing **status strip** floats 8 px above the nav with "● Nahrávám jízdu · 38,2 km ›".
  - SOS keeps priority in the strip.
  - Hidden inside focused flows (`/booking`, payment) and during navigation.
- The Android notification stays as is.
- **New key `rideRecStopShort` [návrh]** for the bar button: Ukončit / Stop / Beenden / Detener / Arrêter / Stoppen / Zakończ / Зупинити. The long `rideManualStop` stays on the recorder screen.

**D. Recorder screen (full screen, dark: outdoor and night use, OLED, immersive).**

- **Top:** back chevron in a 44 disc (R6), title "Záznam jízdy", ⓘ (opens `rideRecordHint`). Going back keeps recording in the background.
- **Live trace:** 358 × 220 r20, neon line on a dark map, start pin, current-position dot.
- **Numbers (no count-up or odometer animation):**
  - time 48/900 white tabular;
  - distance 32/900 neon;
  - average speed 20/800;
  - GPS chip "GPS přesný / slabý".
- **Mode chip:** "Vlastní jízda" or "Výpůjčka · Husqvarna 701 SM".
- **Switch row:** `rideRecordTitle` + `rideRecordHint` (the automatic recording during a rental).
- **Dock:**
  - idle: `[⏺ ZAČÍT ZÁZNAM]` rank CTA [návrh];
  - recording: `[■ UKONČIT ZÁZNAM]` (`rideManualStop`), white button with `#B42318` label, 56 h. Ending is not the money action, so it does not use the rank CTA.

### 6.3 Motion

- Dock idle ↔ live: morph 300 ms.
- Live dot: `ping` 1.8 s (the only loop while recording; the rank CTA's glow loop stops while live).
- Saved: ✓ `pop` 300 ms.
- Reduced motion: static dot, instant swaps.

### 6.4 States (R2: every failure says what, why and how to fix, with a working next action)

| # | State (code condition) | Dock (Trasy) | Home row / strip | Message, sheet and action |
|---|---|---|---|---|
| 1 | Idle, not recording | ⏺ ZAZNAMENAT JÍZDU | row idle | — |
| 2 | Not logged in (`currentUser == null`) | same | same | Light sheet: "Jízdy ukládáme do tvého účtu — přihlas se a můžeš vyrazit." [návrh] · PŘIHLÁSIT SE (`btnInk`) · Zpět |
| 3 | Location services off (`isLocationServiceEnabled` false) | same | same | "Poloha v telefonu je vypnutá — bez ní trasu nenakreslíme." [návrh] · ZAPNOUT POLOHU (`Geolocator.openLocationSettings`) · Zpět |
| 4 | Permission not asked yet | same | same | Pre-prompt sheet: "Pro záznam potřebujeme polohu jen během jízdy." [návrh] · POKRAČOVAT → system dialog |
| 5 | Permission denied (can ask again) | same | same | "Bez polohy jízdu nezaznamenáme." [návrh] · ZKUSIT ZNOVU |
| 6 | Permission denied forever | same | same | "Poloha je pro MotoGo24 zakázaná v nastavení." [návrh] · OTEVŘÍT NASTAVENÍ (`openAppSettings`) |
| 7 | iOS approximate location (`_ensurePreciseOnIos` false) | same | same | "Zapni Přesnou polohu — s přibližnou se trasa nedá nakreslit." [návrh] · OTEVŘÍT NASTAVENÍ (iOS only) |
| 8 | Starting, waiting for a fix | spinner "Hledám GPS…" + Zrušit | strip "Hledám GPS…" | Times out at 30 s → "Nemáme signál GPS — vyjdi pod širé nebe a zkus to znovu." [návrh] · ZKUSIT ZNOVU |
| 9 | Recording manual (`recording && manual`) | live bar + Ukončit | row live / strip | Toast `rideManualStarted`; notification `rideNotifTitle` |
| 10 | Recording automatic (`recording && !manual`) | live bar "NAHRÁVÁM · jízda z výpůjčky · [km] km" + `[Možnosti]` (no Ukončit: it ends with the rental, as in code) | ticket line + strip | Recorder screen with the switch; switching off stops it (`setEnabled(false)`) |
| 11 | Rental running, automatic switch off | ⏺ ZAZNAMENAT JÍZDU (manual possible) | row idle + hint | Recorder: "Automatický záznam výpůjčky je vypnutý · Zapnout" [návrh] |
| 12 | Weak GPS / gap | dot turns amber, "Slabý GPS signál" [návrh] | strip amber | Later in ride detail: `rideGapNotice` (grey dotted segments) |
| 13 | Stop tapped | — | — | Confirm sheet (light): "Ukončit záznam? 38,2 km · 1 h 12 min" [návrh] · POKRAČOVAT V JÍZDĚ (`btnGhostLight`) · UKONČIT A ULOŽIT (`btnInk`). Prevents accidental stops with gloves. |
| 14 | Saved (≥ 1 km) | back to idle | row idle | Sheet `rideManualSaved` · ZOBRAZIT JÍZDU (→ ride detail: add photos and stops) · Hotovo |
| 15 | Too short (< 1 km) | idle | idle | Info `rideManualTooShort` · Rozumím |
| 16 | Save failed offline | idle | ride card badge "Čeká na odeslání" [návrh] | `rideManualStopFailed` (retries every 2 min, as in code) |
| 17 | Start failed, other | idle | idle | `rideManualFailed` is split into 2–7, so the generic text appears only as a last resort |
| 18 | App restarted mid-ride (manual restore) | live bar resumes | strip | Toast "Záznam pokračuje" [návrh] |

---

## 7. Port notes (Flutter, both trees, behind `app_v2_ui`)

- `lib/core/theme_v2.dart` `MotoGoV2`:
  - Add `canvas`, `well`, `line`, `lineInput`, `tintFeature`, `dock`, `iconTileDark`, `iconTileLight`, `eyebrowDark`, `meta = #55705F`.
  - Deprecate `page` / `pageWash` for v2 screens.
  - `MotoGoColors.bg` `#DFF0EC` stays for legacy screens until ported.
  - `MotoGoColors.calRange` (`#74FB71` @25 %) → remove.
- **Calendar:** one `TripCalendar` with a range painter. It replaces the inverted semantics of `availability_calendar.dart` and `edit_reservation_calendar.dart` (both trees; the iOS pins do not matter here, pure Flutter painting).
- **Recorder:**
  - new `RecordDock` widget (Trasy shell) + `RecorderScreen` route;
  - the strings marked [návrh] need all 8 languages;
  - permission helpers already exist (`GpsService.ensurePermission`, `Geolocator.openLocationSettings` / `openAppSettings`).
  - On iOS, keep the `geolocator ^10` API (no new API calls).
- **Checks:**
  - Re-run `sbal/comp.py` on each board after the build against the §R5.4 budgets.
  - Grep the boards for `#DFF0EC`, `#6C8A7B`, `#7C958A`, `rgba(116,251,113,.24)` and `.28`: they should be 0 outside legacy and focus examples.

## 8. Owner decisions (please confirm)

1. **Kalkulačka:** light steps + dark total/CTA (recommended), or keep the web-like all-dark card?
2. **MotoDetail "Tvoje jízda":** light steps + dark total (recommended, one component with Kalkulačka), or keep it dark?
3. **Home header:** keep the dark rank header in compact form (recommended; it carries the rank aura), or switch to a light header like the web?
4. **Record label:** short "Zaznamenat jízdu" (new key, recommended for dock and Home) and keep "Zaznamenat vlastní jízdu" inside the recorder?
5. **Web parity:** apply the uniform calendar band on the web too (separate task)?
