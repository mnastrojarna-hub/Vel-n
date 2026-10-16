# understand:nav: bottom nav, PROFIL tab, AI floating button, SOS access

Scope:
- Android master tree `Motogo-app-main/motogo-app-flutter/lib`.
- The iOS tree has an identical `core/app_shell.dart` and `features/home/home_screen.dart` (`diff -q` is clean).
- Canvas v1 boards in `appdesign/project/*.dc.html`.

Measurements:
- Done on 2026-10-15 with Playwright and Chromium 1194.
- Font: Montserrat woff2 downloaded from Google Fonts. This is the same family that `GoogleFonts.montserratTextTheme` loads at runtime, and it includes Cyrillic.
- Scripts and raw JSON are in `scratchpad/navmeasure/`: `measure.js`, `measure2.js`, `verify*.js`, `compose.js`, `widths*.json`, `verify*.json`.
- Screenshots are in `research/nav_shots/`.

---

## 0. TL;DR

**Key facts**
1. **Today's nav:**
   - 4 tabs: DOMŮ · REZERVOVAT · REZERVACE · TRASY.
   - White bar, 80 px tall plus the safe area.
   - Labels are 11 px, weight 900 when active and 700 when inactive, UPPERCASE, letter-spacing 0.3.
   - Labels sit inside a `FittedBox(scaleDown)`, so long words are shrunk instead of overflowing. On a 360 dp phone the German RESERVIERUNGEN renders at about **8 px**; RESERVATIONS / RÉSERVATIONS at about 9.5 px.
   - The inactive label colour `g400 #8AAB99` on white is **2.51:1**, which fails WCAG.
   - There is no PROFIL tab. Profile and menu are reached through the hamburger in the Home header (`context.go(Routes.profile)`).
2. **AI assistant today:**
   - A 56 px green circle FAB (bot icon + the hard-coded text "AI") at **bottom-left of Home only** (`home_screen.dart:194-236`).
   - A card on the SOS screen.
   - `/ai-agent` highlights the **REZERVACE** tab (`app_shell.dart:47-48`).
   - Canvas v1 moved AI into a 44 px circle in the dark Home header, which is what the owner rejected.
3. **SOS today** shows only while `sosAllowed` is true (`hasActiveRentalProvider`). Entry points:
   - red bar on Home
   - "🆘 Porucha" on the reservation card
   - SOS button in reservation detail
   - Profil → Pomoc
   - SOS link in the AI chat
   - push-notification fallback
   - "SOS dokončit" FAB for a pending replacement
   - The SOS start screen only navigates. Emergency numbers open the dialer (`tel:`), and every incident is sent with an explicit button. **An accidental tap on an SOS entry costs nothing.**
4. **Canvas v1:**
   - Nav: 5 tabs (Domů · Motorky · Rezervace · Trasy · Profil), white, 98 px.
   - Labels 11/700 (active 800), UPPERCASE via CSS, ls .02em.
   - Sliding neon pill 52×30 behind the active icon.
   - AI and bell are in the header. SOS is a red 48 px circle inside the trip ticket (S8) and in the action row on Reservation.
   - The MotoDetail and Booking boards have no nav, only a sticky bar.

**Measured verdict on labels (5 equal tabs; limit = width/5 − 8 → 64 px at 360 dp, 70 px at 390 dp)**
- **UPPERCASE at 11/800 cannot fit Czech, the primary language:**
  - REZERVACE is 70.5 px, which fails even at 390 dp.
  - At 10.5 px it is 67.3, still over the 360 limit. At 10 px it is 64.1.
  - In de, nl, pl, uk and fr the reservations word, and in uk also the routes word, are 70–108 px. Fitting them would need unnatural substitutions in 6 languages.
- **Title case is 10–26 % narrower (REZERVACE → Rezervace: 70.5 → 60.5 px) and fits.** Recommended set at 11/800:

  | | Home | Bikes | Bookings | Routes | Profile |
  |---|---|---|---|---|---|
  | cs | Domů | Motorky | Rezervace | Trasy | Profil |
  | en | Home | Bikes | Bookings | Routes | Profile |
  | de | Home | Bikes | Buchungen | Routen | Profil |
  | es | Inicio | Motos | Reservas | Rutas | Perfil |
  | fr | Accueil | Motos | Locations | Itinéraires | Profil |
  | nl | Home | Motoren | Boekingen | Routes | Profiel |
  | pl | Start | Motory | Rezerwacje | Trasy | Profil |
  | uk | Головна | Мото | Оренда | Маршрути | Профіль |

  - At 390 dp every label fits within column − 8.
  - At 360 dp only Buchungen (−4.2 px), Rezerwacje (−3.8) and Маршрути (−0.5) use part of the 8 px padding. The real gap to the neighbouring label is still ≥ 13.7 px in every language.
  - No overlap at any width from 320 to 430 dp at text scale 1.0 (smallest gap 5.7 px, at 320 dp in fr). At scale 1.15, no overlap from 360 dp up (gaps ≥ 5 px); overlaps appear only at 320 dp.
- **Runtime safety net:**
  - Use a `TextPainter` guard with predefined short fallbacks: fr Itinéraires → Balades, pl Rezerwacje → Wynajmy, uk Маршрути → Траси.
  - Clamp nav labels to text scale 1.0, and show a long-press "large label" bubble instead (the iOS tab-bar behaviour).
  - Never ellipsis, never wrap.

**Recommendations, in one line each**
- **Nav:**
  - Full-width bar (a floating island would cost 24 px of label room).
  - Dark "night glass" style, so all 20 rank colours stay ≥ 3.86:1 against it. On white, 13 of 20 rank colours are < 3:1.
  - Rank-themed sliding pill with a one-shot liquid stretch.
  - PROFIL tab is an avatar with the rank ring and a progress arc.
  - No infinite loops.
- **AI FAB:**
  - Global, in `AppShell`, bottom-right, 56 px, dark disc with rank ring and glow. **Icon only.** "AI" is not universal: it is KI in de, IA in es/fr, ШІ in uk.
  - Sits 12 px above whatever is lowest: nav, status strip or sticky bar. It moves there with `AnimatedPositioned` 300 ms.
  - Shrinks to a 44 px mini without glow above sticky CTA bars.
  - Hidden on payment, success, chat, keyboard and full-screen navigation.
- **SOS:**
  - Never in the nav and never next to the AI FAB.
  - While `sosAllowed`: the red "SOS" pill takes over the header slot that AI vacates, plus SOS in the ticket, the status strip (priority 1), REZERVACE and Profil.
  - Plain tap: no hold-to-confirm, because the target screen is non-destructive.
  - Use red `#D92D20` for white text. `#EF4444` with white text is 3.76:1, which fails.

