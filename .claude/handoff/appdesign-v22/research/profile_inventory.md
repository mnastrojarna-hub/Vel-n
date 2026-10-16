# understand:profile: complete PROFIL inventory and a clearer IA (omits nothing)

Source: `Motogo-app-main/motogo-app-flutter/lib` (Android master). The folders `features/profile`, `documents`, `loyalty`, `messages`, `shop` and `branches` are byte-identical in the iOS tree (`diff -rq` is clean). The only platform difference in this area is `features/payment/payment_methods_screen.dart`: iOS has no manual card entry.

Czech texts are quoted verbatim from `lib/core/i18n` (key = text). Live flags (anon read, 2026-10-15): `eshop_visible=false`, `loyalty_leaderboard=false`, `ai_assistant=true`, `whatsapp_integration=false`.

---

## 0. Key facts (TL;DR)

1. **There is no PROFIL tab today.** `/profile` is opened by the hamburger in the Home header (`home_header.dart:57`, `context.go(Routes.profile)`). While the customer is in Profil and all its sub-screens, the 4-tab nav highlights **DOMŮ** (`app_shell.dart _currentIndex` returns 0). The v2 plan maps `/profile*`, `/messages*`, `/docs*`, `/invoices`, `/contracts`, `/pobocky*`, `/loyalty`, `/shop*`, `/cart`, `/checkout`, `/voucher` and `/permissions` to the PROFIL tab.
2. **What `/profile` shows, in order:**
   - Header: the rank-ringed logo (tap → `/loyalty`), a full-name pill and a "PILOT: {přezdívka} ✎" chip.
   - `LoyaltyRankCard`.
   - Pobočky, then E-shop (only when the flag is on).
   - **Můj účet**: Osobní údaje (inline form), Zprávy z Moto Go [badge], Moje doklady, Faktury a vyúčtování, Dokumenty a smlouvy, Platební metody.
   - **Nastavení**: Oprávnění aplikace, Notifikace, Soukromí a souhlasy, Změna hesla, Jazyk aplikace, Měna.
   - **Pomoc & Podpora**: SOS (only during a rental), Nápověda & FAQ.
   - **Ostatní**: Odhlásit se, Smazat účet.
   - Footer: "MotoGo24 v{version}".

   In total that is **22 entry points**, which lead to **19 screens, sheets and dialogs** plus the dormant e-shop flow (5 more screens).
3. **The AI assistant is not in Profil.** It opens only from the Home FAB and from the SOS screen. **The full ranks screen (`/loyalty`) is reached only by tapping the logo ring.** The rank card itself is not tappable; only its "O programu" link opens a sheet.
4. **Data the customer has given us but cannot see or edit in Profil:**
   - `profiles.gear_sizes` (rider and passenger sizes, plus `rider_own`). It is saved at every payment and pre-fills the next booking.
   - Company billing data (`company_name`, `company_address`, `ico`, `dic`). It is printed on invoices but entered only on the web.
   - `emergency_contact`/`emergency_phone`, `preferred_branch`, `avatar_url`. These exist in the DB with no UI.
5. **Hard requirement:** the path **Profil → Smazat účet** must keep existing under that name. The public page `motogo-web-php/pages/smazani-uctu.php` (Google Play "Data safety" URL, also App Store 5.1.1(v)) describes it literally: "Přejděte do sekce **Profil**. Zvolte **Smazat účet**."
6. **Measured label fit** (Montserrat, 8 languages, see §5):
   - A **3-column** tile grid does **not** fit. It fails for uk "Повідомлення", de "Zahlungsmethoden", nl "Betaalmethoden" / "Loyaliteitsrangen", uk "Інтернет-магазин", and nl "Documenten en contracten" (3 lines).
   - A **2-column** grid (146 px text, 13/800, at most 2 lines) fits every label in every language.
   - In list rows, only fr "Confidentialité et consentements" wraps, so rows must allow 2 lines.
7. **Proposed v2 IA (§7):**
   - A dark "Můj klub" header with avatar, rank ring, nickname and rank strip.
   - An attention strip that appears only when something is actionable.
   - Six 2-column tiles: Zprávy · Moje doklady · Faktury · Dokumenty a smlouvy · Platební metody · Pobočky.
   - An Osobní údaje summary card with "Upravit".
   - Grouped lists: Nastavení · Pomoc a podpora · Ostatní.
   - The version footer.

   Every current item keeps a home; the full mapping is in §7.6. Nothing moves more than one tap deeper than today. Several items move one tap *closer*: rank, documents status, card, unread messages.

---

## 1. How PROFIL is reached today, and its routes

| Route | Screen | Opened from |
|---|---|---|
| `/profile` | `ProfileScreen` (shell, `NoTransitionPage`) | Home hamburger. Fallback "back" from docs, invoices, contracts and permissions (`backOr(Routes.profile)`) |
| `/loyalty` | `LoyaltyRanksScreen` | Logo ring (`LogoRow`, Home and Profil header) via `openLoyaltyRanks` |
| `/messages`, `/messages?n=<admin_message_id>` | `MessagesScreen` | Profil row; push types `message`, `sos`, `door_codes`; SOS detail "Zprávy" |
| `/messages/:id` | `ThreadDetailScreen` | Thread tile; new-thread sheet |
| `/docs` (root route, outside the shell) | `DocumentsScreen` | Profil row; global FAB "NAHRÁT DOKLADY"; access-codes card; `/success` |
| `/docs/scan[?mode=dl_only]` (root) | `DocumentScannerScreen` | /docs buttons |
| `/invoices` | `InvoicesScreen` | Profil row |
| `/contracts` | `ContractsScreen` | Profil row |
| *(pushed MaterialPageRoute)* | `PaymentMethodsScreen` | Profil row (no named route) |
| `/permissions` | `PermissionsScreen` | Profil row |
| `/pobocky`, `/pobocky/:index` | `BranchesInfoScreen`, `BranchDetailScreen` | Profil row |
| `/shop`, `/shop/:id`, `/cart`, `/checkout`, `/voucher` | E-shop | Profil row (flag), cart FAB, push `shop_order` |
| `/sos` | `SosReportScreen` | Profil row (only while `hasActiveRentalProvider`) |
| `/ai-agent` | `AiAgentScreen` | Home FAB, SOS screen. **Not Profil** |
| sheets/dialogs | Consent ×2, password, language, currency, delete account, nickname, gallery doc kind, branches sheet, rank info | see §2 |

---

## 2. Screen-by-screen inventory

### 2.1 `/profile`: `features/profile/profile_screen.dart`

**Lifecycle and states**
- `initState` invalidates `profileProvider` and `loyaltyStatusProvider`, so every open reloads fresh data.
- Loading: a full-screen spinner.
- Error: centred text `profileLoadError` = "Chyba načítání profilu".
- No pull-to-refresh.

**Header** (dark, bottom radius 24)
- `LogoRow`: logo + "MOTO GO 24" + `logoSubtitle` "PŮJČOVNA MOTOREK".
  - A ring (4–5 px) and glow in `loyalty.color` (Legenda uses a gradient).
  - Tap → `/loyalty`. There is no ring when loyalty is null.
- Pill with `full_name`, or `pilot` "Pilot" when there is none.
- `_NicknameChip`: `homePilotLabel` "PILOT: " + nickname (or the first name) + ✎, tinted in the rank colour. Tap → nickname dialog (§2.3).

**Body**, top to bottom (all rows are `ProfileMenuItem`: white, 36 px emoji tile, label 13/700, optional red badge "9+", "›")

1. `LoyaltyRankCard` (§2.4). Hidden entirely (`SizedBox.shrink`) when the status is null.
2. 📍 `branchesLabel` "Pobočky" → `/pobocky`. It sits where the e-shop used to be.
3. 🛒 `eshopMenu` "E-shop" → `/shop`. **Only when `eshop_visible`** (live: off).
4. Section `myAccount` "Můj účet":
   - 👤 `personalInfo` "Osobní údaje": toggles the inline form (§2.2). **Collapsed by default.**
   - 📩 `messages` "Zprávy z Moto Go" + badge `adminUnreadCountProvider` (unread `admin_messages`) → `/messages`.
   - 📋 `documents` "Moje doklady" → `/docs`.
   - 🧾 `invoices` "Faktury a vyúčtování" → `/invoices`.
   - 📄 `contracts` "Dokumenty a smlouvy" → `/contracts`.
   - 💳 `paymentMethods` "Platební metody" → `PaymentMethodsScreen`.
5. Section `settings` "Nastavení":
   - 📱 `permissions` "Oprávnění aplikace" → `/permissions`.
   - 🔔 `notifications` "Notifikace" → consent sheet `notif`.
   - 🔒 `privacy` "Soukromí a souhlasy" → consent sheet `priv`.
   - 🔑 `changePassword` "Změna hesla" → sheet.
   - 🌐 `language` "Jazyk aplikace" → sheet.
   - 💱 `currency` "Měna" → sheet.
