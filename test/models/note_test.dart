import 'package:flutter_test/flutter_test.dart';
import 'package:notiz_app/models/note.dart';

void main() {
  test('parses, persists, and searches memo references', () {
    final note = Note.fromServer({
      'name': 'memos/one',
      'content': '# Alpha\nbody',
      'relations': [
        {
          'memo': {'name': 'memos/one'},
          'relatedMemo': {'name': 'memos/two', 'snippet': '# Beta'},
          'type': 'REFERENCE',
        },
      ],
    });

    expect(note.relatedMemoIds, ['two']);
    expect(note.relations.single.otherMemoSnippet('one'), '# Beta');
    final restored = Note.fromJson(note.toJson());
    expect(restored.relatedMemoIds, ['two']);
    expect(filterNotesByQuery([note, restored], '  body '), hasLength(2));
    expect(filterNotesByQuery([note, restored], ' ALPHA '), hasLength(2));
  });

  test('removing an attachment removes its embedded image references only', () {
    const content =
        'Bild: ![Foto](https://memo.example.com/file/attachments/file-id?size=large)\n'
        '![Anderes Bild](/file/attachments/another-id)';

    expect(
      removeAttachmentImageReferences(content, 'attachments/file-id'),
      'Bild: \n![Anderes Bild](/file/attachments/another-id)',
    );
  });
}
