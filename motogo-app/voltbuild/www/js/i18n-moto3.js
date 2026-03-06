// i18n-moto3.js – Spec labels, months, day abbreviations, pricing labels & merch translations for MotoGo24
(function(){
function m(s){for(var l in s){if(!I18N[l])continue;for(var k in s[l])I18N[l][k]=s[l][k];}}
m({
/* ───── CS ───── */
cs:{
specL:{Motor:'Motor',Výkon:'Výkon','Točivý moment':'Točivý moment',Hmotnost:'Hmotnost',Nádrž:'Nádrž',Sedlo:'Sedlo','ŘP kategorie':'ŘP kategorie',Převodovka:'Převodovka',Věk:'Věk',Typ:'Typ',Bezpečnost:'Bezpečnost','ŘP':'ŘP'},
specV:{Ano:'Ano',Ne:'Ne',jednoválec:'jednoválec',dvojválec:'dvojválec',trojválec:'trojválec',čtyřválec:'čtyřválec',dvoutakt:'dvoutakt',Automatická:'Automatická','Manuál 6st.':'Manuál 6st.',Motokros:'Motokros','Omezovač plynu':'Omezovač plynu',Nevyžaduje:'Nevyžaduje',let:'let'},
months:['Leden','Únor','Březen','Duben','Květen','Červen','Červenec','Srpen','Září','Říjen','Listopad','Prosinec'],
dayAbbr:{po:'Po',ut:'Út',st:'St',ct:'Čt',pa:'Pá',so:'So',ne:'Ne'},
pricingL:{pricingTitle:'\uD83D\uDCB0 Ceník dle dne v týdnu',perDay:'Kč/den',pricingNote:'Ceny bez DPH. Víkend Pá–Ne. 1 den = 24 h.',branch:'Pobočka',todayFree:'\u2713 Dnes volná',todayBusy:'\u2717 Dnes obsazená',rpLabel:'ŘP',fromLabel:'od',perDayNote:'za den / cena bez DPH',detailBtn:'Detail \u2192',kidsWarn:'\u26A0\uFE0F Pouze pro děti \u00B7 uzavřený prostor \u00B7 dohled zákonného zástupce \u00B7 není povolen provoz na veřejných komunikacích'},
merch:{
cap:{name:'Snapback čepice',desc:'Stylová snapback čepice s vyšitým logem MotoGo24. Nastavitelný pásek vzadu pro dokonalé padnutí. Kvalitní bavlněný materiál.',color:'Černá',sub:'Černá · Logo MotoGo24'},
tshirt:{name:'Tričko Classic',desc:'Klasické tričko s logem MotoGo24 na hrudi. Pohodlný střih, kvalitní 100% bavlna. Ideální na motorku i do města.',color:'Černé',sub:'Černé · Logo MotoGo24'},
hoodie:{name:'Hoodie Premium',desc:'Prémiová mikina s kapucí a zipem. Fleece podšívka pro maximální pohodlí. Vyšité logo MotoGo24 na hrudi.',color:'Černá',sub:'Černá · Fleece · Logo MotoGo24'},
tshirt2:{name:'Tričko Ride Hard',desc:'Prémiové tričko z limitované edice Ride Hard. Měkký materiál, moderní střih. Velký potisk MotoGo24 Ride Hard na zádech.',color:'Zelené',sub:'Zelené · Limitovaná edice'}
}
},

/* ───── EN ───── */
en:{
specL:{Motor:'Engine',Výkon:'Power','Točivý moment':'Torque',Hmotnost:'Weight',Nádrž:'Tank',Sedlo:'Seat height','ŘP kategorie':'License',Převodovka:'Gearbox',Věk:'Age',Typ:'Type',Bezpečnost:'Safety','ŘP':'License'},
specV:{Ano:'Yes',Ne:'No',jednoválec:'single-cylinder',dvojválec:'twin-cylinder',trojválec:'triple',čtyřválec:'four-cylinder',dvoutakt:'two-stroke',Automatická:'Automatic','Manuál 6st.':'Manual 6-speed',Motokros:'Motocross','Omezovač plynu':'Throttle limiter',Nevyžaduje:'Not required',let:'years'},
months:['January','February','March','April','May','June','July','August','September','October','November','December'],
dayAbbr:{po:'Mon',ut:'Tue',st:'Wed',ct:'Thu',pa:'Fri',so:'Sat',ne:'Sun'},
pricingL:{pricingTitle:'\uD83D\uDCB0 Price by day of the week',perDay:'CZK/day',pricingNote:'Prices excl. VAT. Weekend Fri\u2013Sun. 1 day = 24 h.',branch:'Branch',todayFree:'\u2713 Available today',todayBusy:'\u2717 Not available today',rpLabel:'License',fromLabel:'from',perDayNote:'per day / prices excl. VAT',detailBtn:'Details \u2192',kidsWarn:'\u26A0\uFE0F Kids only \u00B7 enclosed area \u00B7 parental supervision required \u00B7 not allowed on public roads'},
merch:{
cap:{name:'Snapback Cap',desc:'Stylish snapback cap with embroidered MotoGo24 logo. Adjustable strap at the back for a perfect fit. Premium cotton material.',color:'Black',sub:'Black · MotoGo24 Logo'},
tshirt:{name:'T-shirt Classic',desc:'Classic T-shirt with MotoGo24 logo on the chest. Comfortable fit, premium 100% cotton. Perfect for riding or the city.',color:'Black',sub:'Black · MotoGo24 Logo'},
hoodie:{name:'Hoodie Premium',desc:'Premium hoodie with hood and zip. Fleece lining for maximum comfort. Embroidered MotoGo24 logo on the chest.',color:'Black',sub:'Black · Fleece · MotoGo24 Logo'},
tshirt2:{name:'T-shirt Ride Hard',desc:'Premium T-shirt from the limited Ride Hard edition. Soft material, modern fit. Large MotoGo24 Ride Hard print on the back.',color:'Green',sub:'Green · Limited Edition'}
}
},

/* ───── DE ───── */
de:{
specL:{Motor:'Motor',Výkon:'Leistung','Točivý moment':'Drehmoment',Hmotnost:'Gewicht',Nádrž:'Tank',Sedlo:'Sitzhöhe','ŘP kategorie':'Führerschein',Převodovka:'Getriebe',Věk:'Alter',Typ:'Typ',Bezpečnost:'Sicherheit','ŘP':'Führerschein'},
specV:{Ano:'Ja',Ne:'Nein',jednoválec:'Einzylinder',dvojválec:'Zweizylinder',trojválec:'Dreizylinder',čtyřválec:'Vierzylinder',dvoutakt:'Zweitakt',Automatická:'Automatik','Manuál 6st.':'6-Gang',Motokros:'Motocross','Omezovač plynu':'Gasbegrenzer',Nevyžaduje:'Nicht erforderlich',let:'Jahre'},
months:['Januar','Februar','März','April','Mai','Juni','Juli','August','September','Oktober','November','Dezember'],
dayAbbr:{po:'Mo',ut:'Di',st:'Mi',ct:'Do',pa:'Fr',so:'Sa',ne:'So'},
pricingL:{pricingTitle:'\uD83D\uDCB0 Preis nach Wochentag',perDay:'CZK/Tag',pricingNote:'Preise ohne MwSt. Wochenende Fr\u2013So. 1 Tag = 24 Std.',branch:'Filiale',todayFree:'\u2713 Heute verf\u00FCgbar',todayBusy:'\u2717 Heute nicht verf\u00FCgbar',rpLabel:'F\u00FChrerschein',fromLabel:'ab',perDayNote:'pro Tag / Preise ohne MwSt.',detailBtn:'Details \u2192',kidsWarn:'\u26A0\uFE0F Nur f\u00FCr Kinder \u00B7 geschlossenes Gel\u00E4nde \u00B7 Aufsicht der Eltern erforderlich \u00B7 nicht f\u00FCr \u00F6ffentliche Stra\u00DFen'},
merch:{
cap:{name:'Snapback-Kappe',desc:'Stilvolle Snapback-Kappe mit gesticktem MotoGo24-Logo. Verstellbares Band hinten für perfekten Sitz. Hochwertiges Baumwollmaterial.',color:'Schwarz',sub:'Schwarz · MotoGo24-Logo'},
tshirt:{name:'T-Shirt Classic',desc:'Klassisches T-Shirt mit MotoGo24-Logo auf der Brust. Bequemer Schnitt, hochwertige 100% Baumwolle. Ideal zum Motorradfahren und in der Stadt.',color:'Schwarz',sub:'Schwarz · MotoGo24-Logo'},
hoodie:{name:'Hoodie Premium',desc:'Premium-Hoodie mit Kapuze und Reißverschluss. Fleece-Futter für maximalen Komfort. Gesticktes MotoGo24-Logo auf der Brust.',color:'Schwarz',sub:'Schwarz · Fleece · MotoGo24-Logo'},
tshirt2:{name:'T-Shirt Ride Hard',desc:'Premium-T-Shirt aus der limitierten Ride-Hard-Edition. Weiches Material, moderner Schnitt. Großer MotoGo24 Ride Hard-Druck auf dem Rücken.',color:'Grün',sub:'Grün · Limitierte Edition'}
}
},

/* ───── ES ───── */
es:{
specL:{Motor:'Motor',Výkon:'Potencia','Točivý moment':'Par motor',Hmotnost:'Peso',Nádrž:'Depósito',Sedlo:'Altura del asiento','ŘP kategorie':'Permiso',Převodovka:'Cambio',Věk:'Edad',Typ:'Tipo',Bezpečnost:'Seguridad','ŘP':'Permiso'},
specV:{Ano:'Sí',Ne:'No',jednoválec:'monocilíndrico',dvojválec:'bicilíndrico',trojválec:'tricilíndrico',čtyřválec:'tetracilíndrico',dvoutakt:'dos tiempos',Automatická:'Automático','Manuál 6st.':'Manual 6 vel.',Motokros:'Motocross','Omezovač plynu':'Limitador acelerador',Nevyžaduje:'No requerido',let:'años'},
months:['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'],
dayAbbr:{po:'Lun',ut:'Mar',st:'Mié',ct:'Jue',pa:'Vie',so:'Sáb',ne:'Dom'},
pricingL:{pricingTitle:'\uD83D\uDCB0 Precio por d\u00EDa de la semana',perDay:'CZK/d\u00EDa',pricingNote:'Precios sin IVA. Fin de semana Vie\u2013Dom. 1 d\u00EDa = 24 h.',branch:'Sucursal',todayFree:'\u2713 Disponible hoy',todayBusy:'\u2717 No disponible hoy',rpLabel:'Permiso',fromLabel:'desde',perDayNote:'por d\u00EDa / precios sin IVA',detailBtn:'Detalle \u2192',kidsWarn:'\u26A0\uFE0F Solo para ni\u00F1os \u00B7 \u00E1rea cerrada \u00B7 supervisi\u00F3n parental obligatoria \u00B7 no permitido en v\u00EDas p\u00FAblicas'},
merch:{
cap:{name:'Gorra Snapback',desc:'Elegante gorra snapback con logo bordado MotoGo24. Correa ajustable en la parte trasera para un ajuste perfecto. Material de algodón de calidad.',color:'Negro',sub:'Negro · Logo MotoGo24'},
tshirt:{name:'Camiseta Classic',desc:'Camiseta clásica con logo MotoGo24 en el pecho. Corte cómodo, algodón 100% de calidad. Ideal para la moto y la ciudad.',color:'Negro',sub:'Negro · Logo MotoGo24'},
hoodie:{name:'Hoodie Premium',desc:'Sudadera premium con capucha y cremallera. Forro polar para máximo confort. Logo MotoGo24 bordado en el pecho.',color:'Negro',sub:'Negro · Fleece · Logo MotoGo24'},
tshirt2:{name:'Camiseta Ride Hard',desc:'Camiseta premium de la edición limitada Ride Hard. Material suave, corte moderno. Gran estampado MotoGo24 Ride Hard en la espalda.',color:'Verde',sub:'Verde · Edición Limitada'}
}
},

/* ───── FR ───── */
fr:{
specL:{Motor:'Moteur',Výkon:'Puissance','Točivý moment':'Couple',Hmotnost:'Poids',Nádrž:'Réservoir',Sedlo:'Hauteur de selle','ŘP kategorie':'Permis',Převodovka:'Boîte',Věk:'Âge',Typ:'Type',Bezpečnost:'Sécurité','ŘP':'Permis'},
specV:{Ano:'Oui',Ne:'Non',jednoválec:'monocylindre',dvojválec:'bicylindre',trojválec:'tricylindre',čtyřválec:'quatre-cylindres',dvoutakt:'deux-temps',Automatická:'Automatique','Manuál 6st.':'Manuelle 6 vit.',Motokros:'Motocross','Omezovač plynu':'Limiteur gaz',Nevyžaduje:'Non requis',let:'ans'},
months:['Janvier','Février','Mars','Avril','Mai','Juin','Juillet','Août','Septembre','Octobre','Novembre','Décembre'],
dayAbbr:{po:'Lun',ut:'Mar',st:'Mer',ct:'Jeu',pa:'Ven',so:'Sam',ne:'Dim'},
pricingL:{pricingTitle:'\uD83D\uDCB0 Prix par jour de la semaine',perDay:'CZK/jour',pricingNote:'Prix hors TVA. Week-end Ven\u2013Dim. 1 jour = 24 h.',branch:'Agence',todayFree:'\u2713 Disponible aujourd\u2019hui',todayBusy:'\u2717 Indisponible aujourd\u2019hui',rpLabel:'Permis',fromLabel:'\u00E0 partir de',perDayNote:'par jour / prix hors TVA',detailBtn:'D\u00E9tails \u2192',kidsWarn:'\u26A0\uFE0F Enfants uniquement \u00B7 espace clos \u00B7 surveillance parentale obligatoire \u00B7 interdit sur la voie publique'},
merch:{
cap:{name:'Casquette Snapback',desc:'Casquette snapback élégante avec logo MotoGo24 brodé. Sangle réglable à l\'arrière pour un ajustement parfait. Matériau en coton de qualité.',color:'Noir',sub:'Noir · Logo MotoGo24'},
tshirt:{name:'T-shirt Classic',desc:'T-shirt classique avec logo MotoGo24 sur la poitrine. Coupe confortable, coton 100% de qualité. Idéal pour la moto et la ville.',color:'Noir',sub:'Noir · Logo MotoGo24'},
hoodie:{name:'Hoodie Premium',desc:'Sweat à capuche premium avec fermeture éclair. Doublure polaire pour un confort maximal. Logo MotoGo24 brodé sur la poitrine.',color:'Noir',sub:'Noir · Polaire · Logo MotoGo24'},
tshirt2:{name:'T-shirt Ride Hard',desc:'T-shirt premium de l\'édition limitée Ride Hard. Matériau doux, coupe moderne. Grand imprimé MotoGo24 Ride Hard au dos.',color:'Vert',sub:'Vert · Édition Limitée'}
}
},

/* ───── NL ───── */
nl:{
specL:{Motor:'Motor',Výkon:'Vermogen','Točivý moment':'Koppel',Hmotnost:'Gewicht',Nádrž:'Tank',Sedlo:'Zithoogte','ŘP kategorie':'Rijbewijs',Převodovka:'Versnelling',Věk:'Leeftijd',Typ:'Type',Bezpečnost:'Veiligheid','ŘP':'Rijbewijs'},
specV:{Ano:'Ja',Ne:'Nee',jednoválec:'eencilinder',dvojválec:'tweecilinder',trojválec:'driecilinder',čtyřválec:'viercilinder',dvoutakt:'tweetakt',Automatická:'Automatisch','Manuál 6st.':'6-versnelling',Motokros:'Motocross','Omezovač plynu':'Gasbeperker',Nevyžaduje:'Niet vereist',let:'jaar'},
months:['Januari','Februari','Maart','April','Mei','Juni','Juli','Augustus','September','Oktober','November','December'],
dayAbbr:{po:'Ma',ut:'Di',st:'Wo',ct:'Do',pa:'Vr',so:'Za',ne:'Zo'},
pricingL:{pricingTitle:'\uD83D\uDCB0 Prijs per dag van de week',perDay:'CZK/dag',pricingNote:'Prijzen excl. BTW. Weekend Vr\u2013Zo. 1 dag = 24 uur.',branch:'Vestiging',todayFree:'\u2713 Vandaag beschikbaar',todayBusy:'\u2717 Vandaag niet beschikbaar',rpLabel:'Rijbewijs',fromLabel:'vanaf',perDayNote:'per dag / prijzen excl. BTW',detailBtn:'Details \u2192',kidsWarn:'\u26A0\uFE0F Alleen voor kinderen \u00B7 afgesloten terrein \u00B7 ouderlijk toezicht vereist \u00B7 niet toegestaan op openbare wegen'},
merch:{
cap:{name:'Snapback Pet',desc:'Stijlvolle snapback pet met geborduurd MotoGo24-logo. Verstelbare band aan de achterkant voor een perfecte pasvorm. Hoogwaardig katoenen materiaal.',color:'Zwart',sub:'Zwart · MotoGo24-Logo'},
tshirt:{name:'T-shirt Classic',desc:'Klassiek T-shirt met MotoGo24-logo op de borst. Comfortabele pasvorm, hoogwaardige 100% katoen. Ideaal voor op de motor en in de stad.',color:'Zwart',sub:'Zwart · MotoGo24-Logo'},
hoodie:{name:'Hoodie Premium',desc:'Premium hoodie met capuchon en rits. Fleece voering voor maximaal comfort. Geborduurd MotoGo24-logo op de borst.',color:'Zwart',sub:'Zwart · Fleece · MotoGo24-Logo'},
tshirt2:{name:'T-shirt Ride Hard',desc:'Premium T-shirt uit de gelimiteerde Ride Hard-editie. Zacht materiaal, moderne pasvorm. Grote MotoGo24 Ride Hard-print op de rug.',color:'Groen',sub:'Groen · Gelimiteerde Editie'}
}
},

/* ───── PL ───── */
pl:{
specL:{Motor:'Silnik',Výkon:'Moc','Točivý moment':'Moment obrotowy',Hmotnost:'Waga',Nádrž:'Zbiornik',Sedlo:'Wysokość siedzenia','ŘP kategorie':'Prawo jazdy',Převodovka:'Skrzynia biegów',Věk:'Wiek',Typ:'Typ',Bezpečnost:'Bezpieczeństwo','ŘP':'Prawo jazdy'},
specV:{Ano:'Tak',Ne:'Nie',jednoválec:'jednocylindrowy',dvojválec:'dwucylindrowy',trojválec:'trzycylindrowy',čtyřválec:'czterocylindrowy',dvoutakt:'dwusuw',Automatická:'Automatyczna','Manuál 6st.':'6-bieg.',Motokros:'Motocross','Omezovač plynu':'Ogranicznik gazu',Nevyžaduje:'Nie wymagane',let:'lat'},
months:['Styczeń','Luty','Marzec','Kwiecień','Maj','Czerwiec','Lipiec','Sierpień','Wrzesień','Październik','Listopad','Grudzień'],
dayAbbr:{po:'Pn',ut:'Wt',st:'Śr',ct:'Cz',pa:'Pt',so:'So',ne:'Nd'},
pricingL:{pricingTitle:'\uD83D\uDCB0 Cena wg dnia tygodnia',perDay:'CZK/dzie\u0144',pricingNote:'Ceny bez VAT. Weekend Pt\u2013Nd. 1 dzie\u0144 = 24 godz.',branch:'Oddzia\u0142',todayFree:'\u2713 Dost\u0119pny dzi\u015B',todayBusy:'\u2717 Niedost\u0119pny dzi\u015B',rpLabel:'Prawo jazdy',fromLabel:'od',perDayNote:'za dzie\u0144 / ceny bez VAT',detailBtn:'Szczeg\u00F3\u0142y \u2192',kidsWarn:'\u26A0\uFE0F Tylko dla dzieci \u00B7 teren zamkni\u0119ty \u00B7 wymagany nadz\u00F3r rodzica \u00B7 niedozwolony na drogach publicznych'},
merch:{
cap:{name:'Czapka Snapback',desc:'Stylowa czapka snapback z wyhaftowanym logo MotoGo24. Regulowany pasek z tyłu zapewnia idealne dopasowanie. Wysokiej jakości materiał bawełniany.',color:'Czarny',sub:'Czarny · Logo MotoGo24'},
tshirt:{name:'Koszulka Classic',desc:'Klasyczna koszulka z logo MotoGo24 na piersi. Wygodny krój, wysokiej jakości 100% bawełna. Idealna na motocykl i do miasta.',color:'Czarny',sub:'Czarny · Logo MotoGo24'},
hoodie:{name:'Bluza Premium',desc:'Bluza premium z kapturem i zamkiem. Podszewka polarowa dla maksymalnego komfortu. Wyhaftowane logo MotoGo24 na piersi.',color:'Czarny',sub:'Czarny · Polar · Logo MotoGo24'},
tshirt2:{name:'Koszulka Ride Hard',desc:'Koszulka premium z limitowanej edycji Ride Hard. Miękki materiał, nowoczesny krój. Duży nadruk MotoGo24 Ride Hard na plecach.',color:'Zielony',sub:'Zielony · Limitowana Edycja'}
}
}

});
})();