6. Section `helpAndSupport` "Pomoc & Podpora":
   - 🆘 `sosTitle` "SOS — Pomoc na cestě", red tile → `/sos`. **Only while `hasActiveRentalProvider`** (any `sosAllowed` reservation).
   - ❓ `helpFaq` "Nápověda & FAQ" → external browser `WebLinks.faq(lang)` = `https://www.<jazyková doména>/jak-pujcit/faq`.
7. Section `otherSection` "Ostatní" (red label, `#FEF2F2` tile):
   - 🚪 `logout` "Odhlásit se":
     - Resets `bookingDraftProvider`, `bookingMotoProvider` and `catalogFilterProvider`, then signs out.
     - Toast `logoutTitle` "Odhlášení" / `goodbye` "Nashledanou!", then `/login`.
     - **No confirmation.**
   - 🗑️ `deleteAccountBtn` "Smazat účet" → dialog (§2.17).
8. Footer: `MotoGo24 v{appVersion}` (10 px, grey).

### 2.2 Osobní údaje: inline form (in the same screen)

| Field | Label (cs) | Column | Notes |
|---|---|---|---|
| Name | `fullNameLabel` "Jméno a příjmení" | `full_name` | |
| E-mail | `email` "E-mail" | `email` | **Read-only**: it is the login identity and is changed only through support |
| Phone | `phone` "Telefon" | `phone` | phone keyboard |
| City | `city` "Obec / město" | `city` | |
| Postcode | `zip` "PSČ" | `zip` | |
| Street | `streetShort` "Ulice a č.p." | `street` | |
| Country | `countryLabel` "Stát" | `country` | free text |
| Date of birth | `dob` "Datum narození" | `date_of_birth` | Day/month/year dropdowns. Years from now − 100 to **now − 18** (an older stored value stays selectable) |
| ID / passport no. | `idNumberFull` "Č. OP / pasu" | `id_number` | Printed in the contract |
| Licence no. | `licenseNumberFull` "Č. řidičského průkazu" | `license_number` | |
| Licence valid until | `licenseExpiry` "Platnost ŘP do" | `license_expiry` | Years now to now + 20 |
| Licence groups | `licenseCategory` "Kategorie ŘP" | `license_group[]` (enum) | Multi-select chips **AM · A1 · A2 · A · B**. Saved through RPC `set_my_license_group`; a plain update would fail on the enum |

- Button 💾 `saveChanges` "Uložit změny" runs `profiles.update(...)` and then the RPC.
- Success toast: `saved` "Uloženo" / `profileUpdated` "Profil aktualizován".
- Error toast: `error` "Chyba" + the exception text. `handleAuthError` handles session expiry.

### 2.3 Nickname dialog: `home/nickname_provider.dart` `showNicknameDialog`

- Title `editNickname` "Upravit přezdívku". The text field's hint is the first name.
- Buttons: "Reset" (hard-coded, not translated) and "OK".
- Stored locally in SharedPreferences, which is the source of truth for the header. It is also synced fire-and-forget to `set_loyalty_nickname` for the leaderboard.
- The same dialog opens from the Home pilot badge.

### 2.4 `LoyaltyRankCard`: shown in Profil and on Home

- Kicker `loyaltyMyRank` "Věrnostní rank" (uppercase).
- A dark pill with `GlowPulse` + `ShimmerSweep` loops, 🏅, the rank name in uppercase and "{pct} %".
- Progress bar for level 1–20.
- `loyaltyLevelOf` "Level {lvl} / {max}" · `loyaltyBookingsCount` "{n} b. · rezervace z appky i webu".
- `loyaltyNextRank` "Ještě {n} b. do: {next} ({pct} %)", or `loyaltyMaxRank` "Maximální rank — užíváš nejvyšší slevu!".
- "★ " + `loyaltyAppOnly` "Platí jen pro rezervace vytvořené v aplikaci".
- ℹ️ `loyaltyInfoBtn` "O programu" opens a bottom sheet with the title "🏅 " + `loyaltyInfoTitle` "Věrnostní program MotoGo24" and these rules:
  - `loyaltyRulePoints` "Dokončená rezervace na 1–6 dní = 1 bod, na 7 a více dní = 2 body (z aplikace i webu)"
  - `loyaltyRuleLong` "Rezervace delší než 7 dní = 4 body → postup o 2 ranky najednou" (**stale, contradicts the rule above**: rank.md D1)
  - `loyaltyRuleLevel` "Každé 2 body = nový rank a +1 % slevy (max 20 %)"
  - `loyaltyRuleAppOnly` "Sleva se uplatňuje a zobrazuje POUZE u rezervací vytvořených v aplikaci"
  - `loyaltyRuleCombo` "Kombinuje se s promo kódy i dárkovými poukazy — slevy se sčítají"
- The card itself is **not** a link to `/loyalty`.

### 2.5 `/loyalty`: `LoyaltyRanksScreen`, plus the leaderboard and the level-up

**Screen**
- Dark gradient with `_AmbientSparks` (floating sparks).
- Top bar: back arrow, `loyaltyRanksTitle` "Věrnostní ranky", 🏍️.
- `_Hero`:
  - Title `loyaltyInfoTitle` / `loyaltyMyRank`, rank name, %, progress bar.
  - `loyaltyLevelOf` · `loyaltyBookingsCount`; `loyaltyNextRank` or `loyaltyMaxRank`; `loyaltyAppOnly`.
  - `loyaltyClimbMotivation` "Každá rezervace tě posune výš. Jak vysoko vystoupáš ty? 🏔️".
- `LoyaltyLeaderboardSection`, **only when `loyalty_leaderboard` is on (live: off)**:
  - 🏆 `loyaltyLeaderboardTitle` "Žebříček jezdců".
  - `loyaltyLeaderboardSub` "Kdo za měsíc postoupí o nejvíc ranků. Při shodě rozhodují najeté km bez nehody a škrábnutí."
  - 👑 `loyaltyLastWinner` "Minulý měsíc vyhrál {nick} → postup o 2 ranky".
  - A top-3 podium 🥇🥈🥉, then a list with `loyaltyKm` "{n} km", `loyaltyDays` "{n} dní" and `loyaltyRankGain` "postup +{n}". The customer's own row is marked.
  - Empty state 🏁 `loyaltyLeaderboardEmpty` "Zatím nikdo nesoutěží. Buď první!".
  - Switch `loyaltyShowMe` "Zobrazovat mě v žebříčku" (RPC `set_loyalty_leaderboard_optin`). Its subline reads `loyaltyShowMeOn` "Soutěžíš o hlavní měsíční výhru — postup o 2 ranky." or `loyaltyShowMeOff` "Jsi skrytý/á a nesoutěžíš o měsíční výhru (postup o 2 ranky)."
  - When there is no server nickname: `loyaltyNeedNickname` "Bez vlastní přezdívky se v žebříčku zobrazíš jako jméno s pořadovým číslem. Klepni na odznak pilota a změň si ji."
- Ladder 20 → 1 (`StaggeredReveal`):
  - Each rank shows locked / current / unlocked state, a level badge, the name and a % pill.
  - "od {n} bodů" (`loyaltyFromBooking`), which is **off by one** (rank.md D2).
  - From rank 3: `loyaltyGearBenefit` "Výbava spolujezdce i veškerá obuv zdarma".
  - The current level has the `loyaltyYouChip` "TY" chip.
- `_RulesCard`: the same five rules **plus** `loyaltyRuleGear` "Od 3. ranku: veškerá výbava i obuv — řidič i spolujezdec — ZDARMA (jen v aplikaci)".

**States:** levels loading → spinner; error → empty. A null status still shows the ladder.

**Level-up celebration** (`loyalty_levelup_overlay.dart`, global, `MaterialApp.builder`): **owner: DO NOT CHANGE.**
- Kicker `loyaltyLevelUpKicker` "NOVÝ RANK", or `loyaltyMegaLevelUpTitle` "MIMOŘÁDNÝ POSTUP".
- `loyaltyDiscountForever` "Tvoje sleva {pct} % platí napořád".
- `loyaltyValuedNote` "Základní výhoda navždy — jen pro tebe v aplikaci. Díky, že jezdíš s MotoGo24."
- `loyaltyYourBike` "TVŮJ STROJ" · {bike}.
- `loyaltyContinue` "Pokračovat".
- A ~67 s video and photo montage with music. The logo colour switches old → new with a "+N" badge.

Trigger chain: rank.md §4. Profil only needs to keep the entry points (logo ring, rank strip) and must never block it.

### 2.6 Pobočky: `features/branches/*` + `features/profile/widgets/branches_sheet.dart`, `branch_detail_card.dart`, `branch_moto_list.dart`

