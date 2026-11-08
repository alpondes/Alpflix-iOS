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
1. https://codemagic.io → **Sign up with GitHub** → `alpondes/Alpflix-iOS` deposunu ekle
   (proje türü sorulursa **codemagic.yaml**).
2. **Personal account / Team settings → Integrations → Developer Portal → Connect**:
   ad tam olarak **`Alpflix ASC`**, Issuer ID, Key ID ve `.p8` dosyası.
3. **Code signing identities → iOS certificates → Generate certificate**
   (tür: Apple Distribution, az önceki anahtarla). Sertifika Codemagic'te saklanır.
4. **Code signing identities → iOS provisioning profiles → Fetch profiles**. `com.alpflix.ios` için
   App Store profili yoksa: developer.apple.com → **Profiles → +** → **App Store Connect** → App ID
   `com.alpflix.ios` → Codemagic'in oluşturduğu sertifika → ad `Alpflix AppStore` → **Generate**;
   sonra Codemagic'te yeniden **Fetch profiles**.
5. Uygulamanın sayfasında **Environment variables**: grup adı **`alpflix`**, değişken
   `TMDB_API_TOKEN` = TMDB okuma anahtarın (v4), **Secure** işaretli. (Yoksa uygulamada Ayarlar'dan da girilebilir.)
6. **Start new build** → workflow **Alpflix iOS → TestFlight** → dal `main`.

## 5. iPhone
1. App Store Connect → uygulama → **TestFlight → Internal Testing → +** grup oluştur, kendini ekle,
   **Automatic Distribution** açık olsun.
2. iPhone'a **TestFlight** uygulamasını kur, gelen daveti kabul et → **Alpflix** → Yükle.
3. Uygulamada: Ayarlar → **Eklentiler**'e Torrentio adresini ekle ya da **Android yedeğini içe aktar**
   (Alpflix Android'deki yedek dosyası; eklentiler yedekte varsa onlar da gelir).

Her derleme 90 gün geçerli; `main`'e her push yeni derleme yükler.
