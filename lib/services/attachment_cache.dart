import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'log.dart';

/// Cache für Anhänge (vor allem Bilder): zuerst Arbeitsspeicher (LRU),
/// dann Festplatte (Cache-Ordner), erst danach wird der Server gefragt.
/// Gleichzeitige Anfragen für denselben Anhang teilen sich einen Download.
class AttachmentCache {
  AttachmentCache(this._download);

  static const _maxMemoryBytes = 32 * 1024 * 1024;
  static const _maxDiskBytes = 150 * 1024 * 1024;

  final Future<List<int>> Function(String name) _download;
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  final Map<String, Future<Uint8List>> _loading = {};
  int _memoryBytes = 0;
  Directory? _dir;

  Future<Uint8List> get(String name) {
    final hit = _memory.remove(name);
    if (hit != null) {
      _memory[name] = hit; // ans Ende = zuletzt benutzt
      return Future<Uint8List>.value(hit);
    }
    return _loading[name] ??= _load(name).whenComplete(
      () => _loading.remove(name),
    );
  }

  Future<Uint8List> _load(String name) async {
    final file = await _fileFor(name);
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _remember(name, bytes);
        return bytes;
      }
    } catch (e) {
      LogService.log('Cache lesen fehlgeschlagen ($name): $e');
    }
    final bytes = Uint8List.fromList(await _download(name));
    _remember(name, bytes);
    unawaited(_store(file, bytes));
    return bytes;
  }

  void _remember(String name, Uint8List bytes) {
    if (bytes.length > _maxMemoryBytes ~/ 2) return;
    final old = _memory.remove(name);
    if (old != null) _memoryBytes -= old.length;
    _memory[name] = bytes;
    _memoryBytes += bytes.length;
    while (_memoryBytes > _maxMemoryBytes && _memory.isNotEmpty) {
      final oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.length;
    }
  }

  Future<Directory> _directory() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'attachment_cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<File> _fileFor(String name) async {
    final dir = await _directory();
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File(p.join(dir.path, safe));
  }

  Future<void> _store(File file, Uint8List bytes) async {
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      await _trimDisk();
    } catch (e) {
      LogService.log('Cache schreiben fehlgeschlagen: $e');
    }
  }

  /// Löscht die ältesten Dateien, wenn der Cache zu groß wird.
  Future<void> _trimDisk() async {
    final dir = await _directory();
    final files = <File>[];
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        files.add(entity);
        total += await entity.length();
      }
    }
    if (total <= _maxDiskBytes) return;
    final dated = <File, DateTime>{
      for (final f in files) f: await f.lastModified(),
    };
    files.sort((a, b) => dated[a]!.compareTo(dated[b]!));
    for (final f in files) {
      if (total <= _maxDiskBytes * 0.8) break;
      total -= await f.length();
      await f.delete();
    }
  }

  /// Leert Speicher und Festplatte (z. B. beim Löschen der Zugangsdaten).
  Future<void> clear() async {
    _memory.clear();
    _memoryBytes = 0;
    try {
      final dir = await _directory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      LogService.log('Cache leeren fehlgeschlagen: $e');
    }
  }
}
