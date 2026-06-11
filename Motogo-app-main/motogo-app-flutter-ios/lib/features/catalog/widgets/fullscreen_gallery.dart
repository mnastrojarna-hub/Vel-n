import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Fullscreen zoomable image gallery.
/// Supports swipe between images, pinch-to-zoom, close via X or swipe down.
class FullscreenGallery extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const FullscreenGallery({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  /// Opens the gallery as a fullscreen modal route.
  static void open(
    BuildContext context, {
    required List<String> images,
    int initialIndex = 0,
  }) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => FullscreenGallery(
        images: images,
        initialIndex: initialIndex,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 200),
    ));
  }

  @override
  State<FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<FullscreenGallery> {
  late PageController _pageCtrl;
  late int _current;

  /// Vertical drag offset for swipe-to-dismiss.
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    setState(() => _dragY += d.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    // Dismiss if dragged far enough or fast enough.
    if (_dragY.abs() > 100 ||
        d.velocity.pixelsPerSecond.dy.abs() > 800) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragY = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final opacity = (1.0 - (_dragY.abs() / 300)).clamp(0.4, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(
        children: [
          // === IMAGE PAGER ===
          GestureDetector(
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: Transform.translate(
              offset: Offset(0, _dragY),
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: widget.images.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (_, i) => InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: widget.images[i],
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                          color: MotoGoColors.green,
                        ),
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.motorcycle,
                        size: 64,
                        color: MotoGoColors.g400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // === CLOSE BUTTON ===
          Positioned(
            top: topPad + 8,
            right: 12,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MotoGoColors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.close,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // === COUNTER BADGE ===
          if (widget.images.length > 1)
            Positioned(
              top: topPad + 14,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: MotoGoColors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_current + 1} / ${widget.images.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
