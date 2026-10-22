# Texty majitele – datové migrace (NÁVRH ke schválení, neaplikováno)

Živá DB stažena anon klíčem **2026-10-15 pětkrát** (16:2x, 17:0x, 19:09, 22:00 a 23:21 UTC – beze změny mezi nimi; `live/`, poslední `scratchpad/fixsql5/live/`). Soubory jsou jen ve `scratchpad/sql/final/` – **nejsou v gitu**. Po schválení se zkopírují do `supabase/migrations/` (řadí se za nejnovější `20261012_web_engagement.sql`; pořadí `LC_ALL=C`: `a, b, c, d, da, e … h, ha, i … z, za … zd`) a merge do `main` je nasadí (`deploy-sql.yml`, každý soubor v jedné transakci). Ve **stejném finálním PR** (pravidlo 4 CLAUDE.md, ne až po nasazení) aktualizovat `SUPABASE_BACKEND_STATE_3.md` (funkce `_gate_procedure_msg`) a changelog `SUPABASE_BACKEND_STATE_6.md`.

## Nasazení – POZOR na pořadí

**Nejdřív `git merge origin/main` do větve.** `origin/main` = `ae7c1e9f` (ověřeno `git ls-remote` 22:00 a znovu 23:2x UTC; 15. 10. 18:07 UTC PR #2207 zmergoval starší WIP této větve `1012da7b`, k tomu #2205 a #2206). Velín a edge funkce jsou proto živě ve stavu `1012da7b`. HEAD větve `8bdf4860` je za `main` (merge-base `1012da7b`); `main` od té doby nepřidal žádnou migraci ani nic v `supabase/`, `motogo-web-php/` a `.github/`, takže pořadí `20261015*` za `20261012_web_engagement.sql` platí. PHP v `main` se od SQL liší v **48 zrcadlených listech** (přepočteno 22:00 UTC: 16 v `lang/pages_*.php`, 28 `web.layout` v `lang/<jazyk>.php`, 4 v `lang/v2/*/pobocky.php`; s nezrcadlenými `lang/v2/{en,es,pl,uk}/landing.php` je to 52 jako u verifikátoru), např. `lang/pages_nl.php` / `pages_pl.php` zkrácený úvod vyzvednutí, `lang/*.php` starý `editRez.loc.atRentalDescReturn`, `footer.aboutText`, `nextBookingPickup`. Soubory změněné v `main` od `1012da7b` (19, vč. `SUPABASE_BACKEND_STATE_1/2/6.md`) se se změnami větve nepřekrývají (ověřeno i s necommitnutými CSS/JS z kola oprav webu), merge tedy proběhne bez konfliktů. Migrace + `STATE_3`/`STATE_6` patří do téhož finálního PR; záznam do changelogu `STATE_6` psát až po merge, k 2 řádkům, které tam 15. 10. přidal `main` (App funnel, profil zákazníka – oba bez SQL).

**PHP web (ZIP) nahrát spolu se SQL, nebo hned po merge.** Cizí jazyky en–pl dostanou nové texty už ze SQL (CMS + `pages_overlay`), ale tyto texty bere web jen z PHP souborů, takže do nahrání ZIPu zůstanou staré:

- **čeština bez klíče v CMS** (bere `data/*-content-*.php`): Vrácení jinde – úvod a FAQ 1, Přistavení – krok 9, Dokumenty – převzetí bod 2, Postup – FAQ 2, Vrácení v půjčovně – FAQ 1. Živý `data/vraceni-jinde-content-2.php` dnes píše „Ne. Při vrácení jinde netankuješ ani nemyješ.“ bez pravidla o rezervě.
- **ukrajinština** nemá `pages_overlay`. U 6 klíčů CMS uk překlad chybí (úvod krok 3 text + nadpis, Dokumenty převzetí + Palivo & čištění, Postup úvod, Vyzvednutí úvod). Chybí i u 4 klíčů `web.layout.*` (patička, úprava rezervace ×2, potvrzení). uk proto bere `lang/pages_uk.php` a `lang/uk.php`.
- ZIP stavět přes `git archive <merge commit finálního PR v main> motogo-web-php` (bez `.cache`). Ne ze současného `main` (`ae7c1e9f` – staré PHP, které by odporovalo DB) a ne ze staré HEAD větve.

## Pravidlo

- 2026-10-11 (doslova): „Mytí ani tankování není třeba na obslužné pobočce. Na samoobsluze není potřeba tankovat. To důležité je pouze, aby motorka byla umytá a nesvítila rezerva.“
- 2026-10-12: stav paliva neřešíme – předává se s tím, co je v nádrži (plnou nádrž **nikdy** neslibovat), zákazník tankuje cestou sám; žádný poplatek za palivo.
- **Vrácení kdekoli:** „Tankovat nemusíš – jen ať nesvítí rezerva.“ **Umytá jen na samoobslužné pobočce Velké Němčice u Brna**; Mezná u Pelhřimova i vrácení jinde (odvoz z Mezné) bez mytí.
- Další odpovědi: obě pobočky všude, kde se mluví o převzetí; přistavení/odvoz jen u motorek z Mezné; aplikace na Google Play **i** v App Store; banner ve všech jazycích.

## Princip: DB = PHP texty webu

Každý text v DB, který má protějšek v PHP, dostane **přesně** aktuální PHP řetězec: česky `data/*-content-*.php` = `lang/pages_cs.php` = `master_cs.ts`, překlad v CMS i v `pages_overlay` = `lang/pages_<jazyk>.php`, `web.layout.*` = `lang/<jazyk>.php`, `web.pobocky.*` = `data/pobocky.php` / `lang/v2/<jazyk>/pobocky.php`. Generátor bere řetězce přímo z repa, takže každá oprava v PHP se do SQL promítne sama.

Aby se tím **neztratily vaše červencové úpravy ve Velínu**, upravil jsem nejdřív PHP texty podle nich (všech 8 jazyků):

| list | co z Velínu zůstává / co se doplnilo |
|---|---|
| Vrácení v půjčovně – úvod | „na naši adresu v **Mezné u Pelhřimova**. **Vrať motorku a zapůjčenou výbavu** a je hotovo. Před vrácením nemusíš mýt ani tankovat – jen ať nesvítí rezerva.“ |
| Vrácení v půjčovně – CTA | „Vyber si z naší **široké nabídky motorek (a skútrů)** a rezervuj online **z pohodlí domova**.“ + „Bez kauce, bez tankování (jen ať nesvítí rezerva), v Mezné i bez mytí.“ |
| Přistavení – úvod | „z naší provozovny v **Mezné u Pelhřimova**“ + nová věta: přistavení jen u motorek z Mezné, Velké Němčice jen na pobočce |
| Postup – krok 5 | „Vyber **místo** převzetí – …“ |
| Vyzvednutí – úvod | doplněné chybějící „**je**“ („… na Vysočině je převzetí motorky otázkou pár minut“). **nl a pl měly v CMS i overlay jen zkrácenou jednu větu** (bez „bez kauce / výbava v ceně / nonstop“ a bez obou poboček) → plný překlad v `lang/pages_nl.php` a `lang/pages_pl.php`, včetně „Mezná bij/koło Pelhřimov(a)“ a věty o samoobsluze ve Velkých Němčicích |
| Dokumenty – převzetí | neutrálně „z Mezné **je možné** i přistavení“ (CMS tyká, PHP vyká – teď stejné) |
| Vrácení jinde – úvod | nová věta: odvoz z adresy jen u motorek z Mezné (nl/pl dostaly plný text místo zkrácené verze) |

**Jediná záměrná výjimka:** česká úvodní stránka je ve Velínu psaná **tykáním**, `home.php` / `pages_cs.php` vykáním. Česká CMS hodnota kroku 3 a karty „Kontakty a mapa“ je proto tykací verze PHP textu (obsah stejný).

## Soubory (32 + kontrolní data)

Názvy jsou stejné jako v minulém návrhu. Skupina, která se nevešla do limitu ~13 kB, dostala další část s příponou `a` (`da`, `ha`). Pořadí `LC_ALL=C` zůstává správné (`d_` < `da_` < `e_`).

| soubor | mění | úprav |
|---|---|---|
| `a/b_owner_texts_cms_return_1/2` | CMS: Palivo & čištění, krok 12 Vrácení, Vrácení v půjčovně (úvod, CTA) – cs + všechny překlady | 31 |
| `c/d/da_owner_texts_cms_pickup_1–3` | CMS: převzetí na obou pobočkách (Dokumenty, Postup úvod + krok 5, Vyzvednutí úvod – nl/pl plné, en/es čárka, uk „отримання“, Přistavení úvod) | 37 |
| `e_owner_texts_cms_home_app` | CMS: úvodní stránka krok 3 + nadpis (opravené překlady „3. I'll take it“…), karta Kontakty (es bez „…Brno, o ponte“), FAQ /pujcovna (appka v obou obchodech) | 29 |
| `f_owner_texts_faq_fuel` | FAQ e6df7d9f (překlady k vaší odpovědi z 12. 10. + uk; es „combustible … en el depósito“, pl „W oddziale z obsługą w Mezná“, uk „з персоналом“, uk otázka), 02b6cfc8 uk, „tankvak“ přeložený jako „nádrž na palivo“ (pl, fr, uk, es, de) | 17 |
| `g/h/ha_owner_texts_faq_branches_1–3` | FAQ vrácení jinde (dac51062, 19b96b98, dd9c3286) + „Musím přijet osobně?“ (5c385d19): věta o samoobsluze ve všech jazycích + **chybějící uk** u všech čtyř; e7079920 uk. **Doklady:** „ŘP a OP nebo PAS“ / „OP a ŘP“ bylo přeloženo jako technický průkaz → opraveno v 5c385d19 (en de fr nl pl), 333ae882 (es de fr nl, pl měla české zkratky) a 0b7ecebd (pl; de měla české zkratky). nl „ander plaats“ → „andere plaats“ | 46 |
| `i_owner_texts_faq_app` | FAQ 9eb4103e (úvodní stránka): appka zdarma na Google Play i v App Store; 57912624 uk; es všude „el App Store“ (9eb4103e, 9d0038c0, bff7565d, 57912624); de 7c27d75f „Treurabatte“ → „Treuerabatte“ | 14 |
| `j–o_owner_texts_overlay_*` | cizí jazyky (en de es fr nl pl) stránek Dokumenty, Vrácení v půjčovně, Vrácení jinde, Postup, Přistavení, Vyzvednutí, úvod, /pujcovna = `lang/pages_<jazyk>.php` | 114 |
| `p/q_owner_texts_layout_1/2` | úprava rezervace (Mezná ≠ „autonomní“, PSČ 257 87; obslužná pobočka = de „Filiale mit Personal“, es „sucursal con personal“, pl „oddział z obsługą“), potvrzení rezervace (kódy jen na samoobsluze), patička („v Pelhřimově a u Brna“), samoobsluha – kód až po ověření dokladů | 28 |
| `r_owner_texts_blog_app` | blog „Aplikace MotoGo24…“ (iPhone verze „se chystá“ → je v App Store; es „el App Store“; de perex „Treuerabatte“; pl závěr „Szerokiej drogi…“) + blog „100% smluvní krytí“ (jen Android → oba obchody), všechny jazyky; navíc jen překlad: 4d86e5bb es perex („el App Store“, „la espera“), 5ec9affa de „Treuerabatte“ | 22 |
| `s_owner_texts_ai_policies` | AI asistent webu: krok 4 (obě pobočky = výchozí Velín), krok 5 (odvoz jen z Mezné); `site.policies.fuel` + rezerva na samoobsluze nesmí svítit, mytí jen VN | 3 |
| `t_owner_texts_banner` | překlady horního banneru (7 jazyků + otisk) | 8 |
| `u_owner_texts_pobocky_steps` | postup obou poboček (web /pobocky + appka) = `data/pobocky.php` | 2 |
| `v … zb_owner_texts_pobocky_preklady_1–7` | překlady textů poboček **pro appku** (23 klíčů × 7 jazyků = `lang/v2/<jazyk>/pobocky.php`; uk název „Mezná біля Пельгржимова“ a úvod bez „поблизу міста Pelhřimov“, es „depósito de combustible“) | 161 |
| `zc_owner_texts_gate_procedure` | funkce `_gate_procedure_msg` (zpráva s kódy pro VN): + „Motorku vracejte umytou a tak, aby nesvítila kontrolka rezervy (tankovat do plna nemusíte).“ – **jen když je tělo funkce přesně verze 20261004** | funkce |
| `zd_owner_texts_email_templates` | e-mailové šablony Velínu: starý odstavec o vrácení (vč. neexistujícího „poplatku za dotankování“) → i18n.ts, každý výskyt, i s `&nbsp;`/`&mdash;` z editoru; potvrzení rezervace bez zmínky o aplikaci dostane řádek Google Play + App Store | jen při shodě |

Celkem **504 úprav 500 textů + banner (1 úprava, 8 listů) = 508 změněných listů ve 112 řádcích** (cms_variables 41, app_settings 51, faq_items 16, cms_pages 4). Po dvou úpravách mají 4 texty: prompt AI (kroky 4 a 5), FAQ 4975240d pl (2 slova), blog de perex a pl článek. K tomu 1 funkce a e-mailové šablony, pokud obsahují starý text. Přesný seznam (před/po) je v `expected_changes.json`.

**Bezpečnost každého souboru:**
- Text se mění jen tehdy, když je v DB přesně ověřené znění (otisk md5 celého textu, nebo daná věta).
- Překlad se mění, jen když čeština už má nové znění. U blogu se kontroluje stejné pole: překlad perexu podle českého perexu, článku podle českého článku. Opravy jen v překladu mají prázdnou bránu.
- Doplnění překladu proběhne, jen když překlad chybí.
- Co mezitím upravíte ve Velínu, se přeskočí s NOTICE. Zvláštní NOTICE říká, když čeština není v novém znění.
- Funkce se nahradí, jen když má `md5(prosrc)` přesně verze 20261004 (`7bbb079d…`; ověřeno proti migraci i proti snapshotům živé DB z 10. 10. a z 15. 10. 08:16 UTC, větev `supabase-live-snapshot` `6b38dc9b`). Jiné tělo zůstane beze změny a vypíše se NOTICE.
- E-mailové vzory mají příznak `g` a snesou `&nbsp;`, U+00A0, zalomení řádku, `&mdash;` i `&ndash;`.
- 2. běh nic nezmění. Soubory nemají BEGIN/COMMIT.

## Ukázky (před → po)

- **Dokumenty, Palivo & čištění** (cs): „Vrácení bez povinnosti dotankovat a mýt.“ → „Vrácení bez povinnosti tankovat – jen ať nesvítí rezerva. Umytou je potřeba motorku vrátit jen na samoobslužné pobočce ve Velkých Němčicích. Případné nadměrné znečištění řešíme individuálně.“
- **Postup, krok 12** (cs): „…osobně do půjčovny v Mezné, nebo na předem sjednané místo. Nemusíš tankovat ani mýt.“ → „Motorku vrať včas – osobně na pobočku, kde sis ji půjčil (Mezná u Pelhřimova, nebo samoobslužné Velké Němčice u Brna), u motorek z Mezné i na předem sjednané místo. Tankovat nemusíš – jen ať nesvítí rezerva. Umytou ji vracej jen na samoobslužné pobočce ve Velkých Němčicích.“ (es: „Solo en la sucursal de autoservicio de Velké Němčice hay que devolverla lavada.“)
- **Postup, úvod** (cs): „Motorku si vyzvedni v Pelhřimově, nebo si objednej přistavení…“ → „Motorku si vyzvedni v Mezné u Pelhřimova (odtud ti ji můžeme i přistavit kamkoliv v ČR), nebo samoobslužně ve Velkých Němčicích u Brna.“
- **Vyzvednutí, úvod** (nl): „Bij Motogo24 – motorverhuur Vysočina is het ophalen van de motor in een paar minuten geregeld.“ → „Bij MotoGo24 – motorverhuur in de regio Vysočina is het ophalen van de motor in een paar minuten geregeld. We verhuren zonder borg, met rijuitrusting inbegrepen en met ophalen en inleveren 24/7. Kom persoonlijk naar Mezná bij Pelhřimov en ga op pad! Bij de zelfbedieningsvestiging in Velké Němčice bij Brno haal je de motor zelf op met een toegangscode uit de app of de e-mail.“
- **Úvodní stránka, krok 3** (cs): „Převezmi si motorku v naší půjčovně u Pelhřimova, nebo využij přistavení…“ → „Převezmi si motorku osobně v Mezné u Pelhřimova (odtud ti ji můžeme i přistavit kamkoli v ČR), nebo si ji vyzvedni sám na samoobslužné pobočce ve Velkých Němčicích u Brna.“
- **FAQ /pujcovna** (cs): „…zdarma ke stažení na Google Play (dostupná pro Android).“ → „…v aplikaci MotoGo24, která je zdarma na Google Play (Android) i v App Store (iPhone). Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.“
- **FAQ „Mohu vrátit motorku jinde?“** (cs, + všechny překlady a nově uk): + „Vrácení jinde ale neplatí pro motorky ze samoobslužné pobočky ve Velkých Němčicích – ty se přebírají i vracejí jen přímo na této pobočce.“ (en: „Returning the bike elsewhere is not possible for bikes from the self-service branch in Velké Němčice – …“)
- **FAQ „Musím přijet osobně?“**: + „Tak to probíhá na obslužné pobočce v Mezné. Na samoobslužné pobočce ve Velkých Němčicích si motorku převezmeš sám pomocí kódů z aplikace nebo e-mailu a předávací protokol podepíšeš na displeji – doklady musíš mít předem nahrané a ověřené online.“ Doklady v překladech: en „driver's license and vehicle registration or passport“ → „driving licence and ID card or passport“ (de „KFZ-Schein“ → „Personalausweis“, fr „carte grise“ → „carte d'identité“, nl „registratiebewijs“ → „identiteitskaart“, pl „dowód rejestracyjny“ → „dowód osobisty“).
- **Potvrzení rezervace** (CMS, tykání): „V den vyzvednutí přijeď na pobočku — kódy odemknou dveře, motorka i výbava jsou připravené.“ → „V den vyzvednutí přijeď na pobočku. Na samoobslužné pobočce ve Velkých Němčicích ti kódy odemknou dveře k výbavě i motorce, v Mezné ti motorku i výbavu předá obsluha. Máš-li objednané přistavení, čekej na zvolené adrese.“
- **Úprava rezervace, vrácení** : „Vrátíte v autonomní pobočce.“ → „Vrátíte přímo na pobočce.“; en/de/… převzetí „Mezná 9, 257 87 — autonomous branch“ → „Mezná 9, 393 01 Pelhřimov — staffed branch“ (de „Filiale mit Personal“, es „sucursal con personal“, pl „oddział z obsługą“).
- **Blog o aplikaci** (cs): „Máš "Jabko"? Nezoufej a vydrž, verze pro iOS se chystá…“ → „Máš "Jabko"? Čekání skončilo – od září 2026 je aplikace i v App Store pro iPhone. Stačí v obchodě vyhledat „MotoGo24“.“

## Změny v repu (WIP commity větve; v `main` je zatím jen stav `1012da7b`)

- Dřívější kolo (už v `main`, PR #2207): `motogo-web-php/lang/pages_{cs,en,de,es,fr,nl,pl,uk}.php`, `data/{vraceni-pujcovna-content-1,vraceni-pujcovna-content-2,pristaveni-content-1,vraceni-jinde-content-1,prevzeti-content-1,dokumenty-content-2,postup-content-1}.php`, `supabase/functions/translate-pages-master/master_cs.ts` (7 hodnot) – 35 listů, viz tabulka výše.
- Agent oprav repa (WIP do `7d9f6699`): `lang/pages_nl.php` + `pages_pl.php` (plný úvod Vyzvednutí, pl drobnosti), `lang/<jazyk>.php` ×8 (`editRez.loc.atRentalDescReturn`, `confirm.success.nextBookingPickup`, `footer.aboutText` = `repo_mirror_lang.json`), Velín výchozí texty `velin/src/pages/cms/webTextsUpravit.js` a `webTextsFaq.js` (= hodnoty v DB), en „the Czech Republic“ / „just make sure the reserve light isn't on“, `lang/v2/en/pobocky.php` „any of the spaces 1–7“.
- Toto kolo (fix:sql, WIP `2a959ded`, 18 náhrad, `php -l` OK, `deno check` i18n.ts OK):
  - `lang/pages_es.php`: krok 12 a FAQ Vrácení v půjčovně („Solo en la sucursal … hay que devolverla lavada“), čárka v úvodu Vyzvednutí, karta Kontakty („… cerca de Brno – o ponte en contacto“).
  - `lang/pages_en.php`: čárka v úvodu Vyzvednutí.
  - `lang/pages_uk.php`: krok 5 „спосіб отримання“, úvod Vyzvednutí „…або електронного листа“, 2× otázka „Чи потрібно повертати мотоцикл із повним баком і чистим?“.
  - `lang/{de,es,pl,uk}.php`: `editRez.loc.atRentalDescPickup` (obslužná pobočka jako na štítku). `lang/es.php`: `rez.return.stateText` („depósito de combustible“, nový slovosled).
  - `lang/v2/es/pobocky.php` a `pobocky-v2.php`: „depósito de combustible“. `lang/v2/uk/pobocky.php`: název pobočky „Mezná біля Пельгржимова“, úvod.
  - `supabase/functions/send-booking-email/i18n.ts`: es odstavec Vrácení („depósito de combustible“, slovosled). Ve stejném WIP jsou v tomto souboru i změny agenta Hodnocení (odkazy na recenze). Moje změna je jen 1 řádek (es).
- Kolo oprav webu (necommitnuté `motogo-web-php/css/*` ×7 a `js/ui.js`: menu na tabletu, zalamování slov, tlačítko Rezervovat, kalkulačka): **žádný text, SQL beze změny.** Generátor spuštěný na aktuální pracovní strom a čerstvé stažení živé DB (22:00 a znovu 23:21 UTC, HEAD `8bdf4860`) dává bajtově shodných 32 souborů i `expected_changes.json`. Commit `8bdf4860` (hodnocení jízdy) nemění žádný text webu: PHP listy (`dumpleaves`, `pobv2`) jsou bajtově shodné se stavem, na kterém proběhla kontrola webu.

## Musí dorovnat repo (mimo moje soubory)

- `velin/src/components/ai/WebAgentSettingsPanel.jsx` řádek 23 (krok 5) = nový text z migrace `s` – **stále starý** (ověřeno 23:2x UTC; krok 4 už sedí).
- Ve stejném PR jako migrace (ne po nasazení): `SUPABASE_BACKEND_STATE_3.md` (`_gate_procedure_msg`) a `SUPABASE_BACKEND_STATE_6.md` (changelog).
- Volitelně (starší texty, mimo tyto migrace): de „bediente Filiale“ v `send-booking-email/i18n.ts` (dokumenty) a `lang/de.php` (`rez.steps.docsOptionalNote`, `confirm.success.nextBookingDocsMissing`, `confirm.paydocs.step2`); uk „Філія з обслуговуванням“ (`lang/uk.php` `rez.steps.staffedBranchLabel`, `docsOptionalNote`); es appka „sucursal atendida“ (`translations_ext_5_validation.dart`, oba stromy); es web jinde „sin depósito“ → „sin fianza“.

## Záměrně neměněno / zamítnuté nálezy

- **VOP a nájemní smlouva** – závazné texty, jen návrh níže.
- **Překlady VOP** (en/es/fr/nl „…předán čistý, s plnou nádrží“) – nezobrazují se (bez otisku české verze); zmizí po „Přeložit chybějící a zastaralé“ ve Velínu.
- **„V promptu AI chybí pravidlo vrácení“** – nepravda: edge `ai-public-agent` přidává `HARD_RULES_CS` (pravidlo 33). Doplněn jen krok 5 (odvoz jen z Mezné).
- **FAQ e6df7d9f česky** – vaše znění z 12. 10.; volitelné „(ani při vrácení na jiném sjednaném místě)“ nepřidáno.
- **Vyzvednutí – alternativní věta z jednoho nálezu** – nahrazena textem, který už je v repu („…vyzvedneš sám přístupovým kódem z aplikace nebo e-mailu“).
- **333ae882 es** – navržené „(documento de identidad o pasaporte y permiso de conducir)“ přidávalo pas, který česká odpověď („OP a ŘP“) neuvádí. Je proto „(documento de identidad y permiso de conducir)“, stejně jako de/fr/nl/pl.
- **uk „Приймання“** v nadpisech a úvodu stránky Vyzvednutí zůstává: je to zavedený termín celé uk stránky. Opravena jen nová věta kroku 5. Stejně zůstávají uk SEO popisy a `lang/v2/*/info.php` „Mezná (Pelhřimov, Vysočina)“, které mají stejný tvar ve všech jazycích.
- **`web.pobocky.branches.1.gear`** – překlad nedoplněn: česká hodnota ve Velínu nemá velikosti helem (S–3XL), které má `data/pobocky.php` a `lang/v2`. Rozhodněte, co platí. SEO klíče a `back_link`/galerie appka nepoužívá – web je bere z `lang/v2` jako dřív.
- **63 FAQ (ze 110) bez ukrajinštiny** (dnes 71). Doplněno je 8: 02b6cfc8, e7079920, 57912624, e6df7d9f, dac51062, 19b96b98, dd9c3286 a 5c385d19. Zbytek doplní Velín → FAQ → „Přeložit chybějící“.
- Ostatní staré chyby v překladech mimo dotčené řádky (např. de „Motorradbörse“ v patičce už opraveno, de „rundum-the-clock“ v CTA nahrazeno novým textem).
- Recenze zákazníků („motorka byla natankovaná“, es „con el depósito lleno“) – skutečné citace.

## Závazné dokumenty – NÁVRH, NEAPLIKOVÁNO

Změna českého `content_html` vyžaduje váš výslovný souhlas a zneplatní všechny překlady (cizí jazyky uvidí závaznou češtinu do „Přeložit chybějící a zastaralé“).

- **VOP v14, čl. 5 l)** dnes: „Nájemce nemusí předmět nájmu předávat umytý ani s plnou nádrží, ale nesmí svítit kontrolka rezervy.“ (rozpor: na samoobsluze je mytí povinné). Návrh: „l) Nájemce nemusí předmět nájmu vracet s plnou nádrží, nesmí však svítit kontrolka rezervy paliva. Při vrácení v provozovně pronajímatele s obsluhou (Mezná u Pelhřimova) nebo na jiném sjednaném místě nemusí nájemce předmět nájmu mýt; při vrácení na samoobslužné pobočce (Velké Němčice u Brna) je povinen jej vrátit umytý.“
- **Smlouva v11, „Vrácení předmětu nájmu“** dnes: „Pronajímatel nevyžaduje, aby byl předmět nájmu vrácen ve stavu čistoty nebo s plnou nádrží. Nájemce se však zavazuje…“ Návrh: „Pronajímatel nevyžaduje, aby byl předmět nájmu vrácen s plnou nádrží; nájemce se však zavazuje vrátit jej alespoň s množstvím paliva mimo režim rezervy (tj. aby nesvítila kontrolka rezervy). Při vrácení v provozovně s obsluhou nebo na jiném sjednaném místě pronajímatel nevyžaduje, aby byl předmět nájmu umytý; při vrácení na samoobslužné pobočce se nájemce zavazuje vrátit předmět nájmu umytý.“
- VOP čl. 5 f) a čl. 1 s) v češtině v pořádku (plnou nádrž neslibují).