---

## 1. Current app: facts from the code

### 1.1 Shell and router
- **Shell:** `core/router.dart:306` is a single `ShellRoute` that builds `AppShell`. The tabs use `NoTransitionPage`.
  - Inside the shell: `/`, `/search`, `/reservations`, `/shop`, `/profile`, `/moto/:id`, `/booking`, `/payment`, `/reservations/:id(/edit)`, `/messages(/:id)`, `/invoices`, `/contracts`, `/pobocky(/:i)`, `/shop/:id`, `/cart`, `/checkout`, `/voucher`, `/sos/*`, `/ai-agent`, `/permissions`, `/loyalty`, `/routes` (AllPoisScreen, "Místa" first since 16. 9.), `/routes-list`, `/places-map`, `/routes-map`, `/routes/:id`.
  - So today the nav shows on the bike detail, booking and payment screens too.
- **Outside the shell** (no nav, no shell FABs): `/login`, `/register`, `/reset-password`, `/success`, `/payment-result`, `/docs`, `/docs/scan`, `/route-nav/:id`, `/pois`, `/route-build`, `/my-experiences`, `/ride/:id`, `/route-nav-custom`.
- **Tab index mapping** (`app_shell.dart:39-52`):
  - `/routes*`, `/places-map`, `/pois` → TRASY
  - `/reservations*`, `/sos*`, `/ai-agent` → REZERVACE
  - `/search`, `/moto*`, `/booking`, `/payment` → REZERVOVAT
  - everything else → DOMŮ, including profile, messages and invoices, so "Domů" is highlighted while you are in Profil
- **Tap on a tab:** `context.go(tab.route)`. Tapping DOMŮ resets `bookingDraftProvider`, `bookingMotoProvider` and `catalogFilterProvider` (lines 312-319). Spec §4.1 drops that reset.

### 1.2 Bottom nav (today)
- **Bar:** white, top border `g200`, `bnavHeight 80` inside `SafeArea`. Hidden while the keyboard is open (`app_shell.dart:147, 290`).
- **Tab:** `Expanded` → `PressableScale(0.9)` → `AnimatedContainer` 260 ms with margin 4 h / 6 v.
  - Active tab: neon gradient pill r xxl around **both icon and label**, with a green glow.
  - Icon: 26 px Material outlined/filled, wrapped in `NavBounceIcon` (520 ms pop).
  - Label: 11 px, w900 active / w700 inactive, ls 0.3, black / `g400`, inside a `FittedBox(scaleDown)`.
- **Badge:** unread messages as a red circle on the DOMŮ tab. The same count shows on the header hamburger.
- **Labels in the app today**:

  | | navHome | navBook | navReservations | navRoutes | profile (title case, menu) |
  |---|---|---|---|---|---|
  | cs | DOMŮ | REZERVOVAT | REZERVACE | TRASY | Profil |
  | en | HOME | BOOK | RESERVATIONS | ROUTES | Profile |
  | de | HOME | BUCHEN | RESERVIERUNGEN | ROUTEN | Profil |
  | es | INICIO | RESERVAR | RESERVAS | RUTAS | Perfil |
  | fr | ACCUEIL | RÉSERVER | RÉSERVATIONS | ITINÉRAIRES | Profil |
  | nl | HOME | BOEKEN | RESERVERINGEN | ROUTES | Profiel |
  | pl | START | REZERWUJ | REZERWACJE | TRASY | Profil |
  | uk | ГОЛОВНА | БРОНЮВАТИ | БРОНЮВАННЯ | МАРШРУТИ | Профіль |

  - Files: `translations_ext_1_*.dart:166-168 / 357-359 / 548-550`, `translations_uk_ext_a.dart:166-168`, `translations_ext_11_routes.dart` (navRoutes), `translations_uk_ext_b.dart:96`. `profile` lives in the base files.
  - Only `app_shell.dart` reads the `nav*` keys.
- **Shrinking today:**
  - At 360 dp a column is 90 px, minus a 4+4 margin, so labels get 82 px at 11/900 ls .3:
    - RESERVIERUNGEN 112.7 px → scaled to about 0.73 → **≈ 8.0 px**
    - RESERVERINGEN 103.8 → ≈ 8.7 px
    - RESERVATIONS / RÉSERVATIONS 95.2 → ≈ 9.5 px
    - БРОНЮВАННЯ 93.3 → ≈ 9.7 px
    - REZERWACJE 85.2 → ≈ 10.6 px
    - REZERVOVAT 83.1 → ≈ 10.9 px
  - With 5 tabs this would get much worse, so a different label strategy is required.
- **Contrast:** inactive `#8AAB99` on white is **2.51:1** (fail). Spec C1 proposes `#6C8A7B`, which is **3.78:1** and still fails for 11 px text. Use `#4A6B5A` (5.93:1) on white, or the dark-bar values in §4.

### 1.3 Floating stack in the shell (today, `app_shell.dart:177-284`)

All are centred pills (green main pill + red ✕). Positions are relative to the body bottom, i.e. above the nav:

| FAB | Bottom offset | Shown when |
|---|---|---|
| Cart | 8 | Has items; not on shop flow or payment |
| Booking "Dokončit rezervaci · m:ss" | 25 | — |
| SOS "SOS dokončit" | 8, or 25 when the cart is visible | Pending replacement |
| Docs "Nahrajte doklady" | 25 | Active paid booking + docs incomplete |
| Route "Pokračovat v trase" | 25, or 83 when booking/docs FAB is up | — |

- **Everything** is hidden on payment (`paymentScreenActiveProvider` or route check). This is a deliberate owner rule: nothing may cover "Zaplatit".
- Spec C2 replaces this stack with **one status strip** (52 px, r999, 8 px above the nav, 16 px insets, shows the most urgent item, "+n" opens the rest).
- The level-up watcher is not in the shell. It lives in `MaterialApp.builder`, so it works on every screen.

### 1.4 AI assistant entry points (today)
- **Home FAB:** `home_screen.dart:194-236`, bottom-left 16/16, 56 px circle, neon gradient, `Icons.smart_toy` plus a literal `'AI'`. Home also has a scroll-to-top FAB bottom-right (shown after 600 px of scroll).
- **SOS start screen card:** "AI Servisní agent – Diagnostika závad, kontrolky, rady" (`sos_report_screen.dart:72-98`).
- **Chat screen:** `messages/ai_agent_screen.dart` is a full screen with AppBar "🤖 AI Servisní agent". It sends booking context to the `ai-moto-agent` edge function and suggests SOS when `hasActiveRental` (`aiSuggestSos`).
  - Its state is local (`StatefulWidget`), so the conversation is lost when you leave.
