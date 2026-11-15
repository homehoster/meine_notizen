/// Parst Markdown in Text- und Aufgabenblöcke und schreibt es wieder zurück.
class Task {
  String text;
  bool done;
  List<Task> children;
  Task(this.text, {this.done = false, List<Task>? children})
    : children = children ?? [];
}

enum TaskListType { task, bullet, numbered }

abstract class Segment {}

class TextSeg extends Segment {
  String text;
  TextSeg(this.text);
}

class TaskSeg extends Segment {
  TaskListType type;
  List<Task> roots;
  TaskSeg(this.roots, {this.type = TaskListType.task});
}

final _taskRe = RegExp(r'^(\s*)[-*] \[([ xX])\] ?(.*)$');
final _bulletRe = RegExp(r'^(\s*)[-*] +(.*)$');
final _numberedRe = RegExp(r'^(\s*)\d+\. +(.*)$');

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
    final taskMatch = _taskRe.firstMatch(line);
    final bulletMatch = taskMatch == null ? _bulletRe.firstMatch(line) : null;
    final numberedMatch = taskMatch == null && bulletMatch == null
        ? _numberedRe.firstMatch(line)
        : null;
    if (taskMatch != null || bulletMatch != null || numberedMatch != null) {
      flush();
      final type = taskMatch != null
          ? TaskListType.task
          : bulletMatch != null
          ? TaskListType.bullet
          : TaskListType.numbered;
      if (cur == null || cur.type != type) {
        cur = TaskSeg([], type: type);
        segs.add(cur);
        stack.clear();
      }
      final match = taskMatch ?? bulletMatch ?? numberedMatch!;
      final indent = _level(match.group(1)!);
      final text = taskMatch != null ? taskMatch.group(3)! : match.group(2)!;
      final t = Task(
        text,
        done: taskMatch != null && taskMatch.group(2) != ' ',
      );
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

String widgetPreview(String content) {
  final lines = content.split('\n');
  final first = lines.indexWhere((line) => line.trim().isNotEmpty);
  if (first < 0) return '';

  String plainText(String line) => line
      .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s+'), '')
      .replaceFirst(RegExp(r'^\s{0,3}>\s?'), '')
      .replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'(\*\*|__|~~|`|\*|_)'), '')
      .trim();

  final preview = <String>[];
  void addTasks(List<Task> tasks, TaskListType type, int depth) {
    var number = 0;
    for (final task in tasks) {
      number++;
      if (type != TaskListType.task || !task.done) {
        final marker = switch (type) {
          TaskListType.task => '☐',
          TaskListType.bullet => '•',
          TaskListType.numbered => '$number.',
        };
        final text = plainText(task.text);
        if (text.isNotEmpty) {
          preview.add('${'  ' * depth}$marker $text');
        }
      }
      addTasks(task.children, type, depth + 1);
    }
  }

  for (final segment in parseDoc(lines.skip(first + 1).join('\n'))) {
    if (segment is TextSeg) {
      preview.addAll(
        segment.text
            .split('\n')
            .map(plainText)
            .where((line) => line.isNotEmpty),
      );
    } else {
      final taskSegment = segment as TaskSeg;
      addTasks(taskSegment.roots, taskSegment.type, 0);
    }
  }

  return preview.take(5).join('\n');
}

String _tasksToMd(List<Task> ts, int d, TaskListType type) {
  final lines = <String>[];
  var number = 0;
  for (final t in ts) {
    if (t.text.trim().isEmpty && t.children.isEmpty) continue;
    number++;
    final marker = switch (type) {
      TaskListType.task => '- [${t.done ? 'x' : ' '}]',
      TaskListType.bullet => '-',
      TaskListType.numbered => '$number.',
    };
    final children = t.children.isEmpty
        ? ''
        : '\n${_tasksToMd(t.children, d + 1, type)}';
    lines.add('${'  ' * d}$marker ${t.text}$children');
  }
  return lines.join('\n');
}

String serializeDoc(List<Segment> segs) {
  final parts = <String>[];
  for (final s in segs) {
    if (s is TextSeg) {
      parts.add(s.text);
    } else {
      final taskSeg = s as TaskSeg;
      final md = _tasksToMd(taskSeg.roots, 0, taskSeg.type);
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
      if (!identical(t, exclude) && t.text.toLowerCase().contains(q))
        out.add(t);
      walk(t.children);
    }
  }

  for (final s in segs) {
    if (s is TaskSeg && s.type == TaskListType.task) walk(s.roots);
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
void reorderVisible(
  List<Task> all,
  bool Function(Task) vis,
  int oldI,
  int newI,
) {
  final visible = all.where(vis).toList();
  if (newI > oldI) newI -= 1;
  final item = visible.removeAt(oldI);
  visible.insert(newI, item);
  var k = 0;
  for (var i = 0; i < all.length; i++) {
    if (vis(all[i])) all[i] = visible[k++];
  }
}
