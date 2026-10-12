# Workstream: dbsql — datová SQL pro schválené texty majitele (NÁVRH, neaplikováno, necommitováno)

Pravidlo majitele 2026-10-11: „Mytí ani tankování není třeba na obslužné pobočce. Na samoobsluze není
potřeba tankovat. Důležité je pouze, aby motorka byla umytá a nesvítila rezerva.“
→ Mezná (obslužná, i vrácení na sjednaném místě) = bez mytí a bez tankování; Velké Němčice (samoobsluha) =
plná nádrž netřeba, ale UMYTÁ a NESVÍTÍ rezerva.

## Soubory
- SQL: `scratchpad/sql/m3a_owner_texts.sql` (~46 kB, 4 bloky DO; bez BEGIN/COMMIT; idempotentní)
- Generátor (pracovní, mimo repo): `scratchpad/dbsql/tools/{spec.py,gen.py,template.sql}` — `python3 gen.py`
  ověří každou starou frázi proti živým datům (`dbsql/live/*.json`, staženo 2026-10-11) a SQL vygeneruje znovu.
- Pozn. k velikosti: při commitu do `supabase/migrations/` lze rozdělit na 4 soubory (cms / faq / overlay /
  banner) kvůli limitu ~5000 tokenů na soubor — bloky jsou na sobě nezávislé.

## Jak SQL funguje
- Mění jen text ve stavu ověřeném proti živé DB (celá věta nebo přesná fráze; zbytek textu zůstává).
- Co mezitím někdo změnil ve Velíně, přeskočí s NOTICE. Překlad se mění jen když česká hodnota řádku už
  obsahuje nový text (nikdy nevznikne nesoulad cs × překlad). Chybějící uk se doplní.
- `pages_overlay.*` (auto-překlady PHP stránek, mají přednost před `lang/pages_<lang>.php` a seznamy
  přebírají CELÉ) → mění se jen konkrétní list `jsonb_set`; nový text = string z `lang/pages_<lang>.php`
  pracovního stromu (web workstream). Když web workstream své překlady změní, stačí `gen.py` spustit znovu.
- `header_banner`: `value || {translations, translations_src}`; src = `encode(extensions.digest(convert_to(text,'UTF8'),'sha1'),'hex')`
  = `a298ae81878e23ac13221512d1ef1604c30b4157` (shodné s PHP `sha1()` i Pythonem). Jen pokud text je pořád
  „V zimním období od 1.11.2026 do 25.3.2027 zavřeno.“ a čerstvé překlady chybí. enabled/text/bg/color beze změny.

## Změněné řádky (33 řádků, 103 textových listů)
cms_variables (cs + en de es fr nl pl uk):
1. `web.pujcovna.faq.items.0.a` (/pujcovna FAQ „Jak si mohu rezervovat motorku?“)
   - „…aplikaci MotoGo24, která je zdarma ke stažení na Google Play (dostupná pro Android).“
   + „…aplikaci MotoGo24, která je zdarma ke stažení na Google Play (Android) i v App Store (iPhone).“
2. `web.home.process.steps.2.text` (úvodní stránka, krok 3)
   - „Převezmi si motorku v naší půjčovně u Pelhřimova, nebo využij přistavení motorky kamkoliv v ČR.“
   + „Převezmi si motorku v naší půjčovně v Mezné u Pelhřimova, nebo si ji vyzvedni na samoobslužné pobočce
     ve Velkých Němčicích u Brna. Z Mezné můžeš využít i přistavení motorky kamkoliv v ČR.“
3. `web.home.process.steps.2.title` — cs „3. Převezmi“ beze změny; jen překlady (byly chybné: en „3. I'll take it“,
   de „3. Ich werde abholen“ …) → „3. Pick up / Abholen / Recógela / Récupère / Ophalen / Odbierz / Забери“.
4. `web.jak_pujcit_dokumenty.payments.rows.2.1` (/jak-pujcit/dokumenty, řádek „Palivo & čištění“)
   - „Vrácení bez povinnosti dotankovat a mýt.“
   + „V Mezné a při vrácení jinde bez povinnosti dotankovat a mýt. Na samoobslužné pobočce vraťte motorku
     umytou a bez svítící rezervy (plná nádrž není nutná).“ (vykání jako zbytek stránky)
