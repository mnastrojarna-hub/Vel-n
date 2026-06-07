<?php
// ===== MotoGo24 Web PHP — Smazání účtu a dat (Google Play Data safety) =====
// Veřejná stránka popisující postup, jakým může uživatel aplikace MotoGo24
// požádat o smazání svého účtu a přidružených dat. URL této stránky se zadává
// do Google Play Console → Bezpečnost dat → „Adresa URL ke smazání účtu".

$title = 'Smazání účtu | MotoGo24';
$desc  = 'Jak smazat svůj účet a osobní data v aplikaci MotoGo24 — postup v aplikaci i alternativní žádost e-mailem, rozsah mazaných dat a doba uchování.';

$email = defined('EMAIL_FULL') ? EMAIL_FULL : 'info@motogo24.cz';
$phone = defined('PHONE') ? PHONE : '+420 774 256 271';
$company = defined('COMPANY_NAME') ? COMPANY_NAME : 'Bc. Petra Semorádová';

$bc = '<nav class="breadcrumb" aria-label="Drobečková navigace"><a href="' . BASE_URL . '/">Úvod</a> &rsaquo; <span>Smazání účtu</span></nav>';

$content = '<main id="content"><div class="container"><div class="ccontent" style="max-width:760px;margin:0 auto;line-height:1.7;">'
    . $bc
    . '<h1>Smazání účtu a osobních dat — MotoGo24</h1>'

    . '<p>Tato stránka popisuje, jak můžete jako uživatel aplikace <strong>MotoGo24</strong> '
    . '(provozovatel ' . htmlspecialchars($company) . ') požádat o smazání svého účtu a všech '
    . 'osobních údajů, které s ním souvisejí.</p>'

    . '<h2>1) Smazání přímo v aplikaci (doporučeno)</h2>'
    . '<ol>'
    . '<li>Otevřete aplikaci MotoGo24 a přihlaste se.</li>'
    . '<li>Přejděte do sekce <strong>Profil</strong>.</li>'
    . '<li>Zvolte <strong>Smazat účet</strong>.</li>'
    . '<li>Potvrďte žádost. Účet i přidružená data se smažou.</li>'
    . '</ol>'

    . '<h2>2) Smazání e-mailem</h2>'
    . '<p>Pokud se k aplikaci nemůžete přihlásit, napište nám z e-mailu, kterým jste '
    . 'registrovaní, na adresu <a href="mailto:' . htmlspecialchars($email) . '">'
    . htmlspecialchars($email) . '</a> s předmětem <strong>„Žádost o smazání účtu"</strong>. '
    . 'Žádost vyřídíme nejpozději do <strong>30 dnů</strong>. Pro ověření totožnosti vás '
    . 'můžeme kontaktovat na telefonu ' . htmlspecialchars($phone) . '.</p>'

    . '<h2>Která data budou smazána</h2>'
    . '<p>Po potvrzení žádosti trvale odstraníme zejména:</p>'
    . '<ul>'
    . '<li>přihlašovací údaje a profil (jméno, e-mail, telefon),</li>'
    . '<li>nahrané fotografie a dokumenty (doklady k ověření, fotky k SOS a rezervacím),</li>'
    . '<li>historii konverzací s asistentem a hlášení SOS,</li>'
    . '<li>údaje o poloze sdílené v rámci SOS.</li>'
    . '</ul>'

    . '<h2>Která data a jak dlouho uchováváme</h2>'
    . '<p>Některé údaje jsme ze zákona povinni uchovat i po smazání účtu — zejména '
    . '<strong>účetní a daňové doklady k uskutečněným rezervacím a platbám</strong> '
    . '(vystavené faktury), které uchováváme po dobu vyžadovanou právními předpisy '
    . '(zpravidla 10 let). Údaje o platbách spravuje poskytovatel plateb Stripe v souladu '
    . 'se svými podmínkami. Tyto údaje neslouží k marketingu a po uplynutí zákonné lhůty '
    . 'jsou rovněž odstraněny.</p>'

    . '<p>Podrobnosti o zpracování osobních údajů najdete v '
    . '<a href="' . BASE_URL . '/dokumenty/zasady-ochrany-osobnich-udaju">Zásadách ochrany '
    . 'osobních údajů</a>.</p>'

    . '</div></div></main>';

renderPage($title, $content, '/smazani-uctu', [
    'description' => $desc,
    'breadcrumbs' => [
        ['name' => 'Úvod', 'url' => siteCanonicalUrl('/')],
        ['name' => 'Smazání účtu', 'url' => siteCanonicalUrl('/smazani-uctu')],
    ],
]);
