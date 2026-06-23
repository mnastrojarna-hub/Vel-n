# SUPABASE BACKEND STATE — MotoGo24 (Část 5: RLS, Realtime, Edge, Storage, Secrets, Cron, FK)
> **Soubory:** 1/6 (Tabulky) | 2/6 (Sloupce) | 3/6 (RPC funkce) | 4/6 (Triggery) | **5/6 (RLS, Realtime, Edge, Storage, Secrets)** | 6/6 (Changelog)

---

## 6. RLS POLITIKY (kompletní)

Všechny tabulky mají RLS zapnuté. Vzory:
- **Admin full access:** `FOR ALL USING (is_admin())`
- **Superadmin write:** `FOR ALL USING (is_superadmin())`
- **Customer read own:** `FOR SELECT USING (user_id = auth.uid())`
- **Customer insert own:** `FOR INSERT WITH CHECK (user_id = auth.uid())`
- **Public read:** `FOR SELECT USING (true)` — branches, moto_locations, moto_day_prices, promo_codes(active), app_settings, motorcycles
- **Branch-based admin access:** Některé politiky kontrolují `admin_users.branch_access` pro omezení přístupu dle pobočky

Detailní politiky:
- **bookings:** user SELECT/INSERT/UPDATE (user_id=uid OR is_admin), admin DELETE, **anon SELECT (`bookings_anon_pending_realtime`)** — JEN web pending+unpaid řádky max 4 hod staré (PC ↔ mobil realtime mirror v rezervaci, redirect na děkovací po platbě na mobilu)
- **profiles:** user SELECT (id=uid OR is_admin), user UPDATE (id=uid), admin ALL
- **motorcycles:** public SELECT, admin ALL
- **sos_incidents:** admin ALL, customer SELECT/INSERT/UPDATE (user_id=uid)
- **sos_timeline:** admin ALL, customer SELECT/INSERT (own incident)
- **messages:** admin ALL, customer SELECT (own thread), customer INSERT (direction='customer' + own thread)
- **message_threads:** admin ALL, customer SELECT/UPDATE/INSERT (customer_id=uid)
- **admin_messages:** admin ALL + INSERT, user SELECT (user_id=uid OR is_admin), user UPDATE (own)
- **vouchers:** admin ALL, user SELECT (buyer_id OR redeemed_by = uid)
- **reviews:** admin ALL, customer SELECT (own OR visible=true), customer INSERT (own)
- **documents:** admin ALL, customer SELECT/INSERT (user_id=uid)
- **custom_documents:** admin ALL (is_admin), public SELECT (active=true AND show_on_web=true) — web čte anon klíčem
- **invoices:** admin ALL, customer SELECT/INSERT (customer_id=uid)
- **products:** public SELECT (is_active), admin ALL
- **shop_orders:** admin ALL, customer SELECT/INSERT/UPDATE (customer_id=uid)
- **shop_order_items:** admin ALL, customer SELECT/INSERT (order owned by user)
- **payment_methods:** admin ALL, customer SELECT/INSERT/UPDATE/DELETE (user_id=uid)
- **booking_cancellations:** admin ALL, customer SELECT (cancelled_by=uid)
- **maintenance_log:** admin ALL (is_admin), public SELECT
- **maintenance_schedules:** admin ALL (is_admin), public SELECT
- **service_parts:** admin ALL (is_admin), public SELECT
- **service_orders:** admin ALL (is_admin)
- **emp_attendance:** admin ALL (is_admin)
- **emp_vacations:** admin ALL (is_admin)
- **emp_shifts:** admin ALL (is_admin)
- **emp_documents:** admin ALL (is_admin)
- **delivery_notes:** admin ALL (is_admin)
- **contracts:** admin ALL (is_admin)
- **api_keys:** admin ALL (is_admin)
- **ai_traffic_log:** admin SELECT (is_admin), service_role INSERT (WITH CHECK true) — anon + edge fns mohou logovat
- **ai_citations:** admin ALL (is_admin)
- **ai_public_conversations:** admin ALL (is_admin) — service_role INSERT/UPDATE přes upsert v edge fn ai-public-agent
- **faq_items:** public SELECT (published=true), admin ALL (is_admin) — Realtime ANO

### Doplněno 2026-06-04 ze snapshotu (96 tabulek má RLS; dříve nezdokumentované)
Ověřené vzory z živého schématu (`schema_public.sql`):

- **Admin-only `FOR ALL USING (is_admin())`** (účetnictví / finance / nákup / konfigurace / logy): `acc_depreciation_entries`, `acc_liabilities`, `acc_long_term_assets`, `acc_payrolls`, `acc_short_term_assets`, `acc_tax_returns`, `acc_vat_returns`, `accounting_entries`, `accounting_exceptions`, `approval_queue`, `flexi_reports`, `flexi_sync_log`, `cash_register`, `tax_records`, `daily_stats`, `branch_performance`, `moto_performance`, `predictions`, `automation_rules`, `auto_order_rules`, `notification_rules`, `notification_log`, `sent_emails`, `suppliers`, `purchase_orders`, `purchase_order_items`, `inventory_movements`, `broadcast_campaigns`, `ai_logs`.
- **Public/anyone SELECT + admin write** (číselníky/šablony/CMS): `message_templates` (SELECT true, write is_admin), `accessory_types` (Public read + Admin full), `pricing_rules`, `feature_flags`, `cms_pages` (read true / write is_admin), `loyalty_levels` (**NEW 2026-06-11** — Public read + Admin write; věrnostní ranky pro app).
- **Logy aplikace — admin SELECT + vlastní/anon INSERT:** `app_crash_reports` (admin ALL + INSERT WHERE user_id IS NULL OR =auth.uid()), `app_debug_logs` (dtto), `visitor_log` (admin SELECT + INSERT TO anon,authenticated WITH CHECK true).
- **`admin_audit_log`:** admin SELECT + admin INSERT + **superadmin DELETE** (`is_superadmin()`).
- **Trasy — Public read + Admin write (NEW 2026-06-21, `20260621_routes_feature.sql`):** `routes` (`routes_public_read`: SELECT TO anon,authenticated USING `is_active=true OR is_admin()`; `routes_admin_all`: FOR ALL TO authenticated USING/CHECK `is_admin()`), `route_pois` (`route_pois_public_read`: SELECT USING EXISTS nadřazené trasy `is_active=true OR is_admin()`; `route_pois_admin_all`: FOR ALL `is_admin()`). Appka čte přes SECURITY DEFINER RPC `get_branch_routes`.

> Pozn.: jde o standardní vzory již popsané nahoře (admin full / public read / customer own). Plný a přesný výčet všech 224 politik je v etalonu `supabase-live-snapshot:supabase/_snapshot/schema_public.sql`.

---

## 7. REALTIME (supabase_realtime publication)

- `sos_incidents`
- `sos_timeline`
- `messages`
- `message_threads`
- `admin_messages`
- `motorcycles`
- `bookings`
- `products`
- `documents`
- `invoices`
- `vouchers`
- `faq_items`

---

## 8. EDGE FUNKCE (32 aktivních po cleanup)

### V repozitáři (28 — všechny deployované)

