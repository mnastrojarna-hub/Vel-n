<?php
// ===== MotoGo24 Web PHP — Postup půjčení (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
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
            ['icon' => 'gfx/ico-step1.svg', 'title' => '1. Vyber motorku', 'text' => 'Prohlédni si naši nabídku <strong>cestovních, sportovních, enduro i dětských motorek</strong> a vyber si tu pravou.'],
            ['icon' => 'gfx/ico-step2.svg', 'title' => '2. Počet jezdců', 'text' => 'Zvol, jestli pojedeš sám, nebo se spolujezdcem. Nabídneme ti vhodné stroje a výbavu.'],
            ['icon' => 'gfx/ico-step3.svg', 'title' => '3. Rezervace online', 'text' => 'Jednoduše si zarezervuj motorku podle data. Platbu proveď předem <strong>online</strong>.'],
            ['icon' => 'gfx/ico-step4.svg', 'title' => '4. Výbava v ceně', 'text' => 'Automaticky, jako řidič, dostaneš helmu, bundu, kalhoty a rukavice. Velikost si vybereš při rezervaci.'],
            ['icon' => 'gfx/ico-step5.svg', 'title' => '5. Potvrzení a platba', 'text' => 'Rezervace je závazná po potvrzení. Platbu provedeš online.'],
            ['icon' => 'gfx/ico-step6.svg', 'title' => '6. Převzetí motorky', 'text' => 'Převezmeš motorku osobně v Pelhřimově nebo využiješ <strong>přistavení</strong> na domluvené místo.'],
            ['icon' => 'gfx/ico-step7.svg', 'title' => '7. Užij si jízdu', 'text' => 'Vyraz na cestu – <strong>bez kauce, bez stresu</strong>, s jasnými podmínkami a pojištěním v ceně.'],
            ['icon' => 'gfx/ico-step8.svg', 'title' => '8. Vrácení motorky', 'text' => 'Motorku vrátíš kdykoli během posledního dne výpůjčky. Nemusíš tankovat ani mýt.'],
        ],
    ],
    'faq' => [
        'title' => 'Často kladené otázky',
        'more_link' => '/jak-pujcit/faq',
        'items' => [
            ['q' => 'Je nutná kauce při půjčení?', 'a' => 'Ne. <strong>Půjčujeme bez kauce</strong> – férově a bez zbytečných překážek.'],
            ['q' => 'Je v ceně půjčovného i výbava?', 'a' => 'Ano. Každý řidič dostane <strong>helmu, bundu, kalhoty a rukavice zdarma</strong>.'],
            ['q' => 'Kde si mohu motorku převzít?', 'a' => 'Vyzvednutí probíhá v Pelhřimově, případně nabízíme <strong>přistavení motorky</strong> na tebou zvolené místo.'],
            ['q' => 'Do kdy musím motorku vrátit?', 'a' => 'Motorku můžeš vrátit kdykoli během posledního dne výpůjčky – klidně i o půlnoci.'],
        ],
    ],
    'cta' => [
        'title' => 'Připraven na jízdu?',
        'text' => 'Rezervuj si motorku online ještě dnes a užij si <strong>svobodu na dvou kolech</strong>.',
        'buttons' => [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
    ],
];

$C = $sb->siteContent('jak_pujcit_postup', $defaults);

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Postup půjčení motorky']);

$stepsHtml = '<section aria-labelledby="process"><h2>' . $C['process']['title'] . '</h2><div class="gr4">';
foreach ($C['process']['steps'] as $s) {
    $stepsHtml .= renderWbox($s['icon'], $s['title'], $s['text']);
}
$stepsHtml .= '</div></section>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . $C['h1'] . '</h1>' . $C['intro'] . $stepsHtml .
    renderFaqSection($C['faq']['title'], $C['faq']['items'], $C['faq']['more_link'] ?? null) .
    renderCta($C['cta']['title'], $C['cta']['text'], $C['cta']['buttons']) .
    '</div></div></main>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/postup', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'Postup půjčení', 'url' => 'https://motogo24.cz/jak-pujcit/postup'],
    ],
]);
