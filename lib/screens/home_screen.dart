import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note.dart';
import '../models/saved_view.dart';
import '../models/space.dart';
import '../models/task_doc.dart';
import '../state/app_state.dart';
import '../widgets/markdown_image_blocker.dart';
import '../widgets/app_version_text.dart';
import 'note_screen.dart';
import 'settings_screen.dart';

void openNote(BuildContext c, Note n) =>
    Navigator.of(c)
        .push(MaterialPageRoute(builder: (_) => NoteScreen(note: n)));

Widget _menuLabel(IconData icon, String label, {TextStyle? style}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, size: 18, color: style?.color),
    const SizedBox(width: 12),
    Text(label, style: style),
  ],
);

IconData _visibilityIcon(String visibility) => switch (visibility) {
  'PUBLIC' => Icons.public_outlined,
  'PROTECTED' => Icons.group_outlined,
  'SPACE' => Icons.folder_shared_outlined,
  _ => Icons.lock_outline,
};

String _visibilityLabel(String visibility) => switch (visibility) {
  'PUBLIC' => 'Öffentlich',
  'PROTECTED' => 'Für Mitglieder',
  'SPACE' => 'Für Bereichsmitglieder',
  _ => 'Privat',
};

Future<void> _shareNote(BuildContext context, AppState state, Note note) async {
  final uri = Uri.parse('${state.baseUrl}/m/${Uri.encodeComponent(note.id)}');
  try {
    await SharePlus.instance.share(
      ShareParams(text: uri.toString(), subject: note.title),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Notiz-Link konnte nicht geteilt werden: $e')),
    );
  }
}

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

class _DrawerSection {
  final String title;
  final IconData icon;
  final int count;
  final VoidCallback? onAdd;
  final Widget Function(BuildContext, int) itemBuilder;

  const _DrawerSection({
    required this.title,
    required this.icon,
    required this.count,
    required this.itemBuilder,
    this.onAdd,
  });

