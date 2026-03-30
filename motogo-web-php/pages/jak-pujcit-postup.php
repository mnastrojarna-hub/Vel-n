<?php
// ===== MotoGo24 Web PHP — Postup půjčení =====

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Postup půjčení motorky']);
$intro = '<h1>Postup půjčení motorky</h1>' .
    '<p>V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> je půjčení jednoduché, rychlé a férové. <strong>Bez kauce, s výbavou v ceně a nonstop provozem</strong>. Podívej se, jak snadno to funguje.</p>' .
    '<p>&nbsp;</p><h2>Jak si půjčit motorku – půjčovna Motogo24 Vysočina</h2>' .
    '<p>V <strong>půjčovně motorek Motogo24</strong> je <strong>postup půjčení motorky</strong> jednoduchý: <strong>online rezervace</strong>, <strong>výbava v ceně</strong>, <strong>bez kauce</strong>, <strong>nonstop provoz</strong> a možnost <strong>přistavení motorky</strong>. Ať hledáš <strong>cestovní motorku</strong> na víkend, <strong>sportovní motorku</strong> pro adrenalin nebo <strong>enduro</strong> do terénu, u nás najdeš ideální řešení.</p>';

$steps = '<section aria-labelledby="process"><h2>Jak probíhá pronájem krok za krokem</h2><div class="gr4">' .
    renderWbox('gfx/ico-step1.svg', '1. Vyber motorku', 'Prohlédni si naši nabídku <strong>cestovních, sportovních, enduro i dětských motorek</strong> a vyber si tu pravou.') .
    renderWbox('gfx/ico-step2.svg', '2. Počet jezdců', 'Zvol, jestli pojedeš sám, nebo se spolujezdcem. Nabídneme ti vhodné stroje a výbavu.') .
    renderWbox('gfx/ico-step3.svg', '3. Rezervace online', 'Jednoduše si zarezervuj motorku podle data. Platbu proveď předem <strong>online</strong>.') .
    renderWbox('gfx/ico-step4.svg', '4. Výbava v ceně', 'Automaticky, jako řidič, dostaneš helmu, bundu, kalhoty a rukavice. Velikost si vybereš při rezervaci.') .
    renderWbox('gfx/ico-step5.svg', '5. Potvrzení a platba', 'Rezervace je závazná po potvrzení. Platbu provedeš online.') .
    renderWbox('gfx/ico-step6.svg', '6. Převzetí motorky', 'Převezmeš motorku osobně v Pelhřimově nebo využiješ <strong>přistavení</strong> na domluvené místo.') .
    renderWbox('gfx/ico-step7.svg', '7. Užij si jízdu', 'Vyraz na cestu – <strong>bez kauce, bez stresu</strong>, s jasnými podmínkami a pojištěním v ceně.') .
    renderWbox('gfx/ico-step8.svg', '8. Vrácení motorky', 'Motorku vrátíš kdykoli během posledního dne výpůjčky. Nemusíš tankovat ani mýt.') .
    '</div></section>';

$faqItems = [
    ['q' => 'Je nutná kauce při půjčení?', 'a' => 'Ne. <strong>Půjčujeme bez kauce</strong> – férově a bez zbytečných překážek.'],
    ['q' => 'Je v ceně půjčovného i výbava?', 'a' => 'Ano. Každý řidič dostane <strong>helmu, bundu, kalhoty a rukavice zdarma</strong>.'],
    ['q' => 'Kde si mohu motorku převzít?', 'a' => 'Vyzvednutí probíhá v Pelhřimově, případně nabízíme <strong>přistavení motorky</strong> na tebou zvolené místo.'],
    ['q' => 'Do kdy musím motorku vrátit?', 'a' => 'Motorku můžeš vrátit kdykoli během posledního dne výpůjčky – klidně i o půlnoci.'],
];

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' . $intro . $steps .
    renderFaqSection('Často kladené otázky', $faqItems, '/jak-pujcit/faq') .
    renderCta('Připraven na jízdu?', 'Rezervuj si motorku online ještě dnes a užij si <strong>svobodu na dvou kolech</strong>.', [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']]) .
    '</div></div></main>';

renderPage('Postup půjčení motorky – Motogo24', $content, '/jak-pujcit/postup');
