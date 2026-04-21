<?php
// ===== MotoGo24 Web PHP — Vyzvednutí motocyklu =====

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Vyzvednutí motocyklu']);

$mapIframe = '<iframe class="map" loading="lazy" src="https://frame.mapy.cz/s/?x=15.15413&y=49.35169&z=14&source=coor&id=15.15413%2C49.35169" title="Jak se k nám dostanete"></iframe>';

$faqItems = [
    ['q' => 'Musím platit kauci při vyzvednutí?', 'a' => 'Ne, <strong>půjčujeme bez kauce</strong>. Podmínky jsou jasně dané a férové.'],
    ['q' => 'Je možný kontakt bez osobního setkání?', 'a' => 'Ano, nabízíme <strong>bezkontaktní předání</strong> po domluvě.'],
    ['q' => 'Co když nestíhám domluvený čas?', 'a' => 'Dej nám vědět telefonicky – přizpůsobíme čas, nebo nabídneme <strong>přistavení</strong>.'],
    ['q' => 'Je v ceně i výbava pro spolujezdce?', 'a' => 'Výbava pro řidiče je v ceně vždy. Výbavu pro spolujezdce lze přiobjednat jako <strong>nadstandard</strong>.'],
];

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<section><h1>Vyzvednutí motocyklu – rychle, jednoduše a nonstop</h1>' .
    '<p>V <strong>Motogo24 – půjčovna motorek Vysočina</strong> je <strong>vyzvednutí motorky</strong> otázkou pár minut. Půjčujeme <strong>bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop provozem</strong>.</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/rezervace">REZERVOVAT ONLINE</a></p></section>' .

    '<section><div class="gr2"><div>' .
    '<h2>Kde probíhá vyzvednutí</h2>' .
    '<p><strong>Provozovna:</strong> Mezná 9, 393 01 <strong>Pelhřimov</strong> (Vysočina)</p>' .
    '<p><strong>Provozní doba:</strong> <em>nonstop</em></p>' .
    '<p><strong>Telefon:</strong> <a href="tel:+420774256271">+420 774 256 271</a></p>' .
    '<p>&nbsp;</p><h2>Vrácení motorky – bez stresu</h2>' .
    '<p>Motorku můžeš vrátit <strong>kdykoli během posledního dne výpůjčky</strong>. Nevyžadujeme vrácení s plnou nádrží ani mytí.</p>' .
    '</div><div><p>' . $mapIframe . '</p></div></div></section>' .

    '<section><h2>Jak probíhá vyzvednutí krok za krokem</h2><div class="gr5">' .
    renderWbox('gfx/ico-step1.svg', 'Přijď v domluvený čas', 'na naši adresu nebo vyčkej na přistavení') .
    renderWbox('gfx/ico-step2.svg', 'Ověříme doklady', 'OP/pas + řidičský průkaz odpovídající skupiny') .
    renderWbox('gfx/ico-step3.svg', 'Předáme motorku a výbavu', 'helma, bunda, kalhoty, rukavice') .
    renderWbox('gfx/ico-step4.svg', 'Krátké seznámení se strojem', 'ovládání, tipy, doporučení k trase') .
    renderWbox('gfx/ico-step5.svg', 'Podepíšeme předávací protokol', 'a můžeš vyrazit') .
    '</div></section>' .

    '<section><h2>Co si vzít s sebou</h2><ul>' .
    '<li><strong>Občanský průkaz / pas</strong></li>' .
    '<li><strong>Řidičský průkaz</strong> odpovídající skupiny (A/A2 podle motorky)</li>' .
    '<li><strong>Vhodnou obuv</strong> (moto boty lze půjčit jako nadstandard)</li>' .
    '</ul><p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/rezervace">ZAREZERVOVAT TERMÍN</a></p></section>' .

    renderFaqSection('Časté dotazy k vyzvednutí', $faqItems) .
    renderCta('Vyzvednutí motorky – půjčovna motorek Vysočina',
        'Motogo24 je <strong>půjčovna motorek na Vysočině</strong> s <strong>nonstop vyzvednutím i vrácením</strong>, <strong>bez kauce</strong> a s <strong>výbavou v ceně</strong>.',
        [['label' => 'REZERVOVAT ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse']]) .
    '</div></div></main>';

renderPage('Vyzvednutí motocyklu | MotoGo24', $content, '/jak-pujcit/vyzvednuti', [
    'description' => 'Vyzvednutí motorky v Pelhřimově. Nonstop provoz, bez kauce, výbava v ceně. Co si vzít s sebou a jak probíhá předání.',
    'breadcrumbs' => [['name' => 'Domů', 'url' => 'https://motogo24.cz/'], ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'], ['name' => 'Vyzvednutí', 'url' => 'https://motogo24.cz/jak-pujcit/vyzvednuti']],
]);
