# Journey B state/action matrix (choose bike -> drive away) — original look vs. v2

Source: current code with the kill-switch off (old look), compared with released 4.1.3 (70a94933) where a file was touched. Guard records are in `inv_mx-order.json` (mx-order-01 … mx-order-61). Verdicts: 58 HOLDS, 2 WEAKER (mx-order-15 and mx-order-24), 1 UNCLEAR (mx-order-61), 0 BYPASS.

Legend: **B** = blocked, **R** = redirected, **W** = warned, **A** = allowed, **-** = not reachable or not applicable. Numbers are record ids (mx-order-NN). Bold cells mark where v2 differs from the old look.

| State \ Action | change dates | change bike | add gear / extras | apply promo | submit (to payment) | pay (card / saved / wallet) | pay again | leave & come back | restore cancelled | see door codes | protocol / kiosk | cancel |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Not logged in | R login 01 | R login 01 | - | - | R login 01 | R login 01 | - | - | - | - | - | - |
| Dates not chosen | A calendar; past/occupied days B 03 | A | A | A | B CTA grey 06 (the v2 dock also says why); detail REZERVOVAT grey 04 | - | - | - | - | - | - | - |
| Dates partly unavailable | B range over a busy day 03; catalog hides busy bikes 02 | A | - | - | B own overlap 09; v2 also locks a carried busy range | B at insert 29 | - | - | - | - | - | - |
| Occupancy failed to load | W error + retry 07 | A | A | A | B CTA locked 07 (added on branch, both looks) | - | - | - | - | - | - | - |
| Licence missing / insufficient / expired | A | A (pick another) | A | A | B red/amber banner 08, 13 | not re-checked at payment 28 | - | - | - | codes withheld by docs gate 48 | - | - |
| Profile incomplete | A | A | A | A | B + "Doplnit profil" 12; re-checked at payment 28 | B at insert 28 | - | - | - | - | - | - |
| Own overlapping booking | W 09 | A | A | A | B 09 | B server trigger | - | - | B own_overlap 45 | - | - | - |
| Booking draft (unsent) | A | A | sizes required 16; children / self-service filters 17-22 | rules 23 | B consents 15, sizes 16, lead time 11, min/max 10 | - | - | old: fresh draft on every entry; **v2 keeps consents (15 WEAKER) and codes (24 WEAKER)** | - | - | - | - |
| Bike taken meanwhile | - | - | - | - | A form | B sheet "motorka obsazená" 29 | - | - | B moto_unavailable 45 | - | - | - |
| Created, unpaid, inside 30 min | via edit only | - | - | - | - | A countdown 25; FAB / strip / Home ticket 41 | B while processing 26 | A FAB resumes with remaining time 25, 41 | - | - | - | A with confirmation 43 |
| Created, unpaid, after 30 min | - | - | - | - | - | B "Čas vypršel" 25 | B | shown as cancelled 44 | A from tomorrow, server-checked 45 | - | - | - |
| Payment in progress | - | - | - | - | - | B second tap 26; card sheet locks 34 | B 26 | confirm to leave 27; resume check 39 | - | - | - | - |
| Payment result uncertain | - | - | - | - | - | B verify first 35 | B FAB "ověřuje se" 42 | result page / strip 35, 42 | - | - | - | - |
| Payment failed 3 times | - | - | - | - | - | B max attempts 36 | B 36 | - | - | - | - | - |
| Server refuses amount / stale | - | - | - | - | - | W new amount / 15 Kč / reload 37 | A with the server amount 37 | - | - | - | - | - |
| 100 % discount / ≤ 1 Kč | - | - | - | - | - | A only if the server confirms 38 | - | - | - | - | - | - |
| Paid, documents missing | edit 55-60 | swap 55 | edit 57 | - | - | - | - | docs CTA on confirmation 46; docs FAB / strip 47 | - | B withheld + "Nahrát doklady" 48 | - | A 54 |
| Paid, complete, before pickup day | free move 55, extend 57, calendar 59, server refusals 58 | swap 55 / licence-filtered list 60 | edit extras 57 | - | - | surcharge -> payment (same guards 25-39) | B pending surcharge 57 | - | - | hidden until the rental term 48 | - | A storno % 53, 54 |
| Pickup day before 12:00 (discount) | change-time CTA 51 | - | - | - | - | - | - | - | - | codes visible, kiosk refuses until 12:00 51 | kiosk pickup_too_early 51 | A 54 |
| Self-service branch | - | - | no trailer 18; delivery locked 20; no return time 21; size ranges 22 | - | - | - | - | - | - | swap-held code 49 | protocol-first note 50; hint 52 | - |
| Staffed branch | lead time +1 h 11 | - | trailer only if free 19 | - | - | - | - | - | - | - | protocol by staff | - |
| Delivery | lead time +6 h 11; address required in edit 57 | - | - | - | - | - | - | - | - | - | - | - |
| Handed over (active) | start locked 56 | swap only 55 | hidden 56 | - | - | - | - | - | - | A | - | B no cancel 53 |
| Gear-only booking | not traced 61 | - | - | - | cannot be created in the app | - | - | - | - | locker only (server) | - | - |
| Children bike | overlap exempt 09 | - | no passenger gear 17 | A | guardian consent 15; no licence or profile licence fields 08, 12 | - | - | - | - | docs not needed 46 | - | - |
| Promo / voucher applied | A | **v2 carries the code to another bike 24** | A | duplicates / second percent / invalid B 23 | A | free only if the server confirms 38 | - | **v2 keeps the code on re-entry 24** | B voucher/promo unavailable 45 | - | - | - |

## Not holding in v2
- **mx-order-15 (WEAKER): consents for terms (VOP), personal data (GDPR) and the guardian.** The old look always starts with unticked boxes (`booking_entry.dart:63-68`, `booking_models.dart:84-86`). When the customer comes back to the same bike, v2 keeps the boxes he ticked earlier (`booking_carry_v2.dart:33-46`). The owner decided this on 2026-10-22 ("nic nevyplňovat dvakrát"), but it is weaker than the old guard.
- **mx-order-24 (WEAKER): discount codes.** The old look drops all codes on every new entry. v2 carries them over, both to the same bike and to another bike (`booking_carry_v2.dart:33-46, :57`), and does not call `validate_promo_code` again. I could not prove that the server re-checks the code when the booking is inserted or paid: `process-payment/due-verify.ts` looks at promo codes only to compute the price floor for small remainders.
- **mx-order-61 (UNCLEAR): gear-only bookings.** The server hides them from the app. I did not trace what the edit screen does with a gear-only booking (moto_id NULL) in either look.

## Gaps in BOTH looks (not v2 regressions)
- The payment screen re-checks only login, bike, dates and profile completeness (`payment_screen.dart:573-608`). Licence, own overlap, lead time and min/max days are checked only in the booking form, so a stale draft opened through the deep link `/payment` skips them. The server enforces the overlap rules. I found no server check for licence, lead time or min/max days; the licence is enforced only later, by the documents gate on the door codes.
- The profile and licence checks fail open while the profile is still loading (`booking_provider.dart:216-217, 314-317`).

## Added on this branch to both looks (not in 4.1.3)
Lock while bike occupancy is unknown (07), confirmation before leaving a running payment (27), recovery of the customer's own older draft (30), payment-pending marker and "Platba se ověřuje" (35, 42), restore through a server RPC (45, reworked). v2 also adds stricter locks: a busy carried date range blocks both the booking form and the detail dock (04, 09).