| Funkce | JWT | Popis |
|--------|-----|-------|
| `admin-auth` | OFF | Autentizace a auto-provisioning admin uživatelů (ověření JWT + insert do admin_users přes service role) |
| `resolve-mapy-route` | OFF | **NEW 2026-06-21 (trasy).** Rozbalí zkrácený Mapy.com sdílecí odkaz (`mapy.com/s/…`) — následuje redirect s browser UA (prohlížeč to kvůli CORS nezvládne), vytáhne `rc` a dekóduje body trasy (Mapy.cz delta base64, čteno odzadu, přesnost 2^28). POST `{url}`, vrací `{success,url,rc,waypoints:[{lat,lng}]}`. Auth: jen admin (RPC `is_admin` z předaného JWT), `verify_jwt=false` (vlastní ověření). Plnou URL s `rc` si Velín dekóduje sám (`lib/mapyRoute.js`) bez volání této fn. Použití: Velín → Trasy → „📥 Načíst trasu". |
| `admin-reset-password` | OFF | Admin reset hesla zákazníka |
| `ai-copilot` | OFF | AI Copilot pro Velín dashboard — Anthropic Claude API, system prompt CZ, načítá kontext z DB (bookings, tržby, servis, SOS), ukládá do ai_conversations |
| `ai-moto-agent` | OFF | AI Servisní (SOS) agent pro zákazníky v appce — diagnostika závad motorek přes Claude API, vrací {reply, suggest_sos}, načítá kontext motorky z booking_id. Konfigurace z `app_settings.ai_moto_agent_config` (situations/mustDo/forbidden — Velín AppAgentSettingsPanel). **UPDATE 2026-06-23:** tool `get_motorcycle_manual` nově OTEVÍRÁ A ČTE skutečný návod motorky (PDF `manual_url` v bucketu `media` přes `unpdf`, jinak web `manual_external_url`) a vrací relevantní pasáže dle `query` + základní specs — stejná schopnost jako veřejný agent `ai-public-agent` (do té doby vracel jen řádek z `motorcycles`). Fallback system prompt + auto-footer doplněny o situační/zakázaná pravidla a povinnost brát technické super-detaily VÝHRADNĚ z návodu. Agent reaguje jen na text/fotky (žádný mikrofon). **UPDATE 2026-06-23 (C2):** agent má nově STEJNÉ informační nástroje jako veřejný agent — soubor `public-tools.ts` přebírá z `ai-public-agent` 9 read-only toolů: `search_motorcycles`, `get_availability`, `calculate_price`, `get_faq`, `get_policies`, `get_legal_document`, `get_extras_catalog`, `get_branches`, `validate_promo_or_voucher` (logika 1:1, parametrizovaná `sb`+`lang`). Záměrně VYNECHÁNY: `create_booking_request`, `find/preview/apply_booking_change` (+ light) a prodejní `redirect_to_booking` — agent rezervace NETVOŘÍ ani NEUPRAVUJE. Role přenastavena na **technická podpora a pomocník, ne prodejce** (guardrail v promptu). `index.ts` přijímá `lang` z těla requestu (default cs, appka posílá locale) a předává do toolů → FAQ/policies/dokumenty v jazyce zákazníka. Celkem 14 toolů (5 app: get_active_booking/get_booking_history/get_motorcycle_manual/search_troubleshooting/get_fleet_overview + 9 převzatých). |
| `auto-check-service-parts` | OFF | Automatická kontrola dílů pro blížící se servisy. Volá RPC auto_check_service_parts() → vytvoří PO → odešle email dodavateli přes send-order-email. Spouštěno denně cron jobem |
| `datova-schranka` | OFF | Podání schválených finančních reportů přes ISDS (datová schránka) |
| `flexi-sync` | OFF | Synchronizace s Abra Flexi účetním softwarem |
| `generate-document` | OFF | Generuje dokumenty z šablon (rental_contract, handover_protocol, vop). Firemní údaje načítá z app_settings (company_info). **i18n 2026-06-01:** přijímá volitelný `language` (cs/en/de/es/fr/nl/pl, default cs). Pro non-cs vyzvedne přeložený obsah z `document_templates.content_translations[lang]` + `name_translations[lang]` (plní translate-document), jinak fallback na CZ `content_html` (cs = beze změny). `{{company_web}}` = `motogo24.cz` (cs) / `motogo24.com` (ostatní); URL odkazy `http(s)://(www.)motogo24.cz` v obsahu se pro non-cs přepíšou na `motogo24.com` (e-mail `info@motogo24.cz` se NEmění). `<html lang>` = jazyk zákazníka. Volá se z `send-booking-email` (smlouva/VOP přílohy) s `language=custLang`. **Přemazání starých verzí 2026-06-08:** při přegenerování téhož typu dokumentu pro tutéž rezervaci (identita = `booking_id` + `template_id`) fn po vložení nové `generated_documents` verze: a) přesměruje synchronizovaný `documents` řádek (`type` ∈ contract/protocol/vop dle `template_slug`) na nový `pdf_path`, b) smaže staré `generated_documents` řádky, c) odstraní jejich soubory v bucketu `documents`. Bez toho se ve Velíně hromadily duplicitní smlouvy/protokoly/VOP a `documents.file_path` (trigger `sync_generated_doc_to_documents` vkládá jen `WHERE NOT EXISTS`) visel na smazaném souboru. Fallback dokumenty bez `template_id` se NEpřemazávají. |
| `generate-invoice` | OFF | Generuje proforma/finální fakturu (ZF-/FV-/DP-YYYY-NNNN). Firemní údaje načítá z app_settings (company_info). Deduplikace, odečet záloh. **Voucher/e-shop ODBĚRATEL 2026-06-04:** u anonymní objednávky (bez `customer_id`) čte fakturační údaje (firma/IČO/DIČ/adresa) přímo ze `shop_orders` (`customer_company/customer_ico/customer_dic/billing_address`) — dřív padal na fallback jen jméno/mail/telefon. **Param `regenerate:true` (2026-06-04):** přegeneruje existující doklad aktuálními údaji — místo dedup early-return přepíše stávající `invoices` řádek (zachová číslo i vazby, aktualizuje items/customer/subtotal/total) a znovu vyrenderuje PDF (upsert do stejné storage cesty). Volá Velín `ShopOrderDetail` z tlačítek „Přegenerovat ZF / DP / fakturu" po úpravě fakturačních údajů zákazníka. **Param `render_existing:true` (2026-06-06):** early-return větev, která **dorenderuje PDF pro EXISTUJÍCÍ doklad bez `pdf_path`** z jeho **ULOŽENÝCH** `items` (NEpřepočítává položky, nemění číslo/řádek) — řeší KF k rezervaci, kterou vystavuje DB trigger `generate_final_invoice_on_complete()` bez renderu PDF (Velín ji renderuje client-side, takže `pdf_path` zůstával NULL a mail `booking_completed`/`web_booking_completed` ji neměl jak přiložit). Vstup `{render_existing:true, booking_id, type?}` (type default `final`). Titul „KONEČNÁ FAKTURA" (type=`final`), upsert do `invoices/<id>.pdf` (PDFShift, HTML fallback), doplní `pdf_path`. Idempotentní (když použitelné PDF existuje, jen vrátí). Volá `send-booking-email` z bloku `booking_completed`, když KF řádek existuje, ale `pdf_path` chybí. **Anti-duplicita shop_final (2026-06-04):** elektronický voucher generoval 2× `shop_final` (race: `confirmShopPayment` přímé volání × DB trigger `generate_shop_final_on_ship` přes status→delivered). Fix: (a) když doklad existuje bez PDF, přepíše se stávající řádek místo vytvoření nového; (b) INSERT ošetřen na unique-violation (`23505`) → vrátí existující; (c) DB unikátní index `uq_invoices_active_order_type` na `invoices(order_id, type) WHERE order_id IS NOT NULL AND status<>'cancelled'` garantuje max 1 aktivní doklad daného typu na e-shop objednávku. **Param `price_difference` (2026-06-11, source='edit'):** autoritativní částka doplatku pro rozdílovou ZF/DP při úpravě rezervace — posílá ji send-booking-email z trigger payloadu (NEW.total − OLD.total). Dřív se částka četla VÝHRADNĚ z `modification_history[last].price_diff`, který žádná RPC nezapisuje (a placená výbava / webhook doplatek do historie nezapisují vůbec) → rozdílový doklad nikdy nevznikl a mail nesl starý DP. Denní rozpis přidaných dnů jen pro čerstvý (≤15 min) history záznam se změnou termínu; jinak generický řádek „Doplatek za úpravu rezervace". Idempotence: edit doklad stejného typu a částky ≤15 min starý → vrátí existující (souběžný dispatch hardcoded mail × dispatch_email_event). **+ Věrnostní sleva (2026-06-11):** booking ZF/DP — `baseRental += loyalty_discount_amount` a samostatný záporný řádek „Věrnostní sleva X % — rezervace přes aplikaci MotoGo24" (loyalty je oddělená od promo/voucher `discount_amount`). |
| `manage-payment-methods` | OFF | Správa uložených platebních metod (Stripe). Akce: list, delete, set_default, setup. Synchronizuje karty do tabulky payment_methods |
| `process-payment` | OFF | Stripe platební brána (**LIVE mode**). Podporuje booking, shop, extension i SOS platby. Vytváří Stripe Checkout Session. Automaticky vytváří/používá Stripe Customer. **Web shop:** dvě větve v `handleWebShopCheckout`: a) **`kind:'products'`** (motogo24.cz e-shop, od 2026-04-28) — `handleWebProductCheckout` načte `shop_orders` + `shop_order_items` z DB (RPC `create_web_shop_order` je vytvoří předem, cena z DB), sestaví Stripe line items per item s `(vel. M)` suffixem, oddělený line item pro dopravu (Zásilkovna 79 / pošta 99 Kč), Stripe coupon při `discount > 0`, `automatic_payment_methods` enabled (Apple Pay / Google Pay). `success_url=${SITE_URL}/objednavka/dokoncit?order_id=…&session_id={CHECKOUT_SESSION_ID}`, `cancel_url=${SITE_URL}/kosik`. b) **voucher (default)** — původní flow pro Flutter app a `/poukazy/objednat` beze změny. **Web Checkout — výběr metod (2026-06-06):** rezervační (`handleWebBookingCheckout`), e-shop produktová (`handleWebProductCheckout`) i voucher Session nastavují explicitně `payment_method_types: ['card', 'link']` (karta první, Link druhý) → hosted Checkout zobrazí jako default standardní VÝBĚR metod (karta + Apple Pay/Google Pay peněženky + Link jako volbu) místo vynucené „Link-first" přihlašovací obrazovky, kterou Stripe u vrácených Link uživatelů ukazoval, dokud se metody řešily jen přes Dashboard. Apple Pay / Google Pay (card wallets) zůstávají, vyžadují aktivaci + ověření domény v Dashboardu. Setup mód 0 Kč rezervace = `['card']`. Obě větve generují ZF (`shop_proforma`) + odesílají email se shrnutím. Po platbě webhook detekuje `metadata.type=shop` → `confirm_shop_payment` RPC → existující triggery (faktura, mail). **Bundled booking + shop (od 2026-04-28):** `handleWebBookingCheckout` přijímá volitelný `shop_order_id` — načte `shop_order_items` a přidá je jako další Stripe `line_items` do stejné Checkout Session (jedna platba zákazníka, dva oddělené účetní doklady). `metadata.shop_order_id` umožní webhooku zavolat `confirmShopPayment` vedle `confirmBookingPayment` → vygenerují se **dvě nezávislé faktury** (booking ZF/FV + shop ZF/DP) a odešlou se **dva emaily**. **FIX 2026-06-01 (doplatková změna rezervace):** pro `type='extension'` přijímá z body volitelný objekt `change` (payload změny rezervace z webu „Upravit rezervaci") a — pokud `JSON.stringify(change).length ≤ 500` — uloží ho do `metadata.chg`. Webhook ho po potvrzení platby aplikuje server-side (viz `webhook-receiver`), takže doplatkové prodloužení/změna se uloží a `web_booking_modified` mail dorazí i když se zákazník nevrátí do prohlížeče (platba na jiném zařízení / vyčištěné localStorage). Delší payload se do metadat nevejde → zůstává klientský fallback. **NEW 2026-06-14 (`action:'create_sos_payment_link'`, `payment-flows.ts#handleSosPaymentLink`):** Velín operátor (Nový incident / detail incidentu) vytvoří Stripe Checkout ODKAZ pro PLACENOU SOS náhradu — body `{action:'create_sos_payment_link', booking_id, incident_id, amount}` (amount = nájem náhrady + přistavení + spoluúčast 30 000 Kč). Metadata `type:'sos'` → po zaplacení webhook-receiver zavolá `confirmSosPayment` a označí náhradní rezervaci `paid` (stejná cesta jako placené SOS v aplikaci). `bookings.total_price` zůstává jen nájem+přistavení (spoluúčast = vratná kauce, ne tržba); odkaz se uloží do `bookings.stripe_checkout_url`. Běží přes service_role (nezávislé na JWT volajícího), reuse Stripe Customer dle e-mailu. |
| `process-refund` | OFF | Stripe refundy (LIVE). Částečné i plné vrácení peněz. Volá Stripe Refund API. **UPDATE 2026-05-31:** brána refundu propouští `payment_status IN ('paid','refund_pending')` (předtím jen `paid`) — stornovaná zaplacená rezervace (Velín ji rovnou označí `refund_pending`) jde refundovat. Mapování výsledného stavu: Stripe refund `status='pending'` → `refund_pending` (Čeká na vrácení, finále dorazí webhookem `charge.refunded`); zadaná částečná `amount` menší než zbývající k vrácení → `partial_refund`; jinak plné → `refunded`. **UPDATE 2026-06-11:** `partial_refund` už NENÍ terminální — s explicitní `amount>0` (další rozdílová úprava rezervace se slevou: levnější motorka, odebraná výbava, zkrácení) se vystaví DALŠÍ částečný Stripe refund + dobropis. Dedup: čerstvý CN (≤15 min) na stejnou částku → vrátí existující místo nového refundu; bez `amount` zůstává idempotentní recovery chování (dorenderování PDF / CN ze Stripe dat). Stripe `idempotencyKey` (`refund:<booking/order>:<haléře>:<počet existujících CN>`) sráží souběžné dispatche téže refundace (pg_net z `_apply_booking_changes_core` × recovery retry v send-booking-email) do jediného Stripe refundu. Stripe-side cap (charged − already refunded) dál chrání před over-refundem. |
| `receive-invoice` | OFF | OCR + AI zpracování přijatých faktur (Claude Vision). Extrakce dat, klasifikace, routing do účetních tabulek |
| `scan-document` | OFF | OCR skenování dokladů (OP, ŘP, pas) přes Mindee v2 API (enqueue+poll). Model ID z MINDEE_MODEL_ID secret. Retry 3×, loguje do debug_log |
| `save-verification-document` | OFF | **NEW 2026-05-04** — Robustní uložení fotky verifikačního dokladu (OP/pas/ŘP) z webu. Volá se z rezervačního flow VŽDY (i když Mindee OCR selže), aby zákazník nikdy nepřišel o nahranou fotku. Běží pod **service_role** → obejde RLS pro `storage.objects` i `public.documents`, nezávisí na customer auth session (web booking flow má fragile signin přes `set_web_booking_password`+`signInWithPassword`). Vstup: `{user_id, booking_id?, doc_type: 'id'|'dl'|'passport', image_base64, mindee_status: 'ok'|'failed', ocr_fields?, mime?}`. Validace: user_id musí existovat v `profiles`, booking_id musí patřit user_id, max 8 MB, MIME whitelist (jpeg/png/webp/pdf). Uloží do `documents` bucketu pod `<user_id>/<dbType>_<ts>.<ext>` + insert do `public.documents` s `metadata.mindee_status`. Frontend (`pages-rezervace-scan.js` `MG._rezSaveDocPhoto`) má fallback na přímý SDK upload pokud edge fn selže. |
| `render-pdf` | OFF | **NEW 2026-06-05** — Generický HTML → PDF přes PDFShift (stejný renderer jako `generate-invoice`). Vstup `{ html, landscape?, margin?, format? }` → vrací PDF byty (`Content-Type: application/pdf`) + CORS. Slouží Velínu (Finance/Dokumenty), aby účetní doklady vypadaly 1:1 jako e-shop/maily — předtím Velín skládal PDF klientsky přes `html2pdf.js` (html2canvas) / tisk z prohlížeče → rozbitý layout a chybějící barvy pozadí. Klient (`velin/src/lib/htmlToPdf.js`) volá tuto fn primárně, html2pdf.js zůstává jako fallback. Závisí na secret `PDFSHIFT_API_KEY` (už existuje). Deploy: `supabase functions deploy render-pdf`. |
| `send-booking-email` | OFF | Odesílá branded HTML emaily (booking_reserved, booking_completed, booking_modified, voucher_purchased, **door_codes**, sos_incident, booking_abandoned, booking_cancelled). Retry 3×. **FIX 2026-06-06 (KF v `booking_completed`/`web_booking_completed`):** blok `booking_completed` přikládal KF jen když měla `pdf_path`, ale KF z DB triggeru `generate_final_invoice_on_complete()` PDF nerenderuje (`pdf_path` NULL → Velín renderuje client-side). Nově když KF řádek existuje bez `pdf_path`, zavolá `generate-invoice` s `render_existing:true` (dorenderuje PDF z uložených položek) a teprve poté přiloží. Automaticky načítá aktivní uvolněné přístupové kódy z `branch_door_codes` a vystavuje je jako `{{door_code_moto}}`, `{{door_code_gear}}`, `{{door_codes_block}}` template vars. **i18n 2026-06-01 (Part 2+3):** odkazy/QR/Web-label v patičce + `{{site_url}}` + `docs_url` fallback vedou na doménu zákazníka (`motogo24.cz` cs / `motogo24.com` non-cs); `localizeBodyLinks` přepíše motogo24.cz URL v těle (e-mail `info@` a asset obrázky se nemění). DB šablona (Velín jen CZ) se pro non-cz dynamicky přeloží přes Anthropic (`resolveTemplateForLang` → claude-haiku) + cache do `email_templates.{subject,body}_translations[lang]` + `__src_<lang>` SHA-1 hash (invalidace při změně CZ). cs = beze změny. Smlouva/VOP přílohy generuje s `language=custLang`. Vyžaduje secret `ANTHROPIC_API_KEY`. **Voucher PDF 2026-06-04:** dárkový poukaz (`voucher_purchased`) se generuje jako **PDF přes PDFShift** (`htmlToPdf` + šablona `renderVoucherPdfHtml` s pozadím `gfx/darkovy-poukaz.jpg`) — stejný externí poskytovatel jako faktury, secret `PDFSHIFT_API_KEY`. Nahradilo pdf-lib, který neuměl embednout progresivní JPEG pozadí a poukaz proto vždy padal do HTML fallbacku (`renderVoucherHtmlFallback` zůstává jako pojistka při selhání/chybějícím klíči). **FIX 2026-06-11 (booking_modified přílohy):** doplatek → do generate-invoice volání (rozdílový DP, source='edit') se posílá `price_difference` z trigger payloadu — bez toho rozdílový DP nikdy nevznikl (modification_history nenese price_diff) a Velín synth příloha `DP` přiložila STARÝ doklad z původní platby (přesně reportovaný bug „290 Kč za boty bez dokladu"). Dedup příloh nově i přes `storage_path` — stejná faktura nepřijde 2× pod různými filename (hardcoded `…-uprava-…` vs synth). Vratka → dobropis attach s retry přes process-refund beze změny (s 2026-06-11 fixem process-refund funguje i druhá a další úprava se slevou). **FIX 2026-06-11 (C) — pravidlo „při úpravě nikdy ZF":** a) rozdílová ZF (advance source='edit') se u doplatku už NEGENERUJE — chodí pouze rozdílový DP (platba šla rovnou bránou, proforma nemá smysl); b) Velín attachments konfigurace šablony booking_modified (`["ZF","DP","Smlouva","VOP"]`) se filtruje kontextově podle směru změny ceny: ZF/KF nikdy, DP jen při doplatku (pd>0), Dobropis jen při vratce (pd<0), Smlouva/VOP vždy — dřív synth typy přiložily POSLEDNÍ existující ZF+DP z původní platby i při vratce, kde má přijít pouze dobropis. CZ fallback text mailu aktualizován (bez zmínky o ZF). |
| `send-recovery-otp` | **OFF** | **NEW 2026-05-09** — Reset hesla mimo Supabase Auth SMTP (vestavěný SMTP má rate-limit 3/h, custom SMTP template může postrádat `{{ .Token }}` placeholder). Vstup: `{email}`. Flow: 1) anti-enumeration lookup `profiles.email` (fallback `auth.admin.listUsers`), 2) `auth.admin.generateLink({type:'recovery', email})` → token uložen v `auth.users.recovery_token`, response obsahuje `properties.email_otp` (8-znak. alfanumerický kód, TTL 1h), 3) Resend mail z `noreply@motogo24.cz` s pretty HTML šablonou (zelený monospace box s kódem, CZ texty), 4) log do `message_log` (template_slug='recovery_otp'). Vrací `{success:true, sent:bool}` — `sent=false` pro neexistující mail (anti-enumeration: stejná HTTP odpověď). Volá se z `motogo-web-php/js/pages-rezervace-auth.js#_submitForgot`, `motogo-web-php/js/pages-upravit-rezervaci.js#_submitForgot` a Flutter `Motogo-app-main/.../auth_provider.dart::resetPassword`. Verifikace na klientu beze změny — `verifyOtp({type:'recovery', email, token})` validuje token v `auth.users`. **verify_jwt=false** v `config.toml` (anon-callable, anti-enumeration v kódu). Závisí na `RESEND_API_KEY` + `FROM_EMAIL` secrets (už existují, používá je `send-email`/`send-booking-email`). |
| `send-broadcast` | OFF | Hromadné zasílání kampaní (email, SMS, WhatsApp). Rate-limited, failure threshold 20% |
| `send-cancellation-email` | OFF | Email o stornování rezervace s "obnovit" CTA. Retry 3×. **UPDATE 2026-05-31:** `wasPaid` nově bere i `payment_status='refund_pending'` (vedle `paid`) — stornovaná zaplacená rezervace ve stavu „Čeká na vrácení" tak dál spustí `process-refund` (Stripe refund + dobropis) a přiloží credit_note do mailu. |
| `send-email` | OFF | Obecné odesílání emailů s podporou šablon (`email_templates` slug, `raw_html`, `raw_body`, `type='invoice'`). **NEW 2026-06-23 — přílohy:** přijímá `attachments` (inline `[{filename, content}]` base64) a `attachment_paths` (`[{filename, path}]` — stáhne soubor z bucketu `documents` přes service_role a zakóduje do base64), předá je Resendu. Použito pro odeslání el. předávacího / škodního protokolu zákazníkovi z Velína (slug `handover_protocol_sent` / `damage_protocol_sent`, protokol v příloze). Selhání přílohy e-mail neshodí. |
| `send-invoice-email` | OFF | Odesílání faktur emailem zákazníkům |
| `send-message` | OFF | Centrální odesílání zpráv (SMS/WhatsApp přes Twilio, email přes Resend) |
| `send-order-email` | OFF | Odesílání objednávkových emailů dodavatelům. Retry 3× |
| `translate-content` | ON | Auto-překlad textů z Velínu pro veřejný web. Volá Anthropic API (`claude-haiku-4-5-20251001`), překládá zadaná pole do 6 jazyků (en, de, es, fr, nl, pl) a UPDATEuje sloupec `translations` v cílové tabulce přes service_role. Striktně zachovává HTML tagy, ICO, čísla, SPZ, ceny. Vstup: `{table, id, fields, target_langs?}`. |
| `translate-document` | ON | **NEW 2026-05-12** — Překlad celých dokumentů (Velín → Dokumenty) do 6 jazyků (en/de/es/fr/nl/pl) přes Anthropic API. Umí: a) `custom_documents` typu `pdf` — PDF se pošle Claude přímo jako document content block (`claude-sonnet-4-6`), výstupem je přeložený obsah jako HTML (cizojazyčná verze webu se zobrazí jako HTML stránka, český originál PDF zůstává); b) `custom_documents` typu `html` (RTE obsah, `claude-haiku-4-5-20251001`); c) `document_templates` (VOP/smlouva/GDPR/protokoly) — překládá `content_html` i `name`, `{placeholder}` proměnné zůstávají nepřeložené. Uložení: `custom_documents` → JSONB `translations` = `{lang:{title,description,content_html}}`; `document_templates` → `content_translations` = `{lang:"<html>"}` (RPC `get_document_translation`, mig. `20260503` §5.6) + `name_translations` = `{lang:"<název>"}` (mig. `20260512_document_templates_name_translations.sql`). Merge per jazyk přes service_role. Vyžaduje JWT (admin z Velínu) nebo service_role klíč. Sekret: `ANTHROPIC_API_KEY`. Limit PDF 20 MB. Vstup: `{table:'custom_documents'|'document_templates', id, target_langs?}`. UI: Velín → Dokumenty → Smluvní texty → tlačítko „🌍 Přeložit" u každého dokumentu i smluvní šablony. |
| `translate-pages-master` | ON | **NEW 2026-05-03 / FIX 2026-05-03 (bundled fallback)** — Auto-překlad celého CS masteru velkých CMS stránek (jak_pujcit_*, home, pujcovna, kontakt, jak_pujcit, poukazy) pro multilingvní web **bez FTP uploadu**. Vyžaduje JWT (admin volá z Velínu). **Zdroj CS masteru — priorita:** 1) `body.master_url` (per-call HTTP), 2) `app_settings.master_url` (per-projekt HTTP přes SQL), 3) `app_settings.pages_master_cs` (JSONB snapshot v DB), 4) **bundled `master_cs.ts`** — JSON snapshot 12 stránek, ~84 KB, regeneruje se z motogo-web-php/data/*.php a lang/pages_cs.php přes `php motogo-web-php/scripts/build_master_json.php` (commitnout výsledek + redeploy edge fn). Live HTTP fetch už NENÍ default — `motogo24.cz` často nemá `pages/master-export.php` deployed (deploy lag) a `motogo24.com` nemá SSL cert pro přímou route. Bundled fallback zaručí, že tlačítko „Přeložit vše naráz" projde bez ohledu na deploy stav PHP. Pro každou kombinaci stránka × cílový jazyk volá Anthropic API (`claude-haiku-4-5-20251001`) na překlad celého JSON stromu (preserves HTML/structure/CSS classes/aria) a upsertne výsledek do `app_settings` pod klíčem `pages_overlay.<page>.<lang>` (JSONB strom). PHP `siteContent()` v `motogo-web-php/supabase.php` čte tento overlay s vyšší prioritou než statické `lang/pages_<lang>.php` — změny jsou živé na všech doménách (.com/.es/.pl/.at) okamžitě. Response obsahuje `source` field (URL nebo `bundled` / `app_settings.pages_master_cs`) pro debugging. Vstup: `{pages?: string[], target_langs?: string[], master_url?: string}`. Sekret: `ANTHROPIC_API_KEY`. UI: Velín CMS → Texty webu → tlačítko „🌍 Přeložit vše do EN/DE/ES/FR/NL/PL". |
| `cms-save` | ON | **Inline ukládání CMS textů přímo z webu motogo24.com** (admin overlay). Anon-callable bez JWT — místo toho ověřuje `cms_admin_token` z `app_settings` (timing-safe equal). Po validaci upsertne do `cms_variables` (key/value, category=`web`) přes service_role (obejde RLS) a fire-and-forget zavolá `translate-content` pro auto-překlad do EN/DE/ES/FR/NL/PL. Vstup: `{token, key, value}`. Whitelist klíčů: musí matchovat `^web\.[a-zA-Z0-9_]+(\.[a-zA-Z0-9_]+)+$` (zamezí přepsání systémových rows). Max value 16 KB. |
| `send-push` | OFF | FCM v1 push notifikace na zákaznická zařízení. Volá se ze SQL přes `send_push_via_edge()` (pouze service_role). Načítá `push_tokens.active=true`, podepisuje JWT pro Google OAuth2, posílá FCM message s Android channel `motogo_notifications` + APNS payload. Auto-deaktivuje invalid tokeny (NOT_FOUND/UNREGISTERED). **FIX 2026-06-06 (auth):** kontrola volajícího už NEpoužívá přesnou shodu `token === SUPABASE_SERVICE_ROLE_KEY`, ale helper `isServiceRole()` — akceptuje buď přesnou shodu s env klíčem (fast-path), NEBO jakýkoli JWT s claim `role: service_role`. Důvod: projekt může mít po rotaci JWT secretu / migraci legacy→new API keys **víc platných service_role klíčů zároveň** — klíč v `app_settings.service_role_key` (ze kterého volá `send_push_via_edge`) byl validní (REST `/rest/v1/` ho přijal s 200), ale jako řetězec se lišil od klíče injektovaného do funkce → přesné porovnání vracelo 401 „Unauthorized — service_role only" a push se zahazoval. Stejnou křehkou přesnou shodou trpí i `send-message` (SMS/WA) — viz changelog. **FIX 2026-06-07 (consent gate):** funkce nově načte `profiles.consent_push` a pokud je `false`, vrátí `{success:true, sent:0, reason:'Push consent disabled'}` bez odeslání — souhlas s push v appce (Profil → Notifikace) i ve Velínu (detail zákazníka) tak push reálně zapne/vypne (dřív se sloupec jen ukládal a zobrazoval, ale doručení neovlivnil). Během aktivní/nadcházející zaplacené rezervace appka `consent_push` zamkne na `true`, takže nezbytné pushe (door codes) chodí dál. |
| `webhook-receiver` | OFF | Příjem Stripe webhooků (**LIVE mode**, signature povinná). Auto-generuje dokumenty po platbě. Synchronizuje karty do payment_methods. **Shop platby:** auto-generuje DP + odesílá voucher_purchased email s kódy poukazů. **Bundled booking + shop (od 2026-04-28):** když `event.metadata.type='booking'` a obsahuje `metadata.shop_order_id`, zavolá vedle `confirmBookingPayment` ještě `confirmShopPayment` → trigger `generate_shop_invoice` vystaví shop_final fakturu, odešle voucher/order email. Výsledek: jedna Stripe session, dvě faktury, dva emaily. **FIX 2026-06-01 (doplatková změna rezervace):** v obou větvích (`checkout.session.completed` i `payment_intent.succeeded`) po `confirmBookingPayment` pro `paymentType==='extension'` volá nový helper `applyExtensionChange(supabase, bookingId, metadata.chg)` — naparsuje payload změny z `metadata.chg` a aplikuje `bookings.update` (start/end/moto/pickup+return method/address/lat/lng/fee/time, navíc **absolutní `total_price` z `new_total`** — klient ho dřív vůbec nenastavoval). Update spustí `trg_send_booking_modified_email` (source=`web` → `web_booking_modified`). Idempotentní (absolutní hodnoty + 5min dedup mailu v triggeru), takže druhý Stripe event ani souběžný klientský `_applyPendingAfterPayment` nezpůsobí duplicitu. Loguje `extension_change_applied`/`_failed` do `debug_log`. Řeší dosud otevřený bug PW 50 (2026-05-19): zaplacené prodloužení web rezervace se neuložilo a mail nedorazil, když zákazník zaplatil na jiném zařízení (změna se aplikovala jen klientsky z localStorage). **Gear větev:** když `metadata.chg` obsahuje `{_gear:{sizes}}` (placená změna výbavy), helper místo `bookings.update` volá RPC `apply_paid_gear_change(p_booking_id, p_sizes)` (service-role wrapper impersonující vlastníka → existující `update_booking_gear`, idempotentní). Změna `total_price` opět spustí `web_booking_modified`. Když RPC ještě není nasazená, chyba se zaloguje (`gear_change_apply_failed`) a gear padá zpět na klientský apply (žádná regrese). **UPDATE 2026-06-11 (`applyExtensionChange`):** a) přijímá i **app formát** `metadata.chg` — Flutter `payment_screen.dart` nově posílá kompaktní `change` s DB názvy sloupců (start_date/end_date/moto_id/pickup_*/return_*/total_price) → doplatková změna z appky se aplikuje server-side i když je appka po platbě zabita (stejná záchranná síť, jakou web dostal 2026-06-01; klientský apply v appce zůstává — obě cesty idempotentní); b) při změně termínu zapisuje **`modification_history`** záznam (`{at, from/to dates, source:'stripe_webhook'}`, + `original_*` při prvním zásahu) s guardem proti duplicitě (druhý Stripe event vidí from==to) — rozdílový doklad tak má čerstvý podklad pro denní rozpis a Velín vidí úpravu v historii. |
| `public-api` | OFF | **Veřejné REST API** pro AI agenty / partnery / integrátory. Tenká vrstva nad RPC. 9 endpointů (motorcycles list+detail+availability, branches, extras, quote, bookings, promo/voucher validate) + GET /api/v1/openapi.json (OpenAPI 3.1 spec). Hybrid auth: bez klíče = rate-limit per IP (60/min read, 30/h create_booking), s X-Api-Key header = per-partner rate_limit_rpm z `api_keys`. Loguje do `ai_traffic_log` (source='rest_api'). |
| `mcp-server` | OFF | **Model Context Protocol server** (HTTP + JSON-RPC 2.0) pro Claude Desktop, Cursor, Cline, Smithery, custom agenty. 9 tools (motogo_search_motorcycles, motogo_get_motorcycle, motogo_get_availability, motogo_quote, motogo_create_booking, motogo_get_branches, motogo_get_faq, motogo_validate_promo, motogo_validate_voucher) + 5 resources (about, motorcycles, branches, faq, policies). Methods: initialize, tools/list, tools/call, resources/list, resources/read, ping. GET / vrací discovery JSON. Optional X-Api-Key auth. Loguje do `ai_traffic_log` (source='mcp'). |
| `ai-customer-messages-suggest` | OFF | **NEW 2026-05-05** — AI návrh odpovědi na příchozí zákaznickou zprávu (SMS/email/WhatsApp/app chat). POST `{message_id}`. Načte `app_settings.ai_customer_messages_config` (persona, system_prompt, situations, mustDo, forbidden, tone, max_tokens, enabled, channels, mode, knowledge_extra) + kontext zákazníka (profile, nejbližší booking, posledních 10 zpráv ve vlákně). Anthropic Claude Haiku 4.5 vrací JSON `{reply, confidence: low/medium/high, admin_note}`, edge fn ukládá do `messages.ai_suggested_reply` + `ai_suggestion_status` (pending v `suggest_only` módu, auto_sent v `auto_send` módu po úspěšném volání `send-message`). Per-channel limity (SMS 320, WA 600, email 1500, app_chat 400 znaků), per-channel toggle v `channels`, per-channel se kontroluje `cfg.channels[channel] !== false` před voláním. **Timeout safety:** synchronní HTTP odpověď ihned (~ms) s `{ok, message_id, status:'queued'}`, vlastní inference v `EdgeRuntime.waitUntil()` — frontend sleduje `messages` přes Realtime / polling. **Selhání (LLM error / parse error / send-message failure):** `ai_suggestion_status='failed'` + `ai_error` text, audit do `ai_traffic_log` (source='customer_messages', outcome=suggested/auto_sent/disabled/channel_off/skip_outbound/already_processed/not_found/error). Zpracovává jen `direction='inbound'` zprávy. Idempotentní (skip pokud už má status). |
| `ai-public-agent` | OFF | **AI booking widget backend** (anonymní, bez JWT). Anthropic Claude Haiku 4.5 + **11 tools**: `search_motorcycles`, `get_availability`, `calculate_price` (vrací error když chybí ceník dne, výslovně označuje že NEzahrnuje extras+dopravu), `get_faq` (čistě CMS, žádný hardcoded fallback), **`get_policies`** (čte `app_settings.site.policies`, agent musí přiznat neznalost když prázdné), **`get_legal_document`** (NEW 2026-06-06 — vrací PŘESNÉ znění smluvních/právních dokumentů ze šablon a webu: `document_templates` typu vop/rental_contract/handover_protocol/gdpr + `custom_documents` show_on_web; service_role čtení, per-lang překlad z content_translations/translations, HTML→plaintext, bez param=seznam, s `document`=plné znění, s `query`=relevantní úryvky; agent z toho VÝHRADNĚ cituje, řeší dřívější odbývání zákazníka „najdeš ve smlouvě" u dotazů na vyčíslení škody/spoluúčast/GDPR), `get_extras_catalog`, `get_branches`, `validate_promo_or_voucher`, **`create_booking_request`**, `redirect_to_booking`. **Anti-halucinace policies:** firemní fakta (adresa, telefon, email) se načítají z `app_settings.company_info` dynamicky, statický COMPANY_BRAIN obsahuje jen identitu firmy + obecné zákonné limity ŘP + technický popis flow. Storno, kauce, ceny přistavení, foreign-travel, věkové limity půjčovny — výhradně přes `get_policies`/`get_faq` z CMS. **Anti-halucinace slev (2026-05-02):** model NIKDY nevymýšlí slevy / „obvyklé" rabaty / „možná by ti něco vykombinovali" — slevu smí zmínit jen když ji vrátil tool. **Anti-halucinace cen (2026-05-02):** model NIKDY neuvádí „od X Kč/den" — fleet snapshot už cenu od neobsahuje, místo ní text „ceník dle dne v týdnu, použij calculate_price". Model nikdy nevymýšlí ceny ani datum — system prompt obsahuje hlavičku "DNES JE …" v Europe/Prague. **Jazykově adaptivní**: model detekuje jazyk poslední user zprávy a odpovídá vždy ve stejném (přepínání mid-konverzace OK). UI lang z prohlížeče je jen hint pro 1. zprávu. **Konfigurovatelný z Velínu** přes `app_settings.ai_public_agent_config` (persona_name, system_prompt, situations, mustDo, forbidden, tone, max_tokens, enabled, welcome_cs/en/de). `create_booking_request` přijímá kompletní data: moto_id, datumy, kontakt (jméno/email/telefon/adresa), ŘP skupina, promo kód, pickup/return time, delivery_address/return_address pro přistavení mimo Mezná, extras (jako pole {name, unit_price}), všechny gear sizes řidič+spolujezdec. **Po vytvoření booking (2026-05-02 změna):** vrací `payment_url = https://motogo24.cz/rezervace?resume=<booking_id>` — vede zákazníka do existujícího rezervačního flow, kde nejdřív proběhne **Mindee skener OP/ŘP**, teprve potom Stripe Checkout (doklady musí být PŘED platbou, jinak systém nevydá přístupové kódy k motorce). Edge fn už nevolá `process-payment` přímo — tu si vyvolá rezervační stránka po skenu dokladů. **Persistence konverzací (2026-05-02):** přijímá `session_id` (UUID stabilní per browser session ze widgetu), upsertuje konverzaci do `ai_public_conversations` po každé Anthropic odpovědi (messages, page_context, outcome, booking_id). Rate-limit 20 req/min/IP. Loguje do `ai_traffic_log` (source='widget', outcome=`view`/`quote`/`booking_created`). **NEW 2026-06-06 — `get_motorcycle_manual(moto_id, query?)`:** agent umí otevřít a přečíst NÁVOD konkrétní motorky a odpovědět z něj na technické „super-detaily" (tlak v pneu, druh/množství oleje, servisní intervaly, kontrolky, startování, pojistky, momenty). Zdroj: `motorcycles.manual_url` (nahrané PDF v public bucketu `media`, přednost) nebo `manual_external_url` (externí odkaz výrobce). PDF → text přes `unpdf` (dynamický import `https://esm.sh/unpdf@0.12.1`, serverless pdf.js, `extractText(mergePages:true)`); web → HTML→plaintext; při `query` vrací jen relevantní úryvky (±400 zn. okna, MAX 14000 zn.), jinak zkrácený plný text. Když návod chybí / fetch selže / skenované PDF bez textu → vrací `found:false`/`fetch_failed`/notice + přímý odkaz, agent NESMÍ technický údaj domyslet. `search_motorcycles` nově vrací `has_manual` flag (select obsahuje `manual_url`,`manual_external_url`). System prompt pravidlo 26: **specs z dat jsou NADŘAZENÉ** (kW/ccm/hmotnost/výška sedla/ABS/ŘP), návod doplňuje jen detaily, které ve specs nejsou. **Současně 2026-06-06 fixy chování (analýza reálné konverzace):** (1) helper `motoDisplayName()` dedupuje značku v názvu (DB `model` u některých kusů už značku obsahuje → dřív „Benelli Benelli TRK 502 X"); (2) pravidlo 25 — agent NIKDY nenabídne stroj nad zákazníkův kW/ŘP limit (ani „o kousek", 36 kW při A2 limitu 35 kW = mimo nabídku), dětské motorky se nenabízejí dospělému jako náhrada „nižšího výkonu"; (3) pravidlo 23 rozšířeno o správnou negaci („nemáme nic", ne „máme nic") a zákaz vymýšlení neexistujících slov (komolenina „chopperudel"). |
| `generate-report` | OFF | **ZDROJ DOPLNĚN DO REPA 2026-06-18 ze snapshotu** (dříve jen v dashboardu). Generování finančních a provozních reportů — voláno z Velín Statistics. `POST /functions/v1/generate-report`, auth Bearer JWT (admin, min. manager). Body `{type, period_from, period_to, branch_id?, format?}`. Čte `accounting_entries` (income/expense) za období + větev, vrací summary + details + generated_at. Sdílí `_shared/cors.ts` + `_shared/supabase-client.ts`. |
| `generate-tax` | OFF | **ZDROJ DOPLNĚN DO REPA 2026-06-18 ze snapshotu** (dříve jen v dashboardu). Generování daňových přiznání a podkladů pro Finanční správu ČR — voláno z Velín TaxTab. Podporuje DPH měsíční/čtvrtletní, DPPO roční, kontrolní hlášení. `POST /functions/v1/generate-tax`, auth Bearer JWT (admin/superadmin). Body `{type, period_from, period_to}`. Počítá DPH základ/daň (21/15/10 %) z příjmů a odpočet z výdajů. Sdílí `_shared/cors.ts` + `_shared/supabase-client.ts`. |

