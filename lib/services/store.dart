import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/note.dart';
import '../models/saved_view.dart';
import '../models/space.dart';

class LocalData {
  final List<Note> notes;
  final Set<String> widgetIds;
  final List<SavedView> savedViews;
  final List<MemoSpace> spaces;
  final bool? spacesSupported;

  LocalData(
    this.notes,
    this.widgetIds,
    this.savedViews,
    this.spaces,
    this.spacesSupported,
  );
}

class LocalStore {
  Future<void> _queue = Future<void>.value();
  Database? _database;

  Future<Directory> attachmentsDirectory() async {
    final directory = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'attachments'),
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _pendingDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'pending_attachments'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<Database> _db() async {
    if (_database != null) return _database!;
    final directory = await getApplicationDocumentsDirectory();
    final database = await openDatabase(
      p.join(directory.path, 'notiz_app.sqlite'),
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA busy_timeout = 10000');
        await db.execute('PRAGMA journal_mode = WAL');
      },
      onCreate: _createSchema,
    );
    _database = database;
    return database;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute(
      'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        server_updated_at TEXT,
        pinned INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL DEFAULT 'normal',
        visibility TEXT NOT NULL DEFAULT 'PRIVATE',
        visibility_before_space TEXT,
        space TEXT,
        tags_json TEXT NOT NULL DEFAULT '[]',
        location_json TEXT,
        dirty_fields_json TEXT NOT NULL DEFAULT '[]',
        local_revision INTEGER NOT NULL DEFAULT 0,
        server_revision TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        last_sync_attempt_at TEXT,
        last_sync_error TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_uid TEXT UNIQUE,
        note_id TEXT NOT NULL,
        filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        local_path TEXT,
        sha256 TEXT,
        transfer_status TEXT NOT NULL DEFAULT 'missing',
        storage_type TEXT NOT NULL DEFAULT 'LOCAL',
        last_used_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_attachments_note ON attachments(note_id)',
    );
    await db.execute(
      'CREATE INDEX idx_attachments_status ON attachments(transfer_status)',
    );
    await db.execute('''
      CREATE TABLE pending_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id TEXT NOT NULL,
        local_path TEXT NOT NULL,
        filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        sha256 TEXT,
        upload_status TEXT NOT NULL DEFAULT 'pending',
        uploaded_uid TEXT,
        upload_attempt_count INTEGER NOT NULL DEFAULT 0,
        last_attempt_at TEXT,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE relations (
        memo_id TEXT NOT NULL,
        related_memo_id TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'REFERENCE',
        memo_snippet TEXT,
        related_memo_snippet TEXT,
        PRIMARY KEY(memo_id, related_memo_id, type),
        FOREIGN KEY(memo_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE TABLE saved_views (id TEXT PRIMARY KEY, data_json TEXT NOT NULL, updated_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE spaces (name TEXT PRIMARY KEY, data_json TEXT NOT NULL, updated_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE widget_ids (note_id TEXT PRIMARY KEY, FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE)',
    );
    await db.execute(
      'CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT, updated_at TEXT NOT NULL)',
    );
  }

  Future<LocalData> load() async {
    final db = await _db();
    final notes = <Note>[];
    for (final row in await db.query('notes')) {
      final id = row['id'] as String;
      final attachments = await db.query(
        'attachments',
        where: 'note_id = ?',
        whereArgs: [id],
      );
      final pending = await db.query(
        'pending_attachments',
        where: 'note_id = ?',
        whereArgs: [id],
      );
      final relations = await db.query(
        'relations',
        where: 'memo_id = ?',
        whereArgs: [id],
      );
      final location = row['location_json'] as String?;
      notes.add(
        Note(
          id: id,
          content: row['content'] as String,
          updated: DateTime.parse(row['updated_at'] as String),
          pinned: row['pinned'] == 1,
          dirty: row['dirty'] == 1,
          deleted: row['deleted'] == 1,
          state: row['state'] == 'archived'
              ? NoteState.archived
              : NoteState.normal,
          visibility: row['visibility'] as String,
          visibilityBeforeSpace: row['visibility_before_space'] as String?,
          space: row['space'] as String?,
          tags: (jsonDecode(row['tags_json'] as String) as List)
              .whereType<String>()
              .toList(),
          attachments: attachments
              .map(
                (value) => NoteAttachment(
                  name: value['server_uid'] as String? ?? '',
                  filename: value['filename'] as String,
                  type: value['mime_type'] as String,
                  size: value['size'] as int,
                ),
              )
              .toList(),
          pendingAttachments: pending
              .map(
                (value) => PendingAttachment(
                  path: value['local_path'] as String,
                  filename: value['filename'] as String,
                  type: value['mime_type'] as String,
                  size: value['size'] as int,
                  uploadedName: value['uploaded_uid'] as String?,
                ),
              )
              .toList(),
          relations: relations
              .map(
                (value) => MemoRelation(
                  memoId: value['memo_id'] as String,
                  relatedMemoId: value['related_memo_id'] as String,
                  type: value['type'] as String,
                  memoSnippet: value['memo_snippet'] as String?,
                  relatedMemoSnippet: value['related_memo_snippet'] as String?,
                ),
              )
              .toList(),
          location: location == null
              ? null
              : NoteLocation.fromJson(
                  jsonDecode(location) as Map<String, dynamic>,
                ),
          dirtyFields: (jsonDecode(row['dirty_fields_json'] as String) as List)
              .whereType<String>()
              .toSet(),
        ),
      );
    }
    final widgetRows = await db.query('widget_ids');
    final viewRows = await db.query('saved_views');
    final spaceRows = await db.query('spaces');
    return LocalData(
      notes,
      {for (final row in widgetRows) row['note_id'] as String},
      [
        for (final row in viewRows)
          SavedView.fromJson(
            jsonDecode(row['data_json'] as String) as Map<String, dynamic>,
          ),
      ],
      [
        for (final row in spaceRows)
          MemoSpace.fromJson(
            jsonDecode(row['data_json'] as String) as Map<String, dynamic>,
          ),
      ],
      await _getBoolSyncState(db, 'spacesSupported'),
    );
  }

  Future<bool?> _getBoolSyncState(Database db, String key) async {
    final rows = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty || rows.first['value'] == null) return null;
    return rows.first['value'] == 'true';
  }

  Future<void> save(
    List<Note> notes,
    Set<String> widgetIds,
    List<SavedView> savedViews,
    List<MemoSpace> spaces,
    bool? spacesSupported,
  ) {
    final snapshot = <String, dynamic>{
      'notes': notes.map((note) => note.toJson()).toList(),
      'widgetIds': widgetIds.toList(),
      'savedViews': savedViews.map((view) => view.toJson()).toList(),
      'spaces': spaces.map((space) => space.toJson()).toList(),
      'spacesSupported': spacesSupported,
    };
    final result = _queue.then((_) async => _writeData(await _db(), snapshot));
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<String> _fileChecksum(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _writeData(Database db, Map<String, dynamic> data) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final noteRecords = data['noteRecords'] as List?;
    final attachmentRecords = data['attachmentRecords'] as List?;
    final pendingRecords = data['pendingRecords'] as List?;
    final cachedNotes = <String, Map<String, Object?>>{};
    for (final row in await db.query('notes')) {
      cachedNotes[row['id'] as String] = row;
    }
    final cachedAttachments = <String, Map<String, Object?>>{};
    for (final row in await db.query('attachments')) {
      final uid = row['server_uid'] as String?;
      if (uid != null) cachedAttachments[uid] = row;
    }
    final cachedPending = <String, Map<String, Object?>>{};
    for (final row in await db.query('pending_attachments')) {
      cachedPending[row['local_path'] as String] = row;
    }

    await db.transaction((tx) async {
      await tx.delete('widget_ids');
      await tx.delete('saved_views');
      await tx.delete('spaces');
      await tx.delete('relations');
      await tx.delete('pending_attachments');
      await tx.delete('attachments');
      await tx.delete('notes');
      if (data.containsKey('syncState')) await tx.delete('sync_state');

      for (final view in data['savedViews'] as List? ?? const []) {
        final value = view as Map<String, dynamic>;
        await tx.insert('saved_views', {
          'id': value['id'],
          'data_json': jsonEncode(value),
          'updated_at': now,
        });
      }
      for (final space in data['spaces'] as List? ?? const []) {
        final value = space as Map<String, dynamic>;
        await tx.insert('spaces', {
          'name': value['name'],
          'data_json': jsonEncode(value),
          'updated_at': now,
        });
      }
      if (!data.containsKey('syncState')) {
        await tx.insert('sync_state', {
          'key': 'spacesSupported',
          'value': data['spacesSupported']?.toString(),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final validNoteIds = <String>{};
      for (final value in data['notes'] as List? ?? const []) {
        final note = value as Map<String, dynamic>;
        final id = note['id'] as String;
        validNoteIds.add(id);
        if (noteRecords == null) {
          final cached = cachedNotes[id];
          await tx.insert('notes', {
            'id': id,
            'content': note['content'] as String? ?? '',
            'created_at': cached?['created_at'] ?? now,
            'updated_at': note['updated'] as String? ?? now,
            'server_updated_at': cached?['server_updated_at'],
            'pinned': note['pinned'] == true ? 1 : 0,
            'dirty': note['dirty'] == true ? 1 : 0,
            'deleted': note['deleted'] == true ? 1 : 0,
            'state': note['state'] as String? ?? 'normal',
            'visibility': note['visibility'] as String? ?? 'PRIVATE',
            'visibility_before_space': note['visibilityBeforeSpace'],
            'space': note['space'],
            'tags_json': jsonEncode(note['tags'] ?? const []),
            'location_json': note['location'] == null
                ? null
                : jsonEncode(note['location']),
            'dirty_fields_json': jsonEncode(note['dirtyFields'] ?? const []),
            'local_revision': (cached?['local_revision'] as int? ?? 0) + 1,
            'server_revision': cached?['server_revision'],
            'sync_status': note['dirty'] == true
                ? 'pending'
                : (cached?['sync_status'] ?? 'synced'),
            'last_sync_attempt_at': cached?['last_sync_attempt_at'],
            'last_sync_error': cached?['last_sync_error'],
          });
        }

        if (attachmentRecords == null) {
          for (final attachment in note['attachments'] as List? ?? const []) {
            final value = attachment as Map<String, dynamic>;
            final uid = value['name'] as String? ?? '';
            final cached = uid.isEmpty ? null : cachedAttachments[uid];
            await tx.insert('attachments', {
              'server_uid': uid.isEmpty ? null : uid,
              'note_id': id,
              'filename': value['filename'] as String? ?? 'Anhang',
              'mime_type':
                  value['type'] as String? ?? 'application/octet-stream',
              'size': value['size'] as int? ?? 0,
              'local_path': cached?['local_path'],
              'sha256': cached?['sha256'],
              'transfer_status': uid.isEmpty
                  ? 'missing'
                  : (cached?['transfer_status'] ?? 'remote'),
              'last_used_at': cached?['last_used_at'],
              'storage_type': 'LOCAL',
              'created_at': now,
              'updated_at': now,
            });
          }
        }
        if (pendingRecords == null) {
          for (final pending
              in note['pendingAttachments'] as List? ?? const []) {
            final value = pending as Map<String, dynamic>;
            final localPath = value['path'] as String;
            final cached = cachedPending[localPath];
            final file = File(localPath);
            final checksum = await file.exists()
                ? await _fileChecksum(file)
                : cached?['sha256'];
            await tx.insert('pending_attachments', {
              'note_id': id,
              'local_path': localPath,
              'filename': value['filename'] as String? ?? 'Anhang',
              'mime_type':
                  value['type'] as String? ?? 'application/octet-stream',
              'size': value['size'] as int? ?? 0,
              'sha256': checksum,
              'upload_status': cached?['upload_status'] ?? 'pending',
              'uploaded_uid': value['uploadedName'],
              'upload_attempt_count': cached?['upload_attempt_count'] ?? 0,
              'last_attempt_at': cached?['last_attempt_at'],
              'last_error': cached?['last_error'],
              'created_at': now,
              'updated_at': now,
            });
          }
        }
        for (final relation in note['relations'] as List? ?? const []) {
          final value = relation as Map<String, dynamic>;
          await tx.insert('relations', {
            'memo_id': value['memoId'],
            'related_memo_id': value['relatedMemoId'],
            'type': value['type'] as String? ?? 'REFERENCE',
            'memo_snippet': value['memoSnippet'],
            'related_memo_snippet': value['relatedMemoSnippet'],
          });
        }
      }

      if (noteRecords != null) {
        for (final row in noteRecords) {
          await tx.insert('notes', Map<String, Object?>.from(row as Map));
        }
      }
      if (attachmentRecords != null) {
        for (final row in attachmentRecords) {
          final value = Map<String, Object?>.from(row as Map);
          if (!validNoteIds.contains(value['note_id'])) {
            throw const FormatException(
              'Anhang verweist auf eine fehlende Notiz.',
            );
          }
          await tx.insert('attachments', value);
        }
      }
      if (pendingRecords != null) {
        for (final row in pendingRecords) {
          final value = Map<String, Object?>.from(row as Map);
          if (!validNoteIds.contains(value['note_id'])) {
            throw const FormatException(
              'Upload verweist auf eine fehlende Notiz.',
            );
          }
          await tx.insert('pending_attachments', value);
        }
      }
      for (final id in data['widgetIds'] as List? ?? const []) {
        if (validNoteIds.contains(id)) {
          await tx.insert('widget_ids', {'note_id': id});
        }
      }
      if (data.containsKey('syncState')) {
        for (final row in data['syncState'] as List? ?? const []) {
          await tx.insert(
            'sync_state',
            Map<String, Object?>.from(row as Map),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<File> createBackupArchive() async {
    await _queue;
    final db = await _db();
    final local = await load();
    final attachmentRows = await db.query('attachments');
    final pendingRows = await db.query('pending_attachments');
    final pendingIdByPath = {
      for (final row in pendingRows)
        row['local_path'] as String: row['id'] as int,
    };
    final backupFiles = <Map<String, dynamic>>[];
    final dataNotes = local.notes.map((note) {
      final value = note.toJson();
      for (final raw in value['pendingAttachments'] as List) {
        final item = raw as Map<String, dynamic>;
        final id = pendingIdByPath[item['path']];
        if (id == null) {
          throw StateError(
            'Upload-Anhang ist nicht in der lokalen Datenbank registriert.',
          );
        }
        item['path'] = 'pending:$id';
      }
      return value;
    }).toList();

    final safeAttachmentRows = <Map<String, dynamic>>[];
    for (final row in attachmentRows) {
      final value = Map<String, dynamic>.from(row);
      final path = value['local_path'] as String?;
      if (path != null && await File(path).exists()) {
        final file = File(path);
        final size = await file.length();
        if (size > 100 * 1024 * 1024) {
          throw FileSystemException(
            'Ein lokaler Anhang überschreitet 100 MB.',
            path,
          );
        }
        final entry = 'files/attachment-${value['id']}.bin';
        final checksum = await _fileChecksum(file);
        value['local_path'] = 'bundle:$entry';
        value['sha256'] = checksum;
        backupFiles.add({
          'table': 'attachments',
          'id': value['id'],
          'entry': entry,
          'sha256': checksum,
          'size': size,
        });
      } else {
        value['local_path'] = null;
        if (value['transfer_status'] == 'downloaded') {
          value['transfer_status'] = 'remote';
        }
      }
      safeAttachmentRows.add(value);
    }
    final safePendingRows = <Map<String, dynamic>>[];
    for (final row in pendingRows) {
      final value = Map<String, dynamic>.from(row);
      final path = value['local_path'] as String;
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException(
          'Ein noch nicht hochgeladener Anhang fehlt; Backup wurde abgebrochen.',
          path,
        );
      }
      final id = value['id'] as int;
      final entry = 'files/pending-$id.bin';
      final checksum = await _fileChecksum(file);
      final size = await file.length();
      if (size > 100 * 1024 * 1024) {
        throw FileSystemException(
          'Ein ausstehender Anhang überschreitet 100 MB.',
          path,
        );
      }
      value['local_path'] = 'pending:$id';
      value['sha256'] = checksum;
      backupFiles.add({
        'table': 'pending_attachments',
        'id': id,
        'entry': entry,
        'sha256': checksum,
        'size': size,
      });
      safePendingRows.add(value);
    }

    final data = <String, dynamic>{
      'formatVersion': 1,
      'notes': dataNotes,
      'noteRecords': await db.query('notes'),
      'widgetIds': local.widgetIds.toList(),
      'savedViews': local.savedViews.map((view) => view.toJson()).toList(),
      'spaces': local.spaces.map((space) => space.toJson()).toList(),
      'spacesSupported': local.spacesSupported,
      'attachmentRecords': safeAttachmentRows,
      'pendingRecords': safePendingRows,
      'syncState': await db.query('sync_state'),
    };
    final dataBytes = utf8.encode(jsonEncode(data));
    final totalBytes = backupFiles.fold<int>(
      dataBytes.length,
      (total, file) => total + (file['size'] as int),
    );
    if (totalBytes > 2 * 1024 * 1024 * 1024) {
      throw const FormatException('Das Backup wäre größer als 2 GB.');
    }
    final manifest = <String, dynamic>{
      'format': 'notiz_app_backup',
      'formatVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'dataSha256': sha256.convert(dataBytes).toString(),
      'files': backupFiles,
    };
    final temp = await getTemporaryDirectory();
    final output = File(
      p.join(
        temp.path,
        'notiz_app_backup_${DateTime.now().microsecondsSinceEpoch}.zip',
      ),
    );
    final encoder = ZipFileEncoder();
    encoder.create(output.path);
    try {
      encoder.addArchiveFile(
        ArchiveFile.string('manifest.json', jsonEncode(manifest)),
      );
      encoder.addArchiveFile(
        ArchiveFile('data.json', dataBytes.length, dataBytes),
      );
      for (final item in backupFiles) {
        final table = item['table'] as String;
        final id = item['id'] as int;
        final rows = table == 'attachments' ? attachmentRows : pendingRows;
        final row = rows.firstWhere((candidate) => candidate['id'] == id);
        await encoder.addFile(
          File(row['local_path'] as String),
          item['entry'] as String,
          ZipFileEncoder.store,
        );
      }
      await encoder.close();
      return output;
    } catch (_) {
      await output.delete().catchError((Object _) => output);
      rethrow;
    }
  }

  Future<void> importBackup(File archiveFile) async {
    await _queue;
    if (await archiveFile.length() > 2 * 1024 * 1024 * 1024) {
      throw const FormatException('Das Backup ist größer als 2 GB.');
    }
    final input = InputFileStream(archiveFile.path);
    try {
      final archive = ZipDecoder().decodeStream(input, verify: true);
      final entries = <String, ArchiveFile>{};
      var uncompressedSize = 0;
      for (final entry in archive.files) {
        if (!entry.isFile ||
            entry.name.startsWith('/') ||
            entry.name.contains(r'\') ||
            entry.name.split('/').contains('..')) {
          throw const FormatException(
            'Das Backup enthält ungültige Dateipfade.',
          );
        }
        uncompressedSize += entry.size;
        if (uncompressedSize > 2 * 1024 * 1024 * 1024) {
          throw const FormatException(
            'Das entpackte Backup ist größer als 2 GB.',
          );
        }
        if (entries.containsKey(entry.name)) {
          throw const FormatException('Das Backup enthält doppelte Einträge.');
        }
        entries[entry.name] = entry;
      }
      final manifestFile = entries['manifest.json'];
      final dataFile = entries['data.json'];
      if (manifestFile == null ||
          dataFile == null ||
          manifestFile.size > 1024 * 1024 ||
          dataFile.size > 100 * 1024 * 1024) {
        throw const FormatException(
          'Das Backup ist unvollständig oder ungültig.',
        );
      }
      final manifest =
          jsonDecode(utf8.decode(manifestFile.content)) as Map<String, dynamic>;
      if (manifest['format'] != 'notiz_app_backup' ||
          manifest['formatVersion'] != 1) {
        throw const FormatException(
          'Dieses Backupformat wird nicht unterstützt.',
        );
      }
      final dataBytes = dataFile.content;
      if (sha256.convert(dataBytes).toString() != manifest['dataSha256']) {
        throw const FormatException(
          'Die Daten-Prüfsumme des Backups stimmt nicht.',
        );
      }
      final data = jsonDecode(utf8.decode(dataBytes)) as Map<String, dynamic>;
      if (data['formatVersion'] != 1 ||
          data['notes'] is! List ||
          data['widgetIds'] is! List ||
          data['savedViews'] is! List ||
          data['spaces'] is! List ||
          data['attachmentRecords'] is! List ||
          data['pendingRecords'] is! List) {
        throw const FormatException('Die Backupdaten sind ungültig.');
      }

      final temp = await getTemporaryDirectory();
      final staging = await Directory(
        p.join(
          temp.path,
          'notiz_import_${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create();
      final extracted = <String, File>{};
      final createdFiles = <File>[];
      var committed = false;
      try {
        final listedEntries = <String>{'manifest.json', 'data.json'};
        for (final raw in manifest['files'] as List? ?? const []) {
          final item = raw as Map<String, dynamic>;
          final table = item['table'];
          final id = item['id'];
          final expectedName = table == 'attachments'
              ? 'files/attachment-$id.bin'
              : 'files/pending-$id.bin';
          final entryName = item['entry'];
          if ((table != 'attachments' && table != 'pending_attachments') ||
              id is! int ||
              entryName != expectedName ||
              !listedEntries.add(entryName as String)) {
            throw const FormatException(
              'Ein Anhangverweis im Backup ist ungültig.',
            );
          }
          final entry = entries[entryName];
          if (entry == null ||
              entry.size > 100 * 1024 * 1024 ||
              entry.size != item['size']) {
            throw const FormatException(
              'Ein Anhang im Backup fehlt oder ist zu groß.',
            );
          }
          final file = File(p.join(staging.path, '${table}_$id.bin'));
          await file.writeAsBytes(entry.content, flush: true);
          if (await _fileChecksum(file) != item['sha256']) {
            throw const FormatException(
              'Die Prüfsumme eines Anhangs stimmt nicht.',
            );
          }
          extracted[entryName] = file;
        }
        if (entries.keys.any((name) => !listedEntries.contains(name))) {
          throw const FormatException(
            'Das Backup enthält nicht deklarierte Dateien.',
          );
        }

        final attachmentDirectory = await attachmentsDirectory();
        final pendingDirectory = await _pendingDirectory();
        final attachmentRecords = <Map<String, dynamic>>[];
        for (final raw in data['attachmentRecords'] as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final bundlePath = row['local_path'] as String?;
          if (bundlePath != null) {
            if (!bundlePath.startsWith('bundle:')) {
              throw const FormatException(
                'Ein Anhangpfad im Backup ist ungültig.',
              );
            }
            final stagedFile =
                extracted[bundlePath.substring('bundle:'.length)];
            if (stagedFile == null) {
              throw const FormatException(
                'Eine lokale Anhangdatei fehlt im Backup.',
              );
            }
            final destination = File(
              p.join(
                attachmentDirectory.path,
                'restored-${row['id']}-${DateTime.now().microsecondsSinceEpoch}.bin',
              ),
            );
            await stagedFile.copy(destination.path);
            createdFiles.add(destination);
            row['local_path'] = destination.path;
          }
          attachmentRecords.add(row);
        }

        final pendingRecords = <Map<String, dynamic>>[];
        final pendingPathById = <int, String>{};
        for (final raw in data['pendingRecords'] as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final id = row['id'] as int;
          if (row['local_path'] != 'pending:$id') {
            throw const FormatException(
              'Ein Upload-Pfad im Backup ist ungültig.',
            );
          }
          final stagedFile = extracted['files/pending-$id.bin'];
          if (stagedFile == null) {
            throw const FormatException(
              'Ein ausstehender Anhang fehlt im Backup.',
            );
          }
          final filename = p.basename(row['filename'] as String);
          final destination = File(
            p.join(
              pendingDirectory.path,
              'restored-$id-${DateTime.now().microsecondsSinceEpoch}-$filename',
            ),
          );
          await stagedFile.copy(destination.path);
          createdFiles.add(destination);
          row['local_path'] = destination.path;
          pendingPathById[id] = destination.path;
          pendingRecords.add(row);
        }

        final notes = <Map<String, dynamic>>[];
        for (final raw in data['notes'] as List) {
          final note = Map<String, dynamic>.from(raw as Map);
          for (final rawPending
              in note['pendingAttachments'] as List? ?? const []) {
            final pending = rawPending as Map<String, dynamic>;
            final token = pending['path'] as String;
            if (!token.startsWith('pending:')) {
              throw const FormatException(
                'Ein Upload-Pfad im Backup ist ungültig.',
              );
            }
            final id = int.tryParse(token.substring('pending:'.length));
            final path = id == null ? null : pendingPathById[id];
            if (path == null) {
              throw const FormatException(
                'Ein Upload-Anhang ist nicht zugeordnet.',
              );
            }
            pending['path'] = path;
          }
          notes.add(note);
        }

        await _writeData(await _db(), {
          ...data,
          'notes': notes,
          'noteRecords': data['noteRecords'] as List? ?? const [],
          'attachmentRecords': attachmentRecords,
          'pendingRecords': pendingRecords,
        });
        committed = true;
        await _cleanupUnreferencedFiles();
      } catch (_) {
        if (!committed) {
          for (final file in createdFiles) {
            if (await file.exists()) await file.delete();
          }
        }
        rethrow;
      } finally {
        await staging.delete(recursive: true);
      }
    } finally {
      input.closeSync();
    }
  }

  Future<void> _cleanupUnreferencedFiles() async {
    final db = await _db();
    final attachmentPaths = {
      for (final row in await db.query(
        'attachments',
        columns: ['local_path'],
        where: 'local_path IS NOT NULL',
      ))
        row['local_path'] as String,
    };
    final pendingPaths = {
      for (final row in await db.query(
        'pending_attachments',
        columns: ['local_path'],
      ))
        row['local_path'] as String,
    };
    for (final directoryAndPaths in [
      (await attachmentsDirectory(), attachmentPaths),
      (await _pendingDirectory(), pendingPaths),
    ]) {
      await for (final entity in directoryAndPaths.$1.list()) {
        if (entity is File && !directoryAndPaths.$2.contains(entity.path)) {
          await entity.delete();
        }
      }
    }
  }

  Future<void> setSyncState(String key, String value) async {
    final db = await _db();
    await db.insert('sync_state', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markNoteSynced(String id, {String? serverUpdatedAt}) async {
    final db = await _db();
    await db.update(
      'notes',
      {
        'dirty': 0,
        'sync_status': 'synced',
        'server_updated_at': serverUpdatedAt,
        'last_sync_attempt_at': DateTime.now().toUtc().toIso8601String(),
        'last_sync_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSyncAttempt(String id) async {
    final db = await _db();
    await db.update(
      'notes',
      {
        'sync_status': 'syncing',
        'last_sync_attempt_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSyncError(String id, String error) async {
    final db = await _db();
    await db.update(
      'notes',
      {
        'sync_status': 'error',
        'last_sync_attempt_at': DateTime.now().toUtc().toIso8601String(),
        'last_sync_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> cacheDownloadedAttachment(
    String serverUid,
    List<int> bytes,
  ) async {
    final safeUid = serverUid
        .split('/')
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(
      p.join((await attachmentsDirectory()).path, '$safeUid.bin'),
    );
    await file.writeAsBytes(bytes, flush: true);
    final now = DateTime.now().toUtc().toIso8601String();
    await (await _db()).update(
      'attachments',
      {
        'local_path': file.path,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'transfer_status': 'downloaded',
        'last_used_at': now,
        'updated_at': now,
      },
      where: 'server_uid = ? OR server_uid LIKE ?',
      whereArgs: [serverUid, '%/${serverUid.split('/').last}'],
    );
  }

  Future<String?> cachedAttachmentPath(String serverUid) async {
    final uid = serverUid.split('/').last;
    final db = await _db();
    final rows = await db.query(
      'attachments',
      columns: ['server_uid', 'local_path'],
      where: 'server_uid = ? OR server_uid LIKE ?',
      whereArgs: [serverUid, '%/$uid'],
    );
    if (rows.isEmpty) return null;
    final path = rows.first['local_path'] as String?;
    if (path == null || !await File(path).exists()) return null;
    await db.update(
      'attachments',
      {'last_used_at': DateTime.now().toUtc().toIso8601String()},
      where: 'server_uid = ?',
      whereArgs: [rows.first['server_uid']],
    );
    return path;
  }

  Future<void> pruneAttachments({
    Duration staleAfter = const Duration(days: 30),
  }) async {
    final db = await _db();
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(staleAfter)
        .toIso8601String();
    final rows = await db.query(
      'attachments',
      where:
          'transfer_status = ? AND (last_used_at IS NULL OR last_used_at < ?)',
      whereArgs: ['downloaded', cutoff],
    );
    await db.transaction((tx) async {
      for (final row in rows) {
        final path = row['local_path'] as String?;
        if (path != null) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
        await tx.update(
          'attachments',
          {
            'local_path': null,
            'sha256': null,
            'transfer_status': 'remote',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
    await _cleanupUnreferencedFiles();
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
