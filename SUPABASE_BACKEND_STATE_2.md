# SUPABASE BACKEND STATE — MotoGo24 (Část 2: Klíčové sloupce)
> **Soubory:** 1/6 (Tabulky) | **2/6 (Sloupce)** | 3/6 (RPC funkce) | 4/6 (Triggery) | 5/6 (RLS, Realtime, Edge, Storage, Secrets) | 6/6 (Changelog)

---

## 3. KLÍČOVÉ SLOUPCE (reálný stav DB)

### accounting_entries (reálný stav DB ověřen introspekcí 2026-06-11, znovu ověřeno 2026-06-24)
- id (uuid PK), **type (ENUM `entry_type`: income/expense) NOT NULL** — NE text s CHECK ('revenue','expense'), jak tvrdí migrace `20260321_accounting_entries.sql`
- amount (numeric(12,2) NOT NULL), **category (text NOT NULL)** — insert bez category tiše padá (root cause „tržby 0" ve Velínu do 2026-06-11)
- description (text), date (date **DEFAULT CURRENT_DATE**, nullable — Dashboard/Finance filtrují `.gte('date', ...)`, řádek s NULL date z přehledů vypadne; nově se NULL nestane sám od sebe díky defaultu)
- booking_id, branch_id, invoice_id, reference_id (uuid), reference_type (text)
- tax_amount (numeric(12,2)), tax_rate (numeric(4,2) **DEFAULT 21**), created_by (uuid), created_at, updated_at
- **POZOR: sloupce `vat_rate`, `source`, `entry_date` NEEXISTUJÍ** (process-refund je do 2026-06-11 omylem používal — insert se zahazoval)
- Frontend klasifikace příjmů: `velin/src/lib/revenueUtils.js#classifyEntry` — type='income' sám o sobě NEstačí, příjem se pozná dle category ('pronájem'/'rezervace'/...) nebo description ('platba za rezervaci...')

### admin_users
- id, email, name, role (`admin_role` ENUM, DEFAULT 'viewer'), ~~password_hash~~ (odstraněno 2026-06-24 — autentizace přes `auth.users`, sloupec v reálné DB NEEXISTUJE)
- **phone** (text), **active** (boolean NOT NULL DEFAULT true)
- branch_access (uuid[]), permissions (jsonb)
- last_login_at, created_at, updated_at

### bookings
- id, user_id, moto_id, start_date, end_date, pickup_time, **return_time** (TEXT DEFAULT NULL — čas vrácení motorky HH:MM, default UI 19:00)
- status (`booking_status` ENUM)
- payment_status (`payment_status` ENUM)
- payment_method, total_price, delivery_fee, deposit
- promo_code_id, voucher_id, notes
- confirmed_at, picked_up_at, returned_at
- cancelled_by, cancelled_by_source, cancellation_reason, cancelled_at, cancellation_notified
- sos_replacement (boolean), replacement_for_booking_id, sos_incident_id, ended_by_sos
- ~~pickup_date, return_date (timestamptz pro overlap check)~~ — **OPRAVA 2026-06-08:** tyto sloupce v reálné DB **NEEXISTUJÍ** (ověřeno `column "pickup_date" does not exist`). Overlap se kontroluje výhradně přes `start_date`/`end_date` — triggery `check_booking_overlap` (`tstzrange(start_date,end_date)`) a `check_user_booking_overlap` (`start_date::date`/`end_date::date`).
- **trailer_moto_id** (UUID FK→motorcycles ON DELETE SET NULL, **NEW 2026-06-16** — migrace `20260616_trailer_addon.sql`) — přiřazený kus vozíku, když si zákazník přidá **vozík jako příslušenství** (gear add-on, ne samostatná rezervace). Blokuje kalendář vozíku: `get_moto_booked_dates` má UNION větev `trailer_moto_id`, BEFORE INSERT/UPDATE trigger `check_trailer_overlap` odmítne už obsazený kus (i kolizi standalone × gear). Web 400 Kč/den (řádek v `booking_extras`+`extras_price` → propíše se do ZF/DP/dobropisu i smlouvy), app zdarma (řádek 0 Kč). Volný kus vybírá RPC `get_trailer_availability`. Index `idx_bookings_trailer_moto_id`.
- **actual_return_date** — skutečné datum vrácení
- **pickup_method, pickup_address** — způsob vyzvednutí
- **pickup_lat, pickup_lng** — GPS souřadnice místa vyzvednutí (DOUBLE PRECISION, nullable)
- **return_method, return_address** — způsob vrácení
- **return_lat, return_lng** — GPS souřadnice místa vrácení (DOUBLE PRECISION, nullable)
- **extras_price** — cena příslušenství
- **discount_amount, discount_code** — sleva
- **contract_url** — URL smlouvy
- **insurance_type** — typ pojištění
- **signed_contract** — podepsaná smlouva (boolean)
- **mileage_start, mileage_end** — nájezd km. **2026-06-28:** `mileage_start` = stav tachometru z **předávacího protokolu** (zapisuje edge `submit-handover-protocol` v `mode=customer` + Velín `ElectronicProtocolModal`); trigger `trg_booking_mileage_to_moto` z něj bumpne `motorcycles.mileage` (GREATEST). `mileage_end` = volitelně z protokolu o poškození (jen pro „Najeto" v `BookingSummary`, motorku neovlivní). „Najeto za půjčení" se v analytice dopočítává z rozdílu po sobě jdoucích `mileage_start` téže motorky (RPC `analytics_moto_rental_km`).
- **damage_report** — hlášení poškození
- **promo_code** — promo kód (text)
- **stripe_payment_intent_id** — Stripe Payment Intent ID (pro refundy)
- **stripe_refund_id** (TEXT DEFAULT NULL, **NEW 2026-05-08**) — Stripe Refund ID posledního refundu k rezervaci. Plní `process-refund` po úspěšném Stripe refundu (vedle credit_note dobropisu). Velín booking detail z toho generuje odkaz na `dashboard.stripe.com/refunds/<id>`.
- **card_brand** (TEXT DEFAULT NULL, **NEW 2026-05-08**) — Brand platební karty (visa/mastercard/amex/...). Plní `webhook-receiver` po `payment_intent.succeeded` (přes `stripe.charges.retrieve` na `latest_charge.payment_method_details.card.brand`). Pomocný i v `process-refund` pro renderování dobropisu („Refund proběhl na kartu Visa **** 4242").
- **card_last4** (TEXT DEFAULT NULL, **NEW 2026-05-08**) — Posledních 4 číslic platební karty. Stejný plnič jako `card_brand`. Velín booking detail zobrazuje pod „Způsob platby".
- **payment_reference** (TEXT DEFAULT NULL, **NEW 2026-06-08**) — Číslo / reference transakce u **ruční** (ne-Stripe) platby (QR, převod, hotově, krypto). Plní Velín booking detail při ručním potvrzení platby (`confirmManualPayment` v `BookingDetail.jsx`), zobrazuje se v panelu Platba pod „Způsob platby" jako „Č. transakce". Stripe platby ho nepoužívají (mají `stripe_payment_intent_id`).
- **stripe_session_id** — Stripe Checkout Session ID
- **stripe_checkout_url** (TEXT DEFAULT NULL) — URL aktivní Stripe Checkout session, ukládá `process-payment` při vytvoření session. Použito v abandoned mailu jako přímý odkaz na platbu.
- **checkout_started_at** (TIMESTAMPTZ DEFAULT NULL) — okamžik kliknutí na „Pokračovat k platbě" (= vytvoření Stripe Checkout session). Vstupní bod 10minutového odpočtu pro abandoned mail.
- **abandoned_email_sent_at** (TIMESTAMPTZ DEFAULT NULL) — kdy byl odeslán „nedokončená rezervace" mail (deduplikace v `send_abandoned_booking_emails` pro stavy unpaid+pending — A: chybí platba i doklady, B: chybí jen platba). **POZN. 2026-07-05:** RPC `set_booking_qr_payment` ho u QR/převod rezervací nastavuje na `now()` → cron ji pak přeskočí (zákazník dostal ZF s pokyny, druhý „nedokončeno" mail je nežádoucí).
- **pay_channel** (TEXT DEFAULT NULL, **NEW 2026-07-05** — `20260705_qr_bank_payment.sql`) — platební kanál WEB rezervace: `qr` = zákazník zvolil platbu QR kódem / bankovním převodem; `NULL` = standardní Stripe (karta). Plní RPC `set_booking_qr_payment`. Velín (`BookingDetail`) u `qr` + nezaplaceno ukazuje badge „QR/PŘEVOD — ČEKÁ · VS …". Jen `booking_source='web'`.
- **payment_vs** (TEXT DEFAULT NULL, **NEW 2026-07-05** — `20260705_qr_bank_payment.sql`) — číselný variabilní symbol pro QR/převod (bankovní VS = jen číslice, max 10). Přidělen jednou ze sekvence `booking_vs_seq` (start 10000001) v RPC `set_booking_qr_payment`; jde do SPD (`X-VS`), na ZF (`invoices.variable_symbol`) i do upozornění na info@. Číslo rezervace `id.slice(-8)` (hex) se jako bankovní VS použít NELZE, proto samostatný číselný VS.
- **docs_reminder_sent_at** (TIMESTAMPTZ DEFAULT NULL) — kdy byl odeslán „nahrajte doklady" mail (state C: paid+reserved, 5 min od `confirmed_at`, doklady nenahrané — kontrola přes `check_booking_docs_status`). Deduplikace, jeden mail na rezervaci.
- **handover_protocol_started_at** / **handover_protocol_filled_at** (TIMESTAMPTZ DEFAULT NULL) + **handover_protocol_autofilled** (BOOLEAN NOT NULL DEFAULT false) — **NEW 2026-06-23 (`20260623c_autonomous_handover_protocol.sql`)** — autonomní předávací protokol na samoobslužné pobočce. `started_at` = start 1h okna (zákazník zadal kód ke dveřím / otevřel aktivní samoobslužnou rezervaci, RPC `start_handover_protocol_window`). `filled_at` = vyplněno (zákazníkem v appce přes `submit-handover-protocol`, nebo auto-fillem cronu `autofill_overdue_handover_protocols` po 1h). `autofilled=true` = vyplnil systém („vše dle rezervace, OK", bez podpisu). Po `filled_at` je protokol zamčený (zákazník needituje). Stav čte RPC `get_handover_protocol_state`. **+ 2026-06-23 (d):** `handover_protocol_reminder_sent_at` (TIMESTAMPTZ) — dedup push připomínky „vyplňte protokol" (~10 min před koncem okna, posílá cron).
- **reserved_email_sent_at** (TIMESTAMPTZ DEFAULT NULL) — **NEW 2026-06-17 (`20260617_catchup_booking_reserved_email.sql`)** — marker pro záchranný cron `send_missing_booking_reserved_emails()`. Nastaví se, když cron došle chybějící `booking_reserved` mail (webhook ho v časově omezené cestě „utnul" při synchronní generaci 4 PDF příloh). Realtime cesta (webhook) marker NEnastavuje — tam jistí dedup přes `message_log`. Marker brání, aby cron mail nezdvojil během dlouhé generace příloh (jeden pokus na rezervaci).
- **late_pickup_discount_amount** (NUMERIC NOT NULL DEFAULT 0, **NEW 2026-06-18** — migrace `20260618_late_pickup_discount.sql`) — sleva 50 % na 1. den při **pozdním vyzvednutí** (`pickup_time >= 12:00`) a rezervaci na **2 a více dní**. ODDĚLENÁ od `discount_amount` (promo/voucher) i `loyalty_discount_amount`. Platí pro **web i app**. Autoritativní výpočet: RPC `_late_pickup_discount(moto_id, start, end, pickup_time)` = `round(50 % ceny prvního dne)`; web ji počítá ve `create_web_booking`, app ji posílá z `payment_screen`. BEFORE INSERT trigger `trg_validate_late_pickup` (fn `validate_late_pickup_discount`) je **clamp-down anti-cheat** — slevu NIKDY sám nepřidá (chrání Velín/SOS/admin inserty), jen ořeže, když klient pošle víc než povolené maximum, a dorovná `total_price`. ZF/DP/KF ji vykazují jako samostatný záporný řádek „Sleva 50 % na 1. den (pozdní vyzvednutí)". **MILESTONE 1** = vytváření rezervace; přepočet při úpravě (DP doplatek / dobropis vratka) je Milestone 2.
- **loyalty_level, loyalty_percent** (INT, NEW 2026-06-11) + **loyalty_discount_amount** (NUMERIC DEFAULT 0) — věrnostní sleva dle ranku (1–20 %), JEN pro `booking_source='app'`. ODDĚLENÁ od `discount_amount` (promo/voucher). Plní Flutter `payment_screen` (jen když sleva platí), validuje/ořezává BEFORE INSERT trigger `trg_validate_app_loyalty` proti `_loyalty_qualifying_count`. ZF/DP (`generate-invoice`) i KF (`generate_final_invoice_on_complete`) ji vykazují jako samostatný záporný řádek „Věrnostní sleva X % — rezervace přes aplikaci MotoGo24". Mig. `20260611_loyalty_ranks.sql`
- **created_via_ai** (BOOLEAN DEFAULT false) — TRUE pokud rezervaci vytvořil `ai-public-agent` edge fn (zákazník přes AI asistenta v widgetu na webu). FALSE = klasický web formulář / appka / admin / SOS. Velín to zobrazuje jako 🤖 AI badge vedle WEB.
- **rating, rated_at** — hodnocení zákazníkem
- **helmet_size, jacket_size, pants_size, boots_size, gloves_size** — velikosti výbavy řidiče (helma, bunda, kalhoty, boty, rukavice)
- **passenger_helmet_size, passenger_jacket_size, passenger_pants_size, passenger_boots_size, passenger_gloves_size** — velikosti výbavy spolujezdce
- **original_start_date, original_end_date** — původní data rezervace (před prodloužením/zkrácením)
- **modification_history** (jsonb, default '[]') — historie všech úprav termínu. Každý záznam: `{at, from_start, from_end, to_start, to_end, source}`
- **complaint_status** — stav reklamace (open, in_progress, resolved, rejected, null)
- **booking_source** — zdroj rezervace (text, default 'app') — 'app' nebo 'web'
- **is_test** (boolean DEFAULT false) — testovací rezervace z AI tréninku
- **form_started_at** (timestamptz, NEW 2026-05-23) — okamžik otevření webového rezervačního formuláře (`MG._rezInit`, uloženo v sessionStorage `mg_rez_started_at`). Plní `set_booking_form_seconds` po create_web_booking. Jen `booking_source='web'`.
- **form_fill_seconds** (integer, NEW 2026-05-23) — doba (s) start→vytvoření rezervace = samotné vyplňování formuláře. Spočte `set_booking_form_seconds` (now - form_started_at, clamp 0–86400). Velín detail rezervace → „Doba vyplnění formuláře".
- **payment_fill_seconds** (integer, NEW 2026-05-23) — doba (s) start→úspěšná platba (celý proces vč. dokladů). Dopočítá trigger `trg_booking_payment_fill_seconds` při přechodu na `payment_status='paid'` (confirmed_at - form_started_at, clamp 0–604800). Funguje i přes Stripe redirect (start je v DB). Velín → „Doba do zaplacení".
- **created_device** (text, NEW 2026-05-30) — zařízení při vytvoření web rezervace (krok 1): `pc` | `mobile` | `tablet`. Plní `set_web_booking_device(p_phase='created')` z `pages-rezervace-steps.js` po `create_web_booking` (jen poprvé — `created_device IS NULL`, aby „Zpět"/resume nepřepsal start). Detekce na frontendu `MG._rezDeviceType()` (user-agent + maxTouchPoints).
- **completed_device** (text, NEW 2026-05-30) — zařízení při dokončení / kliknutí na platbu (krok 2). Plní `set_web_booking_device(p_phase='completed')` z `pages-rezervace-scan.js#_rezSubmitPayment`. Pokud se liší od `created_device`, Velín (`BookingSummary.jsx` → „Zařízení") zobrazí cross-device průběh „PC → Mobil" (zákazník začal na PC, dokončil na mobilu — typicky QR resume). Jen `booking_source='web'`.

### booking_complaints
- id (uuid PK), booking_id (refs bookings), customer_id (refs profiles)
- subject (text NOT NULL), description (text)
- status (text: open, in_progress, resolved, rejected)
- resolution (text), created_at, updated_at, resolved_at
- resolved_by (refs auth.users)
- RLS: Admin full access

### messages (rozšíření 2026-05-05 — AI customer messages agent)
- existující sloupce: id, thread_id (FK→message_threads), direction (inbound/outbound), content, ai_suggested_reply, created_at, read_at
- **ai_suggested_at** (TIMESTAMPTZ) — kdy AI návrh dorazil
- **ai_suggestion_status** (ENUM `ai_suggestion_status`: pending / approved / edited / rejected / sent / auto_sent / failed)
- **ai_suggested_by_model** (TEXT) — např. `claude-haiku-4-5-20251001`
- **ai_confidence** (TEXT CHECK: low/medium/high) — sebejistota AI; low → admin musí prověřit
- **ai_admin_note** (TEXT) — krátká poznámka pro admina, proč low/medium nebo na co si dát pozor
- **ai_final_reply** (TEXT) — text, který admin reálně odeslal (může být upravený oproti `ai_suggested_reply`)
- **ai_approved_by** (UUID FK→admin_users ON DELETE SET NULL) — admin, který návrh schválil/zamítl
- **ai_approved_at** (TIMESTAMPTZ) — okamžik schválení/zamítnutí
- **ai_sent_message_id** (UUID FK→messages ON DELETE SET NULL) — odkaz na výslednou outbound zprávu po odeslání (cross-link mezi inbound návrhem a odeslanou odpovědí)
- **ai_error** (TEXT) — pokud generování / auto_send selhalo, krátký chybový popis
- Indexy: `idx_messages_ai_suggestion_pending` (created_at DESC) WHERE status='pending'; `idx_messages_ai_suggestion_status` (status, created_at DESC) WHERE status IS NOT NULL
- Realtime: ANO (přidáno v migraci, aby Velín viděl nové AI návrhy hned)
- Naplňuje edge fn `ai-customer-messages-suggest` na vyžádání ze Velína (per `message_id`)

### profiles
- id (refs auth.users), full_name, email, phone
- street, city, zip, country
- ico, dic, license_number, license_expiry
- license_group (`license_group[]` — pole ENUM hodnot AM/A1/A2/A/B/N, **OPRAVA 2026-06-11:** dříve chybně dokumentováno jako text[]; update vyžaduje cast `ARRAY['A']::license_group[]`), riding_experience
- emergency_contact, emergency_phone
- gear_sizes (jsonb), reliability_score (jsonb)
- marketing_consent (boolean DEFAULT **false** — **ZMĚNA 2026-07-01** z `true` na `false`, marketing je nově opt-in; mig. `20260701_app_save_full_profile_marketing_optin.sql`. Registrace v appce (RPC `app_save_full_profile`) ani web (`create_web_booking`) marketing nesbírají → nově zůstává vypnutý, dokud ho zákazník výslovně nezapne)
- **date_of_birth** — datum narození
- **avatar_url** — URL avataru
- **preferred_branch** — preferovaná pobočka
- **language** — jazyk (cs/en/de)
- **is_test_account** (boolean DEFAULT false) — testovací účet z AI tréninku
- **is_blocked** (boolean DEFAULT false) — zákazník zablokován
- **blocked_at** (timestamptz) — datum blokace
- **blocked_reason** (text) — důvod blokace
- **consent_gdpr** (boolean DEFAULT **true**) — souhlas GDPR
- **consent_vop** (boolean DEFAULT **true**) — souhlas VOP
- **consent_email** (boolean DEFAULT **true**) — souhlas email komunikace
- **consent_sms** (boolean DEFAULT **true**) — souhlas SMS komunikace
- **consent_push** (boolean DEFAULT **true**) — souhlas push notifikace
- **consent_data_processing** (boolean DEFAULT **true**) — souhlas zpracování dat
- **consent_photo** (boolean DEFAULT **true**) — souhlas fotografování dokladů
- **consent_whatsapp** (boolean DEFAULT **true**) — souhlas WhatsApp komunikace
- **consent_contract** (boolean DEFAULT **true**) — souhlas s návrhem smlouvy na motogo24.cz
- **POZN.** 9 consent sloupců default `true` (změna 2026-04-29), **`marketing_consent` nově default `false`** (opt-in, změna 2026-07-01 — viz výše). Backfill NULL→true proběhl (marketing historicky taky true — ALTER defaultu ovlivní jen NOVÉ řádky, existující marketingové souhlasy nemění). Frontend v upravit-rezervaci navíc bere NULL jako ON, jen explicitní `false` zobrazí jako vypnuté. **Velín `CustomerProfileTab` (2026-07-01):** NULL/undefined souhlas zobrazuje jako šedé „Neznámé" (ne červené „NE").
- **stripe_customer_id** (TEXT) — Stripe Customer ID pro uložené platební metody
- **id_number** (TEXT DEFAULT NULL) — číslo dokladu totožnosti (OP nebo pas) z Mindee OCR
- **id_verified_at** (TIMESTAMPTZ) — datum ověření OP přes Mindee OCR
- **id_verified_until** (DATE) — platnost OP — do tohoto data je ověření platné
- **license_verified_at** (TIMESTAMPTZ) — datum ověření ŘP přes Mindee OCR
- **license_verified_until** (DATE) — platnost ŘP — do tohoto data je ověření platné
- **passport_verified_at** (TIMESTAMPTZ) — datum ověření pasu přes Mindee OCR
- **passport_verified_until** (DATE) — platnost pasu — do tohoto data je ověření platné
- **registration_source** (TEXT DEFAULT NULL) — zdroj registrace: 'app' nebo 'web'. **POZN. (oprava 2026-07-01):** DB default byl HISTORICKY chybně `'auth_trigger'` (ne NULL) — trigger `handle_new_user()` sloupec nenastavuje, takže nové profily dostaly placeholder `'auth_trigger'`, který non-null hodnotou blokoval `COALESCE(...,'app'/'web')` v RPC (`app_save_full_profile`, `create_web_booking`) → zdroj se nikdy nedoplnil. Migrací `20260701_fix_registration_source_default.sql` default vrácen na NULL + backfill z nejstarší rezervace (kdo nemá rezervaci → NULL).
- **password_last4_bcrypt** (TEXT) — bcrypt hash posledních 4 znaků hesla. Plní `set_web_booking_password` při nastavení/změně hesla. Používá AI agent (`find_booking_for_modification`, `apply_booking_changes_anon`) pro 3. ověřovací faktor při úpravě rezervace anonymním kanálem (booking_id + email/telefon + last4 z hesla). Existující profily mají NULL → AI úpravu nedovolí, RPC vrátí `password_check_unavailable`.
- **app_permissions** (JSONB DEFAULT NULL) — **NEW 2026-06-07 (`20260607_profiles_app_permissions.sql`)** — poslední snapshot OS oprávnění z mobilní appky: `{location, camera, notification, photos (bool), platform ('android'/'ios'), reported_at (iso)}`. Plní Flutter appka `PermissionService.reportToProfile` (volá se při startu v `main._initPush` a po `requestAll` v obrazovce oprávnění; reportuje se od appky v1.0.8). Čte Velín → detail zákazníka (`CustomerProfileTab.jsx`) read-only v sekci „Oprávnění aplikace (telefon)". Informativní, device-level — nezasahuje do business logiky. NULL = appka oprávnění ještě nenahlásila (starší verze / web-only zákazník).
- **docs_verified_at** (TIMESTAMPTZ), **docs_verification_status** (TEXT) — souhrnný stav ověření dokladů (vedle granulárních `id_verified_at`/`license_verified_at`/`passport_verified_at`).
- **marketing_consent_at** (TIMESTAMPTZ) — okamžik udělení marketingového souhlasu (`marketing_consent`).
- **preferred_channel** (TEXT DEFAULT 'sms') — preferovaný komunikační kanál (sms/email/...).
- **phone_e164** (TEXT) — telefon v normalizovaném E.164 formátu (pro SMS/WhatsApp odesílání).
- **loyalty_nickname** (TEXT, ověřeno 2026-06-24) — přezdívka zákazníka pro věrnostní žebříček (zobrazuje se v leaderboardu místo jména).
- **loyalty_leaderboard_opt_in** (BOOLEAN NOT NULL DEFAULT true) — zákazník souhlasí s účastí ve veřejném věrnostním žebříčku.
- **loyalty_bonus_points** (INTEGER NOT NULL DEFAULT 0) — ručně/akcí přidělené bonusové body do věrnostního skóre.

### payment_methods
- id (UUID PK), user_id (UUID FK→profiles ON DELETE CASCADE)
- **type** (TEXT NOT NULL, ověřeno 2026-06-24) — typ platební metody (card/...)
- stripe_payment_method_id (TEXT UNIQUE) — Stripe PM ID
- brand (TEXT) — visa, mastercard, amex... (reálná DB **bez** defaultu 'unknown')
- last4 (TEXT) — poslední 4 čísla karty (reálná DB **bez** defaultu '****')
- exp_month (INTEGER), exp_year (INTEGER) — expirace
- holder_name (TEXT) — jméno držitele karty
- is_default (BOOLEAN DEFAULT false) — prioritní karta
- created_at, updated_at

### motorcycles
- id, model, spz, vin, year, status (`moto_status` ENUM: active, maintenance, unavailable, retired)
- stk_valid_until, acquired_at
- **unavailable_reason** (TEXT DEFAULT NULL) — důvod dočasného vyřazení (cleaning, transport, inspection, seasonal, damage_wait, other)
- power_kw (NUMERIC(6,1)) — výkon v kW (povolena 1 desetina, např. 92.5)
- torque_nm (NUMERIC(6,1)), fuel_tank_l (NUMERIC(4,1))
- weight_kg (INTEGER), **seat_height_mm (INTEGER DEFAULT 0** — OPRAVA 2026-06-24: v reálné DB je INTEGER, ne TEXT)
- license_required, has_abs, has_asc
- **license_required** (ENUM `license_group` DEFAULT 'A' — OPRAVA 2026-06-24: v reálné DB je typ `public.license_group`, ne TEXT) — JEDNA kanonická skupina ŘP. Drží legacy logiku: dětská/`'N'` check (door codes, docs status, gear audience, AI agenti, smlouvy, web `create_web_booking` overlap). Velín ji **auto-odvozuje** z `license_groups` (`'N'` má přednost; jinak nejnižší moto rank AM<A1<A2<A; jinak B).
- **license_groups** (TEXT[] NOT NULL DEFAULT '{}', **NEW 2026-06-15** — migrace `20260615_moto_license_groups.sql`) — pole VŠECH přijímaných skupin ŘP (OR — stačí, aby zákazník měl kteroukoliv). Umožňuje skútr = `{A1,B}`, přívěs = `{B}` apod. Zadává se ve **Velíně** Fleet detail → „ŘP skupiny (lze vybrat více)" (chip multi-select, `'N'` výlučné). Backfill z `license_required` (jedna hodnota → pole). **Web** (`katalog.php` filtr ŘP + `katalog-detail.php`/karty výpis přes helper `motoLicenseGroups()` v `components.php`) i **App** (`Motorcycle.licenseGroups`/`licenseGroupsOrFallback`, filtr `CatalogFilter.apply` coverage mapa, `BookingValidator.checkLicense`) čtou pole, fallback na `[license_required]` když prázdné. Web `select *` / app `select('*, branches…')` propíše sloupec automaticky.
- description, ideal_usage, features, manual_url
- **manual_external_url** (TEXT) — externí URL na návod (např. stránka výrobce); použije se pouze pokud není nahrán PDF (`manual_url` je prázdný). PDF má vždy přednost.
- engine_type, power_hp
- **branch_id** — pobočka (FK→branches)
- **is_trailer** (BOOLEAN NOT NULL DEFAULT false, **NEW 2026-06-16** — migrace `20260616_trailer_addon.sql`) — tento kus flotily je **vozík/přívěs**. Označuje se ve Velíně (Fleet detail → checkbox „Vozík (lze přidat jako příslušenství)"). Pool pro gear add-on „Vozík" v rezervaci (RPC `get_trailer_availability` filtruje `is_trailer=true AND status='active'`). Vozík lze půjčit i samostatně (běžná rezervace na jeho `moto_id`, kategorie „Ostatní"); obě cesty blokují stejný kalendář.
- **category** — kategorie motorky (volný text: cestovni/sportovni/naked/supermoto/chopper/**scootery**/detske/**ostatni** + historické hodnoty)
- **engine_cc** — objem motoru
- **price_weekday, price_weekend** — ceny
- **price_mon, price_tue, price_wed, price_thu, price_fri, price_sat, price_sun** — ceny dle dne
- **mileage** — aktuální nájezd. **2026-06-28:** udržuje se automaticky jako **nejvyšší známé čtení** — trigger `trg_booking_mileage_to_moto` (z předávacího protokolu) a `update_moto_after_service` (z `km_at_service`) dělají `GREATEST(mileage, nové)`, takže auto NIKDY neklesá. Ruční korekce přes RPC `correct_motorcycle_mileage` (smí i dolů, floored na `purchase_mileage`). Trigger `trg_moto_purchase_mileage_floor` drží `mileage ≥ purchase_mileage`.
- **image_url** — hlavní fotka
- **images[]** — galerie fotek
- **color** — barva
- **deposit_amount** — výše kauce
- **insurance_price** — cena pojištění
- **min_rental_days, max_rental_days** — min/max délka pronájmu
- **oil_interval_km, oil_interval_days** — interval výměny oleje
- **tire_interval_km** — interval výměny pneumatik
- **full_service_interval_km, full_service_interval_days** — interval celkového servisu
- **last_service_date, next_service_date** — datum posledního/příštího servisu
- **brand** (TEXT DEFAULT NULL) — značka motorky (Honda, Yamaha, BMW...)
- **purchase_price** (NUMERIC DEFAULT 0) — pořizovací cena motorky v Kč
- **purchase_mileage** (INTEGER DEFAULT NULL) — km při zakoupení, základ pro výpočet servisních intervalů
- **tracking_unit** (TEXT DEFAULT 'km') — jednotka sledování nájezdu: 'km' (kilometry) nebo 'mh' (motohodiny). CHECK(tracking_unit IN ('km','mh'))
- **translations** (JSONB DEFAULT '{}') — auto-překlady pro web (struktura `{ "en": {"description":"..."}, "de": {...}, ... }` přes 7 jazyků cs/en/de/es/fr/nl/pl). CZ = výchozí sloupec, web čte přes helper `localized()`. Plní edge funkce `translate-content`.
- **transmission** (TEXT) — převodovka jako volný text (např. „6stupňová manuální"). Web zobrazuje v Krátkém popisu (sloučeno do Motor) i v tabulce specs.
- **drivetrain** (TEXT) — typ pohonu, CHECK(drivetrain IN ('chain','shaft','belt')). Web mapuje na lokalizované řetěz/kardan/řemen.
- **top_speed_kmh** (INTEGER) — maximální rychlost v km/h. Spec tabulka.
- **fuel_consumption_l100km** (NUMERIC(4,2)) — průměrná spotřeba l/100 km. Krátký popis + spec tabulka.
- **fuel_type** (TEXT) — druh paliva (např. „Natural 95"). Spec tabulka.
- **brake_type** (TEXT) — popis brzdové soustavy (např. „kotoučové (ABS)"). Spec tabulka.
- **seats_count** (INTEGER) — počet míst k sezení (1 nebo 2). Spec tabulka.
- **suitable_for** (TEXT) — HTML/text sekce „Pro koho je motorka vhodná?" (vykresluje se přes `sanitizeHtml()` v levém sloupci moto-info, mezi Krátkým popisem a Výbavou).
- **box_number** (INTEGER, ověřeno 2026-06-24) — číslo boxu/stání na samoobslužné pobočce, kde kus stojí.
- **unavailable_until** (TIMESTAMPTZ, ověřeno 2026-06-24) — do kdy je kus dočasně nedostupný (vazba na `status='unavailable'` + `unavailable_reason`).
- **short_desc_fields** (TEXT[] NOT NULL DEFAULT '{}', ověřeno 2026-06-24) — výběr polí, která se mají skládat do „Krátkého popisu" na webu (spec klíče jako engine/transmission/...).
- **image_alts** (TEXT[] DEFAULT '{}', **NEW 2026-05-17**) — paralelní pole SEO alt popisků k `images[]` (stejný index). Admin ve Velíně Fleet detail → fotky vyplňuje krátký popisek (např. „zepředu", „detail palubky"), PHP `katalog-detail.php` skládá finální alt jako `"{model} {color} – {popisek}"`. Pokud `image_alts[i]` prázdný/NULL → fallback na `"motorka {model} – půjčovna motogo24"` (původní chování). Migrace `20260517_image_alts.sql`.
- **sort_order** (INTEGER, nullable, **NEW 2026-06-21** — migrace `20260621_motorcycles_sort_order.sql`) — ruční pořadí zobrazení (1-X) nastavované ve **Velíně** (Fleet detail → „Pořadí zobrazení (1-X)" + nepovinné pole v „Nová motorka"; Fleet list má sort „Dle pořadí (ruční)" a u modelu badge `#N`). Řídí pořadí na **webu**: krok „Vyber stroj" v rezervaci (`js/api.js#MG.fetchMotos` → `.order('sort_order',{ascending,nullsFirst:false}).order('model')`), katalog (výchozí řazení) a **pořadí fotek/videí v hero banneru** na home (`pages/home.php` čte `$motos` = `fetchMotos` v daném pořadí). PHP `supabase.php#fetchMotos` řadí `sort_order.asc.nullslast,model.asc`. NULL = neočíslováno → řadí se ZA očíslované dle modelu. Index `idx_motorcycles_sort_order`. SQL: `ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS sort_order integer;`
- **videos** (TEXT[] NOT NULL DEFAULT '{}', **NEW 2026-06-14**) — pole veřejných URL MP4 videí motorky (bucket `media`, složka `motos/<id>/videos/`). Pořadí = pořadí přehrávání. Spravuje se ve **Velíně** Fleet detail → Fotogalerie → sekce „Videa MP4" (komponenta `VideoUploader`, ukládá `FleetDetailPhotos.jsx#syncVideos`, drag&drop / klik, bez komprese, default max 100 MB/soubor). **Web:** a) hero banner na home (`pages/home.php`) — když má aspoň jedna motorka video, hero se přepne na JS-řízený slideshow: motorka s videem hraje svá videa za sebou a přepne se na další až po dovysílání všech (čas zobrazení = délka videí), motorka bez videa zůstává časovaný foto-slide; bez jediného videa zůstává původní CSS-only crossfade. b) detail motorky (`pages/katalog-detail.php`) — video blok nad fotogalerií (autoplay muted, controls, sekvenčně). c) 2. krok rezervace (`js/pages-rezervace-steps.js` `_rezGalleryVideos`/`_rezGalleryHtml`/`_rezInitGallery`) — video(a) se zobrazí jen pokud existují, jinak fotky jako doposud. **Přehled/seznam (web i app) vždy fotka.** **App (Flutter):** model `Motorcycle.videos` (`moto_model.dart`), přehrávač `widgets/moto_video_player.dart` (balík `video_player`) na detailu (`moto_detail_page.dart`) — videa se spustí až po otevření detailu, muted s možností odmutovat, více videí jede za sebou. Web čte přes `select *` (fetchMotos, api.js), app přes `select('*, branches…')` — sloupec se propisuje sám. SQL: `ALTER TABLE motorcycles ADD COLUMN IF NOT EXISTS videos text[] NOT NULL DEFAULT '{}'::text[];`

### sos_incidents
- id, user_id, booking_id, moto_id, type, title, description
- severity (low/medium/high/critical)
- status (`sos_status` ENUM)
- moto_rideable, customer_decision, customer_fault
- damage_description, damage_severity (none/cosmetic/functional/totaled)
- latitude, longitude, address, photos[]
- nearest_service_name/address/phone
- assigned_to, contact_phone, admin_notes
- resolution, resolved_at, resolved_by
- replacement_data (jsonb), replacement_status
- original_booking_id, replacement_booking_id, original_moto_id
- **is_customer_fault** — vina zákazníka (boolean)
- **police_report_number** — číslo policejní zprávy
- **replacement_moto_id** — ID náhradní motorky
- **tow_requested** — požadavek na odtah (boolean)
- **type (ENUM `sos_type` NOT NULL** — OPRAVA 2026-06-24: v reálné DB je to typ `public.sos_type`, ne text s CHECK): theft/accident_minor/accident_major/breakdown_minor/breakdown_major/defect_question/location_share/other
- **is_test** (boolean DEFAULT false) — testovací incident z AI tréninku

### maintenance_log (nové sloupce)
- **technician_id** (UUID FK→acc_employees ON DELETE SET NULL) — technik ze seznamu zaměstnanců
- **labor_hours** (NUMERIC DEFAULT 0) — odpracované hodiny technika
- **extra_cost** (NUMERIC DEFAULT 0) — extra náklady (doprava, diagnostika, externí faktura)
- **sos_incident_id** (UUID FK→sos_incidents ON DELETE SET NULL) — vazba na SOS incident pro urgent servisní záznamy
- **is_test** (boolean DEFAULT false, ověřeno 2026-06-24) — testovací servisní záznam z AI tréninku

### acc_employees (nový sloupec)
- **hourly_rate** (NUMERIC DEFAULT 500) — hodinová sazba technika v Kč

### sent_emails
- id, template_slug, recipient_email, recipient_id, booking_id
- subject, body_html, status (queued/sent/failed/bounced), error_message, provider_id
- **attachments_meta** (jsonb) — `[{filename, storage_path?}]` — `storage_path` cíluje do bucketu `documents` (`invoices/<id>.pdf`, `generated/<...>.pdf`, `vouchers/<order_id>/<code>.pdf`); Velín → Dokumenty → Zaslané maily generuje signed URL pro náhled / stažení. Legacy záznamy mohou mít jen `{filename}`.
- created_at

### invoices
- id, number, type, customer_id, supplier_id, booking_id, order_id
- issue_date, due_date, paid_date ~~issued_at~~ (odstraněno 2026-06-24 — v reálné DB NEEXISTUJE)
- subtotal, tax_amount, total, ~~amount, currency~~ (odstraněno 2026-06-24 — v reálné DB NEEXISTUJÍ), status (DEFAULT 'draft'), pdf_path
- items (jsonb DEFAULT '[]'), notes, variable_symbol, source
- **customer_snapshot** (JSONB, ověřeno 2026-06-24) — zamražený snapshot odběratele (jméno/adresa/IČO/DIČ) v okamžiku vystavení dokladu, aby pozdější změna profilu nezměnila historickou fakturu.
- **matched_delivery_note_id** (UUID FK→delivery_notes ON DELETE SET NULL)
- **original_invoice_id** (UUID FK→invoices ON DELETE SET NULL) — vazba dobropisu na původní fakturu
- **stripe_refund_id** (TEXT) — ID Stripe refundu pro dobropisy — napárovaný dodací list
- **payment_method** (TEXT DEFAULT NULL, **NEW 2026-06-08**) — způsob platby u **ruční** (ne-Stripe) úhrady (bank_transfer/qr/cash/crypto/card/voucher). Plní `createInvoice` (přes `payment` param) při ručním potvrzení platby ve Velínu. `invoiceTemplate.js` z toho renderuje blok PLATBA (label „Bankovní převod / QR platba / Hotově / Kryptoměna …"). U Stripe karet zůstává NULL (metoda se bere z `payment_methods`/`stripe_payment_intent_id`).
- **transaction_ref** (TEXT DEFAULT NULL, **NEW 2026-06-08**) — číslo / reference transakce u ruční platby; renderuje se na DP/faktuře jako „Č. transakce". VS u ruční platby jde do existujícího `variable_symbol`, datum úhrady do `paid_date`.

### delivery_notes
- id (UUID PK), dl_number, supplier_name, supplier_ico
- total_amount (NUMERIC), delivery_date (DATE), variable_symbol
- items (JSONB), notes, photo_url, storage_path, extracted_data (JSONB)
- source (TEXT DEFAULT 'manual'), financial_event_id (UUID FK→financial_events)
- matched_invoice_id (UUID FK→invoices), match_method (TEXT: ai/manual), match_confidence (NUMERIC), matched_at
- created_at, updated_at

### financial_events (klíčové sloupce, zdokumentováno 2026-06-24)
Centrální účetní událost (jednotná vrstva nad fakturami/DL/refundy/výplatami pro FlexiBee sync a schvalování).
- id (UUID PK), **event_type** (TEXT NOT NULL) — druh události, **source** (TEXT NOT NULL) — původ (booking/eshop/refund/manual/...)
- **amount_czk** (NUMERIC(12,2) NOT NULL), **vat_rate** (NUMERIC(5,2) NOT NULL DEFAULT 0), **duzp** (DATE NOT NULL) — datum uskutečnění zdanitelného plnění
- **linked_entity_type** (TEXT), **linked_entity_id** (UUID) — polymorfní vazba na zdrojový záznam (booking/invoice/...)
- **confidence_score** (NUMERIC(3,2) DEFAULT 1.0) — jistota AI klasifikace, **document_type** (TEXT)
- **status** (TEXT NOT NULL DEFAULT 'pending'), **flexi_id** (TEXT) — ID v FlexiBee po syncu, **metadata** (JSONB DEFAULT '{}')
- created_at, updated_at
- Souvisí: `flexi_sync_log`, `accounting_exceptions`, `approval_queue` (všechny FK→financial_events).

### contracts
- id (UUID PK), contract_number, contract_type (TEXT: rental/lease/service/insurance/employment/employment_amendment/employment_termination/dpp/dpc/vacation_request/supply/nda/other)
- title, counterparty, counterparty_ico, amount (NUMERIC), payment_frequency
- valid_from (DATE), valid_until (DATE), status (TEXT: pending/active/expired/terminated/draft)
- notes, storage_path, photo_url, extracted_data (JSONB)
- source (TEXT DEFAULT 'manual'), financial_event_id (UUID FK→financial_events)
- employee_id (UUID FK→acc_employees), employee_name
- approved_at, terminated_at, created_at, updated_at

### vouchers
- id, code, amount, currency, status (active/redeemed/expired/cancelled)
- buyer_id, buyer_name, buyer_email
- valid_from, valid_until
- redeemed_at, redeemed_by, redeemed_for, booking_id
- description, category (rental/gear/experience/gift)
- created_by
- **order_id** (FK→shop_orders) — vazba na e-shop objednávku
- **source** (text) — zdroj voucheru. Plní `auto_process_voucher_order` hodnotou `'eshop'` (poukaz z e-shop objednávky); admin poukazy z Velína mají NULL nebo hodnotu vybranou v modálu. **Velín filtr (2026-06-20):** Slevomat=`slevomat`, E-shop=`eshop`, Spolupráce=`spoluprace`, Vrácení=`vraceni`, Ostatní=`ostatni` (filtr „Ostatní" zahrnuje i NULL).
- **slevomat_apply_status, slevomat_applied_at, slevomat_apply_error, slevomat_apply_attempts (DEFAULT 0), slevomat_apply_last_at** (**NEW 2026-06-30**) — sledování automatického uplatnění Slevomat poukazů přes Partner API. Plní edge `slevomat-voucher` (`action='apply'`, volaná triggerem `redeem_booking_discounts` po zaplacení rezervace + pojistným triggerem `trg_slevomat_auto_apply` na `vouchers`). `slevomat_apply_status` ∈ `applied`/`already_redeemed`/`invalid`/`not_paid`/`cancelled`/`failed`; `slevomat_applied_at` se nastaví u `applied`/`already_redeemed` (= idempotence, znovu se Slevomat nevolá). Velín záložka **Slevomat** (`/slevomat`) tyto sloupce živě zobrazuje. Browser-fallback (`slevomat-bot/`) čte stejné sloupce. SQL: `ALTER TABLE vouchers ADD COLUMN IF NOT EXISTS slevomat_applied_at timestamptz; … slevomat_apply_status text; … slevomat_apply_error text; … slevomat_apply_attempts int NOT NULL DEFAULT 0; … slevomat_apply_last_at timestamptz;`

### promo_codes
- id (uuid PK), code (text UNIQUE), type (text CHECK percent/fixed), value (numeric)
- valid_from, valid_to (date), max_uses (int), used_count (int NOT NULL DEFAULT 0)
- min_order_amount (numeric), applicable_motos (text), active (boolean NOT NULL DEFAULT true), created_at
- **source** (text, **NEW 2026-06-20**) — zdroj slevového kódu pro filtrování ve Velíně (`slevomat`/`eshop`/`spoluprace`/`vraceni`/`ostatni`, NULL = neurčeno). Zadává se v PromoModal, filtruje záložka „Promo kódy". SQL: `ALTER TABLE promo_codes ADD COLUMN IF NOT EXISTS source text;`. **Backfill + auto-tag (2026-06-20 B):** stávajícím kódům z vrácení (`code ILIKE 'VRACENI-%'`) doplněno `source='vraceni'`; budoucí auto-generované kódy z vrácení taguje trigger `trg_set_promo_code_source` (STATE_4).

### loyalty_levels (klíčové sloupce, zdokumentováno 2026-06-24)
Číselník věrnostních úrovní (rank 1–N) pro app slevy a žebříček. **PK = `level`** (integer, ne uuid).
- **level** (INTEGER PK NOT NULL), **discount_percent** (INTEGER NOT NULL) — sleva náležící úrovni (1–20 %)
- **min_booking_order** (INTEGER NOT NULL) — práh kvalifikujících rezervací pro dosažení úrovně
- **name** (TEXT NOT NULL), **color_hex** (TEXT NOT NULL) — popisek a barva odznaku
- **translations** (JSONB NOT NULL DEFAULT '{}') — překlady názvu úrovně pro web/app

### loyalty_monthly_winners (NEW — klíčové sloupce, zdokumentováno 2026-06-24)
Měsíční vítězové věrnostního žebříčku (kdo najel nejvíc dní za měsíc). **PK = `month`** (date, 1. den měsíce).
- **month** (DATE PK NOT NULL) — měsíc ocenění (zarovnáno na 1. den)
- **user_id** (UUID), **nickname** (TEXT) — zákazník + jeho přezdívka (`profiles.loyalty_nickname`)
- **days** (INTEGER) — počet najetých/rezervovaných dní v daném měsíci
- **awarded_level_before** (INTEGER) — věrnostní úroveň vítěze před udělením bonusu
- **awarded_at** (TIMESTAMPTZ NOT NULL DEFAULT now())

### service_orders (klíčové sloupce, zdokumentováno 2026-06-24)
Servisní zakázky navázané na motorky/servisní záznamy.
- id (UUID PK), **moto_id** (UUID NOT NULL), **maintenance_log_id** (UUID)
- **type** (TEXT NOT NULL), **items** (JSONB NOT NULL DEFAULT '[]'), **km** (INTEGER)
- **status** (TEXT NOT NULL DEFAULT 'pending'), **assigned_to** (TEXT), **notes** (TEXT)
- completed_at, created_at, updated_at
- **is_test** (boolean DEFAULT false) — testovací záznam z AI tréninku

### shop_orders
- id (uuid PK), order_number (text UNIQUE)
- customer_id (uuid FK→profiles ON DELETE SET NULL), customer_name, customer_email, customer_phone
- shipping_address (text), billing_address (text)
- **customer_company** (text, **NEW 2026-06-04**), **customer_ico** (text, **NEW 2026-06-04**), **customer_dic** (text, **NEW 2026-06-04**) — fakturační údaje z web objednávky poukazu (`poukazy-objednat.php`). Web voucher objednávka je anonymní (bez `customer_id`), takže firma/IČO/DIČ/adresa se ukládají přímo sem a `generate-invoice` je čte do ODBĚRATEL na DP/faktuře. Dříve JS posílal jen jméno/mail/telefon → na faktuře chybělo IČO i firma i adresa. `billing_address` (spojená adresa) se nově plní vždy (dřív jen `shipping_address` a jen u tisku).
- **shipping_method** (text, CHECK pickup/post/zasilkovna nebo NULL — **NEW 2026-05-07**, doplněno přes `ALTER TABLE` ručně po reportu chyby „column shipping_method does not exist" při doprodeji k rezervaci na webu; backfill ze `shipping_cost` 0/79/99 → pickup/zasilkovna/post)
- status (text CHECK: new/confirmed/processing/shipped/delivered/cancelled/returned/refunded)
- payment_status (text CHECK: pending/paid/refunded/failed) — **POZN.:** „unpaid" zde NENÍ povolené (na rozdíl od `bookings.payment_status`)
- payment_method (text)
- subtotal, shipping_cost, discount, total (numeric(10,2))
- promo_code_id (uuid FK→promo_codes), notes, tracking_number
- shipped_at, delivered_at, cancelled_at (timestamptz)
- **confirmed_at** — datum potvrzení (přidáno migrací)
- **stripe_payment_intent_id** — Stripe Payment Intent ID (pro refundy)
- **stripe_session_id** — Stripe Checkout Session ID
- **language** (text NOT NULL DEFAULT 'cs') — i18n customer comms (2026-05-03)
- created_at, updated_at

### products (nové sloupce)
- **size_stock** (JSONB NOT NULL DEFAULT '{}') — počet kusů per velikost: `{"M":5,"L":10,"XL":3}`. Velín `ProductsTab` modal renderuje input per velikost když má produkt `sizes[]`. `stock_quantity` = SUM hodnot, drženo v sync při ukládání produktu i při dekrementu v RPC `create_web_shop_order`. Produkty bez `sizes[]` mají `{}` a používají `stock_quantity` přímo (zpětná kompatibilita).
- **image_alts** (TEXT[] DEFAULT '{}', **NEW 2026-05-17**) — paralelní pole SEO alt popisků k `images[]` (stejný index). Admin ve Velíně `ProductsTab` u každého náhledu vyplňuje krátký popisek (např. „zepředu", „detail tkaniny"), PHP `shop-detail.php` skládá finální alt jako `"{name} – {popisek}"`. Pokud `image_alts[i]` prázdný/NULL → fallback na `t('shop.productAlt', ['name' => $name])` (původní chování). Migrace `20260517_image_alts.sql`.

### cms_pages (nové sloupce)
- **image_alts** (TEXT[] DEFAULT '{}', **NEW 2026-05-17**) — paralelní pole SEO alt popisků k `images[]` (stejný index). Admin ve Velíně `BlogWizard` u každého náhledu vyplňuje krátký popisek, PHP `blog-detail.php` skládá finální alt jako `"{title} – {popisek}"`. Pokud `image_alts[i]` prázdný/NULL → fallback na `$title` (původní chování). Migrace `20260517_image_alts.sql`.

### shop_order_items (nové sloupce)
- **product_id** (UUID FK→products ON DELETE SET NULL) — vazba na konkrétní produkt v katalogu (web naplní, app dnes ignoruje, NULL kompatibilní zpětně). Index `idx_shop_order_items_product_id`.
- **size** (TEXT NULL) — vybraná velikost položky („M", „42" apod.). Plní web (`create_web_shop_order` validuje proti `products.sizes[]`); Flutter app zatím NULL.

### branches (nové sloupce)
- **branch_code** (TEXT UNIQUE) — unikátní kód pobočky (6 číslic, např. "000126")
- **is_open** (BOOLEAN DEFAULT false) — otevřená (nonstop provoz) / zavřená
- **type** (TEXT DEFAULT NULL) — typ pobočky: turistická, městská, horská, rekreační voda, metropolitní centrum, městská tranzitní
- **translations** (JSONB DEFAULT '{}') — auto-překlady pro web (notes), plní `translate-content`

### Sloupec `translations` — auto-překlady pro veřejný web
**Účel:** Texty zadávané přes Velín (Blog, Produkty, Motorky, Pobočky, CMS proměnné) jsou v češtině; pro web motogo24.cz se automaticky překládají do en/de/es/fr/nl/pl přes Anthropic Claude API (edge funkce `translate-content`). Český text zůstává v původním sloupci jako fallback.

**Struktura:** `{"en":{"title":"...","content":"..."}, "de":{...}, "es":{...}, "fr":{...}, "nl":{...}, "pl":{...}}`

**Tabulky se sloupcem `translations` (JSONB DEFAULT '{}', GIN index):**
| Tabulka | Překládané pole |
|---------|------------------|
| `cms_pages` | title, excerpt, content |
| `cms_variables` | value |
| `products` | name, description, color, material |
| `motorcycles` | description |
| `branches` | notes |

**`cms_variables.category` CHECK constraint** (`cms_variables_category_check`, 2026-04-29): povoluje hodnoty `'general'`, `'web'`, `'pricing'`, `'contact'`, `'content'`, `'legal'` — totožné s `CATEGORIES` v `velin/src/pages/cms/VariablesTab.jsx`. Před 2026-04-29 chyběla `'web'` → `cms-save` edge fn (inline edit z webu) hodila 500 při INSERTu nového klíče s `category='web'`. Při změně Velín UI seznamu je nutné updatovat i tento constraint.

**Web (motogo-web-php):** helper `localized($row, $field)` v `i18n.php` čte `translations[lang][field] ?? row[field]`.

### branch_accessories
- id (UUID PK), branch_id (FK→branches ON DELETE CASCADE)
- type (TEXT) — CHECK constraint odstraněn, typy se řídí tabulkou `accessory_types`
- size (TEXT) — velikost (36-46 pro boty, XS-XXL pro ostatní, UNI pro kukly/spotřební)
- quantity (INTEGER DEFAULT 0)
- created_at, updated_at
- UNIQUE(branch_id, type, size)
- RLS: Admin full access
- **Propojení se skladem:** Při přidání/zvýšení množství se strhne z `inventory` (SKU: `prislusenstvi-{type}-{size}`). Při snížení půjčovaného zboží se vrátí na sklad. Spotřební zboží se nevrací.

### accessory_types
- id (UUID PK), key (TEXT UNIQUE) — slug typu (boots, helmet, passenger_gear, boots_rider, boots_passenger, ubrousky…)
- label (TEXT) — zobrazovaný název
- sizes (TEXT[]) — povolené velikosti (web rezervace je čte při buildu kroku 5 přes `MG._loadAccessoryConfig`). **Stav 2026-06-15:** `helmet = {XS,S,M,L,XL,2XL,3XL}`, `gloves = {M,L,XL,2XL,3XL}` (rozšíření o helma 3XL + rukavice 2XL/3XL pro dospělé). Frontend hardkódovaný fallback (web `pages-rezervace.js`/`pages-upravit-rezervaci.js`, app `booking_models.dart` `*SizesAdult`) sjednocen na stejné hodnoty.
- is_consumable (BOOLEAN DEFAULT false) — spotřební zboží (kukly, ubrousky) vs. půjčované (boty, helmy)
- **price_czk** (INTEGER NOT NULL DEFAULT 0) — cena v Kč pro placené extras (passenger_gear=690, boots_rider=290, boots_passenger=290 ze seedu 2026-05-05). Pro inventury rows (helmet/jacket/gloves/pants/boots/balaclava) zůstává 0.
- **pricing_unit** (TEXT NOT NULL DEFAULT 'per_booking', CHECK IN ('per_booking','per_day','free')) — `per_booking` = jednorázově za rezervaci, `per_day` = × počet dní, `free` = neúčtuje se. Web `MG._accessoryPrice` aktuálně počítá `per_booking`; multiplikace `per_day` se přidá až při zavedení nového typu.
- **audience** (TEXT NOT NULL DEFAULT 'adult', CHECK IN ('adult','child','both'), 2026-05-05) — pro koho jsou velikosti určené. Web `/rezervace` filtruje podle `motorcycles.license_required` (`N` = dětská) až s feature flagem `inventory_v2`. Velín ManageTypesModal nabízí dropdown 👤/👶/👤👶.
- sort_order (INTEGER DEFAULT 0), is_active (BOOLEAN DEFAULT true)
- created_at, updated_at
- RLS: Admin full access, Public read
- Trigger: trg_accessory_types_updated → update_updated_at()
- **Použití:**
  - **Velín** → Pobočky → Příslušenství → „Spravovat typy" — admin edituje key/label/sizes/price_czk/pricing_unit/is_consumable.
  - **Web** /rezervace krok 5 — `pages-rezervace.js#MG._loadAccessoryConfig()` fetchne `is_active=true` rows při init, naplní `MG._rez.accessoryConfig.{prices, sizes}`. Gear cards a size chip panely čtou z toho. Při fetch chybě fallback drží historické hodnoty.
  - **Faktury / refundy** — derivují z `bookings.total_price` a `extras_price`, takže změna ceny ovlivní jen nové rezervace (existující si nesou cenu z checkout času).

### branch_door_codes
- id (UUID PK), branch_id (FK→branches ON DELETE CASCADE)
- booking_id (FK→bookings ON DELETE CASCADE)
- moto_id (FK→motorcycles ON DELETE SET NULL)
- code_type (TEXT CHECK: motorcycle/accessories)
- door_code (TEXT NOT NULL) — 6-místný kód
- is_active (BOOLEAN DEFAULT false) — aktivní jen po dobu aktivní rezervace
- valid_from, valid_until (TIMESTAMPTZ)
- sent_to_customer (BOOLEAN DEFAULT false) — odesláno zákazníkovi
- sent_at (TIMESTAMPTZ)
- withheld_reason (TEXT) — důvod zadržení kódu (chybí doklady)
- created_at, updated_at
- RLS: Admin full access, Customer read own (via booking.user_id)
- Realtime: ANO

### faq_items (NEW)
- id (UUID PK)
- category_key (TEXT NOT NULL) — slug kategorie (reservations, borrowing, conditions, delivery, travel, vouchers...)
- category_label (TEXT NOT NULL) — zobrazovaný název kategorie
- question (TEXT NOT NULL)
- answer (TEXT NOT NULL) — HTML povolené (<strong>, <a href>, <br>)
- sort_order (INTEGER NOT NULL DEFAULT 0) — řazení uvnitř kategorie
- featured_home (BOOLEAN NOT NULL DEFAULT false) — zobrazit i v home FAQ sekci (top 4 podle sort_order)
- published (BOOLEAN NOT NULL DEFAULT true) — viditelné na webu
- translations (JSONB NOT NULL DEFAULT '{}') — auto-překlady přes translate-content edge fn ({en: {question, answer}, de: {...}, ...})
- created_at, updated_at (TIMESTAMPTZ NOT NULL DEFAULT now())
- Indexy: (category_key, sort_order), (published, sort_order) WHERE published, (featured_home, sort_order) WHERE featured_home
- RLS: public SELECT WHERE published=true, admin ALL
- Realtime: ANO

### app_installations (NEW 2026-06-28)
Přesná evidence instalací appky (zdroj pravdy pro DAU/WAU/MAU, instalace, uživatele) — plní `InstallationService` (oba Flutter balíky) heartbeatem.
- **device_id** (TEXT **PK**) — stabilní náhodné UUID v4 vygenerované appkou při 1. spuštění, uloženo v `flutter_secure_storage` (klíč `mg_device_id`). **NE hardwarový identifikátor** (Google Play safe).
- **user_id** (UUID NOT NULL FK→auth.users ON DELETE CASCADE) — heartbeat se posílá jen přihlášenému uživateli.
- **platform** (TEXT) — 'android' / 'ios'
- **app_version** (TEXT) — `version+buildNumber` z `package_info_plus`
- **push_enabled** (BOOLEAN NOT NULL DEFAULT false) — zda má zařízení povolené notifikace (`Permission.notification.isGranted`)
- **first_seen_at** / **last_seen_at** (TIMESTAMPTZ NOT NULL DEFAULT now()) — `last_seen_at` se obnovuje při každém heartbeatu (start po push initu, resume, signedIn; throttle 12 h). MAU/WAU/DAU se počítají z `last_seen_at`.
- created_at, updated_at (TIMESTAMPTZ NOT NULL DEFAULT now())
- Upsert z appky: `onConflict: 'device_id'` (payload bez `first_seen_at`/`created_at` → na konfliktu se zachovají).
- Indexy: `idx_app_installations_user` (user_id), `idx_app_installations_last_seen` (last_seen_at DESC), `idx_app_installations_platform` (lower(platform))
- Trigger: `trg_app_installations_touch` → `app_installations_touch()` (updated_at)
- RLS: `app_installations_owner_rw` (FOR ALL, `user_id = auth.uid()`) + `app_installations_admin_read` (SELECT, `is_admin()`)
- Realtime: NE

### Samoobslužná pobočka (kiosk) — NEW 2026-06-29
Klíčové sloupce (plný popis tabulek v STATE_1, RPC v STATE_3, triggery STATE_4, RLS STATE_5):

#### branch_kiosk_config
- **branch_id** (uuid PK FK→branches CASCADE)
- **music_on_url** / **music_off_url** (text) — HTTP GET spuštění/zastavení hudby na celé pobočce
- **door_open_seconds** (int DEFAULT 8) / **light_seconds** (int DEFAULT 120) / **music_seconds** (int DEFAULT 90)
- **power_status_url** (text) — LAN JSON endpoint měniče, který tablet stahuje a hlásí přes `kiosk_report_power`
- **power_poll_seconds** (int DEFAULT 60), **relay_base_url** (text, informativní), **is_active** (bool DEFAULT true)

#### kiosk_devices
- **id** (uuid PK) — unikátní identita zařízení (zadává se v appce při párování)
- **device_token** (uuid DEFAULT gen_random_uuid()) — tajný párovací token (autentizace všech kiosk RPC)
- **branch_id** (uuid FK→branches CASCADE), **name**, **platform**, **app_version**
- **last_seen_at** (timestamptz) — heartbeat á 30 s; online = < 70 s; **is_active** (revokace)

#### branch_doors
- **door_kind** (text CHECK motorcycle/accessories), **box_number** (int; = `motorcycles.box_number`, NULL u oblečení)
- **relay_url** (text — otevření zámku), **light_url** (text — světlo v garáži), **label**, **is_active**, **sort_order**
- UNIQUE index (branch_id, box_number) WHERE motorcycle; UNIQUE (branch_id) WHERE accessories

#### branch_service_codes
- **code** (text), **label**, **is_active**, **created_by** — UNIQUE(branch_id, code) WHERE is_active

#### kiosk_commands
- **device_id** (uuid FK→kiosk_devices CASCADE), **command** (CHECK open_door/music_on/music_off/identify/reload/camera_control/http_get)
- **params** (jsonb — např. {relay_url, light_url, music_url, url}), **status** (pending/done/failed/expired), **result** (jsonb), **executed_at**

#### branch_door_events
- **device_id** (uuid FK→kiosk_devices SET NULL), **door_id** (FK→branch_doors SET NULL), **kind**, **booking_id**, **success** (bool), **detail** (jsonb), **code_masked**

#### branch_cameras
- **kind** (CHECK snapshot/mjpeg/hls/iframe), **snapshot_url**, **stream_url**, **control_url** (PTZ/relé přes tablet), **sort_order**, **is_active**

#### branch_power_status
- **branch_id** (uuid PK), **battery_soc** numeric(5,1), **battery_voltage** numeric(6,2), **battery_power_w**/**pv_power_w**/**load_power_w** numeric(10,1)
- **grid_present** / **generator_on** (bool), **raw** (jsonb — celý payload z měniče), **updated_at**
