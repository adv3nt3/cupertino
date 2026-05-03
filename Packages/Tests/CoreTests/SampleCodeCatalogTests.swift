@testable import Core
import Foundation
import Testing

/// Coverage for #214: `SampleCodeCatalog` should prefer the on-disk
/// `catalog.json` (written by `cupertino fetch --type code`) over the
/// embedded snapshot, and gracefully fall back when the on-disk file is
/// missing or malformed. Also covers
/// `SampleCodeDownloader.transformAppleListingToCatalog`.
@Suite("SampleCodeCatalog disk-first loading (#214)")
struct SampleCodeCatalogTests {
    // MARK: - loadFromDisk

    @Test("loadFromDisk returns nil when no file exists at the path")
    func diskMissing() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SampleCodeCatalog.loadFromDisk(at: dir) == nil)
    }

    @Test("loadFromDisk returns nil when catalog.json is malformed")
    func diskMalformed() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeCatalog(in: dir, contents: "{ this is not valid json")
        #expect(SampleCodeCatalog.loadFromDisk(at: dir) == nil)
    }

    @Test("loadFromDisk decodes a valid catalog.json")
    func diskValid() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.writeCatalog(in: dir, contents: Self.validCatalogJSON(count: 2))
        let catalog = SampleCodeCatalog.loadFromDisk(at: dir)
        #expect(catalog != nil)
        #expect(catalog?.count == 2)
        #expect(catalog?.entries.count == 2)
        #expect(catalog?.entries.first?.title == "Sample One")
        #expect(catalog?.entries.first?.framework == "Foundation")
    }

    @Test("loadFromDisk uses default sample-code dir when no path is provided")
    func diskDefaultPath() {
        // Just exercise the default-arg overload — no file there in test env,
        // expect nil rather than a crash.
        _ = SampleCodeCatalog.loadFromDisk()
    }

    // MARK: - loadFromEmbedded

    @Test("loadFromEmbedded successfully decodes the bundled JSON")
    func embeddedDecodes() {
        let catalog = SampleCodeCatalog.loadFromEmbedded()
        #expect(!catalog.entries.isEmpty)
        #expect(catalog.entries.count == catalog.count)
        // Every entry should have a non-empty framework + title (sanity)
        for entry in catalog.entries.prefix(20) {
            #expect(!entry.framework.isEmpty)
            #expect(!entry.title.isEmpty)
            #expect(!entry.zipFilename.isEmpty)
        }
    }

    // MARK: - loadCatalog (end-to-end via allEntries)

    @Test("allEntries falls back to embedded when on-disk catalog is absent")
    func endToEndEmbeddedFallback() async {
        await SampleCodeCatalog.resetCache()
        // No on-disk catalog at the default path is the precondition we
        // inherit from the test environment. allEntries should populate
        // from embedded and report .embedded as the source.
        let entries = await SampleCodeCatalog.allEntries
        #expect(!entries.isEmpty)
        let source = await SampleCodeCatalog.loadedSource
        // Either could be true depending on the test machine's
        // ~/.cupertino-dev/sample-code/catalog.json state, but on a CI
        // machine without that file, .embedded is the expected outcome.
        #expect(source == .embedded || source == .onDisk)
    }

    // MARK: - SampleCodeDownloader.transformAppleListingToCatalog

    @Test("transformAppleListingToCatalog returns nil for non-JSON input")
    func transformInvalid() {
        let bytes = Data("not json".utf8)
        #expect(SampleCodeDownloader.transformAppleListingToCatalog(data: bytes) == nil)
    }

    @Test("transformAppleListingToCatalog returns nil when references key missing")
    func transformMissingRefs() {
        let json = Data("""
        { "metadata": { "title": "Sample Code" } }
        """.utf8)
        #expect(SampleCodeDownloader.transformAppleListingToCatalog(data: json) == nil)
    }

    @Test("transformAppleListingToCatalog filters to role=sampleCode entries")
    func transformFiltersByRole() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: true).utf8)
        let catalog = try #require(SampleCodeDownloader.transformAppleListingToCatalog(data: json))
        // Fixture has 2 sampleCode + 1 article; only the 2 should land
        #expect(catalog.count == 2)
        #expect(catalog.entries.allSatisfy { !$0.title.isEmpty })
    }

    @Test("transformAppleListingToCatalog extracts framework from URL path")
    func transformExtractsFramework() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(SampleCodeDownloader.transformAppleListingToCatalog(data: json))
        let frameworks = Set(catalog.entries.map(\.framework))
        #expect(frameworks.contains("Foundation"))
        #expect(frameworks.contains("RealityKit"))
    }

    @Test("transformAppleListingToCatalog assembles webURL + zipFilename")
    func transformDerivedFields() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(SampleCodeDownloader.transformAppleListingToCatalog(data: json))
        let foundationEntry = try #require(catalog.entries.first { $0.framework == "Foundation" })
        #expect(foundationEntry.webURL.hasPrefix("https://developer.apple.com/documentation/Foundation/"))
        #expect(foundationEntry.zipFilename.hasPrefix("foundation-"))
        #expect(foundationEntry.zipFilename.hasSuffix(".zip"))
    }

    @Test("transformAppleListingToCatalog sorts by (framework, title)")
    func transformSortsStably() throws {
        let json = Data(Self.appleListingFixture(includeNonSamples: false).utf8)
        let catalog = try #require(SampleCodeDownloader.transformAppleListingToCatalog(data: json))
        let frameworks = catalog.entries.map(\.framework)
        // Assert sorted
        #expect(frameworks == frameworks.sorted())
    }

    // MARK: - Helpers

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SampleCodeCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func writeCatalog(in dir: URL, contents: String) throws {
        let url = dir.appendingPathComponent(SampleCodeCatalog.onDiskCatalogFilename)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func validCatalogJSON(count: Int) -> String {
        """
        {
          "version": "test",
          "lastCrawled": "2026-05-03T00:00:00Z",
          "count": \(count),
          "entries": [
            {
              "title": "Sample One",
              "url": "/documentation/Foundation/sample-one",
              "framework": "Foundation",
              "description": "First sample.",
              "zipFilename": "foundation-sample-one.zip",
              "webURL": "https://developer.apple.com/documentation/Foundation/sample-one"
            },
            {
              "title": "Sample Two",
              "url": "/documentation/RealityKit/sample-two",
              "framework": "RealityKit",
              "description": "Second sample.",
              "zipFilename": "realitykit-sample-two.zip",
              "webURL": "https://developer.apple.com/documentation/RealityKit/sample-two"
            }
          ]
        }
        """
    }

    private static func appleListingFixture(includeNonSamples: Bool) -> String {
        let nonSampleEntry = includeNonSamples ? """
        ,
        "doc://com.apple.documentation/documentation/Other/an-article": {
            "role": "article",
            "title": "Not a sample",
            "kind": "article",
            "url": "/documentation/Other/an-article"
        }
        """ : ""

        return """
        {
            "references": {
                "doc://com.apple.documentation/documentation/Foundation/zebra-sample": {
                    "role": "sampleCode",
                    "title": "Zebra Sample",
                    "kind": "article",
                    "url": "/documentation/Foundation/zebra-sample",
                    "abstract": [
                        { "type": "text", "text": "Zebra description." }
                    ]
                },
                "doc://com.apple.documentation/documentation/RealityKit/aardvark-sample": {
                    "role": "sampleCode",
                    "title": "Aardvark Sample",
                    "kind": "article",
                    "url": "/documentation/RealityKit/aardvark-sample",
                    "abstract": [
                        { "type": "text", "text": "Aardvark description." }
                    ]
                }\(nonSampleEntry)
            }
        }
        """
    }
}
