# MotoGo24 app — every safeguard ("pojistka") of the original look and how the new look (v2) keeps it

Date: 2026-11-12. Released app 4.1.3 = commit 70a94933. App tree: `Motogo-app-main/motogo-app-flutter/lib` (Android master; the iOS tree is an identical copy apart from platform parts). Read-only audit: no file in the repo was changed.

**How to read this.** Each line is one safeguard: something in the original app that stops, hides, disables, filters, limits, redirects or warns. Columns: **id** · **what the customer tries and what stops them** · **what the original app shows** · **how clearly, old → new** (`clear` = picture, heading or button state makes it obvious; `small` = only body text explains; `silent` = nothing explains) · **server** (`yes(name)` = the backend refuses the same thing on its own; `no` = only the app protects it; `unknown`) · **verdict in the new look** (`HOLDS` = every v2 way in goes through the same check and the customer is told at least as clearly; `WEAKER` = the check exists but the customer is told less clearly, a default differs, or one path skips the early warning). No safeguard was found that the new look **bypasses** (no `BYPASS`). Evidence (file:line for old and new) for every id is in `deep/guards_all.json`, `deep/ver_*.json` and `deep/extra_*.json` next to this file.

**Short answer for the owner.** 1112 safeguards on 386 screens/surfaces were checked. In the new look every one of them still blocks what it blocked before (licence, documents, overlaps, taken dates, payment, extensions, swaps, SOS, codes) — the server-side checks are untouched and no new-look button skips the app checks. **49 are WEAKER**: 23 major, 26 minor, 0 critical. The serious ones are (1) **consents are pre-ticked** when a customer comes back to the same bike, including the **guardian consent for a kids bike** (G-230, G-159); (2) on the reservation detail the **door codes, hold-back reasons, the 'sign the protocol first' line, the pickup procedure link and the rating card are drawn in light colours on a light page and are practically unreadable** (G-409…G-463); (3) on the bike detail the **licence warning is amber and half-way down the page while the animated REZERVOVAT stays on screen** (G-152), and the payment page's big total leaves out the add-on and the gear sizes (G-267). Part B lists them with the steps to reproduce and the fix.

## Part A — every safeguard, grouped by customer step

### Getting in (intro, onboarding, login, registration, password reset) — 56 safeguards, 0 weaker

**Router**

- `G-097` A customer who is not logged in follows a link to the bike list, a bike detail, the shop, the cart, the voucher page, My documents, the document scanner, branches, routes or the AI agent; these paths are NOT in the protected list, so they open without login.… — *sees:* The screen itself; a later step sends them to login or fails with an error. — silent → silent — server yes(for writes (RLS / not_authenticated); browsing is public) — **HOLDS**

**S-022 Unknown link page and router redirects / S-023 Login screen / Login**

- `G-049` The app signed the customer out by itself (invalid or revoked session, token refresh failure) and lands them on the login screen; it must explain why once. — *sees:* Toast with a lock: 'eoAuthTitle' + 'eoForcedSignOut' for 8 seconds. — small → clear — server yes(Supabase Auth refresh token) — **HOLDS**

**S-023 Login screen**

- `G-043` The customer taps Log in again while the first attempt is still running; the second tap is ignored. — *sees:* The green button shows a spinner instead of the label and cannot be pressed. — clear → clear — server no — **HOLDS**
- `G-045` The customer logs in to an account that was deleted in Velín (auth user still exists, profile row gone); the login is undone. — *sees:* Toast: 'loginError' + 'accountNoLongerExists' (account no longer exists, register again). — small → clear — server no — **HOLDS**
- `G-050` A session exists but the profile row is missing (account deleted while logged in) and the account is older than 2 minutes; the app signs the customer out so they cannot use an empty account. — *sees:* The app falls back to the login screen (router redirect after sign-out); no message from this provider. — silent → silent — server no — **HOLDS**
- `G-051` The customer taps Forgot password; the e-mail typed so far travels to the reset screen (the only way into reset from login). — *sees:* Reset screen with the e-mail pre-filled. — clear → clear — server no — **HOLDS**
- `G-052` The customer taps Register from login; an e-mail that belongs to the remembered (existing) account is NOT carried into registration, only a newly typed or verified-unknown e-mail is. — *sees:* Registration opens empty or with the e-mail just typed. — silent → silent — server no — **HOLDS**

**S-023 Login screen / Login**

- `G-042` The customer taps Log in (or presses Done on the keyboard) with the e-mail or the password empty; the app refuses to send anything. — *sees:* Toast with a cross: 'Chyba' + 'fillEmailAndPassword' text; it disappears after a few seconds. — small → clear — server no — **HOLDS**
- `G-044` The customer types a wrong password (or the server refuses the login for another reason: unconfirmed e-mail, rate limit, network); the login does not happen. — *sees:* Toast with a cross, mapped title + explanation, shown 7 seconds; the form stays filled. — small → clear — server yes(Supabase Auth signInWithPassword) — **HOLDS**
- `G-046` The customer logs in with an e-mail that has no account at all; instead of a vague error the app asks whether to register. — *sees:* Dialog 'loginUnknownEmailTitle' with Cancel / Register (see S-025). — clear → clear — server yes(check_web_booking_email RPC answers; Supabase Auth refuses the login) — **HOLDS**

**S-023 Login screen / S-026 Registration screen / S-022 Unknown link page and router redirects / S-030 Password reset screen / Router**

- `G-048` A logged-in customer cannot stay on the reset screen, except while a password recovery is in progress (verified code, step 3 pending); leaving the screen clears that exception. — *sees:* Home instead of the reset screen (when not recovering). — silent → silent — server no — **HOLDS**

**S-023 Login screen / S-032 Home screen (Domů) / S-110 / S-051 / S-171 Shop checkout / S-073 Payment screen / S-084 / S-147 Profile / S-090…**

- `G-047` A customer who is not logged in tries to open the booking form (/booking) or go on to /payment; the router sends them to the login screen instead. — *sees:* The login screen; the form never opens. — clear → clear — server yes(RLS on all customer tables requires auth.uid() — **HOLDS**

**S-024 Biometric login button**

- `G-053` The fingerprint / Face ID button appears only when the phone has biometrics, a stored biometric user exists and biometric login is enabled; otherwise the customer cannot use it. — *sees:* No biometric button at all. — silent → silent — server no — **HOLDS**
- `G-055` Biometrics pass but the stored session cannot be restored because there is no signal; biometric login stays set up and the customer is told to try again. — *sees:* Toast '📡 eoOfflineTitle' + 'eoBioOffline' for 7 s. — small → clear — server no — **HOLDS**
- `G-056` Biometrics pass but the stored session is gone for good (refresh token and stored password refused); biometric data are wiped and the button disappears so the customer must log in with e-mail. — *sees:* Toast 'biometricTitle' + 'sessionExpired'; the biometric button vanishes. — small → clear — server yes(Supabase Auth rejects the expired refresh token / changed password) — **HOLDS**
- `G-057` Biometric restore succeeds but the profile row no longer exists (deleted account); the app signs out instead of letting the customer in. — *sees:* Same as the previous record: 'sessionExpired' toast, biometric button removed. — small → clear — server no — **HOLDS**

**S-024 Biometric login button / Login**

- `G-054` The biometric prompt is cancelled, fails, is locked out, not enrolled or unavailable; the app does not log in. — *sees:* Toast 'biometricTitle' with the reason (locked / not enrolled / unavailable / cancelled), 3-7 s. — small → small — server no — **HOLDS**

**S-025 'Neznámý e-mail' dialog**

- `G-058` After a failed login with an e-mail that has no account, the customer must choose: Cancel (stay on login, nothing happens) or Register (opens registration with the e-mail). — *sees:* Dialog with heading 'loginUnknownEmailTitle', body text and two buttons. — clear → clear — server yes(check_web_booking_email) — **HOLDS**

**S-026 Registration screen**

- `G-060` Step 1: surname fails the same name rule. — *sees:* Toast with ⚠️, field name as title and 'validSurnameMsg' text; the step does not advance. — small → clear — server no — **HOLDS**
- `G-061` Step 1: e-mail not in the form x@y.z. — *sees:* Toast with ⚠️, field name as title and 'validEmailMsg' text; the step does not advance. — small → clear — server yes(Supabase Auth signUp also rejects invalid e-mails -> mapped invalid_e…) — **HOLDS**
- `G-063` Step 1: date of birth not chosen (all three of day/month/year needed). — *sees:* Toast with ⚠️, field name as title and 'selectDob' text; the step does not advance. — small → small — server no — **HOLDS**
- `G-065` Step 1: date of birth gives an age above 99 or lies in the future. — *sees:* Toast with ⚠️, field name as title and 'validDobMsg' text; the step does not advance. — small → small — server no — **HOLDS**
- `G-067` Step 1: password and confirmation differ. — *sees:* Toast with ⚠️, field name as title and 'passwordsDoNotMatch' text; the step does not advance. — small → clear — server no — **HOLDS**
- `G-069` Continue / Finish is pressed again while the e-mail check or the sign-up is running; the extra tap is ignored. — *sees:* Button shows a spinner and cannot be pressed. — clear → clear — server no — **HOLDS**
- `G-070` Two sign-up calls would start at the same time (double tap race); the second one is refused. — *sees:* Toast with the 'registerError' / 'signUpInProgress' text (only if the race happens). — small → clear — server no — **HOLDS**
- `G-071` Step 2: city shorter than 2 characters. — *sees:* Toast with ⚠️, field name as title and 'validCityMsg' text; the step does not advance. — small → clear — server no — **HOLDS**
- `G-073` Step 3: driving-licence number shorter than 4 characters. — *sees:* Toast with ⚠️, field name as title and 'validLicenseNumberMsg' text; the step does not advance. — small → clear — server no — **HOLDS**
- `G-074` Step 3: licence expiry date not chosen. — *sees:* Toast with ⚠️, field name as title and 'selectLicenseExpiry' text; the step does not advance. — small → clear — server no — **HOLDS**
- `G-078` Date pickers limit what can be chosen: birth year from 100 years ago to 15 years ago; licence expiry year from this year to +20 years. — *sees:* Only those years appear in the dropdown. — silent → silent — server no — **HOLDS**
- `G-080` At sign-up the server reports the e-mail is already taken (Supabase anti-enumeration: user with empty identities and no session); registration is refused and the customer is sent back to step 1. — *sees:* Wizard jumps to step 1 and a toast with 'emailTakenTitle' / 'emailTakenBody' (9 s). — small → clear — server yes(Supabase Auth signUp) — **HOLDS**

**S-026 Registration screen / Registration**

- `G-081` Any other server refusal at sign-up (weak password, invalid e-mail, rate limit, network, unknown); nothing is created and, for field errors, the wizard returns to the step with the field. — *sees:* Toast ✗ with mapped title + explanation, 9 seconds. — small → clear — server yes(Supabase Auth signUp) — **HOLDS**

**S-026 Registration screen / Registration step 1**

- `G-059` Step 1: first name shorter than 2, with digits/symbols, or with 3+ identical letters in a row; registration cannot continue. — *sees:* Toast with ⚠️, field name as title and 'validNameMsg' text; the step does not advance. — small → clear — server no — **HOLDS**
- `G-062` Step 1: phone not '+' followed by 8-14 digits (spaces, dashes, brackets ignored). — *sees:* Toast with ⚠️, field name as title and 'validPhoneMsg' text; the step does not advance. — small → clear — server no — **HOLDS**
- `G-064` Step 1: customer younger than 18 years; registration is refused. — *sees:* Toast with ⚠️, field name as title and 'mustBe18' text; the step does not advance. — small → small — server no — **HOLDS**
- `G-066` Step 1: password shorter than 8 characters. — *sees:* Toast with ⚠️, field name as title and 'passwordMinLengthMsg' text; the step does not advance. — small → clear — server yes(Supabase Auth has its own minimum; weak_password is mapped back to st…) — **HOLDS**

**S-026 Registration screen / Registration step 2**

- `G-072` Step 2: street shorter than 3 characters. — *sees:* Toast with ⚠️, field name as title and 'validStreetMsg' text; the step does not advance. — small → clear — server no — **HOLDS**

**S-026 Registration screen / Registration step 3**

- `G-075` Step 3: driving licence expires sooner than 14 days from today; registration is refused. — *sees:* Toast with ⚠️, field name as title and 'licenseMinValid' text; the step does not advance. — small → clear — server no — **HOLDS**
- `G-076` Step 3: the two mandatory consents (terms/VOP and personal data/GDPR) are not both ticked; registration cannot be finished. — *sees:* Toast ⚠️ 'regConsentTitle' + 'consentRequiredMsg'. — small → clear — server no — **HOLDS**
- `G-077` Step 3: the licence category can only be A2 or A, A2 preselected; no other group can be registered. — *sees:* Dropdown with two entries. — clear → clear — server yes(app_save_full_profile / set_my_license_group keep only AM/A1/A2/A/B/N) — **HOLDS**

**S-026 Registration screen / S-020 Discard confirmation / S-028 Discard registration on back / Registration**

- `G-079` The customer goes back from step 1 after typing something (name, password, birth date, changed e-mail or phone); the app asks whether to throw the data away and only leaves on 'Discard'. — *sees:* Dialog 'eoDiscardTitle' / 'eoDiscardBody' with red 'Discard' and 'Stay'. — clear → clear — server no — **HOLDS**

**S-026 Registration screen / S-027 'E-mail už je registrovaný' dialog / Registration step 1**

- `G-068` Step 1: the e-mail already has an account (also accounts created automatically by a web booking); the customer cannot go to step 2 and is offered login instead. — *sees:* Dialog 'emailTakenTitle' / 'emailTakenBody' with Cancel / Log in (see S-027). — clear → clear — server yes(check_web_booking_email; Supabase Auth rejects duplicate sign-up) — **HOLDS**

**S-029 Welcome overlay after registration**

- `G-082` After a successful sign-up a full-screen welcome is shown that cannot be dismissed by tapping the barrier; it closes after 2.8 s or on tap, and then the app always goes to Home (no way back into the finished registration). — *sees:* Dark overlay 'registerComplete' / 'welcomeToMotoGo', then Home. — clear → clear — server no — **HOLDS**

**S-030 Password reset screen**

- `G-083` Back on step 1 (or the back arrow 'backToLogin') always goes to the login screen, never closes the app. — *sees:* Login screen. — clear → clear — server no — **HOLDS**

**S-031 Password reset steps 1-3**

- `G-084` Step 1: the e-mail is empty or has no '@'; no code is sent. — *sees:* Toast ⚠️ 'email' + 'validEmailMsg'. — small → small — server yes(send-recovery-otp answers the same for unknown addresses - anti-enume…) — **HOLDS**
- `G-085` Step 1: the code e-mail cannot be sent (server >= 500, network, limit); the customer stays on step 1. — *sees:* Toast ✗ 'eoCodeSendFail' + reason, 7 s. — small → clear — server yes(send-recovery-otp edge function) — **HOLDS**
- `G-086` Step 1/2: the code is requested again within 60 seconds for the same address; the server silently sends no new e-mail but answers success. — *sees:* 'Code sent' toast although no new mail goes out. — silent → silent — server yes(send-recovery-otp cooldown) — **HOLDS**
- `G-087` Step 1: an unknown e-mail is not revealed; the flow continues to the code step but no code arrives, so the customer cannot get further. — *sees:* Step 2 'enter code' as usual. — silent → silent — server yes(send-recovery-otp anti-enumeration) — **HOLDS**
- `G-088` Step 2: fewer than 8 digits typed; the code is not checked. The field accepts digits only and at most 8. — *sees:* Toast ⚠️ 'codeLabel' + 'enter8DigitCode'. — small → small — server yes(Supabase Auth verifyOTP rejects a wrong code) — **HOLDS**
- `G-089` Step 2: the code is wrong or expired; the customer stays on step 2. — *sees:* Toast ✗ 'eoOtpVerifyFail' + reason, 8 s. — small → clear — server yes(Supabase Auth verifyOTP) — **HOLDS**
- `G-090` Step 2: 'Resend code' is disabled while a request runs. — *sees:* Greyed-out link. — clear → clear — server yes(send-recovery-otp cooldown) — **HOLDS**
- `G-091` Any step: the main button (Send code / Verify / Set password) cannot be pressed twice while the request runs. — *sees:* Spinner in the button, button inactive. — clear → clear — server no — **HOLDS**
- `G-092` Step 3: new password shorter than 8 characters; it is not saved. — *sees:* Toast ⚠️ 'password' + 'passwordMinLengthMsg'. — small → small — server yes(Supabase Auth updateUser enforces its own minimum; value not visible…) — **HOLDS**
- `G-093` Step 3: the two new passwords differ; nothing is saved. — *sees:* Toast ⚠️ 'password' + 'passwordsNoMatch'. — small → small — server no — **HOLDS**
- `G-094` Step 3: saving the new password fails on the server; the customer stays on step 3. — *sees:* Toast ✗ 'eoPwSaveFail' + reason, 8 s. — small → clear — server yes(Supabase Auth updateUser) — **HOLDS**
- `G-095` Step 3 success: the temporary recovery login is signed out and the customer must log in again with the new password. — *sees:* Toast 'passwordChanged' / 'loginWithNewPassword' and the login screen. — clear → clear — server no — **HOLDS**
- `G-096` Back on step 2 or 3 goes to the previous step (typed e-mail and code kept); only step 1 can leave the screen. Known gap in BOTH looks: after a verified code (step 3) the customer can go back to step 1 and to login without setting a new password; the recovery… — *sees:* Previous step; from step 1 the login screen (or Home if the recovery login is active). — clear → clear — server no — **HOLDS**

### Documents and profile (my documents, scanner, profile, permissions) — 118 safeguards, 4 weaker

**S-139**

- `G-521` A customer who is not logged in opens /docs/scan (deep link /app/docs/scan); the route itself is not login-protected, but every photo upload is refused without a session. — *sees:* The scan runs, then the error overlay "Nepodařilo se přečíst" with the save-failed text; after 3 tries the "Pomůžeme vám osobně" contact overlay. No redirect to login. — small → small — server yes(save-verification-document and scan-document both call resolveDocCall…) — **HOLDS**
- `G-522` The customer leaves the scanner with the system back gesture or the header arrow at any time; there is no navigation lock (no PopScope) in either look, the route is wrapped in MgBackGuard so back never strands the customer. — *sees:* Green back arrow top-left on every step; system back works. — clear → clear — server no — **HOLDS**
- `G-523` Floating buttons (pending-booking FAB, route FAB, docs FAB, SOS FAB, cart FAB) cannot appear over the scanner, so the customer is not pulled away mid-scan. — *sees:* No floating buttons on the scanner. — silent → clear — server no — **HOLDS**

**S-140**

- `G-524` While the "only missing sides" plan loads, the customer cannot choose a document or start the camera; the load is capped at 20 s and falls back to the full flow if the status cannot be read. — *sees:* Dark screen with header "Skenování dokladů", back arrow and a green spinner. — clear → clear — server unknown — **HOLDS**
- `G-525` If the plan filter would leave no step (only-set does not match the chosen document), the scanner falls back to all steps of that document rather than finishing with nothing photographed. — *sees:* The normal full set of sides for the chosen document. — silent → silent — server no — **HOLDS**

**S-141**

- `G-526` The camera cannot start until the customer picks the identity document type (ID card, passport or licence only); the camera is initialised only from _selectIdType. — *sees:* Heading "Vyberte doklad totožnosti" and white buttons Občanský průkaz / Cestovní pas / Jen řidičák. — clear → clear — server no — **HOLDS**
- `G-527` The "Jen řidičák" (licence only) option is not offered when the plan says the identity document is still missing (missing / missing_id modes), so the customer cannot skip the ID. — *sees:* The licence-only button is simply absent. — silent → small — server no — **HOLDS**
- `G-528` When opened with ?mode=dl_only or when the plan already knows the document type, the choice screen is skipped and only the planned sides are scanned. — *sees:* Camera opens directly on "Řidičský průkaz – přední strana". — clear → clear — server no — **HOLDS**
- `G-529` The choice screen tells the customer what has to be photographed (old: only a heading; the requirement that both ID and licence are needed is not stated). — *sees:* Heading "Vyberte doklad totožnosti", three buttons, three trust badges. — small → clear — server no — **HOLDS**

**S-142**

- `G-530` The shutter cannot be pressed twice or while a photo is being processed; capture is refused when the camera is not ready. — *sees:* Shutter shows a spinner and ignores taps. — clear → clear — server no — **HOLDS**
- `G-531` While the photo is read and uploaded, the shutter and Skip are hidden and a full-screen processing overlay shows progress (attempt n/3, saving). — *sees:* Dark overlay, green spinner, "Zpracovávám..." / "Pokus 2 ze 3" / "Ukládám...". — clear → clear — server no — **HOLDS**
- `G-532` During upload the back arrow stays usable (header is drawn above the processing overlay); in released 4.1.3 the processing overlay covered the arrow, but system back always worked there, so it was never a real lock. — *sees:* Back arrow visible over the dark processing overlay. — clear → clear — server no — **HOLDS**
- `G-533` Every side can be skipped (Skip under the shutter); skipping is not blocked on the spot but the missing side is reported at the end and door codes stay withheld. — *sees:* Small grey "Přeskočit →" under the shutter. — small → small — server yes(get_docs_gate_checklist / booking_docs_gate) — **HOLDS**
- `G-534` A side counts as done only when the photo was really stored and the server returned a document row; OCR failure alone never fails the side, but a failed upload does. — *sees:* Success overlay "Naskenováno" only after a stored photo; otherwise the warning overlay. — clear → clear — server yes(save-verification-document creates the documents row; get_docs_gate_c…) — **HOLDS**
- `G-535` When OCR could not read the required fields of a side, the side still passes (photo stored, mindee_status failed for staff review) and the customer is told that codes come only after all sides and valid data. — *sees:* Green "Naskenováno" overlay with the text "Fotka dokladu byla uložena. Údaje se nepodařilo automaticky přečíst ... Přístupové kódy dostanete po ...". — small → small — server yes(save-verification-document stores mindee_status; get_docs_gate_checkl…) — **HOLDS**
- `G-536` When the app goes to background the camera is released and only re-opened on return if a document type is chosen and there is no camera error (prevents a crash on a disposed controller). — *sees:* Spinner on return until the camera is ready again. — silent → silent — server no — **HOLDS**
- `G-537` The customer always sees which side is being photographed and how many remain. — *sees:* Title "🪪 Občanský průkaz", "Přední strana 1/4" and progress dots. — clear → clear — server no — **HOLDS**

**S-143**

- `G-538` No camera on the device: the scanner cannot continue and offers retry or back (no settings button). — *sees:* 📷 icon, "Kamera není dostupná", gallery hint, buttons Zkusit znovu / Zpět. — clear → clear — server no — **HOLDS**
- `G-540` When the camera fails the customer is pointed to the gallery upload in Moje doklady as the alternative. — *sees:* Small grey hint under the error. — small → clear — server no — **HOLDS**
- `G-541` After a camera error, returning from background does not silently retry; the customer must press Retry (keeps the error visible). — *sees:* Error stays on screen until Retry. — clear → clear — server no — **HOLDS**

**S-143 / Document scanner**

- `G-539` Camera permission denied: the scanner stops and explains; "Otevřít nastavení" is offered only when the system settings can fix it. — *sees:* Text "errCameraPermission", gallery hint, Otevřít nastavení / Zkusit znovu / Zpět. — clear → clear — server no — **HOLDS**

**S-144**

- `G-542` After a successful side the result overlay covers the camera and the only action is Continue; the customer cannot shoot again or leave via the on-screen arrow until they acknowledge. — *sees:* ✅ "Naskenováno", side name, recognised fields, green "Pokračovat →". — clear → clear — server no — **HOLDS**
- `G-543` After a failed side the overlay offers only Retry or Skip and shows how many attempts are left. — *sees:* ⚠️ "Nepodařilo se přečíst", reason, guidance box, amber "Zbývá pokusů: 2", white "Zkusit znovu", grey "Přeskočit". — clear → clear — server no — **HOLDS**
- `G-544` The failure reason distinguishes no internet, timeout, failed save and unreadable photo, so the customer knows what to fix. — *sees:* Reason text plus a guidance box ("Nafoťte znovu PŘEDNÍ stranu OP ..."). — small → small — server no — **HOLDS**
- `G-545` When the back of the driving licence shows a different licence number than the front, the side still succeeds but the customer is warned to re-photograph both sides. — *sees:* Inside the green "Naskenováno" overlay, under the field list, a line starting with ⚠️ "Číslo ŘP na zadní straně (…) neodpovídá přední straně (…)". — small → small — server no — **WEAKER (minor)**
- `G-546` When saving the recognised data to the profile fails, the side succeeds (photo stored) but the customer is told some data must be filled in manually. — *sees:* Line "⚠️ Fotka uložena. Některá data se nepodařilo uložit do profilu – můžeš je doplnit ručně." under the fields in the success overlay. — small → small — server no — **WEAKER (minor)**

**S-145**

- `G-547` After 3 failed attempts on one side the scanner stops offering Skip/Retry and shows a help overlay with call, e-mail, try once more, or close. — *sees:* 📞 "Pomůžeme vám osobně", side, explanation, green "Zavolat +420 774 256 271", white "Napsat info@motogo24.cz", "Zkusit přesto ještě jednou", "Zavřít skener". — clear → clear — server no — **HOLDS**
- `G-548` "Try once more" resets the attempt counter of that side, so the customer can keep retrying after talking to support. — *sees:* Grey text button "Zkusit přesto ještě jednou". — small → small — server no — **HOLDS**
- `G-549` The attempt counter is per side and is cleared when that side succeeds. — *sees:* Attempts-left counter restarts at the next side. — small → small — server no — **HOLDS**

**S-146**

- `G-550` At the end the app asks the server gate which sides are still missing; if any side is missing it warns that door codes will not come until it is added (no "verified" claim). — *sees:* Toast ⚠️ "docsScanIncompleteTitle" with "Některá strana dokladu chybí ... Chybí: …" for 6 s. — clear → clear — server yes(get_docs_gate_checklist; door codes held by booking_docs_gate) — **HOLDS**
- `G-551` If the gate cannot be asked (offline/timeout) the app does not claim verification, says the result will be in Moje doklady and goes there. — *sees:* Toast ⏳ "Skenování dokončeno" + pending text, then the documents screen. — clear → clear — server yes(get_docs_gate_checklist) — **HOLDS**
- `G-553` If the gate does not answer, completeness falls back to the sides of this scan (ID front+back, passport one side, licence front+back); a skipped required side gives the "incomplete" warning. — *sees:* Toast ⚠️ "docsScanIncompleteTitle" + "docsScanIncomplete". — clear → clear — server no — **HOLDS**
- `G-554` The scanner calls verify_customer_docs at the end, but its result (name/DOB/licence mismatches) is ignored and errors are swallowed; the customer is never told about a mismatch here. — *sees:* Nothing. — silent → silent — server yes(verify_customer_docs RPC, SECURITY DEFINER, per SUPABASE_BACKEND_STAT…) — **HOLDS**
- `G-555` After the scan the customer is returned to Moje doklady (dl_only or missing modes, or gate unreachable) or to Home (full flow); the doc-status providers are refreshed so other screens re-check documents. — *sees:* Lands on Moje doklady or Home. — clear → clear — server no — **HOLDS**
- `G-556` The "Scan complete / verifying" screen is never reached: _stepIdx is never moved past the last step, so during _finalize the camera screen stays with the shutter (a no-op, camera disposed) and Skip still visible; tapping Skip again on the last step runs _fina… — *sees:* Spinner where the camera was, shutter and "Přeskočit" still visible for ~0.5-15 s while the "Ověřuji doklady" toast is shown. — silent → silent — server no — **HOLDS**

**S-146 / Document scanner (finish)**

- `G-552` All sides are present but the gate still withholds codes (missing date of birth, under 18, expired licence, wrong licence group): the app says codes are still withheld and lists why. — *sees:* Toast ⚠️ "Skenování dokončeno" with "codesStillWithheld … Chybí: věk 18+, platnost ŘP …" for 6 s. — clear → clear — server yes(get_docs_gate_checklist / booking_docs_gate) — **HOLDS**

**S-021 Blocking progress dialog (MgProgress) / S-128 Scan buttons**

- `G-487` Gallery processing: progress with attempt counter, 'Zrušit' only after 20 s, hard limit 150 s; a cancelled or timed-out upload that finishes later still refreshes the status. — *sees:* Progress dialog 'Zpracovávám doklad · pokus n/3', cancel after 20 s, toast 'Nahrávání zastaveno' on cancel. — clear → clear — server unknown — **HOLDS**

**S-021 Blocking progress dialog (MgProgress) / S-134 Invoices / S-135 Contracts**

- `G-505` Opening an invoice: one document at a time (double-tap lock), progress with 'Zrušit' after 15 s, 60 s limit, late result discarded; without the profile (offline) the invoice is NOT rendered without the buyer — reason + retry. — *sees:* Progress dialog, then the invoice; on failure 'Doklad se nepodařilo otevřít' + why + 'Zkusit znovu'. — clear → clear — server no — **HOLDS**

**S-127 Documents screen**

- `G-477` A customer who is not signed in opens /docs (deep link, old bookmark); the route is NOT in the login-required list, so the screen opens, but every data source refuses to act without a session. — *sees:* Screen shows 'Doklady neověřeny' with both rows unverified; an upload attempt ends in the generic 'scan failed / use camera' toast. No login prompt. — small → small — server yes(save-verification-document requires a valid user_id / booking owner;…) — **HOLDS**
- `G-478` Back from Moje doklady when the screen was reached with context.go (thank-you page, FAB) and nothing is on the stack: the back arrow must not leave an empty stack. — *sees:* Back arrow returns to the previous screen or to Profile. — clear → clear — server no — **HOLDS**
- `G-479` Status of documents is decided by the server docs gate (both sides of ID or passport, both sides of licence, 18+, licence validity, licence group); without a gate answer it falls back to profile *_verified_at and never promises codes. — *sees:* All banners, rows and the green 'codes ready' box are computed from this one status. — clear → clear — server yes(get_docs_gate_checklist -> _docs_gate_checklist, STATE_3 lines 187/19…) — **HOLDS**
- `G-480` Status cannot be loaded (network / server error): the customer must not see a false 'verified' state; an error with retry is shown instead. — *sees:* Error box 'Nepodařilo se načíst stav dokladů' with why and 'Zkusit znovu'. — clear → clear — server no — **HOLDS**
- `G-481` Warning that BOTH documents are needed to book; shown only while ID/passport or licence is missing. — *sees:* Amber box with ⚠ icon: 'Both documents are required …' (body text only, no heading). — small → small — server no — **HOLDS**
- `G-482` Saved-photo upload path from the gallery is refused while offline (checked before any work) instead of hanging in a modal. — *sees:* Snack 'Doklad se nepodařilo nahrát – nejsi připojený' with 'Zkusit znovu'. — clear → clear — server no — **HOLDS**

**S-128 Scan buttons**

- `G-483` Main camera scan: always available in the old look (full flow: choose ID/passport/DL-only, then all sides). — *sees:* Green 'NASKENOVAT DOKLADY KAMEROU' button. — clear → clear — server yes(save-verification-document + docs gate decide what counts; scanner fi…) — **HOLDS**
- `G-485` Upload from gallery requires choosing WHICH document and side first; cancelling the sheet stops the upload (otherwise the photo would be saved as an ID without side and never count for codes). — *sees:* Bottom sheet 'Co je na fotce?' with 5 choices; nothing happens until one is tapped. — clear → clear — server yes(save-verification-document stores doc_side in metadata; gate needs tw…) — **HOLDS**
- `G-486` Gallery permission denied: picking a photo throws; the customer is told why and offered the settings. — *sees:* Snack with reason and 'Otevřít nastavení'. — clear → clear — server no — **HOLDS**
- `G-488` Gallery result: success only if the photo row really exists on the server; network/server failure -> real reason + retry with the same photo; OCR/upload failure -> steer to the camera scanner. — *sees:* Toast '✅ Nahráno', or error snack with retry, or toast '⚠️ Sken selhal – naskenuj doklad kamerou'. — clear → clear — server yes(save-verification-document: user_id must exist, booking must belong t…) — **HOLDS**

**S-128 Scan buttons / S-139**

- `G-484` Which sides the scanner asks for depends on the entry point: the old look opens the full flow (choose ID + all sides) or ?mode=dl_only; the per-document scan button is removed once that document is verified. — *sees:* Green "Naskenovat doklady kamerou" button; "Naskenovat pouze ŘP" only when ID is verified and DL is missing; no scan button on a verified document row. — clear → clear — server yes(docs gate counts licence sides, STATE_3:187) — **HOLDS**

**S-129 Verification status card**

- `G-489` Top status banner: 'Doklady ověřeny' only when ID/passport AND licence are complete per gate; otherwise 'Doklady neověřeny — Chybí: …'. — *sees:* Green or amber banner with heading. — clear → clear — server yes(get_docs_gate_checklist identity_ok/license_ok) — **HOLDS**
- `G-490` Nothing uploaded at all (no ID/passport and no licence): explicit warning that the motorcycle can be booked but the key-box code comes only after verification, plus the gate's 'Chybí' line. — *sees:* Amber block headed '⚠ Doklady neověřeny' + 'Kód k boxu dostaneš až po ověření dokladů'. — clear → small — server yes(trg_zz_door_codes_docs_gate withholds codes, STATE_4:42) — **WEAKER (minor)**
- `G-491` Sides uploaded but the gate still withholds codes (missing back side, no date of birth, under 18, licence expired / no expiry, licence group too low): one 'Chybí: …' line from the gate. — *sees:* Small 11 px brown line 'Chybí: rub ŘP, platnost ŘP …' under the rows (no heading); the top banner may even say 'Doklady ověřeny' when only age/expiry/group fail. — small → clear — server yes(_docs_gate_checklist missing[]/reason; check_booking_docs_status reas…) — **HOLDS**

**S-129 Verification status card / My documents**

- `G-492` Green 'codes ready' confirmation is shown only when the server gate says ok (never on profile fallback alone). — *sees:* Green box '✅ Doklady ověřeny — kódy k vyzvednutí'. — clear → clear — server yes(get_docs_gate_checklist ok) — **HOLDS**

**S-130 Document rows**

- `G-493` Delete is offered only on a document that is verified; an unverified row has no delete. — *sees:* Red 'Smazat' chip + ✓ on verified rows only. — clear → clear — server unknown — **HOLDS**
- `G-494` Scan shortcut on a row is offered only when that document is NOT verified (ID row -> scan, licence row -> licence scan). — *sees:* Green 'Skenovat' chip; tapping the row opens the scanner. — clear → clear — server yes(gate re-check at scanner finalisation) — **HOLDS**
- `G-495` Row state is shown per document (Ověřeno / Neověřeno) from the gate, so an ID with only one side counts as NOT verified. — *sees:* Row text 'Neověřeno' in grey, green tint when verified. — small → clear — server yes(_docs_gate_checklist identity_ok/license_ok) — **HOLDS**

**S-131 Docs gate missing line**

- `G-497` Child motorcycle (licence not required) in a booking query: gate answer marks all requirements as met so nothing is listed as missing. — *sees:* No 'Chybí' line for that case. — silent → silent — server yes(_docs_gate_checklist child:true, STATE_3:187) — **HOLDS**

**S-131 Docs gate missing line / My documents**

- `G-496` The 'Chybí' line lists exactly what still holds the access codes, in a fixed order: identity side(s), licence side(s), date of birth / 18+, licence expiry / expired on DATE, licence group (with required group). — *sees:* One small brown line 'Chybí: …'. — small → clear — server yes(_docs_gate_checklist missing[], STATE_3:187) — **HOLDS**

**S-132 Gallery kind sheet**

- `G-498` Passport is offered as one side only; ID card and licence must be chosen with front/back, so a gallery photo always lands with a side (needed by the gate). — *sees:* List: OP – líc, OP – rub, Pas, ŘP – líc, ŘP – rub. — clear → clear — server yes(gate requires two different side files for ID and licence, STATE_3:187) — **HOLDS**

**S-133 Delete confirmation**

- `G-500` Delete result is reported honestly: progress toast, then success or 'deleteFailed'; status and gate are re-read. — *sees:* Toast '⏳ Mažu', then '✅ Smazáno' or '❌ Chyba – smazání se nepodařilo'. — clear → clear — server unknown — **HOLDS**

**S-133 Delete confirmation / My documents**

- `G-499` Deleting a verified document always asks for confirmation; anything except an explicit 'Smazat' (cancel, tap outside, back) aborts. — *sees:* Dialog 'Smazat doklad?' with description, 'Zrušit' and red 'Smazat'. — clear → clear — server no — **HOLDS**

**S-134 Invoices**

- `G-501` Only the customer's own invoices are listed. — *sees:* Own invoices grouped by year. — silent → silent — server yes(RLS invoices customer SELECT customer_id=uid) — **HOLDS**
- `G-502` No invoices yet: empty state explains they are generated automatically. — *sees:* 🧾 'Zatím žádné doklady' + 'Doklady se vystaví automaticky'. — clear → clear — server no — **HOLDS**
- `G-503` Loading never spins silently: after 15 s 'trvá to déle' with retry / back; error shows what/why plus retry and back. — *sees:* Spinner then slow state; error box with 'Zkusit znovu'. — clear → clear — server no — **HOLDS**
- `G-504` Credit note is marked as such: amount shown with '−' and in red so it is not mistaken for a charge. — *sees:* Red border, red number and '−1 234 Kč'. — clear → clear — server no — **HOLDS**

**S-135 Contracts**

- `G-506` The list shows only real documents of this customer: contract, handover protocol, damage protocol, VOP; template-prefilled protocols (not signed) and other types (invoices, gdpr) are filtered out. — *sees:* Only signed/real documents with dates. — silent → silent — server yes(RLS documents/generated_documents per user; submit-handover-protocol…) — **HOLDS**
- `G-507` Static legal documents (VOP, GDPR, damage-protocol sample) stay reachable even when the list fails to load; list error shows what/why + retry. — *sees:* Three tiles always; error box under them. — clear → clear — server no — **HOLDS**
- `G-508` A protocol that has no real signed document is NEVER replaced by an empty template: offline -> real reason; online -> 'Dokument zatím není k dispozici'. — *sees:* Toast '📄 … Dokument zatím není k dispozici' or offline error with retry. — clear → clear — server no — **HOLDS**
- `G-509` Contract/VOP without a real file: rendered from the template in the app language (fresh translation or binding Czech with a note); without a template because of the network -> offline error; without a template otherwise -> 'not available yet' page (no improvi… — *sees:* Document with a yellow note 'binding is the Czech text', or a message page. — clear → clear — server yes(get_document_translation RPC; generate-document template rules, STATE…) — **HOLDS**
- `G-510` VOP / GDPR open with the legal note 'consent given at booking'; load failure shows a localized message page instead of an outdated text. — *sees:* Web view with the text and a green '✓ souhlas udělen při rezervaci' note, or the message 'legalLoadFailed'. — clear → clear — server no — **HOLDS**
- `G-511` Damage-protocol sample: placeholders are blanked so no raw {{customer_name}} is shown; failure shows a message page. — *sees:* Sample with '—' in empty fields. — clear → clear — server no — **HOLDS**

**S-136 Document web view**

- `G-512` Main-frame load error is shown with a reason (offline / timeout / server) and retry; errors of images or fonts inside the document do not hide it. — *sees:* Error page 'Dokument se nepodařilo načíst' + why + 'Zkusit znovu' / 'Zpět'. — clear → clear — server no — **HOLDS**
- `G-513` Retry of a stored file asks for a NEW signed URL (old one valid 10 min); failure to refresh shows the error again. — *sees:* Error page again if the refresh fails. — clear → clear — server yes(storage createSignedUrl 600 s, RLS bucket documents, STATE_5:252) — **HOLDS**
- `G-514` Loading never hangs silently: after 15 s 'trvá to déle' with retry and back. — *sees:* Spinner, then slow-state text with buttons. — clear → clear — server no — **HOLDS**
- `G-515` Close/back pops only the viewer (maybePop). — *sees:* Back arrow. — clear → clear — server no — **HOLDS**

**S-137 PDF pages viewer**

- `G-516` PDF render failures (HTTP not 200 incl. expired link, 30 s download limit, PDF without pages) show reason + retry (with a fresh signed URL) + 'Otevřít mimo aplikaci' so the customer is never stuck. — *sees:* Error page with 'Zkusit znovu', 'Zpět' and 'Otevřít mimo aplikaci'. — clear → clear — server yes(storage signed URL 600 s) — **HOLDS**
- `G-517` Loading shows the slow state after 15 s with retry/back. — *sees:* Spinner then slow state. — clear → clear — server no — **HOLDS**
- `G-518` Native PDF rendering only on Android; on iOS the PDF goes to the web view. — *sees:* PDF pages (Android) or web view (iOS). — silent → silent — server no — **HOLDS**

**S-138 Booking document opening flow**

- `G-519` Only REAL documents open: a template-prefilled protocol (generated when Velín switches a booking to active) and marker paths 'mindee_verified/…' are never shown as the customer's protocol. — *sees:* Nothing or 'zatím není k dispozici' instead of a fake protocol. — silent → small — server yes(submit-handover-protocol writes _doc_type electronic protocols; gener…) — **HOLDS**
- `G-520` Customer cancelled the wait: a late result must not suddenly open a document. — *sees:* Nothing opens after 'Zrušit'. — silent → silent — server no — **HOLDS**

**Document scanner -> profile write rules**

- `X-1-05` The customer scans a document; the scan must not overwrite the licence group or licence expiry the customer entered, the back of the licence must not change the number or expiry, the back of the ID writes only the address, and only groups A, A1, A2, AM, B are… — *sees:* The scan result screen lists the read fields; a licence-number mismatch between front and back or a failed save is appended as a warning (document_scanner_screen.dart:289-294). The protection itself… — silent → silent — server no — **HOLDS**

**S-019 Shared error dialog / S-156 Permissions screen**

- `G-753` "Allow all again": the permissions are requested again and, if some are still missing (permanently denied), the customer gets a dialog naming them with a button to open phone settings instead of a false "done". — *sees:* A success toast, or a dialog listing the missing permissions. — clear → clear — server no — **HOLDS**

**S-147 Profile**

- `G-724` When the profile screen opens, the cached profile is thrown away and reloaded so that a stale or empty cache (right after registration) is never shown or edited. — *sees:* A short loading state, then fresh data. — silent → silent — server no — **HOLDS**
- `G-725` While the profile is still loading the menu stays usable but personal data cannot be edited yet. — *sees:* A thin green progress bar above the menu. — small → clear — server no — **HOLDS**
- `G-726` The profile fails to load (offline, server error); the customer gets an error panel with a retry instead of an empty form. — *sees:* A compact error card "Profile could not be loaded" with a Retry button above the menu. — clear → clear — server no — **HOLDS**
- `G-727` The loyalty rank card (discount 1-20 % for app bookings) is hidden until the backend returns a rank, so no wrong discount is shown. — *sees:* Nothing until the rank is known. — silent → silent — server yes(loyalty status computed server-side; the card only displays it) — **HOLDS**
- `G-728` Back from the profile goes to the previous screen or Home, never out of the app. — *sees:* A back arrow in the dark header. — clear → clear — server no — **HOLDS**

**S-148 Personal info form**

- `G-729` The customer taps "Osobní údaje" before the profile has loaded (or after a load error); the form does not open, because an empty form saved would wipe the data. — *sees:* A toast "Profile is still loading - give it a moment" or an error snack with Retry; the form stays closed. — small → small — server no — **HOLDS**
- `G-732` The customer picks a driving-licence expiry: years start at the current year (an already saved expired year stays visible so it can be corrected). — *sees:* Only current and future years are offered. — silent → silent — server yes(_docs_gate_checklist checks licence validity before door codes are re…) — **HOLDS**
- `G-733` The customer can choose only the licence categories AM, A1, A2, A and B. — *sees:* Five toggle chips. — silent → silent — server yes(set_my_license_group keeps only AM/A1/A2/A/B/N, SUPABASE_BACKEND_STAT…) — **HOLDS**
- `G-734` Saving: the licence group is saved by a separate RPC; if that RPC fails the app does NOT say "Saved" but shows an error with Retry (the group decides door-code release). — *sees:* An error snack "We saved your details, but not your licence category" with Retry. — small → small — server yes(set_my_license_group SECURITY DEFINER; door-code gate reads license_g…) — **HOLDS**
- `G-735` Saving fails (offline, server error) or the session has expired; an expired session signs the customer out, other errors show a message with Retry. — *sees:* An error snack with Retry, or the login screen. — small → small — server yes(profiles RLS UPDATE id = auth.uid() — **HOLDS**
- `G-736` Save is pressed with no logged-in user (session gone between frames); nothing is written. — *sees:* Nothing happens. — silent → silent — server yes(RLS) — **HOLDS**

**S-148 Personal info form / Profile**

- `G-730` The customer wants to change the e-mail address; the e-mail field is read-only (it is the login identity). — *sees:* A greyed field that cannot be typed into. — silent → clear — server yes(_trg_guard_customer_profile_columns keeps profiles.email on a direct…) — **HOLDS**
- `G-731` The customer tries to enter a date of birth that makes them younger than 18; the year list simply ends at (this year - 18). An already saved younger year stays in the list. — *sees:* No year under 18 is offered. — silent → silent — server yes(_docs_gate_checklist 18+ withholds door codes; trg_release_codes_on_p…) — **HOLDS**

**S-149 My account menu**

- `G-737` Unread messages from MotoGo are flagged with a red count badge on "Zprávy" (9+ above nine). — *sees:* A red number badge on the Messages row. — clear → clear — server no — **HOLDS**
- `G-739` Payment methods opens the saved-cards screen through the same push (its own guards are on that screen). — *sees:* The payment methods screen. — silent → clear — server no — **HOLDS**

**S-149 My account menu / S-168 E-shop**

- `G-738` A customer looks for the e-shop in the Profile menu, but the e-shop entry is hidden while the feature flag eshop_visible is off (and also when the flag cannot be loaded or the row is missing). — *sees:* No 'E-shop' row in the Profile menu at all; only 'Pobocky' is shown in its place. — silent → silent — server yes(feature_flags row eshop_visible) — **HOLDS**

**S-151 Consent sheet**

- `G-741` When the sheet opens during a rental, any consent that was switched off in the database is silently switched back on. — *sees:* All ticks on. — silent → silent — server no — **HOLDS**
- `G-742` The consents cannot be loaded (offline, no profile); an error with Retry and Close is shown and Save is hidden so nothing wrong is saved. — *sees:* An error card with Retry and Close; no Save button. — clear → clear — server no — **HOLDS**
- `G-743` Save is disabled while the consents are loading or while saving, so an empty or double save cannot happen. — *sees:* A disabled button / spinner on the button. — clear → clear — server no — **HOLDS**
- `G-744` Saving the consents fails; the reason is shown inside the sheet, which stays open with the chosen ticks. — *sees:* A red line of text above Save. — small → small — server no — **HOLDS**

**S-151 Consent sheet / Profile – consents**

- `G-740` During an active or paid upcoming reservation the customer tries to switch off a notification or privacy consent; it is refused. — *sees:* A green banner with a lock "consents are required during the rental" and, on tap, a lock toast; the ticks stay on. — clear → clear — server no — **HOLDS**

**S-152 Change password sheet**

- `G-745` The new password is shorter than 8 characters; it is refused. — *sees:* A red message in the sheet. — small → small — server yes(Supabase Auth applies its own policy and returns weak_password, mappe…) — **HOLDS**
- `G-746` The confirmation does not match the new password; it is refused. — *sees:* A red message in the sheet. — small → small — server no — **HOLDS**
- `G-747` While the password is being saved the button is disabled, so it cannot be sent twice. — *sees:* A spinner on the disabled button. — clear → clear — server no — **HOLDS**
- `G-748` The server refuses the change (same password, weak password, re-authentication needed, session gone, offline); the reason stays in the open sheet. — *sees:* A red, translated reason in the sheet. — small → small — server yes(Supabase Auth updateUser) — **HOLDS**

**S-153 Language picker sheet**

- `G-749` No blocking guard: choosing a language saves it, closes the sheet and sends the customer to Home so every screen is rebuilt in the new language. — *sees:* A toast and the Home screen. — clear → clear — server no — **HOLDS**

**S-154 Currency picker sheet**

- `G-750` The customer is warned that prices are only shown converted (CNB rate) and that card payments are always charged in CZK; choosing a currency returns to Home. — *sees:* A small grey note under the title. — small → small — server unknown — **HOLDS**

**S-155 Permissions sheet**

- `G-751` No reachable guard: showPermissionsSheet (bottom sheet) has no caller; the profile row opens the full Permissions screen (/permissions) instead. — *sees:* n/a (never shown). — silent → silent — server no — **HOLDS**

**S-156 Permissions screen**

- `G-754` Turning on fingerprint/Face ID requires a successful biometric check; if the login data cannot be stored the customer is told the session expired; the option is shown only on devices that support it. — *sees:* A toast; the checkbox stays off if the check fails. — small → small — server no — **HOLDS**
- `G-755` Permission statuses are re-read when the customer returns from phone settings; a spinner shows until they are known. — *sees:* A spinner, then the current statuses. — silent → silent — server no — **HOLDS**

**S-156 Permissions screen / Profile – permissions**

- `G-752` During an active or paid upcoming reservation every permission except photos is marked as required, and a denied required permission is highlighted. — *sees:* A lock banner, a red "Required" label and a red frame around the denied row, plus a red "Denied" badge. — clear → small — server no — **WEAKER (minor)**

**S-157 Help and other: SOS, FAQ, logout**

- `G-756` The SOS entry is offered only while the customer has a rental in which SOS is allowed (active, or paid and in the rental term, not already ended by SOS). — *sees:* A red SOS row appears only during a rental. — clear → clear — server unknown — **HOLDS**

**S-157 Help and other: SOS, FAQ, logout / Profile – log out**

- `G-757` Logging out first clears the booking draft, the selected bike and the catalogue filter, so the next person on the phone does not inherit a half-made booking; there is no confirmation dialog. — *sees:* A goodbye toast and the login screen. — small → small — server no — **HOLDS**

**S-158 Delete account dialog**

- `G-759` The customer has an active or upcoming reservation; the account is not deleted and the app says why instead of claiming success. — *sees:* A warning toast "Account cannot be deleted - you have an active or upcoming reservation". — small → small — server yes(delete_customer_account returns {error:active_bookings}, SUPABASE_BAC…) — **HOLDS**
- `G-760` Deletion fails for another reason or the session has expired; the account is not reported as deleted (auth error signs out, other errors show a message). — *sees:* An error snack, or the login screen. — small → small — server yes(delete_customer_account: is_admin() — **HOLDS**

**S-158 Delete account dialog / Profile / Profile – delete account**

- `G-758` Deleting the account needs an explicit confirmation in a dialog that says it cannot be undone. — *sees:* A dialog "Delete account?" with Cancel and a red Delete. — clear → clear — server no — **HOLDS**

### Choosing a bike and dates (Home, Motorky, filters, calendar, bike detail) — 67 safeguards, 7 weaker

**S-032 Home screen (Domů)**

- `G-099` After filtering, the count line tells the customer how many bikes are left (or that they are loading / failed). — *sees:* "Zobrazeno n motorek", or a loading / red error line. — small → small — server no — **HOLDS**
- `G-100` Loading the bikes fails (offline / server); the customer gets a reason and a retry instead of a raw exception. — *sees:* Error view with an explanation and "Zkusit znovu". — clear → clear — server no — **HOLDS**
- `G-101` Only PAID active or upcoming bookings appear on Domů; an unpaid / pending, cancelled or finished booking is not shown as an active booking. — *sees:* Unpaid bookings are not listed in "Aktivní rezervace" (the unpaid reminder is the shell's floating button, not this section). — silent → silent — server no — **HOLDS**
- `G-102` From Domů the customer can only reach the booking form through the bike detail, where REZERVOVAT stays disabled until a date is chosen and a red ValidationBanner warns about licence, overlap with own bookings and min/max rental days. — *sees:* Grey disabled REZERVOVAT with "first select dates" hint; red banner with the licence / overlap / length problem before the form. — clear → clear — server yes(trg_check_booking_overlap, trg_check_user_booking_overlap, trg_check_…) — **WEAKER (minor)**
- `G-103` The v2 Home funnel offers bikes for a date range; the old Home had no such offer (owner-requested v2 addition). Check that it does not offer bikes the customer may not rent. — *sees:* Old look: no offer card. — silent → clear — server yes(trg_check_booking_overlap / trg_check_booking_branch_open at booking…) — **HOLDS**

**S-032 Home screen (Domů) / Bike list / Home list / Bike list**

- `G-098` The customer sees only bikes that may be offered: status active or maintenance, and never bikes of a permanently closed branch. — *sees:* Such bikes are simply not in the list. — silent → silent — server yes(trg_check_booking_branch_open / branch_is_closed refuse a booking at…) — **HOLDS**

**S-033 Home header with nickname**

- `G-104` The menu button opens Profil and shows a red unread-messages badge (capped at 9+). — *sees:* Green menu button with red number badge. — clear → clear — server no — **HOLDS**
- `G-105` Tapping the logo opens the ranks overview only when the backend returned a loyalty rank; without a rank the logo does nothing. — *sees:* Logo with rank ring is tappable; plain logo is not. — silent → silent — server no — **HOLDS**

**S-034 Nickname dialog**

- `G-107` Reset removes the nickname locally and from the public leaderboard; the leaderboard write happens only when logged in and fails silently. — *sees:* Name returns to the first name; the customer is no longer on the leaderboard. — clear → clear — server yes(set_loyalty_nickname, updates only the caller's own profile) — **HOLDS**

**S-034 Nickname dialog / S-147 Profile**

- `G-106` The customer clears the nickname field and presses OK; an empty or blank nickname is not saved. — *sees:* The dialog closes and the old name stays. — silent → silent — server yes(set_loyalty_nickname stores NULLIF(btrim(p_nickname) — **HOLDS**

**S-035 Loyalty rank card on Home**

- `G-108` The rank card (and its heading) is hidden while the backend returns no loyalty rank. — *sees:* No card at all. — silent → silent — server unknown — **HOLDS**
- `G-109` The 'next rank' line appears only when the customer is not at max and the next rank and missing bookings are known; otherwise 'max rank' text. — *sees:* "Ještě n rezervací do …" or the max-rank line. — small → small — server no — **HOLDS**
- `G-110` The card warns that the loyalty discount applies only to bookings made in the app. — *sees:* Small grey "★ … jen v aplikaci" line. — small → small — server unknown — **HOLDS**

**S-036 Loyalty program info sheet**

- `G-111` The info link opens the program rules (points, long rentals, levels, app-only, combination with other discounts). — *sees:* Bottom sheet with five ✓ rules. — small → small — server no — **HOLDS**

**S-037 My active reservations + SOS shortcut on Home**

- `G-112` Domů shows at most two active bookings and a 'VŠE' link to the full list. — *sees:* Two cards plus "Zobrazit vše". — clear → clear — server no — **HOLDS**
- `G-113` Without a paid active booking the customer sees 'Žádná aktivní rezervace' with a link to book. — *sees:* Grey row "Žádná aktivní rezervace / Rezervuj motorku". — clear → clear — server no — **HOLDS**
- `G-114` The red SOS card is shown only while a paid active/upcoming booking allows SOS (not already ended by SOS; status active, or inside the rental term with an SOS-allowed payment state). — *sees:* Red "NEHODA, KRÁDEŽ, PORUCHA · Okamžitá pomoc 24/7" card or nothing. — clear → clear — server unknown — **HOLDS**
- `G-115` Each booking card shows its status pill (Aktivní / Nadcházející …) and opens that booking's detail. — *sees:* Status pill and booking number + dates. — clear → clear — server no — **HOLDS**

**S-038 Motorcycle filter panel**

- `G-116` The folded filter shows how many filters are on and a red 'Resetovat' only when at least one filter is active. — *sees:* Number badge next to "Filtry" and red Reset. — clear → clear — server no — **HOLDS**
- `G-117` Reset on Rezervovat keeps the chosen dates (the calendar sits outside the panel); on Domů it clears everything including dates and sort. — *sees:* Filters cleared; dates kept on Rezervovat. — silent → silent — server no — **HOLDS**
- `G-118` With the panel folded, a chosen branch is still shown so the customer knows the list is limited to one branch. — *sees:* Green chip "Pobočka: …" under the header. — small → small — server no — **HOLDS**
- `G-120` Choosing a category shows only that category; tapping it again clears it. — *sees:* Highlighted chip, shorter list. — clear → clear — server no — **HOLDS**
- `G-121` The branch choice offers only branches that are not permanently closed; an unknown stored branch reads as 'all branches'. — *sees:* Dropdown with open branches only. — silent → silent — server yes(trg_check_booking_branch_open / branch_is_closed) — **HOLDS**
- `G-122` The power / seat height / torque / weight sliders: hidden when the data has no valid range, the end positions mean 'no limit', a stored value outside the current bounds counts as no limit, the value is written only when the thumb is released, and bikes with a… — *sees:* Slider label shows the range or 'vše'. — silent → silent — server no — **HOLDS**
- `G-123` 'Jen dnes volné' keeps only bikes confirmed free today; if the check fails the bike is hidden (fail-closed); service blocks count as busy. — *sees:* Checked box, shorter list. — clear → clear — server no — **HOLDS**

**S-038 Motorcycle filter panel / Bike list / Home**

- `G-119` Choosing a licence group shows only bikes a holder of that group may ride (A covers A2/A1/AM/N, B covers B/N, N = no licence for everyone); bikes without licence data disappear while the filter is on; tapping the chosen chip clears it. — *sees:* Highlighted chip and a shorter list. — clear → clear — server no — **HOLDS**

**S-038 Motorcycle filter panel / Bike list / Motorky (catalog list)**

- `G-124` On Domů, choosing dates in the filter keeps only bikes free for the whole range (reservation check fail-closed, service-block check fail-open, closed branches excluded). — *sees:* "TERMÍN d. m. – d. m." label and a shorter list. — clear → clear — server yes(check_moto_availability / get_moto_booked_dates are read-only; trg_ch…) — **HOLDS**

**S-039 Motorcycle list cards**

- `G-125` The 'DNES VOLNÁ' badge appears only when today's availability was confirmed (fail-closed, service blocks count). — *sees:* Green "DNES VOLNÁ" badge or none. — clear → small — server no — **WEAKER (minor)**
- `G-126` Each card shows which licence the bike needs ("ŘP A2" / "Bez ŘP") and its branch, so the customer sees early if they may ride it. — *sees:* Licence badge and red branch line. — clear → clear — server unknown — **HOLDS**

**S-039 Motorcycle list cards / S-043**

- `G-127` The list card's only action is opening the bike detail (no booking from the list); the detail pager then swipes only through the bikes the customer was shown, in the shown order. — *sees:* Card and "Detail" button open the detail. — clear → clear — server no — **HOLDS**

**S-040 Home floating buttons**

- `G-128` The scroll-to-top button appears only after the customer scrolled more than 600 px. — *sees:* Small green round arrow button. — clear → clear — server no — **HOLDS**

**S-040 Home floating buttons / S-166 AI assistant chat**

- `G-129` The AI assistant is opened only from logged-in places: the Home floating button and the SOS screen (both routes need login); /ai-agent itself is not in the router's login list, but the edge function refuses requests without a valid session. — *sees:* Round green AI button at bottom-left of Home. — clear → clear — server unknown — **HOLDS**

**S-041 Rezervovat / motorcycle search screen**

- `G-130` Rezervovat can be browsed without login; login is demanded only when the customer enters the booking form, and the back arrow (Domů) and menu (Profil) lead to protected routes. — *sees:* Guest sees the list; booking / Domů / Profil send to login. — clear → clear — server unknown — **HOLDS**
- `G-131` The search list shows only what the shared filter allows; with nothing left the customer is told 'Žádné motorky pro vybraný termín' and to try other filters. — *sees:* Motorcycle icon with the empty message. — clear → clear — server no — **HOLDS**
- `G-132` The results header tells how many bikes are free for how many days when dates are chosen, 'Hledám…' while loading. — *sees:* "Dostupné motorky: n · d dní" or "Zobrazeno motorek: n". — small → small — server no — **HOLDS**
- `G-133` Loading takes long or fails: the customer gets 'trvá to déle' / an explanation with retry. — *sees:* Loading view with retry or error view with retry. — clear → clear — server no — **HOLDS**
- `G-134` From Rezervovat the booking form is reachable only via the bike detail (dates required, ValidationBanner). Check the v2 calculator mode that also offers REZERVOVAT on this tab. — *sees:* Disabled REZERVOVAT until dates; red banner. — clear → clear — server yes(trg_check_booking_overlap, trg_check_user_booking_overlap, trg_check_…) — **HOLDS**
- `G-135` Dates have one source (catalogFilterProvider); the calendar reset clears them so the list is never filtered by dates the screen no longer shows. — *sees:* Tabs and calendar show the dates the list uses. — silent → silent — server no — **HOLDS**

**S-042 Search date tabs + availability calendar**

- `G-138` Tapping the same single day a third time clears the selection; the step text under the calendar says what to tap next. — *sees:* Grey helper line. — small → small — server no — **HOLDS**
- `G-139` On Domů and Rezervovat a lone pickup day does not filter the list; a second tap is needed (the same day twice = one-day rental), as the hint says. — *sees:* Hint line above the calendar. — small → small — server no — **HOLDS**
- `G-140` The legend explains free and occupied colours; if the dates are reset from outside mid-selection the calendar returns to 'pick pickup'. — *sees:* Legend "Volné / Obsazené". — small → small — server no — **HOLDS**

**S-042 Search date tabs + availability calendar / S-044 / S-054**

- `G-136` The customer taps a day in the past in the calendar; nothing happens. — *sees:* Past days drawn dark and not selectable. — clear → clear — server unknown — **HOLDS**
- `G-137` The customer taps a return day earlier than the chosen start day; the tap is ignored. — *sees:* Nothing happens; only the step hint "calSelectReturn" under the calendar. — silent → silent — server no — **HOLDS**

**S-043**

- `G-141` The customer opens the detail from a deep link or notification (nothing to pop) and presses back; instead of crashing ('nothing to pop') the app falls back to the catalogue. — *sees:* Green back arrow top left; goes back or to the bike list. — clear → clear — server no — **HOLDS**
- `G-142` Availability badge: the detail says 'available now' only when the bike is confirmed free today (booked/service day or failed check = badge hidden, never a false promise). — *sees:* Green tick + 'Dostupná ihned' under the photo, only when free today. — clear → clear — server yes(get_moto_booked_dates is the data source; booking blocked by trg_chec…) — **HOLDS**

**S-044**

- `G-148` The booked-days list is still loading or failed to load; the calendar would show every day as free. — *sees:* Nothing: all days look free, no loading or error message, no retry (the provider has a 15 s timeout). — silent → clear — server yes(trg_check_booking_overlap refuses an overlapping booking at creation) — **HOLDS**
- `G-149` Dates are carried into the detail from the catalogue filter (or in v2 from a draft) and the carried range contains a booked day; the detail must not offer booking of an impossible range. — *sees:* Old look: nothing in the detail; REZERVOVAT active; the clash is refused later (booking form / payment / trg_check_booking_overlap). — silent → clear — server yes(trg_check_booking_overlap) — **HOLDS**
- `G-150` Dates carried from the filter start in the past (app left open over midnight). — *sees:* Old look: past dates preselected, REZERVOVAT active; the booking form then refuses the pickup time (pickupLeadTimeValidationProvider). — silent → clear — server unknown — **HOLDS**
- `G-151` The customer picks only a pickup day; the booking is then a single-day rental (pickup day = return day). A hint above the calendar explains this. — *sees:* Grey hint under the calendar heading; REZERVOVAT active after one tap. — small → clear — server no — **HOLDS**

**S-044 / S-054**

- `G-147` The customer picks a return day so that the range would cross a booked day; the range is refused. — *sees:* A short snackbar "calRangeOccupied" for 2 s; the start stays selected. — small → clear — server yes(trg_check_booking_overlap) — **HOLDS**

**S-044 / S-054 / S-042 Search date tabs + availability calendar / Availability calendar (detail, form, filters) / Moto detail calendar**

- `G-146` Occupied days cannot be tapped and a range over an occupied day is refused (only where the calendar gets booked days: detail, calculator; Home/Search calendars get none). — *sees:* Dark occupied days; snackbar "Rozsah obsahuje obsazené dny". — small → clear — server yes(trg_check_booking_overlap, trg_check_booking_branch_open; get_moto_bo…) — **HOLDS**

**S-045**

- `G-153` The chosen range overlaps the customer's own active or upcoming reservation (cancelled/completed and own unpaid pending draft ignored; kids bike exempt). — *sees:* Red box with the overlap message above REZERVOVAT; CTA still active, booking form blocks. — clear → small — server yes(trg_check_user_booking_overlap) — **WEAKER (minor)**
- `G-154` The chosen range is shorter than the bike's minimum or longer than its maximum rental length. — *sees:* Red box 'Minimální délka pronájmu je N dní' / 'Maximální …' above REZERVOVAT; booking form blocks (rentalLengthValidationProvider). — clear → small — server no — **WEAKER (minor)**
- `G-155` Only a pickup day is chosen (single-day booking); the licence / overlap / length warning is not evaluated in the detail at all. — *sees:* No warning; the booking form evaluates it later. — silent → silent — server unknown — **HOLDS**
- `G-156` Logged-out visitor or profile not yet loaded: the licence check sees an empty group list and warns 'no licence' (false warning but never a false all-clear). — *sees:* Red 'no licence' warning. — clear → clear — server no — **HOLDS**

**S-045 / Bike detail**

- `G-152` The customer has no licence group in the profile, or a group that does not cover the bike (A/A2/A1/AM/B hierarchy, OR of bike groups, kids bike 'N' exempt); once both dates are chosen a warning appears. The detail CTA itself is NOT disabled; the hard block is… — *sees:* Red box with warning icon: 'Nemáš řidičské oprávnění …' / 'Tvoje skupina … nestačí na …', placed right above REZERVOVAT, so the customer scrolls past it to reach the button. — clear → small — server unknown — **WEAKER (major)**

**S-046**

- `G-157` Price card: the total is shown only for a complete range with a price list; without a price list the price is '–'; it is the list price (no rank discount, no deposit). — *sees:* 'Cena od …' and 'Celkem za N dní …' card. — clear → clear — server no — **HOLDS**

**S-047**

- `G-160` Boots are never prefilled from the profile (paid add-on chosen only by the customer in the form). — *sees:* No boots preselected. — silent → silent — server no — **HOLDS**

**S-047 / Bike detail / Moto detail**

- `G-158` The customer has not chosen any date; REZERVOVAT is disabled and a hint says to choose dates. — *sees:* Grey disabled button with grey hint above it. — clear → clear — server no — **HOLDS**

**S-047 / S-051 / S-065 / Booking form**

- `G-159` The customer re-enters the booking form for the SAME bike after leaving it unpaid. In the old look every entry starts a fresh draft, so the consents (VOP, GDPR, guardian) must be ticked again; in v2 the earlier draft is carried over with the consents still ti… — *sees:* Old look: unticked consent checkboxes and the grey "consentsRequired" hint; the payment button stays disabled until they are ticked again. — small → silent — server unknown — **WEAKER (major)**

**S-048**

- `G-161` Fullscreen gallery opens only when the bike has photos; a bike without photos shows a placeholder and tapping does nothing. — *sees:* Motorcycle icon placeholder; no reaction. — silent → silent — server no — **HOLDS**

**S-049**

- `G-162` The customer opens the manual but the bike has none; a message says it is not available (the card is always shown). — *sees:* Snackbar 'Manuál není k dispozici' for 2 s. — small → small — server no — **HOLDS**
- `G-163` Manual link modes: a PDF opens in the in-app browser (view/search) or externally (download); an external link opens outside the app. — *sees:* Buttons Zobrazit / Hledat / Stáhnout (PDF) or one 'Zobrazit' (link). — clear → clear — server no — **HOLDS**
- `G-164` Bike videos autoplay muted (volume 0) until the customer unmutes; a video that fails to load is skipped to the next one. — *sees:* Silent autoplaying video with a mute toggle. — clear → clear — server no — **HOLDS**

**S-050**

- `G-144` The bike list is still loading; after 15 s the customer is told it takes longer and gets Retry / Back instead of an endless spinner. — *sees:* Spinner, after 15 s 'trvá to déle' + 'Zkusit znovu' / 'Zpět'. — clear → clear — server no — **HOLDS**
- `G-145` Loading the bikes fails (offline, timeout, server, permission); the customer gets the reason, Retry, Back, 'open settings' for permission problems and a 'Call MotoGo' button for server/unknown errors. — *sees:* Error page with emoji, reason sentence, Retry, Back, optional Settings and Call buttons. — clear → small — server no — **WEAKER (minor)**

**S-050 / Bike detail**

- `G-143` The bike no longer exists in the offer (removed, retired, old link from a reservation, unknown id); the customer cannot book it and is sent to choose another bike. — *sees:* Error page 'bike is no longer offered' with explanation and button 'Vybrat jinou motorku'. (Released 4.1.3 showed only plain text detailNotFoundMessage.) — clear → clear — server unknown — **HOLDS**

### Ordering (booking form: dates, times, delivery, gear, extras, promo codes, consents) — 73 safeguards, 6 weaker

**S-051**

- `G-172` New v2-only entry points start the booking form: the Home funnel "Rezervovat" and the calculator. They hand the bike and dates to the same form, which then applies every form guard. — *sees:* Old look: the form opens only from the bike detail. — clear → clear — server yes(the same insert triggers as above apply to whatever the form submits) — **HOLDS**

**S-051 / Booking form / Booking form (amber banner)**

- `G-168` The customer's driving licence expires before the last rental day (or before today when no dates yet); the form refuses to continue. — *sees:* The same amber profile box with the "licence expired" text and the "Doplnit v profilu" button; payment button disabled. — clear → clear — server no — **HOLDS**

**S-051 / Booking form / Booking form (error banner + CTA)**

- `G-166` The customer's driving licence groups do not cover the bike (or the profile has no licence group at all); the form shows an error and locks the payment button. — *sees:* A red box with the text "validationNoLicense" / "validationInsufficientLicense" (needed group vs. held groups) above a disabled payment button. — small → clear — server no — **HOLDS**

**S-051 / S-061 / Booking form**

- `G-171` A size that is not in the offered range (pre-filled from the profile after switching kids <-> adult bike, or XS/5XL+ helmet on a self-service branch) is silently cleared so a size the customer never saw is not saved. — *sees:* Nothing; the chip is simply not selected and the missing-size rule applies again. — silent → silent — server no — **HOLDS**

**S-051 / S-061 / Booking form (extras)**

- `G-170` Kids bike: passenger gear and passenger boots are not offered at all, and any left over from a previous adult bike are removed. — *sees:* The passenger tiles are not shown. — silent → silent — server no — **HOLDS**

**S-051 / S-061 / Booking form (extras) / Booking form (extras) + payment insert**

- `G-169` The bike is from a self-service branch but the draft still carries a trailer from a previously chosen staffed-branch bike; the form silently removes the trailer. — *sees:* Nothing; the trailer just disappears from the draft (the trailer tile is not offered at a self-service branch). — silent → silent — server yes(trg_check_trailer_overlap refuses a trailer with a self-service bike,…) — **HOLDS**

**S-051 / S-070 / Booking form / Booking form (amber banner)**

- `G-167` The customer's profile lacks the address (street, city, ZIP) or, for a bike that needs a licence, the licence number or expiry; the form refuses to continue and offers "Doplnit v profilu". — *sees:* An amber box listing the missing fields and a brown "Doplnit v profilu" button; payment button disabled. — clear → clear — server no — **HOLDS**

**S-051 / S-072**

- `G-165` The customer taps "Pokračovat k platbě" while anything is still missing: no dates, unknown availability, a validation error (licence, overlap, rental length, pickup time), an incomplete profile, missing gear sizes or unticked consents. The button is disabled. — *sees:* A greyed-out "Pokračovat k platbě" button; the reasons are spread as separate hints/boxes above it (warning box, red error box, profile box, consents hint, availability hint). — small → clear — server yes(server re-checks only some parts: trg_check_booking_overlap, trg_chec…) — **WEAKER (minor)**

**S-053 / S-072 / Booking form**

- `G-173` The booking form is opened without a selected bike (bookingMotoProvider is null, e.g. after an app restart or a deep link). The form is not shown at all; the customer is sent to pick a bike. — *sees:* Bike icon, "Nejprve vyberte motorku" and the "Vybrat motorku" button; back arrow top-left. — clear → clear — server no — **HOLDS**

**S-054**

- `G-176` The date range carried into the form (from the catalog filter, Home or a previous draft) contains a day the bike's calendar shows booked. The old look has no client check and relies on the database refusal at payment; v2 keeps the calendar open and locks the… — *sees:* Old look: the form allows "Pokračovat k platbě"; the payment screen then reports the bike as taken. — small → clear — server yes(trg_check_booking_overlap) — **HOLDS**

**S-054 / Booking form**

- `G-178` The chosen range is shorter than the bike's minimum or longer than its maximum rental length (motorcycles.min_rental_days / max_rental_days); the form shows an error and locks payment. — *sees:* Red box "Minimální délka pronájmu je {n} dní" / max; payment disabled. — small → small — server no — **HOLDS**

**S-054 / Booking form / Booking form (error banner + CTA)**

- `G-177` The customer already has another active or upcoming (non-children's, not own unpaid draft) reservation overlapping the chosen dates; the form shows an error and locks payment. — *sees:* Red box "validationOverlap" naming the other bike and its dates; payment disabled. — small → clear — server yes(trg_check_user_booking_overlap, STATE_4:189) — **HOLDS**

**S-054 / S-071**

- `G-175` The bike's booked days are still loading; the payment button stays locked until they arrive. — *sees:* A disabled payment button with no explanation while loading; the calendar briefly shows all days as free. — silent → clear — server yes(trg_check_booking_overlap) — **HOLDS**

**S-054 / S-071 / Booking form / Booking form (calendar + CTA)**

- `G-174` The bike's booked days could not be loaded (offline, slow LTE, server); the calendar is replaced by an error with "Zkusit znovu" and the payment button stays locked, so the customer cannot pay for dates that may be taken. — *sees:* A compact error box in the date card, a red line "fxBookedDatesWait" with "Zkusit znovu" above a disabled payment button. — clear → clear — server yes(trg_check_booking_overlap refuses an overlapping insert at payment) — **HOLDS**

**S-054 / S-072 / Booking form (section 2 + CTA)**

- `G-179` No dates are chosen yet; the calendar is open and the payment button is disabled. — *sees:* Open calendar with "singleDayClickHint"; disabled payment button, no explicit reason next to it. — small → small — server no — **HOLDS**

**S-055**

- `G-181` The customer chooses delivery to an address and a pickup time less than 6 hours from now; the form shows an error and locks payment. — *sees:* Red box "validationDeliveryLeadTime"; payment disabled. — small → small — server no — **HOLDS**
- `G-182` The customer picks a pickup date/time in the past at a self-service (or unknown) branch; the form shows an error and locks payment. — *sees:* Red box "validationPastPickup"; payment disabled. — small → small — server no — **HOLDS**
- `G-183` Times can only be chosen as whole hours 00-23 and minutes in 15-minute steps (the current minute is kept if off-step). — *sees:* Two dropdowns (hour : minute) with only those values. — clear → clear — server no — **HOLDS**

**S-055 / Booking form (time section)**

- `G-184` At a self-service branch with return at the branch the return time is not offered; the form silently sets it to 23:59 (and resets a legacy 00:01 pickup to 09:00, or a stale 23:59 return to 19:00 when the field becomes visible). — *sees:* No return-time field; nothing explains the 23:59 value (the self-service hint under the pickup time mentions return without time). — small → small — server no — **HOLDS**
- `G-185` Self-service pickup with the 12:00 discount: the hint warns that the kiosk will hand out the bike only from 12:00 (and that return has no time). — *sees:* One small line with the half-moon emoji under the pickup time. — small → small — server yes(_kiosk_release_at / kiosk_resolve_code pickup_too_early, STATE_3:427) — **HOLDS**

**S-055 / Booking form / Booking form (time section + error)**

- `G-180` The customer picks a pickup time at a staffed branch that is less than 1 hour from now; the form shows an error and locks payment. — *sees:* Red box with the lead-time text; payment disabled. — small → small — server no — **HOLDS**

**S-056**

- `G-187` A draft that already has delivery (from an earlier staffed-branch bike or after the flag was switched off) is silently returned to pickup and return at the branch. — *sees:* The selection jumps to "Na pobočce" without a message (the locked tile explains why delivery is unavailable). — small → small — server unknown — **HOLDS**
- `G-188` The address field for pickup is offered only after the customer chooses delivery (and delivery is not locked). — *sees:* An address tile "clickEnterAddress" appears under the delivery option. — clear → clear — server no — **HOLDS**

**S-056 / Booking form (pickup/return) / Booking form (sections 4/5)**

- `G-186` The bike is from a self-service branch and the feature flag self_service_delivery is off (or could not be read); delivery to an address cannot be chosen. — *sees:* A grey locked tile "Přistavení na vaši adresu" with the short reason "ssNoDeliveryShort"; tap expands the explanation. — clear → clear — server unknown — **HOLDS**

**S-057**

- `G-189` The customer taps the locked delivery / pick-up option at a self-service branch; it cannot be selected, it only expands an explanation. — *sees:* Grey tile with a lock, the reason line, and on tap the longer explanation "ssNoDeliveryInfo". — clear → clear — server unknown — **HOLDS**

**S-058**

- `G-190` The bike is from a self-service branch and the flag is off; pick-up from the customer's address at the end of the rental cannot be chosen. — *sees:* Grey locked tile with the reason, expandable. — clear → clear — server unknown — **HOLDS**
- `G-191` The return address field is offered only when the customer chooses pick-up from an address (and it is not locked); the return time field then appears for self-service bikes too. — *sees:* Address tile under the option; return time dropdown appears. — clear → clear — server no — **HOLDS**

**S-059**

- `G-192` The customer taps "Potvrdit" twice or while the address is still being saved; the second tap is ignored and the button shows a spinner. — *sees:* Spinner in the confirm button. — clear → clear — server no — **HOLDS**
- `G-194` The customer closes the address sheet (swipe down, tap outside, back) without confirming; neither the address nor the delivery price changes. — *sees:* The form keeps the previous address and price. — silent → silent — server no — **HOLDS**
- `G-195` The customer types after an address was already picked; the picked address and its distance are dropped so "Potvrdit" saves what was typed, and stale results of earlier lookups are discarded. — *sees:* The green distance line disappears while typing. — small → small — server no — **HOLDS**
- `G-196` Address suggestions are limited to the Czech Republic and start only from 2 typed characters. — *sees:* No suggestions for foreign or 1-letter input. — silent → silent — server no — **HOLDS**
- `G-197` GPS cannot give a position (location off, permission refused, no fix); the sheet says why and offers the settings, and the customer must type or use the map. — *sees:* An amber status line with the reason; for permission / service off an explanation dialog with "Otevřít nastavení". — clear → clear — server no — **HOLDS**

**S-059 / S-114**

- `G-193` Address sheet: confirm waits for a pending suggestion/GPS lookup and computes the distance before the address and fee are accepted; closing the sheet without confirming changes nothing. — *sees:* Spinner on confirm; fee line "~km · Kč" after confirm. — clear → clear — server no — **HOLDS**

**S-060**

- `G-198` On the full-screen map the customer taps "Potvrdit adresu" while the address under the pin is still being looked up; the button is disabled. — *sees:* Text "Hledám adresu..." and a disabled confirm button. — clear → clear — server no — **HOLDS**
- `G-199` The customer leaves the map with back / close; nothing is picked and the address sheet stays unchanged. — *sees:* Back on the address sheet with the old value. — silent → silent — server no — **HOLDS**
- `G-200` A point picked on the map is not saved directly; it fills the address sheet with the routed distance and the customer must still tap "Potvrdit" there. — *sees:* The sheet shows the picked address and "~N km · fee" waiting for confirmation. — small → small — server no — **HOLDS**
- `G-201` The map starts by resolving the address under the starting point, so confirming without moving the map does not give an empty address with 0 km. — *sees:* An address under the pin right away. — silent → small — server no — **HOLDS**

**Booking form**

- `G-235` While the profile is still loading the profile and licence checks return "ok" (fail-open) until it arrives; the CTA can be briefly enabled. — *sees:* Nothing. — silent → silent — server no — **HOLDS**

**S-061**

- `G-203` Customer ticks 'Mám vlastní výbavu': all four basic-gear sizes are wiped and the size rows disappear, so no rental gear is booked by mistake. — *sees:* Checkbox ticked, the four size rows vanish. — clear → clear — server yes(trg_bookings_own_gear_normalize — own_gear=true nulls the four size c…) — **HOLDS**
- `G-204` Customer can only pick a size from the offered range: children's sizes for a kids bike, a narrower adult range on a self-service branch (helmet S–3XL, others max 4XL). — *sees:* Only the allowed size chips are shown. — silent → silent — server unknown — **HOLDS**
- `G-205` Customer taps an added extra that has sizes (passenger gear, boots) - it opens the size sheet with 'Odebrat' instead of removing silently; extra without sizes toggles off. — *sees:* Tile opens the size sheet; tile shows 'Velikost: …'. — clear → clear — server no — **HOLDS**
- `G-206` An extra with sizes that was added but has no size yet is flagged and blocks the booking (driver boots, passenger gear, passenger boots each need a size). — *sees:* Amber '⚠ Klepněte pro výběr velikosti' (clickSelectSize) under the tile, yellow missing-sizes box, CTA greyed. — clear → clear — server no — **HOLDS**
- `G-208` Trailer chosen for one date range is not carried to a different date range (the assigned piece belonged to the old dates). — *sees:* Trailer not selected on re-entry. — silent → silent — server yes(trg_check_trailer_overlap) — **HOLDS**
- `G-209` Free gear by loyalty rank: from the free-gear level the paid gear extras cost 0 Kč; below it they are charged. — *sees:* Price label on each tile, green rank banner when free. — clear → clear — server unknown — **HOLDS**

**S-061 / Booking form (extras)**

- `G-207` Trailer is offered only when a free trailer exists for the dates, never for a kids bike and never on a self-service branch. — *sees:* The trailer tile is simply absent. — silent → silent — server yes(get_trailer_availability RPC + trg_check_trailer_overlap) — **WEAKER (minor)**

**S-061 / Booking form / Booking form (gear warning + CTA)**

- `G-202` Customer leaves the basic free gear empty (no helmet, gloves, jacket or pants size) and does not tick 'Mám vlastní výbavu'; the booking cannot go on until at least one size is picked (not required when the main item is a trailer). — *sees:* Yellow warning box 'Vyplňte velikosti výbavy' with 'Chybí: základní výbava — vyberte aspoň jednu velikost, nebo zaškrtněte „Mám vlastní výbavu“'; 'POKRAČOVAT K PLATBĚ' greyed out. — clear → clear — server no — **HOLDS**

**S-062**

- `G-210` Passenger gear sheet: 'Potvrdit' stays disabled until at least one passenger size is chosen. — *sees:* Grey button with the text 'VYBERTE ALESPOŇ JEDNU VELIKOST'. — clear → clear — server no — **HOLDS**
- `G-211` Passenger sizes are limited to the adult range (narrower on a self-service branch). — *sees:* Only allowed chips shown. — silent → silent — server unknown — **HOLDS**
- `G-212` Pre-fill from the previous booking or from the already chosen passenger gear only uses sizes that are in the offered range. — *sees:* Note 'Velikosti jsme předvyplnili podle minulé rezervace…' when pre-filled. — small → clear — server no — **HOLDS**
- `G-213` Closing the passenger sheet (swipe down, tap outside) saves nothing; only 'Potvrdit' writes the sizes, only 'Odebrat' (shown only when already chosen) removes the extra. — *sees:* Sheet closes, draft unchanged. — clear → clear — server no — **HOLDS**

**S-063**

- `G-214` Boots size sheet: the size from the last booking is only marked, never pre-selected - the customer must tap a size (incident 2026-09-28: boots saved that were never chosen). — *sees:* Size chips; the last one has a darker border and a 'naposledy' tag. — small → clear — server no — **HOLDS**
- `G-215` Boots sizes are children's sizes for a kids bike and the adult range otherwise. — *sees:* Only allowed sizes. — silent → silent — server unknown — **HOLDS**
- `G-216` 'Odebrat' is offered only for boots already chosen; closing the sheet changes nothing. — *sees:* Red 'Odebrat' text button only for chosen boots. — clear → clear — server no — **HOLDS**

**S-064**

- `G-217` Price summary shows discount, loyalty, late-pickup (50 % on day 1 from 12:00) and delivery rows only when they really apply; the total comes from priceBreakdownProvider. — *sees:* Receipt rows and total 'Celkem (cena konečná)'. — clear → clear — server yes(trg_validate_app_loyalty, trg_validate_late_pickup clamp the discount…) — **HOLDS**
- `G-218` Deposit is not charged (depositNotCharged row with 0 Kč). — *sees:* Subtle row with a tick. — small → small — server unknown — **HOLDS**
- `G-219` Loyalty status fails to load: price is shown without the rank discount. — *sees:* Nothing explains it - the discount row is just missing. — silent → small — server yes(trg_validate_app_loyalty) — **HOLDS**

**S-065**

- `G-220` Promo dialog: an empty code does nothing. — *sees:* Nothing happens. — silent → silent — server no — **HOLDS**
- `G-221` The same code cannot be applied twice. — *sees:* Red text 'Kód "…" je již použit' under the field. — small → clear — server unknown — **HOLDS**
- `G-222` Double tap / double Enter cannot apply a fixed voucher twice while validation runs. — *sees:* Button shows a spinner and is inactive. — clear → clear — server unknown — **HOLDS**
- `G-223` Two percent codes cannot be combined. — *sees:* Red text 'Nelze kombinovat dva procentuální kódy'. — small → clear — server unknown — **HOLDS**
- `G-225` Own gift vouchers: tapping one only puts the code into the field - it is applied only with 'Použít' (a voucher bought for someone else must not be spent by one tap); already applied or expired vouchers are not offered. — *sees:* Voucher chips above the field; code appears in the field. — clear → clear — server yes(validate_voucher_code on apply) — **HOLDS**
- `G-226` Cancel / closing the dialog applies nothing; an applied code can be removed with ×. — *sees:* Code row with ×. — clear → clear — server no — **HOLDS**

**S-065 / Booking form (promo) / Booking form (promo dialog)**

- `G-224` Server refuses the code (expired, not yet valid, used up, voucher already used, Slevomat not verified, no internet, not found) - the specific reason is shown and nothing is applied. — *sees:* Red error text with the reason. — small → clear — server yes(validate_promo_code, validate_voucher_code, edge slevomat-voucher) — **HOLDS**

**S-066**

- `G-227` Note for MotoGo is limited to 500 characters and 3 lines; an empty note is stored as null. — *sees:* Character counter under the field. — clear → clear — server unknown — **HOLDS**

**S-067**

- `G-229` Consent to personal data processing (GDPR) is required. — *sees:* Checkbox; grey CTA. — small → clear — server no — **WEAKER (minor)**
- `G-230` Kids bike: the guardian consent ('Potvrzuji, že jsem zákonný zástupce…') is shown and required. — *sees:* Third checkbox; grey CTA. — small → clear — server no — **WEAKER (major)**
- `G-231` Consents always start unticked on every new booking entry - the customer has to tick them for each booking. — *sees:* Unticked boxes. — clear → silent — server no — **WEAKER (minor)**

**S-067 / Booking form / Booking form (consents)**

- `G-228` Consent to terms (VOP) is required; without it the booking cannot continue. — *sees:* Checkbox; grey CTA; hint 'Pro pokračování potvrďte povinné souhlasy.' — small → clear — server no — **WEAKER (minor)**

**S-068**

- `G-232` Missing gear sizes banner lists exactly what is missing (basic gear, driver boots, passenger, passenger boots). — *sees:* Yellow box with warning icon. — clear → clear — server no — **HOLDS**

**S-069**

- `G-233` Validation error blocks the booking: driving licence group does not cover the bike, the customer already has an overlapping booking, rental shorter/longer than allowed, or pickup time in the past / delivery sooner than +6 h. — *sees:* Red box with the error text; grey CTA. — small → clear — server yes(trg_check_user_booking_overlap for the customer overlap) — **HOLDS**

**S-070**

- `G-234` Mandatory consents not ticked: only a hint line, CTA locked. — *sees:* Small grey/red hint under the boxes. — small → clear — server no — **HOLDS**

**Booking form back arrow**

- `X-1-07` The customer taps back in the booking form; it goes one step back, or, with nothing underneath, to the chosen bike's detail (or the bike search when no bike is chosen). — *sees:* Previous screen, or the bike detail / bike search. No leave confirmation; the draft stays in bookingDraftProvider. — clear → clear — server no — **HOLDS**

**Delivery price in the booking form and in reservation edit (address sheet)**

- `X-2-07` The delivery price is computed from the road distance (Mapy.cz, then OSRM); if both routing services fail the app silently uses the straight-line distance without a coefficient, or 50 km when the straight distance is unknown; when the address has no coordinat… — *sees:* A distance and delivery fee as if exact; no 'estimate' wording. — silent → silent — server yes(tly - yes(check_booking_delivery_change / _delivery_guard_violation v…) — **HOLDS**

### Paying (payment page, card sheet, result and thank-you pages, saved cards, e-shop and vouchers) — 155 safeguards, 3 weaker

**S-001 / S-073 Payment screen / S-171 Shop checkout / S-083 'Opravdu opustit probíhající platbu?' dialog**

- `G-237` While a card payment is still being processed (card charge, 3-D Secure, server confirmation), the customer taps a bottom tab and would leave the payment screen; the app stops and asks first, because a lost result led to paying twice. — *sees:* An AlertDialog "psLeaveTitle" with body text, a grey "Odejít" text button and a filled "Zůstat a počkat" button; tapping outside = stay. — clear → clear — server no — **HOLDS**

**S-003/S-004/S-005/S-007/S-008/S-009 / S-073 Payment screen / Payment / Payment screen**

- `G-263` On the payment screen (booking or SOS) no floating panel may cover the "Zaplatit" button; all floating buttons hide while PaymentScreen is alive, even when the route string did not change after a push. — *sees:* Nothing floating over the payment. — silent → silent — server no — **HOLDS**

**S-073 Payment screen**

- `G-238` Back pressed while nothing was sent yet (draft or intent still being created), or the page was opened without history (FAB, deep link): the customer goes to a sensible parent (form, reservation detail, Rezervace, cart, SOS) instead of the app closing, without… — *sees:* The previous page or the fitting parent page. — silent → silent — server no — **HOLDS**
- `G-239` Back is pressed while an error sheet, dialog or the offline overlay is on top of the payment page; back closes that layer first instead of leaving the payment. — *sees:* The top sheet/dialog closes; the payment page stays. — silent → silent — server no — **HOLDS**
- `G-241` Returning to an unfinished or restored booking does not get a fresh 30 minutes; the countdown continues from when the booking was created, so the app never promises time the server no longer holds. — *sees:* The remaining minutes, not 30:00. — clear → clear — server yes(auto_cancel_expired_pending cron) — **HOLDS**
- `G-243` A new booking cannot be created while the profile lacks street, city, ZIP, or (for a bike that needs a licence) licence number and expiry, or when the licence expires before the rental ends; the draft is not inserted and nothing is charged. — *sees:* Sheet 'Rezervaci se nepodařilo vytvořit' with the list of missing fields and button 'Upravit rezervaci'. — clear → clear — server no — **HOLDS**
- `G-249` Delivery to an address for a bike from a self-service branch is refused by the database (feature flag off); the customer is told and sent back to the form. — *sees:* Sheet with 'ssNoDeliveryError' text and 'Upravit rezervaci'. — clear → clear — server unknown — **HOLDS**
- `G-250` For a self-service branch with return at the branch the return time is forced to 23:59, whatever the draft says. — *sees:* Nothing on this page. — silent → silent — server unknown — **HOLDS**
- `G-251` Discount values the app writes (loyalty, late-pickup) are only sent when really earned and are clamped by the server; promo/voucher ids are written so a 100 % discount can be confirmed. — *sees:* Nothing. — silent → silent — server yes(trg_validate_app_loyalty, trg_validate_late_pickup, SUPABASE_BACKEND_…) — **HOLDS**
- `G-253` A saved (default) card is charged directly without the card sheet; if the bank declines, the customer can retry the same card or choose 'Zaplatit jinou kartou'; if the card no longer exists or the bank forbids retry, only another card is offered. — *sees:* Sheet with the decline reason, 'Zkusit znovu' and 'Zaplatit jinou kartou'. — clear → clear — server yes(process-payment off-session charge, Stripe decline codes, declines.ts) — **HOLDS**
- `G-254` 3D Secure is not finished or fails; the customer is told the payment was not completed (or the real bank decline reason) and nothing is charged. — *sees:* Sheet 'Ověření platby' with retry / other card. — clear → clear — server yes(Stripe PaymentIntent status checked by process-payment/webhook) — **HOLDS**
- `G-257` The server says the booking is already paid, a payment is already in progress, or the request is a duplicate; the app finishes as success (new booking), shows 'Platba se ověřuje', or verifies, and never treats the original payment as payment for an edit surch… — *sees:* Success page, 'Platba se ověřuje' page or 'Změna už neplatí' sheet with 'Načíst znovu'. — clear → clear — server yes(process-payment already_paid / payment_in_progress / duplicate_request) — **HOLDS**
- `G-259` Other server refusals before charging: booking cancelled, not found, wrong status, forbidden (other account), voucher used up, delivery fee / route needed, bike unavailable, trailer only on staffed branch, change too large, stale booking, swap codes (licence… — *sees:* Sheet with the reason and an action (Moje rezervace, Načíst znovu, Upravit adresu, Upravit rezervaci, Přihlásit, Do košíku). — clear → clear — server yes(process-payment refusals.ts / index.ts; split_booking_moto_swap dry r…) — **HOLDS**
- `G-261` An edit surcharge or bike swap counts as paid only when the server has applied the change (new total_price) - not because the original booking is 'paid'; the change is queued so it completes even if the app is killed; an amount up to 1 Kč is applied by the se… — *sees:* 'Hotovo', 'Úprava se dokončuje' or 'Platba nebyla dokončena' result page. — clear → clear — server yes(webhook-receiver extension-payment.ts applyExtensionChange, process-p…) — **HOLDS**
- `G-264` Booking documents (advance invoice backup, booking docs, e-mail) are issued only after the server confirmed the payment, never optimistically for a 'processing' payment. — *sees:* Nothing (prevents wrong documents). — silent → silent — server yes(send-booking-email issues the primary advance invoice server-side) — **HOLDS**

**S-073 Payment screen / Payment / Payment screen**

- `G-240` The 30-minute time to pay runs out; the pay button locks, an unpaid new-booking draft is cancelled (bike released) and a sheet that cannot be swiped away sends the customer to pick again (or to the reservation for an edit). — *sees:* Button text '⏱ Čas vypršel' (disabled), then sheet 'Čas na zaplacení vypršel' with 'Vybrat znovu' / 'Otevřít rezervaci'. — clear → clear — server yes(pg_cron auto-cancel-pending-bookings -> auto_cancel_expired_pending() — **HOLDS**
- `G-247` The customer's own older unpaid draft for the same bike blocks the new one; the app cancels it and retries, but if a payment is already running on it the customer is sent to 'Platba se ověřuje' instead of paying twice. — *sees:* Either nothing (automatic) or the 'Platba se ověřuje' result page. — silent → clear — server yes(trg_check_booking_overlap; process-payment payment_in_progress) — **HOLDS**
- `G-252` The phone is offline when a saved card would be charged; nothing is sent and the customer gets a 'no connection' message with retry instead of 15 minutes of 'verifying'. — *sees:* Sheet 'Bez připojení' with 'Zkusit znovu'. — clear → clear — server no — **HOLDS**

**S-073 Payment screen / Payment / Payment screen (draft creation)**

- `G-245` Payment is opened with no bike or no dates in the draft (old draft, direct entry); no booking with empty data is created. — *sees:* Sheet 'Rezervaci se nepodařilo vytvořit' + 'Vyber nejdřív termín' / 'Není vybraná motorka', button 'Upravit rezervaci'. — clear → clear — server unknown — **HOLDS**

**S-073 Payment screen / Payment / Payment screen + shell tabs / Payment screen (surcharge)**

- `G-236` The customer presses back (arrow, system back, iOS swipe) after the payment may already have gone to the bank; they must confirm 'Opravdu opustit probíhající platbu?' and, if they leave, a 'payment sent' marker is set so the app shows 'Platba se ověřuje' inst… — *sees:* A confirmation dialog with 'Odejít' / 'Zůstat'; after leaving, Rezervace with the unpaid strip showing 'Ověřuje se'. — clear → clear — server no — **HOLDS**

**S-073 Payment screen / Payment screen**

- `G-242` The customer taps pay twice or taps while a payment is processing, verifying or already completed; the second tap does nothing. — *sees:* Disabled button with spinner. — clear → clear — server yes(process-payment attempt_id idempotency key / payment_in_progress) — **HOLDS**
- `G-244` Creating the booking fails because the customer is not logged in or the access token expired; the app refreshes the session once and retries, otherwise asks to sign in again. — *sees:* Sheet 'Přihlášení vypršelo' with 'Přihlásit'. — clear → clear — server yes(bookings insert requires auth.uid via RLS) — **HOLDS**
- `G-255` After 3 failed card attempts the customer cannot keep retrying; a sheet that cannot be swiped away sends them to the reservation / Rezervace. — *sees:* Sheet 'Platba se nezdařila' with '(pokus 3 z 3)' history and 'Přejít na rezervace'. — clear → clear — server no — **HOLDS**
- `G-258` The server computed a different price (amount_mismatch / free_mismatch) or the price is outdated (promo or voucher no longer valid); nothing is charged and the customer sees the new amount to confirm, or is sent back to the form / Rezervace. — *sees:* Sheet 'Cena se změnila' with button 'Zaplatit {nová cena}' and 'Zpět'; after confirming, '✓ Cena ověřená serverem' line. — clear → clear — server yes(process-payment amount_mismatch, free_mismatch, price_outdated; due-v…) — **HOLDS**
- `G-260` A booking fully covered by discounts (0 Kč) or a remainder up to 1 Kč is confirmed without card only after the server really marks it paid; otherwise an error is shown instead of a fake thank-you page. — *sees:* Toast 'Potvrzeno' then the success page, or an error sheet. — clear → clear — server yes(process-payment free_booking / free_mismatch requires promo_code_id o…) — **HOLDS**
- `G-262` The thank-you flow can run only once even if the card sheet result and the resume check arrive together; on app resume a payment confirmed by the server is completed. — *sees:* Nothing (prevents duplicate success / documents). — silent → silent — server no — **HOLDS**

**S-073 Payment screen / Payment screen (draft creation)**

- `G-246` Someone else booked the same bike for these dates in the meantime (or the customer already has an overlapping booking); the booking is refused before any charge. — *sees:* Sheet 'Motorka je v tomto termínu obsazená' with the dates, 'Změnit termín' and 'Jiná motorka'. — clear → clear — server yes(trg_check_booking_overlap and trg_check_user_booking_overlap, SUPABAS…) — **HOLDS**
- `G-248` A trailer cannot be booked with a bike from a self-service branch, and a trailer unit taken meanwhile is refused; the app also strips the trailer from self-service bookings before insert. — *sees:* Sheet 'Rezervaci se nepodařilo vytvořit' / 'Vozík je v termínu obsazený', 'Změnit termín'. — clear → clear — server yes(trg_check_trailer_overlap, SUPABASE_BACKEND_STATE_4.md:87) — **HOLDS**

**S-073 Payment screen / Payment screen / result page**

- `G-256` The connection drops after the payment was sent; the app never says 'nothing charged' until verified: it checks for ~30 s and then shows 'Platba se ověřuje' (or success / late refund) instead of offering a second payment. — *sees:* Toast 'Ověřujeme platbu', then the 'Platba se ověřuje' result page or 'Platba nebyla dokončena' with retry. — clear → clear — server yes(process-payment attempt_id idempotency; webhook-receiver refunds paym…) — **HOLDS**

**S-074 Payment header with countdown**

- `G-265` The customer must see how much time is left to pay before the booking is released. — *sees:* White bar '⏱ Zbývá M:SS'. — clear → clear — server yes(auto_cancel_expired_pending cron) — **HOLDS**
- `G-266` The header back arrow is the guarded back of the screen (confirmation during payment), not a plain pop. — *sees:* Arrow; during payment the leave dialog. — clear → clear — server no — **HOLDS**

**S-075 Bike gallery + price summary + server price note**

- `G-267` Before paying a new booking the customer sees the full itemised price (bike x days, extras with sizes or 'zdarma', delivery/return fee, discounts, late-pickup discount, deposit not charged, total incl. VAT). — *sees:* White price card with every line and the total. — clear → clear — server yes(process-payment amount_mismatch recomputes the price) — **WEAKER (major)**
- `G-268` The loyalty discount line carries a small note that the rank discount is valid only for app bookings. — *sees:* Grey 9 px note under the loyalty discount line. — small → silent — server yes(trg_validate_app_loyalty) — **WEAKER (minor)**
- `G-269` After 'Cena se změnila' the price confirmed by the server is the one paid, and a line says so. — *sees:* Green line '✓ Cena ověřená serverem: X Kč'. — small → small — server yes(process-payment amount_mismatch) — **HOLDS**
- `G-270` Bundled e-shop add-ons appear in the price summary only when they are really bundled into the payment. — *sees:* Add-on lines in the price card. — clear → clear — server unknown — **HOLDS**

**S-076 Payment context card (edit / SOS / restore)**

- `G-271` For an edit surcharge, SOS replacement, unfinished or restored booking, the customer sees what they pay for and exactly how much (amounts under 15 Kč with haléře), or that the discount covers everything. — *sees:* Card with label and amount, or green '✓ Sleva pokryla celou cenu'. — clear → clear — server yes(process-payment amount checks) — **HOLDS**
- `G-272` SOS payment shows the breakdown (bike, delivery, deposit) and the note about the deposit. — *sees:* SOS rows, total and an amber 'ℹ️' deposit note. — small → clear — server unknown — **HOLDS**

**S-077 Card rounding / minimum charge note**

- `G-273` Before paying the customer is told that the minimum card payment is 15 Kč (and the rounding line), or that amounts up to 1 Kč are not charged. — *sees:* Amber box 'ℹ️ Minimální platba kartou je 15 Kč – zaplatíš 15 Kč' + 'Dorovnání +X Kč'. — small → clear — server yes(process-payment card-minimum.ts, card_rounding written by server) — **HOLDS**
- `G-274` The amount actually charged follows the card-minimum rule: free -> confirm without card, up to 1 Kč -> confirm without card (edit: server applies), 1-15 Kč -> charge 15 Kč, otherwise the amount. — *sees:* Button text 'Potvrdit bez platby' or 'Zaplatit 15 Kč'. — clear → clear — server yes(process-payment card-minimum.ts / pp-waiver.ts) — **HOLDS**
- `G-275` The server refuses a too small amount or cannot waive a remainder up to 1 Kč; the customer is asked to pay 15 Kč with explanation instead of looping on the waiver. — *sees:* Sheet 'Minimální platba kartou' with 'Zaplatit 15 Kč'. — clear → clear — server yes(process-payment below_minimum, waiver_unverified) — **HOLDS**

**S-078 Upsell products on payment**

- `G-276` E-shop add-ons are offered only when the 'reservation_upsell' feature flag is on and the booking itself meets the 15 Kč card minimum. — *sees:* Section hidden. — silent → silent — server unknown — **HOLDS**
- `G-277` Add-ons are bundled into the charge and ordered only if the booking alone meets the card minimum; otherwise they are neither charged nor ordered. — *sees:* Nothing. — silent → silent — server unknown — **HOLDS**
- `G-278` A product that needs a size cannot be added by tapping the row; a size must be chosen. — *sees:* Size chips; the row tap does nothing until a size is chosen. — small → small — server no — **HOLDS**
- `G-279` The add-on order is created only after the booking payment is confirmed (also after 'Platba se ověřuje'). — *sees:* Nothing. — silent → silent — server unknown — **HOLDS**

**S-079 Saved card preview + encryption note**

- `G-280` Before paying with a saved card the customer sees which card will be charged (last 4 digits, brand, expiry, holder) - the saved card is charged without opening the card form. — *sees:* Green bordered card '•••• 1234 VISA · 12/27 · NAME · Uložená karta'. — clear → clear — server yes(process-payment uses payment_method_id of the customer's Stripe custo…) — **HOLDS**
- `G-281` The encryption / Stripe note appears only when something is charged. — *sees:* '🔒 Šifrovaná platba · Stripe PCI DSS Level 1'. — small → small — server no — **HOLDS**

**S-080 Pay button**

- `G-282` The pay button is disabled while processing or after expiry, shows a spinner and, while verifying, 'Ověřujeme platbu…' plus a permanent note not to pay again. — *sees:* Disabled button, spinner, '⏳ fxVerifyingNote'. — clear → clear — server yes(process-payment payment_in_progress) — **HOLDS**
- `G-283` When nothing is charged the button says 'Potvrdit objednávku zdarma' / 'Potvrdit bez platby' instead of a pay amount. — *sees:* Button with check icon and the free label. — clear → clear — server yes(process-payment free confirm) — **HOLDS**
- `G-284` The amount on the button is what the card will really be charged (15 Kč minimum applied). — *sees:* 'Zaplatit 15 Kč →'. — clear → clear — server yes(card-minimum.ts) — **HOLDS**

**S-081 Card payment sheet**

- `G-287` If the sheet is closed anyway while paying, the result is treated as 'processing' and verified, never as 'cancelled'. — *sees:* 'Platba se ověřuje' path. — silent → silent — server yes(webhook-receiver confirms) — **HOLDS**
- `G-288` The customer closes 3D Secure or Google Pay; nothing is charged and they stay in the sheet with a note to try again. — *sees:* Amber note under the button. — small → clear — server yes(Stripe) — **HOLDS**
- `G-290` Just before the payment is sent to the bank, a 'payment sent' marker is stored (and an edit surcharge is queued), so after a crash or restart the app shows 'Platba se ověřuje' instead of offering a second payment. — *sees:* Nothing directly; later the 'Ověřuje se' FAB. — silent → silent — server yes(process-payment payment_in_progress, attempt_id) — **HOLDS**
- `G-291` A PaymentIntent in 'Processing' is never treated as paid; only Succeeded/RequiresCapture count. — *sees:* 'Platba se ověřuje' instead of thank-you. — clear → clear — server yes(webhook-receiver) — **HOLDS**
- `G-292` The card field is cleared every time the sheet opens, so a wrong card number from the previous attempt is not reused. — *sees:* An empty card field. — silent → silent — server no — **HOLDS**

**S-081 Card payment sheet / S-176 Checkout pay button**

- `G-286` While the card payment is being confirmed the sheet cannot be closed (back, tap outside, drag down, close button). — *sees:* Sheet stays, 'psSheetProcessing' status line. — clear → clear — server no — **HOLDS**
- `G-289` Google Pay can only be used where the device supports it and not while a payment is running. — *sees:* Google Pay button shown only on supported devices. — clear → clear — server no — **HOLDS**

**S-081 Card payment sheet / S-176 Checkout pay button / Card payment sheet**

- `G-285` In the card sheet the Pay button stays disabled until the card number, date and CVC are complete. — *sees:* Greyed pay button until the card is complete. — clear → clear — server yes(Stripe validates the card) — **HOLDS**

**S-082 Payment error sheet**

- `G-293` Terminal states (time expired, 3 attempts used, late refund) cannot be dismissed by swipe or tap outside; system back and ✕ perform the main action. — *sees:* Sheet without dismiss; ✕ leads on. — clear → clear — server no — **HOLDS**
- `G-294` Every error sheet tells what happened and offers an action that really does something (retry, pay 15 Kč, change dates, other bike, sign in, open reservation, edit address/booking, to cart). — *sees:* Title, reason, primary and secondary buttons. — clear → clear — server yes(process-payment refusal codes) — **HOLDS**
- `G-295` Error sheets opened from booking restore, reservation edit and shop checkout use the same sheet and flags. — *sees:* Same sheet. — clear → clear — server no — **HOLDS**
- `G-296` 'Přihlásit' from an error sheet first signs out so the router does not bounce the customer back home. — *sees:* Login screen. — clear → clear — server no — **HOLDS**

**S-083 'Opravdu opustit probíhající platbu?' dialog**

- `G-297` After confirming leave, the payment marker is stored and the unpaid FAB refreshed, so the customer sees 'Platba se ověřuje' and is not offered a second payment. — *sees:* Rezervace with the 'Ověřuje se' strip. — clear → clear — server yes(process-payment payment_in_progress) — **HOLDS**

**S-084**

- `G-298` The customer presses the system Back button or swipes back on the thank-you page; they must not fall back into the payment screen or onto an empty stack (app closed / "restart the app"), they are always sent to Reservations and the reservation list is refresh… — *sees:* Back always lands on the Reservations tab; the X in the top-right corner (:644-655) does the same. — clear → clear — server no — **HOLDS**
- `G-299` After "Dokončit rezervaci" from the floating button or after a restore, the in-memory booking form belongs to another booking; the screen must not show a foreign motorbike, dates or times, so it uses the DB row first and the draft only when it belongs to this… — *sees:* Either the correct booking data, or a "loading" line instead of wrong data. — silent → silent — server no — **HOLDS**
- `G-300` The booking details cannot be loaded right after payment (offline, timeout 15 s, row not found); the customer is told so and can retry instead of seeing an empty or wrong summary. — *sees:* "📡 Údaje rezervace se nepodařilo načíst" with an explanation and a retry text button; while loading "⏳ Načítám". — small → clear — server no — **HOLDS**
- `G-301` The customer leaves the thank-you page via the main green CTA "Moje rezervace" (successCta) when documents are fine. — *sees:* Big green button that leads to Reservations. — clear → clear — server no — **HOLDS**
- `G-302` A safety / liability warning is shown after every booking: never leave keys in the ignition, always lock the handlebars, the customer is liable for damage if the terms are broken. — *sees:* Amber card with a warning heading and three bullet points, always visible. — clear → clear — server no — **HOLDS**
- `G-303` Self-service branch with the "pickup from 12:00" discount: the kiosk releases the bike only from 12:00 Prague time on the start day, so the page warns the customer and tells how to change it. — *sees:* One detail row with a half-moon emoji and a sentence about release from 12:00 and how to change the pickup time. — small → clear — server yes(_kiosk_release_at / kiosk_resolve_code -> pickup_too_early, CONTRACT…) — **HOLDS**
- `G-304` Self-service branch with return to the branch: the return time is not chosen (23:59), so the return-time row must not be shown (no false promise of a time). — *sees:* No return-time row. — silent → silent — server no — **HOLDS**
- `G-305` Pickup location with map link is shown only when the bike is picked up at a branch; for delivery to an address the branch map block is hidden (only the branch name). — *sees:* Branch name, address and map link for branch pickup; for delivery only the branch name. — clear → clear — server no — **HOLDS**

**S-085**

- `G-307` When documents are missing the main button changes from "Moje rezervace" to "Nahrát doklady" and leads to the documents screen. — *sees:* Large orange pulsing button "Nahrát doklady". — clear → clear — server yes(booking_docs_gate withholds door codes until verified) — **HOLDS**
- `G-308` When documents are missing, leaving to Reservations is only the secondary choice. — *sees:* Small white text button under the orange CTA. — clear → clear — server no — **HOLDS**
- `G-309` Children's motorbike (license_required = N) needs no documents; the page must not ask for them and shows a green "no documents needed" note. — *sees:* Green card with the child-bike title and body. — clear → clear — server yes(_docs_gate_checklist in check_booking_docs_status treats license N; S…) — **HOLDS**
- `G-310` Documents verified: the page confirms it (green) and the main button goes to Reservations. — *sees:* Green card "✓ Doklady ověřeny". — clear → clear — server yes(check_booking_docs_status returns NULL) — **HOLDS**
- `G-311` The document status could not be determined (no booking id, network error in the RPC); the page shows no document card at all and offers only "Moje rezervace" - a customer whose documents are actually missing is not told here. — *sees:* Nothing about documents. — silent → silent — server yes(door codes are still withheld server-side by booking_docs_gate) — **HOLDS**

**S-085 / Confirmation page**

- `G-306` The customer has paid but their documents (driving licence, ID) are missing, expired or not verified for this booking; the page must say so and push them to upload documents. — *sees:* Orange card "⚠ Doklady chybí" with the reason from the server and what to do. — clear → clear — server yes(check_booking_docs_status / booking_docs_gate - door codes and contra…) — **HOLDS**

**S-086**

- `G-312` Back or swipe on the payment result must not return to the payment screen (which could lead to paying again); it goes to the CTA destination, or to the secondary destination when there is one. — *sees:* Back leads to the target of the main/secondary button; X in the top-right does the same. — clear → clear — server no — **HOLDS**
- `G-313` A secondary choice such as "Ponechat současnou motorku" exists: closing or Back must lead there, not to the primary action that would send the customer into choosing another bike. — *sees:* Outlined second button; close goes to its destination. — clear → clear — server no — **HOLDS**
- `G-314` Leaving the result clears the stored outcome so the screen cannot be shown again (empty or stale) later. — *sees:* Nothing visible. — silent → silent — server no — **HOLDS**
- `G-315` "Platba se ověřuje" (pending): the bank/server has not confirmed yet; the screen must NOT offer another payment (double charge). It offers only "Moje rezervace" (or "Zpět do e-shopu") and "Ověřit znovu". — *sees:* Amber ⏳ badge, title "Platba se ověřuje", explanation, buttons "Moje rezervace" and "Ověřit znovu". — clear → clear — server yes(process-payment checkout-guard.ts refuses payment_in_progress; webhoo…) — **HOLDS**
- `G-316` "Ověřit znovu" cannot be pressed again while a verification is running (no parallel checks). — *sees:* Button shows a spinner and is disabled. — clear → clear — server no — **HOLDS**
- `G-317` While pending, the screen checks by itself every 10 s for at most 3 minutes (18 runs) and switches to success when the webhook confirms; it does not poll forever. — *sees:* The screen flips to success by itself. — silent → silent — server yes(webhook-receiver confirms the payment in DB) — **HOLDS**
- `G-318` A verified new booking goes on to the rich thank-you page with the correct flags (not "re-confirmed" from an earlier restore, not the form draft). — *sees:* Thank-you page for this booking. — silent → silent — server yes(bookings.payment_status via webhook-receiver) — **HOLDS**
- `G-319` Extras bought together with the booking (upsell) are ordered only after the payment is verified, never before. — *sees:* Nothing visible. — silent → silent — server unknown — **HOLDS**
- `G-320` Stripe says the payment succeeded but the booking state cannot be read (network); the app keeps "verifying" rather than claim success for a possibly cancelled booking. — *sees:* Stays on "Platba se ověřuje". — small → small — server yes(webhook-receiver / process-payment confirm_payment) — **HOLDS**
- `G-321` Verification proves the payment did NOT go through: the screen switches to a red "not paid" state with the reason; payment lines, next-step note, pickup block, secondary button and the "confirmed by server" badge are hidden so nothing suggests success. — *sees:* Red "!" disc, "Platba neproběhla" and what it means for the booking / change / order. — clear → clear — server yes(Stripe PaymentIntent status; booking stays unpaid in DB) — **HOLDS**
- `G-322` The payment went through but the booking had been cancelled in the meantime (not paid in time): the customer must not see "waiting" nor pay again; they are told the money is being refunded. — *sees:* Red disc with "late refund" title and body. — clear → clear — server yes(webhook-receiver refunds payments for cancelled bookings) — **HOLDS**
- `G-323` A paid booking change (swap / edit) is finished through the paid-change queue: failure turns into a "change failed" outcome, "still completing" shows a toast, done shows the verified outcome. — *sees:* The screen switches to the failure / success outcome; toast "⏳ dokončuje se". — small → small — server yes(process-payment / webhook-receiver applyExtensionChange, split_bookin…) — **HOLDS**
- `G-324` Manual "Ověřit znovu" while the bank is still processing: a toast says it is still pending (silent when the timer checks). — *sees:* Toast with ⏳. — small → small — server no — **HOLDS**
- `G-325` Outcome "attention" (paid, but something needs the customer's attention) is distinguished from plain success by an amber badge. — *sees:* Amber ✓ disc. — clear → clear — server unknown — **HOLDS**
- `G-326` Outcome "failed" (e.g. change could not be applied) is shown in red, not as success. — *sees:* Red "!" disc. — clear → clear — server yes(server refusals mapped in paid_change_outcomes.dart) — **HOLDS**
- `G-327` "Platba potvrzena serverem" lock badge appears only for a real confirmed success, never for pending / not paid. — *sees:* Small lock badge. — small → small — server yes(DB confirmation) — **HOLDS**
- `G-328` The screen is opened without any outcome data (e.g. after a restart): it falls back to a generic "Zaplaceno" and sends the customer to Reservations so they never get stuck. — *sees:* Generic success page with "Moje rezervace". — silent → silent — server no — **HOLDS**

**S-087**

- `G-329` The saved-card list cannot be loaded (offline / server); the customer must see why and retry, not an empty "no cards" list. — *sees:* Loading view, then an error view with reason and "Zkusit znovu". — clear → clear — server no — **HOLDS**
- `G-330` No logged-in user: the provider returns no cards instead of reading anything. — *sees:* Empty list. — silent → silent — server yes(RLS payment_methods user_id = auth.uid() — **HOLDS**
- `G-331` Back from Payment methods without navigation history must not close the app; it goes to Profile. — *sees:* Back to Profile. — clear → clear — server no — **HOLDS**
- `G-332` No saved card: an empty state explains there are none and that adding one speeds up payment. — *sees:* 💳, "Žádné uložené karty", short hint. — clear → clear — server no — **HOLDS**
- `G-333` "Set as priority" is offered only for a card that is not already priority AND has a Stripe payment-method id (an old manually saved row cannot be charged and must never become priority); the handler also refuses such a row. — *sees:* Star icon only on eligible cards. — silent → clear — server yes(manage-payment-methods set_default works only on a Stripe payment met…) — **HOLDS**
- `G-334` Setting the priority card fails: an error toast is shown; on success a confirmation toast and the list refreshes. — *sees:* Toast "✗ Chyba - nepodařilo se nastavit" or "✓ Prioritní karta nastavena". — small → small — server yes(manage-payment-methods: 401 without login) — **HOLDS**
- `G-335` Deleting a card fails: an error toast; on success a toast and refresh. An old manually saved row without a Stripe id is deleted directly in the table, others through the edge function. — *sees:* Toast with the result. — small → small — server yes(manage-payment-methods delete checks the card belongs to the customer…) — **HOLDS**
- `G-336` The priority card is visibly marked so the customer knows which card is charged. — *sees:* Green frame and chip. — clear → clear — server no — **HOLDS**

**S-088**

- `G-337` Deleting a saved card requires confirmation; cancel, tapping outside or Back keeps the card. — *sees:* Dialog "Odebrat kartu?" with •••• last4 and a red remove button. — clear → clear — server yes(manage-payment-methods delete ownership check) — **HOLDS**

**S-089**

- `G-338` The "Uložit kartu" button stays disabled until Stripe reports the card details complete. — *sees:* Greyed-out button. — clear → clear — server yes(Stripe createPaymentMethod rejects incomplete cards) — **HOLDS**
- `G-339` A second tap while saving does nothing (no double save). — *sees:* Spinner in the button. — clear → clear — server no — **HOLDS**
- `G-340` While the card is being saved the sheet cannot be closed (Back, X) so the result is not lost. — *sees:* X disabled, Back does nothing. — clear → clear — server no — **HOLDS**
- `G-341` The card is invalid or declined by Stripe: the sheet stays open and shows why under the button (nothing if the customer cancelled). — *sees:* Small amber text under the button. — small → clear — server yes(Stripe) — **HOLDS**
- `G-342` No internet while saving: the customer is told to check the connection; if the answer was lost the app first checks whether the card was already attached so it is not saved twice. — *sees:* Text "zkontroluj připojení" in the sheet. — small → clear — server yes(manage-payment-methods attach is per customer) — **HOLDS**
- `G-343` Any other failure closes the sheet and shows "Kartu se nepodařilo uložit"; success shows "Karta uložena" and refreshes the list. — *sees:* Toast with the result. — small → small — server yes(manage-payment-methods returns success) — **HOLDS**
- `G-344` The card field is cleared when the sheet opens so a card typed earlier (e.g. in the payment sheet) does not reappear. — *sees:* Empty card field. — silent → silent — server no — **HOLDS**
- `G-345` The card number and CVV never go to MotoGo's database: only Stripe receives them and the app stores just the payment-method id; the sheet says the payment is encrypted (Stripe PCI DSS). — *sees:* 🔒 line under the button. — small → small — server yes(manage-payment-methods attach syncs only Stripe pm data) — **HOLDS**

**S-168 E-shop**

- `G-817` The customer browses products; only products marked active in the database are offered (inactive / withdrawn goods never appear). — *sees:* Inactive products simply are not in the grid. — silent → silent — server yes(RLS on products = public SELECT only where is_active, SUPABASE_BACKEN…) — **HOLDS**
- `G-818` A product is sold out (stock_quantity <= 0); the grid marks it so the customer knows before opening it. — *sees:* A tiny red 'Vyprodano' word next to the price on the card. — small → clear — server yes(create_shop_order checks stock per product+size and returns out_of_st…) — **HOLDS**
- `G-819` The product list cannot be loaded (network / server error); the customer cannot browse until they retry. — *sees:* Warning emoji, red 'Chyba nacitani' text and a 'Zkusit znovu' button. — clear → clear — server no — **HOLDS**
- `G-820` There are no active products; the customer sees an empty shop instead of a grid. — *sees:* Shopping bag emoji and grey 'shopEmpty' message. — clear → clear — server no — **HOLDS**
- `G-821` The cart button in the shop header shows a count badge only when the cart has items, so the customer sees whether something is waiting in the cart. — *sees:* Cart icon top right; green circle with the number of pieces when the cart is not empty. — clear → clear — server no — **HOLDS**

**S-169 Product detail**

- `G-822` The customer tries to add a product that has sizes to the cart without choosing a size first; the add is refused. — *sees:* A toast at the top: warning icon, title 'Velikost', text 'Nejdriv vyber velikost'; nothing is added. — clear → small — server yes(create_shop_order rejects a size that is not in products.sizes with b…) — **WEAKER (minor)**
- `G-823` The chosen size becomes part of the cart line (id '<uuid>-<size>' and name 'Name (size)'), so two sizes are never merged into one line. — *sees:* The cart shows 'Name (M)' etc. — clear → clear — server yes(create_shop_order reads size from the item and validates it against p…) — **HOLDS**
- `G-824` A sold-out product cannot be added: the quantity stepper and the 'Add to cart' button are not shown at all. — *sees:* A red 'Vyprodano' box instead of quantity and the add button. — clear → clear — server yes(out_of_stock from create_shop_order, 20260924d:136) — **HOLDS**
- `G-825` The customer tries to lower the quantity below 1; nothing happens (minimum is 1). — *sees:* The minus button stays the same; the number stays 1. No hint. — silent → clear — server yes(create_shop_order: qty must be 1-99, bad_qty, 20260924d:69) — **HOLDS**
- `G-826` Quantity has no upper limit in the app (not even the stock count); the server refuses more than 99 per line or more than stock. — *sees:* Nothing stops the plus; the problem only appears at checkout as an error sheet (out_of_stock -> 'shopOutOfStock' with 'Upravit kosik', other codes -> generic 'pdOrderFail'). — silent → silent — server yes(create_shop_order: bad_qty for qty > 99, too_many_items for > 50 line…) — **HOLDS**
- `G-827` The product opened by link no longer exists or is no longer active; the page refuses to show it. — *sees:* Error page 'product is gone' with a back arrow. — clear → clear — server yes(products RLS is_active; create_shop_order product_not_found, 20260924…) — **HOLDS**
- `G-828` The product list is still loading or failed to load; the customer cannot add anything until it loads. — *sees:* Loading view, or error with 'Zkusit znovu' and back. — clear → clear — server no — **HOLDS**
- `G-829` After adding, the cart floating button is un-dismissed so the customer is reminded of the cart on other screens. — *sees:* Toast 'Pridano' with '<qty>x <name>'; outside the shop the cart pill reappears. — clear → clear — server no — **HOLDS**

**S-170 Cart**

- `G-830` The cart is empty; there is no checkout button, only a way back to the shop. — *sees:* Big cart emoji, 'Kosik je prazdny', button back to the shop; no 'K pokladne'. — clear → clear — server yes(create_shop_order refuses an empty item list, 20260924d:56-57) — **HOLDS**
- `G-831` The 'Vyprazdnit' (empty cart) action is offered only when there is something in the cart; it empties without a confirmation. — *sees:* Small grey 'Vyprazdnit' in the app bar; toast after emptying. — small → clear — server no — **HOLDS**
- `G-832` Lowering a line's quantity from 1 removes the line (there is no 0 pieces line). — *sees:* The line disappears. — silent → silent — server yes(qty 1-99 enforced, 20260924d:69) — **HOLDS**
- `G-833` The cart only shows a shipping line when the cart is not vouchers-only (vouchers are digital, no postage). — *sees:* No shipping line for a vouchers-only cart; otherwise 'Posta +99 Kc' or 'Osobni odber zdarma'. — small → small — server yes(create_shop_order: voucher-only cart shipping 0, other methods -> bad…) — **HOLDS**
- `G-834` The cart shows the note that the final price is confirmed at checkout (shopPriceNote) under the total. — *sees:* Small grey note under the total. — small → small — server yes(server pricing in create_shop_order; process-payment checks the amoun…) — **HOLDS**

**S-171 Shop checkout**

- `G-835` The customer presses Pay a second time while an order / payment is already running; the second press is ignored. — *sees:* Pay button shows a spinner and cannot be pressed. — clear → clear — server yes(process-payment reuses / guards the stored intent per order, supabase…) — **HOLDS**
- `G-837` Checkout opened without history (deep link / after go) -> back leads to the cart, not out of the app. — *sees:* Back goes to the cart. — clear → clear — server no — **HOLDS**
- `G-838` A retry after a failed payment reuses the already created unpaid order as long as cart, codes, shipping and address are unchanged, so no duplicate orders appear. — *sees:* Nothing visible; only one order in history. — silent → silent — server yes(process-payment guards the stored intent per order, index.ts:355; no…) — **HOLDS**
- `G-839` The amount charged is the SERVER's order total, not the total the app computed (stale discount, changed price). — *sees:* The card sheet shows the server amount; the summary on the page shows the app's own computation. — small → small — server yes(create_shop_order computes price; process-payment refuses a different…) — **HOLDS**
- `G-840` An order that the server prices at 0 Kc (discount covers everything) is confirmed without any card payment. — *sees:* Button reads 'Potvrdit objednavku zdarma'; result screen 'Objednavka zdarma'. — clear → clear — server yes(create_shop_order auto-confirms total 0, SUPABASE_BACKEND_STATE_3.md:…) — **HOLDS**
- `G-841` Card minimum: 1-15 Kc is charged as 15 Kc, up to 1 Kc is not charged at all; the customer is told before paying. — *sees:* Amber info box under the summary and the matching button label. — clear → clear — server yes(process-payment below_minimum / waiveShop, supabase/functions/process…) — **HOLDS**
- `G-842` The server says the amount is below the card minimum (below_minimum / amount_too_small); the customer is offered to pay the minimum or edit the cart. — *sees:* Error sheet with 'Zaplatit 15 Kc' and 'Upravit kosik'. — clear → clear — server yes(process-payment below_minimum, index.ts:361) — **HOLDS**
- `G-843` The payment server refuses (session expired, order changed, network); the app maps it to a translated message with the matching action (log in again, send again, retry, pending). — *sees:* Error sheet with a specific title and button ('Prihlasit', 'Odeslat znovu', 'Zkusit znovu') or the pending screen. — clear → clear — server yes(process-payment refusals: amount_mismatch, below_minimum, auth, index…) — **HOLDS**
- `G-844` After a card payment Stripe reports 'processing' or the result is unclear; the app does not show success, it waits for the webhook and otherwise shows 'Platba se overuje' and clears the cart so the customer cannot pay twice. — *sees:* Pending result screen 'Platba se overuje' with the shop CTA. — clear → clear — server yes(only the Stripe webhook marks the order paid; confirm_shop_payment fo…) — **HOLDS**
- `G-845` The checkout is opened with an empty cart (e.g. after the cart was cleared in another place); pressing Pay is refused. — *sees:* Toast 'Kosik je prazdny'; the page itself still shows the sections and a pay button. — small → small — server yes(create_shop_order rejects an empty list, 20260924d:56-57) — **HOLDS**
- `G-846` Server refuses to create the order (out of stock, product withdrawn, bad size, bad code, voucher not allowed, two percent codes, bad shipping, network); the customer gets a specific message and the right action instead of payment. — *sees:* Error sheet 'psOrderFailTitle' with the reason and one action. — clear → clear — server yes(create_shop_order error codes, 20260924d:60-181) — **HOLDS**

**S-171 Shop checkout / Shop checkout**

- `G-836` During a payment that may already have gone to the bank, the back button / back gesture / app-bar arrow does not leave silently; the customer must confirm and then lands on 'Platba se overuje' (cart cleared so they do not pay twice). — *sees:* Dialog 'Opustit platbu?' with 'Odejit' / 'Zustat a pockat'. — clear → clear — server yes(the server keeps the order/payment state; the webhook confirms paymen…) — **HOLDS**

**S-172 Checkout shipping**

- `G-848` The address fields are required only for post; for personal pickup they are hidden and not checked. — *sees:* Address toggle appears only under 'Postou'. — clear → clear — server no — **HOLDS**
- `G-849` A cart with only gift vouchers has no shipping choice at all (digital delivery); the section is not shown and shipping is 0. — *sees:* No delivery card on the page. — clear → clear — server yes(voucher-only cart: shipping 0, other method -> bad_shipping, 20260924…) — **HOLDS**
- `G-850` Only the two methods the shop supports (post 99 Kc, pickup free) can be chosen. — *sees:* Two cards, the active one green. — clear → clear — server yes(create_shop_order accepts only post/pickup/digital-for-vouchers, bad_…) — **HOLDS**

**S-172 Checkout shipping / Shop checkout**

- `G-847` Post delivery is chosen and the name, street, city or post code is empty; Pay is refused and the address block opens at the missing field. — *sees:* Toast naming the missing fields; the address block expands and scrolls into view. — clear → clear — server no — **HOLDS**

**S-175 Checkout promo codes**

- `G-851` The customer types a code while a gift voucher is in the cart; codes are not allowed for voucher purchases and the code is refused without asking the server. — *sees:* Red line under the field 'Na nakup poukazu nelze uplatnit kod'. — small → small — server yes(create_shop_order code_not_allowed_for_voucher, 20260924d:160) — **HOLDS**
- `G-852` The same code is entered twice; it is refused. — *sees:* Red line 'Kod ... uz je pouzity'. — small → small — server unknown — **HOLDS**
- `G-853` The code is invalid, expired, used up, a gift / Slevomat voucher, or there is no internet; it is refused with the concrete reason. — *sees:* Red line with the reason under the field. — small → small — server yes(validate_promo_code; create_shop_order code_invalid / voucher_not_all…) — **HOLDS**
- `G-854` A second percentage code is added; two percent codes cannot be combined. — *sees:* Red line 'Nelze kombinovat dva procentni kody'. — small → small — server yes(create_shop_order multiple_percent, 20260924d:168) — **HOLDS**
- `G-855` While a code is being checked, the Apply button is disabled so the code is not sent twice; an empty field does nothing. — *sees:* Spinner in the Apply button. — clear → clear — server no — **HOLDS**
- `G-856` Applied codes are listed and can be removed with an X; the discount is recalculated. — *sees:* Green chips with code and value, red X. — clear → clear — server yes(server recomputes the discount from the codes it receives) — **HOLDS**

**S-176 Checkout pay button**

- `G-857` The card is declined or the payment fails with a known reason; the customer gets a translated error and can retry (the pending marker is cleared). — *sees:* Error sheet with the reason and 'Zkusit znovu'. — clear → clear — server yes(Stripe decline) — **HOLDS**

**S-177 Gift voucher purchase**

- `G-858` The customer enters a custom voucher value below 100 Kc; the buy button is blocked. — *sees:* Greyed 'Koupit poukaz' button; the field label 'amountMin' is the only hint. — small → clear — server yes(create_shop_order bad_voucher_item when N < 100, 20260924d:77) — **HOLDS**
- `G-859` The custom value is clamped to 100-99 999 Kc and written back into the field when the customer leaves the field, so the shown number equals what is bought. — *sees:* The number in the field jumps to 100 or 99 999. — small → small — server yes(create_shop_order accepts only voucher_<1-5 digits>, N >= 100, 202609…) — **HOLDS**
- `G-860` A printed voucher adds 180 Kc for print and postage; the price on the button includes it. — *sees:* Type card '+180 Kc' and the button 'Koupit poukaz - <total>'. — clear → clear — server yes(create_shop_order prices printed voucher N + 180, 20260924d / SUPABAS…) — **HOLDS**
- `G-861` Buying a voucher only puts it into the cart and opens the cart; payment still goes through the guarded checkout (login, no promo codes for vouchers). — *sees:* Toast 'Pridano do kosiku' and the cart. — clear → clear — server yes(create_shop_order: login-only, code_not_allowed_for_voucher) — **HOLDS**

### Before pickup (reservations list, reservation detail, door codes, pickup procedure, cancel, restore) — 109 safeguards, 14 weaker

**'Review on Google' link (rating card in reservation detail and on Home)**

- `X-2-06` The Google review button opens only an https link on a Google domain (g.page/r/..., goo.gl, google.<tld>); any other value set in Velín (app_settings.google_review_url) is ignored and the built-in link https://g.page/r/CUmeYvk-sNf6EBM/review is used. — *sees:* Nothing about the filter; the browser opens the Google page. If opening fails: toast with title rfGoogleBtn and text rfLinkFailed. — silent → silent — server yes(edge _shared/review-links.ts isGoogleReviewUrl, same rule for e-mails…) — **HOLDS**

**Paid bike swap / paid booking change not yet confirmed by the server (retry queue)**

- `X-2-04` After paying for a swap or booking change that the server has not yet written, the app keeps retrying (backoff 10 s up to 10 min); after 7 days online without confirmation it stops showing 'completing' and shows once 'the staff is checking the payment' (reaso… — *sees:* In reservation detail: amber banner 'Swap/Change is completing' while retrying; after 7 days a red banner with a failure title and text and an 'Understood' button (features/reservations/widgets/paid_… — clear → clear — server yes(process-payment action complete_extension, webhook-receiver; queue ca…) — **HOLDS**

**S-099 Paid change banner**

- `G-438` A paid swap or edit failed permanently (e.g. server refused); the customer is told what happened and what happens to the extra payment (refund), and the banner stays until they confirm 'Rozumím'. — *sees:* Red box '! <title>' with the reason and refund sentence and a 'Rozumím' button. — clear → clear — server yes(refusal reason comes from split_booking_moto_swap / the paid-change a…) — **HOLDS**
- `G-439` A paid bike swap failed because the new bike was taken by someone else in the meantime; the customer must decide: keep the current bike or pick another (routes to the swap tab of the edit screen, where availability is checked again). — *sees:* Red box 'Motorka je mezitím obsazená' with two text buttons 'Ponechat současnou motorku' / 'Vybrat jinou motorku'. — clear → clear — server yes(split_booking_moto_swap refuses with new_moto_unavailable / moto_unav…) — **HOLDS**
- `G-440` The banner only appears for this booking's PAID queue entries and refreshes itself when the background queue finishes; on success it reloads the booking so the new bike/terms show. — *sees:* Nothing when there is nothing pending; the banner disappears and the detail updates when the change is written. — silent → silent — server no — **HOLDS**

**S-100 Status header + rental facts + places**

- `G-441` Pickup time shown: an old 'any time on the first day' booking (00:01 marker) must not show a fake 00:01 time. — *sees:* Row 'Čas vyzvednutí: kdykoliv během prvního dne' or 'HH:MM'. — small → small — server yes(kiosk release rules use the same marker server-side; not traced furth…) — **HOLDS**
- `G-442` Customer taps navigate to the pickup/return place; the navigate button is only offered when there is a target (GPS or an address), and branch navigation always uses GPS (falls back to the main branch coordinates) because the text address 'Mezná 9' is ambiguou… — *sees:* Green navigation icon button next to the address, or no button when no target. — clear → clear — server no — **HOLDS**
- `G-443` Delivery vs branch: the row tells the customer whether the bike is delivered to an address or picked up at the branch. — *sees:* Label 'Přistavení' or 'Pobočka' with truck/store icon above the address. — small → small — server no — **HOLDS**

**S-101 Self-service 12:00 release note**

- `G-444` From the 12:00 note the customer may move to an earlier time (discount lapses, surcharge) — the 'change time' button is offered only for a not-yet-picked-up booking in status 'reserved', never for an active one. — *sees:* Green button '🕛 Chci vyzvednout dřív' under the note; no button otherwise. — clear → clear — server unknown — **HOLDS**

**S-102 Financial summary**

- `G-445` Discounts and extra fees are listed only when they apply (delivery fee, add-ons, 12:00 late-pickup discount, promo/voucher code), so the customer sees what the 12:00 rule is worth before changing the time. — *sees:* Rows with amounts, discounts in green with a minus sign. — small → small — server yes(prices are computed server-side; not re-traced) — **HOLDS**

**S-103 Reservation history**

- `G-446` After a date change the customer sees the original and the new term (extended / shortened / moved), so they know which dates now apply. — *sees:* Coloured summary card (blue/red/green) with original and new term and day counts. — clear → clear — server no — **HOLDS**
- `G-447` A cancelled booking shows who cancelled it, when, why, the storno fee and the refunded amount. — *sees:* Card '🗑️ STORNO' with Zrušeno, Zrušil (zákazník/admin/systém), Důvod, Storno poplatek, Vráceno. — small → small — server yes(cancel_booking_tracked computes fee/refund — STATE_3:99) — **HOLDS**
- `G-448` SOS events: the booking shows it is an SOS replacement, or that it was ended by SOS, plus the list of incidents with their state. — *sees:* Card '🆘 SOS UDÁLOSTI' with green/red badges and incident rows. — clear → clear — server no — **HOLDS**
- `G-449` Timeline: 'Vydáno' (issued) appears only after the bike code was entered AND the handover protocol signed, not just after payment, so the customer is not misled that the bike is out. — *sees:* Timeline rows Vytvořeno / Potvrzeno / Vydáno / Vráceno / Zrušeno / Hodnoceno with times. — small → small — server yes(picked_up_at / handover_protocol_filled_at written by kiosk/edge subm…) — **HOLDS**
- `G-450` Edit history: each paid/unpaid modification (moto, method, address, times, gear, extras) is listed with before → after. — *sees:* Card with history entries and change rows. — small → small — server no — **HOLDS**

**S-104 Access codes card**

- `G-451` Customer has not uploaded valid ID/licence: the code is withheld and instead of the number the card shows the reason (e.g. documents missing / licence expires before the end). — *sees:* In the white card the code row shows the reason text in place of the number (black text). — small → silent — server yes(trg_zz_door_codes_docs_gate + booking_docs_gate; release_my_door_code…) — **WEAKER (major)**
- `G-453` Branch with a gate (Velké Němčice): the gate key-box code is shown only after the server has issued the bike code, with a hint how to use it, and the codes are ordered gate → locker → bike as entered on site. — *sees:* Bold row 'Kód schránky s klíčem od brány' + grey hint; then locker, then bike. — small → silent — server yes(get_booking_gate_info returns gate_code only with an issued bike code…) — **WEAKER (major)**
- `G-456` Codes are loading: the card title shows a spinner so the customer knows codes are coming (not missing). — *sees:* Card '🔑 Přístupové kódy' with a small green spinner. — small → small — server no — **WEAKER (minor)**
- `G-457` Codes change on the server (issued after documents, regenerated, released after swap): the card updates live without restarting, so the customer does not use a stale code. — *sees:* Card updates by itself. — silent → silent — server yes(codes are issued/deactivated only server-side) — **HOLDS**

**S-104 Access codes card / Reservation detail / Reservation detail (codes card) / Reservation detail – access codes**

- `G-452` Codes withheld for missing documents: the card offers 'Nahrát doklady pro kódy'. Tapping tries release_my_door_codes; if refused it sends the customer to the documents screen and retries after they return; result toast success / still withheld. — *sees:* Green full-width button with ID icon; after return a toast 'Kódy odeslány' or 'Kódy jsou stále zadržené'. — clear → clear — server yes(release_my_door_codes: only reserved/active, docs gate booking_docs_g…) — **HOLDS**

**S-104 Access codes card / Reservation detail – access codes**

- `G-454` Customer brings own gear: no locker code is expected; the card says so instead of leaving the customer to look for a missing locker code. — *sees:* Row 'Kód šatny: Máte vlastní výbavu — šatna není potřeba'. — small → silent — server yes(_booking_needs_locker in auto_generate_door_codes — STATE_3:161) — **WEAKER (major)**
- `G-455` Codes cannot be loaded (offline, weak LTE): the customer gets the reason, 'Zkusit znovu', 'Zprávy od MotoGo' (codes are also sent there) and 'Zavolat'; codes loaded earlier stay visible. — *sees:* White card with the reason sentence and three text buttons. — small → silent — server no — **WEAKER (major)**

**S-105 Self-service pickup procedure**

- `G-458` The step-by-step pickup procedure is offered only for a reserved/active, upcoming/active booking at a SELF-SERVICE branch with pickup at the branch (not delivery). — *sees:* Collapsible white card '🧭 Postup při vyzvednutí' (collapsed by default) or nothing. — clear → small — server no — **WEAKER (major)**
- `G-459` Procedure content adapts: gate step only for a gate branch (with the code once issued), locker steps only when the customer rents gear (needsLocker mirrors DB _booking_needs_locker), otherwise 'no locker' step. — *sees:* Numbered steps inside the expanded card. — small → small — server yes(_booking_needs_locker decides locker code issue — STATE_3:161) — **WEAKER (major)**
- `G-460` Gate branch: an 'IMPORTANT' warning (close the gate / return the key etc.) is shown with the procedure. — *sees:* Amber bordered box '⚠️ DŮLEŽITÉ …' at the end of the expanded procedure. — clear → small — server no — **WEAKER (major)**

**S-106 Rating card + ride feedback sheet**

- `G-462` Customer taps a star: saved immediately; tapping the same star again does nothing; if saving fails the stars go back and a toast explains why. — *sees:* Stars fill; toast with thanks or with the failure reason. — clear → clear — server no — **HOLDS**
- `G-463` After rating, every customer (1★ or 5★) gets the same two choices in the same order — Google review and a private message to the team (no review gating). They are hidden until a star is chosen. — *sees:* Two tiles 'Napiš nám recenzi' (Google) and 'Napiš nám přímo, co máme zlepšit'. — clear → silent — server no — **WEAKER (major)**
- `G-464` Google review link cannot be opened: a toast says the link failed. — *sees:* Toast '⚠️ … odkaz se nepodařilo otevřít'. — clear → clear — server no — **HOLDS**
- `G-466` While the feedback is being sent the field and button are disabled (no double send); if the sheet is closed during sending, the app still waits for the result and reports failure. — *sees:* Spinner in the button; disabled field. — clear → clear — server no — **HOLDS**
- `G-467` Sending the feedback fails (offline, not signed in): toast with reason and 'your text is kept'; text stays in the field. Text limited to kRideFeedbackMaxLen. — *sees:* Toast with reason + 'Text zůstal v poli'; counter under the field. — clear → clear — server no — **HOLDS**

**S-106 Rating card + ride feedback sheet / Reservation detail – rating**

- `G-461` Rating is offered only for a finished booking (status Dokončené), not for upcoming/active/cancelled ones. — *sees:* Dark gradient card '⭐ Hodnocení jízdy' with 5 stars. — clear → silent — server no — **WEAKER (major)**
- `G-465` Private feedback: tapping Send with empty text is refused with an error under the field (not a toast hidden by the keyboard). — *sees:* Grey Send button; red text under the field 'Napište prosím…'. — clear → clear — server no — **HOLDS**

**S-107 State-dependent action buttons / Reservation detail**

- `G-468` SOS button appears only for an active rental: bike handed over, or paid and the term is running today, and not already ended by SOS. — *sees:* Light-red '🆘 SOS' button under Edit. — clear → clear — server unknown — **HOLDS**

**S-107 State-dependent action buttons / Reservation detail + list card**

- `G-469` Completed and cancelled bookings offer no edit, no cancel and no SOS. — *sees:* Only documents / book again (completed) or restore (cancelled). — clear → clear — server yes(cancel_booking_tracked wrong_status; edit RPCs refuse finished bookin…) — **HOLDS**

**S-107 State-dependent action buttons / S-138 Booking document opening flow / Reservation detail**

- `G-470` Completed booking: 'Nájemní smlouva' — if the real contract does not exist yet the customer is told so; offline → reason + retry. — *sees:* Toast 'Smlouva zatím není k dispozici' or error snack. — clear → clear — server unknown — **HOLDS**

**S-108 Booking documents buttons / Reservation detail**

- `G-471` Document buttons (contract, handover protocol, damage protocol) appear only during the rental term or while the bike is out (also before handover on pickup day). — *sees:* Section 'DOKUMENTY' with outlined buttons. — clear → clear — server no — **HOLDS**

**S-108 Booking documents buttons / S-138 Booking document opening flow**

- `G-472` Opening a booking document: one at a time, progress with cancel after 15 s, 60 s limit; offline/timeout/server errors are re-thrown so the customer sees the real reason + retry instead of 'not available'; if nothing exists online -> 'Dokument zatím není k dis… — *sees:* Progress, then the document, an error snack with retry, or a toast. — clear → clear — server no — **HOLDS**

**S-109 Restore cancelled booking**

- `G-473` Restore refused because the customer already has another booking in that term, the branch is closed, or the trailer is taken. — *sees:* Same sheet with the specific reason text. — small → small — server yes(customer_restore_booking moto_unavailable reasons) — **HOLDS**
- `G-474` Restore refused because staff cancelled it, it is not restorable, or the restore limit was reached. — *sees:* Sheet with the reason and 'Vybrat znovu' / 'Jiná motorka'. — clear → clear — server yes(customer_restore_booking — migration 20261112a02:96,99,107) — **HOLDS**
- `G-475` Restore refused because the voucher or promo code used in the booking is no longer valid (it may not be used twice) or the price list changed. — *sees:* Sheet naming the code that is no longer valid / that the price changed. — clear → clear — server yes(customer_restore_booking — migration 20261112a02:123,136,186) — **HOLDS**
- `G-476` Session expired or the booking is not the customer's: restore refused with a 'sign in' button; booking gone → 'Moje rezervace'. — *sees:* Sheet with 'Přihlásit se' or 'Moje rezervace'. — clear → clear — server yes(customer_restore_booking forbidden / not_found — migration 20261112a0…) — **HOLDS**

**Reservation detail**

- `G-437` A customer looks at a rental whose end date has passed while the bike is still out (overdue): the app already treats the calendar as ended and shows the booking as Completed, so Edit (extend) and the detail SOS button disappear and the rating card appears. — *sees:* Status "Dokončené", rating stars, final-invoice and contract buttons; no edit, no SOS on the detail. — silent → silent — server unknown — **HOLDS**

**Reservations**

- `G-436` Gear-only bookings are hidden from the app until the owner enables "Zobrazit v aplikaci"; the app cannot create them. — *sees:* Booking not listed. — silent → silent — server yes(RESTRICTIVE RLS, trg_zz_gear_booking_guard) — **HOLDS**

**S-014 Offline full-screen overlay / S-090**

- `G-372` While offline, the 5-second automatic refresh of the reservations list and reservation detail is skipped so loaded data stays visible instead of turning into errors. — *sees:* Last loaded data stays on screen. — silent → silent — server no — **HOLDS**

**S-090**

- `G-370` The session disappears while the list is open (no current user): the provider yields an empty list rather than someone else's data, and an auth error from the server logs the customer out. — *sees:* The empty state "Žádné rezervace" (or the login screen once the auth error is handled). — small → small — server yes(owner RLS on bookings) — **HOLDS**
- `G-371` Only the customer's own bookings are offered in the list. — *sees:* Only own reservations. — silent → silent — server yes(bookings owner RLS; exact policy name not looked up) — **HOLDS**
- `G-373` A refresh fails (weak signal) after the list was already loaded: the list stays and a "stale data" strip with Retry is shown, instead of an error page. — *sees:* A thin strip saying the data may be old, with "Zkusit znovu". — small → small — server no — **HOLDS**
- `G-374` The list is still loading: never a bare spinner; after 15 s a "takes longer" block with Retry appears. — *sees:* Spinner, then after 15 s an explanation and "Zkusit znovu". — clear → clear — server no — **HOLDS**
- `G-375` Loading the list fails with nothing cached: an error view explains what happened and offers Retry and Back to Home. — *sees:* Error page with reason, "Zkusit znovu" and back. — clear → clear — server no — **HOLDS**
- `G-376` The customer has no reservation (or none in the chosen filter): an empty block with a "book" button that leads to the motorcycle search. — *sees:* "Žádné rezervace", short text, button to the bike search. — clear → clear — server no — **HOLDS**
- `G-377` The back arrow at the top of the tab always leads to Home (tab root). — *sees:* Back arrow in the header. — clear → clear — server no — **HOLDS**
- `G-380` A booking that waits for payment (pending payment from the shell provider) is flagged on the list card. — *sees:* No unpaid marker on the card itself. — silent → clear — server yes(auto_cancel_expired_pending after the window) — **HOLDS**

**S-090 / Reservations list / detail**

- `G-378` An unpaid booking whose 30-minute payment window has passed is shown as "Zrušená" (not as upcoming), matching the server auto-cancel. — *sees:* Status badge "Zrušená", grey photo, Restore button. — clear → clear — server yes(auto_cancel_expired_pending cron, per comment at reservation_models.d…) — **HOLDS**

**S-090 / S-100 Status header + rental facts + places / S-095**

- `G-379` Customer looks at the status of the booking; the badge says 'Nadcházející' until the bike is actually handed over (signed protocol / DB active), even when the term has started, so the customer does not think they can already ride. — *sees:* Coloured pill with the status name (green Aktivní, amber Nadcházející, grey Dokončené, red Zrušené) under the bike name; header 'Detail rezervace – <status>'. — clear → clear — server yes(_gate_obsluzna_activation keeps status reserved until protocol, per c…) — **HOLDS**

**S-091**

- `G-381` The customer filters the list (Vše / Aktivní / Nadcházející / Dokončené / Zrušené); only bookings with that display status are shown, and swiping past the first or last filter does nothing. — *sees:* Five chips; the selected one is green. — clear → clear — server no — **HOLDS**
- `G-382` A filter with no matching bookings shows the same "Žádné rezervace" block as an empty account, and the chosen filter is remembered across visits (StateProvider, not auto-disposed), so a customer can return to the tab and see "no reservations" although booking… — *sees:* Empty block with the highlighted filter chip above it. — small → small — server no — **HOLDS**

**S-092**

- `G-384` Upcoming booking (including "term started, bike not handed over") on the list: only Detail and Upravit; no SOS and no storno on the card. — *sees:* Buttons "Detail", "Upravit". — clear → clear — server no — **HOLDS**
- `G-386` Completed booking: "Detail jízdy" and "Hodnotit" both only open the detail; rating is never written from the card. — *sees:* Two buttons, both lead to the detail. — clear → clear — server no — **HOLDS**
- `G-387` Cancelled booking: "Obnovit" runs restore-and-pay (not a free new booking); in 4.1.3 it only jumped to the bike search. — *sees:* Button "Obnovit" -> server check -> payment screen or an explanation sheet. — clear → clear — server yes(customer_restore_booking - but defined only in the not-yet-deployed m…) — **HOLDS**
- `G-393` SOS badges on the card photo tell an SOS replacement bike ("🏍️ SOS", green) apart from a rental ended by SOS ("🆘 SOS", red). — *sees:* Small pill with a motorcycle or SOS emoji, green or red. — clear → silent — server no — **WEAKER (minor)**
- `G-394` Completed and cancelled bookings are shown in grey so they do not look actionable. — *sees:* Grey photo. — clear → clear — server no — **HOLDS**
- `G-395` Status badge on each card (Aktivní / Nadcházející / Dokončená / Zrušená). — *sees:* Coloured pill top right. — clear → clear — server no — **HOLDS**
- `G-396` A booking without a photo URL does not crash the list (placeholder instead of an error widget). — *sees:* Grey placeholder with a motorcycle. — silent → silent — server no — **HOLDS**

**S-092 / Reservations list**

- `G-383` Active (handed-over) booking on the list: the card offers Detail, Upravit and, only when SOS is allowed, a red SOS button to /sos. — *sees:* Buttons "Detail", "Upravit", red "Porucha" only when allowed. — clear → clear — server unknown — **HOLDS**

**S-092 / S-109 Restore cancelled booking**

- `G-390` Restore network error or unknown server error: nothing changed, the customer gets a retry; if the restore RPC is not deployed yet a 'server is updating' text. — *sees:* Sheet 'Rezervaci nelze obnovit' + 'Zkusit znovu'. — clear → clear — server no — **HOLDS**
- `G-391` Restore succeeded on the server earlier but the answer was lost (timeout): a second tap does not restore twice; the app detects the booking awaits payment (within 30 min of restore) and goes straight to payment, otherwise opens the booking. — *sees:* Goes to payment, or sheet 'Otevřít rezervaci'. — small → small — server yes(customer_restore_booking not_cancelled, migration 20261112a02:88 - pe…) — **HOLDS**
- `G-392` After a successful restore the customer must pay: the amount comes from the SERVER (incl. any price adjustment) and a new 30-minute payment window starts from the restore time. — *sees:* Payment screen 'Obnovení rezervace' with the server amount and countdown. — clear → clear — server yes(customer_restore_booking sets restored_at and a new 30 min window - p…) — **HOLDS**

**S-092 / S-109 Restore cancelled booking / Reservation detail / list – restore**

- `G-389` The server refuses a restore (bike taken, own overlapping booking, branch closed, trailer, voucher/promo no longer valid, price changed, restore limit, cancelled by staff, not yours): a sheet with the exact reason and a next step. — *sees:* PaymentErrorSheet with a heading ("Nelze obnovit" / "Motorka je obsazená"), the reason and one or two buttons. — clear → clear — server yes(customer_restore_booking, supabase/migrations/20261112a02_customer_re…) — **HOLDS**

**S-092 / S-109 Restore cancelled booking / Reservations list card / detail / Reservation detail / list – restore**

- `G-388` Customer tries to restore a cancelled booking whose start is today or already past: refused before any server call (today has its own text). — *sees:* Bottom sheet 'Rezervaci nelze obnovit' with the reason and 'Vybrat znovu' + 'Jiná motorka'. — clear → clear — server yes(customer_restore_booking returns date_passed, supabase/migrations/202…) — **HOLDS**

**S-092 / S-110 / Reservation detail**

- `G-385` A customer wants to edit a reservation that is completed or cancelled; the Edit button is only offered for upcoming (nadchazejici) and active (aktivni) reservations, and the late-pickup shortcut only for status reserved. The edit screen itself has NO status c… — *sees:* No Edit button on completed/cancelled cards and detail; Edit only on upcoming/active. — clear → clear — server unknown — **HOLDS**

**S-093**

- `G-397` Cancelling a booking from the list: the list wires onCancel to its own _CancelDialog, but the old card never renders a cancel button, so storno is reachable only from the detail. — *sees:* No storno button on the list card. — clear → clear — server yes(cancel_booking_tracked) — **HOLDS**
- `G-398` Internal guards of the unreachable list dialog: back blocked while cancelling (PopScope canPop !_loading), Zpět and Zrušit disabled with spinner while loading, colour-coded refund preview, result shown in the same dialog. — *sees:* Not reachable by the customer. — silent → silent — server yes(cancel_booking_tracked) — **HOLDS**

**S-094**

- `G-399` Storno went through (or was already done): confirmation with the money outcome - unpaid (nothing to refund), refund amount and percent, refund not known yet (answer lost), or no refund. — *sees:* Dialog "✓ Rezervace zrušena" with the outcome text and "Zavřít". — clear → clear — server yes(cancel_booking_tracked computes refund; send-cancellation-email handl…) — **HOLDS**
- `G-400` Storno failed: the reason is translated (not yours, not found, network, uncertain, generic) and Retry is offered only when retrying can help. — *sees:* Red heading "Storno se nepovedlo" / uncertain heading, reason, Zpět + Zkusit znovu or Zavřít. — clear → clear — server yes(cancel_booking_tracked errors) — **HOLDS**
- `G-401` The server refuses storno because the booking is no longer pending/reserved (wrong_status): the app shows the generic failure with Retry, which cannot succeed. — *sees:* Generic "Storno se nepovedlo" text with "Zkusit znovu". — small → small — server yes(cancel_booking_tracked {error:wrong_status}, SUPABASE_BACKEND_STATE_3…) — **HOLDS**
- `G-403` Which outcome text is chosen depends on wasPaid = paymentStatus == "paid" only; a booking in partial_refund or refund_pending is treated as unpaid and gets the "nothing to refund" text. — *sees:* Possibly the unpaid text after a partly refunded booking. — small → small — server yes(refund computed by cancel_booking_tracked regardless) — **HOLDS**

**S-094 / Cancel dialog**

- `G-402` The storno answer was lost (timeout / dropped connection): before saying "nothing changed" the app re-reads the booking status and, if cancelled, the refund from booking_cancellations. — *sees:* Correct outcome dialog (done / uncertain / network). — clear → clear — server yes(booking_cancellations written by cancel_booking_tracked) — **HOLDS**

**S-095**

- `G-412` In the released 4.1.3 the detail showed a large green banner "fill in the handover protocol" for a self-service booking in its term until signed (RPC can_fill), opening the in-app protocol. The current original look and v2 both no longer have it, because sinc… — *sees:* 4.1.3: green banner with heading; now only the small amber note under the motorcycle code (previous record). — clear → small — server yes(kiosk protocol_required; submit-handover-protocol mode kiosk) — **HOLDS**
- `G-413` Completed booking: the rating card appears only for completed bookings; the same rating logic (one request at a time, rollback on error) serves both looks. — *sees:* Star card with Google review and feedback options. — clear → clear — server unknown — **HOLDS**
- `G-421` Back from the detail returns to where the customer came from, or to the Reservations list. — *sees:* Green back button. — clear → clear — server no — **HOLDS**
- `G-422` Unused v2 widgets with their own actions exist but are not wired anywhere (e.g. ResCoTedV2 with an SOS button, ResActionTilesV2, ResDocsV2, ResMoneyV2, ResJourneyV2, ResGearV2, ResTitleBlockV2). — *sees:* Nothing (not reachable). — silent → silent — server no — **HOLDS**

**S-095 / Reservation detail**

- `G-417` Cancelled booking in the detail: the only action is "Obnovit rezervaci", which runs the same restore-and-pay with server checks (4.1.3 did a client-side availability check and wrote the booking row directly). — *sees:* Button "Obnovit rezervaci" -> payment or explanation sheet. — clear → clear — server yes(customer_restore_booking - pending deploy; _guard_customer_booking_st…) — **HOLDS**

**S-095 / S-099 Paid change banner / Reservation detail**

- `G-420` After paying for a bike swap or booking edit, the customer opens the booking while the paid change is still being written to the server; the app tells them it is not finished yet so they do not pay again or assume it failed. — *sees:* Amber box '⏳ Výměna motorky se dokončuje…' / 'Úprava se dokončuje…' with a short explanation. — clear → clear — server unknown — **HOLDS**

**S-095 / S-100 Status header + rental facts + places**

- `G-404` The booking cannot be found (deleted / not the customer's) or fails to load; the customer gets a reason, back, retry, never a raw exception. — *sees:* Error screen with explanation, 'Moje rezervace' / 'Zkusit znovu' / back. — clear → clear — server no — **HOLDS**
- `G-405` The 5-second refresh or realtime update fails (weak LTE at a self-service branch); the already loaded booking and codes stay visible with a 'data may be old' note and retry, instead of disappearing. — *sees:* Thin note 'Data mohou být zastaralá' with 'Zkusit znovu'. — small → small — server no — **HOLDS**

**S-095 / S-101 Self-service 12:00 release note / Reservation detail + confirmation / Reservation detail**

- `G-407` Customer booked a self-service pickup with the 'pickup from 12:00' discount; the kiosk will not release the locker or bike codes before 12:00 Prague on the start day, and the detail warns about it until that moment. — *sees:* Amber box '🌗 Výdej na pobočce až od 12:00 dne <datum>…'. — small → clear — server yes(_kiosk_release_at; kiosk_resolve_code -> pickup_too_early, per CLAUDE…) — **HOLDS**

**S-095 / S-102 Financial summary**

- `G-408` Customer checks whether the booking is paid; an unpaid/pending payment is shown as the raw status, a paid one with a check mark. — *sees:* Row 'Platba: ✓ Zaplaceno' or e.g. 'Platba: UNPAID'. — small → small — server no — **HOLDS**

**S-095 / S-104 Access codes card / Reservation detail / Reservation detail (codes card) / Reservation detail – access codes**

- `G-411` Self-service branch: the bike code is already issued but the handover protocol is not signed; the kiosk will not open the bike box without the signed protocol, so a note under the code says to sign the protocol first (on the branch display). — *sees:* Amber bold line '📝 Nejdřív podepište předávací protokol…' under the bike code. — small → silent — server yes(kiosk protocol_required, CONTRACT §28) — **WEAKER (major)**

**S-095 / S-104 Access codes card / Reservation detail / Reservation detail – access codes**

- `G-410` Bike swap at a self-service branch: the new bike's code is withheld until the original bike is returned; the 'upload documents' button is deliberately NOT offered (it would not help), only the reason 'Vraťte nejdřív původní motorku' is shown. — *sees:* Code row shows 'Vraťte nejdřív původní motorku' (localized) instead of the number; no button. — small → silent — server yes(withhold_swap_next_codes / release_my_door_codes) — **WEAKER (major)**

**S-095 / S-104 Access codes card / Reservation detail – access codes**

- `G-409` Door codes are shown only during the rental term and only when codes exist; codes held back (missing documents, not yet released) show the reason instead of the number, with a button that tries release_my_door_codes and otherwise sends the customer to upload… — *sees:* Card "Přístupové kódy" with numbers or the hold-back reason, button "Nahrát doklady pro kódy". — clear → small — server yes(get_my_door_codes, release_my_door_codes, booking_docs_gate, trg_zz_d…) — **WEAKER (major)**

**S-095 / S-107 State-dependent action buttons**

- `G-416` Completed booking: 'Znovu rezervovat' clears the old booking draft and selected bike, opens the same bike so the customer chooses NEW dates (availability is checked again downstream), or goes Home if the bike no longer exists. — *sees:* Bike detail opens + toast 'Vyberte termín pro stejnou motorku' (or Home + 'Vyberte motorku'). — clear → small — server no — **HOLDS**

**S-095 / S-107 State-dependent action buttons / Reservation detail**

- `G-406` Buttons follow the server state without restart (protocol signed at the kiosk, booking activated by code): detail refreshes every 5 s and on realtime booking changes. — *sees:* Status and buttons change by themselves. — silent → silent — server no — **HOLDS**
- `G-418` Active booking (bike handed over): the customer can edit but NOT cancel (cancelling would void codes during the ride). — *sees:* Green 'Upravit rezervaci' (+ SOS), no red cancel button. — clear → clear — server no — **HOLDS**

**S-095 / S-107 State-dependent action buttons / S-098**

- `G-419` Upcoming booking (not yet handed over, also on pickup day): edit and cancel are offered; cancel opens the cancellation dialog (refund rules inside). — *sees:* Green 'Upravit rezervaci' and red '🗑️ Zrušit rezervaci'. — clear → clear — server yes(cancel_booking_tracked only pending/reserved) — **HOLDS**

**S-095 / S-107 State-dependent action buttons / S-138 Booking document opening flow / Reservation detail**

- `G-414` Completed booking: 'Konečná faktura' — if no final invoice exists yet the customer is told it is not ready; offline gives the real reason + retry; double taps ignored; waiting can be cancelled after 15 s. — *sees:* Progress overlay; toast 'Faktura zatím není' or error snack with 'Zkusit znovu'. — clear → clear — server yes(invoices / generated_documents under owner RLS; exact policies not lo…) — **HOLDS**

**S-095 / S-108 Booking documents buttons / S-138 Booking document opening flow / Reservation detail**

- `G-415` Reservation detail shows document buttons only for documents that really exist (current version), and only in the right state: completed -> final invoice + contract + signed protocols; in rental term or active -> contract + protocols if present; otherwise non… — *sees:* Outlined buttons '💰 Konečná faktura', '📄 Nájemní smlouva', '📝 Předávací protokol', '⚠️ Protokol o poškození'. — clear → clear — server yes(generated_documents / documents bucket RLS; not looked up) — **HOLDS**

**S-097**

- `G-423` Payment status label: a paid booking that has been cancelled reads "Čeká na vrácení" (refund pending), not "Zaplaceno"; other states mapped like the back office. — *sees:* Row "Stav platby" with the label (green only when paid). — small → small — server no — **HOLDS**
- `G-424` An unpaid edit surcharge (mod_surcharge_due without mod_surcharge_paid_at) is shown bold in red with its variable symbol. — *sees:* Red row "Doplatek k úhradě" and VS row; no pay button on this tab. — small → small — server unknown — **HOLDS**
- `G-425` The Stripe transaction number is shown only for a paid card payment (an unfinished attempt also overwrites stripe_payment_intent_id). — *sees:* Copyable row only when paid by card. — silent → silent — server no — **HOLDS**
- `G-426` The green "payment processed" confirmation appears only for a paid, not cancelled booking. — *sees:* Green box with a tick. — clear → clear — server no — **HOLDS**
- `G-427` Only issued documents are listed (draft and cancelled invoices are filtered out). — *sees:* List "Doklady" with invoice tiles. — silent → silent — server yes(invoices RLS; not looked up) — **HOLDS**
- `G-428` Card-minimum rounding (+) or waived remainder (−) is shown as its own line when non-zero. — *sees:* Extra row with the amount. — small → small — server no — **HOLDS**
- `G-429` Loading the payment details fails: no message; the tab shows only the rows derivable from the booking already loaded (failed invoice fetch is swallowed). — *sees:* Fewer rows, no error text. — silent → silent — server no — **HOLDS**
- `G-430` Long IDs (transaction, reference, VS, refund) copy to the clipboard on tap with a confirmation. — *sees:* Copy icon and toast. — clear → clear — server no — **HOLDS**

**S-098**

- `G-432` Storno needs an explicit confirmation; "Zpět" keeps the booking. — *sees:* Dialog "Zrušit rezervaci?" with "Zpět" and red "Zrušit rezervaci". — clear → clear — server no — **HOLDS**
- `G-434` The reason is optional; without one the server gets "Zrušeno zákazníkem". — *sees:* Optional text field. — small → small — server no — **HOLDS**
- `G-435` After storno the result (refund or reason for failure) is shown in the same dialog, and closing it refreshes the list and the detail. — *sees:* Result dialog (see S-094). — clear → clear — server yes(cancel_booking_tracked) — **HOLDS**

**S-098 / Cancel dialog**

- `G-431` Before confirming, the customer sees the refund they would currently get: 100 % from 7 days, 50 % from 2 days, otherwise 0 %, capped after an earlier date move; the box is green/amber/red. — *sees:* Coloured box "Storno podmínky" with the rules and "aktuálně vrátíme X % (Y Kč)". — clear → clear — server yes(cancel_booking_tracked / _refund_tier_pct / _storno_cap_after_move de…) — **HOLDS**
- `G-433` While the storno is being sent the dialog cannot be closed (system back / barrier) and both buttons are disabled, so the result is never lost and storno is not sent twice. — *sees:* Spinner in the button; buttons inactive. — clear → clear — server no — **HOLDS**

### During the rental (SOS, ride recording) — 134 safeguards, 10 weaker

**Ride recording (automatic pause engine and its time limits, flag ride_autopause)**

- `X-2-03` While a ride is being recorded the app pauses it itself (about 5 min standing or 3 min walking, resumes at about 20 km/h); an own ride standing near its start for 3 h triggers a phone notification; an own ride standing 20 h gets one reminder when the app is o… — *sees:* 3 h: only an Android notification (rpNotifHomeTitle/Text). 20 h: one-time snackbar 'trip standing since <date>' (RideRecorderWatcher._showNotice, ride_recorder_watcher.dart:121-133, 6-12 s) plus noti… — small → small — server no — **HOLDS**

**S-020 Discard confirmation / S-217 Ride point sheet**

- `G-1066` The stop editor cannot be dragged away; closing with unsaved text or new photos asks 'Discard changes?'. — *sees:* Discard / Stay dialog. — clear → clear — server no — **HOLDS**

**S-212 My experiences**

- `G-1026` A signed-out customer opens the first tab (rides + created routes); the account data is not shown and they are asked to log in. — *sees:* Key emoji, the sentence myExpLogin and a green Log in button. — clear → clear — server yes(get_my_saved_routes / get_my_rides are SECURITY DEFINER for auth.uid() — **HOLDS**
- `G-1027` A signed-out customer opens the Places tab; places are hidden behind login. — *sees:* Same login prompt as above. — clear → clear — server yes(get_my_places) — **HOLDS**
- `G-1028` Pull-to-refresh is only offered on the account pages (not on the local navigation history, not when signed out). — *sees:* Nothing happens when pulling on History or when signed out. — silent → silent — server no — **HOLDS**
- `G-1029` Saved routes fail to load: the customer is told what failed and gets Try again instead of an empty list. — *sees:* Error card with reason and Try again. — clear → clear — server no — **HOLDS**
- `G-1030` My places fail to load: reason and Try again. — *sees:* Error view with retry. — clear → clear — server no — **HOLDS**
- `G-1031` A visited place without coordinates cannot be navigated to: the navigate button does nothing. — *sees:* The round navigate button looks the same but does nothing when tapped. — silent → clear — server no — **HOLDS**
- `G-1032` Opening a history entry of a custom route whose stored data is missing does nothing. — *sees:* Nothing happens on tap. — silent → silent — server no — **HOLDS**
- `G-1033` History card action: a finished navigation restarts from the beginning (Ride again), an unfinished one continues; the action opens navigation only if a route can be rebuilt. — *sees:* Button label switches between Continue route and Ride again. — clear → clear — server no — **HOLDS**
- `G-1034` The trash icon on the ACTIVE navigation entry ends the navigation (moves it to history) instead of deleting it; there is no confirmation in either look. — *sees:* Entry is ended / removed immediately, no question. — silent → silent — server no — **HOLDS**
- `G-1035` The Merge rides row is only offered when the server knows trips and there are at least two list items. — *sees:* Row simply absent otherwise. — silent → silent — server yes(set_user_rides_trip must exist; missing RPC -> unavailable) — **HOLDS**
- `G-1036` While recording with location switched off, a warning banner says the recording is standing still and offers Open settings. — *sees:* Amber banner with pin emoji, text eoRideGpsLost, Open settings button. — clear → clear — server no — **HOLDS**
- `G-1037` Recording, pause and the auto-record switch were only reachable on this screen when signed in (they live on the account page). A signed-out start attempt is refused by the recorder. — *sees:* Old: no record card when signed out; from other entry points a snackbar 'sign in'. — small → clear — server yes(start_user_ride / create_manual_ride GRANT authenticated only) — **HOLDS**
- `G-1038` Ride and trip cards show a recording badge while that ride is being recorded. — *sees:* Red/amber chip on the card. — clear → clear — server no — **WEAKER (minor)**

**S-213 Recording controls card**

- `G-1039` On iOS with only approximate location the start is refused (precise location required). — *sees:* Snackbar with Open settings. — small → clear — server no — **HOLDS**
- `G-1040` The server does not accept the new ride (offline / error): start is rolled back, points of the failed attempt are dropped, customer told it failed. — *sees:* Snackbar 'could not start'. — small → clear — server yes(start_user_ride / create_manual_ride) — **WEAKER (major)**
- `G-1041` A new ride cannot start while the previous ride's stop is still unsaved (offline): the app first tries to save it, otherwise refuses. — *sees:* Generic 'could not start' message. — small → clear — server no — **WEAKER (major)**
- `G-1042` While a recording runs, the start card is replaced by the status and Pause/Continue controls; a second start is ignored. — *sees:* Status card with red/amber/grey state and buttons. — clear → clear — server yes(start_user_ride is idempotent - returns the running ride) — **HOLDS**
- `G-1044` A rental (automatic) recording cannot be stopped by the customer: the Stop button exists only for an own manual ride. — *sees:* No Stop button during a rental. — silent → silent — server no — **HOLDS**
- `G-1045` The card explains that a rental recording ends by itself when the motorbike is returned. — *sees:* Grey hint under the buttons on the page. — small → small — server no — **WEAKER (minor)**
- `G-1046` After a safety pause (phone at home / long pause) the recording asks the customer to decide: continue the trip or end and save. — *sees:* Amber box with battery emoji and the question, buttons 'Continue trip' / 'End and save'. — clear → small — server no — **WEAKER (major)**
- `G-1047` Stopping while offline is not reported as 'too short'; the app retries saving. — *sees:* Snackbar 'could not finish, will retry'. — small → clear — server yes(finish_user_ride) — **HOLDS**
- `G-1048` Continue after a manual pause runs the same checks as a start (signed in, location on, permission, precise). — *sees:* Same snackbars as start. — small → clear — server no — **HOLDS**
- `G-1049` Switching off automatic recording immediately ends a running rental recording, without a question. — *sees:* Switch flips; recording ends silently. — silent → silent — server no — **HOLDS**
- `G-1050` v2 asks 'End the recording?' before stopping an own ride (the old card stopped at once). — *sees:* No confirmation in the old look. — silent → clear — server no — **HOLDS**

**S-213 Recording controls card / Ride recording**

- `G-1043` Double tap lock: in the old card the start/stop/pause buttons are locked while an action runs (busy, half-transparent). — *sees:* Buttons fade to 50 % and ignore taps while working. — clear → silent — server no — **WEAKER (minor)**

**S-214 Ride pause / recording status sheet**

- `G-1051` In the sheet, Stop is offered only for an own manual ride; a rental shows why it cannot be stopped. — *sees:* Only Pause/Continue for a rental, with a grey hint. — small → small — server no — **HOLDS**
- `G-1052` After a safety pause the sheet asks Continue trip / End and save. — *sees:* Amber question box. — clear → clear — server no — **HOLDS**
- `G-1053` Continue from the sheet re-runs the location checks; a failure is explained. — *sees:* Snackbar with settings action. — small → clear — server no — **HOLDS**
- `G-1054` Stop from the sheet uses the same stop and reports saved / too short / offline. — *sees:* Snackbar result. — small → clear — server yes(finish_user_ride) — **HOLDS**

**S-215 Delete saved route confirmation**

- `G-1055` Deleting a saved route requires confirmation (Cancel / red Delete). — *sees:* Dialog 'Delete route?' with the route name. — clear → clear — server yes(delete_user_route WHERE user_id = auth.uid() — **HOLDS**
- `G-1056` A failed delete is reported instead of pretending success. — *sees:* Error snackbar. — small → small — server yes(delete_user_route returns success:found) — **HOLDS**

**S-216 Ride detail**

- `G-1057` Only the customer's own rides can be opened; a foreign or deleted ride id (or signed-out user) shows 'Ride not found' with a way back. — *sees:* Bike emoji, 'Ride not found', green back button. — clear → clear — server yes(get_my_rides returns only the caller's rides; RLS user_rides_owner) — **HOLDS**
- `G-1058` A load error is not shown as 'not found': reason + Try again + Back. — *sees:* Error view. — clear → clear — server no — **HOLDS**
- `G-1059` Sharing switch (private / public) is locked while saving; a failed save is reported with retry. A ride stays private until the rider turns it on. — *sees:* Switch greyed while saving; error snackbar with retry. — small → small — server yes(update_user_ride owner-only; public only via get_public_rides) — **HOLDS**
- `G-1060` Editing name/description: Cancel discards, a failed save is reported with retry. — *sees:* Dialog; error snackbar. — small → small — server yes(update_user_ride) — **HOLDS**
- `G-1061` Deleting a ride requires confirmation. — *sees:* Dialog 'Delete ride?' with name. — clear → clear — server yes(delete_user_ride owner-only) — **HOLDS**
- `G-1062` Deleting the ride that is being recorded: the dialog warns what happens (a rental re-records from now, an own ride stops) and the recorder is detached before delete. — *sees:* Warning sentence in the dialog body. — small → small — server no — **HOLDS**
- `G-1063` A failed ride delete keeps the customer on the detail and says so (it used to leave as if deleted). — *sees:* Error snackbar with retry. — small → small — server yes(delete_user_ride returns success:found) — **HOLDS**
- `G-1064` Adding a stop by tapping the map / editing a stop goes through the stop editor; the server limits stops and checks ownership. — *sees:* Stop editor sheet. — small → small — server yes(save_ride_point: owner, max 200 points, coordinates required for a ne…) — **HOLDS**
- `G-1065` 'Add to trip' is offered only when trips are available; 'Remove from trip' is locked while running and reports the result with Undo. — *sees:* Text buttons; remove greys while busy; snackbar with Undo. — small → silent — server yes(set_user_rides_trip, own rides only) — **WEAKER (minor)**

**S-217 Ride point sheet**

- `G-1067` At most 8 photos per stop: the add tile disappears when full and the picker only takes the free slots. — *sees:* Add tile simply absent. — silent → small — server no — **HOLDS**
- `G-1068` No access to photos: the reason and fix are shown inside the sheet. — *sees:* Red text in the sheet. — small → clear — server no — **HOLDS**
- `G-1069` A failed save keeps the sheet open with the text kept; photos that did not upload are reported; a repeated save edits the same new stop instead of creating a second one. — *sees:* Red error text in the sheet. — small → clear — server yes(save_ride_point owner check, 200 point limit; storage policy media_ri…) — **HOLDS**
- `G-1070` Save button is disabled while saving. — *sees:* Spinner in the button. — clear → clear — server no — **HOLDS**
- `G-1071` Delete is offered only for an existing stop and is ignored while busy (no confirmation in either look). — *sees:* Trash icon only when editing an existing stop. — silent → silent — server yes(delete_ride_point joins user_rides on auth.uid() — **HOLDS**
- `G-1072` New photos are uploaded only for a signed-in user. — *sees:* Photos silently not uploaded if signed out. — silent → silent — server yes(storage media_ride_upload for authenticated only) — **HOLDS**

**S-218 Ride share sheet**

- `G-1073` The share link uses only the longest continuous part of the track (no invented straight line over a gap); no link when fewer than 2 points. — *sees:* Shared text without a map link. — silent → silent — server no — **HOLDS**
- `G-1074` Facebook needs a map link; when there is none, or the target app cannot open, the customer is told sharing failed. — *sees:* Snackbar 'sharing failed'. — small → small — server no — **HOLDS**

**S-219 Trip detail**

- `G-1075` A trip that no longer exists (split / deleted elsewhere) shows a clear message with Back. — *sees:* Error view with back. — clear → clear — server no — **HOLDS**
- `G-1076` While a trip operation runs, all actions are locked (rename, split, delete, share, sharing switch). — *sees:* Greyed actions. — clear → silent — server no — **WEAKER (major)**
- `G-1077` Visibility switch for the whole trip is locked while saving; failures are reported. — *sees:* Switch greyed; snackbar on failure. — small → small — server yes(update_user_ride per ride) — **HOLDS**
- `G-1078` Trip operation failures (partial / server without trips / offline) are reported; success offers Undo. — *sees:* Snackbar with reason or Undo. — small → silent — server yes(set_user_rides_trip) — **WEAKER (major)**

**S-220 Merge rides into a trip**

- `G-1083` Merging needs at least two selected rides/trips. — *sees:* Grey button; tap explains 'pick at least two'. — small → clear — server yes(set_user_rides_trip requires 1-300 items; the two-item rule is client…) — **HOLDS**
- `G-1084` When the server does not support trips, the merge screen disables selection and the button and shows an amber note. — *sees:* Amber note, greyed rows and button. — clear → small — server yes(missing set_user_rides_trip -> RideTripOpResult.unavailable) — **HOLDS**
- `G-1085` With fewer than two rides there is nothing to merge: a note, no button. — *sees:* Amber note 'nothing to merge'. — small → clear — server no — **HOLDS**
- `G-1086` While merging, selection and the button are locked. — *sees:* Spinner, rows inert. — clear → clear — server no — **HOLDS**
- `G-1087` Merging into an already named trip pre-fills that trip's name in the name dialog (so it is not lost). — *sees:* Dialog opens with the existing name. — small → silent — server no — **WEAKER (minor)**
- `G-1088` A failed merge keeps the customer on the screen with the reason; success returns with Undo. — *sees:* Snackbar. — small → clear — server yes(set_user_rides_trip) — **HOLDS**

**S-221 Trip name / confirm dialogs, trip delete sheet**

- `G-1079` Splitting a trip asks for confirmation. — *sees:* Dialog with Cancel / Split. — clear → clear — server yes(set_user_rides_trip) — **HOLDS**
- `G-1080` Deleting a trip: first choose 'only ungroup' or 'delete all rides', then a red confirmation with the number of rides. — *sees:* Choice sheet, then red Delete dialog. — clear → clear — server yes(delete_user_ride per ride, owner-only) — **HOLDS**
- `G-1081` Deleting a trip that contains the ride being recorded warns what happens and detaches the recorder. — *sees:* Extra warning sentence in the dialog. — small → small — server no — **HOLDS**
- `G-1082` Trip name dialog: Cancel aborts the operation; name max 120 characters; empty = default name by dates. — *sees:* Dialog with counter. — small → small — server yes(set_user_rides_trip trims to 120) — **HOLDS**

**S-222 Ride recorder watcher**

- `G-1089` Automatic recording runs only during a really picked-up, not yet returned motorbike rental (not the whole calendar day); gear-only rentals are never recorded. — *sees:* Nothing visible; recording simply does not start. — silent → silent — server yes(start_user_ride finds the caller's own reserved/active booking itself…) — **HOLDS**
- `G-1090` No decision is taken until reservations have loaded (an empty list while loading must not look like 'rental ended'). — *sees:* Nothing. — silent → silent — server no — **HOLDS**
- `G-1091` Auto start needs the auto-record switch on, a signed-in user and an already granted location permission (never prompts from the background); it is suppressed shortly after the server ended the rental ride. — *sees:* Nothing. — silent → silent — server yes(start_user_ride authenticated only) — **HOLDS**
- `G-1092` An unsaved previous ride (offline) is saved first, with a retry pause after failures. — *sees:* Nothing. — silent → silent — server yes(finish_user_ride) — **HOLDS**
- `G-1093` Picking up a rental while an own ride is paused saves the own ride and records the rental; a riding own ride is not interrupted. — *sees:* One-time notice snackbar. — small → small — server no — **HOLDS**
- `G-1094` SOS bike swap or a follow-up rental: the old ride is saved and the new bike gets a new ride; two bikes on one account keep the rental being recorded. — *sees:* Nothing / notice. — silent → silent — server yes(start_user_ride pairs by booking id, own bookings only) — **HOLDS**
- `G-1095` When the rental has ended the ride is closed in whatever phase it is. — *sees:* Nothing. — silent → silent — server yes(close_stale_user_rides cron every 15 min) — **HOLDS**
- `G-1096` Recorder notices are shown once as a snackbar and then consumed. — *sees:* Snackbar 6-12 s. — small → small — server no — **HOLDS**
- `G-1097` Points are flushed when the app goes to the background and the GPS stream is checked when it returns. — *sees:* Nothing. — silent → silent — server yes(append_ride_track) — **HOLDS**

**S-019 Shared error dialog / S-183**

- `G-681` An SOS action fails (report, tow, replacement, continue riding): the customer is told why and offered the nonstop line, 112 or retry. — *sees:* Dialog with 📞, 🆘 112 and Zkusit znovu. — clear → clear — server no — **HOLDS**
- `G-682` Location share result: success only for SosLocResult.ok; otherwise the reason, plus 'Open settings' only for missing permission / location off. — *sees:* Success toast or reason dialog with call / settings / retry. — clear → clear — server no — **HOLDS**

**S-019 Shared error dialog / S-187**

- `G-703` Upload fails (camera permission, network, incident cannot be created); the customer gets the reason and Settings (only if needed) / send via Messages / Retry. — *sees:* Error dialog. — clear → clear — server unknown — **HOLDS**

**S-019 Shared error dialog / S-188**

- `G-712` SOS replacement bike was taken by someone else meanwhile: selection is cleared, the list reloads and the customer is told to pick another one (no pointless retry). — *sees:* Dialog 'bike no longer available' + 'Vybrat jinou'. — clear → clear — server yes(RPC sos_swap_bookings refuses an unavailable bike) — **HOLDS**

**S-020 Discard confirmation / S-182**

- `G-680` Closing the sheet (✕, Cancel, system back) with text or photos filled asks for confirmation before discarding. — *sees:* Dialog 'Zahodit?' with Discard / Stay. — clear → clear — server no — **HOLDS**

**S-178**

- `G-663` The customer wants to open SOS when no rental is running; every in-app SOS entry is hidden unless a reservation is sosAllowed (picked up, or paid and inside its term, and not ended by SOS). — *sees:* The red SOS button / menu row simply is not there; a push of type sos opens Messages instead. — silent → silent — server no — **HOLDS**
- `G-664` The active-incident status cannot be loaded (outage); instead of silently hiding the incident, the start screen shows an error card with Retry and Call nonstop. — *sees:* Compact error card 'eoSosStatusFail' + retry + red call button. — clear → clear — server no — **HOLDS**
- `G-666` The incident is attached only to the rental that is running right now (status active, or paid and today inside the term, not ended by SOS), never to an upcoming booking. — *sees:* Nothing; the booking link is invisible. — silent → silent — server unknown — **HOLDS**
- `G-667` While the report is being sent (GPS up to 20 s, insert up to 45 s, photos up to 40 s) the customer cannot close the progress or send twice. — *sees:* Blocking progress dialog 'Odesílám hlášení... (zjišťuji polohu)'. — clear → clear — server no — **HOLDS**
- `G-668` Creating the incident fails (offline, auth, server); the app never claims success and offers Call nonstop, 112 and Retry. — *sees:* Error dialog with reason + 'Zavolat nonstop', '112', 'Zkusit znovu'. — clear → clear — server no — **HOLDS**
- `G-669` Some photos could not be uploaded after the incident was created; the customer is warned to send the rest in Messages. — *sees:* Warning toast 'photoUploadFailed' + 'eoSosPhotosLater' (8 s). — small → small — server no — **HOLDS**

**S-178 / SOS**

- `G-670` Share location: success is reported only when the position really reached MotoGo; without permission, GPS off, no fix or offline the customer gets the reason with Settings / Call / Retry. — *sees:* Progress dialog, then either a success toast or a reason dialog. — clear → clear — server yes(RPC sos_share_location returns true only for the caller's own inciden…) — **HOLDS**

**S-178 / SOS – any report**

- `G-665` The customer reports a second serious incident while one (theft / accident_minor / accident_major / breakdown_major) is still open; the app silently reuses the open incident instead of creating a new one. — *sees:* Normal 'incident reported' result; photos and text go to the existing incident. — silent → silent — server yes(trigger trg_one_active_sos -> check_one_active_sos, STATE_4:93; per b…) — **HOLDS**

**S-179**

- `G-672` Only the newest open incident is considered and the banner is hidden while the state is loading. — *sees:* No banner until the state is known. — silent → silent — server no — **HOLDS**

**S-179 / SOS start / SOS – start screen**

- `G-671` An open incident exists; the start screen shows a tappable 'Active SOS incident' banner only while status is not resolved/closed, so the customer goes to the existing incident instead of starting over. — *sees:* Amber banner with status, short id and 'tap to open detail'. — clear → clear — server no — **HOLDS**

**S-180**

- `G-674` 'Serious accident / bike immobile' and 'Theft' never create a minor report directly; they lead to the dedicated screens where fault / secured decisions are required. — *sees:* Next SOS screen. — clear → clear — server no — **HOLDS**

**S-180 / SOS report sheet**

- `G-673` 'Minor accident, I continue' does not create anything until the mandatory description/photo sheet is completed. — *sees:* Report sheet opens; cancelling it leaves no incident. — clear → clear — server no — **HOLDS**

**S-181**

- `G-675` 'Minor defect, I continue' goes through the same mandatory report sheet before any incident exists. — *sees:* Report sheet. — clear → clear — server no — **HOLDS**
- `G-676` 'Bike immobile' and 'Nearest service, I pay the invoice' route to their own screens (free tow/replacement vs. own repair) instead of reporting a minor defect. — *sees:* Next SOS screen. — clear → clear — server no — **HOLDS**

**S-182**

- `G-677` The customer tries to send the report with a description shorter than 3 characters; Send is disabled. — *sees:* Grey disabled red button; label 'Popis *'. — small → clear — server no — **HOLDS**
- `G-679` Camera unavailable or permission denied: the sheet explains why and offers Open settings. — *sees:* Amber note with reason + 'Otevřít nastavení'. — small → clear — server no — **HOLDS**

**S-182 / SOS – minor accident / minor breakdown report**

- `G-678` The customer tries to send without a photo; Send stays disabled until at least one photo is taken, unless the camera/gallery really failed (then the report may go without photos and is marked '[bez fotek - kamera nedostupná]'). — *sees:* Disabled button; after a camera failure the button reads 'Odeslat bez fotky'. — small → clear — server no — **HOLDS**

**S-183**

- `G-683` The report reached MotoGo but without GPS; the customer is told to tell the dispatcher where they are. — *sees:* Toast 'eoSosNoLocTitle' for 9 s. — small → small — server no — **HOLDS**

**S-184**

- `G-685` Double tap on replacement or tow while a request runs is ignored. — *sees:* Nothing visible (cards just do not react). — silent → clear — server no — **HOLDS**
- `G-686` An open incident is reused instead of creating a new one before replacement or tow. — *sees:* Nothing. — silent → silent — server yes(trg_one_active_sos) — **HOLDS**
- `G-687` Ending the ride with a tow is confirmed only after the request was saved; on failure the customer is told to arrange the tow by phone. — *sees:* Toast 'Odtah objednán' and done screen, or failure dialog. — clear → clear — server no — **HOLDS**
- `G-688` Ordering a replacement first creates/reuses the incident; on failure the replacement screen is not opened. — *sees:* Failure dialog with retry; otherwise the replacement screen. — clear → clear — server yes(replacement itself is checked by sos_swap_bookings) — **HOLDS**
- `G-689` Share GPS on the accident screen reports success only when the position arrived. — *sees:* Progress, then success toast or reason dialog. — clear → clear — server yes(sos_share_location) — **HOLDS**

**S-184 / SOS – major accident (immobile)**

- `G-684` Serious accident: the customer must say whether it was their fault before 'Free replacement' and 'End ride / tow' appear or run. — *sees:* The two action cards are simply absent until a fault card is tapped. — silent → clear — server no — **HOLDS**

**S-185**

- `G-690` Double tap on replacement or tow while a request runs is ignored. — *sees:* Nothing visible. — silent → clear — server no — **HOLDS**
- `G-691` A breakdown is always recorded as not the customer's fault and free (fault forced to false / null); the description is optional with a default text. — *sees:* Green note 'breakdownFreeInfo'. — small → clear — server no — **HOLDS**
- `G-692` Tow / end of ride is confirmed only when saved; failure gives the reason and the phone fallback. — *sees:* Toast 'rentalFreeReturn' + done screen, or failure dialog. — clear → clear — server no — **HOLDS**
- `G-693` Ordering a replacement creates/reuses the incident first; on failure the replacement screen is not opened. — *sees:* Failure dialog with retry. — clear → clear — server yes(sos_swap_bookings at confirm) — **HOLDS**
- `G-694` Share GPS on the breakdown screen reports success only when the position arrived. — *sees:* Progress, then toast or reason dialog. — clear → clear — server yes(sos_share_location) — **HOLDS**

**S-186**

- `G-695` The theft report button cannot be pressed twice: disabled while sending and permanently after a successful report. — *sees:* Button turns green '✅ Krádež nahlášena MotoGo24' and stays disabled. — clear → clear — server yes(trg_one_active_sos blocks a duplicate open incident) — **HOLDS**
- `G-696` The replacement offer appears only after the theft was successfully reported. — *sees:* Section 'Chceš náhradní motorku?' appears below. — clear → clear — server no — **HOLDS**
- `G-698` Theft report fails; the customer gets the reason with call / 112 / retry. Without GPS the success is replaced by the 'sent without location' warning. — *sees:* Failure dialog, or toast. — clear → clear — server no — **HOLDS**
- `G-699` Unsecured bike is recorded as customer fault (isFault = _secured == false). — *sees:* Liability note on screen (theftSecuredInfo / theftUnsecuredInfo). — small → small — server no — **HOLDS**

**S-186 / SOS – theft**

- `G-697` The customer taps 'Order replacement' without answering whether the bike was secured; the app refuses and asks for the answer. — *sees:* Warning toast. — small → small — server no — **HOLDS**

**S-187**

- `G-700` Invoice upload cannot be started twice and the button is locked while uploading. — *sees:* Spinner in the button. — clear → clear — server no — **HOLDS**
- `G-701` After a successful upload the upload button is replaced by '✓ Faktura nahrána' and cannot be used again. — *sees:* Green label 'Faktura nahrána'. — clear → clear — server no — **HOLDS**
- `G-702` 'Done - back to overview' is offered only after the invoice was uploaded. — *sees:* Button absent until upload. — silent → silent — server no — **HOLDS**
- `G-704` Cancelling the camera does nothing (no incident claim, no upload). — *sees:* Back on the screen unchanged. — silent → silent — server no — **HOLDS**

**S-188**

- `G-706` No free bike exists; the customer is pointed to the phone line instead of an empty list. — *sees:* Amber note 'sosNoMotos' + phone + red call button. — clear → clear — server no — **HOLDS**
- `G-707` The bike list cannot be loaded; error with retry and call. — *sees:* Compact error view. — clear → clear — server no — **HOLDS**
- `G-708` Confirm without choosing a bike is refused. — *sees:* Toast 'Vyber náhradní motorku'. — small → small — server yes(sos_swap_bookings p_replacement_moto_id IS NULL -> raise) — **HOLDS**
- `G-709` Confirm without a delivery address is refused (field text must be non-empty; GPS coordinates are added only to an unedited suggestion). — *sees:* Toast 'Zadej adresu přistavení'. — small → small — server no — **HOLDS**
- `G-710` Confirm cannot be sent twice while the swap runs. — *sees:* Spinner in the button. — clear → clear — server yes(sos_swap_bookings double_swap_protection, 20261011c:120-155) — **HOLDS**
- `G-711` No open incident (or its state failed to load): replacement is refused with the reason and phone fallback. — *sees:* Failure dialog 'noActiveIncident' or the load error + 'eoSosReplaceByPhone'. — clear → clear — server yes(sos_swap_bookings: forbidden if not the incident owner, raises if inc…) — **HOLDS**
- `G-713` Any other swap failure: reason + 'replacement by phone' + call / 112 / retry; success is shown only after the RPC succeeded. — *sees:* Failure dialog, or toast + done screen. — clear → clear — server yes(sos_swap_bookings) — **HOLDS**
- `G-714` The replacement is always free; the app sends zero prices and cannot order a paid replacement. — *sees:* Header 'Náhradní motorka zdarma'. — clear → clear — server yes(sos_swap_bookings: customer without own prices, STATE_3:66) — **HOLDS**
- `G-715` 'Where you are now' fills the address only with location permission and GPS; otherwise it explains why. — *sees:* Row with spinner, then address or an explanation snackbar. — small → small — server no — **HOLDS**

**S-188 / SOS – replacement bike**

- `G-705` Only bikes that are free until the end of the rental are offered: not the broken bike, no trailers, not in maintenance, branch open, and motoAvailableForRange true for today..booking end. — *sees:* List contains only offerable bikes. — silent → silent — server yes(sos_swap_bookings raises 'Vybraná motorka není do konce pronájmu voln…) — **HOLDS**

**S-189**

- `G-716` Incident state still loading or failed: the screen says so with Retry and Call instead of claiming 'resolved / all good'. — *sees:* Loading view or error view with call button, both with back arrow. — clear → clear — server no — **HOLDS**
- `G-718` 'I continue riding' is offered only for an active minor incident (accident_minor / breakdown_minor). — *sees:* Button absent otherwise. — silent → silent — server no — **HOLDS**
- `G-719` 'I continue riding' is confirmed only after the decision was saved; the progress cannot be closed; failure gives reason + phone fallback. — *sees:* Progress, then toast + Home, or failure dialog. — clear → clear — server no — **HOLDS**
- `G-720` Only the newest open incident is shown; without one the contextual done view (by SosDoneType) appears. — *sees:* Done view or incident detail. — silent → silent — server no — **HOLDS**
- `G-721` Timeline cannot be loaded: error with retry instead of an empty list. — *sees:* Compact error view. — clear → clear — server no — **HOLDS**
- `G-722` A push of type 'sos' opens SOS only during a running rental, otherwise Messages (the task listed /sos/done; the code opens /sos or Messages). — *sees:* SOS start screen or Messages. — silent → silent — server no — **HOLDS**
- `G-723` After a finished SOS action the done screen is reached with go() so back leads Home, not back into the action (no repeated tow/replacement). — *sees:* Back arrow to Home. — clear → clear — server no — **HOLDS**

**S-189 / SOS – incident detail**

- `G-717` 'Replacement bike' is offered only for an active incident of type accident_major, breakdown_major or theft. — *sees:* Button absent otherwise. — silent → silent — server yes(sos_swap_bookings refuses closed incidents) — **HOLDS**

### Changing or cancelling (reservation edit: extend, shorten, move, swap, extras, delivery) — 106 safeguards, 2 weaker

**S-110**

- `G-557` The reservation cannot be loaded (no network, timeout 15 s) or does not exist; the screen shows an error with "Try again" and a back arrow instead of an endless spinner. — *sees:* Error state with the message, retry button and back arrow. — clear → clear — server no — **HOLDS**
- `G-558` The screen always re-reads the reservation from the database when opened, so an edit made on the web or another device is not overwritten with stale data. — *sees:* Nothing (silent correctness guard). — silent → silent — server no — **HOLDS**
- `G-560` Before any save the app re-checks that the reservation in the DB is still the one the price was computed against (dates, pickup time, bike, price, late discount, status); if not, it reloads and refuses. — *sees:* Toast editStaleTitle / editStaleReloaded and the screen reloads. — small → small — server yes(process-payment refuses a stale surcharge with 409 stale_booking per…) — **HOLDS**

**S-110 / Reservation edit / Edit reservation**

- `G-559` After the bike is physically picked up (DB status active) the customer can no longer change the start date, pickup place/time, motorcycle or paid extras; only end date, return place and return time stay editable. — *sees:* Pickup, motorcycle and extras sections are absent; header says "Aktivní"; a changed start gives toast cannotChangePickupActive. — clear → clear — server yes(tly: yes(trg_guard_booking_delivery active_pickup_locked for pickup p…) — **HOLDS**

**S-110 / S-125 Edit confirmation page**

- `G-563` After a successful save the edit form is replaced by a confirmation page, so the same change cannot be submitted twice; the way out goes to the reservations list (go, not back into the form). — *sees:* Big tick (or refund icon), title, message, 'Zpět na rezervace' button and a close ✕. — clear → clear — server no — **HOLDS**

**S-110 / S-126 Edit failure / uncertain-result sheets / Edit reservation**

- `G-561` A previous paid change / surcharge of this reservation is still being confirmed; a second change or second surcharge is refused. — *sees:* Error sheet psPendingTitle / pdEditCompletingTitle / pdSwapCompletingTitle with button to open the reservation. — clear → clear — server yes(per the comment at Motogo-app-main/motogo-app-flutter/lib/features/re…) — **HOLDS**

**S-111**

- `G-565` Switching tabs throws away a half-made date selection and the shorten direction, so a selection made on one tab is never saved under another tab. — *sees:* Calendar returns to the original dates. — clear → clear — server no — **HOLDS**
- `G-567` On the move tab only the dates can change: pickup, return, motorcycle, extras and price card are hidden (move keeps length and price). — *sees:* Only calendar + green "free" note + button. — clear → clear — server yes(reschedule_booking_free keeps price, returns length_mismatch) — **HOLDS**

**S-111 / Reservation edit (tabs) / Edit reservation**

- `G-564` The "Posunout" (free reschedule) tab is offered only for a reservation with status reserved, fully paid, and whose start is not in the past; otherwise the tab is simply missing. — *sees:* Tab absent (no explanation why). — silent → silent — server yes(reschedule_booking_free requires payment_status='paid' and returns pa…) — **HOLDS**

**S-111 / S-121 Swap bike tab (Výměna)**

- `G-566` On the swap tab the normal save button, the calendar, the place/time, bike and gear sections are hidden so the customer cannot mix a swap with another change. — *sees:* Only the swap content and its own confirm button. — clear → clear — server no — **HOLDS**

**S-111 / S-121 Swap bike tab (Výměna) / S-110 / Edit reservation**

- `G-562` A customer whose booking is not reserved/active or not paid wants to swap the bike mid-rental; the 'Výměna motorky' tab is not offered. Opening the edit through the link ?tab=swap also only lands on the swap tab under the same condition. — *sees:* No swap tab; the link opens the normal 'Prodloužit' tab. — silent → silent — server yes(split_booking_moto_swap, SUPABASE_BACKEND_STATE_3.md:82) — **HOLDS**

**S-112**

- `G-570` Running rental (active): a tap before the original start is ignored — an active rental can only be extended at the end. — *sees:* Nothing happens. — silent → silent — server unknown — **HOLDS**
- `G-572` Extend tab: tapping inside the current reservation is refused with the instruction where to tap. — *sees:* Snackbar with the instruction. — small → small — server no — **HOLDS**
- `G-573` Extending the end: all days from the old end to the tapped day must be free. — *sees:* Snackbar. — small → small — server yes(trg_check_booking_overlap) — **HOLDS**
- `G-574` Shorten tab: tapping outside the reservation is refused. — *sees:* Snackbar. — small → small — server no — **HOLDS**
- `G-575` A one-day reservation cannot be shortened. — *sees:* Snackbar. — small → small — server unknown — **HOLDS**
- `G-577` Running rental: shortening only moves the end earlier and never into the past. — *sees:* Snackbar. — small → small — server unknown — **HOLDS**
- `G-579` The occupied days come from bookedDatesProvider; while it loads or if it fails, the calendar treats all days as free (silent) and only the save-time availability check catches a clash. — *sees:* All days look free until save. — silent → silent — server yes(trg_check_booking_overlap + checkMotoAvailabilityTri at save) — **HOLDS**
- `G-580` Calendar refusal messages are shown to the customer (old: SnackBar 2 s). — *sees:* SnackBar text. — small → small — server no — **HOLDS**

**S-112 / Edit reservation – calendar**

- `G-569` Customer taps a day occupied by another booking (or pending) of this motorcycle; it is refused. — *sees:* Day dark (same colour as own reservation days in extend mode); snackbar "dayOccupied" on tap. — clear → clear — server yes(trg_check_booking_overlap, SUPABASE_BACKEND_STATE_4.md:85) — **HOLDS**
- `G-571` Extending the start earlier: the new start may not be in the past and all days between must be free. — *sees:* Snackbar with the reason. — small → small — server yes(trg_check_booking_overlap) — **HOLDS**
- `G-576` Upcoming reservation: shortening requires first choosing "shorten start" or "shorten end"; without it a tap is refused. — *sees:* Two direction buttons, instruction line, snackbar on a premature tap. — small → small — server no — **HOLDS**
- `G-578` Move tab: a day in the past is refused and the whole shifted range (same length) must be free. — *sees:* Snackbar. — small → small — server yes(reschedule_booking_free moto_overlap / customer_overlap / past_date) — **HOLDS**

**S-112 / Reservation edit calendar**

- `G-568` Customer taps a day in the past; it is refused with a message. — *sees:* Past days dark; snackbar "cannotSelectPast" on tap. — clear → clear — server yes(reschedule_booking_free past_date for move; direct UPDATE: unknown) — **HOLDS**

**S-113**

- `G-581` Move tab explains that the reschedule is free and keeps the length (informational, part of the move contract). — *sees:* Green note with swap icon. — small → small — server yes(reschedule_booking_free keeps the price) — **HOLDS**
- `G-582` Move save button stays disabled until a different start is chosen. — *sees:* Grey button "moveSaveBtn". — clear → clear — server no — **HOLDS**
- `G-583` Move with delivery to an address: new pickup must be at least 6 h from now. — *sees:* Toast with the lead-time message. — small → small — server unknown — **HOLDS**

**S-113 / Reservation edit (move) / Edit reservation**

- `G-584` Server refuses the move (bike occupied, own other booking, wrong length, past date) or the answer is lost; the customer gets a translated reason, or an "uncertain — reload" sheet instead of a false "nothing changed". — *sees:* Toast with reason / error sheet with retry / uncertain sheet with reload. — clear → clear — server yes(reschedule_booking_free) — **HOLDS**

**S-114**

- `G-585` Pickup place and time can only be changed before pickup (card hidden for an active rental and on move/swap tabs). — *sees:* Card absent. — clear → clear — server yes(trg_guard_booking_delivery: active rental → pickup unchangeable, acti…) — **HOLDS**
- `G-587` After a swap to a self-service bike, an already chosen delivery is automatically reset to the branch (fee 0). — *sees:* The option jumps back to "At branch". — silent → silent — server unknown — **HOLDS**
- `G-589` Re-entering the address the booking already has counts as "no change" (no fee, no history entry). — *sees:* Address shown unchanged. — silent → silent — server yes(trg_guard_booking_delivery) — **HOLDS**
- `G-591` Old reservation "any time on the first day" (00:01) is not overwritten until the customer touches the time picker; a line explains it. — *sees:* Line "Čas vyzvednutí: kdykoliv…". — small → small — server no — **HOLDS**
- `G-592` Self-service pickup: hint that the late-pickup discount means the kiosk releases from 12:00. — *sees:* 🌗 hint line. — small → small — server yes(_kiosk_release_at / trg_booking_kiosk_release_sync, SUPABASE_BACKEND_…) — **HOLDS**
- `G-593` Pickup time can only be set in quarter-hours 00–23 h. — *sees:* Two dropdowns. — clear → clear — server no — **HOLDS**

**S-114 / Edit reservation**

- `G-586` Self-service branch: delivery to an address cannot be newly chosen (feature flag self_service_delivery, default off); the option is shown locked with a reason. A booking that already had delivery keeps it unless the bike is swapped. — *sees:* Locked option with short reason, expandable info. — clear → clear — server unknown — **HOLDS**
- `G-588` Delivery newly chosen (or address changed) without an entered address / computed route fee: saving is refused (otherwise delivery would be free). — *sees:* Address row reads "clickEnterAddress"; toast on save. Save button stays enabled. — small → small — server yes(trg_guard_booking_delivery delivery_fee_guard, SUPABASE_BACKEND_STATE…) — **HOLDS**
- `G-590` Delivery to an address: the (new) pickup must be at least 6 h from now when start, pickup time or method changes. — *sees:* Toast with lead-time message on save. — small → small — server unknown — **HOLDS**

**S-115**

- `G-594` Return place/time card is hidden on move and swap tabs (still editable for an active rental). — *sees:* Card absent on those tabs. — clear → clear — server no — **HOLDS**
- `G-595` Self-service return at the branch: return time is not offered (stored 23:59 / kept), so the customer cannot pick an invalid return time. — *sees:* Time picker absent (no explanation). — silent → silent — server unknown — **HOLDS**
- `G-596` Self-service branch: return "pickup from your address" is locked like the pickup side. — *sees:* Locked option with reason. — clear → clear — server unknown — **HOLDS**
- `G-597` Switching a side back to the branch removes the old address so it is not read as delivery later. — *sees:* Address row disappears. — silent → silent — server yes(trg_guard_booking_delivery (a) — **HOLDS**

**S-116**

- `G-598` Shorten tab always shows the storno conditions. — *sees:* Amber text box. — small → clear — server no — **HOLDS**
- `G-599` When days are removed, a coloured warning says how much will be refunded (100 / 50 / 0 %), computed from the NEW start like the server. — *sees:* Green / amber / red banner with icon and refund100/50/0 text. — clear → clear — server yes(tly: process-refund caps to the overpayment; storno % on the app's di…) — **HOLDS**

**S-116 / S-125 Edit confirmation page / Edit reservation**

- `G-600` A shortening or cheaper change was saved but the refund failed or was only partial; the page does not promise money back. — *sees:* Title 'Zkrácení potvrzeno' with text that staff will finish the refund; amber refund icon only when the refund really went through. — small → small — server yes(process-refund overpayment cap + trg_cap_refund_to_paid, SUPABASE_BAC…) — **HOLDS**

**S-117**

- `G-601` Price overview appears only when something changed and not on move/swap tabs. — *sees:* Price card. — clear → clear — server no — **HOLDS**
- `G-602` Result line: Doplatek (red, +) / Vrácení (green) / Rozdíl. — *sees:* Label and coloured amount. — clear → clear — server no — **HOLDS**
- `G-604` Storno percentage line under the result when days are removed (also at 0 Kč). — *sees:* Small grey line. — small → small — server no — **HOLDS**
- `G-605` Discount is re-computed on the new content (variant B) and shown as old → new. — *sees:* Row "discountLabel". — small → small — server unknown — **HOLDS**
- `G-606` Late-pickup (from 12:00) discount: moving the pickup time before 12:00 or below 2 days loses it; the price row shows the impact. — *sees:* Row "latePickupDiscountLabel" with +/−. — small → small — server yes(trg_validate_late_pickup_update, SUPABASE_BACKEND_STATE_4.md:117) — **HOLDS**

**S-117 / Edit reservation**

- `G-603` Card minimum: a surcharge of 1–15 Kč is charged as 15 Kč, up to 1 Kč is waived; explained before paying. — *sees:* Amber info note. — small → small — server yes(per comment Motogo-app-main/motogo-app-flutter/lib/features/reservati…) — **HOLDS**

**S-117 / S-122 Edit gear / extras section**

- `G-607` From loyalty rank loyaltyFreeGearLevel paid gear is free, but only on bookings made in the app; web bookings edited in the app still pay. — *sees:* Medal banner 'loyaltyGearBenefit' and 'ZDARMA' instead of prices. — clear → clear — server no — **HOLDS**

**S-118**

- `G-612` For an active rental the gear check is skipped (gear cannot be changed then), so extension is not blocked. — *sees:* Nothing. — silent → silent — server no — **HOLDS**
- `G-613` The missing-sizes banner is shown only on extend/shorten tabs. — *sees:* Banner. — clear → clear — server no — **HOLDS**

**S-118 / S-122 Edit gear / extras section**

- `G-609` Driver or passenger boots are ticked without a size (on delivery, or newly added/changed); saving is blocked. — *sees:* Card line 'Klikni pro výběr velikosti', amber missing-sizes banner, grey save button. — clear → clear — server unknown — **HOLDS**
- `G-610` Passenger gear is ticked but no passenger size is chosen; saving is blocked (at least one piece needed). — *sees:* Amber missing-sizes banner and grey save button. — clear → clear — server unknown — **HOLDS**
- `G-611` An older booking has a size outside the self-service range and the customer changes gear or moves to a self-service bike; saving is locked until a valid size is picked. — *sees:* Amber banner 'Doplň velikosti výbavy' listing the missing item; grey save button. — clear → clear — server unknown — **HOLDS**

**S-118 / S-122 Edit gear / extras section / Edit reservation**

- `G-608` Without own gear, a customer who changed the rider gear must keep at least one basic size (helmet, jacket, pants or gloves); otherwise saving is blocked. — *sees:* Amber hint under the pickers, amber banner above the save button, grey save button. — clear → clear — server unknown — **HOLDS**

**S-119**

- `G-615` While saving the button is disabled and shows a spinner (no double submit). — *sees:* Spinner. — clear → clear — server no — **HOLDS**
- `G-616` New end before new start is refused. — *sees:* Toast. — small → small — server unknown — **HOLDS**
- `G-617` Active rental: changing the start date is refused. — *sees:* Toast. — small → small — server unknown — **HOLDS**
- `G-619` The customer's own other overlapping booking or a branch closure on the new days is not checked in the app; the server refuses and the app shows a generic edit failure sheet. — *sees:* Error sheet psEditFailTitle / pdEditFail with retry. — small → small — server yes(trg_check_user_booking_overlap SUPABASE_BACKEND_STATE_4.md:189; trg_c…) — **HOLDS**
- `G-622` Difference up to 1 Kč is waived: the button says save for free instead of pay. — *sees:* Button text. — clear → clear — server yes(per comment server writes without payment) — **HOLDS**

**S-119 / Edit reservation**

- `G-621` Positive difference: nothing is written; the customer is redirected to the payment screen and the change is applied only after payment. — *sees:* Button "proceedToPayment (+X Kč)"; then payment screen. — clear → clear — server yes(process-payment stale_booking 409 / check_booking_delivery_change, SU…) — **HOLDS**
- `G-625` Trailer rules (trailer only with a bike from a staffed branch; trailer occupied on new dates) refused by DB trigger and translated. — *sees:* Error sheet fxTrailerStaffedOnly / swap.trailerOccupied. — small → small — server yes(trg_check_trailer_overlap, SUPABASE_BACKEND_STATE_4.md:87) — **HOLDS**

**S-119 / Reservation edit (save) / Edit reservation**

- `G-614` Save button disabled when nothing changed (no date/place/time/bike/gear/extras change and own-gear switch unchanged). — *sees:* Grey button, no explanation. — clear → clear — server no — **HOLDS**

**S-119 / S-120 Change bike section / Edit reservation**

- `G-618` The customer saves a bike change but meanwhile someone else booked that bike (or the availability check fails); the save is refused. — *sees:* Toast 'Obsazeno' / 'Motorka je v tomto termínu už rezervovaná...' or the connection message; nothing is saved. — small → small — server yes(trg_check_booking_overlap) — **HOLDS**

**S-119 / S-122 Edit gear / extras section**

- `G-624` Removing an extra failed on the server → told to the customer (staff will fix). — *sees:* Toast. — small → small — server no — **HOLDS**

**S-119 / S-122 Edit gear / extras section / Edit reservation**

- `G-620` Extras change refused when the original paid extras could not be loaded (prevents charging an extra twice). — *sees:* Toast. — small → small — server no — **HOLDS**

**S-119 / S-126 Edit failure / uncertain-result sheets / Edit reservation**

- `G-623` The answer to a save or move was lost and the app cannot verify whether it was stored; instead of 'nothing changed' or a blind retry the customer must reload the booking. — *sees:* Sheet 'Nevíme jistě...' with the only button 'Načíst znovu'. — clear → clear — server no — **HOLDS**

**S-120 Change bike section**

- `G-626` A customer whose booking is already picked up (active), or who is on the 'move' or 'swap' tab, tries to change the bike in the edit form; the 'Change bike' section is simply not shown, so the bike cannot be changed this way. — *sees:* No 'Change bike' card at all on an active booking or on the move/swap tabs. — silent → silent — server unknown — **HOLDS**
- `G-627` The customer tries to pick another bike that is already booked in the (possibly changed) rental dates; the bike is greyed out, marked 'Obsazeno' and cannot be tapped. — *sees:* Row at 45 % opacity with red 'Obsazeno' on the right; tapping does nothing. — clear → clear — server yes(trg_check_booking_overlap on bookings start_date/end_date/moto_id) — **HOLDS**
- `G-628` Availability is still being checked or the check failed (no connection); the bike cannot be picked until the check says it is free. — *sees:* Small spinner in the header and on each row while checking; after a failed check the bike shows 'Obsazeno'. — clear → clear — server no — **HOLDS**
- `G-629` The customer first picks a new bike and then changes the dates so that this bike is no longer free; the choice is silently cancelled. — *sees:* The before/after row and the 'Změna' badge disappear; the bike row shows 'Obsazeno'. No message explains why. — silent → silent — server yes(trg_check_booking_overlap) — **HOLDS**
- `G-631` The booking has a trailer and the customer tries to switch to a bike from a self-service branch; the bike is greyed out with 'Vozík jen na obslužné' and cannot be selected. — *sees:* Dimmed row with red 'Vozík jen na obslužné' text; tap does nothing. — clear → clear — server yes(trg_check_trailer_overlap 23514 'obslužné pobočky'; process-payment f…) — **HOLDS**
- `G-632` The customer's current bike is never offered as a 'new' bike. — *sees:* The current bike appears only in the 'Aktuální motorka' line, not in the list. — clear → clear — server no — **HOLDS**
- `G-633` The customer narrows the list by branch; a bike already chosen at a different branch is silently unselected. — *sees:* Dropdown changes; the chosen bike disappears from the list and the before/after row goes away. — silent → silent — server no — **HOLDS**
- `G-634` The customer switches to a bike standing at a self-service branch while delivery/collection to an address is selected and the feature flag self_service_delivery is off; delivery is switched back to the branch and the address option is locked. — *sees:* The address choice in pickup/return is shown folded with an explanation (drawn by AddressPickerWidget, deliveryBlocked) and the method jumps back to the branch. — small → small — server yes(trg on bookings via _delivery_guard_violation / check_booking_deliver…) — **HOLDS**
- `G-635` After picking a new bike and folding the card, the customer is reminded that a bike change is pending (before -> after) so it is not saved by accident. — *sees:* Green 'ZMĚNA' badge and a 'Aktuální motorka (crossed out) -> NOVÁ MOTORKA' box. — clear → clear — server no — **HOLDS**
- `G-636` The bike list cannot be loaded; the customer cannot choose any bike. — *sees:* Spinner, or a red error line instead of the list. — small → small — server no — **HOLDS**

**S-120 Change bike section / Reservation edit (bike list) / Edit reservation**

- `G-630` The customer's driving licence group does not cover a bike (e.g. A2 licence, A bike); that bike is not offered in the list at all. — *sees:* Bike is missing from the list; nothing says why. — silent → silent — server unknown — **HOLDS**

**S-121 Swap bike tab (Výměna)**

- `G-638` The customer changes the swap date after choosing a bike; the chosen bike and the price preview are cleared and availability is re-checked from the new date. — *sees:* The selected bike is unselected, price row disappears, spinner while re-checking. — silent → silent — server yes(split_booking_moto_swap: new_moto_unavailable) — **HOLDS**
- `G-639` Bikes the customer's licence does not allow, and the current bike, are left out of the swap list. — *sees:* Those bikes simply are not listed; if nothing remains: 'Žádná vhodná motorka k výměně.' — silent → silent — server yes(split_booking_moto_swap: license_insufficient) — **HOLDS**
- `G-641` A booking with a trailer tries to swap to a bike from a self-service branch; the bike is blocked with 'Vozík jen na obslužné'. — *sees:* Dimmed row with red 'Vozík jen na obslužné'. — clear → clear — server yes(split_booking_moto_swap: trailer_staffed_only already in dry-run; trg…) — **HOLDS**
- `G-642` The customer filters the swap list by branch; a chosen bike outside that branch is unselected and the price preview cleared. — *sees:* Chosen bike disappears from the list. — silent → silent — server no — **HOLDS**
- `G-643` No bike fits (licence, branch filter); the customer is told there is nothing to swap to. — *sees:* Grey line 'Žádná vhodná motorka k výměně.' — small → small — server no — **HOLDS**
- `G-645` Before confirming, the customer sees whether the swap costs extra, gives money back or costs the same (server dry-run), including the card minimum rule. — *sees:* Green box: 'Doplatek za výměnu +X Kč' with a card icon, 'Vrátíme vám −X Kč' with a piggy-bank icon, or 'beze změny' with a tick; note about the 15 Kč card minimum. — clear → small — server yes(split_booking_moto_swap p_dry_run) — **WEAKER (major)**
- `G-646` The server refuses the swap in the dry-run (not paid, wrong status, already split, bike unavailable, licence insufficient, date out of range, forbidden, trailer only at staffed branch, unknown); nothing is changed. — *sees:* Toast with an explanation ('Nic jsme nestrhli – ...'). — small → small — server yes(split_booking_moto_swap) — **HOLDS**
- `G-647` A previous surcharge for this booking is still being verified, or a paid change/swap is still being completed; a second payment or commit is blocked. — *sees:* Bottom sheet 'Platba se ověřuje' / 'Výměna se dokončuje' with button to open the reservation. — clear → clear — server yes(per code comment Motogo-app-main/motogo-app-flutter/lib/features/rese…) — **HOLDS**
- `G-648` The swap costs extra; instead of changing anything the customer is sent to the payment screen, and the swap is written only after a successful payment. — *sees:* Payment screen with 'Doplatek za výměnu' and the amount. — clear → clear — server yes(webhook / complete_extension commit _swap_commit after payment; split…) — **HOLDS**
- `G-649` The swap is free or gives money back; it is committed with server-side refund. If the answer is lost, the app checks with a dry-run before saying anything; if it still cannot tell, it warns instead of claiming success or failure. — *sees:* Confirmation page on success; '⏳ Nevíme jistě...' toast when uncertain. — small → small — server yes(split_booking_moto_swap p_settle_refund) — **HOLDS**
- `G-650` The commit fails because of a database rule (trailer only at staffed branch, trailer already taken) or the network; the customer gets a translated reason instead of a raw error. — *sees:* Toast with the reason. — small → small — server yes(trg_check_trailer_overlap) — **HOLDS**
- `G-651` The customer is told up front that a swap creates a follow-up booking that must be paid, unused days are refunded, and the swap happens only after signing the handover protocol at the branch. — *sees:* Green info box with the explanation (body text). — small → small — server no — **HOLDS**

**S-121 Swap bike tab (Výměna) / Edit reservation – bike swap**

- `G-637` The customer tries to choose a swap date in the past or after the end of the rental; those days cannot be picked. — *sees:* Material date dialog with only the allowed days enabled. — clear → clear — server yes(split_booking_moto_swap: swap_date_out_of_range) — **HOLDS**
- `G-640` The customer tries to pick a bike that is not free from the swap date to the end of the rental; it is greyed out with 'Obsazeno'. — *sees:* Dimmed row with red 'Obsazeno'; tap does nothing; spinner while checking. — clear → clear — server yes(split_booking_moto_swap: new_moto_unavailable; trg_check_booking_over…) — **HOLDS**
- `G-644` The customer presses 'Potvrdit výměnu' before choosing a date and a bike, or while a save is running; the button does nothing. — *sees:* Grey disabled button; spinner while saving. — clear → clear — server no — **HOLDS**

**S-122 Edit gear / extras section**

- `G-652` A customer with a picked-up (active) booking, or on the move/swap tab, wants to change gear or paid add-ons; the gear section is not shown. — *sees:* No 'Doplňky' card. — silent → silent — server unknown — **HOLDS**
- `G-653` A children's bike (licence 'N') booking tries to add passenger gear or passenger boots; these options are not offered. — *sees:* Only driver boots are listed. — silent → silent — server unknown — **HOLDS**
- `G-654` The bike (also after a bike change) stands at a self-service branch; only the narrower size ranges are offered (helmet S–3XL, jacket/pants/gloves max 4XL). — *sees:* Size chips simply do not include XS/5XL/6XL. — silent → silent — server unknown — **HOLDS**
- `G-655` Delivery or collection to an address is selected; the customer is warned that sizes are needed for delivery. — *sees:* Amber info banner at the top of the add-ons. — clear → clear — server no — **HOLDS**
- `G-656` The customer taps the ticked passenger gear card; the add-on and all passenger sizes (including gloves) are removed at once, without a confirmation. — *sees:* Card becomes unticked and the inline passenger sizes disappear. — clear → clear — server no — **HOLDS**
- `G-657` The customer ticks 'Mám vlastní výbavu' (own gear); the rider's free size pickers are hidden and no rider sizes are saved. — *sees:* Checkbox ticked/empty next to 'Mám vlastní výbavu'; the four rider pickers vanish when ticked. — clear → small — server yes(trg_bookings_own_gear_normalize on INSERT; trg_sync_locker_code on ow…) — **WEAKER (major)**

**S-123 Boot size sheet (edit)**

- `G-658` The customer taps driver or passenger boots; a size sheet opens with only the allowed sizes (children / self-service ranges); picking a size adds the boots, closing without a pick adds nothing; 'Odebrat doplněk' appears only when the boots are already ticked. — *sees:* White sheet 'Vyber velikost – Boty řidiče' with size chips and, if ticked, a red 'Odebrat doplněk'. — clear → clear — server no — **HOLDS**

**S-124 Passenger gear sheet (edit)**

- `G-659` The customer ticks passenger gear; a sheet asks for passenger helmet/jacket/pants sizes (allowed ranges only); each tap is saved at once; 'Odebrat doplněk' removes the add-on and clears all passenger sizes including gloves. — *sees:* Sheet with three size pickers, green 'Hotovo' and red 'Odebrat doplněk'. — clear → clear — server no — **HOLDS**
- `G-660` The customer closes the passenger sheet (Hotovo, swipe or back) without choosing any size; the add-on stays ticked and saving is blocked until a size is chosen inline. — *sees:* Inline 'VÝBAVA SPOLUJEZDCE' pickers, amber missing-sizes banner, grey save button. — clear → clear — server no — **HOLDS**

**S-125 Edit confirmation page**

- `G-661` The confirmation shows where to pick up the bike (branch of the new bike after a change) and, where the branch has a gate, the gate notice. — *sees:* 'K vyzvednutí' link with branch and address, and the gate notice box when relevant. — clear → clear — server yes(branch_has_gate RPC) — **HOLDS**

**S-126 Edit failure / uncertain-result sheets**

- `G-662` Saving an edit or a date move fails (DB rule: trailer only at staffed branch, trailer taken, overlapping booking; network; other); the customer gets a sheet with a translated reason and 'Zkusit znovu' that reruns the same save. — *sees:* Bottom sheet 'Úpravu se nepodařilo uložit' with the reason and 'Zkusit znovu'. (At 70a94933 this was a toast with the raw error, old reservation_edit_screen.dart:611, :1049.) — clear → clear — server yes(trg_check_booking_overlap, trg_check_trailer_overlap) — **HOLDS**

### After the ride (routes, navigation, places, reviews, loyalty, branches, messages, AI) — 220 safeguards, 1 weaker

**S-159 Branches list**

- `G-761` The customer taps the booking button in the green CTA box on the branches list; it only opens the bike catalogue (no branch filter, no shortcut past any booking check). — *sees:* Green box with the CMS title/text and a dark button; tapping it lands on the catalogue tab where all availability/licence checks of the catalogue apply. — clear → clear — server no — **HOLDS**
- `G-762` The customer opens a branch from the list (tile tap or 'Detail' button); the route index is clamped so a wrong index can never open a non-existing branch. — *sees:* Branch tile with badge, address, hours and a green detail button. — clear → clear — server no — **HOLDS**
- `G-763` Pull-to-refresh and back navigation on the list: refresh re-reads the CMS texts, back pops or falls back to Profile (no dead end). — *sees:* Back arrow in a dark app bar; pull down refreshes. — clear → clear — server no — **HOLDS**
- `G-764` The 'Motorky na pobočkách' button opens the bikes sheet; the sheet itself loads data and applies its filters (see S-161). — *sees:* Outlined button with a motorbike emoji. — clear → clear — server unknown — **HOLDS**

**S-160 Branch detail**

- `G-765` 'Rezervovat' on a branch: the branch is pre-selected in the catalogue filter only if the catalogue actually offers that branch (a permanently closed branch is not pre-selected, which would give an empty list) or while bikes are still loading; the chosen dates… — *sees:* Green CTA box at the bottom of the branch detail; tapping opens the catalogue filtered to the branch, or unfiltered if the branch is closed. — silent → silent — server yes(branch_is_closed / moto_branch_closed in SUPABASE_BACKEND_STATE_3.md:…) — **HOLDS**
- `G-766` The 'Motorky na pobočce' section is hidden when the branch has no id, when the catalogue failed to load, or when the branch has no bikes; while loading it shows a spinner; the title carries the bike count. — *sees:* Collapsed card '🏍️ Motorky na pobočce (n)' or nothing. — silent → silent — server no — **HOLDS**
- `G-767` Tapping a bike in the branch section limits the bike detail's swipe/next list to this branch's bikes before opening the detail (the detail and booking from there keep their own checks). — *sees:* Bike row with photo, model and specs; tap opens the bike detail. — clear → clear — server no — **HOLDS**
- `G-768` Each bike row shows the required licence groups (ŘP A2 / A …, 'N' excluded), so the customer sees before opening that a bike needs a licence they may not have. — *sees:* Grey spec line 'cc · kW · ŘP A2'. — small → small — server yes(licence is checked again at booking; not part of this screen) — **HOLDS**
- `G-769` The pickup procedure ('Jak to probíhá') tells self-service customers that without verified documents they get no access codes and cannot enter the branch, and the order of codes (box, wardrobe, bike); it is collapsed by default. — *sees:* Collapsed '🧭 Jak to probíhá' card; the document rule is inside the body text. — small → small — server yes(door codes are only issued after document verification; enforced in b…) — **HOLDS**
- `G-770` Opening hours / rules line: self-service is nonstop by code, with the 12:00 release rule for the half-price first day and 'return any time on the last day until 24:00'; gear line lists what the self-service branch does not lend (no rain gear, sizes up to 4XL). — *sees:* Clock and jacket lines with CMS text. — small → small — server yes(12:00 release enforced by kiosk_resolve_code / _kiosk_release_at per…) — **HOLDS**
- `G-771` Branch video is shown only for an https URL; YouTube links or a failed player open externally. — *sees:* Video block or nothing. — silent → silent — server no — **HOLDS**
- `G-772` Photos section only when the branch has photos. — *sees:* Collapsed photo card or nothing. — silent → silent — server no — **HOLDS**
- `G-773` Navigate button opens Google Maps for the branch; back pops or goes to Profile. — *sees:* Outlined 'Navigovat' button. — clear → clear — server no — **HOLDS**

**S-161 Branches / bikes sheet**

- `G-774` Permanently closed branches (is_open = false) and inactive branches are never listed in the bikes sheet; seasonal closures still show (only calendar days are blocked). — *sees:* Closed branches simply do not appear. — silent → silent — server yes(branch_is_closed, SUPABASE_BACKEND_STATE_3.md:298) — **HOLDS**
- `G-775` Only bikes with status 'active' are listed under each branch. — *sees:* Out-of-service bikes do not appear. — silent → silent — server yes(booking RPCs reject non-active bikes; not on this sheet) — **HOLDS**
- `G-776` If loading branches or bikes fails, nothing opens and an error toast explains it. — *sees:* Toast '✗ Chyba – pobočky se nepodařilo načíst'. — clear → clear — server no — **HOLDS**
- `G-777` Open / closed chip on each branch card (green 'Nonstop' or red 'Zavřeno'). — *sees:* Coloured chip in the card header. — clear → clear — server no — **HOLDS**
- `G-778` The 'Otevřít v mapě' button is hidden when the branch has neither GPS nor an address; 'Navigovat na pobočku' only with GPS; 'Zavolat' only with a phone number. — *sees:* Buttons present or absent. — silent → silent — server no — **HOLDS**
- `G-779` Self-service branches state their capacity (max 8 bikes); the old look shows it twice (detail row and an amber badge next to the bike list title). — *sees:* Row 'Kapacita: max 8 motorek' plus amber badge. — small → small — server no — **HOLDS**
- `G-780` Tapping a bike in the sheet closes the sheet and opens the bike detail; a bike without an id is not tappable. — *sees:* Bike row; tap opens detail. — clear → clear — server no — **HOLDS**

**S-162 Loyalty ranks**

- `G-781` A logged-out customer (or one for whom get_loyalty_status returns nothing) sees the welcome variant: first rank, 0 %, and the line 'Platí jen pro rezervace vytvořené v aplikaci' instead of a progress line. — *sees:* Hero with Startér, 0 % and the app-only sentence. — small → small — server yes(get_loyalty_status uses auth.uid() — **HOLDS**
- `G-782` Rank ladder: ranks above the customer's level are locked (dimmed + lock icon), the current rank is highlighted with a 'TY' chip, lower ranks are unlocked. — *sees:* Glowing current tile, dimmed locked tiles with a lock. — clear → clear — server yes(rank computed server-side in get_loyalty_status) — **HOLDS**
- `G-783` Point threshold shown per rank ('od X bodů'). — *sees:* Small grey line under each rank name. — small → small — server yes(get_loyalty_status: level = ceil((points+1) — **WEAKER (minor)**
- `G-784` From rank 3 the rank tiles state 'Výbava spolujezdce i veškerá obuv zdarma' (dimmed while locked). — *sees:* Green line with 🎒 under ranks 3–20. — small → small — server yes(free gear from rank 3 gated server-side with booking_source='app', SU…) — **HOLDS**
- `G-785` Rules card lists the six program rules, including 'discount applies ONLY to bookings made in the app' and how it combines with promo codes and vouchers. — *sees:* Card '🏅 Jak věrnost funguje' with six lines. — small → small — server yes(validate_app_loyalty_discount BEFORE INSERT trigger on bookings) — **HOLDS**
- `G-786` Next-rank / max-rank line: shows how many points to the next rank and its %, or 'max rank' at the top. — *sees:* White line under the progress bar plus 'level x/20 · n bodů'. — small → small — server yes(bookings_to_next from get_loyalty_status) — **HOLDS**
- `G-787` Levels still loading or failed: the screen keeps a back arrow and shows a spinner, or an error explaining the reason with 'Zkusit znovu'. — *sees:* Spinner or error card with retry; back arrow always present. — clear → clear — server no — **HOLDS**
- `G-788` Monthly leaderboard is hidden unless the Velín feature flag loyalty_leaderboard is on, and hidden when the RPC returns nothing. — *sees:* No leaderboard section at all (default). — silent → silent — server yes(get_loyalty_leaderboard returns {error:'unauthenticated'} without log…) — **HOLDS**
- `G-789` Leaderboard opt-in switch is shown only to a customer with a loaded status; switching off warns that they no longer compete for the monthly prize; without a nickname a hint explains how they appear. — *sees:* Switch with grey/amber explanation and nickname hint. — small → small — server yes(set_loyalty_leaderboard_optin uses auth.uid() — **HOLDS**
- `G-790` Rank status is cached per user and kept on network failure (so a short outage never drops the rank/free gear), never leaks between accounts, and is not refreshed while the payment screen is open. — *sees:* Nothing visible; prices stay stable. — silent → silent — server yes(validate_app_loyalty_discount re-checks on insert) — **HOLDS**
- `G-791` Back from the ranks page pops, or goes Home if there is nothing to pop. — *sees:* White back arrow. — clear → clear — server no — **HOLDS**

**S-163 Messages**

- `G-792` Push / deep link with ?n=<id> opens the notification expanded and marks it read. — *sees:* The tapped notification is open and no longer bold. — clear → clear — server no — **HOLDS**
- `G-793` Unread notifications are marked (green left bar + red dot, bolder title); tapping toggles the full text and marks it read; collapsed text is limited to 3 lines. — *sees:* Pale-green card with red dot; expand arrow. — clear → clear — server no — **HOLDS**
- `G-794` 'Mark all read' is offered only on the Notifications tab and only while something is unread. — *sees:* Double-tick icon in the app bar. — clear → clear — server no — **HOLDS**
- `G-795` Notifications tab carries a red unread badge (9+ cap). — *sees:* Red count pill on the tab. — clear → clear — server no — **HOLDS**
- `G-796` Conversations tab: unread team replies mark the thread (green bar + count); SOS threads ('SOS:' subject) carry the ambulance icon. — *sees:* Thread card with count bubble and 🚑 for SOS. — clear → clear — server no — **HOLDS**
- `G-797` Loading and load errors: loading view with retry; error explains what failed with 'Zkusit znovu'; empty lists show an empty state; realtime drop does not kill the list. — *sees:* Spinner, error card or empty illustration. — clear → clear — server no — **HOLDS**
- `G-798` Switching between tabs; v2 adds a horizontal swipe as a twin of the tab tap. — *sees:* Two tab buttons. — clear → clear — server no — **HOLDS**

**S-164 New conversation sheet**

- `G-799` Starting a new conversation with an empty subject is refused (button and keyboard Enter); a toast asks for a subject and the sheet stays open. — *sees:* Toast '⚠️ Nová konverzace – zadejte předmět'. — clear → clear — server unknown — **HOLDS**
- `G-800` Creating the thread fails (offline, not logged in, server error): the sheet is already closed, an error snackbar explains why and offers retry with the same subject. — *sees:* Error snackbar 'Konverzaci se nepodařilo založit' + retry. — clear → clear — server yes(RLS message_threads customer INSERT customer_id = uid, STATE_5:49) — **HOLDS**
- `G-801` The sheet can always be closed with a visible close control. — *sees:* Title row with ✕. — clear → clear — server no — **HOLDS**

**S-165 Conversation thread**

- `G-802` While the thread is loading, failed to load, or does not exist / belongs to someone else, the chat and the input bar are replaced by a state view (spinner, error with retry, or 'conversation no longer exists' with back to Messages) — nothing can be typed or s… — *sees:* Loading / error / gone card with back. — clear → clear — server yes(RLS: customer SELECT own thread only -> foreign id returns null) — **HOLDS**
- `G-804` Sending an empty reply, or sending again while a send is running, is ignored. — *sees:* Nothing happens; button shows ⏳ while sending. — silent → clear — server no — **HOLDS**
- `G-805` A failed send puts the text back into the field and explains why (message kept). — *sees:* Toast 'Zprávu se nepodařilo odeslat … text zůstal'. — clear → clear — server no — **HOLDS**
- `G-806` Opening or refreshing the thread marks the team's replies as read; an auth error in the realtime stream triggers the shared auth handling (re-login). — *sees:* Unread counts disappear. — silent → silent — server no — **HOLDS**

**S-165 Conversation thread / Thread detail**

- `G-803` A closed conversation cannot be replied to: the reply bar is hidden. — *sees:* No input bar; only a small 'Uzavřeno' under the title. — small → clear — server no — **HOLDS**

**S-166 AI assistant chat**

- `G-807` The assistant is tied to the customer's current paid booking (active preferred over reserved); unpaid or other customers' bookings are never used as context. — *sees:* Nothing visible. — silent → silent — server yes(ai-moto-agent loads the booking with .eq('user_id', user.id) — **HOLDS**
- `G-808` Sending is refused when there is neither text nor a photo, or while a reply is still pending; a photo-only message gets a default text. — *sees:* Nothing happens; 'Přemýšlím…' line while waiting. — silent → silent — server yes(backend requires a non-empty message) — **HOLDS**
- `G-809` The red 'Nahlásit SOS' card is offered only when the agent suggests SOS AND the customer has a rental where SOS is allowed; tapping opens the SOS screen. — *sees:* Red SOS card under the reply. — clear → clear — server yes(ai-moto-agent sets suggest_sos=false for gear-only context; SOS scree…) — **HOLDS**
- `G-810` A failed request shows a reason bubble (offline / too large / rate limit / login / service down), offers 'Zkusit znovu' on the failed message (disabled while sending) and, with an active rental, the SOS card. — *sees:* Red ❌ bubble, retry link, SOS card. — clear → clear — server no — **HOLDS**
- `G-811` Slow reply: after 20 s the typing line changes to 'Ještě přemýšlím…' so the customer does not resend. — *sees:* Grey typing line. — small → small — server no — **HOLDS**
- `G-812` At most 3 photos can be attached; the 4th attempt shows a toast and no picker opens. — *sees:* Toast '📷 Maximálně 3 fotky'. — clear → clear — server yes(ai-moto-agent uses images.slice(0, 3) — **HOLDS**
- `G-813` Attached photos are previewed and removable before sending; the camera icon turns green while photos are pending. — *sees:* Thumbnails with ✕; green camera icon. — clear → clear — server no — **HOLDS**
- `G-814` Back leaves the assistant to the previous screen or Home. — *sees:* Back arrow. — clear → clear — server no — **HOLDS**

**S-167 AI chat photo source sheet**

- `G-815` Choosing the photo source: dismissing the sheet does nothing; camera/gallery return the same ImageSource; images are compressed (max 1280 px, quality 75) so 3 photos fit the request limit. — *sees:* Sheet with 'Vyfotit' / 'Vybrat z galerie'. — clear → clear — server yes(request size limit on the edge function; eoAiTooLarge handled at :176) — **HOLDS**
- `G-816` Camera or gallery permission denied / picker error: a snackbar says why and offers the permission settings. — *sees:* Error snackbar with permission hint. — clear → clear — server no — **HOLDS**

**S-020 Discard confirmation / S-198 Submit a place**

- `G-918` Leaving the form with unsent data asks for confirmation (added on this branch in both looks; 4.1.3 had none). — *sees:* Dialog 'discard?' with Discard / Stay. — clear → clear — server no — **HOLDS**

**S-190 Places tab (Místa)**

- `G-862` While the place catalogue and community places are still loading, the customer cannot see or pick any place; the list waits until both sources are in. — *sees:* A green spinner instead of the list. — clear → clear — server no — **HOLDS**
- `G-863` If the place catalogue or community places fail to load (for example offline), the customer gets no places. — *sees:* Only the generic empty text 'poiEmpty' with a map emoji; nothing says loading failed. — silent → clear — server no — **HOLDS**
- `G-864` Community places that are not yet approved (the customer's own pending suggestions or anyone else's) are not offered in the Places list or map. — *sees:* The place simply does not appear in the list. — silent → silent — server yes(get_user_pois returns only user_pois.status='approved'; RLS user_pois…) — **HOLDS**
- `G-865` The list only offers places that pass the current filter (search text, categories, countries, minimum rating, chosen route, 'nearby' radius) and is sorted by the chosen order. — *sees:* A shorter list; active filters are highlighted on the 'Filters' chip with a count badge. — clear → clear — server no — **HOLDS**
- `G-866` With no location permission the customer cannot sort places 'from me'; the screen asks to enable location. — *sees:* A green banner 'poiLocationPrompt' with an 'Enable' action. — clear → clear — server no — **HOLDS**
- `G-867` On opening the Places tab the app asks for location quietly; it never sends the customer to the system settings by itself, and in pick mode it does not ask at all. — *sees:* At most the system permission dialog. — small → small — server no — **HOLDS**
- `G-868` The 'Continue' (build a ride) bar appears only after at least one place is selected; with an empty or unresolvable selection the action does nothing. — *sees:* No bottom bar until something is selected; then 'n selected ✕' plus a green 'Continue' button. — clear → clear — server no — **HOLDS**
- `G-869` After building a ride from Places the shared selection is cleared, so it does not come back on another screen; in pick mode the selection is local and never leaks into the shared selection. — *sees:* Nothing visible; the list starts empty next time. — silent → silent — server no — **HOLDS**
- `G-870` The filter row is not shown at all when there is nothing to filter (fewer than two routes with places, no places and no selection). — *sees:* No filter row. — silent → silent — server no — **HOLDS**
- `G-871` Switching on 'Nearby' needs an anchor: if the customer has no location and nothing selected, the app first asks for location and does not switch the filter on if it is refused. — *sees:* Location request; if refused the chip stays off (4.1.3 gave no explanation). — small → small — server no — **HOLDS**
- `G-872` Radius options (5/10/25/50 km) are only offered while 'Nearby' is on. — *sees:* Extra km chips appear after 'Nearby' is switched on. — clear → clear — server no — **HOLDS**
- `G-873` Category chips are only offered for categories that actually have places under the current filter (or are already selected), so a chip never leads to an empty list. — *sees:* Only non-empty categories with their counts. — clear → clear — server no — **HOLDS**
- `G-874` 'Clear filters' is offered only when at least one filter is active. — *sees:* A red 'Clear filters' chip next to the filter chip. — clear → clear — server no — **HOLDS**
- `G-875` When the search text also matches routes, the customer is offered a jump to the route list; otherwise no banner. — *sees:* Green banner 'searchAlsoRoutes · n'. — clear → clear — server no — **HOLDS**
- `G-876` When no place matches, the list is replaced by an empty message. — *sees:* Map emoji + 'poiEmpty' heading. — clear → clear — server no — **HOLDS**
- `G-877` Selecting a place (for the custom ride) happens only by the + disc, by long-press on the card, or by tapping the place on the map preview; a normal tap opens the detail instead. — *sees:* Card border turns green and the disc shows a tick. — clear → clear — server no — **HOLDS**
- `G-878` The map preview inside the list cannot be dragged (so the list scrolls); tap opens the full map, tap on a place toggles it, long-press on a place opens its detail, long-press on empty map opens 'Add place' at that point. — *sees:* Small map with hint text 'placesMapOpenHint'. — small → small — server no — **HOLDS**
- `G-879` The map preview and the location prompt are shown only on the tab root, never in the route-editor pick mode or on /pois. — *sees:* No map preview in pick mode. — silent → silent — server no — **HOLDS**
- `G-881` In v2 the Places tab header has a '+' button that opens the community add menu (old Places tab had no such button; the menu was reached from the Trasy FAB). — *sees:* Old: '+' FAB on the Trasy list. — clear → small — server yes(RLS routes_user_submit / user_pois_user_insert) — **HOLDS**

**S-191 POI picker for route builder**

- `G-882` In pick mode the customer can return places to the route editor only after selecting at least one; nothing selected = no 'Add to route' button. — *sees:* No bottom bar until a place is selected; then 'Add to route'. — clear → clear — server no — **HOLDS**
- `G-883` In pick mode the filter and selection are local, so filters or selections set in the Places tab do not leak into the route editor and vice versa; the shared search text is ignored. — *sees:* Nothing visible. — silent → silent — server no — **HOLDS**
- `G-884` Pick mode hides the quick links / segments, the map preview, the add '+' and the map button, so the customer stays on choosing places; back closes the picker without changes. — *sees:* Plain header with back arrow. — clear → clear — server no — **HOLDS**
- `G-885` /pois opened with preselected places (edit this route) uses the same local selection and only offers 'Continue' once something is selected. — *sees:* Preselected places shown ticked; Continue bar. — clear → clear — server no — **HOLDS**

**S-192 POI detail sheet**

- `G-886` The 'Add to my ride / Remove from ride' button in the place detail exists only when the sheet was opened from the Places list or Places map; from a route detail or navigation there is no such button. — *sees:* Big green button at the bottom; turns white with a tick when selected. — clear → clear — server no — **HOLDS**
- `G-887` Swiping to the next/previous place only works when the sheet was opened with more than one place, and stops at the first/last; the list of neighbours is limited to a window of 150 on each side. — *sees:* 'n / m' counter; swipe does nothing at the end. — small → small — server no — **HOLDS**
- `G-888` A stop number is shown only for places that belong to a route (route detail), never for catalogue places, so the customer is not given a fake order like '4238'. — *sees:* Green circle with the number next to the name, only on routes. — clear → clear — server no — **HOLDS**
- `G-889` For catalogue and route places loaded in light form, the full description, surroundings and gallery are loaded on opening; inactive or missing catalogue places return nothing and the light data stays. — *sees:* Small spinner under the heading while loading. — small → small — server yes(get_poi_detail returns null for inactive id; get_route_poi_detail) — **HOLDS**
- `G-890` The sheet can be closed by dragging down; current code adds a visible close button in both looks. — *sees:* Drag handle only. — small → clear — server no — **HOLDS**

**S-193 POI image viewer + photo credit sheet**

- `G-891` The photo viewer opens only when the place has photos; the strip of thumbnails is shown only for more than one photo. — *sees:* Big photo with a zoom icon; no photo area otherwise. — clear → clear — server no — **HOLDS**
- `G-892` The photo credit sheet offers 'Open source' only for Wikimedia Commons photos; for other photos only the licence sentence is shown. — *sees:* Credit text; 'Open source' link only for Commons photos. — small → small — server no — **HOLDS**

**S-194 POI tools sheet (sort/filter)**

- `G-893` 'Sort near me' needs location: without it the app asks for location and does not switch sorting if refused. — *sees:* Location request; chip stays unselected if refused. — small → small — server no — **HOLDS**
- `G-894` 'Sort near chosen route' is disabled until a route has been opened or chosen (no route anchor). — *sees:* Greyed chip that does nothing. — small → small — server no — **HOLDS**
- `G-895` The country section appears only when the data has countries; less common countries are hidden behind 'More countries (n)'. — *sees:* Country chips; expandable 'More countries'. — clear → clear — server no — **HOLDS**
- `G-896` Minimum rating options are hidden by default (shown only when a minimum is already set or the customer expands them). — *sees:* '▼ Minimum rating' toggle. — clear → clear — server no — **HOLDS**
- `G-897` Changes in the sheet are not applied until 'Apply (n)' is pressed; the button shows how many places will remain; closing the sheet any other way discards the draft. — *sees:* Green 'Apply (n)' button with the live count. — clear → clear — server no — **HOLDS**
- `G-898` 'Clear filters' in the sheet resets every filter including search and closes the sheet. — *sees:* Text button 'Clear filters' at the top. — clear → clear — server no — **HOLDS**

**S-195 Route picker sheet**

- `G-899` Only routes that have at least one place are offered in the route filter. — *sees:* List of routes with place counts. — silent → silent — server no — **HOLDS**
- `G-900` Searching routes narrows the list; picking a route or 'All routes' applies immediately and closes the sheet. — *sees:* Filtered list; tick on the active route. — clear → clear — server no — **HOLDS**

**S-196 Places map**

- `G-901` The map shows only places that pass the same filter as the list (shared filter), without catalogue route lines. — *sees:* Subtitle 'Places · n · active filters'. — small → small — server no — **HOLDS**
- `G-902` A road route through the selected places is computed only from two selected places; while computing or if routing fails the subtitle says so; with one place selected it says to pick another. — *sees:* Subtitle text: computing / route failed / select one more. — small → small — server no — **HOLDS**
- `G-903` The 'Continue' bar to build a ride appears only when something is selected; empty or unresolvable selection does nothing; after building, the selection is cleared. — *sees:* 'n selected ✕' + 'Continue'. — clear → clear — server no — **HOLDS**
- `G-904` 'My location' needs location: without it the app asks and does not centre if refused. — *sees:* Location request. — small → small — server no — **HOLDS**
- `G-905` 'Add place here' button needs the customer's location; without it the customer is told to long-press the map instead. — *sees:* Snackbar 'placesMapAddHint'. — small → small — server no — **HOLDS**
- `G-906` Long-press on an empty spot opens 'Add place' at that point without a login check up front (login is checked only when sending). — *sees:* The submit form opens. — silent → silent — server yes(RLS user_pois_user_insert requires auth) — **HOLDS**
- `G-907` 'Clear filter' on the map is offered only when a filter is active. — *sees:* Filter-off icon in the header. — clear → clear — server no — **HOLDS**
- `G-908` On opening, 4.1.3 actively asked for location (ensureLocation, could lead to settings); current code in BOTH looks only asks quietly and never opens settings. — *sees:* 4.1.3: system permission/settings prompt on open. — small → small — server no — **HOLDS**

**S-197 Community add menu / S-202 Recommended routes list**

- `G-909` The '+' action menu: proposing a route or adding a place requires login; a logged-out customer is stopped with a message instead of opening the form. — *sees:* Menu closes and a snackbar says to log in. — small → small — server yes(RLS routes_user_submit: created_by=auth.uid() — **HOLDS**

**S-197 Community add menu / S-202 Recommended routes list / S-212 My experiences / S-190 Places tab (Místa)**

- `G-880` Places tab in v2 has a record-ride dock; old Places tab had no recording control there (recording was in the Trasy '+' menu). Starting a manual ride is not offered while any recording (including the automatic rental recording) is running; stop is offered only… — *sees:* Old: in the '+' menu a 'Start recording' row only when no automatic recording is running. — clear → clear — server unknown — **HOLDS**

**S-197 Community add menu / S-202 Recommended routes list / S-213 Recording controls card / Ride recording**

- `G-910` Stopping a manual ride from the list: the old '+' menu stopped immediately; rides under 1 km are discarded and an offline stop is retried, with a message. — *sees:* Snackbar: saved / too short / will retry. — small → clear — server unknown — **HOLDS**

**S-198 Submit a place**

- `G-911` Sending a place requires login; without it the form refuses. — *sees:* Snackbar 'poiRateLogin'. — small → small — server yes(RLS user_pois_user_insert; storage media_user_poi_upload) — **HOLDS**
- `G-912` The place name is required. — *sees:* Snackbar 'poiSubmitNameReq'. — small → small — server unknown — **HOLDS**
- `G-913` While sending, the button is disabled and shows 'Uploading photos' / 'Sending', so the place cannot be sent twice. — *sees:* Spinner with phase text in the button. — clear → clear — server no — **HOLDS**
- `G-914` Only one photo can be attached to a place; the 'Add photo' tile disappears once one is chosen. — *sees:* One thumbnail, no add tile. — clear → clear — server yes(storage policy media_user_poi_upload only under user-pois/) — **HOLDS**
- `G-915` If GPS is unavailable, the point stays where it is and the customer must place it on the map (4.1.3 silently did nothing; current code explains in both looks). — *sees:* 4.1.3: nothing. — silent → small — server no — **HOLDS**
- `G-916` A suggestion goes to moderation (pending) and is not visible to others until approved; the screen says so. — *sees:* Info banner at the top about moderation. — small → small — server yes(RLS user_pois_user_insert forces status='pending'; get_user_pois retu…) — **HOLDS**
- `G-917` If sending fails, the form keeps the data and shows an error (current code adds 'why' and 'Try again'); photos that failed to upload are reported. — *sees:* Snackbar 'poiSubmitErr'. — small → small — server no — **HOLDS**

**S-199 Submit a route**

- `G-919` Sending a route requires login. — *sees:* Snackbar 'poiRateLogin'. — small → small — server yes(RLS routes_user_submit) — **HOLDS**
- `G-920` The route name is required. — *sees:* Snackbar 'poiSubmitNameReq'. — small → small — server unknown — **HOLDS**
- `G-921` A route needs at least two points. — *sees:* Snackbar 'routeSubmitNeedPoints'. — small → small — server no — **HOLDS**
- `G-922` Loading points from a link does nothing when the link field is empty, is disabled while loading, and shows an error line if the link cannot be decoded. — *sees:* Button 'Loading…'; red error text 'routeSubmitDecodeErr'; green 'n points loaded'. — small → small — server no — **HOLDS**
- `G-923` Up to six photos; extra picks are cut to six and the add tile disappears at six. — *sees:* Counter 'n/6'. — clear → clear — server yes(storage policy media_user_poi_upload) — **HOLDS**
- `G-924` While sending the button is disabled with progress text. — *sees:* Spinner + 'Uploading'/'Sending'. — clear → clear — server no — **HOLDS**
- `G-925` Leaving with unsent data (including points) asks for confirmation (added on this branch in both looks). — *sees:* Discard dialog. — clear → clear — server no — **HOLDS**
- `G-926` Route suggestions go to moderation (pending, inactive). — *sees:* Moderation info banner. — small → small — server yes(RLS routes_user_submit forces status pending, is_active false) — **HOLDS**

**S-200 Submission success sheet**

- `G-927` After a successful send the confirmation must be closed before the form closes; the customer is told the suggestion waits for approval. — *sees:* Sheet with big tick, 'submitSuccessTitle', moderation text, OK button. — clear → clear — server no — **HOLDS**

**S-201 POI reviews editor**

- `G-928` Writing or editing a review requires login. — *sees:* Snackbar 'routeReviewLogin'. — small → small — server yes(submit_poi_review raises 'auth required') — **HOLDS**
- `G-929` A review needs at least one star. — *sees:* Snackbar 'routeReviewRatingReq'. — small → small — server yes(submit_poi_review raises 'rating must be 1..5') — **HOLDS**
- `G-930` Only one review per customer per place: an existing review is opened for editing (button says 'Edit review'). — *sees:* 'Edit review' instead of 'Write review'; editor prefilled. — clear → clear — server yes(submit_poi_review upsert ON CONFLICT per user+target) — **HOLDS**
- `G-931` While sending, the send button is disabled. — *sees:* Button shows '…'. — clear → clear — server no — **HOLDS**
- `G-932` 'Delete review' is offered only when the customer has a review; it deletes without confirmation and a failure is silent (logged only). — *sees:* Red text 'Delete review'. — clear → clear — server yes(delete_poi_review requires auth and deletes only own row) — **HOLDS**
- `G-933` Only approved reviews (plus the customer's own) are listed. — *sees:* List or 'routeReviewsNone'. — silent → silent — server yes(get_poi_reviews visible only status='approved' or own or admin) — **HOLDS**
- `G-934` Star rating on the place requires login; taps are ignored while saving; a failed save reverts the stars and says so. — *sees:* Snackbar 'poiRateLogin' / 'poiRateSaved' / 'poiRateErr'; spinner next to stars. — small → small — server yes(rate_poi requires auth.uid() — **HOLDS**

**S-020 Discard confirmation / S-208 Route builder**

- `G-986` Leaving the builder with unsaved stop changes (back arrow, Android back, iOS swipe) is blocked and asks for confirmation to discard. — *sees:* Dialog 'Discard route changes?' with confirm/cancel. — clear → clear — server no — **HOLDS**

**S-202 Recommended routes list**

- `G-935` The customer opens the list and the app only offers routes that the office has published and approved; unapproved customer suggestions and switched-off routes never appear. — *sees:* Only published routes in the list; nothing explains why other routes are missing (none are expected). — silent → silent — server yes(get_branch_routes_lite / get_branch_routes WHERE is_active AND status…) — **HOLDS**
- `G-936` A branch that is permanently closed or inactive is not shown as the route's start label on any card. — *sees:* Card simply has no branch line. — silent → silent — server yes(RLS/branches query filter active+is_open in the select; no RPC) — **HOLDS**
- `G-937` While routes load, the customer cannot interact with a list; on a load error the screen shows a reason and a retry button instead of an empty list. — *sees:* Spinner while loading; on error a cloud icon, heading 'routesError' and a green 'Retry' button. — clear → clear — server no — **HOLDS**
- `G-938` If there are no routes at all, the customer sees an explicit empty state instead of an empty page. — *sees:* Map emoji, heading 'routesEmptyTitle', short explanation. — clear → clear — server no — **HOLDS**
- `G-939` When search text and filters exclude every route, the customer is told nothing matches and is offered a one-tap 'clear filters'. — *sees:* Magnifier emoji, text 'routesFilterEmpty' and a green 'Clear filters' button. — clear → clear — server no — **HOLDS**
- `G-940` The 'Clear filters' chip in the toolbar only appears when at least one filter, a search text or a non-default sort is active (counter on the Filter chip). — *sees:* Filter pill turns dark green with a number badge; a grey 'x Clear filters' link appears next to it. — clear → clear — server no — **HOLDS**
- `G-941` Clearing filters from the Routes list only resets what the Routes list owns (countries, search, length/time, approach, sort); Places categories, 'nearby' and ratings are deliberately kept. — *sees:* Routes reset; place filters elsewhere stay as they were. Not explained. — silent → silent — server no — **HOLDS**
- `G-942` If the screen was torn down while a filter or sort sheet was still open (app returning from background), applying or clearing does nothing to the dead screen instead of crashing. — *sees:* Sheet just closes; no crash. — silent → silent — server no — **HOLDS**
- `G-944` Default order 'nearest to me' silently falls back to the stable random order when location is not allowed; location is only requested quietly (never forced to Settings). — *sees:* Routes appear in random order; the Sort pill still says 'Nearest to me'. No explanation. — silent → silent — server no — **HOLDS**
- `G-945` Tapping the star rating on a route card opens the reviews sheet directly from the list (where writing a review is login-guarded, see S-207). — *sees:* Reviews sheet opens. — clear → clear — server yes(get_route_reviews / submit_route_review) — **HOLDS**
- `G-946` Opening a route remembers it as the anchor for 'sort from chosen route' and passes only the currently filtered siblings for swiping in the detail. — *sees:* Detail opens; swiping stays within the filtered list. — silent → silent — server no — **HOLDS**
- `G-947` Back from the Routes list always has a target: without history it goes to Places (the Routes tab root). — *sees:* Back arrow returns to Places. — clear → clear — server no — **HOLDS**

**S-202 Recommended routes list / S-213 Recording controls card / Ride recording**

- `G-943` Starting a ride with the phone's location service switched off is refused. — *sees:* Snackbar 8 s 'location is off' with Open settings. — small → clear — server yes(start_user_ride requires auth.uid() — **HOLDS**

**S-203 Routes sort sheet**

- `G-948` 'Nearest to me' cannot be chosen while the app has no location; the option is greyed out and does nothing. — *sees:* Row and icon grey, not tappable; no text says why. — clear → clear — server no — **HOLDS**
- `G-949` 'Nearest to the chosen route' cannot be chosen until the customer has opened some route (no anchor yet). — *sees:* Row greyed out, not tappable. — clear → clear — server no — **HOLDS**
- `G-950` Picking a sort option closes the sheet and only changes the list if the screen is still alive. — *sees:* Sheet closes, list re-orders. — silent → silent — server no — **HOLDS**

**S-204 Routes filter sheet**

- `G-951` Filter changes are only a working copy; nothing changes in the list until the customer presses 'Show (N)'. Closing the sheet by swipe/back discards the changes. — *sees:* Big green 'Show results (N)' button with live count; swipe-down leaves filters unchanged. — clear → clear — server no — **HOLDS**
- `G-952` 'Include the ride from my location' needs the customer's location; if location is not available the app asks for it (with explanation) and the toggle stays off when refused. — *sees:* Location permission dialog / explanation; chip stays unselected if refused. — clear → clear — server no — **HOLDS**
- `G-953` The length slider, the time slider and the approach toggle are only offered when the data actually has a usable range (at least two different values). — *sees:* Section simply absent. — silent → silent — server no — **HOLDS**
- `G-954` Turning the approach toggle resets length/time to the new full range, so a slider value outside the new bounds can never be applied (and cannot crash the slider). — *sees:* Sliders jump to full range. — silent → silent — server no — **HOLDS**
- `G-955` A slider left at its full range does not count as a hidden filter; if one axis is full, the linked other axis is dropped too. — *sees:* Filter badge not raised for full ranges. — silent → silent — server no — **HOLDS**
- `G-956` 'Clear filters' inside the sheet both resets and applies, then closes the sheet. — *sees:* Sheet closes, all route filters off. — clear → clear — server no — **HOLDS**
- `G-957` Countries already selected (possibly coming from Places) are always listed so they can be un-ticked, even if no route uses them. — *sees:* Selected country chip visible. — silent → silent — server no — **HOLDS**

**S-205 Routes map**

- `G-958` By default the map shows only points that lie on routes; other places are hidden until the customer switches them on. — *sees:* Toggle chip '+ other places' / 'only routes' in the header. — clear → clear — server no — **HOLDS**
- `G-959` Route lines are drawn only for routes passing through the selected points; if road routing fails no line is drawn (never straight lines) and the card says the line failed. — *sees:* Card subtitle 'Computing...' or 'Line failed'. — small → small — server no — **HOLDS**
- `G-960` 'Next route' chip only appears when the selected point lies on more than one route. — *sees:* Chip absent with a single route. — clear → clear — server no — **HOLDS**
- `G-961` The bottom route picker and the selection bar only appear after the customer has selected at least one point; the picker only when some route matches. — *sees:* No panel until a point is tapped. — clear → clear — server no — **HOLDS**
- `G-962` 'Continue' with selected points does nothing if the selection can no longer be resolved to real places. — *sees:* Nothing happens. — silent → silent — server no — **HOLDS**
- `G-963` 'My location' button: if the app has no location it asks for it (with explanation / Settings) and does not move the map when refused. — *sees:* Permission explanation; map stays. — clear → clear — server no — **HOLDS**
- `G-964` The 'Your route' draft chip is only shown when a road-routed draft (2+ points) exists; its x clears the draft. — *sees:* White pill with km and x. — clear → clear — server no — **HOLDS**
- `G-965` Back from the map always has a target (Routes list) even without history. — *sees:* Back arrow. — clear → clear — server no — **HOLDS**

**S-206 Route detail**

- `G-966` A route that no longer exists (deleted/unpublished, stale link) is not shown; the customer gets 'Route not found' with an explanation and a Back button. — *sees:* Icon, 'routeNotFound' heading, explanation, 'Back' button. — clear → clear — server yes(get_route_detail returns null for missing/inactive; list from get_bra…) — **HOLDS**
- `G-967` While loading the detail the customer sees a loader with Back/Retry; a load error shows the reason with Retry and Back (not 'not found'). — *sees:* Loader; on error message + Retry + Back. — clear → clear — server no — **HOLDS**
- `G-968` Swiping between routes only works when the detail was opened from a list with 2+ routes, and stops at the first/last route. — *sees:* Nothing happens at the ends; no indicator in the old look. — silent → clear — server no — **HOLDS**
- `G-969` 'Customize route' (open in builder) is only offered when the route has points or waypoints. — *sees:* Button absent otherwise. — clear → clear — server no — **HOLDS**
- `G-970` 'Navigate' opens the in-app navigation for this route; there is no login or rental requirement (routes are public). — *sees:* Navigation screen opens. — clear → clear — server no — **HOLDS**
- `G-971` Opening the route in another navigation app is refused when the route has fewer than 2 usable points. — *sees:* Snackbar 'no navigation data'. — small → clear — server no — **HOLDS**
- `G-972` If the external navigation app cannot be opened, the customer is told. — *sees:* Snackbar 'could not open'. — small → small — server no — **HOLDS**
- `G-973` While the road line is still being computed the map shows only the stored road geometry (never straight lines) with a 'computing' chip. — *sees:* 'Computing route' chip on the map. — clear → clear — server no — **HOLDS**
- `G-974` The reviews block is part of the detail, with its write/delete guards (see S-207). — *sees:* Reviews section under the gallery. — clear → clear — server yes(get_route_reviews / submit_route_review / delete_route_review) — **HOLDS**
- `G-975` Rides recorded during one of the customer's rentals (the 'bike booking' rides section in reservation detail) are only listed when that booking has rides; the section is hidden otherwise and needs login. — *sees:* Section absent when no rides. — silent → silent — server yes(get_booking_rides owner or admin only) — **HOLDS**

**S-207 Route reviews sheet + editors**

- `G-976` Writing or editing a review requires login; a logged-out customer is stopped with a message (from the list sheet and from the detail section). — *sees:* Snackbar asking to log in; editor does not open. — small → small — server yes(submit_route_review requires auth.uid() — **HOLDS**
- `G-977` A review cannot be sent without a star rating. — *sees:* Snackbar 'please choose stars'. — small → small — server yes(submit_route_review raises exception when rating not 1-5) — **HOLDS**
- `G-978` The send button is disabled while the review is being sent (no double submit). — *sees:* Button greyed with '...'. — clear → clear — server no — **HOLDS**
- `G-979` If the editor somehow has no logged-in user at send time, nothing is sent. — *sees:* Nothing happens. — silent → silent — server yes(submit_route_review requires auth.uid() — **HOLDS**
- `G-980` A failed send keeps the editor open and tells the customer. — *sees:* Snackbar 'could not send'. — small → small — server no — **HOLDS**
- `G-981` Photos that fail to upload are silently left out of the review (the review is still sent). — *sees:* Review saved without that photo; no message. — silent → silent — server yes(storage policy media_route_review_upload: authenticated, prefix route…) — **HOLDS**
- `G-982` One review per customer per route: when the customer already has one, the button says 'Edit' and opens it pre-filled. — *sees:* Button 'Edit review'. — clear → clear — server yes(submit_route_review upserts ON CONFLICT user_id+route_id) — **HOLDS**
- `G-983` Delete is only offered for the customer's own review and only in the detail section (not in the quick sheet from the list); it deletes without a confirmation dialog in both looks. — *sees:* Red 'Delete review' text button. — clear → clear — server yes(delete_route_review deletes only the caller's own review) — **HOLDS**
- `G-984` Only approved reviews are visible to others; the customer's own hidden review is highlighted red. — *sees:* Red-tinted card for own hidden review. — clear → clear — server yes(get_route_reviews returns approved + own + admin) — **HOLDS**
- `G-985` While reviews load the write button in the detail section is not offered; a load error simply shows the empty list (logged). — *sees:* Spinner, then 'no reviews yet' on error. — silent → silent — server no — **HOLDS**

**S-208 Route builder**

- `G-987` 'Navigate' is disabled until there is at least one stop. — *sees:* Faded button, does nothing. — clear → clear — server no — **HOLDS**
- `G-988` 'Save route' and 'Suggest to community' are disabled until the route has at least 2 stops. — *sees:* Both buttons faded, do nothing. — clear → clear — server no — **HOLDS**
- `G-989` Saving a route for myself requires login. — *sees:* Snackbar asking to log in. — small → small — server yes(save_user_route requires auth) — **HOLDS**
- `G-990` Suggesting a route to the community requires login. — *sees:* Snackbar asking to log in. — small → small — server yes(RLS routes_user_submit created_by = auth.uid() — **HOLDS**
- `G-991` Save/suggest re-check that the route has at least 2 points. — *sees:* Snackbar 'need at least two points'. — small → small — server yes(save_user_route requires waypoints array >= 1; suggestion: unknown) — **HOLDS**
- `G-992` The name sheet refuses to send without a name. — *sees:* Snackbar 'name required'. — small → small — server yes(save_user_route: name required) — **HOLDS**
- `G-993` Send button is disabled while saving/sending; on failure the sheet stays open with an error. — *sees:* Button shows 'Sending...' and is disabled; error snackbar on failure. — clear → clear — server no — **HOLDS**
- `G-994` The server limit of saved routes (200 per customer) refuses saving; the app shows the generic save error. — *sees:* Snackbar 'could not save' (no specific reason). — small → small — server yes(save_user_route limit_reached at 200) — **HOLDS**
- `G-995` 'Suggest to community' tells the customer the suggestion goes to moderation before anyone sees it. — *sees:* Banner with moderation note above the fields. — small → small — server yes(RLS routes_user_submit forces status='pending' AND is_active=false) — **HOLDS**
- `G-996` Without road routing (no signal / API failure) the builder draws no line and shows no length, never straight lines. — *sees:* Length/time show '-'. — silent → silent — server no — **HOLDS**
- `G-997` Points already in the route are not offered again in 'nearby suggestions'; the panel is hidden until there is a first stop and caps the number of cards. — *sees:* Panel absent / only new points listed. — silent → silent — server no — **HOLDS**
- `G-998` The builder cannot be opened without a route payload (process restore / deep link); the customer gets an error page with a way home instead of a crash. — *sees:* Error page with a home button. — clear → clear — server no — **HOLDS**
- `G-999` Picking points from the catalogue and cancelling adds nothing. — *sees:* Nothing changes. — silent → silent — server no — **HOLDS**
- `G-1000` After a successful save the 'unsaved changes' lock is released, so leaving no longer asks. — *sees:* No discard dialog after saving. — silent → silent — server no — **HOLDS**

**S-209 Route navigation**

- `G-1001` Navigation needs location: if permission is denied or location services are off, the map shows a banner with 'Allow location' (when the system can still ask) or 'Open settings', and stop/fork pills are hidden. — *sees:* White banner with pin icon, reason text and an 'Allow' or 'Open settings' button. — clear → clear — server no — **HOLDS**
- `G-1002` After returning from Settings the navigation re-checks location by itself (without asking again). — *sees:* Banner disappears when location becomes available. — silent → silent — server no — **HOLDS**
- `G-1003` Lost GPS, weak signal or no road routing (offline: only joining lines) is announced on the map. — *sees:* Banner at the top with the reason. — clear → clear — server no — **HOLDS**
- `G-1004` A route that no longer exists cannot be navigated: 'Route not found' with explanation and Back. — *sees:* Error view with heading and Back. — clear → clear — server yes(get_branch_routes_lite / get_route_detail only active approved routes) — **HOLDS**
- `G-1005` A custom navigation cannot start without its route payload (deep link / restore). — *sees:* Error page. — clear → clear — server no — **HOLDS**
- `G-1006` Ending the ride with the red X asks for confirmation; only then the ride moves to history and the screen closes. — *sees:* Dialog 'End route?' with Cancel and red 'End'. — clear → clear — server no — **HOLDS**
- `G-1007` The back arrow does not end the ride; the ride stays active and can be continued later (shell strip / app relaunch). — *sees:* Screen closes; 'Continue route' pill appears in the app. — clear → clear — server no — **HOLDS**
- `G-1008` On app launch a still-active (not finished) ride reopens the navigation automatically; a finished ride does not. — *sees:* App opens straight into navigation. — clear → clear — server no — **HOLDS**
- `G-1009` Reopening the same route restores the stops already reached instead of starting over. — *sees:* Ticks on already reached stops. — silent → silent — server no — **HOLDS**
- `G-1010` A stop is only ticked off when the customer presses 'Continue' on the arrival card; closing the card does not confirm it; named stops are never ticked automatically when passed. — *sees:* Arrival card with name, 'Continue to next', 'Stops', X. — clear → clear — server yes(mark_place_visited records the visit server-side; dojezd confirmation…) — **HOLDS**
- `G-1011` 'Rate this place' on the arrival card is only offered when the stop is a point of interest. — *sees:* Star button only for POI stops. — clear → clear — server yes(rate_poi RPC for ratings) — **HOLDS**
- `G-1012` A place visit is recorded only once per point per navigation session. — *sees:* 'Place discovered' badge on the card. — small → small — server yes(mark_place_visited upsert, needs auth) — **HOLDS**
- `G-1013` The finish card offers 'Rate route' only for a published route and 'Save route' only for a custom ride. — *sees:* Finish card with the matching button. — clear → clear — server no — **HOLDS**
- `G-1014` Saving a finished custom ride requires login. — *sees:* Snackbar asking to log in. — small → small — server yes(save_user_route requires auth) — **HOLDS**
- `G-1015` Rating a finished route opens the reviews sheet, where writing is login-guarded (S-207). — *sees:* Reviews sheet. — clear → clear — server yes(submit_route_review) — **HOLDS**
- `G-1016` The stops list chip is only shown when the route has stops. — *sees:* Checklist chip 'n/N' at the top. — clear → clear — server no — **HOLDS**
- `G-1017` The status line under the route name says when the rider is off the route or when the route is being (re)computed. — *sees:* Small text under the route name. — small → small — server no — **HOLDS**
- `G-1019` Routing through at most 15 remaining stops per request (API limit) - extra stops are silently left for later recalculation. — *sees:* Nothing shown. — silent → silent — server no — **HOLDS**

**S-209 Route navigation / S-214 Ride pause / recording status sheet**

- `G-1018` The recording chip in navigation (and its sheet) exists only while something is recorded; when the recording ends the sheet closes itself. — *sees:* No chip; open sheet disappears. — clear → clear — server yes(start/append/finish_user_ride) — **HOLDS**

**S-210 End ride / save custom route dialogs**

- `G-1020` End ride dialog: Cancel (or tapping outside) keeps the ride running; only the red End button ends it. — *sees:* Dialog with Cancel and red End. — clear → clear — server no — **HOLDS**
- `G-1021` Save dialog: cancelling or leaving the name empty saves nothing (no message for an empty name). — *sees:* Dialog closes; nothing saved, no text explains an empty name. — silent → silent — server yes(save_user_route: name required) — **HOLDS**
- `G-1022` After saving, the customer is told whether it worked. — *sees:* Snackbar. — small → small — server yes(save_user_route incl. limit_reached) — **HOLDS**

**S-211 Navigation stops sheet**

- `G-1023` Choosing 'Navigate here' on a later stop skips (ticks) the earlier unreached ones; choosing an already visited stop un-ticks it so arrival must be confirmed again. — *sees:* List with ticks, 'Next' label and a 'Navigate here' button per row. — clear → clear — server no — **HOLDS**
- `G-1024` The MotoGo24 branch appears as an extra last row only while it is not yet added and the branch has a location; it can be added only once. — *sees:* Extra 'MotoGo24 - branch' row. — clear → clear — server no — **HOLDS**
- `G-1025` The sheet cannot be opened when there are no stops. — *sees:* Nothing opens (chip hidden anyway). — silent → silent — server no — **HOLDS**

### Global locks and floating buttons (overlays, shell, tabs, banners, push, back) — 74 safeguards, 2 weaker

**App shell (bottom navigation) while typing**

- `X-2-02` While the keyboard is open (chat, profile, SOS form, any input on a shell route) the customer cannot switch tabs because the bottom navigation bar is removed, so the inner screen's send button is not covered. — *sees:* The bottom bar disappears while the keyboard is up and returns when it closes. — clear → clear — server no — **HOLDS**

**In-app push banner (app open)**

- `X-1-02` A notification arrives while the app is open; the customer must notice it (especially issued door codes) and can open its target with 'Zobrazit'. — *sees:* A floating dark banner: door codes = key emoji, green title, green frame, up to 4 lines, 8 s; others = envelope emoji, 2 lines, 5 s; green 'Zobrazit' action. — clear → clear — server yes(trg_push_on_admin_message -> edge send-push; send-push skips when pro…) — **HOLDS**

**Language after login (profile sync; decides language of e-mails, SMS and contracts)**

- `X-2-05` When the customer logs in (or the app starts with a saved login), if no language was ever chosen in the app the app silently switches to the profile language; otherwise it silently overwrites profiles.language with the app language, which then decides the lan… — *sees:* Nothing; at most the app language changes after login. No confirmation. — silent → silent — server yes(detect_customer_language(user_id, booking_id, order_id) — **HOLDS**

**Notification tap (cold start / login screens)**

- `X-1-01` The customer taps a notification (booking, door codes, SOS answer, message) while the app is still starting or while they are on Login, Registration or Password reset; the target screen is held back until they are inside the app. — *sees:* Nothing special: after logging in the app opens the target screen (detail, Messages, SOS). If the customer stays on the login screens for more than 2 minutes the tap is silently forgotten and they la… — silent → silent — server no — **HOLDS**

**Notification tap routing table**

- `X-1-03` The customer taps a notification; the app decides which screen opens by the notification type. — *sees:* The matching screen opens; for messages/door codes the notification is expanded and marked read (messages_screen.dart:36-39). A booking notification without id opens nothing. 'shop_order' opens the e… — silent → silent — server yes(type and id are set server-side by trg_push_on_admin_message / send-p…) — **HOLDS**

**Push registration and badge clearing (app-wide)**

- `X-1-04` Door-code and SOS-answer pushes reach the phone only when notification permission is granted and a customer is logged in; opening the app clears delivered notifications and the icon badge. — *sees:* Nothing. Without the permission no push and no in-app banner arrives, and nothing in the app says so (door codes still appear in Messages / e-mail / SMS). The tray and the badge are emptied on openin… — silent → silent — server yes(send-push sends only to push_tokens.active = true and skips when prof…) — **HOLDS**

**System back without history (whole app)**

- `X-1-06` The customer presses system back (or swipes back) on a screen with nothing underneath (opened from a tab, a notification or a deep link); instead of closing the app it goes to a fixed parent screen, after the screen's own back handler (confirmation dialog) ge… — *sees:* The parent screen opens instead of the app closing; on screens with their own BackButtonListener (payment_screen.dart:1504, payment_confirmation_screen.dart:284, payment_result_screen.dart:215, shop_… — clear → clear — server no — **HOLDS**

**Whole app (MaterialApp.builder, above both looks)**

- `X-2-01` A customer who has set larger text on the phone opens the app; every text is still drawn at the designed size because the app overrides the phone's text scale with TextScaler.noScaling. — *sees:* Nothing; text simply does not grow. No message. — silent → silent — server no — **HOLDS**

**Whole app - screen orientation**

- `X-1-08` The customer turns the phone; every screen (incl. the document scanner camera, maps, navigation) stays in portrait. — *sees:* The screen does not rotate. — clear → clear — server no — **HOLDS**

**S-011 First-launch intro animation**

- `G-001` On the very first start the intro animation covers the whole app and swallows every touch on the screens below it; it is shown only once per installation. — *sees:* Dark full-screen logo animation with a passing motorbike for about 2.4 s; a tap anywhere ends it. — clear → clear — server no — **HOLDS**
- `G-002` While the intro, the language or the permission overlay is on screen (or onboarding is not yet evaluated), a loyalty level-up celebration is held back so it cannot play invisibly underneath. — *sees:* Nothing; the celebration simply appears after onboarding is finished. — silent → silent — server no — **HOLDS**

**S-012 Language selection overlay**

- `G-003` On first launch (no mg_locale saved) the customer cannot reach the app until a language is chosen; there is no skip or close button and the overlay covers everything. — *sees:* Black page 'MotoGo24 – Choose your language / Vyberte jazyk' with a 2-column grid of 8 flag buttons. — clear → clear — server no — **HOLDS**
- `G-004` Choosing a language also switches the currency to match the language, but only if the customer has not picked a currency by hand. — *sees:* Prices appear in CZK/EUR/PLN according to the language without any message. — silent → silent — server no — **HOLDS**
- `G-005` The permission overlay never appears together with the language overlay: it comes only after a language is chosen and only if it was not shown before. — *sees:* Language page first, then the permission page. — clear → clear — server no — **HOLDS**

**S-013 Permissions onboarding overlay**

- `G-006` Tapping 'Povolit vše' twice is blocked while the system permission dialogs are running (a parallel request would crash permission_handler). — *sees:* The green button turns grey (disabled) while system dialogs are open. — clear → clear — server no — **HOLDS**
- `G-007` 'Přeskočit – nastavím později' is disabled while the permission request is running. — *sees:* Grey skip link during the request. — small → small — server no — **HOLDS**
- `G-008` Back arrow and system back return to the language page, but not while the permission request is running (back then belongs to the system dialog). — *sees:* A back arrow top-left; back shows the language grid again. — clear → clear — server no — **HOLDS**
- `G-009` The permission page is shown once: after 'Allow all' or 'Skip' mg_perms_shown is stored and the page never returns. — *sees:* Nothing further; the app opens. — silent → silent — server no — **HOLDS**

**S-014 Offline full-screen overlay**

- `G-011` 'Zkusit znovu' is disabled while the connection is being checked; if still offline the customer gets a warning instead of the overlay silently staying. — *sees:* Spinner in the button, then amber line 'still offline'. — small → clear — server no — **HOLDS**
- `G-012` System back while the overlay is visible closes it like 'Pokračovat bez internetu' and is not passed to the hidden screen below (screens with their own back listeners stand aside). — *sees:* Overlay disappears, thin 'offline' strip stays at the top. — clear → clear — server no — **HOLDS**
- `G-013` After the customer chose 'continue offline', further connection drops show only the thin strip, not the full overlay again, until the connection comes back. — *sees:* Only the top strip. — small → clear — server no — **HOLDS**
- `G-014` The offline overlay always offers the nonstop MotoGo24 line and 112 (calls work without data), so an offline customer in trouble is never stuck. — *sees:* '📞 Zavolat nonstop' and red '🆘 112' links under the buttons. — clear → clear — server no — **HOLDS**

**S-014 Offline full-screen overlay / S-168..S-177 (all shop screens) / Whole app (overlay)**

- `G-010` When the phone loses connection (or the app starts without one), a full-screen 'you are offline' overlay is placed above every screen and dialog route present at that moment, so the customer cannot keep tapping through screens that would fail. — *sees:* Black page with 📡, 'Nejsi připojený k internetu' heading, explanation, 'Zkusit znovu' and 'Pokračovat bez internetu' buttons, plus emergency call links. — clear → clear — server no — **HOLDS**

**S-015 Offline / back-online strip**

- `G-015` After 'continue offline' a thin strip stays at the top saying the app is offline (saved data only); it does not block touches. — *sees:* Small amber pill '📡 offline' under the status bar. — small → clear — server no — **HOLDS**
- `G-016` Wi-Fi or data is on but the internet does not work (captive portal): after two failed pings to Supabase a strip 'internet nefunguje' appears and is re-checked every 20 s; it disappears and data reloads when a ping succeeds. — *sees:* Small amber pill 'no internet'. — small → clear — server no — **HOLDS**

**S-016 Forced update dialog**

- `G-018` The version gate is re-checked on every return to the app (at most every 15 minutes), and once shown it never closes for the rest of the session. — *sees:* The blocking dialog can appear even after the app has been open for days. — clear → clear — server no — **HOLDS**
- `G-019` If the store cannot be opened, the dialog stays blocking and tells why, and still offers the nonstop line and 112. — *sees:* Red line 'store could not be opened', emergency calls. — small → clear — server no — **HOLDS**
- `G-020` If the version check itself fails (no network, error), the app lets the customer continue (fail-open). — *sees:* Nothing. — silent → silent — server no — **HOLDS**

**S-016 Forced update dialog / Whole app (blocking dialog)**

- `G-017` If the installed version is lower than app_settings.min_app_version (platform key first), a blocking dialog appears: tapping outside and system back do nothing; the only way on is updating from the store. — *sees:* Dialog 'Vyžadována aktualizace' with the required version and one green 'Aktualizovat' button. — clear → clear — server no — **HOLDS**

**S-017 In-app (store) update**

- `G-021` Android: a release marked high priority (>= 4) in Play starts Google's full-screen immediate update; an immediate update the customer left in the background is resumed on the next check. — *sees:* Google Play's own blocking update screen. — clear → clear — server no — **HOLDS**
- `G-022` Android flexible update: download runs in the background, then a snackbar for 12 s offers 'Restartovat'. — *sees:* Snackbar 'Update downloaded' + 'Restart'. — small → small — server no — **HOLDS**
- `G-023` Update offers are throttled to one every 6 hours. — *sees:* Nothing. — silent → silent — server no — **HOLDS**
- `G-024` iOS: a newer App Store version shows a dismissible dialog 'Later / Update'. — *sees:* Dialog 'Nová verze k dispozici' with Později / Aktualizovat. — clear → clear — server no — **HOLDS**

**S-018 Loyalty level-up celebration**

- `G-025` The celebration plays only for a logged-in customer, exactly once per new level (server remembers the celebrated level; local copy as fallback) and never on the very first observation of a rank. — *sees:* Full-screen video celebration with 'Pokračovat'. — clear → clear — server yes(RPC loyalty_get_celebrated / loyalty_advance_celebrated; customers ca…) — **HOLDS**
- `G-026` The celebration is held back while the payment screen is open (and during onboarding) so it cannot cover or interrupt a payment. — *sees:* Nothing during payment; celebration comes after leaving payment. — silent → silent — server no — **HOLDS**
- `G-027` Checkout is locked: while the payment screen is open the loyalty rank is not refreshed, so the charged price cannot drift from the price already prepared. — *sees:* Nothing. — silent → silent — server unknown — **HOLDS**
- `G-028` The celebration cannot be closed by tapping outside; it closes with 'Pokračovat' or by itself after 67 s (system back also closes it - no PopScope). — *sees:* Celebration with a button. — clear → clear — server no — **HOLDS**
- `G-029` Only one celebration can open at a time, and background rank polling pauses while it plays. — *sees:* Nothing. — silent → silent — server no — **HOLDS**

**S-019 Shared error dialog**

- `G-030` An error dialog stops the flow and asks the customer to pick an action (e.g. Zavolat / Zkusit znovu / Otevřít nastavení) or close; tapping outside closes it without an action. — *sees:* Dialog with bold title, explanation and buttons. — clear → clear — server no — **HOLDS**
- `G-031` When a caller passes showClose:false the dialog has no 'Zavřít' and the customer must pick an action. — *sees:* Only action buttons. — clear → clear — server no — **HOLDS**
- `G-032` Location unavailable when the customer asked for it: dialog explaining why (off / denied / no fix); settings open only on tap. — *sees:* Dialog or toast with reason and 'Otevřít nastavení'. — clear → clear — server no — **HOLDS**
- `G-033` Error toast: what failed + why + one action, chosen in a fixed order (settings, retry, call); for payments/bookings the call action is suppressed (contact:false). — *sees:* Snackbar for 7 s with one action. — small → small — server no — **HOLDS**

**S-020 Discard confirmation**

- `G-034` Leaving a form with unsaved input asks 'Zahodit rozpracované?' with Zahodit / Zůstat; tapping outside means stay. — *sees:* Dialog with red 'Zahodit' and 'Zůstat'. — clear → clear — server no — **HOLDS**

**S-021 Blocking progress dialog (MgProgress)**

- `G-035` During document upload or document opening a progress dialog blocks the screen: it cannot be closed by tapping outside, and back does nothing unless the operation is cancellable. — *sees:* Dialog with spinner and live text ('Zpracovávám doklad…'). — clear → clear — server no — **HOLDS**
- `G-036` 'Zrušit' and the 'takes longer' hint appear only after a limit (20 s upload, 15 s opening); a cancelled result is discarded. — *sees:* Hint text + Zrušit after the limit. — small → small — server no — **HOLDS**

**S-022 Unknown link page and router redirects**

- `G-037` An unknown or outdated link opens a clear error page whose only action is 'Domů'; back also leads Home. — *sees:* Error view 'Tahle stránka v aplikaci neexistuje' + 'Domů'. — clear → clear — server no — **HOLDS**
- `G-038` A foreign-scheme link (motogo24://payment returning from bank 3-D Secure) does not navigate: the current screen, including a running payment, stays. — *sees:* Nothing changes. — silent → silent — server no — **HOLDS**
- `G-039` Released 4.1.3 had a global watcher that pushed the customer into the handover-protocol screen (/protocol, login required) when the kiosk asked for it. It is gone from BOTH looks on this branch; the protocol is now signed only on the branch display. — *sees:* Now: nothing in the app. — silent → silent — server yes(kiosk will not open the bike bay without a signed protocol: protocol_…) — **HOLDS**
- `G-040` If a screen crashes while building, a friendly page with 'Zpět' and 'Domů' replaces the red error screen. — *sees:* 'Tady se něco pokazilo' with Zpět / Domů. — clear → clear — server no — **HOLDS**
- `G-041` The kill-switch changes the look only at a safe moment (tab root with nothing pushed, after cold start, on resume) - never in the middle of a booking, edit or payment. — *sees:* Nothing. — silent → silent — server no — **HOLDS**

**S-001**

- `G-346` The customer taps the tab that is already highlighted (for example "Rezervovat" while filling the booking form at /booking or sitting on /payment, or "Rezervace" inside a reservation detail); in the old look the tap does nothing, so an accidental tap never th… — *sees:* Nothing happens; the customer stays on the form / payment. — silent → silent — server no — **WEAKER (minor)**
- `G-347` The customer taps "Domů": the old look throws away the half-filled booking (draft, chosen bike and catalogue date filter), so a later booking never continues with stale choices. — *sees:* Silently a fresh start: Domů, and the next booking starts empty. — silent → silent — server no — **HOLDS**
- `G-348` Login, registration, password reset, payment success, documents and document scanning are full-screen steps without the bottom navigation, so the customer cannot jump away by tabs in the middle of them. — *sees:* No bottom bar on those screens; only the screen's own back. — clear → clear — server no — **HOLDS**
- `G-349` The customer has unread messages from MotoGo24 (admin_messages); a red badge with the count (max "9+") warns them. — *sees:* Red circle with a number on the Domů icon. — clear → clear — server no — **HOLDS**

**S-002**

- `G-350` MotoGo24 publishes an announcement in Velín (app_settings.header_banner, e.g. closure, weather, outage); the old look shows it as a scrolling coloured band at the very top of every shell screen, in the colours chosen in Velín. — *sees:* A fixed coloured marquee strip above the content, always on screen. — clear → small — server no — **WEAKER (minor)**

**S-003**

- `G-351` The customer has items in the e-shop cart and leaves the shop; a floating button reminds them (count + total) and leads to the cart. — *sees:* Green pill "🛒 n položek · X Kč" with a red ✕. — clear → clear — server no — **HOLDS**
- `G-353` The customer closes the cart reminder with ✕; it stays hidden until they add a product again (product detail resets the flag). — *sees:* The pill disappears. — clear → clear — server no — **HOLDS**

**S-003 / S-170 Cart**

- `G-352` Outside the shop, a cart reminder floating button appears only when the cart has items, is hidden on shop/cart/checkout/voucher screens and on the payment screen, and stays away after the customer dismisses it. — *sees:* Green pill 'cart: N items / total' with a red X. — clear → clear — server no — **HOLDS**

**S-004**

- `G-355` The unpaid-booking button disappears exactly when the 30-minute payment window runs out (window restarts from restored_at for a booking restored in Velín), mirroring the server auto-cancel, so the customer is not offered payment for a booking about to be canc… — *sees:* The pill vanishes when the countdown reaches 0. — small → small — server yes(auto_cancel_expired_pending() — **HOLDS**
- `G-356` A booking made on the WEB that waits for a bank transfer (QR) is never offered for card payment in the app, which would cause a double payment. — *sees:* No pill for web bookings. — silent → silent — server yes(set_booking_qr_payment / qr-payment only for web; no server rule foun…) — **HOLDS**
- `G-357` The unpaid-booking button is hidden on login, registration, document scanning, payment and payment-success screens (and whenever the payment screen is active), so it never covers the pay button or interrupts sign-in. — *sees:* No pill there. — silent → silent — server no — **HOLDS**

**S-004 / Shell (floating panel) / Anywhere in app (floating button)**

- `G-354` The customer created a booking in the app but has not paid; a floating button "Dokončit rezervaci · M:SS" with a 30-minute countdown brings them back to payment of exactly that booking (amount and id from the database, not from a possibly empty draft). — *sees:* Green pill "💳 Dokončit rezervaci · 12:34" with red ✕. — clear → clear — server yes(auto_cancel_expired_pending() — **HOLDS**

**S-005 / S-086 / S-073 Payment screen / Floating button**

- `G-358` The customer already submitted a payment that the bank/server has not confirmed yet (local marker, or the last PaymentIntent is still processing on Stripe); the app does NOT offer "Dokončit rezervaci" again (double payment) but only opens "Platba se ověřuje". — *sees:* Yellow pill "⏳ Ověřujeme platbu" without a cancel ✕. — clear → clear — server yes(confirm_payment deduplicates a second webhook; no server rule found t…) — **HOLDS**

**S-006**

- `G-360` The cancel request only cancels a booking that is still unpaid, and if it fails (offline/timeout) the customer gets an explanation with "Zkusit znovu" instead of a silent failure. — *sees:* Error snackbar with title, reason and "Zkusit znovu". — clear → clear — server yes(see previous record) — **HOLDS**

**S-006 / Floating button X**

- `G-359` The customer taps ✕ next to the unpaid-booking button; because cancelling is irreversible and the ✕ sits right next to "pay", a confirmation dialog must be accepted first. — *sees:* Dialog "Zrušit rezervaci?" with Zpět and a red Zrušit rezervaci. — clear → clear — server yes(_trg_guard_customer_booking_status lets the customer write only statu…) — **HOLDS**

**S-007**

- `G-362` The SOS reminder is hidden on the SOS screens themselves, on login/registration, documents and the SOS payment, and whenever a payment screen is active. — *sees:* No SOS pill there. — silent → silent — server no — **HOLDS**
- `G-363` The customer closes the SOS reminder with ✕; it stays hidden for that incident for 7 days (then comes back), without a confirmation. — *sees:* The pill disappears. — clear → clear — server no — **HOLDS**

**S-007 / S-188 / Shell – floating strips**

- `G-361` After reporting an SOS incident whose replacement bike is not chosen yet (replacement_status selecting or pending_payment, incident not resolved/closed), a floating "SOS dokončit" button keeps leading the customer back to choosing the replacement. — *sees:* Green pill "🆘 SOS dokončit" with red ✕. — clear → clear — server no — **HOLDS**

**S-008**

- `G-365` The documents reminder is hidden on Moje doklady and the scanner (the customer is already there) and on any payment screen; while the status is unknown (loading/error) it is hidden rather than shown wrongly. — *sees:* No pill there. — silent → silent — server no — **HOLDS**
- `G-366` The customer closes the documents reminder with ✕; it stays hidden only for the current app session (it comes back after a restart). — *sees:* The pill disappears. — clear → clear — server no — **HOLDS**

**S-008 / S-127 Documents screen / Shell (floating panel) / Shell – floating strips / Anywhere (floating button)**

- `G-364` The customer has a paid active or upcoming booking but the identity document (ID card or passport, both sides) or the driving licence is missing/unverified; a floating "Nahrajte doklady" button sends them to Moje doklady (without documents no door codes are i… — *sees:* Green pill "📋 Nahrajte doklady" with red ✕. — clear → clear — server yes(get_docs_gate_checklist / booking_docs_gate; auto_generate_door_codes…) — **HOLDS**

**S-009**

- `G-367` The customer left a running route navigation (back arrow or closed app); a floating "Pokračovat v trase" button takes them back into it, and ✕ ends the ride (moves it to history) — the only way to close it. — *sees:* Green pill "🧭 Pokračovat v trase · <name>" with red ✕. — clear → clear — server no — **HOLDS**

**S-009 / S-209 Route navigation / Shell – floating strips**

- `G-368` 'Continue route' floating pill appears in the app while a ride is active, hidden on payment, login, register, document scan and success screens; its X ends the ride (no confirmation in either look). — *sees:* Green pill 'Continue route - name' with red X. — clear → clear — server no — **HOLDS**

**S-010**

- `G-369` A payment sent just before the app was killed got confirmed (or the paid change was thwarted because another booking took the bike) while the app was closed; after restart the customer is told once, so they do not pay again or wonder. — *sees:* A snackbar with the result and a "Zobrazit" action. — clear → clear — server no — **HOLDS**

## Part B — confirmed gaps in the new look (most severe first)

No gap is critical: in every case the hard stop (form CTA lock, payment lock, server trigger or kiosk) still holds. Major = the customer is very likely not told, or a consent/price picture is wrong in a way that matters; minor = told later, less prominently, or cosmetic.

### Major — 23

**G-152 · S-045 / Bike detail** — The customer has no licence group in the profile, or a group that does not cover the bike (A/A2/A1/AM/B hierarchy, OR of bike groups, kids bike 'N' exempt); once both dates are chosen a warning appears. The detail CTA i…  
Path and proof: Customer with dates carried in opens a bike their licence does not cover; the licence warning is an amber MgStateBanner inside DetailTripCardV2 (validation_banner.dart:72-82, detail_trip_card_v2.dart:191) below a 340-560 px hero and DetailMoreV2, while the sticky dock shows an animated 'REZERVOVAT · price' (detail_dock_v2.dart:89-95, moto_detail_page.dart:275) with no warning. The form still blocks (booking_form_widget.dart:548-554). No server licence check on a new booking.  
Fix: In the v2 branch use MgTone.err for validation_banner.dart; pass the first ValidationBanner error (licence/overlap/length) to DetailDockV2 as a red/amber context line and stop the CTA loop while it is present; keep the CTA enabled as in the old look.  
Server: unknown.

**G-159 · S-047 / S-051 / S-065 / Booking form** — The customer re-enters the booking form for the SAME bike after leaving it unpaid. In the old look every entry starts a fresh draft, so the consents (VOP, GDPR, guardian) must be ticked again; in v2 the earlier draft is…  
Path and proof: Tick consents (and guardian consent on a kids bike), add a discount code and extras on bike X, go back, change dates, tap REZERVOVAT on X again: carryBookingDraft same-bike branch (booking_carry_v2.dart:35-44) keeps consentVop/Gdpr/Kids, discounts, extras and delivery; carried codes are not re-validated (booking_provider.dart:90,120 only on typing). The server recomputes the charge from valid codes only (process-payment/due-verify.ts:8-70).  
Fix: Reset consentVop, consentGdpr and consentKids in the same-bike copyWith (booking_carry_v2.dart:37-44); optionally re-run validate_promo_code/validate_voucher_code for carried codes on entry and drop rejected ones.  
Server: unknown.

**G-230 · S-067** — Kids bike: the guardian consent ('Potvrzuji, že jsem zákonný zástupce…') is shown and required.  
Path and proof: On a kids bike tick all three boxes, leave, pick other dates, tap REZERVOVAT on the same kids bike: the guardian consent is pre-ticked and the CTA is enabled. booking_carry_v2.dart:24-25 promises the guardian consent is always dropped, but the same-bike branch (:35-44) keeps consentKids. Old look started false (booking_models.dart:86). No server check.  
Fix: Add consentKids: false to the same-bike copyWith in booking_carry_v2.dart:37-44 (as the comment promises).  
Server: no.

**G-267 · S-075 Bike gallery + price summary + server price note** — Before paying a new booking the customer sees the full itemised price (bike x days, extras with sizes or 'zdarma', delivery/return fee, discounts, late-pickup discount, deposit not charged, total incl. VAT).  
Path and proof: On the payment page v2 BookingPriceV2 drops gear sizes from extras (price_v2.dart:71-73 vs price_summary.dart:54-55), drops the delivery/return km detail (price_v2.dart:74-75 vs price_summary.dart:63-74), and the big 'Celkem' MgTotalBox shows bd.total WITHOUT the bundled add-on (price_v2.dart:104-106); the real charge is only in a second smaller card (pay_receipt_v2.dart:108-116) and in the pay dock (payment_view_v2.dart:168-172). Server recomputes (process-payment amount_mismatch).  
Fix: In price_v2.dart append the size suffix to extras, reuse the old km delivery label, and pass the upsell total so MgTotalBox shows bd.total + upsell; then drop the second summary card.  
Server: yes(process-payment amount_mismatch recomputes the price).

**G-409 · S-095 / S-104 Access codes card / Reservation detail – access codes** — Door codes are shown only during the rental term and only when codes exist; codes held back (missing documents, not yet released) show the reason instead of the number, with a button that tries release_my_door_codes and…  
Path and proof: Open the reservation detail during the rental term: ResCodesV2 (heading #FFFFFF res_codes_v2.dart:83, labels :164, code digits neon #74FB71 :196, hold-back reason warnDark :166) is placed directly on the light MgPage canvas #F4F7F5 (res_access_codes_card.dart:88, res_detail_tab_content.dart:244, mg_page.dart:74), contrast about 1.1-1.3:1. The customer may be unable to read the door code. Traced in code only, no render.  
Fix: Put ResCodesV2 on a dark rounded container (MgColors.night) in the v2 branch of res_access_codes_card.dart, or give ResCodesV2 light-page tokens (ink labels, dark green digits, MgColors.warn reasons).  
Server: yes(get_my_door_codes, release_my_door_codes, booking_docs_gate, trg_zz_d…).

**G-410 · S-095 / S-104 Access codes card / Reservation detail / Reservation detail – access codes** — Bike swap at a self-service branch: the new bike's code is withheld until the original bike is returned; the 'upload documents' button is deliberately NOT offered (it would not help), only the reason 'Vraťte nejdřív pův…  
Path and proof: Code held back because of a bike swap: no upload button (correct), but the only text, 'return the original bike first', is warnDark #FFD36B on the #F4F7F5 canvas (res_codes_v2.dart:165-166, :176), so the tile looks blank. Server holds the code (trg_withhold_swap_next_codes, release_my_door_codes).  
Fix: Same as G-409.  
Server: yes(withhold_swap_next_codes / release_my_door_codes).

**G-411 · S-095 / S-104 Access codes card / Reservation detail / Reservation detail (codes card) /…** — Self-service branch: the bike code is already issued but the handover protocol is not signed; the kiosk will not open the bike box without the signed protocol, so a note under the code says to sign the protocol first (o…  
Path and proof: Self-service branch, motorcycle code sent, protocol not signed: the only place that says the bike will not open until the protocol is signed is a meta-size warnDark sub-line on the light canvas (res_codes_v2.dart:120, :167-168). Old look: bold amber on white (res_access_codes_card.dart:133-136). Kiosk enforces protocol_required.  
Fix: Draw the sub-line in MgColors.warn with an icon and w700, or apply the dark container fix of G-409.  
Server: yes(kiosk protocol_required, CONTRACT §28).

**G-451 · S-104 Access codes card** — Customer has not uploaded valid ID/licence: the code is withheld and instead of the number the card shows the reason (e.g. documents missing / licence expires before the end).  
Path and proof: Door code withheld for missing documents or a swap: the reason label (#FFFFFF), reason (#FFD36B), lock (warnDark) and 6 % white tile are drawn on the light canvas (res_codes_v2.dart:164-185); for missing documents the neon CTA still says what to do, for a swap nothing readable explains it. Server withholds the code.  
Fix: Same as G-409 (dark panel around ResCodesV2 or a light variant).  
Server: yes(trg_zz_door_codes_docs_gate + booking_docs_gate; release_my_door_code…).

**G-453 · S-104 Access codes card** — Branch with a gate (Velké Němčice): the gate key-box code is shown only after the server has issued the bike code, with a hint how to use it, and the codes are ordered gate → locker → bike as entered on site.  
Path and proof: Gate, locker and bike codes: label #FFFFFF (res_codes_v2.dart:164), gate hint #B8D4C6 (:168), 30 px digits neon #74FB71 (:196) on #F4F7F5. The actual codes the customer types at the kiosk are hard to read. Traced in code only.  
Fix: Same as G-409.  
Server: yes(get_booking_gate_info returns gate_code only with an issued bike code…).

**G-454 · S-104 Access codes card / Reservation detail – access codes** — Customer brings own gear: no locker code is expected; the card says so instead of leaving the customer to look for a missing locker code.  
Path and proof: Own gear, no locker code: the 'no locker needed' row is onDarkLead #CFE7DA text in a 35 % neon outline on the light canvas (res_codes_v2.dart:122-138); the customer may think the locker code is missing.  
Fix: Same as G-409.  
Server: yes(_booking_needs_locker in auto_generate_door_codes — STATE_3:161).

**G-455 · S-104 Access codes card / Reservation detail – access codes** — Codes cannot be loaded (offline, weak LTE): the customer gets the reason, 'Zkusit znovu', 'Zprávy od MotoGo' (codes are also sent there) and 'Zavolat'; codes loaded earlier stay visible.  
Path and proof: Door codes fail to load: ResCodesV2.error (res_codes_v2.dart:88-108) draws the white title, onDarkBody reason and dark MgBtnText labels on the light canvas; Retry, Messages and Call still work when tapped but are nearly unreadable.  
Fix: Same as G-409; in a light variant use the light MgBtnText style.  
Server: no.

**G-458 · S-105 Self-service pickup procedure** — The step-by-step pickup procedure is offered only for a reserved/active, upcoming/active booking at a SELF-SERVICE branch with pickup at the branch (not delivery).  
Path and proof: Booking at a self-service branch: the only call site (res_detail_tab_content.dart:247) never passes cta:true, so ResProcedureV2 draws the 'Postup při vyzvednutí' link in neonText #A8FF9F on #F4F7F5 (res_procedure_v2.dart:83-99), about 1.1:1. Old look: white titled card. The customer will likely never open the pickup steps.  
Fix: Draw the non-CTA link in MgColors.link or ink (res_procedure_v2.dart:89-96), or wrap it in a white bordered row like other v2 detail cards.  
Server: no.

**G-459 · S-105 Self-service pickup procedure** — Procedure content adapts: gate step only for a gate branch (with the code once issued), locker steps only when the customer rents gear (needsLocker mirrors DB _booking_needs_locker), otherwise 'no locker' step.  
Path and proof: The gate/locker/no-locker pickup steps are correct in the sheet (res_procedure_v2.dart:37-43) but reachable only through the near-invisible link of G-458.  
Fix: Same as G-458.  
Server: yes(_booking_needs_locker decides locker code issue — STATE_3:161).

**G-460 · S-105 Self-service pickup procedure** — Gate branch: an 'IMPORTANT' warning (close the gate / return the key etc.) is shown with the procedure.  
Path and proof: Gate branch 'DŮLEŽITÉ' warning (res_pickup_procedure.dart:78) is drawn clearly inside the sheet (res_procedure_v2.dart:44-62) but the sheet opens only from the near-invisible link of G-458.  
Fix: Fix the link (G-458) and show a small warn chip next to it when important != null.  
Server: no.

**G-461 · S-106 Rating card + ride feedback sheet / Reservation detail – rating** — Rating is offered only for a finished booking (status Dokončené), not for upcoming/active/cancelled ones.  
Path and proof: Finished booking detail: res_detail_tab_content.dart:251 passes RatingLook.dark, so ResRatingDarkV2 draws the title #FFFFFF, question, empty stars (white 25 %) and hint on the light canvas (res_rating_dark_v2.dart:46-104); the rating card is practically invisible. Home uses the light look and is fine.  
Fix: Pass RatingLook.light for v2 at res_detail_tab_content.dart:251, or wrap the dark view in a MgColors.panel container.  
Server: no.

**G-463 · S-106 Rating card + ride feedback sheet** — After rating, every customer (1★ or 5★) gets the same two choices in the same order — Google review and a private message to the team (no review gating). They are hidden until a star is chosen.  
Path and proof: After rating, the Google review and private feedback tiles (res_rating_dark_v2.dart:107-171) use white-on-light colours; the separate 'reviewOnGoogle' button of 4.1.3 was removed, so both choices are effectively invisible in the v2 detail.  
Fix: Same as G-461.  
Server: no.

**G-1040 · S-213 Recording controls card** — The server does not accept the new ride (offline / error): start is rolled back, points of the failed attempt are dropped, customer told it failed.  
Path and proof: Start a ride recording without internet: rollback is shared (ride_recorder.dart:317-331) but the v2 failed sheet (ride_results_v2.dart:79-85) says v2UxRrFailW 'Něco se pokazilo v telefonu… restartuj appku' instead of eoRideStartFailed 'nejspíš chybí internet… až budeš mít signál'. The customer is told the wrong cause.  
Fix: Use why: tr('eoRideStartFailed') at ride_results_v2.dart:83 (exists in all languages) or reword v2UxRrFailW to name the missing signal.  
Server: yes(start_user_ride / create_manual_ride).

**G-1041 · S-213 Recording controls card** — A new ride cannot start while the previous ride's stop is still unsaved (offline): the app first tries to save it, otherwise refuses.  
Path and proof: Start a new ride while the previous one still waits to be saved without a connection (ride_recorder.dart:231-237): same v2 failed sheet with the wrong 'phone/restart' explanation as G-1040.  
Fix: Fixed by the G-1040 change.  
Server: no.

**G-1046 · S-213 Recording controls card** — After a safety pause (phone at home / long pause) the recording asks the customer to decide: continue the trip or end and save.  
Path and proof: Phone left at home or a long pause triggers needsDecision: on the Moje tab the v2 bar reads 'POZASTAVENO · od 20:14 · 12 km', the same as a voluntary pause (ride_phase_v2.dart, rec_live_bar_v2.dart:121); the question 'continue or end and save' appears only on the recorder screen/pause sheet. Old look showed the amber decision note on My experiences (ride_rec_controls.dart:276) and relabelled the buttons.  
Fix: In recBarLineV2 return ph.title in the warn colour when rec.needsDecision; optionally relabel Stop as end-and-save.  
Server: no.

**G-1076 · S-219 Trip detail** — While a trip operation runs, all actions are locked (rename, split, delete, share, sharing switch).  
Path and proof: Trip detail: tap 'Rozdělit cestu' and confirm, then while it runs tap trash in the header and confirm 'Smazat i jízdy': _op (trip_detail_screen_v2.dart:62-76) sets _busy but _rename/_split/_delete/_share never check it and the header buttons (ride_detail_parts_v2.dart:113-130) are never disabled; concurrent writes to the same trip. Old _run returned early while busy.  
Fix: Add 'if (_busy) return;' to _rename, _split, _delete, _visibility, _share; make header callbacks nullable and pass null while busy.  
Server: no.

**G-1078 · S-219 Trip detail** — Trip operation failures (partial / server without trips / offline) are reported; success offers Undo.  
Path and proof: In a trip with several rides scroll down, tap 'Rozdělit cestu', confirm while offline: _op only sets _error (trip_detail_screen_v2.dart:68-73), shown as a banner at the TOP of the list (trip_detail_view_v2.dart:103-104), off screen; no toast. Old look showed a snackbar (ride_trip_ui.dart:15-48).  
Fix: In _op on !op.ok also call showTripErrorV2(context, op.result).  
Server: yes(set_user_rides_trip).

**G-645 · S-121 Swap bike tab (Výměna)** — Before confirming, the customer sees whether the swap costs extra, gives money back or costs the same (server dry-run), including the card minimum rule.  
Path and proof: Bike swap with a surcharge: res_edit_swap_v2.dart:222 draws MgIcons.checkCircle for a surcharge (n > 0.5) as for 'no change'; old look used add_card / savings / check icons (reservation_swap_section.dart:639-646). A customer who reads pictures sees an 'all fine' tick next to an extra charge. Payment is still enforced.  
Fix: Use a card/wallet icon when n > 0.5, refresh when n < -0.5, checkCircle only for no change; optionally warn tone for PayRoundingNoteV2.  
Server: yes(split_booking_moto_swap p_dry_run).

**G-657 · S-122 Edit gear / extras section** — The customer ticks 'Mám vlastní výbavu' (own gear); the rider's free size pickers are hidden and no rider sizes are saved.  
Path and proof: Reservation edit, 'own gear' option OFF: res_edit_sections_v2.dart:239 draws MgIcons.check (a bare tick, mg_icon_paths.dart:26) for OFF and checkCircle for ON; the old look drew an empty box (reservation_edit_extras_section.dart:462). The picture suggests own gear is already chosen and the customer may skip rental gear sizes.  
Fix: Draw an empty bordered box when ownGear is false and the tick only when true.  
Server: yes(trg_bookings_own_gear_normalize on INSERT; trg_sync_locker_code on ow…).

### Minor — 26

**G-346 · S-001** — The customer taps the tab that is already highlighted (for example "Rezervovat" while filling the booking form at /booking or sitting on /payment, or "Rezervace" inside a reservation detail); in the old look the tap doe…  
Path and proof: On /booking (half-filled form) or /payment with no payment running, tap the highlighted Motorky tab: AppShellV2._onTab (app_shell_v2.dart:137-151) treats only the exact tab root as reselect and calls onShellTabTap with isActive:false (:149), so the app jumps to /search; same for the Rezervace tab inside /reservations/:id/edit. Old look ignored a tap on the highlighted tab (shell_tab_action.dart:42-47). Running payment still asks for confirmation; the v2 draft is kept.  
Fix: In AppShellV2._onTab after the reselect check: if (i == v2TabIndexFor(path)) return; (or pass isActive accordingly).  
Server: no.

**G-350 · S-002** — MotoGo24 publishes an announcement in Velín (app_settings.header_banner, e.g. closure, weather, outage); the old look shows it as a scrolling coloured band at the very top of every shell screen, in the colours chosen in…  
Path and proof: Velín announcement banner with custom colours (for example red): v2 MgTopBanner (mg_top_banner.dart:22-26, :53, :65, :84) ignores banner.bg/color and always paints neon on night, and folds away on scroll (:67); old ShellHeaderBanner used the Velín colours as a fixed strip (shell_banner.dart:9-24).  
Fix: Give MgTopBanner optional bg/color and pass banner.bg/banner.color from app_shell_v2.dart:215, home_header_v2.dart:128 and motorky_header_v2.dart; optionally folded:false.  
Server: no.

**G-490 · S-129 Verification status card** — Nothing uploaded at all (no ID/passport and no licence): explicit warning that the motorcycle can be booked but the key-box code comes only after verification, plus the gate's 'Chybí' line.  
Path and proof: My documents with neither ID/passport nor licence: v2 draws an info-tone banner titled 'docsStatus' (docs_view_v2.dart:138-148) instead of the old amber '⚠ docsNotVerified' box (documents_screen.dart:226-240); the consequence (no key-box code) is only body text. The top warn banner (docs_view_v2.dart:238-242) still states the unverified status.  
Fix: Use tone: MgTone.warn and title: tr('docsNotVerified') at docs_view_v2.dart:142-143.  
Server: yes(trg_zz_door_codes_docs_gate withholds codes, STATE_4:42).

**G-545 · S-144** — When the back of the driving licence shows a different licence number than the front, the side still succeeds but the customer is warned to re-photograph both sides.  
Path and proof: Scan result with a licence-number mismatch: scan_states_v2.dart:21 strips the ⚠️ and :117-120 draws all notes in one style, under a green ok disc (:96) and the success heading (:107), so the warning looks like the success line. App-only check.  
Fix: Record lines starting with ⚠️ before stripping and draw them as warning rows (warn icon + MgColors.warn); switch the disc to warn when a warning exists.  
Server: no.

**G-546 · S-144** — When saving the recognised data to the profile fails, the side succeeds (photo stored) but the customer is told some data must be filled in manually.  
Path and proof: Same as G-545 for the saveWarning text (photo saved but data not written).  
Fix: Same fix as G-545.  
Server: no.

**G-752 · S-156 Permissions screen / Profile – permissions** — During an active or paid upcoming reservation every permission except photos is marked as required, and a denied required permission is highlighted.  
Path and proof: Permissions screen: a required but missing permission row has no red frame/tint and its 'Vyžadováno' chip is warn instead of red (permissions_view_v2.dart:118-152). Warning only.  
Fix: Use MgTone.err for the required chip and errBg/errBorder for the row when attention is true.  
Server: no.

**G-102 · S-032 Home screen (Domů)** — From Domů the customer can only reach the booking form through the bike detail, where REZERVOVAT stays disabled until a date is chosen and a red ValidationBanner warns about licence, overlap with own bookings and min/ma…  
Path and proof: Logged-in customer with no licence group, an overlapping own booking, or a bike whose minimum rental is longer than the funnel weekend taps REZERVOVAT on a Home funnel card; home_funnel_v2.dart:209-217 -> booking_entry.dart:80-90 push the form directly without ValidationBanner; funnel_provider.dart:108-133 skips licence when groups empty and ignores overlap/min-max. The form still blocks (booking_form_widget.dart:548-554, :582; BookingWarningsV2 booking_form_view_v2.dart:262-272).  
Fix: Render ValidationBanner(moto, range) under the centred funnel card above REZERVOVAT (as calc_step_dates_v2.dart:108); optionally drop bikes whose min/max days do not fit the range in homeEligibleMotos.  
Server: yes(trg_check_booking_overlap, trg_check_user_booking_overlap, trg_check_…).

**G-125 · S-039 Motorcycle list cards** — The 'DNES VOLNÁ' badge appears only when today's availability was confirmed (fail-closed, service blocks count).  
Path and proof: Customer picks new dates on Motorky or Home; while filteredMotorcyclesProvider reloads (skipLoadingOnReload, motorky_screen_v2.dart:184-187, home_bike_list_v2.dart:74-76) every old card shows 'Volná v termínu' computed from the NEW filter (motorky_screen_v2.dart:236-243, home_bike_list_v2.dart:79,101-102), including busy bikes. Booking a busy range is still blocked on the detail and form.  
Fix: Show the 'Volná v termínu' pill only when hasDates && !motosAsync.isLoading (motorky_screen_v2.dart:242, home_bike_list_v2.dart:101-102).  
Server: no.

**G-145 · S-050** — Loading the bikes fails (offline, timeout, server, permission); the customer gets the reason, Retry, Back, 'open settings' for permission problems and a 'Call MotoGo' button for server/unknown errors.  
Path and proof: Bike list fails with a server/unknown error while the bike detail is open; v2 MgStateScreen (moto_detail_page.dart:196-213) has Retry and Back but no tappable call button; the old MgErrorView offered eoCall (state_views.dart:261-265). The number is only in the body text.  
Fix: Add MgBtnText(eoCall, phone icon, callMotoGo) to MgStateScreen.children when FriendlyError.of(e).suggestContact (pattern of legacy_state_looks.dart:48).  
Server: no.

**G-153 · S-045** — The chosen range overlaps the customer's own active or upcoming reservation (cancelled/completed and own unpaid pending draft ignored; kids bike exempt).  
Path and proof: Same as G-152 for an overlap with the customer's own booking: amber mid-sheet banner, active sticky dock CTA; Home funnel goes straight to the form without overlap check (funnel_provider.dart:108-133) and appears even with an overlapping UNPAID booking (home_screen_v2.dart:98-103). Form blocks (booking_provider.dart:299-304) and server refuses (trg_check_user_booking_overlap).  
Fix: Same dock warning as G-152; in the funnel show ValidationBanner or skip bikes where BookingValidator.checkOverlap returns an error.  
Server: yes(trg_check_user_booking_overlap).

**G-154 · S-045** — The chosen range is shorter than the bike's minimum or longer than its maximum rental length.  
Path and proof: Same as G-152 for min/max rental days; homeEligibleMotos/funnelCandidatesProvider (funnel_provider.dart:108-165) ignore minRentalDays/maxRentalDays, so a weekend funnel card can offer a bike with a longer minimum. Only the form blocks (rentalLengthValidationProvider). No server rule.  
Fix: Same dock warning as G-152; in the funnel skip bikes whose min/max days do not fit.  
Server: no.

**G-165 · S-051 / S-072** — The customer taps "Pokračovat k platbě" while anything is still missing: no dates, unknown availability, a validation error (licence, overlap, rental length, pickup time), an incomplete profile, missing gear sizes or un…  
Path and proof: The CTA lock canProceedNow (booking_form_widget.dart:536-556) is shared and the v2 dock honours it (booking_dock_v2.dart:138-145), but through the same-bike carry the consent part is already satisfied on re-entry, so the CTA unlocks without new ticks (duplicate of G-159/G-228-230).  
Fix: Same as G-228: reset the three consent flags in carryBookingDraft.  
Server: yes(server re-checks only some parts: trg_check_booking_overlap, trg_chec…).

**G-207 · S-061 / Booking form (extras)** — Trailer is offered only when a free trailer exists for the dates, never for a kids bike and never on a self-service branch.  
Path and proof: Tick the trailer, leave the form, someone else books the trailer for overlapping days, re-enter on the same bike and same dates: carry keeps extras and trailerMotoId (booking_carry_v2.dart:42-43) and _buildTrailerTile skips the availability check when selected (booking_form_extras_section.dart:367-375). The server trigger trg_check_trailer_overlap refuses at payment and payment_screen_problems.dart:500 shows 'trailer taken'.  
Fix: Always drop the trailer in carryBookingDraft (extras: _noTrailer, trailerMotoId: null), even for the same dates.  
Server: yes(get_trailer_availability RPC + trg_check_trailer_overlap).

**G-228 · S-067 / Booking form / Booking form (consents)** — Consent to terms (VOP) is required; without it the booking cannot continue.  
Path and proof: Re-entry to the same bike keeps consentVop=true from the earlier unpaid draft even with new dates (booking_entry.dart -> booking_carry_v2.dart:35-44); the old look always started false (booking_models.dart:84). No server consent check; the box is visibly ticked; carry was an owner decision (booking_carry_v2.dart:9-12).  
Fix: Add consentVop: false to the same-bike copyWith; if the owner keeps the carry, show a note in BookingConsentsV2 that the consent was taken over.  
Server: no.

**G-229 · S-067** — Consent to personal data processing (GDPR) is required.  
Path and proof: Same mechanism as G-228 for consentGdpr (old start false, booking_models.dart:85). No server check.  
Fix: Add consentGdpr: false to the same-bike branch of carryBookingDraft.  
Server: no.

**G-231 · S-067** — Consents always start unticked on every new booking entry - the customer has to tick them for each booking.  
Path and proof: Summary of G-228-230: BookingConsentsV2 (booking_consents_v2.dart:44-49) shows all three boxes ticked on re-entry to the same bike, canProceedNow passes (booking_form_widget.dart:537-539), and the 'v2BkConsentsNeed' hint (:50) only appears while a box is unticked, so nothing says the ticks were carried over.  
Fix: Add consentVop/consentGdpr/consentKids: false to the same-bike copyWith; or at least reset consentKids on date change and show an amber 'taken over' line.  
Server: no.

**G-268 · S-075 Bike gallery + price summary + server price note** — The loyalty discount line carries a small note that the rank discount is valid only for app bookings.  
Path and proof: The grey note 'loyaltyAppOnly' under the loyalty discount row (price_summary.dart:108-115) is missing in v2 BookingPriceV2 (price_v2.dart:77-85). Information only; server enforces trg_validate_app_loyalty.  
Fix: Add a meta-coloured Text(tr('loyaltyAppOnly')) after the loyalty row in price_v2.dart when bd.loyaltyDiscount > 0.  
Server: yes(trg_validate_app_loyalty).

**G-822 · S-169 Product detail** — The customer tries to add a product that has sizes to the cart without choosing a size first; the add is refused.  
Path and proof: E-shop product that needs a size, size section scrolled out of view, tap 'add to cart' in the fixed dock: v2 only sets _sizeHint (product_detail_screen.dart:42-44) shown inline under the chips (product_view_v2.dart:150-153); no toast, no scroll, so the tap seems to do nothing. The block holds (:41).  
Fix: Also show showMgToastRich(sizeLabel, selectSizeFirst) or Scrollable.ensureVisible on the size section.  
Server: yes(create_shop_order rejects a size that is not in products.sizes with b…).

**G-393 · S-092** — SOS badges on the card photo tell an SOS replacement bike ("🏍️ SOS", green) apart from a rental ended by SOS ("🆘 SOS", red).  
Path and proof: Reservation list: a replacement bike after SOS and a rental ended by SOS both show one 'SOS' chip with the same label (reservation_card_v2.dart:181-190); only icon/border colour differ. Old look had two distinct pills (reservation_card.dart:110-128). Information only.  
Fix: Use MgIcons.moto for the replacement and MgIcons.sos for ended-by-SOS, or the existing texts replacementForSos / endedBySos as labels.  
Server: no.

**G-456 · S-104 Access codes card** — Codes are loading: the card title shows a spinner so the customer knows codes are coming (not missing).  
Path and proof: Door codes loading: the 'accessCodes' title is #FFFFFF on the canvas (res_codes_v2.dart:80-87); only the icon and spinner show. Blocks nothing.  
Fix: Same as G-409.  
Server: no.

**G-1038 · S-212 My experiences** — Ride and trip cards show a recording badge while that ride is being recorded.  
Path and proof: Phone records a ride offline (or the server closed it while the phone still records): v2 ride cards decide the recording badge only from ride.isRecording (ride_card_v2.dart:39, :73; ride_trip_card_v2.dart:45, :70); the old cards also used the local recorder (ride_card.dart:44-54). Information only.  
Fix: live = ride.isRecording || (rec.recording && rec.rideId == ride.id) in both v2 cards.  
Server: no.

**G-1043 · S-213 Recording controls card / Ride recording** — Double tap lock: in the old card the start/stop/pause buttons are locked while an action runs (busy, half-transparent).  
Path and proof: Double tap on the pause disc in the Home record row, live bar or pause sheet: v2 controls call toggleManualRide / rideTogglePauseV2 directly without a busy lock (home_record_row_v2.dart:116,174-185; rec_live_bar_v2.dart:84,87; ride_pause_sheet_v2.dart:52-65; rec_widgets_v2.dart:64,106); the second tap undoes the pause, a double tap on start can show a spurious 'Záznam se nespustil'. Old controls had _busy (ride_rec_controls.dart:245-254).  
Fix: Add the _busy/_run wrapper of recorder_screen_v2.dart:49-59 to HomeRecordRowV2, TrasyRecordDockV2, RecLiveBarV2 and RidePauseSheetBodyV2.  
Server: no.

**G-1045 · S-213 Recording controls card** — The card explains that a rental recording ends by itself when the motorbike is returned.  
Path and proof: Rental recording on the Moje tab: the live bar shows Pause but no Stop and no reason (rec_live_bar_v2.dart:86-89, 116-124); the old look said rpRentalEndsHint under the buttons (ride_rec_controls.dart:284-287). Information only.  
Fix: When recording && !manual && !canStop add one meta line tr('v2RpRentalEnds') under the bar on the Moje page.  
Server: no.

**G-1065 · S-216 Ride detail** — 'Add to trip' is offered only when trips are available; 'Remove from trip' is locked while running and reports the result with Undo.  
Path and proof: Ride detail, 'Odebrat z cesty' tapped twice quickly: ride_trip_row_v2.dart:42-50, :97 have no busy flag; two set_user_rides_trip calls and two toasts. Same server result.  
Fix: Make RideTripRowV2 stateful with a _busy flag and pass onTap: _busy ? null : remove.  
Server: yes(set_user_rides_trip, own rides only).

**G-1087 · S-220 Merge rides into a trip** — Merging into an already named trip pre-fills that trip's name in the name dialog (so it is not lost).  
Path and proof: Merge a named trip with a single ride in v2: askTripNameV2 opens empty (ride_merge_v2.dart:68) instead of pre-filled with the existing name (ride_merge_screen.dart:66-70); Save on the empty dialog drops the custom name (ride_trip_api.dart:73-85). Undo toast and rename exist.  
Fix: Compute the first explicit trip name of the chosen items and pass initial: existing to askTripNameV2.  
Server: no.

**G-783 · S-162 Loyalty ranks** — Point threshold shown per rank ('od X bodů').  
Path and proof: Loyalty ladder: v2 computes the rank threshold as 2*level-2 (loyalty_ladder_v2.dart:74, :140; loyalty_status_parts_v2.dart:75) instead of loyalty_levels.min_booking_order (loyalty_levels_provider.dart:36); with seed values every label is one lower ('od 2' vs 'od 3'). Information only; v2 may match the server formula in get_loyalty_status; live table values not read.  
Fix: Owner decision: print level.minBookingOrder for strict parity, or fix the DB column/old label if 2L-2 is correct.  
Server: yes(get_loyalty_status: level = ceil((points+1).

Downgraded after challenge (now HOLDS, kept here for the record): G-327 (only wording of the 'synced' line), G-347 (Home tab keeps the draft — owner decision; dates are never carried), G-412 (protocol banner removed for both looks in commit 3e872afe), G-416 ('Znovu rezervovat' keeps the searched dates — owner decision, dates still checked), G-481 (missing-documents line is covered by the warn banner and CTA above it), G-1084 (merge screen has no own server check but every entry point has it).

## Part C — safeguards that hold but are told only in small text or not at all in the new look

These 242 safeguards still block correctly, but the customer learns about the block only from body text (`small`) or not at all (`silent`). The owner said people look at pictures and headings, not text — so these are candidates for a heading, an icon, a coloured banner or a greyed button. Most of them were equally unclear in the original look (no regression). Marked ★ = core money/rental step (documents, ordering, paying, before pickup, changing a booking).

**Getting in (intro, onboarding, login, registration, password reset)** (15)

- `G-048` A logged-in customer cannot stay on the reset screen, except while a password recovery is in progress (verified code, step 3 pending); leaving the screen clears that exception. — old silent, new silent
- `G-050` A session exists but the profile row is missing (account deleted while logged in) and the account is older than 2 minutes; the app signs the customer out so they cannot use an empty account. — old silent, new silent
- `G-052` The customer taps Register from login; an e-mail that belongs to the remembered (existing) account is NOT carried into registration, only a newly typed or verified-unknown e-mail is. — old silent, new silent
- `G-053` The fingerprint / Face ID button appears only when the phone has biometrics, a stored biometric user exists and biometric login is enabled; otherwise the customer cannot use it. — old silent, new silent
- `G-054` The biometric prompt is cancelled, fails, is locked out, not enrolled or unavailable; the app does not log in. — old small, new small
- `G-063` Step 1: date of birth not chosen (all three of day/month/year needed). — old small, new small — idea: Optional: give the v2 date of birth dropdown a red outline when m.errors['dob'] is set (register_steps_v2.dart _date) so it matches the other fields; the block itself already hold…
- `G-064` Step 1: customer younger than 18 years; registration is refused. — old small, new small — idea: Optional: red outline on the v2 date of birth dropdown when the error is set; text 'Registrace je možná od 18 let' already shown under it.
- `G-065` Step 1: date of birth gives an age above 99 or lies in the future. — old small, new small — idea: Same optional red outline on the date dropdown.
- `G-084` Step 1: the e-mail is empty or has no '@'; no code is sent. — old small, new small
- `G-086` Step 1/2: the code is requested again within 60 seconds for the same address; the server silently sends no new e-mail but answers success. — old silent, new silent
- `G-087` Step 1: an unknown e-mail is not revealed; the flow continues to the code step but no code arrives, so the customer cannot get further. — old silent, new silent
- `G-088` Step 2: fewer than 8 digits typed; the code is not checked. The field accepts digits only and at most 8. — old small, new small
- `G-092` Step 3: new password shorter than 8 characters; it is not saved. — old small, new small
- `G-093` Step 3: the two new passwords differ; nothing is saved. — old small, new small
- `G-097` A customer who is not logged in follows a link to the bike list, a bike detail, the shop, the cart, the voucher page, My documents, the document scanner, branches, routes or the AI agent; these paths… — old silent, new silent

**Documents and profile (my documents, scanner, profile, permissions)** (28)

- ★ `G-477` A customer who is not signed in opens /docs (deep link, old bookmark); the route is NOT in the login-required list, so the screen opens, but every data source refuses to act without a session. — old small, new small — idea: No v2-specific fix. Pre-existing gap in both looks: optionally add Routes.docs to _authRequired (affects both looks, so only with owner approval).
- ★ `G-481` Warning that BOTH documents are needed to book; shown only while ID/passport or licence is missing. — old small, new small — idea: In docs_view_v2.dart:77-80 render the line as a warn-tone strip (MgStateBanner tone warn or a tinted box with the warning icon) instead of plain small grey text, keeping the same…
- ★ `G-506` The list shows only real documents of this customer: contract, handover protocol, damage protocol, VOP; template-prefilled protocols (not signed) and other types (invoices, gdpr) are filtered out. — old silent, new silent
- ★ `G-521` A customer who is not logged in opens /docs/scan (deep link /app/docs/scan); the route itself is not login-protected, but every photo upload is refused without a session. — old small, new small — idea: Optional (same as old look): when uploadResult.errorDetail == 'not_authenticated', show a 'Přihlaste se' heading and button to /login in ScanResultV2 instead of the generic save-f…
- ★ `G-527` The "Jen řidičák" (licence only) option is not offered when the plan says the identity document is still missing (missing / missing_id modes), so the customer cannot skip the ID. — old silent, new small — idea: Not a regression. If the owner wants ID never skippable in 'missing' mode, change idPlan in doc_scan_plan.dart to offerDlOnly:false (shared logic, v2-only entry), but that goes be…
- ★ `G-533` Every side can be skipped (Skip under the shutter); skipping is not blocked on the spot but the missing side is reported at the end and door codes stay withheld. — old small, new small
- ★ `G-535` When OCR could not read the required fields of a side, the side still passes (photo stored, mindee_status failed for staff review) and the customer is told that codes come only after all sides and va… — old small, new small
- ★ `G-536` When the app goes to background the camera is released and only re-opened on return if a document type is chosen and there is no camera error (prevents a crash on a disposed controller). — old silent, new silent
- ★ `G-548` "Try once more" resets the attempt counter of that side, so the customer can keep retrying after talking to support. — old small, new small
- ★ `G-549` The attempt counter is per side and is cleared when that side succeeds. — old small, new small
- ★ `G-554` The scanner calls verify_customer_docs at the end, but its result (name/DOB/licence mismatches) is ignored and errors are swallowed; the customer is never told about a mismatch here. — old silent, new silent — idea: Not a v2 regression; nothing to change in v2. (If ever desired: surface mismatches from verify_customer_docs, but that changes behaviour of both looks.)
- ★ `G-556` The "Scan complete / verifying" screen is never reached: _stepIdx is never moved past the last step, so during _finalize the camera screen stays with the shutter (a no-op, camera disposed) and Skip s… — old silent, new silent — idea: Pre-existing in both looks (outside v2 scope): a bool _finalizing guard at the top of _finalize, or setState(_stepIdx++) before _finalize so the verifying screen (old _doneScreen…
- ★ `G-729` The customer taps "Osobní údaje" before the profile has loaded (or after a load error); the form does not open, because an empty form saved would wipe the data. — old small, new small — idea: None required (same toast as old). Optional: show the Upravit button dimmed while !ready so the state is visible from the button.
- ★ `G-732` The customer picks a driving-licence expiry: years start at the current year (an already saved expired year stays visible so it can be corrected). — old silent, new silent — idea: None required (silent in both looks).
- ★ `G-734` Saving: the licence group is saved by a separate RPC; if that RPC fails the app does NOT say "Saved" but shows an error with Retry (the group decides door-code release). — old small, new small — idea: None required (same snack as old).
- ★ `G-735` Saving fails (offline, server error) or the session has expired; an expired session signs the customer out, other errors show a message with Retry. — old small, new small — idea: None required.
- ★ `G-736` Save is pressed with no logged-in user (session gone between frames); nothing is written. — old silent, new silent — idea: None required (silent in both looks; edge case).
- ★ `G-738` A customer looks for the e-shop in the Profile menu, but the e-shop entry is hidden while the feature flag eshop_visible is off (and also when the flag cannot be loaded or the row is missing). — old silent, new silent — idea: None needed; the old look also hides the row silently by design.
- ★ `G-744` Saving the consents fails; the reason is shown inside the sheet, which stays open with the chosen ticks. — old small, new small
- ★ `G-745` The new password is shorter than 8 characters; it is refused. — old small, new small
- ★ `G-746` The confirmation does not match the new password; it is refused. — old small, new small
- ★ `G-748` The server refuses the change (same password, weak password, re-authentication needed, session gone, offline); the reason stays in the open sheet. — old small, new small
- ★ `G-750` The customer is warned that prices are only shown converted (CNB rate) and that card payments are always charged in CZK; choosing a currency returns to Home. — old small, new small
- ★ `G-754` Turning on fingerprint/Face ID requires a successful biometric check; if the login data cannot be stored the customer is told the session expired; the option is shown only on devices that support it. — old small, new small
- ★ `G-757` Logging out first clears the booking draft, the selected bike and the catalogue filter, so the next person on the phone does not inherit a half-made booking; there is no confirmation dialog. — old small, new small
- ★ `G-759` The customer has an active or upcoming reservation; the account is not deleted and the app says why instead of claiming success. — old small, new small
- ★ `G-760` Deletion fails for another reason or the session has expired; the account is not reported as deleted (auth error signs out, other errors show a message). — old small, new small
- ★ `X-1-05` The customer scans a document; the scan must not overwrite the licence group or licence expiry the customer entered, the back of the licence must not change the number or expiry, the back of the ID w… — old silent, new silent — idea: No v2 fix needed. For the inventory record: state the exact protected fields (group, expiry) and the overwritten ones (name, date of birth, licence number, ID number). Optional: s…

**Choosing a bike and dates (Home, Motorky, filters, calendar, bike detail)** (9)

- `G-099` After filtering, the count line tells the customer how many bikes are left (or that they are loading / failed). — old small, new small
- `G-110` The card warns that the loyalty discount applies only to bookings made in the app. — old small, new small — idea: None needed.
- `G-121` The branch choice offers only branches that are not permanently closed; an unknown stored branch reads as 'all branches'. — old silent, new silent
- `G-122` The power / seat height / torque / weight sliders: hidden when the data has no valid range, the end positions mean 'no limit', a stored value outside the current bounds counts as no limit, the value… — old silent, new silent
- `G-135` Dates have one source (catalogFilterProvider); the calendar reset clears them so the list is never filtered by dates the screen no longer shows. — old silent, new silent
- `G-137` The customer taps a return day earlier than the chosen start day; the tap is ignored. — old silent, new silent — idea: Optional (not required for parity): when a return day before the start is tapped in v2, show the same amber inline note style the v2 calendar already uses for a busy range.
- `G-138` Tapping the same single day a third time clears the selection; the step text under the calendar says what to tap next. — old small, new small
- `G-155` Only a pickup day is chosen (single-day booking); the licence / overlap / length warning is not evaluated in the detail at all. — old silent, new silent
- `G-162` The customer opens the manual but the bike has none; a message says it is not available (the card is always shown). — old small, new small

**Ordering (booking form: dates, times, delivery, gear, extras, promo codes, consents)** (10)

- ★ `G-169` The bike is from a self-service branch but the draft still carries a trailer from a previously chosen staffed-branch bike; the form silently removes the trailer. — old silent, new silent — idea: None needed: the old look is silent too.
- ★ `G-170` Kids bike: passenger gear and passenger boots are not offered at all, and any left over from a previous adult bike are removed. — old silent, new silent — idea: None needed: the old look is silent too.
- ★ `G-171` A size that is not in the offered range (pre-filled from the profile after switching kids <-> adult bike, or XS/5XL+ helmet on a self-service branch) is silently cleared so a size the customer never… — old silent, new silent — idea: None needed: the old look is silent too.
- ★ `G-178` The chosen range is shorter than the bike's minimum or longer than its maximum rental length (motorcycles.min_rental_days / max_rental_days); the form shows an error and locks payment. — old small, new small
- ★ `G-179` No dates are chosen yet; the calendar is open and the payment button is disabled. — old small, new small
- ★ `G-180` The customer picks a pickup time at a staffed branch that is less than 1 hour from now; the form shows an error and locks payment. — old small, new small
- ★ `G-181` The customer chooses delivery to an address and a pickup time less than 6 hours from now; the form shows an error and locks payment. — old small, new small
- ★ `G-182` The customer picks a pickup date/time in the past at a self-service (or unknown) branch; the form shows an error and locks payment. — old small, new small
- ★ `G-204` Customer can only pick a size from the offered range: children's sizes for a kids bike, a narrower adult range on a self-service branch (helmet S–3XL, others max 4XL). — old silent, new silent
- ★ `G-220` Promo dialog: an empty code does nothing. — old silent, new silent

**Paying (payment page, card sheet, result and thank-you pages, saved cards, e-shop and vouchers)** (24)

- ★ `G-239` Back is pressed while an error sheet, dialog or the offline overlay is on top of the payment page; back closes that layer first instead of leaving the payment. — old silent, new silent
- ★ `G-276` E-shop add-ons are offered only when the 'reservation_upsell' feature flag is on and the booking itself meets the 15 Kč card minimum. — old silent, new silent
- ★ `G-277` Add-ons are bundled into the charge and ordered only if the booking alone meets the card minimum; otherwise they are neither charged nor ordered. — old silent, new silent
- ★ `G-278` A product that needs a size cannot be added by tapping the row; a size must be chosen. — old small, new small
- ★ `G-290` Just before the payment is sent to the bank, a 'payment sent' marker is stored (and an edit surcharge is queued), so after a crash or restart the app shows 'Platba se ověřuje' instead of offering a s… — old silent, new silent
- ★ `G-292` The card field is cleared every time the sheet opens, so a wrong card number from the previous attempt is not reused. — old silent, new silent
- ★ `G-311` The document status could not be determined (no booking id, network error in the RPC); the page shows no document card at all and offers only "Moje rezervace" - a customer whose documents are actuall… — old silent, new silent — idea: None needed for parity (gap exists in the old look too): optionally show a neutral 'Zkontroluj doklady v Profilu' step when docs == unknown.
- ★ `G-314` Leaving the result clears the stored outcome so the screen cannot be shown again (empty or stale) later. — old silent, new silent — idea: None needed (same as old look).
- ★ `G-319` Extras bought together with the booking (upsell) are ordered only after the payment is verified, never before. — old silent, new silent — idea: None needed (same as old look).
- ★ `G-320` Stripe says the payment succeeded but the booking state cannot be read (network); the app keeps "verifying" rather than claim success for a possibly cancelled booking. — old small, new small — idea: None needed (same as old look).
- ★ `G-323` A paid booking change (swap / edit) is finished through the paid-change queue: failure turns into a "change failed" outcome, "still completing" shows a toast, done shows the verified outcome. — old small, new small
- ★ `G-324` Manual "Ověřit znovu" while the bank is still processing: a toast says it is still pending (silent when the timer checks). — old small, new small
- ★ `G-334` Setting the priority card fails: an error toast is shown; on success a confirmation toast and the list refreshes. — old small, new small
- ★ `G-335` Deleting a card fails: an error toast; on success a toast and refresh. An old manually saved row without a Stripe id is deleted directly in the table, others through the edge function. — old small, new small
- ★ `G-343` Any other failure closes the sheet and shows "Kartu se nepodařilo uložit"; success shows "Karta uložena" and refreshes the list. — old small, new small
- ★ `G-344` The card field is cleared when the sheet opens so a card typed earlier (e.g. in the payment sheet) does not reappear. — old silent, new silent
- ★ `G-817` The customer browses products; only products marked active in the database are offered (inactive / withdrawn goods never appear). — old silent, new silent
- ★ `G-826` Quantity has no upper limit in the app (not even the stock count); the server refuses more than 99 per line or more than stock. — old silent, new silent
- ★ `G-834` The cart shows the note that the final price is confirmed at checkout (shopPriceNote) under the total. — old small, new small
- ★ `G-845` The checkout is opened with an empty cart (e.g. after the cart was cleared in another place); pressing Pay is refused. — old small, new small
- ★ `G-851` The customer types a code while a gift voucher is in the cart; codes are not allowed for voucher purchases and the code is refused without asking the server. — old small, new small
- ★ `G-852` The same code is entered twice; it is refused. — old small, new small
- ★ `G-853` The code is invalid, expired, used up, a gift / Slevomat voucher, or there is no internet; it is refused with the concrete reason. — old small, new small
- ★ `G-854` A second percentage code is added; two percent codes cannot be combined. — old small, new small

**Before pickup (reservations list, reservation detail, door codes, pickup procedure, cancel, restore)** (19)

- ★ `G-370` The session disappears while the list is open (no current user): the provider yields an empty list rather than someone else's data, and an auth error from the server logs the customer out. — old small, new small
- ★ `G-371` Only the customer's own bookings are offered in the list. — old silent, new silent
- ★ `G-372` While offline, the 5-second automatic refresh of the reservations list and reservation detail is skipped so loaded data stays visible instead of turning into errors. — old silent, new silent
- ★ `G-373` A refresh fails (weak signal) after the list was already loaded: the list stays and a "stale data" strip with Retry is shown, instead of an error page. — old small, new small
- ★ `G-382` A filter with no matching bookings shows the same "Žádné rezervace" block as an empty account, and the chosen filter is remembered across visits (StateProvider, not auto-disposed), so a customer can… — old small, new small — idea: Optional (both looks would differ only if wanted): in v2 _EmptyAll, when filter != 'all' and the unfiltered list is non-empty, add a one-line 'Zobrazit vse' link that sets the fil…
- ★ `G-396` A booking without a photo URL does not crash the list (placeholder instead of an error widget). — old silent, new silent — idea: none needed - a crash guard, silent in both looks by design
- ★ `G-398` Internal guards of the unreachable list dialog: back blocked while cancelling (PopScope canPop !_loading), Zpět and Zrušit disabled with spinner while loading, colour-coded refund preview, result sho… — old silent, new silent
- ★ `G-401` The server refuses storno because the booking is no longer pending/reserved (wrong_status): the app shows the generic failure with Retry, which cannot succeed. — old small, new small
- ★ `G-412` In the released 4.1.3 the detail showed a large green banner "fill in the handover protocol" for a self-service booking in its term until signed (RPC can_fill), opening the in-app protocol. The curre… — old clear, new small — idea: No v2 parity fix needed. Optional (both looks, owner decision): show the protocol reminder in the v2 codes tile as a heading line instead of a sub-line.
- ★ `G-416` Completed booking: 'Znovu rezervovat' clears the old booking draft and selected bike, opens the same bike so the customer chooses NEW dates (availability is checked again downstream), or goes Home if… — old clear, new small — idea: In v2 keep the carried-over dates but still show a toast when hasDates, e.g. 'Termín převzat z vyhledávání: <dates> – můžete ho změnit', so the customer sees which dates are used.
- ★ `G-422` Unused v2 widgets with their own actions exist but are not wired anywhere (e.g. ResCoTedV2 with an SOS button, ResActionTilesV2, ResDocsV2, ResMoneyV2, ResJourneyV2, ResGearV2, ResTitleBlockV2). — old silent, new silent
- ★ `G-424` An unpaid edit surcharge (mod_surcharge_due without mod_surcharge_paid_at) is shown bold in red with its variable symbol. — old small, new small
- ★ `G-427` Only issued documents are listed (draft and cancelled invoices are filtered out). — old silent, new silent
- ★ `G-429` Loading the payment details fails: no message; the tab shows only the rows derivable from the booking already loaded (failed invoice fetch is swallowed). — old silent, new silent
- ★ `G-436` Gear-only bookings are hidden from the app until the owner enables "Zobrazit v aplikaci"; the app cannot create them. — old silent, new silent
- ★ `G-443` Delivery vs branch: the row tells the customer whether the bike is delivered to an address or picked up at the branch. — old small, new small
- ★ `G-449` Timeline: 'Vydáno' (issued) appears only after the bike code was entered AND the handover protocol signed, not just after payment, so the customer is not misled that the bike is out. — old small, new small
- ★ `G-473` Restore refused because the customer already has another booking in that term, the branch is closed, or the trailer is taken. — old small, new small — idea: Optional, both looks share it: in _showRefusal (booking_restore.dart:203-208) give own_overlap / branch_closed / trailer their own title instead of 'motoOccupiedTitle', so the hea…
- ★ `X-2-06` The Google review button opens only an https link on a Google domain (g.page/r/..., goo.gl, google.<tld>); any other value set in Velín (app_settings.google_review_url) is ignored and the built-in li… — old silent, new silent — idea: None needed.

**During the rental (SOS, ride recording)** (32)

- `G-663` The customer wants to open SOS when no rental is running; every in-app SOS entry is hidden unless a reservation is sosAllowed (picked up, or paid and inside its term, and not ended by SOS). — old silent, new silent
- `G-669` Some photos could not be uploaded after the incident was created; the customer is warned to send the rest in Messages. — old small, new small
- `G-672` Only the newest open incident is considered and the banner is hidden while the state is loading. — old silent, new silent
- `G-683` The report reached MotoGo but without GPS; the customer is told to tell the dispatcher where they are. — old small, new small
- `G-697` The customer taps 'Order replacement' without answering whether the bike was secured; the app refuses and asks for the answer. — old small, new small — idea: Optional clarity gain (not a regression): pass hint: tr.tr('theftSelectSecured') to the SosChoicePairV2 at sos_theft_view_v2.dart:68-74 so an unanswered 'was it secured?' shows an…
- `G-699` Unsecured bike is recorded as customer fault (isFault = _secured == false). — old small, new small
- `G-702` 'Done - back to overview' is offered only after the invoice was uploaded. — old silent, new silent
- `G-708` Confirm without choosing a bike is refused. — old small, new small — idea: Optional: in the v2 view, show the dock CTA as visibly inactive (opacity) while selectedId is null, still calling _confirm so that the toast appears.
- `G-709` Confirm without a delivery address is refused (field text must be non-empty; GPS coordinates are added only to an unedited suggestion). — old small, new small
- `G-715` 'Where you are now' fills the address only with location permission and GPS; otherwise it explains why. — old small, new small
- `G-717` 'Replacement bike' is offered only for an active incident of type accident_major, breakdown_major or theft. — old silent, new silent
- `G-718` 'I continue riding' is offered only for an active minor incident (accident_minor / breakdown_minor). — old silent, new silent
- `G-1028` Pull-to-refresh is only offered on the account pages (not on the local navigation history, not when signed out). — old silent, new silent
- `G-1032` Opening a history entry of a custom route whose stored data is missing does nothing. — old silent, new silent
- `G-1035` The Merge rides row is only offered when the server knows trips and there are at least two list items. — old silent, new silent
- `G-1044` A rental (automatic) recording cannot be stopped by the customer: the Stop button exists only for an own manual ride. — old silent, new silent
- `G-1051` In the sheet, Stop is offered only for an own manual ride; a rental shows why it cannot be stopped. — old small, new small — idea: Optional: show the rental hint v2RpRentalEnds in the sheet as a small MgWell with a lock/flag icon instead of meta-grey text, so a rider who looks for Stop sees why it is missing.
- `G-1056` A failed delete is reported instead of pretending success. — old small, new small
- `G-1059` Sharing switch (private / public) is locked while saving; a failed save is reported with retry. A ride stays private until the rider turns it on. — old small, new small
- `G-1060` Editing name/description: Cancel discards, a failed save is reported with retry. — old small, new small
- `G-1062` Deleting the ride that is being recorded: the dialog warns what happens (a rental re-records from now, an own ride stops) and the recorder is detached before delete. — old small, new small
- `G-1063` A failed ride delete keeps the customer on the detail and says so (it used to leave as if deleted). — old small, new small
- `G-1064` Adding a stop by tapping the map / editing a stop goes through the stop editor; the server limits stops and checks ownership. — old small, new small
- `G-1071` Delete is offered only for an existing stop and is ignored while busy (no confirmation in either look). — old silent, new silent
- `G-1073` The share link uses only the longest continuous part of the track (no invented straight line over a gap); no link when fewer than 2 points. — old silent, new silent
- `G-1074` Facebook needs a map link; when there is none, or the target app cannot open, the customer is told sharing failed. — old small, new small
- `G-1077` Visibility switch for the whole trip is locked while saving; failures are reported. — old small, new small
- `G-1081` Deleting a trip that contains the ride being recorded warns what happens and detaches the recorder. — old small, new small
- `G-1084` When the server does not support trips, the merge screen disables selection and the button and shows an amber note. — old clear, new small
- `G-1093` Picking up a rental while an own ride is paused saves the own ride and records the rental; a riding own ride is not interrupted. — old small, new small
- `G-1096` Recorder notices are shown once as a snackbar and then consumed. — old small, new small
- `X-2-03` While a ride is being recorded the app pauses it itself (about 5 min standing or 3 min walking, resumes at about 20 km/h); an own ride standing near its start for 3 h triggers a phone notification; a… — old small, new small — idea: None for parity. Optional: the 20 h reminder is only a 6-12 s snackbar in both looks; a persistent strip state would be clearer for customers who do not read text.

**Changing or cancelling (reservation edit: extend, shorten, move, swap, extras, delivery)** (35)

- ★ `G-560` Before any save the app re-checks that the reservation in the DB is still the one the price was computed against (dates, pickup time, bike, price, late discount, status); if not, it reloads and refus… — old small, new small — idea: None needed (same toast as old look).
- ★ `G-564` The "Posunout" (free reschedule) tab is offered only for a reservation with status reserved, fully paid, and whose start is not in the past; otherwise the tab is simply missing. — old silent, new silent — idea: None needed for parity (old look was also silent).
- ★ `G-570` Running rental (active): a tap before the original start is ignored — an active rental can only be extended at the end. — old silent, new silent — idea: None needed for parity (old look was also silent).
- ★ `G-571` Extending the start earlier: the new start may not be in the past and all days between must be free. — old small, new small — idea: None needed; same handler, message now in a v2 toast (reservation_edit_calendar_section.dart:93).
- ★ `G-572` Extend tab: tapping inside the current reservation is refused with the instruction where to tap. — old small, new small — idea: None needed.
- ★ `G-573` Extending the end: all days from the old end to the tapped day must be free. — old small, new small — idea: None needed.
- ★ `G-574` Shorten tab: tapping outside the reservation is refused. — old small, new small — idea: None needed.
- ★ `G-575` A one-day reservation cannot be shortened. — old small, new small — idea: None needed.
- ★ `G-576` Upcoming reservation: shortening requires first choosing "shorten start" or "shorten end"; without it a tap is refused. — old small, new small — idea: None needed.
- ★ `G-577` Running rental: shortening only moves the end earlier and never into the past. — old small, new small — idea: None needed.
- ★ `G-578` Move tab: a day in the past is refused and the whole shifted range (same length) must be free. — old small, new small — idea: None needed.
- ★ `G-580` Calendar refusal messages are shown to the customer (old: SnackBar 2 s). — old small, new small — idea: None needed.
- ★ `G-583` Move with delivery to an address: new pickup must be at least 6 h from now. — old small, new small — idea: None needed.
- ★ `G-588` Delivery newly chosen (or address changed) without an entered address / computed route fee: saving is refused (otherwise delivery would be free). — old small, new small
- ★ `G-590` Delivery to an address: the (new) pickup must be at least 6 h from now when start, pickup time or method changes. — old small, new small
- ★ `G-595` Self-service return at the branch: return time is not offered (stored 23:59 / kept), so the customer cannot pick an invalid return time. — old silent, new silent
- ★ `G-604` Storno percentage line under the result when days are removed (also at 0 Kč). — old small, new small
- ★ `G-612` For an active rental the gear check is skipped (gear cannot be changed then), so extension is not blocked. — old silent, new silent
- ★ `G-616` New end before new start is refused. — old small, new small
- ★ `G-617` Active rental: changing the start date is refused. — old small, new small
- ★ `G-618` The customer saves a bike change but meanwhile someone else booked that bike (or the availability check fails); the save is refused. — old small, new small
- ★ `G-619` The customer's own other overlapping booking or a branch closure on the new days is not checked in the app; the server refuses and the app shows a generic edit failure sheet. — old small, new small
- ★ `G-620` Extras change refused when the original paid extras could not be loaded (prevents charging an extra twice). — old small, new small
- ★ `G-624` Removing an extra failed on the server → told to the customer (staff will fix). — old small, new small
- ★ `G-625` Trailer rules (trailer only with a bike from a staffed branch; trailer occupied on new dates) refused by DB trigger and translated. — old small, new small
- ★ `G-626` A customer whose booking is already picked up (active), or who is on the 'move' or 'swap' tab, tries to change the bike in the edit form; the 'Change bike' section is simply not shown, so the bike ca… — old silent, new silent
- ★ `G-630` The customer's driving licence group does not cover a bike (e.g. A2 licence, A bike); that bike is not offered in the list at all. — old silent, new silent
- ★ `G-634` The customer switches to a bike standing at a self-service branch while delivery/collection to an address is selected and the feature flag self_service_delivery is off; delivery is switched back to t… — old small, new small
- ★ `G-636` The bike list cannot be loaded; the customer cannot choose any bike. — old small, new small
- ★ `G-638` The customer changes the swap date after choosing a bike; the chosen bike and the price preview are cleared and availability is re-checked from the new date. — old silent, new silent
- ★ `G-643` No bike fits (licence, branch filter); the customer is told there is nothing to swap to. — old small, new small
- ★ `G-646` The server refuses the swap in the dry-run (not paid, wrong status, already split, bike unavailable, licence insufficient, date out of range, forbidden, trailer only at staffed branch, unknown); noth… — old small, new small
- ★ `G-649` The swap is free or gives money back; it is committed with server-side refund. If the answer is lost, the app checks with a dry-run before saying anything; if it still cannot tell, it warns instead o… — old small, new small
- ★ `G-650` The commit fails because of a database rule (trailer only at staffed branch, trailer already taken) or the network; the customer gets a translated reason instead of a raw error. — old small, new small
- ★ `G-654` The bike (also after a bike change) stands at a self-service branch; only the narrower size ranges are offered (helmet S–3XL, jacket/pants/gloves max 4XL). — old silent, new silent

**After the ride (routes, navigation, places, reviews, loyalty, branches, messages, AI)** (56)

- `G-765` 'Rezervovat' on a branch: the branch is pre-selected in the catalogue filter only if the catalogue actually offers that branch (a permanently closed branch is not pre-selected, which would give an em… — old silent, new silent — idea: None needed: it is silent in the old look too (a pre-selection convenience). The server still refuses bookings at closed branches (branch_is_closed).
- `G-768` Each bike row shows the required licence groups (ŘP A2 / A …, 'N' excluded), so the customer sees before opening that a bike needs a licence they may not have. — old small, new small — idea: None needed: the same small spec line as the old look. The licence is enforced again in the bike detail and the booking.
- `G-769` The pickup procedure ('Jak to probíhá') tells self-service customers that without verified documents they get no access codes and cannot enter the branch, and the order of codes (box, wardrobe, bike)… — old small, new small — idea: None needed: the same collapsed text card as the old look.
- `G-771` Branch video is shown only for an https URL; YouTube links or a failed player open externally. — old silent, new silent — idea: None needed.
- `G-774` Permanently closed branches (is_open = false) and inactive branches are never listed in the bikes sheet; seasonal closures still show (only calendar days are blocked). — old silent, new silent — idea: None needed: the same as the old look. The server still enforces branch_is_closed.
- `G-789` Leaderboard opt-in switch is shown only to a customer with a loaded status; switching off warns that they no longer compete for the monthly prize; without a nickname a hint explains how they appear. — old small, new small
- `G-806` Opening or refreshing the thread marks the team's replies as read; an auth error in the realtime stream triggers the shared auth handling (re-login). — old silent, new silent
- `G-807` The assistant is tied to the customer's current paid booking (active preferred over reserved); unpaid or other customers' bookings are never used as context. — old silent, new silent
- `G-808` Sending is refused when there is neither text nor a photo, or while a reply is still pending; a photo-only message gets a default text. — old silent, new silent
- `G-811` Slow reply: after 20 s the typing line changes to 'Ještě přemýšlím…' so the customer does not resend. — old small, new small
- `G-864` Community places that are not yet approved (the customer's own pending suggestions or anyone else's) are not offered in the Places list or map. — old silent, new silent
- `G-869` After building a ride from Places the shared selection is cleared, so it does not come back on another screen; in pick mode the selection is local and never leaks into the shared selection. — old silent, new silent
- `G-871` Switching on 'Nearby' needs an anchor: if the customer has no location and nothing selected, the app first asks for location and does not switch the filter on if it is refused. — old small, new small
- `G-878` The map preview inside the list cannot be dragged (so the list scrolls); tap opens the full map, tap on a place toggles it, long-press on a place opens its detail, long-press on empty map opens 'Add… — old small, new small
- `G-881` In v2 the Places tab header has a '+' button that opens the community add menu (old Places tab had no such button; the menu was reached from the Trasy FAB). — old clear, new small
- `G-883` In pick mode the filter and selection are local, so filters or selections set in the Places tab do not leak into the route editor and vice versa; the shared search text is ignored. — old silent, new silent
- `G-887` Swiping to the next/previous place only works when the sheet was opened with more than one place, and stops at the first/last; the list of neighbours is limited to a window of 150 on each side. — old small, new small
- `G-893` 'Sort near me' needs location: without it the app asks for location and does not switch sorting if refused. — old small, new small — idea: None needed; same location request as old.
- `G-894` 'Sort near chosen route' is disabled until a route has been opened or chosen (no route anchor). — old small, new small — idea: None needed for parity; optional: a one-line hint under the greyed chip in both looks is not required.
- `G-899` Only routes that have at least one place are offered in the route filter. — old silent, new silent — idea: None needed; silent in the old look too.
- `G-901` The map shows only places that pass the same filter as the list (shared filter), without catalogue route lines. — old small, new small
- `G-904` 'My location' needs location: without it the app asks and does not centre if refused. — old small, new small
- `G-905` 'Add place here' button needs the customer's location; without it the customer is told to long-press the map instead. — old small, new small
- `G-909` The '+' action menu: proposing a route or adding a place requires login; a logged-out customer is stopped with a message instead of opening the form. — old small, new small
- `G-911` Sending a place requires login; without it the form refuses. — old small, new small
- `G-912` The place name is required. — old small, new small
- `G-917` If sending fails, the form keeps the data and shows an error (current code adds 'why' and 'Try again'); photos that failed to upload are reported. — old small, new small
- `G-919` Sending a route requires login. — old small, new small
- `G-920` The route name is required. — old small, new small
- `G-921` A route needs at least two points. — old small, new small
- `G-922` Loading points from a link does nothing when the link field is empty, is disabled while loading, and shows an error line if the link cannot be decoded. — old small, new small
- `G-928` Writing or editing a review requires login. — old small, new small
- `G-929` A review needs at least one star. — old small, new small
- `G-934` Star rating on the place requires login; taps are ignored while saving; a failed save reverts the stars and says so. — old small, new small
- `G-944` Default order 'nearest to me' silently falls back to the stable random order when location is not allowed; location is only requested quietly (never forced to Settings). — old silent, new silent
- `G-946` Opening a route remembers it as the anchor for 'sort from chosen route' and passes only the currently filtered siblings for swiping in the detail. — old silent, new silent
- `G-953` The length slider, the time slider and the approach toggle are only offered when the data actually has a usable range (at least two different values). — old silent, new silent
- `G-954` Turning the approach toggle resets length/time to the new full range, so a slider value outside the new bounds can never be applied (and cannot crash the slider). — old silent, new silent
- `G-962` 'Continue' with selected points does nothing if the selection can no longer be resolved to real places. — old silent, new silent — idea: Optional (not a regression): in cont() when pois.isEmpty, clear the selection or show a short snackbar so the v2 CTA is not a dead tap.
- `G-972` If the external navigation app cannot be opened, the customer is told. — old small, new small
- `G-976` Writing or editing a review requires login; a logged-out customer is stopped with a message (from the list sheet and from the detail section). — old small, new small
- `G-977` A review cannot be sent without a star rating. — old small, new small
- `G-979` If the editor somehow has no logged-in user at send time, nothing is sent. — old silent, new silent
- `G-980` A failed send keeps the editor open and tells the customer. — old small, new small
- `G-985` While reviews load the write button in the detail section is not offered; a load error simply shows the empty list (logged). — old silent, new silent
- `G-989` Saving a route for myself requires login. — old small, new small
- `G-990` Suggesting a route to the community requires login. — old small, new small
- `G-991` Save/suggest re-check that the route has at least 2 points. — old small, new small
- `G-992` The name sheet refuses to send without a name. — old small, new small
- `G-994` The server limit of saved routes (200 per customer) refuses saving; the app shows the generic save error. — old small, new small
- `G-997` Points already in the route are not offered again in 'nearby suggestions'; the panel is hidden until there is a first stop and caps the number of cards. — old silent, new silent
- `G-1009` Reopening the same route restores the stops already reached instead of starting over. — old silent, new silent
- `G-1014` Saving a finished custom ride requires login. — old small, new small — idea: Optional: in v2 show the login need as a small state sheet with a Log in button instead of a snackbar; logic unchanged.
- `G-1019` Routing through at most 15 remaining stops per request (API limit) - extra stops are silently left for later recalculation. — old silent, new silent
- `G-1022` After saving, the customer is told whether it worked. — old small, new small — idea: Optional: v2 success/error state sheet instead of snackbar.
- `G-1025` The sheet cannot be opened when there are no stops. — old silent, new silent

**Global locks and floating buttons (overlays, shell, tabs, banners, push, back)** (14)

- `G-002` While the intro, the language or the permission overlay is on screen (or onboarding is not yet evaluated), a loyalty level-up celebration is held back so it cannot play invisibly underneath. — old silent, new silent
- `G-007` 'Přeskočit – nastavím později' is disabled while the permission request is running. — old small, new small
- `G-009` The permission page is shown once: after 'Allow all' or 'Skip' mg_perms_shown is stored and the page never returns. — old silent, new silent
- `G-020` If the version check itself fails (no network, error), the app lets the customer continue (fail-open). — old silent, new silent — idea: None needed: identical fail-open behaviour in both looks and in 4.1.3.
- `G-022` Android flexible update: download runs in the background, then a snackbar for 12 s offers 'Restartovat'. — old small, new small — idea: None needed (same snackbar as old; v2 theme only changes its shape).
- `G-026` The celebration is held back while the payment screen is open (and during onboarding) so it cannot cover or interrupt a payment. — old silent, new silent — idea: None needed (deliberately silent deferral, identical to old).
- `G-027` Checkout is locked: while the payment screen is open the loyalty rank is not refreshed, so the charged price cannot drift from the price already prepared. — old silent, new silent — idea: None needed. Optional hardening: make the new v2 retry buttons call maybeRefreshLoyalty(ref, force:true) instead of ref.invalidate so the payment lock covers them too.
- `G-033` Error toast: what failed + why + one action, chosen in a fixed order (settings, retry, call); for payments/bookings the call action is suppressed (contact:false). — old small, new small — idea: No change needed: same as the old look, which was also a toast.
- `G-355` The unpaid-booking button disappears exactly when the 30-minute payment window runs out (window restarts from restored_at for a booking restored in Velín), mirroring the server auto-cancel, so the cu… — old small, new small — idea: None needed (old look communicated it the same way).
- `G-356` A booking made on the WEB that waits for a bank transfer (QR) is never offered for card payment in the app, which would cause a double payment. — old silent, new silent — idea: None needed (old look equally silent by design).
- `G-365` The documents reminder is hidden on Moje doklady and the scanner (the customer is already there) and on any payment screen; while the status is unknown (loading/error) it is hidden rather than shown… — old silent, new silent
- `X-1-03` The customer taps a notification; the app decides which screen opens by the notification type. — old silent, new silent — idea: No v2 fix needed. Optional for both looks: respect eshopVisibleProvider for 'shop_order' (open Messages when the shop is hidden) and open Reservations when a 'booking' notificatio…
- `X-1-04` Door-code and SOS-answer pushes reach the phone only when notification permission is granted and a customer is logged in; opening the app clears delivered notifications and the icon badge. — old silent, new silent — idea: No v2 fix needed. Optional for both looks: when the customer has an upcoming paid booking and notification permission is denied, show a short hint on the reservation detail that d…
- `X-2-05` When the customer logs in (or the app starts with a saved login), if no language was ever chosen in the app the app silently switches to the profile language; otherwise it silently overwrites profile… — old silent, new silent — idea: None for parity. Optional: show the e-mail/document language next to the language picker in Profile so the customer can see which language his contracts will arrive in.

## Part D — counts

| | count |
|---|---|
| Screens / surfaces with at least one safeguard | 386 |
| Safeguards checked | 1112 (inventory 1097 + 15 added by the critic pass) |
| HOLDS in the new look | 1063 |
| WEAKER | 49 (critical 0, major 23, minor 26) |
| BYPASS (new look reaches the action without the check) | 0 |
| UNCLEAR after verification | 0 (G-436 and G-783 resolved) |
| Hold but told only in small text / silently in the new look (Part C) | 242 (of which ★ core steps 116) |
| Visibility old → new: clear→clear 546, small→clear 87, silent→clear 20, silent→small 6, clear→small 19, small→small 206, silent→silent 211 | |
| Server enforces the same rule on its own | yes 416, no 615, unknown 81 |
| Safeguards only the app protects (server = no) | 615 — of these WEAKER: 26 |

Per step:

| Step | safeguards | weaker | major | app-only (server no) |
|---|---|---|---|---|
| Getting in | 56 | 0 | 0 | 34 |
| Documents and profile | 118 | 4 | 0 | 70 |
| Choosing a bike and dates | 67 | 7 | 2 | 41 |
| Ordering | 73 | 6 | 1 | 43 |
| Paying | 155 | 3 | 1 | 49 |
| Before pickup | 109 | 14 | 12 | 51 |
| During the rental | 134 | 10 | 5 | 82 |
| Changing or cancelling | 106 | 2 | 2 | 39 |
| After the ride | 220 | 1 | 0 | 146 |
| Global locks and floating buttons | 74 | 2 | 0 | 60 |

App-only WEAKER safeguards (no server backup, so the app is the only protection): G-230 (major), G-455 (major), G-458 (major), G-460 (major), G-461 (major), G-463 (major), G-1041 (major), G-1046 (major), G-1076 (major), G-346 (minor), G-350 (minor), G-545 (minor), G-546 (minor), G-752 (minor), G-125 (minor), G-145 (minor), G-154 (minor), G-228 (minor), G-229 (minor), G-231 (minor), G-393 (minor), G-456 (minor), G-1038 (minor), G-1043 (minor), G-1045 (minor), G-1087 (minor).

What could not be determined: rendered contrast was traced in code, not measured on a device (G-409…G-463); live `loyalty_levels.min_booking_order` values were not read (G-783); server enforcement of the 6-hour delivery lead time and the shorten minimum is unknown (G-583, G-590, G-575).
