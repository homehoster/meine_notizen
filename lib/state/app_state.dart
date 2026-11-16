import 'dart:async';
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
  /// Ruhezeit nach der letzten Änderung, bevor eine Notiz zum Server gesendet wird.
  /// (Lokal wird bereits nach 600 ms gespeichert, siehe NoteScreen.)
  static const _pushDelay = Duration(seconds: 4);

  final _store = LocalStore();
  final _secure = const FlutterSecureStorage();
  final Map<Note, Timer> _pushTimers = {};

  String baseUrl = '';
  String token = '';
  ThemeMode themeMode = ThemeMode.system;
  bool blockMarkdownImages = true;
  List<Note> notes = [];
  Set<String> widgetIds = {};
  bool syncing = false;
  String? error;

  /// Einmaliger Hinweis (z. B. beschädigte lokale Datei wiederhergestellt).
  String? notice;
  bool logEnabled = false;

  /// Vom geöffneten Editor gesetzt: sichert ungespeicherten Text sofort.
  Future<void> Function()? onBeforeBackground;

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
    blockMarkdownImages = p.getBool('blockMarkdownImages') ?? true;
    logEnabled = p.getBool('log') ?? false;
    LogService.setEnabled(logEnabled);
    token = await _secure.read(key: 'token') ?? '';
    final d = await _store.load();
    notes = d.notes;
    widgetIds = d.widgetIds;
    if (d.warning != null) {
      notice = d.warning;
      LogService.log(d.warning!);
    }
    notifyListeners();
    unawaited(_updateWidget()); // Widget beim Start der App aktualisieren
    if (configured) sync();
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
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

  /// Entfernt Server-URL und Token von diesem Gerät. Lokale Notizen bleiben erhalten.
  Future<void> clearServerSettings() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = '';
    token = '';
    error = null;
    await p.remove('url');
    await _secure.delete(key: 'token');
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme', m.index);
    notifyListeners();
  }

  Future<void> setBlockMarkdownImages(bool value) async {
    blockMarkdownImages = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool('blockMarkdownImages', value);
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
      _pushTimers.remove(n)?.cancel();
      notes.remove(n);
      await _persist();
      notifyListeners();
    }
  }

  /// Speichert lokal (sofort) und plant den Push zum Server nach [_pushDelay] Ruhe.
  Future<void> saveContent(Note n, String content) async {
    if (n.deleted || n.content == content) return;
    n.content = content;
    n.updated = DateTime.now();
    n.dirty = true;
    await _persist();
    if (!notes.contains(n)) return;
    notifyListeners();
    _schedulePush(n);
  }

  /// Beim Verlassen der Notiz: lokal sichern, leere neue Notiz verwerfen, sonst sofort pushen.
  Future<void> finishEditing(Note n, String content) async {
    await saveContent(n, content);
    await discardIfEmpty(n);
    if (notes.contains(n)) await pushNow(n);
  }

  Future<void> deleteNote(Note n) async {
    _pushTimers.remove(n)?.cancel();
    n.deleted = true;
    n.dirty = true;
    widgetIds.remove(n.id);
    if (n.isLocal) notes.remove(n);
    await _persist();
    notifyListeners();
    if (!n.isLocal) unawaited(_push(n));
  }

  Future<void> toggleWidget(Note n) async {
    if (!widgetIds.remove(n.id)) widgetIds.add(n.id);
    await _persist();
    notifyListeners();
  }

  void _schedulePush(Note n) {
    if (!configured) return;
    _pushTimers[n]?.cancel();
    _pushTimers[n] = Timer(_pushDelay, () {
      _pushTimers.remove(n);
      unawaited(_push(n));
    });
  }

  Future<void> pushNow(Note n) async {
    _pushTimers.remove(n)?.cancel();
    if (n.dirty || n.deleted) await _push(n);
  }

  Future<void> _flushPushes() async {
    for (final t in _pushTimers.values) {
      t.cancel();
    }
    _pushTimers.clear();
    for (final n in List.of(notes)) {
      if (n.dirty || n.deleted) await _push(n);
    }
  }

  Future<void> _push(Note n) async {
    if (!configured || n.busy) return;
    // Leere, noch nie gesendete Notizen nicht als leere Memos anlegen.
    if (n.isLocal && !n.deleted && n.content.trim().isEmpty) return;
    n.busy = true;
    var changedMeanwhile = false;
    try {
      if (n.deleted) {
        if (!n.isLocal) await _api.delete(n.id);
        notes.remove(n);
      } else if (n.isLocal) {
        final sent = n.content;
        final oldId = n.id;
        n.id = await _api.create(sent);
        if (widgetIds.remove(oldId)) widgetIds.add(n.id);
        if (n.content == sent) {
          n.dirty = false;
        } else {
          changedMeanwhile = true;
        }
      } else {
        final sent = n.content;
        await _api.update(n.id, sent);
        if (n.content == sent) {
          n.dirty = false;
        } else {
          changedMeanwhile = true;
        }
      }
      error = null;
      await _persist();
    } catch (e) {
      error = '$e';
      LogService.log('Push fehlgeschlagen (${n.id}): $e');
    } finally {
      n.busy = false;
      notifyListeners();
    }
    // Während des Sendens weitergetippt: neuen Stand nach der Ruhezeit nachsenden.
    if (changedMeanwhile && notes.contains(n)) _schedulePush(n);
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
        if (l == null) {
          merged.add(r);
          continue;
        }
        // Bestehendes Objekt behalten (ein geöffneter Editor hält darauf eine Referenz).
        if (!l.dirty && !l.deleted) {
          l.content = r.content;
          l.updated = r.updated;
          l.pinned = r.pinned;
        }
        merged.add(l);
      }
      merged.addAll(notes.where((n) => n.isLocal));
      notes = merged;
      await _persist();
      LogService.log('Sync fertig: ${notes.length} Notizen');
    } catch (e) {
      error = '$e';
      LogService.log('Sync fehlgeschlagen: $e');
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// App kommt in den Vordergrund.
  Future<void> onForeground() => _updateWidget();

  /// App geht in den Hintergrund bzw. wird geschlossen:
  /// Editor sichern, Widget aktualisieren, offene Änderungen zum Server senden.
  Future<void> onBackground() async {
    try {
      await onBeforeBackground?.call();
    } catch (e) {
      LogService.log('Editor sichern fehlgeschlagen: $e');
    }
    await _updateWidget();
    final hadLocal = notes.any((n) => n.isLocal);
    await _flushPushes();
    // Neu angelegte Notizen bekommen beim Senden eine Server-ID: Widget-Links aktualisieren.
    if (hadLocal) await _updateWidget();
    await LogService.flush();
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
