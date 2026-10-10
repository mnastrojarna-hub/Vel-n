<?php
// Landing v2 — informační stránky (Jak si půjčit ×8, FAQ, Kontakt): texty nových
// prvků wrapperu landing-info.php (hero tlačítka a chipy, AI asistent, karty
// poboček na Kontaktu). Ruční ES texty, tykání, kauce = „fianza“.
// CS defaulty: lpiDefaults() v landing-info.php.
return ['pages' => ['landing_info' => [
    'cta_primary' => 'RESERVAR',
    'cta_secondary' => 'VER MOTOS',
    'cta_call' => 'LLAMAR',
    'reserve' => 'Reservar moto',
    'steps_title' => 'Paso a paso',
    'read_more' => 'Leer más',
    'read_less' => 'Mostrar menos',
    'chips' => [
        'postup' => ['Sin fianza', 'Equipo de piloto incluido', 'Reserva online en minutos'],
        'prevzeti' => ['Recogida a tu hora', 'Aparcamiento gratis', 'Sin fianza'],
        'vraceni_pujcovna' => ['Último día hasta las 24:00', 'Sin repostar ni lavar', 'Sin fianza'],
        'vraceni_jinde' => ['En toda Chequia', 'Precio claro por km', 'Sin fianza'],
        'cena' => ['0 € de fianza', 'Equipo de piloto incluido', 'Sin cargos ocultos'],
        'pristaveni' => ['A tu casa, hotel o estación', 'En toda Chequia', 'Sin fianza'],
        'dokumenty' => ['Sin fianza', 'Contrato claro', 'Pago online seguro'],
        'faq' => ['Sin fianza', 'Equipo de piloto incluido', 'Asistente IA 24/7'],
        'kontakt' => ['2 sucursales: Vysočina y Brno', 'Autoservicio 24/7 junto a Brno', 'A unos 90 min de Praga'],
    ],
    'ai' => [
        'title' => 'Asistente IA 24/7',
        'text' => '¿No encuentras tu respuesta? Pregunta a Tomás: te contesta al momento, de día o de noche.',
        'card' => 'Pregunta a Tomás: responde al momento',
        'btn' => 'Preguntar',
    ],
    'contact' => [
        'branches_title' => 'Nuestras sucursales',
        'detail' => 'Ver sucursal',
        'route' => 'Cómo llegar',
        'branches' => [
            [
                'badge' => 'Con personal',
                'title' => 'Mezná (Pelhřimov, Vysočina)',
                'text' => 'Te entregamos la moto en persona a la hora de tu reserva, todos los días, también fines de semana y festivos.',
                'chips' => ['A unos 90 min de Praga', 'Entrega a domicilio'],
            ],
            [
                'badge' => 'Autoservicio 24/7',
                'title' => 'Velké Němčice (junto a Brno)',
                'text' => 'Recoges y devuelves la moto y el equipo tú solo, con los códigos de la app: 100 % non-stop, sin esperas.',
                'chips' => ['A 30 min de Brno', 'A 35 min del aeropuerto de Brno'],
            ],
        ],
    ],
]]];
