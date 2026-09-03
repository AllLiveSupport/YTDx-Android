class VideoItem {
  final String id;
  final String title;
  final String url;
  final String channel;
  final String duration;
  final String thumbnail;
  final String? viewCount;
  final String? uploadDate;
  bool isSelected;

  VideoItem({
    required this.id,
    required this.title,
    required this.url,
    required this.channel,
    required this.duration,
    required this.thumbnail,
    this.viewCount,
    this.uploadDate,
    this.isSelected = true,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) {
    String vidId = json['id'] ?? '';
    String vidUrl = json['url'] ?? (vidId.isNotEmpty ? 'https://www.youtube.com/watch?v=$vidId' : '');
    
    // Format duration
    String dur = '';
    if (json['duration'] != null) {
      if (json['duration'] is int) {
        int sec = json['duration'];
        int mins = sec ~/ 60;
        int secs = sec % 60;
        int hours = mins ~/ 60;
        mins = mins % 60;
        if (hours > 0) {
          dur = '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        } else {
          dur = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        }
      } else {
        dur = json['duration'].toString();
      }
    }

    String thumb = json['thumbnail'] ?? '';
    if (thumb.isEmpty && vidId.isNotEmpty) {
      thumb = 'https://i.ytimg.com/vi/$vidId/mqdefault.jpg';
    }

    return VideoItem(
      id: vidId,
      title: json['title'] ?? 'YouTube Video',
      url: vidUrl,
      channel: json['uploader'] ?? json['channel'] ?? 'YouTube',
      duration: dur.isNotEmpty ? dur : '0:00',
      thumbnail: thumb,
      viewCount: json['view_count'] != null ? '${json['view_count']} views' : json['viewCount'],
      uploadDate: (json['upload_date'] ?? json['uploadDate'])?.toString(),
      isSelected: json['isSelected'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'channel': channel,
    'duration': duration,
    'thumbnail': thumbnail,
    'viewCount': viewCount,
    'uploadDate': uploadDate,
    'isSelected': isSelected,
  };
}