**`/pobocky` (`BranchesInfoScreen`)**
- App bar `branchesLabel` "Pobočky". Pull-to-refresh.
- CMS texts come from `cms_variables web.pobocky.*`, translated (fallback en → cs). Defaults are in `branches_info_provider.dart`:
  - `h1` "Pobočky MotoGo24"
  - `intro`: two places, Mezná (obslužná) and Velké Němčice (samoobslužná, kódy)
- Per branch, a card:
  - Badge ("Obslužná pobočka" / "Samoobslužná pobočka"), title ("Mezná u Pelhřimova" / "Velké Němčice u Brna").
  - 📍 address, 🕑 hours (full CMS text).
  - Button `detail_button` "Detail pobočky" → `/pobocky/<i>`.
- CTA box: `cta.title` "Vyberte si motorku na své pobočce", `cta.text` "V rezervaci si zvolíte pobočku a nabídnou se vám jen motorky, které na ní jsou." and button `cta.button` "REZERVOVAT ONLINE" → `/search`.
- Outlined button 🏍️ `branchesMotos` "Motorky na pobočkách" → **branches sheet** (below).

**`/pobocky/:i` (`BranchDetailScreen`)**
- Card with: badge, title, 📍 address, 🕑 hours, `text` (about), 🧥 `gear` (full gear and size text).
- Optional video (`video` + `video_title`). An MP4 plays inline with a progress bar; YouTube opens externally.
- Button `branchesNavigate` "Navigovat na pobočku" (Google Maps search).
- Collapsible 🧭 `steps_title` "Jak to probíhá" (fallback `pickupProcedure` "Postup při vyzvednutí") with the full CMS `steps`:
  - Mezná has 4 steps.
  - VN has 6 steps (codes order, brána, šatna č. 8, protokol, brána při odjezdu, vrácení do 24:00, umytá a bez rezervy).
- Collapsible 📷 `branchPhotos` "Fotky pobočky" (VN only):
  - 4 photos: `branchPhotoBox`, `branchPhotoBox2`, `branchPhotoKiosk`, `branchPhotoParking`.
  - Two-column thumbnails; tap opens a fullscreen gallery.
- Collapsible 🏍️ `branchMotosTitle` "Motorky na pobočce ({n})": thumbnail, model, "{cc} cc · {kW} kW · ŘP {skupiny}" → `/moto/:id`. Hidden when the branch has no bikes.
- CTA box with "REZERVOVAT ONLINE" → `/search` with this branch pre-filtered (and the dates, if chosen).

**Branches sheet** (`showBranchesSheet`; **not dead code**: it is opened by "Motorky na pobočkách")
- Fetches `branches` (active, `is_open`) and active `motorcycles`.
- Draggable sheet titled `branchesTitle` "Pobočky MotoGo24".
- Per branch, an expandable `BranchDetailCard`:
  - Name, "{adresa}, {město} · Samoobslužná/Obslužná".
  - Badge `nonstop` "Nonstop" / `closed` "Uzavřeno".
  - `openInMaps` "Otevřít v mapách" (GPS directions).
- Expanded, it shows these rows:
  - `addressLabel` "Adresa"
  - `phone` "Telefon"
  - `branchCodeLabel` "Kód pobočky"
  - `localityType` "Typ lokality" (`usageTouristic`/`Urban`/`Mountain`/`RecWater`/`Metro`/`UrbanTransit`)
  - `operationLabel` "Provoz"
  - `capacityLabel` "Kapacita" = `max8Motos` "Max 8 motorek"
- Expanded, it also has these buttons and the bike list:
  - `navigateToBranch` "Navigovat na pobočku"
  - `callLabel` "Zavolat {phone}"
  - `BranchMotoList` "Motorky na pobočce ({n})": category + licence, tap → detail
- Error toast: `branchesLoadFailed` "Nepodařilo se načíst pobočky".

> v1 spec §11 row 104 called `branches_sheet` / `branch_detail_card` / `branch_moto_list` "duplicates to delete". **Careful.** They are the **only** place in the app that shows the branch **phone + "Zavolat"**, the **branch code**, the **locality type**, the **capacity** and the **open/closed** state. Fold these into the v2 branch detail before deleting anything.

### 2.7 Zprávy: `features/messages/*`

**`/messages` (`MessagesScreen`, `focusId` from a push)**
- App bar `messagesTitle` "Zprávy". The ✓✓ action `markAllRead` "Označit vše jako přečtené" shows only on the notifications tab when there are unread items.
- Two tabs: `notificationsTab` "Oznámení" (with an unread badge) and `conversationsTab` "Konverzace".

**Oznámení** (`admin_messages` realtime stream)
- Each card shows:
  - A type icon: 🚑 sos_response/sos_auto · ⚠️ accident_response · 🛠️ replacement · 🚚 tow · ℹ️ info · 🙏 thanks · 🎁 voucher · 🔑 door_codes · 📩 other.
  - Title, translated (`titleFor(lang)`), or `messageFromMotoGo` "Zpráva z Moto Go".
  - The message, 3 lines, expandable.
  - Date "d. m. hh:mm".
  - When unread: a pale green background, a 4 px green left bar and a red dot.
- Tap expands the card and marks it read. A deep link `?n=<id>` expands and marks that message.
- Empty: 📨 `noNotifications` "Žádná oznámení".

**Konverzace** (`message_threads` realtime)
- Top card `newConversation` "Nová konverzace" / `writeMotoGo` "Napsat MotoGo24" opens a sheet:
  - Subject field `conversationTopic` "Napište téma konverzace..." and button `send` "Odeslat".
  - Validation `enterSubject` "Zadejte předmět konverzace". Error `tryAgainPlease` "Zkuste to prosím znovu."
- Thread tiles show:
  - 🚑 for "SOS:" subjects, otherwise 💬.
  - Subject (or `conversation` "Konverzace").
  - A green unread-count circle and a green left bar.
  - A 60-character preview and the date.
- Threads include the **private ride feedback** threads ("Napiš nám přímo, co máme zlepšit", subject `<název> #XXXXXXXX`, `ride_feedback.dart`).
- Empty: 💬 `noConversations` "Žádné konverzace".

**`/messages/:id`**
- Title = subject. Status chip `closed` "Uzavřeno" / `active` "Aktivní".
- Chat bubbles: customer right, admin left, with "date time". Realtime.
- Empty: `writeFirstMessage` "Napište první zprávu".
- Input `writeMessageHint` "Napište zprávu..." + `send` "Odeslat". **The input is hidden when the thread is closed.**
- Error: `messageSendFailed` "Zprávu se nepodařilo odeslat".

**Badge source.** Profil row, hamburger and shell use `adminUnreadCountProvider`, which counts unread notifications. Unread thread messages count per thread only. Admin replies also arrive as an `admin_message` through `trg_bridge_admin_message`, so they reach the badge.

### 2.8 Moje doklady: `/docs`, `documents_screen.dart` + `docs_gate_*`

**App bar:** `myDocuments` "Moje doklady", sub `docsBeforeFirst` "Před první rezervací – stačí jednou".

**Data:** `docsScreenStatusProvider` = profile verification + `get_docs_gate_checklist`.

**Blocks, top to bottom**
1. Incomplete only: amber ⚠️ `docsRequiredInfo` "Pro rezervaci motorky jsou nutné oba doklady. Data z dokladů se automaticky uloží do vašeho profilu."
2. Verification banner:
   - Complete: ✅ `docsVerified` "Doklady ověřeny" · `idPassportShort` "OP/Pas + Řidičský průkaz".
   - Otherwise: amber, listing what is missing (`idOrPassport` "OP nebo pas", "řidičský průkaz").
3. 💡 `scanTips` "Foťte na rovném světlém povrchu, bez odlesků a stínů. Doklad musí být celý v záběru a čitelný."
4. **Primary** 📷 `scanDocsCamera` "NASKENOVAT DOKLADY KAMEROU" → `/docs/scan`.
5. Only when the ID is done and the licence is missing: 🏍️ `scanDlOnly` "NASKENOVAT ŘIDIČSKÝ PRŮKAZ" → `/docs/scan?mode=dl_only`.
6. 📁 `uploadFromGallery` "NAHRÁT Z GALERIE" opens the sheet `galleryPickDocType` "Co je na fotce?" with five options: Občanský průkaz – přední/zadní strana · Cestovní pas · Řidičský průkaz – přední/zadní strana.
   - It then picks the image, runs OCR and uploads it.
   - Toasts: `uploading` "Nahrávám..." / `processingDoc` "Zpracovávám doklad"; `uploaded` "Nahráno" / `docProcessed` "Doklad zpracován"; on failure `scanFailed` "Nepodařilo se načíst" / `scanUseCamera` "Zkuste prosím naskenovat doklad kamerou."
