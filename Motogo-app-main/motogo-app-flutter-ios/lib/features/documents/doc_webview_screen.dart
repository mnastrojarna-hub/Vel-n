import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/friendly_error.dart';
import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/state_views.dart';

/// In-app WebView screen for displaying invoices, contracts, and other
/// HTML documents. Supports loading from URL or raw HTML string.
class DocWebViewScreen extends StatefulWidget {
  /// Load from remote URL (signed Supabase storage URL).
  final String? url;

  /// Load from raw HTML string (built from DB data).
  final String? htmlContent;

  final String title;

  /// Nová podepsaná URL pro „Zkusit znovu" — stará platí jen 10 minut, takže
  /// opakování po delší době by jinak selhalo znovu.
  final Future<String?> Function()? refreshUrl;

  const DocWebViewScreen(
      {super.key, this.url, this.htmlContent, required this.title, this.refreshUrl})
      : assert(url != null || htmlContent != null, 'Provide url or htmlContent');

  @override
  State<DocWebViewScreen> createState() => _DocWebViewScreenState();
}

class _DocWebViewScreenState extends State<DocWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  Object? _error;
  late String? _url = widget.url;

  /// Chyba WebView → výjimka, ze které `FriendlyError` řekne důvod (dřív se
  /// ukazoval syrový text typu „net::ERR_INTERNET_DISCONNECTED").
  static Object _asError(WebResourceError e) {
    switch (e.errorType) {
      case WebResourceErrorType.hostLookup:
      case WebResourceErrorType.connect:
        return const SocketException('webview');
      case WebResourceErrorType.timeout:
        return TimeoutException('webview');
      default:
        final d = e.description.toLowerCase();
        if (d.contains('offline') || d.contains('internet') || d.contains('network')) {
          return const SocketException('webview');
        }
        return Exception('webview ${e.errorCode} ${e.description}');
    }
  }

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
          // Chyba obrázku / písma uvnitř dokumentu nesmí schovat celý dokument.
          if (error.isForMainFrame == false) return;
          FriendlyError.log('doc_webview', '${error.errorType} ${error.description}');
          if (mounted) setState(() { _isLoading = false; _error = _asError(error); });
        },
      ));
    _loadContent();
  }

  void _loadContent() {
    if (widget.htmlContent != null) {
      // baseUrl is required on Android so the WebView honors the document's
      // `<meta viewport width=device-width>` — without it the page is laid out
      // at the default ~980px viewport and the centered invoice card leaves
      // empty (grey) space on the sides instead of filling the screen width.
      _controller.loadHtmlString(widget.htmlContent!, baseUrl: 'https://motogo24.cz/');
    } else {
      _controller.loadRequest(Uri.parse(_url!));
    }
  }

  Future<void> _retry() async {
    setState(() { _error = null; _isLoading = true; });
    final refresh = widget.refreshUrl;
    if (refresh != null && widget.htmlContent == null) {
      try {
        final fresh = await refresh();
        if (fresh != null) _url = fresh;
      } catch (e) {
        if (mounted) setState(() { _isLoading = false; _error = e; });
        return;
      }
    }
    if (mounted) _loadContent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: MgBackArrow(onTap: () => Navigator.of(context).maybePop()),
        ),
        title: Text(widget.title, style: const TextStyle(fontSize: 15)),
        backgroundColor: MotoGoColors.dark,
      ),
      body: Stack(
        children: [
          if (_error != null)
            MgErrorView(
              error: _error,
              what: t(context).tr('eoDocLoadFail'),
              onRetry: _retry,
              onBack: () => Navigator.of(context).maybePop(),
            )
          else
            WebViewWidget(controller: _controller),
          if (_isLoading && _error == null)
            MgLoadingView(onRetry: _retry, onBack: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }
}
