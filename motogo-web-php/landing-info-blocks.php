<?php
// ===== MotoGo24 Web PHP — Landing v2 info stránky: mřížky a sekce (viz landing-info.php) =====
// Procesní mřížky (.wbox s klíči *.process.steps.* nebo titulky „1. …“) → časová
// osa (třídy z landing.css .lp-steps), ostatní .wbox mřížky → ikonové karty,
// dvousloupce → panely, PDF dokumenty → karty. Sekce dostanou role
// (faq / cta / more / billing / sec) — CTA = tmavá karta, outro = sbalený text.

function lpiGrids($doc, $x, $root, $admin, $L) {
    $first = true;
    foreach (iterator_to_array($x->query('.//div[@class]', $root)) as $g) {
        if (!preg_match('/(?:^|\s)gr([2-6])(?:\s|$)/', $g->getAttribute('class'), $m) || !$g->parentNode) continue;
        $cols = (int)$m[1];
        $boxes = iterator_to_array($x->query('./div[contains(concat(" ",normalize-space(@class)," ")," wbox ")]', $g));
        if ($boxes) {
            if (lpiIsSteps($x, $boxes)) { lpiSteps($doc, $x, $g, $boxes, $cols, $admin, $L, $first); $first = false; }
            else lpiCards($x, $g, $boxes, $cols);
            continue;
        }
        if (lpiHas($g, 'attachments')) { lpiDocs($x, $g); continue; }
        if ($x->query('.//details', $g)->length) { $g->setAttribute('class', 'lpi-faq-list'); continue; }
        foreach (iterator_to_array($x->query('./div', $g)) as $col) {
            if (lpiText($col) === '' && !$x->query('.//img|.//iframe', $col)->length) { $g->removeChild($col); continue; }
            lpiAdd($col, 'lpi-panel lp-reveal');
        }
        if (!$x->query('./div', $g)->length) $g->parentNode->removeChild($g);
        else $g->setAttribute('class', 'lpi-cols');
    }
}

function lpiIsSteps($x, $boxes) {
    $num = 0;
    foreach ($boxes as $b) {
        if ($x->query('.//*[contains(@data-cms-key,".process.steps.")]', $b)->length) return true;
        $h = $x->query('.//h3', $b)->item(0);
        if ($h && preg_match('/^\d+\./', lpiText($h))) $num++;
    }
    return $num * 2 >= count($boxes);
}

/** Kroky → <ol class="lp-steps-list"> v tmavé kartě; sekce bez H2 dostane obecný nadpis. */
function lpiSteps($doc, $x, $g, $boxes, $cols, $admin, $L, $ids) {
    $ol = lpiEl($doc, 'ol', 'lp-steps-list lpi-steps-list lpi-c' . min(5, max(3, $cols)));
    foreach ($boxes as $i => $b) {
        $li = lpiEl($doc, 'li', 'lp-step lp-reveal');
        $li->setAttribute('style', '--i:' . ($i % 4));
        if ($ids) $li->setAttribute('id', 'step-' . ($i + 1));
        $num = lpiEl($doc, 'span', 'lp-step-n');
        $num->setAttribute('aria-hidden', 'true');
        $num->appendChild($doc->createTextNode((string)($i + 1)));
        $body = lpiEl($doc, 'div', 'lp-step-body');
        foreach (iterator_to_array($b->childNodes) as $c) {
            if (lpiHas($c, 'wbox-img')) { foreach (iterator_to_array($x->query('.//img', $c)) as $img) $body->appendChild($img); continue; }
            $body->appendChild($c);
        }
        $h3 = $x->query('.//h3', $body)->item(0);
        if ($h3 && !$admin) lpiHideNum($doc, $h3);
        $li->appendChild($num);
        $li->appendChild($body);
        $ol->appendChild($li);
    }
    $g->parentNode->replaceChild($ol, $g);
    $sec = $ol->parentNode;
    if (!($sec instanceof DOMElement) || $sec->nodeName !== 'section') return;
    lpiAdd($sec, 'lp-steps lpi-steps');
    $card = lpiEl($doc, 'div', 'lp-steps-card');
    lpiMoveKids($sec, $card);
    if (!$x->query('.//h2', $card)->length && lpPlain($L['steps_title'] ?? '') !== '') {
        $h2 = lpiEl($doc, 'h2');
        $h2->appendChild($doc->createTextNode(lpPlain($L['steps_title'])));
        $card->insertBefore($h2, $card->firstChild);
    }
    $sec->appendChild($card);
}