  /// Höhe, die der Abschnitt für alle Einträge bräuchte (Kopf + Zeilen).
  double get needed => 48.0 + count * 52.0;
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Widget _buildDrawer(BuildContext context, AppState state) {
    final theme = Theme.of(context);

    void select(NavigationTarget target) {
      state.select(target);
      Navigator.pop(context);
    }

    // Abschnittskopf im Stil der Einstellungen: Symbol + Titel in Primärfarbe.
    Widget sectionHeader(String title, IconData icon, VoidCallback? onAdd) {
      return SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (onAdd != null)
              IconButton(
                tooltip: '$title anlegen',
                icon: const Icon(Icons.add),
                onPressed: onAdd,
              ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          SizedBox(
            height: 112,
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
            onTap: () => select(const NavigationTarget(NavigationKind.all)),
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('Archiv'),
            selected: state.navigation.kind == NavigationKind.archive,
            onTap: () => select(const NavigationTarget(NavigationKind.archive)),
          ),
          const Divider(height: 1),
          // Mittlerer Bereich: Bereiche, Ansichten und Tags teilen sich den
          // gesamten Restplatz. Leere Abschnitte geben ihren Platz ab.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final specs = <_DrawerSection>[
                  if (state.spacesSupported == true)
                    _DrawerSection(
                      title: 'Bereiche',
                      icon: Icons.folder_open_outlined,
                      count: state.spaces.length,
                      onAdd: () => _editSpace(context, state),
                      itemBuilder: (context, index) {
                        final space = state.spaces[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 16),
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
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: _menuLabel(
                                  Icons.edit_outlined,
                                  'Bearbeiten',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: _menuLabel(
                                  Icons.delete_outline,
                                  'Löschen',
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  _DrawerSection(
                    title: 'Ansichten',
                    icon: Icons.tune,
                    count: state.savedViews.length,
                    onAdd: () => _editView(context, state),
                    itemBuilder: (context, index) {
                      final view = state.savedViews[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 16),
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
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: _menuLabel(
                                Icons.edit_outlined,
                                'Bearbeiten',
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: _menuLabel(
                                Icons.delete_outline,
                                'Löschen',
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  _DrawerSection(
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
                ].where((x) => x.count > 0 || x.onAdd != null).toList();

                // Platz fair verteilen: kleine Abschnitte bekommen, was sie
                // brauchen; der Rest geht an die größeren.
                const minHeight = 48.0 + 52.0 * 2;
                final order = [...specs]
                  ..sort((a, b) => a.needed.compareTo(b.needed));
                final heights = <_DrawerSection, double>{};
                var remaining = constraints.maxHeight;
                var left = order.length;
                for (final spec in order) {
                  final share = remaining / left;
                  var height = spec.needed < share ? spec.needed : share;
                  if (height < minHeight && spec.needed > height) {
                    height = spec.needed < minHeight ? spec.needed : minHeight;
                  }
                  heights[spec] = height;
                  remaining -= height;
                  left--;
                }

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final spec in specs)
                        SizedBox(
                          height: heights[spec],
                          child: Column(
                            children: [
                              sectionHeader(spec.title, spec.icon, spec.onAdd),
                              if (spec.count > 0)
                                Expanded(
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    itemExtent: 52,
                                    itemCount: spec.count,
                                    itemBuilder: spec.itemBuilder,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Unten verankert: eine einzige kompakte Zeile, Version rechts.
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Einstellungen'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: AppVersionText(
              showBuild: false,
              prefix: 'meine Notizen v',
              style: TextStyle(color: Colors.grey[400], fontSize: 11),
            ),
          ),
          // // Unten verankert: eine einzige kompakte Zeile, Version rechts.
          // const Divider(height: 1),
          // ListTile(
          //   dense: true,
          //   leading: const Icon(Icons.settings_outlined),
          //   title: const Text('Einstellungen'),
          //   trailing: AppVersionText(
          //     showBuild: false,
          //     prefix: 'v',
          //     style: theme.textTheme.bodySmall?.copyWith(
          //       color: theme.colorScheme.outline,
          //     ),
          //   ),
          //   onTap: () {
          //     Navigator.pop(context);
          //     Navigator.push(
          //       context,
          //       MaterialPageRoute(builder: (_) => const SettingsScreen()),
          //     );
          //   },
          // ),
        ],
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
                                            case 'share':
                                              await _shareNote(ctx, s, n);
                                            case 'delete':
                                              await s.deleteNote(n);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'pin',
                                            child: _menuLabel(
                                              Icons.push_pin_outlined,
                                              n.pinned ? 'Lösen' : 'Anpinnen',
                                            ),
                                          ),
                                          if (n.state == NoteState.normal)
                                            PopupMenuItem(
                                              value: 'archive',
                                              child: _menuLabel(
                                                Icons.archive_outlined,
                                                'Archivieren',
                                              ),
                                            )
                                          else
                                            PopupMenuItem(
                                              value: 'restore',
                                              child: _menuLabel(
                                                Icons.unarchive_outlined,
                                                'Wiederherstellen',
                                              ),
                                            ),
                                          if (s.spacesSupported == true)
                                            PopupMenuItem(
                                              value: 'space',
                                              child: _menuLabel(
                                                Icons.folder_open_outlined,
                                                'Bereich zuordnen',
                                              ),
                                            ),
                                          if (!n.isLocal)
                                            PopupMenuItem(
                                              value: 'share',
                                              child: _menuLabel(
                                                Icons.share_outlined,
                                                'Link teilen',
                                              ),
                                            ),
                                          PopupMenuItem(
                                            value: 'widget',
                                            child: _menuLabel(
                                              Icons.widgets_outlined,
                                              s.widgetIds.contains(n.id)
                                                  ? 'Aus Widget entfernen'
                                                  : 'Im Widget anzeigen',
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: _menuLabel(
                                              Icons.delete_outline,
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
                                      Tooltip(
                                        message: _visibilityLabel(n.visibility),
                                        child: Icon(
                                          _visibilityIcon(n.visibility),
                                          size: 18,
                                        ),
                                      ),
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
            _TaskPreview(
              tasks: (seg as TaskSeg).roots,
              type: seg.type,
              depth: 0,
            ),
        if (rest.length > 5) Text('…', style: theme.textTheme.bodyMedium),
        if (note.attachments.isNotEmpty || note.pendingAttachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in note.attachments.take(3))
                  _HomeAttachmentPreview(
                    key: ValueKey(attachment.name),
                    attachment: attachment,
                  ),
                for (final attachment in note.pendingAttachments.take(
                  note.attachments.length >= 3
                      ? 0
                      : 3 - note.attachments.length,
                ))
                  _HomeAttachmentPreview(
                    key: ValueKey(attachment.path),
                    pending: attachment,
                  ),
                if (note.attachments.length + note.pendingAttachments.length >
                    3)
                  Chip(
                    label: Text(
                      '+ ${note.attachments.length + note.pendingAttachments.length - 3}',
                    ),
                  ),
              ],
            ),
          ),
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

class _HomeAttachmentPreview extends StatefulWidget {
  final NoteAttachment? attachment;
  final PendingAttachment? pending;

  const _HomeAttachmentPreview({super.key, this.attachment, this.pending});

  @override
  State<_HomeAttachmentPreview> createState() => _HomeAttachmentPreviewState();
}

class _HomeAttachmentPreviewState extends State<_HomeAttachmentPreview> {
  Future<Uint8List>? _imageBytes;

  String get _filename =>
      widget.attachment?.filename ?? widget.pending!.filename;
  String get _type => widget.attachment?.type ?? widget.pending!.type;
  bool get _isImage => _type.startsWith('image/');

  @override
  void initState() {
    super.initState();
    final attachment = widget.attachment;
    if (attachment != null && attachment.type.startsWith('image/')) {
      _imageBytes = _loadImage(attachment);
    }
  }

  Future<Uint8List> _loadImage(NoteAttachment attachment) async {
    final bytes = await context.read<AppState>().fetchAttachment(
      attachment.name,
    );
    return Uint8List.fromList(bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isImage) {
      return SizedBox(
        width: 220,
        child: Chip(
          avatar: Icon(
            _type.startsWith('audio/')
                ? Icons.audiotrack
                : Icons.insert_drive_file_outlined,
            size: 18,
          ),
          label: Text(_filename, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    final pending = widget.pending;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 160,
        height: 100,
        child: pending != null
            ? Image.file(
                File(pending.path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined, size: 32),
              )
            : FutureBuilder<Uint8List>(
                future: _imageBytes,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Icon(Icons.broken_image_outlined, size: 32);
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, size: 32),
                  );
                },
              ),
      ),
    );
  }
}

/// Zeigt Listeneinträge passend zum Listentyp:
/// Checkbox nur bei Aufgaben, „•“ bei Aufzählungen, „1.“ bei Nummerierungen.
class _TaskPreview extends StatelessWidget {
  final List<Task> tasks;
  final TaskListType type;
  final int depth;
  const _TaskPreview({
    required this.tasks,
    required this.type,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < tasks.length; index++) ...[
          Padding(
            padding: EdgeInsets.only(left: depth * 20.0, top: 2, bottom: 2),
            child: Row(
              children: [
                if (type == TaskListType.task)
                  Icon(
                    tasks[index].done
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                  )
                else
                  SizedBox(
                    width: 18,
                    child: Text(
                      type == TaskListType.numbered ? '${index + 1}.' : '•',
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tasks[index].text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (tasks[index].children.isNotEmpty)
            _TaskPreview(
              tasks: tasks[index].children,
              type: type,
              depth: depth + 1,
            ),
        ],
      ],
    );
  }
}
