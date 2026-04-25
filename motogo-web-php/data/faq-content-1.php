<?php
// ===== MotoGo24 — FAQ obsah 1/3 (Rezervace + Vypujcka 1/2) =====
// 1:1 prepis z https://www.motogo24.cz/cz/jak-si-pujcit-motorku/casto-kladene-dotazy

return [
    'reservations' => [
        'label' => 'Rezervace',
        'items' => [
            [
                'q' => 'Jak si mohu rezervovat motorku?',
                'a' => 'Motorku si můžeš rezervovat přes náš online rezervační systém přímo tady na webu. Pokud budeš potřebovat pomoc, klidně se nám ozvi – e-mailem, telefonicky nebo přes sociální sítě – rádi ti pomůžeme.',
            ],
            [
                'q' => 'Můžu si motorku půjčit i bez předchozí rezervace?',
                'a' => 'Bez rezervace to bohužel nejde. Každou motorku je nutné předem zamluvit přes náš online systém. Bez rezervace nemůžeme zaručit dostupnost motocyklu.',
            ],
            [
                'q' => 'Jak probíhá rezervace?',
                'a' => 'Rezervace probíhá ve třech krocích: vyplníš základní údaje, zkontroluješ shrnutí a cenu, a rovnou zaplatíš online. Potvrzení platby spolu s návrhem nájemní smlouvy ti přijde e-mailem okamžitě. Smlouva nabývá platnosti až při osobním převzetí motorky, po ověření ŘP a OP (nebo PASu).',
            ],
            [
                'q' => 'Musím mít rezervaci předem?',
                'a' => 'Ano, rezervace je povinná. Bez ní nemůžeme zaručit dostupnost motorky.',
            ],
            [
                'q' => 'Jak zaplatím?',
                'a' => 'Online platební kartou – zaplatíš přímo v rezervačním formuláři.',
            ],
            [
                'q' => 'Kdo podepisuje smlouvu za dítě?',
                'a' => 'Smlouvu podepisuje rodič nebo zákonný zástupce, který je zároveň uveden jako nájemce.',
            ],
            [
                'q' => 'Jaký řidičský průkaz potřebuji?',
                'a' => 'Záleží na tom, jakou motorku si vybereš – u každého modelu je přímo v nabídce uvedeno, jaké řidičské oprávnění je potřeba. Silnější stroje vyžadují skupinu A, slabší skupinu A2. Na dětské motorky řidičský průkaz nepotřebuješ.',
            ],
            [
                'q' => 'Mohu rezervaci zrušit nebo změnit termín?',
                'a' => 'Rezervaci lze zrušit bez poplatku nejpozději 7 dní před sjednaným termínem převzetí. Pokud motorku nepřevezmeš bez předchozího zrušení rezervace, účtujeme plnou výši nájemného. Změnu termínu řeš s námi individuálně co nejdříve – ozvi se telefonicky nebo e-mailem.',
            ],
            [
                'q' => 'Co se stane, když motorku z vaší strany nebudete moci předat?',
                'a' => 'V takovém případě tě okamžitě kontaktujeme a nabídneme ti nejlepší možné řešení – náhradní motorku nebo jiný termín. A jako omluvu dostaneš slevu na příští rezervaci.',
            ],
            [
                'q' => 'Jak si zvolím správnou velikost výbavy?',
                'a' => 'Velikosti můžeš vyplnit předem přímo v rezervačním formuláři. Pokud chceš vybrat až na místě, vyzkoušíš si různé velikosti při převzetí. V případě přistavení motorky na jiné místo je výběr velikostí předem povinný, abychom ti mohli dovézt správnou výbavu. Dostupnost konkrétních velikostí závisí na aktuální obsazenosti půjčovny.',
            ],
        ],
    ],
    'borrowing' => [
        'label' => 'Výpůjčka a vrácení',
        'items' => [
            [
                'q' => 'Můžu motorku při vrácení na jiném místě vrátit dřív, než jsme se domluvili?',
                'a' => 'Na sjednané místo vyjíždíme z Pelhřimova přesně podle domluveného času, takže dřívější vrácení bohužel není možné. Pokud se ti plány změní, ozvi se nám – pokusíme se čas přizpůsobit, ale záleží na naší aktuální vytíženosti.',
            ],
            [
                'q' => 'Můžu motorku vrátit opravdu kdekoliv v ČR?',
                'a' => 'Ano, přijedeme si pro motorku kamkoliv v České republice. Místo vrácení zadáš při rezervaci – může to být hotel, parkoviště, nádraží nebo jakákoliv jiná adresa.',
            ],
            [
                'q' => 'Jak daleko dopředu musím vrácení na jiném místě nahlásit?',
                'a' => 'Místo a čas vrácení zadáváš už v rezervačním formuláři.',
            ],
            [
                'q' => 'Co když se na místo vrácení zpozdím?',
                'a' => 'Zavolej nám, jakmile víš, že to nestihneš na čas. Domluvíme se – většinou na tebe počkáme. Jen potřebujeme vědět, s jakým zpožděním počítat, abychom si mohli přizpůsobit plán dne.',
            ],
            [
                'q' => 'Jak se počítá cena za vrácení na jiném místě?',
                'a' => 'Cena zahrnuje 500 Kč za naložení, 500 Kč za vyložení a 20 Kč za každý kilometr vzdálenosti z místa vrácení do půjčovny (tam i zpět). Například při vrácení 50 km od Pelhřimova zaplatíš 500 + 500 + (50 × 2 × 20) = 3 000 Kč.',
            ],
            [
                'q' => 'Platím za vrácení jinde zvlášť, nebo je to součástí ceny pronájmu?',
                'a' => 'Vrácení na jiném místě je doplňková služba a platí se zvlášť nad rámec ceny pronájmu.',
            ],
            [
                'q' => 'Co když chci motorku vyzvednout v Pelhřimově, ale vrátit jinde – jde to?',
                'a' => 'Ano, můžeš vyzvednout motorku u nás v Pelhřimově a vrátíš ji tam, kde potřebuješ.',
            ],
            [
                'q' => 'Co mám mít připravené, když přijedete pro motorku?',
                'a' => 'Měj připravené klíče a veškerou výbavu, která byla součástí výpůjčky. Společně zkontrolujeme stav motorky a výbavy.',
            ],
            [
                'q' => 'Můžu motorku vrátit do půjčovny dřív, než jsme se domluvili?',
                'a' => 'Ano, motorku můžeš vrátit kdykoliv během posledního dne výpůjčky. Stačí nám dát vědět, že dorazíš dřív. Žádné příplatky za dřívější vrácení neúčtujeme.',
            ],
            [
                'q' => 'Co se stane, když nestihnu motorku do půjčovny vrátit do půlnoci posledního dne?',
                'a' => 'Pokud víš, že se zpozdíš, ozvi se nám co nejdřív. Domluvíme se na řešení. V případě neoznámeného pozdního vrácení se postupuje podle podmínek nájemní smlouvy.',
            ],
            [
                'q' => 'Musím při vrácení v půjčovně něco podepsat?',
                'a' => 'Pokud je vše v pořádku, vrácení proběhne rychle a bez zbytečného papírování. Potvrzení o ukončení nájmu a konečnou fakturu dostaneš na e-mail.',
            ],
            [
                'q' => 'Jak probíhá kontrola motorky při vrácení v půjčovně?',
                'a' => 'Společně projdeme stav motorky a výbavy. Pokud je vše v pořádku, převezmeme klíče a výbavu a ty můžeš jít. Celé to zabere pár minut.',
            ],
            [
                'q' => 'Kde probíhá vyzvednutí a vrácení?',
                'a' => 'V místě půjčovny na adrese Mezná 9, Pelhřimov. V rezervačním formuláři si ale můžeš domluvit i vyzvednutí nebo vrácení na jiném místě.',
            ],
            [
                'q' => 'Do kdy musím motorku vrátit?',
                'a' => 'Motorku vrať ideálně ve sjednaný čas. Pokud vracíš v místě půjčovny, můžeš ale přijet po dohodě kdykoli během posledního dne výpůjčky – nejpozději do půlnoci, bez jakýchkoli sankcí. Vracíš-li na jiném místě, je sjednaný čas závazný.',
            ],
            [
                'q' => 'Musím vracet s plnou nádrží a čistou?',
                'a' => 'Ne. U nás netankuješ ani nemyješ. Jen hlídej, aby nesvítila rezerva.',
            ],
            [
                'q' => 'Musím přijet osobně?',
                'a' => 'Ano, při převzetí motorky je nutná osobní přítomnost – ověříme tvé doklady (ŘP a OP nebo PAS), společně podepíšeme předávací protokol a vybereme výbavu.',
            ],
        ],
    ],
];
