/**
 * MotoGo24 — HTML email šablony v češtině
 * Branding: zelená #74FB71, tmavá #1a2e22, font Montserrat
 */

interface EmailTemplate {
  subject: string;
  html: string;
}

function baseLayout(title: string, content: string): string {
  return `<!DOCTYPE html>
<html lang="cs">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700&display=swap');
    body { margin: 0; padding: 0; background: #f4f4f4; font-family: 'Montserrat', Arial, sans-serif; }
    .wrapper { max-width: 600px; margin: 0 auto; background: #ffffff; }
    .header { background: #1a2e22; padding: 24px; text-align: center; }
    .header h1 { color: #74FB71; margin: 0; font-size: 28px; font-weight: 700; }
    .header p { color: #a0c4a0; margin: 4px 0 0; font-size: 13px; }
    .content { padding: 32px 24px; color: #1a2e22; line-height: 1.6; }
    .content h2 { color: #1a2e22; font-size: 20px; margin-top: 0; }
    .info-box { background: #f0fdf0; border-left: 4px solid #74FB71; padding: 16px; margin: 16px 0; border-radius: 4px; }
    .info-row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #e8e8e8; }
    .info-label { font-weight: 600; color: #555; }
    .info-value { color: #1a2e22; font-weight: 600; }
    .btn { display: inline-block; background: #74FB71; color: #1a2e22; padding: 12px 32px; text-decoration: none; border-radius: 6px; font-weight: 700; font-size: 15px; margin: 16px 0; }
    .btn:hover { background: #5ce659; }
    .footer { background: #1a2e22; padding: 20px 24px; text-align: center; color: #a0c4a0; font-size: 12px; }
    .footer a { color: #74FB71; text-decoration: none; }
    .urgent-header { background: #dc2626; }
    .urgent-header h1 { color: #ffffff; }
    .urgent-box { background: #fef2f2; border-left: 4px solid #dc2626; padding: 16px; margin: 16px 0; border-radius: 4px; }
    table.info-table { width: 100%; border-collapse: collapse; margin: 12px 0; }
    table.info-table td { padding: 8px 12px; border-bottom: 1px solid #e8e8e8; }
    table.info-table td:first-child { font-weight: 600; color: #555; width: 40%; }
    table.info-table td:last-child { color: #1a2e22; }
  </style>
</head>
<body>
  <div class="wrapper">
    ${content}
    <div class="footer">
      <p>&copy; ${new Date().getFullYear()} MotoGo24 — Pronájem motocyklů</p>
      <p><a href="https://motogo24.cz">motogo24.cz</a> | info@motogo24.cz | +420 XXX XXX XXX</p>
    </div>
  </div>
</body>
</html>`;
}

/** Potvrzení rezervace — odesláno zákazníkovi po úspěšné platbě. */
export function bookingConfirmation(data: {
  customer_name: string;
  moto_model: string;
  moto_spz: string;
  start_date: string;
  end_date: string;
  total_price: number;
  branch_name: string;
  branch_address: string;
  booking_id: string;
}): EmailTemplate {
  return {
    subject: `Potvrzení rezervace — ${data.moto_model} | MotoGo24`,
    html: baseLayout('Potvrzení rezervace', `
      <div class="header">
        <h1>MotoGo24</h1>
        <p>Pronájem motocyklů</p>
      </div>
      <div class="content">
        <h2>Rezervace potvrzena!</h2>
        <p>Dobrý den, ${data.customer_name},</p>
        <p>vaše rezervace byla úspěšně potvrzena a zaplacena. Níže najdete všechny detaily.</p>

        <div class="info-box">
          <table class="info-table">
            <tr><td>Číslo rezervace</td><td>${data.booking_id}</td></tr>
            <tr><td>Motocykl</td><td>${data.moto_model}</td></tr>
            <tr><td>SPZ</td><td>${data.moto_spz}</td></tr>
            <tr><td>Začátek</td><td>${data.start_date}</td></tr>
            <tr><td>Konec</td><td>${data.end_date}</td></tr>
            <tr><td>Celková cena</td><td>${data.total_price.toLocaleString('cs-CZ')} Kč</td></tr>
            <tr><td>Pobočka</td><td>${data.branch_name}</td></tr>
            <tr><td>Adresa</td><td>${data.branch_address}</td></tr>
          </table>
        </div>

        <p><strong>Co vzít s sebou:</strong></p>
        <ul>
          <li>Platný občanský průkaz nebo pas</li>
          <li>Řidičský průkaz s odpovídající skupinou</li>
          <li>Kreditní nebo debetní kartu pro kauci</li>
        </ul>

        <p>Těšíme se na vás!</p>
        <p>Tým MotoGo24</p>
      </div>
    `),
  };
}

