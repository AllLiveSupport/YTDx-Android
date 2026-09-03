class CustomPlaylist {
  final String id;
  String title;
  String? description;
  String iconName;
  int colorValue;
  final List<String> trackPaths;
  final DateTime createdAt;

  CustomPlaylist({
    required this.id,
    required this.title,
    this.description,
    this.iconName = 'music_note',
    this.colorValue = 0xFF3B82F6,
    List<String>? trackPaths,
    DateTime? createdAt,
  })  : trackPaths = trackPaths ?? [],
        createdAt = createdAt ?? DateTime.now();

  bool get isFavorites => id == 'favorites';

  factory CustomPlaylist.fromJson(Map<String, dynamic> json) {
    return CustomPlaylist(
      id: json['id'] as String? ?? 'playlist_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Çalma Listesi',
      description: json['description'] as String?,
      iconName: json['iconName'] as String? ?? 'music_note',
      colorValue: json['colorValue'] as int? ?? 0xFF3B82F6,
      trackPaths: (json['trackPaths'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'iconName': iconName,
        'colorValue': colorValue,
        'trackPaths': trackPaths,
        'createdAt': createdAt.toIso8601String(),
      };
}
