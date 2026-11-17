import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../models/saved_view.dart';
import '../models/space.dart';
import '../models/task_doc.dart';
import '../state/app_state.dart';
import '../widgets/markdown_image_blocker.dart';
import 'note_screen.dart';
import 'settings_screen.dart';

void openNote(BuildContext c, Note n) =>
    Navigator.of(c)
        .push(MaterialPageRoute(builder: (_) => NoteScreen(note: n)));

Future<void> _editSpace(
  BuildContext context,
  AppState state, {
  MemoSpace? space,
}) async {
  final title = TextEditingController(text: space?.title ?? '');
  final emoji = TextEditingController(text: space?.emoji ?? '');
  final description = TextEditingController(text: space?.description ?? '');
  final result = await showDialog<List<String>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(space == null ? 'Bereich anlegen' : 'Bereich bearbeiten'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: emoji,
              decoration: const InputDecoration(labelText: 'Symbol / Emoji'),
            ),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Beschreibung'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (title.text.trim().isNotEmpty) {
              Navigator.pop(context, [
                title.text.trim(),
                emoji.text.trim(),
                description.text.trim(),
              ]);
            }
          },
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
  title.dispose();
  emoji.dispose();
  description.dispose();
  if (result == null || !context.mounted) return;
  try {
    await state.saveSpace(
      MemoSpace(
        name: space?.name ?? '',
        title: result[0],
        emoji: result[1],
        description: result[2],
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bereich konnte nicht gespeichert werden: $e')),
    );
  }
}

Future<void> _deleteSpace(
  BuildContext context,
  AppState state,
  MemoSpace space,
) async {
  final count = state.notes
      .where((note) => note.space == space.name && !note.deleted)
      .length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Bereich löschen?'),
      content: Text(
        'Memos löscht mit dem Bereich auch alle darin abgelegten Notizen '
        'dauerhaft. In der lokalen Liste sind $count Notizen zugeordnet. '
        'Diese Aktion kann nicht rückgängig gemacht werden.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Bereich und Notizen löschen'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await state.deleteSpace(space);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bereich konnte nicht gelöscht werden: $e')),
    );
  }
}

