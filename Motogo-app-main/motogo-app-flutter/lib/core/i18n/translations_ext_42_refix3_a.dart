/// Chybové stavy — 3. kolo (2026-10-16): motorka už není v nabídce, varianty
/// chyb PŘIHLÁŠENÍ (účet existuje — ne texty registrace), průběh s „Zrušit"
/// na slabém signálu, nahrávání dokladu z galerie. Klíče `r3*`, cs/en/de/es
/// (fr/nl/pl/uk v `_b`). Tyká se; `r3Auth*` drží oslovení textů
/// `AuthErrorMapper` daného jazyka (zobrazují se s jeho titulky).
const Map<String, Map<String, String>> translationsExt42Refix3A = {
  'cs': {
    'r3MotoGoneTitle': 'Tuhle motorku teď nenabízíme',
    'r3MotoGoneBody': 'Motorka byla z nabídky stažená – třeba kvůli servisu nebo vyřazení. Vyber si jinou motorku. Případnou rezervaci najdeš dál v Rezervacích.',
    'r3PickOtherMoto': 'Vybrat jinou motorku',
    'r3AuthNetBodyIn': 'Zkontroluj připojení k internetu (Wi-Fi nebo mobilní data) a zkus to znovu. Máš-li zapnutou VPN nebo jsi na firemní síti, vypni ji. S tvým účtem je vše v pořádku – jen se k nám telefon teď nedostal.',
    'r3AuthServerBodyIn': 'Přihlášení teď nejde kvůli chybě na našem serveru – není to tvoje chyba a s účtem je vše v pořádku. Zkus to za chvíli znovu; když to nepomůže, ozvi se nám na info@motogo24.cz / +420 774 256 271.',
    'r3AuthRateBodyIn': 'Pokusů o přihlášení bylo v krátké době moc, proto je server na chvíli pozastavil. Počkej pár minut a zkus to znovu. Nevíš-li heslo, nech si poslat nové přes „Zapomenuté heslo".',
    'r3SlowHint': 'Trvá to déle než obvykle – nejspíš slabý signál. Můžeš počkat, nebo to zrušit a zkusit později.',
    'r3UploadStoppedTitle': 'Přestali jsme čekat na nahrání',
    'r3UploadStoppedBody': 'Spojení je teď moc pomalé. Kdyby se doklad mezitím přece jen nahrál, objeví se v seznamu. Jinak to zkus znovu na lepším signálu nebo Wi-Fi.',
    'r3SavingDocPhoto': 'Ukládám fotku dokladu…',
  },
  'en': {
    'r3MotoGoneTitle': 'We don’t offer this motorcycle right now',
    'r3MotoGoneBody': 'The motorcycle has been taken out of our offer – for example for servicing or retirement. Please choose another one. Any booking you have stays in Reservations.',
    'r3PickOtherMoto': 'Choose another motorcycle',
    'r3AuthNetBodyIn': 'Check your internet connection (Wi-Fi or mobile data) and try again. If you use a VPN or a corporate network, turn it off. Your account is fine – your phone just couldn’t reach us right now.',
    'r3AuthServerBodyIn': 'Signing in isn’t possible right now because of an error on our server – it’s not your fault and your account is fine. Please try again shortly; if it keeps failing, contact us at info@motogo24.cz / +420 774 256 271.',
    'r3AuthRateBodyIn': 'There were too many sign-in attempts in a short time, so the server has paused them for a while. Wait a few minutes and try again. If you don’t remember your password, request a new one via "Forgot password".',
    'r3SlowHint': 'This is taking longer than usual – probably a weak signal. You can wait, or cancel and try again later.',
    'r3UploadStoppedTitle': 'We stopped waiting for the upload',
    'r3UploadStoppedBody': 'The connection is very slow right now. If the document still got uploaded in the meantime, it will appear in the list. Otherwise try again with a better signal or on Wi-Fi.',
    'r3SavingDocPhoto': 'Saving the document photo…',
  },
  'de': {
    'r3MotoGoneTitle': 'Dieses Motorrad bieten wir gerade nicht an',
    'r3MotoGoneBody': 'Das Motorrad wurde aus dem Angebot genommen – etwa wegen Wartung oder Ausmusterung. Wähle bitte ein anderes. Eine bestehende Buchung findest du weiterhin unter Reservierungen.',
    'r3PickOtherMoto': 'Anderes Motorrad wählen',
    'r3AuthNetBodyIn': 'Prüfen Sie Ihre Internetverbindung (WLAN oder mobile Daten) und versuchen Sie es erneut. Falls Sie ein VPN oder ein Firmennetz nutzen, schalten Sie es aus. Mit Ihrem Konto ist alles in Ordnung – Ihr Handy hat uns nur gerade nicht erreicht.',
    'r3AuthServerBodyIn': 'Die Anmeldung ist gerade wegen eines Fehlers auf unserem Server nicht möglich – das liegt nicht an Ihnen, Ihr Konto ist in Ordnung. Bitte versuchen Sie es gleich noch einmal; wenn es weiterhin fehlschlägt, schreiben Sie uns an info@motogo24.cz / +420 774 256 271.',
    'r3AuthRateBodyIn': 'In kurzer Zeit gab es zu viele Anmeldeversuche, daher hat der Server sie vorübergehend gestoppt. Warten Sie ein paar Minuten und versuchen Sie es erneut. Falls Sie Ihr Passwort nicht mehr wissen, fordern Sie über „Passwort vergessen" ein neues an.',
    'r3SlowHint': 'Das dauert länger als üblich – wahrscheinlich ein schwaches Signal. Du kannst warten oder abbrechen und es später noch einmal versuchen.',
    'r3UploadStoppedTitle': 'Wir warten nicht mehr auf den Upload',
    'r3UploadStoppedBody': 'Die Verbindung ist gerade sehr langsam. Falls das Dokument inzwischen doch hochgeladen wurde, erscheint es in der Liste. Sonst versuch es mit besserem Signal oder im WLAN noch einmal.',
    'r3SavingDocPhoto': 'Foto des Dokuments wird gespeichert…',
  },
  'es': {
    'r3MotoGoneTitle': 'Ahora no ofrecemos esta moto',
    'r3MotoGoneBody': 'La moto se ha retirado de la oferta, por ejemplo por mantenimiento o baja. Elige otra, por favor. Si tienes una reserva, la sigues encontrando en Reservas.',
    'r3PickOtherMoto': 'Elegir otra moto',
    'r3AuthNetBodyIn': 'Comprueba tu conexión a internet (Wi-Fi o datos móviles) e inténtalo otra vez. Si usas VPN o una red corporativa, desactívala. Tu cuenta está bien: simplemente tu móvil no ha podido conectar con nosotros.',
    'r3AuthServerBodyIn': 'Ahora no se puede iniciar sesión por un error en nuestro servidor; no es culpa tuya y tu cuenta está bien. Inténtalo de nuevo en un momento; si sigue fallando, escríbenos a info@motogo24.cz / +420 774 256 271.',
    'r3AuthRateBodyIn': 'Ha habido demasiados intentos de inicio de sesión en poco tiempo, así que el servidor los ha pausado un rato. Espera unos minutos e inténtalo de nuevo. Si no recuerdas la contraseña, pide una nueva con «He olvidado la contraseña».',
    'r3SlowHint': 'Está tardando más de lo habitual, probablemente por poca cobertura. Puedes esperar o cancelar e intentarlo más tarde.',
    'r3UploadStoppedTitle': 'Hemos dejado de esperar la subida',
    'r3UploadStoppedBody': 'La conexión es muy lenta ahora mismo. Si el documento llega a subirse, aparecerá en la lista. Si no, inténtalo de nuevo con mejor cobertura o por Wi-Fi.',
    'r3SavingDocPhoto': 'Guardando la foto del documento…',
  },
};
