<?php
// ===== MotoGo24 Web PHP — Detail dokumentu (z document_templates ve Velíně) =====
// Zobrazí HTML obsah šablony + nabídne tisk/uložení do PDF přes browser print.
// Všechny veřejné smluvní/informační dokumenty (VOP, smlouva, GDPR, protokoly)
// jsou jeden zdroj pravdy: Velín → Dokumenty → Smluvní texty (`document_templates`).
// Seznam dokumentů je kanonický (mgPublicDocuments()) — stejný na všech doménách,
// názvy přeložené přes i18n. Obsah šablony se zobrazí v jazyce návštěvníka, pokud
// admin doplnil překlad (document_templates.content_translations), jinak CZ originál.
//
// Vlastní dokumenty (Velín → Dokumenty → Vlastní dokumenty, tabulka `custom_documents`)
// se zobrazí pod libovolným slugem mimo kanonický seznam. Typ Text podporuje firemní
// proměnné ({{firma}}…). Cizojazyčné verze čerpají z `custom_documents.translations`
// (plní edge fn `translate-document`); přeložené PDF se na cizí verzi zobrazí jako
// HTML stránka, český originál PDF zůstává.

$sb   = new SupabaseClient();
$lang = function_exists('i18nDetectLanguage') ? i18nDetectLanguage() : 'cs';

// Firemní proměnné pro typ "Text" (custom_documents.kind='html').
// Statické hodnoty z config.php — žádné per-rezervační údaje (dokument není
// navázaný na booking). Podporované: {{firma}} {{ico}} {{adresa}} {{telefon}}
// {{email}} {{web}} {{datum}} (+ varianty s mezerami: {{ firma }}).
function fillDocVars($html) {
    if ($html === '' || strpos($html, '{{') === false) return $html;
    $map = [
        'firma'   => defined('COMPANY_NAME') ? COMPANY_NAME : '',
        'ico'     => defined('COMPANY_ICO') ? COMPANY_ICO : '',
        'adresa'  => defined('COMPANY_ADDRESS') ? COMPANY_ADDRESS : '',
        'telefon' => defined('PHONE') ? PHONE : '',
        'email'   => defined('EMAIL_FULL') ? EMAIL_FULL : '',
        'web'     => 'www.motogo24.cz',
        'datum'   => date('d. m. Y'),
    ];
    return preg_replace_callback('/\{\{\s*([a-z_]+)\s*\}\}/i', function ($m) use ($map) {
        $k = strtolower($m[1]);
        return array_key_exists($k, $map) ? htmlspecialchars($map[$k]) : $m[0];
    }, $html);
}

// Mapa veřejných slug → ['type' => document_templates.type, 'title' => přeložený název].
// Kanonický seznam je v components.php::mgPublicDocuments(). `gdpr` má i zkrácený alias.
$DOC_MAP = [];
foreach (mgPublicDocuments() as $d) {
    $DOC_MAP[$d['slug']] = ['type' => $d['type'], 'title' => $d['title']];
}
if (isset($DOC_MAP['zasady-ochrany-osobnich-udaju'])) {
    $DOC_MAP['gdpr'] = $DOC_MAP['zasady-ochrany-osobnich-udaju'];
}

$slug    = $_GET['doc_slug'] ?? '';
$wantPdf = !empty($_GET['format']) && $_GET['format'] === 'pdf';
$entry   = $DOC_MAP[$slug] ?? null;

$tpl = null;
if ($entry) {
    // Pevná smluvní šablona (document_templates) — obsah v jazyce návštěvníka řeší
    // níže RPC get_document_translation (content_translations[lang]); přeložený NÁZEV
    // bere z name_translations[lang] (plní ho edge fn translate-document), fallback i18n.
    $row = $sb->fetchDocumentTemplate($entry['type']);
    if ($row) {
        if ($lang !== 'cs') {
            $nt = $row['name_translations'] ?? null;
            if (is_string($nt)) { $dec = json_decode($nt, true); $nt = is_array($dec) ? $dec : null; }
            if (is_array($nt) && !empty($nt[$lang]) && is_string($nt[$lang])) $entry['title'] = $nt[$lang];
        }
        $tpl = [
            'content_html' => $row['content_html'] ?? '',
            'version'      => $row['version'] ?? 1,
            'updated_at'   => $row['updated_at'] ?? null,
        ];
    }
} else {
    // Vlastní dokument vytvořený ve Velíně (tabulka custom_documents).
    $cd = $sb->fetchCustomDocument($slug);
    if ($cd) {
        $isPdf = (($cd['kind'] ?? 'html') === 'pdf');
        // U PDF: pokud existuje překlad obsahu pro aktuální (cizí) jazyk, zobrazíme
        // ho jako HTML stránku; jinak (čeština nebo bez překladu) → redirect na PDF.
        $trHtml = ($lang !== 'cs') ? localized($cd, 'content_html') : '';
        $hasTrHtml = ($trHtml !== '' && $trHtml !== ($cd['content_html'] ?? ''));
        if ($isPdf && !$hasTrHtml) {
            $pdfUrl = $cd['pdf_path'] ?? '';
            if ($pdfUrl) { header('Location: ' . $pdfUrl, true, 302); exit; }
        }
        $trTitle = localized($cd, 'title');
        $entry = ['type' => null, 'title' => $trTitle !== '' ? $trTitle : ($cd['title'] ?? 'Dokument')];
        $bodyHtml = $isPdf ? $trHtml : localized($cd, 'content_html');
        $tpl = [
            'content_html' => fillDocVars($bodyHtml),
            'version'      => $cd['version'] ?? 1,
            'updated_at'   => $cd['updated_at'] ?? null,
        ];
    }
}

