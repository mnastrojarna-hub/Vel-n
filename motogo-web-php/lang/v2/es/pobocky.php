<?php
// ES překlad textů poboček (Velín → Texty webu → Pobočky, klíče web.pobocky.*; aktuální
// CS hodnoty z CMS k 2026-10-10). Struktura = pobockyDefaults() (data/pobocky.php) bez
// polí jen z kódu (slug, branch_id, map, photo, gallery, video). siteContent('pobocky')
// použije tento overlay, protože CMS klíče bez ES překladu se pro ES přeskakují.
// Texty v2 (karty, průvodce, srovnání): lang/v2/es/pobocky-v2.php.

return ['pages' => ['pobocky' => [
    'seo' => [
        'title' => 'Sucursales | MotoGo24 – alquiler de motos en Pelhřimov y Brno',
        'description' => 'Sucursales del alquiler de motos MotoGo24: sucursal con personal en Mezná, cerca de Pelhřimov (Vysočina), y sucursal de autoservicio en Velké Němčice, cerca de Brno: recogida de la moto a cualquier hora.',
        'keywords' => 'sucursales MotoGo24, alquiler de motos Pelhřimov, alquiler de motos Brno, alquiler de motos autoservicio, Velké Němčice, Mezná',
    ],
    'h1' => 'Sucursales de MotoGo24',
    'intro' => 'Puedes recoger tu moto en <strong>dos lugares</strong>: en la <strong>sucursal con personal de Mezná, cerca de Pelhřimov</strong>, donde te recibimos en persona, o en la <strong>sucursal de autoservicio de Velké Němčice, cerca de Brno</strong>, donde recoges tú mismo la moto y el equipo con códigos.',
    'branches' => [
        [
            'badge' => 'Sucursal con personal',
            'title' => 'Mezná, cerca de Pelhřimov',
            'address' => 'Mezná 9, 393 01 Pelhřimov',
            'hours' => 'De lunes a domingo, a cualquier hora (nonstop), también fines de semana y festivos. La hora de recogida y de devolución la eliges en la reserva.',
            'text' => 'Nuestra sucursal principal en Vysočina. Te <strong>entregamos la moto en persona</strong>: te lo explicamos todo, te ayudamos con el ajuste y a elegir el equipo, y revisamos juntos el protocolo de entrega. El equipo de piloto está incluido en el precio. Desde aquí también ofrecemos la <strong>entrega de la moto</strong> en la dirección que elijas.',
            'gear' => 'Equipo de piloto incluido en el precio: chaquetas y pantalones en tallas hasta la <strong>6XL</strong>. Solo aquí puedes alquilar también <strong>trajes de lluvia</strong> y otro equipo adicional.',
            'steps_title' => 'Cómo funciona',
            'steps' => '1. Reservas y pagas online (web o app) y subes tus documentos (DNI/pasaporte + carnet de conducir); también te lo pedimos en la sucursal con personal: si no los subes, los revisamos en el momento de la recogida.<br>2. A la hora elegida llegas a la sucursal, donde te esperamos.<br>3. Te entregamos la moto y el equipo y firmamos el protocolo de entrega.<br>4. Después de rodar, devuelves la moto en la sucursal (o la recogemos en la dirección acordada).',
            'video_title' => 'Vídeo: así funciona la sucursal',
            'gallery_title' => 'Galería de fotos de la sucursal',
            'seo_title' => 'Sucursal Mezná, cerca de Pelhřimov | MotoGo24 – alquiler de motos con personal',
            'seo_description' => 'Sucursal con personal del alquiler de motos MotoGo24 en Mezná, cerca de Pelhřimov (Vysočina): entrega de la moto en persona a cualquier hora, equipo incluido, entrega en tu dirección.',
        ],
        [
            'badge' => 'Sucursal de autoservicio',
            'title' => 'Velké Němčice, cerca de Brno',
            'address' => 'Boudky, 691 63 Velké Němčice',
            'hours' => 'Abierta 24/7 con el código de la app. La hora de recogida la eliges en la reserva: si recoges a partir de las 12:00 (alquiler de 2 días o más), el 1.er día te sale a mitad de precio y el quiosco te entrega la moto a partir de las 12:00. La hora de devolución no se elige: devuelves la moto cuando quieras el último día del alquiler, hasta las 24:00.',
            'text' => 'Moderna <strong>sucursal de autoservicio</strong> al sur de Brno. No hay personal: lo gestionas todo tú mismo en la pantalla táctil con los <strong>códigos de la app</strong>, que recibes después de pagar y completar tus documentos. Las motos de esta sucursal se recogen y se devuelven solo en la propia sucursal: no ofrecemos entrega ni recogida a domicilio. Junto a la sucursal puedes <strong>aparcar gratis</strong> durante todo el alquiler.',
            'gear' => 'Solo hay disponible <strong>casco, chaqueta con protector de espalda, pantalón, guantes, sotocasco y botas</strong>: el equipo de piloto está incluido en el precio; las botas de moto, con suplemento. Chaquetas y pantalones hasta la talla <strong>4XL</strong> (las tallas más grandes, hasta la 6XL, las tenemos en Mezná). En la sucursal de autoservicio no alquilamos <strong>trajes de lluvia</strong> ni otro equipo adicional: solo los hay en la sucursal con personal de Mezná. El equipo te lo pruebas en el vestuario y, si la talla no te queda bien, coges otra disponible y simplemente la marcas en el protocolo de entrega. El chaleco reflectante, el botiquín, el parte de accidente, el candado de disco y la llave del soporte del móvil los encontrarás en la moto.',
            'steps_title' => 'Cómo funciona',
            'steps' => '1. Reservas y pagas online, eliges la hora de recogida y subes tus documentos (DNI/pasaporte + carnet de conducir): en la sucursal de autoservicio es imprescindible; sin documentos verificados no recibes los códigos y no puedes entrar en la sucursal. Una vez verificados los documentos, recibirás en la app, por e-mail y por SMS los códigos en el orden en que los vas a introducir: <strong>1) código de la caja con la llave del portón, 2) código del vestuario</strong> (si alquilas equipo) <strong>y 3) código de la moto</strong>.<br>2. <strong>Si el portón de entrada está cerrado</strong>, abre con el código de la app la <strong>caja superior del pilar derecho del portón</strong>: dentro está la llave del candado. Abre el portón, entra y aparca en cualquiera de las plazas <strong>1–7, a la derecha junto a la valla</strong> (mira la foto del aparcamiento). Tu coche puede quedarse aquí gratis durante todo el alquiler. Si el portón está abierto, no necesitas el código de la caja.<br>3. En la pantalla introduces el código del vestuario: <strong>el vestuario es la puerta n.º 8</strong>. Coges el equipo, te cambias y cierras la puerta del vestuario (si llevas tu propio equipo, te saltas el vestuario). Si tienes el descuento por recogida a partir de las 12:00, los códigos valen a partir de las 12:00.<br>4. En la pantalla ajustas las tallas en el protocolo de entrega, lo firmas e introduces el código de la moto: se abre el box con tu moto. Cierras el box y ¡a rodar!<br>5. <strong>Si el portón estaba cerrado, al salir vuelve a cerrarlo, échale el candado, devuelve la llave a la caja superior y gira los números de la combinación.</strong> Si el portón está abierto, déjalo abierto: nunca cambies el estado del portón.<br>6. Después de rodar, devuelves la moto a su box y el equipo al vestuario, cuando quieras el último día del alquiler, hasta las 24:00. Si el portón está cerrado, haces lo mismo: lo abres con la llave de la caja y, al salir, lo vuelves a cerrar con el candado y devuelves la llave.',
            'video_title' => 'Vídeo: cómo usar la sucursal de autoservicio',
            'gallery_title' => 'Galería de fotos de la sucursal',
            'seo_title' => 'Sucursal de autoservicio Velké Němčice, cerca de Brno | MotoGo24',
            'seo_description' => 'Sucursal de autoservicio del alquiler de motos MotoGo24 en Velké Němčice, cerca de Brno: recogida y devolución 24/7 con el código de la app, eliges la hora de recogida en la reserva (desde las 12:00 el 1.er día cuesta la mitad), aparcamiento gratis.',
        ],
    ],
    'detail_button' => 'Ver la sucursal',
    'back_link' => '← Todas las sucursales',
    'cta' => [
        'title' => 'Elige tu moto en tu sucursal',
        'text' => 'En la reserva eliges la sucursal y solo te aparecen las motos que hay en ella.',
        'button' => 'RESERVAR ONLINE',
    ],
]]];
