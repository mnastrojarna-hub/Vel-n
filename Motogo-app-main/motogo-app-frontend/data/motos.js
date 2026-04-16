// ===== MOTOS.JS – Main motorcycle catalogue for MotoGo24 =====
// Part 1 of 2: First 5 motorcycles + all constants, helpers, and AI knowledge base.
// Part 2 (motos-extra.js) adds the remaining motorcycles via MOTOS.concat().

var MOTOS=[
  {id:'bmw',name:'BMW R 1200 GS Adventure',loc:'Mezná 9, 393 01 Mezná · 2023',
   img:'https://images.unsplash.com/photo-1558981359-219d6364c9c8?w=800&q=85&auto=format&fit=crop',
   imgs:['https://images.unsplash.com/photo-1558981806-ec527fa84c39?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1449426468159-d96dbf08f19f?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1558981359-219d6364c9c8?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1568772585407-9361f9bf3a87?w=900&q=90&auto=format&fit=crop'],avail:true,cat:'cestovni',rp:'A',vykon:92,
   desc:'Legenda mezi adventure motorkami. Ideální pro dlouhé roadtripy po silnici i lehkém terénu. Boxer motor s charakteristickým zvukem, nádrž 30 L a prémiové vybavení z ní dělají perfektního společníka na každý výlet.',
   specs:[{l:'Motor',v:'1 254 cc boxer'},{l:'Výkon',v:'92 kW / 125 k'},{l:'Točivý moment',v:'125 Nm'},{l:'Hmotnost',v:'268 kg'},{l:'Nádrž',v:'30 L'},{l:'Sedlo',v:'850–870 mm'},{l:'ŘP kategorie',v:'A'},{l:'ABS / ASC',v:'Ano / Ano'}],
   feats:['Cestovní enduro – prémiová třída','Dlouhé trasy, roadtripy, přejezdy','Jízda ve dvou (spolujezdec OK)','Silnice + lehký terén','Velcí jezdci 175–200 cm'],vyuziti:['silnice','teren','dvou'],
   pricing:{po:4208,ut:3788,st:3367,ct:3788,pa:4208,so:4882,ne:4629},
   branch:'mezna',manual:'BMW_R1200GS_Navod_2023.pdf',
   price:'4 208 Kč',vyuziti:['silnice','teren','dvou','dlouhe-cesty']},
  {id:'jawa',name:'Jawa RVM 500 Adventure',loc:'Mezná 9, 393 01 Mezná · 2023',
   img:'https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=800&q=85&auto=format&fit=crop',
   imgs:['https://images.unsplash.com/photo-1571068316344-75bc76f77890?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1558618047-3c8c76ca7d13?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=900&q=90&auto=format&fit=crop'],avail:true,cat:'cestovni',rp:'A2',vykon:35,
   desc:'Moderní česká legenda v kategorii A2. Výborný poměr ceny a kvality. Díky omezení na 35 kW vhodná pro A2 průkaz. Pohodlná i na delší výlety, přívětivá pro menší jezdce.',
   specs:[{l:'Motor',v:'500 cc jednoválec'},{l:'Výkon',v:'35 kW (A2)'},{l:'Točivý moment',v:'43 Nm'},{l:'Hmotnost',v:'195 kg'},{l:'Nádrž',v:'18 L'},{l:'Sedlo',v:'810 mm'},{l:'ŘP kategorie',v:'A2'},{l:'ABS',v:'Ano'}],
   feats:['Cestovní enduro – kategorie A2','Pro začátečníky i pokročilé','Menší a střední jezdci','Silnice + lehký terén','Výborná cena/výkon'],vyuziti:['silnice','teren','zacatecnici'],
   pricing:{po:1986,ut:1788,st:1589,ct:1788,pa:1986,so:2383,ne:2185},
   branch:'mezna',manual:'Jawa_RVM500_Navod_2023.pdf',
   price:'1 986 Kč',vyuziti:['silnice','teren','zacatecnici']},
  {id:'benelli',name:'Benelli TRK 702 X',loc:'Mezná 9, 393 01 Mezná · 2022',
   img:'https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=800&q=85&auto=format&fit=crop',
   imgs:['https://images.unsplash.com/photo-1547549082-6bc09f2049ae?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1558981852-426c349548ab?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1609630875171-b1321377ee65?w=900&q=90&auto=format&fit=crop','https://images.unsplash.com/photo-1568772585407-9361f9bf3a87?w=900&q=90&auto=format&fit=crop'],avail:true,cat:'cestovni',rp:'A2',vykon:35,
   desc:'Italský charakter a moderní crossover design. TRK 702X je adventure motorka pro vyšší jezdce kategorie A2 se solidní výbavou. Vhodná na silnici i nezpevněné cesty.',
   specs:[{l:'Motor',v:'702 cc dvojválec'},{l:'Výkon',v:'35 kW (A2)'},{l:'Točivý moment',v:'67 Nm'},{l:'Hmotnost',v:'215 kg'},{l:'Nádrž',v:'20 L'},{l:'Sedlo',v:'830 mm'},{l:'ŘP kategorie',v:'A2'},{l:'ABS',v:'Ano'}],
   feats:['Crossover adventure – A2 kategorie','Vyšší jezdci 175–195 cm','Delší cesty a výlety','Silnice i nezpevněno','Italský design'],
   pricing:{po:2951,ut:2725,st:2422,ct:2725,pa:2892,so:3541,ne:3331},
   branch:'mezna',manual:'Benelli_TRK702X_Navod_2022.pdf',
   price:'2 951 Kč',vyuziti:['silnice','teren','dlouhe-cesty']},
  {id:'cfmoto',name:'CF MOTO 800 MT',loc:'Mezná 9, 393 01 Mezná · 2023',
   img:'https://images.unsplash.com/photo-1449426468159-d96dbf08f19f?w=800&q=85&auto=format&fit=crop',
   imgs:['https://images.unsplash.com/photo-1449426468159-d96dbf08f19f?w=800&q=85&auto=format&fit=crop','https://images.unsplash.com/photo-1558981359-219d6364c9c8?w=800&q=85&auto=format&fit=crop','https://images.unsplash.com/photo-1571068316344-75bc76f77890?w=800&q=85&auto=format&fit=crop','https://images.unsplash.com/photo-1558618047-3c8c76ca7d13?w=800&q=85&auto=format&fit=crop'],avail:true,cat:'cestovni',rp:'A',vykon:67,
   desc:'Moderní adventure tourer s výkonným dvojválcem. Skvělá aerodynamika, velký nádrž a pohodlná ergonomie. Výborná volba pro dlouhé trasy i jízdu ve dvou.',
   specs:[{l:'Motor',v:'800 cc dvojválec'},{l:'Výkon',v:'67 kW / 91 k'},{l:'Točivý moment',v:'80 Nm'},{l:'Hmotnost',v:'221 kg'},{l:'Nádrž',v:'18,5 L'},{l:'Sedlo',v:'835 mm'},{l:'ŘP kategorie',v:'A'},{l:'ABS / TCS',v:'Ano / Ano'}],
   feats:['Adventure tourer','Dlouhé roadtripy','Jízda ve dvou (spolujezdec OK)','Silnice + lehký terén','Výborný poměr cena/výkon'],
   pricing:{po:3941,ut:3663,st:3256,ct:3663,pa:3892,so:4729,ne:4476},
   branch:'mezna',manual:'CFMOTO_800MT_Navod_2023.pdf',
   price:'3 941 Kč',vyuziti:['silnice','teren','dvou','dlouhe-cesty']},

  // -- NOVE MOTORKY Z FOTKY --
  {id:'yamaha-niken',name:'Yamaha Niken GT',loc:'Mezná 9, 393 01 Mezná · 2021',
   img:'photos/yamaha-niken_1.jpg',
   imgs:['photos/yamaha-niken_1.jpg','photos/yamaha-niken_2.jpg','photos/yamaha-niken_3.jpg','photos/yamaha-niken_4.jpg','photos/yamaha-niken_5.jpg'],avail:true,cat:'cestovni',rp:'A',vykon:84,
   desc:'Unikátní tříkolová motorka s předními dvěma koly pro maximální stabilitu. Niken GT je revoluční stroj pro dobrodruhy, kteří chtějí zažít něco zcela jiného. Výborná stabilita v zatáčkách, pohodlné GT vybavení.',
   specs:[{l:'Motor',v:'847 cc trojválec'},{l:'Výkon',v:'84 kW / 115 k'},{l:'Točivý moment',v:'88 Nm'},{l:'Hmotnost',v:'263 kg'},{l:'Nádrž',v:'18 L'},{l:'Sedlo',v:'820 mm'},{l:'ŘP kategorie',v:'A'},{l:'ABS / TCS',v:'Ano / Ano'}],
   feats:['Tříkolová – unikátní zážitek','Extrémní stabilita v zatáčkách','GT výbava – vyhřívání, TFT displej','Dlouhé trasy','Pro zkušené jezdce'],
   pricing:{po:3931,ut:3538,st:3144,ct:3538,pa:3931,so:4717,ne:4252},
   branch:'mezna',manual:'Yamaha_NikenGT_Navod_2021.pdf',
   price:'3 931 Kč',vyuziti:['silnice','dvou','dlouhe-cesty']}
];

