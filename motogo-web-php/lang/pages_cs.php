<?php
// ====== MotoGo24 — pages_cs.php (vygenerovano build_pages_cs.php) ======
// CS reference strom — slouzi jako template pro paralelni preklad do ostatnich jazyku.
// Pro CS samotne se nepouziva (defaults se nactou primo z pages/*.php a data/*.php),
// ale je-li primitomny, deep_merge prebije CS hodnoty stejnymi (tj. neni rozdilu).
// Pro non-CS jazyky vytvor stejnou strukturu v pages_<lang>.php s prelozenymi hodnotami.

return [
    'pages' => [
        'jak_pujcit_cena' => [
            'h1' => 'Co je v ceně pronámu motorky',
            'intro' => 'V ceně pronájmu máš <strong>výbavu pro řidiče, kotoučový zámek, povinné ručení se zelenou kartou a 100% smluvní krytí škod se spoluúčastí 0 Kč</strong>. Kilometry neomezujeme a kauci neskládáš. Za příplatek si přiobjednáš jen to, co opravdu potřebuješ.',
            'gear' => [
                'basic' => [
                    'title' => 'Základní výbava v ceně',
                    'lead' => 'Každý řidič má k dispozici kompletní <strong>motorkářskou výbavu</strong>, která je zahrnuta v ceně pronájmu:',
                    'items' => [
                        '<strong>helma</strong>',
                        '<strong>motorkářská bunda</strong> s chrániči',
                        '<strong>moto kalhoty</strong>',
                        '<strong>rukavice</strong>',
                    ],
                    'note1' => 'Výbava je dostupná ve více velikostech a pravidelně ji čistíme a kontrolujeme.',
                    'note2' => 'Vybrané motorky jsou vybaveny kufry – viz detail motorky v katalogu.',
                ],
                'extra' => [
                    'title' => 'Nadstandardní výbava za příplatek',
                    'lead' => 'Jedeš se spolujezdcem nebo chceš motocyklové boty? Můžeš si při rezervaci přiobjednat:',
                    'items' => [
                        'výbava pro spolujezdce (helma, bunda, kalhoty, rukavice)',
                        'motocyklové boty – pro řidiče i spolujezdce',
                    ],
                ],
                'services' => [
                    'title' => 'Nadstandardní služby za příplatek',
                    'items' => [
                        'přistavení motorky na domluvené místo kamkoliv v ČR (u motorek z obslužné pobočky v Mezné)',
                        'vrácení motorky jinam než na pobočku (u motorek z Mezné)',
                    ],
                ],
            ],
            'benefits' => [
                'title' => 'Další výhody v ceně',
                'grid' => 'gr5',
                'items' => [
                    [
                        'icon' => 'gfx/rezervace-online.svg',
                        'title' => 'Online rezervace',
                        'text' => 'rychlá a jednoduchá rezervace z pohodlí domova.',
                    ],
                    [
                        'icon' => 'gfx/ico-nonstop.svg',
                        'title' => 'Nonstop provoz',
                        'text' => 'rezervuj a vyrazit můžeš kdykoliv – ve dne, v noci i o víkendu. Čas převzetí si volíš v rezervaci.',
                    ],
                    [
                        'icon' => 'gfx/ico-bez-kauce.svg',
                        'title' => 'Bez kauce',
                        'text' => 'žádná kauce ani blokace peněz na kartě – platíš jen nájem.',
                    ],
                    [
                        'icon' => 'gfx/jasne-podminky.svg',
                        'title' => 'Jasné podmínky',
                        'text' => 'bez skrytých poplatků.',
                    ],
                    [
                        'icon' => 'gfx/sleva-na-pristi-jizdu.svg',
                        'title' => 'Sleva na další rezervaci',
                        'text' => 'po každém dokončeném pronájmu dostaneš slevový kód na příští rezervaci.&nbsp;',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Rezervuj motorku online',
                'text' => 'Cenu všech doplňků uvidíš v rezervaci ještě před platbou. Vyber si motorku a rezervuj online.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT ONLINE',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                        'aria' => 'Rezervovat motorku s výbavou v ceně v půjčovně Motogo24',
                    ],
                ],
            ],
            'seo' => [
                'title' => 'Co je v ceně pronájmu motorky | MotoGo24',
                'description' => 'V ceně máš výbavu řidiče, neomezené kilometry, kotoučový zámek a 100% smluvní krytí škod. Bez kauce. Za příplatek výbava spolujezdce, boty a přistavení.',
                'keywords' => 'motopůjčovna',
            ],
        ],
        'jak_pujcit_dokumenty' => [
            'h1' => 'Podmínky půjčení motorky a dokumenty ke stažení',
            'intro' => 'Na této stránce najdeš přehled nejdůležitějších pravidel: co potřebuješ k uzavření smlouvy, jak se platí, kolik stojí storno a za co odpovídáš. Níže si stáhneš <strong>obchodní podmínky, vzor smlouvy o pronájmu a protokoly v PDF</strong>.',
            'top_cta' => [
                'label' => 'REZERVOVAT ONLINE',
                'href' => '/rezervace',
                'aria' => 'Přejít na online rezervaci motorky podle nájemní smlouvy Motogo24',
            ],
            'summary' => [
                'title' => 'Shrnutí hlavních bodů',
                'items' => [
                    [
                        'icon' => 'gfx/ico-bez-kauce.svg',
                        'title' => 'Žádná kauce',
                        'text' => 'nic ti neblokujeme na kartě ani nechceme hotovost',
                    ],
                    [
                        'icon' => 'gfx/rezervace-online.svg',
                        'title' => 'Online rezervace',
                        'text' => 'včetně platby',
                    ],
                    [
                        'icon' => 'gfx/vyber-vybavu.svg',
                        'title' => 'Výbava pro řidiče',
                        'text' => 'v ceně (helma, bunda, kalhoty, rukavice)',
                    ],
                    [
                        'icon' => 'gfx/ico-nonstop.svg',
                        'title' => 'Nonstop provoz',
                        'text' => 'čas převzetí si zvolíš v rezervaci, vrátit můžeš kdykoli poslední den do 24:00',
                    ],
                    [
                        'icon' => 'gfx/jasne-podminky.svg',
                        'title' => 'Jasná pravidla užívání',
                        'text' => 'doma i v zahraničí (podle zelené karty)',
                    ],
                    [
                        'icon' => 'gfx/zadne-skryte-poplatky.svg',
                        'title' => 'Žádné skryté poplatky',
                        'text' => 'vše je uvedeno níže a ve smlouvě',
                    ],
                ],
            ],
            'required_docs' => [
                'title' => 'Co potřebujete k uzavření smlouvy',
                'items' => [
                    '<strong>Občanský průkaz / pas</strong>',
                    '<strong>Řidičský průkaz</strong>&nbsp;odpovídající skupiny (A, A2 nebo A1/B podle motorky)',
                    '<strong>Věk</strong>&nbsp;alespoň 18 let (u dětských motorek je nájemcem zákonný zástupce dítěte, např. rodič)',
                    '<strong>Kontakty</strong>&nbsp;(telefon, e-mail) pro komunikaci a potvrzení rezervace',
                ],
            ],
            'payments' => [
                'title' => 'Platby, storno a poplatky',
                'lead' => '<strong>Kauce:</strong>&nbsp;<em>nevyžadujeme</em>. Nájem zaplatíš předem online kartou (i přes Apple Pay nebo Google Pay), při rezervaci na webu také QR platbou nebo bankovním převodem. Platba musí dorazit do 4 hodin od odeslání rezervace, jinak můžeme rezervaci zrušit.',
                'aria' => 'Přehled plateb a poplatků',
                'headers' => [
                    'Položka',
                    'Podmínky',
                ],
                'rows' => [
                    [
                        '<strong>Platba nájemného</strong>',
                        'Online předem.',
                    ],
                    [
                        '<strong>Storno rezervace</strong>',
                        'Zdarma nejpozději 7 dní před převzetím. Při zrušení 2–7 dní předem můžeme účtovat až 50 % nájemného, při zrušení méně než 2 dny předem nebo při nevyzvednutí motorky celé nájemné (VOP čl. 3).',
                    ],
                    [
                        '<strong>Palivo &amp; čištění</strong>',
                        'Vrácení bez povinnosti tankovat – jen ať nesvítí rezerva. Umytou je potřeba motorku vrátit jen na samoobslužné pobočce ve Velkých Němčicích. Případné nadměrné znečištění řešíme individuálně.',
                    ],
                    [
                        '<strong>Přistavení / svoz</strong>',
                        'Dle ceníku přistavení (Vysočina / okolí). Potvrzujeme při rezervaci.',
                    ],
                    [
                        '<strong>Pozdní vrácení</strong>',
                        'Motorku vrať poslední den výpůjčky do 24:00. Za každý další započatý den platíš nájemné za den navíc (VOP čl. 2 d). Nestihneš to? Prodluž si výpůjčku v sekci Upravit rezervaci.',
                    ],
                ],
                'mid_cta' => [
                    'label' => 'POKRAČOVAT K REZERVACI',
                    'href' => '/rezervace',
                    'aria' => 'Zarezervovat motorku a souhlasit s nájemní smlouvou Motogo24',
                ],
            ],
            'usage' => [
                'title' => 'Užívání motorky a odpovědnost',
                'items' => [
                    'Škody na motorce, které zaviníš, kryje <strong>100% smluvní krytí škod</strong> se spoluúčastí 0 Kč. Nevztahuje se na zapůjčenou výbavu, na hrubé porušení podmínek (např. jízda pod vlivem nebo bez řidičského oprávnění) ani na odcizení – u řádně zabezpečené motorky odpovídáš nejvýš do 30 000 Kč, u nezabezpečené až do její obvyklé tržní hodnoty.',
                    'Za&nbsp;<strong>pokuty a přestupky</strong>&nbsp;odpovídá nájemce (informace předáváme dle zákona).',
                    '<strong>Zahraničí</strong>: možné; řiďte se územní platností pojištění (zelená karta). Některé země mohou být vyloučeny.',
                    'Při&nbsp;<strong>nehodě nebo poruše</strong>&nbsp;nám hned zavolej a řiď se našimi pokyny; při dopravní nehodě nebo krádeži vždy přivolej i policii – je to podmínka smluvního krytí škod.',
                    '<strong>Servis</strong>&nbsp;zajišťujeme my, ty během výpůjčky jen pravidelně mažeš řetěz. Závady nám hlas hned.',
                    '<strong>Úpravy motorky</strong>&nbsp;bez souhlasu nejsou dovoleny.',
                ],
            ],
            'handover' => [
                'title' => 'Předání a vrácení',
                'items' => [
                    '<strong>Převzetí</strong>&nbsp;probíhá v Pelhřimově (Mezná 9) nebo na samoobslužné pobočce ve Velkých Němčicích u Brna; z Mezné je možné i&nbsp;<a href="/jak-pujcit/pristaveni">přistavení</a>.',
                    'Při předání obdržíte&nbsp;<strong>klíče, výbavu a dokumenty</strong>&nbsp;(malý TP, zelená karta, formulář nehody).',
                    '<strong>Vrácení</strong>&nbsp;kdykoli během posledního dne výpůjčky (i o půlnoci). Tankovat není nutné – jen ať nesvítí rezerva; umytou je potřeba motorku vrátit jen na samoobslužné pobočce ve Velkých Němčicích.',
                ],
            ],
            'privacy' => [
                'title' => 'Osobní údaje a bezpečnost',
                'text' => 'Osobní údaje zpracováváme pouze pro účely uzavření a plnění nájemní smlouvy (identifikace, komunikace, fakturace). Podrobnosti najdeš v <a href="/dokumenty/zasady-ochrany-osobnich-udaju">zásadách zpracování osobních údajů</a>.',
            ],
            'documents' => [
                'title' => 'Dokumenty ke stažení',
                'items' => [
                    [
                        'name' => 'Smlouva o pronájmu',
                        'href' => '/dokumenty/smlouva-o-pronajmu',
                    ],
                    [
                        'name' => 'Předávací protokol',
                        'href' => '/dokumenty/predavaci-protokol',
                    ],
                    [
                        'name' => 'Obchodní podmínky',
                        'href' => '/dokumenty/obchodni-podminky',
                    ],
                    [
                        'name' => 'Zásady ochrany osobních údajů',
                        'href' => '/dokumenty/zasady-ochrany-osobnich-udaju',
                    ],
                    [
                        'name' => 'Protokol o poškození',
                        'href' => '/dokumenty/protokol-o-poskozeni',
                    ],
                ],
            ],
            'midcta' => [
                'title' => 'Souhlasíte s podmínkami? Rezervujte a jeďte.',
                'text' => 'Vyber motorku a rezervuj online.',
            ],
            'cta' => [
                'title' => 'Rezervuj motorku online',
                'text' => 'Vyber motorku a termín – cenu spočítáme hned.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT ONLINE',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                        'aria' => 'Přejít na online rezervaci motorky podle nájemní smlouvy Motogo24',
                    ],
                ],
            ],
            'seo' => [
                'title' => 'Podmínky půjčení motorky a dokumenty | MotoGo24',
                'description' => 'Obchodní podmínky, smlouva o pronájmu a protokoly ke stažení v PDF. Přehledně: doklady, platba, storno, pozdní vrácení a odpovědnost za škody.',
                'keywords' => 'motopůjčovna',
            ],
        ],
        'jak_pujcit_pristaveni' => [
            'h1' => 'Přistavení motocyklu – doručení až k tobě',
            'intro' => 'Chceš vyrazit bez zbytečného přesunu do půjčovny? Zajistíme <strong>přistavení motorky na domluvené místo</strong> – domů, do hotelu, k nádraží nebo na start tvého výletu. Motorku přivezeme kamkoliv v České republice – přímo z naší provozovny v Mezné u Pelhřimova. Přistavení nabízíme u motorek z obslužné pobočky v Mezné; motorky ze samoobslužné pobočky ve Velkých Němčicích se přebírají jen přímo na pobočce.',
            'when' => [
                'title' => 'Kdy se přistavení hodí',
                'items' => [
                    '<strong>Začátek&nbsp;roadtripu</strong>&nbsp;– motorku dovezeme přímo na start tvého výletu.',
                    '<strong>Hotel a penzion</strong>&nbsp;– doručení k ubytování, ať šetříš čas.',
                    '<strong>Nádraží/autobus</strong>&nbsp;– plynulý přesun bez čekání.',
                    '<strong>Firemní akce a dárky</strong>&nbsp;– překvapení pro partnery či tým.',
                ],
            ],
            'why' => [
                'title' => 'Proč využít přistavení motorky',
                'grid' => 'gr5',
                'items' => [
                    [
                        'icon' => 'gfx/vyzvednuti-vraceni-motorky.svg',
                        'title' => 'Flexibilita',
                        'text' => 'Motorku přivezeme, kam potřebuješ – domů, do hotelu, k nádraží nebo na start výletu.',
                    ],
                    [
                        'icon' => 'gfx/ico-pohodli.svg',
                        'title' => 'Pohodlí',
                        'text' => 'Nemusíš řešit dopravu do motopůjčovny – kde necháš auto nebo kdo tě přiveze.',
                    ],
                    [
                        'icon' => 'gfx/ico-nonstop.svg',
                        'title' => 'Nonstop provoz',
                        'text' => 'Přistavení domlouváme na předem sjednaný čas – klidně večer nebo o víkendu. Stačí zvolit čas v rezervaci.',
                    ],
                    [
                        'icon' => 'gfx/uspora-casu.svg',
                        'title' => 'Úspora času',
                        'text' => 'Čas ušetřený na cestě do půjčovny a zpět můžeš věnovat sobě.',
                    ],
                    [
                        'icon' => 'gfx/ico-vybava.svg',
                        'title' => 'Výbava s sebou',
                        'text' => 'Přivezeme i zapůjčenou výbavu v požadovaných velikostech rovnou k tobě.',
                    ],
                ],
            ],
            'process' => [
                'title' => 'Jak přistavení probíhá',
                'grid' => 'gr5',
                'steps' => [
                    [
                        'icon' => 'gfx/vyber-motorku.svg',
                        'title' => 'Vyber motorku',
                        'text' => 'Prohlédni si naši nabídku cestovních, supermoto, naked a dětských motorek a vyber si tu pravou.',
                    ],
                    [
                        'icon' => 'gfx/rezervace-online.svg',
                        'title' => 'Zvol termín',
                        'text' => 'V kalendáři vyber datum, kdy chceš vyjet. Uvidíš, které motorky jsou volné.',
                    ],
                    [
                        'icon' => 'gfx/kontaktni-udaje.svg',
                        'title' => 'Kontaktní údaje',
                        'text' => 'Vyplň jméno, adresu, e-mail a telefon.',
                    ],
                    [
                        'icon' => 'gfx/cas-prevzeti-motorky.svg',
                        'title' => 'Čas přistavení',
                        'text' => 'Zvol, kdy ti motorku přistavíme – klidně večer nebo o víkendu.',
                    ],
                    [
                        'icon' => 'gfx/vyzvednuti-vraceni-motorky.svg',
                        'title' => 'Místo přistavení',
                        'text' => 'Zadej adresu, kam motorku přivézt – domů, do hotelu, k nádraží nebo na start výletu.',
                    ],
                    [
                        'icon' => 'gfx/vyber-vybavu.svg',
                        'title' => 'Výbava',
                        'text' => 'Základní výbava řidiče je v ceně. Požadované velikosti pro všechny části výbavy uveď do pole Poznámka – povinné.',
                    ],
                    [
                        'icon' => 'gfx/zaplat.svg',
                        'title' => 'Potvrzení a platba',
                        'text' => 'Zkontroluj shrnutí objednávky, odsouhlas podmínky a zaplať online.',
                    ],
                    [
                        'icon' => 'gfx/podpis-dokumentu.svg',
                        'title' => 'Převzetí na místě',
                        'text' => 'Při předání zkontrolujeme doklady, doplníme smlouvu a podepíšeme předávací protokol.',
                    ],
                    [
                        'icon' => 'gfx/uzij-si-jizdu.svg',
                        'title' => 'Užij si jízdu',
                        'text' => 'Vyraz na cestu. Kdyby se cokoli stalo, jsme ti během výpůjčky nonstop k dispozici.',
                    ],
                    [
                        'icon' => 'gfx/predani-motorky.svg',
                        'title' => 'Vrácení motorky',
                        'text' => 'Motorku vrať včas na předem sjednané místo. Mýt ani tankovat ji nemusíš – jen ať nesvítí rezerva.',
                    ],
                ],
            ],
            'pricing' => [
                'title' => 'Ceník přistavení',
                'lead' => '<strong>Cena přistavení se skládá ze tří složek:</strong>',
                'items' => [
                    '<strong>500 Kč</strong>&nbsp;za naložení motorky,',
                    '<strong>500 Kč</strong>&nbsp;za vyložení motorky,',
                    '<strong>20 Kč</strong>&nbsp;za každý kilometr (počítá se vzdálenost z půjčovny na místo určení tam i zpět)',
                ],
                'example' => '<strong>Příklad:</strong>&nbsp;Chceš motorku přistavit 30 km od Mezné? Zaplatíš 500 + 500 + (30 × 2 × 20) =&nbsp;<strong>2 200 Kč.</strong>',
            ],
            'faq' => [
                'title' => 'Často kladené dotazy k přistavení',
                'items' => [
                    [
                        'q' => 'Jak dopředu objednat přistavení?',
                        'a' => 'Ideálně <strong>při</strong> <strong>online rezervaci</strong> – zadáš adresu a čas. U urgentních požadavků nás kontaktuj telefonicky.',
                    ],
                    [
                        'q' => 'Můžu vrátit motorku jinde než jsem ji převzal?',
                        'a' => 'Ano, účtujeme <strong>svoz</strong> dle vzdálenosti od Pelhřimova. Domluvíme při rezervaci.',
                    ],
                    [
                        'q' => 'Kolik stojí přistavení mimo Vysočinu?',
                        'a' => 'Řídíme se tabulkou vzdáleností. Nad 100 km cenu kalkulujeme <strong>individuálně</strong>.',
                    ],
                    [
                        'q' => 'Přistavíte i motorku z Velkých Němčic?',
                        'a' => 'Ne. Přistavení nabízíme jen u motorek z <strong>obslužné pobočky v Mezné u Pelhřimova</strong>; motorky ze samoobslužné pobočky ve Velkých Němčicích se přebírají i vracejí jen na pobočce.',
                    ],
                    [
                        'q' => 'Je v ceně i výbava řidiče?',
                        'a' => 'Ano. Helma, bunda, kalhoty a rukavice jsou pro řidiče&nbsp;<strong>v ceně výpůjčky</strong>.',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Objednej si přistavení',
                'text' => 'Přistavení si objednáš přímo v rezervaci – adresu a čas zadáš ve formuláři a cenu uvidíš hned.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT DORUČENÍ',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                        'aria' => 'Rezervovat doručení motorky na domluvené místo',
                    ],
                ],
            ],
            'seo' => [
                'title' => 'Přistavení motorky kamkoli v ČR – ceník | MotoGo24',
                'description' => 'Motorku z Mezné u Pelhřimova ti přivezeme domů, k hotelu nebo na nádraží kdekoli v ČR. Cena: 500 + 500 Kč a 20 Kč/km tam i zpět. Objednáš v rezervaci.',
                'keywords' => 'motopůjčovna',
            ],
        ],
        'jak_pujcit_vraceni_jinde' => [
            'h1' => 'Vrácení motorky kdekoliv – přijedeme za tebou',
            'intro' => 'Nechceš se vracet do půjčovny v Pelhřimově? Žádný problém. Přijedeme si pro motorku kamkoliv v České republice – v čas, který sis zvolil v rezervačním formuláři. Ty předáš, my naložíme. Jednoduše a bez komplikací. Odvoz z adresy nabízíme u motorek z obslužné pobočky v Mezné; motorky ze samoobslužné pobočky ve Velkých Němčicích se vracejí jen přímo na pobočce.',
            'when' => [
                'title' => 'Kdy se vrácení jinde hodí',
                'items' => [
                    '<strong>Konec roadtripu</strong>&nbsp;– výpůjčka začala v Pelhřimově, cesta končí jinde. Předej nám motorku tam, kde tvůj výlet skončí.',
                    '<strong>Jednosměrná cesta</strong>&nbsp;– cestuješ vlakem nebo autobusem zpátky domů? Motorku nám předej před odjezdem.',
                    '<strong>Hotel nebo penzion</strong>&nbsp;– předej nám motorku přímo u ubytování, ať nemusíš řešit cestu zpátky do půjčovny.',
                    '<strong>Firemní akce</strong>&nbsp;– pronájem pro skupinu s vrácením přímo na místě akce.',
                ],
            ],
            'why' => [
                'title' => 'Proč využít vrácení jinde',
                'grid' => 'gr5',
                'items' => [
                    [
                        'icon' => 'gfx/vyzvednuti-vraceni-motorky.svg',
                        'title' => 'Flexibilita',
                        'text' => 'Vybereš si místo vrácení podle své trasy – hotel, nádraží, parkoviště nebo kdekoliv jinde.',
                    ],
                    [
                        'icon' => 'gfx/uspora-casu.svg',
                        'title' => 'Úspora času',
                        'text' => 'Ušetříš cestu zpátky do půjčovny i domů – předáš motorku tam, kde jsi.',
                    ],
                    [
                        'icon' => 'gfx/ico-pohodli.svg',
                        'title' => 'Pohodlí',
                        'text' => 'Nemusíš řešit, jak se dostaneš z půjčovny domů.&nbsp;',
                    ],
                    [
                        'icon' => 'gfx/ico-nonstop.svg',
                        'title' => 'Nonstop provoz',
                        'text' => 'Vrácení domlouváme na předem sjednaný čas – klidně večer nebo o víkendu.',
                    ],
                    [
                        'icon' => 'gfx/predani-motorky.svg',
                        'title' => 'Jednoduchost',
                        'text' => 'Předáš klíče a výbavu, my zkontrolujeme motorku a odjedeme. Žádné papírování navíc.',
                    ],
                ],
            ],
            'process' => [
                'title' => 'Jak vrácení jinde probíhá',
                'grid' => 'gr5',
                'steps' => [
                    [
                        'icon' => 'gfx/uzij-si-jizdu.svg',
                        'title' => 'Zvol místo a čas vrácení',
                        'text' => 'V rezervačním formuláři zadej adresu a čas, kdy motorku předáš.',
                    ],
                    [
                        'icon' => 'gfx/vyber-vybavu.svg',
                        'title' => 'Připrav si výbavu',
                        'text' => 'Před předáním si nachystej výbavu, která byla součástí výpůjčky.',
                    ],
                    [
                        'icon' => 'gfx/cas-prevzeti-motorky.svg',
                        'title' => 'Přijedeme v domluvený čas',
                        'text' => 'Dorazíme na sjednané místo přesně v domluvený čas.',
                    ],
                    [
                        'icon' => 'gfx/prevezmi-motorku.svg',
                        'title' => 'Společně zkontrolujeme motorku a výbavu',
                        'text' => 'Zkontrolujeme stav motorky a výbavy, naložíme a odjedeme.&nbsp;',
                    ],
                    [
                        'icon' => 'gfx/sleva-na-pristi-jizdu.svg',
                        'title' => 'Na e-mail ti přijde potvrzení',
                        'text' => 'Potvrzení o ukončení nájmu, konečná faktura a slevový kód na další rezervaci.',
                    ],
                ],
            ],
            'pricing' => [
                'title' => 'Ceník vrácení jinde',
                'lead' => 'Cena se skládá ze tří složek:',
                'items' => [
                    '500 Kč za naložení motorky',
                    '500 Kč za vyložení motorky',
                    '20 Kč za každý kilometr (vzdálenost z místa vrácení do půjčovny tam i zpět)',
                ],
                'example_title' => 'Příklad:',
                'example_q' => 'Chceš motorku vrátit 30 km od půjčovny?',
                'example_a' => 'Zaplatíš 500 + 500 + (30 × 2 × 20) = 2 200 Kč.',
            ],
            'issues' => [
                'title' => 'Nesrovnalosti při vrácení',
                'lead' => 'Při vrácení společně zkontrolujeme stav motorky i výbavy. Pokud by nastala některá z níže uvedených situací, sepíšeme protokol o zjištěném poškození:',
                'items' => [
                    'chybějící výbava',
                    'poškozená výbava',
                    'poškozený motocykl',
                ],
                'closing' => 'Protokol zákazník podepíše a obdrží jeho kopii. Další postup se řídí podmínkami nájemní smlouvy a obchodními podmínkami.',
            ],
            'faq' => [
                'title' => 'Často kladené dotazy k vrácení motorky jinde',
                'items' => [
                    [
                        'q' => 'Do kdy musím motorku vrátit?',
                        'a' => 'Motorku vrať ideálně ve sjednaný čas. Pokud vracíš v místě půjčovny, můžeš ale přijet po dohodě kdykoli během posledního dne výpůjčky – nejpozději do půlnoci, bez jakýchkoli sankcí. Vracíš-li na jiném místě, je sjednaný čas závazný.',
                    ],
                    [
                        'q' => 'Musím vracet s plnou nádrží a čistou?',
                        'a' => 'Ne. Při vrácení jinde ji mýt ani tankovat nemusíš – jen ať nesvítí rezerva.&nbsp;',
                    ],
                    [
                        'q' => 'Můžu motorku při vrácení na jiném místě vrátit dřív, než jsme se domluvili?&nbsp;',
                        'a' => 'Na sjednané místo vyjíždíme z Pelhřimova přesně podle domluveného času, takže dřívější vrácení bohužel není možné. Pokud se ti plány změní, ozvi se nám – pokusíme se čas přizpůsobit, ale záleží na naší aktuální vytíženosti.',
                    ],
                    [
                        'q' => 'Můžu motorku vrátit opravdu kdekoliv v ČR?&nbsp;',
                        'a' => 'Ano, přijedeme si pro motorku kamkoliv v České republice. Místo vrácení zadáš při rezervaci – může to být hotel, parkoviště, nádraží nebo jakákoliv jiná adresa.',
                    ],
                    [
                        'q' => 'Jak daleko dopředu musím vrácení na jiném místě nahlásit?&nbsp;',
                        'a' => 'Místo a čas vrácení zadáváš už v rezervačním formuláři.&nbsp;',
                    ],
                    [
                        'q' => 'Co když se na místo vrácení zpozdím?&nbsp;',
                        'a' => 'Zavolej nám, jakmile víš, že to nestihneš. Když dáš vědět předem, většinou na tebe počkáme. Pokud se v domluvený čas bez ohlášení nedostavíš, můžeme podle obchodních podmínek (čl. 2 e) odjet a účtovat ti marnou cestu ve výši poplatku za vyzvednutí.',
                    ],
                    [
                        'q' => 'Jak se počítá cena za vrácení na jiném místě?&nbsp;',
                        'a' => 'Cena zahrnuje 500 Kč za naložení, 500 Kč za vyložení a 20 Kč za každý kilometr vzdálenosti z místa vrácení do půjčovny (tam i zpět). Například při vrácení 50 km od Pelhřimova zaplatíš 500 + 500 + (50 × 2 × 20) = 3 000 Kč.',
                    ],
                    [
                        'q' => 'Platím za vrácení jinde zvlášť, nebo je to součástí ceny pronájmu?&nbsp;',
                        'a' => 'Vrácení na jiném místě je doplňková služba a platí se zvlášť nad rámec ceny pronájmu.&nbsp;',
                    ],
                    [
                        'q' => 'Co když chci motorku vyzvednout v Pelhřimově, ale vrátit jinde – jde to?&nbsp;',
                        'a' => 'Ano, můžeš vyzvednout motorku u nás v Pelhřimově a vrátíš ji tam, kde potřebuješ.&nbsp;',
                    ],
                    [
                        'q' => 'Co mám mít připravené, když přijedete pro motorku?&nbsp;',
                        'a' => 'Měj připravené klíče a veškerou výbavu, která byla součástí výpůjčky. Společně zkontrolujeme stav motorky a výbavy.',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Máš dotaz k vrácení jinde?',
                'text' => 'Místo a čas vrácení zadáš přímo v rezervaci a cenu ti formulář spočítá hned. Když si nevíš rady, zavolej nám nebo napiš.',
                'buttons' => [
                    [
                        'label' => 'KONTAKT',
                        'href' => '/kontakt',
                        'cls' => 'btndark',
                        'aria' => 'Kontaktujte nás',
                    ],
                ],
            ],
            'seo' => [
                'title' => 'Vrácení motorky jinde – odvoz kdekoli v ČR | MotoGo24',
                'description' => 'Motorku z Mezné si vyzvedneme u hotelu, na nádraží i u tebe doma – kdekoli v ČR. Cena: 500 + 500 Kč a 20 Kč/km tam i zpět. Čas vrácení je závazný.',
                'keywords' => 'motopůjčovna',
            ],
        ],
        'jak_pujcit_postup' => [
            'h1' => 'Jak si půjčit motorku – postup krok za krokem',
            'intro_p1' => 'Motorku si u <strong>MotoGo24</strong> rezervuješ a zaplatíš online za pár minut – <strong>bez kauce a s výbavou pro řidiče v ceně</strong>. Tady je celý postup od výběru motorky po vrácení.',
            'intro_h2' => 'Kde si motorku vyzvedneš',
            'intro_p2' => 'V naší <strong>motopůjčovně </strong>zvládneš vše online: vyber motorku, zvol termín a vyplň rezervační formulář – včetně výbavy a způsobu předání. Motorku si vyzvedni v Mezné u Pelhřimova (odtud ti ji můžeme i přistavit kamkoliv v ČR), nebo samoobslužně ve Velkých Němčicích u Brna. Platbu provedeš online při dokončení rezervace.',
            'process' => [
                'title' => 'Jak probíhá pronájem krok za krokem',
                'grid' => 'gr4',
                'steps' => [
                    [
                        'icon' => 'gfx/vyber-motorku.svg',
                        'title' => '1. Vyber motorku',
                        'text' => 'Prohlédni si naši nabídku&nbsp;<strong>cestovních, supermoto, naked a dětských motorek</strong>&nbsp;a vyber si tu pravou.',
                    ],
                    [
                        'icon' => 'gfx/rezervace-online.svg',
                        'title' => '2. Zvol termín',
                        'text' => 'V kalendáři vyber datum, kdy chceš vyjet. Uvidíš, které motorky jsou volné.',
                    ],
                    [
                        'icon' => 'gfx/kontaktni-udaje.svg',
                        'title' => '3. Kontaktní údaje',
                        'text' => 'Vyplň jméno, adresu, e-mail a telefon.',
                    ],
                    [
                        'icon' => 'gfx/cas-prevzeti-motorky.svg',
                        'title' => '4. Čas převzetí',
                        'text' => 'Zvol, kdy si motorku vyzvedneš nebo kdy ji přistavíme.',
                    ],
                    [
                        'icon' => 'gfx/vyzvednuti-vraceni-motorky.svg',
                        'title' => '5. Zvol si předání',
                        'text' => 'Vyber místo převzetí – osobně v Mezné u Pelhřimova, samoobslužně ve Velkých Němčicích u Brna, nebo přistavení z Mezné kamkoliv v ČR.&nbsp;',
                    ],
                    [
                        'icon' => 'gfx/prevezmi-motorku.svg',
                        'title' => '6. Místo a čas vrácení',
                        'text' => 'Vyber, kde a kdy motorku vrátíš – na pobočce, nebo u motorek z Mezné i na jiné adrese v ČR. Ve Velkých Němčicích čas vrácení nevolíš: motorku vrátíš kdykoli poslední den do 24:00.',
                    ],
                    [
                        'icon' => 'gfx/vyber-vybavu.svg',
                        'title' => '7. Výbava',
                        'text' => 'Základní výbava řidiče je v ceně. Chceš výbavu pro spolujezdce, zapůjčit boty nebo jedeš s vlastní výbavou? Zaškrtneš při rezervaci.',
                    ],
                    [
                        'icon' => 'gfx/zaplat.svg',
                        'title' => '8. Shrnutí objednávky a platba',
                        'text' => 'Zkontroluj shrnutí objednávky, odsouhlas podmínky a zaplať online platební kartou.',
                    ],
                    [
                        'icon' => 'gfx/potvrzeni-rezervace.svg',
                        'title' => '9. Potvrzení e-mailem',
                        'text' => 'Po zaplacení ti přijde e-mail s potvrzením rezervace, dokladem o platbě, nájemní smlouvou a instrukcemi k vyzvednutí. U samoobslužné pobočky ve Velkých Němčicích dostaneš po ověření dokladů i přístupové kódy – v aplikaci, e-mailem a SMS.',
                    ],
                    [
                        'icon' => 'gfx/predani-motorky.svg',
                        'title' => '10. Převzetí motorky',
                        'text' => 'V Mezné ti motorku předáme osobně: zkontrolujeme doklady (pokud je nemáš ověřené online), převezmeš výbavu a podepíšeme předávací protokol. Ve Velkých Němčicích si motorku i výbavu vyzvedneš bez obsluhy pomocí kódů z aplikace – doklady musíš mít předem ověřené a protokol podepíšeš na displeji.',
                    ],
                    [
                        'icon' => 'gfx/uzij-si-jizdu.svg',
                        'title' => '11. Užij si jízdu',
                        'text' => 'Vyraz na cestu. Během výpůjčky jsme ti nonstop k dispozici, kdyby se cokoli stalo.',
                    ],
                    [
                        'icon' => 'gfx/vrat-motorku-vcas.svg',
                        'title' => '12. Vrácení motorky',
                        'text' => 'Motorku vrať včas – osobně na pobočku, kde sis ji půjčil (Mezná u Pelhřimova, nebo samoobslužné Velké Němčice u Brna), u motorek z Mezné i na předem sjednané místo. Tankovat nemusíš – jen ať nesvítí rezerva. Umytou ji vracej jen na samoobslužné pobočce ve Velkých Němčicích.',
                    ],
                ],
            ],
            'faq' => [
                'title' => 'Často kladené otázky',
                'items' => [
                    [
                        'q' => 'Je nutná kauce při půjčení?',
                        'a' => 'Ne.&nbsp;<strong>Půjčujeme bez kauce</strong>&nbsp;– férově a bez zbytečných překážek.',
                    ],
                    [
                        'q' => 'Je v ceně půjčovného i výbava?',
                        'a' => 'Ano. Každý řidič dostane&nbsp;<strong>helmu, bundu, kalhoty a rukavice zdarma</strong>.',
                    ],
                    [
                        'q' => 'Kde si mohu motorku převzít?',
                        'a' => 'Na obslužné pobočce v Mezné u Pelhřimova (odtud nabízíme i&nbsp;<strong>přistavení motorky</strong>&nbsp;na tebou zvolené místo), nebo samoobslužně na pobočce ve Velkých Němčicích u Brna.',
                    ],
                    [
                        'q' => 'Do kdy musím motorku vrátit?',
                        'a' => 'Motorku můžeš vrátit kdykoli během posledního dne výpůjčky – klidně i o půlnoci.',
                    ],
                ],
                'more_link' => [
                    'label' => 'Další často kladené otázky',
                    'href' => '/jak-pujcit/faq',
                    'aria' => 'Přečti si další často pokládané otázky',
                ],
            ],
            'cta' => [
                'title' => 'Sedni na motorku!',
                'text' => 'Rezervuj si motorku online ještě dnes a užij si <strong>svobodu na dvou kolech</strong> – jednoduše a bez zbytečných podmínek.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT ONLINE',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                        'aria' => 'Rezervovat motorku online',
                    ],
                ],
            ],
            'seo' => [
                'title' => 'Jak si půjčit motorku – postup krok za krokem | MotoGo24',
                'description' => 'Jak si půjčit motorku u MotoGo24: vyber motorku a termín, zaplať online a vyzvedni ji u Pelhřimova, nebo samoobslužně u Brna. Bez kauce, výbava v ceně.',
                'keywords' => 'motopůjčovna',
            ],
        ],
        'jak_pujcit_vyzvednuti' => [
            'h1' => 'Převzetí motorky v půjčovně: jak předání probíhá',
            'intro' => 'Převzetí motorky trvá pár minut. V <strong>Mezné u Pelhřimova</strong> ti ji předáme osobně v čase, který sis zvolil/a v rezervaci – spolu projdeme motorku, výbavu i předávací protokol. Na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong> si motorku i výbavu vyzvedneš bez obsluhy pomocí kódů z aplikace.',
            'top_cta' => [
                'label' => 'REZERVOVAT ONLINE',
                'href' => '/rezervace',
                'aria' => 'Přejít na online rezervaci motorky v půjčovně Motogo24',
            ],
            'place' => [
                'title' => 'Kde probíhá převzetí motocyklu',
                'address_label' => 'Provozovna:',
                'address' => 'Mezná 9, 393 01 <strong>Pelhřimov</strong> (Vysočina)',
                'hours_label' => 'Provozní doba:',
                'hours' => 'PO–NE <em>nonstop</em>, včetně víkendů a svátků – čas převzetí si zvolíš v rezervaci, vrátit můžeš kdykoli poslední den výpůjčky do 24:00',
                'map_src' => 'https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d53928.274636159236!2d15.154130970132716!3d49.35168867371007!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x470ce75bf69a97b3%3A0xe75f9d3fadf02b5b!2zTWV6bsOhIDksIDM5MyAwMSBNZXpuw6E!5e0!3m2!1scs!2scz!4v1759860051295!5m2!1scs!2scz',
                'map_title' => 'Jak se k nám dostanete',
            ],
            'process' => [
                'title' => 'Jak probíhá převzetí v motopůjčovně',
                'grid' => 'gr4',
                'steps' => [
                    [
                        'icon' => 'gfx/cas-prevzeti-motorky.svg',
                        'title' => 'Přijď v domluvený čas',
                        'text' => 'Na naši adresu: Mezná 9, 393 01 Pelhřimov.',
                    ],
                    [
                        'icon' => 'gfx/overime-doklady.svg',
                        'title' => 'Ověříme doklady',
                        'text' => 'OP/pas a řidičský průkaz odpovídající skupiny',
                    ],
                    [
                        'icon' => 'gfx/doplnime-smlouvu.svg',
                        'title' => 'Doplníme smlouvu',
                        'text' => 'Předvyplněnou nájemní smlouvu doplníme o údaje z dokladů.',
                    ],
                    [
                        'icon' => 'gfx/vyber-vybavu.svg',
                        'title' => 'Vybereš a vyzkoušíš si výbavu',
                        'text' => 'Výbavu z rezervace si můžeš vyzkoušet v naší zkušební kabince.',
                    ],
                    [
                        'icon' => 'gfx/prevezmi-motorku.svg',
                        'title' => 'Společně projdeme motorku',
                        'text' => 'Zkontrolujeme stav stroje a seznámíš se s jeho ovládáním.',
                    ],
                    [
                        'icon' => 'gfx/podpis-dokumentu.svg',
                        'title' => 'Podepíšeme předávací protokol',
                        'text' => 'Zdokumentujeme stav motorky a výbavy před výpůjčkou.',
                    ],
                    [
                        'icon' => 'gfx/predani-motorky.svg',
                        'title' => 'Předáme klíče',
                        'text' => 'Motorka je připravená a čeká na tebe.',
                    ],
                    [
                        'icon' => 'gfx/uzij-si-jizdu.svg',
                        'title' => 'Můžeš vyrazit',
                        'text' => 'Vyraz na cestu. Kdyby se během výpůjčky cokoli stalo, jsme ti nonstop k dispozici.',
                    ],
                ],
            ],
            'amenities' => [
                'title' => 'Co najdeš v půjčovně',
                'lead' => 'Pro pohodlné převzetí máme připraveno – vše zdarma:',
                'items' => [
                    'parkoviště pro zákazníky (kapacita je omezená)',
                    'Wi-Fi',
                    'WC',
                    'zkušební kabinku na vyzkoušení výbavy',
                    'uzamykatelné skříňky na úschovu osobních věcí, které nechceš brát na cestu (kapacita omezená)',
                ],
                'cta' => [
                    'label' => 'ZAREZERVOVAT TERMÍN',
                    'href' => '/rezervace',
                    'aria' => 'Zarezervovat termín vyzvednutí motorky v Motogo24',
                ],
            ],
            'bring' => [
                'title' => 'Co si vzít s sebou',
                'items' => [
                    'platný občanský průkaz nebo pas',
                    'platný řidičský průkaz skupiny, kterou motorka vyžaduje (A, A2, u skútrů A1 nebo B – najdeš ji u motorky v katalogu)',
                    'vlastní výbavu – helmu, bundu, kalhoty, rukavice (pokud je nemáš zarezervované u nás)',
                    'pevnou obuv (pokud u nás nemáš rezervaci na motocyklové boty)',
                    'vlastní navigaci nebo telefon s navigační aplikací – navigace není součástí výpůjčky',
                ],
            ],
            'faq' => [
                'title' => 'Časté dotazy k vyzvednutí',
                'items' => [
                    [
                        'q' => 'Musím platit kauci při vyzvednutí?',
                        'a' => 'Ne, <strong>půjčujeme bez kauce</strong>. Podmínky jsou jasně dané a férové.',
                    ],
                    [
                        'q' => 'Můžu si motorku převzít bez obsluhy?',
                        'a' => 'Ano, na <strong>samoobslužné pobočce ve Velkých Němčicích u Brna</strong>. Motorku i výbavu si tam vyzvedneš pomocí kódů z aplikace a předávací protokol podepíšeš na displeji – doklady musíš mít předem nahrané a ověřené online. V Mezné u Pelhřimova ti motorku předáme vždy osobně.',
                    ],
                    [
                        'q' => 'Co když nestíhám domluvený čas?',
                        'a' => 'Dej nám vědět telefonicky – přizpůsobíme čas, nebo nabídneme <strong>přistavení</strong> / jiný termín.',
                    ],
                    [
                        'q' => 'Je v ceně i výbava pro spolujezdce?',
                        'a' => 'Výbava pro řidiče je v ceně vždy. Výbavu pro spolujezdce lze přiobjednat jako <strong>nadstandard</strong>.',
                    ],
                ],
            ],
            'mid_cta' => [
                'label' => 'REZERVOVAT VYZVEDNUTÍ',
                'href' => '/rezervace',
                'aria' => 'Rezervovat vyzvednutí motorky v půjčovně Motogo24',
            ],
            'cta' => [
                'title' => 'Rezervuj si motorku i čas převzetí',
                'text' => 'Čas převzetí si zvolíš v rezervaci – i večer, o víkendu nebo ve svátek.',
                'text2' => 'Vyber motorku a rezervuj online.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT ONLINE',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                        'aria' => 'Přejít na online rezervaci a domluvit vyzvednutí motorky',
                    ],
                ],
            ],
            'seo' => [
                'title' => 'Převzetí motorky v půjčovně – co si vzít | MotoGo24',
                'description' => 'Jak probíhá převzetí motorky: osobně v Mezné u Pelhřimova, nebo samoobslužně u Brna kódem z aplikace. Jaké doklady si vzít a co tě čeká na místě.',
                'keywords' => 'motopůjčovna',
            ],
        ],
        'jak_pujcit_vraceni_pujcovna' => [
            'h1' => 'Vrácení motocyklu v půjčovně – rychle a bez komplikací',
            'intro' => 'Motorku vrátíš na pobočku, kde sis ji půjčil/a, kdykoli poslední den výpůjčky do 24:00. Tankovat nemusíš – jen ať nesvítí rezerva. V Mezné u Pelhřimova ji nemusíš ani mýt; ve Velkých Němčicích u Brna ji vrať umytou do kóje a výbavu do šatny – pomocí kódů z aplikace.',
            'process' => [
                'grid' => 'gr4',
                'steps' => [
                    [
                        'icon' => 'gfx/cas-prevzeti-motorky.svg',
                        'title' => 'Přijeď poslední den výpůjčky do 24:00',
                        'text' => '',
                    ],
                    [
                        'icon' => 'gfx/predani-motorky.svg',
                        'title' => 'Předej klíče a výbavu',
                        'text' => '',
                    ],
                    [
                        'icon' => 'gfx/prevezmi-motorku.svg',
                        'title' => 'Společně zkontrolujeme stav motorky a výbavy',
                        'text' => '',
                    ],
                    [
                        'icon' => 'gfx/sleva-na-pristi-jizdu.svg',
                        'title' => 'Potvrzení, fakturu a slevový kód dostaneš e-mailem',
                        'text' => '',
                    ],
                ],
            ],
            'time' => [
                'title' => 'Čas vrácení',
                'text' => 'Motorku vrať kdykoli poslední den výpůjčky do 24:00 – čas vrácení uvedený v rezervaci je jen orientační. Když víš, že to do půlnoci nestihneš, zavolej nám, nebo si výpůjčku prodluž v sekci Upravit rezervaci či v aplikaci MotoGo24 (pokud je motorka volná). Za každý další započatý den, kdy máš motorku u sebe, platíš nájemné za den navíc.',
            ],
            'issues' => [
                'title' => 'Nesrovnalosti při vrácení',
                'lead' => 'Při převzetí společně zkontrolujeme stav motorky a výbavy. Pokud by nastala některá z níže uvedených situací, sepíšeme protokol o zjištěném poškození:',
                'items' => [
                    'chybějící výbava',
                    'poškozená výbava',
                    'poškozený motocykl',
                ],
                'closing' => 'Protokol zákazník podepíše a obdrží jeho kopii. Další postup se řídí podmínkami nájemní smlouvy a obchodními podmínkami.',
            ],
            'faq' => [
                'title' => 'Často kladené dotazy k vrácení motocyklu v půjčovně',
                'items' => [
                    [
                        'q' => 'Do kdy musím motorku vrátit?',
                        'a' => 'Motorku vrať ideálně ve sjednaný čas. Pokud vracíš v místě půjčovny, můžeš ale přijet po dohodě kdykoli během posledního dne výpůjčky – nejpozději do půlnoci, bez jakýchkoli sankcí. Vracíš-li na jiném místě, je sjednaný čas závazný.',
                    ],
                    [
                        'q' => 'Musím vracet s plnou nádrží a čistou?',
                        'a' => 'Ne. Tankovat při vrácení nemusíš – jen ať nesvítí rezerva. Umytou ji vracej jen na samoobslužné pobočce ve Velkých Němčicích.&nbsp;',
                    ],
                    [
                        'q' => 'Můžu motorku vrátit do půjčovny dřív, než jsme se domluvili?',
                        'a' => 'Ano, motorku můžeš vrátit kdykoliv během posledního dne výpůjčky. Stačí nám dát vědět, že dorazíš dřív. Žádné příplatky za dřívější vrácení neúčtujeme.',
                    ],
                    [
                        'q' => 'Co se stane, když nestihnu motorku do půjčovny vrátit do půlnoci posledního dne?&nbsp;',
                        'a' => 'Pokud víš, že nestihneš, ozvi se nám co nejdřív. Domluvíme se na řešení. V případě neoznámeného pozdního vrácení se postupuje podle podmínek nájemní smlouvy.',
                    ],
                    [
                        'q' => 'Musím při vrácení v půjčovně něco podepsat?&nbsp;',
                        'a' => 'Pokud je vše v pořádku, vrácení proběhne rychle a bez zbytečného papírování. Potvrzení o ukončení nájmu a konečnou fakturu dostaneš na e-mail.',
                    ],
                    [
                        'q' => 'Jak probíhá kontrola motorky při vrácení v půjčovně?&nbsp;',
                        'a' => 'Společně projdeme stav motorky a výbavy. Pokud je vše v pořádku, převezmeme klíče a výbavu a ty můžeš jít. Celé to zabere pár minut.',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Máš dotaz k vrácení?',
                'text' => 'Zavolej nám nebo napiš – rádi ti poradíme.',
                'buttons' => [
                    [
                        'label' => 'KONTAKT',
                        'href' => '/kontakt',
                        'cls' => 'btndark',
                        'aria' => 'Kontaktujte nás',
                    ],
                ],
            ],
            'seo' => [
                'title' => 'Vrácení motorky v půjčovně – do 24:00 | MotoGo24',
                'description' => 'Motorku vrátíš kdykoli poslední den výpůjčky do 24:00. Tankovat nemusíš, jen ať nesvítí rezerva; u Brna ji vrať umytou. Jak probíhá kontrola při vrácení.',
                'keywords' => 'motopůjčovna',
            ],
        ],
        'home' => [
            'seo' => [
                'title' => 'Motopůjčovna a půjčovna motorek na Vysočině | MotoGo24',
                'description' => 'Motopůjčovna na Vysočině – půjčte si motorku bez kauce, s výbavou v ceně a nonstop provozem. Cestovní, sportovní, enduro i dětské motorky. Online rezervace.',
                'keywords' => 'motopůjčovna, motopůjčovna Vysočina, motopůjčovna Pelhřimov, půjčovna motorek, půjčovna motorek Vysočina, půjčit motorku, pronájem motorky, půjčovna motocyklů, motorka bez kauce, nonstop motopůjčovna, online rezervace motorky, cestovní motorky, enduro motorky, dětské motorky, MotoGo24',
                'og_image' => NULL,
            ],
            'hero' => [
                'image' => 'gfx/hero-banner.jpg',
                'alt' => 'Motopůjčovna a půjčovna motorek Vysočina',
                'eyebrow' => '<strong>Motopůjčovna</strong> a <strong>půjčovna motorek</strong> na Vysočině',
                'body' => 'Půjč si motorku na Vysočině snadno online.<br>Vyber si z cestovních, sportovních i enduro modelů.<br>Rezervace s platbou kartou a rychlým převzetím.',
                'cta_primary' => [
                    'label' => 'VYBER SI MOTORKU',
                    'href' => '/katalog',
                    'cls' => 'btngreen',
                ],
                'cta_secondary' => [
                    'label' => 'REZERVACE',
                    'href' => '/rezervace',
                    'cls' => 'btndark',
                ],
            ],
            'h1' => 'Motopůjčovna Vysočina Motogo24 – půjčovna motorek bez kauce a nonstop',
            'intro' => 'Vítejte v <strong>Motogo24</strong> – vaší <strong>motopůjčovně</strong> a půjčovně motorek na Vysočině. U nás si půjčíte motorku <strong>bez kauce</strong>, s výbavou v ceně a v režimu <strong>nonstop</strong>. Ať hledáte cestovní, sportovní, enduro nebo dětskou motorku, Motogo24 vám v srdci Vysočiny nabídne motorku na míru.',
            'signposts_title' => 'Rychlý rozcestník po Motogo24',
            'signposts' => [
                [
                    'icon' => 'gfx/vyber-motorku.svg',
                    'title' => 'Katalog motorek',
                    'text' => 'Prohlédněte si naši nabídku motorek na pronájem – od sportovních po cestovní modely.',
                    'btn' => 'KATALOG MOTOREK',
                    'href' => '/katalog',
                ],
                [
                    'icon' => 'gfx/potvrzeni-rezervace.svg',
                    'title' => 'Jak si půjčit motorku',
                    'text' => 'Jednoduchý proces: vyberte motorku k zapůjčení, rezervujte a vyjeďte.',
                    'btn' => 'JAK SI PŮJČIT MOTORKU',
                    'href' => '/jak-pujcit',
                ],
                [
                    'icon' => 'gfx/rezervace-online.svg',
                    'title' => 'Online rezervace motorky',
                    'text' => 'Zarezervujte si motorku na pronájem přes snadný online systém.',
                    'btn' => 'REZERVOVAT MOTORKU',
                    'href' => '/rezervace',
                ],
                [
                    'icon' => 'gfx/kontakt.svg',
                    'title' => 'Kontakty a mapa',
                    'text' => 'Navštivte nás v Mezné u Pelhřimova nebo na samoobslužné pobočce ve Velkých Němčicích u Brna – případně nás kontaktujte.',
                    'btn' => 'KONTAKT',
                    'href' => '/kontakt',
                ],
                [
                    'icon' => 'gfx/faq.svg',
                    'title' => 'Často kladené dotazy',
                    'text' => 'Nejčastější dotazy k půjčení motorky přehledně na jednom místě.',
                    'btn' => 'ČASTÉ DOTAZY',
                    'href' => '/jak-pujcit/faq',
                ],
                [
                    'icon' => 'gfx/uzij-si-jizdu.svg',
                    'title' => 'Motocyklové výlety',
                    'text' => 'Objevte nejlepší motocyklové trasy v Česku pro turisty i místní.',
                    'btn' => 'MOTOCYKLOVÉ TRASY',
                    'href' => '/blog',
                ],
            ],
            'motos_section' => [
                'title' => 'Naše motorky k pronájmu na Vysočině',
                'intro' => 'Prohlédněte si nabídku cestovních, sportovních a enduro z naší půjčovny motorek na Vysočině.',
                'empty' => 'Momentálně nemáme žádné motorky v nabídce.',
                'cta_label' => 'KATALOG MOTOREK',
                'cta_href' => '/katalog',
                'limit' => 4,
            ],
            'process' => [
                'title' => 'Jak probíhá půjčení motorky na Vysočině',
                'steps' => [
                    [
                        'icon' => 'gfx/vyber-motorku.svg',
                        'title' => '1. Vyber',
                        'text' => 'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.',
                    ],
                    [
                        'icon' => 'gfx/rezervace-online.svg',
                        'title' => '2. Rezervuj',
                        'text' => 'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.',
                    ],
                    [
                        'icon' => 'gfx/predani-motorky.svg',
                        'title' => '3. Převzetí',
                        'text' => 'Převezměte si motorku osobně v Mezné u Pelhřimova (odtud ji můžeme i přistavit kamkoli v ČR), nebo si ji vyzvedněte sami na samoobslužné pobočce ve Velkých Němčicích u Brna.',
                    ],
                    [
                        'icon' => 'gfx/uzij-si-jizdu.svg',
                        'title' => '4. Užij jízdu',
                        'text' => 'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.',
                    ],
                ],
            ],
            'faq' => [
                'title' => 'Často kladené otázky',
                'more_link' => '/jak-pujcit/faq',
                'items' => [],
            ],
            'cta' => [
                'title' => 'Rezervuj svou motorku online',
                'text' => 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená nonstop. Stačí pár kliků a tvoje jízda začíná.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT MOTORKU',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                    ],
                    [
                        'label' => 'Dárkový poukaz',
                        'href' => '/poukazy',
                        'cls' => 'btndark',
                    ],
                    [
                        'label' => 'Tipy na trasy',
                        'href' => '/blog',
                        'cls' => 'btndark',
                    ],
                ],
            ],
            'blog' => [
                'title' => 'Blog a tipy',
                'empty' => 'Zatím nemáme žádné články.',
                'cta_label' => 'ČÍST VÍCE V BLOGU',
                'cta_href' => '/blog',
                'limit' => 3,
            ],
            'reviews' => [
                'title' => 'Co o nás říkají zákazníci',
                'intro' => 'Reálné recenze od motorkářů, kteří si u nás půjčili. Děkujeme za každé hodnocení.',
            ],
        ],
        'pujcovna' => [
            'seo' => [
                'title' => 'Motopůjčovna na Vysočině – o naší půjčovně motorek | MotoGo24',
                'description' => 'Motopůjčovna a půjčovna motorek Motogo24 na Vysočině. Bez kauce, s online rezervací a výbavou v ceně. Cestovní, sportovní, enduro i dětské motorky. Nonstop provoz.',
                'keywords' => 'motopůjčovna, motopůjčovna Vysočina, motopůjčovna Pelhřimov, půjčovna motorek, půjčovna motorek Vysočina, pronájem motorek, půjčovna motocyklů, motorka bez kauce, nonstop motopůjčovna, MotoGo24',
            ],
            'breadcrumb' => [
                [
                    'label' => 'Domů',
                    'href' => '/',
                ],
                'Půjčovna motorek',
            ],
            'intro' => [
                'h1' => 'Motopůjčovna a půjčovna motorek Vysočina Motogo24',
                'body' => 'Naše <strong>motopůjčovna</strong> a <strong>půjčovna motorek Vysočina</strong> v Pelhřimově nabízí <strong>pronájem motorek</strong> bez zbytečných překážek – <strong>bez kauce</strong>, s <strong>online rezervací</strong> a <strong>výbavou v ceně</strong>. Vyberete si z <strong>cestovních</strong>, <strong>sportovních</strong>, <strong>enduro</strong> i <strong>dětských motorek</strong>, a vyrazíte kdykoli: máme otevřeno <strong>nonstop</strong>.',
            ],
            'benefits' => [
                'title' => 'Proč si půjčit motorku u nás',
                'closing' => 'Hledáte <strong>půjčovnu motorek na Vysočině</strong>? Motogo24 – <strong>půjčovna motorek na Vysočině</strong> – nabízí férové podmínky, jasný postup a špičkově udržované stroje pro výlety po ČR i do zahraničí.',
                'buttons' => [
                    [
                        'label' => 'Zobrazit motorky k pronájmu',
                        'href' => '/katalog',
                        'cls' => 'btngreen',
                    ],
                    [
                        'label' => 'REZERVOVAT',
                        'href' => '/rezervace',
                        'cls' => 'btngreen pulse',
                    ],
                ],
                'items' => [
                    [
                        'icon' => 'gfx/ico-bez-kauce.svg',
                        'title' => 'Bez kauce',
                        'text' => 'a bez skrytých poplatků',
                    ],
                    [
                        'icon' => 'gfx/rezervace-online.svg',
                        'title' => 'Online rezervace',
                        'text' => 'na pár kliknutí',
                    ],
                    [
                        'icon' => 'gfx/vyber-vybavu.svg',
                        'title' => 'Výbava pro řidiče v ceně',
                        'text' => 'helma, bunda, kalhoty a rukavice',
                    ],
                    [
                        'icon' => 'gfx/ico-nonstop.svg',
                        'title' => 'Nonstop provoz',
                        'text' => 'pro vyzvednutí i vrácení dle rezervace',
                    ],
                    [
                        'icon' => 'gfx/ico-spolecne.svg',
                        'title' => 'Jsme v tom společně',
                        'text' => 'když se něco přihodí',
                    ],
                    [
                        'icon' => 'gfx/predani-motorky.svg',
                        'title' => 'Přistavení i vrácení motorky',
                        'text' => 'na domluvené místo',
                    ],
                ],
            ],
            'process' => [
                'title' => 'Jak probíhá půjčení motorky na Vysočině',
                'steps' => [
                    [
                        'icon' => 'gfx/vyber-motorku.svg',
                        'title' => '1. Vyber motorku',
                        'text' => 'Prohlédni si naši nabídku, vyber si typ, který ti vyhovuje, odpovídá tvým zkušenostem a řidičskému oprávnění.',
                    ],
                    [
                        'icon' => 'gfx/rezervace-online.svg',
                        'title' => '2. Rezervuj online',
                        'text' => 'Uskutečni rezervaci podle data nebo podle konkrétní motorky, kterou si chceš půjčit.',
                    ],
                    [
                        'icon' => 'gfx/vyber-vybavu.svg',
                        'title' => '3. Vyber výbavu',
                        'text' => 'Výbava pro řidiče je v ceně, pro spolujezdce za příplatek. Velikost vybereš při rezervaci — výbavu stačí zaškrtnout.',
                    ],
                    [
                        'icon' => 'gfx/zaplat.svg',
                        'title' => '4. Zaplať',
                        'text' => 'Zaplať jednoduše online prostřednictvím platební brány.',
                    ],
                    [
                        'icon' => 'gfx/predani-motorky.svg',
                        'title' => '5. Převezmi motorku',
                        'text' => 'Motorku si vyzvedni přímo v půjčovně, nebo na místě, které jsi zvolil při rezervaci.',
                    ],
                    [
                        'icon' => 'gfx/uzij-si-jizdu.svg',
                        'title' => '6. Užij si jízdu',
                        'text' => 'Vyraz na cestu, objevuj nové zážitky a užij si naplno svobodu na dvou kolech.',
                    ],
                    [
                        'icon' => 'gfx/vrat-motorku-vcas.svg',
                        'title' => '7. Vrať motorku',
                        'text' => 'Motorku jednoduše vrať ve sjednaný den – přímo v půjčovně, nebo na předem domluveném místě.',
                    ],
                    [
                        'icon' => 'gfx/sleva-na-pristi-jizdu.svg',
                        'title' => 'Sleva na příští jízdu',
                        'text' => 'Po vrácení motorky ti automaticky zašleme slevový kód 200 Kč na další rezervaci.',
                    ],
                ],
            ],
            'faq' => [
                'title' => 'Často kladené otázky',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    [
                        'q' => 'Jak si mohu rezervovat motorku?',
                        'a' => 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu nebo v aplikaci MotoGo24, která je zdarma na Google Play (Android) i v App Store (iPhone). Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.',
                    ],
                    [
                        'q' => 'Můžu si motorku půjčit i bez předchozí rezervace?',
                        'a' => 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit.',
                    ],
                    [
                        'q' => 'Musím složit kauci?',
                        'a' => 'Ne! U nás <strong>žádnou kauci platit nemusíš</strong>. Naše půjčovna se tímto zásadně liší od většiny konkurence.',
                    ],
                    [
                        'q' => 'Můžu odcestovat s motorkou do zahraničí?',
                        'a' => 'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Rezervuj svou motorku online',
                'text' => 'Naše <strong>půjčovna motorek Vysočina</strong> je otevřená <strong>nonstop</strong>. Stačí pár kliků a tvoje jízda začíná.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT MOTORKU',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                    ],
                    [
                        'label' => 'Dárkový poukaz',
                        'href' => '/poukazy',
                        'cls' => 'btndark',
                    ],
                    [
                        'label' => 'Tipy na trasy',
                        'href' => '/blog',
                        'cls' => 'btndark',
                    ],
                ],
            ],
        ],
        'kontakt' => [
            'seo' => [
                'title' => 'Kontakt | MotoGo24 – motopůjčovna a půjčovna motorek Vysočina',
                'description' => 'Motopůjčovna a půjčovna motorek MotoGo24 Pelhřimov — telefon +420 774 256 271, e-mail info@motogo24.cz. Nonstop, bez kauce.',
                'keywords' => 'motopůjčovna, motopůjčovna Pelhřimov, půjčovna motorek, půjčovna motorek Vysočina, kontakt MotoGo24, pronájem motorky Pelhřimov',
            ],
            'h1' => 'Kontakty půjčovna motorek Motogo24',
            'intro' => 'Máte dotaz k <strong>půjčení motorky</strong>, chcete si objednat <strong>dárkový poukaz</strong>, poradit s výběrem nebo si rovnou <strong>domluvit rezervaci</strong>? Jsme tu pro vás každý den, <strong>nonstop</strong>.',
            'quick' => [
                [
                    'label' => 'ZAVOLEJTE NÁM',
                    'value' => '+420 774 256 271',
                    'href' => 'tel:+420774256271',
                    'icon' => 'gfx/telefon.svg',
                    'alt' => 'Telefon',
                ],
                [
                    'label' => 'NAPIŠTE NÁM',
                    'value' => 'info@motogo24.cz',
                    'href' => 'mailto:info@motogo24.cz',
                    'icon' => 'gfx/email.svg',
                    'alt' => 'E-mail',
                ],
                [
                    'label' => 'DATOVÁ SCHRÁNKA',
                    'value' => '2xfihrd',
                    'href' => NULL,
                    'icon' => NULL,
                    'alt' => NULL,
                ],
            ],
            'place' => [
                'title' => 'Provozovna',
                'address_label' => 'Adresa:',
                'address' => 'Mezná 9, 393 01 Pelhřimov',
                'hours_label' => 'Provozní doba:',
                'hours' => 'PO – NE: 00:00 – 24:00 (výdej a příjem motorek dle rezervace), včetně víkendů a svátků<br>Telefon: PO – PÁ 8:00 – 17:00',
                'billing_title' => 'Fakturační údaje',
                'billing_name' => 'MotoGo24 s.r.o.',
                'billing_address' => 'Mezná 9, 393 01 Mezná',
                'billing_ico' => '29909864',
                'billing_vat' => 'Nejsme plátci DPH.',
                'billing_note' => 'Společnost je zapsána v obchodním rejstříku vedeném Krajským soudem v Českých Budějovicích, oddíl C, vložka 36876.',
            ],
            'social_title' => 'Sledujte nás',
            'social' => [
                [
                    'label' => 'facebook',
                    'href' => '#',
                    'icon' => 'gfx/facebook.svg',
                    'alt' => 'Facebook',
                ],
                [
                    'label' => 'instagram',
                    'href' => '#',
                    'icon' => 'gfx/instagram.svg',
                    'alt' => 'Instagram',
                ],
                [
                    'label' => 'tiktok',
                    'href' => '#',
                    'icon' => 'gfx/tiktok.svg',
                    'alt' => 'TikTok',
                ],
                [
                    'label' => 'youtube',
                    'href' => '#',
                    'icon' => 'gfx/youtube.svg',
                    'alt' => 'YouTube',
                ],
            ],
            'side_cta' => [
                'title' => 'Chcete si domluvit rezervaci?',
                'text' => 'Rezervujte si motorku online během pár minut a vyražte za dobrodružstvím.',
                'button' => [
                    'label' => 'REZERVOVAT ONLINE',
                    'href' => '/rezervace',
                    'cls' => 'btndark',
                ],
            ],
            'map' => [
                'title' => 'Kde nás najdete',
                'src' => 'https://www.google.com/maps?q=Mezn%C3%A1+9%2C+393+01+Pelh%C5%99imov&hl=cs&z=15&output=embed',
            ],
            'seo_text' => [
                'title' => 'Kontakty – půjčovna motorek Vysočina (Pelhřimov)',
                'body' => 'Motogo24 je <strong>moderní půjčovna motorek na Vysočině</strong>. Sídlíme v <strong>Pelhřimově</strong>, jsme otevřeni <strong>nonstop</strong> a půjčujeme <strong>bez kauce</strong>, s kompletní <strong>výbavou v ceně</strong>.',
            ],
            'outro' => [
                'title' => 'Proč si zákazníci vybírají MotoGo24',
                'body1' => 'Naše půjčovna motorek funguje na Vysočině od roku 2024 a za tu dobu jsme přivítali stovky spokojených zákazníků — místní i turisty, začátečníky i zkušené jezdce. Půjčujeme bez kauce, výbavu pro řidiče (helma, bunda, kalhoty a rukavice) máte vždy v ceně a vyzvednutí motorky si můžete domluvit i mimo standardní otevírací dobu díky našemu nonstop provozu.',
                'body2' => 'Pokud cestujete s motorkou do zahraničí, dostanete od nás zelenou kartu a všechny potřebné dokumenty. Při neočekávaných situacích na cestě máme k dispozici SOS linku a do 24 hodin zařídíme náhradní motorku. Ozvěte se nám telefonicky, e-mailem nebo přes sociální sítě — odpovíme zpravidla do hodiny a rádi pomůžeme s výběrem motorky, plánováním trasy i s dárkovým poukazem.',
            ],
        ],
        'poukazy' => [
            'seo' => [
                'title' => 'Dárkové poukazy | Motopůjčovna a půjčovna motorek Vysočina',
                'description' => 'Kupte dárkový poukaz na pronájem motorky v motopůjčovně MotoGo24. Platnost 3 roky, bez kauce, výbava v ceně. Elektronický i tištěný poukaz. Online objednávka.',
                'keywords' => 'motopůjčovna, půjčovna motorek, dárkový poukaz na motorku, dárek pro motorkáře, poukaz na pronájem motorky, voucher motorka, MotoGo24',
                'og_image' => 'https://www.motogo24.cz/gfx/darkovy-poukaz.jpg',
            ],
            'h1' => 'Kup dárkový poukaz – daruj zážitek na dvou kolech!',
            'intro_left' => '<p>Hledáš originální dárek pro partnera, kamaráda nebo tátu?</p><p>&nbsp;</p><p>Naše <strong>dárkové poukazy na pronájem motorky</strong> od Motogo24 – <strong>půjčovna motorek Vysočina</strong> – potěší začátečníky i zkušené jezdce.</p><p>&nbsp;</p><p>Vyber hodnotu poukazu nebo konkrétní motorku a daruj svobodu na dvou kolech.</p>',
            'intro_cta' => [
                'label' => 'OBJEDNAT DÁRKOVÝ POUKAZ',
                'href' => '/koupit-darkovy-poukaz',
                'aria' => 'Objednat dárkový poukaz na pronájem motorky v půjčovně Motogo24',
            ],
            'intro_image' => [
                'src' => 'gfx/darkovy-poukaz.jpg',
                'alt' => 'Dárkový poukaz',
            ],
            'steps' => [
                [
                    'icon' => 'gfx/vyber-motorku.svg',
                    'title' => '1. Vyber',
                    'text' => 'Vybereš si hodnotu poukazu nebo konkrétní motorku.',
                ],
                [
                    'icon' => 'gfx/zaplat.svg',
                    'title' => '2. Zaplať',
                    'text' => 'Zaplatíš online.',
                ],
                [
                    'icon' => 'gfx/potvrzeni-rezervace.svg',
                    'title' => '3. Vyzvedni',
                    'text' => 'Poukaz po zaplacení přistane do tvé e-mailové schránky.',
                ],
            ],
            'validity_note' => 'Všechny vouchery mají <strong>platnost 3 roky</strong> od data vystavení. <strong>Obdarovaný si sám zvolí termín výpůjčky</strong>, který se mu hodí. Může nás kontaktovat e-mailem, telefonicky nebo přes sociální sítě.',
            'why' => [
                'title' => 'Proč zakoupit poukaz',
                'items' => [
                    '<strong>Flexibilní volba</strong> – hodnota poukazu nebo konkrétní motorka.',
                    '<strong>Platnost 3 roky</strong> – obdarovaný si sám vybere termín.',
                    '<strong>Bez kauce</strong> – férové podmínky bez zbytečných překážek.',
                    '<strong>Výbava v ceně</strong> – helma, bunda, kalhoty a rukavice zdarma.',
                    '<strong>Nonstop provoz</strong> – vyzvednutí i vrácení kdykoli v den výpůjčky.',
                    '<strong>Online objednávka</strong> – poukaz ti po zaplacení přijde e-mailem.',
                ],
            ],
            'how' => [
                'title' => 'Jak poukaz využít',
                'items' => [
                    '<strong>Cestovní motorky</strong> – víkendový roadtrip po Vysočině, celé ČR i v zahraničí.',
                    '<strong>Naked motorky</strong> – dynamická jízda plná zábavy a adrenalinu.',
                    '<strong>Supermoto</strong> – adrenalinová jízda v zatáčkách. <strong>Choppery a cruisery</strong> – pohodová vyjížďka ve stylu, kde je cesta cílem.',
                    '<strong>Dětské motorky</strong> – první jízdy pro malé jezdce pod dohledem. <strong>Skútry</strong> – jednoduché svezení bez řazení, ideální na výlet po okolí.',
                ],
            ],
            'catalog_cta' => [
                'label' => 'ZOBRAZIT KATALOG MOTOREK',
                'href' => '/katalog',
            ],
            'faq' => [
                'title' => 'Často kladené dotazy k dárkovým poukazům',
                'items' => [
                    [
                        'q' => 'Jaká je platnost dárkového poukazu?',
                        'a' => 'Všechny vouchery mají platnost <strong>3 roky</strong> od data vystavení. Termín výpůjčky si obdarovaný volí sám.',
                    ],
                    [
                        'q' => 'Jak poukaz doručíte?',
                        'a' => '<strong>Okamžitě e-mailem</strong> po úhradě. Na požádání umíme připravit i dárkový tisk v provozovně.',
                    ],
                    [
                        'q' => 'Musí obdarovaný skládat kauci?',
                        'a' => 'Ne. <strong>Půjčujeme bez kauce</strong>. Podmínky jsou jasné a férové, výbava řidiče je v ceně.',
                    ],
                    [
                        'q' => 'Lze změnit termín uplatnění?',
                        'a' => 'Ano, <strong>termín lze po domluvě změnit</strong> dle dostupnosti konkrétní motorky v našem kalendáři.',
                    ],
                    [
                        'q' => 'Na jaké motorky lze voucher uplatnit?',
                        'a' => 'Poukaz můžeš uplatnit na všechny motorky v nabídce Motogo24 – podle zvolené hodnoty poukazu.',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Dárkový poukaz na pronájem motorky – Vysočina',
                'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, <strong>bez kauce</strong> a <strong>výbavou v ceně</strong>. Dárkový voucher je ideální volba, jak darovat <em>motorbike rental</em> zážitek – od <strong>cestovních</strong> přes <strong>naked</strong> a <strong>supermoto</strong> až po <strong>dětské motorky, choppery</strong> nebo <strong>skútry</strong>.',
                'buttons' => [
                    [
                        'label' => 'OBJEDNAT VOUCHER',
                        'href' => '/koupit-darkovy-poukaz',
                        'cls' => 'btndark pulse',
                    ],
                ],
            ],
        ],
    ],
];
