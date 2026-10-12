# Spec of m3a_owner_texts.sql — (key/id, lang, old, new). old=None → add missing language.
# 'cs' = Czech source column. Phrase pairs are verified against live data by gen.py.

# ---------------------------------------------------------------- cms_variables
CMS = []

# (a) /pujcovna FAQ 0 — app also on App Store (iPhone)
K = 'web.pujcovna.faq.items.0.a'
G = 'Google Play (Android) i v App Store (iPhone)'
CMS += [
 (K, 'cs', 'která je zdarma ke stažení na Google Play (dostupná pro Android).',
           'která je zdarma ke stažení na Google Play (Android) i v App Store (iPhone).', G),
 (K, 'en', 'which is free to download on Google Play (available for Android).',
           'which is free to download on Google Play (Android) and the App Store (iPhone).', G),
 (K, 'de', 'die im Google Play Store (verfügbar für Android) heruntergeladen werden kann.',
           'die bei Google Play (Android) und im App Store (iPhone) heruntergeladen werden kann.', G),
 (K, 'es', 'que está disponible de forma gratuita en Google Play (disponible para Android).',
           'que está disponible de forma gratuita en Google Play (Android) y en la App Store (iPhone).', G),
 (K, 'fr', 'qui est gratuite à télécharger sur Google Play (disponible pour Android).',
           "qui est gratuite à télécharger sur Google Play (Android) et sur l'App Store (iPhone).", G),
 (K, 'nl', 'die beschikbaar is in Google Play (beschikbaar voor Android).',
           'die beschikbaar is in Google Play (Android) en in de App Store (iPhone).', G),
 (K, 'pl', 'którą można bezpłatnie pobrać z Google Play (dostępna na Androida).',
           'którą można bezpłatnie pobrać z Google Play (Android) i z App Store (iPhone).', G),
 (K, 'uk', 'який можна безплатно завантажити на Google Play (доступний для Android).',
           'який можна безплатно завантажити з Google Play (Android) та App Store (iPhone).', G),
]

# (b) home — step 3 (pickup: Mezná or self-service Velké Němčice; delivery from Mezná)
K = 'web.home.process.steps.2.text'
NEW_CS = ('Převezmi si motorku v naší půjčovně v Mezné u Pelhřimova, nebo si ji vyzvedni na samoobslužné '
          'pobočce ve Velkých Němčicích u Brna. Z Mezné můžeš využít i přistavení motorky kamkoliv v ČR.')
G = 'samoobslužné pobočce ve Velkých Němčicích u Brna'
CMS += [
 (K, 'cs', '@FULL', NEW_CS, G),
 (K, 'en', '@FULL', 'Pick up your bike at our rental shop in Mezná near Pelhřimov, or collect it at our self-service branch '
                    'in Velké Němčice near Brno. From Mezná, you can also have the bike delivered anywhere in the Czech Republic.', G),
 (K, 'de', '@FULL', 'Hol dein Motorrad in unserer Vermietung in Mezná bei Pelhřimov ab oder an unserer Selbstbedienungsfiliale '
                    'in Velké Němčice bei Brno. Von Mezná aus kannst du es dir auch überallhin in Tschechien liefern lassen.', G),
 (K, 'es', '@FULL', 'Recoge la moto en nuestro alquiler de Mezná, cerca de Pelhřimov, o en nuestra sucursal de autoservicio de '
                    'Velké Němčice, cerca de Brno. Desde Mezná también podemos llevarte la moto a cualquier lugar de la República Checa.', G),
 (K, 'fr', '@FULL', "Récupère ta moto à notre agence de Mezná, près de Pelhřimov, ou à notre agence en libre-service de "
                    "Velké Němčice, près de Brno. Depuis Mezná, tu peux aussi te faire livrer la moto n'importe où en Tchéquie.", G),
 (K, 'nl', '@FULL', 'Haal je motor op bij onze verhuur in Mezná bij Pelhřimov, of bij onze zelfbedieningsvestiging in '
                    'Velké Němčice bij Brno. Vanuit Mezná kun je de motor ook overal in Tsjechië laten bezorgen.', G),
 (K, 'pl', '@FULL', 'Odbierz motocykl w naszym oddziale Mezná koło Pelhřimova albo w samoobsługowym oddziale Velké Němčice '
                    'koło Brna. Z oddziału Mezná możesz też zamówić dostawę motocykla w dowolne miejsce w Czechach.', G),
 (K, 'uk', None,    'Забери мотоцикл у нашому прокаті в Mezná біля Пельгржимова або у філії самообслуговування Velké Němčice '
                    'біля Брна. З Mezná можеш скористатися й доставкою мотоцикла будь-куди в Чехії.', G),
]
K = 'web.home.process.steps.2.title'
G = '3. Převezmi'
CMS += [
 (K, 'en', '@FULL', '3. Pick up', G),
 (K, 'de', '@FULL', '3. Abholen', G),
 (K, 'es', '@FULL', '3. Recógela', G),
 (K, 'fr', '@FULL', '3. Récupère', G),
 (K, 'nl', '@FULL', '3. Ophalen', G),
 (K, 'pl', '@FULL', '3. Odbierz', G),
 (K, 'uk', None,    '3. Забери', G),
]