### Pouze v Supabase dashboardu (3 — bez kódu v repo)

| Funkce | Popis |
|--------|-------|
| `cron-daily` | Denní cron úlohy (snapshot_daily_stats, auto_schedule_services) |
| `cron-monthly` | Měsíční cron úlohy (generate-tax, monthly reports) |
| `export-data` | Export dat (CSV/XLSX) — voláno z Velín Finance + TaxTab |

> **2026-06-18:** `generate-report` a `generate-tax` byly dříve vedené jako „pouze v dashboardu (bez kódu v repo)". Snapshot 2026-06-18 jejich nasazený zdroj stáhl a byl **doplněn do repa** (`supabase/functions/generate-report/index.ts`, `supabase/functions/generate-tax/index.ts` + sdílené `_shared/cors.ts`, `_shared/supabase-client.ts`) → nyní jsou v repozitáři (viz tabulka výše). Auto-deploy `deploy-functions.yml` je tak udrží v sync.
>
> **POZN. k inventáři edge funkcí:** snapshot workflow stahuje pouze pevný seznam funkcí (`snapshot-supabase.yml`), který momentálně neobsahuje `cms-admin-auth` a `render-pdf` — kompletní živý seznam edge funkcí tedy z tohoto snapshotu nelze 100% odvodit (DB schéma/funkce/triggery/RLS jsou ale z full pg dumpu kompletní). Počty „28/32" výše jsou orientační a historicky neaktuální.