7. Status block:
   - **Nothing uploaded:** amber `docsNotVerified` "Doklady neověřeny" + `docsNotVerifiedDesc` "Motorku lze rezervovat, ale kód k otevření boxu s klíčem obdržíte až po ověření dokladů. Doporučujeme nahrát předem."
   - **Otherwise:** `docsStatus` "Stav dokladů" with two rows: 🪪 `idCardPassport` "Občanský průkaz / Pas" and 🏍️ `driversLicense` "Řidičský průkaz".
     - Each row reads `verified` "Ověřeno" / `notVerified` "Neověřeno".
     - Actions: `deleteDoc` "Smazat" (dialog `deleteDocTitle` "Smazat doklad?" / `deleteDocDesc` "Doklad bude smazán a bude potřeba nahrát nový.") or `scan` "Skenovat".
   - Gate line `missing` "Chybí: …", built from `gmIdOrPassport` "OP (líc a rub) nebo pas", `gmIdBack` "rub OP", `gmIdFront` "líc OP", `gmDl` "ŘP (líc a rub)", `gmDlBack` "rub ŘP", `gmDlFront` "líc ŘP", `gmDob` "datum narození", `gmAge18` "věk 18+", `gmDlExpiry` "platnost ŘP", `gmDlExpired` "platný ŘP (propadl {date})", `gmGroup` "skupina ŘP" and `gmGroupLow` "skupina ŘP {groups}".
   - When codes are ready: ✅ `docsVerifiedDesc` "Doklady ověřeny — zákazník může dostat kódy k vyzvednutí" (third-person wording, see §4).

**States:** loading spinner; error `loadingError` "Chyba načítání". Delete toasts: `deleting` "Mažu..." / `deletingDoc` "Odstraňuji doklad" → `deleted` "Smazáno" / `docRemoved` "Doklad odstraněn, nahrajte nový", or `deleteFailed`.

**Global:** the shell FAB `docsBlockingBtn` "NAHRÁT DOKLADY" shows while there is a paid active or upcoming booking and the documents are incomplete. It is dismissible and hidden on `/docs*` and `/payment`.

### 2.9 `/docs/scan`: `document_scanner_screen.dart` (+ `document_camera_screen.dart`)

1. Title `scanDocuments` "Skenování dokladů".
2. Choose the document, `selectIdDocument` "Vyberte doklad totožnosti": 🪪 Občanský průkaz · 📕 Cestovní pas · 🏍️ `dlOnly` "Pouze řidičský průkaz". Badges 🔒 `secureRecognition` "Zabezpečené rozpoznávání" and 📱 `dataStoredLocally` "Data uložena v telefonu" (**inaccurate**, see §4).
3. Steps:
   - OP: id_front, id_back, dl_front, dl_back.
   - Passport: passport_front, passport_back, dl_front, dl_back.
   - dl_only: dl_front, dl_back.
4. Camera with a frame (`placeIdInFrame` / `placePassportInFrame` / `placeLicenseInFrame`), step dots and "{strana} n/N". During OCR: `processing` "Zpracovávám...".
5. Result overlay:
   - Success: `docScannedOk` "Doklad úspěšně naskenován" or `docScannedPartial`. Fields: `fieldName`, `fieldDob`, `fieldIdNum`, `fieldLicenseNum`, `fieldCategory`, `fieldExpiry`.
   - Error: `errNetwork`, `errTimeout`, `errServerConfig`, `errServerUpstream`, `errServerGeneric`, `errOcrFailed`, `errOcrHint`, `errOcrEmpty`, `errNoFields`, `errNoFieldsHint`, `errImagePrep`, `errCameraPermission`, `errCameraGeneric`, `errUnknown`, `scanSaveFailed`.
   - Actions: `retry` "Zkusit znovu", `skipArrow` "Přeskočit →", `continueArrow` "Pokračovat →".
6. After N failed attempts, `scanHelpTitle` "Pomůžeme vám osobně" / `scanHelpText` "Sken dokladu se nepodařil po {n} pokusech. Zavolejte nám nebo napište — dokončíme ověření ručně a vaše rezervace bude připravena." Actions: `callLabel` "Zavolat" +420…, `scanWriteBtn` "Napsat" e-mail, `scanTryAgainAnyway` "Zkusit přesto ještě jednou", `scanCloseScanner` "Zavřít skener".
7. Done:
   - Toast `scanComplete` "Skenování dokončeno" + `docsUploadedVerified` "Doklady nahrány a ověřeny".
   - Or `codesStillWithheld` (+ "Chybí: …").
   - Or `docsScanIncompleteTitle` / `docsScanIncomplete`.
   - Or `docPhotoSavedNoOcr`.
   - Then → `/docs` (or Home).

### 2.10 Faktury: `/invoices`

- App bar `invoicesTitle` "Faktury".
- Grouped by year (newest first). Each tile shows:
  - A type icon: 🧾 proforma/advance · 💰 final · ✅ payment_receipt · 🛒 shop_final · 📕 credit_note · 📄 other.
  - The number, or the type label: `docProformaInvoice` "Zálohová faktura", `docFinalInvoice` "Konečná faktura", `docPaymentReceipt` "Doklad k platbě", `docShopInvoice`, `docShopProforma`, `docCreditNote` "Dobropis", `docInvoiceGeneric` "Doklad".
  - The date, and the amount "{n} Kč". A credit note is red with "−".
- Tap builds the HTML (`InvoiceHtmlBuilder`, including profile billing fields and company data) and opens `DocWebViewScreen`.
- Empty: 🧾 `noInvoices` "Žádné faktury" / `invoicesAutoGenerated` "Faktury se generují automaticky".
- Error: `loadingError`.

### 2.11 Dokumenty a smlouvy: `/contracts` + viewers

**App bar:** `documentsAndContracts` "Dokumenty a smlouvy".

**Fixed tiles**
- 📋 `termsOfService` "Všeobecné obchodní podmínky" · `vopSubtitle` "VOP — MotoGo24" → `showLegalDocument('vop')`.
- 🔒 `dataProcessing` "Zpracování osobních údajů" · `gdprSubtitle` "GDPR — informace" → `'gdpr'`.
- ⚠️ `damageProtocol` "Protokol o poškození" · `damageProtocolSubtitle` "Vzor protokolu o poškození" (translated template).

**Real documents of the customer's bookings** (`contract`, `protocol`, `protocol_damage`, `vop`)
- Titles: `rentalContract` "Smlouva o pronájmu", `docHandoverProtocol` "Předávací protokol", `damageProtocol`, `termsOfService`.
- Each tile shows its date; tap opens the signed HTML or the stored PDF (`booking_doc_viewer.dart`).
- Empty: `noOtherDocs` "Žádné další dokumenty".

**Viewers**
- `DocWebViewScreen`: HTML or data URI; `loadingError` + `retry`.
- `PdfPagesScreen`: rendered pages + `openOutsideApp` "Otevřít mimo aplikaci".

**Legal loader**
- `loadLegalDoc` shows a fresh translation, otherwise the binding Czech text with a note. It never shows a stale translation.
- VOP and GDPR carry the footer `consentGivenAtBooking` "Souhlas udělen při rezervaci (zaškrtnutím podmínek)".
- Failures: `legalLoadFailed`, `docNotAvailableYet`.

### 2.12 Platební metody: `payment_methods_screen.dart`

- App bar `paymentMethodsTitle` "Platební metody". Data: `paymentMethodsProvider` (table `payment_methods` + edge `manage-payment-methods`).
- Card tile shows:
  - 💳 "•••• {last4}  {brand}"
  - `validUntil` "Platí do" {MM/YY} · {holder}
  - Green border + `priority` "PRIORITNÍ" for the default card
  - ⭐ set as default (only for non-default Stripe cards): toast `priorityCardSet` "Prioritní karta nastavena" / `setFailed`
  - 🗑️ delete: dialog `removeCard` "Odebrat kartu?" "•••• 4242 Visa" → `removeBtn` "Odebrat", then toast `cardRemoved` / `cardRemoveFailed`
- **Android:**
  - Empty state 💳 `noSavedCards` "Žádné uložené karty" / `addCardForFaster` "Přidejte kartu pro rychlejší platby".
  - Button "+ " `addNewCard` "Přidat novou kartu" opens a sheet `addPaymentCard` "Přidat platební kartu":
    - Stripe `CardField` and `saveCard` "Uložit kartu".
    - Footer "🔒 `encryptedPayment` Šifrovaná platba · Stripe PCI DSS Level 1".
    - Toast `cardSaved` / `cardSaveFailed`.
- **iOS:** no add button. The empty state and the hint read `cardsSavedAtCheckout` "Kartu uložíte přímo při placení rezervace." (App Store 5.1.1 / PCI).
- Footer: `cardsSecuredByStripe` "Údaje karet jsou zabezpečeny přes Stripe.\nMotoGo24 nikdy neukládá číslo karty."
- Loading spinner; error `cardsLoadError` "Chyba při načítání karet".

### 2.13 Oprávnění aplikace: `/permissions`

