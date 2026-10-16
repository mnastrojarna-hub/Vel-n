# understand:states — every result, thank-you and error state in the customer app (owner point R2)

**Sources.** The code is from `Motogo-app-main/motogo-app-flutter/lib` (the Android master tree). Its `features/payment/payment_screen.dart` matches the iOS tree; the iOS-only differences are noted inline (Apple Pay). The backend references are:
- `supabase/functions/process-payment/index.ts`
- the live schema snapshot `origin/supabase-live-snapshot:supabase/_snapshot/schema_public.sql`
- the migrations

The Czech texts below are quoted verbatim from `lib/core/i18n`, in the form key = text. I extracted them with a parser over all `translations_*.dart` files: 1,969 keys in every one of the 8 languages. The `PaymentErrorMapper` and `AuthErrorMapper` texts come from their own string tables. All of this is read-only work: nothing in the repo or the DB was changed.

**Owner requirement (R2).** Every result or error must say:
1. what went wrong,
2. why,
3. how to fix it,
4. with a working next action,
5. and it must never hang.

**Column legend.**
- **Surface**: `Sheet` = `PaymentErrorSheet` (a modal bottom sheet with a red ✗, a primary button, an optional secondary button and the support line "Potřebujete pomoc? Napište nám na info@motogo24.cz"). `Toast` = `showMotoGoToast` (default **3 s**, no action). `Snack` = a Material SnackBar (~4 s, no action). `Dialog` = an AlertDialog. `Screen` = a full screen. `Inline` = a text block inside the screen.
- **Hang**: `—` = bounded. `RISK` = an await with no timeout, or a spinner that can stay up. `DEAD` = no way forward except system back or a restart.
- **Gap**: the parts of the owner requirement that are missing. **WHAT / WHY / FIX / ACTION** mark which part is missing, **FALSE** = the message states something untrue, and **i18n** = the text is Czech-only or a raw technical string.

---

## 0. TL;DR — top findings (these feed the code audit)

| # | Severity | Finding | Where |
|---|---|---|---|
| 1 | **P0 money** | **Payments below 15 Kč (the Stripe CZK minimum) are a dead end.** An edit surcharge `effDiff > 0`, a swap `net > 0.5` or a heavily discounted booking always goes to Stripe. Stripe rejects it with `amount_too_small`, and the app shows:<br>• **New card:** "Platbu nelze zpracovat" + the raw "Payment processing failed: Amount must…".<br>• **Saved card:** "Platba kartou zamítnuta" + the raw Stripe English + "Zkuste platbu znovu, použijte jinou kartu".<br>A retry fails the same way. After 3 attempts: "Platba se nezdařila … dokončit později v Rezervacích", which is impossible. Only the shop has a server guard (`below_minimum`), and the app does not map that code either. | `reservation_edit_screen.dart:946`, `reservation_swap_section.dart:252`, `payment_screen.dart:701/832` (`amount.round()`), `process-payment/index.ts:430` (shop only), outer catch `:1170-1188` |
| 2 | **P0 booking** | **A bike taken meanwhile shows a misleading error.** The DB triggers raise Czech texts:<br>• "Překrývající se rezervace pro moto_id …"<br>• "Zákazník má překrývající se rezervaci…"<br>• "Pobočka … zavřená…"<br>• "Kus … přiřazen jako vozík…"<br>`_createDraftBooking` only matches English patterns (`Booking overlap`, `check_booking_overlap`…), so the customer gets "Rezervaci se nepodařilo vytvořit — Při vytváření rezervace došlo k neznámé chybě. **Zkontrolujte připojení k internetu**". That is the wrong cause, and there is no "choose other dates/bike" action. The mapped text `bookingOverlapError` ("Již máte rezervaci…") would also be wrong for a bike-level conflict. | `payment_screen.dart:594-625` (pattern match at :596); live snapshot `schema_public.sql:7090/7227/7614` |
| 3 | **P0 false success** | **SOS "Sdílet polohu" always says "Poloha sdílena".** It says so even when GPS was denied or off, the incident insert failed, or `shareLocation` threw (all `catch (_) {}`). | `sos_report_screen.dart:428-449` (same pattern in `sos_immobile_screen.dart:86-91`, `sos_breakdown_immobile_screen.dart:96-100`) |
| 4 | **P0 safety** | **The offline overlay blocks the whole app**, including SOS, the nonstop phone line, turn-by-turn navigation and the running ride recorder. It is a full-screen `Material` on the root overlay; its only button is "ZKUSIT ZNOVU". Losing signal mid-ride covers the navigation map. The force-update dialog (`barrierDismissible:false`) also has no SOS or phone escape. | `core/offline_guard.dart`, `core/update_check_provider.dart:94` |
| 5 | **P0 double-pay risk** | **Several paths offer a new payment while the old one may still complete:**<br>• **Webhook delay.** `_showProcessingPending` → toast + `/reservations`. The booking is still `pending/unpaid` in the DB, so the "Dokončit rezervaci · M:SS" FAB comes back and offers a new payment.<br>• **Android card / Google Pay sheet.** It can be swiped down while `confirmPayment` is running; that returns `cancelled`, so the pay button is live again. iOS has a `_WalletGuard` for exactly this; Android does not.<br>• **Shop "processing not confirmed".** It stays on checkout with the pay button active, and the next tap creates a **new order** and a new charge. | `payment_screen.dart:1112`, `widgets/card_payment_sheet.dart:41` (Android) vs the iOS `card_payment_sheet.dart:52-79`, `shop_checkout_screen.dart:322-339` |
| 6 | **P1 false text** | **"No money charged" is claimed where it is unknown:**<br>• **Timeout.** A 30 s timeout of the saved-card charge maps to `network` → "žádné peníze zatím nebyly strženy", but the server may already have charged.<br>• **Unexpected status.** `off_session_unexpected_status` (for example `processing`) maps to the generic "Platbu se nepodařilo dokončit a žádné peníze nebyly strženy". | `stripe_service.dart:138`, `payment_error_mapper.dart serviceError`, `process-payment:968` |
| 7 | **P1 mapping** | **The off-session `error_code` is dropped.** `PaymentResult.offSessionFailed` takes `errorCode` but never stores it, so `expired_card`, `incorrect_cvc`, `authentication_required`, `amount_too_small` and `processing_error` from the saved-card path lose their specific message. Separately, **a failed or cancelled 3-D Secure on a saved card** shows the generic "Platba se nezdařila — nic nebylo strženo" and counts as a failed attempt. The mapper has `authTitle/authBody`, but this path never uses them. | `stripe_service.dart:425-436`, `payment_screen.dart:793-797` |
| 8 | **P1 dead ends** | **Several states leave the customer with no way forward:**<br>• `ErrorWidget` "Restartujte aplikaci / Omlouváme se za komplikace." has no button.<br>• The scanner camera error "Chyba kamery: CameraException(…)" has no "open settings", retry or gallery action.<br>• Navigation with GPS denied shows only a text card, and `ensurePermission` silently jumps to system settings.<br>• `/profile` and product-detail load errors are a bare `Scaffold` with no back.<br>• GoRouter has no `errorBuilder`, so an unknown deep link shows the default English "Page Not Found". | `main.dart:81`, `document_scanner_screen.dart:136/710`, `route_navigation_screen.dart:219/1591`, `profile_screen.dart:179`, `product_detail_screen.dart:40`, `router.dart` |
| 9 | **P1 raw errors** | **Raw exceptions are shown to customers** (`'$e'`), in these places:<br>• Home "Chyba: " + `$e`<br>• Catalogue and Moto detail "Chyba: " + `$e`<br>• Reservation detail "Chyba: $e"<br>• Edit save, Posun termínu and Swap toasts<br>• Profile save and account delete<br>• `cancelBooking` → "Chyba storna: Chyba storna: PostgrestException…"<br>• Reset-password OTP/new-password (raw GoTrue English)<br>• Scanner diagnostics "[id \| network \| HTTP 500 …]" | see §R |
| 10 | **P1 i18n** | **Czech-only or raw text reaches non-Czech users:**<br>• The licence and overlap validation in the booking form is always Czech (`translations['cs']` hard-coded in `booking_validator.dart`).<br>• The reservation detail shows a raw `paymentStatus.toUpperCase()` ("UNPAID", "PARTIAL_REFUND").<br>• `sessionExpired` = "Session vypršela – přihlašte se emailem" is jargon.<br>• Register mixes vykání with tykání. | `booking_validator.dart:37/45/94`, `res_detail_tab_content.dart:221` |
| 11 | **P1 silent wrong data** | **Errors are treated as data:**<br>• An availability fetch error (`bookedDatesProvider`) leaves the calendar showing every day free (`valueOrNull ?? []`).<br>• `checkMotoAvailability` returns `false` on a network error, so the customer sees "Obsazeno – Motorka je v tomto termínu již rezervována" when they are really offline (edit, restore).<br>• A restore-booking network error says "Motorka obsazena".<br>• `paymentMethodsProvider` swallows errors (`[]`) → the saved card is silently ignored. | `moto_detail_page.dart:598`, `catalog_provider.dart:95-108`, `reservation_detail_screen.dart:256-299` |
| 12 | **P1 hang** | **Awaits with no timeout (the spinner can stay forever):**<br>• `_createDraftBooking` (PostgREST insert)<br>• the post-payment `bookings.update` + `replaceModeledExtras` + the swap commit loop<br>• the AI agent `functions.invoke` ("⏳ Přemýšlím…")<br>• `StripeService.handleNextAction` / `confirmPayment` (SDK)<br>• the SOS incident creation chain<br>• the shop `createShopOrder` RPC<br>The 30-min payment countdown keeps running while a payment is in flight and can fire "Čas na zaplacení vypršel" over a payment that is succeeding. | `payment_screen.dart:504/1310`, `ai_agent_screen.dart:105`, `sos_report_screen.dart:241-291` |
| 13 | **P2** | **Missing confirmations and wrong labels:**<br>• Cancelling a booking shows **no success confirmation** (the dialog just closes: no "storno potvrzeno", no refund amount or timing).<br>• The shop "Doručovací údaje" toast uses the same text as title and body.<br>• "Chyba / Chyba" toasts appear for unknown codes (swap, move, shop order create on network error).<br>• Route or place submission without login says "Přihlas se a ohodnoť" (the wrong copy). | `res_cancel_dialog.dart:91`, `shop_checkout_screen.dart:233`, `community_submit.dart:51` |
| 14 | **P2** | **The "Zaznamenat jízdu" (record ride) button is hidden** in the Trasy "+" menu and in a card on Moje zážitky. Starting it can fail with one combined message, "přihlas se a povol polohu", which has no settings link and does not tell login, permission or GPS-off apart. Background-location loss and the reduced-accuracy (iOS) refusal stay silent. | `community_submit.dart:38`, `my_experiences_screen.dart:623`, `ride_recorder.dart:160` |