## Otázky pro vás

1. Vrácení na sjednaném místě (odvoz z Mezné) = jako Mezná (bez mytí, jen nesvítí rezerva)? Texty to tak píší.
2. Samoobsluha vrácená nemytá / se svítící rezervou – má mít VOP sankci? Dnes žádná.
3. VN výbava: platí helmy S–3XL (data/pobocky.php), nebo text ve Velínu bez helem?
4. Ceny přistavení: FAQ „500 Kč za nakládku/vykládku a 20 Kč/km“ vs. AI asistent „1000 Kč + 40 Kč/km“ – sjednotit?
5. Banner: data s názvy měsíců („1 November 2026“) – OK?

## Ověření (lokální PostgreSQL 16, skutečné DDL + triggery, živá data 2026-10-15)

- **Plný běh.** Všech 32 souborů běželo v pořadí `LC_ALL=C` přes `psql --single-transaction -v ON_ERROR_STOP=1 -f` (jako deploy), dvakrát.
  - Běh 1: 0 chyb. Změněné listy JSON se přesně shodují s `expected_changes.json` (508 listů, nic navíc, jiné sloupce beze změny). Funkce vrací novou větu a ACL zůstává.
  - Běh 2: 0 změn. Funkce hlásí „už hotovo“.
  - Totéž platí znovu po zkopírování souborů do `sql/final` (`test/md5_tested.txt`).
