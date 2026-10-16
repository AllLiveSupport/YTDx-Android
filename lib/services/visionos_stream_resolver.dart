import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_logger.dart';
import 'auth_service.dart';

/// High-performance stream resolver that queries YouTube's VisionOS player client.
/// Bypasses YouTube CDN's 60-second / 174MB playback cutoff on standard Android streams,
/// returning direct media URLs that permit unrestricted Range requests across the entire file
/// (8K, 4K, 2K, 1080p, and high-bitrate audio) at full line speed with zero 403 blocks.
class VisionosStreamResolver {
  static const _tag = 'VisionOSResolver';
  static String? _cachedVisitorData;
  static DateTime? _visitorDataExpiry;
  static final Map<String, Map<int, String>> _urlCache = {};

  /// Fetches a fresh visitor data token from YouTube or returns cached / fallback token.
  static Future<String> _getVisitorData() async {
    if (_cachedVisitorData != null &&
        _visitorDataExpiry != null &&
        DateTime.now().isBefore(_visitorDataExpiry!)) {
      return _cachedVisitorData!;
    }

    try {
      final res = await http.get(
        Uri.parse('https://www.youtube.com'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
          'Cookie': 'CONSENT=YES+cb; SOCS=CAESEwgDEgk2MzE5NzUyMDMaAmVuIAEaBgiA_LyaBg',
        },
      ).timeout(const Duration(seconds: 4));

      final match = RegExp(r'"VISITOR_DATA"\s*:\s*"([^"]+)"').firstMatch(res.body);
      if (match != null && match.group(1) != null) {
        _cachedVisitorData = match.group(1)!;
        _visitorDataExpiry = DateTime.now().add(const Duration(hours: 2));
        return _cachedVisitorData!;
      }
    } catch (e) {
      AppLogger.warn(_tag, 'VisitorData çekme uyarısı: $e');
    }

    // Battle-tested fallback visitor token
    return 'CgtTMjZHeWdaR1VDYyibmLjWBjIKCgJUUhIEGgAgZ2KzAgqwAkN1RUJDQVVTa3dFQjhRWnVaaHpabUhxelN4NUtNX0xLOVN5U28tUDlPaEQyUlplQXNXV216Y0NhQUFVdWFPUTkydEwxeGxJdXF3dE0xaHo1cTFGaUd0ZmNlRGFka2tNMnJ1ZG5ON09JNk1IeUJ6bnhneHR2RTVMMnhjSFpnQ19ib01tX1RSV2ZLangzOE40SGxmd1AwRWlYVlpCOWQxZXR2TXNxRElERmQ3eS01ZTNaUVhMbU5OMHkwX3lab3k1enRvWjFxVXktS1VaaUxiNG9CVEpGQWQ2cG5VX1pFdE10d1kwWjJmanllQWM3dEVONHJpUk0xbDU2TVF2YVdBT3phVS1lVnFBZ0RsRXZoNEhaUGkyQlV2Xy1NMkJGbmZHNDhEQnJDSHlTSFBCOUtUWVA%3D';
  }

  /// Resolves an unthrottled direct media stream URL for the specified [videoId] and [itag].
  static Future<String?> getStreamUrl(String videoId, int itag, {bool forceRefresh = false}) async {
    if (videoId.isEmpty) return null;

    if (!forceRefresh && _urlCache.containsKey(videoId)) {
      final cached = _urlCache[videoId]?[itag];
      if (cached != null) return cached;
    }

    try {
      final visitorData = await _getVisitorData();
      final payload = {
        'context': {
          'client': {
            'clientName': 'VISIONOS',
            'clientVersion': '1.02',
            'deviceMake': 'Apple',
            'deviceModel': 'RealityDevice17,1',
            'userAgent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
            'osName': 'visionOS',
            'osVersion': '26.5.23O471',
            'hl': 'en',
            'timeZone': 'UTC',
            'utcOffsetMinutes': 0,
          }
        },
        'videoId': videoId,
        'playbackContext': {
          'contentPlaybackContext': {
            'html5Preference': 'HTML5_PREF_WANTS',
            'signatureTimestamp': 20733,
          }
        },
        'contentCheckOk': true,
        'racyCheckOk': true,
      };

      final headers = <String, String>{
        'X-YouTube-Client-Name': '101',
        'X-YouTube-Client-Version': '1.02',
        'Origin': 'https://www.youtube.com',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'content-type': 'application/json',
        'X-Goog-Visitor-Id': visitorData,
      };

      final token = await AuthService.getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['authorization'] = 'Bearer $token';
      }

      final res = await http
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/player'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final streamingData = data['streamingData'];
        if (streamingData != null) {
          final adaptive = streamingData['adaptiveFormats'] as List? ?? [];
          final formats = streamingData['formats'] as List? ?? [];
          final map = <int, String>{};
          for (final f in [...adaptive, ...formats]) {
            final t = f['itag'];
            final u = f['url'];
            if (t is int && u is String && u.isNotEmpty) {
              map[t] = u;
            }
          }
          _urlCache[videoId] = map;
          final resolved = map[itag];
          if (resolved != null) {
            AppLogger.success(_tag, '🚀 VisionOS unthrottled URL çözüldü: itag=$itag, videoId=$videoId');
          }
          return resolved;
        }
      }
    } catch (e) {
      AppLogger.warn(_tag, 'VisionOS streaming data çözme uyarısı: $e');
    }
    return null;
  }
}
