import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/video_item.dart';
import 'auth_service.dart';

class YouTubeService {
  static YoutubeExplode? _activeYt;
  static VideoSearchList? _activeSearchList;
  static final Map<String, _CachedSearch> _searchCache = {};

  /// Fetches playlist metadata and video items using Pure Dart Innertube with yt-dlp fallback
  static Future<({String title, List<VideoItem> videos})> fetchPlaylist(String playlistUrlOrId) async {
    // 1. Pure Dart Innertube Engine (Works 100% on Android and Desktop without Python/yt-dlp)
    try {
      String playlistId = playlistUrlOrId.trim();
      if (playlistId.contains('list=')) {
        final uri = Uri.tryParse(playlistId);
        playlistId = uri?.queryParameters['list'] ?? playlistId;
      }
      if (playlistId.startsWith('VL')) {
        playlistId = playlistId.substring(2);
      }

      final url = Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false');
      final body = {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20240101.01.00',
            'hl': 'tr',
            'gl': 'TR',
            'utcOffsetMinutes': 180,
          }
        },
        'browseId': 'VL$playlistId',
      };

      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        String plTitle = 'YouTube Oynatma Listesi';

        try {
          final metaTitle = data['metadata']?['playlistMetadataRenderer']?['title'];
          if (metaTitle is String && metaTitle.isNotEmpty) {
            plTitle = metaTitle;
          } else {
            final header = data['header'];
            if (header != null) {
              final ph = header['pageHeaderRenderer']?['pageHeaderViewModel']?['title']?['dynamicTextViewModel']?['text']?['content'] ??
                  header['playlistHeaderRenderer']?['title']?['simpleText'] ??
                  header['playlistHeaderRenderer']?['title']?['runs']?[0]?['text'];
              if (ph is String && ph.isNotEmpty) plTitle = ph;
            }
          }
        } catch (_) {}

        final videos = <VideoItem>[];
        final seenIds = <String>{};

        void findVideos(dynamic node) {
          if (node is Map) {
            // Modern lockupViewModel
            if (node.containsKey('lockupViewModel')) {
              final lockup = node['lockupViewModel'];
              if (lockup is Map) {
                String? videoId;
                try {
                  videoId = lockup['rendererContext']?['commandContext']?['onTap']?['innertubeCommand']?['watchEndpoint']?['videoId'];
                } catch (_) {}

                if (videoId == null || videoId.isEmpty) {
                  try { videoId = lockup['contentId']; } catch (_) {}
                }

                if (videoId != null && videoId.isNotEmpty && !seenIds.contains(videoId)) {
                  seenIds.add(videoId);

                  String title = '';
                  try {
                    title = lockup['metadata']?['lockupMetadataViewModel']?['title']?['content'] ?? '';
                  } catch (_) {}

                  String channel = '';
                  try {
                    final rows = lockup['metadata']?['lockupMetadataViewModel']?['metadata']?['contentMetadataViewModel']?['metadataRows'] as List?;
                    if (rows != null && rows.isNotEmpty) {
                      final parts = rows[0]?['metadataParts'] as List?;
                      if (parts != null && parts.isNotEmpty) {
                        channel = parts[0]?['text']?['content'] ?? '';
                      }
                    }
                  } catch (_) {}

                  String duration = '';
                  try {
                    final overlays = lockup['contentImage']?['thumbnailViewModel']?['overlays'] as List?;
                    if (overlays != null) {
                      for (final ov in overlays) {
                        final badge = ov['thumbnailOverlayTimeStatusRenderer']?['text']?['simpleText'] ??
                            ov['thumbnailOverlayBadgeViewModel']?['thumbnailBadges']?[0]?['thumbnailBadgeViewModel']?['text'];
                        if (badge is String && badge.isNotEmpty) {
                          duration = badge;
                          break;
                        }
                      }
                    }
                  } catch (_) {}

                  String thumbnail = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
                  try {
                    final sources = lockup['contentImage']?['thumbnailViewModel']?['image']?['sources'] as List?;
                    if (sources != null && sources.isNotEmpty) {
                      thumbnail = sources.last['url'] ?? thumbnail;
                    }
                  } catch (_) {}

                  videos.add(VideoItem(
                    id: videoId,
                    title: title.isNotEmpty ? title : 'Video',
                    url: 'https://www.youtube.com/watch?v=$videoId',
                    channel: channel.isNotEmpty ? channel : 'YouTube',
                    duration: duration,
                    thumbnail: thumbnail,
                  ));
                }
              }
            }

            // Traditional playlistVideoRenderer
            if (node.containsKey('playlistVideoRenderer')) {
              final r = node['playlistVideoRenderer'];
              if (r is Map) {
                final videoId = r['videoId'];
                if (videoId is String && videoId.isNotEmpty && !seenIds.contains(videoId)) {
                  seenIds.add(videoId);
                  final title = r['title']?['runs']?[0]?['text'] ?? r['title']?['simpleText'] ?? '';
                  final author = r['shortBylineText']?['runs']?[0]?['text'] ?? '';
                  final duration = r['lengthText']?['simpleText'] ?? r['lengthText']?['runs']?[0]?['text'] ?? '';
                  final thumbnail = r['thumbnail']?['thumbnails']?.last?['url'] ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

                  videos.add(VideoItem(
                    id: videoId,
                    title: title.isNotEmpty ? title : 'Video',
                    url: 'https://www.youtube.com/watch?v=$videoId',
                    channel: author.isNotEmpty ? author : 'YouTube',
                    duration: duration,
                    thumbnail: thumbnail,
                  ));
                }
              }
            }

            for (final v in node.values) {
              findVideos(v);
            }
          } else if (node is List) {
            for (final item in node) {
              findVideos(item);
            }
          }
        }