- **Zopakováno 2026-10-15 ve 22:0x a znovu ve 23:2x UTC** (po kole oprav webu a po commitu `8bdf4860`), pokaždé na nové šabloně DB z čerstvého stažení živé DB. Funkce má ACL jako živě (`REVOKE` z 20261004).
  - Soubory: md5 = `test/md5_tested.txt` (beze změny).
  - Běh 1: 0 chyb, 508 listů = `expected_changes.json`, nic navíc, jiné sloupce beze změny. E-maily: změněno 5 šablon se starým odstavcem (3 listy každá), 3 šablony bez shody beze změny. Funkce vrací novou větu, ACL `{postgres=X/postgres}` před i po.
  - Běh 2: 0 změn.
  - Oba negativní testy: přeskočeno opět 70 a 11 listů, žádný chráněný list se nezměnil; ručně upravená funkce zůstala.
  - Výpisy obou běhů i negativních testů jsou (bez cest) shodné s předchozím testem; seznam změněných listů (523 vč. e-mailů) je totožný.
- **Negativní test 1** (17 simulovaných úprav ve Velínu): čeština kroku 12, en CTA, nadpis kroku 3, de overlay, česká FAQ odpověď, banner, kroky VN, en a uk FAQ dac51062, český článek blogu, policies, patička de, uk FAQ, en text poboček, česká odpověď 333ae882 a 5c385d19, ručně změněné tělo funkce.
  - Přesně tyto texty (a jejich závislé překlady) se přeskočily s NOTICE: 70 listů. Zbylých 438 proběhlo.
  - Perex blogu proběhl, protože česká změna byla jen v článku. Funkce zůstala ručně upravená.
