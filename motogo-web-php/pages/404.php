<?php
// ===== MotoGo24 Web PHP — 404 Stránka nenalezena =====

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Stránka nenalezena']);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>Stránka nenalezena</h1><p>Hledaná stránka neexistuje.</p>' .
    '<p><a class="btn btngreen" href="' . BASE_URL . '/">Zpět na úvodní stránku</a></p></div></div></main>';

renderPage('Stránka nenalezena | MotoGo24', $content, '/404', [
    'robots' => 'noindex,follow',
]);
