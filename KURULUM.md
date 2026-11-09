# Alpflix iOS — TestFlight kurulumu (bir kez, ~20 dk)

> Depo şu an herkese açık: GitHub her push'ta uygulamayı ücretsiz Mac'te derleyip simülatörde açıyor
> ("Derleme denetimi"). TestFlight kurulumu bitince depoyu yeniden gizliye alabilirsin
> (Settings → General → Danger Zone → Change visibility); Codemagic gizli depoyla da çalışır, denetim işi
> gizliyken kendiliğinden durur. Boş kalan `Alpflix-iOS-derleme` deposunu silebilirsin.

Mac gerekmez; hepsi tarayıcıdan (tablet/telefon da olur). Derleme **Codemagic**'in ücretsiz kotasında
(ayda 500 dk Mac M2) yapılır, kart girilmezse ücret çıkmaz.

## 1. App Store Connect API anahtarı
1. https://appstoreconnect.apple.com → **Users and Access** → **Integrations** → **App Store Connect API**.
2. **Team Keys** → **+** → ad: `Alpflix Codemagic`, erişim: **App Manager** → **Generate**.
3. `.p8` dosyasını indir (yalnız bir kez indirilebilir), **Key ID** ve sayfanın üstündeki **Issuer ID**'yi not et.
   `.p8` içeriğini sohbete yapıştırma.

## 2. Uygulama kimliği (Apple Developer)
1. https://developer.apple.com/account/resources/identifiers → **+** → **App IDs** → **App**.
2. Description: `Alpflix`, Bundle ID: **Explicit** → `com.alpflix.ios` → **Register**.

## 3. App Store Connect'te uygulama kaydı
1. https://appstoreconnect.apple.com/apps → **+** → **New App**.
2. Platform: iOS · Name: `Alpflix` (alınmışsa `Alpflix Kişisel`) · Dil: Türkçe ·
   Bundle ID: `com.alpflix.ios` · SKU: `alpflix-ios` · Erişim: Full Access → **Create**.

## 4. Codemagic
Codemagic'te ayarlar "takım" düzeyindedir; tek başına kullanıyorsan takımın adı **Personal Account**'tur.
Aşağıdaki yollar oradan başlar (sol menüde **Teams** → **Personal Account**). Bir takım açtıysan aynı adımları
o takımın sayfasında yap; kişisel hesap ile takım ayrıdır, anahtar ve sertifikalar birinden ötekine geçmez.

1. https://codemagic.io → **Sign up with GitHub** → **Add application** → GitHub → `alpondes/Alpflix-iOS`
   (proje türü sorulursa **Other** / **codemagic.yaml**).
2. **API anahtarı:** Teams → Personal Account → **Integrations** → **Developer Portal** → **Connect**
   (ya da **Manage keys** → **Add key**): **App Store Connect API key name** alanına tam olarak **`Alpflix ASC`**,
   sonra **Issuer ID**, **Key ID** ve `.p8` dosyası → **Save**.
3. **Sertifika:** Teams → Personal Account → **codemagic.yaml settings** → **Code signing identities** →
   **iOS certificates** sekmesi → **Generate certificate**:
   - Certificate type: **Apple Distribution**
   - App Store Connect API key: `Alpflix ASC`
   - Reference name: `alpflix_dagitim` (herhangi bir ad olur) → **Generate**.
   Sertifika Codemagic'te saklanır, Apple Developer'da da görünür.
4. **Profil:** aynı yerde **iOS provisioning profiles** sekmesi → **Fetch profiles** → `com.alpflix.ios` için
   **App Store** profilini seç → reference name `alpflix_profil` → **Download selected**.
   Listede yoksa önce oluştur: developer.apple.com → **Certificates, IDs & Profiles** → **Profiles** → **+** →
   Distribution altında **App Store Connect** → **Continue** → App ID `com.alpflix.ios` → sertifika olarak
   3. adımda oluşan **Apple Distribution** sertifikası → ad `Alpflix AppStore` → **Generate**. Sonra Codemagic'te
   yeniden **Fetch profiles**.
5. **TMDB anahtarı:** Applications → **Alpflix-iOS** → **Environment variables** sekmesi → Variable name
   `TMDB_API_TOKEN`, Variable value: TMDB okuma anahtarın, Group: `alpflix` (yeni grup) → **Secure** işaretli → **Add**.
6. **Derleme:** Applications → Alpflix-iOS → **Start new build** → workflow **Alpflix iOS → TestFlight**,
   branch `main` → **Start new build**. Yaklaşık 15–25 dk; bitince TestFlight'a yüklenir
   (Apple'ın işlemesi 10–30 dk daha).

Not: codemagic.yaml imza dosyalarını paket kimliğinden (`com.alpflix.ios`) kendisi bulur; reference name'leri
yaml'a yazman gerekmez.

## 5. iPhone
1. App Store Connect → uygulama → **TestFlight → Internal Testing → +** grup oluştur, kendini ekle,
   **Automatic Distribution** açık olsun.
2. iPhone'a **TestFlight** uygulamasını kur, gelen daveti kabul et → **Alpflix** → Yükle.
3. Uygulamada: Ayarlar → **Eklentiler**'e Torrentio adresini ekle ya da **Android yedeğini içe aktar**
   (Alpflix Android'deki yedek dosyası; eklentiler yedekte varsa onlar da gelir).

Her derleme 90 gün geçerli; `main`'e her push yeni derleme yükler.