# (c) return rule — /jak-pujcit/dokumenty table row "Palivo & čištění"
K = 'web.jak_pujcit_dokumenty.payments.rows.2.1'
G = 'Na samoobslužné pobočce vraťte motorku umytou a bez svítící rezervy'
CMS += [
 (K, 'cs', '@FULL', 'V Mezné a při vrácení jinde bez povinnosti dotankovat a mýt. Na samoobslužné pobočce vraťte motorku '
                    'umytou a bez svítící rezervy (plná nádrž není nutná).', G),
 (K, 'en', '@FULL', 'In Mezná and when returning elsewhere, no need to refuel or wash the bike. At the self-service branch, '
                    'return it washed and with the reserve light off (no full tank needed).', G),
 (K, 'de', '@FULL', 'In Mezná und bei Rückgabe an einem anderen Ort musst du das Motorrad weder tanken noch waschen. An der '
                    'Selbstbedienungsfiliale bring es gewaschen zurück, ohne dass die Reserveleuchte leuchtet (volltanken musst du nicht).', G),
 (K, 'es', '@FULL', 'En Mezná y si la devuelves en otro lugar, no tienes que repostar ni lavar la moto. En la sucursal de '
                    'autoservicio, cerca de Brno, devuélvela lavada y sin el testigo de reserva encendido (no hace falta el depósito lleno).', G),
 (K, 'fr', '@FULL', "À Mezná et en cas de restitution ailleurs, tu n'as ni à faire le plein ni à laver la moto. À l'agence en "
                    "libre-service, rends-la lavée et sans voyant de réserve allumé (le plein n'est pas nécessaire).", G),
 (K, 'nl', '@FULL', 'In Mezná en bij teruggave op een andere plek hoef je niet te tanken of te wassen. Bij de '
                    'zelfbedieningsvestiging lever je de motor gewassen in en zonder brandend reservelampje (een volle tank is niet nodig).', G),
 (K, 'pl', '@FULL', 'W oddziale Mezná i przy zwrocie w innym miejscu bez obowiązku tankowania i mycia. W oddziale '
                    'samoobsługowym oddaj motocykl umyty i bez świecącej kontrolki rezerwy (pełny bak nie jest potrzebny).', G),
 (K, 'uk', None,    'У Mezná та при поверненні в іншому місці – без обов’язку заправляти й мити. У філії самообслуговування '
                    'поверни мотоцикл вимитим і так, щоб не світився індикатор резерву (повний бак не потрібен).', G),
]

