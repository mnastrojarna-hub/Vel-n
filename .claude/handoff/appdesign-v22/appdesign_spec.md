# MotoGo24 app v2: final design spec

**Base: Concept A.** All three reviews ranked it first (62 / 60 / 60 out of 70).

Grafted ideas:
- **From B:** the state-driven ticket, used both as the DOMŮ hero and as CO TEĎ. Access codes shown in order 1 → 2 → 3. The booking form skips steps that are already done. Sizes are kept out of the calculator. "Díky ranku ušetříš". Routes from your branch on DOMŮ, and "Půjč si motorku na tuhle trasu". Price unit tests.
- **From C:** the `MgMotion.reduced()` system with a fallback for every effect. The net delta chip. Date presets. A live total on the date sheet's confirm button. The kiosk timeline "Tvoje cesta". The loyalty-failure fallback. SOS first in the status strip. No decorative motion on the navigation screen. The needs-action badge on REZERVACE.

Fixes from the reviews, applied everywhere:
- The booking form stays at **`/booking`**. `/checkout` is already the shop checkout.
- **No shared-element (Hero) animation into `/success`.** That route sits outside the shell navigator.
- Pickup times from 12:00 are **never disabled**. Only the discount depends on the rental being 2+ days.
- Self-service return reads **"do 23:59"**.
- The pickup-procedure texts stay **1:1** with the e-mails, SMS and web.
- Moving between motorcycles uses **arrows only**. Swipe changes photos only.
- Route sketches are drawn from **`geometry`**.
- Promo-code **`min_order_amount`** is enforced.
- There is **one** draft and date state.
- A screen shows at most **one** price bar chart at a time.
- Dropped: odometer digits, parallax, spec gauges, the phone mock on Home, and the "+1 bod" earn promise.

---

## 0. Ground rules (every screen)

1. **One primary (neon) action per screen.** It sits in the dark hero card or the sticky bar, never below the fold.
2. **At most about 12 words of visible prose per block.** Longer original texts sit unchanged behind an ⓘ sheet or a "Víc" expander.
3. **One of each:** date component (`TripCalendar`), draft (`bookingDraftProvider`), booking form (`/booking`, entry file `core/booking_form_widget.dart`), and receipt component.
4. **Every headline price is "Tvoje cena"**, with the rank discount applied. The list price appears only as a secondary struck-through value.
5. **At most one dark hero card per screen.** Sticky bars, sheets and the status strip don't count.
6. **At most two infinite loops running at once:** the glow and shine on the screen's one primary CTA, plus one live indicator. Every other motion is one-shot and explains a change.
7. **Every motion widget checks `MgMotion.reduced(context)`.**
8. **Copy uses tykání** for all new and moved Czech strings. These stay 1:1 and unchanged:
   - `procStep*`, `gateCodeHint`, `procStepImportant`, `gateNotice`
   - contracts and documents
9. **No invented data.** Unknown values are written `[like this]`. In mockups, draw them literally, bracket text included.

## 1. Mockup data (all four artboards use it)

**"Today" in every mockup = neděle 11. 10. 2026.**

**Customer**
- Nickname `[přezdívka]`.
- Rank 3 **Motorkář**: 3 % off. Passenger gear and all boots are free (from rank 3, app only).
- Example state: 5 points, 1 point to rank 4 **Stálý jezdec** (4 %).
- Rank colour `[color_hex ranku 3]`. Draw it as `#74FB71`.
- Licence `[skupiny ŘP]`, includes A.
- Unread messages: `[n]`.

**R1, existing booking (Home and Reservation)**

| Field | Value |
|---|---|
| Bike | **Husqvarna 701 SM** (supermoto, ŘP A, 55 kW, 700 cm³) |
| Branch | **MotoGo24 Velké Němčice**, samoobslužná, Boudky, 691 63 Brno - Velké Němčice |
| Dates | pá 16. 10. 2026 **12:00** → ne 18. 10. 2026 **23:59**, 3 dny |
| Gear | Rider gear from the locker room (šatna = dveře č. 8), no paid extras |
| Price | 4 429 + 5 314 + 4 871 = 14 614. Late pickup −2 215. Loyalty 3 % −372. **12 027 Kč** |
| Status | Paid, documents verified, codes ready, booking `#[ID]` |

Codes are `[• • • •]`.

**R2, new booking in progress (Detail and Booking)**

| Field | Value |
|---|---|
| Bike | **BMW R 1200 GS Adventure** (cestovní, ŘP A, 92 kW, 1 254 cm³) |
| Branch | **MotoGo24 Mezná**, obslužná, nonstop, Mezná 9, 393 01 Pelhřimov |
| Dates | pá 23. 10. → ne 25. 10. 2026. Pickup 12:00 at the branch, return 19:00 at the branch |
| Extras | Výbava spolujezdce + Boty řidiče + Boty spolujezdce, all ticked |
| Price | Rental 3 514 + 4 882 + 3 865 = 12 261. Late −1 757 (½ of 3 514). Extras 0 (list 1 270, free at rank 3). Loyalty round(10 504 × 3 %) = −315. **10 189 Kč** |
| Without rank | 11 774 Kč, so the rank saves **1 585 Kč** |

**Weekday list prices**

| Bike | Po | Út | St | Čt | Pá | So | Ne | Days |
|---|---|---|---|---|---|---|---|---|
| BMW R 1200 GS Adventure | 3 514 | 2 811 | 2 811 | 3 163 | 3 514 | 4 882 | 3 865 | 1–180 |
| Husqvarna 701 SM | 4 429 | 3 543 | 3 543 | 3 986 | 4 429 | 5 314 | 4 871 | 1–180 |
| Royal Enfield Shotgun 650 (chopper, A2, Mezná) | 2 292 | 1 833 | 1 833 | 2 063 | 2 292 | 2 750 | 2 521 | 1–**30** |

**Rank 3 "Tvoje cena"**

| Bike | Per day, from | Weekend Fri–Sun, bike only, 09:00 |
|---|---|---|
| BMW | 2 727 | 11 893 |
| Shotgun | 1 778 | 7 336 |
| Husqvarna | 3 437 | 14 176 |

**Images**
- BMW: `…/media/motos/a0000001-0000-0000-0000-000000000001/moj0fnd41cr5-20260427-182831.jpg`
- Husqvarna: `…/media/motos/b850929a-37da-4b87-86a8-9b2fba7b3316/mq22a7zapb2x-1000003421.jpg`
- Royal Enfield: `…/media/motos/c9617cbe-c6d9-441d-9433-1a11e66fa357/msism7zmrm2a-img-0788.jpg`
- The prefix for all three is `https://vnwnqteskbykeucanlhk.supabase.co/storage/v1/object/public`.
- Branch photos: `[fotka pobočky]`.
- Unknown spec values: `[mm]`, `[kg]`, `[Nm]`, `[l]`.

---

## 2. Global tokens

All new tokens go in `lib/core/theme_v2.dart` (class `MotoGoV2`). The file is identical in both trees.

### 2.1 Colours

| Token | Hex | Use |
|---|---|---|
| `neon` | `#74FB71` | Accents, icons on dark, selected rings (= `MotoGoColors.green`) |
| `neonHi` → `neonLo` | `#8DFF86` → `#37CF63` | Primary gradient, 135° (topLeft → bottomRight) |
| `neonPressHi` → `neonPressLo` | `#A8FF9F` → `#5EDC5A` | Pressed primary |
| `neonText` | `#A8FF9F` | Light neon text on dark (eyebrows, hints) |
| `onNeon` | `#08230F` | Text and icons on neon. **Never white on neon** |
| `calPrice` / `calPriceRange` / `calPriceSel` | `#8FF58C` / `#C8FFC4` / `#0B3B1A` | Day price in a calendar cell: normal / in range / selected |
| `night` | `#0A1F14` | Deepest dark. Sticky bar @.96, photo badges @.8, scrim @.55 |
| `panel` | `#0E2A1C` | Dark base, step bar, scallop dots |
| `glow` | `#24563B` | Radial highlight |
| `inkDark` | `#1A2E22` | Primary text on light, active chip bg, secondary-dark button bg |
| `dotIdle` / `dotPast` / `borderDark` | `#173826` / `#1D4A30` / `#2A5A3E` | Timeline and step dots on dark, dark borders |
| Text on dark | `#FFFFFF` titles · `#E8F5EE` body · `#CFE7DA` lead · `#B8D4C6` secondary · `#9FC4B1` small · `#8FB3A1` notes and weekday labels | |
| Text on light | `#1A2E22` primary · `#2C4A3A` secondary · `#4A6B5A` muted · `#6C8A7B` tertiary · `#7C958A` meta · `#0D6E0D` price and link green · `#1F9A4A` route green · `#0D4F1C` text on a checked chip | |
| `page` | `#DFF0EC` | Page background (= `MotoGoColors.bg`) |
| `pageWash` | `#EAF6EF` → `#F5FAF7` over 380 px | Background of the focused flows (`/booking`, edit) |
| `card` | `#FFFFFF` | Cards |
| `tile` / `specTile` | `#F3FBF7` → `#E6F5EE` / `#F6FCF9` → `#EBF6F0` | Light tiles |
| `pill` / `input` / `inputAlt` | `#EEF7F2` / `#FBFDFC` / `#F7FCF9` | Pill and input fills |
| `checkedBg` / `checkedBorder` | `#E8FCE8` / `#37CF63` (soft variant `#9FDCB0`) | Checked chips and tiles |
| `imgPlaceholder` | `#E6F2ED` | Image placeholder |
| Borders on light | `#E1EFE9` card · `#D4E8E0` tile and dashed dividers · `#CFE3DA` chip and input · `#E3EFE9` divider · `#DBEAE3` ring | |
| `warnBg` / `warnText` / `warnLine` | `#FFF4E0` / `#8A4B00` / `#E9B44C` | Amber on light (missing item, blocker) |
| `warnDark` | `#FFD36B` text on `rgba(255,200,87,.16)` | Amber on dark |
| `errDark` / `errLight` | `#FFB3B3` on `rgba(255,120,120,.14)` / `#E5484D`, ring 3 px @.12 | Errors |
| `sos` | `#EF4444` | SOS (existing app red) |
| `stars` | `#FFB400` on / `#D6DFDA` off | Rating |
| Difficulty chips | Lehká `#E8FCE8` / `#0D6E0D` · Střední `#FFF4E0` / `#8A4B00` · Náročná `#FDECEC` / `#B42318` | Routes |

### 2.2 Gradients

- **`gNeon`:** linear 135°, `#8DFF86` → `#37CF63`.
- **`gDark`:** `RadialGradient(center: Alignment.topRight, radius: 1.5, colors: [#24563B, #0E2A1C, #0A1F14], stops: [0, .55, 1])`. Used by dark hero cards, sheets and the header.
- **`gDarkCta`:** radial from topCenter, `#2A6A45` 0 → `#0E2A1C` .6 → `#0A1F14` 1. Used by the receipt total box.
- **`gProgress`:** 90°, `#0D6E0D` → `#37CF63`.
- **`gBar`:** 180°, `#37CF63` → `#0D6E0D`. Weekend bars use `#A8FF9F` → `#37CF63`.
- **Scan line:** 3 px tall across the top of a dark card. Gradient transparent → `neon` → transparent, band width 40 %.

### 2.3 Typography: Montserrat (google_fonts, already in both trees)

| Role | Size / weight / line height | Notes |
|---|---|---|
| Total (display) | 32 / 900 / 1.0 | `tabularFigures`, neon on dark, text shadow 0 0 18 neon@.35 |
| Detail H1 | 25 / 700 / 1.18 | ls −0.2, max 2 lines |
| Screen H1 | 22 / 800 / 1.2 | Booking title, reservation title |
| Greeting | 20 / 800 / 1.2 | Home header |
| Card title (dark hero) | 20 / 800 | |
| Section title | 17 / 800 / 1.25 | On light pages |
| Card title | 16 / 800 / 1.25 | Max 2 lines |
| Body | 14 / 600 / 1.45 | |
| Small | 12.5 / 600 | |
| Meta | 11.5 / 700 | |
| Eyebrow / kicker | 11.5 / 800 | UPPERCASE, ls .06em |
| Micro (minimum) | **11 / 700** | Nothing smaller, except calendar day prices at 10 / 700 |
| Primary button | 14.5 / 800 | UPPERCASE, ls .3 |
| Sticky-bar button | 13.5 / 800 | UPPERCASE |
| Price on card | 17 / 800, `#0D6E0D` | Suffix "/den" 12.5 / 600 |
| Sticky value | 20 / 900, neon, tabular | |
| Code digits | 24 / 900, tabular | ls .18em (full-screen view: 48 / 900) |
| Nav label | 11 / 800 | |

### 2.4 Radii

| Radius | Used on |
|---|---|
| 6 | Category tag, in-range day |
| 8 | Map chips, 28 px icon box |
| 10 | 36 px icon tile, thumbnails |
| 11 | Calendar day |
| 12 | Sticky-bar buttons, action buttons, 48 px icon tile |
| 14 | Buttons, inputs, choice chips, total box |
| **16** | Cards |
| 18 | Receipt, calendar box |
| **20** | Dark hero card, step cards |
| **22** | Calculator card, sheet top corners |
| 24 | Header bottom corners |
| 999 | Pills |

New tokens to add: 16, 20, 22.

### 2.5 Shadows and borders (CSS `x y blur spread` → `BoxShadow`; no inset shadows, use `Border.all`)

| Name | Shadow | Extra |
|---|---|---|
| `shCard` | (0,6) 18 −8 `#1A2E22`@.35 | Border 1 `#E1EFE9`. Pressed: (0,12) 26 −10 @.45 |
| `shDark` | (0,18) 40 −14 `#0A1F14`@.6 | Border 1 neon@.25 |
| `shCurrent` | (0,16) 36 −20 `#0E2A1C`@.55 | Ring 1.5 `#37CF63` (active step card) |
| `shGlow` | (0,8) 22 −8 neon@.6 | Primary button. Pulses: ring grows 0 → 7 px while fading .45 → 0 |
| `shDaySel` | (0,6) 16 −6 neon@.9 | Ring 2 neon@.35 |
| `shSticky` | (0,−8) 24 0 black@.25 | |
| `shSheet` | (0,−14) 40 0 `#0A1F14`@.35 | |
| `shReceipt` | (0,14) 30 −14 black@.55 | |
| `shIcon` | (0,4) 12 −6 `#1A2E22`@.35 | |

- **Focus:** 3 px neon ring with offset 3 on dark; 3 px `#37CF63` on light.
- **Inputs:** default border 1.5 `#CFE3DA`. Focused: border `#37CF63` plus a 4 px ring neon@.28.

### 2.6 Spacing and layout

- **Frame:** 390 px wide. Status bar 47. Home indicator safe area 34.
- **Gutter:** 16. Content width 358.
- **Gaps:** 24 between page sections, 12 inside cards, 8 between chips, 10 between tiles.
- **Card padding:** 16. Dark hero card: 18 top/bottom, 16 sides.
- **Touch targets:** 44 minimum. Chips 40. Choice chips 44. Buttons 52. Main CTA 56. Sticky button 48.
- **Bottom nav:** 64 + 34 safe area. The status strip floats 8 above it.