- App bar `permissions` "Oprávnění aplikace".
- Intro `permsGrantedFirstRun` "Oprávnění udělená při prvním spuštění." + `permsChangeHint` "Klikněte na oprávnění pro změnu v nastavení telefonu."
- During an active or paid-upcoming booking (`hasActiveReservationProvider`): 🔒 `permsRequiredActive` "Máte aktivní rezervaci. Pro správné fungování aplikace (přístupové kódy, navigace, oznámení) jsou všechna oprávnění kromě galerie/fotek vyžadována."
- Rows (icon, title, description, chip `allowedLabel` "Povoleno" green / `deniedLabel` "Zakázáno" red, plus `requiredLabel` "Vyžadováno" while locked):
  - 📍 `permLocationTitle` "Poloha (GPS)" · "Navigace, sdílení pozice při poruše"
  - 📷 `permCameraTitle` "Fotoaparát" · "Skenování dokladů, dokumentace škod"
  - 🔔 `permNotifTitle` "Oznámení" · "SOS aktualizace, zprávy, stav rezervací"
  - 🖼️ `permPhotosTitle` "Galerie / Fotky" · "Nahrávání fotek faktur a dokladů" (**iOS only**)
  - Tap opens the OS settings. Statuses reload on resume.
- `biometric` "Biometrické přihlášení" (only if the device supports it): toggle 🔐 `fingerprintFaceId` "Otisk prstu / Face ID".
  - On: authenticate, then `enableBiometric`. Toast `biometricsTitle` "Biometrika" + `activated` "Aktivována" (or `sessionExpired`).
  - Off: `deactivated` "Deaktivována".
- Buttons: `openPhoneSettings` "Otevřít nastavení telefonu" (green pill) and `allowAllAgain` "Povolit vše znovu" (toast `permissionLabel` / `permsRerequested` "Oprávnění znovu vyžádána"; it also reports to `profiles.app_permissions`).

### 2.14 Consent sheets: Notifikace / Soukromí a souhlasy (`consent_sheet.dart`)

- **`notif`** (title `notificationsSection` "Notifikace"):
  - `consentPush` "Push notifikace"
  - `consentEmail` "Email komunikace"
  - `consentSms` "SMS komunikace"
  - `consentWhatsapp` "WhatsApp komunikace" (shown although `whatsapp_integration` is off)
  - `consentMarketing` "Marketingový souhlas" (opt-in, DB default false)
- **`priv`** (title `privacySection` "Soukromí a souhlasy"):
  - `consentVop` "VOP — všeobecné obchodní podmínky"
  - `consentGdpr` "GDPR — zpracování osobních údajů"
  - `consentDataProcessing` "Zpracování dat pro provoz služby"
  - `consentContract` "Četl/a jsem návrh smlouvy na motogo24.cz a souhlasím"
  - `consentPhoto` "Fotografování dokladů a motorky"
- Square checkboxes; NULL counts as on. Button 💾 `save` "Uložit" → toast `saved` / `settingsSaved` "Nastavení bylo uloženo".
- **Locked during an active booking:**
  - Banner 🔒 `consentsLockedHint` "Máte aktivní rezervaci — souhlasy jsou po dobu pronájmu povinné. Odebrat je můžete po jejím ukončení."
  - All consents are forced on (and silently written to the DB).
  - A tap shows the toast `consentsLockedActive` "Během aktivní rezervace nelze souhlasy odebrat." Its title is always `notifications`, even in the privacy sheet (see §4).
- These are communication **consents**, separate from the OS notification **permission** in §2.13.

### 2.15 Změna hesla · Jazyk · Měna (`settings_sheets.dart`)

**Změna hesla**
- `newPasswordHint` "Nové heslo (min. 8 znaků)", `confirmPasswordLabel` "Potvrďte heslo".
- Validation `min8chars` "Min. 8 znaků" / `passwordsDoNotMatch` "Hesla se neshodují".
- Button `changePasswordBtn` "Změnit heslo" → `success` "Hotovo" / `passwordChanged` "Heslo změněno". No current password is asked.

**Jazyk aplikace**
- Čeština 🇨🇿 · English 🇬🇧 · Deutsch 🇩🇪 · Español 🇪🇸 · Français 🇫🇷 · Nederlands 🇳🇱 · Polski 🇵🇱 · Українська 🇺🇦, with ✓ on the current one.
- Saves `mg_language` and syncs `profiles.language`. Toast `languageChanged` "Jazyk změněn", then `context.go('/')`.

**Měna**
- Note `currencyNote` "Ceny se zobrazují v přepočtu dle kurzu ČNB. Platby kartou probíhají vždy v CZK."
- Options: 🇨🇿 CZK — Kč · 🇪🇺 EUR — € · 🇵🇱 PLN — zł. Subline "1 EUR ≈ {rate} Kč (ČNB)" (other languages show "CZK (CNB)").
- Toast `currencyChanged` "Měna změněna", then `context.go('/')`.

**Dead code:** `showPermissionsSheet` / `_PermissionsSheet` in the same file. It is superseded by `/permissions` and has no caller. It carries `permsRevokeHint` "Pro odvolání otevřete nastavení telefonu.".

### 2.16 Pomoc & Podpora

- SOS row: only while a reservation is `sosAllowed` (`!endedBySos && (active || (inRentalTerm && paid))`) → `/sos`. That opens the whole SOS flow (outside this inventory).
- Nápověda & FAQ: external web FAQ in the app language.
- **Missing today:** AI asistent and a contact (phone, e-mail). The scanner fallback is the only place with phone and e-mail buttons. The web v2 Kontakt page shows "ZAVOLEJTE NÁM" +420 774 256 271 · "NAPIŠTE NÁM" info@motogo24.cz · telephone hours "PO – PÁ 8:00 – 17:00".

### 2.17 Ostatní

**Smazat účet**
- Dialog `deleteAccountTitle` "Smazat účet?" / `deleteAccountDesc` "Tato akce je nevratná. Všechna vaše data, rezervace a dokumenty budou trvale smazány." → `cancel` "Zrušit" / red `deleteAccountBtn` "Smazat účet".
- Calls RPC `delete_customer_account`.
- `{error:'active_bookings'}` → toast `deleteAccountHasBookings` "Účet nelze smazat — máte aktivní nebo nadcházející rezervaci. Nejdřív ji prosím stornujte nebo dokončete."
- Other errors → `deleteAccountFailed` "Účet se nepodařilo smazat. Zkuste to prosím znovu."
- Success → sign out, toast `accountDeleted` "Účet smazán" / "Nashledanou!" → `/login`.

### 2.18 Version and updates

- The footer shows "MotoGo24 v{x.y.z}" (`PackageInfo`).
- The update gates live outside Profil, in `main.dart` (first frame + resume):
  - `UpdateChecker`: a blocking dialog when the app is below `app_settings.min_app_version`. Texts `updateRequired` "Vyžadována aktualizace" / `updateRequiredDesc` "K dispozici je nová verze aplikace (v{version}). Pro pokračování je nutné aplikaci aktualizovat." / `updateNow` "AKTUALIZOVAT".
  - `InAppUpdateService`: a Play flexible or immediate update, or on iOS an iTunes-lookup dialog.
- Profil has no "check for update" entry.

### 2.19 E-shop (flag `eshop_visible` OFF; the code is live and reachable when the flag is on)

**`/shop`**
- `shopTitle` "MotoGo Shop", `shopSubtitle` "Oblečení, výbava a dárkové poukazy". Cart icon with count → `/cart`.
- Voucher banner `giftVoucher` · `voucherDesc` "Libovolná částka · platnost 3 roky" · `voucherType` "Elektronický nebo tištěný" · `buyVoucher` "Koupit poukaz" → `/voucher`.
- Product grid: image, name, price, `soldOut` "Vyprodáno" → `/shop/:id`.
- Empty `shopEmpty` "Zatím žádné produkty"; error `loadingError` + `retry`.

**`/shop/:id`**
- Gallery, name, price, description.
- `sdColor` "Barva", `material` "Materiál".
- Sizes `sizeLabel` "Velikost" (`selectSizeFirst` "Nejdříve vyberte velikost"), `quantityLabel` "Množství".
- `addToCart` "Přidat do košíku" → toast `added`; or `soldOut`.

**`/cart`**
- `cartTitle` "Košík"; items with quantity ±, remove; `emptyBtn` "Vyprázdnit" (`emptied`).
- `orderSummary` "Souhrn objednávky" with `shippingPost` "Doprava (pošta)" / `shippingPickup` "Doprava (osobní odběr)" / `free` "Zdarma", `discountLabel` "Sleva" and `totalToPay` "Celkem k úhradě".
- `shopPriceNote` "Ceny jsou konečné – nejsme plátci DPH · Doručení poštou / osobní odběr na provozovně".
- `toCheckout` "K pokladně →".
- Empty `cartEmpty` "Košík je prázdný" / `addProductsFromShop` / `backToShop`.

