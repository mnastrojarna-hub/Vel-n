<?php
// ===== MotoGo24 — skutečné recenze pro landing v2 (renderLpReviews v landing-trust.php) =====
// JEN ověřené veřejné recenze — nic nevymýšlet ani neupravovat. Ověřeno 2026-10-10:
// Google (firemní profil Mezná) 5,0 / 53 hodnocení — texty Google nejdou stáhnout
// bez přihlášení (doplnit ručně z profilu); Firmy.cz / Mapy.com 5,0 / 12 (všechny
// 5★); Facebook „Doporučuje 100 % (16 recenzí)“ (FB nemá hvězdy).
// `text` = originál (CS). Překlady: lang/v2/<lang>/reviews.php → pages.landing.common.reviews_tr[<id>]
// (na webu označeny „přeloženo“); bez překladu se ukáže originál.
// Autor zkrácen na jméno + iniciálu příjmení. Aktualizovat při změně počtů.

function lpReviewsData() {
    return [
        'aggregates' => [
            ['source' => 'google', 'label' => 'Google', 'rating' => 5.0, 'count' => 53, 'url' => 'https://www.google.com/maps/place/?q=place_id:ChIJ39gMJ3tkeUYRSZ5i-T6w1_o'],
            ['source' => 'firmy', 'label' => 'Firmy.cz', 'rating' => 5.0, 'count' => 12, 'url' => 'https://www.firmy.cz/detail/14009052-motogo24-mezna.html'],
            ['source' => 'facebook', 'label' => 'Facebook', 'recommend' => 100, 'count' => 16, 'url' => 'https://www.facebook.com/61581614672839/reviews'],
        ],
        'items' => [
            ['id' => 'zdenek-firmy', 'source' => 'Firmy.cz', 'author' => 'Zdeneks 59', 'rating' => 5, 'date' => '2026-08-06',
                'text' => 'Perfektní půjčovna! Super jednání, žádná kauce, nemusíte řešit mytí motorky a vybavení vám půjčí zdarma. Rychlé, poctivé a bez starostí. Nelze nic vytknout.'],
            ['id' => 'petr-c-firmy', 'source' => 'Firmy.cz', 'author' => 'Petr C.', 'rating' => 5, 'date' => '2026-06-30',
                'text' => 'Skvělá zkušenost. Oceňuji hlavně přátelský a vstřícný přístup, všechno proběhlo naprosto bez problémů. Motorka byla připravená v domluvený čas a navíc s plnou nádrží, takže jsem mohl hned vyrazit. Předání bylo rychlé a bez zbytečného zdržování, stejně tak vrácení, které bylo možné kdykoli, klidně i v noci. Velké plus bylo také to, že nebylo potřeba před vrácením dotankovat – člověk tak nemusí řešit zbytečné starosti.'],
            ['id' => 'marian-l-fb', 'source' => 'Facebook', 'author' => 'Marián L.', 'recommends' => true, 'date' => '2026-08-30',
                'text' => '… Vše jsem jednoduše řešil pomocí aplikace, ceny a podmínky půjčení nejlepší ze všech, které jsem našel. Po příchodu do půjčovny mě přivítala sympatická a velmi milá paní majitelka. Se vším mě obeznámila, ochotně odpověděla na moje dotazy (techn. záležitosti…). Motorka a příslušenství již bylo připravené. Návrat stroje do půjčovny proběhl také naprosto v pořádku. … Velká spokojenost s přístupem a také s motorkou.'],
            ['id' => 'martin-o-firmy', 'source' => 'Firmy.cz', 'author' => 'Martin O.', 'rating' => 5, 'date' => '2026-09-24',
                'text' => 'Perfektní půjčovna motorek - snadné objednání, dobré ceny, rychlé a snadné předání + bonus ve formě parádních cest po okolí.'],
            ['id' => 'strdyna-firmy', 'source' => 'Firmy.cz', 'author' => 'Strdyna', 'rating' => 5, 'date' => '2026-07-30',
                'text' => 'Poprvé jsem se rozhodl půjčit si cesťák pro lepší pohodlí ve dvou a jsem maximálně spokojený! … Motorka (Benelli TRK 502 x) čekala v dobrém technickém stavu, umytá, s plnou nádrží připravená na vyjížďku, hned vedle jsem si zaparkoval auto, kde mohlo zůstat na oploceném parkovišti přes víkend. Skvělý přístup paní majitelky a vrácení bez problému, i s nabídkou kávy na cestu domů.'],
            ['id' => 'hancl-firmy', 'source' => 'Firmy.cz', 'author' => 'Hancl M.', 'rating' => 5, 'date' => '2026-08-17',
                'text' => 'Motorka byla připravena na dohodnutý čas. Veškerá komunikace již od začátku fungovala na 100%. … Při předání stroje vše majitelka vysvětlila. … Další co oceňuji to, když se objeví jakýkoliv problém, stačí zavolat. Výborná technická podpora. … Co jsem mi velice líbilo, že stroj můžete vrátit večer. Pěkně a přehledně vytvořený web i aplikace. Tuto půjčovnu doporučuji 10/10.'],
            ['id' => 'jan-r-fb', 'source' => 'Facebook', 'author' => 'Jan R.', 'recommends' => true, 'date' => '2026-09-29',
                'text' => 'Je to prostě úžasná firma a parta lidí, kteří motorky milují. Mohu všem, jenom doporučit. Náramně jsem si to užil. Široký výběr motorek a oblečení, které si v pohodě vyzkoušíte. Milí a vstřícný přístup. Prostě paráda. Moc děkuji.'],
            ['id' => 'dejv-m-firmy', 'source' => 'Firmy.cz', 'author' => 'Dejv M.', 'rating' => 5, 'date' => '2026-08-10',
                'text' => '… Když jsem si pro motorku přijel, vše bylo již přichystané, byla mi nabídnuta káva a vše okolo vysvětleno. Motorka byla připravena ve výborném technickém stavu, čistá a s prakticky plnou nádrží. Následné vrácení proběhlo též hladce a naprosto profesionálně. Od komunikace, rezervace a následné realizace. Dokumenty byli zaslané v dostatečném předstihu, tudíž není žádné zbytečné zdržování. …'],
            ['id' => 'pavel-s-fb', 'source' => 'Facebook', 'author' => 'Pavel S.', 'recommends' => true, 'date' => '2026-09-07',
                'text' => 'Půjčili jsme si dva skútry a oba nové v super stavu. Obsluha byla na jedničku a navíc jsou sympatičtí a úplně v pohodě. Děkujeme a doporučujeme.'],
            ['id' => 'jan-m-firmy', 'source' => 'Firmy.cz', 'author' => 'Jan M.', 'rating' => 5, 'date' => '2026-07-24',
                'text' => 'Normálně recenze nepíšu, ale tady na tu si musím udělat čas... Nadstartní přístup, který nemá obdoby. Velmi ochotná a příjemná paní. Skvělé webové stránky, aplikace a rezervační systém. …'],
        ],
    ];
}
