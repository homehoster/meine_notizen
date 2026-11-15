import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/task_doc.dart';

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
  const TaskSegView({super.key, required this.seg, required this.edit, required this.onChanged});

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
              value: t.done ? true : t.children.any(hasDoneTask) ? null : false,
              onChanged: (_) => _toggle(t),
            ),
            title: Text(
              t.text,
              style: t.done
                  ? TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Theme.of(context).disabledColor)
                  : null,
            ),
          ),
        for (final c in t.children) ..._doneRows(c, depth + 1),
      ];

  @override
  Widget build(BuildContext context) {
    final isTaskList = widget.seg.type == TaskListType.task;
    final done = isTaskList ? widget.seg.roots.where(hasDoneTask).toList() : <Task>[];
    final doneCount = isTaskList ? _countDone(widget.seg.roots) : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Level(tasks: widget.seg.roots, host: this),
      if (done.isNotEmpty)
        ExpansionTile(
          key: ObjectKey(widget.seg),
          title: Text('Erledigt ($doneCount)'),
          children: [for (final t in done) ..._doneRows(t, 0)],
        ),
    ]);
  }
}

class _Level extends StatelessWidget {
  final List<Task> tasks;
  final _TaskSegViewState host;
  const _Level({required this.tasks, required this.host});

  @override
  Widget build(BuildContext context) {
    final vis = tasks.where((t) => !t.done).toList();
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: vis.length,
      onReorder: (o, n) {
        reorderVisible(tasks, (t) => !t.done, o, n);
        host._changed();
      },
      itemBuilder: (ctx, i) {
        final t = vis[i];
        return Column(
          key: ObjectKey(t),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TaskRow(task: t, siblings: tasks, index: i, host: host),
            if (t.children.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: _Level(tasks: t.children, host: host),
              ),
          ],
        );
      },
    );
  }
}

/// Eine Zeile mit direkt bearbeitbarem Text (kein Popup).
class _TaskRow extends StatefulWidget {
  final Task task;
  final List<Task> siblings;
  final int index;
  final _TaskSegViewState host;
  const _TaskRow(
      {required this.task, required this.siblings, required this.index, required this.host});

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  late final TextEditingController _c = TextEditingController(text: widget.task.text);
  final FocusNode _f = FocusNode();

  @override
  void initState() {
    super.initState();
    _f.addListener(_onFocus);
    if (widget.host.edit.fresh == widget.task) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _f.requestFocus();
      });
    }
  }

  void _onFocus() {
    if (_f.hasFocus) return;
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
    final matches = host.edit.fresh == t
        ? findTasks(host.edit.segments(), t.text, exclude: t).take(4).toList()
        : const <Task>[];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ReorderableDragStartListener(
            index: widget.index,
            child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.drag_indicator))),
        if (host.widget.seg.type == TaskListType.task)
          Checkbox(
            tristate: true,
            value: t.done ? true : anyDone ? null : false,
            onChanged: (_) => host._toggle(t),
          )
        else
          SizedBox(
            width: 48,
            child: Center(
              child: Text(host.widget.seg.type == TaskListType.numbered ? '${widget.index + 1}.' : '-'),
            ),
          ),
        Expanded(
          child: TextField(
            controller: _c,
            focusNode: _f,
            maxLines: null,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.deny('\n')],
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Neuer Eintrag',
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) {
              t.text = v;
              host._typed();
            },
            onSubmitted: (_) => _f.unfocus(),
            onTapOutside: (_) => _f.unfocus(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Aufgabe auf dieser Ebene hinzufügen',
          onPressed: () => host._addSibling(widget.siblings, t),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'c') host._addChild(t);
            if (v == 'd') host._delete(t);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'c', child: Text('Unteraufgabe hinzufügen')),
            PopupMenuItem(value: 'd', child: Text('Löschen')),
          ],
        ),
      ]),
      if (matches.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 56, right: 8, bottom: 4),
          // Taps hier zählen als "im Textfeld", der Fokus bleibt erhalten.
          child: TextFieldTapRegion(
            child: Card(
              margin: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text('Bereits vorhanden – antippen statt neu anlegen',
                      style: Theme.of(context).textTheme.labelSmall),
                ),
                for (final m in matches)
                  ListTile(
                    dense: true,
                    leading: Icon(m.done ? Icons.check_box : Icons.check_box_outline_blank, size: 20),
                    title: Text(m.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: m.done ? const Text('erledigt – wird wieder geöffnet') : null,
                    onTap: () => host.edit.reuse(t, m),
                  ),
              ]),
            ),
          ),
        ),
    ]);
  }
}