# (c) /jak-pujcit/postup step 12 (CMS row overrides PHP in all 8 languages)
K = 'web.jak_pujcit_postup.process.steps.11.text'
G = 'jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy'
CMS += [
 (K, 'cs', 'Nemusíš tankovat ani mýt.',
           'Nemusíš tankovat ani mýt – jen na samoobslužné pobočce ve Velkých Němčicích ji vrať umytou a bez svítící rezervy.', G),
 (K, 'en', "You don't need to refuel or wash it.",
           "You don't need to refuel or wash it – only at the self-service branch in Velké Němčice, return it washed and with the reserve light off.", G),
 (K, 'de', 'Du musst es nicht tanken oder waschen.',
           'Du musst es nicht tanken oder waschen – nur an der Selbstbedienungsfiliale in Velké Němčice bring es gewaschen und ohne leuchtende Reserveanzeige zurück.', G),
 (K, 'es', 'No necesitas llenar el depósito ni lavar la moto.',
           'No necesitas llenar el depósito ni lavar la moto; solo en la sucursal de autoservicio de Velké Němčice devuélvela lavada y sin la luz de reserva encendida.', G),
 (K, 'fr', "Tu n'as pas besoin de faire le plein ni de la laver.",
           "Tu n'as pas besoin de faire le plein ni de la laver – seulement à l'agence en libre-service de Velké Němčice, rends-la lavée et sans voyant de réserve allumé.", G),
 (K, 'nl', 'Je hoeft niet te tanken of te wassen.',
           'Je hoeft niet te tanken of te wassen – alleen bij de zelfbedieningsvestiging in Velké Němčice lever je de motor gewassen in en zonder brandend reservelampje.', G),
 (K, 'pl', 'Nie musisz tankować ani myć.',
           'Nie musisz tankować ani myć – tylko w samoobsługowym oddziale Velké Němčice oddaj motocykl umyty i bez świecącej kontrolki rezerwy.', G),
 (K, 'uk', 'Тобі не потрібно заправляти бензин чи мити мотоцикл.',
           'Тобі не потрібно заправляти бензин чи мити мотоцикл – лише у філії самообслуговування Velké Němčice поверни його вимитим і так, щоб не світився індикатор резерву.', G),
]

# (c) /jak-pujcit/vraceni-v-pujcovne CTA — company-wide "bez mytí" claim
K = 'web.jak_pujcit_vraceni_pujcovna.cta.text'
G = 'Bez kauce, bez tankování, v Mezné i bez mytí.'
CMS += [
 (K, 'cs', 'Bez kauce, bez mytí, bez tankování.', 'Bez kauce, bez tankování, v Mezné i bez mytí.', G),
 (K, 'en', 'No deposit, no washing, no refueling.', 'No deposit, no refuelling – and in Mezná no washing either.', G),
 (K, 'de', 'Ohne Kaution, ohne Waschen, ohne Tanken.', 'Ohne Kaution, ohne Tanken – und in Mezná auch ohne Waschen.', G),
 (K, 'es', 'Sin depósito, sin lavado, sin repostar.', 'Sin depósito, sin repostar y, en Mezná, también sin lavado.', G),
 (K, 'fr', 'Sans dépôt de garantie, sans lavage, sans carburant.', 'Sans dépôt de garantie, sans faire le plein – et à Mezná, sans lavage non plus.', G),
 (K, 'nl', 'Geen borg, geen schoonmaak, geen tankstation.', 'Geen borg, niet tanken – en in Mezná ook niet wassen.', G),
 (K, 'pl', 'Bez kaucji, bez mycia, bez tankowania.', 'Bez kaucji, bez tankowania, a w oddziale Mezná także bez mycia.', G),
 (K, 'uk', 'Без застави, без миття, без заправлення.', 'Без застави, без заправлення, а в Mezná ще й без миття.', G),
]