- **Labels already in the app** (`aiServiceAgent`):
  - cs "AI Servisní agent", en "AI Service agent", de "**KI**-Serviceagent", es "Agente de servicio **IA**", fr "Agent de service **IA**", nl "AI-serviceagent", pl "Agent serwisowy AI", uk "AI Сервісний агент".
  - The literal "AI" on today's FAB is wrong for de/es/fr and debatable for uk, where the native form is ШІ.

### 1.5 SOS entry points (today)
- **Rule** (`sos_provider.dart:10-14`, `reservation_models.dart:415`): SOS is visible only when `sosAllowed` is true:
  ```
  !endedBySos && (status=='active' || (inRentalTerm && paid))
  ```
- **Entry points:**
  - Home red bar "NEHODA, KRÁDEŽ, PORUCHA / Okamžitá pomoc 24/7" (`home_reservations_section.dart:107-160`)
  - Reservation card "🆘 Porucha" (aktivni only)
  - Reservation detail SOS button (aktivni)
  - Profil → Pomoc & Podpora (with an active rental)
  - AI chat SOS link
  - push-notification fallback (`notification_handler.dart:107`)
  - SOS-dokončit FAB
- **Route navigation (`/route-nav/:id`, outside the shell) has no SOS.** That is the screen open while riding, so it is the most likely moment to need help.
- **SOS screen behaviour:** back arrow, AI card, emergency chips 112 / 155 / 158 (they open the dialer via `tel:`, so dialling is the confirmation step), problem-type tiles, and sub-screens with explicit send buttons.

---

## 2. Canvas v1 boards (what they show today)

| Board | Nav | Top bar | AI | SOS | Bottom obstruction |
|---|---|---|---|---|---|
| Main (Domů) | 5 tabs, white 98 px, 52×30 neon pill (`.npill`), labels 11 px 700/800 uppercase ls .02em, PROFIL = avatar with progress ring + count badge, REZERVACE red dot | Dark header: MG logo with rank arc → loyalty, greeting (nickname), rank chip, **AI 44 px circle** + bell 44 px with badge, date pill | Header (owner: "could get lost") | Red 48 px "SOS" circle inside ticket S8 (riding), SOS tile in S9 secondaries, eyebrow "SOS · rozpracováno" (S1) | Toast at bottom 118 |
| MotoKatalog | Same 5 tabs (MOTORKY active) | Sticky dark blurred header | none | none | Full-bleed cards 600 px, each with a round `.go` arrow button at the bottom-right of the card overlay |
| MotoDetail | **none** | Photo hero | none | none | Sticky `.sk` 110 px (price left, REZERVOVAT right) |
| Booking | **none** | Sticky light header `.ab` | none | none | Sticky summary `.sum` (2 rows + pay) |
| Reservation | 5 tabs (REZERVACE active) | Back | none | `.sos` button in CO TEĎ (active state), SOS in action row (red) | — |

The AI button exists only on Main, and only in the header. No board defines how floating elements stack.

---

## 3. Label measurements (Playwright, Montserrat)

**Method:**
- Each candidate is rendered in an inline-block `span` and its `getBoundingClientRect().width` is read.
- Weight 800 is used for every tab, because any tab can be the active one (inactive 700 is about 1 px narrower).
- **Strict limit** (task rule): label ≤ width/5 − 8, i.e. 64 px at 360 dp and 70 px at 390 dp. Also checked at 320/375/412/430.
- **Real overlap** check: the rendered gap between neighbouring labels must be ≥ 6 px, and the gap to the screen edge ≥ 4 px.
- Chromium and Flutter (HarfBuzz, same font) agree within about 0.5 px. That is why the runtime guard in §4.4 exists anyway.

#### Table A: UPPERCASE (v1 canvas style), width in px

Limits: 360 dp → 64 px, 390 dp → 70 px (column − 8). ✓/✗ is for 11/800, ls 0.