// ===== DYNAMIC DATE HELPERS =====
const NOW=new Date();
const TODAY_Y=NOW.getFullYear(),TODAY_M=NOW.getMonth(),TODAY_D=NOW.getDate();
function fmtDate(d,m,y){return d+'. '+(m+1)+'. '+y;}
function fmtDateShort(d,m){return d+'. '+(m+1)+'.';}
function addDays(d,m,y,n){const dt=new Date(y,m,d+n);return{d:dt.getDate(),m:dt.getMonth(),y:dt.getFullYear()};}
// Active reservation: started yesterday, ends in 2 days
const ACT_START=addDays(TODAY_D,TODAY_M,TODAY_Y,-1);
const ACT_END=addDays(TODAY_D,TODAY_M,TODAY_Y,2);
// Upcoming reservation: starts in 3 days, ends in 5 days
const UPC_START=addDays(TODAY_D,TODAY_M,TODAY_Y,3);
const UPC_END=addDays(TODAY_D,TODAY_M,TODAY_Y,5);
// Done reservations: ended 10 and 20 days ago
const DONE1_START=addDays(TODAY_D,TODAY_M,TODAY_Y,-12);
const DONE1_END=addDays(TODAY_D,TODAY_M,TODAY_Y,-10);
const DONE2_START=addDays(TODAY_D,TODAY_M,TODAY_Y,-22);
const DONE2_END=addDays(TODAY_D,TODAY_M,TODAY_Y,-20);

