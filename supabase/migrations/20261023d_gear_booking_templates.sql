-- =============================================================================
-- 2026-10-23 (d): Výpůjčka JEN výbavy — editovatelné e-mailové šablony (Velín)
-- Navazuje na 20261023a (booking_kind='gear'). Pokračuje 20261023da (smlouva o nájmu
-- výbavy) a 20261023db (konečná faktura + účetní záznam).
--
-- send-booking-email / send-cancellation-email u rezervace s booking_kind='gear'
-- renderují `gear_<typ>` (slugsToTry web_gear_<typ> → gear_<typ>; logovaný slug zůstává
-- podle typu kvůli deduplikaci). Zde se zakládá 9 výchozích CZ šablon (tykání, jen vnitřní
-- tělo — hlavičku/patičku přidá edge wrapInBrandedLayout, ostatní jazyky AI překlad):
--   gear_booking_reserved        ← booking_reserved          (přílohy Smlouva + VOP)
--   gear_invoice_payment_receipt ← invoice_payment_receipt   (ZF + DP, CTA doklad totožnosti)
--   gear_booking_missing_docs    ← booking_missing_docs
--   gear_booking_abandoned       ← booking_abandoned (nezaplacená, web 4 h)
--   gear_door_codes              ← door_codes (brána → šatna → postup ve {{door_codes_block}})
--   gear_booking_modified        ← booking_modified ({{changes_block}})
--   gear_booking_cancelled       ← booking_cancelled (send-cancellation-email, Dobropis)
--   gear_booking_completed       ← booking_completed (KF, Google recenze, BEZ slevového kódu)
--   handover_protocol_gear_sent  ← handover_protocol_sent (send-email ze submit-handover-protocol;
--                                   proměnné customer_name, booking_number, gear_period)
-- Texty univerzální pro obslužnou (Mezná: předání osobně, doklad ověříme na místě) i
-- samoobslužnou pobočku (Velké Němčice: kódy brána + šatna, protokol a potvrzení vrácení
-- na displeji). Doklady u výbavy = jen doklad totožnosti (OP obě strany / pas) + 18 let.
-- Bez věrnostních slev, promo kódů a kódu VRACENI (rozhodnutí majitele).
-- Proměnné jen z DESIGN §3.3; sloupec `variables` se plní automaticky z předmětu a těla
-- (pořadí výskytu) → Velín ukazuje čipy proměnných. `description` = kdy se šablona posílá.
-- Idempotentní: ON CONFLICT (slug) DO NOTHING — text upravený ve Velínu se nepřepíše.
-- =============================================================================

DO $$
DECLARE
  -- společné kusy HTML (styl stávajících šablon: 20260705, 20260717)
  h2  text := '<h2 style="margin:0 0 6px;font-size:20px;color:#0f1a14">';
  h3  text := '<h3 style="color:#1a2e22;font-size:15px;margin:24px 0 8px">';
  lnk text := ' style="color:#2563eb"';
  ba  text := '<div style="text-align:center;margin:24px 0"><a style="display:inline-block;background:#74FB71;color:#1a2e22;padding:14px 28px;border-radius:25px;text-decoration:none;font-weight:800;font-size:15px" href="';
  bz  text := '</a></div>';
  tl  text := '<tr><td style="padding:8px 0;color:#16a34a;font-weight:600;font-size:13px">';
  tr_ text := '</td><td style="padding:8px 0;text-align:right;color:#0f1a14;font-weight:700">';
  te  text := '</td></tr>';
  hi  text := '<p>Ahoj {{customer_name}},</p>';
  bye text := '<p>Tým MotoGo24</p>';
  sm  text;   -- souhrn rezervace bez ceny
  sp  text;   -- souhrn rezervace s cenou
  doc text := 'občanský průkaz (obě strany) nebo cestovní pas — řidičák nepotřebuješ, musí ti být aspoň 18 let';
