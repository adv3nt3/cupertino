import Foundation
import Shared

extension Core {
    /// Walks a downloaded package on disk and writes an `availability.json`
    /// alongside its `manifest.json`, capturing:
    ///
    /// - The package's `Package.swift` `platforms: [...]` block (deployment targets).
    /// - Every `@available(...)` attribute occurrence in `.swift` source under
    ///   `Sources/` and `Tests/`, with file path + line + the parsed platform list.
    ///
    /// Pure on-disk pass — no network. Idempotent: rewrites the JSON each call.
    /// Regex-based; multi-line `@available` attrs aren't recognised and the
    /// scanner doesn't associate hits with specific declarations (would need
    /// AST). Good enough for first-cut ranking signals per #219; an AST upgrade
    /// is a follow-up that can extend `ASTIndexer.SwiftSourceExtractor`.
    public actor PackageAvailabilityAnnotator {
        public init() {}

        public static let outputFilename = "availability.json"

        public struct AnnotationResult: Codable, Sendable, Equatable {
            public let version: String
            public let annotatedAt: Date
            public let deploymentTargets: [String: String]
            public let fileAvailability: [FileAvailability]
            public let stats: Stats

            public struct Stats: Codable, Sendable, Equatable {
                public let filesScanned: Int
                public let filesWithAvailability: Int
                public let totalAttributes: Int
            }
        }

        public struct FileAvailability: Codable, Sendable, Equatable {
            public let relpath: String
            public let attributes: [Attribute]
        }

        public struct Attribute: Codable, Sendable, Equatable {
            public let line: Int
            public let raw: String
            public let platforms: [String]
        }

        public enum AnnotationError: Error, Sendable, Equatable {
            case missingPackageDirectory(URL)
            case writeFailed(String)
        }

        @discardableResult
        public func annotate(packageDirectory: URL) async throws -> AnnotationResult {
            let manager = FileManager.default
            // Resolve symlinks so /var ↔ /private/var on macOS doesn't trip
            // the relpath stripping below when callers pass a non-resolved
            // URL (e.g. test temp dirs).
            let resolvedDir = packageDirectory.resolvingSymlinksInPath()
            guard manager.fileExists(atPath: resolvedDir.path) else {
                throw AnnotationError.missingPackageDirectory(packageDirectory)
            }

            let packageSwiftURL = resolvedDir.appendingPathComponent("Package.swift")
            let deploymentTargets: [String: String]
            if let manifest = try? String(contentsOf: packageSwiftURL, encoding: .utf8) {
                deploymentTargets = Self.parsePlatforms(from: manifest)
            } else {
                deploymentTargets = [:]
            }

            var fileAvailability: [FileAvailability] = []
            var filesScanned = 0
            var totalAttrs = 0

            let basePath = resolvedDir.path
            for subdir in ["Sources", "Tests"] {
                let root = resolvedDir.appendingPathComponent(subdir)
                guard manager.fileExists(atPath: root.path) else { continue }
                let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil)
                while let next = enumerator?.nextObject() as? URL {
                    guard next.pathExtension == "swift" else { continue }
                    filesScanned += 1
                    guard let source = try? String(contentsOf: next, encoding: .utf8) else { continue }
                    let attrs = Self.extractAvailability(from: source)
                    if !attrs.isEmpty {
                        let resolvedFile = next.resolvingSymlinksInPath().path
                        let relpath: String
                        if resolvedFile.hasPrefix(basePath + "/") {
                            relpath = String(resolvedFile.dropFirst(basePath.count + 1))
                        } else {
                            relpath = resolvedFile
                        }
                        fileAvailability.append(FileAvailability(relpath: relpath, attributes: attrs))
                        totalAttrs += attrs.count
                    }
                }
            }

            // Stable sort by relpath so re-runs produce byte-identical output
            // when the corpus is unchanged.
            fileAvailability.sort { $0.relpath < $1.relpath }

            let result = AnnotationResult(
                version: "1.0",
                annotatedAt: Date(),
                deploymentTargets: deploymentTargets,
                fileAvailability: fileAvailability,
                stats: AnnotationResult.Stats(
                    filesScanned: filesScanned,
                    filesWithAvailability: fileAvailability.count,
                    totalAttributes: totalAttrs
                )
            )

            let outputURL = packageDirectory.appendingPathComponent(Self.outputFilename)
            try Self.write(result, to: outputURL)
            return result
        }

