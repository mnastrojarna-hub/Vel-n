<?php
// Categoriepagina's van de catalogus (NL): slottekst + meta description per categorie (pages/katalog.php → siteContent('katalog_<cat>')).
// CS-standaard = $categoryOutros / $catDescriptions in pages/katalog.php. 'models' = zin met maximaal 3 actuele modellen
// ({models}), alleen aan body1 toegevoegd als de categorie motoren heeft; anders 'nomodels'.
return ['pages' => [
'katalog_cestovni' => [
    'outro' => [
        'title' => 'Toermotoren te huur — voor lange tochten en vakanties',
        'body1' => 'De toer- en adventuremotoren in onze vloot zijn gebouwd voor lange afstanden — een hogere zithouding, een comfortabel zadel voor bestuurder en passagier, een grote tank met een actieradius van 300–400 km en koffers voor de bagage.',
        'models' => 'Op dit moment vind je bij ons bijvoorbeeld {models} — allemaal regelmatig onderhouden en klaar voor een tocht door Tsjechië of naar het buitenland.',
        'nomodels' => 'Ze worden allemaal regelmatig onderhouden en zijn klaar voor een tocht door Tsjechië of naar het buitenland.',
        'body2' => 'We verhuren zonder borg, de groene kaart en internationale documenten krijg je automatisch mee en de complete uitrusting voor de bestuurder zit in de prijs. Uitrusting voor de passagier (helm, jas, bivakmuts) kun je tegen meerprijs bijbestellen.',
    ],
    'description' => 'Verhuur van toermotoren (touring, GT) in de regio Vysočina. Adventuremotoren voor lange routes en snelwegen. Zonder borg, online reserveren.',
],
'katalog_naked' => [
    'outro' => [
        'title' => 'Naked motoren — sportieve machines voor elke dag',
        'body1' => 'Naked motoren zonder kuip bieden <strong>een onmiskenbaar gevoel van vrijheid</strong> en een directe verbinding met de motor. Ze zijn ideaal voor vlot rijden in de stad, weekendtochtjes en plezier in de bochten.',
        'models' => 'In onze vloot vind je bijvoorbeeld {models} — allemaal in uitstekende technische staat en regelmatig onderhouden.',
        'nomodels' => 'Ze zijn allemaal in uitstekende technische staat en worden regelmatig onderhouden.',
        'body2' => 'We verhuren zonder borg en de uitrusting voor de bestuurder (helm, jas, broek, handschoenen) zit altijd in de prijs. Voor het ophalen bekijken we de motor samen en leggen we je de bijzonderheden uit. Heb je geen ervaring met een bepaalde vermogensklasse, dan helpen we je graag kiezen.',
    ],
    'description' => 'Verhuur van naked motoren in de regio Vysočina. Sportieve toermachines voor elke dag. Zonder borg, uitrusting inbegrepen, online reserveren.',
],
'katalog_supermoto' => [
    'outro' => [
        'title' => 'Supermoto motoren — lichte en wendbare machines voor fun in de stad',
        'body1' => 'Een supermoto combineert de voordelen van een enduro (licht gewicht, lange veerweg, hoge zithouding) met straatbanden en schijfremmen. Het resultaat is <strong>een zeer wendbare machine</strong> die zich thuis voelt in het stadsverkeer, op landweggetjes en tijdens korte tochten door de Vysočina.',
        'models' => 'In de catalogus vind je bijvoorbeeld {models}.',
        'body2' => 'Voor deze motoren heb je een rijbewijs A of A2 nodig en ze passen beter bij ervaren rijders die willen genieten van een speelse, lichte machine. We verhuren zonder borg, de uitrusting voor de bestuurder zit in de prijs. Bij het ophalen leggen we je uit hoe je rijdt met een hoge zithouding en waarom balans zo belangrijk is.',
    ],
    'description' => 'Verhuur van supermoto motoren in de regio Vysočina. Lichte stadsmachines met een hoge zithouding. Zonder borg, uitrusting inbegrepen, online reserveren.',
],
'katalog_chopper' => [
    'outro' => [
        'title' => 'Chopper- en cruisermotoren voor ontspannen rijden',
        'body1' => 'Choppers en cruisers zijn gebouwd voor <strong>comfortabel rijden over lange afstanden</strong> — een lage zithoogte, een relaxte houding, het karakteristieke geluid van een tweecilinder en een klassieke uitstraling. Ideaal voor een zondagsritje of een langere reis door Tsjechië.',
        'body2' => 'We breiden ons aanbod voortdurend uit — heb je een bepaald model in gedachten, neem dan contact met ons op. We verhuren zonder borg en de uitrusting voor de bestuurder zit in de prijs. Bij het ophalen krijg je de sleutels, de documenten en de complete uitrusting.',
    ],
    'description' => 'Verhuur van chopper- en cruisermotoren in de regio Vysočina. Comfortabele machines voor ontspannen rijden. Zonder borg, uitrusting inbegrepen, online reserveren.',
],
'katalog_detske' => [
    'outro' => [
        'title' => 'Kindermotoren — veilig plezier voor kleine rijders',
        'body1' => 'Kindermotoren kun je <strong>zonder rijbewijs</strong> huren en gebruiken in de tuin, op de camping of tijdens een rijcursus voor kinderen.',
        'models' => 'In de catalogus vind je bijvoorbeeld {models}.',
        'body2' => 'Voor elke rit raden we aan de basisveiligheidsregels met je kind door te nemen en het altijd een helm en beschermers te laten dragen. De datum, de vestiging en eventuele bezorging spreek je direct bij het reserveren af.',
    ],
    'description' => 'Verhuur van kindermotoren zonder rijbewijs. Veilig plezier in de tuin of op de camping. Bezorging in heel Tsjechië, online reserveren.',
],
'katalog_sportovni' => [
    'outro' => [
        'title' => 'Sportmotoren — adrenaline en vermogen voor ervaren rijders',
        'body1' => 'Sportmotoren (supersport) zijn bedoeld voor <strong>ervaren rijders</strong> die hoge prestaties, een scherpe geometrie en een sportieve zithouding zoeken. Ze passen bij het circuit, bochtige wegen en weekendtochten over mooie routes in Moravië en de Vysočina.',
        'body2' => 'We vragen een rijbewijs A en minimaal 2 jaar ervaring op een motor van meer dan 35 kW. We verhuren zonder borg, de complete uitrusting voor de bestuurder zit in de prijs. Voor het ophalen leggen we je de bijzonderheden van een sportmotor uit en geven we tips voor veilig rijden.',
    ],
    'description' => 'Verhuur van sportmotoren in de regio Vysočina. Supersport- en sporttoermachines. Zonder borg, uitrusting inbegrepen, online reserveren.',
],
'katalog_scootery' => [
    'outro' => [
        'title' => 'Scooters te huur — comfortabel door de stad met rijbewijs A1 of B',
        'body1' => 'Scooters zijn de ideale keuze voor <strong>comfortabel en eenvoudig rijden in de stad</strong> — automatische versnellingsbak, lage zithoogte en opbergruimte onder het zadel. Een deel van onze scooters mag je ook met een rijbewijs <strong>B</strong> (autorijbewijs) besturen, de rest met <strong>A1</strong>. De vereiste rijbewijscategorie vind je altijd bij de details van elke machine.',
        'body2' => 'We verhuren zonder borg en de uitrusting voor de bestuurder (helm, handschoenen) zit in de prijs. Een scooter is ideaal voor woon-werkverkeer, tochtjes in de omgeving of als eerste kennismaking met een tweewieler. Bij het ophalen leggen we je de bediening en de bijzonderheden van het rijden uit.',
    ],
    'description' => 'Verhuur van scooters in de regio Vysočina. Scooters voor rijbewijs A1 of B voor comfortabel rijden in de stad. Zonder borg, uitrusting inbegrepen, online reserveren.',
],
'katalog_ostatni' => [
    'outro' => [
        'title' => 'Motoraanhangers en andere uitrusting te huur',
        'body1' => 'In de categorie Overig vind je <strong>aanhangers voor het vervoer van motoren</strong> en andere aanvullende uitrusting te huur. Een motoraanhanger komt goed van pas als je je motor naar het circuit, op vakantie of naar de garage brengt. Om de aanhanger te trekken volstaat een gewoon rijbewijs <strong>B</strong> (afhankelijk van het gewicht van de combinatie).',
        'body2' => 'We verhuren zonder borg en adviseren je graag bij de keuze en bij het correct laden en vastzetten van de motor. De precieze specificaties (laadvermogen, afmetingen, vereiste rijbewijscategorie) vind je bij de details van elk artikel. De datum en plaats van ophalen spreek je direct bij het reserveren af.',
    ],
    'description' => 'Verhuur van motoraanhangers en andere uitrusting in de regio Vysočina. Aanhanger voor rijbewijs B. Zonder borg, online reserveren.',
],
]];
