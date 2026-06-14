import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme.dart';

/// Přehrávač MP4 videí motorky — používá se POUZE na detailu motorky.
/// Videa se spustí automaticky po otevření detailu (muted, lze odmutovat).
/// Více videí jede za sebou; po posledním se vrací na první. Jedno video se
/// přehrává ve smyčce. V přehledu/seznamu se video nepoužívá (vždy fotka).
class MotoVideoPlayer extends StatefulWidget {
  final List<String> urls;
  const MotoVideoPlayer({super.key, required this.urls});

  @override
  State<MotoVideoPlayer> createState() => _MotoVideoPlayerState();
}

class _MotoVideoPlayerState extends State<MotoVideoPlayer> {
  VideoPlayerController? _ctrl;
  int _idx = 0;
  bool _muted = true;
  bool _ready = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    if (widget.urls.isNotEmpty) _load(0);
  }

  Future<void> _load(int i) async {
    final old = _ctrl;
    if (mounted) setState(() => _ready = false);
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.urls[i]));
    _ctrl = c;
    _idx = i;
    c.addListener(_listener);
    try {
      await c.initialize();
      if (_disposed) { await c.dispose(); return; }
      await c.setVolume(_muted ? 0 : 1);
      await c.setLooping(widget.urls.length == 1);
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Když se video nepovede načíst, zkus po chvíli další (pokud existuje).
      if (!_disposed && widget.urls.length > 1) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!_disposed) _load((i + 1) % widget.urls.length);
      }
    }
    old?.removeListener(_listener);
    await old?.dispose();
  }

  void _listener() {
    final c = _ctrl;
    if (c == null || _disposed) return;
    final v = c.value;
    // Postup na další video po dokončení (jen u více videí — single má looping).
    if (widget.urls.length > 1 &&
        v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying) {
      _load((_idx + 1) % widget.urls.length);
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _ctrl?.setVolume(_muted ? 0 : 1);
  }

  @override
  void dispose() {
    _disposed = true;
    _ctrl?.removeListener(_listener);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    final ar = (c != null && c.value.isInitialized && c.value.aspectRatio > 0)
        ? c.value.aspectRatio
        : 16 / 9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: ar,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: MotoGoColors.black),
            if (c != null && _ready)
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: MotoGoColors.green),
              ),
            Positioned(
              bottom: 10,
              right: 10,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: MotoGoColors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: MotoGoColors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        '${_idx + 1} / ${widget.urls.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
