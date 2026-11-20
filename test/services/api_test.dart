import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notiz_app/models/note.dart';
import 'package:notiz_app/services/api.dart';

void main() {
  test('sends attachment objects when setting memo attachments', () async {
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('', 200);
    });
    final api = MemosApi.withClient(
      'https://memos.example.com',
      'token',
      client,
    );

    await api.setMemoAttachments('memo-id', [
      const NoteAttachment(
        name: 'attachments/file-id',
        filename: 'photo.jpg',
        type: 'image/jpeg',
        size: 123,
      ),
    ]);

    expect(body, {
      'attachments': [
        {
          'name': 'attachments/file-id',
          'filename': 'photo.jpg',
          'type': 'image/jpeg',
          'size': 123,
        },
      ],
    });
    client.close();
  });

  test('replaces memo reference relations on the relation endpoint', () async {
    late http.Request sentRequest;
    late Map<String, dynamic> body;
    final client = MockClient((request) async {
      sentRequest = request;
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('', 200);
    });
    final api = MemosApi.withClient(
      'https://memos.example.com',
      'token',
      client,
    );

    await api.setMemoRelations('memo-id', [
      const MemoRelation(memoId: 'memo-id', relatedMemoId: 'related-id'),
    ]);

    expect(sentRequest.method, 'PATCH');
    expect(sentRequest.url.path, '/api/memos/memo-id/relations');
    expect(body, {
      'name': 'memos/memo-id',
      'relations': [
        {
          'memo': {'name': 'memos/memo-id'},
          'relatedMemo': {'name': 'memos/related-id'},
          'type': 'REFERENCE',
        },
      ],
    });
    client.close();
  });

  test('sends a null location with its update mask when clearing it', () async {
    late http.Request sentRequest;
    final client = MockClient((request) async {
      sentRequest = request;
      return http.Response('', 200);
    });
    final api = MemosApi.withClient(
      'https://memos.example.com',
      'token',
      client,
    );

    await api.updateMemo('memo-id', {'location': null});

    expect(sentRequest.method, 'PATCH');
    expect(sentRequest.url.queryParameters['updateMask'], 'location');
    expect(jsonDecode(sentRequest.body), {'location': null});
    client.close();
  });
}
