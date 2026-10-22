<?php
// ===== MotoGo24 — landing v2: CS defaulty sekcí důvěry (landing-trust.php) =====
// Slučuje se do lpDefaults()['common'] (landing.php). Překlady: lang/v2/<lang>/landing.php,
// Velín CMS klíče web.landing.common.*. Fakta ověřena 2026-10-10 (kampaň „8 důvodů“
// na Google profilu, VOP, data/pobocky.php, appka loyalty). POZOR na rozdíly poboček:
// vrácení bez mytí, doplňková výbava a zázemí (káva, WC, wifi…) = JEN Mezná;
// samoobsluha Velké Němčice = výbava řidiče + vesta/lékárnička/zámek, šatna, parkování. Vrácení (majitel
// 2026-10-11/12): tankovat netřeba NIKDE (plná nádrž ne), jen ať nesvítí rezerva (na samoobsluze NESMÍ);
// umytá JEN na samoobslužné Velké Němčice, Mezná (i přistavení/vrácení jinde) bez mytí — POZOR:
// VOP čl. 5 l) zatím říká „bez mytí“ pro obě pobočky. Obě pobočky nonstop; telefon Po–Pá 8–17, AI 24/7.
// Vzdálenosti: OSRM 2026-10-10 (Praha→Mezná 92 min, Brno→VN 28 min, letiště Brno→VN 36 min, Vídeň→VN 100 min).
// Cenová kotva (anchor_*, landing-guarantee.php) — DŮKAZ pro § 5c ZOS (tvrzení musíme umět doložit):
// průzkum 22. 10. 2026, 17 českých půjčoven s veřejným ceníkem (nejvyšší kauce za velkou motorku):
// Renocar 20k, BASE NEXT 20k, Legendy U Vás 25k, NajmiMoto 25k, Půjčovna Motorek Praha 25k, Motolety 30/50k,
// Moravamotors 45k, Yamaha PEMM Brno 30k, Race Tool KTM 30/50k, Motoverse 40/30/50k, Profi-moto 30k,
// AMG Moto Ostrava 40k, Motoráj Zásadka 40k, HD Praha 10k, MTT Brno 15k, Westmoto 15k, motopujcovna-praha 20k
// → rozpětí 10–50 tis., medián 25 tis., 30 tis. přesně u 6 půjčoven; spoluúčast obvykle 10 %, min. 10 000 Kč.
// Zdroje: veřejné ceníky na webech uvedených půjčoven (screenshoty uchovat u majitele). Nejmenovat konkurenty
// (OZ § 2980), neškrtat cizí částky (dojem slevy), kauci nesčítat se spoluúčastí. Ověřit 1× za sezónu.

