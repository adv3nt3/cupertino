@testable import Core
import Foundation
import Shared
import Testing

// MARK: - Checksum stability

@Test("ResolvedPackagesStore.checksum: same inputs yield same checksum")
func checksumStable() throws {
    let seeds: [PackageReference] = [
        .init(owner: "apple", repo: "swift-nio", url: "https://github.com/apple/swift-nio", priority: .appleOfficial),
        .init(owner: "vapor", repo: "vapor", url: "https://github.com/vapor/vapor", priority: .ecosystem),
    ]
    let a = Core.ResolvedPackagesStore.checksum(seeds: seeds, exclusions: ["foo/bar"])
    let b = Core.ResolvedPackagesStore.checksum(seeds: seeds, exclusions: ["foo/bar"])
    #expect(a == b)
}

@Test("ResolvedPackagesStore.checksum: reordering seeds does not change checksum")
func checksumSeedOrderAgnostic() throws {
    let a = Core.ResolvedPackagesStore.checksum(
        seeds: [
            .init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial),
            .init(owner: "vapor", repo: "vapor", url: "", priority: .ecosystem),
        ],
        exclusions: []
    )
    let b = Core.ResolvedPackagesStore.checksum(
        seeds: [
            .init(owner: "vapor", repo: "vapor", url: "", priority: .ecosystem),
            .init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial),
        ],
        exclusions: []
    )
    #expect(a == b)
}

@Test("ResolvedPackagesStore.checksum: adding a seed changes the checksum")
func checksumAddedSeedInvalidates() throws {
    let base: [PackageReference] = [
        .init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial),
    ]
    let extended = base + [
        .init(owner: "vapor", repo: "vapor", url: "", priority: .ecosystem),
    ]
    let a = Core.ResolvedPackagesStore.checksum(seeds: base, exclusions: [])
    let b = Core.ResolvedPackagesStore.checksum(seeds: extended, exclusions: [])
    #expect(a != b)
}

@Test("ResolvedPackagesStore.checksum: adding an exclusion changes the checksum")
func checksumAddedExclusionInvalidates() throws {
    let seeds: [PackageReference] = [
        .init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial),
    ]
    let a = Core.ResolvedPackagesStore.checksum(seeds: seeds, exclusions: [])
    let b = Core.ResolvedPackagesStore.checksum(seeds: seeds, exclusions: ["foo/bar"])
    #expect(a != b)
}

@Test("ResolvedPackagesStore.checksum: seed vs exclusion separation")
func checksumSeedExclusionSeparated() throws {
    // If we didn't separate the two, swapping a seed for an exclusion of the same
    // owner/repo would collide. Confirm it doesn't.
    let seedA = Core.ResolvedPackagesStore.checksum(
        seeds: [.init(owner: "apple", repo: "swift-nio", url: "", priority: .appleOfficial)],
        exclusions: []
    )
    let seedB = Core.ResolvedPackagesStore.checksum(
        seeds: [],
        exclusions: ["apple/swift-nio"]
    )
    #expect(seedA != seedB)
}

// MARK: - ResolvedPackagesStore round-trip

@Test("ResolvedPackagesStore: write + load round-trips")
func storeRoundTrip() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-resolver-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("resolved-packages.json")
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let store = Core.ResolvedPackagesStore(
        generatedAt: generatedAt,
        cupertinoVersion: "0.11.0",
        seedChecksum: "fnv1a64:deadbeefcafebabe",
        packages: [
            Core.ResolvedPackage(
                owner: "apple",
                repo: "swift-nio",
                url: "https://github.com/apple/swift-nio",
                priority: .appleOfficial,
                parents: ["apple/swift-nio"]
            ),
            Core.ResolvedPackage(
                owner: "swift-server",
                repo: "swift-service-lifecycle",
                url: "https://github.com/swift-server/swift-service-lifecycle",
                priority: .appleOfficial,
                parents: ["vapor/vapor", "hummingbird-project/hummingbird"]
            ),
        ]
    )
    try store.write(to: fileURL)
    let loaded = try #require(Core.ResolvedPackagesStore.load(from: fileURL))
    #expect(loaded.schemaVersion == Core.ResolvedPackagesStore.currentSchemaVersion)
    #expect(loaded.cupertinoVersion == "0.11.0")
    #expect(loaded.seedChecksum == "fnv1a64:deadbeefcafebabe")
    #expect(loaded.packages.count == 2)
    #expect(loaded.packages[1].parents.contains("vapor/vapor"))
    #expect(loaded.packages[1].parents.contains("hummingbird-project/hummingbird"))
}

@Test("ResolvedPackagesStore: missing file returns nil (fresh install)")
func storeMissingFileReturnsNil() throws {
    let path = URL(fileURLWithPath: "/tmp/cupertino-nonexistent-\(UUID().uuidString).json")
    #expect(Core.ResolvedPackagesStore.load(from: path) == nil)
}

// MARK: - ExclusionList

@Test("ExclusionList: absent file returns empty set")
func exclusionListAbsent() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-excl-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    #expect(Core.ExclusionList.load(from: tempDir).isEmpty)
}

@Test("ExclusionList: loads and normalises entries")
func exclusionListLoads() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-excl-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let fileURL = tempDir.appendingPathComponent(Shared.Constants.FileName.excludedPackages)
    let json = #"[" APPLE/Swift-NIO ", "vapor/vapor"]"#.data(using: .utf8)!
    try json.write(to: fileURL)
    let excluded = Core.ExclusionList.load(from: tempDir)
    #expect(excluded.contains("apple/swift-nio"))
    #expect(excluded.contains("vapor/vapor"))
    #expect(excluded.count == 2)
}

