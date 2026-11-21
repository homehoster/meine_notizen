// Wendet die Review-Fixes auf das Projekt an.
// Aufruf im Projektstamm:  dart notiz_patch/apply_fixes.dart
//
// Sicherheit: Alle Änderungen werden zuerst im Speicher geprüft. Passt auch nur
// ein Textanker nicht, wird NICHTS geschrieben und die Liste der Probleme
// ausgegeben. Zeilenenden (LF/CRLF) bleiben erhalten.
import 'dart:io';

final _files = <String, String>{};
final _eol = <String, String>{};
final _problems = <String>[];
final _warnings = <String>[];

String _load(String path) {
  return _files.putIfAbsent(path, () {
    final f = File(path);
    if (!f.existsSync()) {
      _problems.add('Datei fehlt: $path');
      return '';
    }
    final raw = f.readAsStringSync();
    _eol[path] = raw.contains('\r\n') ? '\r\n' : '\n';
    return raw.replaceAll('\r\n', '\n');
  });
}

int _count(String text, String needle) {
  var n = 0;
  var i = text.indexOf(needle);
  while (i >= 0) {
    n++;
    i = text.indexOf(needle, i + needle.length);
  }
  return n;
}

void _fail(String path, String what, String msg, bool optional) {
  final line = '$path: $msg\n    Anker: ${what.split('\n').first.trim()}';
  (optional ? _warnings : _problems).add(line);
}

/// Ersetzt genau eine Stelle (oder alle mit [all]).
void edit(
  String path,
  String oldText,
  String newText, {
  bool all = false,
  bool optional = false,
}) {
  final text = _load(path);
  final count = _count(text, oldText);
  if (count == 0) return _fail(path, oldText, 'Anker nicht gefunden', optional);
  if (count > 1 && !all) {
    return _fail(path, oldText, 'Anker mehrfach vorhanden ($count)', optional);
  }
  if (all) {
    _files[path] = text.split(oldText).join(newText);
  } else {
    final i = text.indexOf(oldText);
    _files[path] =
        text.substring(0, i) + newText + text.substring(i + oldText.length);
  }
}

/// Ersetzt den Bereich von [start] bis einschließlich [end].
void editSpan(String path, String start, String end, String newText) {
  final text = _load(path);
  if (_count(text, start) != 1) {
    return _fail(path, start, 'Startanker nicht eindeutig', false);
  }
  final i = text.indexOf(start);
  final j = text.indexOf(end, i);
  if (j < 0) return _fail(path, end, 'Endanker nicht gefunden', false);
  _files[path] =
      text.substring(0, i) + newText + text.substring(j + end.length);
}

