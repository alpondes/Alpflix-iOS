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
    static let seriesDetails = "Dizinin sayfası"
    static let movieDetails = "Filmin sayfası"
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

    // Genel
    static let save = "Kaydet"
    static let reset = "Sıfırla"
    static let more = "Diğer"
    static let watched = "İzlendi"

    // Listeler
    static let lists = "Listeler"
    static let listsEmpty = "Henüz liste yok. Sağ üstteki + ile kendi listeni ya da kurala göre dolan akıllı liste oluştur."
    static let listNew = "Yeni liste"
    static let listNewSmart = "Yeni akıllı liste"
    static let listEdit = "Listeyi düzenle"
    static let listAdd = "Listeye ekle"
    static let listName = "Liste adı"
    static let listSmart = "Akıllı liste"
    static func listCount(_ n: Int) -> String { "\(n) yapım" }
    static let listRemoveItem = "Listeden çıkar"
    static let listManualEmpty = "Liste boş. Yapım sayfasındaki liste simgesiyle ekleyebilirsin."
    static let listSmartEmpty = "Kurala uyan yapım bulunamadı."
    static let listRule = "Kural"
    static let listType = "Tür"
    static let listSort = "Sıralama"
    static let listLanguage = "Özgün dil"
    static let listYearFrom = "Yıldan"
    static let listYearTo = "Yıla"
    static let listMinVoteToggle = "En düşük TMDB ortalaması"
    static func listMinVote(_ v: Double) -> String { String(format: "TMDB ortalaması ≥ %.1f", v) }
    static let listHideKnown = "İzlediklerimi ve kütüphanemdekileri gösterme"
    static let sortPopular = "Popüler"
    static let sortNewest = "En yeni"
    static let sortTopVoted = "TMDB ortalaması yüksek"
    static let languageAny = "Hepsi"
    static let languageKorean = "Korece"
    static let languageJapanese = "Japonca"
    static let languageSpanish = "İspanyolca"
    static let languageFrench = "Fransızca"
    static let languageGerman = "Almanca"

    // İzleme işaretleri ve gizleme
    static let markWatchedOnDate = "Tarih seçerek izlendi işaretle"
    static let markUpTo = "Buraya kadar izledim"
    static let markSeason = "Sezonu izledim"
    static let seasonWatched = "Sezon izlendi"
    static let unmarkSeason = "Sezonun izlemelerini kaldır"
    static let watchDate = "İzleme tarihi"
    static let notInterested = "İlgilenmiyorum"
    static let unhide = "Yeniden göster"
    static let hiddenNotice = "İlgilenmiyorum dedin: satırlarda ve listelerde görünmüyor."
    static let hiddenTitle = "Gizlenenler"
    static let hiddenEmpty = "Gizlenen yapım yok."

    // Dizi rozetleri
    static let badgeCanceled = "İptal edildi"
    static let badgeEnded = "Final yaptı"
    static func badgeNewSeason(_ n: Int) -> String { "Yeni sezon: \(n). sezon" }
    static func badgeSeasonSoon(_ n: Int, _ date: String) -> String { "\(n). sezon \(date)" }
    static func badgeNextEpisode(_ date: String) -> String { "Sıradaki bölüm \(date)" }

    // Kişiler
    static let follow = "Takip et"
    static let following = "Takip ediliyor"
    static let unfollow = "Takibi bırak"
    static let followingTitle = "Takip ettiklerim"
    static let followingEmpty = "Takip ettiğin kimse yok. Oyuncu ya da yönetmen sayfasında Takip et'e dokun."
    static let filmography = "Filmografi"
    static func filmographyProgress(_ watched: Int, _ total: Int) -> String {
        "Filmografi: %\(total > 0 ? watched * 100 / total : 0) izlendi (\(watched) / \(total))"
    }
    static func personAge(_ born: Int, _ age: Int) -> String { "\(born) doğumlu · \(age) yaşında" }
    static func personLived(_ born: Int, _ died: Int) -> String { "\(born) – \(died)" }
    static let departmentActing = "Oyuncu"
    static let departmentDirecting = "Yönetmen"

    // Ana sayfa
    static let homeLayout = "Ana sayfa düzeni"
    static let homeLayoutHint = "Satırları sürükleyerek sırala; kapattıkların ana sayfada görünmez."
    static let homeLayoutReset = "Varsayılan düzene dön"
    static let homeSeasonal = "Mevsimlik satır"
    static let homeTurkeyPlatforms = "Türkiye'de platformlarda popüler"
    static let homeTurkishSeries = "Popüler Türk dizileri"
    static let homeTurkishMovies = "Popüler Türk filmleri"
    static let homeFollowing = "Takip ettiklerinin yeni yapımları"
    static let seasonalNewYear = "Yılbaşı filmleri"
    static let seasonalHalloween = "Cadılar Bayramı'na korku"
    static let seasonalValentine = "Sevgililer Günü'ne romantik filmler"
    static let seasonalSummer = "Yaz filmleri"

    // Takvim
    static let calendar = "Takvim"
    static let calendarEmpty = "Önümüzdeki 60 günde izlediğin dizilerde yeni bölüm yok."
    static let calendarLoading = "Bölümler yükleniyor…"
    static let episodeAlertsToggle = "Yeni bölüm bildirimi"
    static let episodeAlertsHint = "İzlediğin, izleyeceğin ve bitirdiğin dizilerde bölüm çıktığı gün saat 10'da bildirim."
    static func episodeAlert(_ code: String, _ name: String?) -> String {
        ["\(code) bugün yayında", name].compactMap { $0 }.joined(separator: " · ")
    }
    static let dayToday = "Bugün"
    static let dayTomorrow = "Yarın"
    static let dayYesterday = "Dün"

    // İstatistik
    static let stats = "İstatistikler"
    static let statsMonth = "Bu ay"
    static let statsYear = "Bu yıl"
    static let statsAll = "Tümü"
    static let statsTotalTime = "İzleme süresi"
    static let statsMovies = "Film"
    static let statsEpisodesTitle = "Bölüm"
    static let statsSeries = "Dizi"
    static let statsHours = "Saat"
    static let statsHoursAxis = "Saat"
    static let statsGenres = "Türler"
    static let statsTopSeries = "En çok izlenen diziler"
    static func statsEpisodes(_ n: Int) -> String { "\(n) bölüm" }
    static func statsHoursValue(_ h: Int) -> String { "\(h) sa" }
    static func statsMinutesValue(_ m: Int) -> String { "\(m) dk" }
    static func statsBusiestDay(_ day: String, _ time: String) -> String { "En yoğun gün: \(day) · \(time)" }
    static let statsEmpty = "Bu dönemde izleme kaydı yok."
    static let statsFilling = "Yapım süreleri TMDB'den tamamlanıyor…"

    // Oynatıcı ve altyazı görünümü
    static let playerBoost = "2x"
    static let subtitleDelay = "Altyazı gecikmesi"
    static func subtitleDelayValue(_ seconds: Double) -> String {
        seconds == 0 ? "0 sn" : String(format: "%@%.2f sn", seconds > 0 ? "+" : "", seconds).replacingOccurrences(of: ".", with: ",")
    }
    static let subtitleEarlier = "Altyazıyı öne al"
    static let subtitleLater = "Altyazıyı geciktir"
    static let subtitleSize = "Altyazı boyutu"
    static let subtitleColor = "Altyazı rengi"
    static let subtitleBold = "Kalın altyazı"
    static let sizeSmall = "Küçük"
    static let sizeNormal = "Normal"
    static let sizeLarge = "Büyük"
    static let sizeHuge = "Çok büyük"
    static let colorCream = "Krem"
    static let colorYellow = "Sarı"
    static let colorGray = "Açık gri"
    static let wyzieTitle = "Ek altyazı kaynağı: Wyzie Subs"
    static let wyzieKey = "Wyzie anahtarı"
    static let wyzieHint = "sub.wyzie.io'dan ücretsiz anahtar al; girilirse OpenSubtitles, SubDL ve Podnapisi altyazıları eklentilere ek olarak listelenir. Anahtar yalnız bu cihazda tutulur."

    // Trakt
    static let traktImport = "Trakt'tan içe aktar"
    static let traktByUser = "Kullanıcı adıyla (doğrudan)"
    static let traktUser = "Trakt kullanıcı adı"
    static let traktClientId = "Trakt Client ID"
    static let traktImportButton = "İçe aktar"
    static let traktByUserHint = "Profilin herkese açık olmalı. Client ID için trakt.tv/oauth/applications/new adresinde bir uygulama oluştur (ad: Alpflix, Redirect URI: urn:ietf:wg:oauth:2.0:oob), çıkan Client ID'yi buraya yapıştır. Bir kerelik okunur; Trakt'a hiçbir şey yazılmaz."
    static let traktByFile = "Dosyadan"
    static let traktPickFile = "ZIP ya da JSON seç"
    static let traktByFileHint = "Trakt > Settings > Data > Export ile indirdiğin ZIP dosyası (ya da içindeki JSON'lar). Puan dosyaları okunmaz."
    static func traktFetchingHistory(_ page: Int, _ total: Int) -> String { "İzleme geçmişi alınıyor (sayfa \(page)/\(max(page, total)))" }
    static let traktFetchingWatched = "İzlenenler alınıyor…"
    static let traktFetchingWatchlist = "İzleme listesi alınıyor…"
    static let traktFetchingLists = "Listeler alınıyor…"
    static func traktMatching(_ done: Int, _ total: Int) -> String { "TMDB ile eşleştiriliyor: \(done)/\(total)" }
    static func traktStatuses(_ done: Int, _ total: Int) -> String { "Dizi durumları hesaplanıyor: \(done)/\(total)" }
    static let traktNothing = "İçe aktarılacak kayıt bulunamadı."
    static func traktDone(_ events: Int, _ titles: Int, _ lists: Int, _ unmatched: Int, _ ratings: Int) -> String {
        var parts = ["Aktarıldı: \(events) izleme kaydı, \(titles) yeni yapım, \(lists) liste."]
        if unmatched > 0 { parts.append("\(unmatched) yapım TMDB'de eşleşmedi.") }
        if ratings > 0 { parts.append("\(ratings) puan okunmadı (uygulamada puan yok).") }
        return parts.joined(separator: " ")
    }
    static let traktErrorNotFound = "Bu kullanıcı adı Trakt'ta bulunamadı."
    static let traktErrorPrivate = "Profil gizli. Trakt'ta profilini herkese açık yap ya da dışa aktarım dosyasını kullan."
    static let traktErrorKey = "Client ID kabul edilmedi. Trakt uygulamasındaki Client ID'yi kontrol et."
    static let traktErrorNetwork = "Trakt'a bağlanılamadı."

    // Wi-Fi eşitleme
    static let syncTitle = "Wi-Fi eşitleme"
    static let syncIntro = "Aynı Wi-Fi ağındaki cihazlarda Alpflix açıkken kaldığın yerler, izleme geçmişi, durumlar ve İzlemeye devam et kendiliğinden eşitlenir. Android telefon ve tabletle de çalışır. Bulut ya da hesap yok; veri yalnız cihazlar arasında, şifreli gider."
    static let syncCreateCode = "Kod oluştur"
    static let syncEnterCode = "Kodu gir"
    static let syncPairHint = "Bir cihazda kod oluştur, öbür cihazda (iPhone ya da Android) Ayarlar > Wi-Fi eşitleme > Kodu gir ile aynı kodu yaz. Bir kez yapılır. İlk seferde iPhone yerel ağ izni ister; izin ver."
    static let syncCodeTitle = "Eşleştirme kodu"
    static let syncCodeHint = "Bu kodu öbür cihazda Kodu gir ile yaz. Kodu bilen, aynı ağda verine erişebilir; kimseyle paylaşma."
    static let syncCodeFormat = "12 karakter, ör. K7PQ-2MXD-9RTA"
    static let syncCodeInvalid = "Kod 12 karakter olmalı (ör. K7PQ-2MXD-9RTA)."
    static let syncDevices = "Bulunan cihazlar"
    static func syncPeerLast(_ when: String) -> String { "Son eşitleme: \(when)" }
    static let syncPeerNever = "Henüz eşitlenmedi"
    static let syncNow = "Şimdi eşitle"
    static let syncShowCode = "Kodu göster"
    static let syncUnpair = "Eşleştirmeyi kaldır"
    static let syncUnpairConfirm = "Bu cihaz artık eşitlenmez. Veriler silinmez; yeniden eşleştirmek için kodu tekrar girmen gerekir."
    static let syncWhat = "Eşitlenenler: kaldığın yerler, izleme geçmişi (kaldırılan izlemeler dahil), kütüphane durumları ve İzlemeye devam et'ten kaldırılanlar. Her iki cihazda aynı adlı profil açık olmalı. İki cihazda da uygulama açıkken çalışır; değişiklik birkaç saniyede gider."
    static let syncStatusOff = "Kapalı (uygulama arka planda)"
    static let syncStatusSearching = "Açık · aynı ağda cihaz aranıyor"
    static let syncStatusConnected = "Açık · cihaz bulundu"
    static func syncLast(_ when: String) -> String { "Son eşitleme \(when)" }
    static let syncProblemProfile = "Öbür cihazda farklı bir profil açık; aynı adlı profili aç."
    static let syncProblemLocked = "Profil kilitli; PIN girilince eşitlenir."
    static let syncProblemConnection = "Son denemede bağlanılamadı; cihazlar aynı ağda mı?"

    static let errorNoToken = "TMDB anahtarı yok. Ayarlar'dan gir."
    static let errorNetwork = "Bağlantı kurulamadı."
    static let retry = "Yeniden dene"
    static let ok = "Tamam"
    static let cancel = "Vazgeç"
    static let delete = "Sil"
}
