<?php
// ===== MotoGo24 Web PHP — FAQ stránka s taby (CMS-driven) =====

$sb = new SupabaseClient();

$defaults = [
    'seo' => [
        'title' => 'Často kladené dotazy | MotoGo24',
        'description' => 'Často kladené dotazy k pronájmu motorky. Rezervace, vyzvednutí, vrácení, podmínky, přistavení, cestování do zahraničí, dárkové poukazy.',
        'keywords' => 'FAQ půjčovna motorek, otázky pronájem motorky, podmínky půjčení, kauce, výbava',
    ],
    'h1' => 'Často kladené dotazy – půjčovna motorek Motogo24',
    'closing' => 'Naše <strong>půjčovna motorek Vysočina</strong> je tu pro všechny, kdo chtějí zažít <strong>nezapomenutelnou jízdu</strong> bez zbytečných komplikací.',
    'cta' => ['label' => 'Rezervovat motorku online', 'href' => '/rezervace'],
    'categories' => [
        'reservations' => [
            'label' => 'Rezervace',
            'items' => [
                ['q' => 'Jak probíhá rezervace?', 'a' => 'Motorku si zarezervuješ přes náš <strong>online rezervační systém</strong>. Vybereš termín, motorku a výbavu. Potvrzení přijde e-mailem.'],
                ['q' => 'Musím mít rezervaci předem?', 'a' => 'Ano, bez předchozí rezervace neumíme zaručit dostupnost konkrétní motorky.'],
                ['q' => 'Jak zaplatím?', 'a' => 'Online kartou (Visa/Mastercard, Apple/Google Pay) nebo PayPal.'],
            ],
        ],
        'borrowing' => [
            'label' => 'Výpůjčka a vrácení',
            'items' => [
                ['q' => 'Kde probíhá vyzvednutí a vrácení?', 'a' => 'V <strong>Pelhřimově (Mezná 9)</strong>. Nabízíme i <a href="/jak-pujcit/pristaveni">přistavení</a> na domluvené místo.'],
                ['q' => 'Do kdy musím motorku vrátit?', 'a' => 'Kdykoli během <strong>posledního dne výpůjčky</strong>, klidně i o půlnoci.'],
                ['q' => 'Musím vracet s plnou nádrží a čistou?', 'a' => 'Ne. U nás <strong>netankuješ ani nemyješ</strong>. Jen prosíme o ohleduplné zacházení.'],
                ['q' => 'Je možné vyřídit vše bez osobního kontaktu?', 'a' => 'Ano, po domluvě zajišťujeme <strong>bezkontaktní předání</strong>.'],
                ['q' => 'Co dělat, když nestihnu domluvený čas?', 'a' => '<strong>Stačí nám zavolat</strong> – společně najdeme náhradní termín.'],
            ],
        ],
        'conditions' => [
            'label' => 'Výbava a podmínky',
            'items' => [
                ['q' => 'Je v ceně půjčovného výbava řidiče?', 'a' => 'Ano. <strong>Helma, bunda, kalhoty, rukavice</strong> jsou vždy v ceně pro řidiče.'],
                ['q' => 'Je v ceně zahrnutá i výbava pro spolujezdce?', 'a' => 'Základní výbava pro řidiče je součástí, výbavu pro spolujezdce si můžeš <strong>přiobjednat jako doplňkovou službu</strong>.'],
                ['q' => 'Je nutná kauce?', 'a' => 'Ne. Motorky půjčujeme <strong>bez kauce</strong> a bez skrytých poplatků.'],
                ['q' => 'Jaké doklady potřebuji?', 'a' => '<strong>OP/pas</strong> a <strong>řidičský průkaz</strong> odpovídající skupiny (A/A2 dle motorky).'],
            ],
        ],
        'delivery' => [
            'label' => 'Přistavení',
            'items' => [
                ['q' => 'Můžete motorku přistavit k hotelu/na nádraží?', 'a' => 'Ano, zajišťujeme <strong>přistavení motorky</strong> na domluvené místo. Cena dle vzdálenosti od Pelhřimova.'],
                ['q' => 'Jak přistavení objednám?', 'a' => 'Při <strong>online rezervaci</strong> doplň adresu a čas. Potvrdíme přesnou cenu.'],
                ['q' => 'Lze vrátit motorku jinde, než byla převzata?', 'a' => 'Ano, nabízíme <strong>svoz</strong> – účtujeme dle ceníku přistavení/svozu.'],
                ['q' => 'Jaká je cena přistavení mimo Vysočinu?', 'a' => 'Cena se odvíjí od ujeté vzdálenosti – <strong>do 100 km dle ceníku</strong>, dále <strong>individuální kalkulace</strong>.'],
            ],
        ],
        'travel' => [
            'label' => 'Cesty do zahraničí',
            'items' => [
                ['q' => 'Mohu s motorkou vycestovat do zahraničí?', 'a' => 'Ano, ale drž se <strong>územní platnosti pojištění</strong> (zelená karta). Některé země mohou být vyloučené.'],
                ['q' => 'Potřebuji něco speciálního do zahraničí?', 'a' => 'Měj u sebe <strong>malý TP</strong>, <strong>zelenou kartu</strong>, kontakty na Motogo24 a <strong>kopii nájemní smlouvy</strong>. Doporučujeme cestovní pojištění.'],
            ],
        ],
        'vouchers' => [
            'label' => 'Poukazy',
            'items' => [
                ['q' => 'Jaká je platnost dárkového poukazu?', 'a' => '<strong>3 roky</strong> od data vystavení. Termín si obdarovaný volí sám dle dostupnosti.'],
                ['q' => 'Na jaké motorky lze poukaz uplatnit?', 'a' => 'Na <strong>cestovní, sportovní, enduro i dětské</strong> modely dle hodnoty poukazu a oprávnění.'],
                ['q' => 'Musí obdarovaný platit kauci?', 'a' => '<strong>Ne, žádná kauce se neskládá.</strong> Podmínky jsou transparentní a výbava pro řidiče je v ceně.'],
                ['q' => 'Jak voucher doručíte?', 'a' => '<strong>Okamžitě e-mailem</strong> po úhradě (PDF/JPG). Na požádání i tištěný voucher.'],
                ['q' => 'Dá se termín uplatnění změnit?', 'a' => 'Ano, po předchozí domluvě je možné termín upravit podle aktuální dostupnosti.'],
            ],
        ],
    ],
];