BEGIN
  sm := '<table style="width:100%;border-collapse:collapse;margin:0 0 14px">'
     || tl || 'Číslo rezervace' || tr_ || '#{{booking_number}}' || te
     || tl || 'Pobočka' || tr_ || '{{branch_name}}<br><span style="font-weight:400;font-size:13px;color:#374151">{{branch_address}}</span>' || te
     || tl || 'Termín' || tr_ || '{{gear_period}} ({{gear_days}})' || te;
  sp := sm || tl || 'Cena celkem' || tr_ || '{{total_price}} Kč' || te || '</table>'
     || '<p style="margin:0 0 6px;font-weight:700;color:#0f1a14">Výbava</p>{{gear_items_block}}';
  sm := sm || '</table><p style="margin:0 0 6px;font-weight:700;color:#0f1a14">Výbava</p>{{gear_items_block}}';

  INSERT INTO public.email_templates (slug, name, subject, body_html, description, variables, active, attachments)
  SELECT t.slug, t.name, t.subject, t.body, t.descr,
         ARRAY(SELECT x.v FROM (SELECT r.m[1] AS v, min(r.n) AS n
                                  FROM regexp_matches(t.subject || ' ' || t.body, '\{\{([a-z_]+)\}\}', 'g') WITH ORDINALITY AS r(m, n)
                                 GROUP BY r.m[1]) x ORDER BY x.n),
         true, t.att::jsonb
  FROM (VALUES
  ('gear_booking_reserved', 'Výpůjčka výbavy — potvrzení rezervace',
   'Výpůjčka výbavy č. {{booking_number}} je potvrzená — MotoGo24',
   h2 || 'Výpůjčka výbavy je potvrzená</h2>' || hi
   || '<p>děkujeme za rezervaci! Tvoje výpůjčka motorkářské výbavy č. <strong>#{{booking_number}}</strong> je zaplacená a potvrzená.</p>'
   || sp || '{{door_codes_block}}'
   || h3 || 'Jak si výbavu vyzvedneš</h3>'
   || '<p><strong>Obslužná pobočka:</strong> výbavu ti předáme osobně a společně podepíšeme předávací protokol. Pokud jsi doklad totožnosti nenahrál/a předem, vezmi ho s sebou — ověříme ho na místě.</p>'
   || '<p><strong>Samoobslužná pobočka:</strong> výbavu si vyzvedneš sám/sama pomocí přístupových kódů (brána a šatna). Pokud už máš ověřený doklad totožnosti, kódy najdeš výše a dorazí ti i samostatným e-mailem; jinak ti je pošleme hned po jeho ověření — bez něj se dovnitř nedostaneš. Výbavu si vezmi ze šatny, zavři dveře a na dotykovém displeji potvrď velikosti a podepiš předávací protokol (jako identifikaci zadáš kód šatny).</p>'
   || '<p>K výpůjčce stačí doklad totožnosti: ' || doc || '. Pokud jsi ho ještě nenahrál/a, nahraj ho <a href="{{docs_url}}"' || lnk || '>tady</a>.</p>'
   || h3 || 'Vrácení</h3>'
   || '<p>Výbavu vrať nejpozději poslední den výpůjčky ({{end_date}}) na stejnou pobočku. Na obslužné pobočce ji předáš obsluze, na samoobslužné ji ulož zpět do šatny (bránu i šatnu otevřeš stejnými kódy), zavři dveře a na displeji potvrď, že vracíš všechnu výbavu.</p>'
   || '<p>Termín i velikosti můžeš upravit v sekci <a href="{{manage_url}}"' || lnk || '>Upravit rezervaci</a>. V příloze najdeš smlouvu o nájmu výbavy a obchodní podmínky.</p>'
   || '<p>Těšíme se na tebe!</p>' || bye,
   'Potvrzení zaplacené výpůjčky výbavy (bez motorky) — posílá se jako booking_reserved (po platbě a dokladu, příp. při převzetí). Univerzální text pro obslužnou i samoobslužnou pobočku; kódy ve {{door_codes_block}}.',
   '["Smlouva","VOP"]'),

  ('gear_invoice_payment_receipt', 'Výpůjčka výbavy — platba přijata (ZF + DP)',
   'Platba za výpůjčku výbavy č. {{booking_number}} přijata — MotoGo24',
   h2 || 'Platba přijata — děkujeme!</h2>' || hi
   || '<p>tvoje platba za výpůjčku výbavy č. <strong>#{{booking_number}}</strong> dorazila. V příloze najdeš zálohovou fakturu a doklad o přijaté platbě.</p>'
   || sp
   || '<div style="background:#f1faf7;border:1px solid #d4e8e0;border-radius:12px;padding:16px;margin:20px 0"><p style="margin:0 0 6px;font-weight:700">Ještě jeden krok: doklad totožnosti</p>'
   || '<p style="margin:0">Stačí ' || doc || '. Pokud už máš doklad u nás ověřený, nemusíš nic dělat.</p></div>'
   || ba || '{{docs_url}}">Nahrát doklad totožnosti' || bz
   || '<p>Po ověření dokladu ti pošleme potvrzení rezervace se smlouvou o nájmu výbavy. Na samoobslužné pobočce ti teprve potom vydáme přístupové kódy (brána a šatna) — bez ověřeného dokladu se dovnitř nedostaneš. Na obslužné pobočce ti doklad jinak zkontrolujeme při vyzvednutí.</p>'
   || bye,
   'Po zaplacení výpůjčky výbavy (typ invoice_payment_receipt) — ZF + DP v příloze, výzva k nahrání dokladu totožnosti ({{docs_url}}).',
   '["ZF","DP"]'),

  ('gear_booking_missing_docs', 'Výpůjčka výbavy — připomínka dokladu totožnosti',
   'Nahraj doklad totožnosti k výpůjčce výbavy č. {{booking_number}} — MotoGo24',
   hi || '<p>tvoje výpůjčka výbavy č. <strong>#{{booking_number}}</strong> na <strong>{{gear_period}}</strong> ({{branch_name}}) je zaplacená — děkujeme!</p>'
   || '<p>Chybí nám ještě tvůj doklad totožnosti: ' || doc || '. Nahrání zabere jen chvilku.</p>'
   || ba || '{{docs_url}}">Nahrát doklad totožnosti' || bz
   || '<p>Na samoobslužné pobočce je nahrání nutné — bez ověřeného dokladu ti přístupové kódy nevydáme a dovnitř se nedostaneš. Na obslužné pobočce ti ho jinak zkontrolujeme až při vyzvednutí.</p>'
   || bye,
   'Připomínka (cron send_abandoned_booking_emails, zaplacená výpůjčka výbavy bez ověřeného dokladu totožnosti) — CTA {{docs_url}}.',
   '[]'),

  ('gear_booking_abandoned', 'Výpůjčka výbavy — nedokončená rezervace',
   'Dokonči výpůjčku výbavy č. {{booking_number}} — MotoGo24',
   hi || '<p>díky za zájem o půjčení výbavy! Vypadá to, že jsi rezervaci č. <strong>#{{booking_number}}</strong> nedokončil/a — ještě není zaplacená.</p>'
   || sp || '<p>Dokončit ji můžeš jedním klikem, vyplněné údaje zůstaly uložené:</p>'
   || ba || '{{pay_url}}">Dokončit a zaplatit' || bz
   || '<p style="color:#dc2626;font-weight:700">Nezaplacenou rezervaci držíme jen 4 hodiny od jejího vytvoření, potom se automaticky zruší a výbava se uvolní.</p>'
   || bye,
   'Nezaplacená webová výpůjčka výbavy (cron send_abandoned_booking_emails, ~15 min po vytvoření) — CTA {{pay_url}} = /pujceni-obleceni?resume=<id>.',
   '[]'),

  ('gear_door_codes', 'Výpůjčka výbavy — přístupové kódy',
   'Přístupové kódy k výpůjčce výbavy č. {{booking_number}} — MotoGo24',
   hi || '<p>k tvé výpůjčce výbavy č. <strong>#{{booking_number}}</strong> ({{gear_period}}, {{branch_name}}) jsou připravené přístupové kódy.</p>'
   || '{{door_codes_block}}'
   || '<p>Na obslužné pobočce je při vyzvednutí stačí nahlásit obsluze, na samoobslužné pobočce postupuj podle kroků výše. Kód šatny platí po celou dobu výpůjčky.</p>'
   || '<p>Při vrácení na samoobslužné pobočce ulož výbavu zpět do šatny (bránu i šatnu otevřeš stejnými kódy), zavři dveře a na displeji potvrď, že vracíš všechnu výbavu. Na obslužné pobočce ji předáš obsluze.</p>'
   || '<p>Těšíme se na tebe.</p>' || bye,
   'Vydané kódy k výpůjčce výbavy (send_door_codes_email) — jen brána + šatna, nikdy kód motorky; postup ve {{door_codes_block}}.',
   '[]'),

  ('gear_booking_modified', 'Výpůjčka výbavy — úprava rezervace',
   'Výpůjčka výbavy č. {{booking_number}} byla upravena — MotoGo24',
   hi || '<p>tvoje výpůjčka výbavy č. <strong>#{{booking_number}}</strong> byla upravena. Přehled změn:</p>'
   || '{{changes_block}}'
   || '<p style="margin:16px 0 6px;font-weight:700;color:#0f1a14">Aktuální podoba rezervace</p>'
   || sp || '{{door_codes_block}}'
   || '<p>Pokud se změnila cena, doklad o doplatku nebo vratce (dobropis) najdeš v příloze, případně ti ho pošleme samostatně.</p>'
   || '<p>Další úpravy můžeš udělat v sekci <a href="{{manage_url}}"' || lnk || '>Upravit rezervaci</a>.</p>'
   || bye,
   'Změna výpůjčky výbavy (termín přes trigger booking_modified; velikosti/kusy přes gear RPC s changes.gear) — přehled ve {{changes_block}}.',
   '[]'),

  ('gear_booking_cancelled', 'Výpůjčka výbavy — storno',
   'Výpůjčka výbavy č. {{booking_number}} byla zrušena — MotoGo24',
   hi || '<p>potvrzujeme, že tvoje výpůjčka výbavy č. <strong>#{{booking_number}}</strong> ({{gear_period}}, {{branch_name}}) byla zrušena.</p>'
   || '<p>Důvod: {{cancellation_reason}}</p>'
   || '<p>Pokud byla výpůjčka zaplacená a podle storno podmínek ti náleží vrácení peněz, pošleme ti je zpět — při platbě kartou obvykle do 5–7 pracovních dnů. Dobropis na vracenou částku najdeš v příloze.</p>'
   || '<p>Kdybys chtěl/a výbavu půjčit v jiném termínu, novou rezervaci uděláš <a href="{{site_url}}/pujceni-obleceni"' || lnk || '>na webu</a>.</p>'
   || bye,
   'Storno výpůjčky výbavy (send-cancellation-email) — Dobropis v příloze. Částku vratky edge zatím předává jen jako {{refund_amount}}/{{refund_percent}} (prázdné při 0) — proto text bez částky.',
   '["Dobropis"]'),

  ('gear_booking_completed', 'Výpůjčka výbavy — poděkování po vrácení (KF)',
   'Díky za výpůjčku výbavy č. {{booking_number}} — MotoGo24',
   hi || '<p>díky, že sis výbavu půjčil/a u MotoGo24! Výpůjčka č. <strong>#{{booking_number}}</strong> ({{gear_period}}) je ukončená a v příloze ti posíláme konečnou fakturu.</p>'
   || '<p>Pokud bychom při kontrole vrácené výbavy zjistili chybějící kus nebo poškození nad rámec běžného opotřebení, ozveme se ti.</p>'
   || '<p>Budeme moc rádi za tvoje hodnocení na <a href="{{google_review_url}}" style="display:inline-block;background:#74FB71;color:#0a1f15;font-size:12px;font-weight:700;text-decoration:none;padding:6px 14px;border-radius:14px;margin:0 4px">Google</a> — pomůže nám i dalším motorkářům.</p>'
   || '<p>Těšíme se na další jízdu — třeba i s naší <a href="{{site_url}}/katalog"' || lnk || '>motorkou</a>.</p>'
   || bye,
   'Po dokončení výpůjčky výbavy (vznik KF → trg_send_booking_completed_email) — KF v příloze, odkaz na Google recenze, bez slevového kódu VRACENI.',
   '["KF"]'),

  ('handover_protocol_gear_sent', 'Výpůjčka výbavy — předávací protokol',
   'Předávací protokol k výpůjčce výbavy č. {{booking_number}} — MotoGo24',
   '<h2 style="color:#1a8a18;font-size:18px;margin-top:0">Předávací protokol — výpůjčka výbavy</h2>' || hi
   || '<p>v příloze ti posíláme předávací protokol k výpůjčce výbavy č. <strong>#{{booking_number}}</strong> ({{gear_period}}). Najdeš v něm převzaté kusy výbavy a jejich velikosti.</p>'
   || '<p>Protokol je elektronicky podepsaný. Výbavu vrať nejpozději poslední den výpůjčky na stejnou pobočku.</p>'
   || bye,
   'Podepsaný předávací protokol jen výbavy (send-email ze submit-handover-protocol / Velín, příloha = protokol; při chybějící šabloně fallback handover_protocol_sent).',
   '[]')
  ) AS t(slug, name, subject, body, descr, att)
  ON CONFLICT (slug) DO NOTHING;
END $$;

NOTIFY pgrst, 'reload schema';
