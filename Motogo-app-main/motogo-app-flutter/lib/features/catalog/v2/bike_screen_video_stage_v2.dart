import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../../core/v2/motion/mg_motion.dart';
import 'bike_screen_video_v2.dart';

/// Where the stage runs: a list card loops its first video; the detail
/// hero plays the videos in their order (mute disc + "n / m" pill).
enum BikeVideoMode { card, hero }

/// What the photo → video layers draw ([BikeVideoStage] owns it).
class BikeVideoHandle extends ChangeNotifier {
  BikeVideoHandle(this.count);

  int count;
  BikeVideoPlayer? player;

  /// The video covers the photo (it is playing, first frame shown).
  bool showing = false;

  /// The photo stays with a play button (mobile data, reduced motion, or
  /// the customer swiped to another photo).
  bool canTap = false;

  /// Loading after a tap on the play button.
  bool loading = false;
  bool muted = true;
  int index = 0;

  VoidCallback? _tap;
  VoidCallback? _mute;
  void tapPlay() => _tap?.call();
  void toggleMute() => _mute?.call();
  void _changed() => notifyListeners();
}

/// Photo first, then the bike video (owner v5.0.1): when the stage has been
/// settled and at least [minVisible] on screen for [kBikeVideoAutoplay],
/// the app is in the foreground, its page is the current one, the phone is
/// on Wi-Fi, reduced motion is off and the bike has [videos], [builder]'s
/// layers cross-fade to the muted video; it starts loading after
/// [kBikeVideoPreload]. Scrolling it away, another page on top, the app in
/// the background or a photo swipe (a horizontal scroll inside) stop it and
/// dispose the player; only one player lives in the app ([BikeVideoSlot]).
/// A failure keeps the photo, silently.
class BikeVideoStage extends StatefulWidget {
  final List<String> videos;
  final BikeVideoMode mode;
  final double minVisible;
  final Widget Function(BuildContext context, BikeVideoHandle video) builder;

  const BikeVideoStage({
    super.key,
    required this.videos,
    required this.builder,
    this.mode = BikeVideoMode.card,
    this.minVisible = 0.9,
  });

  @override
  State<BikeVideoStage> createState() => _BikeVideoStageState();
}

class _BikeVideoStageState extends State<BikeVideoStage> with WidgetsBindingObserver {
  late final BikeVideoHandle _h = BikeVideoHandle(widget.videos.length);
  final List<ScrollPosition> _positions = [];
  Animation<double>? _routeAnim;
  Timer? _debounce, _preload, _autoplay, _handover;
  bool _armed = false, _swiped = false, _failed = false, _want = false;
  bool _fg = true, _routeOk = true, _ticker = true, _checkQueued = false;
  int _armGen = 0, _playerGen = 0;

  /// Hero: the next video loading while the finished one keeps its last
  /// frame on screen (handed over once it plays).
  BikeVideoPlayer? _next;
  int _nextIdx = 0;

  List<String> get _videos => widget.videos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _h._tap = _tapPlay;
    _h._mute = _toggleMute;
    if (_videos.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _routeOk = route?.isCurrent ?? true;
    _ticker = TickerMode.valuesOf(context).enabled;
    if (!identical(route?.animation, _routeAnim)) {
      _routeAnim?.removeStatusListener(_onRouteAnim);
      _routeAnim = route?.animation?..addStatusListener(_onRouteAnim);
    }
    _wire();
    _queueEvaluate();
  }

