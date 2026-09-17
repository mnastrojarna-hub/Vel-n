import 'dart:async';
import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Výsledek mapování chyby registrace / přihlášení.
/// Zákazník nesmí zůstat u holého „Chyba registrace" — pro každý známý problém
/// vracíme konkrétní titulek (CO je špatně) a tělo (KDE to je a co s tím).
class AuthErrorInfo {
  /// Titulek do toastu — nahrazuje generické „Chyba registrace".
  final String title;

  /// Vysvětlení příčiny + návod, co má zákazník udělat.
  final String message;

  /// Technický kód pro `app_debug_logs` (v UI se nezobrazuje).
  final String code;

  /// Krok registračního průvodce, ve kterém je vadné pole (1–3), nebo null,
  /// když chyba k žádnému poli nepatří (síť, server, rate limit). Formulář se
  /// na tento krok vrátí — zákazník tak vidí, KDE problém je, ne jen ŽE je.
  final int? step;

  const AuthErrorInfo({
    required this.title,
    required this.message,
    this.code = 'unknown',
    this.step,
  });
}

/// Mapuje technické chyby Supabase Auth (anglické hlášky GoTrue, síťové
/// výjimky) na srozumitelné hlášky s konkrétní příčinou a nápravou.
///
/// Záměrně self-contained (vlastní tabulka textů, stejně jako
/// `PaymentErrorMapper`) — hlášky o chybě registrace musí být přeložené i
/// v situaci, kdy se appka nedostane k ničemu dalšímu.
class AuthErrorMapper {
  AuthErrorMapper._();

  /// Chyba při REGISTRACI. [error] je cokoli, co spadlo z `auth.signUp`.
  static AuthErrorInfo signUp(Object? error, String lang) =>
      _map(error, lang, isSignUp: true);

  /// Chyba při PŘIHLÁŠENÍ.
  static AuthErrorInfo signIn(Object? error, String lang) =>
      _map(error, lang, isSignUp: false);

  /// E-mail už u nás účet má. Voláme i bez výjimky — Supabase při zapnutém
  /// potvrzení e-mailu duplicitu NEhlásí chybou, jen vrátí uživatele
  /// s prázdným polem `identities` (anti-enumeration).
  static AuthErrorInfo emailTaken(String lang) => AuthErrorInfo(
        title: _t(lang, 'emailTakenTitle'),
        message: _t(lang, 'emailTakenBody'),
        code: 'email_taken',
        step: 1,
      );

