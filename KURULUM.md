# Alpflix iOS — TestFlight kurulumu (bir kez, ~15 dk)

Her şey GitHub'da: depo herkese açık olduğu için GitHub'ın Mac makineleri ücretsiz. `main`'e her push'ta
"Derleme denetimi" (derleme + simülatör) ve "TestFlight" (Xcode 26, imzalı derleme + yükleme) çalışır. İmza için
profil/sertifika gerekmez: dağıtım sertifikası ve App Store profili API anahtarıyla kendiliğinden oluşturulur.

## 1. App Store Connect API anahtarı (Admin)
1. https://appstoreconnect.apple.com → **Users and Access** → üstte **Integrations** → solda **App Store Connect API**.
2. **Team Keys** sekmesi (Individual Keys değil). Anahtar yerine **Request Access** çıkarsa bas, şartları kabul et.
3. **+** → Name: `Alpflix GitHub` · Access: **Admin** (sertifika/profil oluşturmak için) → **Generate**.
4. Aynı sayfada:
   - **Issuer ID**: listenin üstünde (uzun, tireli; yanında Copy).
   - **Key ID**: anahtarın satırında (10 karakter).
   - **Download**: `AuthKey_<KeyID>.p8` dosyası (yalnız bir kez indirilir).
   Not: "Team ID" ve "Developer ID" (hesap sayfasındaki) bunlar değil.

## 2. Uygulama kaydı (bir kez)
1. https://developer.apple.com/account/resources/identifiers → **+** → **App IDs** → **App** →
   Description `Alpflix`, Bundle ID **Explicit** `com.alpflix.ios` → **Register**. (Zaten varsa geç.)
2. https://appstoreconnect.apple.com/apps → **+** → **New App** → iOS · Name `Alpflix` (alınmışsa `Alpflix Kişisel`) ·
   Türkçe · Bundle ID `com.alpflix.ios` · SKU `alpflix-ios` → **Create**. (Zaten varsa geç.)

## 3. GitHub secret'ları
https://github.com/alpondes/Alpflix-iOS/settings/secrets/actions → **New repository secret**, dört tane:

| Name | Secret |
|---|---|
| `ASC_KEY_ID` | Key ID (10 karakter) |
| `ASC_ISSUER_ID` | Issuer ID (tireli uzun kod) |
| `ASC_KEY_P8` | `.p8` dosyasının **tüm içeriği**: `-----BEGIN PRIVATE KEY-----` satırından `-----END PRIVATE KEY-----` satırına kadar (dosyayı bir metin düzenleyiciyle aç, hepsini kopyala) |
| `TMDB_API_TOKEN` | themoviedb.org → Ayarlar → API → **API Read Access Token** (uzun olan) |

Secret'lar herkese açık depoda da gizlidir; kimse göremez, log'a yazılmaz.

## 4. Derleme ve yükleme
https://github.com/alpondes/Alpflix-iOS/actions/workflows/testflight.yml → **Run workflow** → **Run workflow**.
~20–30 dk; yeşil olunca Apple derlemeyi 10–30 dk içinde işler ve TestFlight'ta görünür. Sonraki her push kendiliğinden yükler.

## 5. iPhone
1. App Store Connect → uygulama → **TestFlight** → **Internal Testing** yanında **+** → grup oluştur,
   kendini ekle, **Enable automatic distribution** açık.
2. iPhone'a **TestFlight** uygulamasını kur, gelen daveti kabul et → **Alpflix** → **Yükle**.
3. Uygulamada: Ayarlar → **Eklentiler**'e Torrentio adresini ekle ya da **Yedeği içe aktar** (Android yedeği).

Her TestFlight derlemesi 90 gün geçerlidir; push'larla yenilenir. Boş kalan `Alpflix-iOS-derleme` deposunu silebilirsin.
