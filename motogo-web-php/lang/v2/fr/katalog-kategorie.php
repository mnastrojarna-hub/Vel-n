<?php
// Pages de catégories du catalogue (FR) : texte de fin + meta description par catégorie (pages/katalog.php → siteContent('katalog_<cat>')).
// Par défaut CS = $categoryOutros / $catDescriptions dans pages/katalog.php. 'models' = phrase avec jusqu’à 3 modèles actuels
// ({models}), ajoutée à body1 seulement si la catégorie a des motos ; sinon 'nomodels'.
return ['pages' => [
'katalog_cestovni' => [
    'outro' => [
        'title' => 'Motos de tourisme à louer — pour les longs voyages et les vacances',
        'body1' => 'Les motos de tourisme et trail de notre flotte sont conçues pour les longues distances — position de conduite plus haute, selle confortable pour le pilote et le passager, grand réservoir offrant 300 à 400 km d’autonomie et valises pour les bagages.',
        'models' => 'Vous trouverez actuellement chez nous, par exemple, {models} — toutes entretenues régulièrement et prêtes pour un voyage en Tchéquie ou à l’étranger.',
        'nomodels' => 'Toutes sont entretenues régulièrement et prêtes pour un voyage en Tchéquie ou à l’étranger.',
        'body2' => 'Nous louons sans caution, la carte verte et les documents internationaux sont fournis automatiquement et l’équipement complet du pilote est compris dans le prix. Pour le passager, vous pouvez ajouter un équipement (casque, blouson, cagoule) moyennant supplément.',
    ],
    'description' => 'Location de motos de tourisme (touring, GT) dans la région de Vysočina. Motos trail pour les longs trajets et l’autoroute. Sans caution, réservation en ligne.',
],
'katalog_naked' => [
    'outro' => [
        'title' => 'Motos naked — des machines sportives pour rouler au quotidien',
        'body1' => 'Les roadsters sans carénage offrent <strong>une sensation de liberté inimitable</strong> et un lien direct avec le moteur. Ils sont parfaits pour rouler vivement en ville, partir en week-end et s’amuser dans les virages.',
        'models' => 'Dans notre flotte, vous trouverez par exemple {models} — toutes en excellent état technique et entretenues régulièrement.',
        'nomodels' => 'Toutes sont en excellent état technique et entretenues régulièrement.',
        'body2' => 'Nous louons sans caution et l’équipement du pilote (casque, blouson, pantalon, gants) est toujours compris dans le prix. Avant le retrait, nous inspectons la moto ensemble et vous expliquons ses particularités. Si vous n’avez pas l’habitude d’une catégorie de puissance donnée, nous vous aidons volontiers à choisir.',
    ],
    'description' => 'Location de motos naked dans la région de Vysočina. Machines sportives et polyvalentes pour rouler au quotidien. Sans caution, équipement compris, réservation en ligne.',
],
'katalog_supermoto' => [
    'outro' => [
        'title' => 'Motos supermoto — légères et agiles pour s’amuser en ville',
        'body1' => 'Le supermoto combine les atouts d’une enduro (légèreté, suspensions à grand débattement, position haute) avec des pneus route et des freins à disque. Résultat : <strong>une machine très agile</strong>, à l’aise en ville, sur les chemins de campagne et pour de courtes balades dans la région de Vysočina.',
        'models' => 'Dans le catalogue, vous trouverez par exemple {models}.',
        'body2' => 'Ces motos exigent un permis A ou A2 et conviennent plutôt aux pilotes expérimentés qui veulent profiter d’une machine joueuse et légère. Nous louons sans caution, l’équipement du pilote est compris. Au retrait, nous vous expliquons les particularités de la conduite avec une position haute et l’importance de l’équilibre.',
    ],
    'description' => 'Location de motos supermoto dans la région de Vysočina. Machines urbaines légères à position haute. Sans caution, équipement compris, réservation en ligne.',
],
'katalog_chopper' => [
    'outro' => [
        'title' => 'Motos chopper et cruiser pour rouler en toute détente',
        'body1' => 'Les choppers et cruisers sont faits pour <strong>rouler confortablement sur de longues distances</strong> — selle basse, position décontractée, sonorité caractéristique du bicylindre et esthétique classique. Idéal pour une balade du dimanche comme pour un plus long voyage en Tchéquie.',
        'body2' => 'Nous enrichissons notre offre en continu — si vous avez un modèle précis en tête, contactez-nous. Nous louons sans caution, l’équipement du pilote est compris. Au retrait, nous vous remettons les clés, les documents et l’équipement complet.',
    ],
    'description' => 'Location de motos chopper et cruiser dans la région de Vysočina. Machines confortables pour rouler en toute détente. Sans caution, équipement compris, réservation en ligne.',
],
'katalog_detske' => [
    'outro' => [
        'title' => 'Motos pour enfants — un plaisir sûr pour les jeunes pilotes',
        'body1' => 'Les motos pour enfants se louent <strong>sans permis de conduire</strong> et s’utilisent dans le jardin, au camping ou dans le cadre d’un cours de pilotage pour enfants.',
        'models' => 'Dans le catalogue, vous trouverez par exemple {models}.',
        'body2' => 'Avant chaque sortie, nous recommandons de revoir avec l’enfant les règles de sécurité de base et de toujours l’équiper d’un casque et de protections. La date, l’agence et une éventuelle livraison se règlent directement lors de la réservation.',
    ],
    'description' => 'Location de motos pour enfants sans permis. Un plaisir sûr au jardin ou au camping. Livraison partout en Tchéquie, réservation en ligne.',
],
'katalog_sportovni' => [
    'outro' => [
        'title' => 'Motos sportives — adrénaline et performances pour pilotes expérimentés',
        'body1' => 'Les motos sportives (supersport) s’adressent aux <strong>pilotes expérimentés</strong> en quête de hautes performances, d’une géométrie affûtée et d’une position sportive. Elles conviennent au circuit, aux routes sinueuses et aux sorties du week-end sur les belles routes de Moravie et de la région de Vysočina.',
        'body2' => 'Nous exigeons un permis A et au moins 2 ans d’expérience sur une moto de plus de 35 kW. Nous louons sans caution, l’équipement complet du pilote est compris. Avant le retrait, nous vous expliquons les particularités d’une moto sportive et vous recommandons des pratiques de conduite sûres.',
    ],
    'description' => 'Location de motos sportives dans la région de Vysočina. Machines supersport et sport-GT. Sans caution, équipement compris, réservation en ligne.',
],
'katalog_scootery' => [
    'outro' => [
        'title' => 'Scooters à louer — rouler en ville confortablement avec un permis A1 ou B',
        'body1' => 'Les scooters sont le choix idéal pour <strong>circuler en ville confortablement et sans effort</strong> — boîte automatique, selle basse et rangement sous la selle. Une partie de nos scooters peut se conduire avec le permis <strong>B</strong> (permis voiture), les autres avec le permis <strong>A1</strong>. La catégorie de permis exacte figure toujours dans la fiche de chaque machine.',
        'body2' => 'Nous louons sans caution et l’équipement du pilote (casque, gants) est compris. Le scooter est parfait pour les trajets quotidiens, les balades dans les environs ou comme première découverte du deux-roues. Au retrait, nous vous expliquons les commandes et les particularités de la conduite.',
    ],
    'description' => 'Location de scooters dans la région de Vysočina. Scooters pour permis A1 ou B pour rouler confortablement en ville. Sans caution, équipement compris, réservation en ligne.',
],
'katalog_ostatni' => [
    'outro' => [
        'title' => 'Remorques pour motos et autres équipements à louer',
        'body1' => 'Dans la catégorie Autres, vous trouverez des <strong>remorques pour transporter des motos</strong> et d’autres équipements complémentaires à louer. Une remorque est bien pratique pour emmener votre moto sur circuit, en vacances ou à l’atelier. Pour la tracter, un permis de conduire ordinaire de <strong>catégorie B</strong> suffit (selon le poids de l’ensemble).',
        'body2' => 'Nous louons sans caution et vous conseillons volontiers sur le choix ainsi que sur le chargement et l’arrimage corrects de la moto. Les caractéristiques précises (charge utile, dimensions, catégorie de permis requise) figurent dans la fiche de chaque article. La date et le lieu de retrait se règlent directement lors de la réservation.',
    ],
    'description' => 'Location de remorques pour motos et d’autres équipements dans la région de Vysočina. Remorque pour permis B. Sans caution, réservation en ligne.',
],
]];
