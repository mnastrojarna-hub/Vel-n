/**
 * MotoGo24 — Edge Function: Send Recovery OTP
 *
 * Bypass Supabase Auth's built-in email sender (rate limit, missing template config)
 * a posílá 8-znakový OTP kód pro reset hesla rovnou přes Resend.
 *
 * Flow:
 *   1) POST {email}  (anon-callable, JWT off — viz config.toml)
 *   2) auth.admin.generateLink({type:'recovery', email}) → vygeneruje token,
 *      perzistuje ho v auth.users.recovery_token, vrátí `email_otp` (8-znak. kód)
 *   3) Pošle pretty mail přes Resend (noreply@motogo24.cz) s tím kódem
 *   4) Anti-enumeration: vždy success response, i když user neexistuje
 *
 * Frontend (verifikace) beze změny — `verifyOtp({type:'recovery', email, token})`
 * validuje token uložený v auth.users (stejný flow jako klasický resetPasswordForEmail).
 */ import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const FROM_EMAIL = Deno.env.get('FROM_EMAIL') || 'noreply@motogo24.cz';
// ── i18n: jazyk + doména zákazníka (cs → .cz, ostatní → .com) ───────────────
const SUPPORTED_LANGS = [
  'cs',
  'en',
  'de',
  'es',
  'fr',
  'nl',
  'pl'
];
function normLang(l) {
  const s = String(l || '').toLowerCase().slice(0, 2);
  return SUPPORTED_LANGS.includes(s) ? s : 'cs';
}
function siteForLang(lang) {
  return lang === 'cs' ? 'https://www.motogo24.cz' : 'https://motogo24.com';
}
function webLabelForLang(lang) {
  return lang === 'cs' ? 'motogo24.cz' : 'motogo24.com';
}
/** Kurátorské překlady OTP mailu (auth-kritický → bez API latence). */ const OTP_L = {
  cs: {
    subject: 'Obnovení hesla — ověřovací kód',
    title: 'Obnovení hesla',
    intro: 'Pro obnovení hesla zadejte na webu MotoGo24 následující ověřovací kód. Pak rovnou nastavíte nové heslo. Kód platí',
    hour: '1 hodinu',
    ignore: 'Pokud jste o obnovení hesla nežádali, e-mail ignorujte. Vaše heslo zůstane beze změny.',
    team: 'Tým MotoGo24',
    auto: 'Tato zpráva byla vygenerována automaticky.'
  },
  en: {
    subject: 'Password reset — verification code',
    title: 'Password reset',
    intro: 'To reset your password, enter the following verification code on the MotoGo24 website. Then set a new password right away. The code is valid for',
    hour: '1 hour',
    ignore: "If you didn't request a password reset, please ignore this email. Your password will remain unchanged.",
    team: 'The MotoGo24 Team',
    auto: 'This message was generated automatically.'
  },
  de: {
    subject: 'Passwort zurücksetzen — Bestätigungscode',
    title: 'Passwort zurücksetzen',
    intro: 'Um Ihr Passwort zurückzusetzen, geben Sie den folgenden Bestätigungscode auf der MotoGo24-Website ein. Anschließend legen Sie direkt ein neues Passwort fest. Der Code ist',
    hour: '1 Stunde',
    ignore: 'Wenn Sie kein Zurücksetzen des Passworts angefordert haben, ignorieren Sie diese E-Mail bitte. Ihr Passwort bleibt unverändert.',
    team: 'Ihr MotoGo24-Team',
    auto: 'Diese Nachricht wurde automatisch generiert.'
  },
  nl: {
    subject: 'Wachtwoord opnieuw instellen — verificatiecode',
    title: 'Wachtwoord opnieuw instellen',
    intro: 'Voer de volgende verificatiecode in op de website van MotoGo24 om je wachtwoord opnieuw in te stellen. Daarna stel je meteen een nieuw wachtwoord in. De code is',
    hour: '1 uur',
    ignore: 'Als je geen wachtwoordherstel hebt aangevraagd, kun je deze e-mail negeren. Je wachtwoord blijft ongewijzigd.',
    team: 'Het MotoGo24-team',
    auto: 'Dit bericht is automatisch gegenereerd.'
  },
  es: {
    subject: 'Restablecer contraseña — código de verificación',
    title: 'Restablecer contraseña',
    intro: 'Para restablecer tu contraseña, introduce el siguiente código de verificación en el sitio web de MotoGo24. Luego podrás establecer una nueva contraseña. El código es válido durante',
    hour: '1 hora',
    ignore: 'Si no solicitaste restablecer la contraseña, ignora este correo. Tu contraseña no cambiará.',
    team: 'El equipo de MotoGo24',
    auto: 'Este mensaje se generó automáticamente.'
  },
  fr: {
    subject: 'Réinitialisation du mot de passe — code de vérification',
    title: 'Réinitialisation du mot de passe',
    intro: 'Pour réinitialiser votre mot de passe, saisissez le code de vérification suivant sur le site MotoGo24. Vous pourrez ensuite définir un nouveau mot de passe. Le code est valable',
    hour: '1 heure',
    ignore: "Si vous n'avez pas demandé de réinitialisation, ignorez cet e-mail. Votre mot de passe restera inchangé.",
    team: "L'équipe MotoGo24",
    auto: 'Ce message a été généré automatiquement.'
  },
  pl: {
    subject: 'Resetowanie hasła — kod weryfikacyjny',
    title: 'Resetowanie hasła',
    intro: 'Aby zresetować hasło, wpisz poniższy kod weryfikacyjny na stronie MotoGo24. Następnie od razu ustawisz nowe hasło. Kod jest ważny',
    hour: '1 godzinę',
    ignore: 'Jeśli nie prosiłeś o zresetowanie hasła, zignoruj tę wiadomość. Twoje hasło pozostanie bez zmian.',
    team: 'Zespół MotoGo24',
    auto: 'Ta wiadomość została wygenerowana automatycznie.'
  }
};
function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...CORS,
      'Content-Type': 'application/json'
    }
  });
}
/** Pretty HTML mail s 8-znakovým OTP kódem v jazyce zákazníka (cs default). */ function renderRecoveryOtpHtml(otp, lang) {
  const prettyOtp = otp.toUpperCase();
  const L = OTP_L[lang] || OTP_L.cs;
  const site = siteForLang(lang);
  const webLabel = webLabelForLang(lang);
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><title>${L.title}</title></head>
<body style="margin:0;padding:0;background:#f0faf5;font-family:Arial,Helvetica,sans-serif;color:#1a2e22">
<div style="max-width:560px;margin:0 auto;padding:32px 16px">
  <div style="background:#fff;border-radius:14px;padding:28px 24px;box-shadow:0 4px 14px rgba(0,0,0,.06)">
    <h1 style="margin:0 0 12px;font-size:22px;color:#1a2e22">${L.title}</h1>
    <p style="margin:0 0 18px;line-height:1.55;font-size:15px;color:#3a5a4a">
      ${L.intro} <strong>${L.hour}</strong>.
    </p>
    <div style="margin:22px 0;padding:22px;background:#e6f4ec;border:2px solid #74FB71;border-radius:12px;text-align:center">
      <div style="font-family:'Courier New',monospace;font-size:34px;font-weight:700;letter-spacing:.4em;color:#1a2e22">${prettyOtp}</div>
    </div>
    <p style="margin:0 0 8px;font-size:13.5px;color:#5a6a62;line-height:1.5">
      ${L.ignore}
    </p>
    <p style="margin:18px 0 0;font-size:13.5px;color:#5a6a62;line-height:1.5">
      ${L.team} &middot; <a href="${site}" style="color:#1a8c1a;text-decoration:none">${webLabel}</a> &middot; +420 774 256 271
    </p>
  </div>
  <p style="margin:14px 0 0;text-align:center;font-size:11px;color:#94a399">${L.auto}</p>
</div>
</body></html>`;
}
/** Send via Resend with 2 retries. */ async function sendViaResend(to, html, subject) {
  if (!RESEND_API_KEY) return {
    ok: false,
    error: 'RESEND_API_KEY not configured'
  };
  for(let attempt = 1; attempt <= 2; attempt++){
    try {
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': 'Bearer ' + RESEND_API_KEY,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          from: 'MotoGo24 <' + FROM_EMAIL + '>',
          to,
          subject,
          html
        })
      });
      if (res.ok) {
        const data = await res.json();
        return {
          ok: true,
          id: data.id
        };
      }
      const errBody = await res.text();
      if (attempt === 2) return {
        ok: false,
        error: `Resend ${res.status}: ${errBody}`
      };
    } catch (e) {
      if (attempt === 2) return {
        ok: false,
        error: `Resend fetch error: ${e.message}`
      };
    }
    await new Promise((r)=>setTimeout(r, 1000 * attempt));
  }
  return {
    ok: false,
    error: 'Resend retry exhausted'
  };
}
serve(async (req)=>{
  if (req.method === 'OPTIONS') return new Response('ok', {
    headers: CORS
  });
  if (req.method !== 'POST') return jsonResponse({
    error: 'Method not allowed'
  }, 405);
  let email = '';
  let reqLang = '' // explicitní jazyk z volajícího (web/app), má přednost před profilem
  ;
  try {
    const body = await req.json().catch(()=>({}));
    email = String(body?.email || '').trim().toLowerCase();
    reqLang = String(body?.language || '').trim();
  } catch  {
    return jsonResponse({
      error: 'Invalid JSON body'
    }, 400);
  }
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return jsonResponse({
      error: 'invalid_email'
    }, 400);
  }
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
  try {
    // Ověř, že user existuje. Když ne — anti-enumeration: vrátíme úspěch
    // (nepředáme info, jestli mail v systému je, nebo není).
    const { data: lookup } = await admin.from('profiles').select('id, language').eq('email', email).maybeSingle();
    let foundUserId = lookup?.id ?? null;
    // Jazyk: explicitní z volajícího > profiles.language > 'cs'.
    const lang = normLang(reqLang || lookup?.language);
    if (!foundUserId) {
      // Fallback: profile může chybět (osiřelý auth.users) — zkus auth lookup.
      try {
        const { data: list } = await admin.auth.admin.listUsers({
          page: 1,
          perPage: 1,
          filter: `email.eq.${email}`
        });
        foundUserId = list?.users?.[0]?.id ?? null;
      } catch  {
      // ignore — silent anti-enumeration
      }
    }
    if (!foundUserId) {
      // Anti-enumeration: stejná odpověď
      return jsonResponse({
        success: true,
        sent: false
      });
    }
    // Generate recovery link → vrátí email_otp (token uložen v auth.users)
    const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
      type: 'recovery',
      email
    });
    if (linkErr || !linkData?.properties?.email_otp) {
      console.error('[send-recovery-otp] generateLink err', linkErr);
      // Pro klienta drž generic — neprozraz, že mail v systému je, jen že to nešlo.
      return jsonResponse({
        success: false,
        error: 'recovery_generation_failed'
      }, 500);
    }
    const otp = String(linkData.properties.email_otp).toUpperCase();
    const html = renderRecoveryOtpHtml(otp, lang);
    const subject = (OTP_L[lang] || OTP_L.cs).subject;
    const sendRes = await sendViaResend(email, html, subject);
    if (!sendRes.ok) {
      console.error('[send-recovery-otp] resend err', sendRes.error);
      return jsonResponse({
        success: false,
        error: 'send_failed',
        detail: sendRes.error
      }, 500);
    }
    // Log do message_log (best-effort, nezávisí na něm response)
    try {
      await admin.from('message_log').insert({
        channel: 'email',
        recipient: email,
        template_slug: 'recovery_otp',
        status: 'sent',
        provider_response: {
          id: sendRes.id
        },
        metadata: {
          user_id: foundUserId
        }
      });
    } catch (e) {
      console.warn('[send-recovery-otp] message_log insert failed', e);
    }
    return jsonResponse({
      success: true,
      sent: true
    });
  } catch (err) {
    console.error('[send-recovery-otp] exception', err);
    return jsonResponse({
      success: false,
      error: err.message
    }, 500);
  }
});
