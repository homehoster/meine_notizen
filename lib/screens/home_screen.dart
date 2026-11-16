import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../models/task_doc.dart';
import '../state/app_state.dart';
import '../widgets/markdown_image_blocker.dart';
import 'note_screen.dart';
import 'settings_screen.dart';

void openNote(BuildContext c, Note n) =>
    Navigator.of(c)
        .push(MaterialPageRoute(builder: (_) => NoteScreen(note: n)));

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final notes = s.visible;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final subColor = dark ? Colors.grey.shade400 : Colors.grey.shade800;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notizen'),
        actions: [
          if (s.syncing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.sync), onPressed: s.sync),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.2,
              width: double.infinity,
              child: DrawerHeader(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'asset/icon/icon_professional_cold.png',
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.sticky_note_2_outlined,
                          size: 40,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Meine Notizen',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'für UseMemo',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: subColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Einstellungen'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (s.notice != null)
            MaterialBanner(
              content: Text(s.notice!),
              actions: [
                TextButton(onPressed: s.dismissNotice, child: const Text('OK')),
              ],
            ),
          if (s.error != null)
            MaterialBanner(
              content: Text(
                'Sync-Fehler: ${s.error}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                TextButton(onPressed: s.sync, child: const Text('Erneut')),
              ],
            ),
          Expanded(
            child: !s.configured && notes.isEmpty
                ? Center(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                      child: const Text('Server & Token einrichten'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: s.sync,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 6, bottom: 96),
                      itemCount: notes.length,
                      itemBuilder: (ctx, i) {
                        final n = notes[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => openNote(ctx, n),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _NotePreview(n, s.blockMarkdownImages),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PopupMenuButton<String>(
                                        onSelected: (v) {
                                          if (v == 'w') s.toggleWidget(n);
                                          if (v == 'd') s.deleteNote(n);
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'w',
                                            child: Text(
                                              s.widgetIds.contains(n.id)
                                                  ? 'Aus Widget entfernen'
                                                  : 'Im Widget anzeigen',
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'd',
                                            child: Text(
                                              'Löschen',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (n.dirty)
                                        const Icon(Icons.cloud_off, size: 18),
                                      if (s.widgetIds.contains(n.id))
                                        const Icon(Icons.widgets, size: 18),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final n = await s.create();
          if (context.mounted) openNote(context, n);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

final _headingRe = RegExp(r'^\s*#{1,6}\s+(.*)$');
final _doneLineRe = RegExp(r'^\s*[-*] \[[xX]\]');

/// Kompakte, schreibgeschützte Version des Ansichtsmodus:
/// Überschrift (falls die Notiz mit einer beginnt) + max. 5 Zeilen,
/// sonst die ersten 5 Zeilen. Erledigte Einträge sind wie in der Ansicht ausgeblendet.
class _NotePreview extends StatelessWidget {
  final Note note;
  final bool blockMarkdownImages;

  const _NotePreview(this.note, this.blockMarkdownImages);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = note.content.split('\n');
    var i = lines.indexWhere((l) => l.trim().isNotEmpty);
    String? heading;
    if (i >= 0) {
      final m = _headingRe.firstMatch(lines[i]);
      if (m != null) {
        final h = m.group(1)!.trim();
        heading = h.isEmpty ? null : h;
        i++;
      }
    }
    final rest = i < 0
        ? <String>[]
        : lines
              .skip(i)
              .where((l) => l.trim().isNotEmpty && !_doneLineRe.hasMatch(l))
              .toList();
    final shown = rest.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              heading,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        for (final seg in parseDoc(shown.join('\n')))
          if (seg is TextSeg)
            MarkdownBody(
              data: seg.text,
              softLineBreak: true,
              imageBuilder: blockMarkdownImages ? blockedMarkdownImage : null,
            )
          else
            _TaskPreview(tasks: (seg as TaskSeg).roots, depth: 0),
        if (rest.length > 5) Text('…', style: theme.textTheme.bodyMedium),
        if (heading == null && shown.isEmpty)
          Text(
            'Leere Notiz',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

class _TaskPreview extends StatelessWidget {
  final List<Task> tasks;
  final int depth;
  const _TaskPreview({required this.tasks, required this.depth});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in tasks) ...[
          Padding(
            padding: EdgeInsets.only(left: depth * 20.0, top: 2, bottom: 2),
            child: Row(
              children: [
                Icon(
                  t.done ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (t.children.isNotEmpty)
            _TaskPreview(tasks: t.children, depth: depth + 1),
        ],
      ],
    );
  }
}
