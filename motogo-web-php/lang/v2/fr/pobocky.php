<?php
// FR překlad textů poboček (tykání „tu“; Velín → Texty webu → Pobočky, klíče web.pobocky.*).
// Přeloženo podle aktuálních CS hodnot (pobockyDefaults() v data/pobocky.php + CMS k 2026-10-10,
// u výbavy Velkých Němčic nové velikosti — helmy S–3XL, bundy/kalhoty/rukavice do 4XL).
// Struktura = lang/v2/es/pobocky.php (bez polí jen z kódu: slug, branch_id, map, photo, gallery, video).
// siteContent('pobocky') použije tento overlay, protože CMS klíče bez FR překladu se pro FR přeskakují.
// Texty v2 (karty, průvodce, srovnání): lang/v2/fr/pobocky-v2.php.

return ['pages' => ['pobocky' => [
    'seo' => [
        'title' => 'Agences | MotoGo24 – location de motos à Pelhřimov et Brno',
        'description' => 'Agences de location de motos MotoGo24 : agence avec personnel à Mezná, près de Pelhřimov (Vysočina), et agence en libre-service à Velké Němčice, près de Brno – retrait de la moto à toute heure.',
        'keywords' => 'agences MotoGo24, location moto Pelhřimov, location moto Brno, location moto libre-service, Velké Němčice, Mezná',
    ],
    'h1' => 'Agences MotoGo24',
    'intro' => 'Tu peux récupérer ta moto à <strong>deux endroits</strong> : à l\'<strong>agence avec personnel de Mezná, près de Pelhřimov</strong>, où nous t\'accueillons en personne, ou à l\'<strong>agence en libre-service de Velké Němčice, près de Brno</strong>, où tu récupères toi-même la moto et l\'équipement grâce à des codes.',
    'branches' => [
        [
            'badge' => 'Agence avec personnel',
            'title' => 'Mezná, près de Pelhřimov',
            'address' => 'Mezná 9, 393 01 Pelhřimov',
            'hours' => 'Du lundi au dimanche, à toute heure (non-stop), week-ends et jours fériés compris. Tu choisis l\'heure de retrait et de retour lors de la réservation.',
            'text' => 'Notre agence principale en Vysočina. Nous te <strong>remettons la moto en personne</strong> : on t\'explique tout, on t\'aide pour les réglages et le choix de l\'équipement, et on passe ensemble le procès-verbal de remise. L\'équipement pilote est inclus dans le prix. D\'ici, nous proposons aussi la <strong>livraison de la moto</strong> à l\'adresse de ton choix.',
            'gear' => 'Équipement pilote inclus dans le prix : vestes et pantalons jusqu\'à la taille <strong>6XL</strong>. Ici seulement, tu peux aussi louer une <strong>tenue de pluie</strong> et d\'autres équipements complémentaires.',
            'steps_title' => 'Comment ça se passe',
            'steps' => '1. Tu réserves et paies en ligne (site ou appli) et tu téléverses tes documents (carte d\'identité/passeport + permis de conduire) ; nous le demandons aussi à l\'agence avec personnel : si tu ne les téléverses pas, nous les vérifions sur place au moment du retrait.<br>2. À l\'heure choisie, tu arrives à l\'agence, où nous t\'attendons.<br>3. Nous te remettons la moto et l\'équipement, et nous signons le procès-verbal de remise.<br>4. Après ta sortie, tu rends la moto à l\'agence (ou nous venons la chercher à l\'adresse convenue).',
            'video_title' => 'Vidéo : comment ça se passe à l\'agence',
            'gallery_title' => 'Galerie photos de l\'agence',
            'seo_title' => 'Agence Mezná, près de Pelhřimov | MotoGo24 – location de motos avec personnel',
            'seo_description' => 'Agence avec personnel de MotoGo24 à Mezná, près de Pelhřimov (Vysočina) : remise de la moto en personne à toute heure, équipement inclus, livraison à ton adresse.',
        ],
        [
            'badge' => 'Agence en libre-service',
            'title' => 'Velké Němčice, près de Brno',
            'address' => 'Boudky, 691 63 Velké Němčice',
            'hours' => 'Ouverte 24/7 avec le code de l\'appli. Tu choisis l\'heure de retrait lors de la réservation : si tu récupères la moto à partir de 12 h (location de 2 jours ou plus), le 1er jour est à moitié prix et la borne te remet la moto à partir de 12 h. L\'heure de retour ne se choisit pas : tu rends la moto quand tu veux le dernier jour de location, jusqu\'à minuit.',
            'text' => 'Une <strong>agence en libre-service</strong> moderne au sud de Brno. Pas de personnel sur place : tu fais tout toi-même sur l\'écran tactile avec les <strong>codes de l\'appli</strong>, que tu reçois après le paiement et l\'ajout de tes documents. Les motos de cette agence se récupèrent et se rendent uniquement sur place : nous ne proposons ni livraison ni enlèvement à domicile. À côté de l\'agence, tu peux <strong>te garer gratuitement</strong> pendant toute la location.',
            'gear' => 'Seuls sont disponibles <strong>casque, veste avec protection dorsale, pantalon, gants, cagoule et bottes</strong> : l\'équipement pilote est inclus dans le prix ; les bottes moto, avec supplément. Casques en tailles <strong>S–3XL</strong> ; vestes, pantalons et gants jusqu\'à la taille <strong>4XL</strong> (les tailles plus grandes, jusqu\'au 6XL, sont à Mezná). À l\'agence en libre-service, nous ne louons ni <strong>tenue de pluie</strong> ni autre équipement complémentaire : ils ne sont disponibles qu\'à l\'agence avec personnel de Mezná. Tu essaies l\'équipement au vestiaire et, si la taille ne te va pas, tu en prends une autre disponible et tu l\'indiques simplement dans le procès-verbal de remise. Le gilet réfléchissant, la trousse de secours, le constat amiable, le bloque-disque et la clé du support de téléphone se trouvent sur la moto.',
            'steps_title' => 'Comment ça se passe',
            'steps' => '1. Tu réserves et paies en ligne, tu choisis l\'heure de retrait et tu téléverses tes documents (carte d\'identité/passeport + permis de conduire) : à l\'agence en libre-service, c\'est indispensable ; sans documents vérifiés, tu ne reçois pas les codes et tu ne peux pas entrer dans l\'agence. Une fois tes documents vérifiés, tu reçois dans l\'appli, par e-mail et par SMS les codes dans l\'ordre où tu vas les saisir : <strong>1) code de la boîte avec la clé du portail, 2) code du vestiaire</strong> (si tu loues de l\'équipement) <strong>et 3) code de la moto</strong>.<br>2. <strong>Si le portail d\'entrée est fermé</strong>, ouvre avec le code de l\'appli la <strong>boîte du haut sur le pilier droit du portail</strong> : elle contient la clé du cadenas. Déverrouille le portail, entre et gare-toi sur l\'une des places <strong>1–7, à droite le long de la clôture</strong> (voir la photo du parking). Ta voiture peut y rester gratuitement pendant toute la location. Si le portail est ouvert, tu n\'as pas besoin du code de la boîte.<br>3. Sur l\'écran, saisis le code du vestiaire : <strong>le vestiaire est la porte n° 8</strong>. Prends l\'équipement, change-toi et referme la porte du vestiaire (avec ton propre équipement, tu passes l\'étape du vestiaire). Si tu as la réduction pour un retrait à partir de 12 h, les codes ne sont valables qu\'à partir de 12 h.<br>4. Sur l\'écran, ajuste les tailles dans le procès-verbal de remise, signe-le et saisis le code de la moto : le box avec ta moto s\'ouvre. Referme le box et c\'est parti !<br>5. <strong>Si le portail était fermé, referme-le en partant, verrouille le cadenas, remets la clé dans la boîte du haut et brouille la combinaison.</strong> Si le portail est ouvert, laisse-le ouvert : ne change jamais l\'état du portail.<br>6. Après ta sortie, rends la moto dans son box et l\'équipement au vestiaire, quand tu veux le dernier jour de location, jusqu\'à minuit. Si le portail est fermé, même procédure : ouvre-le avec la clé de la boîte puis, en partant, referme-le au cadenas et remets la clé.',
            'video_title' => 'Vidéo : comment utiliser l\'agence en libre-service',
            'gallery_title' => 'Galerie photos de l\'agence',
            'seo_title' => 'Agence en libre-service Velké Němčice, près de Brno | MotoGo24',
            'seo_description' => 'Agence en libre-service de MotoGo24 à Velké Němčice, près de Brno : retrait et retour 24/7 avec le code de l\'appli, heure de retrait au choix dans la réservation (dès 12 h, le 1er jour est à moitié prix), parking gratuit.',
        ],
    ],
    'detail_button' => 'Voir l\'agence',
    'back_link' => '← Toutes les agences',
    'cta' => [
        'title' => 'Choisis ta moto dans ton agence',
        'text' => 'Dans la réservation, tu choisis l\'agence et seules les motos présentes sur place s\'affichent.',
        'button' => 'RÉSERVER EN LIGNE',
    ],
]]];
