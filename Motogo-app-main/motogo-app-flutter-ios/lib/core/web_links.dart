/// Odkazy na veřejný web MotoGo24.
///
/// Web řeší jazyky DOMÉNOU (ne cestou) — každý jazyk má vlastní TLD. Zrcadlí
/// `I18N_DOMAIN_MAP` z `motogo-web-php/i18n.php`. Kanonický host je VŽDY `www.`
/// varianta — holá doména (bez www) nemusí mít platný TLS certifikát
/// (Let's Encrypt je jen na www.), takže odkazy musí www obsahovat.
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
  };

  /// Doména webu pro daný jazyk (fallback čeština).
  static String _domain(String lang) =>
      _domainByLang[lang] ?? _domainByLang['cs']!;

  /// Kanonický web origin (vždy s www.) v jazyce zákazníka.
  static String home(String lang) => 'https://www.${_domain(lang)}';

  /// FAQ / časté dotazy — web route `/jak-pujcit/faq` ve správné jazykové doméně.
  static String faq(String lang) => '${home(lang)}/jak-pujcit/faq';
}