| lang | label | source | 11/800 ls0 | 11/800 ls .02em | 10.5/800 ls0 | 10/800 ls0 | 360 | 390 |
|---|---|---|---:|---:|---:|---:|:-:|:-:|
| cs | DOMŮ | app navHome | 37.5 | 38.4 | 35.8 | 34.1 | ✓ | ✓ |
| cs | MOTORKY | new (web/app word) | 59.3 | 60.9 | 56.6 | 53.9 | ✓ | ✓ |
| cs | REZERVOVAT | app navBook | 79 | 81.2 | 75.4 | 71.8 | ✗ | ✗ |
| cs | REZERVACE | app navReservations | 70.5 | 72.5 | 67.3 | 64.1 | ✗ | ✗ |
| cs | TRASY | app navRoutes | 38.4 | 39.5 | 36.6 | 34.9 | ✓ | ✓ |
| cs | PROFIL | app profile | 43 | 44.3 | 41 | 39 | ✓ | ✓ |
| cs | MÍSTA | app poiBrowseAll | 36.5 | 37.6 | 34.8 | 33.2 | ✓ | ✓ |
| en | HOME | app navHome | 36.1 | 37 | 34.4 | 32.8 | ✓ | ✓ |
| en | BIKES | new | 35 | 36.1 | 33.4 | 31.8 | ✓ | ✓ |
| en | MOTORCYCLES | new | 88.5 | 91 | 84.5 | 80.5 | ✗ | ✗ |
| en | BOOK | app navBook | 35.3 | 36.2 | 33.8 | 32.1 | ✓ | ✓ |
| en | BOOKINGS | new | 63.5 | 65.3 | 60.6 | 57.8 | ✓ | ✓ |
| en | RESERVATIONS | app navReservations | 90.5 | 93.1 | 86.3 | 82.2 | ✗ | ✗ |
| en | TRIPS | new | 34.1 | 35.2 | 32.5 | 31 | ✓ | ✓ |
| en | ROUTES | app navRoutes | 47.4 | 48.8 | 45.3 | 43.1 | ✓ | ✓ |
| en | PROFILE | app profile | 50.3 | 51.9 | 48.1 | 45.8 | ✓ | ✓ |
| de | HOME | app navHome | 36.1 | 37 | 34.4 | 32.8 | ✓ | ✓ |
| de | START | new | 37.3 | 38.4 | 35.6 | 33.9 | ✓ | ✓ |
| de | MOTORRÄDER | new | 85.4 | 87.6 | 81.5 | 77.7 | ✗ | ✗ |
| de | BIKES | new | 35 | 36.1 | 33.4 | 31.8 | ✓ | ✓ |
| de | BUCHEN | app navBook | 50.3 | 51.6 | 48 | 45.7 | ✓ | ✓ |
| de | BUCHUNGEN | new | 76.3 | 78.2 | 72.8 | 69.3 | ✗ | ✗ |
| de | RESERVIERUNGEN | app navReservations | 108 | 111 | 103 | 98.1 | ✗ | ✗ |
| de | ROUTEN | app navRoutes | 49.2 | 50.5 | 47 | 44.7 | ✓ | ✓ |
| de | PROFIL | app profile | 43 | 44.3 | 41 | 39 | ✓ | ✓ |
| es | INICIO | app navHome | 37.4 | 38.7 | 35.7 | 34 | ✓ | ✓ |
| es | MOTOS | new | 43 | 44.1 | 41 | 39.1 | ✓ | ✓ |
| es | RESERVAR | app navBook | 63 | 64.7 | 60.1 | 57.3 | ✓ | ✓ |
| es | RESERVAS | app navReservations | 62 | 63.7 | 59.1 | 56.3 | ✓ | ✓ |
| es | RUTAS | app navRoutes | 39 | 40.1 | 37.2 | 35.5 | ✓ | ✓ |
| es | PERFIL | app profile | 41 | 42.4 | 39.2 | 37.3 | ✓ | ✓ |
| fr | ACCUEIL | app navHome | 50.7 | 52.2 | 48.4 | 46.1 | ✓ | ✓ |
| fr | MOTOS | new | 43 | 44.1 | 41 | 39.1 | ✓ | ✓ |
| fr | RÉSERVER | app navBook | 62 | 63.7 | 59.2 | 56.3 | ✓ | ✓ |
| fr | RÉSERVATIONS | app navReservations | 90.5 | 93.1 | 86.3 | 82.2 | ✗ | ✗ |
| fr | RÉSAS | new (colloquial) | 38.4 | 39.5 | 36.7 | 34.9 | ✓ | ✓ |
| fr | ITINÉRAIRES | app navRoutes | 73.9 | 76.3 | 70.5 | 67.2 | ✗ | ✗ |
| fr | ROUTES | new | 47.4 | 48.8 | 45.3 | 43.1 | ✓ | ✓ |
| fr | BALADES | new | 56.1 | 57.7 | 53.6 | 51 | ✓ | ✓ |
| fr | PROFIL | app profile | 43 | 44.3 | 41 | 39 | ✓ | ✓ |
| nl | HOME | app navHome | 36.1 | 37 | 34.4 | 32.8 | ✓ | ✓ |
| nl | MOTOREN | new | 60.3 | 61.8 | 57.5 | 54.8 | ✓ | ✓ |
| nl | BOEKEN | app navBook | 49.7 | 51 | 47.4 | 45.2 | ✓ | ✓ |
| nl | RESERVERINGEN | app navReservations | 99.3 | 102.2 | 94.8 | 90.3 | ✗ | ✗ |
| nl | BOEKINGEN | new | 70.8 | 72.7 | 67.5 | 64.3 | ✗ | ✗ |
| nl | ROUTES | app navRoutes | 47.4 | 48.8 | 45.3 | 43.1 | ✓ | ✓ |
| nl | PROFIEL | app profile | 50.3 | 51.9 | 48.1 | 45.8 | ✓ | ✓ |
| pl | START | app navHome | 37.3 | 38.4 | 35.6 | 33.9 | ✓ | ✓ |
| pl | MOTOCYKLE | new | 73.8 | 75.8 | 70.4 | 67.1 | ✗ | ✗ |
| pl | MOTORY | new (colloquial) | 51.5 | 52.8 | 49.2 | 46.8 | ✓ | ✓ |
| pl | REZERWUJ | app navBook | 66.3 | 68.1 | 63.3 | 60.3 | ✗ | ✓ |
| pl | REZERWACJE | app navReservations | 81.2 | 83.4 | 77.5 | 73.8 | ✗ | ✗ |
| pl | TRASY | app navRoutes | 38.4 | 39.5 | 36.6 | 34.9 | ✓ | ✓ |
| pl | PROFIL | app profile | 43 | 44.3 | 41 | 39 | ✓ | ✓ |
| uk | ГОЛОВНА | app navHome | 59.3 | 60.8 | 56.6 | 53.9 | ✓ | ✓ |
| uk | МОТОЦИКЛИ | new | 80.5 | 82.5 | 76.8 | 73.2 | ✗ | ✗ |
| uk | МОТО | new | 36 | 36.9 | 34.4 | 32.8 | ✓ | ✓ |
| uk | БРОНЮВАТИ | app navBook | 79.8 | 81.8 | 76.2 | 72.6 | ✗ | ✗ |
| uk | БРОНЮВАННЯ | app navReservations | 89.8 | 92 | 85.7 | 81.7 | ✗ | ✗ |
| uk | БРОНІ | new (short) | 38.2 | 39.3 | 36.5 | 34.7 | ✓ | ✓ |
| uk | МАРШРУТИ | app navRoutes | 71.6 | 73.4 | 68.4 | 65.1 | ✗ | ✗ |
| uk | ПРОФІЛЬ | app profile | 57.3 | 58.9 | 54.7 | 52.1 | ✓ | ✓ |

#### Table B: Title case (proposed), width in px

✓/✗ is for 11/800, against the same limits (64 / 70).