  static AuthErrorInfo _map(Object? error, String lang, {required bool isSignUp}) {
    final raw = error?.toString() ?? '';
    final msg = (error is AuthException ? error.message : raw).toLowerCase();

    // ── Síť / server nedostupný ──────────────────────────────────────────
    if (error is SocketException ||
        error is TimeoutException ||
        error is AuthRetryableFetchException ||
        msg.contains('failed host lookup') ||
        msg.contains('socketexception') ||
        msg.contains('clientexception') ||
        msg.contains('connection closed') ||
        msg.contains('connection refused') ||
        msg.contains('network is unreachable') ||
        msg.contains('timeout') ||
        msg.contains('timed out')) {
      return AuthErrorInfo(
        title: _t(lang, 'networkTitle'),
        message: _t(lang, 'networkBody'),
        code: 'network',
      );
    }

    // ── E-mail už je registrovaný ────────────────────────────────────────
    if (msg.contains('already registered') ||
        msg.contains('already been registered') ||
        msg.contains('user_already_exists') ||
        msg.contains('email_exists') ||
        msg.contains('already exists')) {
      return emailTaken(lang);
    }

    // ── Heslo ────────────────────────────────────────────────────────────
    if (msg.contains('weak_password') ||
        msg.contains('password should be') ||
        msg.contains('password is too short') ||
        msg.contains('requires a valid password')) {
      return AuthErrorInfo(
        title: _t(lang, 'weakPasswordTitle'),
        message: _t(lang, 'weakPasswordBody'),
        code: 'weak_password',
        step: 1,
      );
    }

    // ── E-mail ve špatném tvaru / odmítnutý ──────────────────────────────
    if (msg.contains('unable to validate email') ||
        msg.contains('email_address_invalid') ||
        msg.contains('invalid email') ||
        (msg.contains('email address') && msg.contains('invalid'))) {
      return AuthErrorInfo(
        title: _t(lang, 'invalidEmailTitle'),
        message: _t(lang, 'invalidEmailBody'),
        code: 'invalid_email',
        step: 1,
      );
    }

    // ── Rate limit (moc pokusů / moc potvrzovacích mailů) ────────────────
    if (msg.contains('rate limit') ||
        msg.contains('over_email_send_rate_limit') ||
        msg.contains('over_request_rate_limit') ||
        msg.contains('for security purposes') ||
        msg.contains('too many requests') ||
        (error is AuthException && error.statusCode == '429')) {
      return AuthErrorInfo(
        title: _t(lang, 'rateLimitTitle'),
        message: _t(lang, 'rateLimitBody'),
        code: 'rate_limit',
      );
    }

    // ── Registrace vypnutá na serveru ────────────────────────────────────
    if (msg.contains('signups not allowed') ||
        msg.contains('signup_disabled') ||
        msg.contains('email signups are disabled')) {
      return AuthErrorInfo(
        title: _t(lang, 'disabledTitle'),
        message: _t(lang, 'disabledBody'),
        code: 'signup_disabled',
      );
    }

    // ── Chyba na naší straně (trigger handle_new_user apod.) ─────────────
    if (msg.contains('database error') ||
        msg.contains('unexpected_failure') ||
        (error is AuthException && error.statusCode == '500')) {
      return AuthErrorInfo(
        title: _t(lang, 'serverTitle'),
        message: _t(lang, 'serverBody'),
        code: 'server_error',
      );
    }

    // ── Přihlášení: špatné údaje / nepotvrzený e-mail ────────────────────
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return AuthErrorInfo(
        title: _t(lang, 'credentialsTitle'),
        message: _t(lang, 'credentialsBody'),
        code: 'invalid_credentials',
      );
    }
    if (msg.contains('email not confirmed') || msg.contains('email_not_confirmed')) {
      return AuthErrorInfo(
        title: _t(lang, 'unconfirmedTitle'),
        message: _t(lang, 'unconfirmedBody'),
        code: 'email_not_confirmed',
      );
    }

