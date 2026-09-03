# YTDx Studio - Video & Ses İndirme Motoru Mimarisi (Linux & Android)

Bu belge, YouTube'un son dönem bot koruma mekanizmalarına (SABR, n-sig, PO-Token, 403 Forbidden) karşı geliştirilen ve hem **Linux (Masaüstü)** hem de **Android (Mobil)** için kusursuz çalışan indirme mimarisini detaylandırmaktadır.

---

## 1. MİMARİ AYRIM (Neden Linux ve Android Farklı?)

- **Linux (Masaüstü):** 
  - Sistemde Python, Node.js ve FFmpeg tam donanımlı olarak mevcuttur.
  - İndirme motoru olarak **en güncel `yt-dlp` (Nightly)** + **Node.js (JS Challenge Solver)** + **FFmpeg (Remuxer)** kullanılır.
  - 8K, 4K, 2K, 1080p60 HDR ve 320k MP3/M4A/FLAC doğrudan tam kalitede indirilir.

- **Android (Mobil):**
  - Harici binary (Python/yt-dlp) çalıştırılamaz; uygulama boyutu ve pil verimliliği için **Saf Dart (YoutubeExplode)** + **Android Donanım Hızlandırmalı Native MediaMuxer** kullanılır.
  - Video ve ses ayrı DASH akışları olarak saf TCP/HTTP üzerinden tek parça çekilir, ardından cihazın yerel donanımıyla arka planda birleştirilir.

---

## 2. LINUX MOTORU: Çözülen Sorunlar ve Çalışma Prensibi

### A. Sorunlar:
1. **403 Forbidden Hatası:** YouTube, video oynatma parametrelerinde JavaScript ile hesaplanan `n` parametresini (n-sig challenge) zorunlu kılmaktadır. JavaScript çalışma ortamı (runtime) olmadan veya eski yt-dlp sürümlerinde googlevideo sunucuları 10-30 MB sonra `HTTP 403 Forbidden` döndürür.
2. **360p'ye Düşme:** Bazı istemciler (`player_client=android`) YouTube tarafından kısıtlanarak sadece itag 18 (360p) vermeye zorlanmıştır.
3. **Parça Parça İndirme Sorunu:** `--concurrent-fragments` parametresi akışı sunucudan parçalara bölerek çekmeye çalıştığında sunucu bağlantıyı aniden kesmekteydi.

### B. Çözüm (Nasıl Yapıldı?):
1. **En Son Nightly Sürüm:** `yt-dlp` kütüphanesi en güncel sürüme yükseltildi (`yt-dlp[default]` / `--pre`).
2. **Node.js Runtime Entegrasyonu:** Sistemdeki Node.js binary'si otomatik tespit edilir (`/usr/bin/node`, `fnm`, `nvm` dizinleri taranır) ve yt-dlp'ye `--js-runtimes "node:<PATH>"` olarak verilir. Bu sayede tüm n-sig şifreleri yerel olarak anında çözülür.
3. **Tek Parça Akış:** `--concurrent-fragments` kaldırıldı. İndirme standart, kararlı ve kesintisiz tek akışla yapılır.
4. **Doğal İstemci Seçimi:** `android_vr` gibi sunucu tarafından engellenen istemciler zorlanmaz; yt-dlp'nin modern `VisionOS` ve `Web` istemcilerini otomatik seçmesine izin verilir.
5. **Kalite Formatları:**
   - 8K: `bestvideo[height<=4320]+bestaudio/best`
   - 4K: `bestvideo[height<=2160]+bestaudio/best`
   - 2K: `bestvideo[height<=1440]+bestaudio/best`
   - 1080p: `bestvideo[height<=1080]+bestaudio/best`
   - 720p: `bestvideo[height<=720]+bestaudio/best`
   - 480p / 360p: İlgili çözünürlük filtresi
   - Auto: `bestvideo+bestaudio/best` (Maksimum kalite)
   - Ses: `-x --audio-format [mp3/m4a/flac] --audio-quality 0` (FFmpeg ile en yüksek kalite ve kapak resmi)

---

## 3. ANDROID MOTORU: Çözülen Sorunlar ve Çalışma Prensibi

### A. Sorunlar:
1. **Uygulama Donması / ANR ("Sistem: Çık ya da Bekle"):** Video ve ses birleştirme işlemi (`muxVideoAndAudio`) Android ana arayüz iş parçacığında (UI Main Thread) senkron çalışıyordu. 500 MB - 1 GB'lık dosya birleştirilirken arayüz 20 saniye kilitleniyor ve Android işletim sistemi ANR diyaloğu açıyordu.
2. **1 GB'lık Videonun 500 MB veya 150 MB'a Düşmesi (Kalite Kısması):**
   - Kodun içerisinde, DASH akışı takıldığında kullanıcıya hissettirmeden 360p (itag 18) muxed akışına düşen sessiz bir fallback vardı.
   - 'Auto' modu seçildiğinde çözünürlük filtreleri boş dönüyor ve en yüksek kalite yerine düşük kaliteli akışlara yöneliyordu.
3. **Format Uyumsuzluğu:** Android'in native `MediaMuxer`'ı MPEG_4 modunda sadece H.264 (AVC) ve AAC kabul eder. WebM/VP9 video veya Opus ses gelirse hata veriyordu.

### B. Çözüm (Nasıl Yapıldı?):
1. **Asenkron Arka Plan Muxer (Sıfır Donma):**
   - `MainActivity.kt` içerisindeki `muxVideoAndAudio` metodu `Thread { ... }` içine alındı.
   - İşlem bittiğinde `runOnUiThread { result.success(...) }` ile Flutter'a dönülür.
   - Arayüz 120 FPS akıcı kalır, kilitlenme ve ANR tamamen yok edildi.
2. **Dinamik Konteyner Desteği:**
   - Video WebM ise: WebM (Opus) ses ile eşleştirilir ve Android `MediaMuxer.OutputFormat.MUXER_OUTPUT_WEBM` kullanılır.
   - Video MP4 ise: M4A (AAC) ses ile eşleştirilir ve `MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4` kullanılır.
3. **Sessiz 360p Düşürme Kaldırıldı:**
   - İstenen kalite ne ise (4K, 1080p vb.) doğrudan o kalitedeki akış indirilir. Sessizce 360p'ye düşme iptal edildi.
   - 'Auto' modu manifestteki en yüksek bitrate ve çözünürlüğe sahip akışı seçer.
4. **Temiz Manifest Çağrısı:**
   - `streamsClient.getManifest(videoId, requireWatchPage: false)` doğrudan `androidSdkless` istemcisiyle çağrılır; imzasız/hatalı 403 veren ekstra istemciler zorlanmaz.
5. **Kesintisiz Akış:**
   - Stream doğrudan `streamsClient.get(streamInfo)` üzerinden çekilir. 40 saniyelik güvenlik zaman aşımı timer'ı sadece akış tamamen kesilirse devreye girer.

---

## 4. KOD REFERANSLARI

- **Linux yt-dlp & Dart Motor Yöneticisi:** `aura_app/lib/services/download_manager.dart`
- **İkili Konumlandırıcı (Node, Python, yt-dlp):** `aura_app/lib/services/backend_locator.dart`
- **Python Bağımsız Runner:** `src/pytube_runner.py`
- **Android Donanım Muxer'ı:** `aura_app/android/app/src/main/kotlin/com/alllivesupport/ytdx/aura_app/MainActivity.kt`
- **Android Köprü Servisi:** `aura_app/lib/services/native_media_muxer.dart`
