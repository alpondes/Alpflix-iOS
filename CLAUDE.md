# Alpflix iOS — Claude Code çalışma notları

Alpflix'in (Android, `alpondes/Alpflix`) iPhone sürümü: SwiftUI, iOS 17+, kişisel kullanım, TestFlight.
İlk sürüm: keşfet, arama, yapım sayfası (sezon/bölüm, izlendi), Stremio eklentileriyle kaynaklar,
VLC oynatıcı (ses/altyazı/hız, kaldığın yer, sıradaki bölüm), kütüphane durumları, izlemeye devam et, indirme (arka planda, yalnız Wi-Fi; sezonu indir),
Android yedeğini içe aktarma. Hesap ve sunucu yok; veri cihazda tek JSON (`LibraryStore`).

## Kurallar (Android ile aynı)
- Puanlama yok. Yapay zekâ özelliği yok. Analitik/reklam yok. Trakt yok. Doğrudan debrid API yok.
  Kaçak sitelerden kazıma yok. Uygulama içinde torrent motoru yok (torrent kaynakları gösterilir, oynatılmaz).
- Gizli değerler depoya girmez: TMDB anahtarı GitHub secret'ından (TMDB_API_TOKEN) derlemede
  `Alpflix/Core/BuildSecrets.swift`'e yazılır (depoda boş) ya da uygulamada Ayarlar'dan girilir.
  Eklenti adresleri arayüzde maskelenir (`maskedUrl`), hata metnine ve log'a yazılmaz.
- Türkçe arayüz; metinler `App/Strings.swift` (`L`) içinde, görünümlerde sabit metin yok.
- Tasarım: `App/Theme.swift` (zemin #121014, metin #EDE8E3, vurgu #F2784B; Archivo / Atkinson Hyperlegible
  Next / IBM Plex Mono, fontlar `Resources/Fonts`). Saf siyah/beyaz, mor-mavi gradyan, buzlu cam yok.

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