### SMAZANÉ duplicity/nepoužívané (cleanup 2026-03-24)

| Funkce | Důvod smazání |
|--------|---------------|
| `document-generator` | Duplikát generate-document |
| `generate_document` | Duplikát generate-document (starší verze) |
| `generate-html-document` | Duplikát generate-document (nejstarší, fiktivní IČO) |
| `redeploy` | Duplikát generate-invoice |
| `redeploy-invoice` | Duplikát generate-invoice (starší) |
| `bright-endpoint` | Nepoužívané — Bright Data endpoint |
| `cms-sync` | Nepoužívané — žádné CMS v projektu |
| `prediction-engine` | Nepoužívané — nerealizovaná funkce |
| `send-sos` | Nepoužívané — nahrazeno DB triggerem sos_notify_user_on_create() + send-message |
| `upload-handler` | Nepoužívané — upload jde přímo přes Supabase Storage SDK |
| `inventory-check` | Nepoužívané — nahrazeno auto-check-service-parts |

---

## 9. STORAGE BUCKETY

| Bucket | Přístup | Použití |
|--------|---------|---------|
| `documents` | **private** | Faktury (invoices/{id}.html), generované dokumenty (generated/{uuid}.html), smlouvy, naskenované doklady zákazníků (`<user_id>/<doc>_<ts>.<ext>`) |
| `media` | **public** | Fotky motorek, loga, marketingové materiály |
| `sos-photos` | **private** | Fotky z SOS incidentů (poškození, nehody) |

