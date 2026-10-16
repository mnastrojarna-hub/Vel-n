# MotoGo24 app · design iteration 2.1 (DESIGN_V21)

Spec for the v2.1 boards and the later Flutter port (both trees). It **extends** `DESIGN_V2.md`, which extends `appdesign_spec.md` (v1). Everything there stays valid unless a section below says **replaces** or **withdrawn**.

- Mockup "today" = **neděle 11. 10. 2026, 9:41**, Czech UI, tykání.
- Sample customer = v2: rank **3 Motorkář**, 5 points (1 to Stálý jezdec), licence A. R1 = Husqvarna 701 SM, Velké Němčice, pá 16. 10. 12:00 → ne 18. 10. 23:59, **12 027 Kč**. R2 (new booking) = BMW R 1200 GS Adventure, Mezná, pá 23.–ne 25. 10., **10 189 Kč**.
- **New default Home state = no upcoming booking** (funnel, §4). R1 appears only in the ticket states S1–S9.

Inputs read for this spec (all facts below are traced to them):
- `DESIGN_V2.md`, `appdesign_spec.md` §0–2, §4, §6, `V21_FEEDBACK.md`, `.claude/handoff/PLAN.md`
- All six boards in `appdesign/project/` (CSS, markup and script measured with `scratchpad/v21spec/*.py`)
- `research/profile_inventory.md`, `research/trasy_inventory.md`, `research/rank_colors.md`, `sql/20261015_loyalty_colors_no_purple.sql`
- App code (read-only): `features/loyalty/loyalty_levelup_overlay.dart`, `loyalty_provider.dart`, `main.dart:375–410`, `features/reservations/widgets/res_rating_card.dart`, `res_rating_widgets.dart`, `ride_feedback_sheet.dart`, `features/reservations/ride_feedback.dart`, `core/i18n/translations_ext_36_ride_feedback.dart`, `translations_ext_10_loyalty.dart`, `features/home/*`, `core/offline_guard.dart`
- Web v2 opened at 390 px on the local dev server: `/`, `/katalog` (+ the `.km` mode switch and `.kc` calculator, driven with BMW 23.–25. 10.), `/katalog/a0000001-…01`, `/rezervace?moto=…&start=2026-10-23&end=2026-10-25`, `/pobocky`, `/pobocky/velke-nemcice`, `/kontakt`. Source: `pages/katalog-calc.php`, `js/landing-calc-core.js`, `landing-calc-view.js`, `landing-calc.js`, `css/landing-calc.css`, `landing-calc-sum.css`, `landing-catalog-mode.css`, `landing.css`.
- Live DB (anon read, 2026-10-15): `branches`, `motorcycles` (brand, model, videos), `loyalty_levels`.

---

## 0. v2.1 at a glance

### 0.1 Owner feedback → where it is answered

| Owner (2026-10-15) | Answer |
|---|---|
| "V barvách ranků by neměla být růžová ani fialová" | §0.3: ranks 13–16 recoloured (racing orange, olive, coyote khaki, petrol), VIP 17 effects ivory + crimson, gem effects never violet. SQL as text for approval. |
| "v app by měla být i kalkulačka ceny, stejně jako web" | §3 Kalkulačka: the web `.km` switch "Najít motorku · Spočítat cenu" and the `.kc` calculator, ported 1:1 into **Motorky** and reachable from **Domů**. Detail keeps its own calculator. |
| "extra důležitá karta domů, pokud nemám žádnou rezervaci … funnel" | §4 Funnel hero "Tvoje příští jízda", the **default** Home board state. |
| Reviews: "Napiš nám recenzi" + "Napiš nám přímo, co máme zlepšit" | §5 Review card, wording 1:1 from the shipped code (`rfGoogleBtn`, `rfImproveBtn`), on the completed reservation and on Home after a ride. The current Reservation board gates by stars, which is removed. |
| "je tam ještě hodně práce s detaily" | §7 detail pass: one type scale, spacing scale, radius scale, icon sizes, palette and motion tokens, plus concrete fixes per board. The fixes come from measurements of the board CSS. |
| "pozor lvl up video neměň" | §6: the existing celebration is drawn as a faithful storyboard. DESIGN_V2 §3.3–3.7 is **withdrawn**. The boards' level-up demo becomes a replica of today's overlay (`shared/levelup-classic`). |
| "neviděl … profilu a komplet všech obrazovek v hlavní kartě tras" | §1 PROFIL (3 boards) and §2 TRASY (2 boards), with every current item mapped. |
| "dle UX a UI webu udělat i app" | §8: every app screen names its web v2 page or component and what is adapted for native. |
| "vše musí být funkční … nic nesmí chybět … ve všech jazycích" | Completeness tables §1.6, §2.6, §3.9. Label fit in 8 languages measured in §0.4. |
| Fuel fact (2026-10-12) | Unchanged from v2. Never promise a full tank. Returning needs no refuelling. At Mezná the reserve light "ať nesvítí"; at Velké Němčice it "nesmí svítit" and the bike goes back washed. Washing applies to VN only. Checked: all board copy already complies (`grep` 2026-10-15). |

Earlier points 1–14 (rank theming, AI FAB, PROFIL tab, nav without overlap, Sultan Home, full-screen catalogue, detail REZERVOVAT, express booking) stay answered by DESIGN_V2.

### 0.2 What v2.1 replaces in DESIGN_V2

| DESIGN_V2 | v2.1 |
|---|---|
| §2.2 tier table: VIP 17 "pearl / ruby `#881337`, rose glow `#F43F5E`"; Drahokamy label "white (12–16)" | VIP 17 = **ivory** fill `#FFFBF2 → #F3DEC0`, **crimson** label `#7F1D1D`, red-gold-red frame, **red** glow (not SOS red as a fill). Drahokamy label: navy `#0A1F33` for 10–11 and 16, **dark** `#1A1405` for 13–15, white only for 12. Gem shimmer is tinted by the rank colour; there is no fuchsia band. Source: `research/rank_colors.md` §4, regenerated `shared/rank-theme.*`. |
| §2.4 contrast rows 12–17 | `gen/contrast.md` (0 failures). Update DESIGN_V2 lines 99, 102 and 137–141 from it. |
| §3.3–§3.7: triggers T3/T6/T7/T9, the safe-moment list, the new sequence (tier title card, ring stepping, reason line, "Sleva … platí hned", gear line), theme hold, speaker toggle "Zvuk oslav", board demo `levelup.js` | **Withdrawn.** The celebration, its triggers and its persistence stay exactly as today (§6). The boards replay the real overlay (§6.7). Optional improvements are listed only as owner decisions (§6.8). |
| §3.6 landing extras that sit *outside* the overlay (Home concierge note "Gratulujeme, jsi {rank} · sleva {pct} % platí hned", Moje zážitky entry "Nový rank: …") | **Kept** as Home content. They do not touch the overlay. |
| §5 Home default `ticketState` S6 | Default = **S0 funnel** (§4). S10 = review card + funnel. In S0 and S10, "Kdy jedeš příště?" (§5.4) and "Motorky pro tebe" (§5.9) are hidden because the funnel holds both. In S1–S9 the "Kdy jedeš příště?" pill gains a calculator button (§3.1). |
| §5.3 S10 "Díky, [přezdívka]! Tvoje hodnocení si přečteme." + secondary "Ohodnotit na Google" | §5 review card (exact code strings). |
| §7 Motorky | Adds the web `.km` mode switch (§3.1). The per-card web "Spočítat cenu" button is not ported, because the Detail already has its calculator and the card keeps one action. |
| §9 Reservation Dokončeno: stars inside CO TEĎ, toast "Ohodnotíš nás i na Google?" for 4–5★ and "napíšeme ti, co zlepšit" for 1–3★, action "Google" | §5: the same card for every rating. The action row loses "Google" (→ "Jízdy", §7.5). |
| §10 RankStyly level-up mini app (redesigned sequence) | A storyboard reference card that opens the new board `Oslava.dc.html` (§6). |
| §11 row "Level-up overlay (67 s montage) → shared sequence (§3.5) …" | **Withdrawn**: the overlay is unchanged. |
| §14 owner decision #2 (VIP colour), #4 (music default), #5 (`loyalty_events`) | #2 answered by the recolour (§0.3). #4 and #5 are void unless the owner reopens them. |

### 0.3 Rank colours: no pink, no purple

| L | Rank | old `color_hex` | **new** | What it reads as | Text in colour on app pill `#1A2E22` | Dark text on colour |
|---|---|---|---|---|---|---|
| 13 | Šampion | `#6366F1` | **`#FF5A0C`** | racing orange | 4.61 | 5.70 |
| 14 | Veterán MotoGo | `#8B5CF6` | **`#8A9A3B`** | olive | 4.64 | 5.74 |
| 15 | Elitní jezdec | `#A855F7` | **`#B39E7E`** | coyote khaki | 5.56 | 6.88 |
| 16 | Ambasador | `#D946EF` | **`#19A2B4`** | petrol | 4.71 | 5.83 |

- **Ladder after the change:** 10 ice blue → 11 sky → 12 blue → 13 orange → 14 olive → 15 coyote → 16 petrol → 17 VIP red → 18 VIP gold → 19 VIP platinum → 20 Legenda.
- **Spacing between ranks:** every hue lies outside 235–345°. The minimum ΔE2000 to any other rank is 14.5.
- **SQL:** draft as text in `appdesign/sql/20261015_loyalty_colors_no_purple.sql`.
  - Four guarded `UPDATE loyalty_levels SET color_hex … WHERE level=N AND upper(color_hex)=<old>`; it is idempotent.
  - After approval: commit it to `supabase/migrations/`, add the changelog to STATE_6 and the note to STATE_2.
- **App changes, both trees, same commit as the SQL:**
  - Offline fallback colours: `loyalty_levels_provider.dart:58–61`.
  - The on-colour text picker must choose whichever of dark or white contrasts more, in `loyalty_ranks_screen.dart:576` and `loyalty_leaderboard_section.dart:342`. It fails today for 12 of 20 ranks.
  - The same fix in `loyalty_levelup_overlay.dart:718` changes only the text colour of "Pokračovat" and "+N", but that file is the celebration, so it needs the **owner's OK** (§6.8 L2).
- **Boards — step 0, before any other v2.1 edit:**
  - Run `python3 gen/reembed_rank.py --old bak-rankcolors --write project/*.dc.html`. All six boards still embed `#6366F1/#8B5CF6/#A855F7/#D946EF` and VIP `#F43F5E` (checked).
  - Then make the manual RankStyly text edits at lines 1631, 1632 and 1634 (`research/rank_colors.md`).

### 0.4 Label fit for new UI in 8 languages (measured, Montserrat Bold +4 % ≈ w800, `scratchpad/tools/measure.py` method)

| Control | Box | Result | Rule |
|---|---|---|---|
| TRASY segments Místa · Trasy · Moje (13/800) | 358 dp, 3 segments, 70 px text beside an 18 px icon | fr "Itinéraires" 71.9 and "Les miennes" 88.9, and uk "Маршрути" 78.1, **do not fit next to the icon** | Icon **above** the label (segment h 52), 94 px text box at 12.5/800 → all 8 languages fit (worst fr "Les miennes" 85.5). Never `FittedBox` or ellipsis. |
| Motorky switch "Najít motorku / Spočítat cenu" (13/800 title, 11/600 sub) | 172 dp tab, 124 px text | fr "Trouver une moto" 127 and uk "Знайти мотоцикл" 129 / "Розрахувати ціну" 128 wrap | Title max 2 lines, sub 1 line (fits in all 8: max uk 108). Both tabs equal height (54 → 64 dp when any title wraps). Web keys `f_mode_find`, `f_calc`, `f_mode_find_sub`, `f_mode_calc_sub` already exist in all 7 web languages. Reuse those texts. |
| Funnel date presets (13/800) | single row of auto-width chips needs 378–501 px | No language fits in one row with three chips | 2 equal chips (129 dp, label max 2 lines at 13/800 + date line 11.5/700) + a 52 dp calendar button "Jiný termín" (a11y label). Every language fits (de "Übernächstes / Wochenende"). |
| Review tiles (14/800, 244 px text) | — | All 8 languages need 2 lines (de 327 px) | Already as in the code: `minHeight 84`, both tiles the same size. |
| PROFIL tiles and rows | — | `profile_inventory.md` §5: a 3-column grid fails (uk, de, nl); **2 columns × 2 lines pass**; rows allow 2 lines (fr "Confidentialité et consentements") | Use the measured result. |
| Bottom nav | — | DESIGN_V2 §4.1 (fit ladder). The shipped app forces `TextScaler.noScaling` (`main.dart:380`), so today every locale renders at rung ② (11 px). | No change; the ladder stays for when scaling is re-enabled. |

New strings in this spec are given in Czech. The port adds all 8 languages in both trees, and translation proposals are marked "návrh".

---

## 1. PROFIL tab (boards `Profil.dc.html`, `ProfilSluzby.dc.html`, `Pobocky.dc.html`)

Source of truth for content: `research/profile_inventory.md` (cited as **PI §x**). Rule: every current item keeps a home, and nothing moves more than one tap deeper than today. Web reference: `pobocky-v2`, `pobocka-detail-v2`, `kontakt`, `smazani-uctu`, `dokumenty-detail` (§8).

### 1.1 IA

```
PROFIL (tab, /profile)  ── nav PROFIL active for /profile*, /messages*, /docs*, /invoices, /contracts, /pobocky*,
│                          /loyalty, /permissions, /shop*, /cart, /checkout, /voucher (DESIGN_V2 §4.1 mapping)
├─ P1  Profil "Můj klub"                       (root; header, attention, 6 tiles, Osobní údaje, Nastavení, Pomoc, Ostatní)
│   ├─ P2  Osobní údaje · úpravy               (focused sheet 92 %, form)
│   ├─ P3  Přezdívka                           (dialog)
│   ├─ P4  Věrnostní ranky /loyalty            (+ P5 O programu sheet; leaderboard behind its flag)
│   ├─ P6  Notifikace · Soukromí a souhlasy · Změna hesla · Jazyk aplikace · Měna   (sheets)
│   ├─ P7  Oprávnění aplikace /permissions
│   ├─ P8  Smazat účet (dialog) · P9 Odhlásit se (direct, toast)
│   └─ tiles → ProfilSluzby / Pobocky boards:
│       ├─ S1  Zprávy /messages  (Oznámení · Konverzace) → S2 vlákno /messages/:id, S3 Nová konverzace (sheet)
│       ├─ S4  Moje doklady /docs → S5 Skenování /docs/scan (+ "Co je na fotce?" sheet, delete dialog)
│       ├─ S6  Faktury /invoices → DocWebView
│       ├─ S7  Dokumenty a smlouvy /contracts → DocWebView / PdfPages
│       ├─ S8  Platební metody (Android: + "Přidat platební kartu" sheet; iOS: hint only)
│       ├─ S9  Pobočky /pobocky → S10 Pobočka /pobocky/:i (web v2 mirror + "Kontakt a údaje")
│       └─ S11 E-shop /shop … /voucher (only with eshop_visible; live: off)
└─ SOS /sos (Pomoc row, only while sosAllowed) · AI asistent (FAB panel) · Nápověda & FAQ (web)
```

### 1.2 P1 Profil "Můj klub" (root; artboard section 390 × ~2100; y values for the default state)

