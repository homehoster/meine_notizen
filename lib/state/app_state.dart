import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../models/saved_view.dart';
import '../models/space.dart';
import '../models/task_doc.dart';
import '../services/api.dart';
import '../services/log.dart';
import '../services/store.dart';

enum NavigationKind { all, archive, space, view, tag }

class NavigationTarget {
  final NavigationKind kind;
  final String? id;

  const NavigationTarget(this.kind, [this.id]);
}

class AppState extends ChangeNotifier {
  static const _pushDelay = Duration(seconds: 4);
  static const _maxAttachmentBytes = 100 * 1024 * 1024;

  final _store = LocalStore();
  final _secure = const FlutterSecureStorage();
  final Map<Note, Timer> _pushTimers = {};

  String baseUrl = '';
  String token = '';
  String serverVersion = '';
  ThemeMode themeMode = ThemeMode.system;
  bool blockMarkdownImages = true;
  bool assistedEditingEnabled = true;
  List<Note> notes = [];
  List<MemoSpace> spaces = [];
  List<SavedView> savedViews = [];
  Set<String> widgetIds = {};
  bool? spacesSupported;
  bool syncing = false;
  String? error;
  String? notice;
  bool logEnabled = false;
  NavigationTarget navigation = const NavigationTarget(NavigationKind.all);

  Future<void> Function()? onBeforeBackground;

  bool get configured => baseUrl.isNotEmpty && token.isNotEmpty;
  MemosApi get _api => MemosApi(baseUrl, token);

  List<Note> get visible => _sorted(
    notes.where((note) => !note.deleted && note.state == NoteState.normal),
  );

  List<Note> get selectedNotes {
    final target = navigation;
    return _sorted(
      notes.where((note) {
        if (note.deleted) return false;
        switch (target.kind) {
          case NavigationKind.all:
            return note.state == NoteState.normal;
          case NavigationKind.archive:
            return note.state == NoteState.archived;
          case NavigationKind.space:
            return note.state == NoteState.normal &&
                note.space == 'spaces/${target.id}';
          case NavigationKind.view:
            final view = savedViewById(target.id);
            return note.state == NoteState.normal &&
                (view == null || view.matches(note));
          case NavigationKind.tag:
            return note.state == NoteState.normal &&
                note.tags.contains(target.id);
        }
      }),
    );
  }

  String get screenTitle {
    switch (navigation.kind) {
      case NavigationKind.all:
        return 'Alle Notizen';
      case NavigationKind.archive:
        return 'Archiv';
      case NavigationKind.space:
        for (final space in spaces) {
          if (space.id == navigation.id) return space.title;
        }
        return 'Bereich';
      case NavigationKind.view:
        return savedViewById(navigation.id)?.name ?? 'Ansicht';
      case NavigationKind.tag:
        return '#${navigation.id ?? ''}';
    }
  }

  List<String> get tags {
    final result = <String>{};
    for (final note in notes) {
      if (!note.deleted && note.state == NoteState.normal) {
        result.addAll(note.tags);
      }
    }
    return result.toList()..sort();
  }

