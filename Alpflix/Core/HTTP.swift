import Foundation

enum HTTPError: Error {
    case status(Int)
    case badURL
}

/// Ortak ağ katmanı. Hata metinleri ve log'lara adres yazılmaz (eklenti adresleri debrid anahtarı içerir).
enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.urlCache = URLCache(memoryCapacity: 30_000_000, diskCapacity: 150_000_000)
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    static func data(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 20) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return data
    }

    /// TMDB yanıtları snake_case.
    static let snakeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static let plainDecoder = JSONDecoder()
}
