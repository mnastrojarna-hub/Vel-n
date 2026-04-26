<?php
// MotoGo24 — pages_es.php (Espanol overlay nad CS defaults)

$c = require __DIR__ . '/pages_es_c.php';

return [
    'pages' => array_merge($c['pages'], [

        'jak_pujcit_cena' => [
            'seo' => [
                'title' => 'Alquiler de motos Vysočina – Cómo alquilar – Qué incluye el precio',
                'description' => 'Descubre qué incluye el precio del alquiler de motos en MotoGo24. Condiciones claras, equipo y servicios sin tarifas ocultas. Reserva tu moto fácilmente online.',
                'keywords' => 'alquiler de motos Vysočina, alquiler motos Pelhřimov, alquiler sin depósito, alquiler 24/7, reserva online moto',
            ],
            'h1' => 'Qué incluye el precio del alquiler de motos',
            'intro' => 'En <strong>MotoGo24 – alquiler de motos en Vysočina</strong> obtienes condiciones justas. <strong>Sin depósito, con equipo del conductor incluido y servicio 24/7</strong>. Todo lo que necesitas para una conducción segura y agradable está incluido.',
            'cta' => [
                'title' => 'Equipo incluido – alquiler de motos MotoGo24 – Vysočina',
                'text' => '<strong>MotoGo24 es un alquiler de motos moderno en Vysočina</strong> con equipo del conductor incluido, alquiler sin depósito y servicio 24/7. Elige una <strong>moto de turismo, supermoto, naked o infantil</strong> y reserva online.',
                'buttons' => [
                    ['label' => 'RESERVAR EN LÍNEA', 'href' => '/rezervace', 'cls' => 'btndark pulse', 'aria' => 'Reservar moto con equipo incluido en Motogo24'],
                ],
            ],
        ],

        'jak_pujcit_dokumenty' => [
            'seo' => [
                'title' => 'Alquiler de motos Vysočina – Documentos y manuales',
                'description' => 'Contrato de alquiler, condiciones y documentos necesarios para alquilar una moto. Sin depósito, normas claras, seguro incluido.',
                'keywords' => 'contrato alquiler moto, documentos alquiler, condiciones alquiler, seguro moto, MotoGo24',
            ],
            'h1' => 'Contrato de alquiler y depósito – condiciones justas sin anticipo',
            'intro' => 'En <strong>MotoGo24</strong> apostamos por la simplicidad y la equidad. Alquilamos <strong>sin depósito</strong>, con un <strong>contrato claro</strong>, <strong>seguro incluido</strong> y <strong>equipo del conductor</strong>.',
            'top_cta' => ['label' => 'RESERVAR EN LÍNEA', 'href' => '/rezervace', 'aria' => 'Reservar moto online en Motogo24'],
            'cta' => [
                'title' => 'Contrato sin depósito – alquiler de motos Vysočina',
                'text' => 'MotoGo24 es un <strong>alquiler de motos en Vysočina</strong> con condiciones justas.',
                'buttons' => [['label' => 'RESERVAR EN LÍNEA', 'href' => '/rezervace', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_pristaveni' => [
            'seo' => [
                'title' => 'Entrega de la moto | MotoGo24',
                'description' => 'Entrega de la moto en tu puerta. Llevamos la moto al hotel, estación o cualquier dirección. Tarifa desde 290 Kč. Servicio 24/7.',
                'keywords' => 'entrega moto, llevar moto, entrega motocicleta, alquiler motos Vysočina',
            ],
            'h1' => 'Entrega de la moto – directa a ti',
            'intro' => '¿Quieres salir sin tener que ir al alquiler? Organizamos <strong>la entrega de la moto</strong> en el <strong>lugar acordado</strong>.',
            'top_cta' => ['label' => 'RESERVAR CON ENTREGA', 'href' => '/rezervace?delivery=1'],
            'cta' => [
                'title' => 'Entrega de la moto – alquiler de motos Vysočina',
                'text' => 'MotoGo24 ofrece <strong>entrega de la moto</strong> en la región y fuera. <strong>Servicio 24/7, sin depósito, equipo incluido</strong>.',
                'buttons' => [['label' => 'RESERVAR CON ENTREGA', 'href' => '/rezervace?delivery=1', 'cls' => 'btndark pulse']],
            ],
        ],

        'jak_pujcit_vraceni_jinde' => [
            'seo' => [
                'title' => 'Devolución de moto en otro lugar | MotoGo24',
                'description' => 'Devuelve la moto fuera del alquiler – desde el hotel, estación u otra dirección. Recogida en Vysočina y fuera. Precio según distancia, servicio 24/7.',
                'keywords' => 'devolución moto otro lugar, recogida moto, devolución fuera alquiler, alquiler motos Vysočina',
            ],
            'h1' => 'Devolución de moto en otro lugar – recogida hasta donde estés',
            'intro' => 'No tienes que volver al alquiler. <strong>MotoGo24</strong> ofrece <strong>recogida de la moto</strong> desde el lugar que te conviene – hotel, estación, dirección propia.',
            'top_cta' => ['label' => 'RESERVAR CON RECOGIDA', 'href' => '/rezervace?return_delivery=1'],
            'cta' => [
                'title' => 'Devolución de moto en cualquier lugar – MotoGo24',
                'text' => 'MotoGo24 organiza la <strong>recogida de la moto</strong> desde el lugar que te conviene. <strong>24/7, sin depósito, sin preocupaciones.</strong>',
                'buttons' => [['label' => 'RESERVAR CON RECOGIDA', 'href' => '/rezervace?return_delivery=1', 'cls' => 'btndark pulse']],
            ],
        ],

        'faq' => [
            'seo' => [
                'title' => 'Preguntas frecuentes | MotoGo24',
                'description' => 'Preguntas frecuentes sobre alquiler de motos. Reserva, recogida, devolución, condiciones, entrega, viajes al extranjero, vales regalo.',
                'keywords' => 'FAQ alquiler motos, preguntas alquiler moto, condiciones alquiler, depósito, equipo',
            ],
            'h1' => 'Preguntas frecuentes – alquiler de motos MotoGo24',
            'closing' => 'Nuestro <strong>alquiler de motos en Vysočina</strong> está aquí para todos los que quieren vivir una <strong>conducción inolvidable</strong> sin complicaciones.',
            'cta' => ['label' => 'Reservar moto online', 'href' => '/rezervace'],
        ],

        'home' => [
            'seo' => [
                'title' => 'Alquiler de motos en Vysočina | MotoGo24',
                'description' => 'Alquila una moto en Vysočina. Sin depósito, equipo incluido, servicio 24/7. Motos de turismo, sport, enduro e infantiles. Reserva online.',
                'keywords' => 'alquiler motos Vysočina, alquiler motos Pelhřimov, alquiler sin depósito, alquiler 24/7, motos para alquilar, reserva online moto',
                'og_image' => null,
            ],
            'hero' => [
                'image' => 'gfx/hero-banner.jpg',
                'alt' => 'Alquiler de motos Vysočina',
                'eyebrow' => '<strong>Alquiler de motos</strong> en Vysočina',
                'body' => 'Alquila una moto en Vysočina fácilmente online.<br>Elige entre modelos de turismo, sport y enduro.<br>Reserva con pago con tarjeta y recogida rápida.',
                'cta_primary' => ['label' => 'ELIGE TU MOTO', 'href' => '/katalog', 'cls' => 'btngreen'],
                'cta_secondary' => ['label' => 'CÓMO FUNCIONA', 'href' => '/jak-pujcit', 'cls' => 'btndark'],
            ],
            'h1' => 'Alquiler de motos Vysočina Motogo24 – sin depósito y 24/7',
            'intro' => 'Bienvenido a <strong>Motogo24</strong> – tu alquiler de motos en Vysočina. Aquí alquilas una moto <strong>sin depósito</strong>, con equipo incluido y en modo <strong>24/7</strong>. Ya busques moto de turismo, sport, enduro o infantil, Motogo24 en el corazón de Vysočina te ofrece la moto perfecta.',
            'signposts_title' => 'Guía rápida por Motogo24',
            'motos_section' => [
                'title' => 'Nuestras motos para alquilar en Vysočina',
                'intro' => 'Mira nuestra oferta de motos de turismo, sport y enduro de nuestro alquiler en Vysočina.',
                'empty' => 'Actualmente no tenemos motos disponibles.',
                'cta_label' => 'CATÁLOGO DE MOTOS',
                'cta_href' => '/katalog',
                'limit' => 4,
            ],
            'process' => ['title' => 'Cómo funciona el alquiler de motos en Vysočina'],
            'faq' => ['title' => 'Preguntas frecuentes', 'more_link' => '/jak-pujcit/faq'],
            'cta' => [
                'title' => 'Reserva tu moto online',
                'text' => 'Nuestro <strong>alquiler de motos Vysočina</strong> está abierto <strong>24/7</strong>. Unos clics y tu viaje comienza.',
                'buttons' => [
                    ['label' => 'RESERVAR MOTO', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Vale regalo', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Consejos de rutas', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
            'blog' => [
                'title' => 'Blog y consejos',
                'empty' => 'Aún no hay artículos.',
                'cta_label' => 'LEER MÁS EN EL BLOG',
                'cta_href' => '/blog',
                'limit' => 3,
            ],
            'reviews' => [
                'title' => 'Lo que dicen nuestros clientes',
                'intro' => 'Reseñas reales de motoristas que alquilaron con nosotros. Gracias por cada valoración.',
            ],
        ],

        'pujcovna' => [
            'seo' => [
                'title' => 'Sobre el alquiler de motos | MotoGo24',
                'description' => 'Alquiler de motos Motogo24 en Vysočina. Sin depósito, con reserva online y equipo incluido. Motos de turismo, sport, enduro e infantiles. Servicio 24/7.',
                'keywords' => 'alquiler motos, alquiler motos Vysočina, motos sin depósito, alquiler 24/7, equipo incluido',
            ],
            'breadcrumb' => [['label' => 'Inicio', 'href' => '/'], 'Alquiler de motos'],
            'intro' => [
                'h1' => 'Alquiler de motos Vysočina Motogo24',
                'body' => 'Nuestro <strong>alquiler de motos en Vysočina</strong> en Pelhřimov ofrece <strong>alquiler de motos</strong> sin obstáculos – <strong>sin depósito</strong>, con <strong>reserva online</strong> y <strong>equipo incluido</strong>. Elige entre <strong>motos de turismo</strong>, <strong>sport</strong>, <strong>enduro</strong> e <strong>infantiles</strong>, y sal cuando quieras: estamos abiertos <strong>24/7</strong>.',
            ],
            'benefits' => [
                'title' => 'Por qué alquilar con nosotros',
                'closing' => '¿Buscas un <strong>alquiler de motos en Vysočina</strong>? Motogo24 ofrece condiciones justas, un proceso claro y máquinas en perfecto estado para viajes por la República Checa y al extranjero.',
                'buttons' => [
                    ['label' => 'Ver motos para alquilar', 'href' => '/katalog', 'cls' => 'btngreen'],
                    ['label' => 'RESERVAR', 'href' => '/rezervace', 'cls' => 'btngreen pulse'],
                ],
            ],
            'process' => ['title' => 'Cómo funciona el alquiler en Vysočina'],
            'faq' => ['title' => 'Preguntas frecuentes', 'more_link' => '/jak-pujcit/faq'],
            'cta' => [
                'title' => 'Reserva tu moto online',
                'text' => 'Nuestro <strong>alquiler de motos Vysočina</strong> está abierto <strong>24/7</strong>.',
                'buttons' => [
                    ['label' => 'RESERVAR MOTO', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Vale regalo', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Consejos de rutas', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
        ],
    ]),
];