        // MARK: - Platform parsing

        /// Extract the platform → version mapping from a `Package.swift`
        /// source string. Matches `.iOS(.v16)`, `.macOS(.v10_15)`, etc.
        /// inside the first `platforms: [...]` block. Multi-line declarations
        /// are fine; nested array literals other than `platforms:` are
        /// ignored.
        public static func parsePlatforms(from packageSwift: String) -> [String: String] {
            guard let blockMatch = packageSwift.range(
                of: #"platforms\s*:\s*\[([\s\S]*?)\]"#,
                options: .regularExpression
            ) else {
                return [:]
            }
            let block = String(packageSwift[blockMatch])

            var targets: [String: String] = [:]
            let entryPattern = #"\.([A-Za-z]+)\s*\(\s*\.v([0-9_]+)\s*\)"#
            guard let regex = try? NSRegularExpression(pattern: entryPattern) else { return [:] }
            let nsBlock = block as NSString
            let matches = regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length))
            for match in matches where match.numberOfRanges == 3 {
                let platform = nsBlock.substring(with: match.range(at: 1))
                let raw = nsBlock.substring(with: match.range(at: 2))
                let normalized = raw.replacingOccurrences(of: "_", with: ".")
                let version = normalized.contains(".") ? normalized : "\(normalized).0"
                targets[platform] = version
            }
            return targets
        }

        // MARK: - @available attribute parsing

        /// Find every `@available(...)` attribute in a Swift source string.
        /// Per-line scan; multi-line attributes (rare) are not handled.
        /// Records line number (1-indexed), the raw paren content, and a
        /// list of platform tokens parsed from the args (first whitespace-
        /// delimited word per comma-separated entry, with `*` and named
        /// keywords like `deprecated` / `noasync` preserved verbatim).
        public static func extractAvailability(from source: String) -> [Attribute] {
            var attrs: [Attribute] = []
            var lineNo = 0
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                lineNo += 1
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let avRange = trimmed.range(of: "@available") else { continue }
                guard let openParen = trimmed.range(
                    of: "(",
                    range: avRange.upperBound..<trimmed.endIndex
                ) else { continue }

                var depth = 0
                var endIndex: String.Index?
                var idx = openParen.lowerBound
                while idx < trimmed.endIndex {
                    let char = trimmed[idx]
                    if char == "(" {
                        depth += 1
                    } else if char == ")" {
                        depth -= 1
                        if depth == 0 {
                            endIndex = trimmed.index(after: idx)
                            break
                        }
                    }
                    idx = trimmed.index(after: idx)
                }
                guard let close = endIndex else { continue }
                let raw = String(trimmed[openParen.lowerBound..<close])
                let innerStart = trimmed.index(after: openParen.lowerBound)
                let innerEnd = trimmed.index(before: close)
                guard innerStart <= innerEnd else { continue }
                let inner = String(trimmed[innerStart..<innerEnd])

                let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var platforms: [String] = []
                let keywords: Set<String> = [
                    "*", "deprecated", "message", "renamed",
                    "obsoleted", "introduced", "noasync", "unavailable",
                ]
                for part in parts where !part.isEmpty {
                    let firstToken = part.split(whereSeparator: { $0 == " " || $0 == ":" })
                        .first.map(String.init) ?? part
                    if keywords.contains(firstToken) {
                        platforms.append(firstToken)
                    } else {
                        platforms.append(firstToken)
                    }
                }
                attrs.append(Attribute(line: lineNo, raw: raw, platforms: platforms))
            }
            return attrs
        }

        // MARK: - Persistence

        /// Encode `result` and atomically write to `url`. `internal static`
        /// rather than instance-method-on-actor so tests can drive it
        /// without an actor hop.
        static func write(_ result: AnnotationResult, to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(result)
                try data.write(to: url, options: [.atomic])
            } catch {
                throw AnnotationError.writeFailed(error.localizedDescription)
            }
        }
    }
}
