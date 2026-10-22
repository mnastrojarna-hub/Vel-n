// HTTP pro testy UI jízd: každý požadavek (dlaždice mapy, fotky) dostane
// 200 s malým PNG, takže se mapy vykreslí a do testu nedorazí chyba obrázku
// (výchozí testovací klient odpovídá 400). Kopie z test/v2 (iOS strom ji nemá).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

final List<int> _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAFUlEQVR4nGN88eE1AzbAhFV00EoAACn1AtMLqjUYAAAAAElFTkSuQmCC');

class RidesPngHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client();
}

class _Client implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _Request(method, url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request('GET', url);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) async =>
      _Request('GET', Uri(scheme: 'https', host: host, port: port, path: path));
  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final Map<String, List<String>> _m = {};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) => _m[name.toLowerCase()] = ['$value'];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_m[name.toLowerCase()] ??= []).add('$value');
  @override
  String? value(String name) => _m[name.toLowerCase()]?.first;
  @override
  List<String>? operator [](String name) => _m[name.toLowerCase()];
  @override
  void forEach(void Function(String name, List<String> values) action) => _m.forEach(action);
  @override
  ContentType? contentType;
  @override
  int contentLength = -1;
  @override
  bool chunkedTransferEncoding = false;
  @override
  bool persistentConnection = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  @override
  final String method;
  @override
  final Uri uri;
  _Request(this.method, this.uri);

  @override
  final HttpHeaders headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = false;
  @override
  bool bufferOutput = true;
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}
  @override
  void write(Object? object) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
  @override
  Future<HttpClientResponse> close() async => _Response();
  @override
  Future<HttpClientResponse> get done async => _Response();
  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  final _Headers _h = _Headers()..set('content-type', 'image/png');

  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => _png.length;
  @override
  HttpHeaders get headers => _h;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  List<Cookie> get cookies => const [];

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_png).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
