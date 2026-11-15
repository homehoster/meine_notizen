class Note {
  String id;
  String content;
  DateTime updated;
  bool pinned;
  bool dirty;
  bool deleted;
  bool busy = false;

  Note({
    required this.id,
    required this.content,
    required this.updated,
    this.pinned = false,
    this.dirty = false,
    this.deleted = false,
  });

  bool get isLocal => id.startsWith('local-');

  String get title {
    for (final l in content.split('\n')) {
      final t = l.replaceFirst(RegExp(r'^\s*(#+\s*|[-*]\s*(\[[ xX]\]\s*)?)'), '').trim();
      if (t.isNotEmpty) return t;
    }
    return 'Leere Notiz';
  }

  String get preview {
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).skip(1).take(2);
    return lines.join(' · ');
  }

  factory Note.fromServer(Map<String, dynamic> j) => Note(
        id: (j['name'] as String).split('/').last,
        content: (j['content'] as String?) ?? '',
        updated: DateTime.tryParse((j['updateTime'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
        pinned: (j['pinned'] as bool?) ?? false,
      );

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'],
        content: j['content'],
        updated: DateTime.parse(j['updated']),
        pinned: j['pinned'] ?? false,
        dirty: j['dirty'] ?? false,
        deleted: j['deleted'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'updated': updated.toIso8601String(),
        'pinned': pinned,
        'dirty': dirty,
        'deleted': deleted,
      };
}
