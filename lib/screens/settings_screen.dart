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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
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
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Token und Notizen werden im Klartext übertragen und können mitgelesen werden. '
                      'Nur in vertrauenswürdigen Netzwerken (z. B. Heimnetz) verwenden.',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
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
              labelText: 'Access Token (Memos → Settings → My Account)',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _save,
            child: Text(busy ? 'Prüfe …' : 'Testen & speichern'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Server-URL & Token löschen'),
            onPressed: busy ? null : _clear,
          ),
          const SizedBox(height: 32),
          const Text('Darstellung'),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Hell')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => s.setTheme(v.first),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Markdown-Bilder blockieren'),
            subtitle: const Text(
              'Verhindert, dass eingebettete Bilder automatisch geladen werden',
            ),
            value: s.blockMarkdownImages,
            onChanged: s.setBlockMarkdownImages,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Logging aktivieren'),
            subtitle: const Text(
              'Schreibt Sync- und Fehlerprotokolle (max. 5 MB, nur in der App gespeichert)',
            ),
            value: s.logEnabled,
            onChanged: s.setLogEnabled,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Log teilen'),
            onPressed: () async {
              final msg = ScaffoldMessenger.of(context);
              final ok = await LogService.share();
              if (!ok) {
                msg.showSnackBar(
                  const SnackBar(content: Text('Noch keine Logs vorhanden')),
                );
              }
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TravelBalance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const AppVersionText(),
                  const SizedBox(height: 4),
                  const Text('Reisekosten einfach aufteilen.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