# ---------------------------------------------------------------- faq_items
FAQ = []
I = 'e6df7d9f-16a7-4ce6-8f9c-a046f40a1c63'   # Musím vracet s plnou nádrží a čistou?
G = 'Na samoobslužné pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ'
FAQ += [
 (I, 'answer', 'cs', '@FULL', 'Ne. V Mezné u Pelhřimova i při vrácení na domluveném místě netankuješ ani nemyješ. Na samoobslužné '
     'pobočce ve Velkých Němčicích u Brna plnou nádrž taky nepotřebuješ – jen motorku vrať umytou a hlídej, aby nesvítila rezerva.', G),
 (I, 'answer', 'en', '@FULL', "No. In Mezná near Pelhřimov, and when you return the bike at an agreed place, you don't refuel or wash it. "
     "At the self-service branch in Velké Němčice near Brno you don't need a full tank either – just return the bike washed and make sure the reserve light isn't on.", G),
 (I, 'answer', 'de', '@FULL', 'Nein. In Mezná bei Pelhřimov und bei der Rückgabe an einem vereinbarten Ort musst du weder tanken noch waschen. '
     'An der Selbstbedienungsfiliale in Velké Němčice bei Brno musst du auch nicht volltanken – bring das Motorrad nur gewaschen zurück und achte darauf, dass die Reserveanzeige nicht leuchtet.', G),
 (I, 'answer', 'es', '@FULL', 'No. En Mezná, cerca de Pelhřimov, y si devuelves la moto en un lugar acordado, no tienes que repostar ni lavarla. '
     'En la sucursal de autoservicio de Velké Němčice, cerca de Brno, tampoco hace falta el depósito lleno: solo devuelve la moto lavada y asegúrate de que no esté encendida la luz de reserva.', G),
 (I, 'answer', 'fr', '@FULL', "Non. À Mezná, près de Pelhřimov, et si tu rends la moto à un endroit convenu, tu n'as ni à faire le plein ni à la laver. "
     "À l'agence en libre-service de Velké Němčice, près de Brno, le plein n'est pas nécessaire non plus : rends simplement la moto lavée et veille à ce que le voyant de réserve ne soit pas allumé.", G),
 (I, 'answer', 'nl', '@FULL', 'Nee. In Mezná bij Pelhřimov en bij teruggave op een afgesproken plek hoef je niet te tanken of te wassen. '
     'Bij de zelfbedieningsvestiging in Velké Němčice bij Brno hoeft de tank ook niet vol – lever de motor alleen gewassen in en let erop dat het reservelampje niet brandt.', G),
 (I, 'answer', 'pl', '@FULL', 'Nie. W oddziale Mezná koło Pelhřimova i przy zwrocie w umówionym miejscu nie tankujesz ani nie myjesz. '
     'W samoobsługowym oddziale Velké Němčice koło Brna pełny bak też nie jest potrzebny – oddaj tylko motocykl umyty i pilnuj, żeby nie świeciła się kontrolka rezerwy.', G),
 (I, 'question', 'uk', None, 'Чи маю повертати мотоцикл з повним баком і чистим?', G),
 (I, 'answer', 'uk', None, 'Ні. У Mezná біля Пельгржимова і при поверненні в узгодженому місці ти не заправляєш і не миєш мотоцикл. '
     'У філії самообслуговування Velké Němčice біля Брна повний бак теж не потрібен – лише поверни мотоцикл вимитим і стеж, щоб не світився індикатор резерву.', G),
]
I = '02b6cfc8-83af-4887-8f5f-a62214f64f2a'   # Jaké palivo mám tankovat?
G = 'v Mezné u Pelhřimova netankuješ vůbec'
FAQ += [
 (I, 'answer', 'cs', 'Při vrácení nemusíš mít plnou nádrž, jen ať nesvítí kontrolka rezervy.',
     'Při vrácení nemusíš mít plnou nádrž: v Mezné u Pelhřimova netankuješ vůbec, na samoobslužné pobočce ve Velkých Němčicích u Brna jen hlídej, aby nesvítila kontrolka rezervy.', G),
 (I, 'answer', 'en', "When returning the bike, you don't need to have a full tank, just make sure the reserve light isn't on.",
     "When returning the bike, you don't need a full tank: in Mezná near Pelhřimov you don't refuel at all, and at the self-service branch in Velké Němčice near Brno just make sure the reserve light isn't on.", G),
 (I, 'answer', 'de', 'Bei der Rückgabe musst du den Tank nicht vollständig gefüllt haben, nur die Reserveanzeige darf nicht leuchten.',
     'Bei der Rückgabe muss der Tank nicht voll sein: In Mezná bei Pelhřimov musst du gar nicht tanken, an der Selbstbedienungsfiliale in Velké Němčice bei Brno achte nur darauf, dass die Reserveanzeige nicht leuchtet.', G),
 (I, 'answer', 'es', 'Al devolver la moto no necesitas tener el depósito lleno, solo que no se encienda la luz de reserva.',
     'Al devolver la moto no necesitas el depósito lleno: en Mezná, cerca de Pelhřimov, no tienes que repostar en absoluto, y en la sucursal de autoservicio de Velké Němčice, cerca de Brno, solo asegúrate de que no esté encendida la luz de reserva.', G),
 (I, 'answer', 'fr', "Au retour, tu n'as pas besoin d'avoir un réservoir plein, il suffit que le témoin de réserve ne s'allume pas.",
     "Au retour, tu n'as pas besoin d'un réservoir plein : à Mezná, près de Pelhřimov, tu n'as pas du tout à faire le plein, et à l'agence en libre-service de Velké Němčice, près de Brno, veille simplement à ce que le témoin de réserve ne soit pas allumé.", G),
 (I, 'answer', 'nl', 'Bij retournering hoef je niet met een volle tank terug te komen, zolang het reservelampje maar niet brandt.',
     'Bij het terugbrengen hoeft de tank niet vol te zijn: in Mezná bij Pelhřimov hoef je helemaal niet te tanken, en bij de zelfbedieningsvestiging in Velké Němčice bij Brno let je er alleen op dat het reservelampje niet brandt.', G),
 (I, 'answer', 'pl', 'Przy zwracaniu nie musisz mieć pełnego baku, tylko żeby nie świeciła się lampka rezerwy.',
     'Przy zwrocie nie musisz mieć pełnego baku: w oddziale Mezná koło Pelhřimova w ogóle nie tankujesz, a w samoobsługowym oddziale Velké Němčice koło Brna pilnuj tylko, żeby nie świeciła się lampka rezerwy.', G),
 (I, 'question', 'uk', None, 'Яке пальне мені заправляти?', G),
 (I, 'answer', 'uk', None, '<p>Завжди пальне, <strong>передбачене виробником</strong> конкретного мотоцикла – знайдеш його в посібнику користувача, '
     'зазвичай і біля кришки бака (у наших мотоциклів це зазвичай бензин Natural 95). Якщо заправиш неправильне пальне, орендар у повному обсязі '
     'оплачує всі витрати на відкачування пального й ремонт двигуна. Під час повернення повний бак не потрібен: у Mezná біля Пельгржимова взагалі не '
     'заправляєш, а у філії самообслуговування Velké Němčice біля Брна лише стеж, щоб не світився індикатор резерву.</p>', G),
]