| lang | label | 11/800 | 11.5/800 | 12/700 | 12/800 | UPPER 11/800 | 360 | 390 |
|---|---|---:|---:|---:|---:|---:|:-:|:-:|
| cs | Domů | 35.5 | 37.1 | 38.6 | 38.8 | 37.5 | ✓ | ✓ |
| cs | Motorky | 48.8 | 51 | 52.1 | 53.2 | 59.3 | ✓ | ✓ |
| cs | Rezervace | 60.5 | 63.3 | 64.6 | 66 | 70.5 | ✓ | ✓ |
| cs | Trasy | 31.1 | 32.5 | 32.9 | 33.9 | 38.4 | ✓ | ✓ |
| cs | Profil | 31.6 | 33 | 33.5 | 34.5 | 43 | ✓ | ✓ |
| cs | Rezervovat | 65.5 | 68.5 | 69.9 | 71.5 | 79 | ✗ | ✓ |
| cs | Místa | 31.6 | 33 | 33.9 | 34.5 | 36.5 | ✓ | ✓ |
| cs | Jízdy | 30.1 | 31.5 | 32 | 32.9 | 33.7 | ✓ | ✓ |
| cs | Výpůjčky | 54.7 | 57.2 | 58.2 | 59.7 | 62.1 | ✓ | ✓ |
| cs | Termíny | 47.7 | 49.8 | 51 | 52 | 53.1 | ✓ | ✓ |
| en | Home | 34.8 | 36.4 | 37.8 | 38 | 36.1 | ✓ | ✓ |
| en | Bikes | 32.2 | 33.6 | 34.3 | 35.1 | 35 | ✓ | ✓ |
| en | Bookings | 55.5 | 58 | 59.5 | 60.6 | 63.5 | ✓ | ✓ |
| en | Reservations | 76.2 | 79.6 | 81.4 | 83.1 | 90.5 | ✗ | ✗ |
| en | Rentals | 44 | 46 | 47.1 | 48 | 53.5 | ✓ | ✓ |
| en | Trips | 28.8 | 30.1 | 30.7 | 31.5 | 34.1 | ✓ | ✓ |
| en | Routes | 40.9 | 42.8 | 43.9 | 44.6 | 47.4 | ✓ | ✓ |
| en | Rides | 32.3 | 33.8 | 34.7 | 35.3 | 35.5 | ✓ | ✓ |
| en | Profile | 38.7 | 40.4 | 41.1 | 42.2 | 50.3 | ✓ | ✓ |
| en | Motorcycles | 71.1 | 74.3 | 76 | 77.6 | 88.5 | ✗ | ✗ |
| de | Home | 34.8 | 36.4 | 37.8 | 38 | 36.1 | ✓ | ✓ |
| de | Start | 28.7 | 30 | 30.6 | 31.3 | 37.3 | ✓ | ✓ |
| de | Bikes | 32.2 | 33.6 | 34.3 | 35.1 | 35 | ✓ | ✓ |
| de | Motorräder | 65.8 | 68.8 | 70.5 | 71.8 | 85.4 | ✗ | ✓ |
| de | Buchungen | 68.2 | 71.3 | 73.6 | 74.4 | 76.3 | ✗ | ✓ |
| de | Buchung | 53.5 | 55.9 | 57.8 | 58.3 | 60 | ✓ | ✓ |
| de | Mieten | 40.5 | 42.3 | 43.5 | 44.1 | 44.9 | ✓ | ✓ |
| de | Termine | 48 | 50.2 | 51.6 | 52.4 | 53 | ✓ | ✓ |
| de | Routen | 42.5 | 44.5 | 45.8 | 46.4 | 49.2 | ✓ | ✓ |
| de | Touren | 40.8 | 42.7 | 43.8 | 44.5 | 49.2 | ✓ | ✓ |
| de | Profil | 31.6 | 33 | 33.5 | 34.5 | 43 | ✓ | ✓ |
| de | Reservierungen | 93.3 | 97.6 | 100.1 | 101.8 | 108 | ✗ | ✗ |
| es | Inicio | 32.2 | 33.7 | 34.4 | 35.1 | 37.4 | ✓ | ✓ |
| es | Motos | 35.9 | 37.5 | 38.6 | 39.2 | 43 | ✓ | ✓ |
| es | Reservas | 52.8 | 55.3 | 56.4 | 57.6 | 62 | ✓ | ✓ |
| es | Rutas | 33.4 | 34.9 | 35.9 | 36.5 | 39 | ✓ | ✓ |
| es | Perfil | 31.5 | 33 | 33.5 | 34.4 | 41 | ✓ | ✓ |
| fr | Accueil | 43.4 | 45.3 | 46.3 | 47.3 | 50.7 | ✓ | ✓ |
| fr | Motos | 35.9 | 37.5 | 38.6 | 39.2 | 43 | ✓ | ✓ |
| fr | Réservations | 76.2 | 79.6 | 81.4 | 83.1 | 90.5 | ✗ | ✗ |
| fr | Résas | 34.2 | 35.7 | 36.5 | 37.3 | 38.4 | ✓ | ✓ |
| fr | Locations | 56.9 | 59.5 | 60.9 | 62.1 | 68.1 | ✓ | ✓ |
| fr | Itinéraires | 59.6 | 62.3 | 63.4 | 65 | 73.9 | ✓ | ✓ |
| fr | Routes | 40.9 | 42.8 | 43.9 | 44.6 | 47.4 | ✓ | ✓ |
| fr | Balades | 46.6 | 48.7 | 49.9 | 50.8 | 56.1 | ✓ | ✓ |
| fr | Trajets | 39.8 | 41.6 | 42.2 | 43.4 | 51.5 | ✓ | ✓ |
| fr | Profil | 31.6 | 33 | 33.5 | 34.5 | 43 | ✓ | ✓ |
| nl | Home | 34.8 | 36.4 | 37.8 | 38 | 36.1 | ✓ | ✓ |
| nl | Start | 28.7 | 30 | 30.6 | 31.3 | 37.3 | ✓ | ✓ |
| nl | Motoren | 49.4 | 51.7 | 53.1 | 53.9 | 60.3 | ✓ | ✓ |
| nl | Boekingen | 64 | 66.9 | 68.7 | 69.8 | 70.8 | ✓ | ✓ |
| nl | Reserveringen | 85.5 | 89.4 | 91.6 | 93.3 | 99.3 | ✗ | ✗ |
| nl | Ritten | 35.8 | 37.5 | 38.4 | 39.1 | 42.2 | ✓ | ✓ |
| nl | Routes | 40.9 | 42.8 | 43.9 | 44.6 | 47.4 | ✓ | ✓ |
| nl | Profiel | 38.7 | 40.4 | 41.1 | 42.2 | 50.3 | ✓ | ✓ |
| pl | Start | 28.7 | 30 | 30.6 | 31.3 | 37.3 | ✓ | ✓ |
| pl | Motocykle | 61.3 | 64.1 | 65.5 | 66.9 | 73.8 | ✓ | ✓ |
| pl | Motory | 41.6 | 43.5 | 44.5 | 45.4 | 51.5 | ✓ | ✓ |
| pl | Rezerwacje | 67.8 | 70.9 | 72.5 | 74 | 81.2 | ✗ | ✓ |
| pl | Wynajmy | 56.2 | 58.8 | 60.2 | 61.3 | 62.3 | ✓ | ✓ |
| pl | Trasy | 31.1 | 32.5 | 32.9 | 33.9 | 38.4 | ✓ | ✓ |
| pl | Profil | 31.6 | 33 | 33.5 | 34.5 | 43 | ✓ | ✓ |
| uk | Головна | 48.7 | 51 | 52.4 | 53.2 | 59.3 | ✓ | ✓ |
| uk | Мотоцикли | 69.3 | 72.5 | 74.4 | 75.6 | 80.5 | ✗ | ✓ |
| uk | Мото | 30.9 | 32.3 | 33.2 | 33.7 | 36 | ✓ | ✓ |
| uk | Бронювання | 77 | 80.5 | 83.1 | 84 | 89.8 | ✗ | ✗ |
| uk | Броні | 34.3 | 35.9 | 37 | 37.5 | 38.2 | ✓ | ✓ |
| uk | Оренда | 46.5 | 48.6 | 50.1 | 50.7 | 52 | ✓ | ✓ |
| uk | Маршрути | 64.5 | 67.5 | 69.3 | 70.4 | 71.6 | ✗ | ✓ |
| uk | Траси | 35.9 | 37.6 | 38.6 | 39.2 | 40.8 | ✓ | ✓ |
| uk | Поїздки | 49.1 | 51.3 | 52.6 | 53.6 | 55.5 | ✓ | ✓ |
| uk | Профіль | 51.3 | 53.6 | 55 | 55.9 | 57.3 | ✓ | ✓ |

