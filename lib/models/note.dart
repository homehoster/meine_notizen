class NoteAttachment {
  final String name;
  final String filename;
  final String type;
  final int size;

  const NoteAttachment({
    required this.name,
    required this.filename,
    required this.type,
    this.size = 0,
  });

  factory NoteAttachment.fromServer(Map<String, dynamic> json) =>
      NoteAttachment(
        name: json['name'] as String? ?? '',
        filename: json['filename'] as String? ?? 'Anhang',
        type: json['type'] as String? ?? 'application/octet-stream',
        size: int.tryParse('${json['size'] ?? 0}') ?? 0,
      );

  factory NoteAttachment.fromJson(Map<String, dynamic> json) => NoteAttachment(
    name: json['name'] as String? ?? '',
    filename: json['filename'] as String? ?? 'Anhang',
    type: json['type'] as String? ?? 'application/octet-stream',
    size: json['size'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'filename': filename,
    'type': type,
    'size': size,
  };
}

String removeAttachmentImageReferences(String content, String attachmentName) {
  final id = Uri.encodeComponent(attachmentName.split('/').last);
  final imageReference = RegExp(
    r'!\[[^\]]*\]\([^)\r\n]*/file/attachments/' +
        RegExp.escape(id) +
        r"""(?:[?#][^)\s]*)?(?:\s+["'][^)]*["'])?\)""",
  );
  return content.replaceAll(imageReference, '');
}

class PendingAttachment {
  final String path;
  final String filename;
  final String type;
  final int size;
  String? uploadedName;

  PendingAttachment({
    required this.path,
    required this.filename,
    required this.type,
    required this.size,
    this.uploadedName,
  });

  factory PendingAttachment.fromJson(Map<String, dynamic> json) =>
      PendingAttachment(
        path: json['path'] as String,
        filename: json['filename'] as String,
        type: json['type'] as String,
        size: json['size'] as int? ?? 0,
        uploadedName: json['uploadedName'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'path': path,
    'filename': filename,
    'type': type,
    'size': size,
    if (uploadedName != null) 'uploadedName': uploadedName,
  };
}

class NoteLocation {
  final double latitude;
  final double longitude;
  final String placeholder;

  const NoteLocation({
    required this.latitude,
    required this.longitude,
    this.placeholder = '',
  });

  factory NoteLocation.fromJson(Map<String, dynamic> json) => NoteLocation(
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    placeholder: json['placeholder'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    if (placeholder.isNotEmpty) 'placeholder': placeholder,
  };
}

enum NoteState { normal, archived }

class Note {
  String id;
  String content;
  DateTime updated;
  bool pinned;
  bool dirty;
  bool deleted;
  bool busy = false;
  NoteState state;
  String visibility;
  String? visibilityBeforeSpace;
  String? space;
  List<String> tags;
  List<NoteAttachment> attachments;
  List<PendingAttachment> pendingAttachments;
  NoteLocation? location;
  final Set<String> dirtyFields;

  Note({
    required this.id,
    required this.content,
    required this.updated,
    this.pinned = false,
    this.dirty = false,
    this.deleted = false,
    this.state = NoteState.normal,
    this.visibility = 'PRIVATE',
    this.visibilityBeforeSpace,
    this.space,
    List<String>? tags,
    List<NoteAttachment>? attachments,
    List<PendingAttachment>? pendingAttachments,
    this.location,
    Set<String>? dirtyFields,
  }) : tags = tags ?? _extractTags(content),
       attachments = attachments ?? [],
       pendingAttachments = pendingAttachments ?? [],
       dirtyFields = dirtyFields ?? {};

  bool get isLocal => id.startsWith('local-');

  bool get hasPendingMedia => pendingAttachments.isNotEmpty || location != null;

  String get title {
    for (final l in content.split('\n')) {
      final t = l
          .replaceFirst(RegExp(r'^\s*(#+\s*|[-*]\s*(\[[ xX]\]\s*)?)'), '')
          .trim();
      if (t.isNotEmpty) return t;
    }
    return 'Leere Notiz';
  }

  String get preview {
    final lines = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .skip(1)
        .take(2);
    return lines.join(' · ');
  }

  factory Note.fromServer(Map<String, dynamic> json) => Note(
    id: (json['name'] as String).split('/').last,
    content: json['content'] as String? ?? '',
    updated:
        DateTime.tryParse(json['updateTime'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    pinned: json['pinned'] as bool? ?? false,
    state: json['state'] == 'ARCHIVED' ? NoteState.archived : NoteState.normal,
    visibility: json['visibility'] as String? ?? 'PRIVATE',
    visibilityBeforeSpace: json['visibilityBeforeSpace'] as String?,
    space: (json['space'] as String?)?.isEmpty == true
        ? null
        : json['space'] as String?,
    tags:
        (json['tags'] as List?)?.whereType<String>().toList() ??
        _extractTags(json['content'] as String? ?? ''),
    attachments: (json['attachments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NoteAttachment.fromServer)
        .toList(),
    location: json['location'] is Map<String, dynamic>
        ? NoteLocation.fromJson(json['location'] as Map<String, dynamic>)
        : null,
  );

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    content: json['content'] as String? ?? '',
    updated: DateTime.parse(json['updated'] as String),
    pinned: json['pinned'] as bool? ?? false,
    dirty: json['dirty'] as bool? ?? false,
    deleted: json['deleted'] as bool? ?? false,
    state: json['state'] == 'archived' ? NoteState.archived : NoteState.normal,
    visibility: json['visibility'] as String? ?? 'PRIVATE',
    visibilityBeforeSpace: json['visibilityBeforeSpace'] as String?,
    space: json['space'] as String?,
    tags:
        (json['tags'] as List?)?.whereType<String>().toList() ??
        _extractTags(json['content'] as String? ?? ''),
    attachments: (json['attachments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NoteAttachment.fromJson)
        .toList(),
    pendingAttachments: (json['pendingAttachments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PendingAttachment.fromJson)
        .toList(),
    location: json['location'] is Map<String, dynamic>
        ? NoteLocation.fromJson(json['location'] as Map<String, dynamic>)
        : null,
    dirtyFields: json['dirtyFields'] is List
        ? (json['dirtyFields'] as List).whereType<String>().toSet()
        : (json['dirty'] == true ? {'content'} : <String>{}),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'updated': updated.toIso8601String(),
    'pinned': pinned,
    'dirty': dirty,
    'deleted': deleted,
    'state': state.name,
    'visibility': visibility,
    'visibilityBeforeSpace': visibilityBeforeSpace,
    'space': space,
    'tags': tags,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
    'pendingAttachments': pendingAttachments
        .map((attachment) => attachment.toJson())
        .toList(),
    'location': location?.toJson(),
    'dirtyFields': dirtyFields.toList(),
  };
}

List<String> _extractTags(String content) {
  final tags = <String>{};
  for (final match in RegExp(
    r'(?<![\w/])#([A-Za-z0-9_-]+)',
  ).allMatches(content)) {
    final tag = match.group(1);
    if (tag != null) tags.add(tag);
  }
  return tags.toList()..sort();
}
