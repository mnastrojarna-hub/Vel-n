/* ===== MotoGo24 app v2 · shared/rank-theme.js — paste VERBATIM as the first lines INSIDE renderVals() (plain function
   declarations, no globals, no `this`). Generated table: gen/gen.js from research/rankTheme.js — values match rank-theme.css.
   rankTheme(level, points?, lang?) → tokens + Czech copy for holes.  points = effective loyalty points (default = sample: 2L−1, i.e. 1 b. to next).
   lang (board prop "jazyk", 8 langs; default cs): aria (logo ring / rank chip button name) is localized; nameL, tierL, mottoL, mottoAriaL,
   chipShortL carry the localized copy (rank names = translations_ext_35_loyalty_ranks.dart; tier names + mottos = návrh) — name/motto stay Czech.
   Root: class = rk.cls ("rk rk-3 t-road") + board classes.  Prices NEVER read anything from here except rk.pct.
   Step inside the tier (owner 2026-10-15): rk.step / rk.steps drive nothing in CSS (the .rk-N class does) — they feed copy:
   stepLabel "Silnice 3/5", marksLine "3 pruhy z 5", motto (one line per level, Home header under the greeting) + mottoAria.
   v2.1 (owner 2026-10-15 „žádná růžová ani fialová“): no effect stop is violet/pink (research/rank_colors.md).
   v2.2 RAMP (owner 2026-10-16): all 20 colours = one growing progression (greens → metals → blues deepening → VIP crimson / gold / pearl →
   fiery gold only at 20) = appdesign/sql/20261016_loyalty_colors_ramp.sql (supersedes 20261015_loyalty_colors_no_purple.sql); research/rank_ramp.md. */
