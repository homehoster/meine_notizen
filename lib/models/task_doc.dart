/// Parst Markdown in Text- und Aufgabenblöcke und schreibt es wieder zurück.
class Task {
  String text;
  bool done;
  List<Task> children;
  Task(this.text, {this.done = false, List<Task>? children}) : children = children ?? [];
}

abstract class Segment {}

class TextSeg extends Segment {
  String text;
  TextSeg(this.text);
}

class TaskSeg extends Segment {
  List<Task> roots;
  TaskSeg(this.roots);
}

final _taskRe = RegExp(r'^(\s*)[-*] \[([ xX])\] ?(.*)$');

int _level(String ws) => ws.replaceAll('\t', '  ').length ~/ 2;

List<Segment> parseDoc(String content) {
  final segs = <Segment>[];
  final buf = <String>[];
  TaskSeg? cur;
  final stack = <MapEntry<int, Task>>[];

  void flush() {
    if (buf.isNotEmpty) {
      segs.add(TextSeg(buf.join('\n')));
      buf.clear();
    }
  }

  for (final line in content.split('\n')) {
    final m = _taskRe.firstMatch(line);
    if (m != null) {
      flush();
      if (cur == null) {
        cur = TaskSeg([]);
        segs.add(cur);
        stack.clear();
      }
      final indent = _level(m.group(1)!);
      final t = Task(m.group(3)!, done: m.group(2) != ' ');
      while (stack.isNotEmpty && stack.last.key >= indent) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        cur.roots.add(t);
      } else {
        stack.last.value.children.add(t);
      }
      stack.add(MapEntry(indent, t));
    } else {
      cur = null;
      buf.add(line);
    }
  }
  flush();
  return segs;
}

String _tasksToMd(List<Task> ts, int d) => ts
    .where((t) => t.text.trim().isNotEmpty || t.children.isNotEmpty)
    .map((t) =>
        '${'  ' * d}- [${t.done ? 'x' : ' '}] ${t.text}${t.children.isEmpty ? '' : '\n${_tasksToMd(t.children, d + 1)}'}')
    .join('\n');

String serializeDoc(List<Segment> segs) {
  final parts = <String>[];
  for (final s in segs) {
    if (s is TextSeg) {
      parts.add(s.text);
    } else {
      final md = _tasksToMd((s as TaskSeg).roots, 0);
      if (md.isNotEmpty) parts.add(md);
    }
  }
  return parts.join('\n');
}

/// Setzt einen Eintrag samt Unterpunkten auf unerledigt und gleicht alle Listen ab.
void reopenTask(List<Segment> segs, Task t) {
  _setDone(t, false);
  for (final s in segs) {
    if (s is TaskSeg) syncParents(s.roots);
  }
}

/// Sucht Einträge in der ganzen Notiz, deren Text die Eingabe enthält.
List<Task> findTasks(List<Segment> segs, String query, {Task? exclude}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  final out = <Task>[];
  void walk(List<Task> ts) {
    for (final t in ts) {
      if (!identical(t, exclude) && t.text.toLowerCase().contains(q)) out.add(t);
      walk(t.children);
    }
  }

  for (final s in segs) {
    if (s is TaskSeg) walk(s.roots);
  }
  return out;
}
void _setDone(Task t, bool v) {
  t.done = v;
  for (final c in t.children) {
    _setDone(c, v);
  }
}

void syncParents(List<Task> ts) {
  for (final t in ts) {
    if (t.children.isNotEmpty) {
      syncParents(t.children);
      t.done = t.children.every((c) => c.done);
    }
  }
}

/// Hauptaufgabe <-> Unteraufgaben gemeinsam; Elternaufgabe folgt den Kindern.
void toggleTask(List<Task> roots, Task t) {
  _setDone(t, !t.done);
  syncParents(roots);
}

bool removeTask(List<Task> list, Task t) {
  if (list.remove(t)) return true;
  for (final c in list) {
    if (removeTask(c.children, t)) return true;
  }
  return false;
}

bool hasDoneTask(Task task) => task.done || task.children.any(hasDoneTask);

int countOpen(List<Task> ts) =>
    ts.fold(0, (n, t) => n + (t.done ? 0 : 1) + countOpen(t.children));

/// Verschiebt innerhalb der sichtbaren (gefilterten) Liste.
void reorderVisible(List<Task> all, bool Function(Task) vis, int oldI, int newI) {
  final visible = all.where(vis).toList();
  if (newI > oldI) newI -= 1;
  final item = visible.removeAt(oldI);
  visible.insert(newI, item);
  var k = 0;
  for (var i = 0; i < all.length; i++) {
    if (vis(all[i])) all[i] = visible[k++];
  }
}