**`/checkout`**
- `deliveryDetails` "Doručovací údaje": `shippingByPost` "Doručení poštou" `shippingPostInfo` "99 Kč · 2–4 dny" | `personalPickup` "Osobní odběr" `personalPickupInfo` "Zdarma · Mezná 9". Name and address fields.
- `discountCode` "Slevový kód" (`enterCodeHint` "Zadejte kód...", `apply` "Použít") with the rules `promoAlreadyUsed`, `shopCodeNotForVoucher`, `shopCodeInvalid`, `promoNoCombinePercent`, `discountApplied`, `shopVoucherNotAllowed`.
- Stock checks `shopOutOfStock` / `shopProductUnavailable`.
- Card `payment` / `paymentCard` / `selected` / `securePayment` "Bezpečná platba přes Stripe".
- Buttons `payBtn` "Zaplatit" or `confirmOrderFree` "Potvrdit objednávku (zdarma) →".
- Result: `verifyingPayment` "Ověřuji platbu...", `waitingConfirmation`, `paid` "Zaplaceno", `orderConfirmed` "Objednávka potvrzena", `paymentProcessed`, `totalPrice`, `confirmOnEmail`, `successEmailSent`, `close`.

**`/voucher`**
- `giftVoucher` "Dárkový poukaz"; `voucherValue` "Hodnota poukazu" 500 / 1 000 / 2 000 / `other` "Jiná" (`amountMin` "Částka (min. 100 Kč)").
- `voucherTypeLabel` "Typ poukazu": 📧 `electronicVoucher` "Elektronický" (Email · zdarma) | 📦 `printedVoucher` "Tištěný" (+ shipping).
- `buyVoucherBtn` "Koupit poukaz" → `addedToCart`.
- `howItWorks` "Jak to funguje": `voucherInfo1` "Otevřená hodnota – částku volíte vy", `voucherInfo2` "Platnost 3 roky od zakoupení", `voucherInfo3` "Dorazí emailem s unikátním kódem", `voucherInfo5` "Skvělý dárek pro milovníky motorek".

**Global:** the cart FAB `cartFab` "Košík ({count}) · {total} Kč" (dismissible). A push of type `shop_order` → `/shop`.

### 2.20 AI asistent (`/ai-agent`; reached from Home and SOS, not from Profil)

- Title `aiServiceAgent` "AI Servisní agent".
- Greeting `aiGreeting` "👋 Dobrý den! Jsem MotoGo AI asistent. Jak vám mohu pomoci? Mohu poradit s kontrolkami, poruchami, manuály nebo technickými dotazy." (vykání).
- Input `aiDescribeProblemHint` "Popište problém nebo dotaz...". Photos: `aiTakePhoto` "Vyfotit budíky" / `aiPickGallery` "Vybrat z galerie", at most 3 (`aiPhotoLimit`).
- While waiting: `aiThinking` "⏳ Přemýšlím...". Errors `aiProcessError`, `aiCommError`, `aiPhotoError`.
- When the agent says so and `sosAllowed`: `aiSuggestSos` + card `reportSosIncident` "Nahlásit SOS incident" / `clickToReportProblem` → `/sos`.
- The edge function `ai-moto-agent` receives the history, the language, the booking and the photos. The history is lost when the screen is popped.

---

## 3. Stored data with no Profil UI (candidates; adding them is optional, nothing is lost today)

| Data | Column | Used today | Proposal |
|---|---|---|---|
| Gear sizes (rider/passenger) + "own gear" | `profiles.gear_sizes` | Written at every `/payment`; pre-fills the booking and detail | Read-only summary row "Moje velikosti výbavy" in the Osobní údaje card (supports owner point 12). Editing it is new: owner decision |
| Company billing | `company_name`, `company_address`, `ico`, `dic` | Invoice HTML (`InvoiceHtmlBuilder`), web booking step 3 | Show "Firemní údaje" in the Osobní údaje card when set. Editing: owner decision |
| Verification dates | `id_verified_at/_until`, `license_verified_at/_until`, `passport_verified_*`, `docs_verification_status` | Docs gate | Doklady tile subline "Ověřeno · ŘP platí do {date}" |
| Language | `profiles.language` | Synced from the app | Value shown on the "Jazyk aplikace" row |
| Leaderboard opt-in + server nickname | `loyalty_leaderboard_opt_in`, `loyalty_nickname` | `/loyalty` (flag) | No change |
| Emergency contact, preferred branch, avatar, riding experience, preferred channel | `emergency_contact/_phone`, `preferred_branch`, `avatar_url`, `riding_experience`, `preferred_channel` | Nothing in the app | Out of scope; an avatar would need upload UI and storage (new backend) |
| OS permissions snapshot | `profiles.app_permissions` | Velín only | No change |

---

## 4. Defects and inconsistencies found (fix during the port, both trees)

| # | Defect | Where | Fix |
|---|---|---|---|
| P1 | Stale rule "Rezervace delší než 7 dní = 4 body…" (8 languages) | `loyalty_rank_card.dart:209`, `loyalty_ranks_screen.dart:592` | rank.md D1: drop it or rewrite it as "7 a více dní = 2 body = celý rank najednou" |
| P2 | Ladder "od {n} bodů" is off by one | `loyalty_ranks_screen.dart:434` | rank.md D2: show 2L − 2 |
| P3 | The locked-consent toast title is always "Notifikace", also in Soukromí a souhlasy | `consent_sheet.dart` | Use the section title |
| P4 | Scanner badge "📱 Data uložena v telefonu" is inaccurate: photos go to Storage and OCR runs on the server | `document_scanner_screen.dart` | Owner/legal: rewrite (e.g. "Šifrovaný přenos") in 8 languages, or drop it |
| P5 | "Doklady ověřeny — zákazník může dostat kódy k vyzvednutí" speaks in the third person (operator wording) | `docsVerifiedDesc` | Customer wording, e.g. "Doklady ověřeny — kódy k vyzvednutí dostaneš" (8 languages) |
| P6 | Rank card not tappable; `/loyalty` is reachable only via the logo ring | `loyalty_rank_card.dart` | Make the rank strip tap → `/loyalty` |
| P7 | "Reset" and "OK" hard-coded in the nickname dialog | `nickname_provider.dart:101,112` | i18n |
| P8 | Brand spelling "Moto Go" in `messages` "Zprávy z Moto Go" / `messageFromMotoGo` (cs, uk "від Moto Go") vs "MotoGo" in other languages | i18n | Optional: "MotoGo24" |
| P9 | WhatsApp consent shown though `whatsapp_integration` is off | `consent_sheet.dart` | Keep it (the column and Velín exist); optionally hide it behind the flag (owner decision) |
| P10 | Dead `showPermissionsSheet`/`_PermissionsSheet`; unused keys `documentSamplesSection`, `handoverProtocolSubtitle` | `settings_sheets.dart`, i18n | Delete during the port |
| P11 | v1 spec wanted to delete `branches_sheet` etc. as duplicates, but they hold unique data (phone, code, capacity, open state) | §2.6 | Merge into the branch detail first |
| P12 | Logout has no confirmation; delete account has one | `profile_screen.dart` | Optional confirm sheet (the owner said no flow changes, so leave it unless asked) |
| P13 | Language and currency changes jump to Home (`context.go('/')`) | `settings_sheets.dart` | v2 nav keeps PROFIL; optionally rebuild in place and stay in Profil |
| P14 | Emoji icons everywhere in chrome (rows, docs, permissions, flags) | all | v2 spec §2.9: `LpIcon` line icons; emoji only in toasts and chat. Flags in the language sheet can stay as content or become a text code chip (owner decision) |
| P15 | Header full-name pill and nickname chip are rendered side by side and look like a duplicate | `profile_screen.dart` | v2 header: name as the title, nickname as a chip under it |
| P16 | No pull-to-refresh in Profil | `profile_screen.dart` | Add it (it invalidates profile, loyalty, docs and cards) |

---

## 5. Label fit in 8 languages (measured)

Method: Montserrat Bold TTF (Cyrillic included) via PIL, +4 % to approximate weight 800, word-wrapped. Script: `S/tools/measure.py`.

**Tile grid:**
- **3 columns** (text box 88 px, 12/800, ≤ 2 lines) **fails** for:
  - uk `messagesTitle` "Повідомлення" (one word wider than 88 px)
  - de `paymentMethodsTitle` "Zahlungsmethoden" and nl "Betaalmethoden"
  - nl `loyaltyRanksTitle` "Loyaliteitsrangen" and pl "Rangi lojalnościowe"
  - uk `eshopMenu` "Інтернет-магазин"
  - nl `contracts` "Documenten en contracten" (3 lines)
- **2 columns** (146 px, 13/800, ≤ 2 lines): **all labels pass in all 8 languages**. Two lines are needed only for `contracts` (every language).
- → Use **2 columns, label up to 2 lines, no ellipsis, tile min-height 104**.