5. `web.jak_pujcit_postup.process.steps.11.text` (/jak-pujcit/postup, krok 12 — CMS řádek přebíjí PHP ve všech 8 jazycích)
   - „… Nemusíš tankovat ani mýt.“
   + „… Nemusíš tankovat ani mýt – jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy.“
6. `web.jak_pujcit_vraceni_pujcovna.cta.text` (CTA „MotoGo24 je půjčovna… “ — obecné tvrzení „bez mytí“)
   - „Bez kauce, bez mytí, bez tankování.“  + „Bez kauce, bez tankování, v Mezné i bez mytí.“

faq_items (čte i AI přes get_faq):
7. `e6df7d9f…` „Musím vracet s plnou nádrží a čistou?“
   - „Ne. U nás netankuješ ani nemyješ. Jen hlídej, aby nesvítila rezerva.“
   + „Ne. V Mezné u Pelhřimova i při vrácení na domluveném místě netankuješ ani nemyješ. Na samoobslužné
     pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ – jen motorku vrať umytou a hlídej,
     aby nesvítila rezerva.“ (+ uk otázka i odpověď nově)
8. `02b6cfc8…` „Jaké palivo mám tankovat?“ — poslední věta
   - „Při vrácení nemusíš mít plnou nádrž, jen ať nesvítí kontrolka rezervy.“
   + „Při vrácení nemusíš mít plnou nádrž: v Mezné u Pelhřimova netankuješ vůbec, na samoobslužné pobočce
     ve Velkých Němčicích u Brna jen hlídej, aby nesvítila kontrolka rezervy.“ (+ uk celá položka nově)

app_settings `pages_overlay.<stránka>.<en|de|es|fr|nl|pl>` (uk overlay neexistuje), 5 listů × 6 jazyků:
9. `jak_pujcit_vraceni_pujcovna` faq.items.1.a, `jak_pujcit_vraceni_jinde` faq.items.1.a,
   `jak_pujcit_postup` process.steps.11.text, `jak_pujcit_dokumenty` handover.items.2 a payments.rows.2.1
   → texty z nových `lang/pages_<lang>.php` (např. en vrácení jinde: „No. With us, you don't fuel up or wash it.
   Just make sure the reserve light isn't on.“ → „No. When you return the bike elsewhere, you don't refuel or wash it.“).
   Bez toho by úpravy PHP/lang souborů web workstreamu v cizích jazycích NEBYLO VIDĚT.
10. `header_banner` — translations en…uk + translations_src (bez nutnosti klikat „Uložit banner“ ve Velíně).

Záměrně NEZMĚNĚNO (sedí s pravidlem): `web.jak_pujcit_vraceni_pujcovna.intro` (Mezná), overlay
`jak_pujcit_pristaveni` krok 10 a `vraceni_pujcovna` intro/cta (PHP default nezměněn), blogy (jen „benzín“ obecně),
motorky (objem nádrže), branches.notes/translations (prázdné), message_templates, ai_public_agent_config,
site.policies (pravidlo o palivu neobsahují), custom_documents.

## Ověření
- Lokální PostgreSQL 16.15 (`/var/tmp/pg-dbsql`, port 55447), stub tabulky cms_variables (value jsonb),
  faq_items (+trigger updated_at), app_settings + schéma `extensions` s pgcrypto; nahrány VŠECHNY živé řádky
  (1232 / 110 / 84; pozor: REST vrací max 1000 řádků — cms_variables staženy stránkovaně).
- Běh 1 (`psql --single-transaction -v ON_ERROR_STOP=1`): cms 47, faq 18, overlay 30 upraveno, banner doplněn.
- Běh 2: 0 upraveno / vše „už hotovo“, snapshot shodný s během 1 (idempotentní).
- Diff po listech JSON: změnilo se přesně 103 zamýšlených listů, nic jiného (ani jiné klíče overlay/banneru).
- Negativní test (simulované úpravy ve Velíně): změněná čeština → řádek i jeho překlady přeskočeny s NOTICE;
  změněný překlad / list overlay / jiný text banneru → přeskočeno, zbytek proběhl.