function lpTrustDefaults() {
    return [
        'reasons_title' => 'Proč jezdit s MotoGo24',
        'reasons_lead' => 'Z půjčení jsme odstranili všechno, co nás jako motorkáře vždycky štvalo.',
        'reasons_more' => 'Zobrazit všech {n} výhod',
        'reasons_less' => 'Zobrazit méně',
        // 2026-10-22: flexibilita rezervace do popředí (majitel: „nic není závazné, zvlášť při nepřízni počasí“)
        'reasons' => [
            ['icon' => 'swap', 'title' => 'Termín posuneš kdykoliv zdarma', 'text' => 'Pokazí se počasí nebo plány? Přesuň rezervaci na jiné dny — bez poplatku, kdykoliv do začátku pronájmu.'],
            ['icon' => 'resize', 'title' => 'Prodloužíš i zkrátíš', 'text' => 'Prodloužení kdykoliv bez poplatku za změnu (doplatíš jen dny navíc), zkrácení zdarma 7 a víc dní předem.'],
            ['icon' => 'edit', 'title' => 'Rezervaci upravíš kdykoliv', 'text' => 'Až do začátku pronájmu přidáš výbavu nebo boty, změníš čas či místo převzetí — online i v aplikaci.'],
            ['icon' => 'card', 'title' => 'Bez kauce', 'text' => 'Nic ti neblokujeme na kartě.'],
            ['icon' => 'shield', 'title' => '100% smluvní krytí škod', 'text' => 'Při nehodě je tvoje spoluúčast 0 Kč.*'],
            ['icon' => 'helmet', 'title' => 'Výbava v ceně', 'text' => 'Motooblečení, vesta, lékárnička a kotoučový zámek. V Mezné i nepromoky.'],
            ['icon' => 'infinity', 'title' => 'Neomezené km a cesty do zahraničí', 'text' => 'Jeď, kam a jak daleko chceš (v rámci zelené karty).'],
            ['icon' => 'fuel', 'title' => 'Vracíš, jak ti to vyhovuje', 'text' => 'Tankovat nemusíš – jen ať nesvítí rezerva. Umytou ji vracej jen na samoobslužné pobočce ve Velkých Němčicích.'],
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
        'reasons_note' => '* Při dodržení podmínek nájmu (VOP čl. 7); nevztahuje se na odcizení.',
        // Pruh garancí hned pod hero (landing-guarantee.php). 'big' = velká dlaždice nahoře, 'pos' = pořadí
        // v rámci skupiny. Indexy 0–5 zůstávají (CMS klíče web.landing.common.guarantees.N.*), nové jen na konec.
        // Vratky dle pravidla od 2026-10-23 (čas od TEĎ do převzetí, Praha): ≥ 7 dní 100 %, ≥ 2 dny 50 %, jinak 0;
        // po posunu začátku strop 50 % (_storno_cap_after_move) — proto poznámka guar_note.
        'guar_title' => 'Garance MotoGo24',
        'guar_lead' => 'Plány se mění — až do začátku pronájmu rezervaci kdykoliv upravíš, i když se pokazí počasí.',
        'guarantees' => [
            ['icon' => 'shield', 'title' => '0 Kč spoluúčast', 'text' => 'při dodržení smlouvy*', 'pos' => 1],
            ['icon' => 'swap', 'title' => 'Termín posuneš zdarma', 'text' => 'kdykoliv do začátku pronájmu', 'big' => true, 'pos' => 2],
            ['icon' => 'resize', 'title' => 'Prodloužení kdykoliv', 'text' => 'bez poplatku za změnu', 'pos' => 3],
            ['icon' => 'calendar', 'title' => 'Zkrácení s vrácením peněz', 'text' => 'víc než 7 dní 100 %, víc než 2 dny 50 %', 'pos' => 4],
            ['icon' => 'edit', 'title' => 'Rezervaci upravíš zdarma', 'text' => 'do začátku pronájmu, bez poplatku za změnu', 'big' => true, 'pos' => 1],
            ['icon' => 'card', 'title' => 'Bez kauce', 'text' => 'nic ti neblokujeme', 'pos' => 2],
            ['icon' => 'storno', 'title' => 'Storno zdarma', 'text' => '7 a víc dní předem', 'big' => true, 'pos' => 3],
        ],
        'guar_note' => '* Při dodržení podmínek nájmu (VOP čl. 7); nevztahuje se na odcizení. Posun termínu a úpravy rezervace kdykoliv do začátku pronájmu. Zkrácení: vracíme cenu odebraných dní — víc než 7 dní před převzetím 100 %, víc než 2 dny 50 %, později vratku negarantujeme. Po předchozím posunu začátku vracíme při stornu i zkrácení nejvýš 50 %.',
        // Cenová kotva nad garancemi (důkaz v hlavičce souboru). {zero} = „0 Kč“ v měně návštěvníka,
        // {approx} = přepočet 20–30 tis. Kč do cizí měny „ (≈ …)“, u CZK prázdné. Částky v Kč NEpřepočítávat.
        'anchor_big' => '30 000 Kč kauce?',
        'anchor_ours' => 'U nás {zero}.',
        'anchor_sub' => 'Za velkou motorku chtějí půjčovny běžně 20–30 tisíc Kč{approx} kauci, u silných strojů i 50 tisíc. U nás neskládáš nic a spoluúčast při nehodě máš {zero}.*',
        'anchor_src' => 'Průzkum MotoGo24: ceníky 17 českých půjčoven ověřené 22. 10. 2026 — kauce u velkých motorek 10 000–50 000 Kč, nejčastěji 20 000–30 000 Kč.',
        // Promo „jen výbava“ dole na úvodní stránce a na /pujcovna-motorek (landing-gear-promo.php);
        // cena = nejlevnější aktivní komplet z gear_rental_prices (Velín), sekce jen při zapnutém půjčení.
        'gear_promo' => [
            'eyebrow' => 'Půjčení výbavy',
            'title' => 'Máš vlastní motorku? Půjč si jen výbavu',
            'lead' => 'Helma, bunda, kalhoty, rukavice i boty — na den nebo na celou dovolenou, bez kauce.',
            'from' => 'Komplet od {price} / den',
            'cta' => 'Půjčit výbavu',
            'moto' => 'Půjčuješ motorku? Výbava pro řidiče je u ní v ceně',
        ],
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
        'branch_book' => 'Vybrat',
        'branch_more' => 'Detail pobočky',
        'branches' => [
            ['badge' => 'S obsluhou · nonstop', 'title' => 'Mezná u Pelhřimova', 'text' => 'Osobní předání v čase, který si zvolíš, kompletní výbava v ceně, káva na uvítanou a přistavení motorky na adresu.', 'img' => '/gfx/provozovna-1.jpg', 'href' => '/pobocky/mezna', 'book_href' => '/rezervace?pobocka=11111111-1111-1111-1111-111111111111', 'times' => ['90 min z Prahy']],
            ['badge' => 'Samoobsluha · 24/7', 'title' => 'Velké Němčice u Brna', 'text' => 'Vyzvednutí i vrácení kdykoli, 100% nonstop, kódem z aplikace. Šatna s výbavou a parkování zdarma.', 'img' => '/gfx/pobocky/velke-nemcice/vydejni-box-640.webp', 'href' => '/pobocky/velke-nemcice', 'book_href' => '/rezervace?pobocka=22222222-2222-2222-2222-222222222222', 'times' => ['30 min z Brna', '35 min z letiště Brno']],
        ],
    ];
}