### RLS politiky `storage.objects` pro bucket `documents` (2026-05-05)
Před opravou byl pro authenticated zákazníka přístup do bucketu zamaskován jako 404 „Bucket not found" (chyběla SELECT politika); v Supabase Storage se 403 vrací jako 404, aby se neleakly názvy bucketů. Velín admin fungoval díky `is_admin()` bypassu.

| Politika | Cíl | Použití |
|----------|-----|---------|
| `documents_customer_select_own` | authenticated SELECT | Zákazník vidí pouze: a) vlastní složku `<user_id>/...` (nahrané skeny OP/ŘP přes `save-verification-document`), b) `pdf_path` v `invoices` u svých rezervací (přes `bookings.user_id`), c) `pdf_path` v `generated_documents` u svých rezervací, d) `file_path` v `public.documents` se shodným `user_id`. |
| `documents_admin_all` | authenticated ALL | Admin (`is_admin()`) má plný přístup pro správu z Velínu. |

Důsledek: tlačítko „Stáhnout" v `motogo24.cz/upravit-rezervaci?` (Doklady tab) i Mindee scan flow nyní fungují bez 404. Edge fn `save-verification-document` dál běží pod service_role a na RLS nezávisí.

---

## 10. SECRETS (16+)

| Secret | Kde se používá |
|--------|---------------|
| `SUPABASE_URL` | Všechny edge funkce |
| `SUPABASE_SERVICE_ROLE_KEY` | Všechny edge funkce |
| `SUPABASE_ANON_KEY` | admin-reset-password, ai-copilot, ai-moto-agent, webhook-receiver (doc gen) |
| `SUPABASE_DB_URL` | Přímý DB přístup z edge funkcí |
| `ANTHROPIC_API_KEY` | ai-copilot, ai-moto-agent (Anthropic Claude API) |
| `MINDEE_API_KEY` | scan-document (OCR) — Mindee v2 API key |
| `MINDEE_MODEL_ID` | scan-document — Mindee v2 model ID pro National ID / OP (`2e169fdb...`) |
| `MINDEE_MODEL_DRIVERS_LICENSE` | scan-document — Mindee v2 model ID pro Driver's Licence / ŘP (`c9797f99...`) |
| `MINDEE_MODEL_PASSPORT` | scan-document — Mindee v2 model ID pro Passport / pas |
| `STRIPE_SECRET_KEY` | process-payment, webhook-receiver, manage-payment-methods (**LIVE sk_live_...**) |
| `STRIPE_WEBHOOK_SECRET` | webhook-receiver (**POVINNÉ** — ověření Stripe signature, whsec_...) |
| `ADMIN_EMAIL` | SOS notifikace, cron alerty |
| `ADMIN_PHONE` | SOS SMS notifikace |
| `TWILIO_ACCOUNT_SID` | send-message (Twilio SMS/WhatsApp) |
| `TWILIO_API_KEY_SID` | send-message (Twilio API Key) |
| `TWILIO_API_KEY_SECRET` | send-message (Twilio API Key Secret) |
| `TWILIO_PHONE_NUMBER` | send-message (Twilio odesílací číslo) |
| `TWILIO_WHATSAPP_NUMBER` | send-message (Twilio WhatsApp číslo) |
| `INVOICE_API_KEY` | fakturace |
| `PDFSHIFT_API_KEY` | **NEW 2026-05-08** — generate-invoice, generate-document, **send-booking-email (dárkový poukaz PDF, 2026-06-04)**. HTML→PDF konverze pro všechny doklady směrem k zákazníkovi (FV/KF/ZF/DP/dobropis e-shop+booking, smlouvy, VOP, předávací protokoly). Free tier 250 konverzí/měsíc na pdfshift.io. Bez tohoto klíče funkce fallbackují na HTML upload (nic nepadá, jen přílohy chodí v HTML). Edge fn `send-booking-email` / `send-invoice-email` detekují příponu uloženého souboru a podle ní nastaví attachment filename. |
| `FCM_PROJECT_ID` | send-push (Firebase project ID) |
| `FCM_SERVICE_ACCOUNT_JSON` | send-push (Firebase service account JSON — přijímá **raw JSON i base64**; funkce detekuje formát podle úvodního `{`) |

