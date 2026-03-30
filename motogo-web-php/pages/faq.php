<?php
// ===== MotoGo24 Web PHP — FAQ stránka s taby =====
// Odpovídá pages-faq.js

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Často kladené dotazy']);

$faqData = [
    'reservations' => [
        ['q' => 'Jak probíhá rezervace?', 'a' => 'Motorku si zarezervuješ přes náš <strong>online rezervační systém</strong>. Vybereš termín, motorku a výbavu. Potvrzení přijde e-mailem.'],
        ['q' => 'Musím mít rezervaci předem?', 'a' => 'Ano, bez předchozí rezervace neumíme zaručit dostupnost konkrétní motorky.'],
        ['q' => 'Jak zaplatím?', 'a' => 'Online kartou (Visa/Mastercard, Apple/Google Pay) nebo PayPal.'],
    ],
    'borrowing' => [
        ['q' => 'Kde probíhá vyzvednutí a vrácení?', 'a' => 'V <strong>Pelhřimově (Mezná 9)</strong>. Nabízíme i <a href="' . BASE_URL . '/jak-pujcit/pristaveni">přistavení</a> na domluvené místo.'],
        ['q' => 'Do kdy musím motorku vrátit?', 'a' => 'Kdykoli během <strong>posledního dne výpůjčky</strong>, klidně i o půlnoci.'],
        ['q' => 'Musím vracet s plnou nádrží a čistou?', 'a' => 'Ne. U nás <strong>netankuješ ani nemyješ</strong>. Jen prosíme o ohleduplné zacházení.'],
        ['q' => 'Je možné vyřídit vše bez osobního kontaktu?', 'a' => 'Ano, po domluvě zajišťujeme <strong>bezkontaktní předání</strong>.'],
        ['q' => 'Co dělat, když nestihnu domluvený čas?', 'a' => '<strong>Stačí nám zavolat</strong> – společně najdeme náhradní termín.'],
    ],
    'conditions' => [
        ['q' => 'Je v ceně půjčovného výbava řidiče?', 'a' => 'Ano. <strong>Helma, bunda, kalhoty, rukavice</strong> jsou vždy v ceně pro řidiče.'],
        ['q' => 'Je v ceně zahrnutá i výbava pro spolujezdce?', 'a' => 'Základní výbava pro řidiče je součástí, výbavu pro spolujezdce si můžeš <strong>přiobjednat jako doplňkovou službu</strong>.'],
        ['q' => 'Je nutná kauce?', 'a' => 'Ne. Motorky půjčujeme <strong>bez kauce</strong> a bez skrytých poplatků.'],
        ['q' => 'Jaké doklady potřebuji?', 'a' => '<strong>OP/pas</strong> a <strong>řidičský průkaz</strong> odpovídající skupiny (A/A2 dle motorky).'],
    ],
    'delivery' => [
        ['q' => 'Můžete motorku přistavit k hotelu/na nádraží?', 'a' => 'Ano, zajišťujeme <strong>přistavení motorky</strong> na domluvené místo. Cena dle vzdálenosti od Pelhřimova.'],
        ['q' => 'Jak přistavení objednám?', 'a' => 'Při <strong>online rezervaci</strong> doplň adresu a čas. Potvrdíme přesnou cenu.'],
        ['q' => 'Lze vrátit motorku jinde, než byla převzata?', 'a' => 'Ano, nabízíme <strong>svoz</strong> – účtujeme dle ceníku přistavení/svozu.'],
        ['q' => 'Jaká je cena přistavení mimo Vysočinu?', 'a' => 'Cena se odvíjí od ujeté vzdálenosti – <strong>do 100 km dle ceníku</strong>, dále <strong>individuální kalkulace</strong>.'],
    ],
    'travel' => [
        ['q' => 'Mohu s motorkou vycestovat do zahraničí?', 'a' => 'Ano, ale drž se <strong>územní platnosti pojištění</strong> (zelená karta). Některé země mohou být vyloučené.'],
        ['q' => 'Potřebuji něco speciálního do zahraničí?', 'a' => 'Měj u sebe <strong>malý TP</strong>, <strong>zelenou kartu</strong>, kontakty na Motogo24 a <strong>kopii nájemní smlouvy</strong>. Doporučujeme cestovní pojištění.'],
    ],
    'vouchers' => [
        ['q' => 'Jaká je platnost dárkového poukazu?', 'a' => '<strong>3 roky</strong> od data vystavení. Termín si obdarovaný volí sám dle dostupnosti.'],
        ['q' => 'Na jaké motorky lze poukaz uplatnit?', 'a' => 'Na <strong>cestovní, sportovní, enduro i dětské</strong> modely dle hodnoty poukazu a oprávnění.'],
        ['q' => 'Musí obdarovaný platit kauci?', 'a' => '<strong>Ne, žádná kauce se neskládá.</strong> Podmínky jsou transparentní a výbava pro řidiče je v ceně.'],
        ['q' => 'Jak voucher doručíte?', 'a' => '<strong>Okamžitě e-mailem</strong> po úhradě (PDF/JPG). Na požádání i tištěný voucher.'],
        ['q' => 'Dá se termín uplatnění změnit?', 'a' => 'Ano, po předchozí domluvě je možné termín upravit podle aktuální dostupnosti.'],
    ],
];

