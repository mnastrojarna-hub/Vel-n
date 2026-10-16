<?php
// Catalogue category pages (EN): outro text + meta description per category (pages/katalog.php → siteContent('katalog_<cat>')).
// CS defaults = $categoryOutros / $catDescriptions in pages/katalog.php. 'models' = sentence with up to 3 current fleet models
// ({models}), appended to body1 only when the category has bikes; 'nomodels' = the sentence used otherwise.
return ['pages' => [
'katalog_cestovni' => [
    'outro' => [
        'title' => 'Touring motorcycles for rent — for long trips and holidays',
        'body1' => 'The touring and adventure motorcycles in our fleet are built for long distances — a higher riding position, a comfortable seat for rider and passenger, a large tank with a range of 300–400 km and cases for luggage.',
        'models' => 'Right now you will find, for example, {models} — all regularly serviced and ready for a trip around the Czech Republic or abroad.',
        'nomodels' => 'All of them are regularly serviced and ready for a trip around the Czech Republic or abroad.',
        'body2' => 'We rent without a deposit, the green card and international documents come automatically, and complete rider gear is included in the price. Passenger gear (helmet, jacket, balaclava) can be added for an extra fee.',
    ],
    'description' => 'Touring motorcycle rental (touring, GT) in the Vysočina region. Adventure bikes for long routes and motorways. No deposit, online booking.',
],
'katalog_naked' => [
    'outro' => [
        'title' => 'Naked motorcycles — sporty machines for everyday riding',
        'body1' => 'Naked bikes without fairings offer <strong>an unmistakable sense of freedom</strong> and a direct connection with the engine. They are great for brisk city riding, weekend trips and fun in the bends.',
        'models' => 'In our fleet you will find, for example, {models} — all in excellent technical condition and regularly serviced.',
        'nomodels' => 'All of them are in excellent technical condition and regularly serviced.',
        'body2' => 'We rent without a deposit and rider gear (helmet, jacket, trousers, gloves) is always included in the price. Before pick-up we go over the bike together and explain its specifics. If you have no experience with a particular power class, we will gladly help you choose.',
    ],
    'description' => 'Naked motorcycle rental in the Vysočina region. Sport-touring machines for everyday riding. No deposit, gear included, online booking.',
],
'katalog_supermoto' => [
    'outro' => [
        'title' => 'Supermoto motorcycles — light and agile machines for city fun',
        'body1' => 'Supermoto combines the strengths of an enduro bike (low weight, long suspension travel, high seat) with road tyres and disc brakes. The result is <strong>a very agile machine</strong> that handles city traffic, field tracks and short tours around Vysočina.',
        'models' => 'In the catalogue you will find, for example, {models}.',
        'body2' => 'These bikes require an A or A2 licence and suit more experienced riders who want to enjoy a playful, light machine. We rent without a deposit and rider gear is included. At pick-up we explain the specifics of riding with a higher seat and the importance of balance.',
    ],
    'description' => 'Supermoto motorcycle rental in the Vysočina region. Light urban machines with a high seat. No deposit, gear included, online booking.',
],
'katalog_chopper' => [
    'outro' => [
        'title' => 'Chopper and cruiser motorcycles for relaxed riding',
        'body1' => 'Chopper and cruiser motorcycles are built for <strong>comfortable riding over long distances</strong> — a low seat, a laid-back riding posture, the distinctive sound of a twin-cylinder engine and classic looks. They are ideal for a Sunday ride or a longer trip around the Czech Republic.',
        'body2' => 'We keep expanding our fleet — if you have a particular model in mind, get in touch. We rent without a deposit and rider gear is included. At pick-up we hand over the keys, the documents and the complete gear.',
    ],
    'description' => 'Chopper and cruiser motorcycle rental in the Vysočina region. Comfortable machines for relaxed riding. No deposit, gear included, online booking.',
],
'katalog_detske' => [
    'outro' => [
        'title' => 'Kids\' motorcycles — safe fun for young riders',
        'body1' => 'Kids\' motorcycles can be rented <strong>without a driving licence</strong> and used in the garden, at a campsite or as part of a riding course for children.',
        'models' => 'In the catalogue you will find, for example, {models}.',
        'body2' => 'Before every ride we recommend going through the basic safety rules with your child and always equipping them with a helmet and protectors. You arrange the date, the branch and any delivery directly when booking.',
    ],
    'description' => 'Rental of kids\' motorcycles, no licence needed. Safe fun in the garden or at a campsite. Delivery across the Czech Republic, online booking.',
],
'katalog_sportovni' => [
    'outro' => [
        'title' => 'Sport motorcycles — adrenaline and performance for experienced riders',
        'body1' => 'Sport (supersport) motorcycles are designed for <strong>experienced riders</strong> looking for high performance, sharp geometry and a sporty riding position. They suit the track, twisty roads and weekend trips along beautiful Moravian and Vysočina routes.',
        'body2' => 'We require an A licence and at least 2 years of experience on a motorcycle over 35 kW. We rent without a deposit and complete rider gear is included. Before pick-up we explain the specifics of riding a sport bike and recommend safe riding practices.',
    ],
    'description' => 'Sport motorcycle rental in the Vysočina region. Supersport and sport-touring machines. No deposit, gear included, online booking.',
],
'katalog_scootery' => [
    'outro' => [
        'title' => 'Scooters for rent — comfortable city riding on an A1 or B licence',
        'body1' => 'Scooters are the ideal choice for <strong>comfortable, easy riding around town</strong> — automatic transmission, a low seat and storage under the seat. Some of our scooters can be ridden on a <strong>category B</strong> licence (car licence), the rest on <strong>A1</strong>. You will always find the required licence category in the detail of each machine.',
        'body2' => 'We rent without a deposit and rider gear (helmet, gloves) is included. A scooter is great for commuting, trips around the area or as a first introduction to two-wheelers. At pick-up we explain the controls and the specifics of riding.',
    ],
    'description' => 'Scooter rental in the Vysočina region. Scooters for an A1 or B licence for comfortable city riding. No deposit, gear included, online booking.',
],
'katalog_ostatni' => [
    'outro' => [
        'title' => 'Motorcycle trailers and other equipment for rent',
        'body1' => 'In the Other category you will find <strong>trailers for transporting motorcycles</strong> and other additional equipment to rent. A motorcycle trailer comes in handy when taking a bike to the track, on holiday or to a workshop. A standard <strong>category B</strong> licence is enough to tow the trailer (depending on the combined weight).',
        'body2' => 'We rent without a deposit and will gladly help you choose and load and secure the motorcycle correctly. You will find the specific parameters (payload, dimensions, required licence category) in the detail of each item. You arrange the date and place of pick-up directly when booking.',
    ],
    'description' => 'Rental of motorcycle trailers and other equipment in the Vysočina region. Trailer for a B licence. No deposit, online booking.',
],
]];