**App settings (DB) pro pg_net push:**
| Klíč | Účel |
|------|------|
| `app.settings.supabase_url` | URL pro `send_push_via_edge()` SQL helper (GUC, na Supabase managed nepřístupný k zápisu) |
| `app.settings.service_role_key` | Service role key pro autorizaci `send-push` z DB triggerů (GUC) |
| `app_settings(key='supabase_url')` | URL pro `send_abandoned_booking_emails()` — uloženo jako jsonb string v public tabulce, čte se přes `value #>> '{}'`. Použito místo GUC, protože `ALTER DATABASE` vyhazuje na Supabase managed `permission denied`. |
| `app_settings(key='service_role_key')` | Service role JWT pro autorizaci pg_net.http_post z `send_abandoned_booking_emails()`. |

**Frontend config (ne secret):**
| Klíč | Hodnota |
|------|---------|
| `STRIPE_PUBLISHABLE_KEY` | `pk_live_51TBLTTRzZyj...` (v index.html MOTOGO_CONFIG) |

---

## 11. SEED DATA (app_settings)

```json
{
  "company_info": {
    "name": "Bc. Petra Semorádová",
    "ico": "21874263",
    "dic": null,
    "vat_payer": false,
    "address": "Mezná 9, 393 01 Mezná",
    "bank_account": "670100-2225851630/6210",
    "phone": "+420 774 256 271",
    "email": "info@motogo24.cz",
    "web": "https://motogo24.cz"
  }
}
```

