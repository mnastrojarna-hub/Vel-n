<?php
// MotoGo24 — pages_en.php (English overlay nad CS defaults)
// Cast C (kontakt, jak_pujcit, postup, vyzvednuti, vraceni-pujcovna, poukazy)
// je plne prelozena. Casti A+B obsahuji jen klicove texty (h1, intro, seo, cta);
// zbytek strukturalniho obsahu (steps, FAQ items, gear lists) propada na CS
// fallback pres siteContent() deep merge.

$c = require __DIR__ . '/pages_en_c.php';

return [
    'pages' => array_merge($c['pages'], [

        // ====== ČÁST A ======

        'jak_pujcit_cena' => [
            'seo' => [
                'title' => 'Motorcycle rental Vysočina – How to rent – What is included',
                'description' => 'Find out what is included in the motorcycle rental price at MotoGo24. The rental offers clear conditions, gear and services without hidden fees. Book your motorcycle online easily.',
                'keywords' => 'motorcycle rental Vysočina, motorcycle rental Pelhřimov, no-deposit rental, 24/7 motorcycle rental, online motorcycle booking, motorbike rental Czech Republic',
            ],
            'h1' => 'What is included in the motorcycle rental price',
            'intro' => 'At <strong>MotoGo24 – motorcycle rental in Vysočina</strong> you get fair conditions. <strong>Without deposit, with rider gear included and 24/7 service</strong>. Everything you need for a safe and pleasant ride is part of the rental.',
            'cta' => [
                'title' => 'Gear included – motorcycle rental MotoGo24 – Vysočina',
                'text' => '<strong>MotoGo24 is a modern motorcycle rental in Vysočina</strong> with rider gear included, no-deposit rental and 24/7 service. Choose a <strong>touring, supermoto, naked or kids\' motorcycle</strong> and book online. Everything is clear and without hidden fees.',
                'buttons' => [
                    ['label' => 'BOOK ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse', 'aria' => 'Book a motorcycle with gear included at the Motogo24 rental'],
                ],
            ],
        ],

        'jak_pujcit_dokumenty' => [
            'seo' => [
                'title' => 'Motorcycle rental Vysočina – How to rent – Documents and manuals',
                'description' => 'Rental agreement, terms and necessary documents for renting a motorcycle. Without deposit, clear rules, insurance included.',
                'keywords' => 'motorcycle rental agreement, rental documents, rental terms, motorcycle insurance, MotoGo24 Vysočina',
            ],
            'h1' => 'Rental agreement and deposit – fair conditions without an advance',
            'intro' => 'At <strong>MotoGo24</strong> we focus on simplicity and fairness. We rent <strong>without deposit</strong>, with a <strong>clear rental agreement</strong>, <strong>insurance included</strong> and <strong>rider gear</strong>.',
            'top_cta' => ['label' => 'BOOK ONLINE', 'href' => '/rezervace', 'aria' => 'Book a motorcycle online at Motogo24'],
            'cta' => [
                'title' => 'Rental agreement without deposit – motorcycle rental Vysočina',
                'text' => 'MotoGo24 is a <strong>motorcycle rental in Vysočina</strong> with fair conditions.',
                'buttons' => [
                    ['label' => 'BOOK ONLINE', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                ],
            ],
        ],

        'jak_pujcit_pristaveni' => [
            'seo' => [
                'title' => 'Motorcycle delivery | MotoGo24',
                'description' => 'Motorcycle delivery to your door. We bring the motorcycle to your hotel, train station or any address. Delivery price list from 290 Kč. 24/7 service.',
                'keywords' => 'motorcycle delivery, motorcycle door delivery, motorcycle rental Vysočina, MotoGo24 delivery',
            ],
            'h1' => 'Motorcycle delivery – brought right to you',
            'intro' => 'Want to ride without the hassle of getting to the rental? We arrange <strong>motorcycle delivery</strong> to a <strong>place of your choice</strong>.',
            'top_cta' => ['label' => 'BOOK WITH DELIVERY', 'href' => '/rezervace?delivery=1'],
            'cta' => [
                'title' => 'Motorcycle delivery – motorcycle rental Vysočina',
                'text' => 'MotoGo24 offers <strong>motorcycle delivery</strong> across the region and beyond. <strong>24/7 service, no deposit, gear included.</strong>',
                'buttons' => [
                    ['label' => 'BOOK WITH DELIVERY', 'href' => '/rezervace?delivery=1', 'cls' => 'btndark pulse'],
                ],
            ],
        ],

        'jak_pujcit_vraceni_jinde' => [
            'seo' => [
                'title' => 'Return motorcycle elsewhere – pickup service | MotoGo24',
                'description' => 'Return your motorcycle off the rental site – from a hotel, train station or any address. Pickup throughout Vysočina and beyond. Price by distance, 24/7 service.',
                'keywords' => 'return motorcycle elsewhere, motorcycle pickup, return outside the rental, motorcycle rental Vysočina',
            ],
            'h1' => 'Return motorcycle elsewhere – pickup brought to you',
            'intro' => 'You don\'t have to return to the rental. <strong>MotoGo24</strong> offers <strong>motorcycle pickup</strong> from a place that suits you – hotel, train station or your own address.',
            'top_cta' => ['label' => 'BOOK WITH PICKUP', 'href' => '/rezervace?return_delivery=1'],
            'cta' => [
                'title' => 'Return motorcycle anywhere – MotoGo24',
                'text' => 'MotoGo24 arranges <strong>motorcycle pickup</strong> from a place that suits you. <strong>24/7, no deposit, no hassle.</strong>',
                'buttons' => [
                    ['label' => 'BOOK WITH PICKUP', 'href' => '/rezervace?return_delivery=1', 'cls' => 'btndark pulse'],
                ],
            ],
        ],

        // ====== ČÁST B ======

        'faq' => [
            'seo' => [
                'title' => 'Frequently asked questions | MotoGo24',
                'description' => 'Frequently asked questions about renting a motorcycle. Booking, pickup, return, conditions, delivery, travelling abroad, gift vouchers.',
                'keywords' => 'FAQ motorcycle rental, motorcycle rental questions, rental conditions, deposit, gear',
            ],
            'h1' => 'Frequently asked questions – motorcycle rental MotoGo24',
            'closing' => 'Our <strong>motorcycle rental in Vysočina</strong> is here for everyone who wants an <strong>unforgettable ride</strong> without unnecessary complications.',
            'cta' => ['label' => 'Book a motorcycle online', 'href' => '/rezervace'],
        ],

        'home' => [
            'seo' => [
                'title' => 'Motorcycle rental in Vysočina | MotoGo24',
                'description' => 'Rent a motorcycle in Vysočina. Without deposit, gear included, 24/7 service. Touring, sport, enduro and kids\' motorcycles. Online booking.',
                'keywords' => 'motorcycle rental Vysočina, motorcycle rental Pelhřimov, no-deposit motorcycle rental, 24/7 rental, motorcycles for rent, online motorcycle booking',
                'og_image' => null,
            ],
            'hero' => [
                'image' => 'gfx/hero-banner.jpg',
                'alt' => 'Motorcycle rental Vysočina',
                'eyebrow' => '<strong>Motorcycle rental</strong> in Vysočina',
                'body' => 'Rent a motorcycle in Vysočina easily online.<br>Choose from touring, sport and enduro models.<br>Booking with card payment and quick pickup.',
                'cta_primary' => ['label' => 'CHOOSE A MOTORCYCLE', 'href' => '/katalog', 'cls' => 'btngreen'],
                'cta_secondary' => ['label' => 'HOW IT WORKS', 'href' => '/jak-pujcit', 'cls' => 'btndark'],
            ],
            'h1' => 'Motorcycle rental Vysočina Motogo24 – without deposit and 24/7',
            'intro' => 'Welcome to <strong>Motogo24</strong> – your motorcycle rental in Vysočina. With us you rent a motorcycle <strong>without deposit</strong>, with gear included and in <strong>24/7</strong> mode. Whether you\'re looking for a touring, sport, enduro or kids\' motorcycle, Motogo24 in the heart of Vysočina has the right one for you.',
            'signposts_title' => 'Quick guide around Motogo24',
            'signposts' => [
                ['icon' => 'gfx/vyber-motorku.svg', 'title' => 'Motorcycle catalog', 'text' => 'Browse our offer of motorcycles for rent — from sport to touring models.', 'btn' => 'MOTORCYCLE CATALOG', 'href' => '/katalog'],
                ['icon' => 'gfx/potvrzeni-rezervace.svg', 'title' => 'How to rent a motorcycle', 'text' => 'A simple process: choose a motorcycle to rent, book and ride.', 'btn' => 'HOW TO RENT', 'href' => '/jak-pujcit'],
                ['icon' => 'gfx/rezervace-online.svg', 'title' => 'Online motorcycle booking', 'text' => 'Book a motorcycle for rent through our easy online system.', 'btn' => 'BOOK A MOTORCYCLE', 'href' => '/rezervace'],
                ['icon' => 'gfx/kontakt.svg', 'title' => 'Contacts and map', 'text' => 'Visit our motorcycle rental in Pelhřimov or contact us.', 'btn' => 'CONTACT', 'href' => '/kontakt'],
                ['icon' => 'gfx/faq.svg', 'title' => 'Frequently asked questions', 'text' => 'The most common questions about renting a motorcycle in one place.', 'btn' => 'FAQ', 'href' => '/jak-pujcit/faq'],
                ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => 'Motorcycle trips', 'text' => 'Discover the best motorcycle routes in the Czech Republic for tourists and locals.', 'btn' => 'MOTORCYCLE ROUTES', 'href' => '/blog'],
            ],
            'motos_section' => [
                'title' => 'Our motorcycles for rent in Vysočina',
                'intro' => 'Browse our offer of touring, sport and enduro from our motorcycle rental in Vysočina.',
                'empty' => 'We currently have no motorcycles available.',
                'cta_label' => 'MOTORCYCLE CATALOG',
                'cta_href' => '/katalog',
                'limit' => 4,
            ],
            'process' => [
                'title' => 'How motorcycle rental works in Vysočina',
                'steps' => [
                    ['icon' => 'gfx/vyber-motorku.svg', 'title' => '1. Choose', 'text' => 'Pick your ideal motorcycle from our offer of motorcycles for rent.'],
                    ['icon' => 'gfx/rezervace-online.svg', 'title' => '2. Book', 'text' => 'Book your motorcycle rental through our simple online system.'],
                    ['icon' => 'gfx/predani-motorky.svg', 'title' => '3. Pick up', 'text' => 'Pick up the motorcycle at our rental in Pelhřimov.'],
                    ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => '4. Enjoy the ride', 'text' => 'Embrace the freedom and discover the Czech Republic on rental motorcycles.'],
                ],
            ],
            'faq' => [
                'title' => 'Frequently asked questions',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    ['q' => 'How can I book a motorcycle?', 'a' => 'You can book a motorcycle through our online booking system right here on the website. Or contact us by e-mail, phone or via social media.'],
                    ['q' => 'Can I rent a motorcycle without booking in advance?', 'a' => 'Unfortunately not. Every motorcycle has to be booked in advance — online, by phone, e-mail or via social media.'],
                    ['q' => 'Do I have to pay a deposit?', 'a' => 'No! With us you <strong>do not pay any deposit</strong>. Our rental is fundamentally different from most of the competition in this respect.'],
                    ['q' => 'Can I take the motorcycle abroad?', 'a' => 'Yes, you can travel abroad with the motorcycle without any problem. We don\'t restrict trips outside the Czech Republic; you only need to comply with the territorial validity of your insurance (green card).'],
                ],
            ],
            'cta' => [
                'title' => 'Book your motorcycle online',
                'text' => 'Our <strong>motorcycle rental Vysočina</strong> is open <strong>24/7</strong>. A few clicks and your ride begins.',
                'buttons' => [
                    ['label' => 'BOOK A MOTORCYCLE', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Gift voucher', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Route tips', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
            'blog' => [
                'title' => 'Blog and tips',
                'empty' => 'No articles yet.',
                'cta_label' => 'READ MORE ON THE BLOG',
                'cta_href' => '/blog',
                'limit' => 3,
            ],
            'reviews' => [
                'title' => 'What our customers say',
                'intro' => 'Real reviews from riders who rented with us. Thank you for every rating.',
            ],
        ],

        'pujcovna' => [
            'seo' => [
                'title' => 'About the motorcycle rental | MotoGo24',
                'description' => 'Motogo24 motorcycle rental in Vysočina. Without deposit, with online booking and gear included. Touring, sport, enduro and kids\' motorcycles. 24/7 service.',
                'keywords' => 'motorcycle rental, motorcycle rental Vysočina, no-deposit motorcycles, 24/7 rental, gear included',
            ],
            'breadcrumb' => [
                ['label' => 'Home', 'href' => '/'],
                'Motorcycle rental',
            ],
            'intro' => [
                'h1' => 'Motorcycle rental Vysočina Motogo24',
                'body' => 'Our <strong>motorcycle rental in Vysočina</strong> in Pelhřimov offers <strong>motorcycle rentals</strong> without unnecessary obstacles – <strong>without deposit</strong>, with <strong>online booking</strong> and <strong>gear included</strong>. Choose from <strong>touring</strong>, <strong>sport</strong>, <strong>enduro</strong> and <strong>kids\' motorcycles</strong>, and head off any time: we\'re open <strong>24/7</strong>.',
            ],
            'benefits' => [
                'title' => 'Why rent a motorcycle with us',
                'closing' => 'Looking for a <strong>motorcycle rental in Vysočina</strong>? Motogo24 – <strong>motorcycle rental in Vysočina</strong> – offers fair conditions, a clear procedure and top-maintained machines for trips around the Czech Republic and abroad.',
                'buttons' => [
                    ['label' => 'See motorcycles for rent', 'href' => '/katalog', 'cls' => 'btngreen'],
                    ['label' => 'BOOK NOW', 'href' => '/rezervace', 'cls' => 'btngreen pulse'],
                ],
                'items' => [
                    ['icon' => 'gfx/ico-bez-kauce.svg', 'title' => 'No deposit', 'text' => 'and no hidden fees'],
                    ['icon' => 'gfx/rezervace-online.svg', 'title' => 'Online booking', 'text' => 'in just a few clicks'],
                    ['icon' => 'gfx/vyber-vybavu.svg', 'title' => 'Rider gear included', 'text' => 'helmet, jacket, trousers and gloves'],
                    ['icon' => 'gfx/ico-nonstop.svg', 'title' => '24/7 service', 'text' => 'for pickup and return per your booking'],
                    ['icon' => 'gfx/ico-spolecne.svg', 'title' => 'We\'re in it together', 'text' => 'if anything happens'],
                    ['icon' => 'gfx/predani-motorky.svg', 'title' => 'Motorcycle delivery & pickup', 'text' => 'to an agreed place'],
                ],
            ],
            'process' => [
                'title' => 'How motorcycle rental works in Vysočina',
                'steps' => [
                    ['icon' => 'gfx/vyber-motorku.svg', 'title' => '1. Pick a motorcycle', 'text' => 'Browse our offer and choose the type that suits you, your experience and your licence.'],
                    ['icon' => 'gfx/rezervace-online.svg', 'title' => '2. Book online', 'text' => 'Reserve by date or by a specific motorcycle you want to rent.'],
                    ['icon' => 'gfx/vyber-vybavu.svg', 'title' => '3. Choose gear', 'text' => 'Rider gear is included; passenger gear costs extra. You can choose the size on site.'],
                    ['icon' => 'gfx/zaplat.svg', 'title' => '4. Pay', 'text' => 'Pay easily online through the payment gateway.'],
                    ['icon' => 'gfx/predani-motorky.svg', 'title' => '5. Pick up the motorcycle', 'text' => 'Pick up the motorcycle directly at the rental, or at the place you selected when booking.'],
                    ['icon' => 'gfx/uzij-si-jizdu.svg', 'title' => '6. Enjoy the ride', 'text' => 'Hit the road, discover new experiences and enjoy the full freedom of two wheels.'],
                    ['icon' => 'gfx/vrat-motorku-vcas.svg', 'title' => '7. Return the motorcycle', 'text' => 'Simply return the motorcycle on the agreed day – at the rental, or at the agreed place.'],
                    ['icon' => 'gfx/sleva-na-pristi-jizdu.svg', 'title' => 'Discount for your next ride', 'text' => 'After returning the motorcycle, we\'ll automatically send you a 200 Kč discount code for your next booking.'],
                ],
            ],
            'faq' => [
                'title' => 'Frequently asked questions',
                'more_link' => '/jak-pujcit/faq',
                'items' => [
                    ['q' => 'How can I book a motorcycle?', 'a' => 'You can book a motorcycle through our online booking system right here on the website. Or contact us by e-mail, phone or via social media.'],
                    ['q' => 'Can I rent a motorcycle without booking in advance?', 'a' => 'Unfortunately not. Every motorcycle has to be booked in advance.'],
                    ['q' => 'Do I have to pay a deposit?', 'a' => 'No! With us you <strong>do not pay any deposit</strong>. Our rental is fundamentally different from most of the competition in this respect.'],
                    ['q' => 'Can I take the motorcycle abroad?', 'a' => 'Yes, you can travel abroad with the motorcycle without any problem. We don\'t restrict trips outside the Czech Republic; you only need to comply with the territorial validity of your insurance (green card).'],
                ],
            ],
            'cta' => [
                'title' => 'Book your motorcycle online',
                'text' => 'Our <strong>motorcycle rental Vysočina</strong> is open <strong>24/7</strong>. A few clicks and your ride begins.',
                'buttons' => [
                    ['label' => 'BOOK A MOTORCYCLE', 'href' => '/rezervace', 'cls' => 'btndark pulse'],
                    ['label' => 'Gift voucher', 'href' => '/poukazy', 'cls' => 'btndark'],
                    ['label' => 'Route tips', 'href' => '/blog', 'cls' => 'btndark'],
                ],
            ],
        ],
    ]),
];
