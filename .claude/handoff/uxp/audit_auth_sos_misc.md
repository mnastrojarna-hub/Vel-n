# Audit · auth + SOS + scanner + remaining pages (v2, flag ON) — 2026-11-07

Evidence
- Boards rendered at 390 with Playwright (tool `asm/tools/render_board.js`, parked sheets hidden with `HIDE`): Prihlaseni (Přihlášení new device / returning, Registrace 1–3, Hotovo = MotoWelcomeOverlay, Obnovení hesla 1–3, states 18.2 / 18.3 / 8.10), SOS (18 screens incl. type sheets, Lehká nehoda sheet, Ukončit jízdu sheet, Hotovo ×3, Detail), Profil (Skenování dokladů, výsledek, pomoc po chybách, 11.7 kamera, 11.15).
- App rendered from a scratch copy of the Android tree with the existing harness (`test/v2/render/render_harness.dart`, flag ON, scale 1.0): cs 360×780 + 320×690, de + uk 320×690; 30 cases (login, register s1–s3, reset s1–s3, toast, unknown-email dialog, welcome overlay, SOS start idle/active/2 type sheets/report sheet/fail dialog/location dialog/progress, immobile, breakdown, theft, service, replacement, detail, done ×3, scanner choice + camera). Register / reset steps 2–3 were reached with a scratch-only start-step patch. Icons render as boxes in tests (no Material icon font) — ignored. The harness theme is `v2TestTheme()`; in the app the v1 `ElevatedButton`s are `MotoGoTheme` neon pills (wider text), so the overflows below are at least as bad in the app.
- Contact sheets: `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/uxp/asm/v/*.png` (app), `/tmp/claude-0/-home-user-Vel-n/a6963cc3-5559-53b7-8eeb-5fd2cdb37dae/scratchpad/uxp/asm/b/*_sheet*.png` (boards).
- Both trees: every file of the area is byte-identical (cmp).

Render findings (harness failures, flag ON, scale 1.0)
| Screen | lang / width | Finding | file:line (repo) |
|---|---|---|---|
| Register step 3 | cs 320 | licence-category `DropdownButtonFormField` overflows 6.5 px | features/auth/register_screen.dart:649 |
| Register step 3 | de 320 / uk 320 | same dropdown overflows 66 px / 70 px | register_screen.dart:649 |
| Register step 3 | de 320 | bottom button row overflows 30 px ("REGISTRIERUNG ABSCHLIESSEN" clipped) | register_screen.dart:544 |
| Register steps 1–3 | de, uk 320 | floating labels ellipsized: "Passwort (min. 8 Zeichen)", "Postleitzahl", "Straße und Hausnummer", "Населений пункт / місто", "Номер посвідчення водія" | register_screen.dart:603, 616–621, 640 |
| Reset step 3 | de / uk 320 | "NASTAVIT HESLO" button row overflows 6.3 / 6.6 px | features/auth/reset_password_screen.dart:571 |
`test/v2/auth_fit_test.dart` only checks login + register step 1, so none of these is caught today.

## LC · Coverage (flag ON)

| Page / sheet / dialog / overlay / state | v2 look today | Board | Where |
|---|---|---|---|
| Login `/login` | **NO** (old dark gradient header, vykání, neon pills, emoji 🌐; only status-bar seam) | Prihlaseni · Přihlášení | features/auth/login_screen.dart:230-359, widgets/login_*.dart |
| Login: empty fields / wrong credentials / bio results / offline | **NO** — emoji toasts | Prihlaseni stavy 18.1, 18.3, 8.11, 8.12 | login_screen.dart:110, 128-132, 178-206 |
| Login: unknown e-mail dialog | **NO** — raw `AlertDialog`, neon text button on white | 18.2 (T6) | login_screen.dart:142-165 |
| Login: forced sign-out notice | **NO** — 8 s toast | 8.10 (T3 banner) | login_screen.dart:49-59 |
| Register `/register` steps 1–3 | **partly** — v2 canvas + back disc only; old card, floating labels, Material dropdown, v1 button | Prihlaseni · Registrace 1/3–3/3 | register_screen.dart:443-554, 568-699 |
| Register: validation errors | **NO** — ⚠️ toasts | 18.9 inline | register_screen.dart:205-283 |
| Register: e-mail taken dialog | **NO** — raw `AlertDialog` | 18.7 (T6) | register_screen.dart:127-153 |
| Register: server error | **NO** — ✗ toast 9 s | 18.8 (T2) | register_screen.dart:353-367 |
| Register: discard confirm | yes (`confirmDiscard` v2 look) | T6 | core/widgets/error_feedback.dart:166 |
| Register: date fields (DOB, licence expiry) | yes (v2 fit row) — label still v1 12/700 | — | core/widgets/date_dropdown_field.dart:167-190 |
| Registration welcome (MotoWelcomeOverlay) | **NO** — 2.8 s dark overlay with 🏍️ hero | Prihlaseni · Hotovo | core/widgets/moto_fx.dart:620-705 (caller register_screen.dart:370) |
| Reset password `/reset-password` steps 1–3 | **NO** — old header with "← Zpět na přihlášení" pill (no v2 back seam), vykání, single code field | Prihlaseni · Obnovení hesla 1/3–3/3 | reset_password_screen.dart:188-589 |
| Reset: code sent / errors / success | **NO** — emoji toasts | 18.10–18.14 | reset_password_screen.dart:69-165 |
| Toasts app-wide (`showMotoGoToast`, 131 calls) | **NO** — v1 dark snackbar, emoji glyph, elevation 8 black halo, message white@.5 | T5 | features/auth/widgets/toast_helper.dart:8-71 |
| SOS start `/sos` (idle, active incident, status error) | **NO** — light page, 🆘 emoji title, AI card above the emergency numbers, small white number chips, nonstop line not tappable | SOS · Start | features/sos/sos_report_screen.dart:25-190 |
| SOS: accident type / breakdown type sheets | **NO** — old sheet, emoji rows | SOS · Nehoda/Porucha výběr typu | sos_report_screen.dart:198-240 |
| SOS: report sheet (popis + fotky) | **NO** — old sheet | SOS · Lehká nehoda / Drobná závada | features/sos/sos_report_sheet.dart:22-236 |
| SOS: send progress | yes (`MgProgress` v2 look) | 14.2 (in button) | core/widgets/error_feedback.dart:289 |
| SOS: action failed / location result dialogs | **partly** — v2 T6 frame but 3 identical ink buttons with emoji labels, calls not red | 14.3, 14.7–14.10 | features/sos/sos_feedback.dart:17-71 |
| SOS: location ok / sent without location / photos failed | **NO** — emoji toasts | 14.7, 14.11, 14.4 | sos_feedback.dart:47-50, 75-82; sos_report_screen.dart:316-321 |
| SOS: SosCallButton (in error views) | **NO** — red OutlinedButton with 📞 | — | sos_feedback.dart:86-99 |
| SOS: Vážná nehoda `/sos/accident` | **NO** — tinted header card with back on the RIGHT, amber 11 px step text | SOS · Vážná nehoda · nepojízdná | features/sos/sos_immobile_screen.dart:117-305 |
| SOS: Porucha nepojízdná `/sos/breakdown` | **NO** (same pattern) | SOS · Porucha · nepojízdná | features/sos/sos_breakdown_immobile_screen.dart:120-325 |
| SOS: Krádež `/sos/theft` (+ reported state) | **NO** | SOS · Krádež / nahlášena | features/sos/sos_theft_screen.dart:60-296 |
| SOS: Servis `/sos/service` (+ invoice uploaded) | **NO** | SOS · Servis / faktura nahrána | features/sos/sos_service_screen.dart:110-285 |
| SOS: Náhradní motorka `/sos/replacement` (list, empty, error, address) | **partly** — old gradient header + v2 dark back; rows without photos; v1 button | SOS · Náhradní motorka | features/sos/sos_replacement_screen.dart:170-333 |
| SOS: Hotovo `/sos/done` (all SosDoneType) | **NO** — mint header with emoji, second dark block, near-invisible back disc | SOS · Hotovo ×8 | features/sos/sos_detail_screen.dart:54-280 |
| SOS: incident detail `/sos/done` with active incident | **NO** | SOS · Detail incidentu | sos_detail_screen.dart:283-515 |
| SOS: detail loading / error | yes (`MgStateScaffold`, `MgErrorView` v2 looks) — extra button old (SosCallButton) | 8.6 | sos_detail_screen.dart:34-51 |
| `/sos/payment` | pay_shop group (PaymentScreen) | Booking · Režim platby SOS | router.dart:482 |
| Document scanner `/docs/scan` — choice | **NO** (back disc only) | Profil · Skenování dokladů | features/documents/document_scanner_screen.dart:731-802 |
| Scanner — camera step | **partly** (back disc only, dark style over camera) | Profil · Skenování dokladů | :852-968 |
| Scanner — result success / error | **NO** — black 85 % overlay with ✅/⚠️ | Profil · Skenování · výsledek | :970-1042 |
| Scanner — contact fallback | **NO** | Profil · pomoc po chybách | :1044-1121 |
| Scanner — camera error | **NO** | Profil · 11.7 | :804-850 |
| Scanner — plan loading / done (verifying) | **NO** (raw spinners, ✅) | — | :1193-1219 |
| DocumentCameraScreen | dead code (no caller); its `DocumentFramePainter` is used by the scanner | — | features/documents/document_camera_screen.dart |
| Generic error dialog / discard / progress (`error_feedback.dart`) | yes | T6 | core/v2/states/legacy_dialog_looks.dart |
| `MgBackArrow` on light pages | **broken** — `dark:false` maps to the dark style (white@.10 disc) → invisible on canvas | §6.1 | core/widgets/state_views.dart:23-29 |
| Language / permission / intro overlays, offline overlay + Wi-Fi strip, force + optional update dialogs, crash screen, shell pending-cancel dialog | **NO** — specified in audit_shell_home SH-01…SH-05 (same spec, not repeated) | Prihlaseni Úvod/Jazyk/Oprávnění, Stavy 8, 19 | core/overlays/onboarding_overlays.dart, core/offline_guard.dart, core/update_check_provider.dart, core/in_app_update_service.dart, main.dart:90-125, core/shell_fabs.dart |
| All other sheets / dialogs / pushes found by grep (catalog filter, size dialogs, promo, map picker, fullscreen gallery, video, doc viewers, branches sheet, ride feedback sheet, routes/rides sheets, payment sheets) | covered by catalog_booking / res_profile / routes_rides / pay_shop audits | — | grep of `showModalBottomSheet / showDialog / Navigator.push / OverlayEntry` (77 files) |
| Exceptions (stay) | native biometric prompt, camera / image-picker / gallery UI, system settings, `tel:` / `mailto:` / Google Maps handlers, Stripe / Apple Pay / Google Pay, level-up overlay (`loyalty_levelup_overlay.dart`) | — | — |