# ---------------------------------------------------------------- pages_overlay (app_settings)
# Leaves whose PHP CS default the web workstream changed; new = its lang/pages_<lang>.php string (gen.py loads it).
OVERLAY_PATHS = [
 ('jak_pujcit_vraceni_pujcovna', ['faq', 'items', '1', 'a']),
 ('jak_pujcit_vraceni_jinde', ['faq', 'items', '1', 'a']),
 ('jak_pujcit_postup', ['process', 'steps', '11', 'text']),
 ('jak_pujcit_dokumenty', ['handover', 'items', '2']),
 ('jak_pujcit_dokumenty', ['payments', 'rows', '2', '1']),
]

# ---------------------------------------------------------------- header_banner
BANNER_CS = 'V zimním období od 1.11.2026 do 25.3.2027 zavřeno.'
BANNER_TR = {
 'en': 'Closed for the winter season from 1 November 2026 to 25 March 2027.',
 'de': 'In der Wintersaison vom 1. November 2026 bis 25. März 2027 geschlossen.',
 'es': 'Cerrado durante la temporada de invierno, del 1 de noviembre de 2026 al 25 de marzo de 2027.',
 'fr': "Fermé pendant la saison d'hiver, du 1er novembre 2026 au 25 mars 2027.",
 'nl': 'Gesloten in het winterseizoen, van 1 november 2026 tot en met 25 maart 2027.',
 'pl': 'Nieczynne w sezonie zimowym, od 1 listopada 2026 do 25 marca 2027.',
 'uk': 'Зачинено на зимовий сезон: з 1 листопада 2026 до 25 березня 2027.',
}
