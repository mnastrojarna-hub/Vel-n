import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../core/router.dart';

/// Sdílené prvky obrazovek Pobočky (přehled + detail pobočky).

AppBar branchesAppBar(BuildContext context, String title) => AppBar(
      leading: GestureDetector(
        onTap: () => context.canPop() ? context.pop() : context.go(Routes.profile),
        child: Center(
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
            child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
          ),
        ),
      ),
      title: Text(title),
      backgroundColor: MotoGoColors.dark,
    );

const branchesBodyStyle = TextStyle(fontSize: 13.5, height: 1.45, color: MotoGoColors.g600);

BoxDecoration branchesCardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 4))],
    );

Widget branchBadge(String? html) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
      child: Text(plainText(html ?? '').toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: MotoGoColors.dark)),
    );

Widget branchLine(String icon, String? html, TextStyle style) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$icon ', style: style),
        Expanded(child: richText(html, style)),
      ]),
    );

/// Zelený box s tlačítkem do rezervace (texty `cta.*`).
Widget branchesCtaBox(BuildContext context, Map<String, String> tx) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        richText(tx['cta.title'], const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
        const SizedBox(height: 6),
        richText(tx['cta.text'], const TextStyle(fontSize: 13, height: 1.4, color: MotoGoColors.dark)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => context.go(Routes.search),
          style: ElevatedButton.styleFrom(
            backgroundColor: MotoGoColors.dark, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
          ),
          child: Text(plainText(tx['cta.button'] ?? ''), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );

/// Video pobočky z Velína: soubor (MP4 v bucketu media) hraje přímo v appce,
/// odkaz na YouTube otevře externí přehrávač.
class BranchVideo extends StatefulWidget {
  final String url;
  const BranchVideo({super.key, required this.url});
  @override
  State<BranchVideo> createState() => _BranchVideoState();
}

class _BranchVideoState extends State<BranchVideo> {
  VideoPlayerController? _c;
  bool _failed = false;

  bool get _isYt => RegExp(r'youtu\.?be', caseSensitive: false).hasMatch(widget.url);

  @override
  void initState() {
    super.initState();
    if (!_isYt) {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _c = c;
      c.initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  void _openExternal() =>
      launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_isYt || _failed || c == null) {
      return GestureDetector(
        onTap: _openExternal,
        child: Container(
          height: 180,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
          child: const Center(child: Icon(Icons.play_circle_fill, size: 64, color: MotoGoColors.green)),
        ),
      );
    }
    if (!c.value.isInitialized) {
      return Container(
        height: 180,
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
        child: const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
      );
    }
    final playing = c.value.isPlaying;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: Stack(alignment: Alignment.center, children: [
          VideoPlayer(c),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => playing ? c.pause() : c.play(),
            child: AnimatedOpacity(
              opacity: playing ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: const Center(child: Icon(Icons.play_circle_fill, size: 64, color: MotoGoColors.green)),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: VideoProgressIndicator(c, allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: MotoGoColors.green)),
          ),
        ]),
      ),
    );
  }
}

/// CMS texty jsou HTML z editoru Velína — tučné (<strong>/<b>) zachováme,
/// zalomení (<br>, odstavce, div) převedeme na nové řádky, ostatní tagy zahodíme.
Widget richText(String? html, TextStyle style) {
  final src = (html ?? '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|li)>\s*<(p|div|li)[^>]*>', caseSensitive: false), '\n');
  final spans = <TextSpan>[];
  var bold = false;
  for (final part in src.split(RegExp(r'(?=<)|(?<=>)'))) {
    final tag = RegExp(r'^<\s*(/?)\s*(strong|b)\b', caseSensitive: false).firstMatch(part);
    if (tag != null) {
      bold = tag.group(1) != '/';
    } else if (!part.startsWith('<')) {
      final s = _decode(part);
      if (s.isNotEmpty) spans.add(TextSpan(text: s, style: bold ? const TextStyle(fontWeight: FontWeight.w800) : null));
    }
  }
  return Text.rich(TextSpan(style: style, children: spans));
}

String plainText(String html) => _decode(html.replaceAll(RegExp(r'<[^>]*>'), '')).trim();

String _decode(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