// ===== AI KNOWLEDGE BASE =====
const AI_KB = [
  // MANUALY
  {keys:['manuál','manual','návod','příručka','obsluha'],
   ans:`📖 Návody k obsluze najdete v detailu každé motorky (záložka Detail → PDF Návod). Aktuálně máme manuály pro: BMW R1200GS, Yamaha Niken GT, KTM 1290 SA, Triumph Tiger 1200 a další. Chcete odkaz na konkrétní model?`},
  {keys:['kde je manuál','stáhnout manuál'],
   ans:`📥 Manuál stáhnete přímo v aplikaci: Domů → vyberte motorku → Detail → sekce "📖 Návod k obsluze" → klikněte na PDF. Pokud soubor nelze otevřít, pošleme vám jej e-mailem.`},

  // KONTROLKY -- obecne
  {keys:['kontrolka','svítí','bliká','warning','varování'],
   ans:`💡 Orientace v kontrolkách:
🔴 Červená = STOP ihned, vypněte motor
🟡 Oranžová = upozornění, jezděte opatrně
🔵 Modrá = dálková světla
🟢 Zelená = neutrál / blinkr

Která konkrétně svítí? Napište barvu + symbol a poradím přesněji.`},
  {keys:['červená kontrolka','engine','motor kontrolka'],
   ans:`🔴 Červená kontrolka motoru = ZASTAVTE OKAMŽITĚ. Vypněte motor, nepokračujte v jízdě. Mohlo dojít k přehřátí, úniku oleje nebo poruše elektroniky. Kontaktujte nás nebo zvolte možnost Nepojízdná motorka níže.`},
  {keys:['olejová kontrolka','olej svítí','nízký olej'],
   ans:`🛢️ Olejová kontrolka: Zastavte na bezpečném místě, vypněte motor. Zkontrolujte hladinu oleje prohlídkovým okénkem (pokud je přístupné). Při podtečení oleje NEJEĎTE – hrozí zadření motoru. Kontaktujte MotoGo24 ihned.`},
  {keys:['abs kontrolka','abs bliká'],
   ans:`⚙️ ABS kontrolka: Pokud bliká při jízdě, systém ABS může být dočasně deaktivován (nízká rychlost, nízké napětí baterie). Zastavte, vypněte a nastartujte znovu. Pokud zůstane svítit, jízda je nadále možná, ale buďte opatrní při brzdění – ABS nemusí fungovat.`},
  {keys:['tcs','trakce','tcs kontrolka','traction'],
   ans:`🏁 TCS/Trakce: Kontrolka TCS blikající při jízdě = systém aktivně zasahuje (kluzký povrch). To je normální. Trvale svítící TCS = systém deaktivován nebo závada. Zkuste restart, pokud přetrvá – nahlaste závadu.`},
  {keys:['check engine','servisní kontrolka'],
   ans:`🔧 Servisní kontrolka (klíč/motor): Oranžová = motorka potřebuje servis nebo běžnou prohlídku. Jízda je bezpečná, ale navštivte nás co nejdříve. Pokud bliká rychle – závažnější problém, doporučujeme zastavit a kontaktovat nás.`},
  {keys:['benzín','palivo svítí','dochází palivo','rezerva'],
   ans:`⛽ Rezerva paliva: Většina našich motorek má rezervu 2–4 litry po rozsvícení kontrolky. Dojezd cca 30–80 km (záleží na modelu a stylu jízdy). Nejbližší čerpací stanice – použijte GPS navigaci v telefonu. Čerpejte Natural 95 nebo 98.`},

  // INFOTAINMENT & DISPLEJ
  {keys:['displej','display','tft','obrazovka','nastavení displeje'],
   ans:`📱 TFT displej (BMW, KTM, Triumph, Yamaha Niken): Ovládání levou nebo pravou rukojetí – joystick nebo kolečko. Hlavní menu → MODE tlačítko. Jas nastavíte: Menu → Display → Brightness. Bluetooth párování: Menu → Connectivity → Bluetooth → Add device.`},
  {keys:['bluetooth','párovat telefon','hudba','navigace bluetooth'],
   ans:`📡 Bluetooth párování: 1) Na motorce: Menu → Connectivity/Communication → Bluetooth → Pairing mode. 2) V telefonu: Zapněte BT, hledejte zařízení s názvem motorky. 3) Potvrzení PIN kódu (obvykle 0000 nebo 1234). Po spárování funguje navigace, hudba i hovory přes interkom helmy.`},
  {keys:['interkom','headset','helma komunikace'],
   ans:`🎧 Interkom/Headset: Většina interkomů se páruje stejně jako BT telefon. Zapněte interkom do párovacího modu, pak párovací mód motorky. Po spojení slouží k navigaci a hudbě. Doporučujeme Sena nebo Cardo systémy – kompatibilní se všemi našimi motorkami.`},
  {keys:['jízdní mód','riding mode','rain','sport','off-road','mód jízdy'],
   ans:`🏍️ Jízdní módy: Přepínání obvykle tlačítkem MODE nebo přes TFT menu → Riding Mode. Dostupné módy závisí na modelu:
• Rain – snížený výkon, citlivé ABS
• Road/Street – standardní
• Sport – plný výkon, sportovní ABS
• Off-Road – méně citlivé ABS, více prokluzu
• Custom – vlastní nastavení
Přepínat lze pouze v klidu nebo při velmi nízké rychlosti!`},
  {keys:['vyhřívání rukojetí','heated grips','vyhřívané'],
   ans:`🌡️ Vyhřívání rukojetí: Dostupné na BMW GS, KTM 1290, Triumph Tiger, Yamaha Niken GT. Zapnutí: Levé tlačítko nebo přes menu → Heated Grips → Level 1/2/3. Při nízké teplotě baterie se výhřev automaticky snižuje.`},

  // BATERIE
  {keys:['baterka','kde je baterie','baterie umístění','akumulátor'],
   ans:`🔋 Umístění baterie podle modelu:
• BMW R1200GS – pod levým bočním krytím, za palivovým kohoutkem
• KTM 1290 SA – pod sedlem řidiče (odejmout sedlo)
• Yamaha MT-09 / Niken – pod nádrží, přístup přes sedlo
• Kawasaki Z900 – pod sedlem
• Triumph Tiger – pod levým bočním panelem
• Ducati Multistrada – pod sedlem, pravá strana

Na konkrétní model ukáže manuál v detailu motorky.`},
  {keys:['nastartovat baterie','slabá baterie','jumpstart','startovací kabely'],
   ans:`⚡ Slabá baterie: Většina moderních motorek má START/STOP systém – zkuste počkat 30s a nastartovat znovu. Jumpstart je možný přes svorky – VŽDY + na + a - na kostru (NE na -pól baterie). Pokud motor netočí vůbec, kontaktujte nás – pošleme pomoc.`},

  // POJISTKY
  {keys:['pojistka','pojistky','pojistková skříň','fuse','přepálená pojistka'],
   ans:`⚡ Pojistková skříň – umístění podle modelu:
• BMW R1200GS – pod nádrží, přístup přes horní kryt nebo boční panely. Hlavní pojistka 30A u baterie.
• KTM 1290 SA – pod sedlem, vedle baterie. Diagram na víčku.
• Yamaha (MT-09, Niken, Ténéré) – pod sedlem nebo za bočním panelem.
• Kawasaki Z900 – pod sedlem, pravá strana.
• Triumph Tiger – levý boční panel.
• Ducati Multistrada – pod sedlem, diagram v manuálu.

💡 Náhradní pojistky najdete v sadě nářadí motorky (pod sedlem).`},
  {keys:['nářadí','kde je nářadí','tool kit'],
   ans:`🔧 Nářadí: Standardní sada nářadí je uložena pod sedlem v plátěném sáčku nebo plastovém pouzdru. Obsahuje: imbus klíče, otevřené klíče, šroubovák, adaptér ventilu, lepení na defekt (PW50, XT660 nemají). Umístění detailněji v manuálu.`},

  // SPECIFICKE DOTAZY NA MODELY
  {keys:['bmw','r1200','gs adventure kontrolky'],
   ans:`🏍️ BMW R1200GS: TFT panel s Ride Modes Pro (Rain/Road/Dynamic/Enduro/Enduro Pro). ABS+ASC standardně. Baterie vlevo pod bočním panelem. Pojistky pod nádrží. Manuál v detailu motorky.`},
  {keys:['ktm','1290','super adventure'],
   ans:`🧡 KTM 1290 Super Adventure: WP APEX semi-aktivní podvozek. Modes: Street/Sport/Off-Road/Rain. Rally mód (v menu). Baterie pod sedlem. Pojistky u baterie. Velký TFT display – kompletní průvodce v manuálu.`},
  {keys:['triumph','tiger','explorer kontrolky'],
   ans:`🇬🇧 Triumph Tiger 1200: Trojválcový motor, 5 jízdních módů. Bluetooth, TFT, heated grips. Baterie levý boční panel. Pojistky tamtéž. Manuál v aplikaci.`},
  {keys:['yamaha','niken','tříkolová'],
   ans:`⚙️ Yamaha Niken GT: Přední dvě kola – LMW technologie. Ovládání identické s běžnou motorkou. TFT display, heated grips, cruise control. Baterie pod předním kapotáží – přístup v manuálu.`},
  {keys:['kawasaki','z900','naked'],
   ans:`🟢 Kawasaki Z900: Sport naked bike. Ride Modes: Sport/Road/Rain/Rider (custom). Rychlý shifter. Baterie pod sedlem. Manuál v aplikaci.`},
  {keys:['ducati','multistrada'],
   ans:`🔴 Ducati Multistrada 1200: L-twin Testastretta. Modes: Sport/Touring/Urban/Enduro. Skyhook semi-aktivní odpružení. Baterie pod sedlem pravá strana. Manuál v aplikaci.`},

  // KONTROLKY – rozšířené
  {keys:['baterie','nabíjení','vybíjí','akumulátor','napětí'],
   ans:`🔋 Baterie/nabíjení: Pokud kontrolka baterie svítí za jízdy, alternátor nedobíjí. Zkontrolujte napětí – mělo by být 13.5–14.5V. Při poklesu pod 12V hrozí postupná ztráta elektroniky. Omezte spotřebu (vyhřívání, světla) a dojeďte na nejbližší místo. Kontaktujte MotoGo24.`},
  {keys:['teplota','přehřátí','coolant','chladící','termostat'],
   ans:`🌡️ Kontrolka teploty/přehřátí: OKAMŽITĚ zastavte a vypněte motor. Počkejte 15–20 minut na vychladnutí. Zkontrolujte hladinu chladící kapaliny (okénko na nádobce). NIKDY neotevírejte víčko na horký motor! Pokud kontrolka svítí znovu po doplnění – motorka je nepojízdná, volejte MotoGo24.`},
  {keys:['imobilizér','klíč nerozpoznán','security','alarm'],
   ans:`🔑 Imobilizér/security: Motorka nerozpoznává klíč → zkuste klíč vyjmout, počkat 10s a znovu vložit. Zkontrolujte baterii v klíči. Pokud bliká security kontrolka trvale – imobilizér blokuje start. Kontaktujte MotoGo24 – vzdálená deaktivace možná.`},
  {keys:['fi kontrolka','vstřikování','fuel injection','fi bliká'],
   ans:`💉 FI (Fuel Injection) kontrolka: Problém s palivovým vstřikováním. Pokud bliká – snížte rychlost a jeďte opatrně na nejbližší místo. Motor může mít sníženou odezvu. Pokud svítí trvale – doporučujeme zastavit a kontaktovat MotoGo24 pro diagnostiku.`},

  // OBECNE PORUCHY
  {keys:['nastartovat','nechce nastartovat','motor nespustí'],
   ans:`🔑 Nechce nastartovat? Postup:
1. Páčka spojky zcela stisknutá
2. Neutrál (zeleně N na displeji)
3. Pojistka rukojetě (kill switch) – v poloze RUN
4. Stojan zasunutý (některé motorky blokují start)
5. Choke u karburátorových modelů
Pokud nic nezabere – kontaktujte nás.`},
  {keys:['pneumatika','defekt','flat tyre','píchlé'],
   ans:`🛞 Defekt: Okamžitě snižujte rychlost, nesahejte na brzdu prudce. Zastavte u krajnice. Nesnažte se jet dál – hrozí ztráta řízení a poškození ráfku. Zavolejte nás nebo zvolte Náhradní motorka.`},
  {keys:['olej uniká','olejová skvrna','olej pod motorkou'],
   ans:`🛢️ Únik oleje: ZASTAVTE OKAMŽITĚ a vypněte motor. Jízda s únikem oleje = zadření motoru = totální škoda. Zvolte Motorka nepojízdná a kontaktujte nás.`},
  // SIMULATED GENERAL
  {keys:['ahoj','dobrý den','čau','nazdar','hey','hello','hi'],
   ans:`👋 Dobrý den! Jsem MotoGo AI asistent. Jak vám mohu pomoci? Mohu poradit s kontrolkami, poruchami, manuály nebo technickými dotazy k vaší motorce.`},
  {keys:['děkuji','díky','dík','thanks'],
   ans:`👍 Rádo se stalo! Pokud budete potřebovat další pomoc, jsem tu pro vás 24/7. Šťastnou jízdu! 🏍️`},
  {keys:['cena','kolik stojí','ceník','sleva'],
   ans:`💰 Ceny pronájmu najdete v detailu každé motorky. Denní sazby se liší podle dne v týdnu. Zálohu neúčtujeme! Slevové kódy zadáte při rezervaci. Více info: motogo24.vseproweb.com`},
  {keys:['počasí','déšť','mráz','led','mokro'],
   ans:`🌧️ Jízda za deště: Přepněte do Rain/Wet módu. Snižte rychlost, zvětšete rozestupy. Na mokru brzdná dráha 2x delší. Pozor na kanály, zebrahy a listy. V případě silné bouře zastavte a počkejte.`},
  {keys:['helma','přilba','ochranné','oblečení','rukavice'],
   ans:`🪖 Ochranné vybavení: Homologovaná přilba je povinná! Doporučujeme: přilba ECE 22.06, rukavice, bunda s chrániči, kalhoty s chrániči, kotníkové boty. Půjčení helmy možné jako extra při rezervaci.`},
  {keys:['pojištění','havárie','škoda','nehoda'],
   ans:`🛡️ Pojištění: Všechny motorky jsou kryty povinným ručením a havarijním pojištěním. Spoluúčast nájemce: max 30 000 Kč (při zabezpečení). Při nehodě nezaviněné vámi – vše zdarma. Detaily ve VOP.`},
];