---

## A. Booking form → "POKRAČOVAT K PLATBĚ" gates (`core/booking_form_widget.dart`, `booking_provider.dart`)

The CTA stays disabled while any gate is active, and the block is shown inline above it. This part is good: nothing here can hang. The gaps are in the wording and the next actions.

| ID | Trigger | Surface | Current cs text | Action offered | Hang | Gap |
|---|---|---|---|---|---|---|
| B-01 | No dates chosen | CTA disabled | (none) | — | — | WHAT: there is no hint on why the CTA is grey (only the date section "Vyberte termín"). |
| B-02 | No bike | Inline | `selectMotoFirst` "Nejprve vyberte motorku" + button `selectMotoBtn` | opens the bike picker | — | OK |
| B-03 | Licence missing in profile | Inline red | `validationNoLicense` "Nemáte v profilu žádný řidičský průkaz. Tato motorka vyžaduje skupinu {license}." | none | — | ACTION: no "Doplnit ŘP v profilu" and no "Ukaž motorky pro můj ŘP". **i18n: always Czech** (`translations['cs']`). |
| B-04 | Licence group too low | Inline red | `validationInsufficientLicense` "Vaše řidičské oprávnění ({groups}) nestačí pro tuto motorku (vyžaduje {license})." | none | — | ACTION: no filter to suitable bikes and no edit of the licence. i18n: always Czech. |
| B-05 | Own overlapping booking | Inline red | `validationOverlap` "Již máte rezervaci v termínu {start} – {end} ({moto}). Nelze mít dvě překrývající se rezervace." | none | — | ACTION: no "Otevřít rezervaci" / "Změnit termín". i18n: always Czech. Only bookings of the same account are checked (a web account is invisible → falls through to B-12). |
| B-06 | Min/max rental days | Inline red | `validationMinDays` "Minimální délka pronájmu této motorky je {n} dní." / `validationMaxDays` | none | — | FIX implicit (change dates). OK-ish. |
| B-07 | Pick-up in the past / lead time | Inline red | `validationPastPickup` "Čas vyzvednutí už uplynul. Rezervaci nelze vytvořit zpětně – vyberte čas v budoucnosti." · `validationStaffedLeadTime` "…nejdříve za 1 hodinu…" · `validationDeliveryLeadTime` "Přistavení je možné nejdříve za 6 hodin od teď…" | none | — | OK (says why and how). Could offer a "nejbližší možný čas" chip. |
| B-08 | Profile incomplete (address, licence no./expiry) | Inline amber | `validationMissingProfile` "Pro dokončení rezervace nejdřív doplňte v profilu: {fields}. Foto dokladů můžete nahrát i později." | `completeProfileBtn` "Doplnit v profilu" → `/profile` | — | OK. The return path back to the form is not guaranteed (`push('/profile')`, then back works). |
| B-09 | Licence expires before the rental end | Inline amber | `validationLicenseExpired` "Váš řidičský průkaz má propadlou platnost. Aktualizujte platnost ŘP v profilu." | "Doplnit v profilu" | — | OK. Says "propadlou" even when it is only expiring before the end date. |
| B-10 | Delivery chosen + gear sizes missing | Inline amber | `fillGearSizesOnDelivery` "Vyplňte velikosti výbavy" + `missingLabel` "Chybí: …" | none (scroll) | — | ACTION: no jump to the section. |
| B-11 | Consents not ticked | Grey hint | `consentsRequired` "Pro pokračování potvrďte povinné souhlasy." | — | — | OK |
| B-12 | Calendar: range contains occupied days | Snack | `calRangeOccupied` "Rozsah obsahuje obsazené dny" | none | — | WHY/FIX thin. **Silent hole:** if `get_moto_booked_dates` fails, the calendar shows **all days free** → the conflict surfaces only at insert (C-04). |

## C. Booking creation (draft insert on the payment screen, `_createDraftBooking`)

The surface is `Sheet` with the title `bookingCreateFailed` "Rezervaci se nepodařilo vytvořit" and the button `retry` "Zkusit znovu" (which only closes the sheet).

| ID | Trigger | Current body | Hang | Gap |
|---|---|---|---|---|
| C-01 | Not logged in | `notLoggedIn` "Nejste přihlášen/a. Přihlaste se a zkuste znovu." + `tryAgainPlease` "Zkuste to prosím znovu." | — | ACTION: the button is "Zkusit znovu", not "Přihlásit se". |
| C-02 | Draft lost (no bike / no dates) | `noMotoSelected` "Nebyla vybrána motorka. Vraťte se zpět a vyberte ji." / `selectDatesFirst` "Vyberte prosím termín rezervace v kalendáři." | — | ACTION: no button to go back to the bike or dates. |
| C-03 | Profile gate (safety net) | the B-08 / B-09 text | — | ACTION: no "Doplnit v profilu" here. |
| C-04 | **Bike taken meanwhile** (`check_booking_overlap`: "Překrývající se rezervace pro moto_id …") | **Falls through to unknown** → `bookingCreateUnknownError` "Při vytváření rezervace došlo k neznámé chybě. Zkontrolujte připojení k internetu a zkuste to znovu." | — | **FALSE cause, no WHY, no ACTION** (should say "Motorku si mezitím rezervoval někdo jiný" + "Vybrat jiný termín" / "Podobné motorky"). |
| C-05 | Customer overlap (another account / web) "Zákazník má překrývající se rezervaci…" | the same unknown text | — | FALSE cause. |
| C-06 | Branch closed in the range (`check_booking_branch_open`) | the same unknown text | — | FALSE cause. |
| C-07 | Unit assigned as a trailer elsewhere | the same unknown text | — | FALSE cause. |
| C-08 | Trailer on a self-service bike | `swap.trailerStaffedOnly` "Vozík jen na obslužné" | — | WHY/FIX thin (3 words). |
| C-09 | Trailer unit taken meanwhile | `swap.trailerOccupied` "Vozík je v tomto termínu už obsazený" | — | ACTION: no "odebrat vozík". |
| C-10 | Self-service + delivery | `ssNoDeliveryError` "U motorky ze samoobslužné pobočky nelze zvolit přistavení ani odvoz na adresu — vyberte převzetí i vrácení na pobočce." | — | ACTION: no button to change it. |
| C-11 | Server returned no id | `noBookingId` "Server nevrátil ID rezervace." | — | Technical wording; no fix given. |
| C-12 | Network or JWT expired during insert | the unknown text | **RISK** (no timeout on the insert) | WHY: an expired session is not detected here. |

## D. Payment — saved card, one tap (`_chargeSavedCard`, off-session confirm on the server)

These states show `Sheet` with the mapper title, the body + "(Pokus N z 3)", the primary `retry` "Zkusit znovu" (re-charges the saved card) and the secondary `payWithAnotherCard` "Zaplatit jinou kartou" (opens the card sheet).