### header_banner (app_settings key)
```json
{
  "enabled": true,
  "text": "Letní akce -20% na všechny motorky!",
  "bg": "#1a2e22",
  "color": "#74FB71"
}
```

### google_review_url (app_settings key)
```
https://search.google.com/local/writereview?placeid=PLACE_ID
```

### site.policies (app_settings key) — NOVÉ
Strukturované oficiální podmínky půjčovny pro AI public agent (`get_policies` tool) i budoucí zobrazení v CMS. Když je klíč prázdný, agent přizná neznalost místo halucinace. Příklad struktury (admin si plní z Velínu):
```json
{
  "deposit": "Půjčujeme bez kauce — žádná blokace na kartě.",
  "cancellation": {
    "free_until_days": 7,
    "partial_refund_percent_2_to_7_days": 50,
    "less_than_2_days": "Individuálně po dohodě (volá zákazník)."
  },
  "included": ["Helma, bunda, kalhoty a rukavice řidiče", "Povinné ručení / zelená karta", "Neomezené km v ČR a EU"],
  "addons_extra_charge": ["Výbava spolujezdce", "Boty pro řidiče", "Sjezd mimo EU"],
  "delivery_pricing": "Orientačně 1000 Kč + 40 Kč/km, přesný výpočet probíhá v rezervačním formuláři.",
  "foreign_travel": "EU + Schengen v ceně, mimo EU po dohodě a s doplňkovým pojištěním.",
  "fuel": "Vracíš jak chceš (i prázdné). Dotankování za nákupní cenu.",
  "documents_required": ["Občanský průkaz nebo cestovní pas", "Platný řidičský průkaz odpovídající skupiny"],
  "rental_age_min": { "A1": 16, "A2": 18, "A": 24, "B_for_A1": 21 }
}
```

