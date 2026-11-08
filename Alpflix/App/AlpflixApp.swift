import AVFoundation
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
        nav.titleTextAttributes = [.foregroundColor: text]
        nav.largeTitleTextAttributes = [.foregroundColor: text, .font: UIFont(name: "Archivo", size: 32) ?? UIFont.boldSystemFont(ofSize: 32)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0x19 / 255, green: 0x16 / 255, blue: 0x1B / 255, alpha: 1)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
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
    var body: some View {
        TabView {
            tab(HomeView(), L.tabHome, "house")
            tab(DiscoverView(), L.tabDiscover, "safari")
            tab(SearchView(), L.tabSearch, "magnifyingglass")
            tab(LibraryView(), L.tabLibrary, "rectangle.stack")
            tab(SettingsView(), L.tabSettings, "gearshape")
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
