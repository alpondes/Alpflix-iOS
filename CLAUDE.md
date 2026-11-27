# Alpflix iOS — Claude Code çalışma notları

Alpflix'in (Android, `alpondes/Alpflix`) iPhone sürümü: SwiftUI, iOS 17+, kişisel kullanım, TestFlight.
İlk sürüm: keşfet, arama, yapım sayfası (sezon/bölüm, izlendi), Stremio eklentileriyle kaynaklar,
VLC oynatıcı (ses/altyazı/hız, kaldığın yer, sıradaki bölüm), kütüphane durumları, izlemeye devam et, indirme (arka planda, yalnız Wi-Fi; sezonu indir),
Android yedeğini içe aktarma. 0.6: listeler ve akıllı listeler, tarihli izleme / buraya kadar / sezonu izledim,
İlgilenmiyorum, dizi rozetleri, kişi sayfası ve takip, ana sayfa düzeni (Türkiye ve mevsim satırları), takvim ve
yeni bölüm bildirimi, istatistikler, oynatıcıda altyazı gecikmesi/görünümü, basılı tut 2x, parlaklık/ses kaydırma,
duraklatınca oyuncular, Wyzie Subs, bir kerelik Trakt içe aktarma (kullanıcı adı + Client ID ya da ZIP).
0.7: Wi-Fi eşitleme (Android ile aynı protokol, `Sync/`): Bonjour `_alpflix._tcp`, 12 karakterlik eşleştirme kodu,
AES-GCM şifreli TCP çerçeveleri; kaldığın yer, izlemeler/silmeler, durumlar, İzlemeye devam et kaldırmaları.
0.8 (Android 5.4.0 ile aynı): dosya parmak iziyle sürüme göre altyazı (`VideoHash`), gece modu (VLC ekolayzeri +
sıkıştırıcı), ses gecikmesi, "Hâlâ izliyor musun?", rastgele bölüm, oynatma bilgisi, iki parmakla yakınlaştırma.
0.9 (Android 5.5.0 ile aynı): Platformlar yeni tasarım (sekmeler, platform çoklu süzgeç, tür, tarih/ad sıralaması,
gün başlıkları); ad kuralı `TMDBClient.named` (Türk yapımı özgün adıyla, yabancı yapım İngilizce; en-US adları kalıcı
önbellekte) şimdilik Platformlar'da.
1.0 (Android 6.0.0 ile aynı): sinematik sade tasarım (ana sayfada öne çıkan `HeroBanner`, afişlerde ince kenar,
iPad'de geniş afiş ve okunur genişlikte yapım sayfası), Platformlar'da Dijitale düşenler sekmesi (`DigitalDrops`,
sinemadan dijitale; son 30 gün ve yakında), ağ istekleri `concurrentMap` ile paralel (Platformlar, ana sayfa,
takvim, takip, afiş tamamlama).
1.1 (Android 6.1.0 ile aynı): İzlemediklerimi indir, indirme kalitesi (`DownloadPick`: Küçük/Dengeli/En iyi, HEVC/AV1
önce, boyut sınırı), internetsiz açılış (TMDB ayrıntı/sezon `tmdb-cache` diske; çevrimdışıyken ana sayfada indirilenler,
`NetworkStatus`).
2.0 (Android 7.0.0 ile aynı): pano düzeni — ana sayfada `HomeDashboard` (bu akşam, dijitale düştü, bu hafta, Netflix 1
numara, İzleyeceklerim, bu ay), `Components/Bento.swift` (`BentoTile`, `TileLabel`, `GlassBorder`, `glassCapsule`: iOS 26'da
Liquid Glass, öncesinde ince malzeme); iOS 26'da sistemin yüzen cam sekme çubuğu; İstatistikler ve Platformlar kutulu
(Platformlar'da sayılı bölüm kutuları, `PlatformsRoute(tab:)`).
2.1: taşma düzeltmesi — geniş görseller `BackdropImage` ile (doğal genişliği yerleşimi büyütmez; `.fill` görsele
`frame(maxWidth: .infinity)` verme, sütunu ekrandan taşırır). Ana sayfada başlık çubuğu gizli: öne çıkan görsel durum
çubuğunun altına uzanır, üstte cam takvim/profil düğmeleri (`HomeTopButtons`); görsel yokken tarihli kendi başlığı.
iOS 26'da gezinme çubuğuna özel görünüm verilmez (başlıklar hiç çizilmiyordu). Simülatör denetimi TMDB anahtarıyla
derlenir (ekran görüntülerinde gerçek içerik).
2.1.1 (Android 7.0.1 ile aynı): atlama zamanlarında TheIntroDB'de eksik tür introdb.app'ten (IMDb) tamamlanır.
Hesap ve sunucu yok; veri cihazda tek JSON (`LibraryStore`).

## Kurallar (Android ile aynı)
- Puanlama yok. Yapay zekâ özelliği yok. Analitik/reklam yok. Trakt yok. Doğrudan debrid API yok.
  Kazıma yasağı kullanıcı kararıyla kaldırıldı (2.2; yöntem kullanıcıyla birlikte seçilir). Uygulama içinde torrent motoru yok (torrent kaynakları gösterilir, oynatılmaz).
- Gizli değerler depoya girmez: TMDB anahtarı GitHub secret'ından (TMDB_API_TOKEN) derlemede
  `Alpflix/Core/BuildSecrets.swift`'e yazılır (depoda boş) ya da uygulamada Ayarlar'dan girilir.
  Eklenti adresleri arayüzde maskelenir (`maskedUrl`), hata metnine ve log'a yazılmaz.
- Türkçe arayüz; metinler `App/Strings.swift` (`L`) içinde, görünümlerde sabit metin yok.
- Tasarım: `App/Theme.swift` (zemin #121014, metin #EDE8E3, vurgu #F2784B; Archivo / Atkinson Hyperlegible
  Next / IBM Plex Mono, fontlar `Resources/Fonts`). Saf siyah/beyaz, mor-mavi gradyan yok. Cam yalnız görselin üstündeki düğmelerde ve sekme çubuğunda (kullanıcı kararı, 2.0).

## Derleme
- Mac yok; depo herkese açık, GitHub Actions'ın Mac makineleri ücretsiz:
  - `.github/workflows/derleme-denetimi.yml`: XcodeGen → CocoaPods (MobileVLCKit 3.6) → imzasız derleme +
    simülatörde her sekmenin açılışı (ekran görüntüleri günlükte base64).
  - `.github/workflows/testflight.yml` (macos-26, Xcode 26 — Apple iOS 26 SDK istiyor): codemagic-cli-tools ile
    dağıtım sertifikası + App Store profili API anahtarından oluşturulur/alınır, imzalı IPA, `app-store-connect publish`.
    Sertifika özel anahtarı `Config/signing/dist-key.enc` (AES-256, şifre .p8'in SHA-256'sı; fastlane match gibi).
    Secret'lar: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, TMDB_API_TOKEN.
- Kurulum: `KURULUM.md`. Xcode projesi ve Pods depoda yok (`.gitignore`); her derlemede üretilir.
- Bulut konteynerinde Swift derleyicisi yok; sözdizimi tree-sitter ile, gerisi Actions'ta denetlenir.