| y | Block | Content (all texts verbatim from PI unless marked **nové**) |
|---|---|---|
| 0–47 | Status bar | White glyphs on the dark header. |
| 47–331 | **Header "Můj klub"** (`.rk-hero`: rank aura, tier texture, minted 2 px bottom edge, r24; one-shot ambient once per session) | **Row 1 (59–135):** the **avatar 64** (person glyph on `#0E2A1C`) sits in the **rank frame** (ring + progress arc `rk.arcSt` + level badge "3", crown/laurel by tier); tap → `/loyalty`. On the right, a 44 px glass icon button "Nastavení" (gear) that scrolls to the Nastavení group. **Name** 22/800 white `[Jméno Příjmení]` (`full_name`, else `pilot` "Pilot"). **Nickname chip** "PILOT: [přezdívka] ✎" (rank-tinted `.rk-chip`, 11.5/800) → P3. **Rank strip** (glass card white@.06, border neon@.18, r16, tap → `/loyalty`, which fixes PI P6): kicker `loyaltyMyRank` "VĚRNOSTNÍ RANK"; "Motorkář" 17/800 `--rk-acc` + pill "3 %"; **tier bar** (`rk.tierBar`, 1 segment = 1 point); "Level 3 / 20 · 5 b. · rezervace z appky i webu"; "Ještě 1 b. do: Stálý jezdec (4 %)" (`loyaltyNextRank`; at 20: `loyaltyMaxRank`); "★ Platí jen pro rezervace vytvořené v aplikaci"; ⓘ "O programu" → P5. |
| 343–391 | **Attention strip** (conditional, max 2 chips + "+n", priority order) | ① red "SOS — Pomoc na cestě" (only `sosAllowed`) → `/sos` · ② amber "Doklady: Chybí rub ŘP" (gate `missing` text) → `/docs` · ③ "[n] nepřečtené zprávy" → `/messages` · ④ amber "ŘP propadá [datum]" (when `license_expiry` < end of the next booking) → P2. Hidden when nothing applies. |
| (399–455) | **Primary CTA** (only while documents are incomplete) | Rank CTA 56 "NAHRÁT DOKLADY" → `/docs`. This is the screen's only loop. Without it, PROFIL has **no** looping element. |
| 403–735 | **Tiles 2 × 3** (white r16, `shCard`, 171 × 104, gap 10; 24 line icon in a 40 tile; label 13/800 max 2 lines; status 11.5/700) | Zprávy · status "[n] nové" + red count badge `#D92D20` · Moje doklady · "Ověřeno ✓" (`#0D6E0D`) / amber "Chybí: rub ŘP" · Faktury · "[n] dokladů" · Dokumenty a smlouvy · "VOP · GDPR · [n] smluv" · Platební metody · "Visa •••• [XXXX]" (default card; PRIORITNÍ) / "Žádná karta" · Pobočky · "Mezná · Velké Němčice". With `eshop_visible`, a full-width E-shop card "MotoGo Shop · Oblečení, výbava a dárkové poukazy" follows. |
| 759–1059 | **Osobní údaje** (white card, summary, header row "Osobní údaje" 17/800 + ghost "Upravit" → P2) | Rows (label 11.5/700 `#6C8A7B` above value 14/600 `#1A2E22`): Jméno a příjmení · E-mail (lock icon) · Telefon · Adresa (one line: Ulice a č.p., PSČ Obec / město, Stát) · Datum narození · Č. OP / pasu · Č. řidičského průkazu · Platnost ŘP do · Kategorie ŘP chips **AM · A1 · A2 · A · B** (selected filled). A missing value shows amber "Doplnit". Optional rows (owner, PI §3): "Moje velikosti výbavy: helma [M] · bunda [L] · … / Vlastní výbava" (read-only, `profiles.gear_sizes`) and "Firemní údaje" (when set). |
| 1083–1451 | **Nastavení** (section title 14/800 uppercase eyebrow style + white grouped list r16, rows min 56, value right 12.5/600 `#4A6B5A`, label max 2 lines) | Oprávnění aplikace · "Vše povoleno" / amber "Poloha zakázána" → P7 · Notifikace · "Push · E-mail · SMS" (enabled consents) → sheet · Soukromí a souhlasy · "Vše uděleno" / lock "Během pronájmu povinné" → sheet · Změna hesla → sheet · Jazyk aplikace · "Čeština" → sheet · Měna · "CZK" → sheet · [optional, owner] Omezit animace (switch). |
| 1475–1731 | **Pomoc a podpora** | SOS — Pomoc na cestě (red row, only `sosAllowed`) · **AI asistent** (**nové**, opens the FAB panel) · Nápověda & FAQ ↗ (web FAQ in the app language) · [optional, owner] **Kontakt** (**nové**): "Zavolat · +420 774 256 271", "Napsat · info@motogo24.cz", web footer hours "PO - NE 00:00 – 24:00 (výdej a příjem motorek dle rezervace) · PO - PÁ 08:00 – 17:00 (technická podpora)". |
| 1755–1899 | **Ostatní** | Odhlásit se (red text, no confirmation, as today) · **Smazat účet** (red text; the name must not change, PI §0.5) |
| 1923–1947 | Footer | "MotoGo24 v[x.y.z]" 11/700 `#7C958A` centred. Optional: "Nová verze · Aktualizovat". |
| — | Chrome | Nav (PROFIL active, avatar ring + arc, unread count pill), AI FAB full at bottom 110, scroll padding 98 + 56 + 24. |

States (board prop `stav`):
- **Vše v pořádku** (default): rank 3, documents verified, upcoming VN booking, so Oprávnění reads "Vyžadováno" and Soukromí shows the lock.
- **Chybí doklady**: amber chip, the NAHRÁT DOKLADY CTA, and the Doklady tile reads "Chybí: rub ŘP".
- **Probíhá jízda (SOS)**: SOS chip and SOS row.
- **Nový zákazník**: Startér, "Žádná karta" (iOS: hint `cardsSavedAtCheckout`), personal summary with amber "Doplnit" values.
- **Načítání**: skeleton header + 6 tile skeletons; one shimmer pass of 1.2 s, repeating only while loading.
- **Chyba načítání**: `profileLoadError` "Chyba načítání profilu" + ghost "Zkusit znovu" (**nové** button; today the text only).
- Pull-to-refresh (**nové**, PI P16) invalidates profile, loyalty, documents and cards.

### 1.3 Sub-screens

