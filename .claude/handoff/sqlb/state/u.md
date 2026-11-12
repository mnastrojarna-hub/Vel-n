# STATE patch — skupina u (QA opravy textů a překladů, `20261112u01`–`u14`)

Jen data (UPDATE existujících řádků v `cms_variables`, `faq_items`, `cms_pages`, `motorcycles`, `app_settings`,
`document_templates`, `custom_documents`, `products`). Žádná nová tabulka, sloupec, funkce, trigger, politika ani cron.

## SUPABASE_BACKEND_STATE_1.md
Beze změny.

## SUPABASE_BACKEND_STATE_2.md
Beze změny schématu. (Volitelně k `cms_pages.slug`: „blog `5ec9affa-…` od 2026-11-12 `proc-je-motogo24-nejlepsi-motopujcovna-v-cr` (dřív `p`; web přesměruje `/blog/p` 301 přes `$legacySlugs`)“.)

## SUPABASE_BACKEND_STATE_3.md
Beze změny.

## SUPABASE_BACKEND_STATE_4.md
K řádku `trg_sync_cms_flat_to_nested` připsat na konec popisu:
„**POZOR (2026-11-12):** jakýkoli UPDATE plochého klíče (i jen `translations`) přepíše vnořený klíč (např. `web.pujcovna.intro.body`, `web.pujcovna.benefits.closing`) českou hodnotou plochého klíče → vrátí novější texty z Velínu. Datové migrace ploché klíče vynechávají (`20261112u02` — seznam `c_sync_keys`).“

## SUPABASE_BACKEND_STATE_5.md
Beze změny.

## SUPABASE_BACKEND_STATE_6.md — nový řádek changelogu (nahoru)
| 2026-11-12 (QA opravy textů a překladů z QA brány 2026-10-16; **SQL 14 souborů `20261112u01_qa_faq_review_google_only.sql` … `20261112u14_web_blog_slug_p.sql`, jen DATA, APLIKUJE AUTO-DEPLOY po merge za texty majitele `20261112t*`**; ověřeno na lokálním PG16 se živým schématem a živými řádky z 2026-11-12: celý bundle 2× bez chyby, 2. běh nezmění žádný řádek, i bez `t*`, na prázdné DB a s poškozenými tvary JSON) | **Texty webu, FAQ, motorek a dokumentů (bez změny UX/flow).** (1) FAQ „Jak vám mohu zanechat recenzi?“ (`fa9603a9`) jen Google + soukromá zpětná vazba e-mailem (pravidlo majitele 2026-10-15), cs + 7 jazyků. (2) Strojové překlady: pokladna en/es, české pády (Vysočině/Pelhřimově) a „ČR“ v de/nl/pl/uk → Tschechien/Tsjechië/Czechy/Чехія, pl „motorower“ → „motocykl“, nl „motorfietsverhuuring“, adresa FAQ `e7079920` → „Mezná 9, 393 01 Pelhřimov“ (cs + 7 jazyků); ploché klíče `trg_sync_cms_flat_to_nested` se vědomě NEmění (trigger by přepsal novější `web.pujcovna.intro.body` / `benefits.closing`). (3) Pobočky: co-v-ceně „přistavení / vrácení jinde (u motorek z Mezné)“ (CMS + `pages_overlay.jak_pujcit_cena.*`), Jihomoravský kraj + věta o samoobslužné pobočce Velké Němčice, `web.postup.step.5.text` = živý krok 5, blog „12 hlavních výhod“ odkaz `/motorky` → `/katalog` + odstavec o Velkých Němčicích. (4) `document_templates`: VOP — smazány zastaralé překlady en/es/fr/nl bez otisku (slib plné nádrže; appka 4.1.3 je četla přímo → teď ukáže závaznou češtinu), patička „393 01 Mezná“ → „393 01 Pelhřimov“ (v14 → v15, jinak text beze změny); nájemní smlouva — smazány zastaralé překlady de/en/es/fr/nl/pl bez platného otisku (stará věta o čistotě); česká závazná znění a podmínky beze změny, úprava mytí (čl. 5 l) NENÍ součástí (majitel neodsouhlasil). Překlady znovu: Velín → Dokumenty → „Přeložit chybějící a zastaralé“. (5) Doplněné překlady: uk 23 textů CMS + 63 FAQ, nadpis „O našem blogu“ ve všech jazycích, uk názvy vlastních dokumentů, uk 2 produkty e-shopu, výbava (features) / popis 5 motorek, nl angličtina → nizozemština (rezervace, obnova hesla, Dokumenty, Kontakt, 2 motorky) + adresa v překladech, nl blog „Top 10 dárků“ (byl francouzsky), nadpis úpravy rezervace de/es/nl = tlačítko. (6) Blog slug `p` → `proc-je-motogo24-nejlepsi-motopujcovna-v-cr` (web `blog-detail.php` `$legacySlugs` přesměruje `/blog/p` 301 — PHP web nahrát na hosting nejpozději s merge). Každá změna jen při přesném ověřeném znění (eq/podřetězec/md5 české předlohy), úpravy z Velínu mají přednost (NOTICE „beze změny“); `ai_kb_version` se nebumpuje (KB AI agenta TTL 5 min), cache webu vyprší do 40 min. Vynecháno: `20261016a_qa_messages_insert_policy`, `20261016g_qa_binding_docs_washing`. |

Doplněk k řádku STATE_6 (oprava po revizi 2026-11-12): `20261112u03` mění úvod `web.oblasti.region.jihomoravsky_kraj.intro` (cs + překlady) a `web.postup.step.5.text` jen při shodě otisku md5 se živým zněním 2026-11-12 (po `20261112t*`, `u01`, `u02`); text upravený mezitím ve Velínu se nepřepíše.
