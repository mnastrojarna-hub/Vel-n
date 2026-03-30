<?php
// ===== MotoGo24 Web PHP — Dokumenty a návody =====

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Dokumenty a návody']);

$paymentTable = renderTable(
    ['Položka', 'Podmínky'],
    [
        ['<strong>Platba nájemného</strong>', 'Online předem.'],
        ['<strong>Storno rezervace</strong>', 'Lze bezplatně do předem domluveného času.'],
        ['<strong>Palivo & čištění</strong>', 'Vrácení bez povinnosti dotankovat a mýt.'],
        ['<strong>Přistavení / svoz</strong>', 'Dle ceníku přistavení.'],
        ['<strong>Pozdní vrácení</strong>', 'Při zpoždění účtujeme dle domluvy.'],
    ]
);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<section><h1>Nájemní smlouva a kauce – férové podmínky bez zálohy</h1>' .
    '<p>V <strong>Motogo24</strong> klademe důraz na jednoduchost a férovost. Půjčujeme <strong>bez kauce</strong>, s <strong>jasnou nájemní smlouvou</strong>, <strong>pojištěním v ceně</strong> a <strong>výbavou pro řidiče</strong>.</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/rezervace">REZERVOVAT ONLINE</a></p></section>' .

    '<section><h2>Shrnutí hlavních bodů</h2><div class="gr6">' .
    renderWbox('gfx/ico-bez-kauce.svg', 'Bez kauce / zálohy', 'motorku půjčujeme bez blokace peněz') .
    renderWbox('gfx/ico-pojisteni.svg', 'Pojištění', 'v ceně (povinné ručení; havarijní dle konkrétního modelu a podmínek)') .
    renderWbox('gfx/ico-vybava.svg', 'Výbava pro řidiče', 'v ceně (helma, bunda, kalhoty, rukavice)') .
    renderWbox('gfx/ico-nonstop.svg', 'Nonstop provoz', 'převzetí a vrácení kdykoli v den výpůjčky') .
    renderWbox('gfx/ico-jasna-pravidla.svg', 'Jasná pravidla užívání', 'doma i v zahraničí (podle zelené karty)') .
    renderWbox('gfx/ico-bezskryte.svg', 'Žádné skryté poplatky', 'vše je uvedeno níže a ve smlouvě') .
    '</div></section>' .

    '<section><h2>Co potřebujete k uzavření smlouvy</h2><ul>' .
    '<li><strong>Občanský průkaz / pas</strong></li><li><strong>Řidičský průkaz</strong> odpovídající skupiny</li>' .
    '<li><strong>Věk</strong> min. 18 let</li><li><strong>Kontakty</strong> (telefon, e-mail)</li></ul>' .
    '<p>&nbsp;</p><h2>Platby, storno a poplatky</h2>' . $paymentTable . '</section>' .

    '<section><div class="gr2"><div><h2>Užívání motorky a odpovědnost</h2><ul>' .
    '<li>Jezděte v <strong>souladu s předpisy</strong></li>' .
    '<li>Za <strong>pokuty a přestupky</strong> odpovídá nájemce</li>' .
    '<li><strong>Zahraničí</strong>: možné; řiďte se územní platností pojištění</li>' .
    '<li>V případě <strong>nehody nebo poruchy</strong> postupujte dle pokynů</li>' .
    '<li><strong>Úpravy motorky</strong> bez souhlasu nejsou dovoleny</li></ul></div>' .
    '<div><h2>Předání a vrácení</h2><ul>' .
    '<li><strong>Převzetí</strong> v Pelhřimově nebo <a href="' . BASE_URL . '/jak-pujcit/pristaveni">přistavení</a></li>' .
    '<li>Při předání obdržíte <strong>klíče, výbavu a dokumenty</strong></li>' .
    '<li><strong>Vrácení</strong> kdykoli během posledního dne výpůjčky</li></ul></div></div></section>' .

    renderCta('Nájemní smlouva bez kauce – půjčovna motorek Vysočina',
        'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s férovými podmínkami.',
        [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']]) .
    '</div></div></main>';

renderPage('Dokumenty a návody | MotoGo24', $content, '/jak-pujcit/dokumenty', [
    'description' => 'Nájemní smlouva, dokumenty a podmínky pronájmu motorky. Bez kauce, jasná pravidla, pojištění v ceně. Potřebné doklady pro půjčení.',
    'breadcrumbs' => [['name' => 'Domů', 'url' => 'https://motogo24.cz/'], ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'], ['name' => 'Dokumenty', 'url' => 'https://motogo24.cz/jak-pujcit/dokumenty']],
]);