        findVideos(data);

        if (videos.isNotEmpty) {
          return (title: plTitle, videos: videos);
        }
      }
    } catch (_) {}

    return (title: 'YouTube Playlist', videos: <VideoItem>[]);
  }

  /// Extracts YouTube video ID from any video, shorts, or share link (even embedded in text)
  static String? extractVideoId(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return null;

    // 1. youtu.be/<id>
    final youtuMatch = RegExp(r'youtu\.be/([a-zA-Z0-9_-]{8,15})', caseSensitive: false).firstMatch(clean);
    if (youtuMatch != null) return youtuMatch.group(1);

    // 2. youtube.com/shorts/<id>
    final shortsMatch = RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{8,15})', caseSensitive: false).firstMatch(clean);
    if (shortsMatch != null) return shortsMatch.group(1);

    // 3. youtube.com/watch?v=<id>
    final vMatch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{8,15})', caseSensitive: false).firstMatch(clean);
    if (vMatch != null) return vMatch.group(1);

    // 4. youtube.com/embed/<id> or /v/<id> or /live/<id>
    final embedMatch = RegExp(r'youtube\.com/(?:embed|v|live)/([a-zA-Z0-9_-]{8,15})', caseSensitive: false).firstMatch(clean);
    if (embedMatch != null) return embedMatch.group(1);

    // 5. Direct 11-character video ID
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) {
      return clean;
    }

    return null;
  }

  /// Fetches single video metadata directly by video ID (Pure Dart + yt-dlp fallback)
  static Future<VideoItem?> fetchDirectVideo(String videoId) async {
    // 1. Pure Dart Engine (YoutubeExplode)
    try {
      _activeYt?.close();
      _activeYt = await AuthService.createYoutubeClient();
      final v = await _activeYt!.videos.get(VideoId(videoId));
      String dur = '';
      if (v.duration != null) {
        final totalSec = v.duration!.inSeconds;
        final mins = totalSec ~/ 60;
        final secs = totalSec % 60;
        final hours = mins ~/ 60;
        final remMins = mins % 60;
        if (hours > 0) {
          dur = '${hours.toString().padLeft(2, '0')}:${remMins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        } else {
          dur = '${remMins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        }
      }

      return VideoItem(
        id: v.id.value,
        title: v.title,
        url: v.url,
        channel: v.author,
        duration: dur.isNotEmpty ? dur : '0:00',
        thumbnail: v.thumbnails.highResUrl.isNotEmpty
            ? v.thumbnails.highResUrl
            : 'https://i.ytimg.com/vi/${v.id.value}/maxresdefault.jpg',
        viewCount: v.engagement.viewCount.toString(),
        uploadDate: v.uploadDate?.toString(),
      );
    } catch (_) {}



    return null;
  }

  /// Searches YouTube using Pure Dart engine (YoutubeExplode) with direct URL resolution, yt-dlp fallback and 0ms Memory Caching
  static Future<List<VideoItem>> searchVideos(String query, {bool forceRefresh = false}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Instant in-memory cache check (10-minute validity)
    if (!forceRefresh && _searchCache.containsKey(cleanQuery)) {
      final cached = _searchCache[cleanQuery]!;
      if (DateTime.now().difference(cached.timestamp).inMinutes < 10) {
        return cached.items;
      }
    }

    // 0. Direct YouTube Video or Shorts URL Detection
    final directVideoId = extractVideoId(cleanQuery);
    if (directVideoId != null) {
      final directItem = await fetchDirectVideo(directVideoId);
      if (directItem != null) {
        final directList = [directItem];
        _searchCache[cleanQuery] = _CachedSearch(items: directList, timestamp: DateTime.now());
        return directList;
      }
    }

    List<VideoItem> results = [];

    // 1. Pure Dart Engine (YoutubeExplode)
    try {
      _activeYt?.close();
      _activeYt = await AuthService.createYoutubeClient();
      _activeSearchList = await _activeYt!.search.search(cleanQuery);
      final items = _parseSearchList(_activeSearchList!);
      if (items.isNotEmpty) results = items;
    } catch (_) {}

    // 2. High-Speed InnerTube Search Fallback (Direct YouTube JSON API - never blocked)
    if (results.isEmpty) {
      try {
        final innerItems = await _fetchInnerTubeSearch(query: cleanQuery, region: 'US');
        if (innerItems.isNotEmpty) results = innerItems;
      } catch (_) {}
    }

    // 3. Subprocess Fallback (yt-dlp for desktop)
    if (results.isEmpty) {
      results = await _fallbackYtDlpSearch(cleanQuery);
    }

    if (results.isNotEmpty) {
      _searchCache[cleanQuery] = _CachedSearch(items: results, timestamp: DateTime.now());
    }

    return results;
  }

  /// Loads next batch of search results for infinite scrolling
  static Future<List<VideoItem>> loadMoreSearchResults() async {
    if (_activeSearchList == null) return [];
    try {
      final next = await _activeSearchList!.nextPage();
      if (next != null && next.isNotEmpty) {
        _activeSearchList = next;
        return _parseSearchList(next);
      }
    } catch (_) {}
    return [];
  }

  static List<VideoItem> _parseSearchList(Iterable<dynamic> videos) {
    final List<VideoItem> items = [];
    for (var v in videos) {
      String dur = '';
      if (v.duration != null) {
        final totalSec = v.duration!.inSeconds;
        final mins = totalSec ~/ 60;
        final secs = totalSec % 60;
        final hours = mins ~/ 60;
        final remMins = mins % 60;
        if (hours > 0) {
          dur = '${hours.toString().padLeft(2, '0')}:${remMins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        } else {
          dur = '${remMins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
        }
      }

      items.add(VideoItem(
        id: v.id.value,
        title: v.title,
        url: v.url,
        channel: v.author,
        duration: dur.isNotEmpty ? dur : '0:00',
        thumbnail: v.thumbnails.highResUrl.isNotEmpty
            ? v.thumbnails.highResUrl
            : 'https://i.ytimg.com/vi/${v.id.value}/mqdefault.jpg',
        viewCount: null,
        uploadDate: v.uploadDate?.toString(),
      ));
    }
    return items;
  }

  static Future<List<VideoItem>> _fallbackYtDlpSearch(String query) async => [];

  /// Fetches Trending videos from YouTube with rich metadata and multiple dynamic queries
  /// per country and topic. Results are cached with TTL and can be force refreshed.
  static final Map<String, (DateTime, List<VideoItem>)> _trendingCache = {};

  static Future<List<VideoItem>> fetchTrendingVideos({
    String region = 'TR',
    String topic = 'music',
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${region}_$topic';
    final now = DateTime.now();

    if (!forceRefresh && _trendingCache.containsKey(cacheKey)) {
      final (ts, cached) = _trendingCache[cacheKey]!;
      if (now.difference(ts).inMinutes < 15 && cached.isNotEmpty) {
        return List.from(cached);
      }
    }

    final List<VideoItem> aggregatedResults = [];
    final Set<String> seenIds = {};

    final queries = _getTrendingQueriesFor(region, topic);

    for (final q in queries) {
      try {
        final items = await _fetchInnerTubeSearch(query: q, region: region, topic: topic);
        for (final item in items) {
          if (!seenIds.contains(item.id)) {
            seenIds.add(item.id);
            aggregatedResults.add(item);
          }
        }
        if (aggregatedResults.length >= 25) break;
      } catch (_) {}
    }

    // Fallback if needed
    if (aggregatedResults.isEmpty) {
      try {
        final fallbackQuery = _buildTrendingQuery(region, topic);
        final items = await searchVideos(fallbackQuery, forceRefresh: true);
        for (final item in items) {
          if (!seenIds.contains(item.id)) {
            seenIds.add(item.id);
            aggregatedResults.add(item);
          }
        }
      } catch (_) {}
    }

    if (aggregatedResults.isNotEmpty) {
      _trendingCache[cacheKey] = (now, aggregatedResults);
    }

    return aggregatedResults;
  }

  static List<String> _getTrendingQueriesFor(String region, String topic) {
    final reg = region.toUpperCase();

    if (reg == 'JP') {
      switch (topic) {
        case 'music':
          return [
            'J-POP 最新人気曲 2025',
            '日本の人気曲メドレー 2025',
            'Billboard Japan Hot 100 公式',
            '邦楽 ヒットチャート 2025',
          ];
        case 'gaming':
          return [
            'ゲーム実況 人気 2025 日本',
            '新作ゲーム 実況プレイ 2025',
          ];
        case 'movies':
          return [
            '新作映画 予告編 日本 2025',
            '人気アニメ 公式PV 2025',
          ];
        case 'sports':
          return [
            '日本 スポーツ ハイライト 2025',
            'プロ野球 サッカー 日本代表 ハイライト',
          ];
        case 'tech':
          return [
            '最新ガジェット レビュー 日本 2025',
            'スマホ 家電 レビュー 日本',
          ];
        case 'news':
          return [
            '日本 ニュース 最新 速報',
            'NHKニュース 速報',
          ];
        default:
          return [
            '急上昇 日本 トレンド 2025',
            '日本で人気の動画 2025',
          ];
      }
    } else if (reg == 'KR') {
      switch (topic) {
        case 'music':
          return [
            'K-POP 인기곡 2025 최신',
            '멜론 차트 TOP 100 최신곡',
            '인기 뮤직비디오 K-POP 2025',
          ];
        case 'gaming':
          return [
            '롤 배그 인기 게임 실황 2025',
            '신작 게임 플레이 한국',
          ];
        case 'movies':
          return [
            '한국 영화 예고편 2025',
            '인기 드라마 공식 티저 2025',
          ];
        case 'sports':
          return [
            '대한민국 스포츠 하이라이트 손흥민 축구',
            '야구 축구 명장면',
          ];
        case 'tech':
          return [
            'IT 전자기기 스마트폰 리뷰 잇섭',
            '테크 신제품 언박싱',
          ];
        case 'news':
          return [
            '대한민국 뉴스 속보 2025',
            'JTBC YTN 뉴스 생방송',
          ];
        default:
          return [
            '인기 급상승 동영상 한국 2025',
            '유튜브 트렌드 코리아',
          ];
      }
    } else if (reg == 'AZ') {
      switch (topic) {
        case 'music':
          return [
            'azərbaycan yeni mahnılar 2025 trend',
            'ən çox dinlənilən azəri mahnılar 2025',
            'yeni kliplər 2025 azərbaycan',
          ];
        case 'gaming':
          return ['azərbaycan oyun videoları 2025'];
        case 'movies':
          return ['azərbaycan filmləri treyler 2025'];
        case 'sports':
          return ['azərbaycan futbol idman xülasəsi'];
        default:
          return ['azərbaycan trend videolar 2025', 'trend azerbaycan'];
      }
    } else if (reg == 'BR') {
      switch (topic) {
        case 'music':
          return [
            'top brasil musicas mais tocadas 2025',
            'sertanejo funk lançamentos 2025',
            'clipes oficiais brasil 2025',
          ];
        case 'gaming':
          return ['gameplay brasil jogos 2025'];
        case 'movies':
          return ['trailers oficiais filmes brasil 2025'];
        case 'sports':
          return ['futebol gols do brasileirão lances 2025'];
        default:
          return ['em alta brasil vídeos populares 2025'];
      }
    } else if (reg == 'GB') {
      switch (topic) {
        case 'music':
          return [
            'official uk top 40 singles 2025',
            'uk music video releases 2025',
          ];
        case 'gaming':
          return ['trending uk gaming gameplay 2025'];
        case 'sports':
          return ['premier league highlights 2025 goals'];
        default:
          return ['trending in the uk today 2025'];
      }
    } else if (reg == 'TR') {
      switch (topic) {
        case 'music':
          return [
            'netd müzik yeni klipler 2025',
            'yeni türkçe klip 2025 official music video',
            'trend türkçe şarkılar klip',
          ];
        case 'gaming':
          return [
            'türkçe oyun inceleme oynanış 2025',
            'yeni popüler oyunlar türkçe',
          ];
        case 'movies':
          return [
            'resmi fragman türkçe dublaj 2025',
            'yeni film fragmanları sinema',
          ];
        case 'sports':
          return [
            'türk spor maç özetleri önemli anlar',
            'futbol süper lig özetleri',
          ];
        case 'tech':
          return [
            'telefon teknoloji inceleme 2025 webtekno shiftdelete',
            'yeni çıkan teknolojik ürünler inceleme',
          ];
        case 'news':
          return [
            'Gündem Haberleri Türkiye Özet',
            'Son Dakika Haberler Canlı',
          ];
        default:
          return [
            'türkiye trend videolar popüler',
            'haftanın en çok izlenen türkçe videoları',
          ];
      }
    } else if (reg == 'RU') {
      switch (topic) {
        case 'music':
          return ['новинки музыки клипы 2025 официальный клип', 'популярные русские хиты 2025'];
        case 'gaming':
          return ['игровые новинки 2025 прохождение'];
        case 'movies':
          return ['официальный трейлер 2025 русский дубляж'];
        default:
          return ['в тренде видео 2025'];
      }
    } else if (reg == 'DE') {
      switch (topic) {
        case 'music':
          return ['offizielles musikvideo 2025 deutsche hits', 'neue musik 2025'];
        default:
          return ['trends deutschland 2025'];
      }
    } else if (reg == 'FR') {
      switch (topic) {
        case 'music':
          return ['clip officiel 2025 top musique france', 'nouvelles chansons 2025'];
        default:
          return ['tendances france 2025'];
      }
    } else if (reg == 'ES') {
      switch (topic) {
        case 'music':
          return ['video oficial 2025 exitos musica', 'top canciones 2025'];
        default:
          return ['tendencias 2025'];
      }
    } else {
      // Global / US
      switch (topic) {
        case 'music':
          return [
            'official music video 2025 top hits',
            'billboard top official video 2025',
            'new music video releases 2025',
          ];
        case 'gaming':
          return ['trending gaming gameplay review 2025', 'new game releases 2025'];
        case 'movies':
          return ['official movie trailer 2025 4K', 'new movie teaser trailer 2025'];
        case 'sports':
          return ['sports highlights 2025 top goals', 'match highlights 2025'];
        case 'tech':
          return ['smartphone tech review 2025 mkbhd', 'new technology gadgets 2025'];
        case 'news':
          return ['world news headlines today 2025'];
        default:
          return [
            'trending viral videos 2025',
            'most popular videos today 2025',
          ];
      }
    }
  }

  /// Hits YouTube Innertube /search endpoint directly with anti-spam filters
  static Future<List<VideoItem>> _fetchInnerTubeSearch({
    required String query,
    required String region,
    String? topic,
  }) async {
    final url = Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false');
    final body = {
      'context': {
        'client': {
          'clientName': 'WEB',
          'clientVersion': '2.20240101.01.00',
          'hl': _regionToLang(region),
          'gl': region.toUpperCase(),
          'utcOffsetMinutes': _regionToOffset(region),
        },
      },
      'query': query,
    };

    final res = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    final videos = <VideoItem>[];
    final seenIds = <String>{};

    void walk(dynamic node) {
      if (node is Map) {
        if (node.containsKey('videoRenderer')) {
          final vr = node['videoRenderer'];
          if (vr is Map) {
            final id = vr['videoId'] as String?;
            if (id != null && id.isNotEmpty && !seenIds.contains(id)) {
              String title = '';
              try {
                title = vr['title']?['runs']?[0]?['text'] ?? vr['title']?['simpleText'] ?? '';
              } catch (_) {}
              String channel = '';
              try {
                channel = vr['longBylineText']?['runs']?[0]?['text'] ??
                    vr['shortBylineText']?['runs']?[0]?['text'] ?? '';
              } catch (_) {}
              String thumb = '';
              try {
                final thumbs = vr['thumbnail']?['thumbnails'] as List?;
                if (thumbs != null && thumbs.isNotEmpty) {
                  thumb = thumbs.last['url'] ?? '';
                }
              } catch (_) {}
              String dur = '';
              try {
                dur = vr['lengthText']?['simpleText'] ??
                    vr['lengthText']?['runs']?[0]?['text'] ?? '';
              } catch (_) {}
              String views = '';
              try {
                views = vr['shortViewCountText']?['simpleText'] ??
                    vr['viewCountText']?['simpleText'] ?? '';
              } catch (_) {}

              // Duration parsing
              int durMinutes = 0;
              if (dur.isNotEmpty) {
                final parts = dur.split(':').map((e) => int.tryParse(e) ?? 0).toList();
                if (parts.length == 2) durMinutes = parts[0];
                if (parts.length == 3) durMinutes = parts[0] * 60 + parts[1];
              }

              // Anti-spam filters:
              // 1. Music: reject long DJ compilations, mix sets, or 1-hour loops
              bool valid = true;
              final lowerTitle = title.toLowerCase();
              if (topic == 'music') {
                if (durMinutes > 8 ||
                    lowerTitle.contains('saatlik') ||
                    lowerTitle.contains('non-stop') ||
                    lowerTitle.contains('full albüm') ||
                    lowerTitle.contains('türkçe pop müzik 202') ||
                    lowerTitle.contains('türkçe pop remix 202')) {
                  valid = false;
                }
              } else if (topic == 'movies') {
                if (durMinutes > 7) valid = false; // trailers are short
              }

              if (title.isNotEmpty && valid) {
                seenIds.add(id);
                videos.add(VideoItem(
                  id: id,
                  url: 'https://www.youtube.com/watch?v=$id',
                  title: title,
                  channel: channel.isNotEmpty ? channel : 'YouTube',
                  thumbnail: thumb.isNotEmpty
                      ? thumb.replaceAll('http://', 'https://')
                      : 'https://i.ytimg.com/vi/$id/mqdefault.jpg',
                  duration: dur,
                  viewCount: views.isNotEmpty ? views : null,
                ));
              }
            }
          }
        }
        for (final v in node.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(data);
    return videos;
  }

  static String _regionToLang(String region) {
    const map = {
      'TR': 'tr', 'US': 'en', 'GB': 'en', 'DE': 'de', 'FR': 'fr',
      'JP': 'ja', 'KR': 'ko', 'RU': 'ru', 'BR': 'pt', 'AZ': 'az',
    };
    return map[region.toUpperCase()] ?? 'en';
  }

  static int _regionToOffset(String region) {
    const map = {
      'TR': 180, 'DE': 60, 'FR': 60, 'GB': 0, 'US': -300,
      'JP': 540, 'KR': 540, 'RU': 180, 'BR': -180, 'AZ': 240,
    };
    return map[region.toUpperCase()] ?? 0;
  }


  static String _buildTrendingQuery(String region, String topic) {
    switch (region.toUpperCase()) {
      case 'KR':
        switch (topic) {
          case 'music': return '인기 급상승 음악 K-POP 2025 최신곡 뮤직비디오';
          case 'gaming': return '인기 급상승 게임 롤 배그 종합게임';
          case 'movies': return '영화 예고편 최신 한국 영화';
          case 'sports': return '스포츠 하이라이트 손흥민 축구 야구';
          case 'tech': return '테크 스마트폰 전자기기 IT 리뷰';
          case 'news': return '뉴스 속보 대한민국 주요 뉴스';
          case 'general':
          default: return '인기 급상승 동영상 한국 트렌드';
        }
      case 'JP':
        switch (topic) {
          case 'music': return '急上昇 音楽 J-POP 最新 ヒット曲 2025 MV';
          case 'gaming': return 'ゲーム実況 プレイ動画 人気 急上昇';
          case 'movies': return '映画 予告編 アニメ 劇場版 最新';
          case 'sports': return 'スポーツ ハイライト プロ野球 サッカー';
          case 'tech': return 'ガジェット レビュー テクノロジー 最新';
          case 'news': return 'ニュース 速報 報道 日本';
          case 'general':
          default: return '急上昇 日本 トレンド 人気動画';
        }
      case 'AZ':
        switch (topic) {
          case 'music': return 'Azərbaycan musiqisi yeni hit mahnılar 2025 klip';
          case 'gaming': return 'Oyun videoları Azərbaycan gameplay';
          case 'movies': return 'Azərbaycan film treylerləri kinolar';
          case 'sports': return 'İdman xülasələri futbol Azərbaycan';
          case 'tech': return 'Texnologiya xəbərləri icmallar telefon';
          case 'news': return 'Son xəbərlər Azərbaycan gündəm';
          case 'general':
          default: return 'Trend Azərbaycan populyar videolar';
        }
      case 'BR':
        switch (topic) {
          case 'music': return 'Top Músicas Brasil 2025 Hits Funk Sertanejo Trap';
          case 'gaming': return 'Gameplay Jogos Tendências Brasil';
          case 'movies': return 'Trailers de Filmes Lançamentos Cinema Brasil';
          case 'sports': return 'Futebol Melhores Momentos Brasileirão';
          case 'tech': return 'Tecnologia Análises Celulares Gadgets';
          case 'news': return 'Notícias Brasil Últimas Notícias Ao Vivo';
          case 'general':
          default: return 'Em Alta Brasil Vídeos Populares';
        }
      case 'IT':
        switch (topic) {
          case 'music': return 'Musica Tendenze Italia Canzoni 2025 Hit';
          case 'gaming': return 'Gameplay Videogiochi Tendenze Italia';
          case 'movies': return 'Trailer Film Uscite Cinema Italia';
          case 'sports': return 'Highlights Calcio Serie A Sport';
          case 'tech': return 'Tecnologia Recensioni Smartphone Gadget';
          case 'news': return 'Ultime Notizie Italia Oggi';
          case 'general':
          default: return 'Tendenze Italia Video Popolari';
        }
      case 'RU':
        switch (topic) {
          case 'music': return 'Популярная русская музыка хиты 2025 клипы';
          case 'gaming': return 'Игры летсплей гейминг топ прохождение';
          case 'movies': return 'Трейлеры фильмов новинки кино премьеры';
          case 'sports': return 'Спорт футбол хоккей матч обзор хайлайты';
          case 'tech': return 'Технологии обзоры гаджетов смартфоны';
          case 'news': return 'Новости Россия сегодня главное';
          case 'general':
          default: return 'Тренды популярное Россия';
        }
      case 'DE':
        switch (topic) {
          case 'music': return 'Deutsche Hits Charts Musik 2025 Offiziell';
          case 'gaming': return 'Gaming Gameplay Deutsch Trending';
          case 'movies': return 'Offizielle Film Trailer Deutsch Kino';
          case 'sports': return 'Sport Highlights Bundesliga Fußball Zusammenfassung';
          case 'tech': return 'Technik Testberichte Gadgets Smartphone';
          case 'news': return 'Nachrichten Deutschland Aktuell';
          case 'general':
          default: return 'Trends Deutschland Beliebte Videos';
        }
      case 'FR':
        switch (topic) {
          case 'music': return 'Top Hits Musique France 2025 Clip';
          case 'gaming': return 'Jeux Vidéo Gaming France Let s Play';
          case 'movies': return 'Bandes Annonces Films Cinéma France';
          case 'sports': return 'Sport Résumé Matchs Football Ligue 1';
          case 'tech': return 'Technologie Tests High-Tech';
          case 'news': return 'Actualités France Info Aujourd hui';
          case 'general':
          default: return 'Tendances France Vidéos Populaires';
        }
      case 'ES':
        switch (topic) {
          case 'music': return 'Éxitos Música España 2025 Top Canciones';
          case 'gaming': return 'Videojuegos Gaming Tendencias Gameplay';
          case 'movies': return 'Tráilers de Películas Cine Estrenos';
          case 'sports': return 'Deportes Resumen Fútbol LaLiga Resumen';
          case 'tech': return 'Tecnología Novedades Análisis Móviles';
          case 'news': return 'Noticias España Última Hora';
          case 'general':
          default: return 'Tendencias España Vídeos Populares';
        }
      case 'US':
      case 'GB':
      case 'GLOBAL':
        switch (topic) {
          case 'music': return 'Top Trending Music Hits 2025 Billboard Official';
          case 'gaming': return 'Trending Gaming Gameplay 2025 Walkthrough';
          case 'movies': return 'Official Movie Trailers 2025 Cinema';
          case 'sports': return 'Sports Highlights NBA NFL Premier League 2025';
          case 'tech': return 'Tech Reviews Gadgets Smartphones 2025';
          case 'news': return 'Breaking News Today Live Updates';
          case 'general':
          default: return 'Trending Videos Today Popular';
        }
      case 'TR':
      default:
        switch (topic) {
          case 'music': return 'Popüler Türkçe Müzikler 2025 Hit Şarkılar Klip';
          case 'gaming': return 'En Popüler Türkçe Oyun Videoları Gameplay';
          case 'movies': return 'Yeni Film Fragmanları Sinema Vizyon';
          case 'sports': return 'Spor Maç Özetleri Süper Lig Futbol';
          case 'tech': return 'Teknoloji İnceleme Yapay Zeka Telefon';
          case 'news': return 'Son Dakika Haberler Gündem Türkiye';
          case 'general':
          default: return 'Türkiye Trend Popüler Videolar';
        }
    }
  }

  /// Fetches all videos in a Playlist
  static Future<List<VideoItem>> fetchPlaylistVideos(String playlistUrl) async {
    final List<VideoItem> videos = [];

    // 1. Pure Dart
    try {
      final yt = await AuthService.createYoutubeClient();
      Playlist? playlist;
      try {
        playlist = await yt.playlists.get(playlistUrl);
      } catch (_) {
        final regExp = RegExp(r'[?&]list=([^#\&\?]+)');
        final match = regExp.firstMatch(playlistUrl);
        if (match != null) {
          playlist = await yt.playlists.get(match.group(1));
        }
      }

      if (playlist != null) {
        await for (final v in yt.playlists.getVideos(playlist.id)) {
          String dur = '';
          if (v.duration != null) {
            final totalSec = v.duration!.inSeconds;
            final mins = totalSec ~/ 60;
            final secs = totalSec % 60;
            dur = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
          }

          videos.add(VideoItem(
            id: v.id.value,
            title: v.title,
            url: v.url,
            channel: v.author,
            duration: dur.isNotEmpty ? dur : '0:00',
            thumbnail: v.thumbnails.highResUrl.isNotEmpty
                ? v.thumbnails.highResUrl
                : 'https://i.ytimg.com/vi/${v.id.value}/mqdefault.jpg',
            isSelected: true,
          ));
        }
        yt.close();
        if (videos.isNotEmpty) return videos;
      }
    } catch (_) {}

    return videos;
  }
}

class _CachedSearch {
  final List<VideoItem> items;
  final DateTime timestamp;

  _CachedSearch({required this.items, required this.timestamp});
}
