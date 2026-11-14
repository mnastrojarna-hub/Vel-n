// Fake bike video player + Wi-Fi switch for the 5.0.1 photo → video tests
// (no network, no platform channel).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_video_v2.dart';

class FakeVideo extends ChangeNotifier implements BikeVideoPlayer {
  final FakeVideos owner;
  final String url;
  FakeVideo(this.owner, this.url);

  bool _init = false, playing = false, disposed = false, looping = false;
  double volume = 1;
  Duration _pos = Duration.zero;
  Duration length = const Duration(seconds: 30);

  @override
  Future<void> initialize() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // A stalled MP4: neither starts nor fails.
    if (owner.stalling) await Completer<void>().future;
    if (owner.failing) throw StateError('cannot play');
    if (disposed) return;
    _init = true;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    playing = true;
    _pos = const Duration(milliseconds: 40);
    notifyListeners();
  }

  /// The video reached its end (a non-looping one stops).
  void finish() {
    _pos = length;
    if (!looping) playing = false;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> setLooping(bool l) async => looping = l;

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    owner.alive--;
    super.dispose();
  }

  @override
  bool get isInitialized => _init;
  @override
  bool get isPlaying => playing;
  @override
  bool get hasError => false;
  @override
  Duration get position => _pos;
  @override
  Duration get duration => length;
  @override
  Size get size => const Size(1920, 1080);
  @override
  Widget view() => ColoredBox(key: ValueKey('fake-video-$url'), color: const Color(0xFF5577AA));
}

/// Installs the fake factory and Wi-Fi answer; [uninstall] restores both.
class FakeVideos {
  final created = <FakeVideo>[];
  int alive = 0, maxAlive = 0;
  bool wifi;
  bool failing = false;

  /// New players' initialize() never completes (SR-06).
  bool stalling = false;
  final BikeVideoPlayer Function(String) _oldFactory;
  final Future<bool> Function() _oldWifi;

  FakeVideos._(this.wifi) : _oldFactory = bikeVideoFactory, _oldWifi = bikeVideoOnWifi;

  static FakeVideos install({bool wifi = true}) {
    final f = FakeVideos._(wifi);
    bikeVideoFactory = (url) {
      final v = FakeVideo(f, url);
      f.created.add(v);
      f.alive++;
      if (f.alive > f.maxAlive) f.maxAlive = f.alive;
      return v;
    };
    bikeVideoOnWifi = () async => f.wifi;
    return f;
  }

  void uninstall() {
    bikeVideoFactory = _oldFactory;
    bikeVideoOnWifi = _oldWifi;
  }
}

/// A bike at MotoGo24 Mezná (staffed) with [videos] / [images].
Motorcycle bike(String id, {List<String> videos = const ['https://x/v1.mp4'], List<String> images = const []}) => Motorcycle(
      id: id,
      model: 'Bike $id',
      category: 'cestovni',
      videos: videos,
      images: images,
      branchName: 'MotoGo24 Mezná',
      branchCity: 'Pelhřimov',
      branchType: 'obslužná',
    );

/// Pumps [d] in 100 ms frames (timers + animations advance).
Future<void> wait(WidgetTester t, Duration d) async {
  final end = d.inMilliseconds;
  for (var ms = 0; ms < end; ms += 100) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

