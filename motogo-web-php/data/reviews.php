<?php
// ===== MotoGo24 — skutečné recenze pro landing v2 (renderLpReviews v landing-trust.php) =====
// JEN ověřené veřejné recenze — nic nevymýšlet ani neupravovat. Ověřeno 2026-10-10:
// Google (firemní profil Mezná) 5,0 / 53 hodnocení — texty dodal majitel z profilu
// (Google ukazuje jen „před X týdny“ → `date` = rok-měsíc, zobrazí se jako měsíc/rok;
// „…“ = text na Google zkrácený); Firmy.cz / Mapy.com 5,0 / 12 (všechny 5★);
// Facebook „Doporučuje 100 % (16 recenzí)“ (FB nemá hvězdy). `lang` = jazyk originálu
// (výchozí cs; originál v jiném jazyce se nepřekládá).
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
            ['id' => 'karel-s-google', 'source' => 'Google', 'author' => 'Karel Š.', 'rating' => 5, 'date' => '2026-10',
                'text' => 'Super, měl jsem na 1 den půjčenou RVM 500, vše proběhlo online, bez kauce, motorka byla ráno připravená, večer jsem vrátil, bez omezení kilometrů a super domluva s majitelem ;) Doporučuju'],
            ['id' => 'libor-j-google', 'source' => 'Google', 'author' => 'Libor J.', 'rating' => 5, 'date' => '2026-09',
                'text' => 'Vyjímečné služby mezi motopůjčovnami, nejsme motorkáři, nemáme vybavení. Objednali jsme motorku v aplikaci, přijeli jsme, motorka byla připravená, …'],
            ['id' => 'jirka-s-google', 'source' => 'Google', 'author' => 'Jirka S.', 'rating' => 5, 'date' => '2026-09',
                'text' => 'Plus: časová flexibilita, přátelský přístup, skvěle připravený stroj, bez nutnosti zálohy, mobilní aplikace …'],
            ['id' => 'zdenek-r-google', 'source' => 'Google', 'author' => 'Zdeněk R.', 'rating' => 5, 'date' => '2026-09',
                'text' => 'Doporucuji velmi, pujcil jsem si na doporuceni Triumph Tiger 1200 Explorer, rychly a pohodlny proces rezervace, placeni a vyzvednuti motorky, stejne tak pri vraceni potesila vyborna kava :-)'],
            ['id' => 'lenka-g-google', 'source' => 'Google', 'author' => 'Lenka G.', 'rating' => 5, 'date' => '2026-09',
                'text' => 'Skvělý lidský přístup! Pokud uvažujete půjčit motorku na zkoušku pro dítě, neuděláte zde chybu. Milé a přátelské jednání po celou dobu. Rozhodně doporučuji 🙂'],
            ['id' => 'jaroslav-j-google', 'source' => 'Google', 'author' => 'Jaroslav J.', 'rating' => 5, 'date' => '2026-08',
                'text' => 'Jedním slovem ÚŽASNÉ. Vřele doporučuji. Po letech jsem dostal možnost vrátit se do mládí kdy jsem jezdil docela dost. Bezvadný servis od objednání motorky, její půjčení včetně vybavení a vrácení. Majitelé vstřícní a ochotní. 👍'],
            ['id' => 'laza-google', 'source' => 'Google', 'author' => 'Laza', 'rating' => 5, 'date' => '2026-08',
                'text' => 'Skvělá zkušenost se zapůjčením, motorku jsem měl na 2 dny i s vozíkem. Motorky jsou udržované, obsluha velice příjemná a ochotná. Pán co mi moto předával mi to pomohl i naložit a zajistit. Za mě skvělá zkušenost a určitě mohu jen doporučit.'],
            ['id' => 'romana-k-google', 'source' => 'Google', 'author' => 'Romana K.', 'rating' => 5, 'date' => '2026-08',
                'text' => 'Děkujeme za fajnový výlet. Měli jsme s manželem půjčené BMX GS 1200 a já veškeré vybavení na motorku. Skvělý servis, domluva, pěkné prostředí. Moc doporučujeme a ještě se někdy vrátíme :-).'],
            ['id' => 'daniel-h-google', 'source' => 'Google', 'author' => 'Daniel H.', 'rating' => 5, 'date' => '2026-07',
                'text' => 'Absolutní motorkářský ráj – doporučuji všemi deseti! Hledal jsem spolehlivou půjčovnu na výlet a tahle volba byla trefa do černého. Od prvního kontaktu až po vrácení mašiny naprosto bezchybný zážitek.'],
            ['id' => 'martin-k-google', 'source' => 'Google', 'author' => 'Martin K.', 'rating' => 5, 'date' => '2026-09',
                'text' => 'Jednoduchá rezervace, nízká cena, krásná lokalita pro vyjížďku. Rychlé předání a ochotný personál.'],
            ['id' => 'waseem-s-google', 'source' => 'Google', 'author' => 'Waseem S.', 'rating' => 5, 'date' => '2026-06', 'lang' => 'en',
                'text' => 'This guy is extremely kind and generous. I would recommend everyone to rent from …'],
            ['id' => 'zdenek-firmy', 'source' => 'Firmy.cz', 'author' => 'Zdeneks 59', 'rating' => 5, 'date' => '2026-08-06',
                'text' => 'Perfektní půjčovna! Super jednání, žádná kauce, nemusíte řešit mytí motorky a vybavení vám půjčí zdarma. Rychlé, poctivé a bez starostí. Nelze nic vytknout.'],
            ['id' => 'petr-c-firmy', 'source' => 'Firmy.cz', 'author' => 'Petr C.', 'rating' => 5, 'date' => '2026-06-30',
                'text' => 'Skvělá zkušenost. Oceňuji hlavně přátelský a vstřícný přístup, všechno proběhlo naprosto bez problémů. Motorka byla připravená v domluvený čas a navíc s plnou nádrží, takže jsem mohl hned vyrazit. Předání bylo rychlé a bez zbytečného zdržování, stejně tak vrácení, které bylo možné kdykoli, klidně i v noci. Velké plus bylo také to, že nebylo potřeba před vrácením dotankovat – člověk tak nemusí řešit zbytečné starosti.'],
            ['id' => 'marian-l-fb', 'source' => 'Facebook', 'author' => 'Marián L.', 'recommends' => true, 'date' => '2026-08-30',
                'text' => '… Vše jsem jednoduše řešil pomocí aplikace, ceny a podmínky půjčení nejlepší ze všech, které jsem našel. Po příchodu do půjčovny mě přivítala sympatická a velmi milá paní majitelka. Se vším mě obeznámila, ochotně odpověděla na moje dotazy (techn. záležitosti…). Motorka a příslušenství již bylo připravené. Návrat stroje do půjčovny proběhl také naprosto v pořádku. … Velká spokojenost s přístupem a také s motorkou.'],
            ['id' => 'hancl-firmy', 'source' => 'Firmy.cz', 'author' => 'Hancl M.', 'rating' => 5, 'date' => '2026-08-17',
                'text' => 'Motorka byla připravena na dohodnutý čas. Veškerá komunikace již od začátku fungovala na 100%. … Při předání stroje vše majitelka vysvětlila. … Další co oceňuji to, když se objeví jakýkoliv problém, stačí zavolat. Výborná technická podpora. … Co jsem mi velice líbilo, že stroj můžete vrátit večer. Pěkně a přehledně vytvořený web i aplikace. Tuto půjčovnu doporučuji 10/10.'],
            ['id' => 'strdyna-firmy', 'source' => 'Firmy.cz', 'author' => 'Strdyna', 'rating' => 5, 'date' => '2026-07-30',
                'text' => 'Poprvé jsem se rozhodl půjčit si cesťák pro lepší pohodlí ve dvou a jsem maximálně spokojený! … Motorka (Benelli TRK 502 x) čekala v dobrém technickém stavu, umytá, s plnou nádrží připravená na vyjížďku, hned vedle jsem si zaparkoval auto, kde mohlo zůstat na oploceném parkovišti přes víkend. Skvělý přístup paní majitelky a vrácení bez problému, i s nabídkou kávy na cestu domů.'],
            ['id' => 'jan-r-fb', 'source' => 'Facebook', 'author' => 'Jan R.', 'recommends' => true, 'date' => '2026-09-29',
                'text' => 'Je to prostě úžasná firma a parta lidí, kteří motorky milují. Mohu všem, jenom doporučit. Náramně jsem si to užil. Široký výběr motorek a oblečení, které si v pohodě vyzkoušíte. Milí a vstřícný přístup. Prostě paráda. Moc děkuji.'],
        ],
    ];
}
