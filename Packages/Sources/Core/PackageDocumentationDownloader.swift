import Foundation
import Logging
import Shared

// MARK: - Package Documentation Downloader

/// Fetches repository archives (README + CHANGELOG + LICENSE + Package.swift +
/// Sources/ + Tests/ + .docc + Examples) for each package via
/// `codeload.github.com/<owner>/<repo>/tar.gz/<ref>`, strips the noise, and writes
/// the result under `<outputDirectory>/<owner>/<repo>/`. Each package gets a
/// `manifest.json` recording what was saved and where the archive came from.
extension Core {
    public actor PackageDocumentationDownloader {
        private let outputDirectory: URL
        private let extractor: PackageArchiveExtractor

        public init(outputDirectory: URL, extractor: PackageArchiveExtractor? = nil) {
            self.outputDirectory = outputDirectory
            self.extractor = extractor ?? PackageArchiveExtractor()
        }

        // MARK: - Public API

        /// Download documentation for a list of packages
        public func download(
            packages: [PackageReference],
            onProgress: (@Sendable (PackageDownloadProgress) -> Void)? = nil
        ) async throws -> PackageDownloadStatistics {
            var stats = PackageDownloadStatistics(
                totalPackages: packages.count,
                startTime: Date()
            )

            logInfo("📦 Fetching archives for \(packages.count) packages...")

            for (index, package) in packages.enumerated() {
                let packageName = "\(package.owner)/\(package.repo)"
                let progress = PackageDownloadProgress(
                    currentPackage: packageName,
                    completed: index,
                    total: packages.count,
                    status: "Fetching archive"
                )
                onProgress?(progress)

                if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                    let percent = String(format: "%.1f", progress.percentage)
                    logInfo("📊 Progress: \(percent)% (\(index + 1)/\(packages.count))")
                }

                let packageDir = outputDirectory
                    .appendingPathComponent(package.owner)
                    .appendingPathComponent(package.repo)
                let isNew = !FileManager.default.fileExists(atPath: packageDir.path)

                do {
                    let result = try await extractor.fetchAndExtract(
                        owner: package.owner,
                        repo: package.repo,
                        destination: packageDir
                    )

                    let hostedURL = await detectDocumentationSite(
                        owner: package.owner,
                        repo: package.repo
                    )?.baseURL
                    try writeManifest(
                        for: package,
                        result: result,
                        hostedURL: hostedURL,
                        destination: packageDir
                    )

                    if isNew {
                        stats.newPackages += 1
                    } else {
                        stats.updatedPackages += 1
                    }
                    stats.totalFilesSaved += result.savedFiles.count
                    stats.totalBytesSaved += result.totalBytes

                    let sizeKB = result.totalBytes / 1024
                    let label = isNew ? "New" : "Updated"
                    logInfo("  ✅ \(packageName) - \(label), \(result.savedFiles.count) files, \(sizeKB) KB")
                } catch PackageArchiveExtractor.ExtractError.tarballNotFound {
                    stats.errors += 1
                    logError("  ✗ \(packageName) - archive not found on any candidate ref")
                } catch PackageArchiveExtractor.ExtractError.tarballTooLarge(let bytes) {
                    stats.errors += 1
                    let mb = bytes / (1024 * 1024)
                    logError("  ✗ \(packageName) - archive too large (\(mb) MB) — skipped")
                } catch {
                    stats.errors += 1
                    logError("  ✗ \(packageName) - \(error.localizedDescription)")
                }

                if index < packages.count - 1 {
                    try await applyRateLimit(for: package, at: index)
                }
            }

            stats.endTime = Date()

            logInfo("\n✅ Download completed!")
            logInfo("   Total packages: \(stats.totalPackages)")
            logInfo("   New: \(stats.newPackages)")
            logInfo("   Updated: \(stats.updatedPackages)")
            logInfo("   Files saved: \(stats.totalFilesSaved)")
            logInfo("   Bytes saved: \(stats.totalBytesSaved / 1024) KB")
            logInfo("   Errors: \(stats.errors)")
            if let duration = stats.duration {
                logInfo("   Duration: \(Int(duration))s")
            }

            return stats
        }

        // MARK: - Manifest

        private func writeManifest(
            for package: PackageReference,
            result: PackageArchiveExtractor.Result,
            hostedURL: URL?,
            destination: URL
        ) throws {
            struct Manifest: Encodable {
                let owner: String
                let repo: String
                let url: String
                let fetchedAt: Date
                let cupertinoVersion: String
                let branch: String
                let savedFiles: [String]
                let totalBytes: Int64
                let tarballBytes: Int
                let hostedDocumentationURL: String?
            }
            let manifest = Manifest(
                owner: package.owner,
                repo: package.repo,
                url: package.url,
                fetchedAt: Date(),
                cupertinoVersion: Shared.Constants.App.version,
                branch: result.branch,
                savedFiles: result.savedFiles,
                totalBytes: result.totalBytes,
                tarballBytes: result.tarballBytes,
                hostedDocumentationURL: hostedURL?.absoluteString
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: destination.appendingPathComponent("manifest.json"))
        }

        // MARK: - README Download

        /// Download README.md from GitHub
        public func downloadREADME(
            owner: String,
            repo: String
        ) async throws -> String {
            // Validate input to prevent path traversal
            guard isValidGitHubIdentifier(owner),
                  isValidGitHubIdentifier(repo) else {
                throw PackageDownloadError.invalidInput
            }

            // Try multiple README variants and branches
            let readmeNames = ["README.md", "README.MD", "readme.md", "Readme.md"]
            let branches = ["main", "master"]

            for branch in branches {
                for readmeName in readmeNames {
                    do {
                        let urlString = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(readmeName)"
                        guard let url = URL(string: urlString) else {
                            continue
                        }

                        let (data, response) = try await URLSession.shared.data(from: url)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            continue
                        }

                        if httpResponse.statusCode == 200,
                           let content = String(data: data, encoding: .utf8) {
                            return content
                        }
                    } catch {
                        // Try next variant/branch
                        continue
                    }
                }
            }

