import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../locales/app_localizations.dart';
import '../models/task_doc.dart';
import 'markdown_image_blocker.dart';

/// Gemeinsamer Zustand für das Bearbeiten von Listeneinträgen innerhalb einer Notiz.
class TaskEditCtx {
  /// Eben neu angelegter Eintrag (noch nicht bestätigt) – nur für ihn gibt es Vorschläge.
  Task? fresh;

  /// Alle Segmente der Notiz (für die Duplikatsuche).
  final List<Segment> Function() segments;

  /// Vorhandenen Eintrag statt eines neuen verwenden.
  final void Function(Task fresh, Task existing) reuse;

  TaskEditCtx({required this.segments, required this.reuse});
}

int _countDone(List<Task> ts) =>
    ts.fold(0, (n, t) => n + (t.done ? 1 : 0) + _countDone(t.children));

class TaskSegView extends StatefulWidget {
  final TaskSeg seg;
  final TaskEditCtx edit;
  final VoidCallback onChanged;
  final ValueChanged<String?> onOpenLink;
  final bool assistedEditingEnabled;
  final bool blockMarkdownImages;
  const TaskSegView({
    super.key,
    required this.seg,
    required this.edit,
    required this.onChanged,
    required this.onOpenLink,
    required this.assistedEditingEnabled,
    required this.blockMarkdownImages,
  });

  @override
  State<TaskSegView> createState() => _TaskSegViewState();
}

class _TaskSegViewState extends State<TaskSegView> {
  TaskEditCtx get edit => widget.edit;

  void _changed() {
    syncParents(widget.seg.roots);
    setState(() {});
    widget.onChanged();
  }

  void _toggle(Task t) {
    toggleTask(widget.seg.roots, t);
    setState(() {});
    widget.onChanged();
  }

  /// Text wurde getippt: Vorschläge aktualisieren und speichern.
  void _typed() {
    setState(() {});
    widget.onChanged();
  }

  /// Eingabe beendet (Fokus verloren).
  void _commit(Task t) {
    if (edit.fresh == t) edit.fresh = null;
    final text = t.text.trim();
    if (text.isEmpty && t.children.isEmpty) {
      removeTask(widget.seg.roots, t);
    } else {
      t.text = text;
    }
    _changed();
  }

  void _delete(Task t) {
    removeTask(widget.seg.roots, t);
    _changed();
  }

  void _addChild(Task parent) {
    final t = Task('');
    parent.children.add(t);
    edit.fresh = t;
    _changed();
  }

  void _addSibling(List<Task> siblings, Task task) {
    final t = Task('');
    siblings.insert(siblings.indexOf(task) + 1, t);
    edit.fresh = t;
    _changed();
  }

  List<Widget> _doneRows(Task t, int depth) => [
    if (hasDoneTask(t))
      ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 24, right: 16),
        leading: Checkbox(
          tristate: true,
          value: t.done
              ? true
              : t.children.any(hasDoneTask)
              ? null
              : false,
          onChanged: (_) => _toggle(t),
        ),
        title: MarkdownBody(
          data: t.text,
          onTapLink: (text, href, title) => widget.onOpenLink(href),
          imageBuilder: widget.blockMarkdownImages
              ? blockedMarkdownImage
              : null,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              decoration: t.done ? TextDecoration.lineThrough : null,
              color: t.done ? Theme.of(context).disabledColor : null,
            ),
          ),
        ),
      ),
    for (final c in t.children) ..._doneRows(c, depth + 1),
  ];

  @override
  Widget build(BuildContext context) {
    final isTaskList = widget.seg.type == TaskListType.task;
    final done = isTaskList
        ? widget.seg.roots.where(hasDoneTask).toList()
        : <Task>[];
    final doneCount = isTaskList ? _countDone(widget.seg.roots) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Level(
          tasks: widget.seg.roots,
          host: this,
          assistedEditingEnabled: widget.assistedEditingEnabled,
        ),
        if (widget.assistedEditingEnabled && done.isNotEmpty)
          ExpansionTile(
            key: ObjectKey(widget.seg),
            title: Text('${context.tr('Erledigt')} ($doneCount)'),
            children: [for (final t in done) ..._doneRows(t, 0)],
          ),
      ],
    );
  }
}

