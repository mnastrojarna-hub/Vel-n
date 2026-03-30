<?php
// ===== MotoGo24 Web PHP — Rezervace =====

// Fetch motos server-side
$motos = $sb->fetchMotos();

// Read query params
$presetMoto = isset($_GET['moto']) ? $_GET['moto'] : '';
$presetStart = isset($_GET['start']) ? $_GET['start'] : '';
$presetEnd = isset($_GET['end']) ? $_GET['end'] : '';
$presetDelivery = !empty($_GET['delivery']);
$resumeId = isset($_GET['resume']) ? $_GET['resume'] : '';

echo renderHead(
    'Online rezervace motorky | MotoGo24',
    'Rezervujte si motorku online ve třech krocích. Půjčovna motorek Vysočina – bez kauce, výbava v ceně, nonstop provoz.'
);
echo renderHeader();

// Breadcrumb
echo renderBreadcrumb([['href'=>'/', 'label'=>'Domů'], 'REZERVACE']);

echo '<main id="content"><div class="container"><div class="ccontent pcontent">';

// Resume flow — minimal HTML, JS handles the rest
if ($resumeId) {
    echo '<h1>Dokončení rezervace</h1>';
    echo '<div id="rez-form"><div class="loading-overlay"><span class="spinner"></span> Načítám rezervaci...</div></div>';
} else {
    // Step 1: Intro
    echo '<div id="rez-intro"><h1>Rezervace motorky</h1>';
    echo '<h3>Jak rezervace funguje?</h3><p>&nbsp;</p>';
    echo '<p>Pokud si chcete <strong>půjčit motorku v konkrétním termínu</strong>, vyberte „libovolná dostupná motorka" a v kalendáři termín vyznačte.</p><p>&nbsp;</p>';
    echo '<p>V případě, že si chcete <strong>vyzkoušet konkrétní motorku</strong>, vyberte ji ze seznamu.</p><p>&nbsp;</p>';
    echo '<p><strong>Půjčujeme bez kauce. Základní výbavu pro řidiče poskytujeme zdarma.</strong></p><p>&nbsp;</p></div>';

    // Moto dropdown (server-rendered with data)
    echo '<div id="rez-moto-select">';
    echo '<form class="form-product-select gr2"><div>Vyber motorku:</div><select id="rez-moto-dropdown">';
    echo '<option value="">libovolná dostupná motorka v mém termínu</option>';
    foreach ($motos as $m) {
        $mid = e($m['id']);
        $model = e($m['model']);
        $selected = ($mid === $presetMoto) ? ' selected' : '';
        echo '<option value="' . $mid . '"' . $selected . '>' . $model . '</option>';
    }
    echo '</select></form></div>';

    // Calendar placeholder
    echo '<div id="rez-calendar"></div>';

    // Date banner placeholder
    echo '<div id="rez-date-banner" style="display:none"></div>';

    // Available motos placeholder
    echo '<div id="rez-avail-select" style="display:none"></div>';

    // ===== FORM HTML (same structure as _rezFormHtml) =====
    echo '<div id="rez-form"><p>&nbsp;</p>';
    echo '<input type="text" id="rez-name" name="name" placeholder="* Jméno a příjmení" required title="Toto pole je povinné" autocomplete="name">';
    echo '<div class="gr2"><input type="text" id="rez-street" name="street-address" placeholder="* Ulice, č.p." required autocomplete="street-address">';
    echo '<input type="text" id="rez-zip" name="postal-code" placeholder="* PSČ" required autocomplete="postal-code"></div>';
    echo '<div class="gr2"><input type="text" id="rez-city" name="address-level2" placeholder="* Město" required autocomplete="address-level2">';
    echo '<input type="text" id="rez-country" name="country-name" placeholder="* Stát" value="Česká republika" required autocomplete="country-name"></div>';
    echo '<div class="gr2"><input type="email" id="rez-email" name="email" placeholder="* E-mail" required autocomplete="email">';
    echo '<input type="tel" id="rez-phone" name="tel" placeholder="* Telefon (+420XXXXXXXXX)" required autocomplete="tel" pattern="^\\+\\d{12,15}$"></div>';

    // Voucher code
    echo '<div class="gr2 voucher-code"><input type="text" id="rez-voucher" placeholder="Slevový kód" maxlength="255">';
    echo '<div><span class="btn btngreen-small" onclick="MG._applyVoucher()">UPLATNIT</span></div></div>';
    echo '<div id="rez-applied-codes"></div>';
    echo '<div id="rez-voucher-msg" style="font-size:.85rem;margin:-.5rem 0 .75rem"></div>';

    // Pickup time
    echo '<div class="dfc pickup"><div>* Čas převzetí nebo přistavení motorky <span class="ctooltip" style="color:#c00;font-size:.75rem">*<span class="ctooltiptext">Toto pole je povinné</span></span></div><input type="time" id="rez-pickup-time" required title="Toto pole je povinné"></div>';

    // Checkboxes — extras
    echo '<div class="checkboxes">';
    // Výbava spolujezdce
    echo '<div><input type="checkbox" id="rez-eq-passenger"><label for="rez-eq-passenger">Výbava pro spolujezdce <strong>+ 690 Kč</strong>';
    echo ' <span class="ctooltip">&#9432;<span class="ctooltiptext">Výbavu pro spolujezdce zaškrtněte jen v případě, že pojedete ve dvou a spolujezdec si výbavu potřebuje zapůjčit. Velikost si vyzkouší na místě. Základní výbava pro spolujezdce zahrnuje helmu, bundu, rukavice a kuklu.</span></span>';
    echo '</label></div>';
    // Boty řidič
    echo '<div><input type="checkbox" id="rez-eq-boots-rider"><label for="rez-eq-boots-rider">Zapůjčení bot pro řidiče <strong>+ 290 Kč</strong>';
    echo ' <span class="ctooltip">&#9432;<span class="ctooltiptext">Motocyklové boty nejsou součástí základní výbavy. V případě zájmu vám rádi zapůjčíme boty ve vaší velikosti.</span></span>';
    echo '</label></div>';
    // Boty spolujezdec
    echo '<div><input type="checkbox" id="rez-eq-boots-passenger"><label for="rez-eq-boots-passenger">Zapůjčení bot pro spolujezdce <strong>+ 290 Kč</strong></label></div>';
    // Přistavení motorky
    echo '<div><input type="checkbox" id="rez-delivery"><label for="rez-delivery">Přistavení motorky jinam <span id="rez-delivery-price"></span>';
    echo ' <span class="ctooltip">&#9432;<span class="ctooltiptext">Motorku vám dovezeme na domluvené místo. Do ceny za přistavení motorky se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (40 Kč/km, tam i zpět).</span></span>';
    echo '</label></div>';
    // Delivery panel
    echo '<div id="rez-delivery-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px">';
    echo '<input type="text" id="rez-delivery-address" placeholder="Zadejte adresu přistavení">';
    echo '<div style="display:flex;gap:6px;margin-top:.5rem"><button type="button" onclick="MG._openWebMapPicker(\'delivery\')" style="padding:6px 12px;background:#fff;border:1px solid #ccc;border-radius:6px;font-size:.85rem;cursor:pointer">&#128506;&#65039; Vybrat na mapě</button></div>';
    echo '<div id="rez-delivery-confirm" style="display:none;margin-top:.5rem"><input type="checkbox" id="rez-delivery-confirmed"><label for="rez-delivery-confirmed" style="font-size:.85rem;font-weight:600;color:#1a8c1a"> &#10004; Potvrdit adresu přistavení</label></div>';
    echo '<div style="margin-top:.5rem"><input type="checkbox" id="rez-return-same-as-delivery" checked><label for="rez-return-same-as-delivery" style="font-size:.85rem"> Vrátit motorku na stejné adrese</label></div>';
    echo '<div><input type="checkbox" id="rez-own-gear"><label for="rez-own-gear" style="font-size:.85rem"> Mám vlastní výbavu</label></div>';
    echo '</div>';
    // Vrácení motorky jinde
    echo '<div><input type="checkbox" id="rez-return-other"><label for="rez-return-other">Vrácení motorky na jiné adrese <span id="rez-return-price"></span>';
    echo ' <span class="ctooltip">&#9432;<span class="ctooltiptext">Motorku nemusíte vracet zpět v místě motopůjčovny, rádi si ji u vás vyzvedneme. Do ceny za vrácení motorky jinde se promítá: nakládka 500 Kč, vykládka 500 Kč a náklady na dopravu (40 Kč/km, tam i zpět).</span></span>';
    echo '</label></div>';
    // Return panel
    echo '<div id="rez-return-panel" style="display:none;margin:0 0 .75rem 1.5rem;padding:.75rem;background:#f9f9f9;border:1px solid #e0e0e0;border-radius:6px">';
    echo '<input type="text" id="rez-return-address" placeholder="Zadejte adresu vrácení">';
    echo '<div style="display:flex;gap:6px;margin-top:.5rem"><button type="button" onclick="MG._openWebMapPicker(\'return\')" style="padding:6px 12px;background:#fff;border:1px solid #ccc;border-radius:6px;font-size:.85rem;cursor:pointer">&#128506;&#65039; Vybrat na mapě</button></div>';
    echo '<div id="rez-return-confirm" style="display:none;margin-top:.5rem"><input type="checkbox" id="rez-return-confirmed"><label for="rez-return-confirmed" style="font-size:.85rem;font-weight:600;color:#1a8c1a"> &#10004; Potvrdit adresu vrácení</label></div>';
    echo '<div class="dfc" style="margin-top:.5rem"><div>Čas vrácení</div><input type="time" id="rez-return-time" style="max-width:200px"></div>';
    echo '</div>';
    echo '</div>'; // end checkboxes

    // Note
    echo '<textarea id="rez-note" placeholder="Poznámka – uveďte preferovanou velikost výbavy (helma, bunda, rukavice, kalhoty)"></textarea>';

    // Agreements
    echo '<div class="checkboxes">';
    echo '<div class="agreement gr2"><input type="checkbox" id="rez-agree-vop" required checked><div>* Souhlasím s <a href="/obchodni-podminky">obchodními podmínkami</a></div></div>';
    echo '<div class="agreement gr2"><input type="checkbox" id="rez-agree-gdpr" checked><div>Souhlasím se <a href="/gdpr">zpracováním osobních údajů</a></div></div>';
    echo '<div class="agreement gr2"><input type="checkbox" id="rez-agree-marketing" checked><div>Souhlasím se zasíláním marketingových sdělení</div></div>';
    echo '<div class="agreement gr2"><input type="checkbox" id="rez-agree-photo" checked><div>Souhlasím s využitím fotografií pro marketingové účely</div></div></div>';

    // Price preview
    echo '<div id="rez-price-preview"></div>';
    echo '<div class="text-center" style="margin-top:1rem"><button class="btn btngreen" onclick="MG._submitReservation()">Pokračovat v rezervaci</button></div>';
    echo '</div>'; // end rez-form
}

echo '</div></div></main>';

echo renderFooter();
echo renderPageEnd(true);

// Pass motos data + query params to JS
$motosJson = json_encode($motos, JSON_UNESCAPED_UNICODE);
?>
<script>
window.MG_PHP_DATA = {
  motos: <?php echo $motosJson; ?>,
  presetMoto: <?php echo json_encode($presetMoto); ?>,
  presetStart: <?php echo json_encode($presetStart); ?>,
  presetEnd: <?php echo json_encode($presetEnd); ?>,
  presetDelivery: <?php echo $presetDelivery ? 'true' : 'false'; ?>,
  resumeId: <?php echo json_encode($resumeId); ?>
};
</script>
<script src="/js/pages-rezervace.js"></script>
<script src="/js/pages-rezervace-calendar.js"></script>
<script src="/js/pages-rezervace-pricing.js"></script>
<script src="/js/pages-rezervace-steps.js"></script>
<script src="/js/pages-rezervace-scan.js"></script>
