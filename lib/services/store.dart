import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/note.dart';
import '../models/saved_view.dart';
import '../models/space.dart';
import 'log.dart';

class LocalData {
  final List<Note> notes;
  final Set<String> widgetIds;
  final List<SavedView> savedViews;
  final List<MemoSpace> spaces;
  final bool? spacesSupported;
  final String? warning;

  LocalData(
    this.notes,
    this.widgetIds,
    this.savedViews,
    this.spaces,
    this.spacesSupported, {
    this.warning,
  });
}

class LocalStore {
  Future<void> _queue = Future<void>.value();
  Database? _database;

  Future<File> _named(String name) async =>
      File('${(await getApplicationDocumentsDirectory()).path}/$name');

  Future<Directory> attachmentsDirectory() async {
    final directory = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'attachments'),
    );
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
    await _migrateLegacyJson(database);
    return database;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
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
    await db.execute('CREATE INDEX idx_attachments_note ON attachments(note_id)');
    await db.execute('CREATE INDEX idx_attachments_status ON attachments(transfer_status)');
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
    await db.execute('CREATE TABLE saved_views (id TEXT PRIMARY KEY, data_json TEXT NOT NULL, updated_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE spaces (name TEXT PRIMARY KEY, data_json TEXT NOT NULL, updated_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE widget_ids (note_id TEXT PRIMARY KEY, FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT, updated_at TEXT NOT NULL)');
  }

  Future<LocalData?> _readLegacy(File file) async {
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return LocalData(
        [
          for (final value in json['notes'] as List? ?? const [])
            Note.fromJson(value as Map<String, dynamic>),
        ],
        {...List<String>.from(json['widgetIds'] ?? const [])},
        [
          for (final value in json['savedViews'] as List? ?? const [])
            SavedView.fromJson(value as Map<String, dynamic>),
        ],
        [
          for (final value in json['spaces'] as List? ?? const [])
            MemoSpace.fromJson(value as Map<String, dynamic>),
        ],
        json['spacesSupported'] as bool?,
      );
    } catch (error) {
      await file.rename('${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      await LogService.log('Beschadigte JSON-Daten gesichert: $error');
      return null;
    }
  }

  Future<void> _migrateLegacyJson(Database db) async {
    final migrated = await db.query('meta', where: 'key = ?', whereArgs: ['legacy_json_migrated']);
    if (migrated.isNotEmpty) return;
    final candidates = [
      await _named('notes.json'),
      await _named('notes.json.tmp'),
      await _named('notes.json.bak'),
    ];
    File? source;
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        source = candidate;
        break;
      }
    }
    if (source != null) {
      final legacy = await _readLegacy(source);
      if (legacy != null) {
        await _writeData(db, {
          'notes': legacy.notes.map((note) => note.toJson()).toList(),
          'widgetIds': legacy.widgetIds.toList(),
          'savedViews': legacy.savedViews.map((view) => view.toJson()).toList(),
          'spaces': legacy.spaces.map((space) => space.toJson()).toList(),
          'spacesSupported': legacy.spacesSupported,
        });
        await source.rename('${source.path}.imported-${DateTime.now().millisecondsSinceEpoch}');
      }
    }
    await db.insert('meta', {'key': 'legacy_json_migrated', 'value': '1'});
  }

  Future<LocalData> load() async {
    final db = await _db();
    final notes = <Note>[];
    for (final row in await db.query('notes')) {
      final id = row['id'] as String;
      final attachments = await db.query('attachments', where: 'note_id = ?', whereArgs: [id]);
      final pending = await db.query('pending_attachments', where: 'note_id = ?', whereArgs: [id]);
      final relations = await db.query('relations', where: 'memo_id = ?', whereArgs: [id]);
      final location = row['location_json'] as String?;
      notes.add(Note(
        id: id,
        content: row['content'] as String,
        updated: DateTime.parse(row['updated_at'] as String),
        pinned: row['pinned'] == 1,
        dirty: row['dirty'] == 1,
        deleted: row['deleted'] == 1,
        state: row['state'] == 'archived' ? NoteState.archived : NoteState.normal,
        visibility: row['visibility'] as String,
        visibilityBeforeSpace: row['visibility_before_space'] as String?,
        space: row['space'] as String?,
        tags: (jsonDecode(row['tags_json'] as String) as List).whereType<String>().toList(),
        attachments: attachments.map((value) => NoteAttachment(
          name: value['server_uid'] as String? ?? '',
          filename: value['filename'] as String,
          type: value['mime_type'] as String,
          size: value['size'] as int,
        )).toList(),
        pendingAttachments: pending.map((value) => PendingAttachment(
          path: value['local_path'] as String,
          filename: value['filename'] as String,
          type: value['mime_type'] as String,
          size: value['size'] as int,
          uploadedName: value['uploaded_uid'] as String?,
        )).toList(),
        relations: relations.map((value) => MemoRelation(
          memoId: value['memo_id'] as String,
          relatedMemoId: value['related_memo_id'] as String,
          type: value['type'] as String,
          memoSnippet: value['memo_snippet'] as String?,
          relatedMemoSnippet: value['related_memo_snippet'] as String?,
        )).toList(),
        location: location == null ? null : NoteLocation.fromJson(jsonDecode(location) as Map<String, dynamic>),
        dirtyFields: (jsonDecode(row['dirty_fields_json'] as String) as List).whereType<String>().toSet(),
      ));
    }
    final widgetRows = await db.query('widget_ids');
    final viewRows = await db.query('saved_views');
    final spaceRows = await db.query('spaces');
    return LocalData(
      notes,
      {for (final row in widgetRows) row['note_id'] as String},
      [for (final row in viewRows) SavedView.fromJson(jsonDecode(row['data_json'] as String) as Map<String, dynamic>)],
      [for (final row in spaceRows) MemoSpace.fromJson(jsonDecode(row['data_json'] as String) as Map<String, dynamic>)],
      await _getBoolSyncState(db, 'spacesSupported'),
    );
  }

  Future<bool?> _getBoolSyncState(Database db, String key) async {
    final row = await db.query('sync_state', where: 'key = ?', whereArgs: [key]);
    if (row.isEmpty || row.first['value'] == null) return null;
    return row.first['value'] == 'true';
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

  Future<void> _writeData(Database db, Map<String, dynamic> data) async {
    final now = DateTime.now().toUtc().toIso8601String();
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

      for (final id in data['widgetIds'] as List) {
        await tx.insert('widget_ids', {'note_id': id});
      }
      for (final view in data['savedViews'] as List) {
        final value = view as Map<String, dynamic>;
        await tx.insert('saved_views', {'id': value['id'], 'data_json': jsonEncode(value), 'updated_at': now});
      }
      for (final space in data['spaces'] as List) {
        final value = space as Map<String, dynamic>;
        await tx.insert('spaces', {'name': value['name'], 'data_json': jsonEncode(value), 'updated_at': now});
      }
      await tx.insert('sync_state', {
        'key': 'spacesSupported',
        'value': data['spacesSupported']?.toString(),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final value in data['notes'] as List) {
        final note = value as Map<String, dynamic>;
        final id = note['id'] as String;
        await tx.insert('notes', {
          'id': id,
          'content': note['content'] as String? ?? '',
          'created_at': now,
          'updated_at': note['updated'] as String? ?? now,
          'server_updated_at': note['updated'] as String?,
          'pinned': note['pinned'] == true ? 1 : 0,
          'dirty': note['dirty'] == true ? 1 : 0,
          'deleted': note['deleted'] == true ? 1 : 0,
          'state': note['state'] as String? ?? 'normal',
          'visibility': note['visibility'] as String? ?? 'PRIVATE',
          'visibility_before_space': note['visibilityBeforeSpace'],
          'space': note['space'],
          'tags_json': jsonEncode(note['tags'] ?? const []),
          'location_json': note['location'] == null ? null : jsonEncode(note['location']),
          'dirty_fields_json': jsonEncode(note['dirtyFields'] ?? const []),
          'local_revision': 1,
          'sync_status': note['dirty'] == true ? 'pending' : 'synced',
        });

        for (final attachment in note['attachments'] as List? ?? const []) {
          final value = attachment as Map<String, dynamic>;
          final uid = value['name'] as String? ?? '';
          final cached = uid.isEmpty ? null : cachedAttachments[uid];
          await tx.insert('attachments', {
            'server_uid': uid.isEmpty ? null : uid,
            'note_id': id,
            'filename': value['filename'] as String? ?? 'Anhang',
            'mime_type': value['type'] as String? ?? 'application/octet-stream',
            'size': value['size'] as int? ?? 0,
            'local_path': cached?['local_path'],
            'sha256': cached?['sha256'],
            'transfer_status':
                uid.isEmpty ? 'missing' : (cached?['transfer_status'] ?? 'remote'),
            'last_used_at': cached?['last_used_at'],
            'storage_type': 'LOCAL',
            'created_at': now,
            'updated_at': now,
          });
        }
        for (final pending in note['pendingAttachments'] as List? ?? const []) {
          final value = pending as Map<String, dynamic>;
          final localPath = value['path'] as String;
          final cached = cachedPending[localPath];
          String? checksum;
          try {
            final file = File(localPath);
            if (await file.exists()) checksum = sha256.convert(await file.readAsBytes()).toString();
          } catch (_) {}
          await tx.insert('pending_attachments', {
            'note_id': id,
            'local_path': localPath,
            'filename': value['filename'] as String? ?? 'Anhang',
            'mime_type': value['type'] as String? ?? 'application/octet-stream',
            'size': value['size'] as int? ?? 0,
            'sha256': checksum ?? cached?['sha256'],
            'upload_status': cached?['upload_status'] ?? 'pending',
            'uploaded_uid': value['uploadedName'],
            'upload_attempt_count': cached?['upload_attempt_count'] ?? 0,
            'last_attempt_at': cached?['last_attempt_at'],
            'last_error': cached?['last_error'],
            'created_at': now,
            'updated_at': now,
          });
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
    });
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
    await db.update('notes', {
      'dirty': 0,
      'sync_status': 'synced',
      'server_updated_at': serverUpdatedAt,
      'last_sync_attempt_at': DateTime.now().toUtc().toIso8601String(),
      'last_sync_error': null,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markSyncAttempt(String id) async {
    final db = await _db();
    await db.update('notes', {
      'sync_status': 'syncing',
      'last_sync_attempt_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markSyncError(String id, String error) async {
    final db = await _db();
    await db.update('notes', {
      'sync_status': 'error',
      'last_sync_attempt_at': DateTime.now().toUtc().toIso8601String(),
      'last_sync_error': error,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> cacheDownloadedAttachment(String serverUid, List<int> bytes) async {
    final file = File(p.join((await attachmentsDirectory()).path, '${serverUid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.bin'));
    await file.writeAsBytes(bytes, flush: true);
    final now = DateTime.now().toUtc().toIso8601String();
    await (await _db()).update('attachments', {
      'local_path': file.path,
      'size': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'transfer_status': 'downloaded',
      'last_used_at': now,
      'updated_at': now,
    }, where: 'server_uid = ?', whereArgs: [serverUid]);
  }

  Future<String?> cachedAttachmentPath(String serverUid) async {
    final rows = await (await _db()).query('attachments', columns: ['local_path'], where: 'server_uid = ?', whereArgs: [serverUid]);
    if (rows.isEmpty) return null;
    final path = rows.first['local_path'] as String?;
    return path != null && await File(path).exists() ? path : null;
  }

  Future<void> pruneAttachments({Duration staleAfter = const Duration(days: 30)}) async {
    final db = await _db();
    final cutoff = DateTime.now().toUtc().subtract(staleAfter).toIso8601String();
    final rows = await db.query(
      'attachments',
      where: 'transfer_status = ? AND (last_used_at IS NULL OR last_used_at < ?)',
      whereArgs: ['downloaded', cutoff],
    );
    await db.transaction((tx) async {
      for (final row in rows) {
        final path = row['local_path'] as String?;
        if (path != null) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
        await tx.update('attachments', {
          'local_path': null,
          'sha256': null,
          'transfer_status': 'remote',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, where: 'id = ?', whereArgs: [row['id']]);
      }
    });
    final referenced = await db.query(
      'attachments',
      where: 'local_path IS NOT NULL',
      whereArgs: [],
    );
    final referencedPaths = {
      for (final row in referenced) row['local_path'] as String,
    };
    final directory = await attachmentsDirectory();
    await for (final entity in directory.list()) {
      if (entity is File && !referencedPaths.contains(entity.path)) {
        await entity.delete();
      }
    }
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