## Improvements (prioritized)

### ASM-01 · P1 · LC/L0 · Login v2 view (board "Přihlášení", new-device variant)
- Where: features/auth/login_screen.dart:230-359 (+ widgets/login_header.dart, login_buttons.dart, login_form_fields.dart, login_footer.dart)
- Now: v1 look inside the v2 frame — old gradient header, vykání ("Přihlaste se…", "Zažijte svobodu.", "Zapomněli jste heslo?"), neon pill PŘIHLÁSIT SE on white (banned on light, R5.8), outlined bio button, emoji 🌐 hint, grey 11 px labels (#9CA3AF-like g400 fails AA), centred forgot link under the button.
- Change: new `features/auth/v2/login_view_v2.dart`, seam `MgV2.on(context) ? LoginViewV2(...) : <old Scaffold>` with the SAME controllers/flags/callbacks (_doLogin, _doBioLogin, _forgotPassword, _openRegister, _obscurePass toggle). Layout per board: dark header (brand `MgGradients.dark`, no rank before login) — logo tile 64 r16 + "MOTO GO 24" 30/900 white (FittedBox scaleDown) centred, tagline 14/600 italic neon "Zažij svobodu."; white sheet r24 overlapping −24 (R5.3), padding 20/24/20: title 22/800 ink "Přihlas se pro snadnou jízdu", sub 14/600 #4A6B5A "Tvůj profil a rezervace vždy po ruce"; info `MgWell` r14 with `MgIconTileLight` 36 (globe) + 12.5/600 ink "Máš rezervaci nebo účet z webu? Přihlas se stejným e-mailem a heslem."; caps labels 11.5/800 #55705F (E-MAIL, HESLO); inputs 52 tall, lineInput 1.5 px #7C958A r14 (theme overlay), eye `MgIcon` 22; "Zapomenuté heslo?" `MgBtnText` right-aligned with history icon directly under the password field; dark carrier (night r18, padding 8) holding `MgCta` "PŘIHLÁSIT SE" md56 `loop: true` (the screen's one loop), `busy: _loading`, and — when bio is on — `MgBtnGhostDark` 48 with the platform name from the existing `BiometricService.getBiometricLabel()` ("Přihlásit otiskem prstu" / "Přihlásit přes Face ID"); "nebo" divider (1 px #E2EAE5, 12/700 #55705F); `MgBtnGhostLight` "REGISTROVAT" with person-add icon; footer 12/600 #55705F phone (tappable as today) · motogo24.CZ link (#0D6E0D) · version 11/600. Scroll view `keyboardDismissBehavior: onDrag`.
- Why (king / conversion): the first screen after install / sign-out sets the premium tone; tykání matches the rest of v2; one obvious primary.
- Risk: none functional (AuthService, BiometricService, ForcedSignOut untouched). Root route — no back (as today).
- Shared: `MgCta` (brand tokens before login), `MgBtnGhostDark`, `MgBtnGhostLight`, `MgBtnText`, `MgWell`, `MgIconTileLight`; i18n v2Auth* keys ×8.

### ASM-02 · P1 · L3 · Login errors and notices → Stavy 18 / 8 templates
- Where: login_screen.dart:49-59, 105-139, 142-165, 167-208
- Now: empty fields → "✗ Chyba" toast; wrong credentials → 7 s toast; unknown e-mail → raw AlertDialog (neon text on white); forced sign-out → 8 s 🔒 toast; bio lockout / not enrolled / session gone → ℹ️ toasts that vanish before they are read.
- Change (v2 only, same branches, same texts from AuthErrorMapper / existing keys): 18.1 inline under each empty field (12.5/700 #B42318 + 1.5 px error border) "Vyplň e-mail" / "Vyplň heslo" (new keys), same early return; 18.2 `MgDialogFrame` T6 — info disc, "Účet s tímhle e-mailem nemáme", "Zaregistruj se, zabere to pár minut.", safe `MgBtnGhostLight` "Zrušit", action `MgBtnInk` "Zaregistrovat se" → existing `_openRegister(unknown: true)`; 18.3 `showMgStateSheet` tone err — title/why = `error.title`/`error.message`, primary `MgBtnInk` "Zkusit znovu" (closes, focuses password), secondary `MgBtnText` "Poslat nové heslo" → existing `_forgotPassword`, `MgSupportRow`; 8.12 offline (BioRestore.offline / network) → T2 with "Zkusit znovu"; 8.10 forced sign-out → `MgStateBanner` info (lock) above the form: "Odhlásili jsme tě" + existing `eoForcedSignOut`; 8.11 session gone → T2 "Přihlas se e-mailem" (existing `sessionExpired` semantics); bio cancelled stays a T5 toast. Success toast + `go(home)` unchanged.
- Why: "never a 3 s toast for errors that need action" (§5.1.5); the customer always sees what / why / how and a working action.
- Risk: display only; keep every branch and its return.
- Shared: `showMgStateSheet`, `MgDialogFrame`, `MgStateBanner`, `MgSupportRow`.

### ASM-03 · P1 · LC/L0/L2 · Register v2 view (board "Registrace 1/3–3/3")
- Where: register_screen.dart:443-554 (scaffold), 568-699 (steps)
- Now: v2 canvas + back disc only; v1 card with floating labels (ellipsized in de/uk at 320), Material licence dropdown (overflows 6.5 / 66 / 70 px at 320 cs/de/uk), v1 primary button (overflows 30 px in de at 320), passwords without eye, header title 16/900 + plain "1/3".
- Change: `features/auth/v2/register_view_v2.dart`, seam in `_buildScaffold` (inside the existing BackButtonListener/PopScope). Header: `MgV2Back` light at (16,55) → `_back`; title "Registrace pilota" 17/800 (15/800 two lines if needed, never ellipsis); step chip "1/3" (`MgWell` pill, 12/800 #0D6E0D) right; 3-segment progress h 6 r3 (done/active neon gradient #37CF63→#74FB71, todo #E2EAE5; width/colour animate `MgMotion.sticky` 300 `emphasized`). White `MgCard` r20: step head = night disc 34 with neon number 15/900 + eyebrow "KROK 1 / 3" 11.5/800 #55705F + title 20/800 ("Základní údaje" / "Adresa bydliště" / "Řidičský průkaz") + sub 13/600 #4A6B5A ("Vyplň své osobní údaje" / "Potřebujeme tvoji kontaktní adresu" / "Údaje o tvém řidičském oprávnění") + hairline; labels ABOVE inputs 12/800 ink (fixes every truncated label), inputs lineInput 52; eye toggles on both passwords (view-local bool); step 3 licence = two choice cards 2-col (white r16, 1.5 px #E2EAE5; selected tintOk + 1.5 px #37CF63 + ✓ disc 22) "A2 · do 35 kW" / "A · bez omezení výkonu" setting the SAME `_licGroup` (replaces the overflowing dropdown); consents as `MgCheckRow` (same bools); "Souhlasy (povinné)" 13/800. Bottom: `MgDock` (dark) with `MgCta` "POKRAČOVAT →" / "DOKONČIT REGISTRACI ✓" `busy: _loading` (label may wrap to 2 lines — never clipped). Step transition: existing slide+fade but `MgMotion.of(context, MgMotion.hero)` + `MgMotion.emphasized`, 24 px offset; reduced motion → instant; StaggeredReveal kept (already reduced-motion safe).
- Why: three long steps are where a new customer gives up; board fidelity, no clipped words, one consistent CTA.
- Risk: same controllers / validators / `_next` / `_back` / `_doRegister`; layout only. Add `auth_fit_test` cases for steps 2–3 (8 langs × 320/360/412).
- Shared: `MgCard`, `MgCheckRow`, `MgDock`, `MgCta`, NEW `MgChoiceCard` (2-col selectable card with ✓ disc — also used by SOS fault / theft secured, ASM-15).

### ASM-04 · P1 · L3 · Register validation inline + server errors as states
- Where: register_screen.dart:205-283 (16 ⚠️ toasts), 127-153 (e-mail taken AlertDialog), 353-367 (server error toast 9 s)
- Now: a 3 s toast names the field ("Jméno") but the field is not marked; on step 3 the customer has to find it.
- Change (v2): replace each `showMotoGoToast(...)` in the validators by `_fieldError(key, title, msg)` which in v1 calls the same toast and in v2 marks the field (1.5 px #B42318 border + 12.5/700 #B42318 message under it) and scrolls it into view (`Scrollable.ensureVisible`, `MgMotion.sticky` 300, `emphasized`); message cleared on edit. E-mail taken → `MgDialogFrame` T6 18.7 "Tenhle e-mail už účet má" (existing `AuthErrorMapper.emailTaken` texts), safe "Zrušit", action ink "Přihlásit se" (same `go(login?email)`). Server error → `showMgStateSheet` tone err (error.title / error.message, primary "Zkusit znovu" = dismiss, `MgTechDetails` only if a raw code exists), keep the jump to `error.step`.
- Why: the customer sees exactly what to fix; no lost time on the longest form of the app.
- Risk: the validator conditions and order stay; only the display call changes (seam line per toast).
- Shared: `showMgStateSheet`, `MgDialogFrame`.

### ASM-05 · P1 · LC/L0 · Reset password v2 view (board "Obnovení hesla 1/3–3/3")
- Where: reset_password_screen.dart:188-589
- Now: fully v1 — "← Zpět na přihlášení" pill (no v2 back seam at :212-243), vykání ("Zadejte e-mail"), one big code field, v1 pill buttons (overflow 6.3–6.6 px in de/uk at 320, :571).
- Change: `features/auth/v2/reset_view_v2.dart`, seam in `_buildScaffold`. Dark compact header (`MgAppBar`-style band): `MgV2Back` dark → `_onBack`, "Obnovení hesla" 17/800 white, step chip "1/3" (white@.10 pill, neon 12/800) right, 3-segment progress inside the header (neon on white@.14, `MgMotion.sticky`). White sheet r24 overlapping −24. Step 1: "Zadej e-mail" 22/800 + "Na tvůj e-mail pošleme 8místný kód pro obnovení hesla." + E-MAIL input + dark carrier with `MgCta` "ODESLAT KÓD" (send icon, busy) + phone support line. Step 2: "Zadej kód" + "Zadej 8místný kód, který jsme poslali na **{email}**"; 8 boxes 40×52 r12 (lineInput; focused box 2 px #0D6E0D + 4 px neon@.28 ring) driven by the SAME hidden `_codeCtrl` (digitsOnly, maxLength 8, `AutofillHints.oneTimeCode`); "Vložit zkopírovaný kód" `MgBtnText` (Clipboard → digits → `_codeCtrl`, board); "Odeslat kód znovu" `MgBtnText` (existing `_sendCode`); `MgCta` "OVĚŘIT KÓD". Step 3: two password fields with eyes + live checks "Aspoň 8 znaků" / "Hesla se shodují" (`MgMeaningChip` ok/neutral, same rules as `_setPassword`) + `MgCta` "NASTAVIT HESLO" (lock).
- Why: a locked-out customer is anxious; a calm, branded 3-step flow with paste support gets them riding again.
- Risk: AuthService calls unchanged; the paste button only fills the field (no auto-verify).
- Shared: NEW `MgCodeBoxes` (n-box OTP input over one controller, area-local is fine), `MgMeaningChip`, `MgCta`.

### ASM-06 · P1 · L3 · Reset states (Stavy 18.10–18.14)
- Where: reset_password_screen.dart:69-165
- Now: 7 emoji toasts (⚠️ ✗ 📧 ✓).
- Change (v2): invalid e-mail / short code / short or different password → inline under the field; 18.10 code sent → `showMgToast` "Kód je na cestě" + "Poslali jsme ho na {email}"; 18.11 send error and 18.14 save error → `showMgStateSheet` err with "Zkusit znovu" (= dismiss); 18.12 code invalid → T2 with primary "Poslat nový kód" (= existing `_sendCode`); success unchanged (toast + `go(login)`).
- Risk: display only. Shared: as ASM-02.

### ASM-07 · P1 · LC/L0/L4 · Registration welcome overlay (board "Hotovo (MotoWelcomeOverlay)")
- Where: core/widgets/moto_fx.dart:620-705 (caller register_screen.dart:370)
- Now: 2.8 s dark overlay, 🏍️ success hero, title + sub only; vanishes before it can be read; no rank.
- Change: v2 seam in `_MotoWelcomeOverlayState.build`: night page; ✕ dark disc 44 at (16,55) = existing `_close`; `MgToneDisc` ok dark 120 (check draws 300, disc `pop`, one neon ring ripple 700, one-shot); "Registrace dokončena!" 26/900 white; "Vítej v MotoGo24" 15/600 #CFE7DA; glass card (white@.06, 1 px white@.14, r18): eyebrow "TVŮJ STARTOVNÍ RANK" neon 11.5/800, logo ring (level 1) + `MgRankChip` dark pill "Startér · −1 %" (name / discount from the existing loyalty levels provider — hide the card while not loaded), 13/600 #CFE7DA explainer (new key); bottom `MgCta` "POKRAČOVAT →" (= `_close`) with a 2 px neon progress line above it running the SAME 2.8 s timer (reduced motion: static full line); "Klepni kamkoli a pokračuj" 12/700 #9FC4B1. Haptic unchanged.
- Why: the first "you are one of us" moment — the king gets his starting rank and the reason to ride.
- Risk: timer, tap-to-close and return unchanged. (Longer timing = owner decision OD-6.)
- Shared: NEW `MgLogoRing` (see shared list), `MgToneDisc`, `MgRankChip`, `MgCta`.

### ASM-08 · P1 · LC/L2 · Toast look app-wide (`showMotoGoToast`)
- Where: features/auth/widgets/toast_helper.dart:8-71 (131 call sites in the app)
- Now: v1 snackbar — emoji glyph 19 px, title 15/700, message white@.5, `elevation: 8` (renders as a heavy black halo around the toast), fixed margin `bnavHeight + xl` regardless of v2 chrome.
- Change: seam inside the function: when `MgV2.on(context)` → T5 look: night@.96, r14, 1 px neon@.25, elevation 0; `MgIcon` 20 mapped from the passed emoji (✓ ✅ → checkCircle neon; ✗ ❌ → xCircle #FFB3B3; ⚠️ → alert #FFD36B; ℹ️ 🔐 🔒 → info / lock white; 📍 → pin; 📧 → mail; 📡 → wifiOff; unknown → info); title 13.5/800 white; message 12.5/600 #CFE7DA; `MgWordFit`; bottom margin from the v2 chrome (dock / nav height via `MgChromeScope`) + 12; same duration and haptic.
- Why: toasts appear on every screen — today they are the most frequent old-look element.
- Risk: none functional (same calls, same durations). Errors that need action move to states per area (ASM-02/04/06/20; other groups for theirs).
- Shared: NEW `showMgToastRich(context, title:, message:, tone:, duration:)` in core/v2/widgets/mg_toast.dart + emoji→icon map.

### ASM-09 · P1 · LC/L0 · SOS start v2 view (board "Start · výběr problému")
- Where: features/sos/sos_report_screen.dart:25-190, 342-475
- Now: light page; "🆘 SOS — Pomoc na cestě" 16/900 + vykání sub; the dark AI card sits ABOVE the emergency numbers (:91-117); 112/155/158 are small white chips with 16 px red numbers; option rows with emoji tiles; active incident amber card with ⚠️.
- Change: `features/sos/v2/sos_start_view_v2.dart`, seam at :31 (same `activeSosProvider`, same `_showAccidentPicker`, `_showBreakdownPicker`, `_shareLocation`, `push(aiAgent)`, `push(sosDone)`). Dark compact SOS header (gDark, bottom r24, ≈ 210 at 390, NO rank aura): `MgV2Back` dark at (16,55) → `backOr(home)`, red "SOS" pill (#D92D20, 12/900 white), logo ring top-right (rank shows ONLY here, ≥ 16 px from red), eyebrow 11.5/800 caps #9FC4B1 with red dot "HUSQVARNA 701 SM · 16.–18. 10." from the `sosAllowed` reservation of `reservationsProvider` (display only; hidden when none), 48 px red tile (alert icon) + title 22/800 white "SOS — Pomoc na cestě" + sub 14/600 #CFE7DA "Vyber typ problému". Canvas body in this ORDER: active-incident T3 amber banner (when active) → white card "V ohrožení života nejdřív volej!" (alert #B42318 + 14/800) with three tiles 1:1:1, h 96, r16, fill #D92D20→#B42318, number 30/900 white, label 11.5/800 white@.9, phone glyph top-right (same `tel:` actions) → option rows (white r16, 1 px #E2EAE5, icon tile 44: red #FDECEC/#B42318 burst "Nehoda / Krádež", amber #FFF4E0/#8A4B00 wrench "Porucha na cestě", ok #E8FCE8/#0D6E0D pin "Sdílet polohu"; title 15/800 ink; sub 12.5/600 #55705F; chevron) → AI card LAST (gDark r18, icon tile with neon ring, "AI Servisní agent" 15/800 white, sub #CFE7DA). No emoji anywhere.
- Why: in an emergency the first thing after the title must be 112/155/158; today a chatbot comes first. Premium = calm, clear, unmistakable.
- Risk: none functional; the reservation line reads an existing provider.
- Shared: NEW `MgLogoRing` + `MgSosPill` (extract from features/home/v2/home_header_v2.dart:215 `_LogoRow` ring and :273 `_SosPill`), area `SosHeaderV2`.

### ASM-10 · P1 · L3/L5 · Nonstop line dock on every SOS screen (number is not callable today)
- Where: sos_report_screen.dart:152-176 (nonstop card, no tap); sos_detail_screen.dart:150-175 (done "PŘÍMÝ KONTAKT", no tap); core/v2/shell/shell_nav_map.dart:40-51
- Now: the most important number in a crisis is printed but cannot be dialled from the SOS screens; the v2 nav bar stays under SOS (FAB already hidden).
- Change: board "Spodní lišta SOS": `MgDock` (night) on every `/sos*` screen except where the screen has its own dock (replacement): row = neon phone disc 44 + "Nonstop linka MotoGo24" 12/700 #9FC4B1 over "+420 774 256 271" 17/900 white, whole row tappable → existing `callMotoGo()` (core/widgets/error_feedback.dart:20, already used by the SOS error dialogs and `SosCallButton`); `aiDisc: true` → push `/ai-agent` (existing AI card action). Shell: `v2NavHiddenFor` adds `p.startsWith('/sos') && p != '/sos/payment'` handled as today — the dock replaces the nav (board). The done view's contact card becomes a tappable `MgSupportRow`.
- Why: a king in trouble taps once and talks to a human — the single most important SOS affordance.
- Risk: the tap reuses an existing app action; it adds a call entry point on these screens → mention to the owner (recommended). Shell file is shell_home's — coordinate.
- Shared: `MgDock(aiDisc)` exists; nav rule in shell_nav_map (shell owner).

### ASM-11 · P1 · L0/L3 · SOS sub-screens: dark header, back top-left + pinned
- Where: sos_immobile_screen.dart:206-232; sos_breakdown_immobile_screen.dart:140-180; sos_theft_screen.dart:206-231; sos_service_screen.dart:118-140; sos_replacement_screen.dart:180-200; sos_detail_screen.dart:297-318
- Now: the back disc sits on the RIGHT of a tinted header card (render) and scrolls away with it — every other v2 screen has it top-left (§6.1 x16 y55), so the customer looks for it in the wrong place under stress.
- Change: the same `SosHeaderV2` as ASM-09 with a per-screen tile + eyebrow (existing labels): Závažná nehoda — red tile "ban", eyebrow "ZÁVAŽNÁ NEHODA", title "Motorka je nepojízdná", sub "Nelze pokračovat v jízdě"; Porucha — amber tile wrench, "PORUCHA — NEPOJÍZDNÁ"; Krádež — red lock, "KRÁDEŽ", "Krádež motorky", "Okamžitě nahlas"; Servis — green #37CF63 wrench, "DROBNÁ ZÁVADA", "Servis na vlastní pěst"; Náhradní motorka — green bike; Incident detail — amber alert "SOS incident" + #ID. Page = `MgPage(header:, pinnedBack: <same backOr>)` so the back stays pinned when the header scrolls away.
- Why: one back standard everywhere (owner R6); clear "where am I" in the header.
- Risk: none (same back callbacks).
- Shared: `MgPage.pinnedBack` (exists), `SosHeaderV2` (area), `MgLogoRing`, `MgSosPill`.

### ASM-12 · P1 · L0/L3 · SOS step guides as the board's dark "postup" card
- Where: sos_immobile_screen.dart:129-145 (amber card, the whole guide is one 11 px paragraph `accidentSteps`); sos_theft_screen.dart:89-103, 233-270; sos_service_screen.dart:158-180, 228-285
- Now: tiny amber text / emoji step tiles (📞📱📋📍🧾📤), neon pill buttons on light.
- Change: `MgDarkHero(rankAura: false)` r20 = the screen's one dark block: title row (doc icon neon + 16/800 white "Co dělat při nehodě"), `MgTimeline` steps (34 px neon discs with ink numbers, connector, 14/600 #E8F5EE lines). `accidentSteps` is split on "\n" with the "N. " prefix stripped — no new text. Theft: step 1 action `MgBtnSos` "Volat Policii ČR – 158" (existing `tel:158`); service: `MgBtnGhostDark` "Vyhledat servis v okolí" (existing maps link), invoice details in a glass well (white@.06, r12; 12/700 #CFE7DA, name 13/800 white), "Nahrát fakturu (vyfotit)" `MgBtnGhostDark` with upload icon; liability / coverage boxes → T3 warn banner (#FFF4E0 + 1 px #E9B44C, `MgIcon` ✓ #0D6E0D / ✕ #B42318 lines instead of ✅ ❌ ⚖️).
- Why: under stress the customer reads big numbered steps, not a paragraph.
- Risk: none; tappable 155/158 inside step 2 of the accident guide is in the board but a new action on that screen → owner decision OD-4.
- Shared: `MgDarkHero(rankAura:false)`, `MgTimeline` (dark variant if missing), `MgBtnSos`, `MgBtnGhostDark`.

### ASM-13 · P1 · L0/L4 · Fault / "secured?" choice cards
- Where: sos_immobile_screen.dart:234-280 (`_faultDecision`); sos_theft_screen.dart:125-160 (secured choice)
- Now: two pale cards with emoji, selection = neon border only; action cards pop in without a hint.
- Change: `MgChoiceCard` ×2 (white r18, h ≈ 120, icon tile 44 shield-check / alert, 14/800 label, sub 12/600 #55705F for theft "Náhrada zdarma / za poplatek"); selected = tintOk bg + 1.5 px #37CF63 + ✓ disc 22 top-right (`pop` 300) + neon icon tile; colour change `MgMotion.color` 180. Before a choice: hint row (info icon + 12.5/600 #55705F "Nejdřív vyber zavinění — pak nabídneme náhradní motorku nebo odtah.", new key); the action block appears with `MgAnimatedSize` 300 `emphasized` (reduced motion: instant). Same `setState`.
- Why: the customer understands that a choice unlocks the next step; nothing jumps.
- Shared: NEW `MgChoiceCard` (ASM-03).

### ASM-14 · P1 · L3 · In-flight feedback on SOS actions (never looks frozen)
- Where: sos_immobile_screen.dart:50-99, 286-305; sos_breakdown_immobile_screen.dart:56-107, 286-325; sos_theft_screen.dart:33-57, 144-160
- Now: a tap only disables the card / button for up to ~65 s (GPS ≤ 20 s + insert ≤ 45 s) — no spinner, no text (`_submitting` is used only as a gate).
- Change (v2): the tapped action shows a spinner inside + label "Odesílám na centrálu…" (Stavy 14.2, existing `eoSosSending`) while `_submitting`; the other actions dim to .5; no layout jump (fixed height).
- Why: "nikdy se nezaseknu" — in an emergency a silent button is the worst feeling.
- Risk: display of an existing flag only.

### ASM-15 · P1 · L0 · SOS primary actions per board (no neon on light)
- Where: sos_immobile_screen.dart:152-194; sos_breakdown_immobile_screen.dart:220-280; sos_theft_screen.dart:140-200; sos_service_screen.dart:200-216
- Now: "Náhradní motorka – zdarma" = greenPale card; "Sdílet GPS polohu asistentům" = neon pill on white (banned R5.8); theft "Nahlásit incident" = v1 red pill; "Hotovo – zpět na přehled" neon pill.
- Change: "NÁHRADNÍ MOTORKA – ZDARMA" `MgBtnInk` 56 (bike icon) + caption 12/600 #55705F "Vyber motorku a adresu přistavení"; "Ukončit jízdu – zavolat odtah" white row card (truck icon tile well, 15/800 + 12.5/600 sub, chevron); "SDÍLET POLOHU ASISTENTŮM" eyebrow 11.5/800 #0D6E0D + `MgBtnGhostLight` with pin icon; theft "Nahlásit incident MotoGo24" `MgBtnSos` 56 → reported: disabled `MgBtnInk` with ✓ "Krádež nahlášena MotoGo24" + "Chceš náhradní motorku?" 15/800 + `MgBtnInk` "OBJEDNAT NÁHRADNÍ MOTORKU"; service done `MgBtnInk` "Hotovo – zpět na přehled". SOS actions never rank-coloured (board note: dark button on light, neon only in the night dock).
- Risk: none.

### ASM-16 · P1 · LC/L0 · SOS type sheets (accident / breakdown)
- Where: sos_report_screen.dart:198-240
- Now: v1 sheet, centred title, emoji rows on g100.
- Change: `MgSheetFrame` light inside the existing `showModalBottomSheet` builder (grabber 42×5, title 20/800 left, ✕ 44 right, drag-down + scrim close = today's defaults); rows white r16 1 px #E2EAE5, icon tile 40 (Lehká nehoda — ok target; Závažná — red alert; Krádež — red lock; Drobná závada — ok bolt; Nepojízdná — amber ban; Nejbližší servis — ok wrench), 15/800 label, chevron; same `onTap`s.
- Shared: `MgSheetFrame`.

### ASM-17 · P1 · LC/L0/L3 · SOS report sheet (popis + fotky)
- Where: features/sos/sos_report_sheet.dart:90-236
- Now: v1 look ("🆘 Lehká nehoda", g400 hint, neon outlined "Vyfotit", grey disabled pill with no reason).
- Change: v2 frame: icon tile 40 + "Lehká nehoda" 20/800 (no emoji) + ✕ 44 (keep `isDismissible:false` / `enableDrag:false` — deliberate SOS safety; therefore NO grabber); why 14/600 #4A6B5A; "Popis problému *" 12/800; textarea lineInput r14 (3 lines); "Fotodokumentace *"; photo tiles 64 r12 (`Image.file(cacheWidth: 192)` — today a 2048 px decode per thumbnail) ; `MgBtnGhostLight` "Vyfotit" / "Přidat další fotku" (camera icon); camera problem → T3 warn banner + `MgBtnText` "Otevřít nastavení"; when the send button is disabled a line above it says what is missing ("Chybí: popis · fotka", 12.5/700 #8A4B00, new keys; derived from the same `canSubmit` parts — disclosure rule "blockers visible"); primary `MgBtnSos` "Ano, nahlásit" / existing "Odeslat bez fotky" 56; `MgBtnText` "Zrušit".
- Risk: same PopScope / discard confirm / result record.

### ASM-18 · P1 · L3 · SOS failure + location results as SOS states (14.3, 14.7–14.10)
- Where: features/sos/sos_feedback.dart:17-82
- Now: v2 T6 dialog with three identical ink buttons with emoji labels ("📞 Nonstop linka MotoGo24", "🆘 112", "Zkusit znovu") + "Zavřít"; calls are not red; location success / no-location are emoji toasts.
- Change (v2, same return ids 'call' / '112' / 'retry' / 'settings'): `showMgStateSheet` SOS variant — red header band (#D92D20→#B42318, alert disc white, title 20/800 white), why = existing body, actions in order `MgBtnSos` "Zavolat +420 774 256 271" ('call'), `MgBtnSos` outline / smaller "112" ('112'), `MgBtnGhostLight` "Zkusit znovu" ('retry'), ✕; location failure: same template (warn tone, not red header) with `MgBtnInk` "Povolit polohu / Zapnout polohu" ('settings') + call + retry; location ok → `showMgToastRich` ok "Poloha odeslána · {time}" (14.7, existing `locationShared` + time); sent without location → T2 warn 14.11 instead of a 9 s toast; photos failed → T2 warn 14.4 ("Hlášení máme, fotky ne", primary "Hotovo").
- Why: in a failure the red "call a human" must be the obvious first action.
- Shared: NEW SOS tone for `showMgStateSheet` / `MgStateBanner` (red header variant) in core/v2/states.

### ASM-19 · P1 · LC/L0 · SOS "Hotovo" screens
- Where: sos_detail_screen.dart:54-280 (`_doneView`, `_doneConfig`)
- Now: mint header card with emoji, the incident number in a second dark card (R5.2), contact not tappable, v1 outlined + filled pills, and the back disc is nearly invisible (render: white@.10 disc on canvas, see ASM-20).
- Change: `MgPage` with dark hero (gDark, NO rank aura — "SOS is never rank"): `MgToneDisc` ok dark 88 (check draw 300 + pop + one ring ripple 700, one-shot; reduced motion static), eyebrow "SOS INCIDENT · #A41C07E2" neon 11.5/800 (from `lastSosIncidentId`), title 22/800 white (`config.title`), sub 14/600 #CFE7DA; white cards overlapping −24: "ČÍSLO INCIDENTU" (iconTileDark 48 + eyebrow + number 28/900 ink + `sosRefKeep` 12.5/600), "CO BUDE DÁL?" (`config.nextSteps`), tappable `MgSupportRow` (call); actions `MgBtnInk` "MOJE REZERVACE" (existing `go(reservations)`), `MgBtnGhostLight` "Zprávy z MotoGo24" (existing push), `MgBtnText` "Zpět na hlavní obrazovku"; ✕/‹ pinned via `MgPage.pinnedBack` (dark style over the hero, light once collapsed).
- Shared: `MgStateScreen` needs `rankAura: false` (today success always takes the rank aura) or compose `MgDarkHero(rankAura:false)` + `MgToneDisc`.

### ASM-20 · P1 · L0/L3 · `MgBackArrow` v2 style mapping (invisible back on light pages)
- Where: core/widgets/state_views.dart:23-29; call sites sos_detail_screen.dart:76 (light canvas), features/shop/shop_screen.dart:43 (pay_shop), documents/pdf_pages_screen.dart:78 + doc_webview_screen.dart:117 (dark app bars), core/booking_form_widget.dart:398, core/overlays/onboarding_overlays.dart:214
- Now: `dark: false` (v1 "green button for light pages") maps to `MgBackStyle.dark` (white@.10 disc + white icon) → on the canvas the back is practically invisible (SOS done render).
- Change: give `MgBackArrow` an explicit `v2Style` param (default `MgBackStyle.light` for `dark:false`), pass `MgBackStyle.dark` at the dark-app-bar call sites; render every call site.
- Why: owner R6 "always a well visible back".
- Risk: core widget shared by other areas → whoever owns core/widgets in the fix pass; check each call site.

### ASM-21 · P1 · LC/L0 · SOS incident detail (active incident)
- Where: sos_detail_screen.dart:283-515
- Now: light page with emoji title, v1 cards / buttons.
- Change: `SosHeaderV2` (amber alert tile, "SOS incident", #ID); status card white r20: "SOS incident #A41C07E2" 15/800 + amber chip "● Nahlášeno", rows 13/600 #55705F label / 13/800 ink value with #E2EAE5 dividers; photos card (`MgImage` thumbs 72 r12, fade-in); "Průběh" card: `MgTimeline` + "● ŽIVĚ" chip (neon dot `ping` 1.8 s — the screen's one live indicator; reduced motion static); actions `MgBtnInk` "NÁHRADNÍ MOTORKA" (existing push), `MgBtnInk`/ghost "JEDU DÁL" (existing `_continueRide`), `MgBtnGhostLight` "Zprávy z MotoGo24"; nonstop dock (ASM-10).
- Risk: none.

### ASM-22 · P1 · LC/L0/L2 · Document scanner choice screen
- Where: features/documents/document_scanner_screen.dart:731-802
- Now: centred white blocks with emoji (🪪📕🏍️), vykání "Vyberte doklad totožnosti", trust badges 9 px white@.5 (≈ 3 : 1, fails AA) with emoji.
- Change: board "Skenování dokladů": night page; header `MgV2Back` dark + "Skenování dokladů" 20/800 white; title "Vyber doklad totožnosti" 22/800 white left-aligned; rows glass (white@.06, 1 px white@.14, r16, h 72): `MgIconTileDark` 44 (neon id-card / passport / bike) + 15/800 white label + 12.5/600 #9FC4B1 "4 × skenovat" / "2 × skenovat" (count from the existing step plan) + neon chevron; press scale .97 (`MgMotion.press`); trust chips dark pill white@.08 + shield icon 12/700 #CFE7DA (no emoji); same `_selectIdType`.
- Why: the doc check is the last hurdle before the codes — it must feel safe and simple.
- Risk: none; the "Data uložena v telefonu" claim is inaccurate per board → OD-5.

### ASM-23 · P1 · L0 · Scanner camera step
- Where: document_scanner_screen.dart:852-968, 1161-1171; DocumentFramePainter (document_camera_screen.dart:300-340)
- Now: back disc in dark style over the camera (§6.1: over photo/camera = photo style night@.8 + ring), emoji title + 10 px white@.5 sub, #4ADE80 frame + white corners, Material camera icon, white54 skip.
- Change: `MgV2Back` photo style; centred step chip "Občanský průkaz · přední strana 1/4" (night@.6 pill, 12/800 white); progress segments h 6 r3 neon / white@.24 (`MgMotion.sticky`); frame corners neon #74FB71 3.5 px + scrim night@.55 (painter gets colour params; v1 defaults unchanged); guide pill night@.6 13/700; shutter 76 white disc + 4 px neon ring + ink camera icon, press .92 + `HapticFeedback.mediumImpact` on capture; "Přeskočit ›" `MgBtnText` 12.5/700 #CFE7DA.
- Risk: none (same `_capture` / `_skip` / `_safePop`).

### ASM-24 · P1 · LC/L0/L3 · Scanner result, help and camera-error states
- Where: document_scanner_screen.dart:970-1042 (result), 1044-1121 (contact fallback), 804-850 (camera error), 1203-1219 (done)
- Now: black 85 % overlays with ✅ / ⚠️ / 📞 emoji and pill buttons; raw spinners.
- Change: result = light T2 panel sliding up over the camera (`MgMotion.sheet` 300 `emphasized`, no drag-dismiss — a decision is required): success `MgToneDisc` ok 56 + "Doklad úspěšně naskenován" 20/800 + recognised fields as 2-col well tiles (label 11.5/700 #55705F, value 14/800 ink — keep the parsed field list that `_buildFieldsSummary` already builds, display only; fall back to the summary text) + partial-scan note 12.5/700 #8A4B00 + `MgBtnInk` "Pokračovat →" (`_onContinue`); error tone warn + "Sken se nepovedl" + reason + guidance as `MgStateSteps` + chip "Zbývají {n} pokusy" + `MgBtnInk` "Zkusit znovu" (`_onRetry`) + `MgBtnText` "Přeskočit" (`_skip`); contact fallback T2 "Pomůžeme ti osobně" (person disc) + `MgBtnInk` "Zavolat +420 774 256 271" + `MgBtnGhostLight` "Napsat" (existing mailto) + `MgBtnText` "Zkusit přesto ještě jednou" / "Zavřít skener"; camera error → T1 light (warn camera disc 72, "Appka nemá přístup ke kameře", why, "Jak to vyřešit" step, `MgSupportRow`, white dock `MgBtnInk` "Otevřít nastavení" (existing `openFixSettings`) + `MgBtnText` "Zkusit znovu" / "Zpět"); done → night page `MgToneDisc` pending → ok morph 450 ("Ověřujeme doklady…") instead of ✅ + spinner.
- Shared: `MgToneDisc`, `MgStateSteps`, `MgSupportRow`, light panel = `MgSheetFrame` body without route.

### ASM-25 · P2 · L0/L2 · SOS replacement list
- Where: sos_replacement_screen.dart:170-333
- Now: old gradient header, rows without photos, v1 confirm button in a white bar.
- Change: `SosHeaderV2` (green bike tile, eyebrow "NÁHRADNÍ MOTORKA", "Náhradní motorka – zdarma"); eyebrow "VYBER NÁHRADNÍ MOTORKU" 11.5/800 #0D6E0D; rows white r16: radio 22 + photo 72×56 r10 (`MgImage(moto.imageUrl, thumbWidth: 216)`, well placeholder, fade-in) + model 14/800 + category 12/600 #55705F + "Zdarma" tintOk chip; selected tintOk + 1.5 px #37CF63; first 6 then `MgBtnText` "Zobrazit další ({n})" expanding with `MgAnimatedSize` 300 (disclosure); "ADRESA PŘISTAVENÍ" eyebrow; `SosHereAddress` / `AddressAutocompleteField` in v2 input look; night `MgDock` with brand neon button "POTVRDIT OBJEDNÁVKU · ZDARMA" (neon in the night dock, never rank) busy = `_loading`.
- Risk: none.

### ASM-26 · P2 · L3 · Active incident banner + SOS copy in tykání
- Where: sos_report_screen.dart:342-380 and SOS keys (emergencyFirst, selectProblemType, accidentSteps, theft*/service* steps, sosRefKeep, tapToOpenDetail, breakdown info)
- Change: T3 amber banner r16 (#FFF4E0 + 1 px #E9B44C), alert disc 32, "Aktivní SOS incident" 14/800 #8A4B00, "Stav: Nahlášeno · A41C07E2" 12.5/600, "Klepni pro detail" 12/800; copy per board in v2-only keys `v2Sos*` (cs tykání: "V ohrožení života nejdřív volej!", "Vyber typ problému", "Zajisti místo nehody a zkontroluj zranění", "Zavolej Policii ČR: 158", "Najdi nejbližší autorizovaný nebo značkový servis", "Dej MotoGo24 vědět před opravou", "Uveď ho při komunikaci s operátorem.", …) in translations_ext_60_v2_ux_auth_sos_misc.dart (8 langs, informal); old look keeps its keys. Gender-neutral.

### ASM-27 · P2 · L1 · Keyboard, autofill, one-time code
- Where: login_screen.dart:239, register_screen.dart:497, reset_password_screen.dart:256, sos_report_sheet.dart:103
- Change: `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag` (iOS-standard drag-to-hide); `AutofillGroup` around e-mail + password (login, register step 1, reset step 3) so password managers fill / offer to save; `AutofillHints.oneTimeCode` on the reset code; `textInputAction.next` chaining e-mail → password (done = existing `_doLogin`).
- Risk: none (no app logic).

### ASM-28 · P2 · L1 · iOS edge-swipe on guarded multi-step pages
- Where: register_screen.dart:432-440 (PopScope canPop false when dirty / step > 1), reset_password_screen.dart:179
- Now: on iOS a guarded PopScope disables the edge swipe entirely → swiping does nothing (Android back already steps back via BackButtonListener).
- Change: shared `MgEdgeBack` (iOS only): 20 px left-edge drag; page follows the finger (translate 0.3×), release past 30 % width or fling > 700 px/s → the SAME `_back()` / `_onBack()` (step back or discard confirm), otherwise snaps back `MgMotion.sheet` 300 `emphasized`; reduced motion: no follow, action only. Android predictive back stays system.
- Shared: NEW "edge / predictive back for guarded pages" (also booking, reservation edit).

### ASM-29 · P2 · L0 · Small SOS / misc pieces
- `SosCallButton` (sos_feedback.dart:86-99) → v2 seam `MgBtnSos` "Zavolat nonstop linku" (same `callMotoGo`).
- `v2ErrorDialogLook` (core/v2/states/legacy_dialog_looks.dart:16-45): strip leading emoji from action labels; allow per-action style (sos / ghost) so callers like SOS get a red call first (shell/core owner).
- Register date label (core/widgets/date_dropdown_field.dart:167-176) v1 12/700 → v2 12/800 ink (label-above style of ASM-03).
- Scanner plan loading (document_scanner_screen.dart:1193) → `MgSkeleton` rows of the choice list on night.

### ASM-30 · P3 · L4 · Motion hygiene in the area
- register_screen.dart:476-526 fixed 320 / 300 / 340 ms → `MgMotion.of(context, …)` (reduced motion instant); `MotoWelcomeOverlay` transitionDuration 150 → `MgMotion.of`; SOS detail live dot = only loop on the screen; login CTA loop = only loop; no new loops elsewhere.

### ASM-31 · P3 · L2 · Tests to add with the build
- `auth_fit_test`: register steps 2–3 and reset steps 1–3 at 320/360/412 × 8 langs × 1.0/1.3 (today only login + register step 1); SOS screens fit (extend fix_shared_r3); scanner choice + result panel fit; reduced-motion end states for welcome / tone discs; edge-back drag test (`tester.dragFrom(Offset(5, 300), Offset(200, 0))`).

## Owner decisions (not implemented)
- OD-1 Login "Vítej zpátky!" with the remembered rank (ring, chip "Motorkář · −3 %", rank-material CTA) — board "Vracející se zákazník" needs the app to persist the last level / colour on the device at sign-out (new data).
- OD-2 Confirmation sheet before "Ukončit jízdu – zavolat odtah" (board návrh; today one tap ends the rental) — recommended for safety, but it adds a step.
- OD-3 One SOS screen = confirmation + live detail (board note) — restructures `/sos/done`.
- OD-4 New call / message entry points from the board: tappable 155 / 158 pills in the accident guide step 2; "Poslat SMS" (prefilled text + GPS) fallback in 14.3; map picker for the replacement address.
- OD-5 Scanner trust chip "Data uložena v telefonu" is inaccurate (photos go to storage, OCR on the server) — new wording, e.g. "Šifrovaný přenos".
- OD-6 Welcome overlay auto-close 2.8 s is too short for the new rank card — 5 s?
- OD-7 Gendered `eoOfflineReason` "nejsi připojený k internetu" (both looks) → "telefon je offline" (§5.3).
- OD-8 Board extras with new navigation: "Zapomenuté heslo" from the register e-mail-taken dialog; "Všechna oprávnění ›" / "Nahrát z galerie" on the scanner camera error; "Zkusit znovu" on a partial scan success.
- OD-9 Public AI assistant before login (board note) — not implemented.
- OD-10 Level-up timing during SOS (§9 #18) — unchanged.
- OD-11 Fix the old look's 320-dp overflows in register step 3 / reset step 3 too (the v2 views fix them in v2 only).

## Already excellent (keep)
- SOS honesty: location success only when it really arrived; every failure gives reason + call + retry; non-blocking `MgProgress`; replacement list offers only free bikes and recovers when one is taken.
- SOS report sheet cannot be dismissed by accident, asks before discarding, and allows sending without a photo when the camera fails.
- Register checks the e-mail on step 1; server errors jump back to the step of the faulty field; the e-mail travels login ↔ register ↔ reset (never typed twice); system back steps back with a discard confirm.
- Login prefills the saved e-mail; biometric failures say why.
- Scanner: only missing sides, max 3 attempts then a human, back reachable even while uploading.
- SOS hides the AI FAB (SOS priority); status-bar seams; `MgV2Back` 44 disc with haptic; v2 date-field fit row.

## Shared core/v2 primitives needed
1. `MgLogoRing` + `MgSosPill` — extract from features/home/v2/home_header_v2.dart:215 / :273 into core/v2 (SOS header, login returning variant, welcome rank card).
2. SOS tone for `showMgStateSheet` / `MgStateBanner` (red header band, red call first) + `MgStateScreen(rankAura: false)` / SOS success hero.
3. `showMgToastRich` (title + message + tone icon) + emoji→icon map; seam in `showMotoGoToast`.
4. `MgChoiceCard` (2-col selectable card with ✓ disc).
5. `MgEdgeBack` — iOS edge / predictive back for guarded pages.
6. `MgCodeBoxes` (OTP boxes over one controller) — area-local acceptable.
7. `MgBackArrow` style mapping fix (core/widgets/state_views.dart).
8. Shell: hide nav on `/sos*` (shell_nav_map.dart) so the SOS dock replaces it.
9. `v2ErrorDialogLook` emoji strip + per-action styles.
10. Existing, to reuse: `MgDock(aiDisc)`, `MgPage(pinnedBack)`, `MgDarkHero`, `MgTimeline`, `MgToneDisc`, `MgSheetFrame`, `MgSupportRow`, `MgBtnSos/Ink/GhostLight/GhostDark/Text`, `MgCta`, `MgCheckRow`, `MgMeaningChip`, `MgImage` thumbs.