| ID | Trigger | Title / body (cs) | Hang | Gap |
|---|---|---|---|---|
| D-01 | Succeeded | toast `verifyingPayment` "Ověřuji platbu..." / `waitingConfirmation` "Čekám na potvrzení" → G-* | ≤8 s poll | OK |
| D-02 | 3DS required → SDK overlay | (bank UI) | **RISK** (`handleNextAction`, no timeout) | — |
| D-03 | 3DS failed **or cancelled by the user** | generic `genericTitle` "Platba se nezdařila" / `genericBody` "Platbu se nepodařilo dokončit a žádné peníze nebyly strženy. Zkuste to prosím znovu, nebo použijte jinou platební metodu." | — | WHAT/WHY: it does not say "ověření v bance (3-D Secure) se nedokončilo". It counts as a failed attempt even on a user cancel. The mapper's `authTitle` "Potvrzení u banky se nezdařilo" is unused here. |
| D-04 | `insufficient_funds` | `fundsTitle` "Nedostatek prostředků" / `fundsBody` "Na kartě není dostatek peněz pro tuto platbu. Dobijte prosím účet, zvolte jinou kartu, nebo zaplaťte přes Google Pay." | — | OK. ("přes Google Pay" points to a different flow; the secondary button is "Zaplatit jinou kartou", which contains Google Pay.) |
| D-05 | `lost_card` / `stolen_card` / `pickup_card` | `blockedTitle` "Karta je zablokovaná" / `blockedBody` "Vaše banka tuto kartu zablokovala (nahlášena jako ztracená/odcizená). Použijte prosím jinou kartu nebo kontaktujte svou banku." | — | OK. Should also offer "Odebrat kartu z účtu". |
| D-06 | `card_velocity_exceeded` / `withdrawal_count_limit_exceeded` | `limitTitle` "Překročen limit karty" / `limitBody` "Byl překročen denní limit nebo počet plateb. Zvyšte limit v aplikaci své banky, zkuste to později, nebo použijte jinou kartu." | — | OK |
| D-07 | `expired_card` (decline_code) | `expiredTitle` "Platnost karty vypršela" / `expiredBody` "Karta už není platná. Použijte prosím jinou, platnou kartu." | — | Works only if Stripe also sets `decline_code`. The `error_code` is dropped (finding 7). Should offer "Aktualizovat kartu". |
| D-08 | `incorrect_cvc` / `invalid_cvc` | `cvcTitle` "Chybný bezpečnostní kód (CVC)" / `cvcBody` "…Zkuste platbu znovu a zadejte ho pečlivě." | — | For a saved card the retry does **not** ask for the CVC → retry loops. |
| D-09 | `do_not_honor` / `transaction_not_allowed` / `service_not_allowed` / `currency_not_supported` | `bankBlockTitle` "Platbu zamítla banka" / `bankBlockBody` "Vaše banka tuto platbu neschválila. Kartu obvykle odblokujete přímo v aplikaci své banky (často kvůli ochraně proti podvodu). Pak zkuste platbu znovu, nebo použijte jinou kartu." | — | OK |
| D-10 | `generic_decline` / `do_not_try_again` | `cardDeclinedTitle` "Platba kartou zamítnuta" / `bankBlockBody` | — | OK |
| D-11 | Unknown decline, cs app | `cardDeclinedTitle` + **raw Stripe message** (often English) + `genericFix` "Zkuste platbu znovu, použijte jinou kartu, nebo zaplaťte přes Google Pay." | — | i18n/raw |
| D-12 | Unknown decline, other langs | `genericTitle` / `genericBody` | — | WHY missing |
| D-13 | **`amount_too_small` (< 15 Kč)** | cs: `cardDeclinedTitle` "Platba kartou zamítnuta" + raw "Amount must be at least …" + `genericFix` | — | **FALSE (not a card decline), DEAD loop** — see §S. |
| D-14 | `off_session_unexpected_status` (e.g. `processing`) | `genericTitle` + `genericBody` "…žádné peníze nebyly strženy…" | — | **FALSE** — the money may be in flight. This should be the "Platba se ověřuje" pending state. |
| D-15 | Timeout 30 s / network | title `serverNotResponding` "Server neodpovídá" or `connectionError` "Chyba připojení" + `networkBody` "Nepodařilo se spojit s platebním serverem. Zkontrolujte připojení k internetu a zkuste platbu znovu — žádné peníze zatím nebyly strženy." | — | **FALSE** on a timeout (the charge may have happened). It should poll the booking first. |
| D-16 | Session expired (401) | title `sessionExpired` "Session vypršela – přihlašte se emailem" / `authExpiredBody` "Pro dokončení platby se prosím znovu přihlaste. Vaše rezervace zůstává uložená." Button `login` "Přihlášení" → `/login` | — | Jargon ("Session"). After login the app lands on Home, not the payment (the FAB resumes a new booking; an **edit surcharge is lost**). |
| D-17 | Card deleted in the meantime | retry → falls to the card sheet (E) | — | OK |

## E. Payment — card sheet / Google Pay / Apple Pay (`CardPaymentSheet`, a white sheet: "Zaplatit kartou", `[Google Pay]`, "nebo zaplatit kartou", CardField, "Zaplatit {částka} →")

| ID | Trigger | Surface / text | Action | Hang | Gap |
|---|---|---|---|---|---|
| E-01 | Card confirmed (`Succeeded` / `RequiresCapture`) | → G-* | — | ≤8 s | OK |
| E-02 | `Processing` | toast "Ověřuji platbu..." → poll ≤10 s → G or F-02 | — | — | see F-02 |
| E-03 | 3DS cancelled / user `Canceled` | stays in the sheet, spinner off, **no message** | — | — | WHAT: there is no hint "Ověření v bance jsi zrušil — zkus znovu". |
| E-04 | Card error `StripeException` | `Sheet` via `fromStripeException`. Mapped codes: `expired_card`, `incorrect_cvc`, `incorrect_number` (`numberTitle` "Chybné číslo karty" / "Zadané číslo karty není správné. Zkontrolujte ho a zkuste platbu znovu."), `card_declined`, `authentication_required` (`authTitle` "Potvrzení u banky se nezdařilo" / `authBody` "Banka vyžadovala potvrzení platby (3D Secure), které se nepodařilo dokončit. Zkuste platbu znovu a potvrďte ji v aplikaci své banky."), `processing_error` (`processingTitle` "Dočasná chyba při zpracování" / "…Chvíli počkejte a zkuste to prosím znovu."). Unknown → "Platba kartou zamítnuta" + Stripe `localizedMessage` + genericFix. | "Zkusit znovu" reopens the sheet (field cleared) | — | Mostly OK. `insufficient_funds` / `do_not_honor` arrive only as a `localizedMessage` on the client (the bank `decline_code` is not read) → generic title. |
| E-05 | Google Pay cancelled | stays in the sheet, silent | — | — | OK |
| E-06 | Google Pay fails (`StripeException`) | treated like E-04 → title "Platba kartou zamítnuta" | retry | — | WHAT wrong: the wallet titles `walletTitle` "Google Pay teď nelze použít" / `walletBody` "…Zkontrolujte, že máte v Google Pay přidanou platnou kartu, nebo zaplaťte přímo kartou — funguje vždy." apply only to non-Stripe errors (`OR_BIBED`). |
| E-07 | Google Pay not available on the device | the button is simply hidden | — | — | WHY is invisible (acceptable). |
| E-08 | Non-Stripe error / unexpected PI status | `walletTitle` (if the text mentions a wallet) or `genericTitle` "Platba se nezdařila" | retry | — | OK |
| E-09 | **Sheet swiped down during `confirmPayment`** (Android) | treated as cancelled → pay button active | — | — | **Double-pay risk.** iOS has `_WalletGuard` → `processing`. |
| E-10 | iOS Apple Pay: card declined | the D/E mapping with "Apple Pay" substituted | — | — | OK |
| E-11 | iOS Apple Pay: sheet not presented / Stripe-side failure, money verified not sent | `Dialog` `walletFailedTitle` "Platba přes Apple Pay neprošla" / `walletFailedBody` "…nic nebylo strženo. Zaplaťte prosím kartou tady níže, nebo to zkuste později znovu." | OK | — | Good model. Port the guard logic to Android. |
| E-12 | iOS Apple Pay: unverifiable state | → `processing` (F-02) | — | — | OK |
| E-13 | Card add (Profil → Platební metody) fails | Toast `cardSaveFailed` "Kartu se nepodařilo uložit. Zkuste to prosím znovu." | — | — | WHY missing (declined / expired / network). |

## F. Payment — server refusals before Stripe (`_handleIntentError`)

The surface is `Sheet`. The title depends on the code: timeout → `serverNotResponding` "Server neodpovídá", network → `connectionError` "Chyba připojení", otherwise → `paymentCannotProcess` "Platbu nelze zpracovat". The body is the translated `serverRefusal(code)`; failing that, the **raw Czech server text for the cs app**, or the generic text for other languages. The "Zkusit znovu" button only closes the sheet.

| ID | Server code / case | cs body | Gap |
|---|---|---|---|
| F-01a | `moto_unavailable` (edit) | `refMotoUnavailable` "Motorka je v novém termínu už obsazená, nebo je pobočka zavřená — platba doplatku zrušena. Zvolte jiný termín nebo motorku." | ACTION: no button back to the edit. |
| F-01b | `wrong_status` | `refWrongStatus` "Rezervaci v tomto stavu už nelze upravit (stornovaná nebo ukončená) — platba doplatku zrušena." | ACTION: no "Otevřít rezervaci". |
| F-01c | `trailer_staffed_only` | `refTrailerStaffedOnly` "Vozík lze půjčit jen k motorce z obslužné pobočky — … Platba doplatku zrušena." | OK |
| F-01d | `trailer_unavailable` | `refTrailerOccupied` "Vozík je v novém termínu už obsazený jinou rezervací…" | OK |
| F-01e | `trailer_check_unavailable` / `validation_unavailable` | `refCheckUnavailable` / `refValidationUnavailable` "…zkuste to prosím za chvíli znovu." | OK |
| F-01f | `booking_not_found` | `refNotFound` "Rezervace nebyla nalezena — … Načtěte rezervaci znovu a zkuste to znovu." | ACTION: no reload button. |
| F-01g | `forbidden` | `refForbidden` "Tuto rezervaci nelze upravit z tohoto účtu. Přihlaste se prosím účtem, kterým byla vytvořena." | For a **new booking** the "upravit" wording is wrong. |
| F-01h | `stale_booking` | `refStale` "Rezervace se mezitím změnila (jiné zařízení nebo web). Načtěte ji prosím znovu a úpravu zopakujte." | ACTION: no reload button (the edit screen pre-checks and shows `editStaleTitle` "Rezervace se změnila" / `editStaleReloaded`, which is good). |
| F-01i | `amount_mismatch` | `refAmountMismatch` "Částka doplatku neodpovídá výpočtu serveru. Načtěte rezervaci znovu…" | For a **new booking** (price changed: "Cena rezervace je X Kč…") the text wrongly says "doplatku". No reload action. |
| F-01j | `active_pickup_time_locked` | `refActivePickupTimeLocked` "Motorka už byla vyzvednuta — čas vyzvednutí už nelze změnit." | OK |
| F-01k | `delivery_fee_guard`, `location_requires_route`, `not_sos_replacement`, `invalid_amount`, `invalid_type` | **not mapped** → cs: raw server text; others: generic | i18n |
| F-02 | 409 "Tato rezervace je již zaplacena." (double tap, webhook beat us) | cs: shown as an **error** "Platbu nelze zpracovat" | **Should be success / info** → "Už je zaplaceno" + "Zobrazit rezervaci". |
| F-03 | 500 Stripe exception (e.g. **`amount_too_small`**, Stripe outage) | cs: raw "Payment processing failed: …"; others: generic | **raw + DEAD** for < 15 Kč (§S) |
| F-04 | 400 "Chyba kalkulace ceny. Sleva není 100%…" / "Částka neodpovídá ceně rezervace…" (free branch) | cs: raw server text | ACTION: no "Obnovit cenu". |

