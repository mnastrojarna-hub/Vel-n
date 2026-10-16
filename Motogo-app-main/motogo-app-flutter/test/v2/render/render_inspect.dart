// verify:render — frame inspection: clipped / truncated / bleeding text,
// raw translation keys, strings shown from a fallback language, Czech text
// in another language, overlapping labels and the floating AI button over
// a CTA / bar. Walks the render tree like semantics does (offstage,
// invisible and non-current overlay entries are skipped).
import 'package:flutter/rendering.dart';
import 'package:motogo_app/core/i18n/translations.dart';

class RFinding {
  final String kind;
  final bool fail;
  final String text;
  final String detail;
  const RFinding(this.kind, this.fail, this.text, [this.detail = '']);
  String get key => '$kind|$text';
  Map<String, Object?> toJson() => {'kind': kind, 'fail': fail, 'text': text, 'detail': detail};
}

/// Per-language lookup tables built once from the app's real table.
class _LangTables {
  final Set<String> own = {};
  final Map<String, String> fallbackExact = {};
  final List<(RegExp, String)> fallbackTpl = [];
  final List<RegExp> ownTpl = [];
}

final Map<String, _LangTables> _tables = {};
final Set<String> _allKeys = {};
final _ph = RegExp(r'\{[a-zA-Z]+\}');
final _letters = RegExp(r'[A-Za-zÀ-žЀ-ӿ]');

RegExp _tpl(String v) => RegExp(
    '^${v.split(_ph).map(RegExp.escape).join(r'.+?')}\$',
    caseSensitive: false, dotAll: true);

_LangTables _tablesFor(String lang) => _tables.putIfAbsent(lang, () {
      final t = _LangTables();
      final mine = translations[lang] ?? const {};
      if (_allKeys.isEmpty) {
        for (final m in translations.values) {
          _allKeys.addAll(m.keys);
        }
      }
      for (final v in mine.values) {
        t.own.add(v.trim().toLowerCase());
        if (_ph.hasMatch(v) && v.replaceAll(_ph, '').trim().length >= 4) t.ownTpl.add(_tpl(v));
      }
      final keys = <String>{...?translations['cs']?.keys, ...?translations['en']?.keys};
      for (final k in keys) {
        if (mine[k] != null) continue;
        final en = translations['en'];
        final fb = (lang != 'cs' && en != null ? en[k] : null) ?? translations['cs']?[k];
        if (fb == null) continue;
        final v = fb.trim();
        if (v.length < 4 || !_letters.hasMatch(v) || t.own.contains(v.toLowerCase())) continue;
        if (_ph.hasMatch(v)) {
          if (v.replaceAll(_ph, '').trim().length >= 8) t.fallbackTpl.add((_tpl(v), k));
        } else {
          t.fallbackExact[v.toLowerCase()] = k;
        }
      }
      return t;
    });

/// True when [text] is app copy of [lang] (a translation value or a
/// filled-in template) — truncating it is a defect; data may be ellipsized.
bool isUiCopy(String lang, String text) {
  final t = _tablesFor(lang);
  final s = text.trim().toLowerCase();
  if (t.own.contains(s)) return true;
  return t.ownTpl.any((r) => r.hasMatch(text.trim()));
}

final _rawKey = RegExp(r'\b[a-z][a-z0-9]*[A-Z][A-Za-z0-9]*\b');
final _czech = RegExp(r'[ěščřžůťďňĚŠČŘŽŮŤĎŇ]');