  @override
  void didUpdateWidget(BikeVideoStage old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.videos, widget.videos) || old.mode != widget.mode) {
      _failed = false;
      _swiped = false;
      _stop();
      _h.count = widget.videos.length;
      _wire();
      _queueEvaluate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _fg = state == AppLifecycleState.resumed;
    if (!_fg) _stop();
    _queueEvaluate();
  }

  void _onRouteAnim(AnimationStatus s) {
    if (s == AnimationStatus.completed) _queueEvaluate();
  }

  /// Listen to every scrollable around the stage (the list / page and the
  /// bike pager): a scroll stops the countdown; it re-arms once settled.
  void _wire() {
    if (_videos.isEmpty) return _unwire();
    final next = <ScrollPosition>[];
    BuildContext ctx = context;
    for (var k = 0; k < 3; k++) {
      final s = Scrollable.maybeOf(ctx);
      if (s == null) break;
      next.add(s.position);
      ctx = s.context;
    }
    if (listEquals(next, _positions)) return;
    _unwire();
    for (final p in next) {
      p.addListener(_onScroll);
      p.isScrollingNotifier.addListener(_onScroll);
    }
    _positions.addAll(next);
  }

  void _unwire() {
    for (final p in _positions) {
      p.removeListener(_onScroll);
      p.isScrollingNotifier.removeListener(_onScroll);
    }
    _positions.clear();
  }

  void _onScroll() {
    if (!_h.showing && !_h.loading) _disarm();
    if (!_checkQueued) {
      _checkQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkQueued = false;
        if (mounted && _fraction() < widget.minVisible) _stop(left: true);
      });
    }
    _queueEvaluate();
  }

  void _queueEvaluate() {
    _debounce?.cancel();
    if (_videos.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 200), _evaluate);
  }

  /// Share of the stage on the screen (a stage taller than the screen
  /// counts as whole when it fills the screen).
  double _fraction() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return 0;
    final r = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final i = r.intersect(screen);
    if (i.width <= 0 || i.height <= 0) return 0;
    final w = r.width < screen.width ? r.width : screen.width;
    final h = r.height < screen.height ? r.height : screen.height;
    return (i.width / w) * (i.height / h);
  }

  bool _eligible() =>
      mounted && _videos.isNotEmpty && _fg && _routeOk && _ticker && !_failed && _fraction() >= widget.minVisible;

  void _evaluate() {
    if (!mounted) return;
    if (!_eligible()) {
      _stop(left: _fraction() < widget.minVisible);
      return;
    }
    if (_h.showing || _armed || _h.loading) return;
    _armed = true;
    final gen = ++_armGen;
    if (MgMotion.reduced(context) || _swiped) {
      _setTap(true);
      return;
    }
    final wifi = bikeVideoOnWifi().catchError((_) => false);
    wifi.then((w) {
      if (gen == _armGen && mounted && !w) _setTap(true);
    });
    Future<void> go(bool play) async {
      if (!await wifi || gen != _armGen || !_eligible() || _swiped) return;
      if (play) _want = true;
      _ensurePlayer(_h.index);
      _maybePlay();
    }

    _preload = Timer(kBikeVideoPreload, () => go(false));
    _autoplay = Timer(kBikeVideoAutoplay, () => go(true));
  }

  void _disarm() {
    _preload?.cancel();
    _autoplay?.cancel();
    if (_armed) {
      _armed = false;
      _armGen++;
    }
  }

  void _setTap(bool v) {
    if (_h.canTap == v || !mounted) return;
    _h.canTap = v;
    _h._changed();
  }

  void _ensurePlayer(int i) {
    if (_h.player != null && _h.index == i) return;
    _disposePlayer();
    BikeVideoSlot.claim(this, _bumped);
    final p = bikeVideoFactory(_videos[i]);
    final g = ++_playerGen;
    _h.player = p;
    _h.index = i;
    p.addListener(_onPlayer);
    _init(p, g);
    _h._changed();
  }

  Future<void> _init(BikeVideoPlayer p, int g) async {
    try {
      await p.initialize();
      if (g != _playerGen) return;
      await p.setVolume(_h.muted ? 0 : 1);
      await p.setLooping(widget.mode == BikeVideoMode.card || _videos.length == 1);
      if (g == _playerGen) _maybePlay();
    } catch (_) {
      if (g == _playerGen) _fail();
    }
  }

  void _maybePlay() {
    final p = _h.player;
    if (p == null || !_want || !p.isInitialized || p.isPlaying) return;
    p.play().catchError((Object _) => _fail());
  }

  void _onPlayer() {
    final p = _h.player;
    if (p == null || !mounted) return;
    if (p.hasError) {
      _fail();
      return;
    }
    final show = _h.showing ? p.isInitialized : (p.isInitialized && p.isPlaying && p.position > Duration.zero);
    if (show != _h.showing) {
      _h.showing = show;
      if (show) {
        _h.loading = false;
        _h.canTap = false;
      }
      _h._changed();
    }
    // Several videos (detail hero): the next one after the end, in order.
    final d = p.duration;
    if (widget.mode == BikeVideoMode.hero &&
        _videos.length > 1 &&
        p.isInitialized &&
        d > Duration.zero &&
        p.position >= d &&
        !p.isPlaying &&
        _next == null) {
      _startNext((_h.index + 1) % _videos.length);
    }
  }

  /// Loads and starts video [i] behind the finished one; the finished one
  /// stays (last frame, "n / m", mute) until [i] shows its first frame — no
  /// fade back to the photo while a slow MP4 initialises. Two players live
  /// only for that hand-over.
  void _startNext(int i) {
    final p = bikeVideoFactory(_videos[i]);
    final g = _playerGen;
    _next = p;
    _nextIdx = i;
    p.addListener(_onNext);
    // A next video that neither starts nor fails (stalled MP4 on weak LTE):
    // back to the photo after [kBikeVideoHandoverMax], not a frozen frame.
    _handover?.cancel();
    _handover = Timer(kBikeVideoHandoverMax, () {
      if (mounted && g == _playerGen && identical(_next, p)) _fail();
    });
    () async {
      try {
        await p.initialize();
        if (g != _playerGen || !identical(_next, p)) return;
        await p.setVolume(_h.muted ? 0 : 1);
        await p.setLooping(false);
        if (g == _playerGen && identical(_next, p)) await p.play();
      } catch (_) {
        if (g == _playerGen && identical(_next, p)) _fail();
      }
    }();
  }

  void _onNext() {
    final p = _next;
    if (p == null || !mounted) return;
    if (p.hasError) return _fail();
    if (!(p.isInitialized && p.isPlaying && p.position > Duration.zero)) return;
    p.removeListener(_onNext);
    _next = null;
    _handover?.cancel();
    final old = _h.player;
    old?.removeListener(_onPlayer);
    old?.dispose().catchError((Object _) {});
    _playerGen++;
    _h.player = p;
    _h.index = _nextIdx;
    p.addListener(_onPlayer);
    _h._changed();
  }

  void _fail() {
    _failed = true;
    _stop();
  }

  void _disposePlayer() {
    _handover?.cancel();
    final n = _next;
    if (n != null) {
      _next = null;
      n.removeListener(_onNext);
      n.dispose().catchError((Object _) {});
    }
    final p = _h.player;
    if (p == null) return;
    _playerGen++;
    p.removeListener(_onPlayer);
    _h.player = null;
    p.dispose().catchError((Object _) {});
  }

  /// Another stage took the one player: give it up, do not re-arm until
  /// this stage is scrolled / resumed again.
  void _bumped() {
    _preload?.cancel();
    _autoplay?.cancel();
    _want = false;
    _disposePlayer();
    _h.showing = false;
    _h.loading = false;
    if (mounted) _h._changed();
  }

  /// Back to the photo. [left] = the stage left the screen: a photo swipe is
  /// forgotten (coming back plays again).
  void _stop({bool left = false}) {
    _disarm();
    _want = false;
    _disposePlayer();
    BikeVideoSlot.free(this);
    if (left) _swiped = false;
    final changed = _h.showing || _h.loading || _h.canTap || _h.index != 0;
    _h.showing = false;
    _h.loading = false;
    _h.canTap = false;
    _h.index = 0;
    if (changed && mounted) _h._changed();
  }

  void _photoSwipe() {
    if (_videos.isEmpty) return;
    _swiped = true;
    _stop();
    _armed = true;
    if (!_failed) _setTap(true);
  }

  void _tapPlay() {
    if (_videos.isEmpty || _failed) return;
    _disarm();
    _swiped = false;
    _armed = true;
    _want = true;
    _h.canTap = false;
    _h.loading = true;
    _ensurePlayer(_h.index);
    _maybePlay();
    _h._changed();
  }

  void _toggleMute() {
    _h.muted = !_h.muted;
    _h.player?.setVolume(_h.muted ? 0 : 1).catchError((Object _) {});
    _h._changed();
  }

  @override
  void dispose() {
    _h._tap = null;
    _h._mute = null;
    WidgetsBinding.instance.removeObserver(this);
    _routeAnim?.removeStatusListener(_onRouteAnim);
    _unwire();
    _debounce?.cancel();
    _stop();
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollStartNotification>(
        // A photo swipe inside (the photo pager) → back to the photos.
        onNotification: (n) {
          if (n.metrics.axis == Axis.horizontal) _photoSwipe();
          return false;
        },
        child: widget.builder(context, _h),
      );
}
