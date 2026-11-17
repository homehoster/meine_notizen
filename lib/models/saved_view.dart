import 'note.dart';

class SavedView {
  final String id;
  final String name;
  final String icon;
  final String? textContains;
  final String? tag;
  final bool? pinned;
  final bool? hasAttachments;
  final bool? hasLocation;

  const SavedView({
    required this.id,
    required this.name,
    this.icon = '◉',
    this.textContains,
    this.tag,
    this.pinned,
    this.hasAttachments,
    this.hasLocation,
  });

  bool matches(Note note) {
    final query = textContains?.trim().toLowerCase();
    if (query != null &&
        query.isNotEmpty &&
        !note.content.toLowerCase().contains(query)) {
      return false;
    }
    final selectedTag = tag?.trim();
    if (selectedTag != null &&
        selectedTag.isNotEmpty &&
        !note.tags.contains(selectedTag)) {
      return false;
    }
    if (pinned != null && note.pinned != pinned) return false;
    if (hasAttachments != null &&
        (note.attachments.isNotEmpty || note.pendingAttachments.isNotEmpty) !=
            hasAttachments) {
      return false;
    }
    if (hasLocation != null && (note.location != null) != hasLocation) {
      return false;
    }
    return true;
  }

  factory SavedView.fromJson(Map<String, dynamic> json) => SavedView(
    id: json['id'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String? ?? '◉',
    textContains: json['textContains'] as String?,
    tag: json['tag'] as String?,
    pinned: json['pinned'] as bool?,
    hasAttachments: json['hasAttachments'] as bool?,
    hasLocation: json['hasLocation'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'textContains': textContains,
    'tag': tag,
    'pinned': pinned,
    'hasAttachments': hasAttachments,
    'hasLocation': hasLocation,
  };
}
