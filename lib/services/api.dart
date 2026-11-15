import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/note.dart';
import 'log.dart';

class MemosApi {
  final String base;
  final String token;

  MemosApi(String url, this.token) : base = normalizeBaseUrl(url) {
    LogService.log('MemosApi: Eingabe-URL="$url" -> verwendet="$base"');
  }

  static String normalizeBaseUrl(String url) {
    var u = url.replaceAll(RegExp(r'\s+'), '');
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    u = u.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(u);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Ungültige Server-URL.');
    }
    return u;
  }

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$base/api/$path').replace(queryParameters: q);

  Map<String, String> get _h =>
      {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};

  Future<void> _dns(String host) async {
    try {
      final a = await InternetAddress.lookup(host).timeout(const Duration(seconds: 8));
      await LogService.log('    DNS $host -> ${a.map((e) => e.address).join(', ')}');
    } catch (e) {
      await LogService.log('    DNS $host FEHLER: $e');
    }
  }

  Future<http.Response> _send(String method, Uri uri, {String? body}) async {
    await LogService.log('--> $method $uri');
    await _dns(uri.host);
    final sw = Stopwatch()..start();
    try {
      final r = await switch (method) {
        'GET' => http.get(uri, headers: _h),
        'POST' => http.post(uri, headers: _h, body: body),
        'PATCH' => http.patch(uri, headers: _h, body: body),
        _ => http.delete(uri, headers: _h),
      }
          .timeout(const Duration(seconds: 30));
      await LogService.log(
          '<-- ${r.statusCode} nach ${sw.elapsedMilliseconds} ms, ${r.bodyBytes.length} Bytes');
      return r;
    } catch (e) {
      await LogService.log(
          '<-- FEHLER nach ${sw.elapsedMilliseconds} ms (${e.runtimeType}): $e');
      rethrow;
    }
  }

  void _check(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('HTTP ${r.statusCode}: ${utf8.decode(r.bodyBytes)}');
    }
  }

  Future<void> ping() async {
    _check(await _send('GET', _u('memos', {'pageSize': '1'})));
  }

  Future<List<Note>> list() async {
    final out = <Note>[];
    String? tok;
    do {
      final r = await _send(
        'GET',
        _u('memos', {
          'pageSize': '200',
          ...?(tok == null ? null : {'pageToken': tok}),
        }),
      );
      _check(r);
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      for (final m in (j['memos'] as List? ?? [])) {
        out.add(Note.fromServer(m as Map<String, dynamic>));
      }
      tok = j['nextPageToken'] as String?;
    } while (tok != null && tok.isNotEmpty);
    return out;
  }

  /// Gibt die Server-ID zurück.
  Future<String> create(String content) async {
    final r = await _send('POST', _u('memos'),
        body: jsonEncode({'content': content, 'visibility': 'PRIVATE'}));
    _check(r);
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    return (j['name'] as String).split('/').last;
  }

  Future<void> update(String id, String content) async {
    _check(await _send('PATCH', _u('memos/$id', {'updateMask': 'content'}),
        body: jsonEncode({'content': content})));
  }

  Future<void> delete(String id) async {
    _check(await _send('DELETE', _u('memos/$id')));
  }
}
