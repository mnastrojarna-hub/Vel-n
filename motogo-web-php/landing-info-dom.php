<?php
// ===== MotoGo24 Web PHP — Landing v2 info stránky: DOM pomocníci + drobné transformace =====
// (viz landing-info.php). Jen úpravy značek/tříd — text obsahu zůstává.

/** HTML → DOM (UTF-8). Číselné entity (obfuskovaný e-mail &#64;) chráníme značkou — saveHTML by je rozbalil. */
function lpiLoad($html) {
    $html = preg_replace('/&#(x?[0-9a-fA-F]{1,6});/', 'QlpiE$1Q', $html);
    $prev = libxml_use_internal_errors(true);
    $doc = new DOMDocument('1.0', 'UTF-8');
    $doc->loadHTML('<?xml encoding="UTF-8"?><div id="lpi-root">' . $html . '</div>', LIBXML_HTML_NOIMPLIED | LIBXML_HTML_NODEFDTD | LIBXML_NONET);
    libxml_clear_errors();
    libxml_use_internal_errors($prev);
    return $doc;
}

function lpiHtml($doc, $node) {
    return (string)$doc->saveHTML($node);
}

/** Výstup: vrátí chráněné entity a nahradí ikonové značky <i data-lpi-ico> za SVG. */
function lpiFinish($html) {
    $html = preg_replace('/QlpiE(x?[0-9a-fA-F]{1,6})Q/', '&#$1;', $html);
    return preg_replace_callback('#<i data-lpi-ico="([a-z]+)"></i>#', function ($m) { return lpiIcon($m[1]); }, $html);
}

/** Ikony nad rámec lpIcon() (cal, moto, check, arrow, pin). */
function lpiIcon($n) {
    $p = [
        'phone' => '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2"/>',
        'mail' => '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
        'clock' => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
        'chat' => '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/><path d="M8 12h.01M12 12h.01M16 12h.01"/>',
        'spark' => '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"/>',
        'route' => '<path d="M3 11 21 3l-8 18-2-8z"/>',
        'box' => '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M10 13h4"/>',
        'id' => '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="11" r="2"/><path d="M6 16c.6-1.5 1.7-2 3-2s2.4.5 3 2M15 10h3M15 13h3"/>',
        'social' => '<circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="m8.2 10.8 7.6-3.6M8.2 13.2l7.6 3.6"/>',
    ];
    if (!isset($p[$n])) return lpIcon($n);
    return '<svg class="lp-ico" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' . $p[$n] . '</svg>';
}

/** Značka ikony (po serializaci ji lpiFinish nahradí SVG). */
function lpiMark($doc, $name) {
    $i = $doc->createElement('i');
    $i->setAttribute('data-lpi-ico', $name);
    return $i;
}

function lpiText($n) {
    return trim(preg_replace('/[\s\x{00A0}]+/u', ' ', (string)$n->textContent));
}

function lpiHas($el, $c) {
    return $el instanceof DOMElement && strpos(' ' . preg_replace('/\s+/', ' ', $el->getAttribute('class')) . ' ', ' ' . $c . ' ') !== false;
}

function lpiAdd($el, $c) {
    $el->setAttribute('class', trim($el->getAttribute('class') . ' ' . $c));
}

function lpiEl($doc, $tag, $cls = '') {
    $e = $doc->createElement($tag);
    if ($cls !== '') $e->setAttribute('class', $cls);
    return $e;
}

/** HTML řetězec → fragment v $doc (ikony jen jako značky <i data-lpi-ico>, ne inline SVG). */
function lpiFrag($doc, $html) {
    $tmp = lpiLoad($html);
    $root = $tmp->getElementById('lpi-root');
    $f = $doc->createDocumentFragment();
    if ($root) foreach (iterator_to_array($root->childNodes) as $c) $f->appendChild($doc->importNode($c, true));
    return $f;
}

/** Přesune všechny děti $from do $to (volitelně od uzlu $start). */
function lpiMoveKids($from, $to, $start = null) {
    $go = $start === null;
    foreach (iterator_to_array($from->childNodes) as $c) {
        if (!$go && $c === $start) $go = true;
        if ($go) $to->appendChild($c);
    }
}

function lpiIsHref($a, $re) {
    return $a instanceof DOMElement && preg_match($re, $a->getAttribute('href'));
}

/** <p> s blokovým obsahem (CMS: <p>…<div>…</div></p>) → <div class="lpi-p"> (prohlížeč by <p> rozdělil). */
function lpiFixBlockP($doc, $x, $root) {
    foreach (iterator_to_array($x->query('.//p[.//div or .//ul or .//ol or .//p or .//h2 or .//h3 or .//h4 or .//table]', $root)) as $p) {
        $d = lpiEl($doc, 'div');
        foreach (iterator_to_array($p->attributes) as $at) $d->setAttribute($at->name, $at->value);
        lpiAdd($d, 'lpi-p');
        lpiMoveKids($p, $d);
        $p->parentNode->replaceChild($d, $p);
    }
}

