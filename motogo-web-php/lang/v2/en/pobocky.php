<?php
// EN překlad textů poboček (Velín → Texty webu → Pobočky, klíče web.pobocky.*; aktuální
// CS hodnoty z CMS k 2026-10-10, u výbavy Velkých Němčic nové velikosti z data/pobocky.php
// — helmy S–3XL, bundy/kalhoty/rukavice do 4XL). Struktura = lang/v2/es/pobocky.php
// (pobockyDefaults() bez polí jen z kódu: slug, branch_id, map, photo, gallery, video).
// siteContent('pobocky') použije tento overlay, protože CMS klíče bez EN překladu se pro EN přeskakují.
// Texty v2 (karty, průvodce, srovnání): lang/v2/en/pobocky-v2.php.

return ['pages' => ['pobocky' => [
    'seo' => [
        'title' => 'Branches | MotoGo24 – motorcycle rental in Pelhřimov and Brno',
        'description' => 'MotoGo24 motorcycle rental branches: a staffed branch in Mezná near Pelhřimov (Vysočina) and a self-service branch in Velké Němčice near Brno – bike pick-up any time.',
        'keywords' => 'MotoGo24 branches, motorcycle rental Pelhřimov, motorcycle rental Brno, self-service motorcycle rental, Velké Němčice, Mezná',
    ],
    'h1' => 'MotoGo24 branches',
    'intro' => 'You can pick up your bike in <strong>two places</strong>: at the <strong>staffed branch in Mezná near Pelhřimov</strong>, where we welcome you in person, or at the <strong>self-service branch in Velké Němčice near Brno</strong>, where you collect the bike and gear yourself using codes.',
    'branches' => [
        [
            'badge' => 'Staffed branch',
            'title' => 'Mezná near Pelhřimov',
            'address' => 'Mezná 9, 393 01 Pelhřimov',
            'hours' => 'Monday to Sunday, any time (nonstop), including weekends and public holidays. You choose the pick-up and return time in your booking.',
            'text' => 'Our main branch in Vysočina. We <strong>hand over the bike in person</strong>: we explain everything, help you with the set-up and choosing gear, and go through the handover protocol together. Rider gear is included in the price. From here we also offer <strong>delivery of the bike</strong> to an address of your choice.',
            'gear' => 'Rider gear included in the price: jackets and trousers in sizes up to <strong>6XL</strong>. Only here can you also rent <strong>rain gear</strong> and other extra equipment.',
            'steps_title' => 'How it works',
            'steps' => '1. You book and pay online (web or app) and upload your documents (ID card/passport + driving licence); we ask for this at the staffed branch too: if you don\'t upload them, we check them on the spot at pick-up.<br>2. At the chosen time you arrive at the branch, where we are waiting for you.<br>3. We hand over the bike and gear and sign the handover protocol.<br>4. After your ride you return the bike to the branch (or we collect it from the agreed address).',
            'video_title' => 'Video: how it works at the branch',
            'gallery_title' => 'Branch photo gallery',
            'seo_title' => 'Mezná branch near Pelhřimov | MotoGo24 – staffed motorcycle rental',
            'seo_description' => 'Staffed branch of MotoGo24 motorcycle rental in Mezná near Pelhřimov (Vysočina): personal bike handover any time, gear included, delivery to your address.',
        ],
        [
            'badge' => 'Self-service branch',
            'title' => 'Velké Němčice near Brno',
            'address' => 'Boudky, 691 63 Velké Němčice',
            'hours' => 'Open 24/7 with the app code. You choose the pick-up time in your booking: if you pick up from 12:00 (rental of 2+ days), the 1st day is half price and the kiosk releases the bike from 12:00. You don\'t choose a return time: return the bike any time on the last day of the rental, by 24:00.',
            'text' => 'A modern <strong>self-service branch</strong> south of Brno. There are no staff on site: you handle everything yourself on the touchscreen using <strong>codes from the app</strong>, which you receive after paying and completing your documents. Bikes from this branch are picked up and returned only at the branch itself: we don\'t offer delivery or collection for them. You can <strong>park for free</strong> by the branch for the whole rental.',
            'gear' => 'Only a <strong>helmet, jacket with back protector, trousers, gloves, balaclava and boots</strong> are available: rider gear is included in the price, motorcycle boots for a surcharge. Helmets in sizes <strong>S–3XL</strong>; jackets, trousers and gloves up to size <strong>4XL</strong> (larger sizes, up to 6XL, are available in Mezná). We don\'t rent <strong>rain gear</strong> or other extra equipment at the self-service branch: these are only available at the staffed branch in Mezná. You try the gear on in the locker room and, if a size doesn\'t fit, you take another available one and simply mark it in the handover protocol. You\'ll find the reflective vest, first-aid kit, accident report form, disc lock and phone-holder key on the bike.',
            'steps_title' => 'How it works',
            'steps' => '1. You book and pay online, choose your pick-up time and upload your documents (ID card/passport + driving licence): at the self-service branch this is essential; without verified documents you won\'t get the codes and can\'t enter the branch. Once your documents are verified, you\'ll receive the codes in the app, by e-mail and by SMS, in the order you\'ll enter them: <strong>1) lockbox code (gate key), 2) locker room code</strong> (if you\'re renting gear) <strong>and 3) bike code</strong>.<br>2. <strong>If the entrance gate is closed</strong>, use the app code to open the <strong>upper lockbox on the right gate pillar</strong>: it holds the padlock key. Unlock the gate, drive in and park in any of spaces <strong>1–7 on the right by the fence</strong> (see the car park photo). Your car can stay here for free for the whole rental. If the gate is open, you don\'t need the lockbox code.<br>3. Enter the locker room code on the touchscreen: <strong>the locker room is door no. 8</strong>. Take your gear, get changed and close the locker room door (with your own gear, you skip the locker room). If you have the discount for pick-up from 12:00, the codes are valid from 12:00.<br>4. On the touchscreen, adjust the sizes in the handover protocol, sign it and enter the bike code: the bay with your bike opens. Close the bay and off you go!<br>5. <strong>If the gate was closed, close it again when you leave, lock the padlock, return the key to the upper lockbox and scramble the combination.</strong> If the gate is open, leave it open: never change the state of the gate.<br>6. After your ride, return the bike to its bay and the gear to the locker room, any time on the last day of the rental, by 24:00. If the gate is closed, do the same: open it with the key from the lockbox and, when you leave, lock it again with the padlock and return the key.',
            'video_title' => 'Video: how to use the self-service branch',
            'gallery_title' => 'Branch photo gallery',
            'seo_title' => 'Self-service branch Velké Němčice near Brno | MotoGo24',
            'seo_description' => 'Self-service branch of MotoGo24 motorcycle rental in Velké Němčice near Brno: pick-up and return 24/7 with the app code, choose your pick-up time when booking (from 12:00 the 1st day is half price), free parking.',
        ],
    ],
    'detail_button' => 'Branch details',
    'back_link' => '← All branches',
    'cta' => [
        'title' => 'Choose a bike at your branch',
        'text' => 'In the booking you choose the branch and only the bikes available there are shown.',
        'button' => 'BOOK ONLINE',
    ],
]]];