| # | Screen | Shows (1:1, PI §) | v2.1 layout | Primary | States |
|---|---|---|---|---|---|
| P2 | Osobní údaje · úpravy | 12 fields + licence chips AM/A1/A2/A/B; DOB d/m/y dropdowns (years now−100…now−18; older stored value stays selectable); licence expiry now…now+20; E-mail read-only; save → `profiles.update` + RPC `set_my_license_group`; toasts `Uloženo / Profil aktualizován`, `Chyba` (PI §2.2) | 92 % sheet r22, light inputs (border 1.5 `#CFE3DA`, focus ring neon@.28), grouped "Kontakt", "Adresa", "Doklady pro smlouvu". Keyboard hides the nav and the FAB. E-mail row note (**nové**): "E-mail je tvoje přihlášení · změnu vyřeší podpora". | rank CTA "ULOŽIT ZMĚNY" | validation inline, amber |
| P3 | Přezdívka | `editNickname` "Upravit přezdívku", hint = first name, "Reset" + "OK" (PI §2.3; P7: translate "Reset"/"OK") | dialog r22 | OK | — |
| P4 | Věrnostní ranky `/loyalty` | hero (title, name, %, progress, `loyaltyLevelOf`, `loyaltyBookingsCount`, next/max, app-only, `loyaltyClimbMotivation`), leaderboard **only with `loyalty_leaderboard`** (live off; all texts PI §2.5), ladder 20 → 1 (locked / current / unlocked, badge, name, % pill, "od {2L−2} bodů" (P2 fix), gear benefit from 3, chip "TY"), rules card + gear rule | dark page, ladder grouped by the 5 tiers (tier header = emblem + "Silnice / Kovová liga / Liga drahokamů / VIP klub / Legenda" + "od X b."), each row a mini rank frame in its **new** colour. The ambient sparks (`_AmbientSparks`) become a static tier texture: a loop budget fix that the owner must OK, otherwise keep them. | none | loading spinner, error → ladder still shown |
| P5 | O programu (sheet) | title `loyaltyInfoTitle`, the 5 rules; **P1 fix**: replace "Rezervace delší než 7 dní = 4 body…" with "7 a více dní = 2 body = celý rank najednou" | light sheet | — | — |
| P6a | Notifikace | 5 consents (push, email, sms, whatsapp, marketing); lock banner `consentsLockedHint` during a rental; toast `consentsLockedActive` | switches (not squares), "Uložit" ghost | Uložit | locked |
| P6b | Soukromí a souhlasy | 5 consents (VOP, GDPR, data, smlouva, foto); same lock; **P3 fix**: toast title = section title | same | Uložit | locked |
| P6c | Změna hesla | 2 fields, `min8chars`, `passwordsDoNotMatch`, "Změnit heslo", toast `Hotovo / Heslo změněno` | sheet | Změnit heslo | errors inline |
| P6d | Jazyk aplikace | 8 languages + ✓; toast `Jazyk změněn`, today `context.go('/')` (P13: staying in Profil is an owner decision) | list rows with a text code chip (CS, EN, …) or flags (owner P14) | — | — |
| P6e | Měna | CZK / EUR / PLN, `currencyNote`, "1 EUR ≈ [kurz] Kč (ČNB)" | list rows | — | — |
| P7 | Oprávnění aplikace | intro, lock banner, rows Poloha / Fotoaparát / Oznámení / (iOS) Galerie with chips Povoleno / Zakázáno / Vyžadováno, Biometrické přihlášení toggle "Otisk prstu / Face ID", "Otevřít nastavení telefonu", "Povolit vše znovu" (PI §2.13) | white grouped list + status chips | "Otevřít nastavení telefonu" (ghost; no rank CTA here) | — |
| P8 | Smazat účet | dialog `deleteAccountTitle/Desc`, Zrušit / red "Smazat účet", RPC; toasts for `active_bookings`, failure, success → `/login` (PI §2.17) | dialog r22; destructive button `#D92D20` (never rank) | — | 3 toasts |
| S1 | Zprávy `/messages` | tabs Oznámení [n] / Konverzace; "Označit vše jako přečtené"; notification cards (type icon, title, 3 lines expandable, date, unread bar + dot); threads (🚑 for SOS:, 💬, subject, unread count, preview, date); empty texts (PI §2.7) | dark compact header + `.km-sw`-style 2-segment switch (sliding thumb, rank glow on the thumb edge). Line type icons replace the emoji (P14). Ride-feedback threads ("Zpětná vazba k jízdě #XXXXXXXX") carry a small "Hodnocení jízdy" chip. | Konverzace: "NOVÁ KONVERZACE" (rank) | empty "Žádná oznámení" / "Žádné konverzace"; error |
| S2 | Vlákno `/messages/:id` | subject title, chip Uzavřeno / Aktivní, bubbles (customer right neon-tint, team left white), input + "Odeslat", hidden input when closed, `messageSendFailed` | sticky input bar; closed thread shows a banner instead | Odeslat | empty `writeFirstMessage` |
| S3 | Nová konverzace (sheet) | subject field, "Odeslat", validation, error | sheet | Odeslat | — |
| S4 | Moje doklady `/docs` | `docsRequiredInfo`, verification banner, `scanTips` (behind ⓘ), "NASKENOVAT DOKLADY KAMEROU", conditional "NASKENOVAT ŘIDIČSKÝ PRŮKAZ", "NAHRÁT Z GALERIE" + kind sheet, status rows OP/Pas + ŘP (Ověřeno / Neověřeno, Smazat / Skenovat), gate line "Chybí: …", `docsVerifiedDesc` (**P5**: customer wording), delete dialog, toasts (PI §2.8) | hero with 2 document cards (OP/Pas, ŘP; state chip; "Platí do [datum]") | rank CTA "NASKENOVAT DOKLADY KAMEROU" (or the ŘP-only variant) | verified / missing / nothing uploaded; loading; error |
| S5 | Skenování `/docs/scan` | document choice, badges (**P4**: "Data uložena v telefonu" is inaccurate; owner), camera frame per side, step dots, OCR result + errors, help after N attempts (Zavolat / Napsat / Zkusit přesto / Zavřít), done toasts (PI §2.9) | restyle only; no level-up during scanning (today's code does not block here; see §6.8 L5) | camera shutter | all error texts |
| S6 | Faktury `/invoices` | year groups; tile icon by type, number or type label, date, amount (credit note red "−"); empty `noInvoices` / `invoicesAutoGenerated` | white list, amounts right-aligned tabular | — | empty, error |
| S7 | Dokumenty a smlouvy `/contracts` | fixed VOP, GDPR, Protokol o poškození (template); real documents (smlouva, protokol, protokol o poškození, VOP) with date; viewers; `consentGivenAtBooking` footer; `noOtherDocs` | two groups "Obchodní podmínky a vzory" / "Tvoje dokumenty" (grouping by booking = owner) | — | empty, legal load failed |
| S8 | Platební metody | cards (•••• last4 brand, Platí do, holder, PRIORITNÍ, ⭐ set default, 🗑 remove + dialog); Android add-card sheet (CardField, "Uložit kartu", "Šifrovaná platba · Stripe PCI DSS Level 1"); iOS hint `cardsSavedAtCheckout`; footer `cardsSecuredByStripe` | "wallet" cards: dark card r16 with the brand mark, default card first with a neon PRIORITNÍ chip | Android: "PŘIDAT NOVOU KARTU" | empty (Android/iOS), error |
| S9 | Pobočky `/pobocky` | CMS h1 / intro, per branch badge, title, address, hours, "Detail pobočky", CTA box "Vyberte si motorku na své pobočce" + "REZERVOVAT ONLINE", "Motorky na pobočkách" (PI §2.6) | **web v2 `/pobocky` mirror**: hero chips "2 pobočky: Vysočina a Brno · Bez kauce · Výbava v ceně"; two branch cards with photo `[fotka pobočky]`, badge OBSLUŽNÁ / SAMOOBSLUŽNÁ POBOČKA, stat tiles (Mezná "90 min z Prahy (cca) · 6XL max. velikost výbavy · PO–NE nonstop · [n] motorek na pobočce"; VN "24/7 nonstop, bez obsluhy · 30 min z centra Brna (cca) · 35 min z letiště Brno-Tuřany (cca) · [n] motorek na pobočce"), buttons "REZERVOVAT ZDE" (→ Motorky with the branch) + "DETAIL POBOČKY"; compare table "Mezná vs Velké Němčice" (web rows) | per-card "REZERVOVAT ZDE" (only the first in view loops) | loading, error `branchesLoadFailed` |
| S10 | Pobočka `/pobocky/:i` | badge, title, address, hours, about, gear, video, "Navigovat na pobočku", "Jak to probíhá" (Mezná 4 / VN 6 steps), VN photos ×4 + gallery, "Motorky na pobočce ([n])", CTA box (PI §2.6) | **web v2 detail mirror**: hero (badge, H1, stat tiles, "REZERVOVAT NA TÉTO POBOČCE" + "MOTORKY TÉTO POBOČKY"); video (VN first); O pobočce + Provozní doba; interactive step guide "Krok n z N" (PŘEDCHOZÍ / DALŠÍ KROK); Výbava; Fotogalerie; "Jak k nám" map + NAVIGOVAT; Motorky carousel; "Naše druhá pobočka". **Plus "Kontakt a údaje"** (from the branches sheet, PI P11): Telefon `+420 774 256 271` + "Zavolat", Kód pobočky (Mezná `273599`, VN `611174`, live), Typ lokality, Provoz, Kapacita, Otevřeno / Uzavřeno (`is_open`). | "REZERVOVAT NA TÉTO POBOČCE" | — |
| S11 | E-shop (flag off) | `/shop` (voucher banner, grid, sold out), `/shop/:id`, `/cart`, `/checkout`, `/voucher` — all texts PI §2.19 | restyle only; drawn as one screen "E-shop (zapne Velín)" with a note | "KOUPIT POUKAZ" / "K POKLADNĚ →" | empty, sold out |

### 1.4 Rank and motion on PROFIL

- **Rank shows in:** header aura and minted edge; avatar ring and arc; nickname chip; rank strip; the docs CTA. Tiles, lists and statuses stay neutral, because meaning colours stay.
- **Motion:**
  - Tab enter uses the `tab` fade-through (210 ms).
  - The arc fills from 0 once per session (`connector` 700 ms).
  - Tiles `reveal` (550 ms, 70 ms stagger, capped at index 5).
  - A badge `pop`s when its count changes.
  - An attention chip slides in (`sticky` 300 ms).
  - The summary card cross-fades into the edit sheet (`sheet` 300 ms).
  - Save shows a ✓ `pop` and a toast.
  - Reduced motion: everything static.
- **AI FAB:** full at 110 on P1 and S1, S4, S6, S7, S8, S9, S10. Hidden on P2 and S2 (keyboard or input), S5, sheets and dialogs.

### 1.5 Copy, defects and decisions on PROFIL

- **Defects:** fix P1–P16 from PI §4 during the port. **New in v2.1:**
  - **P17:** the branch "Kapacita" always shows a hard-coded `max8Motos` "Max 8 motorek" (`branch_detail_card.dart:226`, `branch_moto_list.dart:48`), while web v2 shows the live count (16 / 7 on 2026-10-15). Show the live count "[n] motorek na pobočce" (owner decision).
  - **P18:** the E-mail field is read-only with no explanation; add the note from P2 (new string, 8 languages).
- **Owner decisions:** see §10.

### 1.6 Completeness: every current item → v2.1

PI §7.6 rows 1–30 apply unchanged (hamburger → tab; logo ring + rank strip → `/loyalty`; name; nickname; rank card texts; Pobočky; E-shop; Osobní údaje; Zprávy + badge; Doklady; Faktury; Dokumenty; Platby; Oprávnění + biometrics; Notifikace; Soukromí; Heslo; Jazyk; Měna; SOS; FAQ; Odhlásit; Smazat účet; verze; global docs FAB; cart FAB; AI; push targets; leaderboard; level-up). Additions:

| Today | v2.1 |
|---|---|
| Branches sheet facts (phone + Zavolat, code, locality, operation, capacity, open/closed) | S10 "Kontakt a údaje" block. Delete the sheet only after this lands (P11). |
| "Motorky na pobočkách" (opens the sheet) | S9 per-card "REZERVOVAT ZDE" → Motorky with the branch preselected, plus S10 "Motorky na pobočce" |
| `/pobocky` CMS texts `web.pobocky.*` | Unchanged source; S9/S10 render the same CMS keys as the web |
| AI only from Home FAB and SOS | Global FAB + "AI asistent" row |

---

## 2. TRASY tab (boards `Trasy.dc.html`, `TrasyJizda.dc.html`)

Source of truth: `research/trasy_inventory.md` (cited as **TI §x**). The web has no routes or places pages. Web references are the landing section `lp-rt` "Kam vyrazit? A kudy jsi jel?" (copy, stat tiles, route draw) and the `.km` dark switch (§8).

### 2.1 IA

```
TRASY (tab, /routes; nav TRASY active for /routes*, /places-map, /routes-map; ride detail and focused flows hide the nav)
├─ shared header: "Trasy" + AnimatedRouteIcon · [🗺 mapa] [＋ přidat] · search (Místa/Trasy) · segments Místa · Trasy · Moje
├─ live strip (conditional): "Pokračovat v trase · {název} · {n}/{m} ✕" · "Nahrávám jízdu · [km] km"
├─ T1  Místa (default, remembered)        ── T4 Detail místa (sheet) ── T5 Fotky (viewer + credit sheet)
│     └─ selection bar "Vlastní vyjížďka ([n]) ›" → T12 Plánovač
├─ T2  Trasy                               ── T9 Detail trasy /routes/:id ── T10 "Otevřít v jiné aplikaci" sheet
│                                                                       └─ T6 Recenze (sheet + editor)
├─ T3  Moje (replaces /my-experiences; nav stays) ── Jízdy (Vše · S MotoGo · Soukromé) → T14 Detail jízdy /ride/:id → T15 Sdílet
│                                                   ├─ Uložené trasy → T12 / T11
│                                                   ├─ Objevená místa → T4 / T11
│                                                   └─ Historie navigace → T9 / T12 / T11
├─ T7  Mapa míst /places-map   · T8 Mapa tras /routes-map   (header map button by segment)
├─ T11 Navigace /route-nav/:id, /route-nav-custom (focused, no nav, no AI, no decorative motion)
├─ T12 Plánovač trasy /route-build (focused) ── T13 Výběr míst do trasy (pick mode)
├─ T16 "+" menu (sheet) → T17 Navrhnout trasu · T18 Přidat místo · T19 Odesláno (dialog) · manual recording start/stop
└─ filter / sort sheets: "Řadit a filtrovat" (Místa), "Vyber trasu", "Filtrovat trasy", "Řadit"
```

Redirects: `/routes-list` → `/routes?seg=trasy`, `/my-experiences` → `/routes?seg=moje`, deep links `?seg=`.

### 2.2 Shared chrome

- **Header** (`gDark` + rank aura, bottom r24, minted edge, collapsing).
  - **Row 1** (56): "Trasy" 22/800 + `AnimatedRouteIcon` (static under reduced motion). On the right:
    - 44 px glass **map** button. It follows the segment: Místa → T7; Trasy → T8; Moje → T7 filtered to my places.
    - 44 px glass **＋** button (a11y "Přidat") → T16. It replaces the bottom-right "+" FAB, so the AI FAB has that corner.
  - **Row 2** (48): search pill, shared query (`placesSearchProvider`). Placeholder by segment: "Hledat místo…" / "Hledat trasu, místo, město…" / hidden on Moje. It collapses on scroll, and a 🔍 icon in Row 1 restores it.
  - **Row 3** (52): **segments** in the web `.km-sw` style (dark pill, border `rgba(116,251,113,.22)`).
    - Each segment: icon 18 above the label 12.5/800, per §0.4.
    - Sliding neon thumb (300 ms spring). The label on the thumb is `#08230F`, and the thumb's outer glow is the rank `--rk-glow` at 30 %.
    - Labels: cs Místa · Trasy · Moje; en Places · Routes · Mine; de Orte · Routen · Meine; es Lugares · Rutas · Mías; fr Lieux · Itinéraires · Les miennes; nl Plekken · Routes · Mijn; pl Miejsca · Trasy · Moje; uk Місця · Маршрути · Мої. The new key is `routesSegMine`; the rest use existing keys.
- **Live strip** (sticky under the header, 52, light glass):
  - (a) Active navigation: "Pokračovat v trase · {název} · {reached}/{total}" + ✕ (`endRide`). On TRASY it replaces the shell route FAB; other tabs keep that FAB.
  - (b) Recording: red dot (the live loop) "Nahrávám jízdu · [km] km" (automatic: + motorka) / manual: + "Ukončit".
- **＋ menu** (T16, light sheet):
  - ⏺ "Zaznamenat vlastní jízdu", or red ⏹ "Ukončit záznam jízdy". Hidden during automatic recording.
  - "Vytvořit novou trasu" (**new entry**, the empty builder).
  - "Navrhnout trasu".
  - "Přidat místo".
  - Not logged in → login prompt with the copy fix (§2.7).
- **AI FAB:**
  - T1–T3: full at 110. With the T1 selection bar (64): bottom 182.
  - T9: mini above the sticky bar.
  - Hidden on: T4 (sheet), T7/T8 (right-side control column), T11–T15, T17–T19.

### 2.3 Screens

| # | Screen | Shows (1:1 from TI) | v2.1 layout and changes | Primary (rank) | States |
|---|---|---|---|---|---|
| T1 | **Místa** (`AllPoisScreen(asTab)`) | location prompt "Zapni polohu a seřadíme místa od nejbližších" + POVOLIT; map preview with gestures + hint "Klepni na mapu pro zvětšení · podrž místo pro detail"; filter toolbar; category chips with counts (12 categories); "Našli jsme i trasy · {n}"; place cards (84 thumb, name, category / route / "Komunitní místo", ★, "↗ 12.4 km · 15m", ⊕/✓); selection bar; tools and route sheets (TI §2.1) | Map preview 180, white r16 card, ⤢ button. **Category chips visible** as one horizontal scrolling row (TI P6), with "⚙ Filtry a řazení (n)", "V okolí 25 km" and "✕ Zrušit" before them. The "Našli jsme i trasy" banner **switches to the Trasy segment** with the same query. | selection bar "VLASTNÍ VYJÍŽĎKA ([n]) ›" (only with a selection) | spinner, empty `poiEmpty`, location denied |
| T2 | **Trasy** (`RoutesScreen`) | stat line, toolbar (Filtry, Řadit: Od mé polohy, Mapa tras, Zrušit), route cards (cover, type pill, name, branch flag, km, čas, míst, Od tebe, ★ → reviews sheet), pull-to-refresh, filter sheet (Země, Délka ⇄ Čas linked sliders, "Počítat i cestu od mé polohy"), sort sheet ×5 (TI §2.4) | **Stat line truth fix:** "{routes} tras · {pois} míst", counted from live data and floored (`floorCount(n)`: < 10 000 → hundreds + "+", ≥ 10 000 → thousands + "+"), e.g. "1 100+ tras · 49 000+ míst". Never a hard-coded floor (today 1 370 > live 1 174). **Card:** cover 16:9 with the **sketch drawn from `waypoints`** (draw once 900 ms; `geometry` is NULL everywhere); **start flag only when `startIsNearRoute`** (today every card says "MotoGo24 Mezná"); difficulty chip colours from v1. | none (browsing) | spinner, error "Trasy se nepodařilo načíst" + Zkusit znovu, empty, filter-empty |
| T3 | **Moje** | see §2.4 | see §2.4 | "VYTVOŘIT NOVOU TRASU" | login prompt, empty per sub-section |
| T4 | **Detail místa** (sheet 85 %, 50–97 %) | swipe siblings "3 / 12", 250 hero + thumbs, number badge, H1, category pill, description, **Okolí**, rating bar, reviews (editor with photos), sticky "📍+ Přidat do mé cesty / ✓ Odebrat z mé cesty" (TI §2.2) | **New secondary "Navigovat sem"** (TI P5; reuses `_navigateToPlace`) beside the add button. Copy fix: the review hint for places says "místo", not "trasa" (§2.7). | "PŘIDAT DO MÉ CESTY" | loading detail |
| T5 | Fotky | PageView, pinch 5×, ✕, "{n} foto", © credit sheet "Fotografie pochází z Wikimedia Commons…" + "Zobrazit zdroj" | unchanged, dark | — | — |
| T6 | Recenze | header "Recenze", "4.5 · 3 recenzí", "Napsat recenzi / Upravit / Smazat", empty "Zatím žádné recenze. Buď první!", editor (stars required, text, "Přidat fotky ({n})", "Odeslat recenzi"), snackbars → v2 toasts | light sheet | "ODESLAT RECENZI" | empty, error |
| T7 | Mapa míst | clusters, status line (6 variants), summary chips, "🛣 Mapa tras", filter-off, ◎, **📍+ Přidat místo**, long-press add, selection road route, "Tvoje trasa" draft (TI §2.3) | nav stays visible (unchanged), AI FAB hidden, right column 48 px round buttons | "PŘIDAT MÍSTO" (round, primary) | loading |
| T8 | Mapa tras | route points, "+ ostatní místa / Jen body tras", routes through a point (colours, labels, cards, "Detail ›", "⤳ Další trasa"), draft chip, ◎, hint "Klepni na bod = trasa" (TI §2.5) | as T7. Route colours avoid the rank-only purple: `#7C3AED` in `routes_map_picker.dart` stays as a **map line colour** (not a rank colour), but the owner may ask to drop violet entirely (§10). | — | computing, error |
| T9 | **Detail trasy** | map (live Mapy.com polyline, computing chip, start flag, numbered POIs rotated to the nearest, fullscreen map), title, chips (type, real km, čas, Od tebe, obtížnost, ★), description, "Místa na trase" carousel, Galerie, Recenze, sticky NAVIGOVAT + "Upravit / přidat body" + "Otevřít v jiné aplikaci" (Mapy.com / Google / Apple), swipe siblings (TI §2.6) | Map hero 220: draw-in 1.6 s + pins pop with a 70 ms stagger. 4 stat tiles (km · čas · obtížnost · míst) + chips "Od tebe ~38 km · ~45 min", ★. Description 3 lines + "Více". Sticky bar 92: **rank CTA 56 "ZVOLIT TRASU – NAVIGOVAT"**, two ghost links under it. Optional ghost "Půjč si motorku na tuhle trasu" → Motorky with the branch nearest the start (v1 §4.3; owner). | ZVOLIT TRASU – NAVIGOVAT | "Trasa nenalezena" + Zkusit znovu |
| T10 | Otevřít v jiné aplikaci | 3 targets, errors "Nepodařilo se otevřít navigaci", "Trasa nemá dostatek bodů pro navigaci" | sheet | — | — |
| T11 | **Navigace** | top bar (back keeps the ride running, name, status ×5, "☑ {n}/{m}", red ✕ → "Ukončit trasu?" dialog), map (ridden grey, ahead green up to the next stop, branch flag, pins, rider arrow), compass / zoom / recenter, HUD (progress, speed, Zbývá / Čas / Příjezd / Výška, "Jsi v cíli 🏁"), context cards (StopReached, RouteDone, NavForkHint, NavNextStopPill), stops sheet (+ "MotoGo24 · {pobočka}" return row), denied banner, persistence (TI §2.7) | **Restyle only, no decorative motion** (v1 rule). The "✨ Místo objeveno!" card gets a one-shot neon ring (static under reduced motion). No AI FAB, no nav. SOS chip 44 when `sosAllowed` (DESIGN_V2 §14 #10). | "DALŠÍ: {name}" inside the StopReached card (no loop) | location denied, rerouting, arrived |
| T12 | **Plánovač trasy** | map 260 (tap = stop, numbered pins, road line, hint), stats (km, čas, "{n} × zastávka", profiles Doporučené · Nejrychlejší · Nejkratší), NearbyPoiPanel (radius 5/10/25/50, categories, cards, empty), "Místa na trase" reorder list + 🗑, "📍+ Přidat z bodů zájmu", bottom bar 🔖 Uložit (sheet: name + note), "✉ Navrhnout" (sheet), "🧭 Navigovat" (TI §2.8) | **Raw coordinates hidden** (TI P7): a row shows "Zastávka N" + the reverse-geocoded name (Mapy.com rgeocode, as already used by PoiSubmit). Sticky bar 88: rank CTA "NAVIGOVAT", 🔖 and ✉ as 48 ghost icon buttons with labels. | NAVIGOVAT | "Přidej aspoň 2 zastávky", computing |
| T13 | Výběr míst do trasy | T1 without the quick links, prompt or map; back arrow, local filter; "+ Přidat do trasy" | focused | "PŘIDAT DO TRASY ([n])" | — |
| T14 | **Detail jízdy** `/ride/:id` | header (name ✎ → "Upravit jízdu" dialog, "{datum} · {moto}", ⇪ share, 🗑 "Smazat jízdu?"), map 260 (tap = new stop, tap stop = edit), stats 3×3 + gap row (📵 bez signálu · 🛰️ bodů stopy · ✂️ přerušení) + `rideGapNotice`, "start → konec", moto, description, "Sdílet ostatním" switch (+ 2 texts), "Zastávky a body zájmu" + hint, point cards, point sheet (Název, Popisek, Fotky ≤ 8, 🗑, Uložit) (TI §2.10) | Dark stat card in the web `lp-rt` phone-mock style (chips "186 km · 3 h 42 min · Ø 58 km/h · ↑ 1 240 m" → real values). A MotoGo ride shows a chip "S MotoGo · {motorka}" + link "Rezervace #[ID] ›" (the reservation that owns it; optional, TI P10). | none | — |
| T15 | Sdílet jízdu | lead, 6 tiles (WhatsApp, Facebook, X, Telegram, E-mail, Kopírovat), toasts | sheet; official brand glyphs | — | — |
| T16 | ＋ menu | §2.2 | sheet | — | login prompt |
| T17 | Navrhnout trasu | intro banner, Název, **link** "Odkaz z Mapy.com nebo Google Maps" + "Načíst body z odkazu" (+ result / error), help box, map tap + reorder, stops, description, photos ≤ 6 "první je titulní", "Odeslat ke schválení" (TI §2.11) | focused, light form | "ODESLAT KE SCHVÁLENÍ" | errors "Vyplň název", "Přidej aspoň 2 body…" |
| T18 | Přidat místo | intro, 220 map with a fixed centre pin, "◎ Moje poloha", Název (reverse-geocoded), Popis, photo (only the 1st is stored; hint "Návrhy s fotkou schvalujeme rychleji."), "Odeslat ke schválení" | focused | "ODESLAT KE SCHVÁLENÍ" | errors |
| T19 | Odesláno | "Díky! Návrh odeslán" / "Po schválení se objeví v aplikaci všem jezdcům." / "Hotovo" | dialog with ✓ `pop` | Hotovo | — |

### 2.4 T3 Moje (the "Sultan" diary; replaces `/my-experiences`, nav stays)

- **Hero card** (`gDark` + rank ring colour on the edge; web `.lp-rt` dark card language):
  - "Moje zážitky" 20/800 + "Tvé trasy a objevená místa s MotoGo24" (`myExpTitle`, existing subtitle).
  - **4 stat tiles**, web `.lp-rt-stats` style (white tile, value 18/900 `#1A2E22` count-up once, label 11.5/700): "[n] objevených míst" (`get_my_places`) · "[n] uložených tras" (`get_my_saved_routes`) · "[n] jízd" (`get_my_rides`) · "[km] km najeto" (Σ `distance_km`). Each tile jumps to its sub-section.
  - Board sample values are marked "ukázka" (personal data is not readable anonymously).
- **CTA row:**
  - Rank CTA 52 "VYTVOŘIT NOVOU TRASU" → empty T12.
  - Outline 52 "Zaznamenat vlastní jízdu"; while recording it turns red "Ukončit záznam jízdy". Hidden during an automatic recording.
- **Sub-chips** (horizontal, remembered):
  - Labels: Jízdy · Uložené trasy · Objevená místa · Historie navigace.
  - Návrh překladu: en Rides · Saved routes · Discovered places · Navigation history; de Fahrten · Gespeicherte Routen · Entdeckte Orte · Navigationsverlauf; es Salidas · Rutas guardadas · Lugares descubiertos · Historial de navegación; fr Sorties · Itinéraires enregistrés · Lieux découverts · Historique de navigation; nl Ritten · Opgeslagen routes · Ontdekte plekken · Navigatiegeschiedenis; pl Przejazdy · Zapisane trasy · Odkryte miejsca · Historia nawigacji; uk Поїздки · Збережені маршрути · Відкриті місця · Історія навігації.
  1. **Jízdy** (default when any ride exists):
     - Filter chips Vše · **S MotoGo** · **Soukromé**, split on `user_rides.booking_id != null`. Návrh: en With MotoGo / Private, de Mit MotoGo / Privat, es Con MotoGo / Privadas, fr Avec MotoGo / Privées, nl Met MotoGo / Privé, pl Z MotoGo / Prywatne, uk З MotoGo / Приватні.
     - At the top, a compact row "Záznam jízdy" + Switch + "Nahrávám" badge. ⓘ expands the full hint text (TI §2.9 item 2) unchanged.
     - `RideCard` list (track preview, badges Nahrávám / Sdíleno, name or "Projetá jízda", meta ×8 incl. moto) → T14.
     - Snackbars (5 texts) → toasts.
  2. **Uložené trasy:** cards (name, 🗑 dialog, km, čas, "{n}× zastávka", date, 2-line description, "Navigovat" → T11 custom, "Upravit" → T12). Empty: "Zatím žádné uložené trasy" + text adjusted to "Začni tlačítkem Vytvořit novou trasu nahoře…" (copy fix: there is no longer a "green button").
  3. **Objevená místa** (= today's "Moje místa"): 92 photo, "✅ {name}", "🗺️ {route}", "{date} · navštíveno {n}×", 🧭 → T11 single place, tap → T4 (swipe my places). Empty texts unchanged.
  4. **Historie navigace** (= today's "Moje trasy", local, works without login): cards (name, chip Aktivní / Dokončeno, 🗑 end / remove, date, "{reached}/{total}", "Pokračovat v trase" / "↻ Jet znovu", tap → T9 or T12). Empty texts unchanged.
- **Not logged in:** the hero shows "Přihlas se a sbírej objevená místa i vlastní trasy" + "PŘIHLÁSIT SE" (rank CTA). Historie navigace stays available.

### 2.5 Motion and rank on TRASY

| Element | Motion | Reduced motion |
|---|---|---|
| Segment thumb | 300 ms spring + rank glow at 30 % | Instant |
| Card reveal | `reveal`, first 6 cards | Static |
| Route sketch | Draws once: 900 ms on cards, 1 600 ms in detail | Static (web pauses its draw too) |
| POI pins | Pop with a 70 ms stagger | Static |
| Moje counts | Count up once per session (700 ms) | Static |
| "Místo objeveno" | One-shot ring | Static |
| Pull-to-refresh | Brand spinner | Static |

- **Loops:** at most the primary CTA + one live indicator (the recording dot or the live-strip ping).
- **Rank shows in:** header aura and edge, segment thumb glow, Moje hero ring, and the primary CTAs (VLASTNÍ VYJÍŽĎKA, ZVOLIT TRASU – NAVIGOVAT, VYTVOŘIT NOVOU TRASU, NAVIGOVAT in the builder). None in navigation (T11).

### 2.6 Completeness

Every row of TI §8 (28 rows: catalogue, filters, banner, place card, place detail, selection, both maps, route list, route detail, navigation, live FAB, builder, add menu, both submit screens, Moje stats, create CTA, recording switch, manual ride, ride cards, saved routes, my places, history, ride detail, reservation "PROJETÉ JÍZDY", login prompts, offline caches and the recording notification) maps to T1–T19 above. Additions and moves:

| Today | v2.1 |
|---|---|
| Rotating quick-link tiles (swipe to cycle) | Segments + header map button (all 3 destinations one tap away; nothing hidden behind a gesture) |
| `/my-experiences` outside the shell (no nav) | T3 segment inside the shell |
| "+" FAB bottom-right on Trasy only | Header "＋" on every segment + "Vytvořit novou trasu" |
| Route FAB "Pokračovat v trase" on TRASY | Live strip (other tabs keep the shell FAB) |
| Rides with MotoGo and private rides mixed | Jízdy filter Vše / S MotoGo / Soukromé |
| Header stats: places + routes only | 4 tiles incl. rides and km |
| Reservation detail "PROJETÉ JÍZDY" | Unchanged + ride detail links back to the reservation (optional) |

### 2.7 Truth and copy fixes (port, 8 languages)

1. Route count floor 1 370 → live count, floored (§2.3 T2). Web FYI: "50 000 zajímavých míst" slightly exceeds the live 49 926.
2. Card branch flag only when `startIsNearRoute`.
3. Sketch from `waypoints` (7–9 points) wherever `geometry` is NULL. Spec C16 said `geometry`.
4. Place review hint: "Napiš pár slov o místě (volitelně)" (**nové**, place only; the route hint stays).
5. Not-logged-in submit: "Přihlas se a pošli návrh" (**nové**) instead of "Přihlas se a ohodnoť".
6. Unused keys `placesMapRoutes`, `poiNavigateThrough`, … (TI P9) may be reused for new labels before new keys are added.

### 2.8 Sample content for the boards (real, anon read 2026-10-15)

- **Routes near VN, by distance from the branch** (their `branch_id` says Mezná):
  - Rajhrad a Židlochovicko (40 km · 55 min · Lehká · 5 míst; "10,6 km od pobočky")
  - To nejlepší v okolí: Špilberk (66 km · 1 h 34 min · Lehká · 8)
  - Za historií: Synagoga v Dolních Kounicích a okolí (122 km · 2 h 54 min · Lehká · 7)
  - Vodní krásy: Věstonická nádrž a okolí (170 km · 4 h 50 min · Střední · 7)
  - Vyhlídková jízda: Stará radnice v Brně a okolí (249 km · 5 h 55 min · Střední · 7)
  - Covers: TI §4.1; sketches: DESIGN_V2 §5.8 `d` paths + `gen/route_sketches.txt`.
- **From Mezná:** UNESCO trojúhelník – Telč, Třebíč, Zelená hora (242 km · 5 h 45 min · Střední · 8, cover `66dd69af…`), Husitské Táborsko a Chýnovská jeskyně (`62ef780c…`), Přehrady, voda a klášter Vysočiny.
- **Places near VN:** TI §4.1 table (Zámek Velké Němčice `f1784715…` with its real description and Okolí text, vodní mlýn, Vodní dílo Nové Mlýny, rozhledny, Římská vojenská pevnost u Mušova, Zámek Pouzdřany).
- **Reviews:** "Vodní krásy: Gösselsdorfer See a okolí" ★5 "Fajn vyjížďka.🤘"; "Za historií: Rychlebský hrad a okolí" ★5.
- **Personal data, every item marked "ukázka":**
  - A MotoGo ride "S MotoGo · [motorka z dřívější výpůjčky]", e.g. "Pálava a Mikulov · 128 km · 2 h 41 min".
  - A private ride "Podyjí · 96 km".
  - 3 saved routes, 12 places, 7 rides, 1 284 km.
  - The R1 Husqvarna ride cannot exist yet (its booking is in the future).

---

## 3. Kalkulačka (board `Kalkulacka.dc.html`)

### 3.1 Place and entry points (web parity: `/katalog` `.km` switch → `.kc`)

- **Where:** inside the **Motorky** tab as its second mode, `/motorky?rezim=kalkulacka`. Nav visible (MOTORKY active). This is exactly the web's `.km` switch: "Najít motorku · Filtr nabídky" | "Spočítat cenu · Volné dny a cena" (`f_mode_*` / `f_calc` texts).
  - The switch sits in the Motorky header under row 1. Sliding thumb 300 ms; the content cross-fades (`enter`).
  - In calculator mode, the catalogue rows (date pill, filter chips) collapse with `AnimatedSize` 300.
  - The mode is remembered per session.
- **Entries:**
  1. The Motorky switch.
  2. **Domů funnel** "Spočítat přesnou cenu ›" (§4), prefilled with the selected bike + preset.
  3. Domů S1–S9: the "Kdy jedeš příště?" pill becomes `[pill …][44 px calculator icon button]`, a11y "Spočítat cenu".
  4. Deep link `?moto=&start=&end=` (prefill, as web `kcData.pre`).
- The **Detail keeps** its own "Tvoje jízda" calculator (DESIGN_V2 §6). It is the per-bike calculator, so no per-card calculator button is needed.

### 3.2 Layout (390 wide; dark `.kc-card` mirror, r22, radial `#24563B → #0E2A1C → #0A1F14`, inset neon@.25 border)

| Block | Web `.kc` source | App |
|---|---|---|
| Head | `.kc-eyebrow` "KALKULAČKA CENY" (calc icon), H2 "Spočítej si cenu", `.kc-lead` | Same texts. Eyebrow 11.5/800 `#A8FF9F` pill neon@.12; H2 22/800 white; lead 14/600 `#CFE7DA`. Rank chip "Motorkář · −3 %" right of the eyebrow. |
| ① Pobočka | `.kc-seg` 3 options (.8fr / 1fr / 1.15fr), each title + sub: "Všechny · 24 motorek", "Mezná · s obsluhou", "Velké Němčice · samoobsluha nonstop" | Identical; option min-h 58 r14; selected = neon border + 1 px neon ring + glow; counts live. |
| ② Motorka | native `<select>` "Jakákoli volná motorka" + options "— od X Kč/den · v servisu"; selected card `.kc-moto` (96×64 photo, name, "Mezná · Cestovní · od 2 811 Kč/den", status pill, "Detail motorky ›") | A 54 dp **picker field** (not a native select) → light sheet list: thumb 54×40, name, "branch · category", **"Tvoje cena od 2 727 Kč/den"** + struck "2 811", status pill ("v servisu", "Volná od 21. 10.", "Momentálně nedostupná"). Selected card as web with **rank price**; pill "● Volná ještě dnes" (live ping = the screen's live indicator); "Detail motorky ›" → `/moto/:id` with the dates. |
| ③ Termín | `.kc-cal-box`: month nav 42 circles, weekday row (weekend neon), day cells 46 r11 (number + list price/day), states free / busy (stripes + line-through) / pending (dashed amber, "Čeká na potvrzení" = pending < 4 h) / past / today dot / start-end `gNeon` / in-range neon@.24; hint line; legend; `.kc-note` | Same component as C9 (v1 §3) **inline**, plus the web **pending** state and legend "Volno · Obsazeno · Čeká na potvrzení · Tvůj termín" + "Cena/den v Kč (ceník) · tvoje sleva se odečte v souhrnu". Without a bike: no prices, note "Bez vybrané motorky uvidíš dny, kdy je volná aspoň jedna motorka." Closed season days come back as busy (as on the web). |
| ④ Předání a výbava (**app-only**) | — (web asks in the reservation form) | Two summary rows, as Detail ②/③ (DESIGN_V2 §6.1). "Na pobočce Mezná · vyzvednutí 12:00 ½ · vrácení 19:00 · Změnit ▾" expands to: segmented Na pobočce / Přistavení (Mezná only; VN locked + ⓘ "Jen na pobočce"), time chips (½ tag from 12:00), return Na pobočce / Odvoz, address sheet "[25] km · ukázka" (fee 1 000 + 40 Kč/km per direction). "Výbava navíc · spolujezdec + boty pro oba · 0 Kč s rankem · Změnit ▾" expands to: rider gear included line, 3 paid items with strike at rank ≥ 3, trailer (Mezná only), "Velikosti vybereš v dalším kroku." Return copy: Mezná "Tankovat před vrácením netřeba, jen ať nesvítí rezerva"; VN "Nádrž plnit netřeba, jen nesmí svítit rezerva · vrať ji umytou" (fuel fact). |
| Summary "účtenka" | `.kc-sum-in` white receipt with a scalloped top on the dark card: "TVOJE CENA", dates Vyzvednutí → Vrácení + "3 dny" pill, bars per day (labels ≤ 10 days, ≤ 31 bars), rows grouped by weekday ("Pá · 3 514 Kč", "2 × 2 811 Kč"), `.kc-total` dark box "CELKEM ZA PRONÁJEM" + value + "průměrně … / den", `.kc-late` ½ card, `.kc-inc` chips, CTA, `.kc-assure`, `.kc-reset` | Same receipt + app rows: "Vyzvednutí od 12:00 (½ 1. dne) −1 757 Kč", "Výbava navíc 1 270 Kč → 0 Kč" (strike, rank), "Věrnostní sleva Motorkář 3 % −315 Kč", delivery rows when chosen. Total box label **"TVOJE CENA"**, value **32/900 neon tabular**, "průměrně 3 396 Kč / den", line "Díky ranku Motorkář ušetříš 1 585 Kč". ½ card: at 09:00 → "Vyzvedni od 12:00 a 1. den máš za půlku: ušetříš 1 704 Kč, zaplatíš 10 189 Kč." + chip button "Nastavit 12:00" (**app-only**, one tap); at 12:00 → "✓ Vyzvedáváš od 12:00 · 1. den za půlku". Chips "Bez kauce · Výbava pro řidiče v ceně · Bez limitu km" (web texts; not for the trailer). |
| CTA | `.lp-btn-primary kc-go` "Rezervovat tento termín" / ghost "Rezervovat tuto motorku" / "Zobrazit volné motorky a rezervovat" | **Rank CTA 60 "REZERVOVAT · 10 189 Kč"** → `/booking` express with bike, dates, times, handover and extras prefilled (DESIGN_V2 §8). No bike → "ZOBRAZIT VOLNÉ MOTORKY" → Motorky (find mode) with the dates. Bike without dates → ghost "VYBRAT TERMÍN" scrolls to ③. |
| Assure + reset | "Storno zdarma do 7 dní před začátkem · Bezpečná platba", "✕ Zrušit termín" | **"Storno zdarma víc než 7 dní předem · Bezpečná platba"**. This is the web landing wording (`landing.php` `assurance`); the calculator's cs default "do 7 dní před začátkem" reads the opposite way and is flagged as a web copy bug (§10). Keep "✕ Zrušit termín". |
| Sticky bar | `.kc-sticky` (mobile; shown while the summary is off-screen): "BMW R 1200 GS Adventure · 3 dny" + "12 261 Kč" + "REZERVOVAT" | Docked **on top of the nav** (night glass, 72): context 12.5/700 `#CFE7DA` + value 20/900 neon + rank CTA 48 "REZERVOVAT". Shown only while the receipt CTA is off-screen (IntersectionObserver equivalent), so **one** primary is visible at a time. Slide 300 ms. |
| FX note | `.kc-fx` | With Profil → Měna EUR/PLN: values "≈ [x] €" + note "Cena v € je orientační (kurz ČNB), platba probíhá v Kč." (`currencyNote` family). Rates are never invented on the board: `[kurz ČNB]`. |

### 3.3 Price engine (v1 §6, unchanged) and check values

```
rental = Σ price_<den>; late = (pickup ≥ 12:00 && days ≥ 2) ? round(day1/2) : 0
extras = Σ (690, 290, 290) unless rank ≥ 3 → 0; trailer 0 (Mezná); delivery = Σ(1000 + 40·km) per direction
loyalty = round((rental − late + extras) · pct/100); total = rental − late + extras + delivery − loyalty − codes
saved  = (rental − late + list extras + delivery) − total
```

BMW R 1200 GS Adventure, Mezná, pá 23.–ne 25. 10. (list 3 514 + 4 882 + 3 865 = **12 261**, late 1 757):

| rank (pct) | 09:00, bike only | 12:00, bike only | 12:00 + passenger gear + both boots |
|---|---|---|---|
| 1 Startér (1 %) | 12 138 | 10 399 | 11 656 |
| 2 Jezdec (2 %) | 12 016 | 10 294 | 11 539 |
| **3 Motorkář (3 %)** | **11 893** | **10 189** | **10 189** (extras free; "ušetříš 1 585 Kč") |
| 6 Bronzový (6 %) | 11 525 | 9 874 | 9 874 |
| 10 Diamantový (10 %) | 11 035 | 9 454 | 9 454 |
| 17 VIP (17 %) | 10 177 | 8 718 | 8 718 |
| 20 Legenda (20 %) | 9 809 | 8 403 | 8 403 |

**The board default must show 10 189 Kč at rank 3.** Board check list: rank 2 → 11 539; the same rank 3 dates with 09:00 → 11 893. Late-card difference at rank 3: 11 893 − 10 189 = 1 704. Bike "od" prices at rank 3: BMW 2 727, Husqvarna 3 437, Shotgun 1 778.

### 3.4 States (board prop `stav`)

| `stav` | Shows |
|---|---|
| **BMW · 23.–25. 10. · vše vybráno** (default) | Full receipt, 10 189 Kč. |
| Bez motorky · jen termín | `.kc-free` list "Volné v tvém termínu: [n]" (≤ 6 rows: 54×40 thumb, name, branch · category, total **Tvoje cena** + arrow, stagger 50 ms; kids' bikes last), "a dalších [n] v Motorkách ›", CTA "ZOBRAZIT VOLNÉ MOTORKY". None → "V tomto termínu na pobočce žádná motorka volná není. Zkus jiný termín nebo pobočku." |
| Motorka bez termínu | "Cena po dnech · Kč" 7 bars Po–Ne with list prices + "Tvoje cena od 2 727 Kč/den" + "Vyber termín v kalendáři — cenu spočítáme hned." + ghost "VYBRAT TERMÍN" |
| Jen den vyzvednutí | Head with "VRÁCENÍ —" + "Vyber den vrácení a uvidíš celkovou cenu." |
| Obsazený den v rozmezí | Amber note "V tomto rozmezí je obsazený den. Vyber jiný termín." (and "Tahle motorka v tvém termínu volná není — vyber jiný."). CTA ghost "ZMĚNIT TERMÍN". |
| Mimo limit dní | "Tuhle motorku půjčujeme minimálně na {n} dní." / "…nejdéle na {n} dní." (Shotgun max 30) |
| Načítání obsazenosti | Cells shimmer (the only loop while loading) + pill "Načítám obsazenost…" |
| Chyba obsazenosti | "Obsazenost se nepodařilo načíst." + "Zkusit znovu" |
| Věrnost nedostupná | List prices + row "Věrnostní slevu teď nevidíme · Zkusit znovu"; the CTA charges exactly the displayed price (v1 §6) |
| Nic nevybráno | Calendar-in-disc art + "Vyber motorku a termín — cenu spočítáme hned." (the web's "bez registrace" is dropped: in the app he is logged in) |

### 3.5 Motion

| Event | Motion |
|---|---|
| Mode switch | Thumb 300 ms + content `enter` |
| Branch or bike change | Card `enter` (web `kcIn` .35 → token 300) |
| Day pick | Start / end `pop`; range cells fill with a 12 ms stagger (≤ 250 ms) |
| Receipt appears | `enter` |
| Bars | `bars` 500 ms with a 45 ms stagger |
| Any recalculation | Total `bump` + delta chip + `scanOnce` on the card (the web's infinite `lpScan` and `kcFloat` are **not** ported: loop budget) |
| ½ card | One `pop` (the web's `kcPulse` loop is not ported) |
| Sticky bar | Slides in |

Loops: the CTA glow + tier fx, and the "Volná ještě dnes" ping. Reduced motion: everything static.

### 3.6 Copy (cs, verbatim from web `kcDefaults()` unless marked)

Web texts reused 1:1: "KALKULAČKA CENY", "Spočítej si cenu", lead, "Pobočka", "Motorka", "Termín", "Všechny", "{n} motorek", "s obsluhou", "samoobsluha nonstop", "Jakákoli volná motorka", "od {price}/den", "Volná ještě dnes", "Volná od {date}", "V servisu — vyber si volné dny v kalendáři", "Momentálně nedostupná", "Detail motorky", "Bez vybrané motorky uvidíš dny, kdy je volná aspoň jedna motorka.", "Načítám obsazenost…", "Obsazenost se nepodařilo načíst.", "Zkusit znovu", "Klepni na den vyzvednutí", "Teď den vrácení (může být i stejný den)", "Klepnutím na jiný den termín změníš", legend ×4, the range, bike-busy, min-days and max-days texts, "Tvoje cena", "Vyzvednutí", "Vrácení", "průměrně {price} / den", "Cena po dnech", late title + text template, `late_one`, includes ×3, "Zrušit termín", "Volné v tvém termínu: {n}", `free_none`.

**App-specific:**
- "Předání a výbava".
- "Cena/den v Kč (ceník) · tvoje sleva se odečte v souhrnu".
- "Nastavit 12:00".
- "✓ Vyzvedáváš od 12:00 · 1. den za půlku".
- "Díky ranku {rank} ušetříš {Kč}".
- "REZERVOVAT · {Kč}".
- "ZOBRAZIT VOLNÉ MOTORKY".
- "VYBRAT TERMÍN".
- "a dalších {n} v Motorkách ›".
- "Vyber motorku a termín — cenu spočítáme hned.".
- "Vyber termín v kalendáři — cenu spočítáme hned.".

The web already has 7-language overlays for its texts (`lang/v2/<lang>/katalog.php`); reuse them.

### 3.7 Rank on the calculator

Rank chip in the head, the rank CTA, and the sticky CTA. Prices are **never** coloured by rank: neon on dark, `#0D6E0D` on the light receipt.

### 3.8 AI FAB

Full at 110. Mini 44 at 182 while the sticky bar shows (98 + 72 + 12). `FabAvoid` zones: the receipt CTA and the sticky CTA are `cta`; picker, cells and reset are `tap`. Chips in the chat panel: "Poraď mi motorku", "Jak funguje vyzvednutí od 12:00?", "Kolik stojí přistavení?".

### 3.9 Web ↔ app parity checklist

Branch step ✓ · bike step with status + detail link ✓ · calendar with free / busy / pending / past / today, price per day, legend, hint, note ✓ · min / max / busy warnings ✓ · loading / error / retry ✓ · summary dates, days, bars, grouped rows, total, average ✓ · late-pickup ½ ✓ · includes ✓ · CTA variants ✓ · assure (corrected) ✓ · reset ✓ · free list without a bike ✓ · currency note ✓ · sticky bar ✓ · deep-link prefill ✓.

**Added for the app:** rank price everywhere, handover / time / delivery / extras, savings line, one-tap 12:00, express booking.

---

## 4. Home without a booking: funnel hero "Tvoje příští jízda" (default Main state)

### 4.1 When

Shown when the customer has **no upcoming or active booking**: today's `HomeReservationsSection` empty state "Žádná aktivní rezervace" / "Zarezervujte si motorku" → `/search`. It takes the ticket's place: **the one dark hero**.

- Also in **S10** (completed, nothing upcoming), under the review card (§5.4).
- With any upcoming or active booking, the ticket (S1–S9) shows instead.
- The funnel replaces today's Home `MotoFilterPanel(showDates)` + bike list. Those move to Motorky (v1 §5), so nothing is lost.

### 4.2 Layout (y budget on a 390 × 844 phone; the CTA must stay above the fold = 844 − nav 98 = 746)

| y | Element |
|---|---|
| 0–246 | Header (DESIGN_V2 §5.1). The S0 concierge note uses the personal season line "Sezóna 2026 · [km] km · [n] jízd · [n] míst", because the question lives in the funnel title. |
| 256–288 | Marquee (only if set in Velín) |
| 300 | **Funnel card** top (r20, `.rk-hero` aura + texture; padding 16; `shDark`) |
| 316–340 | Eyebrow pill "TVOJE PŘÍŠTÍ JÍZDA" (11.5/800, `--rk-acc`, pill white@.06) + right rank chip "Motorkář · −3 %" |
| 348–374 | Title 22/800 white "Kam vyrazíš příště, [přezdívka]?" (no nickname: "Kam vyrazíš příště?"; 2 lines allowed at 360 dp → +26) |
| 378–396 | Sub 12.5/600 `#CFE7DA`. Rank ≥ 3: "Ceny už máš se slevou 3 % · výbava spolujezdce a boty zdarma". Ranks 1–2: "Ceny už máš se slevou {pct} %". Loyalty failed: "Ceny teď bez věrnostní slevy · Zkusit znovu". |
| 408–470 | **Kdy** row: 2 preset chips 129 × 62 (label 13/800 max 2 lines + date 11.5/700 `#A8FF9F`): "Nejbližší víkend · pá 16. – ne 18. 10." (selected by default) · "Další víkend · pá 23. – ne 25. 10." Then the **calendar button** 52 × 62 (calendar icon 24, a11y "Jiný termín"; selected when a custom range is set) → C9 sheet. Selected chip: neon border 1.5 + check `pop`. |
| 482–662 | **Bike carousel** (`PageView` viewport .82 → 294 × 168 cards at 482–650, 10 gap, next card peeks; 6 px dots at 656–662). Card = full-bleed photo (cover; the blurred-backdrop option per `photoFit`), bottom scrim. Top-left pill "● Volná v termínu" (ping only on the centred card). Top-right badge "Pro tvůj ŘP A", or with history "Znovu" on the last-rented bike (sample: "Znovu · ukázka"). Bottom-left: name 17/800 white + "Mezná · Cestovní" 11.5/700 white@.8. Bottom-right: "Tvoje cena · 3 dny" 11/700 `#A8FF9F` + **"11 893 Kč"** 20/900 neon tabular + struck "12 261" 11.5/600 white@.5. Under the value, chip "½ od 12:00 jen 10 189 Kč" (11/800 on neon@.14). The centred card has the 2 px **rank ring** (`--rk-ring`), scale 1; side cards .96, opacity .85. |
| 670–730 | **Primary rank CTA 60 "REZERVOVAT · 11 893 Kč"** (crown / laurel glyph VIP / Legenda). Its label cross-fades on every change. The bottom (730) stays above the fold (746). |
| 738–778 | Two ghost links (13.5/800 `#A8FF9F` + chevron): "Spočítat přesnou cenu ›" (→ Kalkulačka prefilled) · "Všechny motorky ›" (→ Motorky with the dates) |
| 786–810 | Season microline 11.5/600 `#9FC4B1` + calendar icon: "Sezóna 2026 do 31. 10. · Termíny na 2027 rezervuj už teď (od 26. 3.)." Source: CMS `web.landing.common.season_note` (the same text as web v2 `lp-panel`); hidden when empty. |
| 826 | Card bottom; the Home sections follow (§4.7) |

**FabAvoid:** the CTA (670–730, full width) sits under the AI FAB rest slot (678–734), so at rest the FAB **yields** (fade, as v2 §4.2). It returns after ~40 px of scroll.

### 4.3 What it recommends (no invented logic)

- **Candidates:** active bikes the customer's `license_group` allows, **free on every day** of the selected range (`get_moto_booked_dates`, branch closures included), not trailers, not kids' bikes unless the customer has rented one before.
- **Order:** the last-rented bike first (if any completed booking exists; badge "Znovu"), then the Motorky default order (fleet `sort_order`). Up to 5 cards + an end tile "Všech [23] motorek ›" (→ Motorky with the dates).
- **Board sample** (marked "ukázka obsazenosti"): BMW R 1200 GS Adventure (Mezná) · Husqvarna 701 SM (Velké Němčice) · Royal Enfield Shotgun 650 (Mezná). Real photos (v1 §1).
- The CTA uses the centred bike, the selected range, that bike's branch, **pickup 09:00** (the draft default, as on the catalogue cards; the ½ chip shows the 12:00 alternative), return 19:00 at Mezná or "do 23:59" at VN, and no extras.

### 4.4 Prices on the funnel (rank 3, pá–ne, 3 days)

| Bike | List | Tvoje cena 09:00 | ½ od 12:00 |
|---|---|---|---|
| BMW R 1200 GS Adventure | 12 261 | **11 893** | 10 189 |
| Husqvarna 701 SM | 14 614 | **14 176** | 12 027 |
| Royal Enfield Shotgun 650 | 7 563 | **7 336** | 6 224 |

Both weekends have the same weekdays, so the same totals. Other ranks come from the engine (§3.3).

### 4.5 Interactions and motion

| Interaction | Behaviour |
|---|---|
| Preset tap | Chip `pop` + haptic; the carousel re-filters (cards cross-fade `enter`, stagger 70 ms); price `bump`; CTA label cross-fades |
| Calendar button | C9 sheet (v1); the confirm closes it and the button shows filled; the date line is added under the title ("pá 30. 10. → so 31. 10. · 2 dny ✕") |
| Carousel swipe | The snap selects the centred card: ring morph 180 ms + `bump` |
| Centred photo tap | → Detail with the dates (Hero flight 350 ms) |
| Side-card tap | Scrolls it to the centre |
| CTA | → `/booking` express (push 300; the photo flies to the recap). Booking shows "Termín a předání" collapsed with Změnit (DESIGN_V2 §8). |
| First build per session | Card `reveal` 550 ms, chips stagger, then the CTA loop starts |

- **Loops:** the CTA glow + tier fx, and the ping on the centred card's pill. Reduced motion: static, no ping, no Hero.

### 4.6 States

| State | Shows |
|---|---|
| Loading | 3 skeleton cards (one shimmer pass of 1.2 s, repeating only while loading) + disabled ghost CTA "REZERVOVAT" |
| Error | "Motorky se nepodařilo načíst" + "Zkusit znovu" (presets stay) |
| None free | "Na tenhle termín je pro tvůj ŘP všechno rozpůjčené. Zkus další víkend nebo jiný termín." + CTA becomes ghost "VYBRAT JINÝ TERMÍN" |
| Loyalty failed | List prices + sub "Ceny teď bez věrnostní slevy · Zkusit znovu" |
| Off season | Only the season line; presets beyond the season close show struck and disabled (busy) |
| New customer (rank 1, no history) | No "Znovu"; sub "Ceny už máš se slevou 1 %"; the rest identical |

### 4.7 Home around the funnel

- **S0:** Header → marquee → **funnel** → "MotoGo ti píše" (unread) → Tvůj klub → Moje zážitky → Vybrali jsme ti (routes near the **last-used** branch, or Mezná without history) → Pobočky → Tvoje linka.
  - "Kdy jedeš příště?" pill and "Motorky pro tebe": **hidden** (inside the funnel).
- **S10:** Header → marquee → **review card (light, §5.4)** → funnel → … (as S0).
- **S1–S9:** unchanged from DESIGN_V2, except that the "Kdy jedeš příště?" pill gets the calculator button (§3.1).

### 4.8 Board (Main) changes

- `ticketState` options: "S0 · Bez rezervace — nabídka jízdy" (**default**), S1–S9 as v2, "S10 · Po jízdě — hodnocení + nabídka".
- New props:
  - `historie` (boolean, default false; "Zákazník už s námi jel"), which shows the "Znovu" card first.
  - `stavDat` (§7.7).
  - The `levelUpDemo` default stays "+1 rank (jízda dokončena)": it is the natural moment after a completed ride.

---

## 5. Review card (after a completed ride)

### 5.1 Rules

- **No review gating:** for 1–5★, every customer sees the **same two options, in the same order and the same look** (`RatingFollowUpTile` is shared). Google prohibits gating.
- Google: `app_settings.google_review_url`, fallback `https://g.page/r/CUmeYvk-sNf6EBM/review` (`reservation_provider.dart`).
- The private option goes to the customer's own `message_threads` thread (subject "Zpětná vazba k jízdě #XXXXXXXX"; the message starts with "★★☆☆☆ 2/5"). Velín reads it in Zprávy → Hodnocení. It is never written to the public `reviews` table.
- Stars are stored in `bookings.rating` / `rated_at`. They can be changed any time, and the last tap wins.

### 5.2 Exact strings (cs; the other 7 languages already exist in `translations_ext_36_ride_feedback.dart`)

| Key | cs |
|---|---|
| `ratingTitle` | Hodnocení jízdy |
| `rfHowWasRide` | Jak se ti jelo? |
| `rfTapToRate` | Klepni na hvězdičku a ohodnoť jízdu |
| `rfYourRating` | Tvoje hodnocení {n}/5 (+ " · {datum}" once saved) |
| `rfChangeHint` | Hodnocení můžeš kdykoli změnit klepnutím na hvězdičky. |
| `rfThanksTitle` / `rfThanksSub` | Díky za tvoje hodnocení! / Chceš nám k tomu ještě něco napsat? |
| **`rfGoogleBtn`** / `rfGoogleCaption` | **Napiš nám recenzi** / Veřejná recenze na Googlu |
| **`rfImproveBtn`** / `rfImproveCaption` | **Napiš nám přímo, co máme zlepšit** / Zpráva přijde rovnou našemu týmu |
| `rfSheetInfo` | Zpráva přijde přímo týmu MotoGo24 a nikde se nezveřejní. Odpovíme ti tady v aplikaci ve Zprávách. |
| `rfSheetHint` | Co můžeme udělat líp? Napiš cokoli – kritiku, nápad i pochvalu. |
| `rfEmpty` | Napiš nám prosím aspoň pár slov. |
| `rfSentTitle` / `rfSentLine` / `rfOpenThread` | Odesláno, díky! / Zprávu máme – odpověď najdeš ve Zprávách. / Otevřít konverzaci |
| `rfSendFailed` / `rfLinkFailed` | Zprávu se nepodařilo odeslat. Zkus to prosím znovu. / Odkaz se nepodařilo otevřít. |
| toasts | ⭐ "Díky" + "{n}/5 hvězdiček" after rating; ⚠️ `ratingFailed` "Hodnocení se nepodařilo uložit" |

### 5.3 Dark variant: the completed Reservation (CO TEĎ "Dokončeno")

This is today's `ResRatingCard`, restyled to v2 tokens.

- **Container:** gradient `#0E2A1C → #1A2E22`, r16, padding 16.
- **Header:** 44 px badge (star; one `ping` until the first rating, then static) + "Hodnocení jízdy" 15/800 white + subtitle 12/700 `#B8D4C6`, which cross-fades between "Jak se ti jelo?" and "Tvoje hodnocení 4/5 · ne 18. 10.".
- **Stars:** 5 × 40 px `#F59E0B` (off `white@.25`). The tap wave pops 1 → 1.42 → 1 (560 ms, elastic) with a 60 ms stagger per selected star, + `selectionClick`.
- **Hint:** 12/600 white@.8 → 11/600 white@.55 after rating.
- **After rating:** the follow-up expands (`AnimatedSize` 380 ms):
  - a divider;
  - the line "Díky za tvoje hodnocení! / Chceš nám k tomu ještě něco napsat?" (a line icon replaces the 🙏 emoji, per the v1 icon rule);
  - **two equal tiles**, min-h 84, r18, white@.08, border white@.16, 40 px white circle (Google "G" mark / line icon "message-edit" `#0D6E0D`), title 14/800 white (2 lines in every language), caption 11/600 white@.6, neon chevron;
  - the tiles reveal with a 120 ms stagger.
- **Below the card:** rank CTA "ZNOVU REZERVOVAT" (unchanged; the screen's one primary).
- **Sent note** (after the feedback was sent): neon-tint note "Zprávu máme – odpověď najdeš ve Zprávách." + link "Otevřít konverzaci" → `/messages/:id`.

### 5.4 Light variant: Home (S10, above the funnel)

- White card r16, `shCard`, padding 16.
- Header row: 36 px star tile (`#FFF4E0` / `#8A4B00` star) + "Hodnocení jízdy" 15/800 `#1A2E22` + sub "Husqvarna 701 SM · pá 16.–ne 18. 10." 12/700 `#4A6B5A`.
- Stars 36 px (off `#D6DFDA`).
- Tiles on light: bg `#F3FBF7`, border `#D4E8E0`, title 14/800 `#1A2E22`, caption 11/600 `#4A6B5A`, chevron `#0D6E0D`, same order and size.
- ✕ "Skrýt" (44 px, top-right): hides it for this booking (new; owner decision).
- **Shown** while the latest completed booking ended ≤ **[14] dní** ago (owner) AND (not rated, OR rated within the last 24 h so the follow-up stays reachable).
- Never more than one review card.

### 5.5 "Napiš nám přímo, co máme zlepšit" sheet (today's `ride_feedback_sheet.dart`)

- Light sheet r22.
- Header: line icon + title `rfImproveBtn` + "{motorka} · #XXXXXXXX".
- Lock note `rfSheetInfo` (line lock icon).
- Textarea (hint `rfSheetHint`, counter 0/2000).
- "Odeslat" — the sheet's primary (rank CTA; keyboard up: sticky above the keyboard).
- Errors as toasts.
- Success closes the sheet + toast 💬 `rfSentTitle` / `rfSentLine` + the sent note in the card.

### 5.6 Board changes

- **Reservation `stav = Dokončeno`:**
  - Replace the `co.rate` stars + "Ohodnotit na Google ›" with §5.3.
  - Remove the 1–3★ / 4–5★ toast split (line 1353), which is gating.
  - Action row: `Google` → `Jízdy` (→ "PROJETÉ JÍZDY").
  - History rows keep "Hodnoceno · {n} z 5".
- **Main S10:** §5.4 + funnel.
- **RankStyly mini app:** "Ohodnotit na Google ›" → §5.3 compact.

---

## 6. Level-up: storyboard of the EXISTING celebration (board `Oslava.dc.html`)

**Owner: "pozor lvl up video neměň".** Nothing below changes the app. Everything is traced to `loyalty_levelup_overlay.dart`, `loyalty_provider.dart` and `main.dart` as of 2026-10-15.

### 6.1 What it is

- **Global watcher:** `LoyaltyLevelUpWatcher` in `MaterialApp.builder`, above every route, including screens without the nav (login, payment, success).
- **Detection:** `get_loyalty_status` returns a level above the **baseline**.
  - The baseline is the server's `loyalty_get_celebrated()` (5 s timeout).
  - Otherwise it is local SharedPreferences `mg_loyalty_last_level_<uid>`.
  - First observation (server 0 or nothing local): the current level is recorded **without** a celebration.
- **One celebration per jump:** `gained = level − baseline`, shown as "+N". Several level-ups are merged into one celebration. **N ≥ 2 = "turbo"** (MIMOŘÁDNÝ POSTUP).
- **Personal media:** RPC `get_loyalty_celebration_motos` (6 s timeout, else none). `motos[0]` = the bike of the **last completed booking**: its `videos[]` play one after another, muted, then its `image_url`.
  - Example: Husqvarna 701 SM has 5+ MP4s in `media/motos/b850929a…/videos/`.
  - Fallback without history: the RPC returns a showcase fleet bike (`is_personalized=false`), and the app does not check that flag (L7).
- **Persistence:** written **only after** the dialog closes: prefs level + colour (`mg_loyalty_last_color_<uid>`), then RPC `loyalty_advance_celebrated(level)` (server GREATEST).
  - So a kill mid-video catches up later.
  - On a new device or after a reinstall, it is shown once (server baseline).
- **Blocked** (nothing written, catches up later): while `onboardingOverlayActiveProvider` (language / permission / intro overlays) or `paymentScreenActiveProvider`.
- **Latch:** `_showing` + `loyaltyPollPaused` prevent two dialogs.

### 6.2 Triggers (today; this is the "guaranteed" mechanism)

| # | Trigger | Code |
|---|---|---|
| 1 | **Any touch anywhere** (global `Listener.onPointerDown`) → `maybeRefreshLoyalty` (throttle **45 s**; skipped on the payment screen and during a celebration) | `main.dart:387–389`, `loyalty_provider.dart:248–280` |
| 2 | **App resume** → reset throttle + force refresh | watcher `didChangeAppLifecycleState` |
| 3 | **Reservations changed** (`reservationsProvider`) → force refresh | watcher `ref.listen` |
| 4 | **3-minute poll**, foreground only | watcher `Timer.periodic` |
| 5 | Any settled `loyaltyStatusProvider` emission (Home / Profil / screens that read it) | watcher `ref.listen` |
| 6 | Navigator not ready yet → one retry after 800 ms | `_maybeCelebrate` |

### 6.3 Timeline (master clock T = **67 s** = the music cut 0:25–1:32; reveal anchor `rs` = 1.4 s)

| t (s) | What happens |
|---|---|
| 0.00 | Dialog route fades in (250 ms, transparent barrier, not barrier-dismissible). Background radial `#16241B → #070E09` (centre 0,−0.4). **Music** `assets/levelup_music.mp3` starts once (volume 1.0, mixes with other audio). **Montage** starts: video 1 of the bike (cover, muted) once it is initialised; without videos, the photo with Ken Burns 1.00 → 1.14 over 9 s. Cinematic scrim black .55 → .10 → .30 → .88 (stops 0 / .30 / .55 / 1). |
| 0.18–0.90 | Logo column fades in. Logo = real `assets/logo.webp` 92 × 92 r22 inside a 4 px ring r26 in the **old** rank colour (`mg_loyalty_last_color_<uid>`, default `#9CA3AF`), centred at alignment (0, −0.12). |
| 0.20–2.60 | **Light beam** sweep (warm `#FFE9AA`, α .16, half-screen wide, tilted 0.12 rad) left → right. Turbo: 6 speed lines at y 42 %. |
| 0.40–2.40 | Logo scale .6 → 1 (`elasticOut`). Glow pulse loop 1.1 s (blur 30 → 54 px; turbo 36 → 66), soft black spotlight 300 px behind. |
| **1.40** | **Reveal.** Ring colour lerps old → **new** over 1.40–4.40. White flash α .45 (Legenda warm), peaking ~2.2 s, gone by 3.8 s. **Burst** 1.40–4.80: 46 particles (turbo 90) in the rank colour, every 3rd white (Legenda gold / orange), from the emblem centre (y 42 %). Turbo: gold shock ring 1.40–4.40. |
| (with logo) | **Kicker** under the logo: "NOVÝ RANK" 11/900 ls 5 white@.9; turbo "MIMOŘÁDNÝ POSTUP" 13/900; Legenda `#FFE7A0`. |
| 1.70–3.80 | **Bottom texts** fade in and rise 22 px (padding 26, bottom 34 + safe area): rank name UPPERCASE 30/900 ls 1.2 in the rank colour with a double glow (Legenda: gold gradient text) · 12 · "Tvoje sleva {pct} % platí napořád" 16/800 white · 7 · "Základní výhoda navždy — jen pro tebe v aplikaci. Díky, že jezdíš s MotoGo24." 12/600 white@.72 · 13 · "TVŮJ STROJ · {značka model}" 10/800 ls 1.4 rank colour@.85 (only with a bike) · 22 · button. |
| 2.30–4.00 | **"+N" badge** pops (`elasticOut`), top-right of the logo (−12 / −16): pill, rank colour → 25 % darker gradient, 2 px white border, glow, "+1" 17/900. **Always shown, also for +1.** |
| 3.00–4.60 | **"Pokračovat"** fades in: pill (padding 34 / 13) in the rank colour (Legenda gold gradient), glow rank@.5 blur 18, 14/900, text dark or white by luminance (> 0.5 → `#0F1A14`). Tap = close. |
| 4.6 → 62 | Steady state: the montage plays the bike's remaining videos one after another; the logo glow pulses. |
| **62.0** | Last 5 s: the main photo is **forced** (Ken Burns). |
| **67.0** | Music ends → the dialog closes automatically. Then the level and colour are persisted and the server advances. Any earlier "Pokračovat" (or the system back gesture, standard dialog behaviour) does the same. |

### 6.4 Keyframes for the board (each drawn as a real 390 × 844 frame, computed from the same `_seg` formulas)

Sample: rank prop 3 → +1 → **4 Stálý jezdec** (`#4ADE80` → `#22C55E`), bike Husqvarna 701 SM (real poster `mq22a7zapb2x-1000003421.jpg`, video 1 `videos/mqm81u9nngpu-1000003692.mp4`).

| K | t | Frame |
|---|---|---|
| K1 | 0.3 s | Dark scene, video starting, beam entering left, logo at 15 % opacity, small, old green ring |
| K2 | 1.0 s | Logo grows (overshoot), beam mid-screen, old ring, kicker visible |
| K3 | 1.4 s | **Reveal:** flash rising, ring starting to mix, first particles |
| K4 | 2.2 s | Flash peak, particles mid-flight, name rising from below (40 % opacity) |
| K5 | 3.0 s | "+1" popping, ring ~50 % new, texts in, "Pokračovat" starting |
| K6 | 4.6 s | **Settled:** new ring, +1, "STÁLÝ JEZDEC", "Tvoje sleva 4 % platí napořád", note, "TVŮJ STROJ · Husqvarna Husqvarna 701 SM" (as rendered today, see L1), Pokračovat |
| K7 | ~20 s | Montage: a later video of the bike behind the same composition |
| K8 | 62 s | Last 5 s: main photo forced |
| K9 | 67 s | Auto close → back to the screen he tapped; persisted |

### 6.5 Variants (board prop `postup`, `medium`, rank)

| Variant | Differences |
|---|---|
| +2 (výhra měsíce, bonus +4 points) | Kicker "MIMOŘÁDNÝ POSTUP" 13/900, 90 particles, gold shock ring, 6 speed lines, "+2" |
| Legenda (to 20) | Ring gold gradient (`legendGradientColors`), title gold gradient text, gold / orange particles, warm flash, gold "Pokračovat" with `#241A06` text |
| Jen fotka (bike without videos) | Photo with Ken Burns from 0 s |
| Bez motorky (RPC empty or timed out) | Dark background only, no "TVŮJ STROJ" line |

### 6.6 Texts in 8 languages (shipped keys; `translations_ext_10_loyalty.dart`, uk in `translations_uk_ext_b.dart`)

| | NOVÝ RANK | MIMOŘÁDNÝ POSTUP | Tvoje sleva {pct} % platí napořád | TVŮJ STROJ | Pokračovat |
|---|---|---|---|---|---|
| en | NEW RANK | EXCEPTIONAL JUMP | Your {pct} % discount is yours for good | YOUR RIDE | Continue |
| de | NEUER RANG | AUSSERGEWÖHNLICHER AUFSTIEG | Dein Rabatt von {pct} % gilt für immer | DEINE MASCHINE | Weiter |
| es | NUEVO RANGO | ASCENSO EXCEPCIONAL | Tu descuento del {pct} % es para siempre | TU MOTO | Continuar |
| fr | NOUVEAU RANG | ASCENSION EXCEPTIONNELLE | Ta remise de {pct} % est acquise pour toujours | TA MOTO | Continuer |
| nl | NIEUWE RANG | UITZONDERLIJKE SPRONG | Jouw korting van {pct} % geldt voor altijd | JOUW MOTOR | Doorgaan |
| pl | NOWA RANGA | WYJĄTKOWY AWANS | Twój rabat {pct} % obowiązuje na zawsze | TWOJA MASZYNA | Kontynuuj |
| uk | НОВИЙ РІВЕНЬ | НАДЗВИЧАЙНИЙ ПРОГРЕС | Ваша знижка {pct} % діє назавжди | ВАШ МОТОЦИКЛ | Продовжити |

(+ `loyaltyValuedNote` per language in the same file.) The board's `jazyk` prop swaps these strings, so the de kicker can be checked for wrapping at 13/900.

### 6.7 Board replica `shared/levelup-classic.html` + `.js` (replaces `shared/levelup.*` in **every** board)

- **Same call shape** as v2, so the boards change little: `const LU = levelUpVals({ P, S, set, reduced: rm, blocked, bike, boardH: H })`. It returns `{ show, tap, check, level, priceLevel, landCls, congrats, entry, … }`.
- **Behaviour** (faithful):
  - With `levelUpDemo` on, the next root tap opens a 390 × 844 overlay at the tapped viewport.
  - It plays 0–5 s with the real timings (CSS one-shots with the delays of §6.3; the glow pulse 1.1 s is the only loop), then holds K6.
  - A board-only annotation pill "Ukázka: v appce ~67 s s hudbou a videi motorky" sits at the top, dashed yellow, clearly not app UI.
  - "Pokračovat" closes. `blocked` defers exactly as today: only onboarding overlays and payment block. The Booking board's charging state = payment.
- **No** tier title card, ring stepping, reason line, gear line, "Zvuk oslav" toggle, or theme hold.
- The board theme (`rk`) switches to the new level when the overlay opens (as in the app: the status refresh recolours the logo ring before or behind the dialog).
- Prices use the new level at once.
- `reduced`: shows K6 statically. **App today: no reduced-motion branch**; the board shows a note (L4).
- **Oslava board** (§9): a full-size live phone + scrubber prop `cas` (0–67 s) + the 9 keyframes as a 2-column strip (scale .42, captions 11/700) + trigger and persistence diagrams (§6.1–6.2) + variants + L-list.

### 6.8 Known gaps: listed for the owner, **no change without an explicit OK**

| # | Gap (verified) | Minimal fix, if approved |
|---|---|---|
| L1 | "TVŮJ STROJ · {brand model}" doubles the brand for **25 of 27** bikes, because `model` already contains it (e.g. "Husqvarna Husqvarna 701 SM") | Show `model` when it starts with `brand` |
| L2 | "Pokračovat" / "+N" text picks white below luminance .5 → 2.1–3.8:1 on 12 of 20 ranks (e.g. 4 `#22C55E` 2.28) | Choose the higher-contrast of `#0F1A14` / white (same as §0.3) |
| L3 | Customers on 13–16 when the recolour SQL lands see one old-purple → new transition (stored last colour) | Map old → new hex when reading `mg_loyalty_last_color_*` |
| L4 | No reduced-motion handling (OS setting or "Omezit animace") | Static K6 card, music unchanged or off (owner) |
| L5 | Not deferred over navigation (`/route-nav*`), document scan, the handover signature or full-screen codes; only onboarding overlays and payment block | Add those to `_blockedByOverlay` (catches up as today) |
| L6 | "Pokračovat" is tappable while invisible (0–3 s; `Opacity`, not `IgnorePointer`). A stray tap near the bottom centre closes the celebration, which then counts as seen. | `IgnorePointer` until opacity > .5 |
| L7 | A non-personalised showcase bike (`is_personalized=false`) is still labelled "TVŮJ STROJ" | Hide the line when not personalised |
| L8 | `loyalty_get_celebrated` / `loyalty_advance_celebrated` and `profiles.loyalty_celebrated_level` exist live (`live_schema.sql`) but are **missing from STATE_2/3** | Document them (no SQL) |

---

## 7. Detail pass: tokens and concrete corrections per board

Measured on 2026-10-15 from each board's own CSS (shared rank CSS excluded) with `scratchpad/v21spec/{fonts,spacing,offscale_sel,smallsel}.py`.

### 7.0 Shared tokens (all boards and the Flutter port)

- **Type scale (Montserrat; numbers tabular):**

  | Size | Weight / line height | Use |
  |---|---|---|
  | 32 | 900 / 1.0 | Display: totals |
  | 28 | 800 / 1.1 | H1: bike name on catalogue / detail |
  | 22 | 800 / 1.2 | H2: screen titles, funnel and calculator titles |
  | 20 | 800 / 1.2 | H3: greeting, hero card title, sticky value |
  | 17 | 800 / 1.25 | Section titles, card prices |
  | 15 | 800 / 1.3 | Card and row titles |
  | 14 | 600 / 1.45 | Body |
  | 12.5 | 600 / 1.4 | Small |
  | 11.5 | 700 / 1.3 | Meta; eyebrow 11.5/800 UPPERCASE ls .06em |
  | **11** | 700 | **Minimum** |

  - **Button labels:** 14.5/800 (CTA), 13.5/800 (sticky / compact).
  - **Fixed exceptions:** code digits 24/900 and 48/900; calendar day price 10/700; nav per DESIGN_V2 §4.1.
  - **Forbidden elsewhere:** 9.5, 10, 10.5, 12, 13, 16, 18, 19, 26, 34. Snap: 12 → 12.5 (or 11.5 for meta), 13 → 12.5 (secondary) or 14 (body), 16 → 15 or 17, 18 → 17 or 20, 19 → 20, 26 → 28, 34 → 32, ≤ 10.5 → 11.
  - **Weight 900** only for ≥ 20 px numerals and digit badges.
- **Spacing scale:** 2 · 4 · 6 · 8 · 10 (tile and grid gaps only) · 12 · 16 · 20 · 24 · 32 · 40.
  - Constants: status bar 47, home indicator 34, nav 64 + 34.
  - Rhythm: page gutter 16; between sections 24; section title → content 12; inside cards 12; card padding 16; dark hero padding 20 / 16.
  - Snap: 3 → 4, 5 → 4 or 6, 7 → 8, 9 → 8, 11 → 12, **14 → 12 (inline) or 16 (card padding)**, 18 → 16 or 20, 22 → 24, 26 → 24, 28 → 32, 30 → 32.
- **Radius scale:**

  | Radius | Use |
  |---|---|
  | 6 | Tags |
  | 8 | Map chips, small tiles |
  | 10 | Thumbnails, 36 tiles |
  | 11 | Calendar day only |
  | 12 | Sticky / action buttons, 48 tiles |
  | 14 | Buttons, inputs, choice chips |
  | 16 | Cards |
  | 18 | Receipt, calendar box, review tiles |
  | 20 | Dark hero |
  | 22 | Calculator card, sheet tops |
  | 24 | Header bottom |
  | 999 | Pills |

  2 px is allowed only for bars and segments. 3, 4, 5, 7, 9, 26, 34 and 36 snap to the scale.
- **Icons:** one line set, 24 grid, `fill:none`, round caps.
  - Sizes **16** (inline, chips), **20** (rows, buttons), **24** (nav, tiles, header buttons, feature).
  - Stroke 2. Check marks 2.5. Feature icons ≥ 26: 1.8.
  - No emoji in chrome. Brand marks only official (Google "G", Apple Pay, Google Pay).
- **Colour:** only the v1 §2.1 palette + rank tokens. Named additions:
  - `fav` `#FF5A5F` (favourite heart; same look, now a token)
  - `starOn` `#F59E0B` (rating stars, as in the code; the v1 spec's `#FFB400` is replaced to match the app)
  - Brand colours only inside brand marks.
- **Shadows:** `shCard`, `shDark`, `shCurrent`, `shGlow` (rank glow comes from rank tokens), `shSticky`, `shSheet`, `shReceipt`, `shIcon`. Nothing else.
- **Motion tokens:**

  | Token | Value |
  |---|---|
  | press | 150 ms |
  | color | 180 ms |
  | tab | 210 ms |
  | pop / sheet / sticky / thumb | 300 ms |
  | hero | 350 ms |
  | enter | 450 ms |
  | reveal | 550 ms (70 ms stagger) |
  | scanOnce | 600 ms |
  | connector | 700 ms |
  | path | 900 / 1 600 ms |
  | Ken Burns | 8 s one-shot |
  | toast | 2.8 s (300 in, 2.2 s hold, 300 out) |
  | Loops | glow 2.2 s; shine 3.2 → 2.6 s by step; tier fx (sheen 4.8, glint 3.6, edge 4, ember 4.4); ping 1.8 s; scan 3.6 s; shimmer 1.2 s (loading only) |

  Snap off-token durations: .05 / .1 / .12 → 150; .2 / .22 / .25 → 180 or 300; .28 / .32 / .34 / .35 / .4 → 300 (or 350 for Hero); .5 → 450 or 550; .7 / .8 / .9 → 700 or 900; 1.25 / 1.4 / 2 / 2.4 / 3 s → the nearest loop or path token; 2.9 s → 2.8 s.
- **States (every data screen):** Loaded · Loading (skeleton, one shimmer) · Error (text + "Zkusit znovu") · Empty (existing copy) · Offline = the app's global `OfflineGuard` (`noInternet` "Žádné připojení k internetu", `offlineDesc`, `retryBtn` "ZKUSIT ZNOVU" — vykání, existing strings unchanged). All boards get the board prop `stavDat` (§7.7).
- **Transitions between states:** content swap = `enter` cross-fade; expand / collapse = `AnimatedSize` 300 + chevron rotate 180; sheet 300; focused-flow push 300 (nav slides out 110 %); tab fade-through 210; Hero 350 only inside the shell. Never swap layout without one of these.
- **Alignment:** 4 px baseline grid. Icons optically centred in their tiles. Cards left-aligned. Amounts right-aligned tabular in receipts and lists. Horizontal chip rows start at the 16 gutter and end with 16 scroll padding. Every tappable ≥ 44 × 44. Focus ring neon 3 px.
- **Port checklist · no purple (both trees, added 2026-10-16):** the boards contain no purple, but porting 1:1 would bring `#7C3AED` back from the app code. Replace it in **both** `motogo-app-flutter` and `motogo-app-flutter-ios`: `features/routes/routes_map_picker.dart:22` (`kRoutesMapPalette` = green `#1A8A18`, blue `#1D4ED8`, red `#E11D48`, orange `#D97706`, **violet `#7C3AED`** → replace the violet entry with petrol `#19A2B4`, the TrasyHub note's "zelená, oranžová, petrolejová"; `#E11D48` reads rose — owner may prefer `#DC2626`) and `features/reservations/widgets/res_modification_history.dart:204` and `:264` (modification-history type colour → a non-purple token, e.g. petrol `#19A2B4`). Check with `grep -rn "7C3AED\|8B5CF6\|A855F7\|D946EF\|EC4899\|6366F1" lib/` in both trees before the release (owner decision §10.9 only covers whether the map line may stay violet — default: remove).
- **Port checklist · FabAvoid on every shell screen (added 2026-10-16):** the boards demo FabAvoid v2 (DESIGN_V2 §4.2) on Domů, Motorky, Kalkulačka and Rezervace, and dock the AI into the sticky bar on Detail and Rezervace expres. In the port the same function runs on the PROFIL and TRASY tabs too: wrap row chevrons, switches, hearts, the ride share / upload buttons, „Navrhnout trasu“ and the list end buttons as `tap`; the Profil SOS row as `sos`; every primary button (ZVOLIT TRASU – NAVIGOVAT, Uložit, Odeslat) as `cta`; and give each scroll view a bottom pad of nav 98 + 56 + 12 so the last row can always scroll above the button.

### 7.1 Main (Domů)

1. Default state → S0 funnel (§4); S10 → review card + funnel (§5.4); hide "Kdy jedeš příště?" and "Motorky pro tebe" in S0 and S10; calculator button on the pill in S1–S9.
2. Remove S10 "Ohodnotit na Google" + "Díky, [přezdívka]! Tvoje hodnocení si přečteme." (gating-adjacent, not code text).
3. **Type:** 17 sizes / 83 weight-size combos → the scale.
   - `.hcnt` 10.5 → 11/800 (bell count).
   - `.half i` 10 → 11/900 in an 18 px disc.
   - `.nxr-i b` 10.5 → 11.
   - **12 px** (16 rules: `.hd-top .sos`, `.nd.w`, `.chd b`, `.pk .pk-l`, `.cl-s`, `.tl-l`, `.tl-v small`, `.mc-br`, `.mc-pr s` …) → 12.5 or 11.5.
   - **13 px** (12: `.sos`, `.nick-l`, `.tk-dt`, `.s0-h p`, `.code-t b`, `.sosc`, `.tk-tx`, `.tk-lk`, `.pill span` …) → 12.5 or 14 (SOS pill label stays 13.5/800 as a button label).
   - `.ring b`, `.mc-n` 16 → 15 / 17.
   - `.tl-v b` 18 → 17.
4. **Spacing:** 88 of 276 values are off-scale.
   - **10 px ×34** (`.gr-row`, `.greet`, `.hd-top.s .lg-row` …) → 8 or 12.
   - **14 px ×26** (`.sb`, `.tk-b` …) → 16 for card padding, 12 inline.
   - 3 / 5 / 7 / 9 / 11 / 18 → scale.
5. **Colour:** off-palette `#5D7B6B` ×4 → `#4A6B5A`; `#F3F6F4`, `#DDEFE5` → `#F3FBF7`, `#E6F5EE`; `#FF7878`, `#FFD9D9`, `#FF9B9B` → `errDark` / `errLight`; `#FFF4D6`, `#F3E9C8` → `warnBg #FFF4E0`.
6. **Radii:** 15 values → the scale (2, 4, 5, 9 out).
7. **Shadows:** 36 distinct → the 8 tokens.
8. **Durations:** `.25 .4 .5 .9 1s 1.6 2.9 8 9 s` → tokens (toast 2.9 → 2.8).
9. Level-up demo → `levelup-classic` (§6.7); the post-celebration note and deník entry stay (Home content).
10. Add `stavDat` (Načítání: header + funnel skeleton; Chyba sítě: section-level retry; Bez připojení: OfflineGuard).
11. Board height 3100 → **3300** (S10 = review + funnel is the tallest).

### 7.2 MotoKatalog (Motorky)

1. Add the **`.km` switch** under header row 1 (§3.1; texts §0.4); in this board, "Spočítat cenu" shows a toast "Otevírám kalkulačku…" and points to the Kalkulačka board.
2. **Type:** `.fc.fb b`, `.pl`, `.gw` 10.5 → 11. 12 px ×8 (`.dpm small`, `.ntc`, `.av`, `.bc`, `.pv s`, `.rzb`, `.rzr`, `.po small`) → 12.5 or 11.5. 13 px ×5 (`.dpm`, `.pv i`, `.rst`, `.cbx`, `.toast`) → 12.5 or 14. `.fsh-h h2` 18 → 17. `.pv b` 26 → 28.
3. **Spacing:** 36 of 115 off-scale (10 px ×16 in `.rkb`, `.lu-gear`; 13 px in `.fc`, `.oc`; 5, 7, 11, 34) → scale.
4. **Colour:** `#557264` → `#4A6B5A`; `#FF5A5F` → token `fav`; `#C4320A` → `errLight`; `#F3E9C8` → `warnBg`.
5. **Radii:** 2, 3, 9 → scale.
6. Keep: full-screen cards, one looping CTA (first card in view), Ken Burns one-shot. Card copy "Tvoje cena za 3 dny" (exact total; "od" only without dates).
7. Add `stavDat` (skeleton cards; error; offline). Height 2360 → **2420** (+switch).

### 7.3 MotoDetail

1. **Type:** `.vkc small` 10.5 → 11 (V kostce labels). `.cd .cp` 10 → allowed (calendar price). 12 px ×8 (`.sus`, `.lb`, `.xl`, `.dch`, `.rcb`, `.rs`, `.lts`, `.fgh`) → 12.5 or 11.5. 13 px ×6 (`.gls .pl`, `.ofr .oh`, `.tls`, `.lnk`, `.ndt`, `.toast`) → 12.5 or 14. `.sht2` 19 → 20. `.tot` 34 → **32** (display token; the total must match Booking and the calculator).
2. **Spacing:** 65 of 192 off-scale (10 px ×26 in `.sht`, `.stile`, `.npl`; 14 ×9; 18 ×8 in `.tb`, `.ndt`; 3, 5, 9) → scale.
3. **Colour:** `#123321`, `#EAFBEA`, `#BEE8C6`, `#E8F1EC` → palette (`#0E2A1C`, `checkedBg #E8FCE8`, `#9FDCB0`, `#EEF7F2`).
4. **Icons:** 14 / 16 / 22 px mix → 16 / 20 / 24.
5. **Radii:** 2, 4, 5, 7 → scale.
6. Keep the sticky REZERVOVAT (60, rank) and the mini AI FAB.
7. Add `stavDat` (hero skeleton + "Motorku se nepodařilo načíst · Zkusit znovu").

### 7.4 Booking (Rezervace expres)

1. **Type:** `.hf` **9.5** → 11/900 ½ in a 16 disc. `.dtl2 small`, `.bar2 small` 10.5 → 11. 12 px ×20 and 13 px ×19 → 12.5 / 14 (largest cleanup). `.msht h2` 16 → 17. `.sht`, `.sxp b` 18 → 17 / 20. `.sxt` 26 → 28.
2. **Spacing:** 102 of 301 off-scale (10 px ×47 in `.dg2`, `.ch2`, `.ofr2`; 14 ×17; 5 / 3 / 9 / 18 / 7) → scale.
3. **Icons:** 12 px ticks at stroke 3 (×13) → 16 / 2.5. 11 / 14 / 17 → scale.
4. **Colour:** `#C4161C` → `errLight #E5484D` (text) / `#B42318` (on light); `#EFF8F3`, `#FBFEFC`, `#F0FCF2`, `#FFFCF5` → `#F3FBF7`, `#FBFDFC`, `#E8FCE8`, `#FFF4E0`; `#7FA894` → `#6C8A7B`; `#FFE2A3`, `#FFD0D0` → `warnLine`- / `errDark`-tints. Google brand colours only inside the G Pay mark.
5. **Radii:** 2, 4, 7 → scale. Durations: 19 distinct → tokens.
6. Accept entries prefilled from the funnel and the calculator (§3, §4): "Termín a předání" shows the incoming choice (pickup 09:00 vs 12:00) collapsed with Změnit; nothing else changes.
7. Level-up demo blocked while charging (= payment, as in the app).

### 7.5 Reservation (Správa rezervace)

1. **Dokončeno:** review card §5.3. Remove the star-dependent toast (line 1353) and the "Ohodnotit na Google ›" link. Action row `Google` → `Jízdy`.
2. **Type:** `.ns`, `.c19 b` 10 and `.nl`, `.uk` 10.5 → 11. 12 px ×13 / 13 px ×13 → 12.5 / 14. `.psn`, `.pst b` 16 → 15 / 17. `.hh` 19 → 20.
3. **Spacing:** 51 of 153 off-scale (10 px ×27 in `.hh`, `.due`, `.cdx`; 14, 18, 22, 30) → scale.
4. **Colour:** `#557264` ×10 → `#4A6B5A`; `#5D7D6C` → `#4A6B5A`; `#FFD58A`, `#FFC457`, `#F3E9C8`, `#F3E2BF` → warn tokens; `#FFE1DA`, `#FFB4A8`, `#FFC2BA` → `errDark`-tints; `#EEF2F0`, `#DCE5E0` → `#EEF7F2`, `#DBEAE3`; `#050D08` → `#0A1F14`.
5. Keep codes, timeline, CO TEĎ states, fuel and return copy (VN: "nádrž plnit netřeba, jen nesmí svítit rezerva · vrať ji umytou" ✓).
6. Add `stavDat`. Height 2300 → **2400**.

### 7.6 RankStyly

1. Step 0 re-embed (§0.3) + text edits at lines 1631 / 1632 / 1634 (gem contrast "4,6–7,1 : 1", the "Tmavé drahokamy 12–16" note, VIP "perleťové" → ivory).
2. Replace the level-up mini app's redesigned sequence with a **storyboard card** (K1 / K3 / K6 thumbnails + "Otevřít storyboard" → Oslava board) and the real trigger list (§6.2).
3. Mini-app "Ohodnotit na Google ›" → compact review card (§5.3).
4. Hero stat "0 propásnutých oslav povýšení" → "1× · každé povýšení oslavíš právě jednou" (what the code guarantees: server GREATEST).
5. **Type:** 10 / 10.5 px in `.ovb-tag`, `.lg-t span b`, `.hcnt`, `.bdg`, `.th-cr`, `.me`, `.tgb b`, `.stt-r small`, `.lg-e b` → 11. 12 ×10 / 13 ×12 → scale. 16 / 18 / 19 / 26 / 34 → 17 / 20 / 28 / 32.
6. **Spacing:** 80 of 226 off-scale → scale.
7. **Colour:** `#5C3300`, `#7A1A12` → warn / err tokens; `#1F3529` → `#1A2E22`; `#B8932A` is VIP gold (allowed as a rank token only).
8. Height ≤ 7840; recompute after the mini-app removal (expect ~7000).

### 7.7 Cross-board additions

- **`stavDat` prop** (enum "Načteno" · "Načítání" · "Chyba sítě" · "Bez připojení") on Main, MotoKatalog, MotoDetail, Reservation, Kalkulacka, Profil, ProfilSluzby, Pobocky, Trasy. "Bez připojení" draws the `OfflineGuard` overlay.
- **Toasts:** one style (night glass, r14, 13.5/700, icon 20), `toast` token, z 50, above the FAB.
- **Sheets:** grabber 42 × 5 white@.25 (dark) / `#CFE3DA` (light), r22 top, `shSheet`, title 20/800 + close 40.
- **Empty states:** icon in a 64 disc (`#E6F5EE` / neon@.12 on dark), title 15/800, text 12.5/600, one ghost action.

---

## 8. Web v2 → app mapping (every app screen)

| App screen | Web v2 page / component it mirrors | Taken over | Adapted for native |
|---|---|---|---|
| Bottom nav + AI FAB | Header menu + mobile sticky bar "REZERVOVAT \| MOTORKY"; chat FAB bottom-right; `/kontakt` card "AI ASISTENT 24/7" | Two-action priority (book / bikes); AI always bottom-right | 5 native tabs incl. PROFIL; rank pill; FabAvoid; the AI label stays `aiServiceAgent` (the web persona name from CMS is not ported) |
| Domů header | Web header (logo, "Upravit rezervaci", language, currency) | Logo + quick access to the booking | LogoRow with the rank ring; language / currency → Profil; bookings → Rezervace tab |
| **Domů funnel** | `/` `lp-panel` hero (H1, lead, REZERVOVAT + VYBRAT MOTORKU, assure line, Google rating line, chips, **season note**) + `lp-fleet` (category chips, "Dostupné dnes", "od X Kč/den", REZERVOVAT) | Dark panel card, one strong CTA, season note (same CMS key), fleet cards with availability + price | Personal question, date presets, carousel with **rank price**, one CTA → express booking; rating line not ported (conversion is secondary in the app) |
| Domů Trasy section | `/` `lp-rt` "Kam vyrazit? A kudy jsi jel?" (route draw, stat tiles) | Route-draw animation, stat-tile style | Real routes near the branch, sketch from waypoints |
| Domů Pobočky / Tvoje linka | `/` `lp-brs`; `/kontakt` contact cards | Two-branch cards; Zavolat / Napsat | Compact; "Tvoje linka" copy (Sultan) |
| Motorky | `/katalog` `.km` mode switch, `kf` filter (Typ motorky chips with counts, TERMÍN, FILTRY "ŘP, pobočka…", "24 motorek · Zobrazit"), cards (badge "Dostupné dnes / od 21.10.", h3) | **Mode switch**, filter structure, availability badges | Full-screen photo cards (owner), filter sheet, rank CTA per card |
| **Kalkulačka** | `/katalog` `.kc` (katalog-calc.php, landing-calc-*.js / css) | Steps, segmented branch, bike card, calendar states + prices + pending, receipt, bars, grouped rows, total, average, ½ card, includes, CTA, assure, reset, free list, sticky bar | Rank price, handover / extras step, savings line, one-tap 12:00, express booking; picker sheet instead of a native select; assure wording corrected |
| Detail | `/katalog/:id` moto-detail-v2 (badge, H1, chips Cestovní / ŘP A / Mezná, REZERVOVAT ONLINE + SPOČÍTAT CENU, Základní údaje, Technická specifikace, Ceník půjčovného, `kc--detail`, reviews) | Same information blocks and the in-page calculator | Full-bleed photo hero, "Tvoje jízda" card = SPOČÍTAT CENU, one sticky REZERVOVAT |
| Rezervace expres | `/rezervace` v2 (6 step pills, summary bar "POKRAČOVAT V REZERVACI →", time chips "Doporučené časy (06:00 — 14:00)", size chips, Souhlasy) | Step logic, time chips, size chips, consents | Returning customer: steps already known collapse into "Máme to připravené"; one pay button |
| /success | `/potvrzeni` | Confirmation content | Native success hero |
| Rezervace list / Správa | `/upravit-rezervaci` (edit, storno tiers "Více než 7 dní … 100 %") | Edit options, storno tiers | Ticket, codes, timeline, CO TEĎ, review card |
| Profil header / club | `lp-panel-card` + `lp-chips` | Dark panel with chips | Rank strip (no web equivalent) |
| Pobočky / Pobočka | `/pobocky`, `/pobocky/:slug` (pb-hero, pb-stats, pb-video, pb-info, pb-guide stepper, pb-gear, pb-gallery, pb-map NAVIGOVAT, lp-fleet, lp-cta, pb-other, compare table) | Everything, same order | + "Kontakt a údaje" (app-only data); photos `[fotka pobočky]` until the canvas allows `www.motogo24.cz` |
| Kontakt (Profil → Pomoc) | `/kontakt` | Call / write cards, hours line | Rows instead of cards |
| Dokumenty a smlouvy | `/dokumenty/:slug` | Same legal texts (`loadLegalDoc`, never a stale translation) | In-app viewer |
| Smazat účet | `/smazani-uctu` | Must stay "Profil → Smazat účet" | Dialog; optional link "Co se smaže" |
| Nápověda & FAQ | `/jak-pujcit/faq` | — | External link (unchanged) |
| Jak si půjčit pages (postup, vyzvednutí, převzetí, vrácení ×2, co v ceně, dokumenty, přistavení) | `/jak-pujcit/*` | Texts 1:1 (`procStep*`, `gateCodeHint`, …) | Procedure sheet in the reservation, branch step guide, AI chips; no new screens |
| E-shop / Poukazy | `/e-shop`, `/poukazy` (flag) | Voucher flow look | Behind `eshop_visible` |
| Trasy (all) | `/` `lp-rt` + `.km` switch style | Copy tone, stat tiles, route draw, dark switch | All TRASY screens (the web has none) |
| Review card | — (web `lp-reviews` shows ratings only) | — | App-only, wording per the owner |
| Level-up | — | — | App-only, **unchanged** |

---

## 9. Boards

### 9.1 Board list (canvas; the orchestrator edits `canvas.json`)

Proposed order and x (470 apart), heights and props. Every board has `rank` (int 1–20, default 3) and `reducedMotion` (boolean).

| # | File | Canvas title | H | x | Props (besides `rank`, `reducedMotion`) |
|---|---|---|---|---|---|
| 1 | Main.dc.html | 1 · Domů — tvoje příští jízda | **3300** | 0 | `ticketState` (S0 default … S10), `historie`, `levelUpDemo` (default +1), `jazyk`, `unread`, `rozjetaTrasa`, `dokladyS4S5`, `dalsiRezervace`, `telefon360dp`, `aiTlacitko`, `stavDat` |
| 2 | MotoKatalog.dc.html | 2 · Motorky — celá obrazovka + kalkulačka | **2420** | 470 | as v2 + `stavDat` |
| 3 | **Kalkulacka.dc.html** (new) | 3 · Kalkulačka — jako web, s tvou cenou | **2300** | 940 | `stav` (§3.4: "BMW · 23.–25. 10. · vše vybráno" default, "Bez motorky · jen termín", "Motorka bez termínu", "Jen den vyzvednutí", "Obsazený den v rozmezí", "Mimo limit dní", "Načítání obsazenosti", "Chyba obsazenosti", "Věrnost nedostupná", "Nic nevybráno"), `pobocka` ("Všechny", "Mezná", "Velké Němčice"), `mena` (CZK, EUR, PLN), `jazyk`, `levelUpDemo`, `aiTlacitko` ("V klidu", "Posunuto · lišta s cenou") |
| 4 | MotoDetail.dc.html | 4 · Detail — přehledně, REZERVOVAT | 2240 | 1410 | as v2 + `stavDat` |
| 5 | Booking.dc.html | 5 · Rezervace expres — máme to připravené | 844 | 1880 | as v2 + `prichod` ("Z detailu", "Z nabídky na Domů", "Z kalkulačky") |
| 6 | Reservation.dc.html | 6 · Správa rezervace — kódy, vrácení, hodnocení | **2400** | 2350 | as v2 + `hodnoceni` ("Bez hodnocení", "Ohodnoceno 2★", "Ohodnoceno 5★", "Zpráva odeslána") + `stavDat` |
| 7 | **Trasy.dc.html** (new) | 7 · Trasy — Místa · Trasy · Moje | **2300** | 2820 | `obrazovka` ("Místa", "Místa · výběr do vyjížďky", "Trasy", "Moje · Jízdy", "Moje · Uložené trasy", "Moje · Objevená místa", "Moje · Historie navigace", "Detail místa", "Detail trasy", "Mapa míst", "Mapa tras"), `prihlasen` (bool, default true), `rozjetaTrasa` (bool), `nahravani` ("Ne", "Automaticky (výpůjčka)", "Ručně"), `jazyk`, `stavDat`, `levelUpDemo` |
| 8 | **TrasyJizda.dc.html** (new) | 8 · Trasy — navigace, plánovač, jízdy | **2100** | 3290 | `obrazovka` ("Navigace", "Navigace · dojel jsi na místo", "Navigace · trasa dokončena", "Plánovač trasy", "Výběr míst do trasy", "Detail jízdy · s MotoGo", "Detail jízdy · soukromá", "Navrhnout trasu", "Přidat místo"), `jazyk`, `levelUpDemo` (board shows that it is **not** deferred over navigation today, L5) |
| 9 | **Profil.dc.html** (new) | 9 · Profil — můj klub | **2200** | 3760 | `obrazovka` ("Profil", "Osobní údaje · úpravy", "Věrnostní ranky", "Oprávnění aplikace"), `stav` ("Vše v pořádku", "Chybí doklady", "Probíhá jízda (SOS)", "Nový zákazník", "Načítání", "Chyba načítání"), `platforma` (Android, iOS), `eshop` (bool, default false), `jazyk` (all tile, row and nav labels from `tools/i18n_<lang>.json`, keys PI §5), `levelUpDemo` |
| 10 | **ProfilSluzby.dc.html** (new) | 10 · Profil — zprávy, doklady, faktury, platby | **1800** | 4230 | `obrazovka` ("Zprávy · Oznámení", "Zprávy · Konverzace", "Konverzace · vlákno", "Moje doklady", "Skenování dokladů", "Faktury", "Dokumenty a smlouvy", "Platební metody", "E-shop (vypnutý)"), `doklady` ("Ověřené", "Chybí rub ŘP", "Nic nenahráno"), `platforma`, `prazdne` (bool: empty states), `jazyk`, `stavDat` |
| 11 | **Pobocky.dc.html** (new) | 11 · Pobočky — jako web v2 | **3000** | 4700 | `obrazovka` ("Pobočky", "Velké Němčice u Brna", "Mezná u Pelhřimova"), `jazyk`, `stavDat` |
| 12 | RankStyly.dc.html | 12 · Rank styly — bez fialové | ≤ 7840 (recompute) | 5170 | as v2 |
| 13 | **Oslava.dc.html** (new) | 13 · Povýšení — storyboard (beze změny) | **4000** | 5640 | `postup` ("+1 (jízda dokončena)", "+2 (výhra měsíce)"), `cas` (int 0–67, default 5, "Čas oslavy (s)"), `medium` ("Videa motorky", "Jen fotka", "Bez motorky"), `jazyk` (8) |

### 9.2 In-board screen switching (multi-screen boards)

- **The `obrazovka` prop** sets the **initial** screen. In-board taps navigate like the app, storing `scr` in state:
  - tile → sub-screen with the push motion (slide-up 24 px + fade, 300);
  - back arrow → previous;
  - segment → cross-fade;
  - sheet → sheet.
  - When the prop changes, the state resets to it (pattern: `scKey`, as in MotoDetail `renderVals`).
- **Each screen** is drawn at full length inside the board's inner scroll container (`.pg`). Pinned chrome sits at the artboard bottom: nav (tab screens), sticky bars, FAB.
- **Screens shorter than the board:**
  - Phone-height screens (Navigace, Skenování, maps) are drawn **at 844** from the top.
  - Below them, a light annotation panel (dashed border, "Poznámka k návrhu") lists the screen's other states as small cards. Example: context cards StopReached / RouteDone / Fork / NextStop and the end dialog.
- **Sheets** open from a tap at the tapped viewport (v2 `sheetSt(y)` helper).
- **Toasts** are placed near the tap.
- **Fuzz** every `obrazovka` value, besides the required set (§9.3).

### 9.3 Build and validation

0. **Re-embed the rank colours first** (§0.3), then the RankStyly text edits.
1. Skeleton and DC rules as v2 §13. Holes are dotted lookups only; compute in `renderVals`; `sc-if` / `sc-for` with hints; CSS `sc-if,sc-for{display:contents}`; only Supabase `media/...` images. Branch photos stay `[fotka pobočky]` (`www.motogo24.cz` is not allowed).
2. Helmet order: base CSS → `rank-theme.css` → logo → cta → nav → ai-fab → **`levelup-classic`** CSS → board CSS (with the §7.0 tokens as CSS custom properties at the top of the board CSS: `--fs-*`, `--sp-*`, `--r-*`, `--mo-*`).
3. Script: `rank-theme.js`, `nav.js`, `ai-fab.js`, **`levelup-classic.js`** pasted verbatim; prices from `rankTheme(LU.priceLevel).pct` through the v1 §6 engine (copy `quote()` from MotoDetail; check values §3.3).
4. One looping primary per screen; ≤ 2 loops; default style = end state; reduced motion = `.rm` on the root.
5. Real data: §2.8 routes and places, v1 bike photos and weekly prices (MotoKatalog `F` array), branch codes and phone from `branches`, Husqvarna video for the Oslava board. Personal data is bracketed or marked "ukázka".
6. Validate: `python3 dclint/lint.py <file>` → **LINT OK**; `node dclint/fuzz.js <file> '<props>'` → **fuzz ok** for `{}`, `{"rank":1}`, 6, 10, 17, 19, 20, `{"reducedMotion":true}`, every `obrazovka` / `stav` value, and `levelUpDemo` "+2 ranky (výhra měsíce)" where present. Do not render or screenshot.

### 9.4 Suggested work split

| Builder | Scope |
|---|---|
| A | `shared/levelup-classic.*` + Oslava |
| B | Main (funnel + review card) + MotoKatalog switch |
| C | Kalkulačka |
| D | Profil + ProfilSluzby |
| E | Pobočky |
| F | Trasy + TrasyJizda |
| G | §7 polish on MotoDetail, Booking, Reservation (+ review card), RankStyly |

A goes first (the others paste its output). Everyone else may start in parallel with the v2 `levelup.*` and swap it in at the end.

---

## 10. Owner decisions (v2.1)

1. **Rank colours:** approve the SQL text (`sql/20261015_loyalty_colors_no_purple.sql`) + the app fallback colours + the on-colour text fix. The overlay part (L2) and the one-time purple flash fix (L3) need an explicit OK, because they touch the celebration.
2. **Level-up gaps L1–L8** (§6.8): fix each one or leave it.
3. **Funnel CTA target:** `/booking` express (fewest taps; same label as the Detail sticky) — proposed — or Detail first.
4. **Calculator place:** a mode inside Motorky (web parity) — proposed — or a separate screen.
5. **Home review card:** visible for **[14] days** after a completed ride; ✕ "Skrýt" allowed?
6. **PROFIL optional rows:** AI asistent, Kontakt (+ hours line), Omezit animace, Moje velikosti výbavy (read-only or editable), Firemní údaje, "Nová verze · Aktualizovat", E-mail note (P18).
7. **Branches:** fold the sheet into the branch detail ("Kontakt a údaje") and then delete it; show the live bike count instead of the hard-coded "Max 8 motorek" (P17).
8. **Copy fixes:** P4 scanner badge, P5 docs line, TRASY place-review hint and login prompt, "Historie navigace" as the new name for today's "Moje trasy" tab.
9. **TRASY:** the counts formula ("1 100+ tras · 49 000+ míst" vs the web's "1 000+ / 50 000"); the optional "Půjč si motorku na tuhle trasu"; whether the purple **map line** colour `#7C3AED` (routes map, modification history) should also go.
10. **`/loyalty` ambient sparks loop:** keep or make static (loop budget).
11. **Web copy bug (FYI, outside the app):** CMS `web.landing_katalog.assure` cs "Storno zdarma do 7 dní před začátkem" contradicts "Více než 7 dní před začátkem: 100 %". Proposal: "Storno zdarma víc než 7 dní předem · Bezpečná platba".
12. **Canvas:** allow `www.motogo24.cz` images so the branch photos can be real (carried over from v2 #12).
13. **Level-up contrast and motion (L2 / L4, verifier 2026-10-16):** the faithful replica keeps today's `_onColor` (luminance > .5 → `#0F1A14`, else white), so „Pokračovat“ is 2.10–3.76 : 1 on ranks 4, 5, 6, 11–18 and the button is 42.8 px tall; the shipped overlay ignores OS reduce-motion. Proposal (needs OK, „lvl up video neměň“): pick the higher-contrast of `#0F1A14` / white (min 4.74 : 1), „+N“ stop darkened by .10 instead of .25, vertical padding 14 (44 px), and with `MediaQuery.disableAnimations` show the static final card.
14. **Text scaling (both trees):** `main.dart` forces `TextScaler.noScaling` (WCAG 1.4.4). Proposal: `MediaQuery.textScalerOf(context).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3)` + the nav fit ladder from `nav.js`; check the PROFIL nav label in 8 languages at 1.3.
15. **Data fixes in Velín:** BMW R 1200 GS Adventure — „Nádrž 32 l“ (fuel_tank_l) vs „Nádrž 30 l“ in Výbava, and the typo „6 ti stupňová manuální“ (→ „6stupňová manuální“); Yamaha PW 50 — features say „sedlo 470 mm“ / „37 kg“, the record says 485 mm / 41 kg. The boards show the records as they are.
16. **VIP 17 glow:** ring and halo use `#EF4444`, the same red as SOS. Keep (the board marks it „jen prstenec a záře“), or move the halo to a deeper crimson with the gold frame?
17. **Favourites (♥):** drawn as a proposal only — stored on the phone, listed behind the „♥ Oblíbené“ chip in MOTORKY. Build it, or remove the heart?
