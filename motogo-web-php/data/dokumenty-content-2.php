<?php
// ===== MotoGo24 — Dokumenty a navody 2/2 (uzivani + predani + GDPR + PDF + CTA + SEO) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/dokumenty-a-navody

return [
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
];