/** Připomínka 24h před začátkem rezervace. */
export function bookingReminder(data: {
  customer_name: string;
  moto_model: string;
  start_date: string;
  start_time: string;
  branch_name: string;
  branch_address: string;
  booking_id: string;
}): EmailTemplate {
  return {
    subject: `Připomínka: Zítra začíná vaše rezervace | MotoGo24`,
    html: baseLayout('Připomínka rezervace', `
      <div class="header">
        <h1>MotoGo24</h1>
        <p>Pronájem motocyklů</p>
      </div>
      <div class="content">
        <h2>Zítra začíná vaše rezervace!</h2>
        <p>Dobrý den, ${data.customer_name},</p>
        <p>připomínáme, že zítra začíná vaše rezervace motocyklu.</p>

        <div class="info-box">
          <table class="info-table">
            <tr><td>Číslo rezervace</td><td>${data.booking_id}</td></tr>
            <tr><td>Motocykl</td><td>${data.moto_model}</td></tr>
            <tr><td>Datum převzetí</td><td>${data.start_date}</td></tr>
            <tr><td>Čas převzetí</td><td>${data.start_time}</td></tr>
            <tr><td>Pobočka</td><td>${data.branch_name}</td></tr>
            <tr><td>Adresa</td><td>${data.branch_address}</td></tr>
          </table>
        </div>

        <p><strong>Nezapomeňte:</strong></p>
        <ul>
          <li>Občanský průkaz nebo pas</li>
          <li>Řidičský průkaz</li>
          <li>Pohodlné oblečení a pevnou obuv</li>
        </ul>

        <p>Na shledanou zítra!</p>
        <p>Tým MotoGo24</p>
      </div>
    `),
  };
}

/** SOS notifikace pro administrátora — URGENT. */
export function sosAdminAlert(data: {
  incident_type: string;
  customer_name: string;
  customer_phone: string;
  moto_model: string;
  moto_spz: string;
  latitude: number;
  longitude: number;
  description: string;
  is_fault: boolean;
  reported_at: string;
  incident_id: string;
}): EmailTemplate {
  const typeLabels: Record<string, string> = {
    accident_minor: 'Drobná nehoda',
    accident_major: 'Vážná nehoda',
    theft: 'Krádež',
    breakdown_minor: 'Drobná porucha',
    breakdown_major: 'Vážná porucha',
    location_share: 'Sdílení polohy',
  };

  const typeLabel = typeLabels[data.incident_type] ?? data.incident_type;
  const mapsUrl = `https://maps.google.com/?q=${data.latitude},${data.longitude}`;

  return {
    subject: `🚨 SOS MotoGo24: ${typeLabel} — ${data.customer_name}`,
    html: baseLayout('SOS Alert', `
      <div class="header urgent-header">
        <h1>🚨 SOS ALERT</h1>
        <p>MotoGo24 — Vyžaduje okamžitou pozornost</p>
      </div>
      <div class="content">
        <h2 style="color: #dc2626;">Nahlášen incident: ${typeLabel}</h2>

        <div class="urgent-box">
          <table class="info-table">
            <tr><td>ID incidentu</td><td>${data.incident_id}</td></tr>
            <tr><td>Typ</td><td><strong>${typeLabel}</strong></td></tr>
            <tr><td>Zákazník</td><td><strong>${data.customer_name}</strong></td></tr>
            <tr><td>Telefon</td><td><a href="tel:${data.customer_phone}">${data.customer_phone}</a></td></tr>
            <tr><td>Motocykl</td><td>${data.moto_model}</td></tr>
            <tr><td>SPZ</td><td><strong>${data.moto_spz}</strong></td></tr>
            <tr><td>GPS poloha</td><td><a href="${mapsUrl}" style="color: #dc2626; font-weight: 700;">Otevřít v mapě →</a></td></tr>
            <tr><td>Zavinění</td><td>${data.is_fault ? 'Ano (zákazník)' : 'Ne / Třetí strana'}</td></tr>
            <tr><td>Čas nahlášení</td><td>${data.reported_at}</td></tr>
          </table>
        </div>

        ${data.description ? `<p><strong>Popis:</strong> ${data.description}</p>` : ''}

        <a href="${mapsUrl}" class="btn" style="background: #dc2626; color: #ffffff;">📍 Zobrazit polohu na mapě</a>

        <p style="margin-top: 24px; color: #666;">Tento email byl automaticky vygenerován systémem MotoGo24 SOS.</p>
      </div>
    `),
  };
}

