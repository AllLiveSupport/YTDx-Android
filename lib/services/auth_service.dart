import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'app_logger.dart';

/// YouTube isteklerini Google OAuth oturumu ve modern tarayıcı kimliğiyle donatan HTTP istemcisi.
/// Bu istemci bot algılamasını, 429 hız sınırlarını ve yaş kısıtlamalarını aşar.
class AuthenticatedYoutubeHttpClient extends YoutubeHttpClient {
  final String? accessToken;

  AuthenticatedYoutubeHttpClient([this.accessToken, http.Client? client])
      : super(client);

  @override
  Map<String, String> get headers {
    final base = Map<String, String>.from(super.headers);
    base['user-agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    base['cookie'] = 'CONSENT=YES+cb';
    base['accept-language'] = 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7';
    return base;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Sadece Google Video medya akışlarına veya Innertube API isteklerine token ekle.
    // www.youtube.com/watch gibi HTML web sayfalarına ASLA Bearer token eklenmemelidir,
    // aksi halde Google Web sunucusu isteği 401/redirect ile reddederek VideoUnavailable hatası verir!
    final host = request.url.host.toLowerCase();
    final path = request.url.path.toLowerCase();

    if (accessToken != null && accessToken!.isNotEmpty) {
      if (host.contains('googlevideo.com') || path.contains('/youtubei/')) {
        request.headers['authorization'] = 'Bearer $accessToken';
      }
    }
    return super.send(request);
  }
}

class AuthService {
  static const String _tag = 'AuthService';

  static const String clientId = '861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com';
  static const String clientSecret = 'SboVhoG9s0rNafixCSGGKXAT';
  static const String deviceCodeUrl = 'https://oauth2.googleapis.com/device/code';
  static const String tokenUrl = 'https://oauth2.googleapis.com/token';
  static const String scope = 'http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content';

  /// Google hesabı bağlıysa yetkilendirilmiş, bağlı değilse bot korumalı YoutubeExplode istemcisi üretir
  static Future<YoutubeExplode> createYoutubeClient() async {
    final token = await getAccessToken();
    if (token != null && token.isNotEmpty) {
      AppLogger.success(_tag, '🔑 Google OAuth Yetkilendirmesi devrede: YouTube oturumu aktif');
    }
    return YoutubeExplode(httpClient: AuthenticatedYoutubeHttpClient(token));
  }

  static Future<File> getTokensFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/tokens.json');
    } catch (_) {
      return File('tokens.json');
    }
  }

  static Future<bool> isLinked() async {
    try {
      final file = await getTokensFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        return json['access_token'] != null;
      }
    } catch (_) {}
    return false;
  }

  static Future<String?> getAccessToken() async {
    try {
      final file = await getTokensFile();
      if (file.existsSync()) {
        final content = await file.readAsString();
        final json = jsonDecode(content);
        return json['access_token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearTokens() async {
    try {
      final file = await getTokensFile();
      if (file.existsSync()) {
        await file.delete();
      }
      final localFile = File('tokens.json');
      if (localFile.existsSync()) {
        localFile.deleteSync();
      }
    } catch (_) {}
  }

  /// Initiates authentic Google OAuth 2.0 Device Flow
  static Future<Map<String, dynamic>> initiateDeviceAuth() async {
    try {
      AppLogger.info(_tag, 'Google Device OAuth akışı başlatılıyor...');
      final response = await http.post(
        Uri.parse(deviceCodeUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': clientId,
          'scope': scope,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        AppLogger.success(_tag, 'Google cihaz kodu alındı: ${data['user_code']}');
        return {
          'status': 'ok',
          'user_code': data['user_code'] ?? '',
          'device_code': data['device_code'] ?? '',
          'verification_url': data['verification_url'] ?? 'https://www.google.com/device',
          'interval': data['interval'] ?? 5,
          'expires_in': data['expires_in'] ?? 1800,
        };
      } else {
        AppLogger.error(_tag, 'Google API yanıt hatası: ${response.statusCode} - ${response.body}');
        return {
          'status': 'error',
          'message': 'Google API hatası: HTTP ${response.statusCode}',
        };
      }
    } catch (e) {
      AppLogger.error(_tag, 'Bağlantı hatası: $e');
      return {
        'status': 'error',
        'message': 'Bağlantı hatası: $e',
      };
    }
  }

  /// Polls Google token endpoint until user confirms or timeout
  static Stream<bool> pollDeviceToken(String deviceCode, {int intervalSeconds = 5, int maxWaitSeconds = 1800}) async* {
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime).inSeconds < maxWaitSeconds) {
      await Future.delayed(Duration(seconds: intervalSeconds));

      try {
        final response = await http.post(
          Uri.parse(tokenUrl),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': clientId,
            'client_secret': clientSecret,
            'code': deviceCode,
            'grant_type': 'http://oauth.net/grant_type/device/1.0',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['access_token'] != null) {
            final tokenData = {
              'access_token': data['access_token'],
              'refresh_token': data['refresh_token'],
              'token_type': data['token_type'] ?? 'Bearer',
              'expires_in': data['expires_in'],
              'created_at': DateTime.now().toIso8601String(),
            };

            // Write tokens to secure app directory
            final file = await getTokensFile();
            await file.writeAsString(jsonEncode(tokenData));
            try {
              File('tokens.json').writeAsStringSync(jsonEncode(tokenData));
            } catch (_) {}

            AppLogger.success(_tag, '🎉 Google hesabı başarıyla bağlandı ve token kaydedildi!');
            yield true;
            return;
          }
        } else {
          try {
            final err = jsonDecode(response.body);
            final error = err['error'];
            if (error == 'authorization_pending') {
              AppLogger.info(_tag, 'Doğrulama bekleniyor (authorization_pending)...');
              yield false;
              continue;
            } else if (error == 'slow_down') {
              intervalSeconds += 2;
              yield false;
              continue;
            } else {
              AppLogger.error(_tag, 'OAuth polling hatası: $error');
              yield false;
              return;
            }
          } catch (_) {
            yield false;
          }
        }
      } catch (e) {
        AppLogger.warn(_tag, 'Polling ağ hatası: $e');
        yield false;
      }
    }
  }
}
