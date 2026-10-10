<?php
// ===== MotoGo24 Web PHP — Landing v2 info stránky: Kontakt (viz landing-info.php) =====
// Rychlé kontakty → velké klikací karty (+ AI asistent), pod nimi obě pobočky
// jako karty (detail + navigace), provozovna/provozní doba/sítě jako panely,
// mapa s navigací, fakturační údaje a SEO text níž (SEO sbalené).

/** Pobočky na Kontaktu — slug/adresa/mapa/fotka z kódu; texty z lpiTexts()['contact']['branches']. */
const LPI_BRANCHES = [
    ['slug' => 'mezna', 'address' => 'Mezná 9, 393 01 Pelhřimov', 'map' => 'Mezná 9, 393 01 Pelhřimov', 'photo' => 'gfx/provozovna-2.jpg', 'live' => false],
    ['slug' => 'velke-nemcice', 'address' => 'Boudky, 691 63 Velké Němčice', 'map' => '49.0043289,16.6721237', 'photo' => 'gfx/pobocky/velke-nemcice/vydejni-box-640.webp', 'live' => true],
];

function lpiMapUrl($q) {
    return 'https://www.google.com/maps/dir/?api=1&destination=' . rawurlencode($q);
}

function lpiContact($doc, $x, $cc, $L, $TC) {
    $K = (array)($L['contact'] ?? []);
    $quick = $x->query('.//div[contains(@class,"contact-quick-boxes")]', $cc)->item(0);
    $anchor = null;
    if ($quick) {
        $quick->setAttribute('class', 'lpi-ccards');
        foreach (iterator_to_array($x->query('./div', $quick)) as $i => $box) {
            $a = $x->query('.//a[@href]', $box)->item(0);
            $type = lpiIsHref($a, '#^tel:#') ? 'phone' : (lpiIsHref($a, '#^mailto:#') ? 'mail' : (lpiIsHref($a, '#wa\.me|whatsapp#i') ? 'chat' : 'box'));
            $box->setAttribute('class', 'lpi-ccard lpi-ccard--' . $type . ' lp-reveal');
            $box->setAttribute('style', '--i:' . $i);
            foreach (iterator_to_array($x->query('./div[contains(@class,"img-icon")]', $box)) as $ic) $box->removeChild($ic);
            $ico = lpiEl($doc, 'span', 'lpi-ccard-ico');
            $ico->appendChild(lpiMark($doc, $type));
            $box->insertBefore($ico, $box->firstChild);
            if ($a) {
                lpiAdd($a, 'lpi-stretch');
                $go = lpiEl($doc, 'span', 'lpi-ccard-go');
                $go->appendChild(lpiMark($doc, 'arrow'));
                $box->appendChild($go);
            }
        }
        $A = (array)($L['ai'] ?? []);
        $quick->appendChild(lpiFrag($doc, '<button type="button" class="lpi-ccard lpi-ccard--ai" data-lpi-ai><span class="lpi-ccard-ico"><i data-lpi-ico="spark"></i></span>' .
            '<span class="lpi-ccard-txt"><small>' . he(lpPlain($A['title'] ?? '')) . '</small><strong>' . he(lpPlain($A['card'] ?? '')) . '</strong></span>' .
            '<span class="lpi-ccard-go"><i data-lpi-ico="arrow"></i></span></button>'));
        $anchor = $quick->parentNode;
        if ($anchor instanceof DOMElement && $anchor->nodeName === 'section') lpiAdd($anchor, 'lpi-contact');
        else $anchor = $quick;
    }
    $brHtml = lpiBranchesHtml($K);
    if ($brHtml !== '') {
        $br = lpiFrag($doc, $brHtml);
        if ($anchor && $anchor->parentNode === $cc) $cc->insertBefore($br, $anchor->nextSibling);
        else $cc->insertBefore($br, $cc->firstChild);
    }

    $bill = null;
    $info = $x->query('.//div[contains(@class,"contact-info")]', $cc)->item(0);
    if ($info) {
        $info->setAttribute('class', 'lpi-cinfo lpi-block');
        foreach (iterator_to_array($x->query('.//section', $info)) as $s) {
            $h2 = $x->query('./h2', $s)->item(0);
            $key = $h2 ? $h2->getAttribute('data-cms-key') : '';
            if (lpiHas($s, 'cta-green-box')) { $s->setAttribute('class', ''); lpiCta($doc, $x, $s, $L); lpiAdd($s, 'lpi-cta--mini'); continue; }
            if ($key === 'web.kontakt.social_title') { lpiSocial($doc, $x, $s); continue; }
            $bh = $x->query('./h2[@data-cms-key="web.kontakt.place.billing_title"]', $s)->item(0);
            if ($bh) { $bill = lpiEl($doc, 'section', 'lpi-billing lpi-panel'); lpiMoveKids($s, $bill, $bh); }
            lpiAdd($s, 'lpi-panel lpi-place lp-reveal');
            $icons = ['pin', 'clock'];
            foreach (iterator_to_array($x->query('./p|./div[contains(@class,"lpi-p")]', $s)) as $k => $p) {
                $row = lpiEl($doc, 'div', 'lpi-row');
                $ic = lpiEl($doc, 'span', 'lpi-row-ico');
                $ic->appendChild(lpiMark($doc, $icons[$k] ?? 'check'));
                $s->insertBefore($row, $p);
                $row->appendChild($ic);
                $row->appendChild($p);
            }
        }
    }
    foreach (iterator_to_array($x->query('./section[.//iframe]', $cc)) as $ms) {
        lpiAdd($ms, 'lpi-map lpi-panel');
        $ms->appendChild(lpiFrag($doc, '<p class="lpi-btns"><a class="lp-btn lpi-btn-dark" href="' . he(lpiMapUrl(LPI_BRANCHES[0]['map'])) . '" target="_blank" rel="noopener"><i data-lpi-ico="route"></i>' . he(lpPlain($K['route'] ?? '')) . '</a></p>'));
    }
    $sh = $x->query('./h2[@data-cms-key="web.kontakt.seo_text.title"]', $cc)->item(0);
    $first = $sh ?: $x->query('./section[contains(@class,"kontakt-outro")]', $cc)->item(0);
    $more = null;
    if ($first) {
        $more = lpiEl($doc, 'section');
        $cc->insertBefore($more, $first);
        lpiMoveKids($cc, $more, $first);
        lpiMore($doc, $x, $more, $TC, 'lpi-more-k');
    }
    if ($bill) $cc->insertBefore($bill, $more);
}

