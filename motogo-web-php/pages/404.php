<?php
// ===== MotoGo24 Web PHP — 404 Stránka nenalezena =====

$bc = renderBreadcrumb([['label' => t('breadcrumb.home'), 'href' => '/'], t('breadcrumb.notFound')]);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent"><h1>' . te('notFound.heading') . '</h1><p>' . te('notFound.message') . '</p>' .
    '<p><a class="btn btngreen" href="' . BASE_URL . '/">' . te('notFound.backHome') . '</a></p></div></div></main>';

renderPage(t('notFound.title'), $content, '/404', [
    'robots' => 'noindex,follow',
]);