## G. Success / thank-you states

| ID | Flow | Surface | Content (cs) | Actions | Gap |
|---|---|---|---|---|---|
| G-01 | New booking paid (draft or FAB resume) | Screen `/success` (`PaymentConfirmationScreen`), hardware back → Rezervace | toast `paid` "Zaplaceno" / `bookingConfirmed` "Rezervace potvrzena"; title `successTitle` "Rezervace potvrzena!", subtitle `successSubtitle` "Vaše rezervace je aktivní"; booking summary (dates, `pickupTimeLabel`, `returnTimeLabel`); pick-up branch block with map link; self-service late gate `ssLateGateNote` "Sleva za vyzvednutí od 12:00: kiosk vám motorku vydá {datum} od 12:00. Chcete ji dřív? Upravte čas vyzvednutí — sleva zanikne a rozdíl doplatíte."; `successEmailSent` "Potvrzení jsme zaslali na váš email"; safety box `successSafetyTitle` "Bezpečnostní pokyny" + `successSafetyTips`; `successSynced` "Synchronizováno s webem MotoGo24"; docs card (G-01a/b/c) | `uploadDocumentsCta` "Nahrát doklady teď" (only when docs are missing) → `/docs`; `successCta` "Moje rezervace" | The tone mixes vykání (title) with tykání (docs card). No booking number. No "Přidat do kalendáře". No rank / loyalty points earned. |
| G-01a | Docs verified | Inline green | `docsVerifiedTitle` "Doklady ověřeny" / `docsVerifiedBody` "Doklady jsme ověřili — žádná akce není potřeba. Přístupový kód k motorce (a máš-li zapůjčenou výbavu, i kód šatny) ti dorazí e-mailem, SMS i WhatsAppem před začátkem rezervace." | — | OK |
| G-01b | Docs missing / withheld | Inline amber | `docsMissingTitle` "Doklady ještě nejsou ověřené" + server reason (`reasonMissingDocs`, …) + `docsMissingBody` "Doklady můžeš ověřit dodatečně v Dokumentech (foto OP/pasu + ŘP). Bez ověření ti nepošleme přístupové kódy: na samoobslužné pobočce se bez nich dovnitř nedostaneš, na obslužné pobočce doklady zkontrolujeme při převzetí na místě." | "Nahrát doklady teď" | Good model of what / why / how. |
| G-01c | Kids bike | Inline green | `docsChildBikeTitle` "Doklady se nevyžadují" / `docsChildBikeBody` | — | OK |
| G-01d | Docs status fetch failed | card hidden | — | — | Silent (acceptable). |
| G-02 | Edit surcharge paid | Screen `/payment-result` | title "Zaplaceno", subtitle `bookingChangesConfirmed` "Změny rezervace potvrzeny", line "💳 Doplatek za úpravu rezervace: X Kč", `successEmailSent`, pick-up info, `successSynced` | "Moje rezervace" | The post-payment `bookings.update` error is **swallowed** (`debugPrint`) → success is shown even if the client apply failed (the webhook usually applies it). No new date range shown. |
| G-03 | Swap surcharge paid | `/payment-result` | subtitle `swap.successTitle` "Výměna potvrzena" + pick-up branch of the new bike | "Moje rezervace" | The commit can fail 3× and success is still shown (the webhook is the backstop). |
| G-04 | Shop order paid | `/payment-result` | title "Zaplaceno", subtitle `orderConfirmed` "Objednávka potvrzena" (or `paymentProcessed` "Platba byla úspěšně zpracována" when the webhook is late), "🧾 #číslo", "💳 Celková cena: X", `confirmOnEmail` "Potvrzení na email" | `close` "Zavřít" → Shop | OK. The title says "Zaplaceno" even when unconfirmed. |
| G-05 | SOS (dormant `PaymentFlowType.sos`) | `/payment-result` | `replacementMotoOrdered` "Náhradní motorka objednána" | → `/sos/done` | No entry point sets it today (SOS replacement is free). |
| G-06 | Free booking (100 % discount) | toast `confirmed` "Potvrzeno" / `discountCoversAll` "Sleva pokrývá celou cenu — platba kartou není potřeba" → `/success` | — | — | OK. On failure → F-04 / generic. |
| G-07 | Edit without payment (diff ≤ 0) | Inline confirmation page | `changesSavedTitle` "Změny uloženy" / `changesSaved` "Vaše změny byly úspěšně uloženy." + `reservationRange`; shortening: `shorteningConfirmed` "Zkrácení potvrzeno" / `reservationShortened` "Rezervace zkrácena" + `refundAmount` "Vrácení: {amount} Kč" + `refundToOriginalMethod` "Částka bude vrácena původním způsobem platby." | back to reservations | No refund timing ("do 5–10 pracovních dnů"). |
| G-07a | Refund failed after the save | Toast + confirmation without refund | `refundSettleManual` "Automatická vratka se nezdařila — vyřídí ji obsluha a peníze vám vrátíme (ozveme se, není třeba nic dělat)." — the toast may instead show the **raw `process-refund` error** | — | raw text possible |
| G-07b | Extras removal failed | Toast | `extrasRemoveFailed` "Odebrané doplňky se nepodařilo odstranit — vyřídí obsluha." | — | OK |
| G-08 | Free reschedule (Posun termínu) | Inline page | `moveConfirmedTitle` "Termín posunut" / `moveConfirmed` "Rezervace byla zdarma posunuta na {start} – {end}. Potvrzení a aktualizovanou smlouvu jsme poslali e-mailem." | — | OK |
| G-09 | Swap with net ≤ 0 | Inline | `swap.successTitle` "Výměna potvrzena" / `swap.success` "Od {date} {time} pojedete na motorce {moto}." | — | Refund amount not shown. |
| G-10 | Registration complete | Full-screen celebration `MotoWelcomeOverlay` | `registerComplete` / `welcomeToMotoGo` | → Home | OK |
| G-11 | SOS reported | Screen `/sos/done` (`SosDetailScreen` done view) + toast `incidentReported` "Incident nahlášen" / `motoGoInformed` "MotoGo24 byla informována" | Zprávy / Rezervace / Domů | — | OK |
| G-12 | Rating saved | Toast `thanks` "Děkujeme!" / `starsCount` "{n}/5 hvězdiček", then the card shows `rfThanksTitle` "Díky za tvoje hodnocení!" / `rfThanksSub` + 2 buttons `rfGoogleBtn` "Napiš nám recenzi" (`rfGoogleCaption` "Veřejná recenze na Googlu") and `rfImproveBtn` "Napiš nám přímo, co máme zlepšit" (`rfImproveCaption` "Zpráva přijde rovnou našemu týmu") | — | — | OK (owner wording). |
| G-13 | Private feedback sent | Toast + inline | `rfSentTitle` "Odesláno, díky!" / `rfSentLine` "Zprávu máme – odpověď najdeš ve Zprávách." + `rfOpenThread` "Otevřít konverzaci" | — | — | OK |
| G-14 | **Booking cancelled by the customer** | dialog closes | **nothing** | — | — | **WHAT missing:** no "Rezervace stornována, vrátíme X Kč do N dnů". |
| G-15 | Docs scan complete | Toast `scanComplete` "Skenování dokončeno" / `docsUploadedVerified` "Doklady nahrány a ověřeny" → Home | — | — | Disappears in 3 s. |
| G-16 | Level-up | **`loyalty_levelup_overlay.dart` — DO NOT REDESIGN** (full-screen montage, "+N" badge, `loyaltyContinue`) | — | — | Timeouts are fail-open. OK |

## H. Payment pending / confirmation / timeout / attempts

