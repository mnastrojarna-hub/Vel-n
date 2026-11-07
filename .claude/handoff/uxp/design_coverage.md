# 4 · COVERAGE (flag ON) — every page / sheet / dialog / overlay → owner

Legend: v2 today = y (v2 look) · p (partial / hybrid: old body in the v2 frame or only some parts) · n (old look) · t (only themed by `MgThemeV2.overlay`) · — (not reachable with the flag ON / dead code). Owner: FND = foundation, SH / CB / RP / PS / ASM / RR = package, EXC = exception. After all packages, nothing with the flag ON stays old except EXC rows.

| Area | Surface | File | v2 today | Board | Owner (item) |
|---|---|---|---|---|---|
| Global | Intro overlay (first launch) | core/widgets/moto_fx.dart:450 (call main.dart:499) | n | Prihlaseni Úvod | SH (SH-41) |
| Global | Language overlay | core/overlays/onboarding_overlays.dart:18 | n | Prihlaseni Jazyk | SH (SH-01) |
| Global | Permission overlay Android / iOS 5.1.1(iv) | onboarding_overlays.dart:135 (platform) | n | Prihlaseni Oprávnění | SH (SH-01; iOS button set kept) |
| Global | Offline full-screen overlay + Wi-Fi-without-internet strip | core/offline_guard.dart:207-381 (platform) | n | Stavy 8.x | SH (SH-02; banner variant = OD) |
| Global | Force update dialog | core/update_check_provider.dart:99 (platform) | n | Stavy 19.2 | SH (SH-03) |
| Global | Optional update dialog (Android in-app) | core/in_app_update_service.dart:152 | n | Stavy 19.3 | SH (SH-03) |
| Global | Crash screen (ErrorWidget.builder) | main.dart:90-125 | n | Stavy 19.1 | SH (SH-04) |
| Global | Unknown link page | core/widgets/route_error_page.dart | y | Stavy 19.7 | — |
| Global | Foreground push banner (door codes / message) | core/push/notification_handler.dart:35 | n | V22 §6.4 push banner | SH (SH-43) |
| Global | Toasts `showMotoGoToast` (131 calls) | features/auth/widgets/toast_helper.dart:9 | n | Stavy T5 | FND (FND-7) |
| Global | v2 toasts with action / error snack | core/v2/widgets/mg_toast.dart, core/widgets/error_feedback.dart | p (narrow text) | Stavy T5 | FND (FND-7) |
| Global | Logic snackbars (recorder notices, edit errors, routes) | ride_recorder_watcher.dart:130, reservation_edit_screen.dart:1458, routes/* | t | Stavy T5 | keep themed (theme = v2 look) |
| Global | Legacy error view / loading / stale note / error, progress, discard dialogs | core/widgets/state_views.dart, error_feedback.dart → core/v2/states/legacy_*_looks.dart | y (hierarchy fix) | Stavy T1–T3, T6 | FND (FND-6) |
| Global | Level-up celebration | features/loyalty/loyalty_levelup_overlay.dart | unchanged | Oslava | EXC (owner "lvl up video neměň") |
| Global | Native permission dialogs, biometric prompt, camera / gallery / share / settings, tel: / mailto: / maps, Play in-app update UI | system | — | — | EXC (system) |
| Shell | AppShellV2: nav, AI FAB, status strips, top banner | core/v2/shell/app_shell_v2.dart, core/shell_fab_layer.dart | y | Main / all | FND (FND-15/16/17) + SH (SH-06/07) |
| Shell | Strip ✕ "Zrušit rezervaci?" | core/shell_fabs.dart:44-59 | n | Stavy T6 | SH (SH-05) |
| Shell | "+n" strip list sheet | (new per v1 C2) | — | V2 §4.4 | SH (SH-07) |
| Shell | paidAfterRestart snackbar | core/shell_paid_listener.dart:23 | t | T5 | SH (SH-44) |
| Shell | Payment-running confirm on tab tap | features/payment/payment_ui_helpers.dart:17 | t | Stavy T6 | PS (PS-14) |
| Shell | AI chat `/ai-agent` + photo sheet | features/messages/ai_agent_screen.dart | y | AI chat | — |
| Domů | Home S0–S10, loading, errors, review card | features/home/v2/** | y (fidelity fixes) | Main | SH (SH-06…40) |
| Domů | Date sheet / club rules sheet / nickname dialog / banner full text | home_date_sheet_v2.dart, home_club_card_v2.dart, nickname_provider.dart:67 | y | Main | SH (copy CB-24) |
| Domů | Tier preview sheet | (new per board) | — | Main "KLEPNI A UKÁŽEME TI VZHLED" | SH (SH-39) |
| Motorky | `/search` find / grid / calc, header, empty | features/catalog/v2/** | y | MotoKatalog, Kalkulacka | CB (CB-06…30) |
| Motorky | List loading | motorky_screen_v2.dart:166 | n (spinner) | MotoKatalog | CB (CB-08) |
| Motorky | Filter sheet content | widgets/moto_filter_panel.dart | p | MotoKatalog "Filtr motorek" | CB (CB-01) |
| Motorky | Compact sticky bar | (board) | — | MotoKatalog "kompaktní lišta" | CB (CB-07) + FND-14 |
| Motorky | Date sheet, calc picker sheet | catalog_date_sheet_v2.dart, calc/* | y | Main / Kalkulacka | CB (CB-19) |
| Detail | `/moto/:id` detail, pager, loading / gone / error, manual card | catalog/v2/detail/**, moto_detail_page.dart | y (error = legacy look) | MotoDetail | CB (CB-12…17, CB-21) |
| Detail | Fullscreen gallery (also branch photos) | widgets/fullscreen_gallery.dart | n | MotoDetail viewer | CB (CB-02) + FND-10 |
| Detail | Video player controls | widgets/moto_video_player.dart | n | MotoDetail | CB (CB-23) |
| Booking | `/booking` form, calendar, warnings, dock, address sheet, price / promo row / note / consents | features/booking/v2/**, core/booking_form_*.dart | y | Booking | CB (CB-10/11/16) |
| Booking | Passenger gear + boots size sheets | core/booking_size_dialogs.dart | n | Booking | CB (CB-03) |
| Booking | Promo code dialog | core/booking_form_promo_section.dart:30 | n | Booking | CB (CB-04) |
| Booking | Map picker | features/booking/widgets/map_picker.dart (platform) | n | V22 §6.4 addr-picker | CB (CB-05) |
| Booking | Time dropdown menu | core/widgets/time_dropdown_field.dart | n | Booking | CB (CB-22) |
| Booking | Calendar busy-day / busy-range feedback | features/catalog/widgets/availability_calendar.dart:110-146 | n (silent / SnackBar) | V22 §3.3 | CB (CB-24) |
| Booking | `showPromoBottomSheet` | booking_ui_helpers.dart:889 | — dead code | — | none |
| Payment | `/payment` new booking | features/payment/payment_screen.dart | n | Booking step 3 | PS (PS-01) |
| Payment | `/payment` resume / restore / edit / swap / SOS (`/sos/payment`) / shop | payment_screen.dart, payment_header_widgets.dart | n | Booking "Režim platby" | PS (PS-02) |
| Payment | `/success` thank-you | payment_confirmation_screen.dart | n | Stavy 1.1 | PS (PS-03) |
| Payment | `/payment-result` (success / pending / attention / failed / not paid) | payment_result_screen.dart | n | Stavy 1–2 | PS (PS-04) |
| Payment | Card payment sheet Android / iOS (+ iOS Apple Pay "OK" dialog) | widgets/card_payment_sheet.dart (platform) | n | Booking wallet sheet | PS (PS-05) |
| Payment | Payment error sheet (payment, checkout, booking restore, reservation edit) | widgets/payment_error_sheet.dart | n | Stavy 3–10 | PS (PS-06) |
| Payment | Upsell section (flag off) | widgets/upsell_section.dart | n | Booking | PS (PS-07) |
| Payment | Payment methods + delete dialog + Android add-card sheet | payment_methods_screen.dart (platform) | n | Profil | PS (PS-13) |
| Payment | Stripe 3-D Secure page, Google Pay / Apple Pay sheets + buttons, CardField internals | Stripe / OS | — | — | EXC (not ours) |
| E-shop | `/shop` | features/shop/shop_screen.dart | p (back + status bar) | Profil e-shop | PS (PS-08) |
| E-shop | `/shop/:id` product | product_detail_screen.dart | p (loading / error) | Profil e-shop | PS (PS-09) |
| E-shop | `/cart` | cart_screen.dart | n | Profil / Stavy 13.1 | PS (PS-10) |
| E-shop | `/checkout` | shop_checkout_screen.dart | n | Profil "Doručovací údaje" | PS (PS-11) |
| E-shop | `/voucher` | voucher_screen.dart | n | Profil | PS (PS-12) |
| Rezervace | List, detail (all statuses, codes, late gate, delivery, SOS), procedure sheet, payment details, history, docs rows, rating card | features/reservations/v2/** | y (fidelity fixes) | Reservation | RP (RP-06…30) |
| Rezervace | Edit chooser + 8 intents + calendar + price + dock + confirm / refund + load states, edit size pickers | v2/res_edit_*_v2.dart, widgets/reservation_edit_extras_section.dart | y | Reservation Úprava | RP (RP-11/18/27) |
| Rezervace | Cancel confirm / done / fail | v2/res_cancel_v2.dart | y | Stavy 12.21–23 | RP (RP-21) |
| Rezervace | Ride feedback sheet | widgets/ride_feedback_sheet.dart | n | V21 §5.5 | RP (RP-04) |
| Rezervace | "Jízdy z výpůjčky": trip card, trip detail, merge, trip dialogs | routes/ride_booking_section.dart, ride_trip_card.dart, ride_trip_ui.dart | n | Zazitky | RR (F-10) |
| Rezervace | Old list `_CancelDialog` | reservations_screen.dart:224 | — (old list only) | — | none |
| Profil | Hub, personal form, nickname, settings sheets, delete dialog, consent sheet, permissions screen | features/profile/v2/**, profile_screen.dart | y | Profil | RP (RP-19/25/28) |
| Profil | `showPermissionsSheet` | profile/widgets/settings_sheets.dart:248 | — dead code | — | none |
| Profil | Moje doklady, doc-kind sheet, delete dialog, faktury, smlouvy | features/documents/v2/** | y | Profil | RP (RP-22) |
| Profil | Document viewers DocWebView / PdfPages | documents/doc_webview_screen.dart, pdf_pages_screen.dart | n | V22 §6.2 viewer | RP (RP-03) |
| Profil | Zprávy, vlákno, new-thread sheet | features/messages/v2/** | y | Profil | RP (RP-10/19) |
| Profil | Pobočky, pobočka detail | features/branches/v2/** | y | Profil | RP (RP-14) |
| Profil | "Motorky na pobočkách" sheet | profile/widgets/branches_sheet.dart:53 | n | Profil | RP (RP-05) |
| Profil | Věrnostní ranky + O programu | features/loyalty/v2/** | y | RankStyly / Profil | — |
| Doklady | Scanner `/docs/scan`: choice, camera step, result, contact fallback, camera error, loading, done | documents/document_scanner_screen.dart:731-1238 | p (back only) | Profil scanner / Stavy 11.x | ASM (ASM-22/23/24) |
| Doklady | DocumentCameraScreen | document_camera_screen.dart | — dead code (painter reused) | — | ASM (painter params) |
| Auth | `/login` + unknown-e-mail dialog + forced sign-out + errors | features/auth/login_screen.dart | n | Prihlaseni | ASM (ASM-01/02) |
| Auth | `/register` steps 1–3 + e-mail-taken dialog + server errors | register_screen.dart | p (canvas + back) | Prihlaseni | ASM (ASM-03/04) |
| Auth | `/reset-password` steps 1–3 + states | reset_password_screen.dart | n | Prihlaseni | ASM (ASM-05/06) |
| Auth | Welcome overlay after registration | moto_fx.dart:620 (call register_screen.dart:370) | n | Prihlaseni Hotovo | ASM (ASM-07) |
| SOS | `/sos` start, accident / breakdown type sheets | features/sos/sos_report_screen.dart | n | SOS | ASM (ASM-09/16) |
| SOS | Report sheet | sos_report_sheet.dart | n | SOS | ASM (ASM-17) |
| SOS | `/sos/accident` immobile, `/sos/breakdown`, `/sos/theft`, `/sos/service` | sos_immobile_screen.dart, sos_breakdown_immobile_screen.dart, sos_theft_screen.dart, sos_service_screen.dart | n | SOS | ASM (ASM-11…15) |
| SOS | `/sos/replacement` | sos_replacement_screen.dart | p | SOS | ASM (ASM-25) |
| SOS | `/sos/done` done screens + incident detail | sos_detail_screen.dart | n | SOS / Stavy 14 | ASM (ASM-19/21) |
| SOS | Fail / location dialogs, SosCallButton | sos_feedback.dart | p | Stavy 14 | ASM (ASM-18/29) |
| SOS | Nonstop-line dock (replaces nav on /sos*) | (board) | — | V22 §2.4 SOS | ASM (ASM-10) + FND-15 |
| Trasy | Místa root, Trasy list, Moje (4 sub-tabs), "+" menu, record dock, recorder, ride detail, point sheet, share sheet / dialogs, trips (Moje paths), builder, place picker, submit forms, places map, photo credit sheet | features/routes/v2/** + seamed old files | y (fidelity fixes) | TrasyHub, Zazitky, TrasaDetail | RR (F-04…F-40) |
| Trasy | Route detail (body y, loading spinner) | route_detail_screen.dart:107 | p | TrasaDetail | RR (F-09′/F-19) |
| Trasy | Route reviews section / sheet / editor | route_reviews.dart:87/245/396 | n | TrasaDetail | RR (F-01) |
| Trasy | POI rating bar + POI reviews | poi_rating.dart:20, poi_reviews.dart:31/82 | n | Zazitky | RR (F-02) |
| Trasy | Fullscreen photo viewer | route_poi_sheet.dart:593 | n | TrasaDetail viewer | RR (F-03) + FND-10 |
| Trasy | Fullscreen route map + "Otevřít v jiné aplikaci" sheet | route_detail_screen.dart:661/703 | n | TrasaDetail | RR (F-12) |
| Trasy | "Odesláno" success sheet | submit_common.dart:262 | n | Stavy 16 | RR (F-11) |
| Trasy | Mapa tras point panel | routes_map_picker.dart:46, routes_map_screen.dart:340 | n | TrasyHub | RR (F-13) |
| Trasy | Route navigation (HUD, cards, banners, controls, stops sheet, 2 dialogs) | route_navigation_screen.dart (platform), route_nav_widgets.dart, route_nav_status.dart | p (top bar only) | TrasaDetail Navigace | RR (F-07) |
| Trasy | Ride start / stop results | ride_actions.dart:22, ride_start_feedback.dart:13 | p (toasts) | V22 §4.4 / Stavy 16 | RR (F-06) |
| Trasy | Old RideGpsLostBanner, RideRecControlsCard, RideTripRow, RideNavRecChip, ride_pause_sheet.dart | features/routes/* | — (old bodies only) | — | none |
