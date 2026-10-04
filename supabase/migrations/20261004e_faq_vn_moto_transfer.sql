-- =============================================================================
-- FAQ: motorka z Mezné do Velkých Němčic přistavit nelze
-- Migrace: 20261004e_faq_vn_moto_transfer.sql (5/5; DATOVÁ, bez změn schématu)
--
-- Zadání majitele 2026-10-04: „Mohu si zvolit motorku, která je v Mezné, a nechat
-- si ji přistavit do Velkých Němčic? Ne, nelze. V Němčicích jsou jen motorky,
-- které jsou tam uvedené; časem (střednědobě / dlouhodobě) se mění, ale nelze
-- si zvolit, že tam bude konkrétní motorka na určitý den přistavená.“
-- Nová otázka v kategorii „Přistavení“ (delivery, sort 6 — hned za 5b1e0c7a…c03
-- „Nabízíte přistavení … u samoobslužné pobočky?“), 7 překladů; pevné id +
-- ON CONFLICT DO NOTHING = idempotentní. Čte web (FAQ + JSON-LD), AI agenti
-- (get_faq + znalostní báze — ai_kb_version se zvedne, ať se nečeká na TTL).
-- Kód schránky u brány se ve FAQ NEUVÁDÍ (veřejné).
-- =============================================================================

INSERT INTO public.faq_items (id, category_key, category_label, question, answer, sort_order, featured_home, published, translations)
VALUES ('5b1e0c7a-3f2d-4c8e-9a61-2d7f4e8b1c05'::uuid, 'delivery', 'Přistavení',
  $t$Můžu si vybrat motorku z Mezné a nechat si ji přistavit do Velkých Němčic?$t$,
  $t$Ne, to nejde. Ve Velkých Němčicích si můžete půjčit jen motorky, které jsou u této pobočky uvedené v nabídce. Jejich složení se časem mění — ve střednědobém až dlouhodobém horizontu motorky mezi pobočkami obměňujeme — ale není možné objednat si, aby byla konkrétní motorka z Mezné na určitý den přistavená do Velkých Němčic. Které motorky na pobočce právě jsou, uvidíte v rezervaci po výběru pobočky.$t$,
  6, false, true,
  jsonb_build_object(
    'en', jsonb_build_object('question', $t$Can I choose a motorcycle from Mezná and have it brought to Velké Němčice?$t$,
      'answer', $t$No, that is not possible. In Velké Němčice you can only rent the motorcycles listed for this branch. The lineup changes over time — we rotate motorcycles between branches in the medium to long term — but it is not possible to have a specific motorcycle from Mezná brought to Velké Němčice for a particular day. You can see which motorcycles are currently at the branch in the booking form after selecting the branch.$t$),
    'de', jsonb_build_object('question', $t$Kann ich ein Motorrad aus Mezná auswählen und es mir nach Velké Němčice bringen lassen?$t$,
      'answer', $t$Nein, das ist nicht möglich. In Velké Němčice können nur die Motorräder gemietet werden, die bei dieser Filiale im Angebot aufgeführt sind. Das Angebot ändert sich mit der Zeit — mittel- bis langfristig tauschen wir die Motorräder zwischen den Filialen aus —, es ist jedoch nicht möglich, ein bestimmtes Motorrad aus Mezná für einen bestimmten Tag nach Velké Němčice bringen zu lassen. Welche Motorräder gerade in der Filiale stehen, ist bei der Buchung nach Auswahl der Filiale zu sehen.$t$),
    'nl', jsonb_build_object('question', $t$Kan ik een motor uit Mezná kiezen en die naar Velké Němčice laten brengen?$t$,
      'answer', $t$Nee, dat kan niet. In Velké Němčice zijn alleen de motoren te huur die bij deze vestiging in het aanbod staan. Dat aanbod verandert in de loop van de tijd — op middellange tot lange termijn wisselen we motoren uit tussen de vestigingen — maar het is niet mogelijk om een bepaalde motor uit Mezná op een bepaalde dag naar Velké Němčice te laten brengen. Welke motoren er op dit moment bij een vestiging staan, is bij het reserveren te zien nadat die vestiging is gekozen.$t$),
    'es', jsonb_build_object('question', $t$¿Se puede elegir una moto de Mezná y pedir que la lleven a Velké Němčice?$t$,
      'answer', $t$No, no es posible. En Velké Němčice solo se pueden alquilar las motos que figuran en la oferta de esta sucursal. La oferta cambia con el tiempo —a medio y largo plazo rotamos las motos entre las sucursales—, pero no se puede pedir que una moto concreta de Mezná se traslade a Velké Němčice para un día determinado. Las motos que hay en este momento en cada sucursal aparecen en la reserva al seleccionarla.$t$),
    'fr', jsonb_build_object('question', $t$Peut-on choisir une moto de Mezná et la faire amener à Velké Němčice ?$t$,
      'answer', $t$Non, ce n'est pas possible. À Velké Němčice, seules les motos figurant dans l'offre de cette agence peuvent être louées. Cette sélection évolue avec le temps — à moyen et long terme, nous faisons tourner les motos entre les agences — mais il n'est pas possible de demander qu'une moto précise de Mezná soit amenée à Velké Němčice pour une date donnée. Les motos actuellement présentes à l'agence s'affichent dans la réservation une fois l'agence choisie.$t$),
    'pl', jsonb_build_object('question', $t$Czy mogę wybrać motocykl z oddziału Mezná i zamówić jego podstawienie do oddziału Velké Němčice?$t$,
      'answer', $t$Nie, nie jest to możliwe. W oddziale Velké Němčice można wypożyczyć tylko motocykle, które znajdują się w ofercie tego oddziału. Oferta ta z czasem się zmienia — w perspektywie średnio- i długoterminowej przenosimy motocykle między oddziałami — ale nie można zamówić podstawienia konkretnego motocykla z oddziału Mezná do Velké Němčice na określony dzień. Jakie motocykle są aktualnie w oddziale, można sprawdzić podczas rezerwacji po wybraniu oddziału.$t$),
    'uk', jsonb_build_object('question', $t$Чи можна вибрати мотоцикл із філії Mezná й замовити його доставку до Velké Němčice?$t$,
      'answer', $t$Ні, це неможливо. У Velké Němčice можна орендувати лише мотоцикли, які зазначені в пропозиції цієї філії. Їхній склад із часом змінюється — у середньо- та довгостроковій перспективі ми обмінюємо мотоцикли між філіями, — але замовити, щоб конкретний мотоцикл із Mezná на певний день доставили до Velké Němčice, не можна. Які мотоцикли зараз є у філії, видно в бронюванні після вибору філії.$t$)
  ))
ON CONFLICT (id) DO NOTHING;

-- Znalostní báze AI agentů: nová verze → okamžité znovunačtení FAQ.
DO $$
BEGIN
  IF to_regclass('public.app_settings') IS NOT NULL THEN
    INSERT INTO public.app_settings (key, value)
    VALUES ('ai_kb_version', to_jsonb((extract(epoch FROM clock_timestamp()) * 1000)::bigint))
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'ai_kb_version: %', SQLERRM;
END $$;
