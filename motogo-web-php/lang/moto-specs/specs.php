<?php
// Překlady technických údajů motorek (i18n_moto_specs.php): převodovka, palivo, barva.
// Klíč = česká hodnota z Velína (velikost písmen, pomlčky a „6ti/6 ti stupňová“ se normalizují).
// Hodnota = [en, de, es, fr, nl, pl, uk]. Novou hodnotu z Velína doplnit sem, jinak zůstane česky.
return [
    // ── Převodovka ──
    '6stupňová manuální' => ['6-speed manual', '6-Gang-Schaltgetriebe', 'manual de 6 velocidades', 'manuelle à 6 rapports', 'handgeschakeld, 6 versnellingen', 'manualna, 6-biegowa', 'механічна, 6-ступінчаста'],
    '6stupňová' => ['6-speed', '6-Gang', '6 velocidades', '6 rapports', '6 versnellingen', '6-biegowa', '6-ступінчаста'],
    '5stupňová' => ['5-speed', '5-Gang', '5 velocidades', '5 rapports', '5 versnellingen', '5-biegowa', '5-ступінчаста'],
    '6stupňová + QS' => ['6-speed + quickshifter', '6-Gang + Quickshifter', '6 velocidades + quickshifter', '6 rapports + quickshifter', '6 versnellingen + quickshifter', '6-biegowa + quickshifter', '6-ступінчаста + квікшифтер'],
    '6stupňová manuální, Ducati Quick Shift up/down (řazení bez spojky)' => ['6-speed manual, Ducati Quick Shift up/down (clutchless shifting)', '6-Gang-Schaltgetriebe, Ducati Quick Shift up/down (Schalten ohne Kupplung)', 'manual de 6 velocidades, Ducati Quick Shift up/down (cambio sin embrague)', 'manuelle à 6 rapports, Ducati Quick Shift up/down (passage sans embrayage)', 'handgeschakeld, 6 versnellingen, Ducati Quick Shift up/down (schakelen zonder koppeling)', 'manualna, 6-biegowa, Ducati Quick Shift up/down (zmiana biegów bez sprzęgła)', 'механічна, 6-ступінчаста, Ducati Quick Shift up/down (перемикання без зчеплення)'],
    'automatická' => ['automatic', 'Automatik', 'automática', 'automatique', 'automatisch', 'automatyczna', 'автоматична'],
    'automat' => ['automatic', 'Automatik', 'automática', 'automatique', 'automatisch', 'automatyczna', 'автоматична'],
    'automatická (CVT variátor)' => ['automatic (CVT)', 'Automatik (CVT-Variomatik)', 'automática (variador CVT)', 'automatique (variateur CVT)', 'automatisch (CVT-variator)', 'automatyczna (wariator CVT)', 'автоматична (варіатор CVT)'],
    // ── Palivo (Natural 95 = označení na českých čerpacích stanicích) ──
    'Natural 95' => ['unleaded 95 (Natural 95)', 'Super bleifrei 95 (Natural 95)', 'gasolina sin plomo 95 (Natural 95)', 'sans plomb 95 (Natural 95)', 'Euro 95 (Natural 95)', 'benzyna bezołowiowa 95 (Natural 95)', 'бензин А-95 (Natural 95)'],
    'Natural 95 (doporučeno 98)' => ['unleaded 95 (Natural 95; 98 recommended)', 'Super bleifrei 95 (Natural 95; empfohlen 98)', 'gasolina sin plomo 95 (Natural 95; recomendada 98)', 'sans plomb 95 (Natural 95 ; 98 recommandé)', 'Euro 95 (Natural 95; aanbevolen 98)', 'benzyna bezołowiowa 95 (Natural 95; zalecana 98)', 'бензин А-95 (Natural 95; рекомендовано 98)'],
    'Natural 95 + Olej 1:50' => ['unleaded 95 (Natural 95) + oil 1:50', 'Super bleifrei 95 (Natural 95) + Öl 1:50', 'gasolina sin plomo 95 (Natural 95) + aceite 1:50', 'sans plomb 95 (Natural 95) + huile 1:50', 'Euro 95 (Natural 95) + olie 1:50', 'benzyna bezołowiowa 95 (Natural 95) + olej 1:50', 'бензин А-95 (Natural 95) + олива 1:50'],
    'Natural' => ['unleaded petrol (Natural)', 'bleifreies Benzin (Natural)', 'gasolina sin plomo (Natural)', 'essence sans plomb (Natural)', 'loodvrije benzine (Natural)', 'benzyna bezołowiowa (Natural)', 'неетилований бензин (Natural)'],
    'Benzín 95' => ['petrol 95', 'Benzin 95', 'gasolina 95', 'essence 95', 'benzine 95', 'benzyna 95', 'бензин А-95'],
    'Benzín' => ['petrol', 'Benzin', 'gasolina', 'essence', 'benzine', 'benzyna', 'бензин'],
    'Benzín + 2T olej' => ['petrol + 2-stroke oil', 'Benzin + 2-Takt-Öl', 'gasolina + aceite 2T', 'essence + huile 2 temps', 'benzine + 2-taktolie', 'benzyna + olej 2T', 'бензин + олива 2T'],
    // ── Barva ──
    'černá' => ['black', 'Schwarz', 'negro', 'noir', 'zwart', 'czarny', 'чорний'],
    'matná černá' => ['matte black', 'Mattschwarz', 'negro mate', 'noir mat', 'matzwart', 'czarny matowy', 'матовий чорний'],
    'bílá' => ['white', 'Weiß', 'blanco', 'blanc', 'wit', 'biały', 'білий'],
    'šedá' => ['grey', 'Grau', 'gris', 'gris', 'grijs', 'szary', 'сірий'],
    'stříbrná' => ['silver', 'Silber', 'plateado', 'argent', 'zilver', 'srebrny', 'сріблястий'],
    'červená' => ['red', 'Rot', 'rojo', 'rouge', 'rood', 'czerwony', 'червоний'],
    'modrá' => ['blue', 'Blau', 'azul', 'bleu', 'blauw', 'niebieski', 'синій'],
    'světle modrá' => ['light blue', 'Hellblau', 'azul claro', 'bleu clair', 'lichtblauw', 'jasnoniebieski', 'світло-блакитний'],
    'zelená' => ['green', 'Grün', 'verde', 'vert', 'groen', 'zielony', 'зелений'],
    'žlutá' => ['yellow', 'Gelb', 'amarillo', 'jaune', 'geel', 'żółty', 'жовтий'],
    'oranžová' => ['orange', 'Orange', 'naranja', 'orange', 'oranje', 'pomarańczowy', 'помаранчевий'],
    'černá/zelená' => ['black/green', 'Schwarz/Grün', 'negro/verde', 'noir/vert', 'zwart/groen', 'czarny/zielony', 'чорний/зелений'],
];
