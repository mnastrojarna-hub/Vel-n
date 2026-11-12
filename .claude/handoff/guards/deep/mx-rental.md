# Journey C: during and after the rental (state × action matrix)

Scope: the Android tree `Motogo-app-main/motogo-app-flutter/lib`, original look (kill-switch off) compared with the v2 look. I checked the old files against 70a94933 where this branch touched them. The guard conditions for `sosAllowed`, `displayStatus`, `canMove` and the save button are identical to 4.1.3. Guard records are in `inv_mx-rental.json` (mx-rental-01 … 69).

## Overall result

**All 69 guards hold in the v2 look.**

The v2 screens are built inside the old screens and get their buttons and actions from the old code. The reservation detail, the edit screen, the SOS screens, the cancel dialog, the codes card and the profile all work this way, so each block runs through the same condition in both looks. I found no v2 path that skips a check.

Things to know (they apply to both looks, so they are not v2 regressions):

- **Late-return gap (owner decision):** once the last rental day has passed, the app shows the rental as "Dokončené" even if the bike is still out. Edit/extend and the SOS button on the detail disappear, and the rating card appears (`reservation_models.dart:413-414`).
- **Edit link not locked:** the edit link `/reservations/:id/edit` has no status check of its own. Only the buttons decide when it is offered.
- **Replacement list:** the SOS replacement-bike list is not filtered by driving licence.
- **Calendar taps:** on the v2 calendar, past and occupied days are drawn greyed or busy and cannot be tapped. The old look let the tap through and showed a text message instead.

Legend: ✅ allowed · ⛔ blocked · ⚠️ allowed with warning or condition · ↪ redirect · — not offered.

| State (displayStatus / DB) | Extend | Shorten | Shift dates (free) | Swap bike | Pay difference | Refund | Cancel | Door codes | SOS | Replacement bike | Record ride | Rate / review | Invoices / contract | Delete account | Log out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Upcoming, paid, before term (reserved) | ✅ calendar rules (01,27-29) | ✅ choose direction first; storno % warning (29,43) | ✅ only if not past start day (25) | ✅ only if paid (26,46-48) | ↪ payment; stale check; second payment blocked (40,41) | ✅ after save; partial refund reported honestly (43) | ⚠️ storno % dialog, no back while sending (19-21) | — hidden outside term (13) | — not offered | — | ✅ manual (59) | — | — | ⛔ server refuses (active_bookings) (67) | ✅ |
| Upcoming, unpaid (pending) | ⚠️ edit offered; surcharge goes to payment (40) | ⚠️ | — move needs paid (25) | — swap needs paid (26) | ↪ | — | ⚠️ (19) | — | — | — | ✅ | — | — | ⛔ (67) | ✅ |
| In term, not handed over (reserved, inRentalTerm) | ✅ start still changeable (24) | ✅ | ✅ only on the start day itself (25) | ✅ (26) | ↪ (40) | ✅ | ⚠️ cancel still offered (02) | ⚠️ withheld until documents; 12:00 gate; protocol first (05,14,16) | ✅ if paid (03) | — | ✅ | — | ✅ contract / protocols if they exist (07) | ⛔ (67) | ✅ |
| Active (handed over, DB active) | ✅ end only (24,28) | ✅ return day only, not in the past (29) | — (25) | ✅ if paid (26) | ↪ (40) | ✅ (43) | ⛔ not offered (02) | ✅ codes; withheld after swap (15) | ✅ (03) | — until SOS | ✅ auto + manual (59-61) | — | ✅ (07) | ⛔ (67) | ✅ no confirmation (68) |
| Last day | same as Active (no separate rule in the app) | same | — | ✅ date range ends today (46) | ↪ | ✅ | ⛔ | ✅ | ✅ | — | ✅ | — | ✅ | ⛔ | ✅ |
| Overdue (today > end, still DB active) | ⛔ shown as Completed, no edit (04) | ⛔ | ⛔ | ⛔ | — | — | ⛔ | ⛔ card hidden (13) | ⚠️ not on the detail; still from Profile / Home ticket (sosAllowed) (03,04) | — | ✅ | ⚠️ rating card shown (63) | ✅ final invoice button (06) | ⛔ | ✅ |
| Rental ended / completed | ⛔ (01) | ⛔ | ⛔ | ⛔ | — | — | ⛔ | ⛔ (13) | ⛔ (03) | — | ✅ manual | ✅ stars changeable; feedback not empty (63,64) | ✅ final invoice + contract + real protocols (06,08,09) | ✅ if no other booking (67) | ✅ |
| Cancelled | — | — | — | — | ↪ via restore → payment (22) | server-side | — | ⛔ | ⛔ | — | ✅ | — | — | ✅ (67) | ✅ |
| Refund pending / partial refund | ✅ edit | ✅ | ⛔ move needs paid (25) | ⛔ swap needs paid (26) | ↪ | ⚠️ "obsluha vyřídí" (43) | per state | per state | ✅ in term (03) | — | ✅ | per state | per state | ⛔ while active / upcoming | ✅ |
| Edit pending / paid change being written | ⛔ second change blocked (41) | ⛔ (41) | ✅ (server only) | ⛔ (41,48) | ⛔ (41) | — | per state | per state | per state | — | ✅ | — | — | per state | ✅ |
| SOS incident open | per state | per state | per state | per state | — | — | per state | per state | ⚠️ new serious report reuses the open one (51); banner (52) | ⚠️ only theft / major accident / major breakdown (56); fault choice first (53); secured question first (54) | ✅ | — | — | per state | ✅ |
| Replacement waiting (selecting / pending payment) | — | — | — | — | ↪ SOS payment | — | — | — | floating SOS strip on every screen (57) | ⚠️ needs a bike + address; only bikes free to the end (55) | ✅ | — | — | — | ✅ |
| Ride being recorded | per state | per state | per state | per state | — | — | per state | per state | ✅ | — | ⚠️ stop: <1 km discarded; controls busy-locked; v2 asks before stop (60,61) | — | — | per state | ✅ no guard |
| Rating already given | — | — | — | — | — | — | — | — | — | — | — | ✅ can change any time (not one-time) (63) | ✅ | — | ✅ |