## VOP / smlouva — závazné texty (cs, RPC get_document_translation), NEMĚNĚNO
- VOP v14, čl. 5 l): „Nájemce nemusí předmět nájmu předávat umytý ani s plnou nádrží, ale nesmí svítit kontrolka rezervy.“
  → rozpor: v Mezné rezerva nevadí (tankování netřeba), na samoobsluze je mytí povinné.
  Návrh: „l) Při vrácení v provozovně pronajímatele s obsluhou (Mezná u Pelhřimova) nebo na jiném sjednaném
  místě nemusí nájemce předmět nájmu mýt ani tankovat. Při vrácení na samoobslužné pobočce (Velké Němčice u Brna)
  nemusí mít předmět nájmu plnou nádrž, nájemce je však povinen jej vrátit umytý a s množstvím paliva mimo
  režim rezervy (nesmí svítit kontrolka rezervy).“
- VOP čl. 1 s) „Nájemce je povinen tankovat výhradně palivo předepsané výrobcem motocyklu.“ — v pořádku.
- Smlouva o pronájmu v11, oddíl „Vrácení předmětu nájmu“: „Pronajímatel nevyžaduje, aby byl předmět nájmu
  vrácen ve stavu čistoty nebo s plnou nádrží. Nájemce se však zavazuje vrátit předmět nájmu alespoň s množstvím
  paliva mimo režim rezervy (tj. aby nesvítila kontrolka rezervy).“
  Návrh: „Při vrácení v provozovně pronajímatele s obsluhou nebo na jiném sjednaném místě pronajímatel
  nevyžaduje, aby byl předmět nájmu umytý ani dotankovaný. Při vrácení na samoobslužné pobočce pronajímatel
  nevyžaduje plnou nádrž, nájemce se však zavazuje vrátit předmět nájmu umytý a alespoň s množstvím paliva mimo
  režim rezervy (tj. aby nesvítila kontrolka rezervy).“
- Smlouva „Tankování paliva: … výhradně palivo předepsané výrobcem (… obvykle i na palivové nádrži)“ — v pořádku.
- Předávací/škodní protokol: o mytí/palivu nic. Pozor: změna českého content_html zneplatní překlady
  (translation_src) → cizí jazyky uvidí závaznou češtinu, dokud se ve Velíně nepřeloží znovu.

## Otevřené otázky pro majitele
1. Mezná: opravdu nevadí ani svítící rezerva? (texty teď říkají „v Mezné netankuješ vůbec“; VOP/smlouva dnes rezervu vyžadují všude)
2. Vrácení na sjednaném místě (svoz z Mezné) = stejně jako Mezná (bez mytí i tankování)? (tak to píšou texty, AI i e-mail)
3. Samoobsluha vrácena špinavá / se svítící rezervou — má VOP uvést poplatek (mytí, dotankování)? Teď žádná sankce.
4. CTA „Bez kauce, bez tankování, v Mezné i bez mytí.“ — ponechat, nebo tuto změnu vypustit?
5. `web.jak_pujcit_dokumenty.handover.items.0` „Převzetí probíhá v Pelhřimově (Mezná 9) nebo využij přistavení.“
   nezmiňuje Velké Němčice — upravit? (v SQL není)
6. CMS řádek „Palivo & čištění“ nemá větu „Případné nadměrné znečištění řešíme individuálně.“ (PHP ji má) — doplnit?
7. Data v banneru přeložena s názvy měsíců (1 November 2026 …) — OK?

## Pro ostatní workstreamy / commit
- email_templates nejsou anon čitelné (RLS) — po nasazení ve Velíně/SQL editoru:
  `SELECT slug, name FROM public.email_templates t WHERE to_jsonb(t)::text ~* '(tankov|nádrž|umyt|umýt|nemyj|mytí|rezerv[uy] |refuel|full tank|wash|tanken|waschen)';`
- `translate-pages-master/master_cs.ts` (web workstream ho upravuje) má dál CTA „Bez kauce, bez mytí, bez tankování.“ a
  „Přeložit vše naráz“ ve Velíně přegeneruje pages_overlay z master_cs.ts — musí obsahovat nové věty, jinak overlay zestárne.
- Po aplikaci aktualizovat SUPABASE_BACKEND_STATE_6 (changelog) a STATE_2 (faq_items poznámka).
- Web: data cache 30 min + page cache 10 min → změny se projeví do ~40 min.
