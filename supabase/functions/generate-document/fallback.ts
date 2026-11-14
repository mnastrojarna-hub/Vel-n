// Záložní šablony protokolů pro případ, že v DB chybí aktivní šablona (audit EDGE-DOC-15).
// Jen NEUTRÁLNÍ kostry protokolů (česky; u cizího jazyka s upozorněním na závaznou českou verzi).
// Právní dokumenty (VOP, nájemní smlouva, GDPR) ZÁLOHU NEMAJÍ — dřívější záloha VOP obsahovala
// neplatné podmínky (vratná kauce, plná odpovědnost, storno 48 h, věk 21 let); bez DB šablony
// generate-document vrací 503 + debug_log, nikdy nevymyšlené smluvní podmínky.
export function getFallbackTemplate(slug) {
  if (slug === 'handover_protocol') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Předávací protokol</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a">
<div style="max-width:780px;margin:0 auto;padding:32px">
  <h1 style="text-align:center;font-size:20px;border-bottom:2px solid #2563eb;padding-bottom:12px">PŘEDÁVACÍ PROTOKOL</h1>
  <p style="text-align:center;font-size:12px;color:#666">k rezervaci č. {{booking_number}} ze dne {{today}}</p>
  <table style="width:100%;border-collapse:collapse;font-size:12px;margin:20px 0">
    <tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600;width:160px">Zákazník</td><td style="padding:6px 10px">{{customer_name}}</td></tr>
    <tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">Motocykl</td><td style="padding:6px 10px">{{moto_model}} ({{moto_spz}})</td></tr>
    <tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">VIN</td><td style="padding:6px 10px">{{moto_vin}}</td></tr>
    <tr><td style="padding:6px 10px;background:#f8faf9;font-weight:600">Období</td><td style="padding:6px 10px">{{start_date}} — {{end_date}}</td></tr>
  </table>
  <h3 style="font-size:13px">Stav při předání</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;margin:8px 0;border:1px solid #ddd">
    <tr><td style="padding:8px;border:1px solid #ddd;width:50%">Stav km:</td><td style="padding:8px;border:1px solid #ddd">{{mileage}}</td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Viditelné poškození:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
    <tr><td style="padding:8px;border:1px solid #ddd">Poznámky:</td><td style="padding:8px;border:1px solid #ddd"></td></tr>
  </table>
  <h3 style="font-size:13px">Příslušenství a výbava</h3>
  {{accessories_block}}
  <div style="margin-top:48px;display:flex;justify-content:space-between">
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Předávající</div></div>
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Přebírající — {{customer_name}}</div></div>
  </div>
</div></body></html>`;
  }
  if (slug === 'damage_protocol') {
    return `<!DOCTYPE html><html lang="cs"><head><meta charset="utf-8"><title>Protokol o zjištěném poškození</title></head>
<body style="margin:0;padding:0;font-family:'Segoe UI',sans-serif;color:#1a1a1a;font-size:12px">
<div style="max-width:780px;margin:0 auto;padding:32px">
  <h1 style="text-align:center;font-size:18px;border-bottom:2px solid #dc2626;padding-bottom:12px">PROTOKOL O ZJIŠTĚNÉM POŠKOZENÍ PŘI VRÁCENÍ</h1>
  <p style="text-align:center;font-size:12px;color:#666">k rezervaci č. {{booking_number}} ze dne {{today}}</p>
  <h3 style="font-size:13px;margin-top:16px">1. Identifikace smlouvy a stran</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Číslo smlouvy</td><td style="padding:6px 8px;border:1px solid #ddd">{{booking_number}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Pronajímatel</td><td style="padding:6px 8px;border:1px solid #ddd">{{company_name}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Nájemce</td><td style="padding:6px 8px;border:1px solid #ddd">{{customer_name}}</td></tr>
  </table>
  <h3 style="font-size:13px;margin-top:14px">2. Identifikace vozidla</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Značka a model</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_model}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">VIN</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_vin}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">SPZ</td><td style="padding:6px 8px;border:1px solid #ddd">{{moto_spz}}</td></tr>
  </table>
  <h3 style="font-size:13px;margin-top:14px">3. Stav motocyklu při vrácení</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Stav tachometru</td><td style="padding:6px 8px;border:1px solid #ddd">&nbsp; km</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;vertical-align:top">Celkový vizuální stav</td><td style="padding:18px 8px;border:1px solid #ddd"></td></tr>
  </table>
  <h3 style="font-size:13px;margin-top:14px">4. Zjištěná poškození / chybějící příslušenství</h3>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px;vertical-align:top">Popis poškození motocyklu</td><td style="padding:28px 8px;border:1px solid #ddd"></td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;vertical-align:top">Chybějící / poškozené vybavení</td><td style="padding:20px 8px;border:1px solid #ddd"></td></tr>
  </table>
  <p style="font-size:11px;color:#666;margin-top:6px">Zapůjčené příslušenství dle rezervace: {{accessories}}</p>
  <p style="font-size:12px;margin-top:12px">Příslušná fotodokumentace je přiložena k protokolu a je jeho nedílnou součástí.</p>
  <table style="width:100%;border-collapse:collapse;font-size:12px;border:1px solid #ddd;margin-top:8px">
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600;width:220px">Datum a čas vrácení</td><td style="padding:6px 8px;border:1px solid #ddd">{{today}} {{today_time}}</td></tr>
    <tr><td style="padding:6px 8px;border:1px solid #ddd;background:#f8faf9;font-weight:600">Vystavil/a</td><td style="padding:6px 8px;border:1px solid #ddd">{{company_name}}</td></tr>
  </table>
  <div style="margin-top:48px;display:flex;justify-content:space-between">
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Podpis pronajímatele<br>{{company_name}}</div></div>
    <div style="text-align:center;width:45%"><div style="border-top:1px solid #999;padding-top:8px;font-size:11px">Podpis nájemce<br>{{customer_name}}</div></div>
  </div>
  <div style="margin-top:32px;text-align:center;font-size:10px;color:#888;border-top:1px solid #ddd;padding-top:12px">{{company_name}} · IČO: {{company_ico}} · {{company_address}} · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>`;
  }
  return null;
}
