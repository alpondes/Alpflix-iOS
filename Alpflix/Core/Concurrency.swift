import Foundation

extension Sequence {
    /// Öğeleri aynı anda en çok [limit] iş olacak şekilde dönüştürür; sıra korunur. Ağ isteklerini
    /// tek tek beklemek yerine paralel yapmak için (ekranlar daha çabuk dolar).
    func concurrentMap<T>(limit: Int = 6, _ transform: @escaping (Element) async -> T) async -> [T] {
        let items = Array(self)
        guard !items.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, T).self) { group in
            var results = [T?](repeating: nil, count: items.count)
            var next = 0
            func addNext() {
                guard next < items.count else { return }
                let index = next
                let item = items[index]
                next += 1
                group.addTask { (index, await transform(item)) }
            }
            for _ in 0..<Swift.min(limit, items.count) { addNext() }
            while let (index, value) = await group.next() {
                results[index] = value
                addNext()
            }
            return results.compactMap { $0 }
        }
    }
}