| ID | Trigger | Surface / text | Action | Hang | Gap |
|---|---|---|---|---|---|
| H-01 | Webhook did not confirm within 8 s (card or off-session succeeded) | Toast "⏳ Ověřuji platbu... / Čekám na potvrzení Potvrzení jsme zaslali na váš email" → go `/reservations` | — | — | **Toast only (3 s).** The reservation then looks unpaid and the **"Dokončit rezervaci" FAB invites a second payment.** There is no "Platba se ověřuje" badge on the card or in the detail, and no live update to success. This needs a dedicated **Pending** state. |
| H-02 | App resumed from the browser / 3DS / Link | silent DB poll; if paid → success | — | — | OK. If unpaid, nothing tells the user. |
| H-03 | 30-min countdown visible | `timeRemainingLabel` "Zbývá {time} na zaplacení" | — | — | Shown also for **edit surcharge and shop**, where there is no server deadline. |
| H-04 | Countdown hits 0 | Sheet `paymentExpired` "Čas na zaplacení vypršel" / `paymentExpiredDesc` "Rezervace vypršela. Vraťte se na detail motorky a vytvořte novou." | button `confirm` "Potvrdit" → `/reservations` | — | The button label and target contradict the text (it says "go to the bike detail"). **Wrong for edit/shop flows** (nothing expired). **Fires during an in-flight payment.** No "Rezervovat znovu stejnou motorku". |
| H-05 | 3 failed attempts | Sheet `paymentFailed` "Platba se nezdařila" / `paymentFailedAfterAttempts` "Platba se nepodařila. Vaše rezervace zůstane uložena — platbu můžete dokončit později v sekci Rezervace." + " 3 " + `paymentFailedAttemptsRest` "Nebo nás kontaktujte na info@motogo24.cz." | `goToReservations` "Přejít na rezervace" | — | Broken sentence assembly ("…Rezervace. 3 Nebo nás…"). It does not mention the **30-min auto-cancel deadline**. For an **edit surcharge** the promise is false: the change is not saved. |
| H-06 | Pending booking FAB | "💳 Dokončit rezervaci · M:SS" + ✕ (`cancelReservationQ` "Zrušit rezervaci?") | pay / cancel | — | When the cancel fails → Snack `cancelError` "Chyba storna" (no why). |
| H-07 | Pending booking auto-cancelled (cron) | the card switches to "Zrušená" | `restoreBtn` "Obnovit" → **Search** (the card) vs the restore flow (the detail) | — | No reason shown ("nezaplaceno do 30 min"). Inconsistent restore. |
| H-08 | Reservation detail payment row | raw `paymentStatus.toUpperCase()` ("UNPAID", "REFUNDED"…) | — | — | i18n/raw (`payStatus*` keys exist in ext_26). |

## J. Reservation edit / cancel / restore (`reservation_edit_screen.dart`, `res_cancel_dialog.dart`, `reservation_swap_section.dart`)

| ID | Trigger | Surface / cs text | Action | Gap |
|---|---|---|---|---|
| J-01 | Invalid range | Toast "Chyba" / `invalidDateRange` "Neplatný rozsah dat" | — | WHY/FIX |
| J-02 | Active booking, start changed | Toast / `cannotChangePickupActive` "U aktivní rezervace nelze měnit datum vyzvednutí" | — | OK |
| J-03 | Delivery lead time | Toast (B-07 texts) | — | 3 s toast |
| J-04 | Delivery without an address | Toast "Chyba" / `clickEnterAddress` "Klikněte pro zadání adresy" | — | No jump to the field. |
| J-05 | Missing gear sizes | Toast `missingGearSizesTitle` "Chybí velikosti výbavy" / "Při přistavení doplňte: …" | — | — |
| J-06 | Bike occupied (pre-check) | Toast `occupiedTitle` "Obsazeno" / `motoOccupied` "Motorka je v tomto termínu již rezervována" | — | **FALSE when offline** (`checkMotoAvailability` → false on error). |
| J-07 | Stale (changed on the web) | Toast `editStaleTitle` "Rezervace se změnila" / `editStaleReloaded` "Rezervace byla mezitím upravena jinde (web nebo jiné zařízení). Načetli jsme aktuální stav — úpravu prosím zopakujte." | auto-reload | Good |
| J-08 | Extras baseline not loaded | Toast / `extrasBaselineFailed` "Doplňky rezervace se nepodařilo načíst. Otevřete úpravu rezervace znovu." | — | OK |
| J-09 | Surcharge > 0 | → payment (D/E/F) | — | **< 15 Kč dead end (§S).** |
| J-10 | Save / refund exception | Toast "Chyba" / **raw `$e`** (trailer errors mapped) | — | raw |
| J-11 | Posun termínu RPC error | Toast "Chyba" / `moveOccupiedRange` "V tomto termínu je motorka obsazená. Vyberte jiný den, kde je volná celá délka." · `moveErrCustomerOverlap` · `moveErrLength` · `cannotSelectPast`; unknown code → **"Chyba / Chyba"**; exception → raw `$e` | — | partial |
| J-12 | Swap dry-run / commit error | Toast "Chyba" / `swap.err.*`: "Rezervace nenalezena." · "K této rezervaci nemáte oprávnění." · "Výměnu lze provést jen u nadcházející nebo probíhající rezervace." · "Rezervace není zaplacená." · "Zvolenou motorku nelze použít." · "Datum výměny musí být v termínu rezervace." · "Výměna už na této rezervaci proběhla — druhou najdete v přehledu rezervací." · "Nová motorka je v úseku po výměně obsazená. Vyberte jinou." · "Nedostatečný řidičský průkaz — na tuto motorku váš ŘP nestačí."; unknown → "Chyba"; exception → raw | — | 3 s toasts, raw fallback |
| J-13 | Cancel dialog | Dialog `cancelReservationQ` "Zrušit rezervaci?" + storno box (`stornoRules` "7+ dní = 100% · 2–7 dní = 50% · <2 dny = 0%", `currentlyRefund` "Aktuálně: {pct}% vrácení ({amount} Kč)") + optional reason | `back` "Zpět" / `cancelReservationBtn` "Zrušit rezervaci" | OK |
| J-14 | Cancel success | dialog closes, list refreshes | — | **No confirmation** (G-14). |
| J-15 | Cancel failure | Snack "Chyba storna: Chyba storna: {PostgrestException…}" | — | raw, duplicated prefix, Czech hard-coded in `reservation_provider.dart:261`. |
| J-16 | Restore — date passed | Toast `cannotRestore` "Nelze obnovit" / `restoreDatePassed` "Termín rezervace již uplynul." → Search | — | OK |
| J-17 | Restore — bike occupied **or any error** | Toast `motoOccupiedTitle` "Motorka obsazena" / `restoreMotoOccupied` "Motorka je v tomto termínu již obsazená." → Search | — | **FALSE on a network or DB error.** |
| J-18 | Contract / invoice not ready or failed | Toast `contractNotReady` "Smlouva zatím není připravena." · `contractLoadError` "Smlouvu se nepodařilo načíst." · `invoiceNotReady` "Konečná faktura zatím nebyla vystavena" · `invoiceLoadError` | — | WHY/WHEN missing ("vystavíme po vrácení"). |
| J-19 | Access codes | Inline rows: `awaitingDocs` "Čeká na doklady" / server reason · `protocolFirst` "Nejdřív podepište předávací protokol na displeji pobočky" · `ownGearNoLocker` · button `uploadDocsForCodes` "Nahrát doklady a uvolnit kódy"; release result toast `codesReleased` "Přístupové kódy byly uvolněny." / title **"Chyba"** + `codesStillWithheld`; load error `doorCodesUnavailable` "Přístupové kódy se nepodařilo načíst. Zkuste to později nebo kontaktujte MotoGo." | — | "Chyba" is the wrong title for an expected gate; no retry button. |

## L. Shop & vouchers (`shop_checkout_screen.dart`, `voucher_screen.dart`) — the shop is behind the `eshop_visible` flag

| ID | Trigger | Surface / cs text | Gap |
|---|---|---|---|
| L-01 | Empty cart | Toast `cart` / `cartEmpty` "Košík je prázdný" | OK |
| L-02 | Post shipping fields missing | Toast `deliveryDetails` "Doručovací údaje" / **the same text** | WHAT/FIX missing |
| L-03 | Promo code checks | inline `promoAlreadyUsed` "Kód "{code}" je již použit" · `shopCodeNotForVoucher` "Slevový kód nelze uplatnit na nákup dárkového poukazu." · `shopCodeInvalid` "Kód {code} nelze v e-shopu uplatnit. Platí jen slevové (promo) kódy — …" · `promoNoCombinePercent` · success `discountApplied` "Sleva {value} aplikována" | OK |
| L-04 | Order create refused | Toast "Chyba" / `shopVoucherNotAllowed` · `shopOutOfStock` "Některé zboží v košíku už není skladem v požadovaném množství." · `shopProductUnavailable` "…Upravte prosím košík." | No "Upravit košík" action. 3 s toast. |
| L-05 | Order create network error / unknown | Toast **"Chyba / Chyba"** | WHAT/WHY/FIX all missing |
| L-06 | Payment intent error (`below_minimum`, `amount_mismatch` "Cena objednávky se přepočítala na X Kč. Vraťte se prosím do košíku…", `already_paid`, `wrong_status`, `order_not_found`, `forbidden`, `no_payment_needed`) | Sheet; cs: title `cardDeclinedTitle` **"Platba kartou zamítnuta"** + raw server text + genericFix "Zkuste platbu znovu, použijte jinou kartu…"; other languages: generic | **FALSE title** (not a card decline). `already_paid` / `no_payment_needed` should be success. `below_minimum` is a dead end. |
| L-07 | Card or GPay failure | Sheet (E-04 mapping), "Zkusit znovu" only closes | Retry = **new order** each time (duplicate pending orders). |
| L-08 | Processing, not confirmed within 10 s | Toast "Ověřuji platbu… Čekám na potvrzení Potvrzení jsme zaslali na váš email", stays on checkout | **Double order / charge risk.** No pending screen. |
| L-09 | No app-resume recovery and no countdown in the shop | — | Browser / 3DS return relies on the webhook; the user sees nothing. |
| L-10 | Voucher purchase | Toast `addedToCart` "Přidáno do košíku" → cart; custom amount field `amountMin` "Částka (min. 100 Kč)" | OK |