if (!$entry) {
    http_response_code(404);
    require __DIR__ . '/404.php';
    return;
}

// Obsah v jazyce návštěvníka: u dokumentů z `document_templates` zkus pro non-CZ
// přeloženou variantu přes RPC get_document_translation (čte content_translations[lang]).
// Pokud překlad neexistuje (RPC vrátí null) → fallback na CZ originál content_html,
// aby dokument nebyl nikdy prázdný. Vlastní dokumenty (custom_documents) překlad
// řeší výše přes `localized()` — `$entry['type']` je null.
$rawHtml = $tpl && !empty($tpl['content_html']) ? $tpl['content_html'] : '';
if ($lang !== 'cs' && !empty($entry['type'])) {
    try {
        $translated = $sb->rpc('get_document_translation', [
            'p_template_slug' => $entry['type'],
            'p_language'      => $lang,
        ]);
        if (is_string($translated) && trim($translated) !== '') {
            $rawHtml = $translated;
        }
    } catch (\Throwable $e) { /* fallback na CZ originál */ }
}

// Stejné CSS jako Velín RichTextEditor (ContentEditable .rte-content) — WYSIWYG
// parita: co admin vidí v editoru, to se vyrenderuje na webu i v PDF / tisku.
$DOC_CSS = <<<CSS
:root { color-scheme: light; }
html, body { margin: 0; padding: 0; background: #fff; }
body.doc-render { font-family: 'Segoe UI', system-ui, sans-serif; font-size: 14px; line-height: 1.6; color: #0f1a14; padding: 24px; }
body.doc-render p { margin: 0 0 10px; }
body.doc-render h1 { font-size: 1.8em; font-weight: 800; margin: 14px 0 8px; }
body.doc-render h2 { font-size: 1.45em; font-weight: 800; margin: 12px 0 6px; }
body.doc-render h3 { font-size: 1.2em; font-weight: 700; margin: 10px 0 6px; }
body.doc-render h4 { font-size: 1.05em; font-weight: 700; margin: 8px 0 4px; }
body.doc-render ul, body.doc-render ol { padding-left: 1.4em; margin: 0 0 10px; }
body.doc-render li { margin: 2px 0; }
body.doc-render blockquote { margin: 8px 0; padding: 8px 12px; border-left: 4px solid #74FB71; background: #f1faf7; color: #1a2e22; border-radius: 4px; }
body.doc-render pre { background: #0f1a14; color: #a7f3d0; padding: 10px 12px; border-radius: 8px; font-family: ui-monospace,SFMono-Regular,Menlo,monospace; font-size: 12px; overflow: auto; white-space: pre-wrap; }
body.doc-render a { color: #1d4ed8; text-decoration: underline; }
body.doc-render img { max-width: 100%; height: auto; border-radius: 8px; }
body.doc-render hr { border: none; border-top: 1px solid #d4e8e0; margin: 12px 0; }
body.doc-render table { border-collapse: collapse; width: 100%; }
body.doc-render table td, body.doc-render table th { border: 1px solid #d4e8e0; padding: 4px 8px; }
@media print {
  body.doc-render { padding: 0; }
  .no-print { display: none !important; }
}
CSS;

// SEO sanitace CMS obsahu z Velin RichTextEditor:
//  - <b>/<i>/<font> -> <strong>/<em>/<span> (semantic)
//  - prazdne <strong></strong>/<em></em>/<span></span> -> pryc (Seobility 'Empty tags')
//  - vnoreny <h1> -> <h2> (Seobility 'Multiple H1 in page' — sablona uz ma jeden <h1>)
//  - <iframe>/<script> raw HTML chrana (i kdyz Velin editor by je nemel pustit)
$tplHtml = $rawHtml !== '' ? sanitizeHtml($rawHtml) : '';

// `format=pdf` → vrátí samostatný HTML dokument optimalizovaný pro tisk/uložení
// jako PDF (Ctrl+P → Save as PDF). Žádné navigační prvky webu, jen čistý obsah.
//
// SEO: Print verze NESMÍ jít do Google indexu — vrací noindex/nofollow (HTTP + meta).
if ($wantPdf) {
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Robots-Tag: noindex, nofollow');
    $title    = htmlspecialchars($entry['title']);
    $htmlLang = htmlspecialchars($lang);
    echo '<!DOCTYPE html><html lang="' . $htmlLang . '"><head><meta charset="utf-8"><title>' . $title . '</title>';
    echo '<meta name="robots" content="noindex, nofollow">';
    echo '<style>' . $DOC_CSS . '</style></head>';
    echo '<body class="doc-render" onload="setTimeout(function(){window.print()},250)">';
    echo $tplHtml ?: '<p>' . htmlspecialchars(t('doc.notPublished')) . '</p>';
    echo '</body></html>';
    exit;
}

// HTML stránka v rámci webu — breadcrumbs, nadpis, obsah šablony, akční tlačítka.
$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('menu.howto.documents'), 'href' => '/jak-pujcit/dokumenty'],
    $entry['title'],
]);

$title   = htmlspecialchars($entry['title']);
$pdfHref = BASE_URL . '/dokumenty/' . urlencode($slug) . '?format=pdf';

$body = '<main id="content"><div class="container">' . $bc;
$body .= '<style>' . $DOC_CSS . '</style>';
$body .= '<div class="ccontent">';
$body .= '<h1>' . $title . '</h1>';

if (!$tpl || empty($tplHtml)) {
    $body .= '<p>' . htmlspecialchars(t('doc.notPublished')) . ' <a href="' . BASE_URL . '/kontakt">' . htmlspecialchars(t('common.contactUs')) . '</a></p>';
} else {
    if (!empty($tpl['updated_at'])) {
        $body .= '<p style="color:#6b7a72;font-size:13px">' . htmlspecialchars(t('doc.version', [
            'v'    => (int)($tpl['version'] ?? 1),
            'date' => date('d. m. Y', strtotime($tpl['updated_at'])),
        ])) . '</p>';
    }
    $body .= '<div class="no-print" style="display:flex;gap:8px;margin:12px 0 20px">';
    $body .= '<a class="btn btngreen" href="' . htmlspecialchars($pdfHref) . '" target="_blank" rel="noopener nofollow">'
          .  '<img src="' . BASE_URL . '/gfx/ico-stahnout.svg" alt="" style="height:16px;vertical-align:middle;margin-right:6px">'
          .  htmlspecialchars(t('doc.download')) . '</a>';
    $body .= '</div>';
    $body .= '<article class="doc-render" style="border:1px solid #e2ece7;border-radius:12px;background:#fff;padding:24px">'
          .  $tplHtml
          .  '</article>';
}

// Sdílená SEO outro sekce — Velín → Texty webu → Detail dokumentu
$docDetailDefaults = [
    'outro' => [
        'title' => 'O našich dokumentech',
        'body1' => 'Všechny smluvní dokumenty a protokoly MotoGo24 jsou vždy <strong>aktuální verze</strong> — pravidelně je revidujeme s ohledem na změny v legislativě a zpětnou vazbu zákazníků. Najdete je v textové i tištěné podobě, můžete si je stáhnout ve formátu PDF a vytisknout, nebo si je prohlédnout přímo zde na webu. Plné znění obchodních podmínek, smlouvy o pronájmu a zásad ochrany osobních údajů máme dostupné v sekci <a href="/jak-pujcit/dokumenty">Dokumenty a návody</a>.',
        'body2' => 'Pokud máte jakýkoli dotaz ke smluvním podmínkám, postupu při převzetí nebo vrácení motorky či k pojištění, neváhejte nás kontaktovat. Naše smlouvy záměrně píšeme tak, aby byly <strong>srozumitelné</strong> — bez drobného písma a skrytých podmínek. Pokud chcete dokumenty fyzicky podepsat předem nebo si je s námi projít osobně, můžete přijet do půjčovny v Pelhřimově nebo si je necháme připravit k vyzvednutí.',
    ],
];
$DDC = $sb->siteContent('dokumenty_detail', $docDetailDefaults);
$docOutroT = $DDC['outro']['title'] ?? $docDetailDefaults['outro']['title'];
$docOutroB1 = $DDC['outro']['body1'] ?? $docDetailDefaults['outro']['body1'];
$docOutroB2 = $DDC['outro']['body2'] ?? $docDetailDefaults['outro']['body2'];
$body .= '<section class="dokumenty-detail-outro">'
    . '<h2 data-cms-key="web.dokumenty_detail.outro.title">' . htmlspecialchars($docOutroT) . '</h2>'
    . '<p data-cms-key="web.dokumenty_detail.outro.body1">' . $docOutroB1 . '</p>'
    . '<p data-cms-key="web.dokumenty_detail.outro.body2">' . $docOutroB2 . '</p>'
    . '</section>';

$body .= '</div></div></main>';

// Bohatsi meta description: title + standardni kontext (pujcovna + adresa).
// Bez kontextu byl Seobility 'meta description too short' na vsech /dokumenty/* (cca 17-50 znaku).
// Seobility limit ~1000 px = ~155 znaku (Czech s diakritikou ~6 px/znak).
$metaDesc = $entry['title']
    . ' u půjčovny motorek MotoGo24 Pelhřimov — vzor pro půjčení motocyklu. Bez kauce, výbava v ceně, nonstop provoz na Vysočině.';
$metaDesc = preg_replace('/\s+\S*$/u', '', mb_substr(preg_replace('/\s+/', ' ', $metaDesc), 0, 155));

renderPage($entry['title'] . ' | MotoGo24', $body, '/dokumenty/' . $slug, [
    'description' => $metaDesc,
]);
