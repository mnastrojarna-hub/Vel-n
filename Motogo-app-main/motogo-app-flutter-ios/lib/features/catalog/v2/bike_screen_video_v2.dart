import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/offline_guard.dart';

/// One bike video player as the new look's photo → video stage needs it
/// (owner v5.0.1 "fotka 5 vteřin, pak video"). The real one wraps
/// `VideoPlayerController` (only calls that exist in the iOS-pinned
/// video_player 2.10.1); tests swap [bikeVideoFactory] for a fake.
abstract class BikeVideoPlayer implements Listenable {
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> setVolume(double volume);
  Future<void> setLooping(bool looping);
  Future<void> dispose();

  bool get isInitialized;
  bool get isPlaying;
  bool get hasError;
  Duration get position;
  Duration get duration;
  Size get size;

  /// The picture (contain-fitted by the caller).
  Widget view();
}

class _RealBikeVideo implements BikeVideoPlayer {
  final VideoPlayerController c;
  _RealBikeVideo(String url)
      // mixWithOthers: a muted bike video never stops the customer's music.
      : c = VideoPlayerController.networkUrl(Uri.parse(url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));

  @override
  void addListener(VoidCallback l) => c.addListener(l);
  @override
  void removeListener(VoidCallback l) => c.removeListener(l);
  @override
  Future<void> initialize() => c.initialize();
  @override
  Future<void> play() => c.play();
  @override
  Future<void> pause() => c.pause();
  @override
  Future<void> setVolume(double v) => c.setVolume(v);
  @override
  Future<void> setLooping(bool l) => c.setLooping(l);
  @override
  Future<void> dispose() => c.dispose();
  @override
  bool get isInitialized => c.value.isInitialized;
  @override
  bool get isPlaying => c.value.isPlaying;
  @override
  bool get hasError => c.value.hasError;
  @override
  Duration get position => c.value.position;
  @override
  Duration get duration => c.value.duration;
  @override
  Size get size => c.value.size;
  @override
  Widget view() => VideoPlayer(c);
}

/// Creates the player of one video URL (tests: a fake, no network).
BikeVideoPlayer Function(String url) bikeVideoFactory = _RealBikeVideo.new;

/// "Is the phone on Wi-Fi?" — autoplay only then (owner: on mobile data the
/// photo stays with a play button). Tests swap it.
Future<bool> Function() bikeVideoOnWifi = OfflineGuard.onWifi;

/// Settle → start loading in the background.
const Duration kBikeVideoPreload = Duration(seconds: 1);

/// Settle → the photo cross-fades to the video.
const Duration kBikeVideoAutoplay = Duration(seconds: 5);

/// The one bike video player alive in the app: a stage that claims it stops
/// the previous holder first (never two downloads / decoders at once).
class BikeVideoSlot {
  BikeVideoSlot._();
  static Object? _owner;
  static VoidCallback? _release;

  /// [owner] now holds the player; the previous holder's [release] runs.
  static void claim(Object owner, VoidCallback release) {
    if (identical(_owner, owner)) return;
    final prev = _release;
    _owner = owner;
    _release = release;
    prev?.call();
  }

  /// [owner] gave its player up (no-op when it no longer holds the slot).
  static void free(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _release = null;
  }

  @visibleForTesting
  static Object? get owner => _owner;
}
