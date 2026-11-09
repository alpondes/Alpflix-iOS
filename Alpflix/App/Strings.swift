/// Arayüz metinleri (Türkçe). Sabit kodlanmış metin yok; hepsi burada.
enum L {
    static let tabHome = "Ana Sayfa"
    static let tabDiscover = "Keşfet"
    static let tabSearch = "Ara"
    static let tabLibrary = "Kütüphane"
    static let tabSettings = "Ayarlar"

    static let continueWatching = "İzlemeye devam et"
    static let watchlist = "İzleyeceklerim"
    static let removeFromContinue = "İzlemeye devam et'ten kaldır"
    static let trending = "Bu hafta trend"
    static let popularMovies = "Popüler filmler"
    static let popularSeries = "Popüler diziler"
    static let nowPlaying = "Vizyonda"
    static let onTheAir = "Yayında olan diziler"
    static let topRated = "En sevilenler"
    static let movies = "Filmler"
    static let series = "Diziler"
    static let all = "Tümü"
    static let genres = "Türler"
    static let platforms = "Platformlar"
    static let upcoming = "Yakında"
    static let periodThisWeek = "Bu hafta"
    static let periodNextWeek = "Gelecek hafta"
    static let periodComingWeeks = "Önümüzdeki haftalar"
    static let periodLater = "Daha sonra"
    static let kindNewSeries = "Yeni dizi"
    static func kindNewSeason(_ n: Int) -> String { "\(n). sezon başlıyor" }
    static let kindDigital = "Dijital çıkış"
    static func today(_ text: String) -> String { "Bugün: \(text)" }
    static let unknownPlatform = "Platform belli değil"
    static let reminders = "Hatırlatıcıların"
    static let remind = "Hatırlat"
    static let removeReminder = "Hatırlatıcıyı kaldır"
    static let upcomingEmpty = "Yakında bir çıkış bulunamadı."
    static let netflixTop10 = "Netflix Türkiye Top 10"
    static func weekEnding(_ date: String) -> String { "Hafta sonu: \(date)" }
    static let newEntry = "Yeni"
    static let sameRank = "Aynı"
    static func weeksCount(_ n: Int) -> String { "\(n) hafta" }
    static func platformNew(_ name: String) -> String { "\(name): son gelenler" }
    static let top10Failed = "Netflix listesi alınamadı."
    static let platformsCredit = "Netflix Top 10: Netflix Tudum (haftalık). Platform verileri JustWatch'tan (TMDB üzerinden)."

    static let searchPrompt = "Film, dizi ara"
    static let searchEmpty = "Sonuç bulunamadı."
    static let searchHint = "Aramak için en az iki harf yaz."

    static let play = "Oynat"
    static let resume = "Devam et"
    static let sources = "Kaynaklar"
    static let seasons = "Sezonlar"
    static func season(_ n: Int) -> String { "\(n). sezon" }
    static let cast = "Oyuncular"
    static let trailer = "Fragman"
    static let providersCredit = "Türkiye'de izlenebildiği platformlar · JustWatch"
    static let recommendations = "Benzer yapımlar"
    static let markWatched = "İzlendi olarak işaretle"
    static let markUnwatched = "İzlenmedi olarak işaretle"
    static let status = "Durum"
    static let removeStatus = "Kütüphaneden çıkar"
    static func minutesLeft(_ m: Int) -> String { "\(m) dk kaldı" }
    static func nextUp(_ code: String) -> String { "Sıradaki: \(code)" }

    static let statusWatching = "İzliyorum"
    static let statusPlan = "İzleyeceğim"
    static let statusOnHold = "Beklemede"
    static let statusDropped = "Bıraktım"
    static let statusCompleted = "Bitti"