    // ── Neznámá chyba — ukaž aspoň původní text, ať víme, KDE to vázne ───
    final detail = _shorten(error is AuthException ? error.message : raw);
    return AuthErrorInfo(
      title: _t(lang, isSignUp ? 'genericSignUpTitle' : 'genericSignInTitle'),
      message: detail.isEmpty
          ? _t(lang, 'genericBody')
          : '${_t(lang, 'genericBody')}\n$detail',
      code: 'unknown',
    );
  }

  /// Ořízne technický text na délku, která se ještě vejde do toastu.
  static String _shorten(String s) {
    final clean = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return '';
    return clean.length <= 160 ? clean : '${clean.substring(0, 157)}…';
  }

  static String _t(String lang, String key) {
    final l = lang.isEmpty ? 'cs' : lang.substring(0, lang.length.clamp(0, 2));
    final m = _strings[l] ?? _strings['cs']!;
    return m[key] ?? _strings['cs']![key] ?? key;
  }

  static const _contactCs = 'info@motogo24.cz / +420 774 256 271';

  static const Map<String, Map<String, String>> _strings = {
    'cs': {
      'emailTakenTitle': 'Tento e-mail už u nás účet má',
      'emailTakenBody':
          'Na tuto adresu už je účet založený — často vznikne automaticky při rezervaci na webu. Přihlaste se stejným e-mailem; heslo si můžete nechat poslat přes „Zapomenuté heslo".',
      'weakPasswordTitle': 'Heslo je příliš slabé',
      'weakPasswordBody':
          'Zvolte prosím heslo alespoň o 8 znacích, ideálně kombinaci písmen a číslic.',
      'invalidEmailTitle': 'E-mail není ve správném tvaru',
      'invalidEmailBody':
          'Zkontrolujte adresu — nejčastěji je v ní mezera, překlep v doméně (např. @gmial.com) nebo chybí tečka.',
      'rateLimitTitle': 'Příliš mnoho pokusů po sobě',
      'rateLimitBody':
          'Registraci jste zkoušeli několikrát rychle za sebou. Počkejte prosím pár minut a zkuste to znovu.',
      'networkTitle': 'Nepodařilo se spojit se serverem',
      'networkBody':
          'Zkontrolujte připojení k internetu (Wi-Fi nebo mobilní data) a zkuste to znovu. Máte-li zapnutou VPN nebo jste na firemní síti, vypněte ji. Účet zatím nevznikl.',
      'serverTitle': 'Chyba na naší straně',
      'serverBody':
          'Účet se nepodařilo založit kvůli chybě serveru. Zkuste to prosím za chvíli znovu — pokud to nepomůže, ozvěte se nám na $_contactCs.',
      'disabledTitle': 'Registrace je dočasně vypnutá',
      'disabledBody':
          'Nové účty teď nejde zakládat. Zkuste to prosím později, nebo nám napište na $_contactCs.',
      'credentialsTitle': 'Nesprávný e-mail nebo heslo',
      'credentialsBody':
          'Zkontrolujte překlepy a velká písmena. Nové heslo si můžete nechat poslat přes „Zapomenuté heslo".',
      'unconfirmedTitle': 'E-mail zatím není potvrzený',
      'unconfirmedBody':
          'Otevřete e-mail od MotoGo24 a klepněte na potvrzovací odkaz. Podívejte se i do složky Spam / Hromadné.',
      'genericSignUpTitle': 'Registraci se nepodařilo dokončit',
      'genericSignInTitle': 'Přihlášení se nezdařilo',
      'genericBody':
          'Zkuste to prosím znovu. Pokud chyba trvá, ozvěte se nám na $_contactCs a přepošlete nám tento text:',
    },
    'en': {
      'emailTakenTitle': 'This e-mail already has an account',
      'emailTakenBody':
          'An account already exists for this address — it is often created automatically when you book on our website. Sign in with the same e-mail; you can request a new password via "Forgot password".',
      'weakPasswordTitle': 'Password is too weak',
      'weakPasswordBody':
          'Please choose a password with at least 8 characters, ideally letters and digits combined.',
      'invalidEmailTitle': 'E-mail format is not valid',
      'invalidEmailBody':
          'Check the address — usually there is a space, a typo in the domain (e.g. @gmial.com) or a missing dot.',
      'rateLimitTitle': 'Too many attempts in a row',
      'rateLimitBody':
          'You tried to register several times in quick succession. Please wait a few minutes and try again.',
      'networkTitle': 'Could not reach the server',
      'networkBody':
          'Check your internet connection (Wi-Fi or mobile data) and try again. If you use a VPN or a corporate network, turn it off. No account has been created yet.',
      'serverTitle': 'Error on our side',
      'serverBody':
          'The account could not be created because of a server error. Please try again shortly — if it keeps failing, contact us at $_contactCs.',
      'disabledTitle': 'Registration is temporarily disabled',
      'disabledBody':
          'New accounts cannot be created right now. Please try later or write to us at $_contactCs.',
      'credentialsTitle': 'Wrong e-mail or password',
      'credentialsBody':
          'Check for typos and capital letters. You can request a new password via "Forgot password".',
      'unconfirmedTitle': 'E-mail is not confirmed yet',
      'unconfirmedBody':
          'Open the e-mail from MotoGo24 and tap the confirmation link. Check your Spam / Promotions folder too.',
      'genericSignUpTitle': 'Registration could not be completed',
      'genericSignInTitle': 'Sign-in failed',
      'genericBody':
          'Please try again. If the error persists, contact us at $_contactCs and forward this text:',
    },
    'de': {
      'emailTakenTitle': 'Für diese E-Mail gibt es bereits ein Konto',
      'emailTakenBody':
          'Zu dieser Adresse besteht schon ein Konto — es entsteht oft automatisch bei einer Buchung auf unserer Website. Melden Sie sich mit derselben E-Mail an; ein neues Passwort erhalten Sie über „Passwort vergessen".',
      'weakPasswordTitle': 'Passwort ist zu schwach',
      'weakPasswordBody':
          'Bitte wählen Sie ein Passwort mit mindestens 8 Zeichen, idealerweise Buchstaben und Ziffern kombiniert.',
      'invalidEmailTitle': 'E-Mail-Format ist ungültig',
      'invalidEmailBody':
          'Prüfen Sie die Adresse — meist ist ein Leerzeichen, ein Tippfehler in der Domain (z. B. @gmial.com) oder ein fehlender Punkt die Ursache.',
      'rateLimitTitle': 'Zu viele Versuche hintereinander',
      'rateLimitBody':
          'Sie haben die Registrierung mehrmals kurz hintereinander versucht. Bitte warten Sie ein paar Minuten und versuchen Sie es erneut.',
      'networkTitle': 'Server nicht erreichbar',
      'networkBody':
          'Prüfen Sie Ihre Internetverbindung (WLAN oder mobile Daten) und versuchen Sie es erneut. Falls Sie ein VPN oder ein Firmennetz nutzen, schalten Sie es aus. Es wurde noch kein Konto angelegt.',
      'serverTitle': 'Fehler auf unserer Seite',
      'serverBody':
          'Das Konto konnte wegen eines Serverfehlers nicht angelegt werden. Bitte versuchen Sie es gleich noch einmal — wenn es weiterhin fehlschlägt, schreiben Sie uns an $_contactCs.',
      'disabledTitle': 'Registrierung ist vorübergehend deaktiviert',
      'disabledBody':
          'Neue Konten können derzeit nicht angelegt werden. Bitte später erneut versuchen oder schreiben Sie an $_contactCs.',
      'credentialsTitle': 'Falsche E-Mail oder falsches Passwort',
      'credentialsBody':
          'Achten Sie auf Tippfehler und Großschreibung. Ein neues Passwort erhalten Sie über „Passwort vergessen".',
      'unconfirmedTitle': 'E-Mail ist noch nicht bestätigt',
      'unconfirmedBody':
          'Öffnen Sie die E-Mail von MotoGo24 und tippen Sie auf den Bestätigungslink. Schauen Sie auch im Spam-Ordner nach.',
      'genericSignUpTitle': 'Registrierung konnte nicht abgeschlossen werden',
      'genericSignInTitle': 'Anmeldung fehlgeschlagen',
      'genericBody':
          'Bitte versuchen Sie es erneut. Bleibt der Fehler, schreiben Sie uns an $_contactCs und leiten Sie diesen Text weiter:',
    },
    'pl': {
      'emailTakenTitle': 'Ten e-mail ma już konto',
      'emailTakenBody':
          'Dla tego adresu istnieje już konto — często powstaje automatycznie przy rezerwacji na naszej stronie. Zaloguj się tym samym e-mailem; nowe hasło otrzymasz przez „Nie pamiętam hasła".',
      'weakPasswordTitle': 'Hasło jest za słabe',
      'weakPasswordBody':
          'Wybierz hasło o długości co najmniej 8 znaków, najlepiej litery i cyfry.',
      'invalidEmailTitle': 'Nieprawidłowy format e-maila',
      'invalidEmailBody':
          'Sprawdź adres — najczęściej jest w nim spacja, literówka w domenie (np. @gmial.com) albo brakuje kropki.',
      'rateLimitTitle': 'Zbyt wiele prób pod rząd',
      'rateLimitBody':
          'Rejestracja była próbowana kilka razy w krótkim czasie. Odczekaj kilka minut i spróbuj ponownie.',
      'networkTitle': 'Nie udało się połączyć z serwerem',
      'networkBody':
          'Sprawdź połączenie z internetem (Wi-Fi lub dane mobilne) i spróbuj ponownie. Jeśli używasz VPN lub sieci firmowej, wyłącz ją. Konto jeszcze nie powstało.',
      'serverTitle': 'Błąd po naszej stronie',
      'serverBody':
          'Konta nie udało się założyć z powodu błędu serwera. Spróbuj za chwilę ponownie — jeśli to nie pomoże, napisz na $_contactCs.',
      'disabledTitle': 'Rejestracja jest tymczasowo wyłączona',
      'disabledBody':
          'Nowych kont nie można teraz zakładać. Spróbuj później albo napisz na $_contactCs.',
      'credentialsTitle': 'Błędny e-mail lub hasło',
      'credentialsBody':
          'Sprawdź literówki i wielkie litery. Nowe hasło otrzymasz przez „Nie pamiętam hasła".',
      'unconfirmedTitle': 'E-mail nie jest jeszcze potwierdzony',
      'unconfirmedBody':
          'Otwórz e-mail od MotoGo24 i kliknij link potwierdzający. Sprawdź też folder Spam.',
      'genericSignUpTitle': 'Nie udało się dokończyć rejestracji',
      'genericSignInTitle': 'Logowanie nie powiodło się',
      'genericBody':
          'Spróbuj ponownie. Jeśli błąd się powtarza, napisz na $_contactCs i prześlij nam ten tekst:',
    },
    'uk': {
      'emailTakenTitle': 'Для цієї пошти вже є обліковий запис',
      'emailTakenBody':
          'На цю адресу вже створено обліковий запис — часто він виникає автоматично під час бронювання на сайті. Увійдіть із тією самою поштою; новий пароль можна отримати через «Забули пароль».',
      'weakPasswordTitle': 'Пароль надто слабкий',
      'weakPasswordBody':
          'Оберіть пароль щонайменше з 8 символів, найкраще з літер і цифр.',
      'invalidEmailTitle': 'Неправильний формат пошти',
      'invalidEmailBody':
          'Перевірте адресу — найчастіше в ній пробіл, помилка в домені (напр. @gmial.com) або бракує крапки.',
      'rateLimitTitle': 'Забагато спроб поспіль',
      'rateLimitBody':
          'Ви намагалися зареєструватися кілька разів поспіль. Зачекайте кілька хвилин і спробуйте знову.',
      'networkTitle': 'Не вдалося зв’язатися із сервером',
      'networkBody':
          'Перевірте підключення до інтернету (Wi-Fi або мобільні дані) і спробуйте знову. Якщо увімкнено VPN або ви в корпоративній мережі, вимкніть їх. Обліковий запис ще не створено.',
      'serverTitle': 'Помилка на нашому боці',
      'serverBody':
          'Обліковий запис не вдалося створити через помилку сервера. Спробуйте за хвилину знову — якщо не допоможе, напишіть на $_contactCs.',
      'disabledTitle': 'Реєстрацію тимчасово вимкнено',
      'disabledBody':
          'Нові облікові записи зараз створити не можна. Спробуйте пізніше або напишіть на $_contactCs.',
      'credentialsTitle': 'Невірна пошта або пароль',
      'credentialsBody':
          'Перевірте помилки та великі літери. Новий пароль можна отримати через «Забули пароль».',
      'unconfirmedTitle': 'Пошту ще не підтверджено',
      'unconfirmedBody':
          'Відкрийте лист від MotoGo24 і натисніть посилання підтвердження. Перевірте також теку Спам.',
      'genericSignUpTitle': 'Не вдалося завершити реєстрацію',
      'genericSignInTitle': 'Не вдалося увійти',
      'genericBody':
          'Спробуйте ще раз. Якщо помилка триває, напишіть на $_contactCs і перешліть цей текст:',
    },
    'es': {
      'emailTakenTitle': 'Este correo ya tiene una cuenta',
      'emailTakenBody':
          'Ya existe una cuenta con esta dirección — suele crearse automáticamente al reservar en nuestra web. Inicia sesión con el mismo correo; puedes pedir una nueva contraseña con «He olvidado la contraseña».',
      'weakPasswordTitle': 'La contraseña es demasiado débil',
      'weakPasswordBody':
          'Elige una contraseña de al menos 8 caracteres, preferiblemente con letras y números.',
      'invalidEmailTitle': 'El formato del correo no es válido',
      'invalidEmailBody':
          'Revisa la dirección — normalmente hay un espacio, una errata en el dominio (p. ej. @gmial.com) o falta un punto.',
      'rateLimitTitle': 'Demasiados intentos seguidos',
      'rateLimitBody':
          'Has intentado registrarte varias veces seguidas. Espera unos minutos e inténtalo de nuevo.',
      'networkTitle': 'No se pudo conectar con el servidor',
      'networkBody':
          'Comprueba tu conexión a internet (Wi-Fi o datos móviles) e inténtalo otra vez. Si usas VPN o una red corporativa, desactívala. Todavía no se ha creado ninguna cuenta.',
      'serverTitle': 'Error por nuestra parte',
      'serverBody':
          'No se pudo crear la cuenta por un error del servidor. Inténtalo de nuevo en un momento — si sigue fallando, escríbenos a $_contactCs.',
      'disabledTitle': 'El registro está desactivado temporalmente',
      'disabledBody':
          'Ahora no se pueden crear cuentas nuevas. Inténtalo más tarde o escríbenos a $_contactCs.',
      'credentialsTitle': 'Correo o contraseña incorrectos',
      'credentialsBody':
          'Revisa las erratas y las mayúsculas. Puedes pedir una contraseña nueva con «He olvidado la contraseña».',
      'unconfirmedTitle': 'El correo aún no está confirmado',
      'unconfirmedBody':
          'Abre el correo de MotoGo24 y pulsa el enlace de confirmación. Mira también en la carpeta de Spam.',
      'genericSignUpTitle': 'No se ha podido completar el registro',
      'genericSignInTitle': 'No se ha podido iniciar sesión',
      'genericBody':
          'Inténtalo de nuevo. Si el error persiste, escríbenos a $_contactCs y reenvíanos este texto:',
    },
    'fr': {
      'emailTakenTitle': 'Cet e-mail a déjà un compte',
      'emailTakenBody':
          'Un compte existe déjà pour cette adresse — il est souvent créé automatiquement lors d’une réservation sur notre site. Connectez-vous avec le même e-mail ; vous pouvez demander un nouveau mot de passe via « Mot de passe oublié ».',
      'weakPasswordTitle': 'Mot de passe trop faible',
      'weakPasswordBody':
          'Choisissez un mot de passe d’au moins 8 caractères, idéalement des lettres et des chiffres.',
      'invalidEmailTitle': 'Format d’e-mail invalide',
      'invalidEmailBody':
          'Vérifiez l’adresse — le plus souvent il y a un espace, une faute dans le domaine (p. ex. @gmial.com) ou un point manquant.',
      'rateLimitTitle': 'Trop de tentatives d’affilée',
      'rateLimitBody':
          'Vous avez essayé de vous inscrire plusieurs fois coup sur coup. Attendez quelques minutes puis réessayez.',
      'networkTitle': 'Impossible de joindre le serveur',
      'networkBody':
          'Vérifiez votre connexion internet (Wi-Fi ou données mobiles) et réessayez. Si vous utilisez un VPN ou un réseau d’entreprise, désactivez-le. Aucun compte n’a encore été créé.',
      'serverTitle': 'Erreur de notre côté',
      'serverBody':
          'Le compte n’a pas pu être créé à cause d’une erreur serveur. Réessayez dans un instant — si cela persiste, écrivez-nous à $_contactCs.',
      'disabledTitle': 'Inscription temporairement désactivée',
      'disabledBody':
          'Impossible de créer de nouveaux comptes pour l’instant. Réessayez plus tard ou écrivez-nous à $_contactCs.',
      'credentialsTitle': 'E-mail ou mot de passe incorrect',
      'credentialsBody':
          'Vérifiez les fautes de frappe et les majuscules. Vous pouvez demander un nouveau mot de passe via « Mot de passe oublié ».',
      'unconfirmedTitle': 'E-mail pas encore confirmé',
      'unconfirmedBody':
          'Ouvrez l’e-mail de MotoGo24 et appuyez sur le lien de confirmation. Regardez aussi dans le dossier Spam.',
      'genericSignUpTitle': 'L’inscription n’a pas pu être terminée',
      'genericSignInTitle': 'La connexion a échoué',
      'genericBody':
          'Réessayez. Si l’erreur persiste, écrivez-nous à $_contactCs en nous transmettant ce texte :',
    },
    'nl': {
      'emailTakenTitle': 'Dit e-mailadres heeft al een account',
      'emailTakenBody':
          'Er bestaat al een account met dit adres — vaak ontstaat het automatisch bij een reservering op onze website. Log in met hetzelfde e-mailadres; een nieuw wachtwoord vraagt u aan via „Wachtwoord vergeten".',
      'weakPasswordTitle': 'Wachtwoord is te zwak',
      'weakPasswordBody':
          'Kies een wachtwoord van minstens 8 tekens, bij voorkeur letters en cijfers.',
      'invalidEmailTitle': 'E-mailadres heeft geen geldige vorm',
      'invalidEmailBody':
          'Controleer het adres — meestal staat er een spatie in, een typefout in het domein (bijv. @gmial.com) of ontbreekt een punt.',
      'rateLimitTitle': 'Te veel pogingen achter elkaar',
      'rateLimitBody':
          'U hebt kort achter elkaar meerdere keren geprobeerd te registreren. Wacht een paar minuten en probeer het opnieuw.',
      'networkTitle': 'Kon de server niet bereiken',
      'networkBody':
          'Controleer uw internetverbinding (wifi of mobiele data) en probeer het opnieuw. Gebruikt u een VPN of een bedrijfsnetwerk, schakel dat dan uit. Er is nog geen account aangemaakt.',
      'serverTitle': 'Fout aan onze kant',
      'serverBody':
          'Het account kon niet worden aangemaakt door een serverfout. Probeer het zo meteen opnieuw — lukt het dan nog niet, mail ons op $_contactCs.',
      'disabledTitle': 'Registratie is tijdelijk uitgeschakeld',
      'disabledBody':
          'Er kunnen nu geen nieuwe accounts worden aangemaakt. Probeer het later of mail ons op $_contactCs.',
      'credentialsTitle': 'Onjuist e-mailadres of wachtwoord',
      'credentialsBody':
          'Let op typefouten en hoofdletters. Een nieuw wachtwoord vraagt u aan via „Wachtwoord vergeten".',
      'unconfirmedTitle': 'E-mailadres is nog niet bevestigd',
      'unconfirmedBody':
          'Open de e-mail van MotoGo24 en tik op de bevestigingslink. Kijk ook in de map Spam.',
      'genericSignUpTitle': 'Registratie kon niet worden voltooid',
      'genericSignInTitle': 'Inloggen is mislukt',
      'genericBody':
          'Probeer het opnieuw. Blijft de fout, mail ons dan op $_contactCs en stuur deze tekst mee:',
    },
  };
}
