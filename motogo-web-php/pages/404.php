<?php
// ===== MotoGo24 Web PHP — 404 Stránka nenalezena =====

echo renderHead('Stránka nenalezena – Motogo24', 'Stránka, kterou hledáte, nebyla nalezena.');
echo renderHeader();

echo '<main id="content"><div class="container">' .
    '<div class="ccontent">' .
    '<h1>Stránka nenalezena</h1>' .
    '<p>Omlouváme se, ale stránka, kterou hledáte, neexistuje nebo byla přesunuta.</p>' .
    '<p>&nbsp;</p>' .
    '<p><a class="btn btngreen" href="/">Zpět na úvodní stránku</a></p>' .
    '</div></div></main>';

echo renderFooter();
echo renderPageEnd();
