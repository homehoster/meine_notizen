class MemoSpace {
  final String name;
  final String title;
  final String description;
  final String emoji;
  final String lucideIcon;
  final int memberCount;

  const MemoSpace({
    required this.name,
    required this.title,
    this.description = '',
    this.emoji = '',
    this.lucideIcon = '',
    this.memberCount = 1,
  });

  factory MemoSpace.fromServer(Map<String, dynamic> json) {
    final icon = json['icon'] as Map<String, dynamic>? ?? const {};
    return MemoSpace(
      name: json['name'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      emoji: icon['emoji'] as String? ?? '',
      lucideIcon: icon['lucide'] as String? ?? '',
      memberCount: json['memberCount'] as int? ?? 1,
    );
  }

  factory MemoSpace.fromJson(Map<String, dynamic> json) => MemoSpace(
    name: json['name'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    emoji: json['emoji'] as String? ?? '',
    lucideIcon: json['lucideIcon'] as String? ?? '',
    memberCount: json['memberCount'] as int? ?? 1,
  );

  String get id => name.split('/').last;

  Map<String, dynamic> toJson() => {
    'name': name,
    'title': title,
    'description': description,
    'emoji': emoji,
    'lucideIcon': lucideIcon,
    'memberCount': memberCount,
  };

  Map<String, dynamic> toRequestJson() => {
    'title': title,
    'description': description,
    'icon': {
      if (emoji.isNotEmpty) 'emoji': emoji,
      if (lucideIcon.isNotEmpty) 'lucide': lucideIcon,
    },
  };
}
