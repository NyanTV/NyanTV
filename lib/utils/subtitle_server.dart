import 'dart:async';
import 'dart:io';

class SubtitleServer {
  HttpServer? _server;
  final Map<String, String> _cache = {};
  int _port = 0;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen((request) {
      final key = request.uri.path.replaceFirst('/', '');
      final content = _cache[key];
      if (content != null) {
        request.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'text/vtt; charset=utf-8')
          ..headers.set('Access-Control-Allow-Origin', '*')
          ..write(content)
          ..close();
      } else {
        request.response
          ..statusCode = 404
          ..close();
      }
    });
  }

  String serve(String vttContent) {
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    _cache[key] = vttContent;
    return 'http://127.0.0.1:$_port/$key';
  }

  void remove(String url) {
    final key = Uri.parse(url).path.replaceFirst('/', '');
    _cache.remove(key);
  }

  void dispose() {
    _cache.clear();
    _server?.close(force: true);
    _server = null;
  }
}