// ===== KM ESTIMATES (for delivery price calculation) =====
const KM_ESTIMATES={
  'Praha':130,'Brno':90,'Jihlava':30,'Třebíč':45,'České Budějovice':70,
  'Havlíčkův Brod':50,'Humpolec':15,'Mezná':0,'Pelhřimov':10,'Tábor':35,
  'Ostrava':280,'Plzeň':200,'Liberec':210,'Olomouc':180,'Hradec Králové':170,
  'Ústí nad Labem':200,'Pardubice':120,'Zlín':180,'Havířov':290,'Kladno':145,
  'Most':210,'Opava':290,'Frýdek-Místek':270,'Karviná':300,'Teplice':200,
  'Děčín':210,'Karlovy Vary':220,'Chomutov':210,'Jablonec nad Nisou':200,
  'Prostějov':150,'Přerov':170,'Mladá Boleslav':150,'Česká Lípa':190,
  'Třinec':280,'Znojmo':110,'Příbram':100,'Cheb':240,'Kolín':120,
  'Trutnov':190,'Písek':55,'Kroměříž':160,'Šumperk':180,'Vsetín':190,
  'Valašské Meziříčí':195,'Litoměřice':190,'Uherské Hradiště':170,
  'Břeclav':130,'Hodonín':140,'Vyškov':120,'Blansko':100,'Klatovy':160,
  'Sokolov':230,'Nový Jičín':250,'Žďár nad Sázavou':55,'Benešov':100,
  'Beroun':120,'Kutná Hora':110,'Chrudim':95,'Svitavy':90,'Náchod':180,
  'Rychnov nad Kněžnou':170,'Strakonice':75,'Prachatice':60,'Domažlice':180,
  'Rokycany':170,'Louny':190,'Rakovník':160,'Mělník':155,'Nymburk':140,
  'Semily':180,'Pacov':15,'Kamenice nad Lipou':20
};

