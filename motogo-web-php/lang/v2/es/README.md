Texty landing v2 po stránkách (načítá i18n.php → i18nDictionary). Každý soubor
vrací `['pages' => ['<klic_stranky>' => [...]]]` a deep-merguje se do `pages.*`
daného jazyka (CS fallback zůstává). Pro češtinu se adresář lang/v2/cs nepoužívá
(CS defaulty jsou v kódu stránek).
