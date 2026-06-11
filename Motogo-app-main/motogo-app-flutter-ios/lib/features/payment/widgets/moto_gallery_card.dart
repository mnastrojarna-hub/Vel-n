import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// Swipeable motorcycle photo gallery for payment summary screen.
/// Shows all motorcycle images with dot indicators and swipe navigation.
class MotoGalleryCard extends StatefulWidget {
  final List<String> images;
  final String model;
  final String? branchName;
  final String? branchCity;

  const MotoGalleryCard({
    super.key,
    required this.images,
    required this.model,
    this.branchName,
    this.branchCity,
  });

  @override
  State<MotoGalleryCard> createState() => _MotoGalleryCardState();
}

class _MotoGalleryCardState extends State<MotoGalleryCard> {
  final _controller = PageController();
  int _currentPage = 0;
  Timer? _autoSwipeTimer;

  List<String> get _imgs =>
      widget.images.isNotEmpty ? widget.images : [''];

  @override
  void initState() {
    super.initState();
    _startAutoSwipe();
  }

  void _startAutoSwipe() {
    _autoSwipeTimer?.cancel();
    if (_imgs.length <= 1) return;
    _autoSwipeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_controller.hasClients) return;
      final next = (_currentPage + 1) % _imgs.length;
      _controller.animateToPage(next,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _autoSwipeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.card,
      ),
      child: Column(
        children: [
          // Image carousel
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MotoGoRadius.card),
            ),
            child: SizedBox(
              height: 200,
              child: Stack(
                children: [
                  // PageView
                  PageView.builder(
                    controller: _controller,
                    itemCount: _imgs.length,
                    onPageChanged: (i) =>
                        setState(() => _currentPage = i),
                    itemBuilder: (_, i) {
                      final url = _imgs[i];
                      if (url.isEmpty) {
                        return Container(
                          color: MotoGoColors.g100,
                          child: const Center(
                            child: Icon(Icons.motorcycle,
                                size: 48, color: MotoGoColors.g400),
                          ),
                        );
                      }
                      return CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (_, __) => Container(
                          color: MotoGoColors.g100,
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MotoGoColors.green,
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: MotoGoColors.g100,
                          child: const Center(
                            child: Icon(Icons.motorcycle,
                                size: 48, color: MotoGoColors.g400),
                          ),
                        ),
                      );
                    },
                  ),

                  // Gradient overlay at bottom
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 80,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            MotoGoColors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Model name + branch
                  Positioned(
                    left: 14,
                    bottom: 12,
                    right: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.model,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        if (widget.branchName != null)
                          Row(children: [
                            const Icon(Icons.location_on,
                                size: 11, color: MotoGoColors.green),
                            const SizedBox(width: 3),
                            Text(
                              '${widget.branchName}'
                              '${widget.branchCity != null ? ', ${widget.branchCity}' : ''}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ]),
                      ],
                    ),
                  ),

                  // Swipe hint arrow (right)
                  if (_imgs.length > 1 && _currentPage < _imgs.length - 1)
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: MotoGoColors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chevron_right,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Dot indicators
          if (_imgs.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _imgs.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _currentPage ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i == _currentPage
                          ? MotoGoColors.green
                          : MotoGoColors.g200,
                      borderRadius: BorderRadius.circular(3),
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
