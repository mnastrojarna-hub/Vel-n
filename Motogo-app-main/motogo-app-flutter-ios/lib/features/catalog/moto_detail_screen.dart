import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'catalog_provider.dart';
import 'moto_detail_page.dart';

/// Moto detail pager — wraps [MotoDetailPage] instances in a horizontal
/// PageView so the user can swipe left/right between filtered motorcycles.
/// When only one motorcycle is available, it falls back to a single page.
class MotoDetailScreen extends ConsumerStatefulWidget {
  final String motoId;
  const MotoDetailScreen({super.key, required this.motoId});

  @override
  ConsumerState<MotoDetailScreen> createState() => _MotoDetailScreenState();
}

class _MotoDetailScreenState extends ConsumerState<MotoDetailScreen> {
  late PageController _pagerCtrl;
  late List<String> _motoIds;
  int _currentIndex = 0;

  /// Large multiplier so the user can swipe in both directions "infinitely".
  static const _loopMultiplier = 10000;

  @override
  void initState() {
    super.initState();
    _motoIds = ref.read(filteredMotoIdsProvider);

    // Find initial index; fall back to single-item list if not found.
    final idx = _motoIds.indexOf(widget.motoId);
    if (idx == -1) {
      _motoIds = [widget.motoId];
      _currentIndex = 0;
    } else {
      _currentIndex = idx;
    }

    // Start in the middle of the virtual list so we can swipe both ways.
    final startPage = _motoIds.length > 1
        ? (_loopMultiplier ~/ 2) * _motoIds.length + _currentIndex
        : _currentIndex;
    _pagerCtrl = PageController(initialPage: startPage);
  }

  @override
  void dispose() {
    _pagerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPager = _motoIds.length > 1;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          // === MAIN CONTENT (single page or pager) ===
          if (hasPager)
            PageView.builder(
              controller: _pagerCtrl,
              itemCount: _motoIds.length * _loopMultiplier,
              onPageChanged: (i) =>
                  setState(() => _currentIndex = i % _motoIds.length),
              itemBuilder: (_, i) {
                final idx = i % _motoIds.length;
                return MotoDetailPage(
                  key: ValueKey(_motoIds[idx]),
                  motoId: _motoIds[idx],
                );
              },
            )
          else
            MotoDetailPage(
              motoId: widget.motoId,
              showBackButton: true,
            ),

          // === BACK BUTTON (pager mode) ===
          if (hasPager)
            Positioned(
              top: topPad + 8,
              left: 12,
              child: GestureDetector(
                onTap: () => context.pop(),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: MotoGoColors.green,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: Colors.black,
                  ),
                ),
              ),
            ),

          // === POSITION INDICATOR (pager mode) ===
          if (hasPager)
            Positioned(
              top: topPad + 14,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: MotoGoColors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${_motoIds.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
