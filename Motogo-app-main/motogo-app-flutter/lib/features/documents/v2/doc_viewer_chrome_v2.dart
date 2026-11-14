import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/states/legacy_state_looks.dart' show v2LoadingLook;
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';

/// v2 chrome of the document viewers (`DocWebViewScreen`, `PdfPagesScreen`;
/// V22 §6.2 "viewer = ✕"): compact dark `MgAppBar` with a ✕ 44 disc (the
/// SAME close the old ‹ ran), title 17/800 on one line or 15/800 on two —
/// never an ellipsis — and the canvas page behind the document. DUMB: the
/// screens keep loading, retry, refresh and errors.
class DocViewerScaffoldV2 extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget body;

  /// Document surface: white for an HTML document (it paints its own page),
  /// canvas for rendered PDF pages (white page cards on it).
  final Color background;

  const DocViewerScaffoldV2({
    super.key,
    required this.title,
    required this.onClose,
    required this.body,
    this.background = MgColors.canvas,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgAppBar(title: title, onBack: onClose, close: true),
        Expanded(child: body),
      ]),
    );
  }
}

/// Loading look of a document: one white A4 page (r12) with text-line
/// skeletons on the canvas, in the final page geometry (no jump when the
/// document lands). Never stuck silently: after 15 s the same "takes
/// longer" state as `MgLoadingView` (retry / back = the screen's actions).
class DocA4SkeletonV2 extends StatefulWidget {
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  const DocA4SkeletonV2({super.key, this.onRetry, this.onBack});

  @override
  State<DocA4SkeletonV2> createState() => _DocA4SkeletonV2State();
}

class _DocA4SkeletonV2State extends State<DocA4SkeletonV2> {
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slow) {
      return ColoredBox(
        color: MgColors.canvas,
        child: v2LoadingLook(context, slow: true, onRetry: widget.onRetry, onBack: widget.onBack),
      );
    }
    // Řádky stránky: nadpis, odstavce, podpisový blok — jen tvar, žádný text.
    const lines = [0.55, 1.0, 0.92, 0.97, 0.6, 0.0, 1.0, 0.88, 0.94, 0.7, 0.0, 0.95, 0.82, 0.4];
    return ColoredBox(
      color: MgColors.canvas,
      child: Semantics(
        label: t(context).loading,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: AspectRatio(
            aspectRatio: 1 / 1.414,
            child: DocPageCardV2(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: LayoutBuilder(builder: (context, c) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final f in lines)
                      Padding(
                        padding: EdgeInsets.only(bottom: f == 0 ? 18 : 10),
                        child: f == 0 ? const SizedBox.shrink() : MgSkeleton(width: c.maxWidth * f, height: 10, radius: 5),
                      ),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White page card (r12, card shadow) of a document page on the canvas.
class DocPageCardV2 extends StatelessWidget {
  final Widget child;
  const DocPageCardV2({super.key, required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: MgShadows.card,
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
      );
}
