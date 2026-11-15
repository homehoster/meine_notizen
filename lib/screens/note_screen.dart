import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/note.dart';
import '../models/task_doc.dart';
import '../state/app_state.dart';
import '../widgets/task_seg_view.dart';

class NoteScreen extends StatefulWidget {
  final Note note;
  const NoteScreen({super.key, required this.note});
  @override
  State<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends State<NoteScreen> {
  late final TextEditingController c;
  late final AppState s;
  late final TaskEditCtx edit;
  final UndoHistoryController _undo = UndoHistoryController();
  List<Segment> segs = [];
  int mode = 0; // 0 Ansicht, 1 Editor (Markdown)
  Timer? _t;

  @override
  void initState() {
    super.initState();
    s = context.read<AppState>();
    c = TextEditingController(text: widget.note.content);
    segs = parseDoc(c.text);
    edit = TaskEditCtx(segments: () => segs, reuse: _reuse);
    mode = c.text.trim().isEmpty ? 1 : 0;
  }

  @override
  void dispose() {
    _t?.cancel();
    s.saveContent(widget.note, c.text).then((_) => s.discardIfEmpty(widget.note));
    c.dispose();
    _undo.dispose();
    super.dispose();
  }

  void _schedule() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 600), () => s.saveContent(widget.note, c.text));
  }

  void _changed() {
    c.text = serializeDoc(segs);
    _schedule();
  }

  void _setMode(int m) {
    if (m == 0) {
      segs = parseDoc(c.text);
      edit.fresh = null;
    }
    setState(() => mode = m);
  }

  /// Neuer Eintrag ist ein Duplikat: bestehenden Eintrag wieder öffnen, neuen verwerfen.
  void _reuse(Task fresh, Task existing) {
    setState(() {
      for (final sg in segs) {
        if (sg is TaskSeg) removeTask(sg.roots, fresh);
      }
      reopenTask(segs, existing);
      edit.fresh = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _changed();
  }

  void _addListItem(TaskListType type) {
    final t = Task('');
    setState(() {
      if (segs.isNotEmpty && segs.last is TaskSeg && (segs.last as TaskSeg).type == type) {
        (segs.last as TaskSeg).roots.add(t);
      } else {
        segs.add(TaskSeg([t], type: type));
      }
      edit.fresh = t;
    });
    _changed();
  }

  Future<void> _showAddMenu() async {
    final type = await showModalBottomSheet<TaskListType>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_box_outlined),
              title: const Text('Aufgabe hinzufügen'),
              onTap: () => Navigator.pop(context, TaskListType.task),
            ),
            ListTile(
              leading: const Icon(Icons.format_list_bulleted),
              title: const Text('Aufzählung hinzufügen'),
              onTap: () => Navigator.pop(context, TaskListType.bullet),
            ),
            ListTile(
              leading: const Icon(Icons.format_list_numbered),
              title: const Text('Nummerierung hinzufügen'),
              onTap: () => Navigator.pop(context, TaskListType.numbered),
            ),
          ],
        ),
      ),
    );
    if (type != null && mounted) _addListItem(type);
  }

  void _wrap(String a, String b) {
    final sel = c.selection;
    final t = c.text;
    if (!sel.isValid) {
      c.text = '$t$a$b';
    } else {
      final mid = t.substring(sel.start, sel.end);
      c.value = TextEditingValue(
        text: t.replaceRange(sel.start, sel.end, '$a$mid$b'),
        selection: TextSelection(
            baseOffset: sel.start + a.length, extentOffset: sel.start + a.length + mid.length),
      );
    }
    _schedule();
  }

  void _linePrefix(String p) {
    final t = c.text;
    final pos = c.selection.isValid ? c.selection.start : t.length;
    final ls = pos == 0 ? 0 : t.lastIndexOf('\n', pos - 1) + 1;
    c.value = TextEditingValue(
      text: t.replaceRange(ls, ls, p),
      selection: TextSelection.collapsed(offset: pos + p.length),
    );
    _schedule();
  }

  /// level 0 = normaler Text, 1 = H1, 2 = H2. Ersetzt eine vorhandene Überschrift der Zeile.
  void _setHeading(int level) {
    final t = c.text;
    final pos = c.selection.isValid ? c.selection.start : t.length;
    final ls = pos == 0 ? 0 : t.lastIndexOf('\n', pos - 1) + 1;
    var le = t.indexOf('\n', ls);
    if (le == -1) le = t.length;
    final line = t.substring(ls, le);
    final m = RegExp(r'^#{1,6}\s*').firstMatch(line);
    final stripped = m == null ? line : line.substring(m.end);
    final newLine = '${level == 0 ? '' : '${'#' * level} '}$stripped';
    final offset = (pos + newLine.length - line.length).clamp(ls, ls + newLine.length).toInt();
    c.value = TextEditingValue(
      text: t.replaceRange(ls, le, newLine),
      selection: TextSelection.collapsed(offset: offset),
    );
    _schedule();
  }

  Widget _toolbar() {
    Widget b(IconData i, String tip, VoidCallback f) =>
        IconButton(icon: Icon(i), tooltip: tip, onPressed: f);
    Widget h(String label, String tip, VoidCallback f, {bool bold = true}) => Tooltip(
          message: tip,
          child: TextButton(
            style: TextButton.styleFrom(
                minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: f,
            child: Text(label,
                style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        ValueListenableBuilder<UndoHistoryValue>(
          valueListenable: _undo,
          builder: (_, v, _) => IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Rückgängig',
            onPressed: v.canUndo ? _undo.undo : null,
          ),
        ),
        h('H1', 'Überschrift 1', () => _setHeading(1)),
        h('H2', 'Überschrift 2', () => _setHeading(2)),
        h('Abc', 'Normaler Text', () => _setHeading(0), bold: false),
        b(Icons.format_bold, 'Fett', () => _wrap('**', '**')),
        b(Icons.format_italic, 'Kursiv', () => _wrap('*', '*')),
        b(Icons.format_list_bulleted, 'Aufzählung', () => _linePrefix('- ')),
        b(Icons.format_list_numbered, 'Nummeriert', () => _linePrefix('1. ')),
        b(Icons.check_box_outlined, 'Aufgabe', () => _linePrefix('- [ ] ')),
        b(Icons.link, 'Link', () => _wrap('[', '](https://)')),
        b(Icons.code, 'Code', () => _wrap('`', '`')),
        b(Icons.format_quote, 'Zitat', () => _linePrefix('> ')),
      ]),
    );
  }

  Widget _body() {
    if (mode == 0) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        for (final seg in segs)
          if (seg is TextSeg)
            (seg.text.trim().isEmpty
                ? const SizedBox.shrink()
                : MarkdownBody(
                    data: seg.text,
                    onTapLink: (t, href, title) {
                      if (href != null) {
                        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                      }
                    },
                  ))
          else
            TaskSegView(
                key: ObjectKey(seg), seg: seg as TaskSeg, edit: edit, onChanged: _changed),
      ]);
    }
    return Column(children: [
      _toolbar(),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: c,
            undoController: _undo,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            onChanged: (_) => _schedule(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration:
                const InputDecoration(border: InputBorder.none, hintText: 'Notiz schreiben …'),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note.isLocal ? 'Neue Notiz' : 'Notiz'),
        actions: [
          IconButton(
            icon: Icon(s.widgetIds.contains(widget.note.id) ? Icons.widgets : Icons.widgets_outlined),
            tooltip: 'Im Widget anzeigen',
            onPressed: () async {
              await s.toggleWidget(widget.note);
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final nav = Navigator.of(context);
              _t?.cancel();
              await s.deleteNote(widget.note);
              nav.pop();
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.checklist), label: Text('Ansicht')),
              ButtonSegment(value: 1, icon: Icon(Icons.edit), label: Text('Editor')),
            ],
            selected: {mode},
            onSelectionChanged: (v) => _setMode(v.first),
          ),
        ),
        Expanded(child: _body()),
      ]),
      floatingActionButton: mode == 0
          ? FloatingActionButton(
              onPressed: _showAddMenu,
              tooltip: 'Eintrag hinzufügen',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}