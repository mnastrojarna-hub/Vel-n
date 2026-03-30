<?php
// ===== MotoGo24 Web PHP — Rezervace =====
// Interaktivní stránka — JS zůstává pro kalendář, formulář a Stripe platby.
// PHP renderuje jen shell + header/footer, JS se načítá ze souborů.

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'Rezervace']);

// Předvyplnění z query stringu
$motoId = $_GET['moto'] ?? '';
$startDate = $_GET['start'] ?? '';
$endDate = $_GET['end'] ?? '';
$delivery = $_GET['delivery'] ?? '';
$resume = $_GET['resume'] ?? '';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent">' .
    '<h1>Online rezervace motorky</h1>' .
    '<p>Zarezervujte si <strong>motorku na pronájem</strong> přes náš jednoduchý systém. <strong>Bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop provozem</strong>.</p>' .
    '<p>&nbsp;</p>' .
    '<div id="rezervace-app"><div class="loading-overlay"><span class="spinner"></span> Načítám rezervační systém...</div></div>' .
    '</div></div></main>';

// Inline JS — rezervační systém se načte z původních JS souborů
$rezervaceJs = '<script>
window.MOTOGO_CONFIG = {
  SUPABASE_URL: ' . json_encode(SUPABASE_URL) . ',
  SUPABASE_ANON_KEY: ' . json_encode(SUPABASE_ANON_KEY) . '
};
window.REZERVACE_PARAMS = {
  moto: ' . json_encode($motoId) . ',
  start: ' . json_encode($startDate) . ',
  end: ' . json_encode($endDate) . ',
  delivery: ' . json_encode($delivery) . ',
  resume: ' . json_encode($resume) . '
};
</script>
<script src="js/supabase-sdk.js"></script>
<script src="js/supabase-init.js"></script>
<script src="js/api.js"></script>
<script src="js/components.js"></script>
<script src="js/pages-rezervace-calendar.js"></script>
<script src="js/pages-rezervace-pricing.js"></script>
<script src="js/pages-rezervace-steps.js"></script>
<script src="js/pages-rezervace-scan.js"></script>
<script src="js/pages-rezervace.js"></script>';

renderPage('Online rezervace motorky – Motogo24', $content . $rezervaceJs, '/rezervace');
