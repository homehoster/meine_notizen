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
}
