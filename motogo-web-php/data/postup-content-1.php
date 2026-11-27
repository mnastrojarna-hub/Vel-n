<?php
// ===== MotoGo24 — Postup pujceni motorky 1/2 (intro + proces 12x) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/postup-pujceni-motorky
// 2026-10-15: intro_p2, krok 5, krok 12 a FAQ (data 2/2) — mista prevzeti dle majitele
//       (Mezna u Pelhrimova + samoobsluzna pobocka Velke Nemcice); ".." opraveno.
// 2026-11-27: copy/SEO revize — h1, intro_p1 (uz bez preklepu "pujcove"), intro_h2,
//       kroky 6, 9, 10 a 11 (samoobsluzna pobocka, kody, vraceni do 24:00).

return [
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
];