## M. Documents & scanner (`document_scanner_screen.dart`, `documents_screen.dart`, docs gate)

| ID | Trigger | Surface / cs text | Action | Gap |
|---|---|---|---|---|
| M-01 | No camera | Inline centred text `cameraNotAvailable` "Kamera není dostupná" | — | **DEAD**: no gallery fallback, no back hint. |
| M-02 | Camera init error / **permission denied** | Inline "Chyba kamery: {raw CameraException}" | — | **DEAD + raw.** No "Povolit v nastavení" (`openAppSettings`) and no "Nahrát z galerie". |
| M-03 | Capture permission error | result overlay `errCameraPermission` "Přístup ke kameře zamítnut.\n\nPovolte kameru v Nastavení → Aplikace → MotoGo24." | retry | No settings button (text only). |
| M-04 | Photo saved, OCR read nothing | success `docPhotoSavedNoOcr` "Fotka dokladu byla uložena. Údaje se nepodařilo automaticky přečíst, ale doklad je nahraný. Přístupové kódy dostanete po nahrání líce i rubu…" | "Pokračovat →" | OK |
| M-05 | Upload failed | `scanSaveFailed` "Záznam o dokladu se nepodařilo uložit na server.\n\nZkuste to prosím znovu. Pokud problém přetrvává, kontaktujte nás." **+ "[id \| upload_failed …]"** | retry | Diagnostics visible to the customer. |
| M-06 | OCR network / timeout / server | `errNetwork` "Chyba připojení k internetu.\n\nZkontrolujte Wi-Fi nebo mobilní data a zkuste to znovu." · `errTimeout` "Rozpoznávání trvalo příliš dlouho.…" · `errServerConfig` "Chyba konfigurace serveru.…Kontaktujte podporu." · `errServerUpstream` · `errServerGeneric` · `errOcrEmpty` · `errImagePrep` — each + a "[docType \| code \| HTTP n \| #n]" diagnostic | retry, after 3× → contact overlay (`scanHelpTitle` "Pomůžeme vám osobně", call +420 774 256 271, e-mail, `scanTryAgainAnyway`, `scanCloseScanner`) | Good structure; hide the diagnostics behind "Technické detaily". |
| M-07 | Fields missing on a side | `scanMissingDlFront` "Na přední straně ŘP nebylo rozpoznáno číslo ani datum platnosti. Bez těchto údajů nelze doklad ověřit." · `scanMissingDlBack` · `scanMissingFront` · `scanMissingBack` + per-step guidance `scanGuide*` + `errOcrHint` tips | retry | Good |
| M-08 | Finalize: a side missing | Toast 6 s `docsScanIncompleteTitle` "Doklady nejsou kompletní" / `docsScanIncomplete` "Některá strana dokladu chybí. Přístupové kódy dostanete až po nahrání líce i rubu OP (nebo pasu) a líce i rubu ŘP — chybějící stranu doplňte v Moje doklady." + "Chybí: líc OP, rub ŘP…" | → Home | The toast vanishes and the app **goes to Home**, not to the missing step. |
| M-09 | Finalize: sides OK, gate still blocks (DOB / 18+ / expired licence / group) | Toast 6 s `scanComplete` "Skenování dokončeno" / `codesStillWithheld` "Kódy se zatím neuvolnily. Dostanete je po nahrání…" + "Chybí: věk 18+ / platný ŘP (propadl {date}) / skupina ŘP {groups}" | → Home | This is the "documents rejected" equivalent. The titles say "complete" for a blocked state. No fix action (update the licence, contact). |
| M-10 | Doc delete / upload | Toast "Mažu..." → `deleted` "Smazáno" / `docRemoved` "Doklad odstraněn, nahrajte nový" or `deleteFailed` "Nepodařilo se smazat"; `uploaded` "Nahráno" / `docProcessed`; failure `scanFailed` "Nepodařilo se načíst" | — | WHY missing on failure. |
| M-11 | Docs list load error | `loadingError` "Chyba načítání" (red text) | — | No retry. |

## N. SOS (`features/sos/*`) — every incident path

The shared failure path for all incidents is `sosErrorMessage`: it returns `notLoggedIn` or `errUnknown` ("Došlo k neočekávané chybě.\n\nZkuste to prosím znovu."), shown in a **3 s toast**.

| ID | Trigger | Surface / cs text | Action | Hang | Gap |
|---|---|---|---|---|---|
| N-01 | Report (accident / breakdown): description + photo mandatory | sheet; hint `sosReportRequiredHint` "Popis a fotodokumentace jsou povinné — pomohou nám rychle reagovat." | `yesReport` | — | In an emergency the mandatory photo can block. The "Zavolat" escape is on the screen behind (the nonstop card). |
| N-02 | Sending | Toast `reportingIncident` "Hlásím incident..." / `sendingToCentral` "Odesílám na centrálu" | — | **RISK** (GPS 2 s+ + insert + upload, no timeout) | No progress or cancel. |
| N-03 | Incident create failed (offline, …) | Toast "Chyba" / `errUnknown` | — | — | **For an SOS this is critical.** It needs "Nepodařilo se odeslat — zavolej hned +420 774 256 271" with a call button, SMS fallback and an offline queue. |
| N-04 | Photo upload failed | Toast `photoUploadFailed` "Foto se nepodařilo nahrát" / `incidentCreatedNoPhoto` "Incident byl vytvořen bez fotodokumentace" | — | — | No "Doplnit fotky" later. |
| N-05 | Camera failed (gallery fallback also failed) | Toast `photoCaptureFailed` "Nepodařilo se vyfotit" / `tryAgainOrSkip` "Zkuste to znovu nebo přeskočte" | — | — | Says "přeskočte" though the photo is mandatory. |
| N-06 | Success | Toast + `/sos/done` | — | — | OK |
| N-07 | Share location | Toast `sharingLocation` "Zjišťuji polohu..." then **always** `locationShared` "Poloha sdílena" / `locationSharedMsg` "MotoGo24 obdržela vaši pozici" | — | — | **FALSE SUCCESS** when GPS is denied or off or the request failed. |
| N-08 | GPS denied while reporting | silent (lat/lng null) | — | — | WHAT: the customer does not know the position was not sent. |
| N-09 | Replacement: no bike selected / no active incident | Toast `selectReplacementMoto` / "Chyba" `noActiveIncident` "Žádný aktivní incident" | — | — | ACTION missing |
| N-10 | Replacement: none available | Inline `sosNoMotos` "Momentálně není dostupná žádná náhradní motorka. Zavolejte nám, domluvíme řešení.\n📞 +420 774 256 271" | — | — | The number is not tappable. |
| N-11 | Replacement: load error | `errorLoadingMotos` "Chyba načítání motorek" | — | — | No retry, no call. |
| N-12 | Replacement ordered | Toast `ordered` "Objednáno" / `replacementWillBeDeliveredFree` "Náhradní motorka bude přistavena zdarma" → `/sos/done` | — | — | OK |
| N-13 | Tow ordered | Toast `towOrdered` "Odtah objednán" / `towOrderedMsg` "MotoGo24 zařídí odtah motorky" | — | — | OK |
| N-14 | Theft | Toast `theftReported` "Krádež nahlášena"; validation `theftSecuredQuestion` / `theftSelectSecured`; "Volat 158" tile | — | — | OK |
| N-15 | Self-service repair invoice | Toast `invoiceUploaded` "Faktura nahrána" / `reimbursement7days` "Proplatíme do 7 dnů od doručení" or `invoiceUploadFailed`; `incidentCreateFailed` "Nepodařilo se vytvořit incident" | — | — | WHY missing on failure. |
| N-16 | Active incident banner | `activeSosIncident` "Aktivní SOS incident" + `tapToOpenDetail` | — | — | OK |
| N-17 | **Offline** | the global overlay covers SOS (R-01) | — | **DEAD** | **P0** |

## O. Ride recorder, navigation, routes community

