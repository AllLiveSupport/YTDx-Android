# 🛡️ YTDx Studio: YouTube PO Token (Proof of Origin) & BotGuard Savunma Mimarisi (B Planı)

Bu doküman, YouTube'un gelecekte uygulayabileceği `po_token` (Proof of Origin), `visitor_data` ve BotGuard WebAssembly meydan okumalarına karşı YTDx Studio'nun geliştirdiği ve devreye alabileceği çok katmanlı savunma stratejisini detaylandırır.

---

## 1. PO Token ve BotGuard Nedir? Neden Ortaya Çıktı?

Google, YouTube video akışlarını botlardan, izleyicilerden ve yetkisiz üçüncü parti indiricilerden korumak amacıyla web ve mobil istemcilerinde kademeli olarak **BotGuard** sistemini zorunlu kılmaktadır:

```
[Kullanıcı / Tarayıcı] 
       │
       ▼ (1) YouTube Web Sayfasını veya Oynatıcıyı Açar
[Google BotGuard (Wasm/JS VM)] 
       │
       ▼ (2) Cihaz Çevre Denetimi (Canvas, WebGL, Touch, Headers, Timing)
[po_token (Proof of Origin) Üretimi] 
       │
       ▼ (3) Innertube /player İsteğine Eklenir: visitorData + poToken
[YouTube Sunucuları] ──▶ (4) Onaylanırsa: Tam Hız Akış URL'leri (4K/1080p DASH)
                     ──▶ (5) Başarısızsa: 403 Forbidden veya 50 KB/s Throttling
```

---

## 2. GitHub Devleri Bunu Nasıl Çözüyor? (Sektör Analizi)

Dünyadaki popüler açık kaynak YouTube projeleri PO Token krizini şu 3 ana yaklaşımla yönetmektedir:

| Proje | Platform | Kullandığı PO Token Çözümü | Güçlü / Zayıf Yönü |
|---|---|---|---|
| **yt-dlp** | Python (CLI) | Node.js tabanlı `youtube-po-token-generator` / `bgUtils` veya tarayıcıdan `--cookies-from-browser` aktarımı | Sunucuda Node.js/Chrome gerektirir; mobilde doğrudan çalıştırılamaz. |
| **NewPipe** | Android (Java) | Innertube İstemci Değişimi (`IOS`, `ANDROID_TESTSUITE`) + Web Scraping Fallback | Basit ve hafiftir ancak YouTube tüm mobil istemcileri sıkılaştırdığında aralıklı güncelleme gerektirir. |
| **ReVanced** | Android (Patch) | GmsCore (MicroG) üzerinden sahte Play Integrity yanıtı veya iOS / VR istemci spoof yaması | Yalnızca yamalanmış resmi YouTube uygulamasında çalışır; bağımsız uygulamalarda çalışmaz. |
| **Cobalt** | Node.js (Web) | Arka planda Docker içinde çalışan özel PO Token API servisi | Kendi API sunucusunu barındırmayı gerektirir. |

---

## 3. YTDx Studio'nun "Efsane B Planı": 3 Aşamalı Mobil Zırh Mimarisi

Bir Android uygulamasında bulunmamız bize komut satırı (CLI) veya web araçlarında olmayan **büyük bir yerel avantaj** sağlar: **Cihazın içinde Google onaylı gerçek bir Chromium motoru (Android System WebView) mevcuttur!**

YTDx Studio için tasarlanan 3 katmanlı B Planı:

```
                          ┌─────────────────────────────────────────────────────────────┐
                          │                İndirme Talebi (DownloadTask)                │
                          └──────────────────────────────┬──────────────────────────────┘
                                                         │
                                    ┌────────────────────┴────────────────────┐
                                    ▼                                         ▼
                     [KATMAN 1: OAuth & Client Spoofing]          [KATMAN 2: Muxed Fallback]
                     - Google Bearer Token                         - itag 18 (360p)
                     - Innertube iOS / Android Music Client        - itag 22 (720p)
                     - PO Token zorunluluğu yoktur                 - PO Token kontrolü yoktur
                                    │                                         │
                                    ▼ (Eğer YouTube İleride Tamamen Kilitlerse)│
                     ┌──────────────────────────────────────────────┐         │
                     │    KATMAN 3: Headless Android WebView         │         │
                     │    - 1x1 piksellik görünmez WebView          │         │
                     │    - Gerçek Chromium DOM + BotGuard çalışır  │         │
                     │    - Taze visitor_data + po_token üretir     │         │
                     │    - 12 saat önbellekler                     │         │
                     └──────────────────────┬───────────────────────┘         │
                                            │                                 │
                                            ▼                                 ▼
                                    ┌───────────────────────────────────────────────┐
                                    │      %100 Başarılı & Kesintisiz İndirme       │
                                    └───────────────────────────────────────────────┘
```

### Katman 1: Google OAuth Yetkilendirmesi & İstemci Değişimi (Aktif)
- **Google OAuth**: `AuthenticatedYoutubeHttpClient` aracılığıyla Ayarlar'dan bağlanan Google hesabı, isteklere `Authorization: Bearer $token` ekler. Google, kendi onaylı kullanıcı oturumlarına anonim botlara uyguladığı kaba PO Token blokajını uygulamaz.
- **İstemci Değişimi (Client Spoofing)**: YouTube, iOS istemcisine (`com.google.ios.youtube`) BotGuard (WebAssembly) çalıştıramadığı için PO Token şartı koyamaz. İhtiyaç anında `youtube_explode_dart` istekleri iOS istemcisine yönlendirilir.

### Katman 2: Progressive Muxed (itag 18 / 22) Dokunulmazlığı (Aktif)
- YouTube; eski akıllı televizyonlar (Smart TV), web sitelerindeki iframe gömülü videolar ve düşük hızlı mobil tarayıcılar için tek parça birleşik akışları (360p ve 720p) **daima açık tutmak zorundadır**.
- YTDx Studio'nun Muxed Fallback Zırhı, YouTube DASH adaptif akışlara PO Token zorunluluğu getirdiğinde dahi anında tek parça akışa geçerek indirmeyi başarıyla tamamlar.

### Katman 3: Headless (Görünmez) Android WebView İle Otomatik PO Token Üretimi (Hazır B Planı)
YouTube ileride oturumlu veya oturumsuz fark etmeksizin tüm adaptif akışlara %100 PO Token zorunluluğu getirirse devreye girecek nihai çözüm:
1. Flutter içinde görünmez (0x0 veya 1x1 piksel) bir `InAppWebView` başlatılır.
2. WebView, `https://www.youtube.com/embed/` adresini açar.
3. Android WebView gerçek bir tarayıcı ortamı olduğu için YouTube'un BotGuard WebAssembly kodunu resmi olarak çalıştırır ve geçerli bir `po_token` ile `visitor_data` üretilir.
4. WebView'ın `evaluateJavascript` köprüsüyle üretilen `po_token` yakalanır ve hafızada 12 saat saklanır.
5. İndirme motoru (`DownloadManager`), tüm akış isteklerine bu gerçek token'ı ekler.
6. **Sonuç**: Sunucu tarafı bunu resmi bir Chrome/Android cihazı olarak gördüğü için engelleme ihtimali **sıfırdır**.

---

## 4. Sonuç ve Güvenlik Değerlendirmesi

YTDx Studio, tek bir kütüphaneye bağımlı kalmayan, çok katmanlı geri çekilme (fallback) mimarisi sayesinde YouTube'un anti-bot değişikliklerine karşı piyasadaki bağımsız en dayanıklı açık kaynak mimarilerden birine sahiptir.
