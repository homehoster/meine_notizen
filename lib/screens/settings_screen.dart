import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(
            title: 'Synchronisation',
            icon: Icons.cloud_sync_outlined,
          ),
          const _SubsectionHeader(title: 'Verbindung', icon: Icons.dns_outlined),
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
            child: RadioGroup<ThemeMode>(
              groupValue: s.themeMode,
              onChanged: (mode) {
                if (mode != null) s.setTheme(mode);
              },
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    secondary: Icon(Icons.light_mode_outlined),
                    title: Text('Hell'),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    secondary: Icon(Icons.dark_mode_outlined),
                    title: Text('Dunkel'),
                    value: ThemeMode.dark,
                  ),
                  RadioListTile<ThemeMode>(
                    secondary: Icon(Icons.settings_brightness_outlined),
                    title: Text('Wie Systemeinstellung'),
                    value: ThemeMode.system,
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
                  const Text('Notizen erfassen – optional mit Memos synchronisiert.'),
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