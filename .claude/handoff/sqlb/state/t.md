# STATE patch – skupina t (texty majitele, `20261112t01`–`20261112t32`)

Bez změn schématu (žádná tabulka, sloupec, trigger, politika, index, cron, edge funkce). Mění se jen data (`cms_variables`, `faq_items`, `app_settings`, `cms_pages`, `email_templates`) a text v těle jedné funkce.

## SUPABASE_BACKEND_STATE_1.md (tabulky)
Beze změny.

## SUPABASE_BACKEND_STATE_2.md (klíčové sloupce)
Beze změny. (Pro úplnost: `app_settings.header_banner` dostane klíče `translations` {en,de,es,fr,nl,pl,uk} + `translations_src` = SHA-1 hex českého `text` – stejný tvar, jaký už zapisuje Velín → Banner a čte web `layout-banner.php` i appka `banner_provider.dart`; nový sloupec to není.)

## SUPABASE_BACKEND_STATE_3.md (RPC funkce)
Do řádku tabulky `_door_codes_msg_lines(...) / _door_codes_msg_valid(...) / _gate_procedure_msg(...) / ...` (NEW 2026-10-04) připsat na konec buňky:

> **UPDATE 2026-11-12 (`20261112t31_owner_texts_gate_procedure.sql`, APLIKUJE AUTO-DEPLOY po merge):** `_gate_procedure_msg` – k bodu „DŮLEŽITÉ … Stejně postupujte i při vrácení motorky.“ přidána věta „Motorku vracejte umytou a tak, aby nesvítila kontrolka rezervy (tankovat do plna nemusíte).“ (pravidlo majitele 2026-10-11; shodné s e-mailem `branch-gate-texts-a.ts` `stepImportant`, appkou `procStepImportant` a webem). Nahrazuje se JEN když má živé tělo otisk verze 20261004 (`md5(prosrc)` 7bbb079d…), jinak NOTICE a beze změny. Signatura, IMMUTABLE, vlastník i ACL (`postgres`, `service_role`) beze změny. Výbavy bez motorky se netýká (ta má `_gear_procedure_msg`).

## SUPABASE_BACKEND_STATE_4.md (triggery)
Beze změny.

## SUPABASE_BACKEND_STATE_5.md (RLS, realtime, edge, storage, secrets, cron, FK)
Beze změny.

## SUPABASE_BACKEND_STATE_6.md (changelog) – nový řádek nahoru do tabulky

| 2026-11-12 (texty majitele – pravidlo vrácení, obě pobočky, appka i v App Store; **SQL 32 datových souborů `20261112t01_owner_texts_cms_return_1.sql` … `20261112t32_owner_texts_email_templates.sql`, APLIKUJE AUTO-DEPLOY po merge v bytovém pořadí; ověřeno na lokálním PG16 se živým schématem (snapshot e5d5b0f7) a živými daty staženými 2026-11-12 anon klíčem: 2× bez chyby, 2. běh nic nemění, 504 úprav textů + banner + 1 funkce, 0 přeskočeno; prázdné tabulky, rozbité tvary JSON a 11 simulovaných úprav ve Velínu bez chyby a bez přepsání**) | **Pravidlo majitele 2026-10-11 (doslova): „Mytí ani tankování není třeba na obslužné pobočce. Na samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila rezerva.“; 2026-10-12: stav paliva neřešíme, plnou nádrž nikdy neslibovat, žádný poplatek za palivo.** Jen data (compare-and-set: text se změní, jen když má v DB přesně znění ověřené 2026-10-15 – otisk md5 nebo věta; co mezitím někdo upravil ve Velínu, se přeskočí s NOTICE; překlad se mění jen když čeština má nové znění). `cms_variables` (Jak si půjčit: Palivo & čištění, krok 12 Vrácení, Vrácení v půjčovně, převzetí na obou pobočkách, úvodní stránka krok 3 + Kontakty, FAQ /pujcovna; web.layout úprava rezervace/potvrzení/patička/samoobsluha; `web.pobocky.*` postup obou poboček + překlady pro appku 7 jazyků), `faq_items` (palivo/mytí, vrácení jinde, osobní převzetí vs. samoobsluha, doklady „OP a ŘP“ v překladech, appka na Google Play i v App Store, chybějící uk), `app_settings` (`pages_overlay.*` en–pl stránek Dokumenty, Vrácení v půjčovně/jinde, Postup, Přistavení, Vyzvednutí, úvod, /pujcovna = `lang/pages_<jazyk>.php`; `ai_public_agent_config.system_prompt` kroky 4–5; `site.policies.fuel`; `header_banner` překlady 7 jazyků + `translations_src`), `cms_pages` (blog „Aplikace MotoGo24…“ – iPhone verze je v App Store, „100% smluvní krytí“ oba obchody), `email_templates` (starý odstavec o vrácení vč. neexistujícího „poplatku za dotankování“ → text z `i18n.ts`, potvrzení rezervace + řádek Google Play/App Store; změněné šabloně vynulována cache `body_translations`; šablony nejsou čitelné anon klíčem → co se změnilo a co zkontrolovat ve Velínu, vypíše log deploye) a text v těle `_gate_procedure_msg` (viz STATE_3). FAQ 77557a0b („tankvak“ v fr/uk): česká odpověď se mezitím změnila jen migrací `20261023f_faq_gear_rental.sql` – brána přijímá oba ověřené otisky. Záměrně NEMĚNÍ závazné dokumenty (VOP čl. 5 l, nájemní smlouva) ani otevřené otázky majitele (VN výbava helmy S–3XL, ceny přistavení FAQ vs. AI, formát dat v banneru). |
