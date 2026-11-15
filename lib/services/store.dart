import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';

class LocalData {
  final List<Note> notes;
  final Set<String> widgetIds;
  LocalData(this.notes, this.widgetIds);
}

class LocalStore {
  Future<File> _file() async =>
      File('${(await getApplicationDocumentsDirectory()).path}/notes.json');

  Future<LocalData> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return LocalData([], {});
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return LocalData(
        [for (final n in (j['notes'] as List)) Note.fromJson(n as Map<String, dynamic>)],
        {...List<String>.from(j['widgetIds'] ?? [])},
      );
    } catch (_) {
      return LocalData([], {});
    }
  }

  Future<void> save(List<Note> notes, Set<String> widgetIds) async {
    final f = await _file();
    await f.writeAsString(jsonEncode({
      'notes': notes.map((n) => n.toJson()).toList(),
      'widgetIds': widgetIds.toList(),
    }));
  }
}
