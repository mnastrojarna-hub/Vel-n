<?php
// ===== MotoGo24 — skutečné recenze pro landing v2 (renderLpReviews v landing-trust.php) =====
// JEN ověřené veřejné recenze — nic nevymýšlet ani neupravovat. Ověřeno 2026-10-10:
// Google (firemní profil Mezná) 5,0 / 53 hodnocení — texty Google nejdou stáhnout
// bez přihlášení (doplnit ručně z profilu); Firmy.cz / Mapy.com 5,0 / 12 (všechny
// 5★); Facebook „Doporučuje 100 % (16 recenzí)“ (FB nemá hvězdy).
// `text` = originál (CS), `text_<lang>` = překlad (na webu označen „přeloženo“).
// Autor zkrácen na jméno + iniciálu příjmení. Aktualizovat při změně počtů.

function lpReviewsData() {
    return [
        'aggregates' => [
            ['source' => 'google', 'label' => 'Google', 'rating' => 5.0, 'count' => 53, 'url' => 'https://www.google.com/maps/place/?q=place_id:ChIJ39gMJ3tkeUYRSZ5i-T6w1_o'],
            ['source' => 'firmy', 'label' => 'Firmy.cz', 'rating' => 5.0, 'count' => 12, 'url' => 'https://www.firmy.cz/detail/14009052-motogo24-mezna.html'],
            ['source' => 'facebook', 'label' => 'Facebook', 'recommend' => 100, 'count' => 16, 'url' => 'https://www.facebook.com/61581614672839/reviews'],
        ],
        'items' => [
            ['source' => 'Firmy.cz', 'author' => 'Zdeneks 59', 'rating' => 5, 'date' => '2026-08-06',
                'text' => 'Perfektní půjčovna! Super jednání, žádná kauce, nemusíte řešit mytí motorky a vybavení vám půjčí zdarma. Rychlé, poctivé a bez starostí. Nelze nic vytknout.',
                'text_es' => '¡Un alquiler perfecto! Trato estupendo, sin fianza, no tienes que preocuparte de lavar la moto y te prestan el equipamiento gratis. Rápido, honesto y sin complicaciones. No hay nada que reprochar.'],
            ['source' => 'Firmy.cz', 'author' => 'Petr C.', 'rating' => 5, 'date' => '2026-06-30',
                'text' => 'Skvělá zkušenost. Oceňuji hlavně přátelský a vstřícný přístup, všechno proběhlo naprosto bez problémů. Motorka byla připravená v domluvený čas a navíc s plnou nádrží, takže jsem mohl hned vyrazit. Předání bylo rychlé a bez zbytečného zdržování, stejně tak vrácení, které bylo možné kdykoli, klidně i v noci. Velké plus bylo také to, že nebylo potřeba před vrácením dotankovat – člověk tak nemusí řešit zbytečné starosti.',
                'text_es' => 'Una experiencia genial. Valoro sobre todo el trato amable y servicial; todo salió sin ningún problema. La moto estaba lista a la hora acordada y además con el depósito lleno, así que pude salir enseguida. La entrega fue rápida, igual que la devolución, que se podía hacer en cualquier momento, incluso de noche. Otra gran ventaja: no hacía falta repostar antes de devolverla, así que te ahorras preocupaciones innecesarias.'],
            ['source' => 'Facebook', 'author' => 'Marián L.', 'recommends' => true, 'date' => '2026-08-30',
                'text' => '… Vše jsem jednoduše řešil pomocí aplikace, ceny a podmínky půjčení nejlepší ze všech, které jsem našel. Po příchodu do půjčovny mě přivítala sympatická a velmi milá paní majitelka. Se vším mě obeznámila, ochotně odpověděla na moje dotazy (techn. záležitosti…). Motorka a příslušenství již bylo připravené. Návrat stroje do půjčovny proběhl také naprosto v pořádku. … Velká spokojenost s přístupem a také s motorkou.',
                'text_es' => '… Lo resolví todo fácilmente con la app; los precios y las condiciones de alquiler, los mejores de todos los que encontré. Al llegar me recibió la dueña, muy simpática y amable. Me lo explicó todo y respondió con gusto a mis preguntas (temas técnicos…). La moto y los accesorios ya estaban preparados. La devolución también fue perfecta. … Muy satisfecho con el trato y también con la moto.'],
            ['source' => 'Firmy.cz', 'author' => 'Martin O.', 'rating' => 5, 'date' => '2026-09-24',
                'text' => 'Perfektní půjčovna motorek - snadné objednání, dobré ceny, rychlé a snadné předání + bonus ve formě parádních cest po okolí.',
                'text_es' => 'Un alquiler de motos perfecto: reserva sencilla, buenos precios, entrega rápida y fácil y, de regalo, unas carreteras espectaculares por la zona.'],
            ['source' => 'Firmy.cz', 'author' => 'Strdyna', 'rating' => 5, 'date' => '2026-07-30',
                'text' => 'Poprvé jsem se rozhodl půjčit si cesťák pro lepší pohodlí ve dvou a jsem maximálně spokojený! … Motorka (Benelli TRK 502 x) čekala v dobrém technickém stavu, umytá, s plnou nádrží připravená na vyjížďku, hned vedle jsem si zaparkoval auto, kde mohlo zůstat na oploceném parkovišti přes víkend. Skvělý přístup paní majitelky a vrácení bez problému, i s nabídkou kávy na cestu domů.',
                'text_es' => 'Por primera vez alquilé una trail de viaje para ir más cómodos los dos y ¡estoy encantado! … La moto (Benelli TRK 502 X) me esperaba en buen estado, lavada y con el depósito lleno, lista para salir; aparqué el coche justo al lado, en un parking vallado donde se quedó todo el fin de semana. Un trato estupendo de la dueña y una devolución sin problemas, incluso con un café para el camino.'],
            ['source' => 'Firmy.cz', 'author' => 'Hancl M.', 'rating' => 5, 'date' => '2026-08-17',
                'text' => 'Motorka byla připravena na dohodnutý čas. Veškerá komunikace již od začátku fungovala na 100%. … Při předání stroje vše majitelka vysvětlila. … Další co oceňuji to, když se objeví jakýkoliv problém, stačí zavolat. Výborná technická podpora. … Co jsem mi velice líbilo, že stroj můžete vrátit večer. Pěkně a přehledně vytvořený web i aplikace. Tuto půjčovnu doporučuji 10/10.',
                'text_es' => 'La moto estaba lista a la hora acordada. Toda la comunicación funcionó al 100 % desde el principio. … En la entrega, la dueña me lo explicó todo. … Otra cosa que valoro: si surge cualquier problema, basta con llamar. Excelente soporte técnico. … Lo que más me gustó: puedes devolver la moto por la noche. Web y app bonitas y claras. Recomiendo este alquiler: 10/10.'],
            ['source' => 'Facebook', 'author' => 'Jan R.', 'recommends' => true, 'date' => '2026-09-29',
                'text' => 'Je to prostě úžasná firma a parta lidí, kteří motorky milují. Mohu všem, jenom doporučit. Náramně jsem si to užil. Široký výběr motorek a oblečení, které si v pohodě vyzkoušíte. Milí a vstřícný přístup. Prostě paráda. Moc děkuji.',
                'text_es' => 'Una empresa increíble y un equipo de gente que ama las motos. Solo puedo recomendarla a todos. Lo disfruté muchísimo. Amplia oferta de motos y de ropa que te pruebas con calma. Trato amable y cercano. Sencillamente genial. Muchas gracias.'],
            ['source' => 'Firmy.cz', 'author' => 'Dejv M.', 'rating' => 5, 'date' => '2026-08-10',
                'text' => '… Když jsem si pro motorku přijel, vše bylo již přichystané, byla mi nabídnuta káva a vše okolo vysvětleno. Motorka byla připravena ve výborném technickém stavu, čistá a s prakticky plnou nádrží. Následné vrácení proběhlo též hladce a naprosto profesionálně. Od komunikace, rezervace a následné realizace. Dokumenty byli zaslané v dostatečném předstihu, tudíž není žádné zbytečné zdržování. …',
                'text_es' => '… Cuando llegué a por la moto todo estaba preparado, me ofrecieron un café y me lo explicaron todo. La moto estaba en excelente estado, limpia y con el depósito prácticamente lleno. La devolución también fue fluida y totalmente profesional. Desde la comunicación y la reserva hasta la entrega. Los documentos llegaron con antelación, así que no hubo esperas innecesarias. …'],
            ['source' => 'Facebook', 'author' => 'Pavel S.', 'recommends' => true, 'date' => '2026-09-07',
                'text' => 'Půjčili jsme si dva skútry a oba nové v super stavu. Obsluha byla na jedničku a navíc jsou sympatičtí a úplně v pohodě. Děkujeme a doporučujeme.',
                'text_es' => 'Alquilamos dos scooters, ambos nuevos y en perfecto estado. El trato fue de diez y además son majos y muy tranquilos. ¡Gracias, lo recomendamos!'],
            ['source' => 'Firmy.cz', 'author' => 'Jan M.', 'rating' => 5, 'date' => '2026-07-24',
                'text' => 'Normálně recenze nepíšu, ale tady na tu si musím udělat čas... Nadstartní přístup, který nemá obdoby. Velmi ochotná a příjemná paní. Skvělé webové stránky, aplikace a rezervační systém. …',
                'text_es' => 'Normalmente no escribo reseñas, pero aquí tengo que sacar tiempo… Un trato excepcional, sin igual. Una señora muy atenta y agradable. Web, app y sistema de reservas estupendos. …'],
        ],
    ];
}
