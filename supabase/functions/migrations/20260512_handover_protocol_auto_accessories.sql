-- 2026-05-12: Předávací protokol (handover_protocol)
--  • odstraněna kolonka „Stav paliva" ({{fuel_state}})
--  • sekce „Příslušenství a výbava" se vyplňuje automaticky z rezervace přes {{accessories_block}}
--    (velikosti řidiče i spolujezdce; u dětských motorek „dětská velikost")
-- POZNÁMKA: po aplikaci aktualizovat SUPABASE_BACKEND_STATE_6.md (changelog).

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
<tr><td>Technický stav (brzdy, světla, pneu, zrcátka, plexy, stojan, řetěz…)</td><td>{{technical_state}}</td></tr>
</table>

<h2>4. Příslušenství a výbava</h2>
{{accessories_block}}
<table class="checklist">
<tr><th>Položka</th><th>Počet ks</th><th>Stav při převzetí</th><th>Předáno</th></tr>
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

-- ── Nové šablony: Protokol o poškození (damage_protocol) + GDPR souhlas (gdpr) ──
-- Proměnné: {{booking_number}}, {{customer_name}}, {{customer_address}}, {{customer_email}},
-- {{moto_model}}, {{moto_vin}}, {{moto_spz}}, {{today}}, {{today_time}}, {{accessories}},
-- {{company_name}}, {{company_address}}, {{company_ico}}

INSERT INTO public.document_templates (name, type, content_html, version, active)
VALUES (
  'Protokol o zjištěném poškození',
  'damage_protocol',
  '<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Protokol o zjištěném poškození při vrácení</title>
<style>body{font-family:"Segoe UI",sans-serif;color:#1a1a1a;margin:0;padding:0;font-size:12px;line-height:1.55}.wrap{max-width:780px;margin:0 auto;padding:28px}h1{text-align:center;font-size:18px;border-bottom:2px solid #dc2626;padding-bottom:12px;margin-bottom:8px}h2{font-size:13px;margin:18px 0 6px;color:#dc2626;border-bottom:1px solid #e5e7eb;padding-bottom:4px}.subtitle{text-align:center;font-size:12px;color:#666;margin-bottom:20px}table{width:100%;border-collapse:collapse;font-size:11px;margin:6px 0;border:1px solid #ddd}td{padding:6px 8px;border:1px solid #ddd;text-align:left;vertical-align:top}td:first-child{background:#f8faf9;font-weight:600;width:220px}.sig{margin-top:40px;display:flex;justify-content:space-between}.sig-box{text-align:center;width:45%}.sig-line{border-top:1px solid #999;padding-top:8px;font-size:10px}.footer{margin-top:32px;text-align:center;font-size:10px;color:#888;border-top:1px solid #ddd;padding-top:12px}p{margin:4px 0}</style></head>
<body><div class="wrap">
<h1>PROTOKOL O ZJIŠTĚNÉM POŠKOZENÍ PŘI VRÁCENÍ</h1>
<p class="subtitle">k rezervaci č. {{booking_number}} ze dne {{today}}</p>
<h2>1. Identifikace smlouvy a stran</h2>
<table>
<tr><td>Číslo smlouvy</td><td>{{booking_number}}</td></tr>
<tr><td>Pronajímatel</td><td>{{company_name}}</td></tr>
<tr><td>Nájemce (jméno a příjmení)</td><td>{{customer_name}}</td></tr>
</table>
<h2>2. Identifikace vozidla</h2>
<table>
<tr><td>Značka a model</td><td>{{moto_model}}</td></tr>
<tr><td>VIN</td><td>{{moto_vin}}</td></tr>
<tr><td>SPZ</td><td>{{moto_spz}}</td></tr>
</table>
<h2>3. Stav motocyklu při vrácení</h2>
<table>
<tr><td>Stav tachometru</td><td>&nbsp; km</td></tr>
<tr><td>Celkový vizuální stav vozidla při vrácení</td><td style="padding:22px 8px"></td></tr>
</table>
<h2>4. Zjištěná poškození / chybějící příslušenství</h2>
<table>
<tr><td>Popis poškození motocyklu</td><td style="padding:34px 8px"></td></tr>
<tr><td>Chybějící nebo poškozené vybavení</td><td style="padding:24px 8px"></td></tr>
</table>
<p style="font-size:11px;color:#666">Zapůjčené příslušenství dle rezervace: {{accessories}}</p>
<p>Příslušná fotodokumentace je přiložena k protokolu a je jeho nedílnou součástí.</p>
<table>
<tr><td>Datum a čas vrácení</td><td>{{today}} {{today_time}}</td></tr>
<tr><td>Vystavil/a</td><td>{{company_name}}</td></tr>
</table>
<div class="sig">
<div class="sig-box"><div class="sig-line">Podpis pronajímatele<br>{{company_name}}</div></div>
<div class="sig-box"><div class="sig-line">Podpis nájemce<br>{{customer_name}}</div></div>
</div>
<div class="footer">{{company_name}} · IČO: {{company_ico}} · {{company_address}} · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>',
  1, true
)
ON CONFLICT (type) DO UPDATE SET
  content_html = EXCLUDED.content_html,
  name = EXCLUDED.name,
  version = document_templates.version + 1,
  updated_at = now();

INSERT INTO public.document_templates (name, type, content_html, version, active)
VALUES (
  'GDPR — souhlas se zpracováním osobních údajů',
  'gdpr',
  '<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Souhlas se zpracováním osobních údajů (GDPR)</title>
<style>body{font-family:"Segoe UI",sans-serif;color:#1a1a1a;margin:0;padding:0;font-size:12px;line-height:1.55}.wrap{max-width:780px;margin:0 auto;padding:28px}h1{text-align:center;font-size:17px;border-bottom:2px solid #1a8a18;padding-bottom:12px;margin-bottom:8px}h2{font-size:13px;margin:16px 0 6px;color:#1a8a18}.subtitle{text-align:center;font-size:12px;color:#666;margin-bottom:18px}.sig{margin-top:40px;display:flex;justify-content:space-between}.sig-box{text-align:center;width:45%}.sig-line{border-top:1px solid #999;padding-top:8px;font-size:10px}.footer{margin-top:32px;text-align:center;font-size:10px;color:#888;border-top:1px solid #ddd;padding-top:12px}p{margin:6px 0}</style></head>
<body><div class="wrap">
<h1>INFORMACE A SOUHLAS SE ZPRACOVÁNÍM OSOBNÍCH ÚDAJŮ (GDPR)</h1>
<p class="subtitle">{{company_name}} | IČO: {{company_ico}} | {{company_address}} | ze dne {{today}}</p>
<h2>1. Správce osobních údajů</h2>
<p>Správcem osobních údajů je {{company_name}}, IČO: {{company_ico}}, se sídlem {{company_address}}, kontakt: info@motogo24.cz, +420 774 256 271.</p>
<h2>2. Subjekt údajů</h2>
<p>Jméno a příjmení: <strong>{{customer_name}}</strong><br>Adresa: {{customer_address}}<br>E-mail: {{customer_email}}</p>
<h2>3. Rozsah a účel zpracování</h2>
<p>Správce zpracovává identifikační a kontaktní údaje, údaje z dokladu totožnosti a řidičského průkazu a údaje o rezervaci za účelem uzavření a plnění nájemní smlouvy, vedení evidence, fakturace a plnění právních povinností.</p>
<h2>4. Právní základ a doba uchování</h2>
<p>Zpracování je nezbytné pro plnění smlouvy a plnění právních povinností správce (zejm. účetní a daňové předpisy). Údaje jsou uchovávány po dobu trvání smluvního vztahu a následně po dobu stanovenou právními předpisy.</p>
<h2>5. Práva subjektu údajů</h2>
<p>Subjekt údajů má právo na přístup k údajům, jejich opravu, výmaz, omezení zpracování, přenositelnost, vznesení námitky a právo podat stížnost u Úřadu pro ochranu osobních údajů (www.uoou.cz).</p>
<h2>6. Souhlas</h2>
<p>Svým podpisem potvrzuji, že jsem byl/a informován/a o zpracování osobních údajů v rozsahu uvedeném výše a beru je na vědomí.</p>
<div class="sig">
<div class="sig-box"><div class="sig-line">Za správce — {{company_name}}</div></div>
<div class="sig-box"><div class="sig-line">{{customer_name}}</div></div>
</div>
<div class="footer">{{company_name}} · IČO: {{company_ico}} · {{company_address}} · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>',
  1, true
)
ON CONFLICT (type) DO UPDATE SET
  content_html = EXCLUDED.content_html,
  name = EXCLUDED.name,
  version = document_templates.version + 1,
  updated_at = now();