/** Ostatní .wbox mřížky → ikonové karty (krátké texty = dlaždice 2×N, delší = řádky). */
function lpiCards($x, $g, $boxes, $cols) {
    $long = false;
    foreach ($boxes as $b) {
        $p = $x->query('./p', $b)->item(0);
        if ($p && mb_strlen(lpiText($p)) > 80) $long = true;
    }
    $g->setAttribute('class', 'lpi-cards lpi-cards--' . ($long ? 'rows' : 'tiles') . ' lpi-c' . $cols);
    foreach ($boxes as $i => $b) {
        $b->setAttribute('class', 'lpi-card lp-reveal');
        $b->setAttribute('style', '--i:' . ($i % 6));
        foreach ($x->query('./div[contains(@class,"wbox-img")]', $b) as $ic) $ic->setAttribute('class', 'lpi-card-ico');
    }
}

/** Karty PDF dokumentů — inline styly pryč, vzhled dělá CSS. */
function lpiDocs($x, $g) {
    $g->setAttribute('class', 'lpi-docs');
    foreach (iterator_to_array($x->query('.//*[@style]', $g)) as $el) $el->removeAttribute('style');
    foreach ($x->query('./a', $g) as $a) lpiAdd($a, 'lpi-doc lp-reveal');
    foreach ($x->query('./a/span[contains(@class,"btn")]', $g) as $s) $s->setAttribute('class', 'lpi-doc-dl');
}

/** Holé uzly → sekce, role sekcí, CTA/outro úpravy. $ai = výzva AI pod první FAQ. Vrací [bloky, index pro pruh motorek]. */
function lpiBlocks($doc, $x, $cc, $L, $TC, $ai = true) {
    $out = [];
    $grp = null;
    foreach (iterator_to_array($cc->childNodes) as $n) {
        if (!($n instanceof DOMElement)) {
            if (lpiText($n) === '') { $cc->removeChild($n); continue; }
        } elseif ($n->nodeName === 'section' || lpiHas($n, 'lpi-block')) {
            $grp = null;
            $out[] = $n;
            continue;
        }
        if (!$grp) { $grp = lpiEl($doc, 'section'); $cc->insertBefore($grp, $n); $out[] = $grp; }
        $grp->appendChild($n);
        if (lpiHas($n, 'tab-content')) $grp = null;
    }
    $last = count($out) - 1;
    $faqDone = false;
    $roles = [];
    foreach ($out as $i => $s) {
        $h2 = $x->query('.//h2', $s)->item(0);
        $key = $h2 ? $h2->getAttribute('data-cms-key') : '';
        if (lpiHas($s, 'lp-steps')) $r = 'steps';
        elseif (lpiHas($s, 'lpi-billing')) $r = 'billing';
        elseif (lpiHas($s, 'lp-more') || lpiHas($s, 'cvc-outro') || preg_match('/\.outro\.title$/', $key)) $r = 'more';
        elseif ($x->query('.//details', $s)->length) $r = 'faq';
        elseif (preg_match('/\.cta\.title$/', $key) || ($i === $last && $x->query('.//a[contains(@class,"lp-btn")]', $s)->length)) $r = 'cta';
        else $r = 'sec';
        if ($r === 'cta') lpiCta($doc, $x, $s, $L);
        elseif ($r === 'more' && !lpiHas($s, 'lp-more')) lpiMore($doc, $x, $s, $TC, 'lpi-more-' . $i);
        elseif ($r === 'faq') {
            lpiAdd($s, 'lpi-faq');
            if ($ai && !$faqDone) { $s->appendChild(lpiFrag($doc, lpiAiBox($L))); $faqDone = true; }
        } elseif ($r === 'sec' && $s->nodeName === 'section' && !preg_match('/(?:^|\s)lpi?-/', $s->getAttribute('class'))) {
            $rich = $x->query('.//*[contains(@class,"lpi-cards") or contains(@class,"lpi-cols") or contains(@class,"lpi-table") or contains(@class,"lpi-docs")]|.//iframe', $s)->length;
            $btnTxt = '';
            foreach ($x->query('.//a[contains(@class,"lp-btn")]', $s) as $a) $btnTxt .= lpiText($a);
            $onlyBtns = $btnTxt !== '' && str_replace(' ', '', lpiText($s)) === str_replace(' ', '', $btnTxt);
            lpiAdd($s, 'lpi-sec' . ($onlyBtns ? ' lpi-sec--btns' : ($rich ? '' : ' lpi-sec--text lp-reveal')));
        }
        $roles[$i] = $r;
    }
    // Sbalené texty (outro/SEO) až úplně na konec, za CTA
    $keep = $tail = [];
    foreach ($out as $i => $s) { if ($roles[$i] === 'more') $tail[] = [$s, 'more']; else $keep[] = [$s, $roles[$i]]; }
    $all = array_merge($keep, $tail);
    $cut = count($all);
    foreach ($all as $i => [$s, $r]) {
        if ($r === 'faq') { $cut = $i === 0 ? 1 : $i; break; }
    }
    if ($cut === count($all)) foreach ($all as $i => [$s, $r]) { if (in_array($r, ['cta', 'more', 'billing'], true)) { $cut = $i; break; } }
    return [array_column($all, 0), $cut];
}

