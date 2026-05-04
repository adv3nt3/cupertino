import Foundation
@testable import MCPSupport
@testable import Shared
import Testing

@Test func cupertinoMCPSupport() async throws {
    // Test placeholder
}

// MARK: - Path Traversal Hardening

@Suite("DocsResourceProvider path traversal hardening")
struct DocsResourceProviderPathTraversalTests {
    private static func makeTempRoot(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcpsupport-pathtraversal-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func makeProvider(
        outputDir: URL,
        evolutionDir: URL,
        archiveDir: URL
    ) -> DocsResourceProvider {
        let config = Shared.Configuration(
            crawler: Shared.CrawlerConfiguration(outputDirectory: outputDir),
            changeDetection: Shared.ChangeDetectionConfiguration(),
            output: Shared.OutputConfiguration()
        )
        return DocsResourceProvider(
            configuration: config,
            evolutionDirectory: evolutionDir,
            archiveDirectory: archiveDir
        )
    }

    @Test("apple-docs URI with parent-directory segments is rejected")
    func appleDocsRejectsParentTraversal() async throws {
        let outputDir = try Self.makeTempRoot("docs-traversal-out")
        let evolutionDir = try Self.makeTempRoot("docs-traversal-evo")
        let archiveDir = try Self.makeTempRoot("docs-traversal-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        // Create a sibling file outside the configured outputDirectory to verify the
        // traversal would otherwise resolve to readable bytes.
        let escapeTarget = outputDir.deletingLastPathComponent()
            .appendingPathComponent("escape-target-\(UUID().uuidString).md")
        try "secret".write(to: escapeTarget, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: escapeTarget) }

        let escapeName = escapeTarget.deletingPathExtension().lastPathComponent
        let uri = "apple-docs://swiftui/../\(escapeName)"

        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: uri)
        }
    }

    @Test("apple-docs URI with backslash component is rejected")
    func appleDocsRejectsBackslash() async throws {
        let outputDir = try Self.makeTempRoot("docs-bslash-out")
        let evolutionDir = try Self.makeTempRoot("docs-bslash-evo")
        let archiveDir = try Self.makeTempRoot("docs-bslash-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "apple-docs://swiftui/foo\\bar")
        }
    }

    @Test("apple-docs URI with NUL byte is rejected")
    func appleDocsRejectsNullByte() async throws {
        let outputDir = try Self.makeTempRoot("docs-nul-out")
        let evolutionDir = try Self.makeTempRoot("docs-nul-evo")
        let archiveDir = try Self.makeTempRoot("docs-nul-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "apple-docs://swiftui/foo\0bar")
        }
    }

    @Test("apple-archive URI with parent-directory in guideUID is rejected")
    func archiveRejectsTraversalInGuideUID() async throws {
        let outputDir = try Self.makeTempRoot("arc-guide-out")
        let evolutionDir = try Self.makeTempRoot("arc-guide-evo")
        let archiveDir = try Self.makeTempRoot("arc-guide-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "apple-archive://../etc/passwd")
        }
    }

    @Test("apple-archive URI with parent-directory in filename is rejected")
    func archiveRejectsTraversalInFilename() async throws {
        let outputDir = try Self.makeTempRoot("arc-file-out")
        let evolutionDir = try Self.makeTempRoot("arc-file-evo")
        let archiveDir = try Self.makeTempRoot("arc-file-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "apple-archive://core-animation/../../escape")
        }
    }

    @Test("swift-evolution URI with parent-directory is rejected")
    func evolutionRejectsParentTraversal() async throws {
        let outputDir = try Self.makeTempRoot("evo-traversal-out")
        let evolutionDir = try Self.makeTempRoot("evo-traversal-evo")
        let archiveDir = try Self.makeTempRoot("evo-traversal-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "swift-evolution://..")
        }
    }

    @Test("swift-evolution URI containing slash is rejected")
    func evolutionRejectsSlash() async throws {
        let outputDir = try Self.makeTempRoot("evo-slash-out")
        let evolutionDir = try Self.makeTempRoot("evo-slash-evo")
        let archiveDir = try Self.makeTempRoot("evo-slash-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "swift-evolution://SE-0001/../passwd")
        }
    }

    @Test("apple-docs happy-path read still succeeds after hardening")
    func appleDocsHappyPath() async throws {
        let outputDir = try Self.makeTempRoot("docs-happy-out")
        let evolutionDir = try Self.makeTempRoot("docs-happy-evo")
        let archiveDir = try Self.makeTempRoot("docs-happy-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let frameworkDir = outputDir.appendingPathComponent("swiftui")
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        let mdFile = frameworkDir.appendingPathComponent("documentation_swiftui_view.md")
        try "# View\n\nbody".write(to: mdFile, atomically: true, encoding: .utf8)

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        let result = try await provider.readResource(uri: "apple-docs://swiftui/documentation_swiftui_view")
        guard case let .text(textContent) = result.contents.first else {
            Issue.record("expected text content")
            return
        }
        #expect(textContent.text.contains("View"))
    }

    @Test("apple-docs URI with percent-encoded dots (%2e%2e) does not escape base dir")
    func appleDocsPercentEncodedDots() async throws {
        let outputDir = try Self.makeTempRoot("docs-pct-dots-out")
        let evolutionDir = try Self.makeTempRoot("docs-pct-dots-evo")
        let archiveDir = try Self.makeTempRoot("docs-pct-dots-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        // %2e%2e is not ".." literally, so it passes the component validator and is treated
        // as a filename; the call either throws resourceNotFound or invalidURI — both ToolError.
        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "apple-docs://swiftui/%2e%2e")
        }
    }

    @Test("apple-docs URI with consecutive slashes is rejected at parse time")
    func appleDocsRejectsDoubleSlash() async throws {
        let outputDir = try Self.makeTempRoot("docs-dslash-out")
        let evolutionDir = try Self.makeTempRoot("docs-dslash-evo")
        let archiveDir = try Self.makeTempRoot("docs-dslash-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        // "swiftui//foo" produces an empty segment between the slashes; isValidRelativePath
        // rejects empty segments, so parseAppleDocsURI returns nil → throws ToolError.
        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "apple-docs://swiftui//foo")
        }
    }

    @Test("apple-docs URI with percent-encoded slash (%2F) in path is not a traversal vector")
    func appleDocsPercentEncodedSlash() async throws {
        let outputDir = try Self.makeTempRoot("docs-pctslash-out")
        let evolutionDir = try Self.makeTempRoot("docs-pctslash-evo")
        let archiveDir = try Self.makeTempRoot("docs-pctslash-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        // %2F is treated as a literal filename character (no slash in the string),
        // passes validation, and then fails at file-not-found — never escaping the root.
        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "apple-docs://swiftui/foo%2Fbar")
        }
    }

    @Test("evolution proposal lookup with bare 'S' does not match SE-0001")
    func evolutionLookupRequiresBoundary() async throws {
        let outputDir = try Self.makeTempRoot("evo-prefix-out")
        let evolutionDir = try Self.makeTempRoot("evo-prefix-evo")
        let archiveDir = try Self.makeTempRoot("evo-prefix-arc")
        defer {
            try? FileManager.default.removeItem(at: outputDir)
            try? FileManager.default.removeItem(at: evolutionDir)
            try? FileManager.default.removeItem(at: archiveDir)
        }

        let proposal = evolutionDir.appendingPathComponent("SE-0001-keywords-as-argument-labels.md")
        try "# SE-0001\n\nbody".write(to: proposal, atomically: true, encoding: .utf8)

        let provider = Self.makeProvider(
            outputDir: outputDir,
            evolutionDir: evolutionDir,
            archiveDir: archiveDir
        )

        await #expect(throws: ToolError.self) {
            _ = try await provider.readResource(uri: "swift-evolution://S")
        }

        // Sanity check: the canonical SE-0001 lookup still resolves the same fixture file.
        let result = try await provider.readResource(uri: "swift-evolution://SE-0001")
        guard case let .text(textContent) = result.contents.first else {
            Issue.record("expected text content")
            return
        }
        #expect(textContent.text.contains("SE-0001"))
    }
}
