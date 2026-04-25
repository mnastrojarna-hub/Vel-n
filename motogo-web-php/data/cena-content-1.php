<?php
// ===== MotoGo24 — Co je v cene najmu 1/2 (intro + 2-col vybava + sluzby) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/co-je-v-cene-najmu
// POZN: H1 zachovava puvodni preklep "pronamu" misto "pronajmu" (1:1).

return [
    // POZOR: V originalu je preklep "pronamu" - zachovavame 1:1
    'h1' => 'Co je v ceně pronámu motorky',
    'intro' => 'V <strong>MotoGo24 – půjčovně motorek na Vysočině</strong> –&nbsp; dostaneš férové podmínky. <strong>Bez kauce, s výbavou pro řidiče v ceně a nonstop provozem</strong>. Vše, co potřebuješ k bezpečné a pohodové jízdě, je součástí půjčovného.',
    'gear' => [
        'basic' => [
            'title' => 'Základní výbava v ceně',
            'lead' => 'Každý řidič má k dispozici kompletní <strong>motorkářskou výbavu</strong>, která je zahrnuta v ceně pronájmu:',
            'items' => [
                '<strong>helma</strong>',
                '<strong>motorkářská bunda</strong> s chrániči',
                '<strong>moto kalhoty</strong>',
                '<strong>rukavice</strong>',
            ],
            'note1' => 'Výbava je dostupná ve více velikostech a pravidelně ji čistíme a kontrolujeme.',
            'note2' => 'Vybrané motorky jsou vybaveny kufry – viz detail motorky v katalogu.',
        ],
        'extra' => [
            'title' => 'Nadstandardní výbava za příplatek',
            'lead' => 'Jedeš se spolujezdcem nebo chceš motocyklové boty? Můžeš si při rezervaci přiobjednat:',
            'items' => [
                'výbava pro spolujezdce (helma, bunda, kalhoty, rukavice)',
                'motocyklové boty – pro řidiče i spolujezdce',
            ],
        ],
        'services' => [
            'title' => 'Nadstandardní služby za příplatek',
            'items' => [
                'přistavení motorky na domluvené místo kamkoliv v ČR',
                'vrácení motorky jinam než na adresu půjčovny',
            ],
        ],
    ],
];
