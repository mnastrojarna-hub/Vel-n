<?php
// ===== MotoGo24 Web PHP — FAQ stránka (DB-driven) =====
// Položky jsou v Supabase tabulce `faq_items` (spravuje se ve Velíně,
// záložka CMS → Texty webu → Časté dotazy). Chrome (h1, closing, cta, SEO)
// stále řízeno přes `cms_variables` (klíče `web.faq.*`) + tento PHP fallback.

$sb = new SupabaseClient();
$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';

// Chrome stránky (přes siteContent — overlay z cms_variables web.faq.*)
$defaults = [
    'seo' => [
        'title' => 'Časté dotazy k půjčení motorky | Motopůjčovna MotoGo24 Vysočina',
        'description' => 'Nejčastější dotazy k půjčení motorky v motopůjčovně MotoGo24. Odpovědi na rezervaci motorky, podmínky i průběh zapůjčení motocyklu.',
        'keywords' => 'motopůjčovna, půjčovna motorek, časté dotazy půjčovna motorek, podmínky pronájmu motorky, jak si půjčit motorku, MotoGo24',
    ],
    'h1' => 'Často kladené dotazy',
    'closing' => 'Naše <strong>půjčovna motorek Vysočina</strong> je tu pro všechny, kdo chtějí zažít <strong>nezapomenutelnou jízdu</strong> bez zbytečných komplikací. Pronájem je <strong>bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop</strong>.',
    'cta' => ['label' => 'Rezervovat motorku online', 'href' => '/rezervace'],
];
$C = $sb->siteContent('faq', $defaults);

// Položky FAQ z DB — jen published, seřazené podle kategorie a sort_order
$rows = $sb->fetchFaqItems();

// Group by category, použij localized() pro překlady (translations jsonb)
$categories = [];
foreach ($rows as $r) {
    $catKey = $r['category_key'] ?? 'other';
    $catLabel = localized($r, 'category_label', $lang) ?: ($r['category_label'] ?? $catKey);
    if (!isset($categories[$catKey])) {
        $categories[$catKey] = ['label' => $catLabel, 'items' => []];
    }
    $q = localized($r, 'question', $lang) ?: ($r['question'] ?? '');
    $a = localized($r, 'answer', $lang) ?: ($r['answer'] ?? '');
    // Relativní href v odpovědi → BASE_URL prefix (pro správný routing)
    $a = preg_replace_callback('/href="(\/[^"]+)"/', function ($m) { return 'href="' . BASE_URL . $m[1] . '"'; }, $a);
    $categories[$catKey]['items'][] = [
        'id' => $r['id'] ?? '',
        'q' => $q,
        'a' => $a,
    ];
}

$allItems = [];
foreach ($categories as $cat) { $allItems = array_merge($allItems, $cat['items']); }

// SEO: predtim se renderovaly tabs jako oddelene panes (vse + per kategorie).
// Vsechny tabs byly vzdy v DOM, jen JS skryval ne-aktivni. Crawler videl
// kazdou polozku 2x (jednou v 'Vse', jednou v kategorii) -> Seobility hlasil
// 82 duplicate paragraphs (= 41 polozek x 2). Fix: renderujeme polozky JEN
// JEDNOU ve sjednocenem panelu, kategorie funguji jako CSS filter na
// data-faq-category atribut. Zadny duplicate v DOM, ale UX zustava (taby
// stale filtruji co je videt).

$tabs = [['id' => 'all', 'label' => t('faq.tabAll', ['count' => count($allItems)])]];
foreach ($categories as $id => $cat) {
    $tabs[] = ['id' => $id, 'label' => $cat['label'] . ' (' . count($cat['items']) . ')'];
}

$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('breadcrumb.howto'), 'href' => '/jak-pujcit'],
    t('menu.howto.faq'),
]);

$tabsHtml = '<ul class="tabs">';
foreach ($tabs as $tab) {
    $tabsHtml .= '<li><a class="tab' . ($tab['id'] === 'all' ? ' active' : '') . '" href="#' . htmlspecialchars($tab['id']) . '" data-tab="' . htmlspecialchars($tab['id']) . '">' . htmlspecialchars($tab['label']) . '</a></li>';
}
$tabsHtml .= '</ul>';

// Render JEN JEDEN pane se vsemi polozkami. Kazda polozka ma data-faq-category
// pro filtrovani pres CSS class. Tab klik prepne data-active na containeru.
$panesHtml = '<div class="tab-content"><div class="tab-pane active" id="all" data-active="all"><div class="gr2">';
if (empty($allItems)) {
    $panesHtml .= '<p>' . htmlspecialchars(t('faq.empty')) . '</p>';
} else {
    // Pripoj data-faq-category aby JS mohl filtrovat
    foreach ($categories as $catId => $cat) {
        foreach ($cat['items'] as $faq) {
            $catAttr = htmlspecialchars($catId);
            // Render FAQ item s kategorii wrapper
            $panesHtml .= '<div data-faq-category="' . $catAttr . '">' . renderFaqItem($faq['q'], $faq['a']) . '</div>';
        }
    }
}
$panesHtml .= '</div></div></div>';

$tabJs = '<script>
document.querySelectorAll(".tab[data-tab]").forEach(function(t){
  t.addEventListener("click", function(e){
    e.preventDefault();
    var tabId = t.getAttribute("data-tab");
    document.querySelectorAll(".tab").forEach(function(el){ el.classList.remove("active"); });
    t.classList.add("active");
    document.querySelectorAll("[data-faq-category]").forEach(function(item){
      item.style.display = (tabId === "all" || item.getAttribute("data-faq-category") === tabId) ? "" : "none";
    });
  });
});
</script>';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1 data-cms-key="web.faq.h1">' . htmlspecialchars($C['h1']) . '</h1>' .
    $tabsHtml . $panesHtml .
    '<p>&nbsp;</p><p data-cms-key="web.faq.closing">' . $C['closing'] . '</p>' .
    '<p>&nbsp;</p><p><a class="btn btngreen" href="' . BASE_URL . $C['cta']['href'] . '" data-cms-key="web.faq.cta.label">' . htmlspecialchars($C['cta']['label']) . '</a></p>' .
    '</div></div></main>' . $tabJs;

// FAQPage strukturovaná data — Google rich snippet
$faqSchemaItems = [];
foreach ($allItems as $faq) {
    $faqSchemaItems[] = '{"@type":"Question","name":' . json_encode(strip_tags($faq['q']), JSON_UNESCAPED_UNICODE) . ',"acceptedAnswer":{"@type":"Answer","text":' . json_encode(strip_tags($faq['a']), JSON_UNESCAPED_UNICODE) . '}}';
}
$faqSchema = '';
if (!empty($faqSchemaItems)) {
    $faqSchema = '
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"FAQPage","mainEntity":[' . implode(',', $faqSchemaItems) . ']}
  </script>';
}

renderPage($C['seo']['title'], $content, '/jak-pujcit/faq', [
    'description' => $C['seo']['description'],
    'keywords' => $C['seo']['keywords'],
    'schema' => $faqSchema,
    'breadcrumbs' => [
        ['name' => t('breadcrumb.home'), 'url' => siteCanonicalUrl('/')],
        ['name' => t('breadcrumb.howto'), 'url' => siteCanonicalUrl('/jak-pujcit')],
        ['name' => t('menu.howto.faq'), 'url' => siteCanonicalUrl('/jak-pujcit/faq')],
    ],
]);