void main() {
  if (!File('pubspec.yaml').existsSync() || !Directory('lib').existsSync()) {
    stderr.writeln('Bitte im Projektstamm ausführen (dort liegt pubspec.yaml).');
    exit(1);
  }

  const api = 'lib/services/api.dart';
  const state = 'lib/state/app_state.dart';
  const home = 'lib/screens/home_screen.dart';
  const note = 'lib/screens/note_screen.dart';
  const mainDart = 'lib/main.dart';
  const kotlinService =
      'android/app/src/main/kotlin/com/github/homehoster/meine_notizen/NoteWidgetService.kt';
  const plist = 'ios/Runner/Info.plist';

  // ───────────────────────── api.dart (Punkte 3, 4, 14) ─────────────────────
  edit(
    api,
    r'''  static const _uploadChunkSize = 2 * 1024 * 1024;''',
    r'''  static const _uploadChunkSize = 2 * 1024 * 1024;

  /// Gemeinsamer Client für alle Anfragen (Keep-Alive, eine TLS-Verbindung).
  static final http.Client _shared = http.Client();''',
  );

  edit(
    api,
    r'''  @override
  String toString() => 'HTTP $statusCode: $message';''',
    r'''  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => isUnauthorized
      ? 'Anmeldung abgelehnt (HTTP 401): Token ungültig oder abgelaufen. '
            'Bitte in den Einstellungen ein neues Token eintragen.'
      : 'HTTP $statusCode: $message';''',
  );

  editSpan(
    api,
    r'''      final client = _client;''',
    r'''}.timeout(const Duration(seconds: 60));''',
    r'''      final client = _client ?? _shared;
      final response = await switch (method) {
        'GET' => client.get(uri, headers: _h),
        'POST' => client.post(uri, headers: _h, body: body),
        'PATCH' => client.patch(uri, headers: _h, body: body),
        _ => client.delete(uri, headers: _h),
      }.timeout(const Duration(seconds: 60));''',
  );

  edit(
    api,
    r'''Future<List<Note>> list({String state = 'NORMAL'}) async {''',
    r'''Future<List<Note>> list({
    String state = 'NORMAL',
    DateTime? updatedSince,
  }) async {''',
  );

  edit(
    api,
    r'''          'state': state,''',
    r'''          'state': state,
          if (updatedSince != null)
            'filter':
                'updated_ts >= timestamp("${updatedSince.toUtc().toIso8601String().substring(0, 19)}Z")',''',
  );

  // ───────────────────── app_state.dart (1, 2, 3, 4, 8, 10, 13, 14, 15) ─────
  edit(
    state,
    r'''import 'package:home_widget/home_widget.dart';''',
    r'''import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' show ClientException;''',
  );
  edit(
    state,
    r'''import '../services/api.dart';''',
    r'''import '../services/api.dart';
import '../services/attachment_cache.dart';''',
  );
  edit(
    state,
    r'''  static const _maxAttachmentBytes = 100 * 1024 * 1024;''',
    r'''  static const _maxAttachmentBytes = 100 * 1024 * 1024;
  static const _maxWidgetNotes = 30;
  static const _fullSyncInterval = Duration(hours: 6);''',
  );
  edit(
    state,
    r'''  final Map<Note, Timer> _pushTimers = {};''',
    r'''  final Map<Note, Timer> _pushTimers = {};
  final Map<Note, int> _pushFailures = {};
  late final AttachmentCache attachmentCache = AttachmentCache(fetchAttachment);
  bool _networkFailed = false;
  DateTime? _lastSyncStart;
  DateTime? _lastFullSync;
  int _revision = 0;
  int _visibleRevision = -1;
  List<Note> _visibleCache = const [];
  int _selectedRevision = -1;
  List<Note> _selectedCache = const [];''',
  );
  edit(
    state,
    r'''  bool syncing = false;
  String? error;''',
    r'''  bool syncing = false;
  bool authFailed = false;
  String? error;''',
  );

  // Punkt 3: MemosApi nur bei geänderten Einstellungen neu bauen.
  edit(
    state,
    r'''  MemosApi get _api => MemosApi(baseUrl, token);''',
    r'''  MemosApi? _apiCache;
  String _apiKey = '';
  MemosApi get _api {
    final key = '$baseUrl\n$token';
    if (_apiCache == null || _apiKey != key) {
      _apiCache = MemosApi(baseUrl, token);
      _apiKey = key;
    }
    return _apiCache!;
  }

  @override
  void notifyListeners() {
    _revision++; // macht die gecachten Sortierungen ungültig
    super.notifyListeners();
  }''',
  );

  // Punkt 13: Sortierung nur neu berechnen, wenn sich etwas geändert hat.
  edit(
    state,
    r'''  List<Note> get visible => _sorted(
    notes.where((note) => !note.deleted && note.state == NoteState.normal),
  );''',
    r'''  List<Note> get visible {
    if (_visibleRevision != _revision) {
      _visibleCache = _sorted(
        notes.where(
          (note) => !note.deleted && note.state == NoteState.normal,
        ),
      );
      _visibleRevision = _revision;
    }
    return _visibleCache;
  }''',
  );
  edit(
    state,
    r'''  List<Note> get selectedNotes {
    final target = navigation;''',
    r'''  List<Note> get selectedNotes {
    if (_selectedRevision != _revision) {
      _selectedCache = _computeSelected();
      _selectedRevision = _revision;
    }
    return _selectedCache;
  }

  List<Note> _computeSelected() {
    final target = navigation;''',
  );

  edit(
    state,
    r'''    token = tok.trim();
    spacesSupported = null;''',
    r'''    token = tok.trim();
    authFailed = false;
    _lastFullSync = null;
    _lastSyncStart = null;
    spacesSupported = null;''',
  );
  edit(
    state,
    r'''    error = null;
    spacesSupported = null;''',
    r'''    error = null;
    authFailed = false;
    _lastFullSync = null;
    _lastSyncStart = null;
    unawaited(attachmentCache.clear());
    spacesSupported = null;''',
  );

  // Punkt 10: Widget begrenzen.
  edit(
    state,
    r'''      final values = selected.isEmpty ? ordered : selected;''',
    r'''      final values = (selected.isEmpty ? ordered : selected)
          .take(_maxWidgetNotes)
          .toList();''',
  );

  // Punkt 8: Widget-Thumbnail über den Cache laden.
  edit(
    state,
    r'''          ? Uint8List.fromList(await fetchAttachment(serverImage.name))''',
    r'''          ? await attachmentBytes(serverImage.name)''',
  );

  // Punkt 15: Backoff.
  edit(
    state,
    r'''  void _schedulePush(Note note) {''',
    r'''  /// Wartezeit bis zum nächsten Versand: normal 4 s, nach Netzwerkfehlern
  /// verdoppelt sie sich (8, 16, 32 … s) bis höchstens 5 Minuten.
  Duration _pushDelayFor(Note note) {
    final failures = _pushFailures[note] ?? 0;
    if (failures == 0) return _pushDelay;
    final exponent = failures > 6 ? 6 : failures;
    final seconds = 4 * (1 << exponent);
    return Duration(seconds: seconds > 300 ? 300 : seconds);
  }

  void _schedulePush(Note note) {''',
  );
  edit(
    state,
    r'''Timer(_pushDelay, () {''',
    r'''Timer(_pushDelayFor(note), () {''',
  );

  // Punkt 2: Beim Wechsel in den Hintergrund bei Netzwerkfehler abbrechen.
  edit(
    state,
    r'''    for (final note in List.of(notes)) {
      if (note.dirty || note.deleted) await _push(note);
    }
  }''',
    r'''    _networkFailed = false;
    for (final note in List.of(notes)) {
      if (note.dirty || note.deleted) await _push(note);
      if (_networkFailed || authFailed) break;
    }
  }''',
  );

  // Punkte 2, 4, 15 in _push.
  edit(
    state,
    r'''    var changedMeanwhile = false;
    final dirtyFieldsAtStart = Set<String>.of(note.dirtyFields);''',
    r'''    var changedMeanwhile = false;
    var retryLater = false;
    final dirtyFieldsAtStart = Set<String>.of(note.dirtyFields);''',
  );
  edit(
    state,
    r'''      error = null;
      await _persist();
    } catch (e) {
      error = '$e';
      LogService.log('Push fehlgeschlagen (${note.id}): $e');''',
    r'''      error = null;
      _pushFailures.remove(note);
      await _persist();
    } catch (e) {
      error = '$e';
      if (e is MemosApiException && e.statusCode == 401) {
        authFailed = true;
      } else if (_isNetworkError(e)) {
        _networkFailed = true;
        retryLater = true;
        _pushFailures[note] = (_pushFailures[note] ?? 0) + 1;
      }
      LogService.log('Push fehlgeschlagen (${note.id}): $e');''',
  );
  edit(
    state,
    r'''    if (changedMeanwhile && notes.contains(note)) _schedulePush(note);''',
    r'''    if ((changedMeanwhile || retryLater) && notes.contains(note)) {
      _schedulePush(note);
    }''',
  );

  // Punkt 2: Netzwerkfehler beim Profil nicht verschlucken (sonst 2× Timeout).
  edit(
    state,
    r'''      LogService.log('Instanzprofil konnte nicht gelesen werden: $e');''',
    r'''      LogService.log('Instanzprofil konnte nicht gelesen werden: $e');
      if (_isNetworkError(e)) rethrow;''',
  );

  // sync(): Signatur, Abbruch bei Netzwerk-/401-Fehler, inkrementeller Abruf.
  edit(
    state,
    r'''  Future<void> sync() async {
    if (!configured || syncing) return;
    syncing = true;
    error = null;''',
    r'''  Future<void> sync({bool full = false}) async {
    if (!configured || syncing) return;
    syncing = true;
    error = null;
    authFailed = false;
    _networkFailed = false;''',
  );
  edit(
    state,
    r'''      final api = _api;
      await _refreshSpacesAndVersion(api);
      for (final note in List.of(notes)) {
        if (note.dirty || note.deleted) await _push(note);
      }
      final normal = await api.list();
      final archived = await api.list(state: 'ARCHIVED');''',
    r'''      final startedAt = DateTime.now().toUtc();
      final api = _api;
      await _refreshSpacesAndVersion(api);
      for (final note in List.of(notes)) {
        if (note.dirty || note.deleted) await _push(note);
        // Server nicht erreichbar oder Token ungültig: nicht jede weitere
        // Notiz noch einmal bis zum Timeout versuchen.
        if (_networkFailed || authFailed) break;
      }
      if (_networkFailed || authFailed) return;

      var incremental =
          !full &&
          _lastSyncStart != null &&
          _lastFullSync != null &&
          startedAt.difference(_lastFullSync!) < _fullSyncInterval;
      List<Note> normal;
      List<Note> archived;
      try {
        final since = incremental
            ? _lastSyncStart!.subtract(const Duration(minutes: 5))
            : null;
        normal = await api.list(updatedSince: since);
        archived = await api.list(state: 'ARCHIVED', updatedSince: since);
      } on MemosApiException catch (e) {
        if (!incremental || e.statusCode == 401) rethrow;
        LogService.log('Inkrementeller Sync nicht möglich ($e), lade alles');
        incremental = false;
        normal = await api.list();
        archived = await api.list(state: 'ARCHIVED');
      }''',
  );

  // Punkt 1: Ungesendete Änderungen nie verwerfen.
  edit(
    state,
    r'''      merged.addAll(notes.where((note) => note.isLocal));
      notes = merged;''',
    r'''      if (incremental) {
        // Nur geänderte Notizen wurden geladen: alle anderen bleiben unverändert.
        merged.addAll(notes.where((note) => !remoteById.containsKey(note.id)));
      } else {
        merged.addAll(notes.where((note) => note.isLocal));
        var recreated = 0;
        for (final note in List.of(notes)) {
          if (note.isLocal || remoteById.containsKey(note.id)) continue;
          if (note.busy) {
            merged.add(note); // wird gerade gesendet
            continue;
          }
          if (!note.dirty || note.deleted) continue; // wirklich entfernt
          // Lokal geändert, auf dem Server aber nicht mehr vorhanden
          // (z. B. im Web gelöscht): als neue Notiz erneut anlegen.
          final oldId = note.id;
          note.id =
              'local-${DateTime.now().microsecondsSinceEpoch}-${recreated++}';
          if (widgetIds.remove(oldId)) widgetIds.add(note.id);
          note.relations = [];
          note.dirtyFields.addAll({'content', 'pinned', 'state', 'visibility'});
          if (note.space != null) note.dirtyFields.add('space');
          merged.add(note);
          LogService.log('Notiz $oldId fehlt auf dem Server, wird neu angelegt');
          _schedulePush(note);
        }
        if (recreated > 0) {
          notice =
              '$recreated lokal geänderte Notiz(en) gab es auf dem Server nicht '
              'mehr und werden dort neu angelegt.';
        }
      }
      notes = merged;
      _lastSyncStart = startedAt;
      if (!incremental) _lastFullSync = startedAt;''',
  );
  edit(
    state,
    r'''      error = '$e';
      LogService.log('Sync fehlgeschlagen: $e');''',
    r'''      error = '$e';
      if (e is MemosApiException && e.statusCode == 401) authFailed = true;
      LogService.log('Sync fehlgeschlagen: $e');''',
  );

  // Punkt 14: Beim Zurückkehren in die App kurz (inkrementell) abgleichen.
  edit(
    state,
    r'''  Future<void> onForeground() => _updateWidget();''',
    r'''  Future<void> onForeground() async {
    await _updateWidget();
    if (configured) unawaited(sync());
  }''',
  );

  // Punkt 8: Cache-Zugriff.
  edit(
    state,
    r'''  Future<List<int>> fetchAttachment(String name) =>
      _api.downloadAttachment(name.split('/').last);''',
    r'''  Future<List<int>> fetchAttachment(String name) =>
      _api.downloadAttachment(name.split('/').last);

  /// Anhang-Bytes über den Speicher-/Festplatten-Cache.
  Future<Uint8List> attachmentBytes(String name) => attachmentCache.get(name);''',
  );

  edit(
    state,
    r'''List<String> _extractTags(String content) {''',
    r'''bool _isNetworkError(Object e) =>
    e is SocketException ||
    e is TimeoutException ||
    e is HandshakeException ||
    e is ClientException;

List<String> _extractTags(String content) {''',
  );

  // ───────────────────── home_screen.dart (4, 5, 8, 13, 14) ─────────────────
  edit(
    home,
    r'''import '../models/task_doc.dart';''',
    r'''import '../models/task_doc.dart';
import '../services/api.dart';''',
  );

  // Punkt 5: Teilen-Link.
  edit(
    home,
    r'''  final uri = Uri.parse(
    '${state.baseUrl}memos/${Uri.encodeComponent(note.id)}',
  );''',
    r'''  final String base;
  try {
    base = MemosApi.normalizeBaseUrl(state.baseUrl);
  } on FormatException {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Keine gültige Server-URL eingerichtet'),
      ),
    );
    return;
  }
  final uri = Uri.parse('$base/memos/${Uri.encodeComponent(note.id)}');''',
  );

  // Punkt 4: 401-Banner.
  edit(
    home,
    r''''Sync-Fehler: ${s.error}',''',
    r'''s.authFailed
                    ? 'Anmeldung fehlgeschlagen: Das Token ist ungültig oder abgelaufen.'
                    : 'Sync-Fehler: ${s.error}',''',
  );
  edit(
    home,
    r'''TextButton(onPressed: s.sync, child: const Text('Erneut')),''',
    r'''if (s.authFailed)
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                    child: const Text('Einstellungen'),
                  )
                else
                  TextButton(onPressed: s.sync, child: const Text('Erneut')),''',
  );

  // Punkt 14: Symbol und Ziehen nach unten laden vollständig.
  edit(
    home,
    r'''IconButton(icon: const Icon(Icons.sync), onPressed: s.sync),''',
    r'''IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Vollständig synchronisieren',
              onPressed: () => s.sync(full: true),
            ),''',
  );
  edit(
    home,
    r'''onRefresh: s.sync,''',
    r'''onRefresh: () => s.sync(full: true),''',
  );

  // Punkt 13: Vorschau pro Notiz cachen.
  edit(
    home,
    r'''final _doneLineRe = RegExp(r'^\s*[-*] \[[xX]\]');''',
    r'''final _doneLineRe = RegExp(r'^\s*[-*] \[[xX]\]');

class _PreviewData {
  final String content;
  final String? heading;
  final List<String> rest;
  final List<String> shown;
  final List<Segment> segments;
  const _PreviewData(
    this.content,
    this.heading,
    this.rest,
    this.shown,
    this.segments,
  );
}

/// Vorschau wird nur neu berechnet, wenn sich der Inhalt der Notiz ändert.
final _previewCache = Expando<_PreviewData>('notePreview');

_PreviewData _previewFor(Note note) {
  final cached = _previewCache[note];
  if (cached != null && cached.content == note.content) return cached;
  final lines = note.content.split('\n');
  var i = lines.indexWhere((l) => l.trim().isNotEmpty);
  String? heading;
  if (i >= 0) {
    final m = _headingRe.firstMatch(lines[i]);
    if (m != null) {
      final h = m.group(1)!.trim();
      heading = h.isEmpty ? null : h;
      i++;
    }
  }
  final rest = i < 0
      ? <String>[]
      : lines
            .skip(i)
            .where((l) => l.trim().isNotEmpty && !_doneLineRe.hasMatch(l))
            .toList();
  final shown = rest.take(5).toList();
  final data = _PreviewData(
    note.content,
    heading,
    rest,
    shown,
    parseDoc(shown.join('\n')),
  );
  _previewCache[note] = data;
  return data;
}''',
  );
  editSpan(
    home,
    r'''    final lines = note.content.split('\n');''',
    r'''    final shown = rest.take(5).toList();''',
    r'''    final data = _previewFor(note);
    final heading = data.heading;
    final rest = data.rest;
    final shown = data.shown;''',
  );
  edit(
    home,
    r'''for (final seg in parseDoc(shown.join('\n')))''',
    r'''for (final seg in data.segments)''',
  );

  // Punkt 8: Bilder über den Cache laden und verkleinert dekodieren.
  editSpan(
    home,
    r'''    final bytes = await context.read<AppState>().fetchAttachment(''',
    r'''    return Uint8List.fromList(bytes);''',
    r'''    return context.read<AppState>().attachmentBytes(attachment.name);''',
  );
  edit(
    home,
    r'''                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,''',
    r'''                  return Image.memory(
                    snapshot.data!,
                    cacheWidth: 320,
                    fit: BoxFit.cover,''',
  );
  edit(
    home,
    r'''            ? Image.file(
                File(pending.path),
                fit: BoxFit.cover,''',
    r'''            ? Image.file(
                File(pending.path),
                cacheWidth: 320,
                fit: BoxFit.cover,''',
  );

  // ───────────────────────── note_screen.dart (8) ───────────────────────────
  edit(
    note,
    r'''Uint8List.fromList(await s.fetchAttachment(attachment.name))''',
    r'''await s.attachmentBytes(attachment.name)''',
    all: true,
  );
  edit(
    note,
    r'''              return Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,''',
    r'''              return Image.memory(
                snapshot.data!,
                cacheWidth: 1200,
                fit: BoxFit.contain,''',
  );
  edit(
    note,
    r'''      child: Image.file(
        File(attachment.path),
        fit: BoxFit.contain,''',
    r'''      child: Image.file(
        File(attachment.path),
        cacheWidth: 1200,
        fit: BoxFit.contain,''',
  );

  // ───────────────────────── main.dart (7) ──────────────────────────────────
  edit(
    mainDart,
    r'''import 'package:flutter/material.dart';''',
    r'''import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';''',
  );
  edit(
    mainDart,
    r'''class _NotizAppState extends State<NotizApp> with WidgetsBindingObserver {''',
    r'''class _NotizAppState extends State<NotizApp> with WidgetsBindingObserver {
  StreamSubscription<Uri?>? _widgetClicks;
''',
  );
  editSpan(
    mainDart,
    r'''_widgetChannel.setMethodCallHandler(''',
    r'''_widgetChannel.invokeMethod<void>('ready');''',
    r'''if (Platform.isAndroid) {
      _widgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'openWidgetUri' && call.arguments is String) {
          _open(Uri.tryParse(call.arguments as String));
        }
      });
      _widgetChannel.invokeMethod<void>('ready');
    } else if (Platform.isIOS) {
      // Der MethodChannel gibt es nur auf Android (MainActivity.kt).
      HomeWidget.initiallyLaunchedFromHomeWidget()
          .then(_open)
          .catchError((Object _) {});
      _widgetClicks = HomeWidget.widgetClicked.listen(_open);
    }''',
  );
  edit(
    mainDart,
    r'''WidgetsBinding.instance.removeObserver(this);''',
    r'''WidgetsBinding.instance.removeObserver(this);
    _widgetClicks?.cancel();''',
  );

  // ───────────────────────── Android-Widget (11) ────────────────────────────
  edit(
    kotlinService,
    r'''override fun getItemId(position: Int): Long = notes[position].id.hashCode().toLong()''',
    r'''override fun getItemId(position: Int): Long =
        notes.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()''',
  );

  // ───────────────────────── iOS (12) ───────────────────────────────────────
  edit(
    plist,
    '<key>LSRequiresIPhoneOS</key>',
    '<key>CFBundleURLTypes</key>\n'
        '\t<array>\n'
        '\t\t<dict>\n'
        '\t\t\t<key>CFBundleURLName</key>\n'
        '\t\t\t<string>com.github.homehoster.meine_notizen</string>\n'
        '\t\t\t<key>CFBundleURLSchemes</key>\n'
        '\t\t\t<array>\n'
        '\t\t\t\t<string>notizapp</string>\n'
        '\t\t\t</array>\n'
        '\t\t</dict>\n'
        '\t</array>\n'
        '\t<key>NSAppTransportSecurity</key>\n'
        '\t<dict>\n'
        '\t\t<key>NSAllowsLocalNetworking</key>\n'
        '\t\t<true/>\n'
        '\t</dict>\n'
        '\t<key>LSRequiresIPhoneOS</key>',
  );

  // ───────────────────────── Doku (16) ──────────────────────────────────────
  const readme = 'README.md';
  const doc = 'docs/DOKUMENTATION.md';
  edit(
    readme,
    r'''[flutter_markdown](https://pub.dev/packages/flutter_markdown)''',
    r'''[flutter_markdown_plus](https://pub.dev/packages/flutter_markdown_plus)''',
    optional: true,
  );
  edit(doc, r'''Farbschema Teal''', r'''Farbschema Blau''', optional: true);
  edit(
    doc,
    r'''| `flutter_markdown` | Darstellung von Markdown in der Ansicht |''',
    r'''| `flutter_markdown_plus` | Darstellung von Markdown in der Ansicht |''',
    optional: true,
  );
  edit(
    doc,
    r'''| `record`, `audioplayers` | Audio aufnehmen und wiedergeben |''',
    r'''| `record` | Audio aufnehmen |
| `open_filex` | Anhänge mit der passenden App des Systems öffnen |
| `package_info_plus` | App-Version anzeigen |''',
    optional: true,
  );
  edit(
    doc,
    r'''> ℹ️ `flutter_markdown` wird vom Flutter-Team nicht mehr weiterentwickelt. Eine Alternative ist der Nachfolger `flutter_markdown_plus`.''',
    r'''> ℹ️ Für Markdown wird `flutter_markdown_plus` verwendet (Nachfolger des eingestellten `flutter_markdown`).''',
    optional: true,
  );
  edit(
    doc,
    r'''mit der Schaltfläche **Erneut**.''',
    r'''mit der Schaltfläche **Erneut**.

Bei einem Netzwerkfehler bricht der Sync beim ersten fehlgeschlagenen Versand ab, statt für jede Notiz bis zum Timeout zu warten. Fehlgeschlagene Notizen werden automatisch mit wachsendem Abstand erneut versucht (8 s, 16 s, 32 s … höchstens 5 Minuten). Bei HTTP 401 (Token ungültig oder abgelaufen) wird nicht wiederholt; das Banner bietet stattdessen den Sprung in die Einstellungen an.

**Inkrementeller Sync:** Der erste Sync nach dem Start lädt alles. Beim Zurückkehren in die App werden danach nur Notizen mit neuerem `updated_ts` geladen. Das Sync-Symbol und Ziehen nach unten laden immer vollständig (nur so fallen auf dem Server gelöschte Notizen auf); spätestens nach 6 Stunden wird ebenfalls wieder vollständig abgeglichen. Lehnt der Server den Filter ab, fällt die App auf den vollständigen Abgleich zurück.''',
    optional: true,
  );
  edit(
    doc,
    r'''Das Gerät mit nicht gesendeten Änderungen gewinnt beim nächsten Sync.''',
    r'''Das Gerät mit nicht gesendeten Änderungen gewinnt beim nächsten Sync. Existiert eine lokal geänderte Notiz auf dem Server nicht mehr (z. B. im Web gelöscht), wird sie nicht verworfen, sondern dort als neue Notiz angelegt; die Startseite zeigt einen Hinweis.''',
    optional: true,
  );
  edit(
    doc,
    r'''ist keine markiert, zeigt es alle sichtbaren Notizen.''',
    r'''ist keine markiert, zeigt es alle sichtbaren Notizen (höchstens 30).''',
    optional: true,
  );

  // ───────────────────────── Ergebnis ───────────────────────────────────────
  if (_problems.isNotEmpty) {
    stderr.writeln('ABBRUCH – es wurde nichts geändert. Probleme:');
    for (final p in _problems) {
      stderr.writeln(' - $p');
    }
    exit(1);
  }

  for (final entry in _files.entries) {
    final eol = _eol[entry.key] ?? '\n';
    File(entry.key).writeAsStringSync(
      eol == '\n' ? entry.value : entry.value.replaceAll('\n', eol),
    );
  }

  // Neue bzw. komplett ersetzte Dateien kopieren.
  final source = Directory('notiz_patch/files');
  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = entity.path
        .replaceAll('\\', '/')
        .substring('notiz_patch/files/'.length);
    File(rel).createSync(recursive: true);
    entity.copySync(rel);
  }

  // Punkt 16: Überbleibsel löschen.
  final bak = File('android/app/src/main/res/NoteWidgetProvider.kt.bak');
  if (bak.existsSync()) bak.deleteSync();

  stdout.writeln('Fertig: ${_files.length} Dateien geändert, neue Dateien kopiert.');
  for (final w in _warnings) {
    stdout.writeln('Hinweis (übersprungen): $w');
  }
  stdout.writeln('Nächste Schritte: flutter pub get && flutter analyze && flutter test');
}
