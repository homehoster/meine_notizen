import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/log.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController url;
  late final TextEditingController token;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    url = TextEditingController(text: s.baseUrl);
    token = TextEditingController(text: s.token);
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final msg = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      await s.testConnection(url.text, token.text);
      await s.saveSettings(url.text, token.text);
      msg.showSnackBar(const SnackBar(content: Text('Verbunden & gespeichert')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
              labelText: 'Server-URL', hintText: 'https://memos.example.com'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: token,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Access Token (Memos → Settings → My Account)'),
        ),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: busy ? null : _save, child: Text(busy ? 'Prüfe …' : 'Testen & speichern')),
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
          title: const Text('Logging aktivieren'),
          subtitle: const Text('Schreibt Sync- und Fehlerprotokolle (max. ca. 10 MB)'),
          value: s.logEnabled,
          onChanged: s.setLogEnabled,
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.share),
          label: const Text('Log teilen'),
          onPressed: () async {
            final msg = ScaffoldMessenger.of(context);
            final ok = await LogService.share();
            if (!ok) msg.showSnackBar(const SnackBar(content: Text('Noch keine Logs vorhanden')));
          },
        ),
      ]),
    );
  }
}
