// This file loads the Apple Sample Code Library from JSON
// Last updated: 2025-11-17
// JSON file: CupertinoResources/sample-code-catalog.json

import Foundation
import Resources
import Shared

/// Represents a sample code project from Apple
public struct SampleCodeEntry: Codable, Sendable {
    public let title: String
    public let url: String
    public let framework: String
    public let description: String
    public let zipFilename: String
    public let webURL: String

    public init(
        title: String, url: String, framework: String,
        description: String, zipFilename: String, webURL: String
    ) {
        self.title = title
        self.url = url
        self.framework = framework
        self.description = description
        self.zipFilename = zipFilename
        self.webURL = webURL
    }
}

/// JSON structure for sample code catalog
struct SampleCodeCatalogJSON: Codable {
    let version: String
    let lastCrawled: String
    let count: Int
    let entries: [SampleCodeEntry]
}

/// Complete catalog of all Apple sample code projects
public enum SampleCodeCatalog {
    /// File name written by `SampleCodeDownloader` next to the fetched zips
    /// so `cupertino save` can pick up the freshly-discovered metadata
    /// instead of the stale embedded snapshot. (#214)
    public static let onDiskCatalogFilename = "catalog.json"

    /// Source the catalog was loaded from on the most recent `loadCatalog` call.
    /// Useful for telling users via the build log whether they're indexing from
    /// fresh on-disk data or the embedded fallback.
    public enum Source: String, Sendable {
        case onDisk
        case embedded
    }

    /// Cached catalog data (thread-safe via actor isolation)
    private actor Cache {
        var catalog: SampleCodeCatalogJSON?
        var source: Source?

        func get() -> (SampleCodeCatalogJSON, Source)? {
            guard let catalog, let source else { return nil }
            return (catalog, source)
        }

        func set(_ newCatalog: SampleCodeCatalogJSON, source: Source) {
            catalog = newCatalog
            self.source = source
        }

        func clear() {
            catalog = nil
            source = nil
        }
    }

    private static let cache = Cache()

    /// Reset the cached catalog. Used by tests to force `loadCatalog` to
    /// re-evaluate the disk-vs-embedded preference between cases.
    public static func resetCache() async {
        await cache.clear()
    }

    /// Load catalog. First checks `<sample-code-dir>/catalog.json` so a fresh
    /// `cupertino fetch --type code` run surfaces in `cupertino save` (#214).
    /// Falls back to the embedded catalog when no on-disk file exists or it
    /// fails to decode. The decision is cached for the process lifetime.
    private static func loadCatalog() async -> SampleCodeCatalogJSON {
        if let cached = await cache.get() {
            return cached.0
        }

        if let onDisk = loadFromDisk() {
            await cache.set(onDisk, source: .onDisk)
            return onDisk
        }

        let embedded = loadFromEmbedded()
        await cache.set(embedded, source: .embedded)
        return embedded
    }

    /// Read `<sample-code-dir>/catalog.json` if present and parseable.
    /// `internal` so tests can drive it directly.
    static func loadFromDisk(at directory: URL? = nil) -> SampleCodeCatalogJSON? {
        let dir = directory ?? Shared.Constants.defaultSampleCodeDirectory
        let url = dir.appendingPathComponent(onDiskCatalogFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SampleCodeCatalogJSON.self, from: data)
    }

    /// Decode the embedded catalog. Crashes if the embedded resource is
    /// missing or invalid (those are build-time guarantees).
    static func loadFromEmbedded() -> SampleCodeCatalogJSON {
        guard let data = CupertinoResources.jsonData(named: "sample-code-catalog") else {
            fatalError("❌ sample-code-catalog embedded JSON missing — should be impossible")
        }

        do {
            return try JSONDecoder().decode(SampleCodeCatalogJSON.self, from: data)
        } catch {
            fatalError("❌ Failed to decode embedded sample-code-catalog JSON: \(error)")
        }
    }

    /// Which source the cached catalog was loaded from (on-disk or embedded).
    /// Returns nil before the first `loadCatalog` call.
    public static var loadedSource: Source? {
        get async {
            await cache.get()?.1
        }
    }

    /// Total number of sample code entries
    public static var count: Int {
        get async {
            await loadCatalog().count
        }
    }

    /// Last crawled date
    public static var lastCrawled: String {
        get async {
            await loadCatalog().lastCrawled
        }
    }

    /// Catalog version
    public static var version: String {
        get async {
            await loadCatalog().version
        }
    }

    /// All sample code entries
    public static var allEntries: [SampleCodeEntry] {
        get async {
            await loadCatalog().entries
        }
    }

    /// Get entries for a specific framework
    public static func entries(for framework: String) async -> [SampleCodeEntry] {
        await allEntries.filter { $0.framework.lowercased() == framework.lowercased() }
    }

    /// Search entries by title or description
    public static func search(_ query: String) async -> [SampleCodeEntry] {
        let lowercasedQuery = query.lowercased()
        return await allEntries.filter { entry in
            entry.title.lowercased().contains(lowercasedQuery) ||
                entry.description.lowercased().contains(lowercasedQuery)
        }
    }
}