#### Table C: Final set rendered in the nav (weight 800 for every tab = worst case, scale 1.0)

Margin = (column − 8) − label width: negative means the label is wider than column − 8.
Min gap = smallest real gap between two neighbouring labels; the gap to the screen edge is ≥ 10 px at ≥ 360 dp (6.4 px at 320 dp).

| lang | labels (px @ 11/800) | 360: min margin | 360: min gap | 390: min margin | 390: min gap | 320: min gap |
|---|---|---:|---:|---:|---:|---:|
| cs | Domů 35.5 · Motorky 48.8 · Rezervace 60.5 · Trasy 31.1 · Profil 31.6 | 3.5 | 17.3 | 9.5 | 23.3 | 9.3 |
| en | Home 34.8 · Bikes 32.2 · Bookings 55.5 · Routes 40.9 · Profile 38.7 | 8.5 | 23.8 | 14.5 | 29.8 | 15.8 |
| de | Home 34.8 · Bikes 32.2 · Buchungen 68.2 · Routen 42.5 · Profil 31.6 | -4.2 | 16.6 | 1.8 | 22.6 | 8.6 |
| es | Inicio 32.2 · Motos 35.9 · Reservas 52.8 · Rutas 33.4 · Perfil 31.5 | 11.2 | 27.6 | 17.2 | 33.6 | 19.6 |
| fr | Accueil 43.4 · Motos 35.9 · Locations 56.9 · Itinéraires 59.6 · Profil 31.6 | 4.4 | 13.7 | 10.4 | 19.7 | 5.7 |
| nl | Home 34.8 · Motoren 49.4 · Boekingen 64 · Routes 40.9 · Profiel 38.7 | 0 | 15.3 | 6 | 21.3 | 7.3 |
| pl | Start 28.7 · Motory 41.6 · Rezerwacje 67.8 · Trasy 31.1 · Profil 31.6 | -3.8 | 17.3 | 2.2 | 23.3 | 9.3 |
| uk | Головна 48.7 · Мото 30.9 · Оренда 46.5 · Маршрути 64.5 · Профіль 51.3 | -0.5 | 14.1 | 5.5 | 20.1 | 6.1 |