  List<Note> _sorted(Iterable<Note> values) {
    final result = values.toList();
    result.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updated.compareTo(a.updated);
    });
    return result;
  }

  SavedView? savedViewById(String? id) {
    for (final view in savedViews) {
      if (view.id == id) return view;
    }
    return null;
  }

  Note? byId(String id) {
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  Future<void> init() async {
    final preferences = await SharedPreferences.getInstance();
    baseUrl = preferences.getString('url') ?? '';
    themeMode = ThemeMode.values[preferences.getInt('theme') ?? 0];
    blockMarkdownImages = preferences.getBool('blockMarkdownImages') ?? true;
    assistedEditingEnabled =
        preferences.getBool('assistedEditingEnabled') ?? true;
    logEnabled = preferences.getBool('log') ?? false;
    LogService.setEnabled(logEnabled);
    token = await _secure.read(key: 'token') ?? '';
    final data = await _store.load();
    notes = data.notes;
    widgetIds = data.widgetIds;
    savedViews = data.savedViews;
    spaces = data.spaces;
    spacesSupported = data.spacesSupported;
    if (data.warning != null) {
      notice = data.warning;
      LogService.log(data.warning!);
    }
    notifyListeners();
    unawaited(_updateWidget());
    if (configured) unawaited(sync());
  }

  void dismissNotice() {
    notice = null;
    notifyListeners();
  }

  Future<void> testConnection(String url, String tok) =>
      MemosApi(url, tok).ping();

  Future<void> saveSettings(String url, String tok) async {
    final preferences = await SharedPreferences.getInstance();
    baseUrl = url.trim();
    token = tok.trim();
    spacesSupported = null;
    spaces = [];
    await preferences.setString('url', baseUrl);
    await _secure.write(key: 'token', value: token);
    await _persist();
    notifyListeners();
    unawaited(sync());
  }

  Future<void> clearServerSettings() async {
    final preferences = await SharedPreferences.getInstance();
    baseUrl = '';
    token = '';
    error = null;
    spacesSupported = null;
    spaces = [];
    await preferences.remove('url');
    await _secure.delete(key: 'token');
    await _persist();
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('theme', mode.index);
    notifyListeners();
  }

  Future<void> setBlockMarkdownImages(bool value) async {
    blockMarkdownImages = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('blockMarkdownImages', value);
    notifyListeners();
  }

  Future<void> setAssistedEditingEnabled(bool value) async {
    assistedEditingEnabled = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('assistedEditingEnabled', value);
    notifyListeners();
  }

  Future<void> setLogEnabled(bool value) async {
    logEnabled = value;
    LogService.setEnabled(value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('log', value);
    LogService.log('Logging ${value ? 'aktiviert' : 'deaktiviert'}');
    notifyListeners();
  }

  Future<void> _persist() =>
      _store.save(notes, widgetIds, savedViews, spaces, spacesSupported);

  void select(NavigationTarget target) {
    navigation = target;
    notifyListeners();
  }

  Future<Note> create() async {
    final note = Note(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      content: '',
      updated: DateTime.now(),
      dirty: true,
    );
    notes.add(note);
    await _persist();
    notifyListeners();
    return note;
  }

  Future<void> discardIfEmpty(Note note) async {
    if (note.isLocal &&
        note.content.trim().isEmpty &&
        note.pendingAttachments.isEmpty &&
        note.location == null) {
      _pushTimers.remove(note)?.cancel();
      notes.remove(note);
      await _persist();
      notifyListeners();
    }
  }

  Future<void> saveContent(Note note, String content) async {
    if (note.deleted || note.content == content) return;
    note.content = content;
    note.tags = _extractTags(content);
    note.updated = DateTime.now();
    note.dirty = true;
    note.dirtyFields.add('content');
    await _persist();
    if (!notes.contains(note)) return;
    notifyListeners();
    _schedulePush(note);
  }

  Future<void> finishEditing(Note note, String content) async {
    await saveContent(note, content);
    await discardIfEmpty(note);
    if (notes.contains(note)) await pushNow(note);
  }

  Future<void> deleteNote(Note note) async {
    _pushTimers.remove(note)?.cancel();
    note.deleted = true;
    note.dirty = true;
    widgetIds.remove(note.id);
    if (note.isLocal) notes.remove(note);
    await _persist();
    notifyListeners();
    await _removePendingFiles(note.pendingAttachments);
    if (!note.isLocal) unawaited(_push(note));
  }

  Future<void> setPinned(Note note, bool value) =>
      _updateNoteField(note, 'pinned', () => note.pinned = value);

  Future<void> archive(Note note) =>
      _updateNoteField(note, 'state', () => note.state = NoteState.archived);

  Future<void> restore(Note note) =>
      _updateNoteField(note, 'state', () => note.state = NoteState.normal);

  Future<void> assignSpace(Note note, MemoSpace? space) async {
    if (note.space == space?.name) return;
    note.space = space?.name;
    if (space != null && note.visibility != 'SPACE') {
      note.visibilityBeforeSpace = note.visibility;
      note.visibility = 'SPACE';
    } else if (space == null && note.visibility == 'SPACE') {
      note.visibility = note.visibilityBeforeSpace ?? 'PRIVATE';
      note.visibilityBeforeSpace = null;
    }
    note.dirty = true;
    note.dirtyFields.add('space');
    note.dirtyFields.add('visibility');
    await _persist();
    notifyListeners();
    _schedulePush(note);
  }

  Future<void> _updateNoteField(
    Note note,
    String field,
    void Function() update,
  ) async {
    update();
    note.dirty = true;
    note.dirtyFields.add(field);
    await _persist();
    notifyListeners();
    _schedulePush(note);
  }

  Future<void> addPendingAttachment(
    Note note, {
    required String sourcePath,
    required String filename,
    required String type,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Datei nicht gefunden', sourcePath);
    }
    final size = await source.length();
    if (size > _maxAttachmentBytes) {
      throw const FileSystemException('Datei überschreitet 100 MB.');
    }
    final directory = await _pendingDirectory();
    final safeName = p
        .basename(filename)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File(
      p.join(
        directory.path,
        '${note.id}-${DateTime.now().microsecondsSinceEpoch}-$safeName',
      ),
    );
    await source.copy(destination.path);
    note.pendingAttachments.add(
      PendingAttachment(
        path: destination.path,
        filename: p.basename(filename),
        type: type.isEmpty ? 'application/octet-stream' : type,
        size: size,
      ),
    );
    note.dirty = true;
    note.dirtyFields.add('attachments');
    await _persist();
    notifyListeners();
    _schedulePush(note);
  }

  Future<void> addPendingBytes(
    Note note, {
    required List<int> bytes,
    required String filename,
    required String type,
  }) async {
    if (bytes.length > _maxAttachmentBytes) {
      throw const FileSystemException('Datei überschreitet 100 MB.');
    }
    final directory = await _pendingDirectory();
    final safeName = p
        .basename(filename)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File(
      p.join(
        directory.path,
        '${note.id}-${DateTime.now().microsecondsSinceEpoch}-$safeName',
      ),
    );
    await destination.writeAsBytes(bytes, flush: true);
    note.pendingAttachments.add(
      PendingAttachment(
        path: destination.path,
        filename: p.basename(filename),
        type: type,
        size: bytes.length,
      ),
    );
    note.dirty = true;
    note.dirtyFields.add('attachments');
    await _persist();
    notifyListeners();
    _schedulePush(note);
  }

  Future<void> addPendingStream(
    Note note, {
    required Stream<List<int>> stream,
    required String filename,
    required String type,
  }) async {
    final directory = await _pendingDirectory();
    final safeName = p
        .basename(filename)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final destination = File(
      p.join(
        directory.path,
        '${note.id}-${DateTime.now().microsecondsSinceEpoch}-$safeName',
      ),
    );
    final sink = destination.openWrite();
    var size = 0;
    try {
      await for (final chunk in stream) {
        size += chunk.length;
        if (size > _maxAttachmentBytes) {
          throw const FileSystemException('Datei überschreitet 100 MB.');
        }
        sink.add(chunk);
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    await sink.close();
    note.pendingAttachments.add(
      PendingAttachment(
        path: destination.path,
        filename: p.basename(filename),
        type: type.isEmpty ? 'application/octet-stream' : type,
        size: size,
      ),
    );
    note.dirty = true;
    note.dirtyFields.add('attachments');
    await _persist();
    notifyListeners();
    _schedulePush(note);
  }

  Future<void> removeAttachment(Note note, NoteAttachment attachment) async {
    if (!note.attachments.remove(attachment)) return;
    note.dirty = true;
    note.dirtyFields.add('attachments');
    await _persist();
    notifyListeners();
    _schedulePush(note);
  }

  Future<void> removePendingAttachment(
    Note note,
    PendingAttachment attachment,
  ) async {
    if (!note.pendingAttachments.contains(attachment)) return;
    final file = File(attachment.path);
    if (await file.exists()) await file.delete();

    note.pendingAttachments.remove(attachment);
    if (attachment.uploadedName case final name?) {
      note.attachments.removeWhere((item) => item.name == name);
      note.dirtyFields.add('attachments');
    }
    note.dirty =
        note.dirtyFields.isNotEmpty || note.pendingAttachments.isNotEmpty;
    await _persist();
    notifyListeners();
    _schedulePush(note);
  }

  Future<Directory> _pendingDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'pending_attachments'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> setLocation(Note note, NoteLocation location) async {
    note.location = location;
    note.dirty = true;
    note.dirtyFields.add('location');
    await _persist();
    notifyListeners();
    _schedulePush(note);
  }

  Future<void> toggleWidget(Note note) async {
    if (!widgetIds.remove(note.id)) widgetIds.add(note.id);
    await _persist();
    notifyListeners();
  }

  Future<void> saveView(SavedView view) async {
    final index = savedViews.indexWhere((candidate) => candidate.id == view.id);
    if (index < 0) {
      savedViews.add(view);
    } else {
      savedViews[index] = view;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> deleteView(String id) async {
    savedViews.removeWhere((view) => view.id == id);
    if (navigation.kind == NavigationKind.view && navigation.id == id) {
      navigation = const NavigationTarget(NavigationKind.all);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> saveSpace(MemoSpace space) async {
    final saved = space.name.isEmpty
        ? await _api.createSpace(space)
        : await _api.updateSpace(space);
    spaces.removeWhere((current) => current.name == saved.name);
    spaces.add(saved);
    spaces.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    spacesSupported = true;
    await _persist();
    notifyListeners();
  }

  Future<void> deleteSpace(MemoSpace space) async {
    await _api.deleteSpace(space);
    spaces.removeWhere((current) => current.name == space.name);
    final removed = notes.where((note) => note.space == space.name).toList();
    for (final note in removed) {
      _pushTimers.remove(note)?.cancel();
    }
    notes.removeWhere((note) => note.space == space.name);
    if (navigation.kind == NavigationKind.space && navigation.id == space.id) {
      navigation = const NavigationTarget(NavigationKind.all);
    }
    widgetIds.removeWhere((id) => !notes.any((note) => note.id == id));
    await _persist();
    notifyListeners();
    for (final note in removed) {
      await _removePendingFiles(note.pendingAttachments);
    }
  }

  Future<void> _removePendingFiles(
    Iterable<PendingAttachment> attachments,
  ) async {
    for (final attachment in attachments) {
      final file = File(attachment.path);
      try {
        if (await file.exists()) await file.delete();
      } catch (e) {
        LogService.log('Lokaler Anhang konnte nicht entfernt werden: $e');
      }
    }
  }

  Future<void> _updateWidget() async {
    try {
      final ordered = visible;
      final selected = ordered
          .where((note) => widgetIds.contains(note.id))
          .toList();
      final values = selected.isEmpty ? ordered : selected;
      final items = <Map<String, dynamic>>[];
      for (final note in values) {
        final attachments = <Map<String, String>>[
          for (final attachment in note.attachments)
            {'filename': attachment.filename, 'type': attachment.type},
          for (final attachment in note.pendingAttachments)
            {'filename': attachment.filename, 'type': attachment.type},
        ];
        final attachmentSummary = attachments.isEmpty
            ? ''
            : 'Anhang: ${attachments.take(2).map((a) => a['filename']).join(', ')}'
                  '${attachments.length > 2 ? ', +${attachments.length - 2}' : ''}';
        final imagePath = await _widgetImagePath(note);
        items.add({
          'id': note.id,
          'title': note.title,
          'preview': widgetPreview(note.content),
          'attachmentSummary': attachmentSummary,
          'imagePath': imagePath ?? '',
        });
      }
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

  Future<String?> _widgetImagePath(Note note) async {
    final attachment = note.attachments.where(
      (item) => item.type.startsWith('image/'),
    );
    final pending = note.pendingAttachments.where(
      (item) => item.type.startsWith('image/'),
    );
    final serverImage = attachment.isEmpty ? null : attachment.first;
    final pendingImage = pending.isEmpty ? null : pending.first;
    final id = note.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final pathKey = 'note_${id}_image';
    final sourceKey = 'note_${id}_image_source';
    final cachedSource = await HomeWidget.getWidgetData<String>(sourceKey);
    final cachedPath = await HomeWidget.getWidgetData<String>(pathKey);

    if (serverImage == null && pendingImage == null) {
      if (cachedPath != null) {
        await HomeWidget.saveWidgetData<String>(pathKey, null);
      }
      if (cachedSource != null) {
        await HomeWidget.saveWidgetData<String>(
          sourceKey,
          null,
          deleteFile: false,
        );
      }
      return null;
    }

    final source = serverImage?.name ?? pendingImage!.path;
    if (cachedSource == source &&
        cachedPath != null &&
        await File(cachedPath).exists()) {
      return cachedPath;
    }

    try {
      final Uint8List bytes = serverImage != null
          ? Uint8List.fromList(await fetchAttachment(serverImage.name))
          : await File(pendingImage!.path).readAsBytes();
      final thumbnail = await _createWidgetThumbnail(bytes);
      final path = await HomeWidget.saveFile(
        pathKey,
        thumbnail,
        extension: 'png',
      );
      await HomeWidget.saveWidgetData<String>(
        sourceKey,
        source,
        deleteFile: false,
      );
      return path;
    } catch (e) {
      LogService.log(
        'Widget-Bild konnte nicht geladen werden (${note.id}): $e',
      );
      return null;
    }
  }

  Future<Uint8List> _createWidgetThumbnail(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 192,
      targetHeight: 128,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) {
          throw const FormatException(
            'Widget-Bild konnte nicht kodiert werden.',
          );
        }
        return data.buffer.asUint8List();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  void _schedulePush(Note note) {
    if (!configured) return;
    _pushTimers[note]?.cancel();
    _pushTimers[note] = Timer(_pushDelay, () {
      _pushTimers.remove(note);
      unawaited(_push(note));
    });
  }

  Future<void> pushNow(Note note) async {
    _pushTimers.remove(note)?.cancel();
    if (note.dirty || note.deleted) await _push(note);
  }

  Future<void> _flushPushes() async {
    for (final timer in _pushTimers.values) {
      timer.cancel();
    }
    _pushTimers.clear();
    for (final note in List.of(notes)) {
      if (note.dirty || note.deleted) await _push(note);
    }
  }

  dynamic _fieldValue(Note note, String field) => switch (field) {
    'content' => note.content,
    'pinned' => note.pinned,
    'state' => note.state == NoteState.archived ? 'ARCHIVED' : 'NORMAL',
    'visibility' => note.visibility,
    'space' => note.space ?? '',
    'location' => note.location?.toJson(),
    _ => null,
  };

  Future<void> _push(Note note) async {
    if (!configured || note.busy) return;
    if (note.isLocal &&
        !note.deleted &&
        note.content.trim().isEmpty &&
        note.pendingAttachments.isEmpty &&
        note.location == null) {
      return;
    }
    note.busy = true;
    var changedMeanwhile = false;
    try {
      if (note.deleted) {
        if (!note.isLocal) await _api.delete(note.id);
        notes.remove(note);
      } else {
        if (note.isLocal) {
          final sent = note.content;
          final oldId = note.id;
          note.id = await _api.create(sent);
          if (widgetIds.remove(oldId)) widgetIds.add(note.id);
          if (note.content == sent) {
            note.dirtyFields.remove('content');
          } else {
            changedMeanwhile = true;
          }
        }

        final fields = <String, dynamic>{};
        for (final field in note.dirtyFields.toList()) {
          switch (field) {
            case 'content':
              fields['content'] = note.content;
            case 'pinned':
              fields['pinned'] = note.pinned;
            case 'state':
              fields['state'] = note.state == NoteState.archived
                  ? 'ARCHIVED'
                  : 'NORMAL';
            case 'visibility':
              fields['visibility'] = note.visibility;
            case 'space':
              fields['space'] = note.space ?? '';
            case 'location':
              if (note.location != null) {
                fields['location'] = note.location!.toJson();
              }
          }
        }
        if (fields.isNotEmpty) {
          await _api.updateMemo(note.id, fields);
          for (final entry in fields.entries) {
            final currentValue = _fieldValue(note, entry.key);
            final sameValue = entry.key == 'location'
                ? jsonEncode(currentValue) == jsonEncode(entry.value)
                : currentValue == entry.value;
            if (sameValue) {
              note.dirtyFields.remove(entry.key);
            } else {
              changedMeanwhile = true;
            }
          }
        }

        if (note.pendingAttachments.isNotEmpty ||
            note.dirtyFields.contains('attachments')) {
          final uploading = List<PendingAttachment>.of(note.pendingAttachments);
          for (final pending in uploading) {
            if (pending.uploadedName == null) {
              final uploaded = await _api.uploadAttachment(pending);
              pending.uploadedName = uploaded.name;
              note.attachments.add(uploaded);
              await _persist();
            }
          }
          final attachmentsToSave = List<NoteAttachment>.of(note.attachments);
          await _api.setMemoAttachments(note.id, attachmentsToSave);
          for (final pending in uploading) {
            final file = File(pending.path);
            if (await file.exists()) await file.delete();
            note.pendingAttachments.remove(pending);
          }
          final attachmentsUnchanged =
              note.attachments.length == attachmentsToSave.length &&
              List.generate(
                attachmentsToSave.length,
                (index) =>
                    note.attachments[index].name ==
                    attachmentsToSave[index].name,
              ).every((same) => same);
          if (attachmentsUnchanged && note.pendingAttachments.isEmpty) {
            note.dirtyFields.remove('attachments');
          } else {
            changedMeanwhile = true;
          }
        }

        note.dirty =
            note.dirtyFields.isNotEmpty || note.pendingAttachments.isNotEmpty;
      }
      error = null;
      await _persist();
    } catch (e) {
      error = '$e';
      LogService.log('Push fehlgeschlagen (${note.id}): $e');
    } finally {
      note.busy = false;
      notifyListeners();
    }
    if (changedMeanwhile && notes.contains(note)) _schedulePush(note);
  }

  Future<void> _refreshSpacesAndVersion(MemosApi api) async {
    try {
      final profile = await api.getInstanceProfile();
      serverVersion = profile['version'] as String? ?? '';
    } catch (e) {
      LogService.log('Instanzprofil konnte nicht gelesen werden: $e');
    }
    try {
      spaces = await api.listSpaces();
      spacesSupported = true;
      spaces.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    } on MemosApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 501) {
        spacesSupported = false;
        spaces = [];
      } else {
        rethrow;
      }
    }
  }

  Future<void> sync() async {
    if (!configured || syncing) return;
    syncing = true;
    error = null;
    notifyListeners();
    LogService.log('Sync gestartet ($baseUrl)');
    try {
      final api = _api;
      await _refreshSpacesAndVersion(api);
      for (final note in List.of(notes)) {
        if (note.dirty || note.deleted) await _push(note);
      }
      final normal = await api.list();
      final archived = await api.list(state: 'ARCHIVED');
      final remoteById = <String, Note>{
        for (final note in normal) note.id: note,
        for (final note in archived) note.id: note,
      };
      final remote = remoteById.values.toList();
      final local = {for (final note in notes) note.id: note};
      final merged = <Note>[];
      for (final serverNote in remote) {
        final current = local[serverNote.id];
        if (current == null) {
          merged.add(serverNote);
          continue;
        }
        if (!current.dirty && !current.deleted) {
          current.content = serverNote.content;
          current.updated = serverNote.updated;
          current.pinned = serverNote.pinned;
          current.state = serverNote.state;
          current.visibility = serverNote.visibility;
          current.space = serverNote.space;
          current.tags = serverNote.tags;
          current.attachments = serverNote.attachments;
          current.location = serverNote.location;
        }
        merged.add(current);
      }
      merged.addAll(notes.where((note) => note.isLocal));
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

  Future<List<int>> fetchAttachment(String name) =>
      _api.downloadAttachment(name.split('/').last);

  Future<void> onForeground() => _updateWidget();

  Future<void> onBackground() async {
    try {
      await onBeforeBackground?.call();
    } catch (e) {
      LogService.log('Editor sichern fehlgeschlagen: $e');
    }
    await _updateWidget();
    final hadLocal = notes.any((note) => note.isLocal);
    await _flushPushes();
    if (hadLocal) await _updateWidget();
    await LogService.flush();
  }
}

List<String> _extractTags(String content) {
  final tags = <String>{};
  for (final match in RegExp(
    r'(?<![\w/])#([A-Za-z0-9_-]+)',
  ).allMatches(content)) {
    final tag = match.group(1);
    if (tag != null) tags.add(tag);
  }
  return tags.toList()..sort();
}
