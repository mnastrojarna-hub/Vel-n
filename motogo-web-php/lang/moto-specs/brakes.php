<?php
// Překlady brzd (motorcycles.brake_type) — viz i18n_moto_specs.php. [en, de, es, fr, nl, pl, uk]
$twin = ['twin front discs, single rear disc', 'Doppelscheibe vorn, Einzelscheibe hinten', 'doble disco delantero, disco trasero', 'double disque à l\'avant, disque à l\'arrière', 'dubbele schijf voor, enkele schijf achter', 'podwójna tarcza z przodu, pojedyncza z tyłu', 'два диски спереду, один ззаду'];
$single = ['single disc front and rear', 'Einzelscheibe vorn und hinten', 'disco simple delante y detrás', 'simple disque à l\'avant et à l\'arrière', 'enkele schijf voor en achter', 'pojedyncza tarcza z przodu i z tyłu', 'по одному диску спереду й ззаду'];
return [
    'kotoučové' => ['disc', 'Scheibenbremsen', 'de disco', 'à disque', 'schijfremmen', 'tarczowe', 'дискові'],
    'kotoučové (ABS)' => ['disc (ABS)', 'Scheibenbremsen (ABS)', 'de disco (ABS)', 'à disque (ABS)', 'schijfremmen (ABS)', 'tarczowe (ABS)', 'дискові (ABS)'],
    'kotoučové (ABS + TCS)' => ['disc (ABS + TCS)', 'Scheibenbremsen (ABS + TCS)', 'de disco (ABS + TCS)', 'à disque (ABS + TCS)', 'schijfremmen (ABS + TCS)', 'tarczowe (ABS + TCS)', 'дискові (ABS + TCS)'],
    'kotoučové (přední i zadní)' => ['disc (front and rear)', 'Scheibenbremsen (vorn und hinten)', 'de disco (delante y detrás)', 'à disque (avant et arrière)', 'schijfremmen (voor en achter)', 'tarczowe (przód i tył)', 'дискові (передні й задні)'],
    'bubnové (vpředu i vzadu)' => ['drum (front and rear)', 'Trommelbremsen (vorn und hinten)', 'de tambor (delante y detrás)', 'à tambour (avant et arrière)', 'trommelremmen (voor en achter)', 'bębnowe (przód i tył)', 'барабанні (спереду й ззаду)'],
    'propojené Dual CBS' => ['linked Dual CBS', 'Verbundbremse Dual CBS', 'frenada combinada Dual CBS', 'freinage couplé Dual CBS', 'gekoppeld Dual CBS', 'zespolone Dual CBS', 'комбіновані Dual CBS'],
    'dvojité kotouče vpředu' => ['twin front discs', 'Doppelscheibe vorn', 'doble disco delantero', 'double disque à l\'avant', 'dubbele schijf voor', 'podwójna tarcza z przodu', 'подвійні диски спереду'],
    'Dva kotouče vepředu 1 kotouč vzadu' => $twin,
    'Dva kouče vepředu 1 kotouč vzadu' => $twin,
    'Dva kotouče ve předu 1 kotouč vzadu' => $twin,
    'Dva kotouče vepředu jeden vzadu' => $twin,
    '2 kotouče vepředu 1 vzadu' => $twin,
    '2 kotouče vepředu 1 kotouč vzadu' => $twin,
    'Přední dual kotouč + zadní kotouč' => $twin,
    'Jednokotoučové přední i zadní' => $single,
    'Jednokotoučové vepředu i vzadu' => $single,
    'kotoučové — vpředu 2×310 mm, vzadu 282 mm, ABS + sdružené brzdy (UBS)' => ['disc — front 2×310 mm, rear 282 mm, ABS + linked brakes (UBS)', 'Scheibenbremsen — vorn 2×310 mm, hinten 282 mm, ABS + Verbundbremse (UBS)', 'de disco — delante 2×310 mm, detrás 282 mm, ABS + frenada combinada (UBS)', 'à disque — avant 2×310 mm, arrière 282 mm, ABS + freinage couplé (UBS)', 'schijfremmen — voor 2×310 mm, achter 282 mm, ABS + gekoppeld remsysteem (UBS)', 'tarczowe — przód 2×310 mm, tył 282 mm, ABS + hamulce zespolone (UBS)', 'дискові — спереду 2×310 мм, ззаду 282 мм, ABS + комбіновані гальма (UBS)'],
    'kotoučové – vpředu 2× 330 mm Brembo M50 monoblok, vzadu 265 mm, Bosch Cornering ABS' => ['disc – front 2× 330 mm Brembo M50 monobloc, rear 265 mm, Bosch Cornering ABS', 'Scheibenbremsen – vorn 2× 330 mm Brembo M50 Monoblock, hinten 265 mm, Bosch Cornering ABS', 'de disco – delante 2× 330 mm Brembo M50 monobloque, detrás 265 mm, Bosch Cornering ABS', 'à disque – avant 2× 330 mm Brembo M50 monobloc, arrière 265 mm, Bosch Cornering ABS', 'schijfremmen – voor 2× 330 mm Brembo M50 monoblock, achter 265 mm, Bosch Cornering ABS', 'tarczowe – przód 2× 330 mm Brembo M50 monoblok, tył 265 mm, Bosch Cornering ABS', 'дискові – спереду 2× 330 мм Brembo M50 моноблок, ззаду 265 мм, Bosch Cornering ABS'],
];