            throw PackageDownloadError.readmeNotFound
        }

        // MARK: - Documentation Site Detection

        /// Detect if package has hosted documentation
        public func detectDocumentationSite(
            owner: String,
            repo: String
        ) async -> DocumentationSite? {
            // Justification: KnownSite is a private helper struct that only exists to replace
            // a 4-member tuple (which would violate large_tuple rule). This struct is used
            // exclusively within this method to store known documentation site mappings.
            // Moving it outside would expose it unnecessarily and reduce code locality.
            // Trade-off: Accept nesting violation to avoid large_tuple violation and maintain encapsulation.
            struct KnownSite {
                let owner: String
                let repo: String
                let url: String
                let type: DocumentationSite.DocumentationType
            }

            let knownSites = [
                KnownSite(owner: "vapor", repo: "vapor", url: "https://docs.vapor.codes", type: .customDomain),
                KnownSite(owner: "hummingbird-project", repo: "hummingbird", url: "https://docs.hummingbird.codes", type: .customDomain),
                KnownSite(owner: "apple", repo: "swift-nio", url: "https://swiftpackageindex.com/apple/swift-nio/main/documentation", type: .githubPages),
                KnownSite(owner: "apple", repo: "swift-collections", url: "https://swiftpackageindex.com/apple/swift-collections/main/documentation", type: .githubPages),
                KnownSite(owner: "apple", repo: "swift-algorithms", url: "https://swiftpackageindex.com/apple/swift-algorithms/main/documentation", type: .githubPages),
            ]

            // Check known sites first
            for site in knownSites {
                let knownOwner = site.owner
                let knownRepo = site.repo
                let urlString = site.url
                let type = site.type
                if owner.lowercased() == knownOwner.lowercased(),
                   repo.lowercased() == knownRepo.lowercased(),
                   let url = URL(string: urlString) {
                    return DocumentationSite(type: type, baseURL: url)
                }
            }

            // Try GitHub Pages convention: owner.github.io/repo
            if let githubPagesURL = URL(string: "https://\(owner).github.io/\(repo)/") {
                if await urlExists(githubPagesURL) {
                    return DocumentationSite(type: .githubPages, baseURL: githubPagesURL)
                }
            }

            return nil
        }

        // MARK: - File System Operations

        private func saveREADME(
            _ content: String,
            owner: String,
            repo: String
        ) async throws {
            let packageDir = outputDirectory
                .appendingPathComponent(owner)
                .appendingPathComponent(repo)

            // Create directory structure
            try FileManager.default.createDirectory(
                at: packageDir,
                withIntermediateDirectories: true
            )

            // Save README
            let readmePath = packageDir.appendingPathComponent("README.md")
            try content.write(to: readmePath, atomically: true, encoding: .utf8)
        }

        // MARK: - Helpers

        private func urlExists(_ url: URL) async -> Bool {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 5

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    return (200...299).contains(httpResponse.statusCode)
                }

                return false
            } catch {
                return false
            }
        }

        private func isValidGitHubIdentifier(_ identifier: String) -> Bool {
            // GitHub identifier rules (conservative union of owner + repo):
            //   alphanumeric + "-_.".
            // `.` is valid in repo names (e.g. `jmespath.swift`, `SwiftyJSON.swift`);
            // owners use only alphanumeric + hyphen in practice, but allowing `.`
            // here is safe because `..` is still rejected and `/` can't appear.
            let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
            return identifier.rangeOfCharacter(from: allowedCharacters.inverted) == nil
                && !identifier.isEmpty
                && !identifier.contains("..")
                && !identifier.hasPrefix("/")
                && !identifier.hasPrefix(".")
                && !identifier.hasSuffix(".")
        }

        // MARK: - Rate Limiting

        /// Apply priority-based rate limiting between package downloads
        private func applyRateLimit(for package: PackageReference, at index: Int) async throws {
            // Use higher delay for periodic checkpoints (every N packages)
            if (index + 1) % Shared.Constants.Interval.progressLogEvery == 0 {
                try await Task.sleep(for: Shared.Constants.Delay.packageFetchHighPriority)
            } else {
                // Normal delay between downloads
                try await Task.sleep(for: Shared.Constants.Delay.packageFetchNormal)
            }
        }

        // MARK: - Logging

        private func logInfo(_ message: String) {
            Log.info(message, category: .packages)
        }

        private func logError(_ message: String) {
            Log.error(message, category: .packages)
        }
    }
}

// MARK: - Errors

public enum PackageDownloadError: Error, LocalizedError {
    case readmeNotFound
    case invalidInput
    case networkError(Error)
    case fileSystemError(Error)

    public var errorDescription: String? {
        switch self {
        case .readmeNotFound:
            return "README.md not found in repository"
        case .invalidInput:
            return "Invalid owner or repository name"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case let .fileSystemError(error):
            return "File system error: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .readmeNotFound:
            return "Ensure the repository has a README.md file in the root directory"
        case .invalidInput:
            return "Provide a valid GitHub owner and repository name"
        case .networkError:
            return "Check your internet connection and try again"
        case .fileSystemError:
            return "Ensure you have write permissions to the output directory"
        }
    }
}
