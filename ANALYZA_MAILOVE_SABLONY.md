# MotoGo24 — Analýza mailových triggerů a šablon (podklad pro copywriterku)

> Zdroj pravdy: edge funkce `send-booking-email`, `send-invoice-email`, `send-recovery-otp`
> + DB triggery a cron joby. Velín UI: **Dokumenty → E-mailové šablony**.
> Všechny zákaznické maily chodí přes **Resend** z adresy `noreply@motogo24.cz`.

---

## 1. Jak to celé funguje (technický rámec)

- **Spouštěč = událost** (platba, storno, dokončení, úprava…), ne ručně z Velínu (až na faktury).
- Událost vyvolá **DB trigger** nebo **cron**, který zavolá edge funkci `send-booking-email` s parametrem `type` + `source`.
- `source` určuje variantu šablony: **`app`** (mobilní aplikace / Velín) nebo **`web`** (motogo24.cz).
  - Pravidlo: `web_<type>` se hledá první; když web varianta neexistuje, použije se základní (app) šablona.
  - Příklad: web platba → hledá `web_booking_reserved`, fallback `booking_reserved`.
- Šablony se editují ve Velíně, ukládají do tabulky `email_templates` (sloupec `slug`).
- Každý mail má **branded HTML layout** (černá + zelená `#74FB71`, hlavička „MOTO GO 24").
- Paralelně s e-mailem chodí u většiny událostí i **SMS + WhatsApp** (přes Twilio) — jiné, kratší šablony (tabulka `message_templates`). Tento dokument řeší **e-maily**.

---

## 1b. Všech 24 šablon (přesně jak je třídí Velín)

Velín → Dokumenty → E-mailové šablony načítá **všechny řádky** z tabulky `email_templates`
a třídí je do 5 kategorií podle metadat slugu. Slugy bez kategorie spadnou do **„Ostatní"** —
proto tam jsou i e-shop objednávky a přístupové kódy.

| Kategorie | Počet | Šablony |
|---|---|---|
| **Rezervace** | 8 | `booking_reserved` + `web_`, `booking_modified` + `web_`, `booking_completed` + `web_`, `booking_abandoned` + `web_` |
| **Storno** | 2 | `booking_cancelled` + `web_` |
| **Faktura** | 4 | `invoice_advance`, `invoice_payment_receipt`, `invoice_final`, `invoice_shop_final` |
| **E-shop** | 2 | `voucher_purchased` + `web_` |
| **Ostatní** | 8 | `shop_order_confirmed`, `shop_order_shipped`, `door_codes`, `web_door_codes`, `sos_incident`, `booking_missing_docs`, `booking_abandoned_full`, ~~`shop_order_created`~~ (vypnuto) |
| **CELKEM** | **24** | 23 aktivních + 1 vypnutý |

> ✅ **Ověřeno proti ostré DB** (24 řádků). `shop_order_created` je deaktivováno (2026-05-03, nahrazeno `shop_order_confirmed`).
>
> 📌 **Mimo tabulku `email_templates`:** mail **„Reset hesla"** (`recovery_otp`) se needituje ve Velíně — je natvrdo v edge funkci `send-recovery-otp` (zelený box s 8znakovým kódem, platnost 1 h). Úprava textu = zásah do kódu.

---

## 2. KOMPLETNÍ PŘEHLED SCÉNÁŘŮ — co, kdy, odkud, s čím

### A) REZERVACE

| Scénář | Slug šablony | Kdy přesně se odešle | Kanál | Přílohy |
|---|---|---|---|---|
| **Potvrzení rezervace** | `booking_reserved` / `web_booking_reserved` | Ihned po **úspěšné platbě** (Stripe webhook). Pro budoucí termín → stav `reserved`, pro dnešek → `active`. | App + Web | **ZF** (zálohová/proforma), **DP** (doklad o platbě), **Smlouva**, **VOP** |
| **Úprava rezervace** | `booking_modified` / `web_booking_modified` | Při **jakékoli změně** rezervace — zkrácení, prodloužení, změna motorky, místa přistavení nebo času. Trigger `trg_booking_modified_email` pokrývá Velín, web (RPC `apply_booking_changes`), Flutter app i AI agenta. Mail obsahuje **diff tabulku „Původní vs Nové"**. Dedup 5 min. | App + Web + Velín | **ZF, DP, Smlouva, VOP**; při **doplatku** DP rozdílu, při **zkrácení/vratce** Dobropis |
| **Dokončení pronájmu** | `booking_completed` / `web_booking_completed` | Po přechodu **`active → completed`** (vrácení motorky). Spouští se při vložení **KF** (konečné faktury). Cron auto-complete běží denně 00:01 pro propadlé. Obsahuje **žádost o recenzi** (Google/FB) + **slevový kód `VRACENI-…`** (200 Kč, platnost 1 rok) na příště. | App + Web | **KF** (konečná faktura) |
| **Nedokončená rezervace** (opuštěný košík) | `booking_abandoned` / `web_booking_abandoned` | **POUZE WEB.** Cron každé 2 min; odešle se **15 min od založení** rezervace, pokud zůstala pending+unpaid. Obsahuje **CTA „Dokončit rezervaci"** (link na Stripe checkout, jinak `…/rezervace?resume=<id>`). 1 mail na rezervaci (dedup). | Web | **ZF** |
| **Chybí doklady** | `booking_missing_docs` | **POUZE WEB**, zaplacená rezervace, ale chybí nahraný OP/ŘP. **5 min od potvrzení**. Link na `…/upravit-rezervaci?id=…#doklady`. Posílá se jen u **samoobslužného vyzvednutí** (ne delivery, ne obslužná pobočka Mezná, ne dětská motorka). | Web | — |

### B) STORNO

| Scénář | Slug šablony | Kdy přesně | Kanál | Přílohy |
|---|---|---|---|---|
| **Storno rezervace** | `booking_cancelled` / `web_booking_cancelled` | Při přechodu na stav **`cancelled`** z jakéhokoli zdroje (zákazník v appce/webu, admin ve Velíně). Automatický **Stripe refund** dle storno tabulky: **7+ dní = 100 %, 2–7 dní = 50 %, <2 dny = 0 %**. | App + Web + Velín | **Dobropis** (credit note) |

> Pozn.: U **app** rezervace zrušené auto-cancelem (nezaplaceno do 10 min) se posílá storno mail bez dobropisu. U **web** pending+unpaid se storno mail **neposílá** — zákazník už dostal „Nedokončenou rezervaci".

### C) E-SHOP / DÁRKOVÉ POUKAZY

| Scénář | Slug šablony | Kdy přesně | Kanál | Přílohy |
|---|---|---|---|---|
| **Nákup dárkového poukazu** | `voucher_purchased` / `web_voucher_purchased` | Po **zaplacení objednávky poukazu** (Stripe webhook → trigger). Generuje voucher kódy. | App + Web | **ZF, DP, dárkový poukaz (PDF, fallback HTML), FV** (u elektronických poukazů) |
| **Potvrzení e-shop objednávky** | `shop_order_confirmed` | Trigger na `shop_orders` při **`payment_status: pending → paid`**. | App + Web | **DP** (doklad o platbě) |
| **Objednávka odeslána** | `shop_order_shipped` | Při **expedici** z Velínu (stav `shipped`/`delivered`) u fyzického zboží. | Velín | **KF** (konečná faktura) |

### D) OSTATNÍ

| Scénář | Slug šablony | Kdy přesně | Kanál | Přílohy |
|---|---|---|---|---|
| **Přístupové kódy k pobočce** | `door_codes` / `web_door_codes` | **Jen dodatečně** — když kódy nebyly uvolněné už v `booking_reserved` mailu. Typicky když zákazník nahrál doklady (OP/ŘP) **až po platbě**. Spouští `release_withheld_door_codes_for_user` → `send_door_codes_email`. 1 mail na rezervaci. | App + Web | — |
| **SOS incident** | `sos_incident` | Automaticky při **nahlášení SOS** z aplikace. Omluva + kontakt na linku pomoci. | App | — |
| **Reset hesla (OTP)** | `recovery_otp` *(jiná edge fn `send-recovery-otp`)* | Při žádosti o reset hesla z webu i appky. **Zelený monospace box s 8znakovým kódem**, platnost 1 h. Nejde přes `send-booking-email`. | App + Web | — |

### E) FAKTURAČNÍ MAILY (edge fn `send-invoice-email`, většinou ručně z Velínu)

| Slug | Co je to | Kdy | Příloha |
|---|---|---|---|
| `invoice_advance` | Zálohová faktura (ZF/proforma) | Ruční odeslání z Velínu / auto | Faktura |
| `invoice_payment_receipt` | Doklad o přijaté platbě (DP) | Ruční / auto | Doklad |
| `invoice_final` | Konečná faktura (FV/KF) | Po dokončení pronájmu / ručně | Faktura |
| `invoice_shop_final` | Konečná faktura za e-shop | Při expedici z Velínu | Faktura |

---

## 3. APP vs WEB — rychlá orientace

- **Web** (motogo24.cz): používá `web_*` slugy. Navíc jen na webu existují: **nedokončená rezervace** a **chybí doklady**.
- **App** (mobilní aplikace) + **Velín**: základní slugy bez prefixu.
- **Společné** (nemají web/app variantu): faktury, `sos_incident`, `shop_order_confirmed`, `shop_order_shipped`, `door_codes`.
- Když web varianta není vyplněná, **automaticky padá na app verzi** — copywriterka nemusí povinně psát obě, ale web verze je vhodná pro odlišný tón (anonymní zákazník bez účtu).

---

## 4. Časování (shrnutí cronů a prahů)

| Událost | Práh / čas |
|---|---|
| Nedokončená rezervace (web) | **15 min** od založení; cron každé 2 min |
| Chybí doklady (web) | **5 min** od potvrzení platby |
| Auto-zrušení nezaplacené rezervace | App **10 min**, Web **4 h** |
| Auto-dokončení propadlých rezervací | denně **00:01** |
| Expirace poukazů | denně **01:00 UTC** |

---

## 5. Nejčastější proměnné v šablonách (placeholdery)

Copywriterka je vkládá ve formátu `{{nazev}}`. Nejdůležitější:

- **Rezervace:** `{{booking_number}}`, `{{customer_name}}`, `{{moto_model}}` / `{{motorcycle}}`, `{{start_date}}`, `{{end_date}}`, `{{total_price}}`, `{{pickup_location}}`, `{{pickup_time}}`
- **Úprava:** `{{price_difference}}` (záporné = vratka), diff tabulka „Původní vs Nové"
- **Dokončení:** `{{google_review_url}}`, `{{facebook_review_url}}`, `{{discount_code}}` (např. `VRACENI-…`)
- **Nedokončená rezervace:** `{{resume_link}}` (CTA na dokončení)
- **Poukaz / e-shop:** `{{voucher_code}}`, `{{voucher_amount}}`, `{{voucher_expiry}}`, `{{order_number}}`
- **Přístupové kódy:** `{{door_code_moto}}`, `{{door_code_gear}}`, `{{door_codes_block}}`
- **Storno:** `{{cancellation_reason}}`, `{{refund_amount}}`, `{{refund_percent}}`
- **Firma:** `{{company_name}}`, `{{company_phone}}`, `{{company_email}}`, `{{site_url}}`

---

## 6. Co si pamatovat při psaní textů

1. **Mail = potvrzení transakce**, ne marketing — zákazník čeká věcnou informaci (kdy, kde, kolik, jak vyzvednout).
2. **Přílohy jsou účetní doklady** (ZF/DP/KF/Dobropis/Smlouva/VOP) — v textu na ně lze odkázat („fakturu najdete v příloze").
3. **Web zákazník nemusí mít účet** — web varianty piš tak, aby fungovaly i pro anonyma.
4. **door_codes / přístupové kódy** jsou citlivé — text by měl upozornit, že kódy jsou jen pro daný pronájem.
5. **booking_completed** je jediný „prodejní" mail — recenze + slevový kód na příště.
