// Real photos in screenshots (journey rig + render harness). When the env
// var MG_SHOT_IMG_DIR points at a folder with `moto/*.jpg` and
// `route/*.jpg` (real fleet / route photos, outside the repo), every
// network photo the app loads through CachedNetworkImage (MgImage,
// RouteImage, precache) resolves to one of those files: an in-memory cache
// manager (no sqflite, no disk, no network) answers from the local files.
// Without the env var nothing changes (photos show their placeholders).
//
// Mapping, stable per URL (query and the `render/image` thumbnail prefix
// are ignored):
//   …/shot/moto/07.jpg  or …/shot/route/03.jpg  → that exact file
//   a URL listed as `source` in <dir>/manifest.json → its file
//   any other URL → a file picked by a hash of the URL, from `route/` when
//   the URL looks like a route / place photo, else from `moto/`.
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/supabase_client.dart';

/// The local photo folder (MG_SHOT_IMG_DIR) or null.
String? get shotImgDir {
  final v = Platform.environment['MG_SHOT_IMG_DIR'];
  return v == null || v.isEmpty || !Directory(v).existsSync() ? null : v;
}

/// True while real photos are served (after [installShotImages]).
bool shotImagesOn = false;

/// A fixture photo URL: `shotUrl('moto', 3)` → …/media/shot/moto/03.jpg.
/// With MG_SHOT_IMG_DIR it shows `moto/03.jpg`; without, a placeholder.
String shotUrl(String kind, int n) =>
    '${MotoGoSupabase.url}/storage/v1/object/public/media/shot/$kind/${n.toString().padLeft(2, '0')}.jpg';

final _files = <String, List<String>>{};
Map<String, String>? _manifest;

List<String> _list(String dir, String kind) => _files.putIfAbsent(kind, () {
      final d = Directory('$dir/$kind');
      if (!d.existsSync()) return const [];
      return d.listSync().whereType<File>().map((f) => f.path).where((p) => p.toLowerCase().endsWith('.jpg')).toList()
        ..sort();
    });

Map<String, String> _readManifest(String dir) {
  final out = <String, String>{};
  final f = File('$dir/manifest.json');
  if (!f.existsSync()) return out;
  // Minimal parse: "file":"moto/01.jpg" … "source":"https://…" pairs.
  final s = f.readAsStringSync();
  final re = RegExp(r'"file":\s*"([^"]+)",\s*"source":\s*"([^"]+)"');
  for (final m in re.allMatches(s)) {
    out[_norm(m.group(2)!)] = '$dir/${m.group(1)}';
  }
  return out;
}

String _norm(String url) {
  var u = url.startsWith('http://') ? 'https://${url.substring(7)}' : url;
  final q = u.indexOf('?');
  if (q >= 0) u = u.substring(0, q);
  return u.replaceFirst('/storage/v1/render/image/public/', '/storage/v1/object/public/');
}

int _fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The local file for [url] (null = no MG_SHOT_IMG_DIR or no files).
String? shotFileFor(String url) {
  final dir = shotImgDir;
  if (dir == null) return null;
  final u = _norm(url);
  final fixed = RegExp(r'/shot/(moto|route)/(\d+)\.jpg$').firstMatch(u);
  if (fixed != null) {
    final f = '$dir/${fixed.group(1)}/${fixed.group(2)!.padLeft(2, '0')}.jpg';
    if (File(f).existsSync()) return f;
  }
  final m = (_manifest ??= _readManifest(dir))[u];
  if (m != null && File(m).existsSync()) return m;
  final low = u.toLowerCase();
  final route = ['routes-mirror', '/route', 'poi', 'place', 'wikimedia', 'wikipedia', '-cover', '-sights', '-castle',
    '-lookout', '-food', '-water', '-nature', '-tech'].any(low.contains);
  final list = _list(dir, route ? 'route' : 'moto');
  final pool = list.isNotEmpty ? list : _list(dir, route ? 'moto' : 'route');
  if (pool.isEmpty) return null;
  return pool[_fnv(u) % pool.length];
}

final _bytes = <String, List<int>>{};

/// Serves local photos to every CachedNetworkImage (no-op without
/// MG_SHOT_IMG_DIR). Call before the first frame.
void installShotImages() {
  if (shotImgDir == null || shotImagesOn) return;
  shotImagesOn = true;
  final client = MockClient((r) async {
    final f = shotFileFor(r.url.toString());
    if (f == null) return http.Response('', 404, request: r);
    final b = _bytes.putIfAbsent(f, () => File(f).readAsBytesSync());
    return http.Response.bytes(b, 200, request: r, headers: {'content-type': 'image/jpeg'});
  });
  CachedNetworkImageProvider.defaultCacheManager = CacheManager(Config(
    'mg_shot_images',
    stalePeriod: const Duration(days: 365),
    repo: NonStoringObjectProvider(),
    fileSystem: MemoryCacheSystem(),
    fileService: HttpFileService(httpClient: client),
  ));
}

/// Lets real-time work (image decoding) finish and shows the result:
/// a few rounds of a real-time pause + a frame. No-op without photos.
Future<void> warmShotImages(WidgetTester t, {int rounds = 4}) async {
  if (!shotImagesOn) return;
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 50));
  }
}
