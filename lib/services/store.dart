import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import 'log.dart';

class LocalData {
  final List<Note> notes;
  final Set<String> widgetIds;

  /// Hinweis für den Nutzer, falls beim Laden etwas schiefging
  /// (beschädigte Datei, Wiederherstellung aus der Sicherung).
  final String? warning;

  LocalData(this.notes, this.widgetIds, {this.warning});
}

/// Speichert Notizen in `notes.json`.
///
/// Schreiben: erst in `notes.json.tmp`, dann wird die bisherige Datei zu
/// `notes.json.bak` und die neue Datei per Umbenennen (atomar) eingesetzt.
/// Laden: ist `notes.json` defekt, wird sie als `notes.json.corrupt-<zeit>`
/// aufbewahrt (nicht gelöscht) und die Sicherung verwendet.
class LocalStore {
  Future<void> _queue = Future<void>.value();

  Future<File> _named(String name) async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$name');

  Future<LocalData> _read(File f) async {
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return LocalData(
      [for (final n in (j['notes'] as List)) Note.fromJson(n as Map<String, dynamic>)],
      {...List<String>.from(j['widgetIds'] ?? [])},
    );
  }

  Future<File> _quarantine(File f) =>
      f.rename('${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');

  Future<LocalData> load() async {
    final main = await _named('notes.json');
    final tmp = await _named('notes.json.tmp');
    final bak = await _named('notes.json.bak');
    String? warning;
    var restoreFrom = <File>[];

    if (await main.exists()) {
      try {
        return await _read(main);
      } catch (e) {
        final q = await _quarantine(main);
        final name = q.path.split(RegExp(r'[\\/]')).last;
        LogService.log('notes.json beschädigt ($e) -> gesichert als $name');
        warning = 'Die lokale Notizdatei war beschädigt und wurde als „$name“ gesichert.';
        restoreFrom = [bak];
      }
    } else {
      // Abbruch zwischen den beiden Umbenennungen: neueste vollständige Datei zuerst.
      restoreFrom = [tmp, bak];
    }

    for (final f in restoreFrom) {
      if (!await f.exists()) continue;
      try {
        final d = await _read(f);
        return LocalData(
          d.notes,
          d.widgetIds,
          warning: warning == null
              ? 'Notizen wurden aus der Sicherungskopie wiederhergestellt.'
              : '$warning Der Stand wurde aus der Sicherungskopie wiederhergestellt.',
        );
      } catch (e) {
        LogService.log('Wiederherstellung aus ${f.path} fehlgeschlagen: $e');
      }
    }
    return LocalData([], {}, warning: warning);
  }

  /// Schreibvorgänge laufen nacheinander; Fehler gehen an den Aufrufer weiter.
  Future<void> save(List<Note> notes, Set<String> widgetIds) {
    // Daten sofort einfrieren, spätere Änderungen landen nicht im laufenden Schreibvorgang.
    final data = jsonEncode({
      'notes': notes.map((n) => n.toJson()).toList(),
      'widgetIds': widgetIds.toList(),
    });
    final result = _queue.then((_) => _write(data));
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<void> _write(String data) async {
    final main = await _named('notes.json');
    final tmp = await _named('notes.json.tmp');
    final bak = await _named('notes.json.bak');
    await tmp.writeAsString(data, flush: true);
    if (await main.exists()) await main.rename(bak.path);
    await tmp.rename(main.path);
  }
}