- **Negativní test 2:** změněn jen český perex blogu, uk 57912624 vyplněno ve Velínu a pl úvod Vyzvednutí změněn ve Velínu. Přeskočeno přesně těchto 11 listů (perex cs + 7 překladů perexu, uk otázka + odpověď, pl úvod Vyzvednutí v CMS). Článek blogu proběhl.
- **E-mail** (syntetické šablony, živé nejsou čitelné anon klíčem):
  - Starý odstavec se nahradil všude: i dvakrát v jedné šabloně, s `&nbsp;`/`&mdash;`, U+00A0 a `&ndash;`, i ve znění z 11. 10.
  - Šablona s jiným textem zůstala. 2. běh: 0 změn.
- **Web** (kopie repa s novými PHP texty proti stavu DB po migracích, 8 jazyků): 372 kontrol na 128 stránkách, 0 problémů.
  - Kontrolované stránky: Postup, Přistavení, Vyzvednutí, Vrácení v půjčovně/jinde, Dokumenty, FAQ (vč. otázek a uk), úvod v1/v2, /pujcovna, blogy, pobočky (uk název a úvod), patička, banner, úprava rezervace, potvrzení, rezervace (es).
  - Žádná stará věta nezůstala, ani žádný z opravených chybných výrazů. Každá vrstva (CMS/overlay) = PHP text.
