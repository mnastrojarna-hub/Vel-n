<?php
// ===== MotoGo24 Web PHP — OpenSearch description =====
// /opensearch.xml — popisuje vyhledávání pro prohlížeče (Firefox, Chrome,
// Edge) a Seznam Webmaster. Po přidání umožní uživateli "Add MotoGo24 to
// search" rovnou v search baru. Seznam Webmaster doporučuje OpenSearch
// pro lepší rozpoznávání webu jako "search-aware" zdroje.

require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/../i18n.php';

header('Content-Type: application/opensearchdescription+xml; charset=utf-8');
header('Cache-Control: public, max-age=86400');

$origin = i18nIsComDomain() ? 'https://motogo24.com' : 'https://motogo24.cz';
$lang = i18nIsComDomain() ? 'en' : 'cs';
$shortName = 'MotoGo24';
$desc = $lang === 'cs'
    ? 'Hledat motorky a články na MotoGo24 — půjčovna motocyklů Vysočina'
    : 'Search motorcycles and articles on MotoGo24 — motorcycle rental in Czechia';

echo '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/" xmlns:moz="http://www.mozilla.org/2006/browser/search/">
  <ShortName><?= htmlspecialchars($shortName) ?></ShortName>
  <Description><?= htmlspecialchars($desc) ?></Description>
  <InputEncoding>UTF-8</InputEncoding>
  <Image width="32" height="32" type="image/svg+xml"><?= $origin ?>/favicon.svg</Image>
  <Image width="180" height="180" type="image/png"><?= $origin ?>/apple-touch-icon.png</Image>
  <Url type="text/html" method="get" template="<?= $origin ?>/katalog?q={searchTerms}"/>
  <Url type="application/opensearchdescription+xml" rel="self" template="<?= $origin ?>/opensearch.xml"/>
  <moz:SearchForm><?= $origin ?>/katalog</moz:SearchForm>
  <Language><?= $lang === 'cs' ? 'cs-CZ' : 'en-GB' ?></Language>
  <OutputEncoding>UTF-8</OutputEncoding>
  <SyndicationRight>open</SyndicationRight>
  <AdultContent>false</AdultContent>
</OpenSearchDescription>
