import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Schreibt Ereignisse in eine app-private Logdatei (auf beiden Plattformen).
/// Die Datei ist von außen nicht lesbar und wird nur über [share] weitergegeben.
///
/// - Standardmäßig deaktiviert.
/// - Die Datei wird auf maximal 5 MB begrenzt; ältere Zeilen fallen weg.
/// - Zeilen werden gepuffert und in Blöcken geschrieben.
class LogService {
  static const _fileName = 'notizen.log';
  static const _maxBytes = 5 * 1024 * 1024;

  /// Größe nach dem Kürzen (Platz für neue Einträge, ohne sofort wieder zu kürzen).
  static const _keepBytes = 3 * 1024 * 1024;
  static const _flushDelay = Duration(seconds: 2);
  static const _flushLines = 50;

  static bool _enabled = false;
  static bool get enabled => _enabled;

  static File? _file;
  static int _size = -1;
  static final StringBuffer _buffer = StringBuffer();
  static int _bufferedLines = 0;
  static Timer? _timer;
  static Future<void> _writeQueue = Future<void>.value();

  static void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) unawaited(flush());
  }

  static void function(String name) {
    unawaited(log('function=$name'));
  }

  static Future<File> _logFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'logs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return _file = File(p.join(dir.path, _fileName));
  }

  static Future<void> log(String message) {
    // Im Release-Build nichts in Logcat ausgeben.
    if (kDebugMode) debugPrint(message);
    if (!_enabled) return Future<void>.value();
    _buffer.write('[${DateTime.now().toIso8601String()}] $message\n');
    if (++_bufferedLines >= _flushLines) return flush();
    _timer ??= Timer(_flushDelay, () => unawaited(flush()));
    return Future<void>.value();
  }

  /// Schreibt gepufferte Zeilen sofort in die Datei.
  static Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return _writeQueue;
    final text = _buffer.toString();
    _buffer.clear();
    _bufferedLines = 0;
    _writeQueue = _writeQueue.then((_) => _append(text)).catchError((Object e) {
      if (kDebugMode) debugPrint('Fehler beim Schreiben des Logs: $e');
    });
    return _writeQueue;
  }

  /// Löscht die Logdatei und alle noch nicht geschriebenen Einträge.
  static Future<void> clear() {
    _timer?.cancel();
    _timer = null;
    _buffer.clear();
    _bufferedLines = 0;
    _writeQueue = _writeQueue.then((_) async {
      final file = await _logFile();
      if (await file.exists()) await file.delete();
      _size = 0;
    });
    return _writeQueue;
  }

  static Future<void> _append(String text) async {
    final f = await _logFile();
    if (_size < 0) _size = await f.exists() ? await f.length() : 0;
    final bytes = utf8.encode(text);
    if (_size + bytes.length > _maxBytes) await _trim(f);
    await f.writeAsBytes(bytes, mode: FileMode.append);
    _size += bytes.length;
  }

  /// Behält nur die letzten [_keepBytes] (beginnend an einem Zeilenanfang).
  static Future<void> _trim(File f) async {
    final all = await f.readAsBytes();
    var start = all.length > _keepBytes ? all.length - _keepBytes : 0;
    final newline = all.indexOf(10, start);
    start = newline < 0 ? all.length : newline + 1;
    await f.writeAsBytes(all.sublist(start), flush: true);
    _size = all.length - start;
  }

  /// Öffnet das Teilen-Menü mit einer Kopie der Logdatei.
  /// Gibt false zurück, wenn es noch keine Logs gibt.
  static Future<bool> share() async {
    await flush();
    final f = await _logFile();
    if (!await f.exists() || await f.length() == 0) return false;
    // Kopie im Cache: sichere Quelle für den Share-Dialog, Original bleibt privat.
    final tmp = await getTemporaryDirectory();
    final copy = await f.copy(p.join(tmp.path, _fileName));
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Notizen Log',
        files: [XFile(copy.path, mimeType: 'text/plain')],
      ),
    );
    return true;
  }
}
