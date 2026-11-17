import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notiz_app/models/note.dart';
import 'package:notiz_app/services/api.dart';
import 'package:path/path.dart' as p;

void main() {
  test('space placement updates space and visibility in one request', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response('', 204);
    });
    addTearDown(client.close);
    final api = MemosApi.withClient('https://memos.example', 'token', client);

    await api.updateMemo('memo-1', {
      'space': 'spaces/work',
      'visibility': 'SPACE',
    });

    expect(sent.method, 'PATCH');
    expect(sent.url.path, '/api/memos/memo-1');
    expect(sent.url.queryParameters['updateMask'], 'space,visibility');
    expect(jsonDecode(sent.body), {
      'space': 'spaces/work',
      'visibility': 'SPACE',
    });
  });

  test('uploads an attachment as bounded base64 chunks', () async {
    final directory = await Directory.systemTemp.createTemp('notiz_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'datei.txt'));
    await file.writeAsBytes([97, 98, 99, 100, 101]);
    final requests = <http.Request>[];
    final responses = [
      {'uploadId': 'upload-1', 'committedSize': '0', 'maxChunkSize': 3},
      {'uploadId': 'upload-1', 'committedSize': '3', 'maxChunkSize': 3},
      {
        'uploadId': 'upload-1',
        'committedSize': '5',
        'maxChunkSize': 3,
        'attachment': {
          'name': 'attachments/file-1',
          'filename': 'datei.txt',
          'type': 'text/plain',
          'size': '5',
        },
      },
    ];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode(responses.removeAt(0)), 200);
    });
    addTearDown(client.close);
    final api = MemosApi.withClient('https://memos.example', 'token', client);

    final attachment = await api.uploadAttachment(
      PendingAttachment(
        path: file.path,
        filename: 'datei.txt',
        type: 'text/plain',
        size: 5,
      ),
    );

    expect(attachment.name, 'attachments/file-1');
    expect(requests, hasLength(3));
    expect(requests[0].url.path, '/api/attachments:upload');
    final firstChunk = jsonDecode(requests[1].body) as Map<String, dynamic>;
    final lastChunk = jsonDecode(requests[2].body) as Map<String, dynamic>;
    expect(firstChunk['data'], 'YWJj');
    expect(firstChunk['writeOffset'], '0');
    expect(firstChunk['finishWrite'], isFalse);
    expect(lastChunk['data'], 'ZGU=');
    expect(lastChunk['writeOffset'], '3');
    expect(lastChunk['finishWrite'], isTrue);
  });
}
