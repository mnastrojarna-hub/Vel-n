/// Odkazy na veřejný web MotoGo24.
///
/// Web řeší jazyky DOMÉNOU (ne cestou) — každý jazyk má vlastní TLD. Zrcadlí
/// `I18N_DOMAIN_MAP` z `motogo-web-php/i18n.php`. Kanonický host je VŽDY `www.`
/// varianta — holá doména (bez www) nemusí mít platný TLS certifikát
/// (Let's Encrypt je jen na www.), takže odkazy musí www obsahovat.
/// Ukrajinština nemá vlastní TLD — bydlí na .com s `?lang=uk` (web si jazyk
/// uloží do cookie `mg_web_lang`).
class WebLinks {
  WebLinks._();

  static const _domainByLang = <String, String>{
    'cs': 'motogo24.cz',
    'en': 'motogo24.com',
    'de': 'motogo24.at',
    'es': 'motogo24.es',
    'pl': 'motogo24.pl',
    'fr': 'motogo24.fr',
    'nl': 'motogo24.nl',
    'uk': 'motogo24.com',
  };

  /// Jazyky bez vlastní domény → `?lang=xx`.
  static const _langQuery = <String>{'uk'};

  /// Doména webu pro daný jazyk (neznámý jazyk → mezinárodní .com).
  static String _domain(String lang) =>
      _domainByLang[lang] ?? _domainByLang['en']!;

  static String _withLang(String url, String lang) =>
      _langQuery.contains(lang) ? '$url?lang=$lang' : url;

  /// Kanonický web origin (vždy s www.) v jazyce zákazníka.
  static String home(String lang) => _withLang('https://www.${_domain(lang)}', lang);

  /// FAQ / časté dotazy — web route `/jak-pujcit/faq` ve správné jazykové doméně.
  static String faq(String lang) =>
      _withLang('https://www.${_domain(lang)}/jak-pujcit/faq', lang);
}
