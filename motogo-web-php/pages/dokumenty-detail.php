<?php
// ===== MotoGo24 Web PHP — Detail dokumentu (z document_templates ve Velíně) =====
// Zobrazí HTML obsah šablony + nabídne tisk/uložení do PDF přes browser print.
// Všechny veřejné smluvní/informační dokumenty (VOP, smlouva, GDPR, protokoly)
// jsou jeden zdroj pravdy: Velín → Dokumenty → Smluvní texty.

$sb = new SupabaseClient();

// Mapa veřejných slug → typ šablony v `document_templates` + lidský název
$DOC_MAP = [
    'obchodni-podminky'             => ['type' => 'vop',               'title' => 'Obchodní podmínky (VOP)'],
    'smlouva-o-pronajmu'            => ['type' => 'rental_contract',   'title' => 'Smlouva o pronájmu motocyklu'],
    'predavaci-protokol'            => ['type' => 'handover_protocol', 'title' => 'Předávací protokol'],
    'protokol-o-poskozeni'          => ['type' => 'damage_protocol',   'title' => 'Protokol o poškození'],
    'zasady-ochrany-osobnich-udaju' => ['type' => 'gdpr',               'title' => 'Zásady ochrany osobních údajů (GDPR)'],
    'gdpr'                          => ['type' => 'gdpr',               'title' => 'Zásady ochrany osobních údajů (GDPR)'],
];

$slug    = $_GET['doc_slug'] ?? '';
$wantPdf = !empty($_GET['format']) && $_GET['format'] === 'pdf';
$entry   = $DOC_MAP[$slug] ?? null;

if (!$entry) {
    http_response_code(404);
    require __DIR__ . '/404.php';
    return;
}

$tpl = $sb->fetchDocumentTemplate($entry['type']);

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

$tplHtml = $tpl && !empty($tpl['content_html']) ? $tpl['content_html'] : '';

// `format=pdf` → vrátí samostatný HTML dokument optimalizovaný pro tisk/uložení
// jako PDF (Ctrl+P → Save as PDF). Žádné navigační prvky webu, jen čistý obsah.
// Backend-side PDF render přes PDFShift se může přidat později — pro většinu
// uživatelů je browser print → PDF dostatečné a okamžitě k dispozici.
if ($wantPdf) {
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: no-store');
    $title = htmlspecialchars($entry['title']);
    echo '<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>' . $title . '</title>';
    echo '<style>' . $DOC_CSS . '</style></head>';
    echo '<body class="doc-render" onload="setTimeout(function(){window.print()},250)">';
    echo $tplHtml ?: '<p>Dokument zatím nebyl publikován.</p>';
    echo '</body></html>';
    exit;
}

// HTML stránka v rámci webu — breadcrumbs, nadpis, obsah šablony, akční tlačítka.
$bc = renderBreadcrumb([
    ['label' => t('breadcrumb.home'), 'href' => '/'],
    ['label' => t('menu.howto.documents') ?? 'Dokumenty', 'href' => '/jak-pujcit/dokumenty'],
    $entry['title'],
]);

$title = htmlspecialchars($entry['title']);
$pdfHref = BASE_URL . '/dokumenty/' . urlencode($slug) . '?format=pdf';

$body = '<main id="content"><div class="container">' . $bc;
$body .= '<style>' . $DOC_CSS . '</style>';
$body .= '<div class="ccontent">';
$body .= '<h1>' . $title . '</h1>';

if (!$tpl || empty($tplHtml)) {
    $body .= '<p>Tento dokument zatím nebyl publikován. Pro detaily nás prosím <a href="' . BASE_URL . '/kontakt">kontaktujte</a>.</p>';
} else {
    if (!empty($tpl['updated_at'])) {
        $body .= '<p style="color:#6b7a72;font-size:13px">Verze ' . (int)($tpl['version'] ?? 1)
              . ' &middot; aktualizováno ' . htmlspecialchars(date('d. m. Y', strtotime($tpl['updated_at']))) . '</p>';
    }
    $body .= '<div class="no-print" style="display:flex;gap:8px;margin:12px 0 20px">';
    $body .= '<a class="btn btngreen" href="' . htmlspecialchars($pdfHref) . '" target="_blank" rel="noopener">'
          .  '<img src="' . BASE_URL . '/gfx/ico-stahnout.svg" alt="" style="height:16px;vertical-align:middle;margin-right:6px">'
          .  'Stáhnout / Tisk (PDF)</a>';
    $body .= '</div>';
    $body .= '<article class="doc-render" style="border:1px solid #e2ece7;border-radius:12px;background:#fff;padding:24px">'
          .  $tplHtml
          .  '</article>';
}

$body .= '</div></div></main>';

renderPage($entry['title'] . ' | MotoGo24', $body, '/dokumenty/' . $slug, [
    'description' => $entry['title'] . ' — aktuální znění dokumentu MotoGo24, online ke stažení v PDF.',
]);
