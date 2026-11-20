import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/note.dart';
import '../models/space.dart';
import 'log.dart';

class MemosApiException implements Exception {
  final int statusCode;
  final String message;

  const MemosApiException(this.statusCode, this.message);

  @override
  String toString() => 'HTTP $statusCode: $message';
}

class MemosApi {
  static const _uploadChunkSize = 2 * 1024 * 1024;
  final http.Client? _client;
  final String base;
  final String token;

  MemosApi(String url, String token) : this._(url, token, null);

  MemosApi.withClient(String url, String token, http.Client client)
    : this._(url, token, client);

  MemosApi._(String url, this.token, this._client)
    : base = normalizeBaseUrl(url) {
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

  Map<String, String> get _h => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<void> _dns(String host) async {
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 8));
      await LogService.log(
        '    DNS $host -> ${addresses.map((entry) => entry.address).join(', ')}',
      );
    } catch (e) {
      await LogService.log('    DNS $host FEHLER: $e');
    }
  }

  Future<http.Response> _send(String method, Uri uri, {String? body}) async {
    await LogService.log('--> $method $uri');
    if (LogService.enabled) await _dns(uri.host);
    final sw = Stopwatch()..start();
    try {
      final client = _client;
      final response = await switch (method) {
        'GET' =>
          client == null
              ? http.get(uri, headers: _h)
              : client.get(uri, headers: _h),
        'POST' =>
          client == null
              ? http.post(uri, headers: _h, body: body)
              : client.post(uri, headers: _h, body: body),
        'PATCH' =>
          client == null
              ? http.patch(uri, headers: _h, body: body)
              : client.patch(uri, headers: _h, body: body),
        _ =>
          client == null
              ? http.delete(uri, headers: _h)
              : client.delete(uri, headers: _h),
      }.timeout(const Duration(seconds: 60));
      await LogService.log(
        '<-- ${response.statusCode} nach ${sw.elapsedMilliseconds} ms, '
        '${response.bodyBytes.length} Bytes',
      );
      return response;
    } catch (e) {
      await LogService.log(
        '<-- FEHLER nach ${sw.elapsedMilliseconds} ms '
        '(${e.runtimeType}): $e',
      );
      rethrow;
    }
  }

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MemosApiException(
        response.statusCode,
        utf8.decode(response.bodyBytes),
      );
    }
  }

  Future<Map<String, dynamic>> getInstanceProfile() async {
    final response = await _send('GET', _u('instance/profile'));
    _check(response);
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> ping() async {
    _check(await _send('GET', _u('memos', {'pageSize': '1'})));
  }

  Future<List<MemoSpace>> listSpaces() async {
    final result = <MemoSpace>[];
    String? pageToken;
    do {
      final response = await _send(
        'GET',
        _u('spaces', {
          'pageSize': '200',
          ...?(pageToken == null ? null : {'pageToken': pageToken}),
        }),
      );
      _check(response);
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      for (final value in json['spaces'] as List? ?? const []) {
        result.add(MemoSpace.fromServer(value as Map<String, dynamic>));
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return result;
  }

  Future<MemoSpace> createSpace(MemoSpace space) async {
    final response = await _send(
      'POST',
      _u('spaces'),
      body: jsonEncode(space.toRequestJson()),
    );
    _check(response);
    return MemoSpace.fromServer(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<MemoSpace> updateSpace(MemoSpace space) async {
    final response = await _send(
      'PATCH',
      _u('spaces/${space.id}', {'updateMask': 'title,description,icon'}),
      body: jsonEncode(space.toRequestJson()),
    );
    _check(response);
    return MemoSpace.fromServer(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> deleteSpace(MemoSpace space) async {
    _check(await _send('DELETE', _u('spaces/${space.id}')));
  }

  Future<List<Note>> list({String state = 'NORMAL'}) async {
    final result = <Note>[];
    String? pageToken;
    do {
      final response = await _send(
        'GET',
        _u('memos', {
          'pageSize': '200',
          'state': state,
          ...?(pageToken == null ? null : {'pageToken': pageToken}),
        }),
      );
      _check(response);
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      for (final memo in json['memos'] as List? ?? const []) {
        result.add(Note.fromServer(memo as Map<String, dynamic>));
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return result;
  }

  Future<String> create(String content) async {
    final response = await _send(
      'POST',
      _u('memos'),
      body: jsonEncode({'content': content, 'visibility': 'PRIVATE'}),
    );
    _check(response);
    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (json['name'] as String).split('/').last;
  }

  Future<void> updateMemo(String id, Map<String, dynamic> fields) async {
    if (fields.isEmpty) return;
    _check(
      await _send(
        'PATCH',
        _u('memos/$id', {'updateMask': fields.keys.join(',')}),
        body: jsonEncode(fields),
      ),
    );
  }

  Future<void> setMemoAttachments(
    String id,
    List<NoteAttachment> attachments,
  ) async {
    _check(
      await _send(
        'PATCH',
        _u('memos/$id/attachments'),
        body: jsonEncode({
          'attachments': attachments
              .map((attachment) => attachment.toJson())
              .toList(),
        }),
      ),
    );
  }

  Future<void> setMemoRelations(String id, List<MemoRelation> relations) async {
    _check(
      await _send(
        'PATCH',
        _u('memos/$id/relations'),
        body: jsonEncode({
          'name': 'memos/$id',
          'relations': relations
              .map((relation) => relation.toServerJson())
              .toList(),
        }),
      ),
    );
  }

  Future<NoteAttachment> uploadAttachment(PendingAttachment pending) async {
    final file = File(pending.path);
    if (!await file.exists()) {
      throw FileSystemException(
        'Anhang wurde lokal nicht gefunden',
        pending.path,
      );
    }
    final totalSize = await file.length();
    final initResponse = await _send(
      'POST',
      _u('attachments:upload'),
      body: jsonEncode({
        'spec': {
          'attachment': {'filename': pending.filename, 'type': pending.type},
          'totalSize': '$totalSize',
        },
        'writeOffset': '0',
      }),
    );
    _check(initResponse);
    final initJson =
        jsonDecode(utf8.decode(initResponse.bodyBytes)) as Map<String, dynamic>;
    final uploadId = initJson['uploadId'] as String?;
    final maxChunkSize = initJson['maxChunkSize'] as int? ?? 0;
    if (uploadId == null || uploadId.isEmpty || maxChunkSize <= 0) {
      throw const FormatException('Ungültige Antwort beim Anhang-Upload.');
    }

    final chunkSize = math.min(maxChunkSize, _uploadChunkSize);
    final input = await file.open();
    try {
      var offset = 0;
      while (true) {
        final bytes = await input.read(chunkSize);
        final nextOffset = offset + bytes.length;
        final finished = nextOffset >= totalSize;
        final response = await _send(
          'POST',
          _u('attachments:upload'),
          body: jsonEncode({
            'uploadId': uploadId,
            'writeOffset': '$offset',
            'data': base64Encode(bytes),
            'finishWrite': finished,
          }),
        );
        _check(response);
        final json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final committed = int.tryParse('${json['committedSize']}');
        if (committed != nextOffset) {
          throw const FormatException('Unerwarteter Upload-Offset.');
        }
        if (finished) {
          final attachment = json['attachment'] as Map<String, dynamic>?;
          if (attachment == null) {
            throw const FormatException(
              'Der Server hat den Upload nicht abgeschlossen.',
            );
          }
          return NoteAttachment.fromServer(attachment);
        }
        offset = nextOffset;
      }
    } finally {
      await input.close();
    }
  }

  Future<List<int>> downloadAttachment(String id) async {
    final uri = Uri.parse('$base/file/attachments/${Uri.encodeComponent(id)}');
    final response = await _send('GET', uri);
    _check(response);
    return response.bodyBytes;
  }

  Future<void> delete(String id) async {
    _check(await _send('DELETE', _u('memos/$id')));
  }
}
