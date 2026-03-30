<?php
// ===== MotoGo24 Web PHP — Co je v ceně =====

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Co je v ceně']);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<section><h1>Co je v ceně pronájmu motorky</h1>' .
    '<p>V <strong>Motogo24 – půjčovna motorek na Vysočině</strong> dostaneš férové podmínky. <strong>Bez kauce, s výbavou v ceně a nonstop provozem</strong>.</p>' .
    '<div class="gr2"><div>' .
    '<h2>Základní výbava zdarma</h2>' .
    '<p>Každý řidič má k dispozici kompletní <strong>motorkářskou výbavu</strong>:</p>' .
    '<ul><li><strong>Helma</strong> – vždy čistá a bezpečná</li><li><strong>Motorkářská bunda</strong> s chrániči</li><li><strong>Moto kalhoty</strong> pro maximální komfort</li><li><strong>Rukavice</strong> ve správné velikosti</li></ul>' .
    '</div><div>' .
    '<h2>Nadstandardní výbava</h2>' .
    '<ul><li><strong>Výbava pro spolujezdce</strong></li><li><strong>Páteřák</strong> pro maximální ochranu</li><li><strong>Chrániče hrudi</strong> (pro enduro/cross)</li><li><strong>Motorkářské boty</strong></li><li><strong>Bluetooth komunikátor</strong></li><li><strong>Kufry</strong> a zavazadlový systém</li></ul>' .
    '</div></div></section>' .

    '<section aria-labelledby="benefits"><h2>Další výhody v ceně</h2><div class="gr6">' .
    renderWbox('gfx/ico-nonstop.svg', 'Nonstop provoz', 'vyzvednutí i vrácení kdykoli') .
    renderWbox('gfx/ico-bez-kauce.svg', 'Bez kauce', 'žádná záloha při půjčení') .
    renderWbox('gfx/ico-pojisteni.svg', 'Pojištění', 'součástí pronájmu') .
    renderWbox('gfx/ico-bezkontaktni.svg', 'Bezkontaktní předání', 'na vyžádání') .
    renderWbox('gfx/ico-jasna-pravidla.svg', 'Jasné podmínky', 'bez skrytých poplatků') .
    '</div></section>' .

    '<section><h2>Rezervuj si motorku s výbavou v ceně</h2>' .
    '<p>Vyber si z nabídky <strong>cestovních, sportovních, enduro i dětských motorek</strong> a vyraž na cestu bez starostí. Vše potřebné máš zahrnuto v půjčovném.</p></section>' .

    renderCta('Výbava v ceně – půjčovna motorek Vysočina',
        'Motogo24 je moderní <strong>půjčovna motorek na Vysočině</strong>. U nás dostaneš <strong>výbavu v ceně</strong>, půjčení <strong>bez kauce</strong>, <strong>online rezervaci</strong> a <strong>nonstop provoz</strong>.',
        [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']]) .
    '</div></div></main>';

renderPage('Co je v ceně pronájmu motorky | MotoGo24', $content, '/jak-pujcit/co-v-cene', [
    'description' => 'Co je v ceně pronájmu motorky. Helma, bunda, kalhoty, rukavice zdarma. Pojištění, nonstop provoz, bez kauce.',
    'breadcrumbs' => [['name' => 'Domů', 'url' => 'https://motogo24.cz/'], ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'], ['name' => 'Co je v ceně', 'url' => 'https://motogo24.cz/jak-pujcit/co-v-cene']],
]);
