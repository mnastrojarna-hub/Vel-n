<?php
// MotoGo24 — pages_fr.php (Francais overlay nad CS defaults)

$c = require __DIR__ . '/pages_fr_c.php';

return [
    'pages' => array_merge($c['pages'], [

        'jak_pujcit_cena' => [
            'seo' => [
                'title' => 'Location de motos Vysočina – Comment louer – Ce qui est inclus',
                'description' => 'Découvre ce qui est inclus dans le prix de location chez MotoGo24. Conditions claires, équipement et services sans frais cachés. Réserve ta moto en ligne facilement.',
                'keywords' => 'location de motos Vysočina, location motos Pelhřimov, location sans caution, location 24h/24, réservation en ligne moto',
            ],
            'h1' => 'Ce qui est inclus dans le prix de location',
            'intro' => 'Chez <strong>MotoGo24 – location de motos en Vysočina</strong>, tu obtiens des conditions justes. <strong>Sans caution, avec équipement du conducteur inclus et service 24h/24</strong>. Tout ce dont tu as besoin pour rouler en sécurité est inclus.',
            'cta' => [
                'title' => 'Équipement inclus – location de motos MotoGo24 – Vysočina',
                'text' => '<strong>MotoGo24 est une location de motos moderne en Vysočina</strong> avec équipement du conducteur inclus, location sans caution et service 24h/24. Choisis une <strong>moto de tourisme, supermoto, naked ou pour enfants</strong> et réserve en ligne.',
                'buttons' => [
                    ['label' => 'RÉSERVER EN LIGNE', 'href' => '/rezervace', 'cls' => 'btndark pulse', 'aria' => 'Réserver une moto avec équipement inclus chez Motogo24'],
                ],
            ],
        ],

        'jak_pujcit_dokumenty' => [
            'seo' => [
                'title' => 'Location de motos Vysočina – Documents et manuels',
                'description' => 'Contrat de location, conditions et documents nécessaires pour louer une moto. Sans caution, règles claires, assurance incluse.',
                'keywords' => 'contrat location moto, documents location, conditions location, assurance moto, MotoGo24',
            ],
            'h1' => 'Contrat de location et caution – conditions justes sans avance',
            'intro' => 'Chez <strong>MotoGo24</strong>, nous misons sur la simplicité et l\'équité. Nous louons <strong>sans caution</strong>, avec un <strong>contrat clair</strong>, <strong>assurance incluse</strong> et <strong>équipement du conducteur</strong>.',
            'top_cta' => ['label' => 'RÉSERVER EN LIGNE', 'href' => '/rezervace', 'aria' => 'Réserver une moto en ligne chez Motogo24'],
            'cta' => [
                'title' => 'Contrat sans caution – location de motos Vysočina',
                'text' => 'MotoGo24 est une <strong>location de motos en Vysočina</strong> avec des conditions justes.',
                'buttons' => [['label' => 'RÉSERVER EN LIGNE', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_pristaveni' => [
            'seo' => [
                'title' => 'Livraison de la moto | MotoGo24',
                'description' => 'Livraison de la moto à ta porte. Nous apportons la moto à ton hôtel, gare ou n\'importe quelle adresse. Tarif à partir de 290 Kč. Service 24h/24.',
                'keywords' => 'livraison moto, apport moto, livraison motocycle, location motos Vysočina',
            ],
            'h1' => 'Livraison de la moto – directement à toi',
            'intro' => 'Tu veux partir sans devoir te déplacer à la location ? Nous organisons <strong>la livraison de la moto</strong> au <strong>lieu convenu</strong>.',
            'top_cta' => ['label' => 'RÉSERVER AVEC LIVRAISON', 'href' => '/rezervace?delivery=1'],
            'cta' => [
                'title' => 'Livraison de la moto – location de motos Vysočina',
                'text' => 'MotoGo24 propose la <strong>livraison de la moto</strong> dans la région et au-delà. <strong>Service 24h/24, sans caution, équipement inclus</strong>.',
                'buttons' => [['label' => 'RÉSERVER AVEC LIVRAISON', 'href' => '/rezervace?delivery=1', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_vraceni_jinde' => [
            'seo' => [
                'title' => 'Restitution de moto ailleurs | MotoGo24',
                'description' => 'Rends la moto en dehors de la location – depuis l\'hôtel, gare ou autre adresse. Récupération en Vysočina et au-delà. Prix selon distance, service 24h/24.',
                'keywords' => 'restitution moto ailleurs, récupération moto, restitution hors location, location motos Vysočina',
            ],
            'h1' => 'Restitution de moto ailleurs – récupération à toi',
            'intro' => 'Pas besoin de revenir à la location. <strong>MotoGo24</strong> propose la <strong>récupération de la moto</strong> depuis le lieu qui te convient – hôtel, gare, ton adresse.',
            'top_cta' => ['label' => 'RÉSERVER AVEC RÉCUPÉRATION', 'href' => '/rezervace?return_delivery=1'],
            'cta' => [
                'title' => 'Restitution de moto n\'importe où – MotoGo24',
                'text' => 'MotoGo24 organise la <strong>récupération de la moto</strong> depuis le lieu qui te convient. <strong>24h/24, sans caution, sans souci.</strong>',
                'buttons' => [['label' => 'RÉSERVER AVEC RÉCUPÉRATION', 'href' => '/rezervace?return_delivery=1', 'cls' => 'btndark pulse']],
            ],
        ],

        'faq' => [
            'seo' => [
                'title' => 'Foire aux questions | MotoGo24',
                'description' => 'Questions fréquentes sur la location de motos. Réservation, prise en charge, restitution, conditions, livraison, voyages à l\'étranger, bons cadeaux.',
                'keywords' => 'FAQ location motos, questions location moto, conditions location, caution, équipement',
            ],
            'h1' => 'Foire aux questions – location de motos MotoGo24',
            'closing' => 'Notre <strong>location de motos en Vysočina</strong> est là pour tous ceux qui veulent vivre une <strong>balade inoubliable</strong> sans complications.',
            'cta' => ['label' => 'Réserver une moto en ligne', 'href' => '/rezervace'],
        ],

        'home' => [
            'seo' => [
                'title' => 'Location de motos en Vysočina | MotoGo24',
                'description' => 'Loue une moto en Vysočina. Sans caution, équipement inclus, service 24h/24. Motos de tourisme, sport, enduro et pour enfants. Réservation en ligne.',
                'keywords' => 'location motos Vysočina, location motos Pelhřimov, location sans caution, location 24h/24, motos à louer, réservation en ligne moto',
                'og_image' => null,
            ],
            'hero' => [
                'image' => 'gfx/hero-banner.jpg',
                'alt' => 'Location de motos Vysočina',
                'eyebrow' => '<strong>Location de motos</strong> en Vysočina',
                'body' => 'Loue une moto en Vysočina facilement en ligne.<br>Choisis parmi des modèles tourisme, sport et enduro.<br>Réservation avec paiement par carte et prise en charge rapide.',
                'cta_primary' => ['label' => 'CHOISIS TA MOTO', 'href' => '/katalog', 'cls' => 'btngreen'],
                'cta_secondary' => ['label' => 'COMMENT ÇA MARCHE', 'href' => '/jak-pujcit', 'cls' => 'btndark'],
            ],
            'h1' => 'Location de motos Vysočina Motogo24 – sans caution et 24h/24',
            'intro' => 'Bienvenue chez <strong>Motogo24</strong> – ta location de motos en Vysočina. Ici tu loues une moto <strong>sans caution</strong>, avec équipement inclus et en mode <strong>24h/24</strong>. Que tu cherches une moto de tourisme, sport, enduro ou pour enfants, Motogo24 au cœur de Vysočina te propose la moto idéale.',
            'signposts_title' => 'Guide rapide chez Motogo24',
            'signposts' => [
                ['icon' => 'gfx/ico-katalog.svg', 'title' => 'Catalogue de motos', 'text' => 'Découvre notre offre de motos à louer — du sport au tourisme.', 'btn' => 'CATALOGUE DE MOTOS', 'href' => '/katalog'],
                ['icon' => 'gfx/ico-jak.svg', 'title' => 'Comment louer une moto', 'text' => 'Processus simple : choisis une moto, réserve et pars en route.', 'btn' => 'COMMENT LOUER', 'href' => '/jak-pujcit'],
                ['icon' => 'gfx/ico-rezervace.svg', 'title' => 'Réservation en ligne', 'text' => 'Réserve ta moto via notre système en ligne facile.', 'btn' => 'RÉSERVER UNE MOTO', 'href' => '/rezervace'],
                ['icon' => 'gfx/ico-kontakt.svg', 'title' => 'Contact et carte', 'text' => 'Visite notre location de motos à Pelhřimov ou contacte-nous.', 'btn' => 'CONTACT', 'href' => '/kontakt'],
                ['icon' => 'gfx/ico-faq.svg', 'title' => 'Foire aux questions', 'text' => 'Les questions les plus fréquentes sur la location de motos en un seul endroit.', 'btn' => 'FAQ', 'href' => '/jak-pujcit/faq'],
                ['icon' => 'gfx/ico-trasy.svg', 'title' => 'Itinéraires moto', 'text' => 'Découvre les meilleurs itinéraires moto en République tchèque pour touristes et locaux.', 'btn' => 'ITINÉRAIRES MOTO', 'href' => '/blog'],
            ],
            'motos_section' => [
                'title' => 'Nos motos à louer en Vysočina',
                'intro' => 'Découvre notre offre de motos tourisme, sport et enduro de notre location en Vysočina.',
                'empty' => 'Actuellement aucune moto disponible.',
                'cta_label' => 'CATALOGUE DE MOTOS',
                'cta_href' => '/katalog',
                'limit' => 4,
            ],
            'process' => [
                'title' => 'Comment fonctionne la location en Vysočina',
                'steps' => [
                    ['icon' => 'gfx/ico-step1.svg', 'title' => '1. Choisis', 'text' => 'Choisis ta moto idéale dans notre offre de motos à louer.'],
                    ['icon' => 'gfx/ico-step2.svg', 'title' => '2. Réserve', 'text' => 'Réserve ta moto via notre système en ligne simple.'],
                    ['icon' => 'gfx/ico-step3.svg', 'title' => '3. Récupère', 'text' => 'Récupère la moto à notre location à Pelhřimov.'],
                    ['icon' => 'gfx/ico-step4.svg', 'title' => '4. Profite du voyage', 'text' => 'Vis la liberté et découvre la République tchèque sur des motos de location.'],
                ],
            ],
            'faq' => [
                'title' => 'Foire aux questions',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    ['q' => 'Comment puis-je réserver une moto ?', 'a' => 'Tu peux réserver une moto via notre système de réservation en ligne directement ici sur le site. Ou contacte-nous par e-mail, téléphone ou réseaux sociaux.'],
                    ['q' => 'Puis-je louer une moto sans réservation préalable ?', 'a' => 'Hélas non. Chaque moto doit être réservée à l\'avance — en ligne, par téléphone, e-mail ou réseaux sociaux.'],
                    ['q' => 'Dois-je verser une caution ?', 'a' => 'Non ! Chez nous tu <strong>ne paies aucune caution</strong>. Notre location se distingue ainsi fondamentalement de la plupart de la concurrence.'],
                    ['q' => 'Puis-je voyager à l\'étranger avec la moto ?', 'a' => 'Oui, tu peux voyager à l\'étranger sans problème. Nous ne limitons pas les voyages hors de la République tchèque ; tu dois juste respecter la validité territoriale de l\'assurance (carte verte).'],
                ],
            ],
            'cta' => [
                'title' => 'Réserve ta moto en ligne',
                'text' => 'Notre <strong>location de motos Vysočina</strong> est ouverte <strong>24h/24</strong>. Quelques clics et ta balade commence.',
                'buttons' => [
                    ['label' => 'RÉSERVER UNE MOTO', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Bon cadeau', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Conseils d\'itinéraire', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
            'blog' => [
                'title' => 'Blog et conseils',
                'empty' => 'Aucun article pour le moment.',
                'cta_label' => 'LIRE PLUS SUR LE BLOG',
                'cta_href' => '/blog',
                'limit' => 3,
            ],
            'reviews' => [
                'title' => 'Ce que disent nos clients',
                'intro' => 'Avis réels de motards qui ont loué chez nous. Merci pour chaque évaluation.',
            ],
        ],

        'pujcovna' => [
            'seo' => [
                'title' => 'À propos de la location de motos | MotoGo24',
                'description' => 'Location de motos Motogo24 en Vysočina. Sans caution, avec réservation en ligne et équipement inclus. Motos de tourisme, sport, enduro et pour enfants. Service 24h/24.',
                'keywords' => 'location motos, location motos Vysočina, motos sans caution, location 24h/24, équipement inclus',
            ],
            'breadcrumb' => [['label' => 'Accueil', 'href' => '/'], 'Location de motos'],
            'intro' => [
                'h1' => 'Location de motos Vysočina Motogo24',
                'body' => 'Notre <strong>location de motos en Vysočina</strong> à Pelhřimov propose la <strong>location de motos</strong> sans obstacles – <strong>sans caution</strong>, avec <strong>réservation en ligne</strong> et <strong>équipement inclus</strong>. Choisis parmi des <strong>motos de tourisme</strong>, <strong>sport</strong>, <strong>enduro</strong> et <strong>pour enfants</strong>, et pars quand tu veux : nous sommes ouverts <strong>24h/24</strong>.',
            ],
            'benefits' => [
                'title' => 'Pourquoi louer chez nous',
                'closing' => 'Tu cherches une <strong>location de motos en Vysočina</strong> ? Motogo24 propose des conditions justes, un processus clair et des machines parfaitement entretenues pour des voyages en République tchèque et à l\'étranger.',
                'buttons' => [
                    ['label' => 'Voir les motos à louer', 'href' => '/katalog', 'cls' => 'btngreen'],
                    ['label' => 'RÉSERVER', 'href' => '/rezervace', 'cls' => 'btngreen pulse'],
                ],
                'items' => [
                    ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'Sans caution', 'text' => 'et sans frais cachés'],
                    ['icon' => 'gfx/ico-online-rez.svg', 'title' => 'Réservation en ligne', 'text' => 'en quelques clics'],
                    ['icon' => 'gfx/ico-vybava.svg', 'title' => 'Équipement pilote inclus', 'text' => 'casque, blouson, pantalon et gants'],
                    ['icon' => 'gfx/ico-nonstop.svg', 'title' => 'Service 24h/24', 'text' => 'pour la prise en charge et le retour selon ta réservation'],
                    ['icon' => 'gfx/ico-spolecne.svg', 'title' => 'Nous sommes avec toi', 'text' => 'si quelque chose se passe'],
                    ['icon' => 'gfx/ico-pristaveni.svg', 'title' => 'Livraison et reprise', 'text' => 'à un endroit convenu'],
                ],
            ],
            'process' => [
                'title' => 'Comment fonctionne la location en Vysočina',
                'steps' => [
                    ['icon' => 'gfx/ico-step1.svg', 'title' => '1. Choisis une moto', 'text' => 'Découvre notre offre et choisis le type qui te convient, à ton expérience et à ton permis.'],
                    ['icon' => 'gfx/ico-step3.svg', 'title' => '2. Réserve en ligne', 'text' => 'Réserve par date ou par moto précise que tu veux louer.'],
                    ['icon' => 'gfx/ico-step4.svg', 'title' => '3. Choisis l\'équipement', 'text' => 'L\'équipement pilote est inclus, celui du passager est en supplément. La taille se choisit sur place.'],
                    ['icon' => 'gfx/ico-step5.svg', 'title' => '4. Paie', 'text' => 'Paie facilement en ligne via la passerelle de paiement.'],
                    ['icon' => 'gfx/ico-step6.svg', 'title' => '5. Récupère la moto', 'text' => 'Récupère la moto directement à la location, ou à l\'endroit choisi lors de la réservation.'],
                    ['icon' => 'gfx/ico-step7.svg', 'title' => '6. Profite du voyage', 'text' => 'Prends la route, découvre de nouvelles expériences et profite pleinement de la liberté à deux roues.'],
                    ['icon' => 'gfx/ico-step8.svg', 'title' => '7. Rends la moto', 'text' => 'Rends simplement la moto le jour convenu – à la location ou à un endroit convenu.'],
                    ['icon' => 'gfx/ico-sleva.svg', 'title' => 'Réduction pour la prochaine balade', 'text' => 'Après le retour de la moto nous t\'envoyons automatiquement un code de réduction de 200 Kč pour ta prochaine réservation.'],
                ],
            ],
            'faq' => [
                'title' => 'Foire aux questions',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    ['q' => 'Comment puis-je réserver une moto ?', 'a' => 'Tu peux réserver une moto via notre système de réservation en ligne directement ici sur le site. Ou contacte-nous par e-mail, téléphone ou réseaux sociaux.'],
                    ['q' => 'Puis-je louer une moto sans réservation préalable ?', 'a' => 'Hélas non. Chaque moto doit être réservée à l\'avance.'],
                    ['q' => 'Dois-je verser une caution ?', 'a' => 'Non ! Chez nous tu <strong>ne paies aucune caution</strong>. Notre location se distingue ainsi fondamentalement de la plupart de la concurrence.'],
                    ['q' => 'Puis-je voyager à l\'étranger avec la moto ?', 'a' => 'Oui, tu peux voyager à l\'étranger sans problème. Nous ne limitons pas les voyages hors de la République tchèque ; il suffit de respecter la validité territoriale de l\'assurance (carte verte).'],
                ],
            ],
            'cta' => [
                'title' => 'Réserve ta moto en ligne',
                'text' => 'Notre <strong>location de motos Vysočina</strong> est ouverte <strong>24h/24</strong>.',
                'buttons' => [
                    ['label' => 'RÉSERVER UNE MOTO', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Bon cadeau', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Conseils d\'itinéraire', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
        ],
    ]),
];
