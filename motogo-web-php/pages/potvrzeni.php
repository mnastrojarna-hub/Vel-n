<?php
// ===== MotoGo24 Web PHP — Potvrzení rezervace/objednávky =====
// Interaktivní stránka — JS zůstává pro polling stavu platby.

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Potvrzení']);

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<div id="potvrzeni-app"><div class="loading-overlay"><span class="spinner"></span> Načítám stav objednávky...</div></div>' .
    '</div></div></main>';

// Inline JS — potvrzovací stránka
$potvrzeniJs = '<script>
window.MOTOGO_CONFIG = {
  SUPABASE_URL: ' . json_encode(SUPABASE_URL) . ',
  SUPABASE_ANON_KEY: ' . json_encode(SUPABASE_ANON_KEY) . '
};
</script>
<script src="js/supabase-sdk.js"></script>
<script src="js/supabase-init.js"></script>
<script src="js/api.js"></script>
<script src="js/components.js"></script>
<script src="js/pages-potvrzeni.js"></script>';

renderPage('Potvrzení – Motogo24', $content . $potvrzeniJs, '/potvrzeni');