// ===== DISCOUNT CODES =====
const CODES={MOTO10:10,MOTO20:20,JARO25:25,BETA15:15,PRVNI10:10};

// ===== CALENDAR DATA =====
const MONTHS=['Leden','Únor','Březen','Duben','Květen','Červen','Červenec','Srpen','Září','Říjen','Listopad','Prosinec'];
// Dynamic occupied dates based on current month
const OCC={};
(function(){
  var dim=new Date(TODAY_Y,TODAY_M+1,0).getDate();
  var o1=Math.max(1,TODAY_D-5),o2=Math.max(1,TODAY_D-4);
  var o3=TODAY_D+10<=dim?TODAY_D+10:Math.min(dim,TODAY_D+12);
  // Never mark today as occupied
  if(o1===TODAY_D)o1=Math.max(1,TODAY_D-6);
  if(o2===TODAY_D)o2=Math.max(1,TODAY_D-7);
  if(o3===TODAY_D)o3=TODAY_D+11<=dim?TODAY_D+11:null;
  var arr=[o1,o2];if(o3)arr.push(o3);
  OCC[TODAY_M]=arr;
})();
OCC[(TODAY_M+1)%12]=[3,10,11,18];
OCC[(TODAY_M+2)%12]=[7,8,20,21];
OCC[(TODAY_M+3)%12]=[5,15,16];

// Dynamic unconfirmed dates based on current month
const UNCONF={};
(function(){
  var dim=new Date(TODAY_Y,TODAY_M+1,0).getDate();
  var u1=Math.min(dim,TODAY_D+7),u2=Math.min(dim,TODAY_D+8);
  if(u1===TODAY_D)u1=Math.min(dim,TODAY_D+9);
  if(u2===TODAY_D)u2=Math.min(dim,TODAY_D+10);
  UNCONF[TODAY_M]=[u1,u2];
})();
UNCONF[(TODAY_M+1)%12]=[5,19,20];
UNCONF[(TODAY_M+2)%12]=[15,16];
