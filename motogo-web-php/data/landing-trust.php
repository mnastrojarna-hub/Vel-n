<?php
// ===== MotoGo24 — landing v2: CS defaulty sekcí důvěry (landing-trust.php) =====
// Slučuje se do lpDefaults()['common'] (landing.php). Překlady: lang/v2/<lang>/landing.php,
// Velín CMS klíče web.landing.common.*. Fakta ověřena 2026-10-10 (kampaň „8 důvodů“
// na Google profilu, VOP, data/pobocky.php, appka loyalty). POZOR na rozdíly poboček:
// vrácení bez mytí/tankování, doplňková výbava a zázemí (káva, WC, wifi…) = JEN Mezná;
// samoobsluha Velké Němčice = výbava řidiče + vesta/lékárnička/zámek, šatna, parkování; motorku vrátit
// umytou a natankovanou (pokyn majitele 2026-10-10 — POZOR: VOP čl. 5 l) zatím říká opak pro obě pobočky).
// Vzdálenosti: OSRM 2026-10-10 (Praha→Mezná 92 min, Brno→VN 28 min, letiště Brno→VN 36 min, Vídeň→VN 100 min).

function lpTrustDefaults() {
    return [
        'reasons_title' => 'Proč jezdit s MotoGo24',
        'reasons_lead' => 'Z půjčení jsme odstranili všechno, co nás jako motorkáře vždycky štvalo.',
        'reasons_more' => 'Zobrazit všech {n} výhod',
        'reasons_less' => 'Zobrazit méně',
        'reasons' => [
            ['icon' => 'card', 'title' => 'Bez kauce', 'text' => 'Nic ti neblokujeme na kartě.'],
            ['icon' => 'shield', 'title' => '100% smluvní krytí škod', 'text' => 'Při nehodě je tvoje spoluúčast 0 Kč.*'],
            ['icon' => 'helmet', 'title' => 'Výbava v ceně', 'text' => 'Motooblečení, vesta, lékárnička a kotoučový zámek. V Mezné i nepromoky.'],
            ['icon' => 'infinity', 'title' => 'Neomezené km a cesty do zahraničí', 'text' => 'Jeď, kam a jak daleko chceš (v rámci zelené karty).'],
            ['icon' => 'fuel', 'title' => 'Vracíš, jak ti to vyhovuje', 'text' => 'Nemusí mít plnou nádrž. V Mezné ani nemusí být umytá; na samoobslužné pobočce ji vrať umytou.'],
            ['icon' => 'calendar', 'title' => 'Rezervace i platba online', 'text' => 'Vyřídíš za pár minut, klidně v neděli večer.'],
            ['icon' => 'app', 'title' => 'Vlastní aplikace', 'text' => 'Úprava tvojí rezervace, SOS, věrnostní program i tipy na trasy na jednom místě.'],
            ['icon' => 'coffee', 'title' => 'Zázemí zdarma', 'text' => 'V Mezné káva, voda, WC, wifi, převlékací kabinka a skříňky. Parkování pro tvoje auto na obou pobočkách.'],
            ['icon' => 'kiosk', 'title' => 'Obě pobočky nonstop', 'text' => 'Vyzvedneš i vrátíš kdykoli podle rezervace. Velké Němčice jsou 100% samoobslužné — kódem z aplikace.'],
            ['icon' => 'route', 'title' => 'Trasy a záznam jízdy', 'text' => 'Přes 1 000 tras s navigací a záznam každé jízdy: kudy jsi jel, kolik km a jak dlouho.'],
            ['icon' => 'moto', 'title' => 'Motorka pro každého', 'text' => 'Od skútrů přes A2 až po silné stroje na áčko. A dětské motorky pro nejmenší.'],
            ['icon' => 'bot', 'title' => 'AI asistent 24/7', 'text' => 'Poradí kdykoli na webu i v aplikaci. Telefonicky jsme tu Po–Pá 8–17.'],
            ['icon' => 'percent', 'title' => 'Věrnostní program', 'text' => 'Sleva od první rezervace v aplikaci, až 20 %. Od ranku 3 výbava spolujezdce i boty zdarma.'],
            ['icon' => 'phone', 'title' => 'SOS v aplikaci', 'text' => 'Pomoc na cestách na pár klepnutí.'],
            ['icon' => 'clock', 'title' => '1. den za polovinu', 'text' => 'Při vyzvednutí od 12:00 a výpůjčce na 2 a více dní.'],
            ['icon' => 'star', 'title' => 'I pro začátečníky', 'text' => 'Stačí 18 let a řidičák odpovídající skupiny. Praxi nevyžadujeme, zahraniční ŘP bereme.'],
            ['icon' => 'truck', 'title' => 'Přistavení na adresu', 'text' => 'Z Mezné ti motorku přivezeme kamkoli v ČR (za příplatek).'],
            ['icon' => 'pin', 'title' => 'Snadno k nám', 'text' => 'Mezná 90 min z Prahy, Velké Němčice 30 min z Brna a 35 min z brněnského letiště.'],
            ['icon' => 'helmet', 'title' => 'Velikosti až 6XL', 'text' => 'Bundy a kalhoty do 6XL v Mezné, do 4XL na samoobslužné pobočce.'],
            ['icon' => 'check', 'title' => 'Storno zdarma', 'text' => 'Zrušení víc než 7 dní předem bez poplatku.'],
        ],
        'reasons_note' => '* Při dodržení podmínek nájmu (VOP čl. 7).',
        'panel_rating' => '{r} · {n} hodnocení na Google',
        'reviews_title' => 'Co o nás říkají motorkáři',
        'reviews_count' => '{n} hodnocení',
        'reviews_recommend_pct' => '{p} %',
        'reviews_recommends' => 'Doporučuje',
        'reviews_translated' => 'Přeloženo z češtiny',
        'reviews_prev' => 'Předchozí recenze',
        'reviews_next' => 'Další recenze',
        'routes' => [
            'eyebrow' => 'Aplikace MotoGo24 zdarma',
            'title' => 'Kam vyrazit? A kudy jsi jel?',
            'lead' => 'Nevíš, kam vyjet? Vyber si z přes 1 000 tras s navigací. A po jízdě uvidíš, kudy jsi jel, kolik km a jak dlouho.',
            'stats' => [['v' => '1 000+', 'l' => 'tras s navigací'], ['v' => '50 000', 'l' => 'zajímavých míst'], ['v' => '0 Kč', 'l' => 'aplikace zdarma']],
            'items' => [
                ['icon' => 'route', 'title' => 'Záznam každé jízdy', 'text' => 'Trasa na mapě, km, čas jízdy i stání, průměrná a max. rychlost, nastoupané metry a fotky ze zastávek.'],
                ['icon' => 'pin', 'title' => 'Tipy na trasy', 'text' => 'Přes 1 000 doporučených tras u nás i v zahraničí — s navigací.'],
                ['icon' => 'star', 'title' => 'Zajímavá místa', 'text' => 'Téměř 50 000 míst: hrady, vyhlídky, jídlo i moto spoty. Objevená místa se ti ukládají.'],
                ['icon' => 'app', 'title' => 'Vlastní trasy', 'text' => 'Naklikej si trasu v mapě, ulož ji a sdílej jízdu s partou.'],
            ],
            'mock' => ['title' => 'Okruh Vysočinou', 'km' => '186 km', 'time' => '3 h 42 min', 'avg' => 'Ø 58 km/h', 'climb' => '↑ 1 240 m'],
        ],
        'hl_title' => 'Víc než půjčovna',
        'highlights' => [
            ['kind' => 'kiosk', 'title' => 'Autonomní pobočka 24/7', 'text' => 'Motorku vyzvedneš i vrátíš klidně ve 3 ráno. Kódy z aplikace otevřou šatnu i kóji s motorkou.', 'href' => '/pobocky/velke-nemcice', 'cta' => 'Jak to funguje'],
            ['kind' => 'ai', 'title' => 'AI asistent 24/7', 'text' => 'Poradí s výběrem motorky, rezervací i trasou — kdykoli na webu i v aplikaci.'],
            ['kind' => 'app', 'title' => 'Vše v aplikaci', 'text' => 'Rezervace a její úpravy, doklady, kódy k pobočce i SOS na cestách — na jednom místě.', 'stores' => true],
            ['kind' => 'loyalty', 'title' => 'Věrnostní program', 'text' => 'Každá jízda tě posune výš: sleva až 20 % a od ranku 3 výbava spolujezdce i boty zdarma.'],
        ],
        'branches_title' => 'Dvě pobočky — vyber si',
        'branch_book' => 'Rezervovat',
        'branch_more' => 'Detail pobočky',
        'branches' => [
            ['badge' => 'S obsluhou · nonstop', 'title' => 'Mezná u Pelhřimova', 'text' => 'Osobní předání v čase, který si zvolíš, kompletní výbava v ceně, káva na uvítanou a přistavení motorky na adresu.', 'img' => '/gfx/provozovna-1.jpg', 'href' => '/pobocky/mezna', 'book_href' => '/rezervace?pobocka=11111111-1111-1111-1111-111111111111', 'times' => ['90 min z Prahy']],
            ['badge' => 'Samoobsluha · 24/7', 'title' => 'Velké Němčice u Brna', 'text' => 'Vyzvednutí i vrácení kdykoli, 100% nonstop, kódem z aplikace. Šatna s výbavou a parkování zdarma.', 'img' => '/gfx/pobocky/velke-nemcice/vydejni-box-640.webp', 'href' => '/pobocky/velke-nemcice', 'book_href' => '/rezervace?pobocka=22222222-2222-2222-2222-222222222222', 'times' => ['30 min z Brna', '35 min z letiště Brno']],
        ],
    ];
}