/** Sociální sítě → řada klikacích dlaždic. */
function lpiSocial($doc, $x, $s) {
    lpiAdd($s, 'lpi-panel lpi-social lp-reveal');
    $wrap = lpiEl($doc, 'div', 'lpi-soc-list');
    foreach (iterator_to_array($x->query('./p[contains(@class,"dfc")]', $s)) as $p) {
        $p->setAttribute('class', 'lpi-soc');
        $a = $x->query('.//a', $p)->item(0);
        if ($a) lpiAdd($a, 'lpi-stretch');
        foreach (iterator_to_array($p->childNodes) as $c) {
            if ($c->nodeType === XML_TEXT_NODE && lpiText($c) === '') $p->removeChild($c);
        }
        $wrap->appendChild($p);
    }
    $s->appendChild($wrap);
}

/** Karty obou poboček (odkaz na detail /pobocky/<slug> + navigace Google Maps). */
function lpiBranchesHtml($K) {
    $cards = '';
    foreach (LPI_BRANCHES as $i => $b) {
        $t = (array)($K['branches'][$i] ?? []);
        $title = lpPlain($t['title'] ?? '');
        if ($title === '') continue;
        $href = '/pobocky/' . $b['slug'];
        $chips = '';
        foreach ((array)($t['chips'] ?? []) as $c) {
            if (lpPlain($c) !== '') $chips .= '<li class="lp-chip"><i data-lpi-ico="check"></i><span>' . he(lpPlain($c)) . '</span></li>';
        }
        $cards .= '<article class="lpi-branch lp-reveal" style="--i:' . $i . '">' .
            '<div class="lpi-branch-media"><a class="lpi-branch-img" href="' . $href . '" tabindex="-1" aria-hidden="true"><img src="/' . he($b['photo']) . '" alt="' . he($title) . '" loading="lazy" decoding="async" width="640" height="480"></a>' .
            '<span class="lpi-badge' . ($b['live'] ? ' lpi-badge--live' : '') . '">' . he(lpPlain($t['badge'] ?? '')) . '</span></div>' .
            '<div class="lpi-branch-body"><h3><a href="' . $href . '">' . he($title) . '</a></h3>' .
            '<p class="lpi-branch-addr"><i data-lpi-ico="pin"></i><span>' . he($b['address']) . '</span></p>' .
            (lpPlain($t['text'] ?? '') !== '' ? '<p>' . he(lpPlain($t['text'])) . '</p>' : '') .
            ($chips !== '' ? '<ul class="lp-chips lpi-branch-chips">' . $chips . '</ul>' : '') .
            '<div class="lpi-branch-btns"><a class="lp-btn lpi-btn-dark" href="' . $href . '"><span>' . he(lpPlain($K['detail'] ?? '')) . '</span><i data-lpi-ico="arrow"></i></a>' .
            '<a class="lp-btn lpi-btn-line" href="' . he(lpiMapUrl($b['map'])) . '" target="_blank" rel="noopener"><i data-lpi-ico="route"></i><span>' . he(lpPlain($K['route'] ?? '')) . '</span></a></div>' .
            '</div></article>';
    }
    if ($cards === '') return '';
    return '<section class="lpi-branches" aria-labelledby="lpi-br-h"><h2 id="lpi-br-h">' . he(lpPlain($K['branches_title'] ?? '')) . '</h2>' .
        '<div class="lpi-branch-grid">' . $cards . '</div></section>';
}
