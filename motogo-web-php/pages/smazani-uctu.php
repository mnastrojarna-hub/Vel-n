<?php
// ===== MotoGo24 Web PHP — Smazání účtu a dat (Google Play Data safety) =====
// Veřejná stránka popisující postup, jakým může uživatel aplikace MotoGo24
// požádat o smazání svého účtu a přidružených dat. URL této stránky se zadává
// do Google Play Console → Bezpečnost dat → „Adresa URL ke smazání účtu".
// Texty: čeština níže (výchozí), cizí jazyky lang/v2/<jazyk>/static-pages.php (pages.smazani_uctu).

$email = defined('EMAIL_FULL') ? EMAIL_FULL : 'info@motogo24.cz';
$phone = defined('PHONE') ? PHONE : '+420 774 256 271';
$company = defined('COMPANY_NAME') ? COMPANY_NAME : 'Bc. Petra Semorádová';

$T = [
    'title' => 'Smazání účtu | MotoGo24',
    'desc' => 'Jak smazat svůj účet a osobní data v aplikaci MotoGo24 — postup v aplikaci i alternativní žádost e-mailem, rozsah mazaných dat a doba uchování.',
    'crumb_aria' => 'Drobečková navigace',
    'crumb_home' => 'Úvod',
    'crumb' => 'Smazání účtu',
    'h1' => 'Smazání účtu a osobních dat — MotoGo24',
    'intro' => 'Tato stránka popisuje, jak můžete jako uživatel aplikace <strong>MotoGo24</strong> (provozovatel {company}) požádat o smazání svého účtu a všech osobních údajů, které s ním souvisejí.',
    'app_title' => '1) Smazání přímo v aplikaci (doporučeno)',
    'app_steps' => [
        'Otevřete aplikaci MotoGo24 a přihlaste se.',
        'Přejděte do sekce <strong>Profil</strong>.',
        'Zvolte <strong>Smazat účet</strong>.',
        'Potvrďte žádost. Účet i přidružená data se smažou.',
    ],
    'mail_title' => '2) Smazání e-mailem',
    'mail_text' => 'Pokud se k aplikaci nemůžete přihlásit, napište nám z e-mailu, kterým jste registrovaní, na adresu {email} s předmětem <strong>„Žádost o smazání účtu"</strong>. Žádost vyřídíme nejpozději do <strong>30 dnů</strong>. Pro ověření totožnosti vás můžeme kontaktovat na telefonu {phone}.',
    'deleted_title' => 'Která data budou smazána',
    'deleted_intro' => 'Po potvrzení žádosti trvale odstraníme zejména:',
    'deleted_items' => [
        'přihlašovací údaje a profil (jméno, e-mail, telefon),',
        'nahrané fotografie a dokumenty (doklady k ověření, fotky k SOS a rezervacím),',
        'historii konverzací s asistentem a hlášení SOS,',
        'údaje o poloze sdílené v rámci SOS.',
    ],
    'kept_title' => 'Která data a jak dlouho uchováváme',
    'kept_text' => 'Některé údaje jsme ze zákona povinni uchovat i po smazání účtu — zejména <strong>účetní a daňové doklady k uskutečněným rezervacím a platbám</strong> (vystavené faktury), které uchováváme po dobu vyžadovanou právními předpisy (zpravidla 10 let). Údaje o platbách spravuje poskytovatel plateb Stripe v souladu se svými podmínkami. Tyto údaje neslouží k marketingu a po uplynutí zákonné lhůty jsou rovněž odstraněny.',
    'privacy' => 'Podrobnosti o zpracování osobních údajů najdete v {a}Zásadách ochrany osobních údajů{/a}.',
];
$tr = function_exists('i18nDetectLanguage') && i18nDetectLanguage() !== 'cs' ? t('pages.smazani_uctu') : null;
if (is_array($tr)) $T = array_merge($T, $tr);

$h = function ($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); };
$fill = function ($s) use ($h, $company, $email, $phone) {
    return strtr((string)$s, [
        '{company}' => $h($company),
        '{email}' => '<a href="mailto:' . $h($email) . '">' . $h($email) . '</a>',
        '{phone}' => $h($phone),
        '{a}' => '<a href="' . BASE_URL . '/dokumenty/zasady-ochrany-osobnich-udaju">',
        '{/a}' => '</a>',
    ]);
};
$li = function ($items) use ($fill) {
    $o = '';
    foreach ((array)$items as $it) $o .= '<li>' . $fill($it) . '</li>';
    return $o;
};

$bc = '<nav class="breadcrumb" aria-label="' . $h($T['crumb_aria']) . '"><a href="' . BASE_URL . '/">' . $h($T['crumb_home']) . '</a> &rsaquo; <span>' . $h($T['crumb']) . '</span></nav>';

$content = '<main id="content"><div class="container"><div class="ccontent" style="max-width:760px;margin:0 auto;line-height:1.7;">'
    . $bc
    . '<h1>' . $h($T['h1']) . '</h1>'
    . '<p>' . $fill($T['intro']) . '</p>'
    . '<h2>' . $h($T['app_title']) . '</h2>'
    . '<ol>' . $li($T['app_steps']) . '</ol>'
    . '<h2>' . $h($T['mail_title']) . '</h2>'
    . '<p>' . $fill($T['mail_text']) . '</p>'
    . '<h2>' . $h($T['deleted_title']) . '</h2>'
    . '<p>' . $fill($T['deleted_intro']) . '</p>'
    . '<ul>' . $li($T['deleted_items']) . '</ul>'
    . '<h2>' . $h($T['kept_title']) . '</h2>'
    . '<p>' . $fill($T['kept_text']) . '</p>'
    . '<p>' . $fill($T['privacy']) . '</p>'
    . '</div></div></main>';

// Stránka je dostupná POUZE přes přímou URL (pro Google Play Data safety).
// Nevede na ni žádný odkaz v navigaci ani patičce a je vyloučena z indexace
// i ze sitemapy — proto noindex,nofollow a bez breadcrumbs schématu.
renderPage($T['title'], $content, '/smazani-uctu', [
    'description' => $T['desc'],
    'robots' => 'noindex,nofollow',
]);
