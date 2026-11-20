// ===== _shared/agent-knowledge/agent-messages.ts =====
// Záložní hlášky AI agentů ve VŠECH 8 jazycích webu/appky (audit i18n 2026-10-10,
// AI-05/AI-06): dřív jen cs/en/de (web) resp. jen česky (appka) → Španěl, Francouz,
// Nizozemec, Polák i Ukrajinec dostal při timeoutu / vypnutí / chybě češtinu.
// Web = tykání (persona widgetu), appka = vykání (stejně jako dosavadní české texty).
// {phone} / {email} se doplní z company_info. Telefon: podpora Po–Pá 8:00–17:00.
import { normLang } from './site-url.ts';
const M = {
  cs: {
    timeout: 'Promiň, tohle mi teď na mé straně trvalo moc dlouho. Napiš prosím jen „pokračuj" — celou naši konverzaci si pamatuju a navážu přesně tam, kde jsme skončili. Nemusíš nic opakovat.',
    trunc: '\n\n*(Odpověď se nevešla celá — napiš „pokračuj" a dopovím zbytek.)*',
    disabled: 'Asistent je momentálně vypnutý. Zavolejte prosím {phone} (Po–Pá 8:00–17:00) nebo napište na {email}.',
    unavailable: 'AI asistent je dočasně nedostupný — zkus to prosím za chvíli, nebo napiš na {email}.',
    rateLimit: 'Příliš mnoho zpráv za krátkou dobu — zkus to prosím za minutu.',
    appDisabled: 'AI asistent je momentálně vypnutý. Ozvěte se nám prosím na {phone} (Po–Pá 8:00–17:00) nebo {email} — v nouzi použijte SOS tlačítko v aplikaci.',
    appTimeout: 'Omlouvám se, odpověď mi teď trvala moc dlouho. Napište prosím jen „pokračuj" — celou konverzaci si pamatuji a navážu, nemusíte nic opakovat.',
    appNoReply: 'Odpověď teď není k dispozici — zkuste to prosím znovu.',
    appAnalysisFail: 'Omlouvám se, nepodařilo se dokončit analýzu. Zkuste prosím znovu.'
  },
  en: {
    timeout: 'Sorry — that took too long on my side. Just type "continue" — I remember our whole conversation and will pick up right where we left off, no need to repeat anything.',
    trunc: '\n\n*(The reply got cut off — type "continue" and I\'ll finish the rest.)*',
    disabled: 'The assistant is switched off at the moment. Please call {phone} (Mon–Fri 8:00–17:00) or write to {email}.',
    unavailable: 'The AI assistant is temporarily unavailable — please try again in a moment or write to {email}.',
    rateLimit: 'Too many messages in a short time — please try again in a minute.',
    appDisabled: 'The AI assistant is switched off at the moment. Please contact us at {phone} (Mon–Fri 8:00–17:00) or {email} — in an emergency use the SOS button in the app.',
    appTimeout: 'Sorry, that took too long. Just type "continue" — I remember the whole conversation and will pick up where we left off, no need to repeat anything.',
    appNoReply: 'No reply available right now — please try again.',
    appAnalysisFail: 'Sorry, I could not finish the analysis. Please try again.'
  },
  de: {
    timeout: 'Sorry — das hat bei mir gerade zu lange gedauert. Schreib einfach „weiter" — ich habe unser ganzes Gespräch im Kopf und mache genau dort weiter, du musst nichts wiederholen.',
    trunc: '\n\n*(Die Antwort wurde abgeschnitten — schreib „weiter" und ich ergänze den Rest.)*',
    disabled: 'Der Assistent ist gerade ausgeschaltet. Bitte rufen Sie {phone} an (Mo–Fr 8:00–17:00) oder schreiben Sie an {email}.',
    unavailable: 'Der KI-Assistent ist vorübergehend nicht erreichbar — bitte versuch es gleich noch einmal oder schreib an {email}.',
    rateLimit: 'Zu viele Nachrichten in kurzer Zeit — bitte versuch es in einer Minute noch einmal.',
    appDisabled: 'Der KI-Assistent ist gerade ausgeschaltet. Bitte kontaktieren Sie uns unter {phone} (Mo–Fr 8:00–17:00) oder {email} — im Notfall nutzen Sie die SOS-Taste in der App.',
    appTimeout: 'Entschuldigung, die Antwort hat zu lange gedauert. Schreiben Sie einfach „weiter" — ich kenne das ganze Gespräch und mache dort weiter, Sie müssen nichts wiederholen.',
    appNoReply: 'Gerade ist keine Antwort verfügbar — bitte versuchen Sie es erneut.',
    appAnalysisFail: 'Entschuldigung, die Analyse konnte nicht abgeschlossen werden. Bitte versuchen Sie es erneut.'
  },
  es: {
    timeout: 'Perdona, esto me ha tardado demasiado. Escribe solo «continúa»: recuerdo toda nuestra conversación y seguiré justo donde lo dejamos, no hace falta repetir nada.',
    trunc: '\n\n*(La respuesta se ha cortado — escribe «continúa» y termino el resto.)*',
    disabled: 'El asistente está desactivado en este momento. Llama al {phone} (lun–vie 8:00–17:00) o escribe a {email}.',
    unavailable: 'El asistente de IA no está disponible temporalmente — inténtalo de nuevo en un momento o escribe a {email}.',
    rateLimit: 'Demasiados mensajes en poco tiempo — inténtalo de nuevo dentro de un minuto.',
    appDisabled: 'El asistente de IA está desactivado en este momento. Contáctenos en el {phone} (lun–vie 8:00–17:00) o en {email}; en caso de emergencia use el botón SOS de la aplicación.',
    appTimeout: 'Lo siento, la respuesta ha tardado demasiado. Escriba solo «continúa»: recuerdo toda la conversación y seguiré donde lo dejamos, no hace falta repetir nada.',
    appNoReply: 'Ahora no hay respuesta disponible — inténtelo de nuevo.',
    appAnalysisFail: 'Lo siento, no he podido terminar el análisis. Inténtelo de nuevo.'
  },
  fr: {
    timeout: 'Désolé, cela m\'a pris trop de temps. Écris simplement « continue » : je me souviens de toute notre conversation et je reprends exactement là où nous en étions, inutile de répéter.',
    trunc: '\n\n*(La réponse a été coupée — écris « continue » et je termine.)*',
    disabled: 'L\'assistant est désactivé pour le moment. Appelez le {phone} (lun–ven 8h–17h) ou écrivez à {email}.',
    unavailable: 'L\'assistant IA est temporairement indisponible — réessaie dans un instant ou écris à {email}.',
    rateLimit: 'Trop de messages en peu de temps — réessaie dans une minute.',
    appDisabled: 'L\'assistant IA est désactivé pour le moment. Contactez-nous au {phone} (lun–ven 8h–17h) ou à {email} — en cas d\'urgence, utilisez le bouton SOS de l\'application.',
    appTimeout: 'Désolé, la réponse a pris trop de temps. Écrivez simplement « continue » : je me souviens de toute la conversation et je reprends, inutile de répéter.',
    appNoReply: 'Aucune réponse disponible pour le moment — veuillez réessayer.',
    appAnalysisFail: 'Désolé, l\'analyse n\'a pas pu être terminée. Veuillez réessayer.'
  },
  nl: {
    timeout: 'Sorry, dat duurde aan mijn kant te lang. Typ gewoon "ga door" — ik onthoud ons hele gesprek en ga verder waar we gebleven waren, je hoeft niets te herhalen.',
    trunc: '\n\n*(Het antwoord is afgebroken — typ "ga door" en ik maak het af.)*',
    disabled: 'De assistent staat momenteel uit. Bel {phone} (ma–vr 8:00–17:00) of mail naar {email}.',
    unavailable: 'De AI-assistent is tijdelijk niet beschikbaar — probeer het zo opnieuw of mail naar {email}.',
    rateLimit: 'Te veel berichten in korte tijd — probeer het over een minuut opnieuw.',
    appDisabled: 'De AI-assistent staat momenteel uit. Neem contact met ons op via {phone} (ma–vr 8:00–17:00) of {email} — gebruik in noodgevallen de SOS-knop in de app.',
    appTimeout: 'Sorry, het antwoord duurde te lang. Typ gewoon "ga door" — ik onthoud het hele gesprek en ga verder, u hoeft niets te herhalen.',
    appNoReply: 'Er is nu geen antwoord beschikbaar — probeer het opnieuw.',
    appAnalysisFail: 'Sorry, de analyse kon niet worden afgerond. Probeer het opnieuw.'
  },
  pl: {
    timeout: 'Przepraszam, trwało to u mnie za długo. Napisz po prostu „kontynuuj" — pamiętam całą naszą rozmowę i wrócę dokładnie tam, gdzie skończyliśmy, nie musisz niczego powtarzać.',
    trunc: '\n\n*(Odpowiedź została ucięta — napisz „kontynuuj", a dokończę resztę.)*',
    disabled: 'Asystent jest obecnie wyłączony. Zadzwoń pod {phone} (pon.–pt. 8:00–17:00) lub napisz na {email}.',
    unavailable: 'Asystent AI jest chwilowo niedostępny — spróbuj ponownie za chwilę lub napisz na {email}.',
    rateLimit: 'Zbyt wiele wiadomości w krótkim czasie — spróbuj ponownie za minutę.',
    appDisabled: 'Asystent AI jest obecnie wyłączony. Skontaktuj się z nami: {phone} (pon.–pt. 8:00–17:00) lub {email} — w nagłych przypadkach użyj przycisku SOS w aplikacji.',
    appTimeout: 'Przepraszam, odpowiedź trwała za długo. Napisz po prostu „kontynuuj" — pamiętam całą rozmowę i będę kontynuować, nie trzeba niczego powtarzać.',
    appNoReply: 'Odpowiedź jest teraz niedostępna — spróbuj ponownie.',
    appAnalysisFail: 'Przepraszam, nie udało się dokończyć analizy. Spróbuj ponownie.'
  },
  uk: {
    timeout: 'Вибач, у мене це зайняло забагато часу. Просто напиши «продовжуй» — я пам\'ятаю всю нашу розмову і продовжу саме з того місця, нічого не потрібно повторювати.',
    trunc: '\n\n*(Відповідь обірвалася — напиши «продовжуй», і я допишу решту.)*',
    disabled: 'Асистент зараз вимкнений. Зателефонуйте за номером {phone} (пн–пт 8:00–17:00) або напишіть на {email}.',
    unavailable: 'AI-асистент тимчасово недоступний — спробуй ще раз за хвилинку або напиши на {email}.',
    rateLimit: 'Забагато повідомлень за короткий час — спробуй ще раз за хвилину.',
    appDisabled: 'AI-асистент зараз вимкнений. Зв\'яжіться з нами за номером {phone} (пн–пт 8:00–17:00) або {email} — у надзвичайній ситуації скористайтеся кнопкою SOS у застосунку.',
    appTimeout: 'Вибачте, відповідь зайняла забагато часу. Просто напишіть «продовжуй» — я пам\'ятаю всю розмову і продовжу, нічого не потрібно повторювати.',
    appNoReply: 'Відповідь зараз недоступна — спробуйте ще раз.',
    appAnalysisFail: 'Вибачте, не вдалося завершити аналіз. Спробуйте ще раз.'
  }
};
/** Lokalizovaná hláška; {phone}/{email} z company_info (fallback firemní kontakty). */ export function agentMsg(lang, key, contact) {
  const t = M[normLang(lang)][key] || M.cs[key];
  return t.replace('{phone}', contact?.phone || '+420 774 256 271').replace('{email}', contact?.email || 'info@motogo24.cz');
}