    static let sourcesLoading = "Eklentilerden kaynaklar aranıyor…"
    static let sourcesEmpty = "Kaynak bulunamadı."
    static let sourcesNoAddons = "Hiç eklenti yok. Ayarlar > Eklentiler'den Torrentio gibi bir eklenti ekle."
    static let sourceTorrentOnly = "Torrent (iPhone'da doğrudan oynatılamaz)"
    static let cached = "Hazır"
    static let noImdb = "Bu yapımın IMDb kimliği yok; eklentiler kaynak bulamaz."

    static let playerAudio = "Ses"
    static let playerSubtitles = "Altyazı"
    static let playerSubtitlesOff = "Kapalı"
    static let playerSpeed = "Hız"
    static let playerNext = "Sıradaki bölüm"
    static let playerFailed = "Bu kaynak oynatılamadı. Başka bir kaynak dene."
    static let playerClose = "Kapat"
    static let skipIntro = "Girişi atla"
    static let skipRecap = "Özeti atla"
    static let skipCredits = "Jeneriği atla"
    static let skipPreview = "Önizlemeyi atla"
    static func nextIn(_ seconds: Int) -> String { "Sıradaki bölüm \(seconds) sn içinde" }
    static let autoPlayNext = "Sıradaki bölümü kendiliğinden oynat"

    static let libraryEmpty = "Bu bölümde yapım yok."

    static let profiles = "Profiller"
    static let defaultProfileName = "Alp"
    static let profilesHint = "Her profilin kütüphanesi, geçmişi, kaldığı yerleri ve eklentileri ayrıdır. Basılı tutunca: ad, PIN, sil."
    static let profileAdd = "Profil ekle"
    static let profileName = "Profil adı"
    static let profileRename = "Yeniden adlandır"
    static let profileActive = "Kullanımda"
    static let profileTapToSwitch = "Geçmek için dokun"
    static let profilePin = "PIN (4 hane)"
    static let profilePinSet = "PIN koy"
    static let profilePinRemove = "PIN'i kaldır"
    static let profilePinNew = "Yeni PIN (4 hane)"
    static let profilePinCurrent = "Şu anki PIN"
    static let profilePinWrong = "PIN yanlış."
    static func profileUnlock(_ name: String) -> String { "\(name) profilinin PIN'i" }
    static let profileGateBody = "Bu profil PIN ile kilitli."
    static let profileGateOpen = "Aç"
    static let profileGateOther = "Başka profil"

    static let settingsAddons = "Eklentiler"
    static let settingsAddAddon = "Eklenti ekle"
    static let settingsAddonUrl = "Manifest adresi (…/manifest.json)"
    static let settingsAddonAdd = "Ekle"
    static let settingsAddonFailed = "Eklenti eklenemedi. Adresi kontrol et."
    static let settingsTmdb = "TMDB anahtarı"
    static let settingsTmdbHint = "Derlemede anahtar yoksa buraya TMDB okuma anahtarını (v4) gir."
    static let settingsTmdbSave = "Kaydet"
    static let settingsBackup = "Yedek"
    static let settingsExport = "Yedeği Dosyalar'a kaydet"
    static let settingsExportDone = "Yedek kaydedildi."
    static let settingsImport = "Yedeği içe aktar (iOS ya da Android)"
    static let settingsImportHint = "iOS yedeği ya da Alpflix Android'in yedek dosyası (alpflix-yedek-….json.gz): kütüphane, izleme geçmişi, kaldığın yerler ve eklentiler birleştirilir."
    static func settingsImportDone(_ titles: Int, _ events: Int, _ addons: Int) -> String {
        "Aktarıldı: \(titles) yapım, \(events) izleme kaydı, \(addons) eklenti."
    }
    static let settingsImportFailed = "Yedek okunamadı."
    static let settingsSubtitleLanguage = "Altyazı dili"
    static let settingsPlayer = "Oynatıcı"
    static let languageTurkish = "Türkçe"
    static let languageEnglish = "İngilizce"
    static let settingsAbout = "Hakkında"
    static func settingsVersion(_ v: String, _ b: String) -> String { "Alpflix iOS \(v) (derleme \(b))" }
    static let settingsCredit = "Film ve dizi bilgileri TMDB'den. Bu ürün TMDB API'sini kullanır ama TMDB tarafından onaylanmamıştır."

