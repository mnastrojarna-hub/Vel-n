-- =============================================================================
-- 2026-10-23 (da): Výpůjčka JEN výbavy — šablona dokumentu „Smlouva o nájmu výbavy“.
-- Navazuje na 20261023a/d; pokračuje 20261023db (KF + účetnictví).
--
-- document_templates `gear_rental_contract` — výchozí CZ text (editovatelný ve Velínu →
-- Dokumenty; překlady jako u ostatních dokumentů). Fragment s inline styly (RichTextEditor;
-- generate-document fragment obalí stránkou). Proměnné jako rental_contract (vars.ts:
-- customer_*, company_*, start/end_date + _time, total_price(_words), branch_name/address,
-- booking_number, today) + gear proměnné generate-document: {{gear_items_table}}
-- {{gear_period}} {{gear_days}}. generate-document ji volí místo rental_contract, když je
-- rezervace gear (příloha „Smlouva“ v e-mailu gear_booking_reserved). Odpovědnost za
-- výbavu odkazuje na VOP (smluvní krytí škod se na výbavu nevztahuje).
-- ON CONFLICT (type) DO NOTHING — text upravený ve Velínu se nepřepíše. Bez BEGIN/COMMIT.
-- PO NASAZENÍ (před ostrým provozem): Velín → Dokumenty → „Přeložit“ u gear_rental_contract —
-- seed je jen CZ; bez překladu dostane první cizojazyčný zákazník CZ text s upozorněním
-- a překlad se teprve vyžádá na pozadí (generate-document/translation.ts).
-- =============================================================================