- **Nástroje:** `scratchpad/sqlfix/tools/gen3.py` (generátor, `spec3.py`, `spec2.py`, `repo_edits.py`), testy `scratchpad/sqlfix/test/` (kopie v `test/`), opakované testy 22:0x `scratchpad/fixsql4/` a 23:2x `scratchpad/fixsql5/` (`run4.sh`/`run5.sh`, `load4.sql`/`load5.sql`, stažení `fetch.py`, výstupy `o1`, `n1`, `n2`; kopie skriptů a posledních výpisů v `test/`). Předchozí verze návrhu je v `scratchpad/sqlfix/final_before/`.

## Doplněk QA brány 2026-10-16 – POVINNĚ ve stejném nasazení (soubory v `scratchpad/qa-final/sql/`)

Bez těchto souborů zůstanou na živém webu i po nasazení 32 souborů výše porušená pravidla majitele (recenze jen Google, přistavení jen z Mezné, uk FAQ česky, zastaralé překlady VOP/smlouvy, nl texty v angličtině/francouzštině, adresa „393 01 Mezná“). Zkopírují se do `supabase/migrations/` spolu s 32 soubory výše. Výsledné pořadí `LC_ALL=C` (= pořadí `deploy-sql.yml`):

```
20261015a … 20261015zd            (32 souborů výše)
20261016b_qa_faq_review_google_only.sql        recenze jen Google (FAQ fa9603a9, cs + 7 překladů) – nahrazuje reviews/sql/DRAFT_20261015_faq_review_google_only.sql (nasadit jen jeden z nich)
20261016c_qa_translation_fixes.sql             adresa FAQ e7079920 (8 jazyků), pl palivo, „ČR“ v překladech (14× „beze změny“ = vzor už chybí, OK)
20261016d_qa_texts_branches.sql                přistavení jen z Mezné („co v ceně“ ad.), obě pobočky
20261016e_qa_vop_stale_translations.sql        smaže skryté zastaralé překlady VOP („předán čistý, s plnou nádrží“)
20261016f_qa_vop_footer_address.sql            NOVÉ: patička VOP „393 01 Mezná“ → „393 01 Pelhřimov“ (jen adresa, nezávislé na g; VOP v14→v15)
20261016g_qa_binding_docs_washing.sql          ⚠ JEN PO VÝSLOVNÉM SOUHLASU MAJITELE (závazný text VOP 5 l + smlouva: mytí jen VN); bez souhlasu soubor NEKOPÍROVAT
20261016ga_qa_contract_stale_translations.sql  smaže skryté zastaralé překlady smlouvy („ve stavu čistoty“) – nasadit i bez g
20261016h_qa_uk_texts.sql                      uk texty stránek (e-shop, katalog, poukaz, mapa webu, názvy dokumentů)
20261016i_qa_faq_uk_1.sql                      uk FAQ 1/2 (chybějící překlady)
20261016j_qa_faq_uk_2.sql                      uk FAQ 2/2
20261016k_qa_moto_translations.sql             výbava motorek (PW 50, KTM SX 50 …) – jen prázdná pole
20261016l_qa_nl_wrong_language.sql             NOVÉ: nl angličtina → nizozemština (tip přistavení/odvozu, obnova hesla, Dokumenty, Kontakt, popis KTM SX 50 + XT660 X i výbava); adresa „393 01 Mezná“ → „393 01 Pelhřimov“ v překladech (rezervace, úprava rezervace, kontakt)
20261016m_qa_blog_top10_nl.sql                 NOVÉ: blog „Top 10 dárků…“ – nl byl francouzsky → nizozemský překlad
20261016w1_web_editrez_h1_terms.sql            jednotný název „Upravit rezervaci“ (H1 = tlačítko) de/es/nl
20261016w2_web_blog_slug_p.sql                 /blog/p → /blog/proc-je-motogo24-nejlepsi-motopujcovna-v-cr – PHP web (blog-detail.php, 301) nahrát nejpozději současně
```

