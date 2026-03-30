<?php
// ===== MotoGo24 Web PHP — Rezervace =====
// PHP renderuje HTML shell + header/footer, JS zajišťuje interaktivitu
// (kalendář, ceník, mapa, OCR, Stripe platby)

$bc = renderBreadcrumb([['label' => 'Domů', 'href' => '/'], 'REZERVACE']);

// Předvyplnění z query stringu
$motoId = $_GET['moto'] ?? '';
$startDate = $_GET['start'] ?? '';
$endDate = $_GET['end'] ?? '';
$delivery = $_GET['delivery'] ?? '';
$resume = $_GET['resume'] ?? '';

$content = '<main id="content"><div class="container">' . $bc .
    '<div class="ccontent pcontent">' .
    '<h1>Online rezervace motorky</h1>' .
    '<p>Zarezervujte si <strong>motorku na pronájem</strong> přes náš jednoduchý systém. <strong>Bez kauce</strong>, s <strong>výbavou v ceně</strong> a <strong>nonstop provozem</strong>.</p>' .
    '<p>&nbsp;</p>' .
    '<div id="rezervace-app"><div class="loading-overlay"><span class="spinner"></span> Načítám rezervační systém...</div></div>' .
    '</div></div></main>';

// Supabase SDK + konfigurace + JS moduly pro rezervaci
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
<script src="' . BASE_URL . '/js/supabase-sdk.js"></script>
<script src="' . BASE_URL . '/js/supabase-init.js"></script>
<script src="' . BASE_URL . '/js/api.js"></script>
<script src="' . BASE_URL . '/js/components.js"></script>
<script src="' . BASE_URL . '/js/pages-rezervace-calendar.js"></script>
<script src="' . BASE_URL . '/js/pages-rezervace-pricing.js"></script>
<script src="' . BASE_URL . '/js/pages-rezervace-steps.js"></script>
<script src="' . BASE_URL . '/js/pages-rezervace-scan.js"></script>
<script src="' . BASE_URL . '/js/pages-rezervace.js"></script>
<script>
// Spustit inicializaci po načtení všech JS souborů
(function(){
  function tryInit(){
    if(window.sb && MG._rezInit){ MG._rezInit(); }
    else { setTimeout(tryInit, 100); }
  }
  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", function(){ setTimeout(tryInit, 100); });
  } else { setTimeout(tryInit, 100); }
})();
</script>';

renderPage('Online rezervace motorky | MotoGo24', $content . $rezervaceJs, '/rezervace', [
    'description' => 'Online rezervace motorky na Vysočině. Bez kauce, s výbavou v ceně a nonstop provozem. Vyberte motorku, termín a zaplaťte online.',
    'keywords' => 'rezervace motorky online, půjčit motorku, pronájem motorky Vysočina, online booking',
    'robots' => 'noindex,follow',
]);
