import ArgumentParser
import Foundation
import Logging
import Search
import Shared

// MARK: - Ask command (#192 section E5)
//
// Public-facing smart query: `cupertino ask "<question>"`. Fans the question
// across every configured source (packages, apple-docs, apple-archive, HIG,
// swift-evolution, swift-org, swift-book) using `Search.SmartQuery` and
// prints the fused top-N as a plain-text report.
//
// Compared to `cupertino search` (which is a thin CLI over one source):
//  - `ask` accepts free-text questions, not FTS MATCH expressions
//  - `ask` runs every source automatically, no `--source` required
//  - `ask` returns chunked excerpts (ready for LLM context), not URIs

@available(macOS 10.15, macCatalyst 13, iOS 13, tvOS 13, watchOS 6, *)
struct AskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "Ask a natural-language question across all indexed sources"
    )

    @Argument(help: "Plain-text question, e.g. \"how do I make a SwiftUI view observable\"")
    var question: String

    @Option(name: .long, help: "Max fused results to return across all sources.")
    var limit: Int = 5

    @Option(name: .long, help: "Per-source candidate cap before rank fusion.")
    var perSource: Int = 10

    @Option(name: .long, help: "Override search.db path.")
    var searchDb: String?

    @Option(name: .long, help: "Override packages.db path.")
    var packagesDb: String?

    @Flag(name: .long, help: "Skip the packages source (useful when packages.db is absent or stale).")
    var skipPackages: Bool = false

    @Flag(name: .long, help: "Skip all apple-docs-backed sources (useful when search.db is absent).")
    var skipDocs: Bool = false

    mutating func run() async throws {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Logging.ConsoleLogger.error("❌ Question cannot be empty.")
            throw ExitCode.failure
        }

        var fetchers: [any Search.CandidateFetcher] = []
        var searchIndex: Search.Index?

        // Docs-backed fetchers share one Search.Index actor.
        if !skipDocs {
            let searchDBURL = searchDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Constants.defaultSearchDatabase
            if FileManager.default.fileExists(atPath: searchDBURL.path) {
                do {
                    let index = try await Search.Index(dbPath: searchDBURL)
                    searchIndex = index
                    for source in Self.docsSources {
                        fetchers.append(Search.DocsSourceCandidateFetcher(
                            searchIndex: index,
                            source: source.prefix,
                            includeArchive: source.includeArchive
                        ))
                    }
                } catch {
                    Logging.ConsoleLogger.error("⚠️  Could not open search.db: \(error.localizedDescription)")
                }
            } else {
                Logging.ConsoleLogger.info("ℹ️  search.db not found at \(searchDBURL.path) — skipping doc sources.")
            }
        }

        if !skipPackages {
            let packagesDBURL = packagesDb.map { URL(fileURLWithPath: $0).expandingTildeInPath }
                ?? Shared.Constants.defaultPackagesDatabase
            if FileManager.default.fileExists(atPath: packagesDBURL.path) {
                fetchers.append(Search.PackageFTSCandidateFetcher(dbPath: packagesDBURL))
            } else {
                Logging.ConsoleLogger.info("ℹ️  packages.db not found at \(packagesDBURL.path) — skipping packages.")
            }
        }

        guard !fetchers.isEmpty else {
            Logging.ConsoleLogger.error("❌ No data sources available. Run `cupertino setup` to populate them.")
            throw ExitCode.failure
        }

        let smartQuery = Search.SmartQuery(fetchers: fetchers)
        let result = await smartQuery.answer(
            question: trimmed,
            limit: limit,
            perFetcherLimit: perSource
        )

        if let index = searchIndex {
            await index.disconnect()
        }

        Self.printReport(result: result, question: trimmed)
    }

    // MARK: - Helpers

    /// Docs-backed sources in a consistent order. `apple-archive` is included
    /// but explicitly flags `includeArchive: true` so the base search path
    /// doesn't exclude it.
    private static let docsSources: [(prefix: String, includeArchive: Bool)] = [
        (Shared.Constants.SourcePrefix.appleDocs, false),
        (Shared.Constants.SourcePrefix.appleArchive, true),
        (Shared.Constants.SourcePrefix.hig, false),
        (Shared.Constants.SourcePrefix.swiftEvolution, false),
        (Shared.Constants.SourcePrefix.swiftOrg, false),
        (Shared.Constants.SourcePrefix.swiftBook, false),
    ]

    private static func printReport(result: Search.SmartResult, question: String) {
        if result.candidates.isEmpty {
            let sources = result.contributingSources.isEmpty
                ? "no sources responded"
                : "searched \(result.contributingSources.joined(separator: ", "))"
            print("No matches for: \(question)")
            print("(\(sources))")
            return
        }

        print("Question: \(question)")
        print("Searched: \(result.contributingSources.joined(separator: ", "))")
        print("")

        for (i, fused) in result.candidates.enumerated() {
            let c = fused.candidate
            print("══════════════════════════════════════════════════════════════════════")
            print("[\(i + 1)] \(c.title)  •  source: \(c.source)  •  score: \(String(format: "%.4f", fused.score))")
            print("    \(c.identifier)")
            print("──────────────────────────────────────────────────────────────────────")
            print(c.chunk)
            print("")
        }
    }
}
