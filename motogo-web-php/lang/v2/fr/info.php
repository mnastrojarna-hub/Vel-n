<?php
// Landing v2 — informační stránky (Jak si půjčit ×8, FAQ, Kontakt): texty nových
// prvků wrapperu landing-info.php (hero tlačítka a chipy, AI asistent, karty
// poboček na Kontaktu). Ruční FR texty, tykání (tu), kauce = „caution“.
// CS defaulty: lpiDefaults() v landing-info.php.
return ['pages' => ['landing_info' => [
    'cta_primary' => 'RÉSERVER',
    'cta_secondary' => 'VOIR LES MOTOS',
    'cta_call' => 'APPELER',
    'reserve' => 'Réserver une moto',
    'steps_title' => 'Étape par étape',
    'read_more' => 'Lire la suite',
    'read_less' => 'Afficher moins',
    'chips' => [
        'postup' => ['Sans caution', 'Équipement pilote inclus', 'Réservation en ligne en quelques minutes'],
        'prevzeti' => ['Retrait à ton heure', 'Parking gratuit', 'Sans caution'],
        'vraceni_pujcovna' => ['Dernier jour jusqu\'à minuit', 'Ni plein ni lavage', 'Sans caution'],
        'vraceni_jinde' => ['Partout en Tchéquie', 'Prix clair au km', 'Sans caution'],
        'cena' => ['0 € de caution', 'Équipement pilote inclus', 'Sans frais cachés'],
        'pristaveni' => ['Chez toi, à l\'hôtel ou à la gare', 'Partout en Tchéquie', 'Sans caution'],
        'dokumenty' => ['Sans caution', 'Contrat clair', 'Paiement en ligne sécurisé'],
        'faq' => ['Sans caution', 'Équipement pilote inclus', 'Assistant IA 24h/24'],
        'kontakt' => ['2 agences : Vysočina et Brno', 'Libre-service 24h/24 près de Brno', 'À environ 90 min de Prague'],
    ],
    'ai' => [
        'title' => 'Assistant IA 24h/24',
        'text' => 'Tu ne trouves pas ta réponse ? Demande à Tomáš : il répond tout de suite, de jour comme de nuit.',
        'card' => 'Demande à Tomáš : réponse immédiate',
        'btn' => 'Demander',
    ],
    'contact' => [
        'branches_title' => 'Nos agences',
        'detail' => 'Voir l\'agence',
        'route' => 'Itinéraire',
        'branches' => [
            [
                'badge' => 'Avec personnel',
                'title' => 'Mezná (Pelhřimov, Vysočina)',
                'text' => 'On te remet la moto en personne à l\'heure de ta réservation, tous les jours, week-ends et jours fériés compris.',
                'chips' => ['À environ 90 min de Prague', 'Livraison à ton adresse'],
            ],
            [
                'badge' => 'Libre-service 24h/24',
                'title' => 'Velké Němčice (près de Brno)',
                'text' => 'Tu récupères et rends la moto et l\'équipement toi-même, avec les codes de l\'appli : 100 % nonstop, sans attente.',
                'chips' => ['À 30 min de Brno', 'À 35 min de l\'aéroport de Brno'],
            ],
        ],
    ],
]]];
