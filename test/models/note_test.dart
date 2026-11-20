import 'package:flutter_test/flutter_test.dart';
import 'package:notiz_app/models/note.dart';

void main() {
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