**List rows** (220 px text, 14/700, one line): everything fits except fr `privacy` "Confidentialité et consentements" (257 px). So rows allow 2 lines with min-height 56. The longest rows otherwise:

| Row | Worst language | Text | Width |
|---|---|---|---|
| `deleteAccountBtn` | uk | "Видалити обліковий запис" | 214 px |
| `messages` | uk | "Повідомлення від Moto Go" | 211 px |
| `contracts` | nl | "Documenten en contracten" | 211 px |

**Section titles:** the longest is uk "Допомога та підтримка", 186 px at 14 px. All fit.

Nav label PROFIL / PROFILE / PERFIL / PROFIEL / ПРОФІЛЬ: already solved in `research/nav.md` and `DESIGN_V2.md` §4.1 (title case, fit ladder).

---

## 6. Web v2 references to mirror (owner: "dle UX a UI webu udělat i app")

| App area | Web v2 source | Patterns to take over |
|---|---|---|
| Pobočky list | `pages/pobocky-v2.php`, `pobocky-v2-ui.php`, `-blocks.php`, `-texts.php`, `css/landing-branch*.css` | See list A below |
| Pobočka detail | `pages/pobocka-detail-v2.php` | See list B below |
| Kontakt (new optional row) | `pages/kontakt.php`, `landing-info-contact.php` | Call / Write cards, telephone hours, billing data (IČO 21874263, "Nejsem plátce DPH", datová schránka iuw3vnb), map, social links |
| Smazání účtu | `pages/smazani-uctu.php` | The in-app path must stay "Profil → Smazat účet". Optionally link this page in the delete dialog ("Co se smaže") |
| Dokumenty (VOP, GDPR, smlouva) | `/dokumenty/*` (`dokumenty-detail.php`) | The same documents in-app via `loadLegalDoc` (already 1:1) |
| FAQ | `/jak-pujcit/faq` | Stays a web link (external) |
| Poukazy | `pages/poukazy.php` | Voucher flow look (e-shop is behind the flag on both web and app) |

**A. Pobočky list (web v2 order)**
- Action panel: H1 + intro + chips "2 pobočky: Vysočina a Brno · Bez kauce · Výbava v ceně".
- Two big branch cards:
  - Photo, badge and highlight ("Osobní předání motorky — vše ti vysvětlíme" / "100 % nonstop, bez obsluhy").
  - Stats (90 min z Prahy · 6XL · PO–NE / 24/7 · 30 min z centra Brna · 35 min z letiště).
  - Facts with icons, address, hours.
  - "Detail pobočky" + "Rezervovat zde".
- Compare table "Mezná vs Velké Němčice": 12 rows (předání, provozní doba, výbava, velikosti, nepromoky, přistavení, vrácení, doklady, zázemí, parkování, dojezd, počet motorek).
- Fleet, CTA, sticky bar.

**B. Pobočka detail (web v2 order)**
- Hero: photo, badge, address, driving distance, 2 CTAs ("Rezervovat na této pobočce" / "Motorky této pobočky"), facts, "Video" badge.
- Video (VN at the top), "O pobočce" + "Provozní doba".
- Interactive step guide "Krok {n} z {total}" (Předchozí / Další krok / Rezervovat).
- "Výbava" icons + sizes + "V motorce najdeš" (vesta, lékárnička, záznam o nehodě, kotoučový zámek, klíček k držáku).
- Gallery, map "Jak k nám" + "Navigovat", "Motorky na této pobočce" carousel, CTA, "Naše druhá pobočka".

---

## 7. Proposed information architecture: PROFIL v2

Design language: v2 tokens (`gDark` header, `page #DFF0EC`, cards r16, line icons, tykání, Montserrat), the rank as an accent layer (`rankTheme`), **one primary CTA per screen**, and motion tokens with `MgMotion.reduced()`.

### 7.1 Screen skeleton (390 px, scroll; nav PROFIL active, AI FAB bottom-right at 110)

```
┌ HEADER "Můj klub" (gDark + rank aura + minted edge, r24) ─────────────┐
│ (avatar 64 in rank ring + progress arc + L3 badge)   [⚙︎ Nastavení ↓]  │
│ [full_name] 20/800                                                   │
│ PILOT: [přezdívka] ✎   (rank-tinted chip → nickname dialog)          │
│ ── rank strip (tap → /loyalty) ─────────────────────────────────────  │
│ Motorkář · sleva 3 % · Level 3 / 20                    ⓘ O programu  │
│ ▓▓▓▓▓▓░░░  Ještě 1 b. do: Stálý jezdec (4 %)                         │
│ 5 b. · rezervace z appky i webu  ·  ★ Platí jen pro rezervace v app  │
└──────────────────────────────────────────────────────────────────────┘
 ATTENTION STRIP (only if something is actionable; max 2 chips, priority order)
   SOS — Pomoc na cestě (active rental, red) · Doklady: Chybí rub ŘP (amber → /docs)
   · [n] nepřečtené zprávy (→ /messages) · ŘP propadá před další jízdou (amber → Osobní údaje)
   → if documents are missing, the ONE primary CTA = "NAHRÁT DOKLADY" (rank material)
 TILES 2 × 3 (white cards r16, icon 24 line, label 13/800 ≤ 2 lines, status subline 11.5/700)
   [Zprávy  ·(n)]            [Moje doklady · Ověřeno ✓ | Chybí: …]
   [Faktury · [počet]]        [Dokumenty a smlouvy · [počet]]
   [Platební metody · •••• 4242 | Žádná karta]   [Pobočky · Mezná · V. Němčice]
   (+ full-width "E-shop" card only when eshop_visible)
 OSOBNÍ ÚDAJE card (summary, collapsed)                       [Upravit]
   Jméno · E-mail (zámek) · Telefon · Adresa (1 řádek) · Datum narození
   Č. OP/pasu · ŘP č. · platí do · skupiny [A][B]  (missing → amber "Doplnit")
   [opt.] Moje velikosti výbavy: helma M · bunda L · … | Vlastní výbava
   [opt.] Firemní údaje (if set)
 NASTAVENÍ (grouped list, value on the right)
   Oprávnění aplikace ……… "Vše povoleno" | "Poloha zakázána" (amber)
   Notifikace ……………… "Push · E-mail · SMS"
   Soukromí a souhlasy …… "Vše uděleno" | "🔒 během pronájmu"
   Změna hesla
   Jazyk aplikace ………… "Čeština"
   Měna ……………………… "CZK"
   [new, owner §13] Omezit animace (switch)
 POMOC A PODPORA
   SOS — Pomoc na cestě (only sosAllowed; red row)
   AI asistent (new row; same panel as the FAB)
   Nápověda & FAQ ↗ (web)
   [opt., new] Kontakt: Zavolat · Napsat (web v2 Kontakt)
 OSTATNÍ
   Odhlásit se (red text) · Smazat účet (red text)
 FOOTER  MotoGo24 v{x.y.z}  [opt.: "Nová verze · Aktualizovat" when the store reports a newer one]
```

### 7.2 Grouping logic (why it is clearer)

- **Identity and rank** are the header, so the logo ring, nickname chip and rank card are no longer three separate places. The rank is the first thing the customer sees, which is the "Sultán" feeling. Tapping the strip opens `/loyalty`, which fixes P6.
- **Status before navigation.** The attention strip appears only when something is actionable, so there is no noise.
- **The six most-used destinations become tiles with live status.** Today they are plain rows. A customer sees "Ověřeno", "•••• 4242" or "(2)" without opening anything. The tiles replace the six account rows (no duplicate list rows), so clutter goes down.
- **Personal data shows a summary instead of a hidden form.** Today it is collapsed and empty-looking; v2 shows the summary and moves the same full form behind "Upravit" (sheet or expanded card).
- **Settings rows show their current value** (language, currency, permission state).
- **Help is one group:** SOS (conditional), AI, FAQ and the optional contact.
- **The destructive actions stay last**, unchanged.

### 7.3 Visible vs behind a tap

| Item | Visible on PROFIL | Behind 1 tap | Behind 2+ taps |
|---|---|---|---|
| Rank name, %, level, points, next rank, app-only note | ✓ header | `/loyalty` full ladder, rules, leaderboard (flag) | — |
| Rules "O programu" | ⓘ | sheet | — |
| Nickname | ✓ chip | dialog | — |
| Unread count | ✓ tile badge + attention chip | `/messages` | thread |
| Documents status + missing list | ✓ tile subline (+ chip) | `/docs` | scanner |
| Default card | ✓ tile subline | Platební metody | add-card sheet (Android) |
| Invoice and contract counts | ✓ tile subline (optional) | lists | viewers |
| Branches | ✓ tile | `/pobocky` | detail, sheet facts |
| Personal data | ✓ summary | edit form | date pickers |
| Settings values | ✓ row values | sheets / `/permissions` | OS settings |
| SOS | ✓ row (+ chip) when allowed | `/sos` | flow |
| AI | ✓ FAB + row | chat | — |
| FAQ | ✓ row | web | — |
| Logout / delete | ✓ rows | dialog | — |
| Version | ✓ footer | — | — |
| E-shop (flag) | ✓ card | `/shop` | product / cart / checkout / voucher |

