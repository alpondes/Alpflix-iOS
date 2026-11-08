import AVFoundation
import CoreText
import SwiftUI

@main
struct AlpflixApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore()

    init() {
        // Sessiz düğmesi açıkken de ses gelsin; resim içinde resim ve arka planda ses için.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let background = UIColor(red: 0x12 / 255, green: 0x10 / 255, blue: 0x14 / 255, alpha: 1)
        let text = UIColor(red: 0xED / 255, green: 0xE8 / 255, blue: 0xE3 / 255, alpha: 1)
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = background
        nav.shadowColor = .clear
        nav.largeTitleTextAttributes = [.foregroundColor: text, .font: Self.archivo(size: 32, weight: 700)]
        nav.titleTextAttributes = [.foregroundColor: text, .font: Self.archivo(size: 17, weight: 650)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0x19 / 255, green: 0x16 / 255, blue: 0x1B / 255, alpha: 1)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    /// Archivo değişken yazı tipi, istenen kalınlıkta ("wght" ekseni); yoksa sistemin kalını.
    private static func archivo(size: CGFloat, weight: CGFloat) -> UIFont {
        guard let base = UIFont(name: "Archivo", size: size) else { return .boldSystemFont(ofSize: size) }
        let wght = 0x77676874 // 'wght'
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = base.fontDescriptor.addingAttributes([variation: [wght: weight]])
        return UIFont(descriptor: descriptor, size: size)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

/// Oynatıcı açıkken yatay kilit.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    static func setOrientation(_ mask: UIInterfaceOrientationMask) {
        orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// Kaynak listesine gidiş: yapım, bölüm ve (devam ediliyorsa) başlangıç konumu.
struct SourcesRoute: Hashable {
    let ref: MediaRef
    let imdbId: String?
    let season: Int?
    let episode: Int?
    var episodeTitle: String? = nil
    var startMs: Int64 = 0
}

struct RootView: View {
    /// Simülatör denetimi açılışta bir sekmeyle başlatabilir ("-alpflixTab 2").
    @State private var selection: Int = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-alpflixTab"), i + 1 < args.count, let tab = Int(args[i + 1]) { return tab }
        return 0
    }()

    var body: some View {
        TabView(selection: $selection) {
            tab(HomeView(), L.tabHome, "house").tag(0)
            tab(DiscoverView(), L.tabDiscover, "safari").tag(1)
            tab(SearchView(), L.tabSearch, "magnifyingglass").tag(2)
            tab(LibraryView(), L.tabLibrary, "rectangle.stack").tag(3)
            tab(SettingsView(), L.tabSettings, "gearshape").tag(4)
        }
    }

    private func tab<V: View>(_ content: V, _ title: String, _ icon: String) -> some View {
        NavigationStack {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationDestination(for: MediaRef.self) { DetailView(ref: $0) }
                .navigationDestination(for: SourcesRoute.self) { SourcesView(route: $0) }
        }
        .tabItem { Label(title, systemImage: icon) }
    }
}
