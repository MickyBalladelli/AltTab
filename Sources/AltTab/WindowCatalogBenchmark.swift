import AppKit
import Foundation

enum WindowCatalogBenchmark {
    static func run() {
        SettingsStore.registerDefaults()
        WindowCatalog.resetCaches()

        let cold = measure()
        let warmRuns = (0..<5).map { _ in measure() }
        let warmAverage = warmRuns.map(\.elapsedMilliseconds).reduce(0, +) / Double(warmRuns.count)
        let warmBest = warmRuns.map(\.elapsedMilliseconds).min() ?? 0

        print("AltTab window catalog benchmark")
        print(String(format: "cold: %.1f ms (%d items)", cold.elapsedMilliseconds, cold.itemCount))
        print(String(format: "warm average: %.1f ms, best: %.1f ms (%d items)", warmAverage, warmBest, warmRuns.last?.itemCount ?? 0))
        print(String(format: "last profile: %.1f ms, thumbnails %d hits / %d misses", WindowCatalog.lastProfile.elapsedMilliseconds, WindowCatalog.lastProfile.thumbnailCacheHits, WindowCatalog.lastProfile.thumbnailCacheMisses))
    }

    private static func measure() -> (elapsedMilliseconds: Double, itemCount: Int) {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let itemCount = WindowCatalog.items(for: .windows).count
        return ((CFAbsoluteTimeGetCurrent() - startedAt) * 1000, itemCount)
    }
}