@Test("ExclusionList: malformed JSON returns empty set")
func exclusionListMalformed() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-excl-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let fileURL = tempDir.appendingPathComponent(Shared.Constants.FileName.excludedPackages)
    try "not a json array".data(using: .utf8)!.write(to: fileURL)
    #expect(Core.ExclusionList.load(from: tempDir).isEmpty)
}

// MARK: - Canonicalizer disk cache

@Test("GitHubCanonicalizer: cache-hit avoids network")
func canonicalizerCacheHit() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-canon-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")

    // Seed the cache file directly so the canonicalizer should NOT hit the network.
    let seed: [String: String] = ["apple/swift-docc": "swiftlang/swift-docc"]
    let data = try JSONEncoder().encode(seed)
    try data.write(to: cacheURL)

    let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    let canonical = await canonicalizer.canonicalize(owner: "apple", repo: "swift-docc")
    #expect(canonical.owner == "swiftlang")
    #expect(canonical.repo == "swift-docc")
}

@Test("GitHubCanonicalizer: primeCache + persist round-trips")
func canonicalizerPersistRoundTrip() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-canon-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")

    let c1 = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    await c1.primeCache(
        inputOwner: "apple", inputRepo: "swift-docc",
        canonicalOwner: "swiftlang", canonicalRepo: "swift-docc"
    )
    await c1.persist()

    // New canonicalizer reads the persisted cache from disk.
    let c2 = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    let canonical = await c2.canonicalize(owner: "apple", repo: "swift-docc")
    #expect(canonical.owner == "swiftlang")
    #expect(canonical.repo == "swift-docc")
    let snapshot = await c2.cacheSnapshot()
    #expect(snapshot["apple/swift-docc"] == "swiftlang/swift-docc")
}

// MARK: - Resolver provenance + canonicalization

@Test("Resolver: seed lists itself as its only parent")
func resolverSeedIsSelfParent() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-resolver-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")
    // Prime the canonicalizer so we don't hit the network: canonical == input.
    let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    await canonicalizer.primeCache(
        inputOwner: "apple", inputRepo: "only-seed",
        canonicalOwner: "apple", canonicalRepo: "only-seed"
    )

    let resolver = Core.PackageDependencyResolver(canonicalizer: canonicalizer)
    let seeds: [PackageReference] = [
        .init(owner: "apple", repo: "only-seed", url: "https://github.com/apple/only-seed", priority: .appleOfficial),
    ]
    // No Package.swift will be found for a fake repo → missing manifest, seed still
    // appears in output with self as parent.
    let (packages, stats) = await resolver.resolve(seeds: seeds)
    #expect(stats.seedCount == 1)
    #expect(packages.count == 1)
    #expect(packages[0].parents == ["apple/only-seed"])
}

@Test("Resolver: exclusion list drops the seed entirely")
func resolverExcludesSeed() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-resolver-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")
    let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    await canonicalizer.primeCache(
        inputOwner: "apple", inputRepo: "only-seed",
        canonicalOwner: "apple", canonicalRepo: "only-seed"
    )

    let resolver = Core.PackageDependencyResolver(
        canonicalizer: canonicalizer,
        exclusions: ["apple/only-seed"]
    )
    let seeds: [PackageReference] = [
        .init(owner: "apple", repo: "only-seed", url: "https://github.com/apple/only-seed", priority: .appleOfficial),
    ]
    let (packages, stats) = await resolver.resolve(seeds: seeds)
    #expect(packages.isEmpty)
    #expect(stats.excludedCount == 1)
    #expect(stats.seedCount == 0)
}

@Test("Resolver: seeds that canonicalize to the same repo dedupe into one entry")
func resolverCanonicalizeDedupes() async throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cupertino-resolver-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let cacheURL = tempDir.appendingPathComponent("canonical-owners.json")
    let canonicalizer = Core.GitHubCanonicalizer(cacheURL: cacheURL)
    // Use fake repos so no real Package.swift is fetched; both canonicalize to the
    // same fake canonical name to prove dedupe.
    await canonicalizer.primeCache(
        inputOwner: "fakealias", inputRepo: "only",
        canonicalOwner: "canonicalfake", canonicalRepo: "only"
    )
    await canonicalizer.primeCache(
        inputOwner: "canonicalfake", inputRepo: "only",
        canonicalOwner: "canonicalfake", canonicalRepo: "only"
    )

    let resolver = Core.PackageDependencyResolver(canonicalizer: canonicalizer)
    let seeds: [PackageReference] = [
        .init(owner: "fakealias", repo: "only", url: "https://github.com/fakealias/only", priority: .appleOfficial),
        .init(owner: "canonicalfake", repo: "only", url: "https://github.com/canonicalfake/only", priority: .appleOfficial),
    ]
    let (packages, stats) = await resolver.resolve(seeds: seeds)
    // Repo doesn't exist → Package.swift 404 → no transitive expansion. The two
    // aliased seeds collapse to one ResolvedPackage after canonicalization.
    #expect(stats.seedCount == 1)
    let canonicalMatches = packages.filter { $0.owner == "canonicalfake" && $0.repo == "only" }
    #expect(canonicalMatches.count == 1)
    #expect(!packages.contains { $0.owner == "fakealias" })
}
