-- ============================================================================
-- UPDATE: Plný text smlouvy o pronájmu + předávací protokol dle zadání
-- Datum: 2026-03-11
-- Nájemce se vyplní automaticky z dat rezervace (placeholders {{...}})
-- ============================================================================

-- 1. Smlouva o pronájmu motocyklu (rental_contract) — PLNÁ VERZE
UPDATE public.document_templates
SET content_html = '<!DOCTYPE html>
<html lang="cs">
<head><meta charset="utf-8"><title>Smlouva o pronájmu motocyklu – MotoGo24</title>
<style>
body{font-family:"Segoe UI",sans-serif;color:#1a1a1a;margin:0;padding:0;font-size:12px;line-height:1.55}
.wrap{max-width:780px;margin:0 auto;padding:28px}
h1{text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px;margin-bottom:8px}
h2{font-size:13px;margin:18px 0 6px;color:#1a8a18;border-bottom:1px solid #e5e7eb;padding-bottom:4px}
.subtitle{text-align:center;font-size:12px;color:#666;margin-bottom:20px}
.parties{display:flex;gap:20px;margin:16px 0}
.party{flex:1;padding:12px;background:#f8faf9;border-radius:8px}
.party-label{margin:0 0 4px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888}
.party p{margin:2px 0;font-size:11px}
table{width:100%;border-collapse:collapse;font-size:11px;margin:6px 0}
td{padding:5px 8px}
td:first-child{background:#f8faf9;font-weight:600;width:180px}
ul,ol{padding-left:18px;margin:4px 0} li{margin-bottom:3px}
.sig{margin-top:40px;display:flex;justify-content:space-between}
.sig-box{text-align:center;width:45%}
.sig-line{border-top:1px solid #999;padding-top:8px;font-size:10px}
.footer{margin-top:32px;text-align:center;font-size:10px;color:#888;border-top:1px solid #ddd;padding-top:12px}
p{margin:4px 0}
</style></head>
<body><div class="wrap">
<h1>SMLOUVA O PRONÁJMU MOTOCYKLU</h1>
<p class="subtitle">č. {{booking_number}} ze dne {{today}}</p>

<p>Tato smlouva o nájmu movité věci – motocyklu (dále jen „smlouva") se uzavírá mezi níže uvedenými stranami prostřednictvím elektronických komunikací na dálku, zejména prostřednictvím rezervačních formulářů na webových stránkách <strong>www.motogo24.cz</strong>.</p>

<div class="parties">
<div class="party">
<p class="party-label">Pronajímatel</p>
<p style="font-weight:700;margin:0">Bc. Petra Semorádová</p>
<p>Mezná 9, 393 01 Mezná</p>
<p>IČO: 21874263</p>
<p>Telefon: +420 774 256 271</p>
<p>E-mail: info@motogo24.cz</p>
<p>Bankovní spojení: 670100-2225851630/6210</p>
<p>Není plátce DPH.</p>
<p>(dále jen „pronajímatel")</p>
</div>
<div class="party">
<p class="party-label">Nájemce</p>
<p style="font-weight:700;margin:0">{{customer_name}}</p>
<p>Trvalé bydliště: {{customer_address}}</p>
<p>Číslo OP/PAS: {{customer_id_number}}</p>
<p>Číslo ŘP: {{customer_license}}</p>
<p>Telefon: {{customer_phone}}</p>
<p>E-mail: {{customer_email}}</p>
<p>(dále jen „nájemce")</p>
</div>
</div>

<p>Pronajatý motocykl smí řídit pouze nájemce uvedený ve smlouvě, jehož řidičské oprávnění a dovednosti jsou způsobilé k bezproblémové manipulaci s pronajatými stroji. V případě, že nájemce stroj zapůjčí svévolně třetí osobě, chápe se toto svévolné zapůjčení jako hrubé porušení nájemní smlouvy.</p>
<p>Jedinou výjimkou, kdy nájemce není zároveň řidič předmětu nájmu, jsou dětské motocykly. V případě pronájmu dětského motocyklu platí, že nájemcem je zákonný zástupce (rodič) nezletilého dítěte, který bude předmět nájmu užívat. Nájemce v tomto případě není osobou, která vozidlo řídí, nicméně nese plnou odpovědnost za jeho užívání nezletilým, včetně dohledu, bezpečnosti, dodržování pokynů pronajímatele a případně způsobené škody.</p>

<h2>Předmět nájmu</h2>
<table>
<tr><td>Značka a model</td><td>{{moto_model}}</td></tr>
<tr><td>SPZ</td><td>{{moto_spz}}</td></tr>
<tr><td>VIN</td><td>{{moto_vin}}</td></tr>
</table>
<p>Veškeré standardní příslušenství a nadstandardní vybavení zapůjčené nájemci je specifikováno předávacím protokolem, který tvoří nedílnou součást této nájemní smlouvy. (dále jen „předmět nájmu")</p>

<h2>Platnost nájemní smlouvy, termín výpůjčky, výše nájemného a kauce</h2>
<p>Nájemní smlouva je uzavřena v okamžiku, kdy pronajímatel potvrdí rezervaci nájemce a nájemce ve stanovené lhůtě, tj. buď do 24 h od potvrzení rezervace, nebo při rezervaci na týž den okamžitě, uhradí nájemné a předloží pronajímateli všechny požadované platné doklady. Nedodrží-li nájemce tuto lhůtu, považuje se rezervace za neplatnou a nájemní smlouva nevzniká.</p>
<p>Platnost smlouvy končí okamžikem fyzického vrácení předmětu nájmu pronajímateli, není-li dohodnuto jinak.</p>
<table>
<tr><td>Nájemní smlouva platí od</td><td>{{start_date}} {{start_time}}</td></tr>
<tr><td>Platnost smlouvy končí</td><td>{{end_date}} {{end_time}}</td></tr>
<tr><td>Termín výpůjčky</td><td>{{rental_period}}</td></tr>
<tr><td>Celkové nájemné</td><td><strong>{{total_price}} Kč</strong></td></tr>
<tr><td>Slovy</td><td>{{total_price_words}}</td></tr>
<tr><td>Kauce</td><td>0 Kč (pronajímatel nevyžaduje kauci)</td></tr>
</table>
<p>Cena zahrnuje veškeré náklady spojené s pronájmem včetně zapůjčeného příslušenství a doplňků navíc, jakož i případné dohodnuté služby navíc (např. přistavení předmětu nájmu na dohodnutém místě apod.).</p>
<p>Nájemce se zavazuje uhradit nájemné ve výši uvedené v této smlouvě:</p>
<ul>
<li>Při rezervaci s minimálně jednodenním předstihem musí být nájemné uhrazeno do 24 h od potvrzení rezervace pronajímatelem.</li>
<li>Při rezervaci na tentýž den musí být nájemné připsáno na účet pronajímatele okamžitě po potvrzení rezervace.</li>
<li>V případě, že nájemné nebude uhrazeno ve stanovené lhůtě, je rezervace automaticky považována za neplatnou a motocykl bude uvolněn pro jiného zájemce.</li>
<li>Platba je podmínkou pro vyhrazení předmětu nájmu a dokončení uzavření smlouvy.</li>
<li>Částku za pronájem nájemce uhradí prostřednictvím bankovního převodu.</li>
</ul>
<p>Ceny jsou platné dle aktuálního ceníku zveřejněného na webu pronajímatele. Kalkulátor ceny ukazuje nájemci výslednou cenu za pronájem, a to ještě před odesláním rezervačního formuláře.</p>

<h2>Předání předmětu nájmu</h2>
<table>
<tr><td>Místo předání</td><td>{{pickup_location}}</td></tr>
</table>
<p>Předmět nájmu je nájemci předán ve stavu způsobilém k řádnému užívání. Skutečný technický a vizuální stav předmětu nájmu v okamžiku předání je zaznamenán v samostatném Předávacím protokolu, který mimo jiné obsahuje výčet případných vad (např. škrábance, deformace plastů apod.) a je doplněn fotodokumentací.</p>
<p>Nájemce bere na vědomí a souhlasí s tím, že fotodokumentace pořízená při převzetí a vrácení předmětu nájmu může zachycovat jeho podobu, osobní údaje či jiné identifikátory. Fotodokumentace slouží výhradně k ochraně práv a oprávněných zájmů pronajímatele.</p>
<p>Nájemce potvrzuje, že se před převzetím předmětu nájmu seznámil s uživatelským manuálem příslušného předmětu nájmu, který je k dispozici online prostřednictvím odkazů uvedených na webových stránkách poskytovatele.</p>

<h2>Místo a rozsah užívání předmětu nájmu</h2>
<p>Nájemce je oprávněn užívat předmět nájmu na území České republiky a dalších států, jež nejsou přeškrtnuty na zelené kartě (mezinárodním dokladu o pojištění odpovědnosti), která je nájemci předána společně s předmětem nájmu.</p>
<p>Je zakázáno užívat předmět nájmu na území států, které jsou na zelené kartě přeškrtnuty. V případě porušení tohoto ustanovení přebírá nájemce plnou odpovědnost za případné škody, pokuty či jiná právní nebo finanční rizika.</p>
<p>Nájemce se zavazuje užívat předmět nájmu v souladu s právními předpisy státu, na jehož území se předmět nájmu právě nachází, a pouze k účelu odpovídajícímu jeho konstrukci.</p>

<h2>Vrácení předmětu nájmu</h2>
<table>
<tr><td>Místo vrácení</td><td>{{return_location}}</td></tr>
</table>
<p>Předmět nájmu musí být vrácen nejpozději do půlnoci (tj. 24:00 h) dne, který je ve smlouvě uveden jako poslední den nájmu. Vrácení po půlnoci je považováno za prodlení a je účtováno jako další den nájmu plus poplatek 500 Kč za každou započatou hodinu prodlení, není-li mezi stranami písemně dohodnuto jinak.</p>
<p>Předmět nájmu musí být vrácen v řádném stavu, s přihlédnutím k běžnému opotřebení, spolu s veškerým technickým příslušenstvím a výbavou. V případě poškození nad rámec běžného opotřebení je nájemce povinen uhradit náklady na opravu.</p>

<h2>Motivační sleva za vrácení ve výborném stavu</h2>
<p>V případě, že nájemce vrátí předmět nájmu ve viditelně čistém stavu, bez jakéhokoliv nového mechanického poškození, včetně kompletního vybavení, a bude zřejmé, že k předmětu nájmu přistupoval šetrně, bude mu jako poděkování poskytnuta sleva ve výši 400 Kč na další pronájem formou slevového kódu.</p>

<h2>Pojištění, nehody a odpovědnost za škodu</h2>
<p>Předmět nájmu má sjednáno pouze zákonné pojištění odpovědnosti z provozu vozidla (tzv. povinné ručení) s územní platností dle zelené karty. V případě dopravní nehody, poškození, zcizení nebo jiné mimořádné události je nájemce povinen:</p>
<ul>
<li>okamžitě přivolat policii ČR (popř. příslušné složky v zahraničí);</li>
<li>kontaktovat pronajímatele, a to telefonicky a následně i písemně (e-mailem);</li>
<li>zajistit fotodokumentaci a spolupracovat na sepsání záznamu o nehodě.</li>
</ul>
<p>Nájemce je povinen řídit předmět nájmu s maximální opatrností, v souladu s právními předpisy, a je zakázáno řídit pod vlivem alkoholu, omamných a psychotropních látek. Předmět nájmu nesmí být dále pronajímán ani zapůjčen třetí osobě bez předchozího výslovného souhlasu pronajímatele.</p>
<p>Pokud nájemce poruší povinnosti uvedené v této smlouvě nebo v obchodních podmínkách, případně způsobí škodu úmyslně, hrubou nedbalostí nebo vlivem návykových látek, odpovídá za vzniklou škodu v plném rozsahu. V ostatních případech, kdy není prokázáno porušení ani hrubá nedbalost, platí nájemce spoluúčast ve výši 10 % z celkové škody, maximálně však 30 000 Kč.</p>

<h2>Povinnost zabezpečení předmětu nájmu a odpovědnost za odcizení</h2>
<p>Nájemce se zavazuje vždy řádně zabezpečit předmět nájmu proti odcizení:</p>
<ul>
<li>zamknout řízení předmětu nájmu;</li>
<li>vyjmout klíč ze zapalování;</li>
<li>zajistit parkování na vhodném místě (veřejné, osvětlené, ideálně kamerově sledované).</li>
</ul>
<p>V případě odcizení je nájemce povinen kontaktovat pronajímatele a nahlásit událost policii ČR. Pokud se prokáže, že nájemce předmět řádně nezabezpečil, nese plnou odpovědnost. Pokud prokáže řádné zabezpečení, odpovídá pouze do výše spoluúčasti 10 % z hodnoty předmětu, maximálně 30 000 Kč.</p>

<h2>Závěrečná ustanovení</h2>
<p>Smluvní strany se dohodly, že veškeré skutečnosti neupravené touto smlouvou se řídí příslušnými ustanoveními zákona č. 89/2012 Sb., občanského zákoníku, a dále zákona č. 99/1963 Sb., občanského soudního řádu, v platném znění.</p>
<p>Tato smlouva je výrazem pravé a svobodné vůle smluvních stran a byla uzavřena vážně, svobodně a nikoli v tísni nebo za nevýhodných podmínek.</p>
<p>Odesláním rezervačního formuláře a zaškrtnutím příslušných souhlasů nájemce výslovně potvrzuje, že se seznámil se všemi souvisejícími dokumenty – zejména s touto Nájemní smlouvou, Obchodními podmínkami, Předávacím protokolem a Informacemi o zpracování osobních údajů (GDPR). Elektronický souhlas má stejnou právní váhu jako fyzický podpis nájemce.</p>
<p>Vyplněná nájemní smlouva bude nájemci zaslána e-mailem v elektronické podobě po splnění všech podmínek uzavření smlouvy.</p>
<p>V případě porušení této smlouvy je pronajímatel oprávněn smlouvu vypovědět a nájemci odebrat předmět nájmu, přičemž nespotřebovaná část nájemného se nevrátí.</p>
<p>Nedílnou součástí této nájemní smlouvy jsou:</p>
<ul>
<li>Obchodní podmínky pronajímatele;</li>
<li>souhlas se zpracováním osobních údajů dle Nařízení (EU) 2016/679 (GDPR);</li>
<li>Předávací protokol vyplněný při převzetí předmětu nájmu včetně příslušné fotodokumentace;</li>
<li>Protokol o zjištěném poškození při vrácení motocyklu (pokud relevantní).</li>
</ul>

<div class="sig">
<div class="sig-box"><div class="sig-line">Pronajímatel<br>Bc. Petra Semorádová</div></div>
<div class="sig-box"><div class="sig-line">Nájemce<br>{{customer_name}}</div></div>
</div>

<div class="footer">Bc. Petra Semorádová · IČO: 21874263 · Mezná 9, 393 01 Mezná · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>',
    version = version + 1,
    updated_at = now()
WHERE type = 'rental_contract';

-- 2. Předávací protokol (handover_protocol) — PLNÁ VERZE s tabulkami
UPDATE public.document_templates
SET content_html = '<!DOCTYPE html>
<html lang="cs">
<head><meta charset="utf-8"><title>Předávací protokol – MotoGo24</title>
<style>
body{font-family:"Segoe UI",sans-serif;color:#1a1a1a;margin:0;padding:0;font-size:12px;line-height:1.55}
.wrap{max-width:780px;margin:0 auto;padding:28px}
h1{text-align:center;font-size:20px;border-bottom:2px solid #2563eb;padding-bottom:12px;margin-bottom:8px}
h2{font-size:13px;margin:18px 0 6px;color:#2563eb;border-bottom:1px solid #e5e7eb;padding-bottom:4px}
.subtitle{text-align:center;font-size:12px;color:#666;margin-bottom:20px}
table{width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd}
td,th{padding:6px 8px;border:1px solid #ddd;text-align:left}
th{background:#f0f7ff;font-weight:700;font-size:10px;text-transform:uppercase}
td:first-child{background:#f8faf9;font-weight:600;width:200px}
.checklist td{background:#fff;font-weight:normal}
.checklist td:first-child{width:auto;background:#fff}
.notes-area{width:100%;min-height:60px;border:1px solid #ddd;border-radius:4px;padding:8px;font-family:inherit;font-size:11px}
.sig{margin-top:40px;display:flex;justify-content:space-between}
.sig-box{text-align:center;width:45%}
.sig-line{border-top:1px solid #999;padding-top:8px;font-size:10px}
.footer{margin-top:32px;text-align:center;font-size:10px;color:#888;border-top:1px solid #ddd;padding-top:12px}
p{margin:4px 0}
</style></head>
<body><div class="wrap">
<h1>PŘEDÁVACÍ PROTOKOL</h1>
<p class="subtitle">k rezervaci č. {{booking_number}} ze dne {{today}}</p>

<h2>1. Identifikace smlouvy a stran</h2>
<table>
<tr><td>Číslo smlouvy</td><td>{{booking_number}}</td></tr>
<tr><td>Pronajímatel</td><td>MotoGo24, Bc. Petra Semorádová</td></tr>
<tr><td>Nájemce (jméno a příjmení)</td><td>{{customer_name}}</td></tr>
</table>

<h2>2. Identifikace vozidla</h2>
<table>
<tr><td>Značka a model</td><td>{{moto_model}}</td></tr>
<tr><td>VIN</td><td>{{moto_vin}}</td></tr>
</table>

<h2>3. Stav motocyklu při předání</h2>
<table>
<tr><td>Stav tachometru</td><td>{{mileage}} km</td></tr>
<tr><td>Stav paliva</td><td>{{fuel_state}}</td></tr>
<tr><td>Technický stav (brzdy, světla, pneu, zrcátka, plexy, stojan, řetěz…)</td><td>{{technical_state}}</td></tr>
</table>

<h2>4. Příslušenství a výbava</h2>
<table class="checklist">
<tr><th>Položka</th><th>Počet ks</th><th>Stav při převzetí</th><th>Předáno</th></tr>
<tr><td>Helma</td><td></td><td></td><td>☐</td></tr>
<tr><td>Kalhoty</td><td></td><td></td><td>☐</td></tr>
<tr><td>Bunda</td><td></td><td></td><td>☐</td></tr>
<tr><td>Rukavice</td><td></td><td></td><td>☐</td></tr>
<tr><td>Kukla</td><td></td><td>nová (zůstává nájemci)</td><td>☐</td></tr>
<tr><td>Kufr zadní</td><td></td><td></td><td>☐</td></tr>
<tr><td>Kufr boční</td><td></td><td></td><td>☐</td></tr>
</table>

<h2>5. Povinná výbava a dokumenty</h2>
<table class="checklist">
<tr><th>Položka</th><th>Počet ks</th><th>Předáno</th></tr>
<tr><td>Malý technický průkaz</td><td></td><td>☐</td></tr>
<tr><td>Zelená karta</td><td></td><td>☐</td></tr>
<tr><td>Kontakt na asistenční službu</td><td></td><td>☐</td></tr>
<tr><td>Záznam o dopravní nehodě s propiskou</td><td></td><td>☐</td></tr>
<tr><td>Klíče</td><td></td><td>☐</td></tr>
<tr><td>Lékárnička</td><td></td><td>☐</td></tr>
<tr><td>Reflexní vesta</td><td></td><td>☐</td></tr>
</table>

<h2>6. Převzetí motocyklu</h2>
<p>Nájemce potvrzuje, že převzal motocykl ve výše uvedeném stavu a s uvedeným příslušenstvím. Příslušná fotodokumentace je přiložena k protokolu a je jeho nedílnou součástí.</p>
<p>Nájemce bere na vědomí, že fotodokumentace pořízená v čase předání motocyklu je rozhodující pro posouzení stavu motorky.</p>
<p>Převzetím motocyklu nájemce souhlasí s obsahem tohoto Předávacího protokolu, který bude nájemci zaslán elektronicky na e-mail uvedený v nájemní smlouvě bezprostředně po převzetí motocyklu. Odesláním se považuje za správně doručený.</p>

<table>
<tr><td>Datum a čas převzetí</td><td>{{today}} {{today_time}}</td></tr>
<tr><td>Vystavil/a</td><td>Bc. Petra Semorádová</td></tr>
</table>

<div class="sig">
<div class="sig-box"><div class="sig-line">Předávající<br>Bc. Petra Semorádová</div></div>
<div class="sig-box"><div class="sig-line">Přebírající<br>{{customer_name}}</div></div>
</div>

<div class="footer">Bc. Petra Semorádová · IČO: 21874263 · Mezná 9, 393 01 Mezná · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>',
    version = version + 1,
    updated_at = now()
WHERE type = 'handover_protocol';