bool _isIconGlyph(String s) => s.runes.every((r) => (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000 || r == 0x20);

class _Para {
  final RenderParagraph p;
  final String text;
  final Rect rect;
  Rect visible;
  RenderObject? layer;
  _Para(this.p, this.text, this.rect, this.visible);
}

/// The overlay entry (route / sheet / dialog) [o] is painted in.
RenderObject? _layerOf(RenderObject o) {
  RenderObject? x = o;
  while (x != null && x.parent != null) {
    if (x.parent.runtimeType.toString() == '_RenderTheater') return x;
    x = x.parent;
  }
  return null;
}

AxisDirection? _axisOf(RenderObject o) {
  try {
    return (o as dynamic).axisDirection as AxisDirection?;
  } catch (_) {
    return null;
  }
}

Rect _global(RenderObject o, Rect r) => MatrixUtils.transformRect(o.getTransformTo(null), r);

/// Global rect of [o] when it is actually painted (reached by the
/// semantics-style walk: not offstage, not at opacity 0), else null.
Rect? paintedRect(RenderObject root, RenderObject o) {
  var found = false;
  void visit(RenderObject x) {
    if (found) return;
    if (identical(x, o)) {
      found = true;
      return;
    }
    x.visitChildrenForSemantics(visit);
  }

  root.visitChildrenForSemantics(visit);
  if (!found || o is! RenderBox || !o.hasSize) return null;
  return _global(o, Offset.zero & o.size);
}

/// Inspects the current frame. [screen] = logical screen size.
List<RFinding> inspectFrame(RenderObject root, String lang, Size screen,
    {Rect? fab, List<Rect> avoid = const [], Set<RenderObject> ignore = const {}}) {
  final out = <RFinding>[];
  final paras = <_Para>[];
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.attached && o.hasSize && !o.debugNeedsLayout) {
      final text = o.text.toPlainText(includeSemanticsLabels: false).trim();
      if (text.isNotEmpty && !_isIconGlyph(text)) {
        final rect = _global(o, Offset.zero & o.size);
        paras.add(_Para(o, text, rect, rect));
      }
    }
    o.visitChildrenForSemantics(visit);
  }

  root.visitChildrenForSemantics(visit);
  final t = _tablesFor(lang);
  for (final para in paras) {
    final p = para.p, text = para.text;
    final short = text.length > 80 ? '${text.substring(0, 80)}…' : text;
    // 1) Clipped by an ancestor (up to the nearest scroll viewport: there
    //    only the cross axis counts — main-axis cut = scrolling).
    var visible = para.rect;
    var inViewport = false;
    if (ignore.isNotEmpty) {
      var ignored = false;
      for (RenderObject? x = p; x != null; x = x.parent) {
        if (ignore.contains(x)) {
          ignored = true;
          break;
        }
      }
      if (ignored) continue;
    }
    RenderObject child = p;
    var parent = p.parent;
    while (parent != null) {
      final clip = parent.describeApproximatePaintClip(child);
      final isViewport = parent is RenderAbstractViewport;
      if (clip != null) {
        final g = _global(parent, clip);
        final inter = visible.intersect(g);
        final outside = inter.width <= 0.5 || inter.height <= 0.5;
        if (outside) {
          visible = Rect.zero;
          break; // not on screen at all (scrolled away / hidden)
        }
        if (isViewport) {
          final ax = _axisOf(parent);
          final horizontal = ax == AxisDirection.left || ax == AxisDirection.right;
          final crossCut = horizontal
              ? (visible.top < g.top - 1 || visible.bottom > g.bottom + 1)
              : (visible.left < g.left - 1 || visible.right > g.right + 1);
          if (crossCut) {
            out.add(RFinding('clipped', true, short, 'cross-axis of ${parent.runtimeType} ${_r(visible)} vs ${_r(g)}'));
          }
          visible = inter;
          inViewport = true;
          break;
        }
        if (visible.left < g.left - 1 || visible.right > g.right + 1 || visible.top < g.top - 1 || visible.bottom > g.bottom + 1) {
          out.add(RFinding('clipped', true, short, 'by ${parent.runtimeType} ${_r(visible)} vs ${_r(g)}'));
        }
        visible = inter;
      }
      child = parent;
      parent = parent.parent;
    }
    para.visible = visible;
    para.layer = _layerOf(p);
    if (visible == Rect.zero) continue;
    // 2) Off the screen sideways (no scroll viewport in between).
    if (!inViewport && (para.rect.left < -1 || para.rect.right > screen.width + 1)) {
      out.add(RFinding('offscreen', true, short, _r(para.rect)));
    }
    // 3) Truncated / bleeding text.
    final ui = isUiCopy(lang, text);
    if (p.didExceedMaxLines) {
      out.add(RFinding(ui ? 'truncated-ui' : 'truncated-data', ui, short,
          'maxLines=${p.maxLines} overflow=${p.overflow.name} box=${_s(p.size)}'));
    } else {
      final ts = p.textSize;
      if (ts.width > p.size.width + 1 || ts.height > p.size.height + 1) {
        out.add(RFinding('text-box-overflow', true, short,
            'text ${_s(ts)} > box ${_s(p.size)} overflow=${p.overflow.name}'));
      }
    }
    // 4) Translation problems.
    for (final m in _rawKey.allMatches(text)) {
      final tok = m.group(0)!;
      if (tok.startsWith('v2') || (_allKeys.contains(tok) && tok.length > 5)) {
        out.add(RFinding('raw-key', true, tok, short));
      }
    }
    final lower = text.toLowerCase();
    final fk = t.fallbackExact[lower];
    if (fk != null) {
      out.add(RFinding('fallback', true, short, 'key $fk missing in $lang'));
    } else if (t.fallbackTpl.isNotEmpty && !isUiCopy(lang, text)) {
      for (final (re, k) in t.fallbackTpl) {
        if (re.hasMatch(text)) {
          out.add(RFinding('fallback', true, short, 'key $k missing in $lang'));
          break;
        }
      }
    }
    if (lang != 'cs' && _czech.hasMatch(text) && !isUiCopy(lang, text)) {
      out.add(RFinding('czech-text', false, short));
    }
    // 5) Floating AI button over a label of a bar / CTA.
    if (fab != null && !fab.contains(para.rect.center) && visible.overlaps(fab.deflate(2))) {
      final covered = avoid.any((a) => a.overlaps(fab.deflate(2)) && a.overlaps(visible));
      if (covered) out.add(RFinding('fab-covers', true, short, 'fab ${_r(fab)}'));
    }
  }
  // 6) Overlapping labels (different text, > 25 % of the smaller box).
  final vis = paras.where((x) => x.visible != Rect.zero && x.visible.width > 1 && x.visible.height > 1).toList();
  for (var i = 0; i < vis.length; i++) {
    for (var j = i + 1; j < vis.length; j++) {
      final a = vis[i], b = vis[j];
      if (a.text == b.text || !identical(a.layer, b.layer)) continue;
      final r = a.visible.intersect(b.visible);
      if (r.width <= 1 || r.height <= 1) continue;
      final small = a.visible.width * a.visible.height < b.visible.width * b.visible.height ? a.visible : b.visible;
      if (r.width * r.height > 0.25 * small.width * small.height) {
        out.add(RFinding('overlap', false, '${_cut(a.text)} ⟂ ${_cut(b.text)}', '${_r(a.visible)} ${_r(b.visible)}'));
      }
    }
  }
  return out;
}

String _cut(String s) => s.length > 40 ? '${s.substring(0, 40)}…' : s;
String _r(Rect r) => '[${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)} ${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}]';
String _s(Size s) => '${s.width.toStringAsFixed(1)}x${s.height.toStringAsFixed(1)}';