| ID | Trigger | Surface / cs text | Gap |
|---|---|---|---|
| O-01 | Manual start OK | Snack `rideManualStarted` "Záznam jízdy běží 🛰️" + foreground notification `rideNotifTitle` "MotoGo24 zaznamenává jízdu" / `rideNotifText` | The entry point is buried (R3): Trasy "+" menu `rideManualStart` "Zaznamenat vlastní jízdu" (`rideManualHint` "Nemáš půjčenou motorku? Spusť si záznam trasy ručně…") and the Moje zážitky card. |
| O-02 | Start failed | Snack `rideManualFailed` "Záznam se nepodařilo spustit — přihlas se a povol polohu" | **One message for 4 causes** (not logged in / permission denied / denied forever / location services off). `GpsService.ensurePermission` silently opens system settings. No reduced-accuracy explanation. |
| O-03 | Stop: saved / too short / offline | `rideManualSaved` "Jízda uložena mezi projeté jízdy" · `rideManualTooShort` "Jízda byla kratší než 1 km — neuložila se" · `rideManualStopFailed` "Jízdu se nepodařilo uložit (bez připojení). Zkusím to znovu, jakmile bude signál." | Good copy. A 4 s snack only; no "Zobrazit jízdu" action. |
| O-04 | Auto recording during a rental | silent | No visible "nahrává se" indicator outside the notification. |
| O-05 | Navigation: permission denied | card `routeNavNoLocation` "Pro navigaci povol přístup k poloze v nastavení telefonu." | **No button** (open settings / retry). The settings jump happens before the explanation. |
| O-06 | Navigation: locating / off route | `routeNavLocating` "Hledám polohu…" · `routeNavOffRoute` "Mimo trasu — přepočítávám…" | No "GPS signal lost" state; the stream has no `onError` (location turned off mid-ride → unhandled). The **offline overlay covers navigation**. |
| O-07 | Route save / submit | Snack `routeSaved` "Uloženo do Mých zážitků ✅" · `routeSaveErr` "Uložení se nepovedlo" · `poiSubmitErr` "Odeslání se nepovedlo" · `routeSubmitDecodeErr` "Odkaz se nepodařilo načíst" · `routeSubmitNeedPoints` "Přidej aspoň 2 body…" · `routeSaveLogin` "Přihlas se pro uložení trasy" | WHY missing on errors. Login requirement for submit / place: **wrong text** `poiRateLogin` "Přihlas se a ohodnoť". No login button. |
| O-08 | Share ride | Snack `rideShareFailed` "Sdílení se nepodařilo" | WHY |
| O-09 | Road routing failed (map) | `routesMapLineFailed` "Trasu po silnici se nepodařilo spočítat" | FIX |
| O-10 | Routes list error | `routesError` "Trasy se nepodařilo načíst" + `routesRetry` "Zkusit znovu" | Good model |

## P. AI agent, messages, reviews

| ID | Trigger | Surface / cs text | Hang | Gap |
|---|---|---|---|---|
| P-01 | Thinking | bubble `aiThinking` "⏳ Přemýšlím..." | **RISK** (`functions.invoke`, no timeout) | No cancel. |
| P-02 | Request failed | bot bubble `aiCommError` "❌ Chyba komunikace s AI agentem. Zkuste to znovu." | — | No "Odeslat znovu" (retype). Offline, rate limit and server error are not told apart. |
| P-03 | Empty reply | `aiProcessError` "Omlouvám se, nepodařilo se zpracovat dotaz." | — | FIX |
| P-04 | Suggests SOS | `aiSuggestSos` "🆘 Agent doporučuje nahlásit SOS incident." + card `reportSosIncident` | — | OK |
| P-05 | Photo limit / error | Toast `aiPhotoLimit` "Maximálně 3 fotky na zprávu" · `aiPhotoError` "Fotku se nepodařilo načíst" | — | OK |
| P-06 | Message send failed (thread) | Toast "Chyba" / `messageSendFailed` "Zprávu se nepodařilo odeslat" (text restored into the input) | — | WHY missing (offline vs server); retry = tap send again. OK-ish. |
| P-07 | New conversation without a subject | Toast `enterSubject` "Zadejte předmět konverzace" | — | OK |
| P-08 | Messages list error | plain red "Chyba" | — | WHAT/WHY/ACTION all missing |
| P-09 | Rating save failed | Toast "Chyba" / `ratingFailed` "Hodnocení se nepodařilo uložit" | — | No retry. |
| P-10 | Google link failed | Toast `rfGoogleBtn` / `rfLinkFailed` "Odkaz se nepodařilo otevřít." | — | OK |
| P-11 | Private feedback | validation `rfEmpty` "Napiš nám prosím aspoň pár slov."; failure `rfSendFailed` "Zprávu se nepodařilo odeslat. Zkus to prosím znovu." | — | OK |

## Q. Auth (login, registration, reset, biometrics, session)

The auth surface is `Toast` for 7–9 s. `AuthErrorMapper` covers all 8 languages; unknown languages fall back to Czech.

| ID | Trigger | cs title / body | Action | Gap |
|---|---|---|---|---|
| Q-01 | Empty fields | "Chyba" / `fillEmailAndPassword` "Vyplňte email a heslo" | — | OK |
| Q-02 | Unknown e-mail | Dialog `loginUnknownEmailTitle` "Účet nenalezen" / `loginUnknownEmailBody` "Tento e-mail u nás zatím nemáme. Vytvořte si prosím registraci." | Zrušit / REGISTROVAT | Good |
| Q-03 | Wrong password | `credentialsTitle` "Nesprávný e-mail nebo heslo" / `credentialsBody` "Zkontrolujte překlepy a velká písmena. Nové heslo si můžete nechat poslat přes „Zapomenuté heslo"." | (link is elsewhere) | ACTION button "Obnovit heslo" missing in the toast. |
| Q-04 | E-mail not confirmed | `unconfirmedTitle` "E-mail zatím není potvrzený" / "Otevřete e-mail od MotoGo24 a klepněte na potvrzovací odkaz. Podívejte se i do složky Spam / Hromadné." | — | No "Poslat znovu". |
| Q-05 | Network | `networkTitle` "Nepodařilo se spojit se serverem" / "…Máte-li zapnutou VPN … vypněte ji. **Účet zatím nevznikl.**" | — | The last sentence is wrong for login. |
| Q-06 | Rate limit | `rateLimitTitle` "Příliš mnoho pokusů po sobě" / "**Registraci** jste zkoušeli několikrát…" | — | Wrong for login. |
| Q-07 | Register: e-mail taken | Dialog `emailTakenTitle` "Tento e-mail už u nás účet má" / "…Přihlaste se stejným e-mailem; heslo si můžete nechat poslat přes „Zapomenuté heslo"." | Zrušit / Přihlášení | Good |
| Q-08 | Register: weak password / invalid e-mail / server / disabled / generic | `weakPasswordTitle` "Heslo je příliš slabé" … `serverTitle` "Chyba na naší straně" … `genericSignUpTitle` "Registraci se nepodařilo dokončit" + `genericBody` "…přepošlete nám tento text:" + raw detail | the wizard jumps to the faulty step | Good. The raw detail is intentional. |
| Q-09 | Register field validation | Toast per field (title = field name), e.g. `licenseMinValid`, `consentRequiredMsg` | — | OK |
| Q-10 | Reset: send code | `codeSent` "Kód odeslán" / `checkEmail` "Zkontrolujte si e-mail"; error `serverUnavailable` "Server je nedostupný, zkuste to prosím za chvíli." / `resetFailed` "Reset hesla se nepodařil." | — | WHY thin |
| Q-11 | Reset: verify OTP / set password | error = **raw GoTrue English** (e.g. "Token has expired or is invalid"); success `codeCorrect` "Kód je správný" → `passwordChanged` "Heslo změněno" / `loginWithNewPassword` | — | **raw / i18n** |
| Q-12 | Biometrics | `authCancelled` "Ověření zrušeno" · `bioVerified` "Ověřeno – přihlašuji..." · session gone → `sessionExpired` "Session vypršela – přihlašte se emailem" | — | Jargon |
| Q-13 | Token expired anywhere (`handleAuthError`) | silent sign-out → router redirect to login | — | **WHAT missing** ("Z bezpečnostních důvodů tě odhlásilo — přihlas se znovu"). Unsaved work is lost. |
| Q-14 | Change password (Profil) | `min8chars` / `passwordsDoNotMatch`; error = raw `AuthException.message`; success "Hotovo" / `passwordChanged` | — | raw |

## R. App-level / cross-cutting

