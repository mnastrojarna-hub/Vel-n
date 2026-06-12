import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';

/// In-app WebView screen for displaying invoices, contracts, and other
/// HTML documents. Supports loading from URL or raw HTML string.
class DocWebViewScreen extends StatefulWidget {
  /// Load from remote URL (signed Supabase storage URL).
  final String? url;

  /// Load from raw HTML string (built from DB data).
  final String? htmlContent;

  final String title;

  const DocWebViewScreen({super.key, this.url, this.htmlContent, required this.title})
      : assert(url != null || htmlContent != null, 'Provide url or htmlContent');

  @override
  State<DocWebViewScreen> createState() => _DocWebViewScreenState();
}

class _DocWebViewScreenState extends State<DocWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() { _isLoading = true; _error = null; });
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          if (mounted) setState(() { _isLoading = false; _error = error.description; });
        },
      ));

    if (widget.htmlContent != null) {
      // baseUrl is required on Android so the WebView honors the document's
      // `<meta viewport width=device-width>` — without it the page is laid out
      // at the default ~980px viewport and the centered invoice card leaves
      // empty (grey) space on the sides instead of filling the screen width.
      _controller.loadHtmlString(widget.htmlContent!, baseUrl: 'https://motogo24.cz/');
    } else {
      _controller.loadRequest(Uri.parse(widget.url!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
      body: Stack(
        children: [
          if (_error != null)
            Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 48, color: MotoGoColors.red),
                const SizedBox(height: 12),
                const Text('Nepodařilo se načíst dokument',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(_error!, style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                const SizedBox(height: 16),
                // Bez retry byl error stav slepá ulička (zvlášť po výpadku sítě)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() { _error = null; _isLoading = true; });
                    if (widget.htmlContent != null) {
                      _controller.loadHtmlString(widget.htmlContent!, baseUrl: 'https://motogo24.cz/');
                    } else {
                      _controller.loadRequest(Uri.parse(widget.url!));
                    }
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Zkusit znovu'),
                ),
              ]),
            ))
          else
            WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: MotoGoColors.green)),
        ],
      ),
    );
  }
}