**Nekopírovat:** `20261016a_qa_messages_insert_policy.sql` (samostatný návrh politiky RLS, mimo texty).

**Brána g:** bez souhlasu majitele se nasadí vše kromě `g`; patička VOP se opraví i tak (`f`), čl. 5 l) a smlouva zůstanou v dnešním znění („nemusí … umytý“). Po případném pozdějším souhlasu jde `g` jako samostatná migrace s novým názvem (soubor s už evidovaným názvem `deploy-sql.yml` znovu nespustí).

**Ověření (2026-10-16 ~04:40 UTC, čerstvé stažení živé DB anon klíčem, lokální PostgreSQL 16, `qa-final/fix-other3/pg/run.sh`):** všech 32 + 15 souborů (s `g`) i 32 + 14 (bez `g`) v pořadí `LC_ALL=C`, každý `--single-transaction -v ON_ERROR_STOP=1`, dvakrát: 0 chyb, 2. běh 0 změn. Nové soubory `f`/`l`/`m` mění přesně 40 (s g) / 41 (bez g) listů: 33 překladů cms_variables, 3 pole motorek, 3 pole blogu nl, VOP patička + verze; nic jiného. Negativní test (simulované úpravy ve Velínu: nl tip, česká hodnota kontaktu, nl popis KTM, česká výbava XT660, nl titulek blogu, 2× adresa ve VOP) → přesně tyto přeskočeny s NOTICE. Render (PHP web proti mocku DB po migracích): `393 01 Mezná` 0× na /rezervace a /upravit-rezervaci v de/en/es/fr/nl/pl (dřív 2× + 1×), VOP patička „393 01 Pelhřimov“, nl stránky bez angličtiny/francouzštiny (blog Top 10 nl: H1 „Top 10 cadeaus voor motorrijders waar ze echt blij mee zijn“).