---

## 12. SEKVENCE

- `shop_order_seq` — formát: OBJ-YYYY-NNNNN (start 1001)

---

## 13. CRON JOBS (pg_cron)

| Job | Čas | Funkce |
|-----|-----|--------|
| `auto-cancel-pending-bookings` (1) | každé 2 min (`*/2 * * * *`) | `SELECT auto_cancel_expired_pending()` — ruší pending+unpaid bookings: app=10min, web=4h |
| `send-abandoned-booking-emails` (12) | každé 2 min (`*/2 * * * *`) | `SELECT send_abandoned_booking_emails()` — pošle „nedokončená rezervace" mail web bookingu po 20 min od kroku 1, resp. 10 min od kliknutí „Pokračovat k platbě" (Stripe session). Dedup přes `bookings.abandoned_email_sent_at`. |
| `send-missing-booking-reserved-emails` | každé 2 min (`*/2 * * * *`) | **NEW 2026-06-17 (`20260617_catchup_booking_reserved_email.sql`):** `SELECT send_missing_booking_reserved_emails()` — záchranný cron, došle `booking_reserved` mail web rezervacím reserved/active+paid, kterým v `message_log` chybí `web_booking_reserved`/`booking_reserved` (webhook ho v časově omezené cestě „utnul" při generaci 4 PDF příloh). 3 min grace od `confirmed_at`. Dedup: `message_log` NOT EXISTS + marker `bookings.reserved_email_sent_at`. Vrací `{sent_reserved}`. |
| `auto-complete-expired-bookings` (4) | denně 00:01 (`1 0 * * *`) | `SELECT auto_complete_expired_bookings()` — active/reserved + end_date < today + paid → completed |
| `expire-vouchers` (8) | denně 01:00 UTC (`0 1 * * *`) | `SELECT expire_vouchers()` |
| `cron-daily` (9) | denně 02:00 UTC (`0 2 * * *`) | `SELECT snapshot_daily_stats(); SELECT auto_schedule_services();` |
| `auto-check-service-parts` (10) | denně 06:00 UTC (`0 6 * * *`) | `SELECT auto_check_service_parts()` — kontrola dílů, auto PO + email dodavateli |
| `auto-activate-reserved` (11) | denně 00:01 (`1 0 * * *`) | `SELECT auto_activate_reserved_bookings()` — reserved + paid + start_date <= today → active |

---

## 14. FOREIGN KEYS (klíčové vazby)

- `bookings.user_id` → `profiles.id`
- `bookings.moto_id` → `motorcycles.id`
- `bookings.trailer_moto_id` → `motorcycles.id` (**ON DELETE SET NULL**, NEW 2026-06-16 — vozík jako gear add-on, `20260616_trailer_addon.sql`). **POZOR — DRUHÝ FK na `motorcycles`:** od této migrace má `bookings` dvě vazby na `motorcycles` (`moto_id` + `trailer_moto_id`), takže PostgREST embed `motorcycles(...)` je **nejednoznačný** a padá `Could not embed because more than one relationship was found`. Všechny dotazy s kořenem v `bookings` musí embed **disambiguovat hintem na FK**: `motorcycles!moto_id(...)`. Opraveno ve Velíně (24 dotazů ve 23 souborech, commit 576a82e). Web (`motogo-web-php`) ani Flutter app ambiguózní embed nepoužívají.
- `bookings.promo_code_id` → `promo_codes.id`
- `bookings.voucher_id` → `vouchers.id`
- `bookings.replacement_for_booking_id` → `bookings.id`
- `bookings.sos_incident_id` → `sos_incidents.id`
- `booking_extras.booking_id` → `bookings.id`
- `booking_extras.extra_id` → `extras_catalog.id`
- `sos_incidents.user_id` → `profiles.id`
- `sos_incidents.booking_id` → `bookings.id`
- `sos_incidents.moto_id` → `motorcycles.id`
- `sos_incidents.original_booking_id` → `bookings.id`
- `sos_incidents.replacement_booking_id` → `bookings.id`
- `invoices.customer_id` → `profiles.id`
- `invoices.booking_id` → `bookings.id`
- `invoices.order_id` → `shop_orders.id`
- `vouchers.order_id` → `shop_orders.id`
- `shop_orders.customer_id` → `profiles.id`
- `booking_complaints.customer_id` → `profiles.id` (**ON DELETE SET NULL** — změněno 2026-05-27 z `NO ACTION`, jinak zákazník s reklamací nešel smazat a `delete_customer_account` padala na FK)
- `shop_order_items.order_id` → `shop_orders.id`
- `motorcycles.branch_id` → `branches.id`
- `moto_day_prices.moto_id` → `motorcycles.id`
- `message_threads.customer_id` → `profiles.id`
- `messages.thread_id` → `message_threads.id`
- `promo_code_usage.promo_code_id` → `promo_codes.id`
- `promo_code_usage.user_id` → `profiles.id`
- `maintenance_log.moto_id` → `motorcycles.id`
- `service_parts.schedule_id` → `maintenance_schedules.id` (ON DELETE CASCADE)
- `service_parts.inventory_item_id` → `inventory.id` (ON DELETE CASCADE)
- `service_orders.moto_id` → `motorcycles.id`
- `branch_accessories.branch_id` → `branches.id`
- `payment_methods.user_id` → `auth.users.id` (ON DELETE CASCADE) — *(oprava dokumentace 2026-05-29: míří na `auth.users`, ne `profiles`; ověřeno FK auditem)*
- `branch_door_codes.branch_id` → `branches.id`
- `branch_door_codes.booking_id` → `bookings.id`
- `branch_door_codes.moto_id` → `motorcycles.id`
- `invoices.matched_delivery_note_id` → `delivery_notes.id` (ON DELETE SET NULL)
- `invoices.original_invoice_id` → `invoices.id` (ON DELETE SET NULL)
- `delivery_notes.matched_invoice_id` → `invoices.id` (ON DELETE SET NULL)
- `delivery_notes.financial_event_id` → `financial_events.id` (ON DELETE SET NULL)
- `contracts.financial_event_id` → `financial_events.id` (ON DELETE SET NULL)
- `contracts.employee_id` → `acc_employees.id` (ON DELETE SET NULL)

### FK na `auth.users` — opraveno 2026-05-29 (FK audit)
Tyto 4 byly `ON DELETE NO ACTION` a blokovaly smazání auth účtu (admina/zákazníka), pokud měl řádek v dané tabulce. Změněno na **ON DELETE SET NULL** (nullable audit sloupce „kdo to udělal" — záznam zůstane, aktér se odpojí):
- `ai_actions.admin_id` → `auth.users.id` (**ON DELETE SET NULL** — dříve NO ACTION)
- `ai_citations.recorded_by` → `auth.users.id` (**ON DELETE SET NULL** — dříve NO ACTION)
- `api_keys.created_by` → `auth.users.id` (**ON DELETE SET NULL** — dříve NO ACTION)
- `booking_complaints.resolved_by` → `auth.users.id` (**ON DELETE SET NULL** — dříve NO ACTION)

> **Audit 2026-05-29:** Všechny FK mířící na `profiles` jsou již `CASCADE` nebo `SET NULL` (žádný `NO ACTION`/`RESTRICT`) → smazání zákazníka (`delete_customer_account`) na FK nepadá. FK na `auth.users` spravované Supabase Auth (`identities`, `sessions`, `mfa_factors`, `one_time_tokens`, `webauthn_*`, `oauth_*`, `admin_users.id`, `profiles.id`, `ai_customer_conversations.user_id`) jsou `CASCADE`.