### 2.7 Motion tokens (`lib/core/motion.dart`)

| Token | Value | Use |
|---|---|---|
| `press` | 150 ms, scale .97, `Curves.ease`, plus haptic `selectionClick` | All tappables (existing `PressableScale`) |
| `color` | 180 ms `ease` | Colour and border changes |
| `sheet` | 300 ms `ease`, translateY 105 % → 0. Scrim 250 ms | Bottom sheets |
| `sticky` | 300 ms `ease`, `AnimatedSlide` Y 1.1 ↔ 0 | Sticky bars, status strip |
| `pop` | 300 ms `TweenSequence` .85 → 1.08 (40 %) → 1 (60 %) | Selection, ✓, chips, badges |
| `enter` | 450 ms `ease`, opacity 0 → 1 + Y 12 → 0 | Content switching |
| `reveal` | 550 ms `ease`, Y 16 → 0, stagger 70 ms (capped at index 5), base delay 0 | Lists on first build |
| `bump` | 450 ms 1 → 1.12 → 1, plus `AnimatedSwitcher` crossfade with 6 px slide | Totals only. No count-up, no odometer |
| `delta` | Pop in 300 → hold 1 600 → rise 10 px + fade 500 | Delta chip |
| `bars` | 500 ms `Cubic(.2,.9,.3,1.2)`, stagger 45 ms | Price bars |
| `connector` | 700 ms `ease`, stagger 90 ms + 200 ms base | Timelines |
| `strike` | 300 ms `easeOut`, line drawn left → right | Price made free by rank |
| `hero` | 350 ms `Cubic(.2,0,0,1)`, radius 16 → 0 via `flightShuttleBuilder` | Only inside the shell navigator |
| `tab` | 210 ms fade-through: old fades out 0–90 ms, new fades in with scale .98 → 1 | Tab switch |
| `push` | 300 ms `ease`, slide-up 24 px + fade. Bottom nav slides out 110 % | Focused flows |
| `path` | 900 ms `easeInOut` on cards, 1 600 ms on route detail. Pins pop .6 → 1.3 → 1 over 350 ms | Route sketch, drawn once |
| `scanOnce` | 600 ms linear, a single sweep | Each calculator recalculation |
| Loop: `glow` | 2.2 s `easeInOut` | Primary CTA only |
| Loop: `shine` | 3.2 s, sweeps during the last 40 % of the cycle | Same CTA |
| Loop: `ping` | 1.8 s, ring 0 → 7 px, opacity .7 → 0 | Live dot, current timeline node |
| Loop: `scan` | 3.6 s linear | Only on live ticket states (pickup day, riding, SOS, unpaid) |

**Rules for loops:**
- Wrap every loop in a `RepaintBoundary`.
- Stop loops with `TickerMode(enabled: visible)` when the element is off-screen, its sheet is closed, its route is covered, or the app is not `resumed`.

### 2.8 Reduced motion

`MgMotion.reduced(context)` returns `MediaQuery.disableAnimationsOf(context)` OR the app setting "Omezit animace" (Profil → Nastavení, stored in shared_preferences; owner decision §13).

When it returns true:
- All loops are off.
- Reveal, pop, bump, bars, strike and connectors snap to their end state.
- Delta chip: shown statically for 2 s, then removed.
- Hero: `HeroMode(enabled: false)`.
- Page transitions and sheets: no transition.
- Route paths: drawn complete and static.

**Retrofit the check into the existing widgets:** `StaggeredReveal` (also retune it to the `reveal` token), `GlowPulse`, `ShimmerSweep`, `NavBounceIcon`, `MotoSuccessHero`, the loyalty level-up overlay (static card; music stays optional), and the register `AnimatedSwitcher`.

**`RouteNavigationScreen`: no decorative motion at all**, regardless of the setting.

### 2.9 Icons

- **Style:** line icons on a 24-unit grid, `fill: none`, round caps and joins. Stroke 2 for UI icons at 16–22 px; stroke 1.8 for feature icons at 22–26 px.
- **Implementation:** `LpIcon` (`core/widgets/v2/lp_icon.dart`) using `SvgPicture.string` + `ColorFilter.mode(srcIn)`.
- **Paths from the web:** copy them from `landing.php:197` (cal, moto, check, arrow, pin) and `landing-trust.php:9` (card, shield, helmet, fuel, phone, kiosk, bot, route, star, gift, truck, percent, child, clock, calendar).
- **Fallback:** Material `Icons.*_outlined` / `*_rounded` for home, user, bell, copy, navigation, edit, close, doc, lock, info, chevron, boot.
- **Emoji:** none in UI chrome (today there are ~358). Emoji stay only in toasts and chat content.
- **Feedback:** redesigned screens use only `showMotoGoToast`, never `SnackBar`.

---

## 3. Shared components (`lib/core/widgets/v2/`, each file under 5 000 tokens)

**C1 Bottom nav (`v2_nav_bar.dart`)**
- Container: white, 64 + 34 safe area, top hairline 1 `#E1EFE9`, shadow (0,−6) 20 −10 `#1A2E22`@.25.
- Items: 5 equal columns (78 px). Icon 24, label 11/800 UPPERCASE below.
- Active tab:
  - A `gNeon` pill 52×30 r999 sits behind the icon, with glow (0,6) 14 −6 neon@.6.
  - The pill slides between tabs with `AnimatedAlign` 250 ms `easeOutCubic`.
  - Icon `#08230F`, label `#1A2E22`.
- Inactive tab: icon and label `#6C8A7B`, label weight 700.
- Icons keep `NavBounceIcon`.
- Tabs: **DOMŮ** (home), **MOTORKY** (moto), **REZERVACE** (calendar-check), **TRASY** (route), **PROFIL**.
  - The PROFIL icon is a 26 px avatar circle with a 2.5 px ring in the rank colour, plus an arc showing progress to the next rank.
- Badges:
  - REZERVACE: an 8 px `#EF4444` dot with a 2 px white ring when a booking needs action (unpaid, or documents missing).
  - PROFIL: a count pill, min 16 px, `#EF4444`, white 11/800, for unread messages.
- Hidden while the keyboard is open and on focused flows (§4.1).

**C2 Status strip (`v2_status_strip.dart`)**
- Floats 8 px above the nav, 16 px side insets.
- Container: height 52, r999, `#0A1F14`@.95, border 1 neon@.30, `shSticky`.
- Left: a 32 px circle icon.
  - SOS: `#EF4444` fill, white icon.
  - Payment: `gNeon` fill, `onNeon` icon.
  - Documents: `warnLine` fill.
  - Route: neon outline.
  - Cart: white@.10 fill.
- Text: 13.5/800 white + secondary 12/600 `#B8D4C6`.
- Right: a "+n" chip (neon@.16 bg, `#A8FF9F` text 12/800) and a chevron.
- Shows the single most urgent item. Priority:
  1. "SOS hlášení nedokončeno · Dokončit"
  2. "Dokonči platbu · mm:ss"
  3. "Nahraj doklady · uvolníme ti kódy"
  4. "Pokračovat v trase · [název]"
  5. "Košík ([n]) · [částka] Kč"
- Taps: the item → its action. "+n" → light sheet listing all items.
- Hidden on focused flows, and whenever the same item is already the hero on screen (for example, the Home ticket in the unpaid state).
- Item change: `enter` 250 ms.

**C3 Buttons**
- **Primary:**
  - Layout: h52 (56 for the main CTA), r14, `gNeon`. Text `onNeon` 14.5/800 UPPERCASE, trailing arrow icon 18, gap 8.
  - Motion: `GlowPulse` + `ShimmerSweep` (white@.75, skewed −22°, half the button wide) **only on the screen's single primary**. Pressed: `press` + pressed gradient.
  - Disabled: on light, bg `#CFE3DA` + text `#6C8A7B`; on dark, bg white@.10 + text `#8FB3A1`. No loops.
- **Secondary dark:** `#1A2E22` bg, neon text 13.5/800 UPPERCASE, h44, r12.
- **Ghost light:** white bg, border 1.5 `#37CF63`, text `#1A2E22` 13.5/800, h44, r12.
- **Ghost dark:** white@.05 bg, border 1.5 neon@.6, white text, h44, r12.
- **Action tile** (reservation action row):
  - Flex width, h64, r14, white, border 1 `#E1EFE9`.
  - Icon 22 `#0D6E0D` above a label 11.5/800 `#1A2E22`.
  - Destructive variant: icon and label `#E5484D`.
- **Text link:** 13/700 `#0D6E0D` on light, `#A8FF9F` on dark.

**C4 Chips**
- **Category chip (light):**
  - Inactive: h40, padding 0 14, r999, white, border 1.5 `#CFE3DA`, text 13/700 `#1A2E22`.
  - Active: bg `#1A2E22`, white text.
  - Count badge: 22×20 r999, `#E6F5EE` with `#0D6E0D` 11/800. On an active chip the badge turns neon with `onNeon` text.
- **Choice chip on dark** (times, presets):
  - h44, min width 64, r14, white@.06, border 1 neon@.22, text 14/800 `#E8F5EE` tabular.
  - Selected: `gNeon`, text `onNeon`, ring 2 neon@.35 + glow (0,6) 16 −6 neon@.7, `pop`.
  - **"½" tag:** 20×18 r6, offset −6 from the top-right corner. Bg `#0E2A1C`, border 1 neon, "½" in 11/900 neon. On a selected chip the tag bg becomes `#08230F`. It pops in (280 ms) when the rental reaches 2+ days.
- **Choice chip on light** (same widget, `tone: light`):
  - White, border 1.5 `#CFE3DA`, text `#1A2E22`.
  - Selected: bg `#0E2A1C`, neon text, ring 2 neon@.35.
- **Segmented control (dark):**
  - Container: r16, white@.05, border 1 neon@.22, padding 4.
  - Options: h56, r12, title 13.5/800 white + sub 11.5/700 `#A8FF9F`.
  - Selected: bg neon@.16, border 1.5 neon, glow (0,6) 18 −8 neon@.7.
  - Locked: lock icon, text `#8FB3A1`, trailing ⓘ (opens the info sheet).
- **Size chip (light):**
  - h48 (h36 in compact rows), r12, `#F7FCF9`, border 1.5 `#CFE3DA`. Label 11.5/700 `#4A6B5A` + value 14/800 `#1A2E22`.
  - Missing: bg `warnBg`, border 1.5 `warnLine`, value "Vyber" 14/800 `warnText`.
  - Tap opens the existing `booking_size_dialogs` sheet (restyled).
- **Status pill:** h24, r999, padding 0 10, 11.5/800 UPPERCASE ls .04em. Variants:

  | Variant | Background / text |
  |---|---|
  | ok on light | `#E8FCE8` / `#0D6E0D` |
  | ok on dark | neon@.16 / `#A8FF9F` |
  | warn | `warnBg` / `warnText` |
  | off | `#FDECEC` / `#B42318` |
  | neutral | `#EEF7F2` / `#2C4A3A` |
  | on photo | `#0A1F14`@.8 / white, with an optional 7 px neon `ping` dot |

- **Category tag:** r6, neon bg, `onNeon` 11/800 UPPERCASE ls .04em, padding 3/7.
- **Rank chip (dark):**
  - h28, r999, bg rank@.16, border 1 rank@.6, 8 px dot in the rank colour, text 12/800 white.
  - Example: "Motorkář · sleva 3 %".
- **Delta chip (C7):**
  - h24, r999, padding 0 8, 12/800 tabular.
  - Decrease: neon@.16 bg, border neon@.45, `#A8FF9F` text, e.g. "celkem −1 704 Kč".
  - Increase: white@.10 bg, border white@.25, `#E8F5EE` text.
  - Light variants: `#E8FCE8` / `#0D6E0D` and `#EEF7F2` / `#2C4A3A`.
  - It always shows the **net change of the total**, never a line item. Motion: `delta`.

**C5 Cards**
- **Light card:** r16, white, `shCard`, padding 16.
- **Dark hero card:**
  - r20 (calculator r22), `gDark`, `shDark` with the neon@.25 border, padding 18/16.
  - Optional infinite `scan` line only on live states. `scanOnce` on every recalculation.
- **Step card** (booking): r20, white, `shCard`.
  - Current step: `shCurrent` ring.
  - Done step: collapsed summary.

**C6 Receipt (`receipt_card.dart` + `receipt_painters.dart`)**
- Shell:
  - White, r18, `shReceipt`, padding 16/14.
  - Scalloped top edge: circles r5 in the parent colour (`#0E2A1C` on dark, `page` on light), every 16 px, centred on the edge. Drawn with `CustomPainter`.
- Header row: kicker "TVOJE CENA" 11.5/800 `#0D6E0D` ls .07em. Right: a days pill, `#0E2A1C` bg with neon text 11.5/800 ("3 dny").
- Date line: 12.5/600 `#4A6B5A`.
- **Day bars:**
  - 78 px tall area. One bar per rental day (max 14 bars; longer rentals show a weekly sparkline). Bar width 34 (min 14), gap 10, r 6/6/2/2.
  - Weekday bars use `gBar`; Sat/Sun use the weekend gradient.
  - Under each bar: weekday 11/700 `#6C8A7B` and price 11/800 `#1A2E22`.
  - Late pickup: the first bar's top half gets 45° stripes white@.55, 4 px.
- Rows:
  - Label 13.5/600 `#2C4A3A`, value 14/800 `#1A2E22` tabular, right aligned.
  - Discounts in `#0D6E0D` with a "−" sign.
  - Dashed 1 px `#D4E8E0` dividers, dash 4 / gap 3.
  - Rows appear only when non-zero.
- Total box: r14, `gDarkCta`, padding 14/16. "TVOJE CENA" 12/800 `#A8FF9F` + value 32/900 neon. Delta chip slot top-right.
- Below the box:
  - Rank line 12.5/700 `#0D6E0D`: "Díky ranku [rank] ušetříš [X] Kč".
  - Footer 11.5/600 `#6C8A7B`: "Bez kauce · konečná cena · nejsme plátci DPH".
- **One widget** is used by the detail calculator, the booking live summary, the reservation "Rozpis ceny" and the edit delta (in mode `delta`).

**C8 Sticky price bar (`v2_sticky_bar.dart`)**
- Container: bottom, full width, `#0A1F14`@.96, top radius 20, `shSticky`, padding 10/16 + safe area. Layout `1fr auto`. No `BackdropFilter`.
- Left:
  - Label 11.5/700 `#CFE7DA`.
  - Value 20/900 neon tabular, with the delta chip popping above it.
  - Blocker state: the label is replaced by `#FFD36B` text naming **the single** missing thing.
- Right: button h48, r12, padding 0 18, 13.5/800.
- Blocked: the button turns ghost-dark "DOPLNIT ↓". Tapping it scrolls to the blocker (350 ms `easeInOut`) and pops its ring once.
- Visibility: `AnimatedSlide` (`sticky`). The glow and shine pause while the bar is hidden.

**C9 Date sheet `TripCalendar` (`v2_date_sheet.dart`, restyles the `AvailabilityCalendar` logic)**
- Container: dark sheet `gDark`, top radius 22, max height 88 %, grabber 42×5 white@.25.
- Title "Kdy jedeš?" 20/800 white + close button 40 (ghost dark).
- Two tiles, h56, r14, white@.05, border 1 neon@.22 (active tile: border neon). Tile label 11/800 `#A8FF9F` + value 15/800 white:
  - "VYZVEDNUTÍ · pá 23. 10."
  - "VRÁCENÍ · ne 25. 10."