**Uppercase vs title case:**
- Title case is 10–26 % narrower, depending on the word.
- At 11/800 only the title-case set passes every language with natural words.
- Uppercase would need these swaps:
  - cs REZERVACE → ✗ (no good Czech synonym; VÝPŮJČKY is 62.1 but not the app's term)
  - de BUCHUNGEN → ✗
  - nl BOEKINGEN → ✗
  - pl REZERWACJE → WYNAJMY
  - uk БРОНЮВАННЯ → ОРЕНДА and МАРШРУТИ → ТРАСИ
  - fr ITINÉRAIRES → BALADES and RÉSERVATIONS → RÉSAS
- Even then, at 360 dp the real gaps are 5.6 px (pl) and about 7 px (cs MOTORKY|REZERVACE). See `nav_shots/nav_upper_360.png`.

**Verification of the final title-case set** (`verify3.json`):

| width | scale 1.0: overlap (< 6 px)? | strict (col − 8) misses | scale 1.15 |
|---|---|---|---|
| 320 | none (fr min 5.7 px, still > 4) | cs, de, fr, nl, pl, uk | overlaps → needs clamp + short labels |
| 360 | **none, min gap 13.7 px** | de −4.2, pl −3.8, uk −0.5 | fr 5.0 / uk 5.5 px gaps (no overlap) |
| 375 | none | de −1.2, pl −0.8 | none |
| 390 | none | **none** | none |
| 412 / 430 | none | none | none |

The short-fallback set (fr Balades, pl Motory + Wynajmy, uk Мото + Траси) has no overlap from 320 dp at scale 1.0 and from 360 dp at scale 1.15 (`verify2.json`).

**Word choices:**
- **cs:** keeps every existing app word; only "Motorky" is new, and it is the web and v1 canvas word.
- **en:**
  - "Bikes" instead of "Motorcycles" (88.5 px uppercase / 71 title, too wide).
  - "Bookings" instead of "Reservations" (76 title, too wide).
- **de:**
  - "Bikes" is common in the German motorcycle scene. "Motorräder" is 65.8 and fits only at ≥ 390 dp next to Buchungen.
  - "Buchungen" is the natural word. The alternatives that fit strictly at 360 are "Termine" (48.0) and "Reisen" (39.4), and both change the meaning.
  - Avoid "Fahrten": the app already uses it for recorded rides ("Fahrtenbuch").
- **es:** all existing words plus "Motos".
- **fr:**
  - "Locations" (= rentals, 56.9) instead of "Réservations" (76.2).
  - "Itinéraires" (59.6) stays.
  - "Balades" is the short fallback.
- **nl:**
  - "Boekingen" (64.0) instead of "Reserveringen" (85.5).
  - "Motoren" for bikes.
  - "Ritten" is free but means rides.
- **pl:**
  - "Motory" (colloquial, very common) instead of "Motocykle". Motocykle + Rezerwacje side by side leave only 7.5 px at 360 dp.
  - "Rezerwacje" stays; "Wynajmy" is the fallback.
- **uk:**
  - "Мото" instead of "Мотоцикли" (69.3).
  - "Оренда" (rental, 46.5) instead of "Бронювання" (77.0, too wide even at 390).
  - "Маршрути" stays; "Траси" is the fallback.
- **Owner check:** en/fr/nl/uk get a different noun for the reservations tab. Screen titles ("Moje rezervace", "My reservations"…) stay unchanged.

**i18n keys:**
- Add new keys `tabHome`, `tabBikes`, `tabBookings`, `tabRoutes`, `tabProfile`, plus `tabRoutesShort` / `tabBookingsShort` / `tabBikesShort` where §3 lists a fallback.
- Add them in all 8 languages, in both trees.
- Leave the old UPPERCASE `nav*` keys alone until the old nav is deleted. `app_shell.dart` is their only consumer.

---

## 4. Nav recommendation (C1 v2): premium, rank-aware, guaranteed no overlap

### 4.1 Geometry
- **Bar:**
  - Full width, 64 px content plus the bottom safe area (spec §2.6). No floating island: side insets would cost 4.8 px of label width per tab at 360 dp.
  - Top corners r20, so it reads as a "sheet".
  - 5 equal columns (72 px at 360 dp, 78 at 390). Hit target is the full column × 64 px.
- **Icon:** 24 px, line style (spec §2.9), at y = 10.
- **Active pill:** 52×30 r999 behind the icon at y = 7.
- **Label:** y = 40, 11 px. **Weight 800 for the active tab, 700 for inactive.** Space is reserved for 800, so switching tabs causes no layout jitter.
- **Labels are not inside the pill.** The current app wraps the label in the pill, which wastes 8 px of width.

### 4.2 Colours: dark "night glass" (recommended) vs white
| | Dark (recommended) | White (v1) |
|---|---|---|
| Bar | `#0A1F14` @ .96 + 20 px backdrop blur, top hairline neon @ .18, shadow 0 −10 28 black @ .25 | `#FFFFFF`, hairline `#E1EFE9` |
| Inactive icon / label | `#9FC4B1` (9.0:1) / `#B8D4C6` (10.9:1) | `#4A6B5A` (5.93:1). **Not** `#6C8A7B` (3.78) or `#8AAB99` (2.51) |
| Active label | `#FFFFFF` (17.2:1) | `#1A2E22` (14.4:1) |
| Active pill | Rank button gradient `rankTheme(level).btn.stops`; glyph `btn.label` (solved ≥ 4.5:1); glow `rankTheme.glow` | same |
| Rank ring (PROFIL avatar, FAB) | All 20 rank colours ≥ **3.86:1** on `#0A1F14` | 13 of 20 < 3:1 on white (VIP Platinum 1.10, Platinový 1.27, Jezdec / Zlatý / Legenda 1.40) |

Why dark:
- It matches the dark header, sticky bars, sheets and status strip.
- It makes the rank glow visible.
- It keeps rank rings legible for every level without per-rank hacks.
- Content scrolling under a dark bar ends cleanly, which feels premium.

### 4.3 Motion (all one-shot; the nav runs no infinite loops, per spec §0.6)
- **Tab press:**
  - Icon + label scale to .92 over 120 ms `easeOut`, back with a spring.
  - `HapticFeedback.selectionClick`.
  - No Material ink splash.
- **Indicator:**
  - The pill moves with a spring (`SpringDescription(mass:1, stiffness:520, damping:34)`, about 280 ms).
  - It does a "liquid" stretch: width 52 → 52 + 0.35·|Δx| → 52 at mid-flight, and colour stays continuous.
  - Reduced motion: it jumps, with a 120 ms crossfade.
- **Icon:**
  - Outline → filled crossfade over 180 ms, plus the existing `NavBounceIcon` pop retuned to the `pop` token (.85 → 1.08 → 1, 300 ms).
  - Reduced motion: no pop.
- **Label:** colour transitions over 180 ms. The weight changes in one step without moving anything, because the width is reserved.
- **Re-tapping the active tab** scrolls to the top (replaces the scroll-to-top FAB) with a 3 px icon nudge up.
- **Badges:**
  - Pop in when the count changes (`pop` token).
  - The REZERVACE needs-action dot does **one** ping when it appears, never a loop.
- **Content between tabs:** 210 ms fade-through (`CustomTransitionPage`, spec `tab` token).
- **Focused flows** (`/moto/:id`, `/booking`, `/payment`, edit): the nav slides out to Y 110 % over 300 ms and back on return. The AI FAB moves in sync (§5).
- **Level-up "landing"** (ties into guaranteed level-up, item 11). After `LevelUpCelebration` closes:
  - The PROFIL avatar's progress arc animates 0 → new progress over 700 ms.
  - The ring colour crossfades old → new rank colour.
  - The pill gradient and glow crossfade to the new `rankTheme`.
  - The AI FAB ring follows.
  - The level-up itself thus visibly "lands" in the chrome.
- **Nav taps as a level-up trigger:** a tab tap is a route change. Calling the watcher's check from the nav's `onTap` (or a `GoRouter` observer) closes the "no route-change trigger" gap from `personal.md`.

### 4.4 No-overlap guarantee in code (`v2_nav_bar.dart`)
1. Wrap the labels in `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0)`.
   - Long-press on a tab shows a "large content" bubble above it (icon + label at 2×, dark pill). This is how UIKit tab bars treat Dynamic Type.
   - The `Semantics(label:, selected:, button:)` label always uses the full word.
2. Inside a `LayoutBuilder`, measure each label with a `TextPainter` at w800, 11 px.
   - Compute the real gaps: col − (wᵢ + wᵢ₊₁)/2, and the edge gaps: col/2 − w₀/2.
3. If any gap is < 6 px (edge < 4), swap the offending label for its `…Short` key.
   - If it still fails, use 10.5 px for that bar only.
   - **Never use ellipsis, wrapping or `FittedBox` below 10.5 px.**
4. Add a golden test for each of the 8 locales at 320/360/390/430 dp that asserts the measured gaps.

---

## 5. AI floating button (`MgAiFab`, global)

**Where it lives:**
- In the `AppShell` `Stack`, above the content and the status strip, below sheets, scrims and global overlays (level-up, language, permission, intro).
- It replaces the Home bottom-left FAB, the v1 header AI circle and the Home scroll-to-top FAB.
- Screens outside the shell where AI help matters can embed the same widget: `/docs` and `/my-experiences`.

**Look:**
- 56 px disc, radial `#24563B` → `#0A1F14`.
- 2 px ring in the rank colour (`rankTheme.ring` / hex; ≥ 3.86:1 on the disc for every rank).
- Soft glow in `rankTheme.glow` (0 0 18 −2) and a drop shadow 0 8 18 black @ .35.
- Neon line glyph: a chat bubble with a spark. **No text.**
- Semantics and long-press tooltip use the localized `aiServiceAgent` (KI / IA / ШІ forms are already translated).
- **No idle loop.** It is not neon-filled, so the screen's one neon CTA stays the only primary.

**Vertical position** (`AnimatedPositioned`, `bottom` = lowest obstruction + 12, 300 ms `ease`; reduced motion → 0 ms). Measured in `nav_shots/bottom_zone_*.png` and `compose.js`:

| Screen state | Obstruction | FAB | Measured gap |
|---|---|---|---|
| Tab screens | nav 64 + safe 34 = 98 | 56 px, bottom 110, right 16 | 11–12 px to nav |
| + status strip (C2) | nav 98 + 8 + strip 52 = 158 | Rides up to bottom 170 (stacked above the strip; the strip keeps its full width) | 10–12 px to strip |
| `/moto/:id` detail (nav hidden) | sticky bar 110 | **Mini 44 px**, no glow, ring @ .7, bottom 122 | 12 px to bar, 29 px to REZERVOVAT |
| `/booking` | sticky summary (2-row C8, ~166) | Mini 44 px above the summary | ≥ 12 px |
| `/routes/:id`, places multi-select, edit flows (C6 delta box) | their sticky bar | Mini above the bar | ≥ 12 px |
| `/payment`, `/sos/payment`, `/success`, `/payment-result`, `/ai-agent`, `/messages/:id`, keyboard open, `/docs/scan`, `/route-nav*`, login/register/onboarding, any modal sheet | — | **Hidden** (fade + scale .8, 150 ms) | — |

**Obstruction registry:**
- `bottomObstructionProvider`, keyed by route. Each sticky bar wraps itself in `ReportBottomObstruction(child:)`, which reports its size after layout and clears it on dispose.
- `AppShell` adds the nav height (when visible) and the strip height (when visible).
- **Every scrollable** in the shell gets bottom padding = obstruction + 56 + 24, so the last item and the last card's `.go` button can scroll clear of the FAB.

**Scroll behaviour on long lists** (MOTORKY full-bleed cards, Trasy, Místa):
- While scrolling down, the FAB tucks into a 40 px "peek" half off the right edge (translateX +20, opacity .85). It returns 700 ms after scrolling stops or immediately on scroll-up.
- It stays tappable in peek state, so it is "available anytime".
- This also stops it sitting on top of a catalogue card's bottom-right `.go` button.

**Opening:**
- A container transform: the disc expands into the chat over 350 ms `Cubic(.2,0,0,1)`, radius 28 → 16 → 0, with the nav sliding out. Reduced motion: 150 ms fade.
- Implement it with a `PageRouteBuilder` and a `ClipRRect` radius tween. No new package is needed; `animations` is not in pubspec, and iOS pins old versions.

**Chat context:**
- The chat opens with context chips for the current screen, for example:
  - bike detail: "Zeptej se na Husqvarna 701 SM"
  - reservation: "Kódy a postup na pobočce", "Prodloužit"
  - SOS-allowed: a red "SOS" chip
- Keep the conversation in a provider for the session, so reopening continues it. Today it is lost on pop.

**First run:** one-time coach bubble "Zeptej se kdykoli" next to the FAB (8 languages), dismissed on tap. Never repeated.

**Tab highlight:** `/ai-agent` should no longer map to REZERVACE. The chat is a focused flow (nav hidden), so no tab is "selected".

---

## 6. SOS quick access

**Principles:**
- SOS is **never in the bottom nav** (5 tabs stay meaningful; no mis-taps while switching tabs).
- SOS is **never next to the AI FAB** (calm help bottom-right, emergency help top or in-card).
- Keep the existing visibility rule (`sosAllowed`). Outside an active rental, SOS hides and help goes through AI, Zprávy and the call link in Profil → Pomoc.

**Entry points while `sosAllowed`** (Home therefore always has SOS, as the owner asked):
1. **Home header, top-right:** the 44 px slot AI vacates becomes a red pill "SOS" (shield/alert icon + "SOS"; same word in all 8 languages; ~76×44).
   - It is visible as soon as Home opens.
   - It is far from the thumb's resting zone near the nav/FAB.
   - Outside a rental the slot shows nothing; the bell stays.
2. **Home ticket S8/S9** (v1 canvas): red 48 px circle at the card's right edge, ≥ 16 px from the neon primary button.
3. **Status strip priority 1:** "SOS hlášení nedokončeno · Dokončit". This replaces the "SOS dokončit" FAB.
4. **REZERVACE:**
   - list card: red badge + action
   - detail: action row "SOS" (red) and the CO TEĎ button
5. **PROFIL → Pomoc & podpora** (unchanged).
6. **AI chat:** the SOS chip, which is the existing `aiSuggestSos` logic.
7. **Recommended addition** (owner to confirm): a 44 px static SOS chip in the corner of `/route-nav*` while `sosAllowed`. It has no motion, consistent with the "no decorative motion in navigation" rule.

**Avoiding accidental taps without slowing a real emergency:**
- The entry button only **navigates** to the SOS start screen. The irreversible steps are:
  - calling 112 / 155 / 158 — opens the system dialer, where the user still has to press call
  - sending an incident — explicit button on each sub-screen

  So **no hold-to-confirm** on entry: under stress a long press fails and feels broken.
- Targets ≥ 44 px with ≥ 8 px separation from other targets (≥ 16 px from the neon CTA). Never placed on the bottom 120 px of the screen.
- Feedback: `HapticFeedback.heavyImpact` and the press scale.
- **Colour:**
  - With white text: fill `#D92D20` (4.83:1) or `#C62828` (5.62:1).
  - `#EF4444` (spec `sos`) with white text is 3.76:1 and fails AA for 11–14 px text. Keep `#EF4444` for dots and icons only (3.76:1 on white, 4.58:1 on night — passes the 3:1 non-text rule).
- **Motion:** in the S1 / S8 ticket the red ping is the screen's single "live indicator" loop. The header pill is static. Reduced motion → no ping.

---

## 7. Open points for the owner
1. **Title-case tab labels** instead of the v1 UPPERCASE. Required for Czech to fit at 11 px without shrinking.
2. **New nouns:**
   - en "Bikes" / "Bookings"
   - de "Bikes"
   - fr "Locations"
   - nl "Boekingen"
   - pl "Motory"
   - uk "Мото" / "Оренда"
3. **Dark nav** (recommended for rank legibility) vs the white v1 nav.
4. **SOS chip on the route-navigation screen** during a rental (new entry point).
5. Opening the AI chat as a **full-screen container transform** vs a 92 % bottom sheet over the current screen.
