import 'package:flutter_test/flutter_test.dart';
import 'package:notiz_app/models/note.dart';
import 'package:notiz_app/models/saved_view.dart';

void main() {
  test(
    'loads legacy local notes and marks previously dirty content for sync',
    () {
      final note = Note.fromJson({
        'id': 'memo-1',
        'content': '# Einkauf\n#privat',
        'updated': '2026-01-01T10:00:00.000',
        'dirty': true,
        'deleted': false,
      });

      expect(note.state, NoteState.normal);
      expect(note.attachments, isEmpty);
      expect(note.tags, contains('privat'));
      expect(note.dirtyFields, contains('content'));
    },
  );

  test('parses server archive, placement, attachments, and location', () {
    final note = Note.fromServer({
      'name': 'memos/memo-1',
      'content': 'Notiz #arbeit',
      'updateTime': '2026-01-01T10:00:00Z',
      'state': 'ARCHIVED',
      'pinned': true,
      'space': 'spaces/projekte',
      'tags': ['arbeit'],
      'attachments': [
        {
          'name': 'attachments/datei-1',
          'filename': 'plan.pdf',
          'type': 'application/pdf',
          'size': '2048',
        },
      ],
      'location': {'placeholder': 'Büro', 'latitude': 48.1, 'longitude': 11.5},
    });

    expect(note.state, NoteState.archived);
    expect(note.pinned, isTrue);
    expect(note.space, 'spaces/projekte');
    expect(note.attachments.single.size, 2048);
    expect(note.location?.placeholder, 'Büro');
  });

  test('saved views combine filters and include pending attachments', () {
    final note = Note(
      id: 'memo-1',
      content: 'Termin #arbeit',
      updated: DateTime(2026),
      pinned: true,
      tags: ['arbeit'],
      pendingAttachments: [
        PendingAttachment(
          path: 'pending.pdf',
          filename: 'plan.pdf',
          type: 'application/pdf',
          size: 12,
        ),
      ],
    );
    const view = SavedView(
      id: 'view-1',
      name: 'Arbeit',
      textContains: 'termin',
      tag: 'arbeit',
      pinned: true,
      hasAttachments: true,
      hasLocation: false,
    );

    expect(view.matches(note), isTrue);
    expect(
      view.matches(
        Note(
          id: 'memo-2',
          content: 'Termin #arbeit',
          updated: DateTime(2026),
          pinned: false,
          tags: ['arbeit'],
        ),
      ),
      isFalse,
    );
  });
}
