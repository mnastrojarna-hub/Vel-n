import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_section.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';

/// Home section header with a "see all" link (`MgSectionHeader`): the link
/// stays beside the title only while the title's longest word fits there
/// at full size; otherwise (fr ×1,3 „Des itiné|raires…" — the long
/// "Tous les itinéraires ›" took the room) the title gets the full width
/// and the link moves to its own line, right-aligned above the cards.
class HomeSectionHead extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String link;
  final VoidCallback onLink;
  const HomeSectionHead({super.key, required this.title, this.eyebrow, required this.link, required this.onLink});

  /// true when every word of [title] fits beside [link] in a header of
  /// outer [width] (gutters 2 × 16, gap 8, `MgTextLink` = 4 + label + 2 +
  /// chevron 16 + 4, at least 44).
  static bool linkInline(BuildContext context, String title, String link, double width) {
    final linkW = math.max(44.0, mgLineWidth(context, link, MgType.small.copyWith(fontWeight: FontWeight.w800)) + 26);
    return mgWordsFit(context, title, MgType.section, width - 2 * MgSpace.gutter - 8 - linkW);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (!c.hasBoundedWidth || linkInline(context, title, link, c.maxWidth)) {
          return MgSectionHeader(eyebrow: eyebrow, title: title, trailingLabel: link, onTrailing: onLink);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MgSectionHeader(
            eyebrow: eyebrow,
            title: title,
            padding: const EdgeInsets.symmetric(horizontal: MgSpace.gutter),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MgSpace.gutter),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: MgTextLink(label: link, onTap: onLink),
            ),
          ),
        ]);
      });
}
