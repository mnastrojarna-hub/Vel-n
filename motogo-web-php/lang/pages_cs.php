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
            'intro' => 'V <strong>MotoGo24 – půjčovně motorek na Vysočině</strong> –&nbsp; dostaneš férové podmínky. <strong>Bez kauce, s výbavou pro řidiče v ceně a nonstop provozem</strong>. Vše, co potřebuješ k bezpečné a pohodové jízdě, je součástí půjčovného.',
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
                        'přistavení motorky na domluvené místo kamkoliv v ČR',
                        'vrácení motorky jinam než na adresu půjčovny',
                    ],
                ],
            ],
            'benefits' => [
                'title' => 'Další výhody v ceně',
                'grid' => 'gr5',
                'items' => [
                    [
                        'icon' => 'gfx/ico-online-rezervace.svg',
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
                        'text' => 'žádná záloha při půjčení.',
                    ],
                    [
                        'icon' => 'gfx/ico-jasne-podminky.svg',
                        'title' => 'Jasné podmínky',
                        'text' => 'bez skrytých poplatků.',
                    ],
                    [
                        'icon' => 'gfx/ico-sleva.svg',
                        'title' => 'Sleva na další rezervaci',
                        'text' => 'po každém dokončeném pronájmu dostaneš slevový kód na příští rezervaci.&nbsp;',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Výbava v ceně – půjčovna motorek MotoGo24 – Vysočina',
                'text' => '<strong>MotoGo24 je moderní půjčovna motorek na Vysočině</strong> s výbavou pro řidiče v ceně, půjčením bez kauce a nonstop provozem. Vyber si <strong>cestovní, supermoto, naked nebo dětskou motorku</strong> a rezervuj online. U nás je vše jasné a bez skrytých poplatků.',
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
                'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Co je v ceně nájmu',
                'description' => 'Zjisti, co obsahuje cena půjčení motorky u MotoGo24. Půjčovna motorek nabízí jasné podmínky, výbavu i služby bez skrytých poplatků. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
                'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovní motorky, pronájem sportovní motorky, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle hire Vysocina, rent a motorbike Pelhřimov',
            ],
        ],
        'jak_pujcit_dokumenty' => [
            'h1' => 'Nájemní smlouva a kauce – férové podmínky bez zálohy',
            'intro' => 'V <strong>Motogo24 – půjčovna motorek Vysočina (Pelhřimov)</strong> klademe důraz na jednoduchost a férovost. Půjčujeme <strong>bez kauce</strong>, s <strong>jasnou nájemní smlouvou</strong>, <strong>pojištěním v ceně</strong> a <strong>výbavou pro řidiče</strong> zahrnutou v půjčovném.',
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
                        'title' => 'Bez kauce / zálohy',
                        'text' => 'motorku půjčujeme bez blokace peněz',
                    ],
                    [
                        'icon' => 'gfx/ico-pojisteni.svg',
                        'title' => 'Pojištění',
                        'text' => 'v ceně (povinné ručení; havarijní dle konkrétního modelu a podmínek)',
                    ],
                    [
                        'icon' => 'gfx/ico-vybava.svg',
                        'title' => 'Výbava pro řidiče',
                        'text' => 'v ceně (helma, bunda, kalhoty, rukavice)',
                    ],
                    [
                        'icon' => 'gfx/ico-nonstop.svg',
                        'title' => 'Nonstop provoz',
                        'text' => 'převzetí a vrácení kdykoli v den výpůjčky',
                    ],
                    [
                        'icon' => 'gfx/ico-jasna-pravidla.svg',
                        'title' => 'Jasná pravidla užívání',
                        'text' => 'doma i v zahraničí (podle zelené karty)',
                    ],
                    [
                        'icon' => 'gfx/ico-bezskryte.svg',
                        'title' => 'Žádné skryté poplatky',
                        'text' => 'vše je uvedeno níže a ve smlouvě',
                    ],
                ],
            ],
            'required_docs' => [
                'title' => 'Co potřebujete k uzavření smlouvy',
                'items' => [
                    '<strong>Občanský průkaz / pas</strong>',
                    '<strong>Řidičský průkaz</strong>&nbsp;odpovídající skupiny (A / A2 dle stroje)',
                    '<strong>Věk</strong>&nbsp;min. 18 let (u dětských motorek ručí zákonný zástupce)',
                    '<strong>Kontakty</strong>&nbsp;(telefon, e-mail) pro komunikaci a potvrzení rezervace',
                ],
            ],
            'payments' => [
                'title' => 'Platby, storno a poplatky',
                'lead' => '<strong>Kauce:</strong>&nbsp;<em>nevyžadujeme</em>. Platba za nájem probíhá online nebo při převzetí.',
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
                        'Lze bezplatně do předem domluveného času (uvedeno v potvrzení rezervace). Později dle individuální dohody.',
                    ],
                    [
                        '<strong>Palivo &amp; čištění</strong>',
                        'Vrácení bez povinnosti dotankovat a mýt. Případné nadměrné znečištění řešíme individuálně.',
                    ],
                    [
                        '<strong>Přistavení / svoz</strong>',
                        'Dle ceníku přistavení (Vysočina / okolí). Potvrzujeme při rezervaci.',
                    ],
                    [
                        '<strong>Pozdní vrácení</strong>',
                        'Prosíme o včasné vrácení v poslední den výpůjčky; při zpoždění účtujeme dle domluvy (ohled na další rezervace).',
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
                    'Jezděte v&nbsp;<strong>souladu s předpisy</strong>&nbsp;a s ohledem na technický stav a typ motorky.',
                    'Za&nbsp;<strong>pokuty a přestupky</strong>&nbsp;odpovídá nájemce (informace předáváme dle zákona).',
                    '<strong>Zahraničí</strong>: možné; řiďte se územní platností pojištění (zelená karta). Některé země mohou být vyloučeny.',
                    'V případě&nbsp;<strong>nehody nebo poruchy</strong>&nbsp;postupujte podle pokynů v palubní sadě (formulář nehody, kontakt na Motogo24).',
                    '<strong>Servis a údržbu</strong>&nbsp;zajišťujeme my; závady hlaste okamžitě.',
                    '<strong>Úpravy motorky</strong>&nbsp;bez souhlasu nejsou dovoleny.',
                ],
            ],
            'handover' => [
                'title' => 'Předání a vrácení',
                'items' => [
                    '<strong>Převzetí</strong>&nbsp;probíhá v Pelhřimově (Mezná 9) nebo využijte&nbsp;<a href="/jak-pujcit/pristaveni">přistavení</a>.',
                    'Při předání obdržíte&nbsp;<strong>klíče, výbavu a dokumenty</strong>&nbsp;(malý TP, zelená karta, formulář nehody).',
                    '<strong>Vrácení</strong>&nbsp;kdykoli během posledního dne výpůjčky (i o půlnoci). Není nutné mýt ani tankovat.',
                ],
            ],
            'privacy' => [
                'title' => 'Osobní údaje a bezpečnost',
                'text' => 'Osobní údaje zpracováváme pouze pro účely uzavření a plnění nájemní smlouvy (identifikace, komunikace, fakturace). Podrobnosti najdete v <a href="/cms/zasady-ochrany-osobnich-udaju">zásadách zpracování osobních údajů</a>.',
            ],
            'documents' => [
                'title' => 'Dokumenty ke stažení',
                'items' => [
                    [
                        'name' => 'Smlouva o pronájmu',
                        'href' => '/cms/smlouva-o-pronajmu',
                        'size' => '87.4kB',
                    ],
                    [
                        'name' => 'Předávací protokol',
                        'href' => '/cms/predavaci-protokol',
                        'size' => '47.6kB',
                    ],
                    [
                        'name' => 'Obchodní podmínky',
                        'href' => '/cms/obchodni-podminky',
                        'size' => '87.7kB',
                    ],
                    [
                        'name' => 'Zásady ochrany osobních údajů',
                        'href' => '/cms/zasady-ochrany-osobnich-udaju',
                        'size' => '76.3kB',
                    ],
                ],
            ],
            'midcta' => [
                'title' => 'Souhlasíte s podmínkami? Rezervujte a jeďte.',
                'text' => 'Vyberte si z&nbsp;<strong>cestovních, sportovních, enduro i dětských motorek</strong>&nbsp;a potvrďte rezervaci online.',
            ],
            'cta' => [
                'title' => 'Nájemní smlouva bez kauce – půjčovna motorek Vysočina',
                'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s férovými podmínkami: <strong>bez kauce</strong>, <strong>pojištění v ceně</strong>, <strong>výbava pro řidiče</strong> a <strong>nonstop provoz</strong>. Vše přehledně ve vzorové nájemní smlouvě a na této stránce.',
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
                'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Dokumenty a návody',
                'description' => 'Všechny dokumenty k půjčení motorky na jednom místě. Přehledné návody a podmínky od MotoGo24 pro bezpečné používání motocyklu. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
                'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovní motorky, pronájem sportovní motorky, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle hire Vysocina, rent a motorbike Pelhřimov',
            ],
        ],
        'jak_pujcit_pristaveni' => [
            'h1' => 'Přistavení motocyklu – doručení až k tobě',
            'intro' => 'Chceš vyrazit bez zbytečného přesunu do půjčovny? Zajistíme <strong>přistavení motorky na domluvené místo</strong> – domů, do hotelu, k nádraží nebo na start tvého výletu. Motorku přivezeme kamkoliv v České republice – přímo z naší provozovny v Pelhřimově.',
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
                        'icon' => 'gfx/ico-flexibilita.svg',
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
                        'icon' => 'gfx/ico-uspora-casu.svg',
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
                        'icon' => 'gfx/ico-step-vyber.svg',
                        'title' => 'Vyber motorku',
                        'text' => 'Prohlédni si naši nabídku cestovních, supermoto, naked a dětských motorek a vyber si tu pravou.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-termin.svg',
                        'title' => 'Zvol termín',
                        'text' => 'V kalendáři vyber datum, kdy chceš vyjet. Uvidíš, které motorky jsou volné.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-udaje.svg',
                        'title' => 'Kontaktní údaje',
                        'text' => 'Vyplň jméno, adresu, e-mail a telefon.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-cas.svg',
                        'title' => 'Čas přistavení',
                        'text' => 'Zvol, kdy ti motorku přistavíme – klidně večer nebo o víkendu.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-misto.svg',
                        'title' => 'Místo přistavení',
                        'text' => 'Zadej adresu, kam motorku přivézt – domů, do hotelu, k nádraží nebo na start výletu.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-vybava.svg',
                        'title' => 'Výbava',
                        'text' => 'Základní výbava řidiče je v ceně. Požadované velikosti pro všechny části výbavy uveď do pole Poznámka – povinné.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-platba.svg',
                        'title' => 'Potvrzení a platba',
                        'text' => 'Zkontroluj shrnutí objednávky, odsouhlas podmínky a zaplať online.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-prevzeti.svg',
                        'title' => 'Převzetí na místě',
                        'text' => 'Při předání zkontrolujeme doklady, doplníme smlouvu a podepíšeme předávací protokol.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-jizda.svg',
                        'title' => 'Užij si jízdu',
                        'text' => 'Vyraz na cestu – bez kauce, bez stresu. Zbytek je jen asfalt a svoboda.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-vraceni.svg',
                        'title' => 'Vrácení motorky',
                        'text' => 'Motorku vrať včas na předem sjednané místo. Nemusíš tankovat ani mýt.',
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
                'example' => '<strong>Příklad:</strong>&nbsp;Chcete motorku přistavit 30 km od půjčovny? Zaplatíte 500 + 500 + (30 × 2 × 20) =&nbsp;<strong>2 200 Kč.</strong>',
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
                        'q' => 'Platí se kauce?',
                        'a' => 'Ne. <strong>Půjčujeme bez kauce</strong>, podmínky jsou jasné a férové.',
                    ],
                    [
                        'q' => 'Je v ceně i výbava řidiče?',
                        'a' => 'Ano. Helma, bunda, kalhoty a rukavice jsou pro řidiče&nbsp;<strong>v ceně výpůjčky</strong>.',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Přistavení motorky – půjčovna motorek',
                'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s možností <strong>přistavení motocyklu</strong> kamkoliv v České republice. Cena přistavení se odvíjí od vzdálenosti z naší provozovny v Pelhřimově.&nbsp;Nabízíme <strong>nonstop provoz, bez kauce, výbavu pro řidiče v ceně</strong> a jednoduchou<strong> online rezervaci</strong>.',
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
                'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Přistavení motocyklu',
                'description' => 'MotoGo24 zajistí přistavení motorky na místo podle tvého výběru. Pohodlné půjčení motorky na Vysočině bez zbytečného cestování. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
                'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovní motorky, pronájem sportovní motorky, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle hire Vysocina, rent a motorbike Pelhřimov',
            ],
        ],
        'jak_pujcit_vraceni_jinde' => [
            'h1' => 'Vrácení motorky kdekoliv – přijedeme za tebou',
            'intro' => 'Nechceš se vracet do půjčovny v Pelhřimově? Žádný problém. Přijedeme si pro motorku kamkoliv v České republice – v čas, který sis zvolil v rezervačním formuláři. Ty předáš, my naložíme. Jednoduše a bez komplikací.',
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
                        'icon' => 'gfx/ico-flexibilita.svg',
                        'title' => 'Flexibilita',
                        'text' => 'Vybereš si místo vrácení podle své trasy – hotel, nádraží, parkoviště nebo kdekoliv jinde.',
                    ],
                    [
                        'icon' => 'gfx/ico-uspora-casu.svg',
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
                        'icon' => 'gfx/ico-jednoduchost.svg',
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
                        'icon' => 'gfx/ico-step-misto-cas.svg',
                        'title' => 'Zvol místo a čas vrácení',
                        'text' => 'V rezervačním formuláři zadej adresu a čas, kdy motorku předáš.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-vybava.svg',
                        'title' => 'Připrav si výbavu',
                        'text' => 'Před předáním si nachystej výbavu, která byla součástí výpůjčky.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-prijedeme.svg',
                        'title' => 'Přijedeme v domluvený čas',
                        'text' => 'Dorazíme na sjednané místo přesně v domluvený čas.',
                    ],
                    [
                        'icon' => 'gfx/ico-step-kontrola.svg',
                        'title' => 'Společně zkontrolujeme motorku a výbavu',
                        'text' => 'Zkontrolujeme stav motorky a výbavy, naložíme a odjedeme.&nbsp;',
                    ],
                    [
                        'icon' => 'gfx/ico-step-email.svg',
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
                        'a' => 'Ne. U nás netankuješ ani nemyješ. Jen hlídej, aby nesvítila rezerva.&nbsp;',
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
                        'a' => 'Zavolej nám, jakmile víš, že to nestihneš na čas. Domluvíme se – většinou na tebe počkáme. Jen potřebujeme vědět, s jakým zpožděním počítat, abychom si mohli přizpůsobit plán dne.',
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
                'title' => 'Vrácení motorky jinde – půjčovna motorek MotoGo24',
                'text' => 'Půjčovna motorek MotoGo24 na Vysočině nabízí vrácení motorky kdekoliv v České republice. Předej nám motorku na místě podle svého výběru – my přijedeme v domluvený čas. Cena se odvíjí od vzdálenosti z místa vrácení do naší provozovny v Pelhřimově. Vyber si cestovní, supermoto, naked nebo dětskou motorku, rezervuj online a vyraž. O zbytek se postaráme my.',
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
                'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Vrácení motorky jinde',
                'description' => 'Vrať motorku tam, kde ti to vyhovuje. MotoGo24 nabízí flexibilní vrácení motocyklu na Vysočině bez nutnosti návratu do půjčovny. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
                'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovní motorky, pronájem sportovní motorky, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorky online, motorky k pronájmu Vysočina, motorbike rental Czech Republic, motorcycle hire Vysocina, rent a motorbike Pelhřimov',
            ],
        ],
        'faq' => [
            'seo' => [
                'title' => 'Půjčovna motorek Vysočina – Jak si půjčit motorku – Často kladené dotazy',
                'description' => 'Nejčastější dotazy k půjčení motorky u MotoGo24. Odpovědi na rezervaci motorky, podmínky i průběh zapůjčení motocyklu. Rezervuj si motorku jednoduše online. Vyber termín, stroj i výbavu a vyraz na nezapomenutelnou jízdu s MotoGo24 na Vysočině.',
                'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Vysočina, půjčovna motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna motorek, půjčovna cestovních motorek, pronájem sportovních motorek, půjčovna enduro motorek, půjčovna skútrů Vysočina, dětské motorky k pronájmu, rezervace motorek online, motorky k pronájmu Vysočina, půjčovna motorek Česká republika, půjčovna motocyklů Pelhřimov',
            ],
            'h1' => 'Často kladené dotazy',
            'closing' => 'Naše <strong>půjčovna motorek Vysočina</strong> je tu pro všechny, kdo chtějí zažít <strong>nezapomenutelnou jízdu</strong> bez zbytečných komplikací. Pronájem je <strong>bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop</strong>. Stačí si vybrat svůj stroj a rezervovat motorku online během pár minut. Ať už hledáte <strong>cestovní motorku, sportovní model nebo enduro</strong>, u nás si vyberete.',
            'cta' => [
                'label' => 'Rezervovat motorku online',
                'href' => '/rezervace',
            ],
            'categories' => [
                'reservations' => [
                    'label' => 'Rezervace',
                    'items' => [
                        [
                            'q' => 'Jak si mohu rezervovat motorku?',
                            'a' => 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Pokud budeš potřebovat pomoc, klidně se nám ozvi – e-mailem, telefonicky nebo přes sociální sítě – rádi ti pomůžeme.',
                        ],
                        [
                            'q' => 'Můžu si motorku půjčit i bez předchozí rezervace?',
                            'a' => 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit přes náš online systém. Bez rezervace nemůžeme zaručit dostupnost motocyklu.',
                        ],
                        [
                            'q' => 'Jak probíhá rezervace?',
                            'a' => 'Rezervace probíhá ve třech krocích: vyplníš základní údaje, zkontroluješ shrnutí a cenu, a rovnou zaplatíš online. Potvrzení platby spolu s návrhem nájemní smlouvy ti přijde e-mailem okamžitě. Smlouva nabývá platnosti až při osobním převzetí motorky, po ověření ŘP a OP (nebo PASu).',
                        ],
                        [
                            'q' => 'Musím mít rezervaci předem?',
                            'a' => 'Ano, rezervace je povinná. Bez ní nemůžeme zaručit dostupnost motorky.',
                        ],
                        [
                            'q' => 'Jak zaplatím?',
                            'a' => 'Online platební kartou – zaplatíš přímo v rezervačním formuláři.',
                        ],
                        [
                            'q' => 'Kdo podepisuje smlouvu za dítě?',
                            'a' => 'Smlouvu podepisuje rodič nebo zákonný zástupce, který je zároveň uveden jako nájemce.',
                        ],
                        [
                            'q' => 'Jaký řidičský průkaz potřebuji?',
                            'a' => 'Záleží na tom, jakou motorku si vybereš – u každého modelu je přímo v nabídce uvedeno, jaké řidičské oprávnění je potřeba. Silnější stroje vyžadují skupinu A, slabší skupinu A2. Na dětské motorky řidičský průkaz nepotřebuješ.',
                        ],
                        [
                            'q' => 'Mohu rezervaci zrušit nebo změnit termín?',
                            'a' => 'Rezervaci lze zrušit bez poplatku nejpozději 7 dní před sjednaným termínem převzetí. Pokud motorku nepřevezmeš bez předchozího zrušení rezervace, účtujeme plnou výši nájemného. Změnu termínu řeš s námi individuálně co nejdříve – ozvi se telefonicky nebo e-mailem.',
                        ],
                        [
                            'q' => 'Co se stane, když motorku z vaší strany nebudete moci předat?',
                            'a' => 'V takovém případě tě okamžitě kontaktujeme a nabídneme ti nejlepší možné řešení – náhradní motorku nebo jiný termín. A jako omluvu dostaneš slevu na příští rezervaci.',
                        ],
                        [
                            'q' => 'Jak si zvolím správnou velikost výbavy?',
                            'a' => 'Velikosti můžeš vyplnit předem přímo v rezervačním formuláři. Pokud chceš vybrat až na místě, vyzkoušíš si různé velikosti při převzetí. V případě přistavení motorky na jiné místo je výběr velikostí předem povinný, abychom ti mohli dovézt správnou výbavu. Dostupnost konkrétních velikostí závisí na aktuální obsazenosti půjčovny.',
                        ],
                    ],
                ],
                'borrowing' => [
                    'label' => 'Výpůjčka a vrácení',
                    'items' => [
                        [
                            'q' => 'Můžu motorku při vrácení na jiném místě vrátit dřív, než jsme se domluvili?',
                            'a' => 'Na sjednané místo vyjíždíme z Pelhřimova přesně podle domluveného času, takže dřívější vrácení bohužel není možné. Pokud se ti plány změní, ozvi se nám – pokusíme se čas přizpůsobit, ale záleží na naší aktuální vytíženosti.',
                        ],
                        [
                            'q' => 'Můžu motorku vrátit opravdu kdekoliv v ČR?',
                            'a' => 'Ano, přijedeme si pro motorku kamkoliv v České republice. Místo vrácení zadáš při rezervaci – může to být hotel, parkoviště, nádraží nebo jakákoliv jiná adresa.',
                        ],
                        [
                            'q' => 'Jak daleko dopředu musím vrácení na jiném místě nahlásit?',
                            'a' => 'Místo a čas vrácení zadáváš už v rezervačním formuláři.',
                        ],
                        [
                            'q' => 'Co když se na místo vrácení zpozdím?',
                            'a' => 'Zavolej nám, jakmile víš, že to nestihneš na čas. Domluvíme se – většinou na tebe počkáme. Jen potřebujeme vědět, s jakým zpožděním počítat, abychom si mohli přizpůsobit plán dne.',
                        ],
                        [
                            'q' => 'Jak se počítá cena za vrácení na jiném místě?',
                            'a' => 'Cena zahrnuje 500 Kč za naložení, 500 Kč za vyložení a 20 Kč za každý kilometr vzdálenosti z místa vrácení do půjčovny (tam i zpět). Například při vrácení 50 km od Pelhřimova zaplatíš 500 + 500 + (50 × 2 × 20) = 3 000 Kč.',
                        ],
                        [
                            'q' => 'Platím za vrácení jinde zvlášť, nebo je to součástí ceny pronájmu?',
                            'a' => 'Vrácení na jiném místě je doplňková služba a platí se zvlášť nad rámec ceny pronájmu.',
                        ],
                        [
                            'q' => 'Co když chci motorku vyzvednout v Pelhřimově, ale vrátit jinde – jde to?',
                            'a' => 'Ano, můžeš vyzvednout motorku u nás v Pelhřimově a vrátíš ji tam, kde potřebuješ.',
                        ],
                        [
                            'q' => 'Co mám mít připravené, když přijedete pro motorku?',
                            'a' => 'Měj připravené klíče a veškerou výbavu, která byla součástí výpůjčky. Společně zkontrolujeme stav motorky a výbavy.',
                        ],
                        [
                            'q' => 'Můžu motorku vrátit do půjčovny dřív, než jsme se domluvili?',
                            'a' => 'Ano, motorku můžeš vrátit kdykoliv během posledního dne výpůjčky. Stačí nám dát vědět, že dorazíš dřív. Žádné příplatky za dřívější vrácení neúčtujeme.',
                        ],
                        [
                            'q' => 'Co se stane, když nestihnu motorku do půjčovny vrátit do půlnoci posledního dne?',
                            'a' => 'Pokud víš, že se zpozdíš, ozvi se nám co nejdřív. Domluvíme se na řešení. V případě neoznámeného pozdního vrácení se postupuje podle podmínek nájemní smlouvy.',
                        ],
                        [
                            'q' => 'Musím při vrácení v půjčovně něco podepsat?',
                            'a' => 'Pokud je vše v pořádku, vrácení proběhne rychle a bez zbytečného papírování. Potvrzení o ukončení nájmu a konečnou fakturu dostaneš na e-mail.',
                        ],
                        [
                            'q' => 'Jak probíhá kontrola motorky při vrácení v půjčovně?',
                            'a' => 'Společně projdeme stav motorky a výbavy. Pokud je vše v pořádku, převezmeme klíče a výbavu a ty můžeš jít. Celé to zabere pár minut.',
                        ],
                        [
                            'q' => 'Kde probíhá vyzvednutí a vrácení?',
                            'a' => 'V místě půjčovny na adrese Mezná 9, Pelhřimov. V rezervačním formuláři si ale můžeš domluvit i vyzvednutí nebo vrácení na jiném místě.',
                        ],
                        [
                            'q' => 'Do kdy musím motorku vrátit?',
                            'a' => 'Motorku vrať ideálně ve sjednaný čas. Pokud vracíš v místě půjčovny, můžeš ale přijet po dohodě kdykoli během posledního dne výpůjčky – nejpozději do půlnoci, bez jakýchkoli sankcí. Vracíš-li na jiném místě, je sjednaný čas závazný.',
                        ],
                        [
                            'q' => 'Musím vracet s plnou nádrží a čistou?',
                            'a' => 'Ne. U nás netankuješ ani nemyješ. Jen hlídej, aby nesvítila rezerva.',
                        ],
                        [
                            'q' => 'Musím přijet osobně?',
                            'a' => 'Ano, při převzetí motorky je nutná osobní přítomnost – ověříme tvé doklady (ŘP a OP nebo PAS), společně podepíšeme předávací protokol a vybereme výbavu.',
                        ],
                        [
                            'q' => 'Co dělat, když nestihnu domluvený čas vyzvednutí?',
                            'a' => 'Ozvi se nám co nejdřív – telefonicky nebo e-mailem. Domluvíme se.',
                        ],
                        [
                            'q' => 'Od kolika let si lze dětskou motorku půjčit?',
                            'a' => 'Neplatí jeden věk pro všechny – záleží na fyzické a psychické vyspělosti dítěte. Obecně nabízíme dětské motorky od 3–4 let pro ty nejmenší, od 5–6 let pak klasické dětské motorky. Rádi vám pomůžeme s výběrem vhodného stroje.',
                        ],
                        [
                            'q' => 'Může dítě jezdit samo, nebo musí být pod dohledem?',
                            'a' => 'Dítě musí být vždy pod dohledem rodiče nebo zákonného zástupce, který za něj nese plnou odpovědnost. Jízda na veřejných komunikacích není povolena.',
                        ],
                        [
                            'q' => 'Je výbava pro dítě součástí ceny?',
                            'a' => 'Ano, základní výbava je vždy součástí ceny. Půjčíme dítěti helmu, bundu, kalhoty a rukavice ve vhodné a dostupné velikosti.',
                        ],
                        [
                            'q' => 'Půjčíte motorku i začátečníkovi?',
                            'a' => 'Ano, půjčíme každému, kdo má platné řidičské oprávnění příslušné skupiny a platný OP nebo PAS. Žádnou minimální praxi nevyžadujeme.',
                        ],
                        [
                            'q' => 'Mohu prodloužit výpůjčku?',
                            'a' => 'Ano, pokud to dovolí dostupnost motorky. Stačí se nám co nejdříve ozvat – telefonicky nebo e-mailem – a domluvíme se.',
                        ],
                        [
                            'q' => 'Jak probíhá převzetí motorky v půjčovně?',
                            'a' => 'Přátelsky a bez stresu. Přivítáme tě, společně si projdeme motorku, zkontrolujeme tvé doklady (OP a ŘP) a vyřídíme papíry. Vybereš si výbavu, která ti sedí, podepíšeme předávací protokol a ty dostaneš klíče, dokumenty a všechny potřebné instrukce. Auto můžeš zaparkovat u nás, osobní věci odložit ve skřínce – a než vyrazíš, klidně si odskočíš na toaletu. Pak už jen nasednout a jet!',
                        ],
                        [
                            'q' => 'Jaké velikosti výbavy nabízíte?',
                            'a' => 'Dospělí jezdci si mohou vybrat z těchto velikostí: helmy XS–XL, bundy a kalhoty M–2XL, rukavice M–XL, motoboty 39–46. Kukla a reflexní vesta jsou univerzální. Pro děti nabízíme: helmy pro obvod hlavy 47–52 cm (větší děti vybírají z dospělých velikostí), bundy a kalhoty pro výšku 110–152 cm (věk 5–12 let), rukavice pro věk 4–7 a 8–12 let, motoboty 29–35.',
                        ],
                        [
                            'q' => 'Mohu si půjčit i motoboty?',
                            'a' => 'Ano, motorkářské boty nabízíme jako doplňkovou službu za příplatek – pro řidiče i spolujezdce. Jednoduše si je přidáš v rezervačním formuláři. Nabízíme velikosti 39–46 pro dospělé a 29–35 pro děti.',
                        ],
                        [
                            'q' => 'Jak zajišťujete hygienu výbavy?',
                            'a' => 'O čistotu dbáme pečlivě. Kuklu dostaneš vždy zbrusu novou – je jednorázová a po výpůjčce zůstane tvoje. Boty dezinfikujeme po každém zákazníkovi. Oblečení pereme v pravidelných intervalech a nadstandardně i při každém větším znečištění.',
                        ],
                        [
                            'q' => 'Mohu použít vlastní výbavu?',
                            'a' => 'Ano, vlastní výbava je vítána. V rezervačním formuláři jednoduše zaškrtneš, že výbavu nepotřebuješ půjčit.',
                        ],
                        [
                            'q' => 'Co je součástí motorky při převzetí?',
                            'a' => 'Vždy dostaneš klíče, malý technický průkaz, zelenou kartu, reflexní vestu, motolékárničku, záznam o dopravní nehodě s propiskou, kontakt na asistenční službu a jednorázovou kuklu. Případná výbava (helma, bunda, kalhoty, rukavice, boty) se předává dle toho, co sis objednal v rezervaci. Kufry jsou součástí vybraných modelů motorek – jejich dostupnost zjistíš přímo v nabídce konkrétní motorky.',
                        ],
                        [
                            'q' => 'Mají motorky kufry?',
                            'a' => 'Záleží na typu motorky. Cestovní motorky mívají zpravidla 3 kufry, naked a supermoto 1 kufr nebo tankvak. Dětské motorky kufry nemají. Kufry jsou vždy pevnou součástí motorky bez příplatku – přesné vybavení najdeš v nabídce každého modelu na webu.',
                        ],
                        [
                            'q' => 'Mohu zaplatit až při převzetí motorky?',
                            'a' => 'Ne, platba probíhá výhradně online při dokončení rezervace. Bez úspěšné platby rezervace nevzniká.',
                        ],
                        [
                            'q' => 'Je u půjčovny možnost parkování?',
                            'a' => 'Ano, přímo před půjčovnou máme k dispozici několik parkovacích míst zdarma. Kapacita je ale omezená, takže počítej s tím, že nemusí být vždy volno.',
                        ],
                    ],
                ],
                'conditions' => [
                    'label' => 'Výbava a podmínky',
                    'items' => [
                        [
                            'q' => 'Je v ceně půjčovného výbava řidiče?',
                            'a' => 'Ano, výbava řidiče je vždy součástí ceny. Půjčíme ti helmu, bundu, kalhoty i rukavice – ve více velikostech.',
                        ],
                        [
                            'q' => 'Je v ceně zahrnutá i výbava pro spolujezdce?',
                            'a' => 'Výbava pro spolujezdce není součástí základní ceny, ale snadno si ji přiobjednáš jako doplňkovou službu přímo v rezervačním formuláři.',
                        ],
                        [
                            'q' => 'Je nutná kauce?',
                            'a' => 'Ne. Motorky půjčujeme <strong>bez kauce</strong> a bez skrytých poplatků.',
                        ],
                        [
                            'q' => 'Jaké doklady potřebuji?',
                            'a' => '<strong>OP/pas</strong> a <strong>řidičský průkaz</strong> odpovídající skupiny (A/A2 dle motorky).',
                        ],
                    ],
                ],
                'delivery' => [
                    'label' => 'Přistavení',
                    'items' => [
                        [
                            'q' => 'Můžete motorku přistavit k hotelu/na nádraží?',
                            'a' => 'Ano, motorku přistavíme na domluvené místo v rámci ČR. Cena se skládá z poplatku za nakládku a vykládku (2 × 500 Kč) a sazba 20 Kč/km – počítáme kilometry tam i zpět od Mezné u Pelhřimova.',
                        ],
                        [
                            'q' => 'Jak přistavení objednám?',
                            'a' => 'Jednoduše – při online rezervaci doplníš adresu a čas přistavení. Cena se dopočítá automaticky.',
                        ],
                        [
                            'q' => 'Mohu vrátit motorku jinde, než byla převzata?',
                            'a' => 'Ano, vrácení na jiném místě je možné v rámci celé ČR. Cena se řídí stejným ceníkem jako přistavení – 500 Kč za nakládku/vykládku a 20 Kč/km od Mezné u Pelhřimova.',
                        ],
                        [
                            'q' => 'Lze vrátit motorku jinde, než byla převzata?',
                            'a' => 'Ano, nabízíme <strong>svoz</strong> – účtujeme dle ceníku přistavení/svozu.',
                        ],
                        [
                            'q' => 'Máte věrnostní program?',
                            'a' => 'Zatím ne, ale každý zákazník po vrácení motorky dostane slevový kód 200 Kč na příští rezervaci.',
                        ],
                        [
                            'q' => 'Jak daleko přistavení motorky nabízíte?',
                            'a' => 'Přistavujeme po celé České republice, do zahraničí přistavení nenabízíme.',
                        ],
                        [
                            'q' => 'Jak probíhá převzetí motorky při přistavení na jiné místo?',
                            'a' => 'Přijedeme na domluvené místo ve sjednaný čas. Přivezeme ti motorku i výbavu, kterou sis zvolil při rezervaci. Společně si motorku projdeme, zkontrolujeme tvé doklady, podepíšeme předávací protokol a dostaneš klíče a instrukce.',
                        ],
                    ],
                ],
                'travel' => [
                    'label' => 'Cesty do zahraničí',
                    'items' => [
                        [
                            'q' => 'Můžu odcestovat s motorkou do zahraničí?',
                            'a' => 'Ano, s motorkou můžeš bez problémů vyrazit i do zahraničí. Cesty mimo Česko neomezujeme, jen je potřeba dodržet územní platnost pojištění (zelená karta).<br>Pojištění se nevztahuje na Bělorusko, Írán, Rusko, Srbsko a Kypr – jízda do těchto zemí je proto zakázána.',
                        ],
                        [
                            'q' => 'Mohu s motorkou vycestovat do zahraničí?',
                            'a' => 'Ano, ale drž se <strong>územní platnosti pojištění</strong> (zelená karta). Některé země mohou být vyloučené.',
                        ],
                        [
                            'q' => 'Potřebuji něco speciálního do zahraničí?',
                            'a' => 'Nic speciálního – malý technický průkaz a zelená karta jsou součástí motorky. Doporučujeme mít u sebe <strong>nájemní smlouvu</strong>, kterou dostaneš při převzetí – slouží jako doklad oprávněného užívání vozidla při případné policejní kontrole. Rovněž doporučujeme sjednání cestovního pojištění.',
                        ],
                    ],
                ],
                'vouchers' => [
                    'label' => 'Poukazy',
                    'items' => [
                        [
                            'q' => 'Jaká je platnost dárkového poukazu?',
                            'a' => '<strong>3 roky</strong> od data vystavení. Termín na motorku si obdarovaný volí sám přes náš rezervační systém podle aktuální dostupnosti.',
                        ],
                        [
                            'q' => 'Na jaké motorky lze poukaz uplatnit?',
                            'a' => 'Na <strong>cestovní, sportovní, enduro i dětské</strong> modely dle hodnoty poukazu a oprávnění.',
                        ],
                        [
                            'q' => 'Musí obdarovaný platit kauci?',
                            'a' => '<strong>Ne, žádná kauce se neskládá.</strong> Naše podmínky jsou transparentní a výbava pro řidiče je vždy zahrnuta v ceně.',
                        ],
                        [
                            'q' => 'Jak voucher doručíte?',
                            'a' => '<strong>Okamžitě e-mailem</strong> po úhradě (PDF). Na požádání i tištěný voucher.',
                        ],
                        [
                            'q' => 'Dá se termín uplatnění změnit?',
                            'a' => 'Ano, po předchozí domluvě je možné termín upravit podle aktuální dostupnosti zvolené motorky.',
                        ],
                    ],
                ],
            ],
        ],
        'home' => [
            'seo' => [
                'title' => 'Půjčovna motorek na Vysočině | MotoGo24',
                'description' => 'Půjčte si motorku na Vysočině. Bez kauce, výbava v ceně, nonstop provoz. Cestovní, sportovní, enduro i dětské motorky. Online rezervace.',
                'keywords' => 'půjčovna motorek Vysočina, pronájem motorek Pelhřimov, půjčovna motorek bez kauce, nonstop půjčovna, motorky k pronájmu, online rezervace motorky',
                'og_image' => NULL,
            ],
            'hero' => [
                'image' => 'gfx/hero-banner.jpg',
                'alt' => 'Půjčovna motorek Vysočina',
                'eyebrow' => '<strong>Půjčovna motorek</strong> na Vysočině',
                'body' => 'Půjč si motorku na Vysočině snadno online.<br>Vyber si z cestovních, sportovních i enduro modelů.<br>Rezervace s platbou kartou a rychlým převzetím.',
                'cta_primary' => [
                    'label' => 'VYBER SI MOTORKU',
                    'href' => '/katalog',
                    'cls' => 'btngreen',
                ],
                'cta_secondary' => [
                    'label' => 'JAK TO FUNGUJE',
                    'href' => '/jak-pujcit',
                    'cls' => 'btndark',
                ],
            ],
            'h1' => 'Půjčovna motorek Vysočina Motogo24 – bez kauce a nonstop',
            'intro' => 'Vítejte v <strong>Motogo24</strong> – vaší půjčovně motorek na Vysočině. U nás si půjčíte motorku <strong>bez kauce</strong>, s výbavou v ceně a v režimu <strong>nonstop</strong>. Ať hledáte cestovní, sportovní, enduro nebo dětskou motorku, Motogo24 vám v srdci Vysočiny nabídne motorku na míru.',
            'signposts_title' => 'Rychlý rozcestník po Motogo24',
            'signposts' => [
                [
                    'icon' => 'gfx/ico-katalog.svg',
                    'title' => 'Katalog motorek',
                    'text' => 'Prohlédněte si naši nabídku motorek na pronájem – od sportovních po cestovní modely.',
                    'btn' => 'KATALOG MOTOREK',
                    'href' => '/katalog',
                ],
                [
                    'icon' => 'gfx/ico-jak.svg',
                    'title' => 'Jak si půjčit motorku',
                    'text' => 'Jednoduchý proces: vyberte motorku k zapůjčení, rezervujte a vyjeďte.',
                    'btn' => 'JAK SI PŮJČIT MOTORKU',
                    'href' => '/jak-pujcit',
                ],
                [
                    'icon' => 'gfx/ico-rezervace.svg',
                    'title' => 'Online rezervace motorky',
                    'text' => 'Zarezervujte si motorku na pronájem přes snadný online systém.',
                    'btn' => 'REZERVOVAT MOTORKU',
                    'href' => '/rezervace',
                ],
                [
                    'icon' => 'gfx/ico-kontakt.svg',
                    'title' => 'Kontakty a mapa',
                    'text' => 'Navštivte naši půjčovnu motorek v Pelhřimově nebo nás kontaktujte.',
                    'btn' => 'KONTAKT',
                    'href' => '/kontakt',
                ],
                [
                    'icon' => 'gfx/ico-faq.svg',
                    'title' => 'Často kladené dotazy',
                    'text' => 'Nejčastější dotazy k půjčení motorky přehledně na jednom místě.',
                    'btn' => 'ČASTÉ DOTAZY',
                    'href' => '/jak-pujcit/faq',
                ],
                [
                    'icon' => 'gfx/ico-trasy.svg',
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
                        'icon' => 'gfx/ico-step1.svg',
                        'title' => '1. Vyber',
                        'text' => 'Vyberte si svou ideální motorku z naší nabídky motorek na pronájem.',
                    ],
                    [
                        'icon' => 'gfx/ico-step2.svg',
                        'title' => '2. Rezervuj',
                        'text' => 'Zarezervujte si půjčení motorky přes náš jednoduchý online systém.',
                    ],
                    [
                        'icon' => 'gfx/ico-step3.svg',
                        'title' => '3. Převzetí',
                        'text' => 'Vyzvedněte si motorku v naší půjčovně motorek v Pelhřimově.',
                    ],
                    [
                        'icon' => 'gfx/ico-step4.svg',
                        'title' => '4. Užij jízdu',
                        'text' => 'Užijte si svobodu a objevte Česko na motorkách k zapůjčení.',
                    ],
                ],
            ],
            'faq' => [
                'title' => 'Často kladené otázky',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    [
                        'q' => 'Jak si mohu rezervovat motorku?',
                        'a' => 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.',
                    ],
                    [
                        'q' => 'Můžu si motorku půjčit i bez předchozí rezervace?',
                        'a' => 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit – online, telefonicky, e-mailem nebo přes sociální sítě.',
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
                'title' => 'O půjčovně motorek | MotoGo24',
                'description' => 'Půjčovna motorek Motogo24 na Vysočině. Bez kauce, s online rezervací a výbavou v ceně. Cestovní, sportovní, enduro i dětské motorky. Nonstop provoz.',
                'keywords' => 'půjčovna motorek, pronájem motorek Vysočina, motorky bez kauce, nonstop půjčovna, výbava v ceně',
            ],
            'breadcrumb' => [
                [
                    'label' => 'Domů',
                    'href' => '/',
                ],
                'Půjčovna motorek',
            ],
            'intro' => [
                'h1' => 'Půjčovna motorek Vysočina Motogo24',
                'body' => 'Naše <strong>půjčovna motorek Vysočina</strong> v Pelhřimově nabízí <strong>pronájem motorek</strong> bez zbytečných překážek – <strong>bez kauce</strong>, s <strong>online rezervací</strong> a <strong>výbavou v ceně</strong>. Vyberete si z <strong>cestovních</strong>, <strong>sportovních</strong>, <strong>enduro</strong> i <strong>dětských motorek</strong>, a vyrazíte kdykoli: máme otevřeno <strong>nonstop</strong>.',
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
                        'icon' => 'gfx/ico-online-rez.svg',
                        'title' => 'Online rezervace',
                        'text' => 'na pár kliknutí',
                    ],
                    [
                        'icon' => 'gfx/ico-vybava.svg',
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
                        'icon' => 'gfx/ico-pristaveni.svg',
                        'title' => 'Přistavení i vrácení motorky',
                        'text' => 'na domluvené místo',
                    ],
                ],
            ],
            'process' => [
                'title' => 'Jak probíhá půjčení motorky na Vysočině',
                'steps' => [
                    [
                        'icon' => 'gfx/ico-step1.svg',
                        'title' => '1. Vyber motorku',
                        'text' => 'Prohlédni si naši nabídku, vyber si typ, který ti vyhovuje, odpovídá tvým zkušenostem a řidičskému oprávnění.',
                    ],
                    [
                        'icon' => 'gfx/ico-step3.svg',
                        'title' => '2. Rezervuj online',
                        'text' => 'Uskutečni rezervaci podle data nebo podle konkrétní motorky, kterou si chceš půjčit.',
                    ],
                    [
                        'icon' => 'gfx/ico-step4.svg',
                        'title' => '3. Vyber výbavu',
                        'text' => 'Výbava pro řidiče je v ceně, pro spolujezdce za příplatek. Velikost si můžeš zvolit až na místě.',
                    ],
                    [
                        'icon' => 'gfx/ico-step5.svg',
                        'title' => '4. Zaplať',
                        'text' => 'Zaplať jednoduše online prostřednictvím platební brány.',
                    ],
                    [
                        'icon' => 'gfx/ico-step6.svg',
                        'title' => '5. Převezmi motorku',
                        'text' => 'Motorku si vyzvedni přímo v půjčovně, nebo na místě, které jsi zvolil při rezervaci.',
                    ],
                    [
                        'icon' => 'gfx/ico-step7.svg',
                        'title' => '6. Užij si jízdu',
                        'text' => 'Vyraz na cestu, objevuj nové zážitky a užij si naplno svobodu na dvou kolech.',
                    ],
                    [
                        'icon' => 'gfx/ico-step8.svg',
                        'title' => '7. Vrať motorku',
                        'text' => 'Motorku jednoduše vrať ve sjednaný den – přímo v půjčovně, nebo na předem domluveném místě.',
                    ],
                    [
                        'icon' => 'gfx/ico-sleva.svg',
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
                        'a' => 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Případně se nám můžeš ozvat e-mailem, telefonicky nebo přes naše sociální sítě.',
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
                'title' => 'Kontakt | MotoGo24 – půjčovna motorek Vysočina',
                'description' => 'Kontakty na půjčovnu motorek Motogo24 v Pelhřimově. Telefon +420 774 256 271, e-mail info@motogo24.cz. Nonstop provoz, adresa Mezná 9, 393 01 Pelhřimov.',
                'keywords' => 'kontakt Motogo24, půjčovna motorek Pelhřimov, telefon, adresa, provozní doba, nonstop',
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
                    'value' => 'iuw3vnb',
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
                'hours' => 'PO – NE: 00:00 – 24:00 (nonstop)<br>Včetně víkendů a svátků',
                'billing_title' => 'Fakturační údaje',
                'billing_name' => 'Bc. Petra Semorádová',
                'billing_address' => 'Mezná 9, 393 01 Pelhřimov',
                'billing_ico' => '21874263',
                'billing_vat' => 'Nejsem plátce DPH',
                'billing_note' => 'Společnost byla zapsána dne 31. 7. 2024 u Městského úřadu v Pelhřimově.',
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
        ],
        'jak_pujcit' => [
            'seo' => [
                'title' => 'Jak si půjčit motorku | MotoGo24',
                'description' => 'Jak si půjčit motorku v Motogo24. Jednoduchý postup: výběr, rezervace, převzetí. Bez kauce, výbava v ceně, nonstop provoz.',
                'keywords' => 'jak si půjčit motorku, postup půjčení, rezervace motorky, pronájem motorek Vysočina',
            ],
            'h1' => 'Jak si půjčit motorku',
            'intro' => 'V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové.',
            'links' => [
                [
                    'href' => '/jak-pujcit/postup',
                    'label' => 'Postup půjčení motorky',
                ],
                [
                    'href' => '/jak-pujcit/prevzeti',
                    'label' => 'Převzetí v půjčovně',
                ],
                [
                    'href' => '/jak-pujcit/vraceni-pujcovna',
                    'label' => 'Vrácení motocyklu v půjčovně',
                ],
                [
                    'href' => '/jak-pujcit/vraceni-jinde',
                    'label' => 'Vrácení motorky jinde',
                ],
                [
                    'href' => '/jak-pujcit/co-v-cene',
                    'label' => 'Co je v ceně nájmu',
                ],
                [
                    'href' => '/jak-pujcit/pristaveni',
                    'label' => 'Přistavení motocyklu',
                ],
                [
                    'href' => '/jak-pujcit/dokumenty',
                    'label' => 'Dokumenty a návody',
                ],
                [
                    'href' => '/jak-pujcit/faq',
                    'label' => 'Často kladené dotazy',
                ],
            ],
        ],
        'jak_pujcit_postup' => [
            'seo' => [
                'title' => 'Postup půjčení motorky | MotoGo24',
                'description' => 'Postup půjčení motorky v Motogo24 krok za krokem. Online rezervace, výbava v ceně, bez kauce, nonstop provoz a možnost přistavení.',
                'keywords' => 'postup půjčení motorky, jak půjčit motorku, rezervace motorky, pronájem motorek Pelhřimov',
            ],
            'h1' => 'Postup půjčení motorky',
            'intro' => '<p>V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové. <strong>Bez kauce, s výbavou v ceně a nonstop provozem</strong>. Podívej se, jak snadno to funguje.</p><p>&nbsp;</p><h2>Jak si půjčit motorku – půjčovna Motogo24 Vysočina</h2><p>V <strong>půjčovně motorek Motogo24</strong> je <strong>postup půjčení motorky</strong> jednoduchý: <strong>online rezervace</strong>, <strong>výbava v ceně</strong>, <strong>bez kauce</strong>, <strong>nonstop provoz</strong> a možnost <strong>přistavení motorky</strong>. Ať hledáš <strong>cestovní motorku</strong> na víkend, <strong>sportovní motorku</strong> pro adrenalin nebo <strong>enduro</strong> do terénu, u nás najdeš ideální řešení.</p>',
            'process' => [
                'title' => 'Jak probíhá pronájem krok za krokem',
                'steps' => [
                    [
                        'icon' => 'gfx/ico-step1.svg',
                        'title' => '1. Vyber motorku',
                        'text' => 'Prohlédni si naši nabídku <strong>cestovních, sportovních, enduro i dětských motorek</strong> a vyber si tu pravou.',
                    ],
                    [
                        'icon' => 'gfx/ico-step2.svg',
                        'title' => '2. Počet jezdců',
                        'text' => 'Zvol, jestli pojedeš sám, nebo se spolujezdcem. Nabídneme ti vhodné stroje a výbavu.',
                    ],
                    [
                        'icon' => 'gfx/ico-step3.svg',
                        'title' => '3. Rezervace online',
                        'text' => 'Jednoduše si zarezervuj motorku podle data. Platbu proveď předem <strong>online</strong>.',
                    ],
                    [
                        'icon' => 'gfx/ico-step4.svg',
                        'title' => '4. Výbava v ceně',
                        'text' => 'Automaticky, jako řidič, dostaneš helmu, bundu, kalhoty a rukavice. Velikost si vybereš při rezervaci.',
                    ],
                    [
                        'icon' => 'gfx/ico-step5.svg',
                        'title' => '5. Potvrzení a platba',
                        'text' => 'Rezervace je závazná po potvrzení. Platbu provedeš online.',
                    ],
                    [
                        'icon' => 'gfx/ico-step6.svg',
                        'title' => '6. Převzetí motorky',
                        'text' => 'Převezmeš motorku osobně v Pelhřimově nebo využiješ <strong>přistavení</strong> na domluvené místo.',
                    ],
                    [
                        'icon' => 'gfx/ico-step7.svg',
                        'title' => '7. Užij si jízdu',
                        'text' => 'Vyraz na cestu – <strong>bez kauce, bez stresu</strong>, s jasnými podmínkami a pojištěním v ceně.',
                    ],
                    [
                        'icon' => 'gfx/ico-step8.svg',
                        'title' => '8. Vrácení motorky',
                        'text' => 'Motorku vrátíš kdykoli během posledního dne výpůjčky. Nemusíš tankovat ani mýt.',
                    ],
                ],
            ],
            'faq' => [
                'title' => 'Často kladené otázky',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    [
                        'q' => 'Je nutná kauce při půjčení?',
                        'a' => 'Ne. <strong>Půjčujeme bez kauce</strong> – férově a bez zbytečných překážek.',
                    ],
                    [
                        'q' => 'Je v ceně půjčovného i výbava?',
                        'a' => 'Ano. Každý řidič dostane <strong>helmu, bundu, kalhoty a rukavice zdarma</strong>.',
                    ],
                    [
                        'q' => 'Kde si mohu motorku převzít?',
                        'a' => 'Vyzvednutí probíhá v Pelhřimově, případně nabízíme <strong>přistavení motorky</strong> na tebou zvolené místo.',
                    ],
                    [
                        'q' => 'Do kdy musím motorku vrátit?',
                        'a' => 'Motorku můžeš vrátit kdykoli během posledního dne výpůjčky – klidně i o půlnoci.',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Připraven na jízdu?',
                'text' => 'Rezervuj si motorku online ještě dnes a užij si <strong>svobodu na dvou kolech</strong>.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT ONLINE',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                    ],
                ],
            ],
        ],
        'jak_pujcit_vyzvednuti' => [
            'seo' => [
                'title' => 'Převzetí motocyklu v půjčovně | MotoGo24',
                'description' => 'Převzetí motorky v půjčovně Pelhřimov. Nonstop provoz, bez kauce, výbava v ceně. Co si vzít s sebou a jak probíhá předání.',
                'keywords' => 'převzetí motorky v půjčovně, vyzvednutí motocyklu, půjčovna Pelhřimov, nonstop převzetí',
            ],
            'h1' => 'Převzetí motocyklu v půjčovně – rychle, jednoduše a nonstop',
            'intro' => 'V <strong>Motogo24 – půjčovna motorek Vysočina</strong> je <strong>převzetí motorky</strong> otázkou pár minut. Půjčujeme <strong>bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop provozem</strong>.',
            'top_cta' => [
                'label' => 'REZERVOVAT ONLINE',
                'href' => '/rezervace',
            ],
            'place' => [
                'title' => 'Kde probíhá převzetí',
                'address' => 'Mezná 9, 393 01 <strong>Pelhřimov</strong> (Vysočina)',
                'hours' => '<em>nonstop</em>',
                'phone' => '+420 774 256 271',
                'return_title' => 'Vrácení motorky – bez stresu',
                'return_text' => 'Motorku můžeš vrátit <strong>kdykoli během posledního dne výpůjčky</strong>. Více informací viz <a href="/jak-pujcit/vraceni-pujcovna">vrácení v půjčovně</a> nebo <a href="/jak-pujcit/vraceni-jinde">vrácení jinde</a>.',
                'map_src' => 'https://frame.mapy.cz/s/?x=15.15413&y=49.35169&z=14&source=coor&id=15.15413%2C49.35169',
            ],
            'steps' => [
                'title' => 'Jak probíhá převzetí krok za krokem',
                'items' => [
                    [
                        'icon' => 'gfx/ico-step1.svg',
                        'title' => 'Přijď v domluvený čas',
                        'text' => 'na naši adresu nebo vyčkej na přistavení',
                    ],
                    [
                        'icon' => 'gfx/ico-step2.svg',
                        'title' => 'Ověříme doklady',
                        'text' => 'OP/pas + řidičský průkaz odpovídající skupiny',
                    ],
                    [
                        'icon' => 'gfx/ico-step3.svg',
                        'title' => 'Předáme motorku a výbavu',
                        'text' => 'helma, bunda, kalhoty, rukavice',
                    ],
                    [
                        'icon' => 'gfx/ico-step4.svg',
                        'title' => 'Krátké seznámení se strojem',
                        'text' => 'ovládání, tipy, doporučení k trase',
                    ],
                    [
                        'icon' => 'gfx/ico-step5.svg',
                        'title' => 'Podepíšeme předávací protokol',
                        'text' => 'a můžeš vyrazit',
                    ],
                ],
            ],
            'bring' => [
                'title' => 'Co si vzít s sebou',
                'items' => [
                    '<strong>Občanský průkaz / pas</strong>',
                    '<strong>Řidičský průkaz</strong> odpovídající skupiny (A/A2 podle motorky)',
                    '<strong>Vhodnou obuv</strong> (moto boty lze půjčit jako nadstandard)',
                ],
                'cta' => [
                    'label' => 'ZAREZERVOVAT TERMÍN',
                    'href' => '/rezervace',
                ],
            ],
            'faq' => [
                'title' => 'Časté dotazy k převzetí',
                'items' => [
                    [
                        'q' => 'Musím platit kauci při převzetí?',
                        'a' => 'Ne, <strong>půjčujeme bez kauce</strong>. Podmínky jsou jasně dané a férové.',
                    ],
                    [
                        'q' => 'Je možný kontakt bez osobního setkání?',
                        'a' => 'Ano, nabízíme <strong>bezkontaktní předání</strong> po domluvě.',
                    ],
                    [
                        'q' => 'Co když nestíhám domluvený čas?',
                        'a' => 'Dej nám vědět telefonicky – přizpůsobíme čas, nebo nabídneme <strong>přistavení</strong>.',
                    ],
                    [
                        'q' => 'Je v ceně i výbava pro spolujezdce?',
                        'a' => 'Výbava pro řidiče je v ceně vždy. Výbavu pro spolujezdce lze přiobjednat jako <strong>nadstandard</strong>.',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Převzetí motorky v půjčovně – Motogo24 Vysočina',
                'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop převzetím i vrácením</strong>, <strong>bez kauce</strong> a s <strong>výbavou v ceně</strong>.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT ONLINE',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                    ],
                ],
            ],
        ],
        'jak_pujcit_vraceni_pujcovna' => [
            'seo' => [
                'title' => 'Vrácení motocyklu v půjčovně | MotoGo24',
                'description' => 'Vrácení motorky přímo v půjčovně Pelhřimov. Nonstop, bez kauce, bez zbytečné administrativy. Jak probíhá vrácení motorky krok za krokem.',
                'keywords' => 'vrácení motorky, vrácení motocyklu v půjčovně, půjčovna Pelhřimov, nonstop vrácení motorky',
            ],
            'h1' => 'Vrácení motocyklu v půjčovně',
            'intro' => 'Motorku vracíš pohodlně přímo v <strong>Motogo24 – půjčovně motorek na Vysočině</strong>. <strong>Nonstop provoz</strong>, žádný stres a férové podmínky.',
            'top_cta' => [
                'label' => 'REZERVOVAT ONLINE',
                'href' => '/rezervace',
            ],
            'place' => [
                'title' => 'Kde a kdy motorku vrátit',
                'address' => 'Mezná 9, 393 01 <strong>Pelhřimov</strong> (Vysočina)',
                'hours' => '<em>nonstop</em> – kdykoli během posledního dne výpůjčky',
                'phone' => '+420 774 256 271',
                'note_title' => 'Co je potřeba splnit',
                'note_text' => 'Motorku vracej <strong>v dohodnutém čase</strong> a v podobném technickém stavu, v jakém jsi ji převzal/a. <strong>Plnou nádrž ani mytí nevyžadujeme.</strong>',
                'map_src' => 'https://frame.mapy.cz/s/?x=15.15413&y=49.35169&z=14&source=coor&id=15.15413%2C49.35169',
            ],
            'steps' => [
                'title' => 'Jak vrácení v půjčovně probíhá',
                'items' => [
                    [
                        'icon' => 'gfx/ico-step1.svg',
                        'title' => 'Přijeď v dohodnutém čase',
                        'text' => 'na adresu půjčovny v Pelhřimově',
                    ],
                    [
                        'icon' => 'gfx/ico-step2.svg',
                        'title' => 'Společně projdeme stav motorky',
                        'text' => 'kontrola karoserie, nádrže a výbavy',
                    ],
                    [
                        'icon' => 'gfx/ico-step3.svg',
                        'title' => 'Vrátíš výbavu',
                        'text' => 'helma, bunda, kalhoty, rukavice',
                    ],
                    [
                        'icon' => 'gfx/ico-step4.svg',
                        'title' => 'Podepíšeme protokol o vrácení',
                        'text' => 'jasný a férový záznam',
                    ],
                    [
                        'icon' => 'gfx/ico-step5.svg',
                        'title' => 'Hotovo',
                        'text' => 'pošleme ti potvrzení e-mailem',
                    ],
                ],
            ],
            'tips' => [
                'title' => 'Praktické tipy k vrácení',
                'items' => [
                    '<strong>Plnou nádrž nevyžadujeme</strong> – pohonné hmoty se účtují jen v případě potřeby.',
                    '<strong>Mytí motorky není nutné</strong> – běžné znečištění z jízdy je v pořádku.',
                    '<strong>Pozdní vrácení</strong> hlas předem telefonicky, abychom domluvili řešení.',
                    '<strong>Bezkontaktní vrácení</strong> je možné po předchozí domluvě.',
                ],
                'cta' => [
                    'label' => 'ZAREZERVOVAT TERMÍN',
                    'href' => '/rezervace',
                ],
            ],
            'faq' => [
                'title' => 'Časté dotazy k vrácení v půjčovně',
                'items' => [
                    [
                        'q' => 'Co když nestihnu domluvený čas vrácení?',
                        'a' => 'Dej nám prosím vědět telefonicky. Většinou se domluvíme na <strong>posunutí o pár hodin</strong>; delší prodlení může být zpoplatněno dle ceníku.',
                    ],
                    [
                        'q' => 'Musím motorku umýt?',
                        'a' => 'Ne. Běžné znečištění je v pořádku, mytí <strong>nevyžadujeme</strong>.',
                    ],
                    [
                        'q' => 'Musím motorku vrátit s plnou nádrží?',
                        'a' => 'Není to povinné. Pokud nádrž není plná, doplníme palivo a <strong>doúčtujeme jen reálnou cenu</strong> bez přirážek.',
                    ],
                    [
                        'q' => 'Co když je půjčovna zavřená?',
                        'a' => 'Provoz je <strong>nonstop</strong>. V noci stačí zavolat na +420 774 256 271 a domluvíme předání.',
                    ],
                    [
                        'q' => 'Můžu vrátit motorku na jiném místě?',
                        'a' => 'Ano, využij <a href="/jak-pujcit/vraceni-jinde"><strong>vrácení motorky jinde</strong></a> (přistavení/svoz dle ceníku).',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Vrácení motorky v půjčovně – Motogo24 Pelhřimov',
                'text' => 'Vrať motorku přímo u nás v Pelhřimově – <strong>nonstop, bez kauce, bez stresu</strong>.',
                'buttons' => [
                    [
                        'label' => 'REZERVOVAT ONLINE',
                        'href' => '/rezervace',
                        'cls' => 'btndark pulse',
                    ],
                ],
            ],
        ],
        'poukazy' => [
            'seo' => [
                'title' => 'Půjčovna motorek Vysočina - Poukazy',
                'description' => 'Kupte dárkový poukaz na pronájem motorky. Platnost 3 roky, bez kauce, výbava v ceně. Elektronický i tištěný poukaz. Online objednávka.',
                'keywords' => 'dárkový poukaz motorka, voucher pronájem motorky, dárek pro motorkáře, poukaz Motogo24, půjčovna motorek Vysočina',
                'og_image' => 'https://motogo24.cz/gfx/darkovy-poukaz.jpg',
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
                    'icon' => 'gfx/ico-step1.svg',
                    'title' => '1. Vyber',
                    'text' => 'Vybereš si hodnotu poukazu nebo konkrétní motorku.',
                ],
                [
                    'icon' => 'gfx/ico-step2.svg',
                    'title' => '2. Zaplať',
                    'text' => 'Zaplatíš online.',
                ],
                [
                    'icon' => 'gfx/ico-step3.svg',
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
                    '<strong>Cestovní motorky</strong> – víkendový roadtrip po Vysočině i celé ČR.',
                    '<strong>Sportovní motorky</strong> – adrenalinová jízda v zatáčkách.',
                    '<strong>Enduro</strong> – lehký terén a dobrodružství mimo hlavní cesty.',
                    '<strong>Dětské motorky</strong> – první jízdy pro malé jezdce pod dohledem.',
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
                        'a' => 'Na <strong>cestovní, sportovní, enduro i dětské motorky</strong> v nabídce Motogo24 – podle zvolené hodnoty poukazu.',
                    ],
                ],
            ],
            'cta' => [
                'title' => 'Dárkový poukaz na pronájem motorky – Vysočina',
                'text' => 'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop provozem</strong>, <strong>bez kauce</strong> a <strong>výbavou v ceně</strong>. Dárkový voucher je ideální volba, jak darovat <em>motorbike rental</em> zážitek – od <strong>cestovních</strong> přes <strong>sportovní</strong> až po <strong>enduro</strong> a <strong>dětské motorky</strong>.',
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