**STATE:** do changelogu `SUPABASE_BACKEND_STATE_6.md` ve stejném PR zapsat i tyto datové migrace (bez změn schématu).

**Co SQL nevyřeší (akce majitele ve Velínu):**
- Blog: „Zavádíme 100% smluvní krytí škod“ má jen `en` (de/es/fr/nl/pl/uk česky) – uložit znovu až PO nasazení `20261015r`; dál bez překladu: de 4, es 1, fr 1, nl 2, pl 7, uk 8 článků → otevřít a Uložit (auto-překlad všech 7 jazyků).
- Dokumenty: všech 7 šablon má `translation_src = {}` → cizí jazyky vidí závaznou češtinu s poznámkou „překlad se připravuje“ → Velín → Dokumenty → „Přeložit chybějící a zastaralé“ (po `e`/`ga`, případně po `g`).
- E-mailové šablony: anon klíčem nečitelné. Po nasazení `zd` zkontrolovat v logu deploye NOTICE „s Google Play bez App Store“ a „s textem o palivu/mytí“; případně upravit ve Velínu → Šablony e-mailů.
- Vlastní dokumenty e-shopu (cookies, obchodní podmínky e-shopu, reklamační řád) jsou PDF; jejich překlady obsahují adresu „393 01 Mezná“ tak, jak je v PDF – sjednotit až s novým PDF (záměrně neměněno).