Future<void> _editView(
  BuildContext context,
  AppState state, {
  SavedView? view,
}) async {
  final name = TextEditingController(text: view?.name ?? '');
  final icon = TextEditingController(text: view?.icon ?? '◉');
  final textContains = TextEditingController(text: view?.textContains ?? '');
  final tag = TextEditingController(text: view?.tag ?? '');
  var pinned = view?.pinned == null
      ? 'any'
      : view!.pinned!
      ? 'pinned'
      : 'notPinned';
  var attachments = view?.hasAttachments == null
      ? 'any'
      : view!.hasAttachments!
      ? 'yes'
      : 'no';
  var location = view?.hasLocation == null
      ? 'any'
      : view!.hasLocation!
      ? 'yes'
      : 'no';
  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(view == null ? 'Ansicht anlegen' : 'Ansicht bearbeiten'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: icon,
                decoration: const InputDecoration(labelText: 'Symbol / Emoji'),
              ),
              TextField(
                controller: textContains,
                decoration: const InputDecoration(
                  labelText: 'Text enthält (optional)',
                ),
              ),
              TextField(
                controller: tag,
                decoration: const InputDecoration(labelText: 'Tag (optional)'),
              ),
              DropdownButtonFormField<String>(
                initialValue: pinned,
                decoration: const InputDecoration(labelText: 'Anpinnen'),
                items: const [
                  DropdownMenuItem(value: 'any', child: Text('Beliebig')),
                  DropdownMenuItem(
                    value: 'pinned',
                    child: Text('Nur angepinnte'),
                  ),
                  DropdownMenuItem(
                    value: 'notPinned',
                    child: Text('Nicht angepinnt'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => pinned = value ?? 'any'),
              ),
              DropdownButtonFormField<String>(
                initialValue: attachments,
                decoration: const InputDecoration(labelText: 'Anhänge'),
                items: const [
                  DropdownMenuItem(value: 'any', child: Text('Beliebig')),
                  DropdownMenuItem(value: 'yes', child: Text('Mit Anhängen')),
                  DropdownMenuItem(value: 'no', child: Text('Ohne Anhänge')),
                ],
                onChanged: (value) =>
                    setDialogState(() => attachments = value ?? 'any'),
              ),
              DropdownButtonFormField<String>(
                initialValue: location,
                decoration: const InputDecoration(labelText: 'Standort'),
                items: const [
                  DropdownMenuItem(value: 'any', child: Text('Beliebig')),
                  DropdownMenuItem(value: 'yes', child: Text('Mit Standort')),
                  DropdownMenuItem(value: 'no', child: Text('Ohne Standort')),
                ],
                onChanged: (value) =>
                    setDialogState(() => location = value ?? 'any'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                Navigator.pop(context, {
                  'name': name.text.trim(),
                  'icon': icon.text.trim(),
                  'text': textContains.text.trim(),
                  'tag': tag.text.trim(),
                  'pinned': pinned,
                  'attachments': attachments,
                  'location': location,
                });
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  icon.dispose();
  textContains.dispose();
  tag.dispose();
  if (result == null || !context.mounted) return;
  await state.saveView(
    SavedView(
      id: view?.id ?? 'view-${DateTime.now().microsecondsSinceEpoch}',
      name: result['name']!,
      icon: result['icon']!.isEmpty ? '◉' : result['icon']!,
      textContains: result['text']!.isEmpty ? null : result['text'],
      tag: result['tag']!.isEmpty ? null : result['tag'],
      pinned: switch (result['pinned']) {
        'pinned' => true,
        'notPinned' => false,
        _ => null,
      },
      hasAttachments: switch (result['attachments']) {
        'yes' => true,
        'no' => false,
        _ => null,
      },
      hasLocation: switch (result['location']) {
        'yes' => true,
        'no' => false,
        _ => null,
      },
    ),
  );
}

Future<void> _chooseNoteSpace(
  BuildContext context,
  AppState state,
  Note note,
) async {
  final selection = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('Keinem Bereich zuordnen'),
            onTap: () => Navigator.pop(context, ''),
          ),
          for (final space in state.spaces)
            ListTile(
              leading: Text(space.emoji.isEmpty ? '📁' : space.emoji),
              title: Text(space.title),
              selected: note.space == space.name,
              onTap: () => Navigator.pop(context, space.name),
            ),
        ],
      ),
    ),
  );
  if (selection == null || !context.mounted) return;
  MemoSpace? selectedSpace;
  for (final space in state.spaces) {
    if (space.name == selection) selectedSpace = space;
  }
  if (selectedSpace != null && note.space != selectedSpace.name) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notiz in Bereich verschieben?'),
        content: Text(
          'Die Notiz wird für Mitglieder des Bereichs „${selectedSpace!.title}“ '
          'sichtbar. Ihre bisherige Sichtbarkeit wird dabei auf „Bereich“ gesetzt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verschieben'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }
  await state.assignSpace(note, selectedSpace);
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget _buildDrawer(BuildContext context, AppState state) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxSectionHeight = constraints.maxHeight / 3;
          final theme = Theme.of(context);

          Widget section({
            required String title,
            required IconData icon,
            required int count,
            required Widget Function(BuildContext, int) itemBuilder,
            VoidCallback? onAdd,
          }) {
            if (count == 0 && onAdd == null) {
              return const SizedBox.shrink();
            }
            if (count == 0) {
              return SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(icon, size: 20),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleSmall),
                    ),
                    IconButton(
                      tooltip: '$title anlegen',
                      icon: const Icon(Icons.add),
                      onPressed: onAdd,
                    ),
                  ],
                ),
              );
            }
            final sectionHeight = maxSectionHeight.clamp(76.0, 100000.0);
            final listHeight = (sectionHeight - 48).clamp(28.0, count * 52.0);
            return SizedBox(
              height: 48 + listHeight,
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(icon, size: 20),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(title, style: theme.textTheme.titleSmall),
                        ),
                        if (onAdd != null)
                          IconButton(
                            tooltip: '$title anlegen',
                            icon: const Icon(Icons.add),
                            onPressed: onAdd,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: listHeight,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemExtent: 52,
                      itemCount: count,
                      itemBuilder: itemBuilder,
                    ),
                  ),
                ],
              ),
            );
          }

          void select(NavigationTarget target) {
            state.select(target);
            Navigator.pop(context);
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: 128,
                  width: double.infinity,
                  child: DrawerHeader(
                    margin: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'asset/icon/icon_professional_cold.png',
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.sticky_note_2_outlined,
                              size: 40,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Meine Notizen',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                              const Text('für UseMemo'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.notes_outlined),
                  title: const Text('Alle Notizen'),
                  selected: state.navigation.kind == NavigationKind.all,
                  onTap: () =>
                      select(const NavigationTarget(NavigationKind.all)),
                ),
                ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('Archiv'),
                  selected: state.navigation.kind == NavigationKind.archive,
                  onTap: () =>
                      select(const NavigationTarget(NavigationKind.archive)),
                ),
                const Divider(height: 1),
                if (state.spacesSupported == true)
                  section(
                    title: 'Bereiche',
                    icon: Icons.folder_open_outlined,
                    count: state.spaces.length,
                    onAdd: () => _editSpace(context, state),
                    itemBuilder: (context, index) {
                      final space = state.spaces[index];
                      return ListTile(
                        dense: true,
                        leading: Text(
                          space.emoji.isEmpty ? '📁' : space.emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                        title: Text(
                          space.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected:
                            state.navigation.kind == NavigationKind.space &&
                            state.navigation.id == space.id,
                        onTap: () => select(
                          NavigationTarget(NavigationKind.space, space.id),
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Bereichsoptionen',
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editSpace(context, state, space: space);
                            } else if (value == 'delete') {
                              _deleteSpace(context, state, space);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Bearbeiten'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Löschen'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                section(
                  title: 'Ansichten',
                  icon: Icons.tune,
                  count: state.savedViews.length,
                  onAdd: () => _editView(context, state),
                  itemBuilder: (context, index) {
                    final view = state.savedViews[index];
                    return ListTile(
                      dense: true,
                      leading: Text(view.icon),
                      title: Text(
                        view.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected:
                          state.navigation.kind == NavigationKind.view &&
                          state.navigation.id == view.id,
                      onTap: () => select(
                        NavigationTarget(NavigationKind.view, view.id),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Ansichtsoptionen',
                        onSelected: (value) {
                          if (value == 'edit') {
                            _editView(context, state, view: view);
                          } else if (value == 'delete') {
                            state.deleteView(view.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Bearbeiten'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Löschen'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                section(
                  title: 'Tags',
                  icon: Icons.tag,
                  count: state.tags.length,
                  itemBuilder: (context, index) {
                    final tag = state.tags[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.tag, size: 20),
                      title: Text(tag),
                      selected:
                          state.navigation.kind == NavigationKind.tag &&
                          state.navigation.id == tag,
                      onTap: () =>
                          select(NavigationTarget(NavigationKind.tag, tag)),
                    );
                  },
                ),
                const Divider(height: 1),
                SizedBox(
                  height: 48,
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    minVerticalPadding: 0,
                    leading: const Icon(Icons.settings),
                    title: const Text('Einstellungen'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(
                  height: 24,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(72, 0, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _AppVersionLabel(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final notes = s.selectedNotes;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.screenTitle),
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
      drawer: Drawer(child: _buildDrawer(context, s)),
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
                                    child: _NotePreview(
                                      n,
                                      s.blockMarkdownImages,
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PopupMenuButton<String>(
                                        onSelected: (value) async {
                                          switch (value) {
                                            case 'pin':
                                              await s.setPinned(n, !n.pinned);
                                            case 'archive':
                                              await s.archive(n);
                                            case 'restore':
                                              await s.restore(n);
                                            case 'space':
                                              await _chooseNoteSpace(ctx, s, n);
                                            case 'widget':
                                              await s.toggleWidget(n);
                                            case 'delete':
                                              await s.deleteNote(n);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'pin',
                                            child: Text(
                                              n.pinned ? 'Lösen' : 'Anpinnen',
                                            ),
                                          ),
                                          if (n.state == NoteState.normal)
                                            const PopupMenuItem(
                                              value: 'archive',
                                              child: Text('Archivieren'),
                                            )
                                          else
                                            const PopupMenuItem(
                                              value: 'restore',
                                              child: Text('Wiederherstellen'),
                                            ),
                                          if (s.spacesSupported == true)
                                            const PopupMenuItem(
                                              value: 'space',
                                              child: Text('Bereich zuordnen'),
                                            ),
                                          PopupMenuItem(
                                            value: 'widget',
                                            child: Text(
                                              s.widgetIds.contains(n.id)
                                                  ? 'Aus Widget entfernen'
                                                  : 'Im Widget anzeigen',
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
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

class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _packageInfo,
    builder: (context, snapshot) {
      final style = Theme.of(context).textTheme.bodySmall;
      if (snapshot.hasError) {
        return Tooltip(
          message: 'App-Version konnte nicht geladen werden: ${snapshot.error}',
          child: Text(
            'Version nicht verfügbar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        );
      }
      if (!snapshot.hasData) {
        return Text(
          'Version wird geladen …',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      }
      final info = snapshot.data!;
      return Text(
        'Version ${info.version}+${info.buildNumber}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    },
  );
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