| ID | Trigger | Surface / cs text | Action | Hang | Gap |
|---|---|---|---|---|---|
| R-01 | Connectivity goes to `none` | full-screen dark overlay 📡 `noInternet` "Žádné připojení k internetu" / `offlineDesc` "Pro používání MotoGo24 je potřeba připojení k internetu.\nZkontrolujte Wi-Fi nebo mobilní data." | `retryBtn` "ZKUSIT ZNOVU" (re-checks the interface only) | **DEAD while offline** | Blocks SOS, call, navigation, the recorder and offline-safe content (codes!). Only fires on a *change*: starting the app offline shows no overlay → screens show raw errors. Wi-Fi without internet is not detected (`pingSupabase` is unused). `requireOnline` is unused. |
| R-02 | Flutter build error | `ErrorWidget`: 🔄 `restartApp` "Restartujte aplikaci" / `sorryInconvenience` "Omlouváme se za komplikace." | none | **DEAD** | No "Zpět", "Domů", "Restartovat" or "Nahlásit". |
| R-03 | Force update (`app_settings` min version) | blocking dialog `updateRequired` "Vyžadována aktualizace" / `updateRequiredDesc` "K dispozici je nová verze aplikace (v{version}). Pro pokračování je nutné aplikaci aktualizovat." | `updateNow` "AKTUALIZOVAT" → Play | — | No SOS or phone escape (risky mid-rental). No "co je nového". |
| R-04 | Optional update | dialog `updateAvailable` "Nová verze k dispozici" / `updateAvailableDesc`; flexible download snack `updateDownloaded` "Aktualizace stažena. Restartujte pro instalaci." + `updateRestart` "RESTARTOVAT" | Později / AKTUALIZOVAT | — | OK |
| R-05 | Home load error | inline **"Chyba: " + raw exception** | none | — | raw, no retry |
| R-06 | Catalogue / moto detail load error | **"Chyba: " + raw** · `catalogLoadingError` "Chyba načítání" · `detailNotFoundMessage` "Motorka neexistuje" | none | — | raw, no retry, no back to the catalogue |
| R-07 | Reservations list error | ⚠️ `loadingError` "Chyba načítání" + "Zkusit znovu" | retry | — | WHY missing; otherwise a good model |
| R-08 | Reservation detail error / not found | Scaffold "Detail" (hard-coded) + "Chyba: {raw}" / `reservationNotFound` "Rezervace nenalezena" | back only | — | raw, title not translated |
| R-09 | Profile load error | `profileLoadError` "Chyba načítání profilu" in a bare `Scaffold` | **none, no AppBar** | **DEAD** | |
| R-10 | Product detail error | "Chyba" in a bare `Scaffold` | none | **DEAD** | |
| R-11 | Contracts / invoices / docs list error | `loadingError` red text | none | — | no retry |
| R-12 | Profile save / account delete error | Toast "Chyba" / **raw `$e`** | — | — | raw |
| R-13 | Payment methods load error | `cardsLoadError` "Chyba při načítání karet" | — | — | no retry |
| R-14 | Unknown deep link / push route | GoRouter default error page (English, technical) | — | **DEAD-ish** | No `errorBuilder`. |
| R-15 | Permissions screen | statuses `allowedLabel` / `deniedLabel`, `openPhoneSettings`, `allowAllAgain` → toast `permsRerequested` | settings | — | OK (central place). The feature screens do not link to it. |
| R-16 | Language / currency / consents saved | Toast `languageChanged`, `settingsSaved`, `consentsLockedActive` "Během aktivní rezervace nelze souhlasy odebrat." | — | — | OK |

---

## S. Deep dive — the Stripe minimum (15 Kč)

- **Stripe rule.** Stripe rejects a CZK PaymentIntent below 15.00 Kč with `amount_too_small` (HTTP 400).
- **Server.** Only the app shop path guards it (`process-payment:430`, `{code:'below_minimum', error:'Minimální částka platby kartou je 15 Kč.'}`). The booking, SOS and extension paths have **no guard**, so `stripe.paymentIntents.create` throws:
  - In the **Payment Sheet path** this hits the outer catch → `500 {error:'Payment processing failed: <Stripe msg>'}` with no `code`.
  - In the **saved-card path** it is caught → `200 {off_session:true, error_code:'amount_too_small', message:<Stripe msg>}`.
- **App — who can produce < 15 Kč:**
  - The edit surcharge: any `effDiff > 0`, e.g. a later return time, a gear add-on of a few Kč, a rounding difference after a loyalty discount, or delivery-fee deltas.
  - The swap: `net > 0.5`.
  - A new booking whose voucher or promo leaves 1–14 Kč.
  - A shop order (guarded on the server).
  - **Nowhere in the app is the amount checked before payment.**
- **What the customer sees today:**
  - New card, cs: Sheet "Platbu nelze zpracovat" / "Payment processing failed: Amount must convert to at least …" (raw English) + "(Pokus 1 z 3)".
  - New card, other languages: "Platba se nezdařila" / "Platbu se nepodařilo dokončit a žádné peníze nebyly strženy. Zkuste to prosím znovu, nebo použijte jinou platební metodu." The **advice is useless**: every method fails the same way.
  - Saved card, cs: "Platba kartou zamítnuta" + raw message + "Zkuste platbu znovu, použijte jinou kartu, nebo zaplaťte přes Google Pay." This is **false** (the card is fine), and "Zaplatit jinou kartou" fails the same way.
  - Shop, cs: "Platba kartou zamítnuta" + "Minimální částka platby kartou je 15 Kč." + the card advice. Other languages: generic.
  - After 3 attempts: "Platba se nezdařila … platbu můžete dokončit později v sekci Rezervace". For an edit this is false: the change is **not saved**, and nothing can ever complete it.
- **Needed (design + code):** a dedicated state "Doplatek je menší než 15 Kč", decided **before** the payment screen. It must say what (the amount is below the card minimum), why (the payment processor limit) and how (the business choice: waive the difference and save the change for free, or round it up to 15 Kč with an explanation, or settle it at pick-up). It must have a primary action that **completes the change**. The same rule must apply to the shop (`below_minimum` → "Přidej zboží za X Kč nebo zvol osobní odběr…").

## T. Proposed structure for the "Stavy" board (one template, every state)

**Template.** A full-screen result or a bottom sheet with:
- an icon + rank-tinted ring (success = green glow, pending = amber pulse, error = red, info = blue);
- **Title = what happened** (one line);
- **Why** (one sentence, human);
- **How to fix** (one or two steps);
- **Primary action** (always present, never only "OK");
- a secondary action;
- the support row "Zavolat +420 774 256 271 · Napsat do Zpráv";
- a collapsible "Technické detaily" (code, reference) instead of raw text in the body.

Toasts are only for non-blocking confirmations. Errors that need action must never be a 3 s toast. Use tykání consistently.

**Board sections (suggested, covering everything above):**
1. **Payment success**: G-01 (+ docs a/b/c, late gate), G-02, G-03, G-04, G-06, G-08/G-09, G-07 (shortening + refund).
2. **Payment pending**: H-01 (webhook delay, with live switch to success and the FAB suppressed), E-02, E-12, D-14, the Android sheet-dismiss guard (E-09).
3. **Card declined family**: D-04 funds, D-05 blocked, D-06 limit, D-07 expired, D-08 CVC, D-09 bank block, D-10 generic, E-04 number / processing.
4. **3-D Secure**: D-03 / E-03 (failed vs cancelled — not counted as an attempt).
5. **Wallet**: E-06 Google Pay failed, E-07 unavailable, E-11 Apple Pay not sent, E-05 cancelled.
6. **Amount below the 15 Kč minimum** (§S): edit, swap, booking, shop.
7. **Server refusal before charge**: F-01a…k, F-02 already paid (as success), F-04 price recalculated (with "Obnovit cenu").
8. **Network / timeout / server down / session expired**: D-15 (with "ověřujeme, zda platba neproběhla"), D-16 / Q-13, R-01 redesigned as a banner with offline-safe features (codes, SOS call, navigation, recorder).
9. **Booking conflict**: C-04…C-07 (bike taken meanwhile → alternatives: other dates / similar bikes / another branch), B-05, B-12, J-06, J-17.
10. **Payment timer / attempts**: H-04 expired (with "Rezervovat znovu"), H-05 max attempts (with the real 30-min deadline), H-07 auto-cancelled.
11. **Documents**: M-08 incomplete, M-09 blocked by the gate (expired licence / age / group — the "rejected" equivalent), M-02 camera permission (settings + gallery), M-06 OCR errors, J-19 codes withheld / protocol first.
12. **Edit / cancel results**: G-07, G-07a refund failed, G-14 cancel confirmation (new), J-15 cancel error, J-07 stale.
13. **Shop & voucher**: L-04/L-05/L-06/L-08, G-04, L-10.
14. **SOS**: N-03 send failed (call now + queue), N-07 location share honest result, N-08 GPS denied, N-10/N-11 no replacement, N-12/N-13/N-14/N-15 confirmations, N-17 offline.
15. **Permissions**: location (navigation O-05, recorder O-02, SOS N-08), camera (M-02/M-03, SOS N-05), notifications (recorder foreground) — each with "Povolit" / "Otevřít nastavení" / an alternative.
16. **Ride recorder**: O-01 started, O-02 split into 4 causes, O-03 saved / too short / queued offline, O-04 recording indicator, O-06 GPS lost.
17. **AI & messages**: P-01 timeout, P-02 retry-send, P-06/P-08.
18. **App-level**: R-02 crash fallback (Domů / Restartovat / Nahlásit), R-03 force update (+ SOS call), R-14 unknown link, R-05/R-06/R-08/R-09/R-10 load errors with retry + back, G-16 level-up (unchanged, reference only).

## U. Hang / dead-end register (for the code audit)

**Unbounded awaits (spinner can stay):**
- `_createDraftBooking` insert (`payment_screen.dart:504`)
- `booking_discounts` insert (`:526`)
- post-payment `bookings.update` and `replaceModeledExtras` (`:1310-1320`)
- `loadMotoPickupInfo` / `loadBookingPickupInfo` before navigating to the result
- `handleNextAction` / `confirmPayment` / `confirmPlatformPayPaymentIntent` (SDK)
- `ai-moto-agent` invoke
- `createSosIncident` + `uploadSosPhotos`
- `create_shop_order` RPC
- `cancel_booking_tracked` RPC (dialog spinner)
- `split_booking_moto_swap` dry-run / commit
- `reschedule_booking_free`

**Timers that ignore in-flight work:** the payment countdown fires `_onTimeout` while `_processing`.

**Dead ends:** R-01 offline overlay, R-02 ErrorWidget, R-09 profile error, R-10 product error, M-01/M-02 camera errors, O-05 navigation denied (text only), R-14 unknown route, §S below 15 Kč (loop until max attempts).

**Silent failures that look like success or another cause:** N-07 location share, J-06/J-17 offline = "obsazeno", B-12 availability error = all free, G-02/G-03 swallowed apply / commit errors, `_saveBookingExtras` / `EmailService` / `InvoiceService` fire-and-forget, `paymentMethodsProvider` → [] (the saved card silently ignored).
