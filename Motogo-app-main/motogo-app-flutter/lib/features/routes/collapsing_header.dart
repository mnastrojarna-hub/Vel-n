import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Sbalitelná hlavička obrazovky: nadpis (s ikonou a volitelným tlačítkem
/// zpět) zůstane připnutý nahoře, podtitulek s polem hledání se při scrollu
/// plynule složí a zmizí — na seznam pod hlavičkou tak zbude celá obrazovka.
/// Když je hledání složené, objeví se v nadpisu lupa: tapem se obsah vrátí
/// nahoru a pole je zase po ruce.
///
/// Sdílí ji seznam Míst i seznam Tras (zadání uživatele: „když scrolluju,
/// mělo by se zabalit i políčko hledat v hlavičce, ať je co nejvíc prostoru").
class CollapsingSearchHeader extends SliverPersistentHeaderDelegate {
  /// Ikona vlevo od nadpisu (emoji v Místech, animovaná ikona v Trasách).
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget search;

  /// null = kořen tabu (bez tlačítka zpět).
  final VoidCallback? onBack;
  final VoidCallback onSearchTap;
  final EdgeInsets padding;

  /// Výška sbalitelné části (podtitulek + mezera + pole hledání). Podtitulek
  /// je proto JEDNOŘÁDKOVÝ — kdyby se zalomil, pole hledání by se do pevné
  /// výšky sliveru nevešlo a spodek by se ořízl.
  final double collapsibleHeight;

  /// Výška řádku s nadpisem.
  final double titleHeight;

  const CollapsingSearchHeader({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.search,
    required this.onBack,
    required this.onSearchTap,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 16, 10),
    this.collapsibleHeight = 78,
    this.titleHeight = 34,
  });

  @override
  double get minExtent => padding.top + titleHeight + padding.bottom;

  @override
  double get maxExtent => minExtent + collapsibleHeight;

  @override
  bool shouldRebuild(covariant CollapsingSearchHeader old) =>
      old.title != title ||
      old.subtitle != subtitle ||
      old.search != search ||
      old.leading != leading ||
      old.onBack != onBack ||
      old.collapsibleHeight != collapsibleHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      _content((shrinkOffset / collapsibleHeight).clamp(0.0, 1.0));

  /// Plně rozbalená hlavička jako běžný widget — pro stavy bez scrollu
  /// (načítání, chyba), kde žádný sliver není.
  Widget expanded() => SizedBox(height: maxExtent, child: _content(0));

  /// [t] 0 = rozbaleno, 1 = sbaleno na úzký pruh.
  Widget _content(double t) {
    return Container(
      decoration: const BoxDecoration(
        color: MotoGoColors.dark,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(MotoGoRadius.hdr)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: titleHeight,
            child: Row(
              children: [
                if (onBack != null) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onBack,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child:
                          Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                leading,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: MotoGoTypo.sizeH1,
                      fontWeight: MotoGoTypo.w900,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                // Lupa se objeví, teprve když je hledání složené — tapem
                // se obsah vrátí nahoru a pole je zase po ruce.
                if (t > 0.5)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSearchTap,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Icon(Icons.search, color: Colors.white, size: 22),
                    ),
                  ),
              ],
            ),
          ),
          // Sbalitelná část — výšku určuje zbytek hlavičky, obsah se ořízne
          // (žádné přetečení ani při větším písmu v systému).
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: 0,
                maxHeight: collapsibleHeight,
                child: Opacity(
                  opacity: 1 - t,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6, top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: MotoGoTypo.sizeBase,
                            fontWeight: MotoGoTypo.w600,
                            color: Color(0xFF8AAB99),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      search,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
