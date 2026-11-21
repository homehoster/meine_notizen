import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../locales/app_localizations.dart';
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
    final savedMessage = context.tr('Verbunden & gespeichert');
    final errorPrefix = context.tr('Fehler');
    setState(() => busy = true);
    try {
      final u = _withScheme(url.text);
      await s.testConnection(u, token.text);
      await s.saveSettings(u, token.text);
      if (!context.mounted) return;
      msg.showSnackBar(SnackBar(content: Text(savedMessage)));
    } catch (e) {
      if (!mounted) return;
      msg.showSnackBar(SnackBar(content: Text('$errorPrefix: $e')));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _clear() async {
    final s = context.read<AppState>();
    final msg = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Zugangsdaten löschen?')),
        content: Text(
          context.tr(
            'Server-URL und Token werden von diesem Gerät entfernt. Lokal gespeicherte Notizen bleiben erhalten, werden aber nicht mehr synchronisiert.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('Löschen')),
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
      SnackBar(content: Text(context.tr('Server-URL und Token gelöscht'))),
    );
  }

  Future<void> _clearLog() async {
    final msg = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Logdatei löschen?')),
        content: Text(
          context.tr('Das gespeicherte Diagnoseprotokoll wird gelöscht.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('Löschen')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => clearingLog = true);
    try {
      await LogService.clear();
      if (mounted) {
        msg.showSnackBar(
          SnackBar(content: Text(context.tr('Logdatei gelöscht'))),
        );
      }
    } catch (e) {
      if (mounted) {
        msg.showSnackBar(
          SnackBar(
            content: Text(
              '${context.tr('Logdatei konnte nicht gelöscht werden')}: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => clearingLog = false);
    }
  }

  Future<void> _setLanguage(String code) async {
    try {
      await context.read<AppState>().setLanguage(code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.tr('Sprache konnte nicht gespeichert werden')}: $e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Einstellungen'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            title: context.tr('Synchronisation'),
            icon: Icons.cloud_sync_outlined,
          ),
          _SubsectionHeader(
            title: context.tr('Verbindung'),
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
                  title: Text(context.tr('HTTPS verwenden')),
                  subtitle: Text(
                    https
                        ? context.tr('Verschlüsselte Verbindung (empfohlen)')
                        : context.tr('Unverschlüsselt (HTTP)'),
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
                            context.tr(
                              'Token und Notizen werden im Klartext übertragen und können mitgelesen werden. Nur in vertrauenswürdigen Netzwerken (z. B. Heimnetz) verwenden.',
                            ),
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
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link),
                          labelText: context.tr('Server-URL'),
                          hintText: 'https://memos.example.com',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: token,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key_outlined),
                          labelText: 'Access Token',
                          helperText: context.tr(
                            'Memos → Settings → My Account',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(
                            busy
                                ? context.tr('Prüfe …')
                                : context.tr('Testen & speichern'),
                          ),
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
          _SubsectionHeader(
            title: context.tr('Zugangsdaten'),
            icon: Icons.vpn_key_outlined,
          ),
          Card(
            child: ListTile(
              enabled: !busy,
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text(context.tr('Server-URL & Token löschen')),
              subtitle: Text(context.tr('Lokale Notizen bleiben erhalten')),
              onTap: busy ? null : _clear,
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: context.tr('Darstellung'),
            icon: Icons.palette_outlined,
          ),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: s.themeMode,
              onChanged: (mode) {
                if (mode != null) s.setTheme(mode);
              },
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    secondary: Icon(Icons.light_mode_outlined),
                    title: Text(context.tr('Hell')),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    secondary: Icon(Icons.dark_mode_outlined),
                    title: Text(context.tr('Dunkel')),
                    value: ThemeMode.dark,
                  ),
                  RadioListTile<ThemeMode>(
                    secondary: Icon(Icons.settings_brightness_outlined),
                    title: Text(context.tr('Wie Systemeinstellung')),
                    value: ThemeMode.system,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: context.tr('Sprache'),
            icon: Icons.language_outlined,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<String>(
                initialValue: s.languageCode,
                decoration: InputDecoration(
                  labelText: context.tr('Sprache'),
                  border: InputBorder.none,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(context.tr('Wie Systemeinstellung')),
                  ),
                  for (final language in appLanguages)
                    DropdownMenuItem(
                      value: language.code,
                      child: Text(language.name),
                    ),
                ],
                onChanged: (code) {
                  if (code != null) _setLanguage(code);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: context.tr('Bearbeitung'),
            icon: Icons.edit_note_outlined,
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.playlist_add_check_outlined),
              title: Text(context.tr('Unterstützte Bearbeitung')),
              subtitle: Text(
                context.tr(
                  'Erledigte Aufgaben ausblenden sowie Listen direkt bearbeiten, ergänzen und verschieben',
                ),
              ),
              value: s.assistedEditingEnabled,
              onChanged: s.setAssistedEditingEnabled,
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: context.tr('Datenschutz'),
            icon: Icons.privacy_tip_outlined,
          ),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.hide_image_outlined),
              title: Text(context.tr('Markdown-Bilder blockieren')),
              subtitle: Text(
                context.tr(
                  'Verhindert, dass eingebettete Bilder automatisch geladen werden',
                ),
              ),
              value: s.blockMarkdownImages,
              onChanged: s.setBlockMarkdownImages,
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: context.tr('Diagnose'),
            icon: Icons.bug_report_outlined,
          ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.description_outlined),
                  title: Text(context.tr('Logging aktivieren')),
                  subtitle: Text(
                    context.tr(
                      'Schreibt Sync- und Fehlerprotokolle (max. 5 MB, nur in der App gespeichert)',
                    ),
                  ),
                  value: s.logEnabled,
                  onChanged: s.setLogEnabled,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.share, color: Colors.deepPurple),
                  title: Text(context.tr('Log teilen')),
                  subtitle: Text(context.tr('Vorhandene Logdatei teilen')),
                  onTap: () async {
                    final msg = ScaffoldMessenger.of(context);
                    final ok = await LogService.share();
                    if (!context.mounted) return;
                    if (!ok) {
                      msg.showSnackBar(
                        SnackBar(
                          content: Text(
                            context.tr('Noch keine Logs vorhanden'),
                          ),
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: !clearingLog,
                  leading: Icon(Icons.delete_outline, color: scheme.error),
                  title: Text(context.tr('Logdatei löschen')),
                  subtitle: Text(
                    context.tr('Gespeichertes Diagnoseprotokoll entfernen'),
                  ),
                  onTap: clearingLog ? null : _clearLog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: context.tr('Info'), icon: Icons.info_outline),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Meine Notizen'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const AppVersionText(),
                  const SizedBox(height: 4),
                  Text(
                    context.tr(
                      'Notizen erfassen – optional mit Memos synchronisiert.',
                    ),
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
