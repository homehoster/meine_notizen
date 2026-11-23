import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../services/log.dart';
import '../state/app_state.dart';
import '../widgets/app_version_text.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

final _schemeRe = RegExp(r'^(https?)://', caseSensitive: false);

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController url;
  late final TextEditingController token;
  late bool https;
  bool busy = false;
  bool clearingLog = false;
  bool backupBusy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    final saved = s.baseUrl.trim();
    https = !saved.toLowerCase().startsWith('http://');
    url = TextEditingController(text: saved.isEmpty ? 'https://' : saved);
    token = TextEditingController(text: s.token);
    url.addListener(_syncSwitchFromUrl);
  }

  @override
  void dispose() {
    url.dispose();
    token.dispose();
    super.dispose();
  }

  /// Wird das Schema direkt in der URL-Zeile geändert, folgt der Schalter.
  void _syncSwitchFromUrl() {
    final t = url.text.trim().toLowerCase();
    final next = t.startsWith('http://')
        ? false
        : t.startsWith('https://')
        ? true
        : https;
    if (next != https) setState(() => https = next);
  }

  /// Schalter umgelegt: Schema in der URL-Zeile ersetzen.
  void _setHttps(bool value) {
    final host = url.text.trim().replaceFirst(_schemeRe, '');
    setState(() => https = value);
    url.text = '${value ? 'https' : 'http'}://$host';
  }

  /// Ergänzt ein fehlendes Schema passend zum Schalter und vereinheitlicht es.
  String _withScheme(String raw) {
    final t = raw.replaceAll(RegExp(r'\s+'), '');
    if (_schemeRe.hasMatch(t)) {
      return t.replaceFirstMapped(
        _schemeRe,
        (m) => '${m[1]!.toLowerCase()}://',
      );
    }
    return '${https ? 'https' : 'http'}://$t';
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final msg = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      final u = _withScheme(url.text);
      await s.testConnection(u, token.text);
      await s.saveSettings(u, token.text);
      msg.showSnackBar(
        const SnackBar(content: Text('Verbunden & gespeichert')),
      );
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _clear() async {
    final s = context.read<AppState>();
    final msg = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zugangsdaten löschen?'),
        content: const Text(
          'Server-URL und Token werden von diesem Gerät entfernt. '
          'Lokal gespeicherte Notizen bleiben erhalten, werden aber nicht mehr synchronisiert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await s.clearServerSettings();
    if (!mounted) return;
    setState(() => https = true);
    url.text = 'https://';
    token.clear();
    msg.showSnackBar(
      const SnackBar(content: Text('Server-URL und Token gelöscht')),
    );
  }

  Future<void> _clearLog() async {
    final msg = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logdatei löschen?'),
        content: const Text(
          'Das gespeicherte Diagnoseprotokoll wird gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => clearingLog = true);
    try {
      await LogService.clear();
      if (mounted) {
        msg.showSnackBar(const SnackBar(content: Text('Logdatei gelöscht')));
      }
    } catch (e) {
      if (mounted) {
        msg.showSnackBar(
          SnackBar(content: Text('Logdatei konnte nicht gelöscht werden: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => clearingLog = false);
    }
  }

  Future<void> _chooseBackupFolder() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => backupBusy = true);
    try {
      await state.chooseBackupFolder();
      if (mounted && state.backupFolderUri != null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Backup-Ordner gespeichert')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Backup-Ordner konnte nicht gesetzt werden: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => backupBusy = false);
    }
  }

  Future<void> _exportBackup() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => backupBusy = true);
    try {
      await state.exportBackupNow();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Export wurde gespeichert')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Export fehlgeschlagen: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => backupBusy = false);
    }
  }

  Future<void> _importBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    Directory? importTempDirectory;
    try {
      final selected = await FilePicker.pickFile(
        dialogTitle: 'Backup auswählen',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (selected == null || !mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Backup importieren?'),
          content: const Text(
            'Der aktuelle lokale Datenbestand wird durch das Backup ersetzt. '
            'Serverdaten werden dabei nicht verändert.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Importieren'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final state = context.read<AppState>();
      setState(() => backupBusy = true);
      final path = selected.path;
      if (path != null) {
        await state.importBackup(File(path));
      } else {
        importTempDirectory = await Directory.systemTemp.createTemp(
          'notiz_backup_import_',
        );
        final temporary = File(
          p.join(importTempDirectory.path, p.basename(selected.name)),
        );
        final sink = temporary.openWrite();
        try {
          var copiedBytes = 0;
          await for (final chunk in selected.readAsByteStream()) {
            copiedBytes += chunk.length;
            if (copiedBytes > 2 * 1024 * 1024 * 1024) {
              throw const FileSystemException(
                'Das Backup ist größer als 2 GB.',
              );
            }
            sink.add(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        await state.importBackup(temporary);
      }
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Backup wurde importiert')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Import fehlgeschlagen: $error')),
        );
      }
    } finally {
      try {
        if (importTempDirectory != null && await importTempDirectory.exists()) {
          await importTempDirectory.delete(recursive: true);
        }
      } catch (error) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Temporäre Importdatei konnte nicht gelöscht werden: $error',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => backupBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(
            title: 'Synchronisation',
            icon: Icons.cloud_sync_outlined,
          ),
          const _SubsectionHeader(
            title: 'Verbindung',
            icon: Icons.dns_outlined,
          ),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  secondary: Icon(
                    https ? Icons.lock_outline : Icons.lock_open_outlined,
                    color: https ? null : scheme.error,
                  ),
                  title: const Text('HTTPS verwenden'),
                  subtitle: Text(
                    https
                        ? 'Verschlüsselte Verbindung (empfohlen)'
                        : 'Unverschlüsselt (HTTP)',
                  ),
                  value: https,
                  onChanged: _setHttps,
                ),
                if (!https)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Token und Notizen werden im Klartext übertragen und können mitgelesen werden. '
                            'Nur in vertrauenswürdigen Netzwerken (z. B. Heimnetz) verwenden.',
                            style: TextStyle(fontSize: 12, color: scheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: url,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link),
                          labelText: 'Server-URL',
                          hintText: 'https://memos.example.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: token,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key_outlined),
                          labelText: 'Access Token',
                          helperText: 'Memos → Settings → My Account',
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(busy ? 'Prüfe …' : 'Testen & speichern'),
                          onPressed: busy ? null : _save,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SubsectionHeader(
            title: 'Zugangsdaten',
            icon: Icons.vpn_key_outlined,
          ),
          Card(
            child: ListTile(
              enabled: !busy,
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: const Text('Server-URL & Token löschen'),
              subtitle: const Text('Lokale Notizen bleiben erhalten'),
              onTap: busy ? null : _clear,
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader(
            title: 'Darstellung',
            icon: Icons.palette_outlined,
          ),
          Card(
            child: RadioGroup<AppTheme>(
              groupValue: s.themeSelection,
              onChanged: (mode) {
                if (mode != null) s.setTheme(mode);
              },
              child: Column(
                children: [
                  const RadioListTile<AppTheme>(
                    secondary: Icon(Icons.light_mode_outlined),
                    title: Text('Hell'),
                    value: AppTheme.light,
                  ),
                  const RadioListTile<AppTheme>(
                    secondary: Icon(Icons.dark_mode_outlined),
                    title: Text('Dunkel'),
                    value: AppTheme.dark,
                  ),
                  const RadioListTile<AppTheme>(
                    secondary: Icon(Icons.menu_book_outlined),
                    title: Text('Papier'),
                    subtitle: Text('Warme, helle Farben wie Papier und Tinte'),
                    value: AppTheme.paper,
                  ),
                  const RadioListTile<AppTheme>(
                    secondary: Icon(Icons.settings_brightness_outlined),
                    title: Text('Wie Systemeinstellung'),
                    value: AppTheme.system,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader(
            title: 'Bearbeitung',
            icon: Icons.edit_note_outlined,
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.playlist_add_check_outlined),
              title: const Text('Unterstützte Bearbeitung'),
              subtitle: const Text(
                'Erledigte Aufgaben ausblenden sowie Listen direkt bearbeiten, '
                'ergänzen und verschieben',
              ),
              value: s.assistedEditingEnabled,
              onChanged: s.setAssistedEditingEnabled,
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader(
            title: 'Im- und Export',
            icon: Icons.import_export_outlined,
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  enabled: !backupBusy,
                  leading: Icon(
                    s.backupFolderError == null
                        ? Icons.folder_open_outlined
                        : Icons.warning_amber_rounded,
                    color: s.backupFolderError == null ? null : scheme.error,
                  ),
                  title: const Text(
                    'Backup-Ordner festlegen oder Berechtigung erneuern',
                  ),
                  subtitle: Text(
                    s.backupFolderError ??
                        (s.backupFolderUri == null
                            ? 'Noch kein Ziel ausgewählt'
                            : 'Zielordner und Schreibberechtigung sind verfügbar'),
                    style: s.backupFolderError == null
                        ? null
                        : TextStyle(color: scheme.error),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: backupBusy ? null : _chooseBackupFolder,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.backup_outlined),
                  title: const Text('Automatisches Backup'),
                  subtitle: const Text(
                    'Bei jedem lokalen Speichern eine ZIP-Sicherung erstellen',
                  ),
                  value: s.automaticBackupsEnabled,
                  onChanged: backupBusy || s.backupFolderUri == null
                      ? null
                      : (value) async {
                          try {
                            await s.setAutomaticBackupsEnabled(value);
                          } catch (error) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Einstellung fehlgeschlagen: $error',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                ),
                ListTile(
                  enabled: !backupBusy && s.automaticBackupsEnabled,
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Aufbewahrte Versionen'),
                  trailing: DropdownButton<int>(
                    value: s.backupRetentionCount,
                    onChanged: !s.automaticBackupsEnabled || backupBusy
                        ? null
                        : (value) {
                            if (value != null) s.setBackupRetentionCount(value);
                          },
                    items: [
                      for (var count = 2; count <= 10; count++)
                        DropdownMenuItem(value: count, child: Text('$count')),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !backupBusy && s.backupFolderUri != null,
                  leading: const Icon(Icons.save_alt_outlined),
                  title: const Text('Jetzt exportieren'),
                  subtitle: const Text(
                    'ZIP mit Notizen, Synchronisationsstatus und Anhängen',
                  ),
                  onTap: backupBusy ? null : _exportBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !backupBusy,
                  leading: const Icon(Icons.folder_zip_outlined),
                  title: const Text('Backup importieren'),
                  subtitle: const Text(
                    'Wählt eine ZIP-Sicherung; ersetzt den lokalen Datenbestand',
                  ),
                  onTap: backupBusy ? null : _importBackup,
                ),
                if (backupBusy)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: LinearProgressIndicator(),
                  ),
                if (s.backupError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      s.backupError!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader(
            title: 'Datenschutz',
            icon: Icons.privacy_tip_outlined,
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.hide_image_outlined),
              title: const Text('Markdown-Bilder blockieren'),
              subtitle: const Text(
                'Verhindert, dass eingebettete Bilder automatisch geladen werden',
              ),
              value: s.blockMarkdownImages,
              onChanged: s.setBlockMarkdownImages,
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader(
            title: 'Diagnose',
            icon: Icons.bug_report_outlined,
          ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.description_outlined),
                  title: const Text('Logging aktivieren'),
                  subtitle: const Text(
                    'Schreibt Sync- und Fehlerprotokolle (max. 5 MB, nur in der App gespeichert)',
                  ),
                  value: s.logEnabled,
                  onChanged: s.setLogEnabled,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.share, color: Colors.deepPurple),
                  title: const Text('Log teilen'),
                  subtitle: const Text('Vorhandene Logdatei teilen'),
                  onTap: () async {
                    final msg = ScaffoldMessenger.of(context);
                    final ok = await LogService.share();
                    if (!ok) {
                      msg.showSnackBar(
                        const SnackBar(
                          content: Text('Noch keine Logs vorhanden'),
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !clearingLog,
                  leading: Icon(Icons.delete_outline, color: scheme.error),
                  title: const Text('Logdatei löschen'),
                  subtitle: const Text(
                    'Gespeichertes Diagnoseprotokoll entfernen',
                  ),
                  onTap: clearingLog ? null : _clearLog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionHeader(title: 'Info', icon: Icons.info_outline),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Meine Notizen',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const AppVersionText(),
                  const SizedBox(height: 4),
                  const Text(
                    'Notizen erfassen – optional mit Memos synchronisiert.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubsectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SubsectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.secondary),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
