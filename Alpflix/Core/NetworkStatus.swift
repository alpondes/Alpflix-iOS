import Foundation
import Network

/// İnternet var mı (herhangi bir ağ). Çevrimdışıyken ana sayfa indirilenleri öne alır.
@MainActor
final class NetworkStatus: ObservableObject {
    static let shared = NetworkStatus()
    @Published private(set) var online = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkStatus.shared.online = online }
        }
        monitor.start(queue: DispatchQueue(label: "alpflix.network"))
    }
}