$allItems = array_merge(
    $faqData['reservations'], $faqData['borrowing'], $faqData['conditions'],
    $faqData['delivery'], $faqData['travel'], $faqData['vouchers']
);

$tabs = [
    ['id' => 'all', 'label' => 'Vše (' . count($allItems) . ')', 'items' => $allItems],
    ['id' => 'reservations', 'label' => 'Rezervace (' . count($faqData['reservations']) . ')', 'items' => $faqData['reservations']],
    ['id' => 'borrowing', 'label' => 'Výpůjčka a vrácení (' . count($faqData['borrowing']) . ')', 'items' => $faqData['borrowing']],
    ['id' => 'conditions', 'label' => 'Výbava a podmínky (' . count($faqData['conditions']) . ')', 'items' => $faqData['conditions']],
    ['id' => 'delivery', 'label' => 'Přistavení (' . count($faqData['delivery']) . ')', 'items' => $faqData['delivery']],
    ['id' => 'travel', 'label' => 'Cesty do zahraničí (' . count($faqData['travel']) . ')', 'items' => $faqData['travel']],
    ['id' => 'vouchers', 'label' => 'Poukazy (' . count($faqData['vouchers']) . ')', 'items' => $faqData['vouchers']],
];

$tabsHtml = '<ul class="tabs">';
foreach ($tabs as $t) {
    $tabsHtml .= '<li><a class="tab' . ($t['id'] === 'all' ? ' active' : '') . '" href="#' . $t['id'] . '" data-tab="' . $t['id'] . '">' . $t['label'] . '</a></li>';
}
$tabsHtml .= '</ul>';

$panesHtml = '<div class="tab-content">';
foreach ($tabs as $t) {
    $panesHtml .= '<div class="tab-pane' . ($t['id'] === 'all' ? ' active' : '') . '" id="' . $t['id'] . '"><div class="gr2">';
    foreach ($t['items'] as $faq) {
        $panesHtml .= renderFaqItem($faq['q'], $faq['a']);
    }
    $panesHtml .= '</div></div>';
}
$panesHtml .= '</div>';

$tabJs = '<script>
document.querySelectorAll(".tab[data-tab]").forEach(function(t){
  t.addEventListener("click", function(e){
    e.preventDefault();
    var tabId = t.getAttribute("data-tab");
    document.querySelectorAll(".tab").forEach(function(el){ el.classList.remove("active"); });
    document.querySelectorAll(".tab-pane").forEach(function(el){ el.classList.remove("active"); });
    t.classList.add("active");
    var pane = document.getElementById(tabId);
    if(pane) pane.classList.add("active");
  });
});
</script>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>Často kladené dotazy – půjčovna motorek Motogo24</h1>' .
    $tabsHtml . $panesHtml .
    '<p>&nbsp;</p><p>Naše <strong>půjčovna motorek Vysočina</strong> je tu pro všechny, kdo chtějí zažít <strong>nezapomenutelnou jízdu</strong> bez zbytečných komplikací.</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . '/rezervace">Rezervovat motorku online</a></p>' .
    '</div></div></main>' . $tabJs;

renderPage('Často kladené dotazy – Motogo24', $content, '/jak-pujcit/faq');
