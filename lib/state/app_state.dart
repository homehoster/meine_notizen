import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../models/task_doc.dart';
import '../services/api.dart';
import '../services/log.dart';
import '../services/store.dart';

class AppState extends ChangeNotifier {
  final _store = LocalStore();
  final _secure = const FlutterSecureStorage();

  String baseUrl = '';
  String token = '';
  ThemeMode themeMode = ThemeMode.system;
  List<Note> notes = [];
  Set<String> widgetIds = {};
  bool syncing = false;
  String? error;
  bool logEnabled = false;

  bool get configured => baseUrl.isNotEmpty && token.isNotEmpty;
  MemosApi get _api => MemosApi(baseUrl, token);

  List<Note> get visible {
    final l = notes.where((n) => !n.deleted).toList();
    l.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updated.compareTo(a.updated);
    });
    return l;
  }

  Note? byId(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('url') ?? '';
    themeMode = ThemeMode.values[p.getInt('theme') ?? 0];
    logEnabled = p.getBool('log') ?? true;
    LogService.setEnabled(logEnabled);
    token = await _secure.read(key: 'token') ?? '';
    final d = await _store.load();
    notes = d.notes;
    widgetIds = d.widgetIds;
    notifyListeners();
    _updateWidget();
    if (configured) sync();
  }

  Future<void> testConnection(String url, String tok) =>
      MemosApi(url, tok).ping();

  Future<void> saveSettings(String url, String tok) async {
    final p = await SharedPreferences.getInstance();
    baseUrl = url.trim();
    token = tok.trim();
    await p.setString('url', baseUrl);
    await _secure.write(key: 'token', value: token);
    notifyListeners();
    sync();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme', m.index);
    notifyListeners();
  }

  Future<void> setLogEnabled(bool v) async {
    logEnabled = v;
    LogService.setEnabled(v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('log', v);
    LogService.log('Logging ${v ? 'aktiviert' : 'deaktiviert'}');
    notifyListeners();
  }

  Future<void> _persist() => _store.save(notes, widgetIds);

  Future<Note> create() async {
    final n = Note(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      content: '',
      updated: DateTime.now(),
      dirty: true,
    );
    notes.add(n);
    await _persist();
    notifyListeners();
    return n;
  }

  Future<void> discardIfEmpty(Note n) async {
    if (n.isLocal && n.content.trim().isEmpty) {
      notes.remove(n);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> saveContent(Note n, String content) async {
    if (n.content == content) return;
    n.content = content;
    n.updated = DateTime.now();
    n.dirty = true;
    await _persist();
    if (!notes.contains(n)) return;
    notifyListeners();
    _updateWidget();
    _push(n);
  }

  Future<void> deleteNote(Note n) async {
    n.deleted = true;
    n.dirty = true;
    widgetIds.remove(n.id);
    if (n.isLocal) notes.remove(n);
    await _persist();
    notifyListeners();
    _updateWidget();
    if (!n.isLocal) _push(n);
  }

  Future<void> toggleWidget(Note n) async {
    if (!widgetIds.remove(n.id)) widgetIds.add(n.id);
    await _persist();
    notifyListeners();
    _updateWidget();
  }

  Future<void> _push(Note n) async {
    if (!configured || n.busy) return;
    n.busy = true;
    try {
      if (n.deleted) {
        if (!n.isLocal) await _api.delete(n.id);
        notes.remove(n);
      } else if (n.isLocal) {
        final sent = n.content;
        final oldId = n.id;
        n.id = await _api.create(sent);
        if (widgetIds.remove(oldId)) widgetIds.add(n.id);
        if (n.content == sent) n.dirty = false;
      } else {
        final sent = n.content;
        await _api.update(n.id, sent);
        if (n.content == sent) n.dirty = false;
      }
      error = null;
      await _persist();
      await _updateWidget();
    } catch (e) {
      error = '$e';
      LogService.log('Push fehlgeschlagen (${n.id}): $e');
    } finally {
      n.busy = false;
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (!configured || syncing) return;
    syncing = true;
    error = null;
    notifyListeners();
    LogService.log('Sync gestartet ($baseUrl)');
    try {
      for (final n in List.of(notes)) {
        if (n.dirty || n.deleted) await _push(n);
      }
      final remote = await _api.list();
      final local = {for (final n in notes) n.id: n};
      final merged = <Note>[];
      for (final r in remote) {
        final l = local[r.id];
        merged.add(l != null && (l.dirty || l.deleted) ? l : r);
      }
      merged.addAll(notes.where((n) => n.isLocal));
      notes = merged;
      await _persist();
      _updateWidget();
      LogService.log('Sync fertig: ${notes.length} Notizen');
    } catch (e) {
      error = '$e';
      LogService.log('Sync fehlgeschlagen: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> _updateWidget() async {
    try {
      final ordered = visible;
      final selected = ordered.where((n) => widgetIds.contains(n.id)).toList();
      final sel = selected.isEmpty ? ordered : selected;
      final items = [
        for (final note in sel)
          {
            'id': note.id,
            'title': note.title,
            'preview': widgetPreview(note.content),
          },
      ];
      await HomeWidget.saveWidgetData<String>(
        'widget_notes',
        jsonEncode(items),
      );
      await HomeWidget.updateWidget(
        androidName: 'NoteWidgetProvider',
        iOSName: 'NoteWidget',
      );
    } catch (e) {
      LogService.log('Widget konnte nicht aktualisiert werden: $e');
    }
  }
}