Numbers in brackets are the record ids (mx-rental-NN) in `inv_mx-rental.json`.

## Where each block is enforced (old file → v2 path)

| Block | Old code | v2 path | Verdict |
|---|---|---|---|
| Detail buttons per state (edit, cancel, SOS, restore, documents, 12:00 gate) | `reservations/widgets/res_detail_tab_content.dart:171-350` | the same widget, drawn by `v2/res_detail_view_v2.dart:96-107` | HOLDS |
| Door codes / withheld / release via documents | `widgets/res_access_codes_card.dart:35-160` | the same card, v2 branch `:87-103` → `v2/res_codes_v2.dart` | HOLDS |
| Edit tabs, locks, save button, validations, payment handoff | `reservation_edit_screen.dart:173-178, 422-1255, 1416-1538` | `ResEditV2View` gets the same sections and the same saveAction (`:1546-1592`) | HOLDS |
| Calendar tap rules | `widgets/edit_reservation_calendar.dart:100-275` | the same `_onDayTap`; v2 disables past / busy cells | HOLDS |
| Bike change / swap filters (licence, free bikes, trailer) | `reservation_edit_moto_section.dart:98-113`, `reservation_swap_section.dart:100-114, 389, 409` | the same lists, passed to `res_edit_moto_v2.dart:123-139` and `res_edit_swap_v2.dart:142-190` | HOLDS |
| Cancel dialog (storno %, back blocked while sending) | `widgets/res_cancel_dialog.dart:28-127` | v2 branch inside the same State `:40-54` | HOLDS |
| Restore | `booking_restore.dart:36-243` | the same function from the v2 card and the v2 detail | HOLDS |
| SOS report, fault and secured choices, replacement | `sos/*.dart` | the same State hands its handlers to the v2 views | HOLDS |
| Floating strips (SOS, pay, documents, ride, cart) | `core/shell_fab_layer.dart:60-130` | `_v2Strips` `:255-340`, all stacked | HOLDS |
| Delete account / consents lock | `profile/profile_screen.dart:494-556`, `profile/widgets/consent_sheet.dart:87-170` | the same handlers | HOLDS |

## What I could not determine

- Whether the server rejects a direct `bookings` update (refund-side edit, `effDiff <= 0`) for a bike the customer's licence does not allow. `license_insufficient` exists only in the paid-change RPC path.
- The name of the database safeguard that silently keeps the dates, bike and price of a paid booking (the app reacts to it in `reservation_edit_screen.dart:1149-1166`).
- Whether the server refuses rating a non-completed booking (`rateBooking` updates the table directly).
- `customer_restore_booking` exists only in the pending migration `supabase/migrations/20261112a02_customer_restore.sql`. It is not yet listed in `SUPABASE_BACKEND_STATE_3.md`.
