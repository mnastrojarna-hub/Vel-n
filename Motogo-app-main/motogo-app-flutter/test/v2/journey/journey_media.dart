// Journey rig — media options (README "Photos, video, motion"):
//   MG_SHOT_IMG_DIR=<dir>      real photos (test/v2/support/shot_images.dart)
//   MG_JOURNEY_VIDEO=wifi      bike videos load and autoplay (fake player)
//   MG_JOURNEY_VIDEO=mobile    on mobile data: no autoplay, play button;
//                              a tap on it plays the fake video
//   MG_JOURNEY_VIDEO=fail      every video fails while loading
//   MG_JOURNEY_MOTION=full     animations ON (default: reduced motion)
// Without MG_JOURNEY_VIDEO the app's own player and Wi-Fi check run
// against the mocked plugin channels (no Wi-Fi → play button only).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_video_v2.dart';

String? _env(String k) {
  final v = Platform.environment[k];
  return v == null || v.isEmpty ? null : v;
}

/// MG_JOURNEY_MOTION=full → animations on.
bool get journeyFullMotion => _env('MG_JOURNEY_MOTION') == 'full';

/// MG_JOURNEY_VIDEO (wifi | mobile | fail) or null.
String? get journeyVideoMode => _env('MG_JOURNEY_VIDEO');

/// Fake players created in this run (for the step log).
int journeyVideosCreated = 0;

/// Installs the fake player + Wi-Fi answer for [mode] (no-op for null).
void installJourneyVideo(String? mode) {
  if (mode == null) return;
  if (!const ['wifi', 'mobile', 'fail'].contains(mode)) {
    throw ArgumentError('Unknown MG_JOURNEY_VIDEO "$mode". Known: wifi, mobile, fail');
  }
  bikeVideoOnWifi = () async => mode != 'mobile';
  bikeVideoFactory = (url) {
    journeyVideosCreated++;
    return _JourneyVideo(url, fail: mode == 'fail');
  };
}

/// A 16:9 "video": a blue frame with the file name, so a screenshot shows
/// which video plays.
class _JourneyVideo extends ChangeNotifier implements BikeVideoPlayer {
  final String url;
  final bool fail;
  _JourneyVideo(this.url, {required this.fail});

  bool _init = false, _playing = false, _disposed = false, _loop = false;
  static const _len = Duration(seconds: 20);

  @override
  Future<void> initialize() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (fail) throw StateError('journey: video failed');
    if (_disposed) return;
    _init = true;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> setLooping(bool l) async => _loop = l;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  @override
  bool get isInitialized => _init;
  @override
  bool get isPlaying => _playing;
  @override
  bool get hasError => false;
  @override
  Duration get position => _playing ? const Duration(seconds: 2) : Duration.zero;
  @override
  Duration get duration => _len;
  @override
  Size get size => const Size(1920, 1080);

  @override
  Widget view() => AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF16324F), Color(0xFF2B5D8A)]),
          ),
          child: Center(
            child: Text(
              'TEST VIDEO ${url.split('/').last}${_loop ? ' · loop' : ''}',
              style: const TextStyle(fontFamily: 'Montserrat', color: Colors.white, fontSize: 110, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
}