    // Eklenti altyazıları (oynatıcı menüsünde durum satırları)
    static let subtitleSources = "Altyazı eklentileri"
    static let subtitleSearching = "Eklenti altyazıları aranıyor…"
    static let subtitleNoAddon = "Altyazı sunan eklenti yok (Ayarlar > Eklentiler)"
    static let subtitleDownloaded = "İndirilen altyazılar"
    static func subtitleCount(_ name: String, _ n: Int) -> String { "\(name): \(n) altyazı" }
    static func subtitleProblem(_ name: String, _ problem: String) -> String { "\(name): \(problem)" }
    static func subtitleHTTP(_ code: Int) -> String { "sunucu hatası (HTTP \(code))" }
    static let subtitleTimeout = "zaman aşımı"
    static let subtitleUnreadable = "yanıt okunamadı"
    static let subtitleNetwork = "bağlanılamadı"
    static let resourceStream = "Kaynak"
    static let resourceSubtitles = "Altyazı"
    static let resourceCatalog = "Katalog"
    static let resourceMeta = "Bilgi"

    // İndirmeler
    static let downloads = "İndirilenler"
    static let download = "İndir"
    static let downloadSwipeHint = "İndirmek için kaynağı sola kaydır ya da basılı tut. İndirme yalnız Wi-Fi ile yapılır."
    static let downloadsEmpty = "İndirilen yapım yok. Kaynak listesinde bir kaynağı sola kaydırıp İndir'e dokun."
    static let downloadWifiOnly = "İndirmeler yalnız Wi-Fi ile yapılır."
    static let downloadWaitingWifi = "Wi-Fi bekleniyor"
    static let downloadQueued = "Sırada"
    static let downloadPaused = "Duraklatıldı"
    static let downloadDone = "İndirildi"
    static let downloadPause = "Duraklat"
    static let downloadResume = "Sürdür"
    static let downloadRetry = "Yeniden dene"
    static let downloadPlay = "Oynat"
    static let downloadPlayLocal = "İndirilen dosyayı oynat"
    static let downloadStarted = "İndirme sıraya eklendi."
    static let downloadExists = "Bu yapım zaten indirilenlerde."
    static let downloadTorrent = "Torrent kaynağı indirilemez."
    static let downloadNoSpace = "Cihazda yeterli boş alan yok."
    static let downloadPlaceholder = "Kaynak hazır değil (debrid indiriyor ya da hata verdi). Başka bir kaynak dene."
    static let downloadFailed = "İndirme başarısız oldu."
    static func downloadSpace(_ used: String, _ free: String) -> String { "Kullanılan: \(used) · Boş: \(free)" }
    static func downloadProgress(_ done: String, _ total: String) -> String { "\(done) / \(total)" }
    static let downloadSeason = "Sezonu indir"
    static func downloadSeasonConfirm(_ season: Int, _ n: Int) -> String {
        "\(season). sezonun \(n) bölümü için kaynak kendiliğinden seçilip indirilecek (yalnız Wi-Fi)."
    }
    static func downloadSeasonProgress(_ done: Int, _ total: Int) -> String { "Kaynaklar seçiliyor: \(done)/\(total)" }
    static func downloadSeasonDone(_ added: Int, _ missing: Int) -> String {
        missing > 0 ? "\(added) bölüm sıraya eklendi; \(missing) bölüm için indirilebilir kaynak bulunamadı." : "\(added) bölüm sıraya eklendi."
    }
    static let downloadSeasonNothing = "Bu sezonda indirilecek yeni bölüm yok."

    static let errorNoToken = "TMDB anahtarı yok. Ayarlar'dan gir."
    static let errorNetwork = "Bağlantı kurulamadı."
    static let retry = "Yeniden dene"
    static let ok = "Tamam"
    static let cancel = "Vazgeç"
    static let delete = "Sil"
}