- Presets row, choice chips on dark:
  - "Nejbližší víkend · 16.–18. 10."
  - "Další víkend · 23.–25. 10."
  - A preset is struck through and disabled when any of its days is busy for this bike.
- Hint 12.5/600 `#A8FF9F`: "Klepni na den vyzvednutí", then "Teď den vrácení (může být i stejný den)".
- Month header "ŘÍJEN 2026" 13/800 ls .08em white. Nav buttons are 42 px circles, border neon@.5, bg neon@.08, neon chevron.
- Weekday row "po út st čt pá so ne", 11/700 `#8FB3A1`.
- Grid: `GridView.count(7, spacing 4)`. Cell h48, r11, white@.08. Number 15/800 white tabular. Day list price below it, 10/700 `#8FF58C` (bike context only; no prices when no bike).
- Cell states:
  - Free weekend: bg neon@.10.
  - Busy (`get_moto_booked_dates`): 45° stripes white@.05 4 px, number line-through white@.3, no price.
  - Past or beyond `max_rental_days`: text white@.22, no bg.
  - Today: 4 px neon dot under the number.
  - In range: neon@.24, r6, price `#C8FFC4`.
  - Start / end: `gNeon`, number `onNeon`, price `#0B3B1A`, `shDaySel`, `pop`. Range cells fill in order, 12 ms stagger, total ≤ 250 ms.
- Legend: 12 px r4 swatches "Volné · Obsazené · Tvůj termín".
- One-line note `#8FB3A1` 11.5: "1 den = kalendářní den (0:01–24:00), ne 24 h od převzetí."
- Confirm (primary):
  - Bike context: "POTVRDIT · 3 DNY · 10 189 KČ" (live total from the current draft).
  - No bike: "POTVRDIT · 3 DNY".
- Month change: slide + fade 250 ms `ease`.

**C10 Status timeline (`status_timeline.dart`)**
- Horizontal. Nodes are 22 px circles.
  - Done: `gNeon` fill with a check in `onNeon`.
  - Current: ring 2 neon + 10 px neon inner dot + `ping`.
  - Upcoming: on light, `#E6F2ED` with border `#CFE3DA`; on dark, `#173826`.
- Connectors: 2 px. Done segments use `gProgress`; upcoming segments are dashed `#D4E8E0`. They grow with `connector`.
- Labels 11/700 centred below (on light: `#1A2E22` done / `#6C8A7B` upcoming), max 2 lines. Optional sub-label 11/600 `#0D6E0D`.

**C11 Code tile (`code_tile.dart`)**
- On dark: h64, r14, white@.06, border 1 neon@.22, padding 10/12.
- Left: a 22 px `gNeon` step circle ("1", 11/900 `onNeon`). Then a label 13/800 `#E8F5EE` and a sub 11.5/600 `#9FC4B1`.
- Right: digits 24/900 white tabular ls .18em, then a 36 px copy button (neon icon).
- Tap anywhere: copy, `HapticFeedback.lightImpact`, toast "Zkopírováno".
- Locked: digits rendered as `• • • •` under `ImageFiltered(blur σ6)`, plus an amber reason line (11.5/700 `#FFD36B`).
- First reveal after documents verify: blur → sharp over 400 ms + `pop`.
- `Semantics(label: "Kód brány 4 8 2 1")` style, digits spelled one by one.

**C12 Section header:** title 17/800 `#1A2E22`, right link "Vše ›" 13/700 `#0D6E0D`.
- **Eyebrow pill (dark):** h24, neon@.12 bg, border 1 neon@.4, text `#A8FF9F` 11.5/800 UPPERCASE ls .06em.

**C13 Info sheet ⓘ:**
- Light sheet: white, top radius 22, grabber 42×5 `#CFE3DA`, scrim `#0A1F14`@.55.
- Title 17/800, body 14/600 lh 1.5 `#2C4A3A`.
- Holds the full original texts word for word.

**C14 List row / collapsible:**
- h56. A 36 px icon tile (r10, `#EEF7F2`, `#0D6E0D` icon), title 14/800, sub 12/600 `#6C8A7B`, trailing count chip + chevron.
- Expand: `AnimatedSize` 300 ms `easeInOut`; the chevron rotates 180° in 200 ms.

**C15 Rank strip (`rank_strip.dart`)**
- Light card.
- Header: MG logo 40 px inside a rank ring (stroke 3, progress arc), name 15/800, sub 12/700 `#4A6B5A` "Level 3 z 20 · sleva 3 % na každou jízdu v appce".
- From rank 3: benefit line 12.5/600 "Výbava spolujezdce a boty máš zdarma".
- Progress bar h8, r4, `#E6F2ED` track, `gProgress` fill.
- Line 12/700 `#0D6E0D`: "Ještě [n] b. → Stálý jezdec (4 %)". Same data source as today's `LoyaltyRankCard` (`bookingsToNext`).
- Chevron → `/loyalty`.
- Fill animates from the last seen value: 700 ms `easeOutCubic`, 200 ms delay.

**C15b Moto card (`moto_card_v2.dart`)**
- Shell: r16, white, `shCard`.
- Image 3:2, `BoxFit.cover`, Hero `moto-img-{id}`.
  - Top-left: status pill on photo ("● Dnes volná" with `ping`, "Volná v termínu", or "Obsazená v termínu" in warn variant).
  - Bottom-right: category tag.
- Body, padding 12/14:
  - Title 16/800, 2 lines max.
  - Meta 12/600 `#4A6B5A` with pin icon + branch name.
  - Up to 3 spec pills, h24, r999, `#EEF7F2`, 11/700 `#2C4A3A`.
- Price row:
  - No dates: "od" 12.5/600 `#4A6B5A`, value 17/800 `#0D6E0D` "2 727 Kč", "/den", then the struck list price 12/600 `#7C958A` "2 811".
  - Line 2, 12/700 `#2C4A3A`: "pá–ne 11 893 Kč".
  - With dates: "3 dny · **[tvoje cena] Kč**" + struck list total + a 42×42 "Rozpis" icon button (opens C6 in a sheet).
- The whole card is tappable.

**C16 Route sketch card (`route_sketch_painter.dart`)**
- Card r16, white. Sketch area 296×140, `#F2F7F3`.
- Path:
  - Source: `routes.geometry`, decimated to ≤ 200 points, normalised into the box with 14 px padding.
  - Stroke `#1F9A4A`, 4 px, round caps and joins.
  - Start pin: r6, fill `#0E2A1C`, neon stroke 3. End pin: r6, fill neon, `#0E2A1C` stroke 3. A loop route has one pin.
  - Draws in once with `path` + `PathMetric.extractPath`.
  - Mockup placeholder: the web phone-mock route path in a 220×300 viewBox, `M40,262 C30,220 70,205 66,168 C62,131 30,120 64,96 C98,72 128,92 136,64 C144,36 168,30 186,44`, labelled `[geometrie trasy]`.
- Body:
  - Title 15/800 "[název trasy]".
  - Chips: "[km] km", "[čas]", difficulty chip, "Okruh" / "Za místy".

**C17 Bottom sheet shell:**
- Light (white) or dark (`gDark`), top radius 22.
- Grabber 42×5: `#CFE3DA` on light, white@.25 on dark.
- Scrim `#0A1F14`@.55. Max height 88 %. Motion: `sheet`.

**C18 Step progress (booking):**
- Bar: h42, r999, `#0E2A1C`, ring 1 neon@.25, padding 6.
- Base line white@.14. Progress line neon, `scaleX` animated 450 ms.
- 3 dots, 30 px: past = `#1D4A30` with neon ring + check; current = `gNeon`; future = `#173826`.
- The current step's label 11.5/800 white expands with `AnimatedSize` 400 ms; other labels show only their number.

**C19 Offer strip (dark):**
- r12, dashed 1.5 border neon@.6 (painter), padding 10/12.
- A 28 px neon "½" circle in `onNeon` 13/900, then text 13/700 white, then the right value 13/800 neon.

---

## 4. Navigation and information architecture

### 4.1 Tabs (keep the current single `ShellRoute`; no `StatefulShellRoute`)

| Tab | Path | Holds |
|---|---|---|
| **DOMŮ** | `/` | Customer hub (Screen 1) |
| **MOTORKY** | `/motorky` (new) | The **only** catalogue. Replaces the REZERVOVAT tab and the Home bike list |
| **REZERVACE** | `/reservations` | List → detail (Screen 4) → edit, storno, SOS |
| **TRASY** | `/routes` | Segments **Místa · Trasy · Moje**. Default Místa (the 16. 9. decision); the last choice is remembered |
| **PROFIL** | `/profile` | Former hamburger menu |

**Focused flows hide the nav** with the `push` motion: `/moto/:id`, `/booking`, `/payment`, `/reservations/:id/edit/*`. Back pops to wherever the user came from, so the highlight no longer jumps.

**Tab highlight (index mapping in `app_shell.dart`):**
- `/reservations*`, `/sos*`, `/ai-agent` → REZERVACE.
- `/profile*`, `/messages*`, `/docs*`, `/invoices`, `/contracts`, `/pobocky*`, `/loyalty`, `/shop*`, `/cart`, `/checkout`, `/voucher` → PROFIL.
- `/routes*`, `/places-map`, `/routes-map`, `/my-experiences`, `/ride/:id` → TRASY.

**Other navigation rules:**
- Tapping a tab **no longer resets** `bookingDraftProvider`, `bookingMotoProvider` or `catalogFilterProvider`.
- Re-tapping the active tab scrolls to the top. This replaces the scroll-to-top FAB.
- Tabs switch with the `tab` fade-through (`CustomTransitionPage` instead of `NoTransitionPage`).
- The global overlays are unchanged: `LanguageOverlay`, `PermissionOverlay`, `MotoIntroOverlay`, `MotoWelcomeOverlay`, `LoyaltyLevelUpWatcher`, `RideRecorderWatcher`.

**Redirects (old deep links keep working):**
- `/search` → `/motorky?dates=open`
- `/routes-list` → `/routes?seg=trasy`

### 4.2 MOTORKY (no artboard; builders of screens 1 and 2 link to it)

- **Dark compact header** (`gDark`, bottom r24):
  - Title "Motorky".
  - Date pill, h48: "Kdy jedeš? · Vyber termín". With dates: "pá 23. 10. → ne 25. 10. · 3 dny ✕". The pill opens C9 with no bike context.
  - Branch segmented control: "Všechny · Mezná · Velké Němčice".