class _Level extends StatelessWidget {
  final List<Task> tasks;
  final _TaskSegViewState host;
  final bool assistedEditingEnabled;
  const _Level({
    required this.tasks,
    required this.host,
    required this.assistedEditingEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final visible = assistedEditingEnabled
        ? tasks.where((t) => !t.done).toList()
        : tasks;
    Widget item(int index) {
      final task = visible[index];
      return Column(
        key: ObjectKey(task),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaskRow(task: task, siblings: tasks, index: index, host: host),
          if (task.children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: _Level(
                tasks: task.children,
                host: host,
                assistedEditingEnabled: assistedEditingEnabled,
              ),
            ),
        ],
      );
    }

    if (!assistedEditingEnabled) {
      return Column(
        children: [for (var i = 0; i < visible.length; i++) item(i)],
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: visible.length,
      onReorderItem: (oldIndex, newIndex) {
        reorderVisible(tasks, (task) => !task.done, oldIndex, newIndex);
        host._changed();
      },
      itemBuilder: (context, index) => item(index),
    );
  }
}

/// Eine Zeile mit direkt bearbeitbarem Text (kein Popup).
class _TaskRow extends StatefulWidget {
  final Task task;
  final List<Task> siblings;
  final int index;
  final _TaskSegViewState host;
  const _TaskRow({
    required this.task,
    required this.siblings,
    required this.index,
    required this.host,
  });

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  late final TextEditingController _c = TextEditingController(
    text: widget.task.text,
  );
  final FocusNode _f = FocusNode();
  late bool _editing;

  @override
  void initState() {
    super.initState();
    _editing =
        widget.host.widget.assistedEditingEnabled &&
        widget.host.edit.fresh == widget.task;
    _f.addListener(_onFocus);
    if (_editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _f.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.host.widget.assistedEditingEnabled && _editing) {
      _editing = false;
      if (_f.hasFocus) widget.host._commit(widget.task);
    }
  }

  void _onFocus() {
    if (_f.hasFocus || !_editing) return;
    final host = widget.host;
    final t = widget.task;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_f.hasFocus) host._commit(t);
    });
  }

  @override
  void dispose() {
    _f.removeListener(_onFocus);
    _f.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final host = widget.host;
    final anyDone = t.children.any((c) => c.done);
    final canEdit = host.widget.assistedEditingEnabled;
    final matches = canEdit && host.edit.fresh == t
        ? findTasks(host.edit.segments(), t.text, exclude: t).take(4).toList()
        : const <Task>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (canEdit)
              ReorderableDragStartListener(
                index: widget.index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.drag_indicator),
                ),
              ),
            if (host.widget.seg.type == TaskListType.task)
              Checkbox(
                tristate: true,
                value: t.done
                    ? true
                    : anyDone
                    ? null
                    : false,
                onChanged: (_) => host._toggle(t),
              )
            else
              SizedBox(
                width: 48,
                child: Center(
                  child: Text(
                    host.widget.seg.type == TaskListType.numbered
                        ? '${widget.index + 1}.'
                        : '-',
                  ),
                ),
              ),
            Expanded(
              child: _editing
                  ? TextField(
                      controller: _c,
                      focusNode: _f,
                      maxLines: null,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.deny('\n')],
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: context.tr('Neuer Eintrag'),
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (value) {
                        t.text = value;
                        host._typed();
                      },
                      onSubmitted: (_) => _f.unfocus(),
                      onTapOutside: (_) => _f.unfocus(),
                    )
                  : GestureDetector(
                      onTap: canEdit
                          ? () => setState(() {
                              _editing = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) _f.requestFocus();
                              });
                            })
                          : null,
                      child: MarkdownBody(
                        data: t.text.isEmpty ? ' ' : t.text,
                        onTapLink: (text, href, title) =>
                            host.widget.onOpenLink(href),
                        imageBuilder: host.widget.blockMarkdownImages
                            ? blockedMarkdownImage
                            : null,
                      ),
                    ),
            ),
            if (canEdit) ...[
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: context.tr('Aufgabe auf dieser Ebene hinzufügen'),
                onPressed: () => host._addSibling(widget.siblings, t),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'c') host._addChild(t);
                  if (value == 'd') host._delete(t);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'c',
                    child: Text(context.tr('Unteraufgabe hinzufügen')),
                  ),
                  PopupMenuItem(
                    value: 'd',
                    child: Text(
                      context.tr('Löschen'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        if (matches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 8, bottom: 4),
            // Taps hier zählen als "im Textfeld", der Fokus bleibt erhalten.
            child: TextFieldTapRegion(
              child: Card(
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Text(
                        context.tr(
                          'Bereits vorhanden – antippen statt neu anlegen',
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    for (final m in matches)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          m.done
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 20,
                        ),
                        title: Text(
                          m.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: m.done
                            ? Text(
                                context.tr('erledigt – wird wieder geöffnet'),
                              )
                            : null,
                        onTap: () => host.edit.reuse(t, m),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