$C = $sb->siteContent('faq', $defaults);

// Postprocess: link expand + aggregate
$allItems = [];
$cats = $C['categories'];
foreach ($cats as $k => &$cat) {
    foreach ($cat['items'] as &$it) {
        // relative href → BASE_URL prefix
        $it['a'] = preg_replace_callback('/href="(\/[^"]+)"/', function ($m) { return 'href="' . BASE_URL . $m[1] . '"'; }, $it['a']);
    }
    unset($it);
    $allItems = array_merge($allItems, $cat['items']);
}
unset($cat);

$tabs = [['id' => 'all', 'label' => 'Vše (' . count($allItems) . ')', 'items' => $allItems]];
foreach ($cats as $id => $cat) {
    $tabs[] = ['id' => $id, 'label' => $cat['label'] . ' (' . count($cat['items']) . ')', 'items' => $cat['items']];
}

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], ['label' => 'Jak si půjčit', 'href' => '/jak-pujcit'], 'Často kladené dotazy']);

$tabsHtml = '<ul class="tabs">';
foreach ($tabs as $t) {
    $tabsHtml .= '<li><a class="tab' . ($t['id'] === 'all' ? ' active' : '') . '" href="#' . htmlspecialchars($t['id']) . '" data-tab="' . htmlspecialchars($t['id']) . '">' . htmlspecialchars($t['label']) . '</a></li>';
}
$tabsHtml .= '</ul>';

$panesHtml = '<div class="tab-content">';
foreach ($tabs as $t) {
    $panesHtml .= '<div class="tab-pane' . ($t['id'] === 'all' ? ' active' : '') . '" id="' . htmlspecialchars($t['id']) . '"><div class="gr2">';
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
    '<div class="ccontent"><h1>' . htmlspecialchars($C['h1']) . '</h1>' .
    $tabsHtml . $panesHtml .
    '<p>&nbsp;</p><p>' . $C['closing'] . '</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['cta']['href'] . '">' . htmlspecialchars($C['cta']['label']) . '</a></p>' .
    '</div></div></main>' . $tabJs;

// FAQPage schema
$faqSchemaItems = [];
foreach ($allItems as $faq) {
    $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode(strip_tags($faq['q']), JSON_UNESCAPED_UNICODE) . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode(strip_tags($faq['a']), JSON_UNESCAPED_UNICODE) . '}}';
}
$faqSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}
  </script>';

renderPage($C['seo']['title'], $content, '/jak-pujcit/faq', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => 'Domů', 'url' => 'https://motogo24.cz/'],
        ['name' => 'Jak si půjčit', 'url' => 'https://motogo24.cz/jak-pujcit'],
        ['name' => 'FAQ', 'url' => 'https://motogo24.cz/jak-pujcit/faq'],
    ],
]);
