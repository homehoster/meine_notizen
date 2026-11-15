import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Schreibt Ereignisse nach Android/Downloads bzw. unter iOS in die App-Dokumente.
/// Alle Ereignisse werden an dieselbe Logdatei angehängt.
class LogService {
  static const _fileName = 'notizen.log';
  static const _androidChannel =
      MethodChannel('com.github.homehoster.meine_notizen/logs');
  static bool _enabled = true;

  static Directory? _dir;
  static Future<void> _writeQueue = Future<void>.value();

  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  static void function(String name) {
    unawaited(log('function=$name'));
  }

  static Future<Directory> _logDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'logs'));
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  static Future<void> log(String message) {
    debugPrint(message);
    if (!_enabled) return Future<void>.value();
    final next = _writeQueue.then((_) => _write(message));
    _writeQueue = next.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Fehler beim Schreiben des Logs: $error');
    });
    return _writeQueue;
  }

  static Future<void> _write(String message) async {
    try {
      final line = '[${DateTime.now().toIso8601String()}] $message\n';
      if (Platform.isAndroid) {
        await _androidChannel.invokeMethod<void>('appendLog', {'line': line});
      } else {
        final dir = await _logDir();
        final file = File(p.join(dir.path, _fileName));
        await file.writeAsString(line, mode: FileMode.append, encoding: utf8);
      }
    } catch (e) {
      debugPrint('Fehler beim Schreiben des Logs: $e');
    }
  }

  /// Vorhandene Logdateien (aktuelle zuerst).
  static Future<List<File>> logFiles() async {
    if (Platform.isAndroid) {
      final paths = await _androidChannel.invokeListMethod<String>(
        'readLogFiles',
      );
      return (paths ?? []).map(File.new).toList();
    }
    final dir = await _logDir();
    final file = File(p.join(dir.path, _fileName));
    if (await file.exists() && await file.length() > 0) return [file];
    return [];
  }

  /// Öffnet das Teilen-Menü mit den Logdateien.
  /// Gibt false zurück, wenn es noch keine Logs gibt.
  static Future<bool> share() async {
    final files = await logFiles();
    if (files.isEmpty) return false;
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Notizen Log',
        files: files.map((f) => XFile(f.path, mimeType: 'text/plain')).toList(),
      ),
    );
    return true;
  }
}