- **Marquee strip:** shown when set in Velín.
- **Category chips:** horizontal scroll with counts, plus a "Filtry ([n])" button. It opens a light sheet with all of today's `MotoFilterPanel` content, unchanged: ŘP AM/A/B/N, kW / sedlo mm / Nm / kg sliders, "Zobrazit dnes volné", sorting (cena / výkon ↑↓), "Resetovat".
- **Active filters:** removable chips.
- **Count line:** "[n] motorek · [k] volných v termínu · 3 dny".
- **List:** C15b cards with `reveal`. With dates set, each card shows the total ("tvoje cena", bike only, the draft's pickup time, default 09:00) and a "Rozpis" button.
- **Branch detail** "Motorky na pobočce" → MOTORKY with that branch preselected. This replaces the duplicate `branches_sheet`.

### 4.3 TRASY (no artboard)

**Header** (dark, collapsing):
- Title "Trasy", a segmented control "Místa · Trasy · Moje" (web `.km-sw` style, sliding neon thumb), and a map button.
- This replaces the rotating quick links.

**Segments:**
- **Místa:** the whole of `AllPoisScreen` (search "Hledat místo…", location prompt, map preview, list).
  - "Filtry a řazení" moves into a sheet.
  - Multi-select shows a sticky "Vlastní vyjížďka ([n]) ›" → builder.
- **Trasy:** the whole of `routes_screen`: "Přes [n] tras a [m] míst", sort chips, filters, "Mapa tras". Cards become C16 sketches showing "Od tebe: [km] km".
- **Moje:** `my_experiences` ("Vytvořené trasy / Moje místa / Moje trasy", "Vytvořit novou trasu") plus recorded rides.
  - A "+" button opens: "Nahrát jízdu · Navrhnout trasu · Přidat místo" (community submit, moderation unchanged).

**Route detail:**
- Map hero: the polyline draws over 1.6 s, then POI pins pop in order with a 70 ms stagger.
- 4 stat tiles: km, čas, obtížnost, počet míst.
- Then "Místa na trase", "Galerie", recenze.
- Sticky primary "ZVOLIT TRASU – NAVIGOVAT". Secondary: "Upravit / přidat body", "Otevřít v jiné aplikaci".
- **New** ghost link "Půjč si motorku na tuhle trasu" → MOTORKY with branch = `route.branchId`.
- Swiping between sibling routes stays.

**Navigation, builder, POI sheet and maps:** unchanged. No decorative motion in navigation.

### 4.4 PROFIL (no artboard)

- **Header:** avatar with the rank ring, name, PILOT nickname (tap → nickname dialog), compact C15 rank strip.
- **Tile grid:** Zprávy ([n]), Doklady (status chip "Ověřeno" / "Chybí ŘP"), Faktury, Smlouvy, Platby, Pobočky, Věrnostní program, E-shop (only with `eshop_visible`).
- **Groups below the grid, the same rows as today:**
  - Můj účet: Osobní údaje (inline form as today), Zprávy z Moto Go, Moje doklady, Faktury a vyúčtování, Dokumenty a smlouvy, Platební metody.
  - Nastavení: Oprávnění aplikace, Notifikace, Soukromí a souhlasy, Změna hesla, Jazyk aplikace, Měna, + "Omezit animace" (optional).
  - Pomoc & Podpora: SOS (with an active booking), AI asistent, Nápověda & FAQ.
  - Ostatní: Odhlásit se, Smazat účet.

---

## 5. Flow unification decision (what happens to the duplicate flow)

**Decision:** both catalogue flows merge into **MOTORKY**, and both form steps merge into **one `/booking` stepper**.

```
DOMŮ "Kdy jedeš příště?" ─┐      ┌──────────────────────────────┐
MOTORKY date pill ────────┼─────►│ TripCalendar (one component) │──► bookingDraftProvider.dates
DOMŮ / MOTORKY / pobočka  │      └──────────────────────────────┘
 / "Znovu rezervovat" ────┴──► /moto/:id  DETAIL + KALKULAČKA (termín · předání · výbava navíc · TVOJE CENA)
                                   │ sticky "REZERVOVAT"
                                   ▼
                               /booking  STEPPER: 1 Termín a předání ✓(skips) · 2 Výbava a velikosti · 3 Kontrola a platba
                                   │ "ZAPLATIT" → bookings insert (pending/unpaid, booking_source 'app') → off-session charge / card sheet
                                   ▼
                               /success (root route, no Hero; existing MotoSuccessHero + receipt slides in under it)
PaymentContext entries (Dokonči platbu · Obnovit · Doplatek úpravy · Výměna motorky · SOS náhrada)
                               ──► /payment = only step 3's payment block (same widget), header names the mode
```

**What it removes:**
- **The REZERVOVAT tab.** `moto_search_screen.dart` is replaced by the MOTORKY screen; `DateTabsSection` and the step bubble are removed.
- **The Home bike list and filter panel.** `MotoFilterPanel` is reused unchanged inside the "Filtry" sheet.
- **The 3rd and 4th date pickers.** The detail calendar card and the form's DATUM card now open the same C9 sheet.
- **The repeated gallery, price summary and upsell on `/payment`** for new bookings.
- **Tab-tap wipes of the draft.** The draft resets only after successful payment or via "✕" on the date pill.

**State:**
- `bookingDraftProvider` is the **single** draft and holds the dates. `catalogFilterProvider` *reads* its dates from it.
- `priceQuoteProvider.family(motoId)` is the only price source for cards, calculator, stepper and edit. It calls the existing `PriceCalculator.calculate`.
- A pure `normalizeDraft(draft, moto, branch)` keeps today's silent normalisation:
  - No trailer and no delivery at self-service.
  - No passenger gear on kids' bikes.
  - Off-list sizes cleared.
  - Legacy 00:01 / 23:59 times fixed.
- The UI shows the affected options **locked with ⓘ or hidden**, so nothing disappears silently.

**Entry points:**

| Entry | Lands on | Pre-filled |
|---|---|---|
| Card (any list) | Detail | Draft dates if set |
| DOMŮ ticket S0 presets / header pill | C9 sheet → MOTORKY filtered "volné v termínu" | Dates |
| "Znovu rezervovat" (completed booking) | Detail of that bike, C9 opens | Pickup and return methods + extras of the old booking. **Dates empty. Boots never pre-filled** (incident 2026-09-28) |
| "Obnovit" (cancelled; list **and** detail) | Real restore: availability check → `/payment` "Obnovit a zaplatit" | Everything |
| Route detail "Půjč si motorku na tuhle trasu" | MOTORKY, branch preset | Branch |

**Stepper skipping:**
- From a complete calculator, step 1 arrives collapsed ✓.
- Step 2 is open only if a size is missing.
- Otherwise the user lands on step 3.

---

## 6. Price engine (one implementation)

```
days      = calendar days incl. both ends (by date, DST-safe); limits motorcycles.min_rental_days..max_rental_days
dayPrice  = price_mon…price_sun (fallback price_weekend Sat/Sun → price_weekday)
rental    = Σ dayPrice
late      = (pickupTime ≥ 12:00 && days ≥ 2) ? round(dayPrice(start)/2) : 0        // any branch, any method
extras    = Σ accessory_types.price_czk (passenger_gear 690, boots_rider 290, boots_passenger 290);
            all 0 when rank ≥ 3 (loyaltyFreeGearLevel); trailer 0 (Mezná only, get_trailer_availability)
delivery  = Σ per direction (1000 + 40 × km), km by road from Mezná 9; rounded to whole Kč [owner §13]
loyalty   = round((rental − late + extras) × pct/100)      // pct = get_loyalty_status().percent; delivery excluded
codes     = applied to (rental − late + extras + delivery − loyalty): max one % code first (rounded), then fixed
            codes/vouchers/Slevomat; never below 0; enforce validate_promo_code.min_order_amount
total     = max(0, rental − late + extras + delivery − loyalty − codes)
regular   = same with pct = 0 and extras at list price, without codes  →  "Díky ranku ušetříš" = regular − (total + codes)
cardFrom  = round(min(dayPrice) × (100 − pct)/100)          // "od X Kč/den", indicative
```

- **Not applied:** `pricing_rules`, `calc_booking_price_v2` (season, long-rental and PRVNIJIZDA discounts) and `extras_catalog`.
- **Server guards** `validate_app_loyalty_discount` and `validate_late_pickup_discount` stay. The displayed total equals what the server accepts.

**Loyalty status fails to load:** show list prices with the row "Věrnostní slevu teď nevidíme · Zkusit znovu".
- The pay button still charges exactly the displayed price. Never promise the discount "at payment", because the insert would get 0.

**Unit tests (`price_calculator_test.dart`, both trees).** BMW, Fri–Sun, Mezná:

| Scenario | Rank 2 | Rank 3 |
|---|---|---|
| A: bike only, 09:00 | 12 016 | 11 893 |
| B: A + all 3 paid items | 13 260 | 11 893 |
| C: B with pickup 12:00 | 11 539 | **10 189** |

- Delivery 25 km, A, rank 2 = 14 016.
- 10 % code, A, rank 2 = 10 814.
- Husqvarna 12:00, rank 3 = 12 027; rank 2 = 12 151.
- Weekend bike-only, rank 3: Shotgun 7 336, Husqvarna 14 176.

---

## 7. Screen 1: DOMŮ (customer hub)

**Artboard 390 × 1900** (scrolling; nav pinned at the bottom of the artboard).
**Components:** C1, C3, C4, C5, C10, C12, C15, C15b, C16. Status strip: none in this state.

```
┌──────────────────────────────────────┐ y0
│▓ 9:41 status bar                     ▓│
│▓ (MG◔) Ahoj, [přezdívka]   (bot)(bell[n])▓│ y59
│▓       ● Motorkář · sleva 3 %        ▓│ y88
│▓ ╭ cal  Kdy jedeš příště? Vyber termín › ╮▓│ y124–172
│▓ ╰──────────────────────────────────╯▓│
├──────────────────────────────────────┤ y188 (bottom r24)
│ » [text banneru z Velínu]            │ y188–220 marquee (only if set)
│┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓│ y236 TICKET (dark, Hero res-img-{id})
│┃[photo Husqvarna 358×150]           ┃│
│┃ (ZA 5 DNÍ)            (✓ PŘIPRAVENO)┃│
│┃ Husqvarna 701 SM                   ┃│ y398
│┃ pin MotoGo24 Velké Němčice · samoobsluha┃│
│┃ pá 16. 10. 12:00 → ne 18. 10. 23:59 · 3 dny┃│
│┃ ✓Zaplaceno━✓Doklady━✓Kódy━◉Výdej   ┃│ y478
│┃ ½ Kiosk ti motorku vydá v pá od 12:00┃│
│┃ [ KÓDY A POSTUP NA POBOČCE      › ] ┃│ y566–618 primary (glow)
│┃ (Navigovat)  (Upravit)  (Více)      ┃│ y628–672
│┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛│ y688
│┌ RANK ──────────────────────────────┐│ y712–842
│ Motorky pro tebe            Všechny ›│ y866
│ [BMW card][Shotgun card][Husky…      │ y898–1238
│ Trasy z pobočky Velké Němčice  Všechny trasy ›│ y1262
│ [sketch card][sketch card][…         │ y1294–1544
│ Pobočky                              │ y1568
│ [Mezná card]      [V. Němčice card]  │ y1600–1760
│ DOMŮ  MOTORKY  REZERVACE  TRASY  PROFIL│ y1802–1900 (DOMŮ active)
└──────────────────────────────────────┘
```

### Sections

**1. Header** (`gDark`, bottom radius 24, y 0–188)
- MG logo 44 px inside the rank ring (stroke 3, rank colour, progress arc) → `/loyalty`. The old logo route stays.
- "Ahoj, [přezdívka]" 20/800 white. Tap → existing nickname dialog. With no nickname: "Ahoj, jezdče" + link "Nastav si přezdívku".
- Rank chip "Motorkář · sleva 3 %" → `/loyalty`. It replaces the "PILOT: {nick}" glow badge.
- Right, two 40 px circles (white@.08, border neon@.22):
  - Bot → `/ai-agent`.
  - Bell with a count pill "[n]" → `/messages`.
- **Date pill** (h48, r999, white@.08, border 1.5 neon@.4):
  - Calendar icon (neon) + "Kdy jedeš příště?" 14/800 white + "Vyber termín" 13/600 `#A8FF9F` + chevron.
  - Tap → C9 (no bike), then MOTORKY filtered. It replaces the fake search "Kdy jedete? Vyberte termín…".
  - With draft dates it shows "pá 23. 10. → ne 25. 10. · 3 dny ✕".

**2. Marquee:** 32 px strip, `#0E2A1C`, neon text 12.5/700, data from `banner_provider`. Static under reduced motion. Shown only when set.

**3. Ticket** (dark hero card r20, the one dark card). Content comes from `TicketState.of(reservations, docsStatus, sosDraft, activeRide)`, a pure function over the existing getters: `displayStatus`, `paymentStatus`, `isSelfService`, `kioskReleasePending`, `protocolSigned`, `issuedAt`, `sosAllowed`, `ownGearEffective`, `rating`.

**Artboard state = S6.** Draw it as follows:
- **Photo:** 358×150, cover, top corners r20, Hero `res-img-{id}`. Overlays at the top: eyebrow pill "ZA 5 DNÍ" on the left, status pill ok-on-dark "✓ PŘIPRAVENO" on the right.
- **Text:**
  - "Husqvarna 701 SM" 20/800 white.
  - Pin icon + "MotoGo24 Velké Němčice · samoobsluha" 13/600 `#CFE7DA`.
  - Calendar icon + "pá 16. 10. 12:00 → ne 18. 10. 23:59 · 3 dny" 13/700 white.
- **Mini timeline** (C10 on dark, 4 nodes): Zaplaceno ✓, Doklady ✓, Kódy ✓, Výdej ◉ (sub "pá 12:00").
- **Late-gate line:** C19 compact, without the dashed border: "½ Kiosk ti motorku vydá v pá od 12:00" 12.5/700 white.
- **Primary** "KÓDY A POSTUP NA POBOČCE" → `/reservations/:id` scrolled to CO TEĎ (Hero).
- **Secondary row**, 3 ghost-dark buttons, each 1/3 width:
  - "Navigovat" → maps to Boudky.
  - "Upravit" → edit chooser.
  - "Více" → sheet: Detail rezervace · Dokumenty · Zrušit rezervaci.

**Ticket states** (priority when there are several bookings: S1 > S2 > S8 / S9 > S7 > upcoming soonest > S10 > S0):

| State | Condition | Eyebrow | Body | Primary | Secondary | Live loop |
|---|---|---|---|---|---|---|
| S0 | No upcoming or active booking | "KAM VYRAZÍŠ PŘÍŠTĚ?" | Preset chips "Nejbližší víkend · [d.–d. m.]", "Další víkend · [d.–d. m.]", "Jiný termín" | "VYBRAT MOTORKU" | Link "Znovu: [poslední motorka]" (if any completed) | — |
| S1 | SOS draft unfinished | "SOS · ROZPRACOVÁNO" (red) | Step of the SOS timeline | "DOKONČIT HLÁŠENÍ" | — | Red ping |
| S2 | pending + unpaid (30 min window) | "DOKONČI PLATBU" | Countdown ring "mm:ss" (tabular, updates without animation) | "ZAPLATIT [částka] KČ" → `/payment` | "Zrušit" | Ping |
| S3 | Upcoming, documents missing | "ZA [n] DNÍ · [datum]" | Checklist ✓ Zaplaceno · ⚠ Doklady · ○ Kódy + "Bez ověřených dokladů ti kódy neuvolníme." (staffed: "Doklady potřebujeme před převzetím.") | "NAHRÁT DOKLADY" → `/docs` | Navigovat · Upravit · Více | — |
| S4 | Upcoming, staffed (Mezná), at branch | "ZA [n] DNÍ" | "Čekáme tě v [den] v [čas] · Mezná 9, Pelhřimov · nonstop" | "NAVIGOVAT NA POBOČKU" | Upravit · Zavolat · Více | — |
| S5 | Upcoming, delivery | "ZA [n] DNÍ" | "Přivezeme ti ji · [adresa] · [čas]" | "DETAIL REZERVACE" | Upravit · Zavolat | — |
| **S6** | Upcoming, self-service, documents OK | see artboard | | "KÓDY A POSTUP NA POBOČCE" | Navigovat · Upravit · Více | — |
| S7 | Pickup day, self-service | "DNES · VÝDEJ OD 12:00" (or "DNES · VYZVEDNUTÍ") | Codes 1 → 2 → 3 as C11, **masked `• • • •` until tapped "Zobrazit kódy"** | "POSTUP NA POBOČCE" | Navigovat · Kódy na celou obrazovku | Ping + scan |
| S8 | `displayStatus == aktivni` | "JEDEŠ · DEN [x] ZE [y]" | Day ring. "Vrať do [datum] [23:59 / čas] · [pobočka]". "● Nahrávám jízdu · [km] km" when recording. **Round red SOS button 48 px** at the card's right edge when `sosAllowed` | "DETAIL A VRÁCENÍ" | Prodloužit · Navigovat · Kódy (self-service) | Ping + scan |
| S9 | Return day | "DNES VRACÍŠ · DO [23:59 / čas]" | "[pobočka]" + "Vrácení na kiosku tvoji rezervaci dokončí samo." (self-service) | "NAVIGOVAT NA POBOČKU" | Kódy · SOS | Ping |
| S10 | Completed ≤ 14 days ago, `rating == null` | "JAK SE JELO?" | 5 inline stars (`rateBooking`) | "ZNOVU REZERVOVAT" | "Ohodnotit na Google" | — |

- **"Další rezervace ([n]) ›"**: a light row under the ticket, only when there are 2+ upcoming or active bookings. Not drawn.

**4. Rank strip (C15).** "Motorkář" · "Level 3 z 20 · sleva 3 % na každou jízdu v appce" · "Výbava spolujezdce a boty máš zdarma" · bar at 5 / 6 (example) · "Ještě 1 b. → Stálý jezdec (4 %)".

**5. "Motorky pro tebe"** (filtered by licence groups from the profile; falls back to all)
- `PageView(viewportFraction: .76)` of C15b cards, each 296 wide. No availability badge (unknown without dates).
  - **BMW R 1200 GS Adventure:** pin Mezná · pills "92 kW", "ŘP A", "Cestovní" · "od **2 727 Kč**/den" ~~2 811~~ · "pá–ne 11 893 Kč"
  - **Royal Enfield Shotgun 650:** pin Mezná · "34,6 kW", "ŘP A2", "Chopper" · "od **1 778 Kč**/den" ~~1 833~~ · "pá–ne 7 336 Kč"
  - **Husqvarna 701 SM:** pin Velké Němčice · "55 kW", "ŘP A", "Supermoto" · "od **3 437 Kč**/den" ~~3 543~~ · "pá–ne 14 176 Kč"
- "Všechny ›" → MOTORKY.

**6. "Trasy z pobočky Velké Němčice"**
- The branch is the next booking's branch; otherwise the last booking's; otherwise all.
- 3 C16 cards in a `PageView` (.76), filtered by `routes.branch_id`: "[název trasy]", "[km] km · [čas] · [obtížnost]".
- "Všechny trasy ›" → TRASY (segment Trasy).

**7. Pobočky:** two cards side by side (171 wide each).
- Photo 171×90 `[fotka pobočky]`.
- **"MotoGo24 Mezná"** / "Mezná 9, 393 01 Pelhřimov" / chip "S obsluhou · nonstop".
- **"MotoGo24 Velké Němčice"** / "Boudky, 691 63 Brno - Velké Němčice" / chip "Samoobsluha · kód z appky".
- Tap → `/pobocky/:i`.

**8. Nav (C1):** DOMŮ active.

### Interactions and motion

| Element | Behaviour |
|---|---|
| Sections | `reveal`, stagger 70 ms, first build per session only |
| Ticket state change (e.g. documents verified → S6) | `AnimatedSwitcher` `enter` 350 ms. Newly ✓ nodes `pop` + haptic. Connectors `connector` |
| Primary CTA | `glow` + `shine`: the screen's only CTA loop. In S7, S8 and S1 the live `ping` / `scan` is the second allowed loop |
| Ticket → detail | Hero `res-img-{id}` (inside the shell) |
| Bike card → detail | Hero `moto-img-{id}` |
| Rank bar | Fills from the last seen value (`connector`-style 700 ms) |
| Route sketches | `path` draw once when first built |
| Reduced motion | Everything static; Hero off |

---

## 8. Screen 2: Motorcycle detail with live calculator (`/moto/:id`)

**Artboard 390 × 2400.** Nav hidden. The sticky bar (C8) is pinned at the artboard bottom, y 2290–2400, overlapping content as it does on a device.
**Components:** C3, C4, C5, C6, C7, C8, C9 (as an interaction), C12, C13, C14, C19.

```
┌──────────────────────────────────────┐
│ [BMW photo 390×292, cover, Hero]     │ y0–292
│ (‹)                    ( ‹ 1 / [n] › )│ y55
│ (● Volná v tvém termínu)  • ○ ○ ○ (cam 1/[n])│ y248
│ (CESTOVNÍ) (ŘP A)                    │ y308
│ BMW R 1200 GS Adventure              │ y334 (25/700)
│ pin MotoGo24 Mezná · s obsluhou nonstop ›│ y400
│ [92 kW][1 254 cm³][[mm]][[kg]]       │ y432–514 spec tiles
│ Všechny parametry (8) ▾              │ y522
│ V kostce: ([údaj 1])([údaj 2])…      │ y566–630
│┏━━ SPOČÍTEJ SI CENU ━━ (Motorkář −3 %)┓│ y650 calculator (dark, r22)
│┃ ① TERMÍN                    (3 dny) ┃│
│┃ [VYZVEDNUTÍ pá 23. 10.]→[VRÁCENÍ ne 25. 10.]┃│
│┃ ② VYZVEDNUTÍ                        ┃│
│┃ [● Na pobočce][Přistavení od 1 000 Kč]┃│
│┃ Čas vyzvednutí                      ┃│
│┃ 08:00 09:00 10:00 11:00 [12:00½] 13:00½ 14:00½ 16:00½ Jiný čas ┃│
│┃ ┆½ Od 12:00 máš 1. den za polovinu  −1 757 Kč┆┃│
│┃ VRÁCENÍ  [● Na pobočce][Odvoz od 1 000 Kč]┃│
│┃ Čas vrácení 16:00 17:00 18:00 [19:00] 20:00 Jiný čas┃│
│┃ ③ VÝBAVA   (Motorkář: výbava navíc zdarma)┃│
│┃ check V ceně pro řidiče: helma, rukavice, bunda, kalhoty, kukla┃│
│┃ ☑ Výbava spolujezdce  ~~690~~ 0 Kč  ┃│
│┃ ☑ Boty řidiče         ~~290~~ 0 Kč  ┃│
│┃ ☑ Boty spolujezdce    ~~290~~ 0 Kč  ┃│
│┃ ☐ Vozík (přívěs)          zdarma    ┃│
│┃ Velikosti vybereš v dalším kroku.   ┃│
│┃ ╭◠◠◠◠◠◠ RECEIPT ◠◠◠◠◠◠◠◠◠◠◠◠◠◠╮   ┃│
│┃ │ TVOJE CENA              (3 dny)│   ┃│
│┃ │ pá 23. 10. 12:00 → ne 25. 10. 19:00│┃│
│┃ │ ▆▧ █ ▇   pá 3 514 · so 4 882 · ne 3 865│┃│
│┃ │ Pronájem · 3 dny      12 261 Kč│   ┃│
│┃ │ Vyzvednutí od 12:00 · 1. den ½ −1 757 Kč│┃│
│┃ │ Výbava navíc (ceník 1 270 Kč)  0 Kč│┃│
│┃ │ Věrnostní sleva · Motorkář 3 % −315 Kč│┃│
│┃ │▓ TVOJE CENA      10 189 Kč (−1 704)▓│┃│
│┃ │ Díky ranku Motorkář ušetříš 1 585 Kč│┃│
│┃ │ Bez kauce · konečná cena · nejsme plátci DPH│┃│
│┃ ╰──────────────────────────────╯   ┃│
│┃ [ REZERVOVAT ZA 10 189 KČ  → ]      ┃│ y1876–1932
│┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛│ y1950
│ Popis  (4 lines + fade) (Celý popis) │ y1970–2110
│ Víc o motorce                        │ y2126
│ ▶ Video · [délka]                   ›│
│ Návod k obsluze · Zobrazit · Hledat ›│
│ Ceník podle dne                     ▾│
│ Pobočka Mezná · Mezná 9, Pelhřimov ›│
│▓ Tvoje cena · 3 dny  10 189 Kč [REZERVOVAT]▓│ y2290–2400 sticky
└──────────────────────────────────────┘
```

### Sections

**1. Gallery** (y 0–292, 4:3, `BoxFit.cover` on `imgPlaceholder`, Hero `moto-img-{id}`)
- Swipe changes **photos only**. Video(s) are the last slides with a play badge (`MotoVideoPlayer`).
- Overlays:
  - **Back:** 40 px white@.92 circle, icon `#1A2E22`.
  - **Bike pager:** pill h40, `#0A1F14`@.8, "‹ 1 / [n] ›" 13/800 white, over the same filtered list as today's pager.
  - **Status pill:** "● Volná v tvém termínu" with `ping`. Alternatives: "Dnes volná" with no dates; warn variant "Obsazená v tvém termínu".
  - **Dots:** active dot widens 6 → 18 px over 200 ms.
  - **Count pill:** camera icon + "1 / [n]", plus a "▶ Video" pill when a video exists (jumps to the video slide).
- Tap → existing `FullscreenGallery` (fade route).
- **The bike pager is arrows-only.** Each change slides the content horizontally under the static top bar (280 ms `easeOutCubic`). On the first visit the pager pill does one `pop` (shared_prefs flag).

**2. Title block**
- Tags: category tag "CESTOVNÍ" + neutral pill "ŘP A".
- H1 "BMW R 1200 GS Adventure" 25/700.
- Meta row 13.5/700 `#2C4A3A`: "pin MotoGo24 Mezná · s obsluhou nonstop ›" → `/pobocky/:i`.
  - Self-service variant: "MotoGo24 Velké Němčice · samoobsluha · kód z appky".

**3. Key specs:** 4 tiles, 83.5 × 82, `specTile`, r16, border `#D4E8E0`. Each tile: 28 px white icon box (r8, `#0D6E0D` icon), value 15/800, label 11/700 `#4A6B5A`. Tiles: Výkon "92 kW" · Motor "1 254 cm³" · Výška sedla "[mm]" · Hmotnost "[kg]".
- Link "Všechny parametry (8) ▾" expands today's 2-column grid in place: Motor "1 254 cm³ · [typ]", Výkon "92 kW", Točivý moment "[Nm]", Hmotnost "[kg]", Nádrž "[l]", Výška sedla "[mm]", Skupina ŘP "A", ABS/ASC "[Ano/Ne]".

**4. "V kostce":** label 12/800 + horizontal chips (pill style, 12.5/700) holding all `short_desc_fields` from Velín: "[údaj 1]" … "[údaj 6]".

**5. Calculator "SPOČÍTEJ SI CENU"** (C5 dark, r22, `shDark`; `scanOnce` on every recalculation)
- Header: eyebrow pill "SPOČÍTEJ SI CENU" + rank chip "Motorkář · −3 %".
- **Shared widgets:** each block below is one of `core/booking_form_*_section.dart` re-skinned with `tone: dark`. The stepper uses the same widgets with `tone: light`.

- **① TERMÍN** (kicker 11.5/800 `#A8FF9F` + "3 dny" pill)
  - Two tiles, h60 (white@.05, border neon@.22, r14): "VYZVEDNUTÍ / pá 23. 10." → "VRÁCENÍ / ne 25. 10.". Tapping either opens C9 in bike context.
  - Without dates: the tiles show "Vyber" plus the presets "Nejbližší víkend · 16.–18. 10.", "Další víkend · 23.–25. 10.".
  - Limits: end days beyond `max_rental_days` are disabled in C9. A blocker shows in the sticky bar, e.g. Shotgun "Tuhle motorku půjčujeme nejdéle na 30 dní".

- **② VYZVEDNUTÍ**
  - Segmented: "Na pobočce" | "Přistavení" / "od 1 000 Kč".
    - Přistavení opens the existing address sheet + `map_picker.dart`. Afterwards the option reads "Přistavení · [km] km · [1 000 + 40 × km] Kč".
    - Self-service: the option is locked, "Jen na pobočce ⓘ". C13 shows `ssNoDeliveryInfo` in full.
  - "Čas vyzvednutí" 12/800 `#9FC4B1`, then a horizontal row of choice chips:
    - 08:00, 09:00, 10:00, 11:00, **12:00½** (selected), 13:00½, 14:00½, 16:00½, "Jiný čas".
    - "Jiný čas" opens a wheel: 0–23 h, 15-min steps, as in today's `TimeDropdownField`.
    - **Chips from 12:00 are never disabled.** The ½ tag shows only when days ≥ 2.
  - Line item (C19), shown when pickup ≥ 12:00 and days ≥ 2: "Od 12:00 máš 1. den za polovinu" + "−1 757 Kč".
    - Self-service adds " · kiosk vydá od 12:00".
    - ⓘ shows the web sentence "Vyzvedni si motorku od 12:00 a první den máš za polovinu (výpůjčka na 2 a více dní)." or, at self-service, `ssPickupHint`.

- **VRÁCENÍ**
  - Segmented: "Na pobočce" | "Odvoz" / "od 1 000 Kč".
  - "Čas vrácení" chips: 16:00, 17:00, 18:00, **19:00** (default), 20:00, "Jiný čas".
  - Self-service: one locked chip "do 23:59 · vrátíš kdykoli poslední den" (forced 23:59).

- **③ VÝBAVA** (rank badge on the right: "Motorkář: výbava navíc zdarma", neon@.16, `pop` the first time an item is ticked)
  - Info line with check icon, 12.5/600 `#CFE7DA`: "V ceně pro řidiče: helma, rukavice, bunda, kalhoty, kukla".
  - Paid tiles (h56, r14, white@.05, border neon@.22). Each: checkbox 22 (checked = `gNeon` + `onNeon` check), title 14/800 white, sub 11.5/600 `#9FC4B1`, right side list price struck `#8FB3A1` + "0 Kč" 14/800 neon.
    - "Výbava spolujezdce" / "Helma, rukavice, vesta" / ~~690 Kč~~ **0 Kč**
    - "Boty řidiče" / ~~290 Kč~~ **0 Kč**
    - "Boty spolujezdce" / ~~290 Kč~~ **0 Kč**
    - "Vozík (přívěs)" / "Mezná · podle dostupnosti" / **zdarma**. Unchecked. Shown only at Mezná when `get_trailer_availability` reports one free; otherwise disabled with "V termínu obsazený".
  - Below rank 3 the prices are not struck; they show "690 Kč" / "290 Kč".
  - Kids' bikes (`N`): both passenger tiles are hidden.
  - Self-service: the trailer row is replaced by the one-liner "Vozík jen na pobočce Mezná".
  - Footer 12/600 `#9FC4B1`: "Velikosti vybereš v dalším kroku." Sizes are **not** in the calculator.

- **Receipt (C6),** data exactly as in §1 R2:
  - Bars: pá 3 514 (56 px, top half striped), so 4 882 (78 px, weekend gradient), ne 3 865 (62 px, weekend gradient).
  - Rows: "Pronájem · 3 dny" 12 261 Kč · "Vyzvednutí od 12:00 · 1. den ½" −1 757 Kč · "Výbava navíc" "(ceník 1 270 Kč)" 0 Kč · "Věrnostní sleva · Motorkář 3 %" −315 Kč.
  - Total "TVOJE CENA **10 189 Kč**". Delta chip "celkem −1 704 Kč" (example: the change from 09:00 to 12:00, 11 893 → 10 189).
  - "Díky ranku Motorkář ušetříš 1 585 Kč" · "Bez kauce · konečná cena · nejsme plátci DPH".
  - With delivery: an extra row "Přistavení · [km] km" "[1 000 + 40 × km] Kč" (outside the loyalty base).
- **In-card CTA** (primary, h56): "REZERVOVAT ZA 10 189 KČ →" → `/booking`. The Hero thumbnail flies to the stepper recap.

**6. "Ceník podle dne"** (shown only when no dates are set, placed **above** the calculator; with dates it collapses into section 8)
- Headline "Tvoje cena od **2 727 Kč**/den" + 12/600 `#4A6B5A` "(ceník od 2 811 Kč · −3 % Motorkář)".
- 7 bars, width 30, gap 14, max 78 px, values above at 11/800:
  - Po 3 514 (56) · Út 2 811 (45) · St 2 811 (45) · Čt 3 163 (51) · Pá 3 514 (56) · So 4 882 (78, weekend) · Ne 3 865 (62, weekend).
- Note 11.5/600: "1 den = kalendářní den (0:01–24:00), ne 24 h od převzetí."
- **Only one bar chart is ever visible:** this one before dates, the receipt bars after.

**7. Popis**
- Title 17/800.
- The DB HTML renders through `SimpleHtmlText` (p / br / ul / li / b / i → `TextSpan`, about 60–150 lines) instead of `stripHtml`.
- Clamped to 4 lines (14/600 lh 1.5 `#2C4A3A`) with a `ShaderMask` fade.
- Ghost-light pill "Celý popis" → C13 with the full text.

**8. "Víc o motorce":** C14 rows.
- "Video · [délka]" → `MotoVideoPlayer` in a sheet.
- "Návod k obsluze · Zobrazit · Hledat" → existing viewer. When missing, the row is dimmed: "Návod zatím není k dispozici".
- "Ceník podle dne ▾" → section 6 content (when dates are set).
- "Pobočka Mezná · Mezná 9, 393 01 Pelhřimov" → branch detail, with a "Navigovat" icon.

**9. Sticky bar (C8)**
- Visible whenever the in-card CTA row is outside the viewport. Hidden while it is inside, so the same price never appears twice.

| State | Left | Button |
|---|---|---|
| No dates | "Tvoje cena od" / "**2 727 Kč**/den" | "VYBRAT TERMÍN" → C9 |
| Valid | "Tvoje cena · 3 dny" / "**10 189 Kč**" | "REZERVOVAT" (`glow` + `shine`) |
| Busy | amber "V tomhle termínu je obsazená" | "ZMĚNIT TERMÍN" |
| Over limit | amber "Nejdéle na [max] dní" | "ZMĚNIT TERMÍN" |
| Loyalty failed | "Tvoje cena · 3 dny" + receipt row "Věrnostní slevu teď nevidíme · Zkusit znovu" | "REZERVOVAT" (list price) |

### Motion

| Trigger | Effect |
|---|---|
| Card → detail | Hero image 350 ms |
| Any input change | Receipt rows appear or leave with `AnimatedSize` 250 + fade + 8 px slide. The total `bump`s. The delta chip shows the net change. `scanOnce` over the calculator |
| Extra ticked at rank ≥ 3 | `strike` across the list price → "0 Kč" `pop` → rank badge `pop` (first time) |
| Days reach 2 | ½ tags `pop` on the 12:00+ chips |
| Pickup set to ≥ 12:00 | Pá bar stripes slide in (300 ms). C19 strip enters with `enter` |
| Receipt bars | `bars` on first show and on date change |
| C9 open | `sheet`. Day `pop`, range fill |
| Sticky bar | `sticky`. Blocker text crossfades 200 ms. The button changes colour over 180 ms |
| Loops | Only the CTA `glow`/`shine` (paused when the bar is hidden) + the "Volná" `ping` |
| Reduced motion | All snaps; Hero off; no loops |

---

## 9. Screen 3: Unified booking flow (`/booking`, one stepper with live price)

- **Entry file:** `core/booking_form_widget.dart`, which stays the only live form (CLAUDE.md rule 4). Its section files are re-skinned; no new form generation.
- **Artboard 390 × 2100.** Page bg `pageWash`. Nav hidden. Live summary (C8, two-row variant) pinned at y 1934–2100.
- **Artboard state:** arrived from the calculator. Step 1 is done, step 2 is current with one blocker (rider boots size), step 3 is visible.
- **Components:** C3, C4 (light tone), C5 step cards, C6 (inside the summary sheet), C7, C8, C13, C17, C18.

```
┌──────────────────────────────────────┐
│ (‹)  Rezervace                       │ y47–103 (22/800)
│      BMW R 1200 GS Adventure         │ 12.5/700 #4A6B5A
│ (✓)━━━━━(2 Výbava a velikosti)━━━(3) │ y115–157 C18
│ ┌[thumb 64×48] BMW R 1200 GS Adventure┐│ y173–255 recap (Hero target)
│ │ MotoGo24 Mezná · pá 23. 10. → ne 25. 10.││
│ ┌ (✓) TERMÍN A PŘEDÁNÍ        Změnit ┐│ y271–375 done
│ │ pá 23. 10. 12:00 → ne 25. 10. 19:00 · 3 dny││
│ │ Vyzvednutí i vrácení na pobočce Mezná││
│ ┏ (2) VÝBAVA A VELIKOSTI ━━━━━━━━━━━━┓│ y391–1131 current (ring)
│ ┃ V ceně pro řidiče: (helma)(rukavice)(bunda)(kalhoty)(kukla)┃│
│ ┃ Mám vlastní výbavu              [○ ]┃│
│ ┃ TVOJE VELIKOSTI · z profilu         ┃│
│ ┃ [Helma · [M]]   [Rukavice · [L]]    ┃│
│ ┃ [Bunda · [L]]   [Kalhoty · [M]]     ┃│
│ ┃ VÝBAVA NAVÍC   (Motorkář: zdarma)   ┃│
│ ┃ ☑ Výbava spolujezdce  ~~690~~ 0 Kč  ┃│
│ ┃   [Helma [L]][Rukavice [M]][Bunda [L]][Kalhoty [L]]┃│
│ ┃ ☑ Boty řidiče  ~~290~~ 0 Kč  [Velikost · Vyber]◄ amber┃│
│ ┃ ☑ Boty spolujezdce ~~290~~ 0 Kč [Velikost · [40]]┃│
│ ┃ ☐ Vozík (přívěs) · Mezná · zdarma   ┃│
│ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛│
│ ┌ (3) KONTROLA A PLATBA ─────────────┐│ y1147–1760
│ │ Slevový kód nebo poukaz            ││
│ │ [ Zadej kód            ][ POUŽÍT ] ││
│ │ + Poznámka k rezervaci (nepovinné) ││
│ │ ☐ Souhlasím s obchodními podmínkami (VOP) ›││
│ │ ☐ Souhlasím se zpracováním osobních údajů ›││
│ │ PLATBA                             ││
│ │ [card icon [uložená karta •••• XXXX]  Změnit ›]││
│ │ lock Platba přes Stripe · PCI DSS Level 1││
│ │ Po klepnutí na Zaplatit máš 30 minut na dokončení platby.││
│ └────────────────────────────────────┘│
│▓ Tvoje cena · 3 dny        Rozpis ▴ ▓│ y1934–2100
│▓ 10 189 Kč                          ▓│
│▓ Chybí: velikost bot řidiče [DOPLNIT ↓]▓│
└──────────────────────────────────────┘
```

### Sections

**1. App bar**
- Back 40 px circle (white, border `#E1EFE9`) → back to the detail with its state intact.
- "Rezervace" 22/800 + bike name 12.5/700 `#4A6B5A`.
- After the insert (payment window running), a right-aligned chip "⏱ [mm:ss]" (warn pill, tabular).

**2. Step progress (C18):** "Termín a předání" ✓ → **"Výbava a velikosti"** (current, label expanded) → "Kontrola a platba".

**3. Recap:** light card. Thumbnail 64×48 r10 (Hero `moto-img-{id}` lands here), title 14/800, line 12/600 "MotoGo24 Mezná · pá 23. 10. → ne 25. 10.".

**4. Step 1 "TERMÍN A PŘEDÁNÍ"**
- Done state (collapsed): 28 px `gNeon` ✓ + kicker 12/800 `#0D6E0D` + "Změnit" link. Lines: "pá 23. 10. 12:00 → ne 25. 10. 19:00 · 3 dny" 14/700 and "Vyzvednutí i vrácení na pobočce Mezná" 12.5/600.
- "Změnit" expands in place with the calculator blocks ①② in `tone: light`: date tiles → C9, segmented controls, time chips with the ½ tag, C19 line item.
- **Entered without the calculator** (old deep link, card shortcut): this step opens expanded and is current.

**5. Step 2 "VÝBAVA A VELIKOSTI"** (current: `shCurrent` ring)
- **Free gear:** 5 small check chips (h28, `checkedBg`, `#0D4F1C` 12/700): "helma", "rukavice", "bunda", "kalhoty", "kukla".
- **Own gear:** "Mám vlastní výbavu" switch row, sub "Velikosti pak nevybíráš".
  - Self-service adds the sub "· bez kódu šatny".
  - When on, the size grid collapses to one chip "Vlastní výbava – velikosti nepotřebujeme".
- **"TVOJE VELIKOSTI · z profilu"** (pre-filled from `profiles.gear_sizes.rider`): 2×2 size chips (167 × 48): Helma "[M]", Rukavice "[L]", Bunda "[L]", Kalhoty "[M]".
  - Self-service size lists come from `gearSizesFor(…, selfService)`.
- **"VÝBAVA NAVÍC"** (same draft as calculator ③; light tiles; rank badge on the right):
  - "Výbava spolujezdce" ~~690~~ 0 Kč. Compact size chips (h36) from today's passenger sheet: Helma "[L]", Rukavice "[M]", Bunda "[L]", Kalhoty "[L]" (example values).
  - "Boty řidiče" ~~290~~ 0 Kč, size chip **missing**: "Velikost · Vyber" in amber. **This is the blocker.** Boots are never pre-filled. The size list is 39–48 (owner question §13).
  - "Boty spolujezdce" ~~290~~ 0 Kč, size "[40]".
  - "Vozík (přívěs)" · "Mezná · podle dostupnosti" · zdarma, unchecked.
- **Upsell:** "Přidat z e-shopu" (collapsed row), only when `reservation_upsell` is on, which it is not today. Not drawn.
- **Completion:** when all sizes are set, the card collapses to "✓ VÝBAVA" + "Helma [M] · Rukavice [L] · Bunda [L] · Kalhoty [M] · boty [43] · spolujezdec + boty [40]" + "Změnit".

**6. Step 3 "KONTROLA A PLATBA"**
- Before it becomes current, its number circle is `#E6F2ED` with "3" in `#4A6B5A`.
- **Profile check** (only when a field is missing; not drawn): warn row "Chybí ti [údaj] pro smlouvu" + secondary-dark "DOPLNIT".
  - It opens a light sheet with **only** the missing Osobní údaje fields (name, birth date, ID, licence number and expiry, licence groups). The user never leaves the stepper.
  - It replaces the "Doplnit v profilu" banner.
- **"Slevový kód nebo poukaz":** input h52 (`input`, border 1.5 `#CFE3DA`, placeholder "Zadej kód") + secondary-dark "POUŽÍT".
  - Validation as today: `validate_promo_code` → `validate_voucher_code` → edge `slevomat-voucher`.
  - Success: a row "Slevový kód [KÓD] −[X] Kč" slides into the receipt + delta chip + `bump`.
  - Errors (inline, `errLight`): "Tenhle kód neznáme" / "Kód platí od [min_order_amount] Kč" (new enforcement) / "Kód už vypršel".
- **"+ Poznámka k rezervaci (nepovinné)":** C14 collapsed → textarea.
- **Consents:** rows h56, checkbox 24 (r6; checked `gNeon` + `onNeon` check, `pop`). The link part opens the existing document viewer.
  - "Souhlasím s obchodními podmínkami (VOP)"
  - "Souhlasím se zpracováním osobních údajů"
  - Kids' bike only: "[souhlas zákonného zástupce – stávající text]"
- **PLATBA:**
  - Method row h56 (`inputAlt`, r14): card icon + "[uložená karta •••• XXXX]" + "Změnit ›".
  - Android shows Google Pay; iOS shows Apple Pay and **no manual card entry**. These are the existing platform files, called as they are: `card_payment_sheet.dart`, `payment_methods_screen.dart`, `apple_pay_failure.dart`, `payment_error_mapper.dart`.
  - Lock icon + "Platba přes Stripe · PCI DSS Level 1" 12/600 `#4A6B5A`.
  - Note 12/600 `#6C8A7B`: "Po klepnutí na Zaplatit máš 30 minut na dokončení platby."

**7. Live summary (C8, two rows, h132 + safe area)**
- Row 1: "Tvoje cena · 3 dny" + right link "Rozpis ▴". "Rozpis" opens a dark sheet with the C6 receipt: same rows as the detail plus any code row.
- Row 2: "**10 189 Kč**" + delta chip slot.
- Row 3:

| State | Left | Button |
|---|---|---|
| Blocked (artboard) | amber "Chybí: velikost bot řidiče" | ghost-dark "DOPLNIT ↓" (scrolls to the chip + `pop` ring) |
| Next blocker types | "Potvrď souhlasy" / "Doplň údaje pro smlouvu" / "Vyber termín" / "[chyba adresy]" | "DOPLNIT ↓" |
| All valid | "Vše připraveno" in `#A8FF9F` | Primary "ZAPLATIT 10 189 KČ" (`glow` + `shine`) |
| Total = 0 | — | "POTVRDIT OBJEDNÁVKU (ZDARMA) →" |
| Charging | spinner | Disabled. Back gesture blocked during the charge |

- **Tap ZAPLATIT:**
  1. `bookings` insert (pending / unpaid, `booking_source:'app'`, stored price fields as today).
  2. Off-session charge, or the card sheet.
  3. Success → `/success`.
  4. If the card sheet is abandoned: the "⏱ mm:ss" chip appears, plus DOMŮ ticket S2 and status strip item 2.

### `/payment` modes (same pay block, no gallery)
- **Header** names the mode: "Dokonči platbu" / "Obnovit a zaplatit" / "Doplatek za úpravu" / "Doplatek za výměnu motorky" / "Platba za náhradní motorku".
- **Recap row:** the booking from `PaymentContext`.
- **Receipt:** C6 in delta mode where it applies.
- **Primary:** "ZAPLATIT [X] KČ" / "DOPLATIT [X] KČ" / "OBNOVIT A ZAPLATIT".

### `/success` (root route, content unchanged, no Hero)
- `MotoSuccessHero`, then "Rezervace potvrzena!" / "Tvoje rezervace je aktivní", "pá 23. 10. 12:00 · Mezná".
- The receipt slides down from under the hero (500 ms `easeOutCubic`). The level-up overlay, if it fires, runs after it.
- Documents card (3 variants). When documents are missing the primary is "NAHRÁT DOKLADY TEĎ" and "Moje rezervace" becomes a text link.
- "K vyzvednutí" + "Otevřít v mapě"; "Bezpečnostní pokyny" collapsed; "Synchronizováno s webem".

### Motion

| Trigger | Effect |
|---|---|
| Enter | `push`. Nav slides out. Hero thumbnail lands in the recap |
| Step done | Card collapses (`AnimatedSize` 300). ✓ `pop` + haptic. C18 line `scaleX` 450. Next label expands 400 |
| DOPLNIT | Scroll 350 `easeInOut` + one `pop` on the amber chip |
| Size chosen / consent ticked | `pop` 280. The blocker text crossfades to the next blocker |
| Code applied | Row enters (`enter`). Total `bump`. Delta chip |
| Becomes valid | Button colour transition 180. Glow starts. Only one loop on screen |
| Reduced motion | Snaps. Haptics kept |

---

## 10. Screen 4: Reservation detail and management (`/reservations/:id`)

**Artboard 390 × 2200.** Nav visible (REZERVACE active).
**Components:** C1, C3 (action tiles), C4, C5, C6 (in sheets), C10, C11, C13, C14, C17.

```
┌──────────────────────────────────────┐
│ [Husqvarna photo 390×220, Hero res-img-{id}]│ y0–220
│ (‹)                                  │
│ (ZA 5 DNÍ)                           │
│ REZERVACE #[ID]                      │ y236 eyebrow
│ Husqvarna 701 SM                     │ 22/800
│ Supermoto · MotoGo24 Velké Němčice · samoobsluha│
│ TVOJE CESTA                          │ y338
│ ✓━━━✓━━━◉┈┈┈○┈┈┈○┈┈┈○              │
│ Zaplaceno Doklady Šatna Protokol Motorka Vrácení│
│              pá 12:00           ne 23:59│
│┏━━ CO TEĎ ━━━━━━━━━━━━━━━━━━━━━━━━━━━┓│ y434–842 dark
│┃ Kódy máš připravené                 ┃│
│┃ ½ Kiosk ti motorku vydá v pá 16. 10. od 12:00.┃│
│┃ (1) Brána · horní schránka, pravý sloupek [• • • •] copy┃│
│┃ (2) Šatna · dveře č. 8          [• • • •] copy┃│
│┃ (3) Motorka · kóje se otevře po podpisu protokolu [• • • •] copy┃│
│┃ Kódy na celou obrazovku ›           ┃│
│┃ [   POSTUP NA POBOČCE           › ] ┃│
│┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛│
│ [Upravit][Navigovat][Dokumenty][Zrušit]│ y858–922
│ ┌ KDY A KDE ─────────────────────────┐│ y944–1204
│ │ ↑ Vyzvednutí  pá 16. 10. od 12:00 (➤)││
│ │   Boudky, 691 63 Brno - Velké Němčice││
│ │   (½ 1. den za polovinu · −2 215 Kč · Změnit čas)││
│ │ ↓ Vrácení     ne 18. 10. do 23:59 (➤)││
│ │   Vrácením na kiosku poslední den se rezervace dokončí sama. ⓘ││
│ ┌ VÝBAVA  (Šatna · dveře č. 8) Upravit┐│ y1220–1340
│ │ (Helma [M])(Rukavice [L])(Bunda [L])(Kalhoty [M])(kukla)││
│ ┌ PENÍZE ────────────────────────────┐│ y1356–1520
│ │ 12 027 Kč             (✓ ZAPLACENO) ││
│ │ Rozpis ceny ›   Platební údaje ›    ││
│ ┌ DOKUMENTY ─────────────────────────┐│ y1536–1760
│ │ Smlouva                  Zobrazit › ││
│ │ Předávací protokol  po podpisu na kiosku││
│ │ Protokol o poškození     Zobrazit › ││
│ │ Konečná faktura          po dokončení││
│ Historie úprav ([n])               ▾ │ y1776–1944
│ Před jízdou — bezpečnostní pokyny   ▾ │
│ Potřebuješ pomoct? +420 774 256 271 · AI asistent│ y1960–2020
│ DOMŮ MOTORKY REZERVACE TRASY PROFIL  │ y2102–2200
└──────────────────────────────────────┘
```

### Sections

**1. Photo** (220 px, Hero): back circle; on-photo status pill "ZA 5 DNÍ".
- Other states: "PROBÍHÁ · DEN 2/3", "✓ DOKONČENO", neutral "ZRUŠENO".

**2. Title block**
- Eyebrow "REZERVACE #[ID]" 11.5/800 `#0D6E0D`.
- "Husqvarna 701 SM" 22/800.
- **One merged meta row:** "Supermoto · MotoGo24 Velké Němčice · samoobsluha". It replaces "Kategorie" and the row with the empty value.
- **No tabs.**

**3. "Tvoje cesta" (C10 on light)**

| Variant | Nodes |
|---|---|
| Self-service | Zaplaceno ✓ · Doklady ✓ · **Šatna ◉** (sub "pá 12:00") · Protokol ○ · Motorka ○ · Vrácení ○ (sub "ne 23:59") |
| Own gear | Šatna node omitted |
| Staffed | Zaplaceno · Doklady · Převzetí · Jízda · Vrácení |

Data mapping:
- `paymentStatus` → Zaplaceno.
- Document verification → Doklady.
- Šatna and Protokol → `protocolSigned`. Šatna has no separate signal and is inferred from the signature.
- Motorka → `issuedAt` / `isHandedOver`.
- Vrácení → completed / `returnedAt`.

The current node `ping`s (this screen's live loop).

**4. CO TEĎ** (dark hero card; the same `TicketState` as DOMŮ in a full rendering)

**Artboard state S6:**
- Eyebrow "CO TEĎ". Headline "Kódy máš připravené" 18/800 white.
- Line with C19 "½": "Kiosk ti motorku vydá v pá 16. 10. od 12:00." 13/600 `#CFE7DA`.
- C11 tiles, stacked, gap 8:
  - **1 "Brána"**, sub "horní schránka, pravý sloupek". ⓘ shows the 1:1 `gateCodeHint`.
  - **2 "Šatna"**, sub "dveře č. 8". Hidden when the booking has own gear: replaced by the info row "Vlastní výbava — bez kódu šatny".
  - **3 "Motorka"**, sub "kóje se otevře po podpisu protokolu".
- Link "Kódy na celou obrazovku ›":
  - Full-screen `night` page, codes in order at 48/900, `wakelock_plus` on. No brightness change.
  - Opens with fade + scale .96 → 1 over 250 ms.
- Primary "POSTUP NA POBOČCE" → procedure sheet.

**Other CO TEĎ states:**

| State | Content | Primary |
|---|---|---|
| Unpaid | "Platba čeká · ⏱ [mm:ss]" | "ZAPLATIT [X] KČ" |
| Documents missing | "Kódy ti uvolníme po ověření dokladů" + blurred tiles | "NAHRÁT DOKLADY A UVOLNIT KÓDY" |
| Protocol not signed (pickup day) | Tile 3 locked, amber "Nejdřív podepiš předávací protokol na displeji" | "POSTUP NA POBOČCE" |
| Staffed, upcoming | "Čekáme tě v [den] v [čas] · Mezná 9, 393 01 Pelhřimov · nonstop" | "NAVIGOVAT NA POBOČKU" |
| Active | "Den [x] ze [y] · vracíš [datum] [čas]" + **red SOS button** | "DETAIL VRÁCENÍ" (staffed) / "KÓDY" (self-service) |
| Completed | Stars "Hodnocení jízdy" + link "Ohodnotit na Google" | "ZNOVU REZERVOVAT" |
| Cancelled | "Ověříme, jestli je motorka v termínu volná" | "OBNOVIT A ZAPLATIT" |

**5. Action row** (4 C3 action tiles; the row pins under the app bar once the photo scrolls away):

| Status | Actions |
|---|---|
| Upcoming | Upravit · Navigovat · Dokumenty · **Zrušit** (red) |
| Active | Upravit · **SOS** (red) · Navigovat · Dokumenty |
| Completed | Hodnotit · Znovu rezervovat · Faktura · Google |
| Cancelled | Hidden. CO TEĎ carries "OBNOVIT A ZAPLATIT" |

**6. "KDY A KDE"** (light card)
- Each row: arrow icon in a 36 px tile, label 12/800 `#6C8A7B`, value 15/800, address 12.5/600 `#4A6B5A`, and a 40 px navigation circle (`res_location_row`).
- **Vyzvednutí** "pá 16. 10. od 12:00" / "Boudky, 691 63 Brno - Velké Němčice".
  - Chip (light C19): "½ 1. den za polovinu · −2 215 Kč · Změnit čas". "Změnit čas" → the "Čas vyzvednutí" edit intent. ⓘ shows the full late-gate note.
- **Vrácení** "ne 18. 10. do 23:59" / same address.
  - One-liner: "Vrácením na kiosku poslední den se rezervace dokončí sama." ⓘ.
- **Duration appears once**, in the timeline sub-labels and the title context, with correct plurals: 1 den / 2–4 dny / 5+ dní.

**7. "VÝBAVA"**
- Size chips (read-only): Helma "[M]", Rukavice "[L]", Bunda "[L]", Kalhoty "[M]", "kukla".
- Pill "Šatna · dveře č. 8".
- Link "Upravit" → "Výbava a velikosti" intent.

**8. "PENÍZE"**
- "**12 027 Kč**" 22/900 tabular + ok pill "✓ ZAPLACENO".
- "Rozpis ceny ›" → light sheet with C6: "Pronájem · 3 dny" 14 614 Kč (pá 4 429 · so 5 314 · ne 4 871) · "Vyzvednutí od 12:00 · 1. den ½" −2 215 Kč · "Věrnostní sleva · Motorkář 3 %" −372 Kč · TVOJE CENA 12 027 Kč.
- "Platební údaje ›" expands **the whole former payment tab**: číslo rezervace, stav, částka, metoda, zaplaceno dne, Stripe transakce / refundace, VS, "Doklady k platbě".

**9. "DOKUMENTY"** (one list replacing the two old blocks; viewer `booking_doc_viewer`):
- "Smlouva · Zobrazit ›"
- "Předávací protokol": dimmed "po podpisu na kiosku" until signed
- "Protokol o poškození · Zobrazit ›"
- "Konečná faktura": dimmed "po dokončení"

**10. C14 collapsibles**
- "Historie úprav ([n])" → `ResModificationHistory` unchanged, including "SOS UDÁLOSTI". Hidden when there are none.
- "Před jízdou — bezpečnostní pokyny" → the same text as on the success screen.
- "Projeté jízdy ([n])": C16-style sketches from `UserRide.track` → `/ride/:id`. Hidden while 0 (upcoming).

**11. Help line:** "Potřebuješ pomoct?" + phone link "+420 774 256 271" + "AI asistent" → `/ai-agent`.

### Overlays opened from this screen (specified, not drawn)

**Procedure sheet "Postup na pobočce Velké Němčice"** (light, full height; the same component is used on branch detail)
- A vertical photo timeline. Each step has a 40 px `gNeon` number circle (`onNeon` 16/900), a connector drawn with `connector` (90 ms stagger), a neutral noun-phrase title (16/800, no ty/vy register), and a photo 326×160 r14.
- The **1:1 original text** is clamped to 2 lines with "Víc".

| # | Title | Photo | Text (1:1) |
|---|---|---|---|
| 1 | "Brána a parkování" | `branchPhotoParking` | `procStep1Code` with {gate} |
| 2 | "Šatna, výbava a protokol" | `branchPhotoBox2` | `procStep2GearDoor` with {n} = 8 |
| 3 | "Motorka" | `branchPhotoKiosk` | `procStep3Gear` |

- Own gear: step 2 becomes "Motorka a protokol" with `procStep2NoGear`, and step 3 is dropped.
- Final amber callout (`warnBg`, r12, 2-line clamp + "Víc"): `procStepImportant`.

**Edit chooser "Co chceš změnit?"** (light sheet, 2-column tile grid, tiles 171 × 96, r16; unavailable tiles dimmed with their reason; tiles enter with `reveal`):

| Tile | Sub-text | Available when | This booking |
|---|---|---|---|
| "Prodloužit" | "doplatíš rozdíl" | reserved / active | ✓ |
| "Zkrátit" | "vrátíme podle storna" | reserved / active | ✓ |
| "Posunout termín" | "zdarma, cena se nemění" | reserved, until the start day | ✓. ⓘ "Po posunu už storno nikdy nebude 100 %." (`capAfterMove` rule) |
| "Čas vyzvednutí" | "i sleva od 12:00" | upcoming | ✓ |
| "Místo předání" | — | upcoming, staffed | ✗ "Samoobslužná pobočka — jen osobně" |
| "Vyměnit motorku" | "doplatek nebo vratka" | reserved / active + paid | ✓ |
| "Výbava a velikosti" | — | upcoming | ✓ (step 2 widget) |

Each tile opens a focused screen (`push`, nav hidden) with only its own inputs: C9, chips, segments, or bike cards showing your price for a swap. Every one ends with C6 in **delta mode**, box "ROZDÍL":
- Rows: Původní cena, Nová délka, Prodloužení / Zkrácení, late-pickup delta, delivery delta, Doplňky, Sleva.
- Big "Doplatek [X] Kč" / "Vrátíme ti [X] Kč" / "Beze změny", plus storno % when shortening.
- Values come from `reservation_edit_price_calc`.
- Sticky "POTVRDIT ZMĚNU" or "DOPLATIT [X] KČ" → `/payment` "Doplatek" → `EditConfirmPage` "Zpět na rezervaci".

**Cancel sheet "Zrušit rezervaci?"**
- A 3-segment bar, h12, r999:
  - "7+ dní · 100 %" `#E8FCE8`
  - "2–7 dní · 50 %" `warnBg`
  - "< 2 dny · 0 %" `#FDECEC`
- A "dnes" marker (a 14 px dark dot on a stem) slides to the current segment (400 ms `easeOutCubic`). For 11. 10. vs a start of 16. 10. that is **2–7 dní**.
- Big line 22/900: "Vrátíme ti **6 014 Kč**" (50 % of 12 027, rounded as today's `StornoCalc.effectiveRefundAmount`), crossfading in.
- Destructive button `#E5484D`, white 14.5/800: "ZRUŠIT REZERVACI". Text link "Ponechat".

**SOS** (from the action row, CO TEĎ, ticket, strip): all `/sos/*` content unchanged.
- The start screen becomes 3 big tiles: "Nehoda / Krádež", "Porucha na cestě", "Zavolat nonstop".
- Kept: the emergency-numbers row at the top, "AI Servisní agent", "Odeslat GPS pozici".

### Reservation list (`/reservations`; context for this builder, not drawn)
- Segment "Aktuální · Dokončené · Zrušené · Vše". Aktuální merges Aktivní and Nadcházející. Swipe between segments is kept.
- Mini-ticket cards: image (Hero), model, `#ID`, status pill ("Probíhá · den 2/3", "Za 5 dní", "Dokončeno", "Zrušeno"), "pá 16. 10. – ne 18. 10. · 3 dny", total, SOS badges, needs-action badge ("Nahraj doklady", "Doplatit · mm:ss").
- One contextual button plus "⋯":
  - Probíhá → "Kódy" (self-service) / "Detail".
  - Za X dní → "Nahraj doklady" when missing, otherwise "Detail".
  - Dokončeno → "Ohodnotit" (opens the stars with the first star focused).
  - Zrušeno → "Obnovit" (the real restore).
- Empty: "Zatím nic naplánovaného" + "VYBRAT MOTORKU".

### Motion

| Trigger | Effect |
|---|---|
| From the Home ticket or list | Hero `res-img-{id}` |
| Timeline | Connectors `connector`. Current node `ping` (the screen's live loop). Plus CTA `glow` |
| Codes first released | Blur → sharp 400 + `pop`. Copy: `press` + haptic + toast |
| CO TEĎ state change | `AnimatedSwitcher` `enter` |
| Collapsibles | 300 `easeInOut`, chevron 200 |
| Procedure sheet | `sheet`; connectors draw per step |
| Storno marker | 400 `easeOutCubic`; refund crossfade |
| ROZDÍL value | `bump` + delta chip |
| Reduced motion | Static; codes shown sharp; no Hero |

---

## 11. Content-preservation table (acceptance checklist)

| # | Today | v2 location |
|---|---|---|
| **Shell** | | |
| 1 | Nav DOMŮ / REZERVOVAT / REZERVACE / TRASY | DOMŮ / MOTORKY / REZERVACE / TRASY / PROFIL |
| 2 | Unread badge on the DOMŮ tab | PROFIL tab badge + bell in the DOMŮ header |
| 3 | Marquee banner (`banner_provider`) | Strip under the DOMŮ and MOTORKY headers |
| 4 | FAB Košík | Status strip (5) |
| 5 | FAB "Dokončit rezervaci · mm:ss" | Ticket S2 + strip (2) + REZERVACE badge + stepper ⏱ chip |
| 6 | FAB "Pokračovat v trase" | Strip (4) |
| 7 | FAB "SOS dokončit" | Ticket S1 + strip (1) |
| 8 | FAB "NAHRÁT DOKLADY" | Ticket S3 + strip (3) + timeline "Doklady" + CO TEĎ |
| 9 | AI FAB | Bot in the DOMŮ header, SOS screen, PROFIL → Pomoc, reservation help line |
| 10 | Scroll-to-top FAB | Re-tap the active tab |
| 11 | Nav hidden with keyboard | Kept; also hidden on focused flows |
| 12 | Global overlays (6) | Unchanged |
| 13 | Home tap resets draft and filter | Removed; reset after payment or "✕" on the date pill |
| **Home** | | |
| 14 | Logo → `/loyalty` (only path) | Logo in the rank ring + rank chip + rank strip + PROFIL |
| 15 | Hamburger → `/profile` | PROFIL tab |
| 16 | "PILOT: {nick}" + nickname dialog | "Ahoj, [přezdívka]" (tap → dialog) + rank chip; PROFIL header |
| 17 | Fake search "Kdy jedete? Vyberte termín…" | Header pill "Kdy jedeš příště?" → C9 → MOTORKY; ticket S0 presets |
| 18 | `LoyaltyRankCard` (Home + Profile), "ℹ️ O programu" | Rank strip (DOMŮ, PROFIL); "Jak to funguje" on `/loyalty` |
| 19 | "Aktivní rezervace" + VŠE + cards | Ticket + "Další rezervace ([n]) ›" |
| 20 | Empty state | Ticket S0 |
| 21 | Red SOS bar | Red SOS in ticket S8, CO TEĎ, action row |
| 22 | `MotoFilterPanel(showDates)` | MOTORKY: date pill, branch segment, chips, "Filtry" sheet (all controls) |
| 23 | "Zobrazeno: {n}" + `MotoCard` list | MOTORKY list; DOMŮ "Motorky pro tebe" |
| **Rezervovat tab** | | |
| 24 | Header "Vyhledávání" + hamburger | MOTORKY header |
| 25 | `DateTabsSection` | C9 tiles "Vyzvednutí / Vrácení" + date pill |
| 26 | "1 · VYBERTE DATUM…" + "klikněte 2×" | C9 title "Kdy jedeš?" + hints "Klepni na den vyzvednutí" / "Teď den vrácení (může být i stejný den)" |
| 27 | `AvailabilityCalendar` | `TripCalendar` (C9), shared everywhere |
| 28 | "{n} volných motorek · N dní" | MOTORKY count line |
| **Moto card** | | |
| 29 | Carousel + model overlay | Cover image (Hero) + title below; carousel in detail |
| 30 | "DNES VOLNÁ" | "● Dnes volná" / "Volná v termínu" with `ping` |
| 31 | Spec badges, branch | Spec pills + pin line |
| 32 | "Základní údaje" (≤ 6) | Detail "V kostce" (all) |
| 33 | "od X Kč · za den / cena bez DPH" | "od [tvoje cena] Kč/den" + struck list; VAT wording in the receipt footer |
| 34 | DETAIL button | Whole card tappable; "Rozpis" button with dates |
| **Moto detail** | | |
| 35 | Infinite pager + "i / n" | "‹ i / n ›" arrows, same filtered list |
| 36 | Carousel 260 px, gradient, city, "📷 i/n", dots, fullscreen | 4:3 gallery + dots + count pill + `FullscreenGallery` |
| 37 | Video(s) | Last slides + "▶ Video" pill + row in "Víc o motorce" |
| 38 | "✓ DOSTUPNÁ – REZERVUJ HNED" | Status pill on the photo + sticky state |
| 39 | "Pobočka: {name}, {city}" | Meta row → branch; row in "Víc o motorce" |
| 40 | Description (flattened HTML) | "Popis" 4 lines + "Celý popis" (structured) |
| 41 | TECHNICKÁ SPECIFIKACE (8) | 4 tiles + "Všechny parametry (8)" |
| 42 | 7-column price table + note | "Ceník podle dne" bars (before dates) / collapsible row (after); note kept |
| 43 | Calendar card DOSTUPNOST (+ summary, UPRAVIT) | Calculator ① + C9 |
| 44 | NÁVOD K OBSLUZE / not available | Row (dimmed when missing) |
| 45 | CENA OD · ZÁLOHA · Celkem za N dní | Sticky bar + receipt ("Bez kauce") |
| 46 | Min/max banner | Disabled days in C9 + sticky blocker |
| 47 | CTA + hint | In-card CTA + sticky bar |
| **Booking form** | | |
| 48 | Header "Rezervace: {model} / Vyplňte formulář" | `/booking` app bar + C18 |
| 49 | 1 MOTORKA (thumb, "od…/den · záloha neúčtována", pobočka) | Recap card; "Bez kauce" in the receipt |
| 50 | 2 DATUM + "Celkem za pronájem" | Step 1 / calculator ① + receipt row |
| 51 | 3 ČAS + 🌗 hint + `ssPickupHint` | Time chips with ½ + C19 line item; full texts in ⓘ; self-service "do 23:59" |
| 52 | 4 VYZVEDNUTÍ (radio, address sheet, map picker, 1 000 + 40 Kč/km) | Segmented + same sheet / picker; km and fee in the option + receipt |
| 53 | Locked option + `ssNoDeliveryInfo` | Locked "Jen na pobočce ⓘ" |
| 54 | 5 VRÁCENÍ | Segmented "Na pobočce / Odvoz" + time chips |
| 55 | 6 Free gear + "Mám vlastní výbavu" | Calculator info line; step 2 chips + switch |
| 56 | 6 Size rows (`booking_size_dialogs`) | Step 2 size chips (same dialogs) |
| 57 | 6 Paid extras, trailer, loyalty tag | Calculator ③ + step 2 (one draft); strike + rank badge |
| 58 | Price rows (days, delivery, Sleva, Věrnostní sleva, 50 % 1. den, záloha, DPH) | C6 receipt (detail, live summary, Rozpis) |
| 59 | SLEVOVÝ KÓD sheet | Step 3 inline field (+ `min_order_amount`) |
| 60 | Poznámka | Step 3, collapsed |
| 61 | VOP / GDPR / guardian consents | Step 3 |
| 62 | Banners: missing sizes / validation / profile | Amber chip + blocker / inline error / profile row + sheet |
| 63 | "Pro pokračování potvrďte…" + CTA | Blocker text + "DOPLNIT ↓" / "ZAPLATIT" |
| 64 | Silent normalisation | `normalizeDraft()` + locked or hidden options with ⓘ |
| **Payment** | | |
| 65 | Header "Platba / Bezpečná platba…" | Step 3 "Kontrola a platba"; `/payment` mode header |
| 66 | `PaymentCountdown` | ⏱ chip in `/booking` + ticket S2 + strip |
| 67 | `MotoGalleryCard`, `PriceSummaryCard` | Recap thumbnail + live summary (no repeat) |
| 68 | `UpsellSection` (flag) | Collapsed "Přidat z e-shopu" (flag) |
| 69 | Saved card / Apple Pay / Google Pay, Stripe note, Pay / "Potvrdit (zdarma)" | Step 3 pay block (platform files untouched) + live summary button |
| 70 | Other `/payment` entries | `/payment` modes using the same pay block |
| **Success** | | |
| 71 | Hero animation, title, times, documents card, safety, sync, K vyzvednutí, CTAs | All kept; receipt slides in; documents CTA primary when missing |
| **Reservation list** | | |
| 72 | Chips Vše / Aktivní / Nadcházející / Dokončené / Zrušené + swipe | Aktuální / Dokončené / Zrušené / Vše + swipe; status pill per card |
| 73 | Card data | Same + needs-action badge + countdown |
| 74 | Status actions | One contextual button + "⋯"; Ohodnotit → stars; Obnovit → real restore |
| 75 | Empty state | "Zatím nic naplánovaného" + VYBRAT MOTORKU |
| 76 | Dead `_CancelDialog` | Deleted |
| **Reservation detail** | | |
| 77 | Tabs Podrobnosti / Podrobnosti o platbě | No tabs; Peníze → "Platební údaje" |
| 78 | Info card + Kategorie + empty-value row | Title block + one meta row |
| 79 | Datum / Délka / Délka celkem | Timeline + "Kdy a kde"; duration once, correct plurals |
| 80 | Pickup time, location rows + GPS | "Kdy a kde" rows + navigation buttons |
| 81 | Late-gate note + "Upravit čas vyzvednutí" | Chip "½ … · Změnit čas" + ⓘ |
| 82 | Finanční souhrn | Peníze + "Rozpis ceny" |
| 83 | HISTORIE ÚPRAV + SOS UDÁLOSTI | Collapsible "Historie úprav ([n])" |
| 84 | Přístupové kódy (all states, upload button) | CO TEĎ C11 tiles 1 → 2 → 3 + full screen + states |
| 85 | Postup při vyzvednutí + DŮLEŽITÉ | Procedure sheet (photos, 1:1 texts, amber callout); also branch detail |
| 86 | Completed: rating, DOKUMENTY, Google, Znovu | CO TEĎ completed + action row + Dokumenty |
| 87 | Cancelled: Obnovit | CO TEĎ "OBNOVIT A ZAPLATIT" |
| 88 | Active: Upravit + SOS; Upcoming: Upravit, Zrušit | Action row (+ SOS in CO TEĎ) |
| 89 | Two DOKUMENTY blocks | One Dokumenty list |
| 90 | PROJETÉ JÍZDY | "Projeté jízdy ([n])" with sketches |
| 91 | Bezpečnostní pokyny (success only) | Also a collapsible row in detail |
| **Edit / cancel** | | |
| 92 | 4 mixed tabs | Chooser with 7 intents |
| 93 | Calendar, pickup method / time, return, bike change, extras | Inside the matching intent screen |
| 94 | Price overview (Doplatek / Vrácení / Rozdíl, storno %) | C6 delta "ROZDÍL" |
| 95 | Storno text + refund | 3-segment bar + "dnes" marker + "Vrátíme ti X Kč" |
| 96 | Missing-sizes banner, CTA, `EditConfirmPage` | Blocker, sticky CTA, `EditConfirmPage` kept |
| **SOS** | | |
| 97 | All `/sos/*` screens and sheets | Unchanged; start screen with 3 tiles + emergency row; more entry points |
| **Routes** | | |
| 98 | Tab = Places + rotating quick links | TRASY segments Místa · Trasy · Moje + map button |
| 99 | Places content, multi-select → builder | Místa (filters in a sheet, sticky "Vlastní vyjížďka (n)") |
| 100 | `/routes-list` | Trasy segment; C16 sketches from `geometry` |
| 101 | `/routes/:id` | Same content + draw-in, stat tiles, sticky NAVIGOVAT + "Půjč si motorku na tuhle trasu" |
| 102 | Navigation, builder, POI sheet, maps, recorder | Unchanged; navigation without decorative motion |
| 103 | `my_experiences`, community submit, `/ride/:id` | Moje segment + "+" button; reservation "Projeté jízdy" |
| **Other** | | |
| 104 | `/pobocky`, `/pobocky/:i` + duplicate `branches_sheet` etc. | PROFIL → Pobočky + DOMŮ cards; "Motorky na pobočce" → MOTORKY preset; duplicates deleted |
| 105 | `/loyalty`, leaderboard, toggle, level-up | Kept; 4 entries; rules text fixed |
| 106 | Shop, cart, checkout, voucher (flag) | PROFIL tile (flag); cart in the strip |
| 107 | Profile menu + inline Osobní údaje | PROFIL tab (same rows) |
| 108 | Messages, chat, AI agent | PROFIL → Zprávy + bell; AI from header / SOS / Pomoc |
| 109 | `/docs`, scanner, `/invoices`, `/contracts` | Unchanged; entries from PROFIL, ticket S3, strip, CO TEĎ, consent links |

**Only removed: dead or replaced code.**
- Dead: `router.dart:501–1365` (`_BookingDebugWrapper`), `_noNavRoutes`, `catalog/catalog_screen.dart`, `_CancelDialog`, `profile/widgets/branches_sheet.dart`, `branch_detail_card`, `branch_moto_list`.
- Replaced once MOTORKY ships: `catalog/moto_search_screen.dart`.

---

## 12. Engineering notes for all builders

**Both trees, one commit.**
- Every shared file goes into `motogo-app-flutter` and `motogo-app-flutter-ios` together.
- `diff -rq` of both `lib/` must show only the listed intended differences. The `userAgentPackageName` lines in map files stay per tree.

**No new packages.** These are already in both trees: go_router ^13, flutter_riverpod, google_fonts, flutter_svg ^2.0.9, cached_network_image, shared_preferences, wakelock_plus ^1.6.1, flutter_map. iOS pins are untouched.

**No backend change.** Reads only:
- Tables: `motorcycles`, `branches`, `accessory_types`, `routes`.
- RPCs and functions: `get_loyalty_status`, `get_moto_booked_dates`, `get_trailer_availability`, `get_motos_availability_status`, `validate_promo_code`, `validate_voucher_code`, edge `slevomat-voucher`.
- Optional `app_v2_ui` feature flag: an SQL insert that goes to the owner **as text first** (rule 3), then the `SUPABASE_BACKEND_STATE` update.

**Routing**
- Keep `ShellRoute`.
- Hero works **only inside the shell** (go_router wraps the shell in a `HeroControllerScope`). Never Hero into `/success` or any root route.
- New `/motorky`. `/booking` stays.
- `CustomTransitionPage` for tabs (`tab`) and focused flows (`push`).

**Files** (each under 5 000 tokens):

| Area | Files |
|---|---|
| Core | `core/theme_v2.dart`, `core/motion.dart` |
| `core/widgets/v2/` | `lp_icon`, `v2_nav_bar`, `v2_status_strip`, `v2_buttons`, `v2_chips`, `v2_sticky_bar`, `v2_date_sheet`, `receipt_card` + `receipt_painters`, `status_timeline`, `code_tile`, `route_sketch_painter`, `rank_strip`, `moto_card_v2`, `simple_html_text` |
| Features | `features/home/ticket_state.dart` + `ticket_card.dart`, `features/catalog/motorky_screen.dart`, `features/booking/price_quote_provider.dart`, `features/payment/pay_block.dart` (extracted from `payment_screen.dart`), `features/reservations/detail_v2/*`, `features/reservations/edit_v2/*` |

- The calculator **reuses** the re-skinned `core/booking_form_*_section.dart` widgets.

**i18n:** every new key goes into all 8 languages (cs, en, de, es, fr, nl, pl, uk) in the `translations_ext_*` pattern. The Czech tykání pass excludes the 1:1 texts listed in §0.8.

**Fixes shipped with this work:**
- Loyalty rules text and the stale comment in `loyalty_provider.dart` become "1–6 dní = 1 bod, 7 a více dní = 2 body".
- Plurals for den / dny / dní.
- Reduced-motion retrofit.

**Rollout order:**
1. Tokens, motion, reduced-motion retrofit, price tests.
2. Detail calculator, `/booking` stepper, receipt, pay block.
3. Tabs, MOTORKY, status strip, DOMŮ ticket.
4. Reservation detail, edit chooser, storno sheet.
5. TRASY segments and sketches.
6. Dead-code removal and the copy pass.

---

## 13. Owner decisions needed before build

1. **Trailer price.** The app shows "zdarma"; the web charges 400 Kč/den. The spec shows zdarma.
2. **Tykání.** Switch the whole `cs` app (recommended)? The 1:1 procedure, gate and document texts stay as they are unless e-mails, SMS and web switch together.
3. **VAT and deposit copy.** Use "Bez kauce · konečná cena · nejsme plátci DPH" everywhere, replacing "cena bez DPH" and "Záloha se neúčtuje"?
4. **Delivery rounding.** Round to whole Kč, as the web does (recommended)?
5. **"Tvoje cena" at rank 1.** Show it at rank 1 too, where the difference is only 1 %? Recommended yes, for one consistent rule.
6. **Paid boots sizes.** The DB `accessory_types` lists 36–46; the app offers 39–48. The spec uses 39–48.
7. **Passenger gear contents.** The label says "Helma, rukavice, vesta", but the size sheet asks for Helma / Rukavice / Bunda / Kalhoty. Which is right?
8. **TRASY default segment.** Keep Místa (the 16. 9. decision)?
9. **"Omezit animace"** in-app setting: add it, or rely on the OS setting only?
10. **Full-screen codes.** Use `wakelock_plus` only (spec), or add a brightness package as an explicit decision?
11. **Rollout behind `app_v2_ui`?** This needs an SQL insert, sent as text first.