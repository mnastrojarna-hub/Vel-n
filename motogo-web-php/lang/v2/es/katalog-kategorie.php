<?php
// Páginas de categorías del catálogo (ES): texto final + meta description por categoría (pages/katalog.php → siteContent('katalog_<cat>')).
// Por defecto CS = $categoryOutros / $catDescriptions en pages/katalog.php. 'models' = frase con hasta 3 modelos actuales
// ({models}), se añade a body1 solo si la categoría tiene motos; si no, 'nomodels'.
return ['pages' => [
'katalog_cestovni' => [
    'outro' => [
        'title' => 'Motos de turismo en alquiler: para largos viajes y vacaciones',
        'body1' => 'Las motos de turismo y adventure de nuestra flota están hechas para largas distancias: posición de conducción más alta, asiento cómodo para piloto y pasajero, depósito grande con 300–400 km de autonomía y maletas para el equipaje.',
        'models' => 'Ahora mismo encontrarás, por ejemplo, {models}, todas con mantenimiento periódico y listas para viajar por la República Checa o al extranjero.',
        'nomodels' => 'Todas tienen mantenimiento periódico y están listas para viajar por la República Checa o al extranjero.',
        'body2' => 'Alquilamos sin fianza, la carta verde y los documentos internacionales van incluidos automáticamente y el equipamiento completo del piloto está incluido en el precio. Para el pasajero puedes añadir equipamiento (casco, chaqueta, braga) con suplemento.',
    ],
    'description' => 'Alquiler de motos de turismo (touring, GT) en la región de Vysočina. Motos adventure para rutas largas y autopistas. Sin fianza, reserva online.',
],
'katalog_naked' => [
    'outro' => [
        'title' => 'Motos naked: máquinas deportivas para el día a día',
        'body1' => 'Las naked sin carenado ofrecen <strong>una sensación de libertad inconfundible</strong> y una conexión directa con el motor. Son ideales para moverse con agilidad por la ciudad, escapadas de fin de semana y disfrutar de las curvas.',
        'models' => 'En nuestra flota encontrarás, por ejemplo, {models}, todas en excelente estado técnico y con mantenimiento periódico.',
        'nomodels' => 'Todas están en excelente estado técnico y con mantenimiento periódico.',
        'body2' => 'Alquilamos sin fianza y el equipamiento del piloto (casco, chaqueta, pantalón, guantes) siempre está incluido en el precio. Antes de la recogida revisamos la moto juntos y te explicamos sus particularidades. Si no tienes experiencia con una determinada clase de potencia, te ayudamos encantados a elegir.',
    ],
    'description' => 'Alquiler de motos naked en la región de Vysočina. Máquinas deportivas y ruteras para el día a día. Sin fianza, equipamiento incluido, reserva online.',
],
'katalog_supermoto' => [
    'outro' => [
        'title' => 'Motos supermoto: ligeras y ágiles para divertirse en ciudad',
        'body1' => 'La supermoto combina las ventajas de una enduro (ligereza, suspensiones de largo recorrido, posición alta) con neumáticos de carretera y frenos de disco. El resultado es <strong>una máquina muy ágil</strong> que se desenvuelve bien en el tráfico urbano, por caminos rurales y en rutas cortas por Vysočina.',
        'models' => 'En el catálogo encontrarás, por ejemplo, {models}.',
        'body2' => 'Estas motos requieren permiso A o A2 y son más adecuadas para pilotos con experiencia que quieren disfrutar de una moto ligera y juguetona. Alquilamos sin fianza y el equipamiento del piloto está incluido. En la recogida te explicamos las particularidades de conducir con una posición alta y la importancia del equilibrio.',
    ],
    'description' => 'Alquiler de motos supermoto en la región de Vysočina. Máquinas urbanas ligeras con posición alta. Sin fianza, equipamiento incluido, reserva online.',
],
'katalog_chopper' => [
    'outro' => [
        'title' => 'Motos chopper y cruiser para rodar con calma',
        'body1' => 'Las chopper y cruiser están hechas para <strong>viajar con comodidad en largas distancias</strong>: asiento bajo, postura relajada, el sonido característico de un bicilíndrico y una estética clásica. Perfectas para una salida de domingo o un viaje más largo por la República Checa.',
        'body2' => 'Ampliamos nuestra flota continuamente: si tienes en mente un modelo concreto, escríbenos. Alquilamos sin fianza y el equipamiento del piloto está incluido. En la recogida te entregamos las llaves, la documentación y el equipamiento completo.',
    ],
    'description' => 'Alquiler de motos chopper y cruiser en la región de Vysočina. Máquinas cómodas para rodar con calma. Sin fianza, equipamiento incluido, reserva online.',
],
'katalog_detske' => [
    'outro' => [
        'title' => 'Motos infantiles: diversión segura para los más pequeños',
        'body1' => 'Las motos infantiles se pueden alquilar <strong>sin permiso de conducir</strong> y usar en el jardín, en un camping o en un curso de conducción para niños.',
        'models' => 'En el catálogo encontrarás, por ejemplo, {models}.',
        'body2' => 'Antes de cada salida recomendamos repasar con el niño las normas básicas de seguridad y equiparlo siempre con casco y protecciones. La fecha, la sucursal y la posible entrega a domicilio se acuerdan directamente al reservar.',
    ],
    'description' => 'Alquiler de motos infantiles sin permiso. Diversión segura en el jardín o en el camping. Entrega en toda la República Checa, reserva online.',
],
'katalog_sportovni' => [
    'outro' => [
        'title' => 'Motos deportivas: adrenalina y potencia para pilotos con experiencia',
        'body1' => 'Las motos deportivas (supersport) están pensadas para <strong>pilotos con experiencia</strong> que buscan alto rendimiento, una geometría afilada y una posición deportiva. Son ideales para circuito, carreteras de curvas y escapadas de fin de semana por bonitas rutas de Moravia y Vysočina.',
        'body2' => 'Exigimos permiso A y al menos 2 años de experiencia con motos de más de 35 kW. Alquilamos sin fianza y el equipamiento completo del piloto está incluido. Antes de la recogida te explicamos las particularidades de una moto deportiva y te recomendamos prácticas de conducción segura.',
    ],
    'description' => 'Alquiler de motos deportivas en la región de Vysočina. Máquinas supersport y sport-turismo. Sin fianza, equipamiento incluido, reserva online.',
],
'katalog_scootery' => [
    'outro' => [
        'title' => 'Scooters en alquiler: comodidad en ciudad con permiso A1 o B',
        'body1' => 'Los scooters son la opción ideal para <strong>moverse por la ciudad de forma cómoda y sencilla</strong>: cambio automático, asiento bajo y espacio bajo el asiento. Parte de nuestros scooters se pueden conducir con el permiso de <strong>categoría B</strong> (el del coche) y el resto con <strong>A1</strong>. La categoría exacta siempre la encontrarás en la ficha de cada moto.',
        'body2' => 'Alquilamos sin fianza y el equipamiento del piloto (casco, guantes) está incluido. Un scooter es perfecto para ir al trabajo, hacer excursiones por la zona o como primer contacto con las dos ruedas. En la recogida te explicamos los mandos y las particularidades de la conducción.',
    ],
    'description' => 'Alquiler de scooters en la región de Vysočina. Scooters para permiso A1 o B para moverse cómodamente por la ciudad. Sin fianza, equipamiento incluido, reserva online.',
],
'katalog_ostatni' => [
    'outro' => [
        'title' => 'Remolques para motos y otro equipamiento en alquiler',
        'body1' => 'En la categoría Otros encontrarás <strong>remolques para transportar motos</strong> y otro equipamiento complementario en alquiler. Un remolque para motos resulta muy útil para llevar la moto al circuito, de vacaciones o al taller. Para remolcarlo basta con el permiso de conducir normal de <strong>categoría B</strong> (según el peso del conjunto).',
        'body2' => 'Alquilamos sin fianza y te asesoramos encantados sobre la elección y sobre cómo cargar y sujetar correctamente la moto. Los parámetros concretos (carga útil, dimensiones, categoría de permiso requerida) están en la ficha de cada artículo. La fecha y el lugar de recogida se acuerdan directamente al reservar.',
    ],
    'description' => 'Alquiler de remolques para motos y otro equipamiento en la región de Vysočina. Remolque para permiso B. Sin fianza, reserva online.',
],
]];