/** CTA sekce → tmavá karta (landing .lp-cta-card); rezervace vždy jako první tlačítko. */
function lpiCta($doc, $x, $s, $L) {
    lpiAdd($s, 'lp-cta lpi-cta');
    $as = iterator_to_array($x->query('.//a[contains(concat(" ",@class," ")," lp-btn ")]', $s));
    usort($as, function ($a, $b) { return (int)lpiIsHref($b, '#^/rezervace#') <=> (int)lpiIsHref($a, '#^/rezervace#'); });
    if (!$as || !lpiIsHref($as[0], '#^/rezervace#')) {
        $r = lpiEl($doc, 'a');
        $r->setAttribute('href', '/rezervace');
        $r->appendChild(lpiMark($doc, 'cal'));
        $r->appendChild($doc->createTextNode(lpPlain($L['reserve'] ?? '')));
        array_unshift($as, $r);
    }
    $btns = lpiEl($doc, 'div', 'lp-cta-btns');
    foreach ($as as $k => $a) {
        $a->setAttribute('class', 'lp-btn ' . ($k === 0 ? 'lp-btn-primary' : 'lp-btn-ghost'));
        $par = $a->parentNode;
        $btns->appendChild($a);
        if ($par instanceof DOMElement && $par !== $s && lpiText($par) === '' && $par->parentNode) $par->parentNode->removeChild($par);
    }
    $card = lpiEl($doc, 'div', 'lp-cta-card');
    $h2 = $x->query('./h2', $s)->item(0);
    if ($h2) $card->appendChild($h2);
    $txt = lpiEl($doc, 'div', 'lpi-cta-text');
    lpiMoveKids($s, $txt);
    if (mb_strlen(lpiText($txt)) > 320) {
        $txt->setAttribute('data-lpi-clamp', '');
        $txt->setAttribute('data-more', lpS($L['read_more'] ?? ''));
        $txt->setAttribute('data-less', lpS($L['read_less'] ?? ''));
    }
    if ($txt->childNodes->length) $card->appendChild($txt);
    $card->appendChild($btns);
    $s->appendChild($card);
}

/** Outro/SEO sekce → sbalitelná karta (landing.js [data-lp-more]); text zůstává v DOM celý. */
function lpiMore($doc, $x, $s, $TC, $id) {
    lpiAdd($s, 'lp-more lpi-more');
    $s->setAttribute('data-lp-more', '');
    $card = lpiEl($doc, 'div', 'lp-more-card');
    $h2 = $x->query('./h2', $s)->item(0);
    if ($h2) $card->appendChild($h2);
    $body = lpiEl($doc, 'div', 'lp-more-body');
    $body->setAttribute('id', $id . '-b');
    lpiMoveKids($s, $body);
    $card->appendChild($body);
    $btn = lpiEl($doc, 'button', 'lp-more-btn');
    foreach (['type' => 'button', 'aria-controls' => $id . '-b', 'aria-expanded' => 'true', 'data-open' => lpS($TC['more_open'] ?? ''), 'data-close' => lpS($TC['more_close'] ?? ''), 'hidden' => 'hidden'] as $k => $v) $btn->setAttribute($k, $v);
    $btn->appendChild($doc->createTextNode(lpS($TC['more_close'] ?? '')));
    $card->appendChild($btn);
    $s->appendChild($card);
}

/** Výzva k AI asistentovi (JS ji skryje, když na stránce není bublina chatu — bez posunu layoutu v běžném případě). */
function lpiAiBox($L) {
    $A = (array)($L['ai'] ?? []);
    return '<div class="lpi-ai" data-lpi-ai-box><span class="lpi-ai-ico"><i data-lpi-ico="spark"></i></span>' .
        '<p><strong>' . he(lpPlain($A['title'] ?? '')) . '</strong> ' . he(lpPlain($A['text'] ?? '')) . '</p>' .
        '<button type="button" class="lp-btn lpi-btn-dark" data-lpi-ai><i data-lpi-ico="chat"></i>' . he(lpPlain($A['btn'] ?? '')) . '</button></div>';
}