INSERT INTO public.document_templates (type, name, content_html, active, version)
VALUES ('gear_rental_contract', 'Smlouva o nájmu výbavy',
'<h1 style="text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:10px;margin:0 0 6px">SMLOUVA O NÁJMU MOTORKÁŘSKÉ VÝBAVY</h1>
<p style="text-align:center;color:#666;margin:0 0 16px">č. {{booking_number}} ze dne {{today}}</p>
<p>Tato smlouva o nájmu movitých věcí – motorkářské výbavy (dále jen „smlouva“) se uzavírá mezi níže uvedenými stranami prostřednictvím prostředků komunikace na dálku, zejména rezervačního formuláře na webových stránkách {{company_web}}.</p>
<table style="width:100%;border-collapse:collapse;margin:10px 0"><tr>
<td style="width:50%;vertical-align:top;padding:10px;background:#f8faf9"><strong>Pronajímatel</strong><br>{{company_name}}<br>{{company_address}}<br>IČO: {{company_ico}}<br>Telefon: {{company_phone}}<br>E-mail: {{company_email}}<br>Není plátce DPH.<br>(dále jen „pronajímatel“)</td>
<td style="width:50%;vertical-align:top;padding:10px;background:#f8faf9"><strong>Nájemce</strong><br>{{customer_name}}<br>Bydliště: {{customer_address}}<br>Datum narození: {{customer_dob}}<br>Číslo OP/pasu: {{customer_id_number}}<br>Telefon: {{customer_phone}}<br>E-mail: {{customer_email}}<br>(dále jen „nájemce“)</td>
</tr></table>
<h2 style="font-size:14px;color:#1a8a18;border-bottom:1px solid #e5e7eb;padding-bottom:4px;margin:16px 0 6px">1. Předmět nájmu</h2>
<p>Pronajímatel přenechává nájemci k dočasnému užívání tuto motorkářskou výbavu (dále jen „výbava“):</p>
{{gear_items_table}}
<p>Výbava se pronajímá samostatně, bez motocyklu. Skutečně předané kusy, jejich velikosti a stav při převzetí zaznamenává předávací protokol, který je nedílnou součástí této smlouvy. Upraví-li nájemce před převzetím velikosti nebo rozsah výbavy, platí údaje z předávacího protokolu.</p>
<h2 style="font-size:14px;color:#1a8a18;border-bottom:1px solid #e5e7eb;padding-bottom:4px;margin:16px 0 6px">2. Doba nájmu a nájemné</h2>
<table style="width:100%;border-collapse:collapse;margin:6px 0">
<tr><td style="width:40%;background:#f8faf9;font-weight:600">Doba nájmu</td><td>{{gear_period}} ({{gear_days}})</td></tr>
<tr><td style="background:#f8faf9;font-weight:600">Nájem platí od</td><td>{{start_date}} {{start_time}}</td></tr>
<tr><td style="background:#f8faf9;font-weight:600">Nájem končí</td><td>{{end_date}} {{end_time}}</td></tr>
<tr><td style="background:#f8faf9;font-weight:600">Nájemné celkem</td><td><strong>{{total_price}} Kč</strong> (slovy: {{total_price_words}})</td></tr>
<tr><td style="background:#f8faf9;font-weight:600">Kauce</td><td>0 Kč (pronajímatel kauci nevyžaduje)</td></tr>
</table>
<p>Smlouva je uzavřena potvrzením rezervace pronajímatelem a úhradou nájemného. Nájemné se řídí ceníkem výbavy platným ke dni uzavření smlouvy a je splatné předem, nejpozději před převzetím výbavy. Nájem začíná převzetím výbavy a končí jejím vrácením pronajímateli.</p>
<h2 style="font-size:14px;color:#1a8a18;border-bottom:1px solid #e5e7eb;padding-bottom:4px;margin:16px 0 6px">3. Převzetí a vrácení</h2>
<p>Místem převzetí i vrácení je pobočka <strong>{{branch_name}}</strong>, {{branch_address}}.</p>
<p>Na obslužné pobočce předává výbavu obsluha pronajímatele a nájemce prokáže svou totožnost platným dokladem totožnosti, pokud ji neověřil předem. Na samoobslužné pobočce nájemce převezme výbavu ze šatny pomocí přístupových kódů, které mu pronajímatel zašle po úhradě a ověření dokladu totožnosti, a předávací protokol podepíše na dotykovém displeji; identifikací je kód šatny k této rezervaci.</p>
<p>Nájemce je povinen vrátit výbavu kompletní na tutéž pobočku nejpozději v poslední den nájmu. Na samoobslužné pobočce ji vrátí uložením do šatny, zavřením dveří a potvrzením vrácení na dotykovém displeji. Nevrátí-li nájemce výbavu ve sjednaný den vrácení, je povinen uhradit nájemné za každý další započatý den, kdy má výbavu v držení.</p>
<h2 style="font-size:14px;color:#1a8a18;border-bottom:1px solid #e5e7eb;padding-bottom:4px;margin:16px 0 6px">4. Užívání výbavy</h2>
<ul>
<li>Nájemce užívá výbavu s péčí řádného hospodáře, výhradně k účelu, ke kterému je určena (ochrana při jízdě na motocyklu), a nesmí ji upravovat.</li>
<li>Výbavu smí užívat nájemce nebo osoba, které ji nájemce předá (např. spolujezdec); i v takovém případě za výbavu odpovídá nájemce.</li>
<li>Za volbu vhodné velikosti odpovídá nájemce; pronajímatel mu s výběrem na požádání poradí.</li>
<li>Každý pád, náraz nebo jiné poškození výbavy je nájemce povinen bez zbytečného odkladu oznámit pronajímateli. Helmu, která utrpěla náraz, nesmí dále používat.</li>
</ul>
<h2 style="font-size:14px;color:#1a8a18;border-bottom:1px solid #e5e7eb;padding-bottom:4px;margin:16px 0 6px">5. Odpovědnost za škodu</h2>
<p>Smluvní krytí škod podle obchodních podmínek se na zapůjčenou výbavu nevztahuje. Za ztrátu, odcizení nebo poškození výbavy nad rámec běžného opotřebení odpovídá nájemce a je povinen uhradit její hodnotu, případně náklady na uvedení do původního stavu, a to na základě faktury se splatností 14 dní.</p>
<p>Chybí-li při vrácení některý kus nebo je výbava poškozená, vyhotoví pronajímatel protokol o zjištěném poškození s fotodokumentací. Zjistí-li to pronajímatel až po vrácení na samoobslužné pobočce, oznámí to nájemci bez zbytečného odkladu.</p>
<h2 style="font-size:14px;color:#1a8a18;border-bottom:1px solid #e5e7eb;padding-bottom:4px;margin:16px 0 6px">6. Změny a zrušení rezervace</h2>
<p>Změny termínu, velikostí a rozsahu výbavy a zrušení rezervace se řídí obchodními podmínkami pronajímatele, zejména ustanoveními o rezervaci a stornu. Rezervaci lze spravovat v sekci Upravit rezervaci na webu pronajímatele nebo po dohodě s pronajímatelem.</p>
<h2 style="font-size:14px;color:#1a8a18;border-bottom:1px solid #e5e7eb;padding-bottom:4px;margin:16px 0 6px">7. Závěrečná ustanovení</h2>
<p>Nájemce prohlašuje, že dosáhl věku 18 let a svou totožnost doložil platným dokladem totožnosti. Práva a povinnosti touto smlouvou neupravené se řídí obchodními podmínkami pronajímatele a zákonem č. 89/2012 Sb., občanským zákoníkem, v platném znění.</p>
<p>Odesláním rezervace a potvrzením souhlasů nájemce stvrzuje, že se seznámil s touto smlouvou, obchodními podmínkami a informacemi o zpracování osobních údajů; elektronický souhlas má stejnou právní váhu jako vlastnoruční podpis. Nedílnou součástí smlouvy jsou obchodní podmínky pronajímatele, informace o zpracování osobních údajů (GDPR), předávací protokol a případný protokol o zjištěném poškození.</p>
<table style="width:100%;border-collapse:collapse;margin-top:36px"><tr>
<td style="width:50%;text-align:center;border:none;padding:0 20px"><div style="border-top:1px solid #999;padding-top:6px;font-size:10px">Pronajímatel<br>{{company_name}}</div></td>
<td style="width:50%;text-align:center;border:none;padding:0 20px"><div style="border-top:1px solid #999;padding-top:6px;font-size:10px">Nájemce<br>{{customer_name}}</div></td>
</tr></table>
<p style="text-align:center;font-size:10px;color:#888;margin-top:24px">{{company_name}} · IČO: {{company_ico}} · {{company_address}} · {{company_email}} · {{company_phone}}</p>',
true, 1)
ON CONFLICT (type) DO NOTHING;

NOTIFY pgrst, 'reload schema';
