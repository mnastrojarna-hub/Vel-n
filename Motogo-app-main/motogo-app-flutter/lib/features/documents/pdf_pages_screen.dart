import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';

/// PDF dokument rezervace (smlouva, protokol v PDF…) PŘÍMO v appce na Androidu.
/// Android WebView PDF nevykreslí, a tak se dřív otevíral externí prohlížeč —
/// zákazník viděl „odkaz na web“ místo podepsané smlouvy (zadání majitele
/// 2026-09-29). Stránky vykreslí nativní `PdfRenderer` (MainActivity, kanál
/// `cz.motogo24/pdf`) do PNG. iOS zobrazí PDF ve WKWebView sám
/// (`DocWebViewScreen`), tuhle obrazovku nepoužívá. Když vykreslení selže,
/// nabídne otevření mimo appku (dřívější chování) — nikdy slepá ulička.
class PdfPagesScreen extends StatefulWidget {
  /// Podepsaná URL souboru v bucketu `documents` (platí 10 min).
  final String url;
  final String title;

  const PdfPagesScreen({super.key, required this.url, required this.title});

  @override
  State<PdfPagesScreen> createState() => _PdfPagesScreenState();
}

class _PdfPagesScreenState extends State<PdfPagesScreen> {
  static const _channel = MethodChannel('cz.motogo24/pdf');
  late Future<List<Uint8List>> _pages;

  @override
  void initState() {
    super.initState();
    _pages = _load();
  }

  Future<List<Uint8List>> _load() async {
    final resp = await http.get(Uri.parse(widget.url)).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    // Šířka v pixelech displeje (ostré písmo), strop kvůli paměti.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final width = view.physicalSize.width.clamp(720.0, 1600.0).round();
    final res = await _channel.invokeMethod<List<Object?>>(
        'render', {'bytes': resp.bodyBytes, 'width': width});
    final pages = (res ?? const []).whereType<Uint8List>().toList();
    if (pages.isEmpty) throw Exception('PDF bez stránek');
    return pages;
  }

  void _retry() => setState(() => _pages = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.g200,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        title: Text(widget.title, style: const TextStyle(fontSize: 15)),
        backgroundColor: MotoGoColors.dark,
      ),
      body: FutureBuilder<List<Uint8List>>(
        future: _pages,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: MotoGoColors.green));
          }
          if (snap.hasError || !snap.hasData) {
            debugPrint('[PDF_VIEW] render failed: ${snap.error}');
            return _error(context);
          }
          final pages = snap.data!;
          // Jeden InteractiveViewer přes celý dokument: tah = posun (i svisle,
          // se setrvačností), dva prsty = zoom. ListView uvnitř by se s gesty
          // zoomu hádal.
          return LayoutBuilder(
            builder: (context, c) => InteractiveViewer(
              constrained: false,
              minScale: 1,
              maxScale: 5,
              boundaryMargin: EdgeInsets.zero,
              child: SizedBox(
                width: c.maxWidth,
                child: Column(children: [
                  for (final p in pages)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6)],
                        ),
                        child: Image.memory(p, width: c.maxWidth - 16, fit: BoxFit.fitWidth, gaplessPlayback: true),
                      ),
                    ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _error(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: MotoGoColors.red),
            const SizedBox(height: 12),
            Text(t(context).tr('loadingError'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(t(context).tr('retry')),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(t(context).tr('openOutsideApp')),
            ),
          ]),
        ),
      );
}