/** Odeslání dokumentu zákazníkovi. */
export function documentSend(data: {
  customer_name: string;
  document_type: string;
  document_name: string;
  download_url: string;
}): EmailTemplate {
  const typeLabels: Record<string, string> = {
    contract: 'Smlouva',
    protocol: 'Předávací protokol',
    invoice: 'Faktura',
    report: 'Zpráva',
  };

  const typeLabel = typeLabels[data.document_type] ?? data.document_type;

  return {
    subject: `${typeLabel}: ${data.document_name} | MotoGo24`,
    html: baseLayout('Dokument', `
      <div class="header">
        <h1>MotoGo24</h1>
        <p>Pronájem motocyklů</p>
      </div>
      <div class="content">
        <h2>Nový dokument k dispozici</h2>
        <p>Dobrý den, ${data.customer_name},</p>
        <p>v příloze najdete požadovaný dokument:</p>

        <div class="info-box">
          <table class="info-table">
            <tr><td>Typ dokumentu</td><td>${typeLabel}</td></tr>
            <tr><td>Název</td><td>${data.document_name}</td></tr>
          </table>
        </div>

        <a href="${data.download_url}" class="btn">📄 Stáhnout dokument</a>

        <p style="color: #666; font-size: 13px;">Odkaz je platný 7 dní od odeslání.</p>
      </div>
    `),
  };
}

/** Reset hesla. */
export function passwordReset(data: {
  customer_name: string;
  reset_url: string;
}): EmailTemplate {
  return {
    subject: `Reset hesla | MotoGo24`,
    html: baseLayout('Reset hesla', `
      <div class="header">
        <h1>MotoGo24</h1>
        <p>Pronájem motocyklů</p>
      </div>
      <div class="content">
        <h2>Požadavek na reset hesla</h2>
        <p>Dobrý den, ${data.customer_name},</p>
        <p>obdrželi jsme požadavek na reset vašeho hesla. Klikněte na tlačítko níže pro nastavení nového hesla:</p>

        <a href="${data.reset_url}" class="btn">🔑 Nastavit nové heslo</a>

        <p style="color: #666; font-size: 13px;">Odkaz je platný 1 hodinu. Pokud jste o reset hesla nežádali, tento email ignorujte.</p>
        <p style="color: #666; font-size: 13px;">Z bezpečnostních důvodů nikdy nesdílejte tento odkaz s nikým.</p>
      </div>
    `),
  };
}

/** Odeslání faktury. */
export function invoiceSend(data: {
  customer_name: string;
  invoice_number: string;
  amount: number;
  due_date: string;
  download_url: string;
  items: Array<{ description: string; amount: number }>;
}): EmailTemplate {
  const itemsHtml = data.items
    .map(
      (item) =>
        `<tr><td>${item.description}</td><td style="text-align: right;">${item.amount.toLocaleString('cs-CZ')} Kč</td></tr>`,
    )
    .join('');

  return {
    subject: `Faktura ${data.invoice_number} | MotoGo24`,
    html: baseLayout('Faktura', `
      <div class="header">
        <h1>MotoGo24</h1>
        <p>Pronájem motocyklů</p>
      </div>
      <div class="content">
        <h2>Faktura ${data.invoice_number}</h2>
        <p>Dobrý den, ${data.customer_name},</p>
        <p>zasíláme vám fakturu za služby MotoGo24:</p>

        <div class="info-box">
          <table class="info-table">
            <tr><td>Číslo faktury</td><td>${data.invoice_number}</td></tr>
            <tr><td>Datum splatnosti</td><td>${data.due_date}</td></tr>
          </table>
          <table class="info-table" style="margin-top: 12px;">
            ${itemsHtml}
            <tr style="border-top: 2px solid #1a2e22;">
              <td><strong>Celkem</strong></td>
              <td style="text-align: right;"><strong>${data.amount.toLocaleString('cs-CZ')} Kč</strong></td>
            </tr>
          </table>
        </div>

        <a href="${data.download_url}" class="btn">📄 Stáhnout fakturu (PDF)</a>

        <p style="color: #666; font-size: 13px;">Faktura je automaticky generována systémem MotoGo24.</p>
      </div>
    `),
  };
}

/** Dispatcher — vrátí šablonu dle typu. */
export function getEmailTemplate(
  type: string,
  data: Record<string, unknown>,
): EmailTemplate {
  switch (type) {
    case 'booking_confirmation':
      return bookingConfirmation(data as Parameters<typeof bookingConfirmation>[0]);
    case 'booking_reminder':
      return bookingReminder(data as Parameters<typeof bookingReminder>[0]);
    case 'sos_admin_alert':
      return sosAdminAlert(data as Parameters<typeof sosAdminAlert>[0]);
    case 'document_send':
      return documentSend(data as Parameters<typeof documentSend>[0]);
    case 'password_reset':
      return passwordReset(data as Parameters<typeof passwordReset>[0]);
    case 'invoice_send':
      return invoiceSend(data as Parameters<typeof invoiceSend>[0]);
    default:
      throw new Error(`Unknown email template type: ${type}`);
  }
}