### 7.4 Sub-screen guidance (layout only; all content from §2 stays 1:1)

- **Zprávy:**
  - Dark compact header with a segmented control "Oznámení [n] · Konverzace" (web `.km-sw` style sliding thumb).
  - "Označit vše jako přečtené" as a text button.
  - Notification cards with line type-icons; the unread left bar stays.
  - Konverzace: "Nová konverzace" becomes the screen's one primary CTA. Ride-feedback and SOS threads keep their markers.
  - Thread: chat bubbles in v2 colours, with the closed-thread banner instead of an input.
- **Moje doklady:**
  - Hero with two document cards (OP/Pas, ŘP) showing state and the gate "Chybí:" line.
  - The one primary CTA is the camera scan (or "NASKENOVAT ŘIDIČSKÝ PRŮKAZ").
  - "Nahrát z galerie" is secondary. The tips sit behind ⓘ. The `docsRequiredInfo` / `docsNotVerifiedDesc` texts stay unchanged.
  - The scanner flow is unchanged (restyle only).
- **Faktury:** year sections; tile = type icon, number or type, date, amount right-aligned (credit note red −). Empty state as today.
- **Dokumenty a smlouvy:**
  - Two groups. "Obchodní podmínky a vzory": VOP, GDPR, Vzor protokolu o poškození. "Tvoje dokumenty": real documents, newest first, with the date.
  - Optional: group by booking `#ID · motorka`. That needs a join; owner decision.
- **Platební metody:**
  - A card "wallet" look: brand, •••• last4, Platí do, PRIORITNÍ.
  - ⭐ and 🗑 become line icons with text tooltips.
  - Android keeps the add-card sheet; iOS keeps the "Kartu uložíte přímo při placení rezervace." hint.
- **Pobočky:**
  - Mirror web v2 (§6): cards with photo, highlight, stats and facts, plus the compare table.
  - Detail with the step guide, gear, "V motorce najdeš", gallery, map, bikes and the other branch.
  - **Plus a "Kontakt a údaje" block** with phone + Zavolat, kód pobočky, typ lokality, provoz, kapacita and Otevřeno/Uzavřeno, taken from the branches sheet. Then the sheet can go (P11).
- **Věrnostní ranky:**
  - Keep the screen. Recolour the ranks per the new no-pink/purple palette.
  - Fix P1/P2. The leaderboard stays behind its flag.
  - **The level-up celebration is untouched** (storyboard only).
- **Oprávnění, souhlasy, heslo, jazyk, měna:**
  - Same content, v2 sheets (r22, `shSheet`) and switches instead of squares.
  - The lock banners stay. Fix P3.

### 7.5 Motion and rank (Profil-specific, all one-shot, reduced-motion safe)

- **Tab enter:** header fade-through (`tab` 210 ms). The rank arc fills from 0 to the current progress once per session (`connector` 700 ms); reduced = static.
- **Tiles:** `reveal` stagger 70 ms (capped at index 5); press .97 + `selectionClick`. The badge `pop`s when the count changes.
- **Personal summary → edit:** `enter` 450 ms. Save shows ✓ `pop` + toast.
- **Attention chip:** slides in with `sticky` 300 ms; one `ping` on SOS only.
- **Rank:**
  - The header aura and the minted edge use the rank tier material.
  - The avatar ring and arc use `color_hex` (new masculine palette, no pink or purple).
  - The only CTA (docs missing) uses rank material + glow.
  - Tiles and lists stay neutral (meaning colours stay).
- **Loops:** none on Profil except the CTA glow when the docs CTA is present, at most 1.
- **Level-up:** Profil never blocks it; the global watcher plays it on the next tap (unchanged).

### 7.6 Completeness checklist: every current item → v2 location

| # | Today | v2 |
|---|---|---|
| 1 | Hamburger on Home → `/profile` | PROFIL tab (avatar + rank ring, unread badge); the hamburger is removed |
| 2 | Logo ring → `/loyalty` | Avatar ring + rank strip → `/loyalty` (Home logo ring stays too) |
| 3 | Full-name pill | Header title |
| 4 | PILOT nickname chip + dialog | Header chip → same dialog |
| 5 | `LoyaltyRankCard` (name, %, level, points, next/max, app-only, O programu sheet) | Header rank strip + ⓘ sheet (same texts; P1 fixed) |
| 6 | Pobočky row | Tile "Pobočky" → `/pobocky` (web v2 layout + sheet data folded in) |
| 7 | E-shop row (flag) | Full-width card (flag) |
| 8 | Osobní údaje (collapsed form, 12 fields + ŘP chips + save) | Summary card + "Upravit" (same fields, validation, RPC) |
| 9 | Zprávy z Moto Go + badge | Tile "Zprávy" + badge + attention chip |
| 10 | Moje doklady | Tile with status + attention chip / CTA |
| 11 | Faktury a vyúčtování | Tile "Faktury" |
| 12 | Dokumenty a smlouvy | Tile "Dokumenty a smlouvy" |
| 13 | Platební metody | Tile with default card |
| 14 | Oprávnění aplikace (+ biometrics inside) | Nastavení row with status value |
| 15 | Notifikace (5 consents) | Nastavení row with summary value |
| 16 | Soukromí a souhlasy (5 consents, lock) | Nastavení row with value / lock |
| 17 | Změna hesla | Nastavení row |
| 18 | Jazyk aplikace (8) | Nastavení row with value |
| 19 | Měna (CZK/EUR/PLN, ČNB note) | Nastavení row with value |
| 20 | SOS row (conditional) | Pomoc row (conditional) + attention chip |
| 21 | Nápověda & FAQ (web) | Pomoc row |
| 22 | Odhlásit se | Ostatní row |
| 23 | Smazat účet (dialog, RPC, errors) | Ostatní row, **same name** (Play / App Store / web page) |
| 24 | Version footer | Footer |
| 25 | Docs FAB "NAHRÁT DOKLADY" (global) | Stays global (status strip item in v2 spec) + Profil attention CTA |
| 26 | Cart FAB (flag) | Stays global (status strip "cart") |
| 27 | AI (Home FAB, SOS) | Global FAB + Pomoc row (new) |
| 28 | Push targets `/messages?n=`, `/shop` | Unchanged routes, PROFIL tab highlighted |
| 29 | Leaderboard + opt-in + nickname hint (flag) | `/loyalty` unchanged |
| 30 | Level-up celebration | Unchanged (owner) |

### 7.7 States to draw on the PROFIL board

- **Default (sample customer):**
  - Rank 3 Motorkář, 5 b., documents verified, card •••• [last4].
  - [n] unread, an upcoming VN booking, so the consents and permissions show "Vyžadováno" / 🔒 values.
- **Variants:**
  - Docs missing: amber chip + CTA "NAHRÁT DOKLADY", Doklady tile "Chybí: rub ŘP".
  - Active rental: SOS chip + SOS row.
  - New customer: Startér, no card ("Žádná karta" / iOS hint), personal summary with amber "Doplnit".
  - Loading: skeleton header + tiles.
  - Error: "Chyba načítání profilu" + Zkusit znovu.
  - Language switch: all 8 languages to prove the tile and row fit.
- **Sub-boards:**
  - Zprávy (both tabs + thread).
  - Moje doklady (verified / missing).
  - Platební metody (Android vs iOS).
  - Pobočky (list + detail with the "Kontakt a údaje" block).
  - Nastavení sheets (consents locked).
  - Smazat účet dialog (+ active-booking error).
  - Edit Osobní údaje.

---

## 8. Owner decisions / open questions

1. **New rows.** Each is purely additive and none removes anything; each needs i18n in 8 languages:
   - "AI asistent" in Pomoc
   - "Kontakt" (call / e-mail / hours, web v2 Kontakt)
   - "Omezit animace" (spec §13)
   - "Moje velikosti výbavy" (read-only, or editable)
   - "Firemní údaje"
   - "Nová verze · Aktualizovat"
2. **Fold the branches sheet into the branch detail** ("Kontakt a údaje" block), then delete the sheet (P11).
3. **Copy fixes** P4 ("Data uložena v telefonu") and P5 (third-person docs line). The legal and accuracy implications are the owner's call.
4. **WhatsApp consent visibility** while the integration is off (P9).
5. **Language picker flags** (emoji) vs text codes (P14).
6. **Group "Tvoje dokumenty" by booking** (needs a join; optional).
7. **Stay in Profil after a language or currency change** instead of jumping to Home (P13): a behaviour change, so it needs the owner's OK.