/** Prázdné odstavce-mezery (<p>&nbsp;</p>, p.sp, <p><br></p>) pryč — rozestupy řeší CSS. */
function lpiStripSpacers($x, $root) {
    foreach (iterator_to_array($x->query('.//p', $root)) as $p) {
        if ($x->query('.//*[not(self::br)]', $p)->length) continue;
        if (lpiText($p) === '') $p->parentNode->removeChild($p);
    }
}

/** Tlačítka obsahu → v2 (rezervace = zelené s ikonou kalendáře, ostatní tmavé). */
function lpiButtons($doc, $x, $root) {
    foreach (iterator_to_array($x->query('.//a[contains(concat(" ",normalize-space(@class)," ")," btn ")]', $root)) as $a) {
        $res = lpiIsHref($a, '#^/rezervace#');
        $a->setAttribute('class', 'lp-btn ' . ($res ? 'lp-btn-primary' : 'lpi-btn-dark') . ' lpi-btn');
        $ico = $res ? 'cal' : (lpiIsHref($a, '#^/katalog#') ? 'moto' : (lpiIsHref($a, '#^/kontakt#') ? 'chat' : ''));
        if ($ico !== '') $a->insertBefore(lpiMark($doc, $ico), $a->firstChild);
        else $a->appendChild(lpiMark($doc, 'arrow'));
        $p = $a->parentNode;
        if ($p instanceof DOMElement && $p->nodeName === 'p') {
            lpiAdd($p, 'lpi-btns');
            foreach (iterator_to_array($p->childNodes) as $c) {
                if ($c->nodeType === XML_TEXT_NODE && lpiText($c) === '') $p->removeChild($c);
            }
        }
    }
}

/** Odrážkové seznamy → „fajfkové“; úvodní „- “ z textu položky pryč (odrážku kreslí CSS). */
function lpiLists($x, $root, $admin) {
    foreach (iterator_to_array($x->query('.//ul[not(contains(@class,"tabs")) and not(contains(@class,"lp-chips"))]', $root)) as $ul) {
        lpiAdd($ul, 'lpi-checks');
        if (!$admin) foreach ($x->query('./li', $ul) as $li) lpiStripDash($li);
    }
    // CMS „seznam“ z <div>- položka</div> (aspoň 3 řádky začínající pomlčkou)
    foreach (iterator_to_array($x->query('.//div[count(div) >= 3]', $root)) as $d) {
        $kids = iterator_to_array($x->query('./div', $d));
        foreach ($kids as $k) if (!preg_match('/^[-–—•]/u', lpiText($k))) continue 2;
        lpiAdd($d, 'lpi-checks lpi-checks--div');
        if (!$admin) foreach ($kids as $k) lpiStripDash($k);
    }
}

function lpiStripDash($el) {
    for ($n = $el->firstChild; $n && $n->nodeType === XML_TEXT_NODE && lpiText($n) === ''; $n = $n->nextSibling);
    if ($n && $n->nodeType === XML_TEXT_NODE) $n->nodeValue = preg_replace('/^[\s\x{00A0}]*[-–—•][\s\x{00A0}]*/u', '', $n->nodeValue);
}

/** Tabulky: popisky sloupců do data-label (mobil = karty). */
function lpiTables($x, $root) {
    foreach (iterator_to_array($x->query('.//div[contains(@class,"table-responsive")]', $root)) as $w) {
        $heads = [];
        foreach ($x->query('.//thead//th', $w) as $th) $heads[] = lpiText($th);
        lpiAdd($w, 'lpi-table' . (count($heads) === 2 ? ' lpi-table--kv' : ''));
        foreach ($x->query('.//tbody/tr', $w) as $tr) {
            $i = 0;
            foreach ($x->query('./td', $tr) as $td) {
                if (($heads[$i] ?? '') !== '') $td->setAttribute('data-label', $heads[$i]);
                $i++;
            }
        }
    }
}

/** FAQ: nový styl položek, taby (stránka FAQ) jako chipy. */
function lpiFaqStyle($x, $root) {
    foreach ($x->query('.//details[contains(@class,"faq-item")]', $root) as $d) lpiAdd($d, 'lpi-faq-item');
    foreach ($x->query('.//ul[contains(concat(" ",normalize-space(@class)," ")," tabs ")]', $root) as $ul) $ul->setAttribute('class', 'lpi-tabs');
}

/** Číslo kroku z titulku („1. …“) vizuálně skryje (číslo kreslí kolečko); text zůstává pro čtečky/SEO. */
function lpiHideNum($doc, $h) {
    $n = $h;
    while ($n && $n->firstChild) $n = $n->firstChild;
    if (!$n || $n->nodeType !== XML_TEXT_NODE || !preg_match('/^[\s\x{00A0}]*\d+\.[\s\x{00A0}]*/u', $n->nodeValue, $m)) return;
    $sr = lpiEl($doc, 'span', 'lpi-sr');
    $sr->appendChild($doc->createTextNode($m[0]));
    $n->nodeValue = substr($n->nodeValue, strlen($m[0]));
    $n->parentNode->insertBefore($sr, $n);
}