function rankTheme(level, points, lang) {
  const T = [["Startér","road","#A3B8A8","#A3B8A8","#5F6B61","#08230F","#A6FF8F","linear-gradient(#A3B8A8,#A3B8A8)","linear-gradient(135deg,#9BD19C,#A1BFA5 33%,#A3B8A8 67%,#A3B8A8)","linear-gradient(135deg,#D1DCD4,#A3B8A8,#A3B8A8,#8B9C8F)","#264132","#A3B8A8","#A3B8A8","#86978A","#458050"],
    ["Jezdec","road","#BDF6D1","#BDF6D1","#536C5C","#08230F","#BDF6D1","linear-gradient(#BDF6D1,#BDF6D1)","linear-gradient(135deg,#ACF9B7,#B8F7CA 33%,#BDF6D1 67%,#BDF6D1)","linear-gradient(135deg,#DEFBE8,#BDF6D1,#BDF6D1,#A1D1B2)","#2A4B39","#BDF6D1","#BDF6D1","#799D86","#4A7E61"],
    ["Motorkář","road","#4ADE80","#4ADE80","#287845","#08230F","#4ADE80","linear-gradient(#4ADE80,#4ADE80)","linear-gradient(135deg,#61EA82,#51E181 33%,#4ADE80 67%,#4ADE80)","linear-gradient(135deg,#A5EFC0,#4ADE80,#4ADE80,#3FBD6D)","#18472C","#4ADE80","#4ADE80","#37A45F","#2E784C"],
    ["Stálý jezdec","road","#00AC7F","#00AC7F","#007859","#08230F","#00AC7F","linear-gradient(#00AC7F,#00AC7F)","linear-gradient(135deg,#31C981,#0EB480 33%,#00AC7F 67%,#00AC7F)","linear-gradient(135deg,#80D6BF,#00AC7F,#00AC7F,#00926C)","#0C3F2C","#00B687","#00AC7F","#00A97C","#1B6C4C"],
    ["Věrný zákazník","road","#0AA2A4","#0AA2A4","#077576","#08230F","#0AA2A4","linear-gradient(#0AA2A4,#0AA2A4)","linear-gradient(135deg,#38C39A,#17ABA1 33%,#0AA2A4 67%,#0AA2A4)","linear-gradient(135deg,#85D1D2,#0AA2A4,#0AA2A4,#098A8B)","#0D3D32","#0BB0B2","#0AA2A4","#0AA2A4","#1E6955"],
    ["Bronzový jezdec","metal","#C2844A","#C2844A","#8C5F35","#1A1405","#C2844A","conic-gradient(from 210deg,#E7CEB7,#C2844A,#9C6B3C,#E7CEB7)","linear-gradient(115deg,#E4C8AE,#CD9A6B 33%,#C2844A 67%,#AF7743)","linear-gradient(135deg,#F0E0D2,#D4B9A0,#B7916D,#9B6A3B)","#2B3823","#C8915D","#C2844A","#C2844A","#576540"],
    ["Stříbrný jezdec","metal","#929496","#929496","#666869","#0B1512","#8E9298","conic-gradient(from 210deg,#CDCECF,#8E9092,#76787A,#CDCECF)","linear-gradient(115deg,#C6C7C8,#9FA1A3 33%,#8B8D90 67%,#7F8184)","linear-gradient(135deg,#E4E4E5,#BFBFC1,#9A9B9C,#757678)","#233B30","#9E9E9E","#929496","#929496","#466959"],
    ["Zlatý jezdec","metal","#E5D376","#E5D376","#72693B","#1A1405","#E5D376","conic-gradient(from 210deg,#F5EDC8,#E5D376,#AC9E59,#F5EDC8)","linear-gradient(115deg,#F3EBC1,#EADB8F 33%,#E5D376 67%,#CEBE6A)","linear-gradient(135deg,#F9F4DD,#E3DBB3,#CDC288,#B7A95E)","#30452A","#E5D376","#E5D376","#A09453","#607C4D"],
    ["Platinový jezdec","metal","#B9BEC6","#B9BEC6","#686A6F","#0B1512","#C3C9D3","conic-gradient(from 210deg,#EEF1F5,#C3CAD5,#9AA3B0,#EEF1F5)","linear-gradient(115deg,#E0E2E5,#C6CAD0 33%,#B9BEC6 67%,#A7ABB2)","linear-gradient(135deg,#EEEFF1,#D0D2D5,#B2B5BA,#94989E)","#294237","#C1C5D1","#B9BEC6","#90949A","#577B6C"],
    ["Diamantový jezdec","jewel","#AEE9FF","#AEE9FF","#506B75","#0A1F33","#AEE9FF","repeating-conic-gradient(from 8deg,rgba(255,255,255,.26) 0 15deg,rgba(255,255,255,0) 15deg 30deg),conic-gradient(from 20deg,#AEE9FF,#A7EDF5,#AEE9FF,#B1DCFF,#AEE9FF)","linear-gradient(135deg,#AEE9FF,#AFE4FF 33%,#B0E0FF 67%,#B1DBFF)","linear-gradient(135deg,#D2F3FF,#CEEEFF,#C9E9FF,#C5E4FF)","#284940","#AEE9FF","#AEE9FF","#739AA8","#4D7E75"],
    ["Prémiový zákazník","jewel","#2CD1D4","#2CD1D4","#197577","#0A1F33","#2CD1D4","repeating-conic-gradient(from 8deg,rgba(255,255,255,.26) 0 15deg,rgba(255,255,255,0) 15deg 30deg),conic-gradient(from 20deg,#2CD1D4,#2CD4BB,#2CD1D4,#52C3DC,#2CD1D4)","linear-gradient(135deg,#2CD1D4,#3DCCD7 33%,#4FC8DB 67%,#60C3DE)","linear-gradient(135deg,#8BE6E7,#8ADFE7,#89D9E6,#88D2E6)","#134539","#2CDFE2","#2CD1D4","#22A3A5","#268171"],
    ["Mistr silnic","jewel","#6EAFFF","#6EAFFF","#446C9E","#0A1F33","#6EAFFF","repeating-conic-gradient(from 8deg,rgba(255,255,255,.26) 0 15deg,rgba(255,255,255,0) 15deg 30deg),conic-gradient(from 20deg,#6EAFFF,#66B7EB,#6EAFFF,#7FA3FF,#6EAFFF)","linear-gradient(135deg,#6EAFFF,#6BB2F8 33%,#69B4F2 67%,#66B7EB)","linear-gradient(135deg,#AFD3FF,#A3D0FA,#98CCF5,#8CC9F0)","#1D3F40","#8ABEFF","#6EAFFF","#5F97DB","#407885"],
    ["Šampion","jewel","#00A1C7","#00A1C7","#00748F","#0A1F33","#00A1C7","repeating-conic-gradient(from 8deg,rgba(255,255,255,.26) 0 15deg,rgba(255,255,255,0) 15deg 30deg),conic-gradient(from 20deg,#00A1C7,#00A5A9,#00A1C7,#2F97D1,#00A1C7)","linear-gradient(135deg,#00A1C7,#00A4BB 33%,#00A6AE 67%,#00A9A2)","linear-gradient(135deg,#73CBE0,#62C7D3,#51C3C6,#40BFB9)","#0C3D37","#00ADD6","#00A1C7","#00A1C7","#167370"],
    ["Veterán MotoGo","jewel","#5087D4","#90A0C3","#3E69A5","#0A1F33","#118BDF","repeating-conic-gradient(from 8deg,rgba(255,255,255,.26) 0 15deg,rgba(255,255,255,0) 15deg 30deg),conic-gradient(from 20deg,#5087D4,#4A91C4,#5087D4,#5E7CD8,#5087D4)","linear-gradient(135deg,#578CD6,#5B88D7 33%,#6085D9 67%,#6481DA)","linear-gradient(135deg,#A3C0E8,#9BB6E6,#93ABE5,#8BA1E3)","#193939","#90A0C3","#5087D4","#5087D4","#1D6A79"],
    ["Elitní jezdec","jewel","#117897","#7FB8C5","#107391","#FFFFFF","#348D79","repeating-conic-gradient(from 8deg,rgba(255,255,255,.26) 0 15deg,rgba(255,255,255,0) 15deg 30deg),conic-gradient(from 20deg,#1B7D9B,#188189,#1B7D9B,#357AA7,#1B7D9B)","linear-gradient(135deg,#117897,#107B8E 33%,#0E7D85 67%,#0D807C)","linear-gradient(135deg,#7CB5C6,#6BAEB8,#5BA7AB,#4AA09D)","#0E3630","#7FB8C5","#117897","#117897","#2A6B53"],
    ["Ambasador","jewel","#165EEB","#5E8CFF","#165EEB","#FFFFFF","#4773FD","repeating-conic-gradient(from 8deg,rgba(255,255,255,.26) 0 15deg,rgba(255,255,255,0) 15deg 30deg),conic-gradient(from 20deg,#286BEC,#4568EF,#286BEC,#4965F0,#286BEC)","linear-gradient(135deg,#165EEB,#1C5CEC 33%,#2259EC 67%,#2857ED)","linear-gradient(135deg,#7FA6F4,#749AF3,#698DF3,#5E81F2)","#0F323D","#5792FF","#2468EC","#165EEB","#316185"],
    ["VIP","vip","#D42020","#F6E7C9","#D01F1F","#7F1D1D","#E13B2B","linear-gradient(135deg,#D8322C,#E46648 50%,#D8322C)","linear-gradient(135deg,#FFF7E6,#FCEED3 33%,#F8E2BD 67%,#F2D5A6)","linear-gradient(135deg,#D42020,#EFA467,#E6A365,#B91C1C)","#2E281D","#F6E7C9","#D52422","#D42020","#734B34"],
    ["VIP Gold","vip","#EDB42D","#EDB42D","#856519","#14100A","#EDB42D","linear-gradient(135deg,#C8952F,#DDB862 50%,#B08429)","linear-gradient(135deg,#F7E4A8,#E6BE4E 33%,#D2A22A 67%,#9C7818)","linear-gradient(135deg,#FFF6D6,#D9C795,#B29953,#8C6A12)","#32401F","#EDB42D","#EDB42D","#B98C23","#747934"],
    ["VIP Platinum","vip","#F5F8FB","#F5F8FB","#676869","#14100A","#FBF7EE","linear-gradient(135deg,#F5F8FB,#F8FAFC 50%,#F5F8FB)","linear-gradient(135deg,#FFFFFF,#F6F8FB 33%,#EAEFF5 67%,#DCE3EC)","linear-gradient(135deg,#E2E8F0,#BAE6FD,#BBF7D0,#FDE68A)","#334B40","#F5F8FB","#F5F8FB","#939597","#607A68"],
    ["Legenda MotoGo","legend","#FF8C1A","#FF8C1A","#9E5710","#241A06","#FF8C00","conic-gradient(from 210deg,#FFE27A,#FFD700,#FF9A1F,#FF6B00,#FFE27A)","linear-gradient(135deg,#FFE27A,#FFD700 33%,#FF9A1F 67%,#FF6B00)","linear-gradient(135deg,#FFF4D6,#FFDD8F,#FFC747,#FFB000)","#353A1C","#FF8C1A","#FF8C1A","#DB7816","#8F6F1E"]];
  const TIERS = [
    { id: 'road', cs: 'Silnice', from: 1, to: 5, icon: 'M12 3l7 3v5.2c0 4.4-3 8-7 9.8-4-1.8-7-5.4-7-9.8V6z' },
    { id: 'metal', cs: 'Kovová liga', from: 6, to: 9, icon: 'M8.5 3h7l-2 5.5h-3zM12 21a6 6 0 1 0 0-12 6 6 0 0 0 0 12zM12 12.6l1 2 2.2.3-1.6 1.5.4 2.2-2-1.1-2 1.1.4-2.2-1.6-1.5 2.2-.3z' },
    { id: 'jewel', cs: 'Liga drahokamů', from: 10, to: 16, icon: 'M6.5 4h11L21 9l-9 11L3 9zM3 9h18M9.5 4 8 9l4 11M14.5 4 16 9l-4 11' },
    { id: 'vip', cs: 'VIP klub', from: 17, to: 19, icon: 'M3 18h18M4.2 15.5 3 7l5 4 4-6.5L16 11l5-4-1.2 8.5z' },
    { id: 'legend', cs: 'Legenda', from: 20, to: 20, icon: 'M12 20.5c-3.6-1-6.2-4.1-6.6-8.3M12 20.5c3.6-1 6.2-4.1 6.6-8.3M6 14.4c-1.7.1-3-.6-3.6-2 1.6-.3 3 .3 3.6 2zM5.4 10.6c-1.6-.3-2.5-1.5-2.6-3 1.5.1 2.5 1.2 2.6 3zM6.2 7.1c-1.3-.9-1.7-2.2-1.3-3.6 1.3.6 1.8 1.9 1.3 3.6zM18 14.4c1.7.1 3-.6 3.6-2-1.6-.3-3 .3-3.6 2zM18.6 10.6c1.6-.3 2.5-1.5 2.6-3-1.5.1-2.5 1.2-2.6 3zM17.8 7.1c1.3-.9 1.7-2.2 1.3-3.6-1.3.6-1.8 1.9-1.3 3.6z' }
  ];
  const LG = ['cs', 'en', 'de', 'es', 'fr', 'nl', 'pl', 'uk'].indexOf(String(lang || 'cs').slice(0, 2)) >= 0 ? String(lang || 'cs').slice(0, 2) : 'cs';
  // localized copy (aria = WCAG name of the logo ring / rank chip; rank names shipped; tiers, steps and mottos = návrh)
  const RNL = {
    en: ['Starter', 'Rider', 'Biker', 'Regular Rider', 'Loyal Customer', 'Bronze Rider', 'Silver Rider', 'Gold Rider', 'Platinum Rider', 'Diamond Rider', 'Premium Customer', 'Road Master', 'Champion', 'MotoGo Veteran', 'Elite Rider', 'Ambassador', 'VIP', 'VIP Gold', 'VIP Platinum', 'MotoGo Legend'],
    de: ['Starter', 'Fahrer', 'Biker', 'Stammfahrer', 'Treuer Kunde', 'Bronze-Fahrer', 'Silber-Fahrer', 'Gold-Fahrer', 'Platin-Fahrer', 'Diamant-Fahrer', 'Premium-Kunde', 'Meister der Straße', 'Champion', 'MotoGo-Veteran', 'Elite-Fahrer', 'Botschafter', 'VIP', 'VIP Gold', 'VIP Platinum', 'MotoGo-Legende'],
    es: ['Principiante', 'Piloto', 'Motero', 'Piloto habitual', 'Cliente fiel', 'Piloto de bronce', 'Piloto de plata', 'Piloto de oro', 'Piloto de platino', 'Piloto de diamante', 'Cliente prémium', 'Maestro de la carretera', 'Campeón', 'Veterano MotoGo', 'Piloto élite', 'Embajador', 'VIP', 'VIP Gold', 'VIP Platinum', 'Leyenda MotoGo'],
    fr: ['Débutant', 'Pilote', 'Motard', 'Pilote régulier', 'Client fidèle', 'Pilote bronze', 'Pilote argent', 'Pilote or', 'Pilote platine', 'Pilote diamant', 'Client premium', 'Maître de la route', 'Champion', 'Vétéran MotoGo', 'Pilote d’élite', 'Ambassadeur', 'VIP', 'VIP Gold', 'VIP Platinum', 'Légende MotoGo'],
    nl: ['Starter', 'Rijder', 'Motorrijder', 'Vaste rijder', 'Trouwe klant', 'Bronzen rijder', 'Zilveren rijder', 'Gouden rijder', 'Platina rijder', 'Diamanten rijder', 'Premium klant', 'Meester van de weg', 'Kampioen', 'MotoGo-veteraan', 'Eliterijder', 'Ambassadeur', 'VIP', 'VIP Gold', 'VIP Platinum', 'MotoGo-legende'],
    pl: ['Starter', 'Jeździec', 'Motocyklista', 'Stały jeździec', 'Wierny klient', 'Brązowy jeździec', 'Srebrny jeździec', 'Złoty jeździec', 'Platynowy jeździec', 'Diamentowy jeździec', 'Klient premium', 'Mistrz szos', 'Czempion', 'Weteran MotoGo', 'Elitarny jeździec', 'Ambasador', 'VIP', 'VIP Gold', 'VIP Platinum', 'Legenda MotoGo'],
    uk: ['Новачок', 'Райдер', 'Мотоцикліст', 'Постійний райдер', 'Вірний клієнт', 'Бронзовий райдер', 'Срібний райдер', 'Золотий райдер', 'Платиновий райдер', 'Діамантовий райдер', 'Преміум-клієнт', 'Майстер доріг', 'Чемпіон', 'Ветеран MotoGo', 'Елітний райдер', 'Амбасадор', 'VIP', 'VIP Gold', 'VIP Platinum', 'Легенда MotoGo']
  };
  const TRL = { cs: ['Silnice', 'Kovová liga', 'Liga drahokamů', 'VIP klub', 'Legenda'], en: ['Road', 'Metal League', 'Gem League', 'VIP club', 'Legend'],
    de: ['Straße', 'Metall-Liga', 'Edelstein-Liga', 'VIP-Club', 'Legende'], es: ['Carretera', 'Liga de Metal', 'Liga de Gemas', 'Club VIP', 'Leyenda'],
    fr: ['Route', 'Ligue métal', 'Ligue des gemmes', 'Club VIP', 'Légende'], nl: ['Weg', 'Metaalliga', 'Edelsteenliga', 'VIP-club', 'Legende'],
    pl: ['Szosa', 'Liga metali', 'Liga klejnotów', 'Klub VIP', 'Legenda'], uk: ['Дорога', 'Металева ліга', 'Ліга самоцвітів', 'VIP-клуб', 'Легенда'] };
  const STL = { cs: 'stupeň {s} z {n}', en: 'step {s} of {n}', de: 'Stufe {s} von {n}', es: 'grado {s} de {n}', fr: 'degré {s} sur {n}', nl: 'trede {s} van {n}', pl: 'stopień {s} z {n}', uk: 'щабель {s} з {n}' };
  const ARL = { cs: 'Věrnostní rank {n}, level {L} z 20, sleva {L} % na rezervace v aplikaci', en: 'Loyalty rank {n}, level {L} of 20, {L} % off bookings in the app',
    de: 'Treue-Rang {n}, Level {L} von 20, {L} % Rabatt auf Buchungen in der App', es: 'Rango de fidelidad {n}, nivel {L} de 20, {L} % de descuento en reservas en la app',
    fr: 'Rang fidélité {n}, niveau {L} sur 20, {L} % de remise sur les réservations dans l’app', nl: 'Loyaliteitsrang {n}, level {L} van 20, {L} % korting op boekingen in de app',
    pl: 'Ranga lojalnościowa {n}, poziom {L} z 20, {L} % rabatu na rezerwacje w aplikacji', uk: 'Ранг лояльності {n}, рівень {L} з 20, знижка {L} % на бронювання в застосунку' };
  const MOL = {
    en: ['Your MotoGo24 journey starts here', 'Next rank: free passenger gear', 'Passenger gear and boots free', 'You’re one of the MotoGo24 regulars', 'Next rank takes you into the Metal League', 'Welcome to the Metal League', 'The silver shine of the Metal League', 'The MotoGo24 gold standard', 'Top of the Metal League', 'Welcome to the Gem League', 'The premium cut of the Gem League', 'The roads know you by name', 'Champion of the Gem League', 'You’ve ridden like few others', 'Elite of the Gem League', 'Next rank takes you into the VIP club', 'Welcome to the MotoGo24 VIP club', 'The gold tier of the VIP club', 'One step from MotoGo Legend', 'Top rank · it doesn’t get higher'],
    de: ['Deine Reise mit MotoGo24 beginnt', 'Nächster Rang: Sozius-Ausrüstung gratis', 'Sozius-Ausrüstung und Stiefel gratis', 'Du gehörst zur MotoGo24-Stammcrew', 'Der nächste Rang bringt dich in die Metall-Liga', 'Willkommen in der Metall-Liga', 'Silberglanz der Metall-Liga', 'Der Goldstandard von MotoGo24', 'Spitze der Metall-Liga', 'Willkommen in der Edelstein-Liga', 'Der Premium-Schliff der Edelstein-Liga', 'Die Straßen kennen deinen Namen', 'Champion der Edelstein-Liga', 'Du bist gefahren wie kaum einer', 'Elite der Edelstein-Liga', 'Der nächste Rang bringt dich in den VIP-Club', 'Willkommen im VIP-Club von MotoGo24', 'Die goldene Stufe des VIP-Clubs', 'Einen Schritt vor der MotoGo-Legende', 'Höchster Rang · höher geht’s nicht'],
    es: ['Tu viaje con MotoGo24 empieza', 'Próximo rango: equipo del pasajero gratis', 'Equipo del pasajero y botas gratis', 'Eres de los habituales de MotoGo24', 'El próximo rango te lleva a la Liga de Metal', 'Bienvenido a la Liga de Metal', 'El brillo plateado de la Liga de Metal', 'El estándar de oro de MotoGo24', 'La cima de la Liga de Metal', 'Bienvenido a la Liga de Gemas', 'La talla prémium de la Liga de Gemas', 'Las carreteras te conocen por tu nombre', 'Campeón de la Liga de Gemas', 'Has rodado como pocos', 'La élite de la Liga de Gemas', 'El próximo rango te lleva al club VIP', 'Bienvenido al club VIP de MotoGo24', 'El nivel dorado del club VIP', 'A un paso de Leyenda MotoGo', 'Rango máximo · más alto no se puede'],
    fr: ['Ton aventure MotoGo24 commence', 'Prochain rang : équipement passager offert', 'Équipement passager et bottes offerts', 'Tu fais partie des habitués MotoGo24', 'Le prochain rang t’ouvre la Ligue métal', 'Bienvenue dans la Ligue métal', 'L’éclat argenté de la Ligue métal', 'L’étalon or de MotoGo24', 'Le sommet de la Ligue métal', 'Bienvenue dans la Ligue des gemmes', 'La taille premium de la Ligue des gemmes', 'Les routes te connaissent par ton nom', 'Champion de la Ligue des gemmes', 'Tu as roulé comme peu d’autres', 'L’élite de la Ligue des gemmes', 'Le prochain rang t’ouvre le club VIP', 'Bienvenue au club VIP MotoGo24', 'Le palier or du club VIP', 'À un pas de Légende MotoGo', 'Rang suprême · impossible de monter plus haut'],
    nl: ['Je reis met MotoGo24 begint', 'Volgende rang: passagiersuitrusting gratis', 'Passagiersuitrusting en laarzen gratis', 'Je hoort bij de vaste MotoGo24-club', 'De volgende rang brengt je in de Metaalliga', 'Welkom in de Metaalliga', 'De zilveren glans van de Metaalliga', 'De gouden standaard van MotoGo24', 'De top van de Metaalliga', 'Welkom in de Edelsteenliga', 'De premium slijpvorm van de Edelsteenliga', 'De wegen kennen je bij naam', 'Kampioen van de Edelsteenliga', 'Je hebt gereden als bijna niemand', 'De elite van de Edelsteenliga', 'De volgende rang brengt je in de VIP-club', 'Welkom in de VIP-club van MotoGo24', 'De gouden laag van de VIP-club', 'Eén stap van MotoGo-legende', 'Hoogste rang · hoger kan niet'],
    pl: ['Twoja droga z MotoGo24 się zaczyna', 'Następna ranga: sprzęt pasażera gratis', 'Sprzęt pasażera i buty gratis', 'Należysz do stałej ekipy MotoGo24', 'Następna ranga wprowadzi cię do Ligi metali', 'Witaj w Lidze metali', 'Srebrny blask Ligi metali', 'Złoty standard MotoGo24', 'Szczyt Ligi metali', 'Witaj w Lidze klejnotów', 'Premium szlif Ligi klejnotów', 'Drogi znają cię po imieniu', 'Czempion Ligi klejnotów', 'Masz przejechane jak mało kto', 'Elita Ligi klejnotów', 'Następna ranga wprowadzi cię do klubu VIP', 'Witaj w klubie VIP MotoGo24', 'Złota warstwa klubu VIP', 'Krok od Legendy MotoGo', 'Najwyższa ranga · wyżej się nie da'],
    uk: ['Твоя дорога з MotoGo24 починається', 'Наступний рівень: екіпірування пасажира безкоштовно', 'Екіпірування пасажира й черевики безкоштовно', 'Ти в постійній команді MotoGo24', 'Наступний рівень відкриє тобі Металеву лігу', 'Ласкаво просимо до Металевої ліги', 'Срібний блиск Металевої ліги', 'Золотий стандарт MotoGo24', 'Вершина Металевої ліги', 'Ласкаво просимо до Ліги самоцвітів', 'Преміум-огранка Ліги самоцвітів', 'Дороги знають тебе на ім’я', 'Чемпіон Ліги самоцвітів', 'Ти проїхав як мало хто', 'Еліта Ліги самоцвітів', 'Наступний рівень відкриє тобі VIP-клуб', 'Ласкаво просимо до VIP-клубу MotoGo24', 'Золотий рівень VIP-клубу', 'Крок до Легенди MotoGo', 'Найвищий рівень · вище вже нікуди']
  };
  const L = Math.max(1, Math.min(20, parseInt(level, 10) || 3));
  const r = T[L - 1];
  const tierIdx = TIERS.findIndex((t) => L >= t.from && L <= t.to);
  const tier = TIERS[tierIdx];
  const from = 2 * L - 2;
  const pts = (points === undefined || points === null) ? (L === 20 ? 38 : 2 * L - 1) : Math.max(from, parseInt(points, 10) || from);
  const isMax = L === 20;
  const next = isMax ? null : { level: L + 1, name: T[L][0], pct: L + 1, from: 2 * L };
  const toNext = next ? Math.max(1, next.from - pts) : 0;
  const pl = (n, a, b, c) => (n === 1 ? a : (n >= 2 && n <= 4 ? b : c));
  const arcPct = isMax ? 100 : Math.max(4, Math.min(100, Math.round((pts - from) / 2 * 100)));
  // tier bar: one segment per point inside the current tier (Silnice 0–9, Kovy 10–17, Drahokamy 18–31, VIP 32–37; Legenda = one full bar)
  const tFrom = 2 * tier.from - 2, tTo = isMax ? 38 : 2 * tier.to;
  const tierBar = [];
  for (let p = tFrom; p < Math.max(tTo, tFrom + 1); p++) {
    const k = p - tFrom;
    tierBar.push({ cls: (p < pts || isMax ? 'on' : (p === pts ? 'nx' : '')) + (k > 0 && p % 2 === 0 ? ' lv' : ''), st: 'animation-delay:' + (200 + k * 45) + 'ms' });
  }
  const nextTier = TIERS[tierIdx + 1] || null;
  // within-tier step: Silnice 1–5 lane marks, Kovy 1–4 rivets, Drahokamy 1–7 facets, VIP 1–3 crowns, Legenda = single level (no marks)
  const st = L - tier.from + 1, sn = tier.to - tier.from + 1;
  const MKN = { road: ['pruh', 'pruhy', 'pruhů'], metal: ['nýt', 'nýty', 'nýtů'], jewel: ['faseta', 'fasety', 'faset'], vip: ['korunka', 'korunky', 'korunek'], legend: ['', '', ''] }[tier.id];
  const MOTTO = ['Tvoje cesta s MotoGo24 začíná', 'Příští rank: výbava spolujezdce zdarma', 'Výbava spolujezdce i boty zdarma', 'Patříš ke stálé partě MotoGo24',
    'Příští rank tě pustí do Kovové ligy', 'Vítej v Kovové lize', 'Stříbrný lesk Kovové ligy', 'Zlatý standard MotoGo24', 'Vrchol Kovové ligy',
    'Vítej v Lize drahokamů', 'Prémiový brus Ligy drahokamů', 'Silnice tě znají jménem', 'Šampion Ligy drahokamů', 'Najeto máš jako málokdo',
    'Elita Ligy drahokamů', 'Příští rank tě pustí do VIP klubu', 'Vítej ve VIP klubu MotoGo24', 'Zlatá vrstva VIP klubu', 'Krok od Legendy MotoGo',
    'Nejvyšší rank · výš už to nejde'];
  const nameL = LG === 'cs' ? r[0] : RNL[LG][L - 1], tierL = TRL[LG][tierIdx], mottoL = LG === 'cs' ? MOTTO[L - 1] : MOL[LG][L - 1];
  const marksLine = sn > 1 ? st + ' ' + pl(st, MKN[0], MKN[1], MKN[2]) + ' z ' + sn : 'jediný rank ligy, bez stupňů';
  const tiers = TIERS.map((t, i) => {
    const rep = T[t.from - 1];
    const cur = i === tierIdx, lock = i > tierIdx;
    return { id: t.id, cs: t.cs, level: t.from, name: rep[0], fromPts: 2 * t.from - 2, cur, lock,
      cls: 'rk-sw' + (cur ? ' cur' : '') + (lock ? ' lock' : ''), swSt: 'background:' + (cur ? r[8] : rep[8]),
      scope: 'rk rk-' + t.from + ' t-' + t.id, sub: cur ? 'Tady jsi' : (lock ? 'od ' + (2 * t.from - 2) + ' b.' : 'Máš za sebou'), icon: t.icon };
  });
  return {
    level: L, name: r[0], pct: L, tier: r[1], tierIdx, tierCs: tier.cs, icon: tier.icon,
    cls: 'rk rk-' + L + ' t-' + r[1],
    hex: r[2], acc: r[3], accLight: r[4], on: r[5], glow: r[6], ringBg: r[7], btnBg: r[8], edgeBg: r[9], chipBg: r[10], chipTx: r[11], uid: r[12], uil: r[13], aura: r[14],
    ringSt: 'background:' + r[7], btnSt: 'background:' + r[8] + ' padding-box,' + r[9] + ' border-box', swSt: 'background:' + r[8],
    glyph: r[1] === 'vip' ? 'crown' : (r[1] === 'legend' ? 'laurel' : ''),
    chip: r[0] + ' · sleva ' + L + ' %', chipShort: r[0] + ' · −' + L + ' %',
    aria: ARL[LG].replace('{n}', nameL).split('{L}').join(String(L)),
    nameL, tierL, mottoL, chipShortL: nameL + ' · −' + L + ' %',
    mottoAriaL: nameL + ' · ' + (sn > 1 ? tierL + ', ' + STL[LG].replace('{s}', st).replace('{n}', sn) : tierL) + '. ' + mottoL,
    levelLine: 'Level ' + L + ' z 20 · sleva ' + L + ' % na každou jízdu v appce',
    from, points: pts, toNext, isMax, next,
    nextLine: isMax ? 'Máš nejvyšší rank' : 'Ještě ' + toNext + ' ' + pl(toNext, 'bod', 'body', 'bodů') + ' → ' + next.name + ' (' + next.pct + ' %)',
    gear: L >= 3,
    gearLine: L >= 3 ? 'Výbava spolujezdce a boty máš zdarma' : 'Od Motorkáře: výbava spolujezdce + boty zdarma',
    gearValue: 'až 1 270 Kč na každé výpůjčce',
    arcPct, arcSt: 'stroke-dasharray:' + arcPct + ' 100',
    tierBar, tierBarLabel: isMax ? 'Celá cesta · 20 z 20' : tier.cs + ' · ' + (pts - tFrom) + ' z ' + (tTo - tFrom) + ' ' + pl(tTo - tFrom, 'bod', 'body', 'bodů'),
    tierBarNext: nextTier ? nextTier.cs + ' od ' + (2 * nextTier.from - 2) + ' b.' : '',
    tiers,
    step: st, steps: sn, stepLabel: sn > 1 ? tier.cs + ' ' + st + '/' + sn : tier.cs, marksLine,
    stepLine: sn > 1 ? tier.cs + ' · stupeň ' + st + ' z ' + sn + ' · ' + marksLine : tier.cs + ' · ' + marksLine,
    motto: MOTTO[L - 1], mottoAria: r[0] + ' · ' + (sn > 1 ? tier.cs + ', stupeň ' + st + ' z ' + sn : tier.cs) + '. ' + MOTTO[L - 1],
    rule: 'Každá dokončená výpůjčka (appka i web): 1–6 dní = 1 bod, 7 a víc dní = 2 body. 2 body = 1 rank a +1 % slevy (max 20 %). Rank ti časem nepropadá. Sleva platí jen na rezervace v aplikaci a sčítá se s promo kódy i poukazy. Od Motorkáře (3) máš výbavu spolujezdce a boty zdarma.'
  };
}
