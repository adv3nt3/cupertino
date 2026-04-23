import Foundation
import Shared

extension Core {
    /// Fetches a repo's source tarball from `codeload.github.com/<owner>/<repo>/tar.gz/<ref>`
    /// and extracts the subset of files useful for "how do I use this package":
    /// README, CHANGELOG, LICENSE, Package.swift, all markdown and DocC contents, all
    /// Sources/ and Tests/ Swift files, all Examples/Demo directories. Binary assets,
    /// CI metadata, and build artefacts are pruned post-extract.
    ///
    /// Uses `/usr/bin/tar` via a subprocess so we don't drag a Swift tar implementation
    /// into the dependency graph; macOS's bsdtar reads `.tar.gz` directly.
    public actor PackageArchiveExtractor {
        public struct Result: Sendable {
            public let branch: String
            public let savedFiles: [String]
            public let totalBytes: Int64
            public let tarballBytes: Int
        }

        public enum ExtractError: Error {
            case tarballNotFound
            case tarballTooLarge(Int)
            case tarFailed(code: Int32, stderr: String)
            case tarballTimeout
            case downloadFailed
        }

        private let session: URLSession
        private let candidateRefs: [String]
        private let maxTarballBytes: Int

        public init(
            session: URLSession = .shared,
            candidateRefs: [String] = ["HEAD", "main", "master"],
            maxTarballBytes: Int = 75 * 1024 * 1024
        ) {
            self.session = session
            self.candidateRefs = candidateRefs
            self.maxTarballBytes = maxTarballBytes
        }

        /// Download + extract a package archive into `destination`. The destination
        /// directory is wiped before extraction so re-runs produce a clean tree
        /// (no stale files from a previous layout).
        public func fetchAndExtract(
            owner: String,
            repo: String,
            destination: URL
        ) async throws -> Result {
            for ref in candidateRefs {
                switch await downloadTarball(owner: owner, repo: repo, ref: ref) {
                case .success(let data):
                    if data.count > maxTarballBytes {
                        throw ExtractError.tarballTooLarge(data.count)
                    }
                    return try extract(
                        data: data,
                        branch: ref,
                        destination: destination
                    )
                case .notFound:
                    continue
                case .transient:
                    continue
                }
            }
            throw ExtractError.tarballNotFound
        }

        // MARK: - Download

        private enum DownloadResult {
            case success(Data)
            case notFound
            case transient
        }

        private func downloadTarball(owner: String, repo: String, ref: String) async -> DownloadResult {
            let urlString = "https://codeload.github.com/\(owner)/\(repo)/tar.gz/\(ref)"
            guard let url = URL(string: urlString) else { return .transient }
            var request = URLRequest(url: url)
            request.setValue(Shared.Constants.App.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 60
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return .transient }
                if http.statusCode == 200 { return .success(data) }
                if http.statusCode == 404 { return .notFound }
                return .transient
            } catch {
                return .transient
            }
        }

        // MARK: - Extraction

        private func extract(
            data: Data,
            branch: String,
            destination: URL
        ) throws -> Result {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("cupertino-pkg-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }

            let tarballURL = scratch.appendingPathComponent("archive.tar.gz")
            try data.write(to: tarballURL)

            let extractDir = scratch.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            try runTar(tarballURL: tarballURL, outputDir: extractDir)

            try prune(rootURL: extractDir)

            // Wipe destination for a clean re-extract.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: extractDir, to: destination)

            let savedFiles = collectRelativePaths(under: destination)
            let totalBytes = totalBytesUnder(destination)

            return Result(
                branch: branch,
                savedFiles: savedFiles,
                totalBytes: totalBytes,
                tarballBytes: data.count
            )
        }

        private func runTar(tarballURL: URL, outputDir: URL) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = [
                "-xzf", tarballURL.path,
                "-C", outputDir.path,
                "--strip-components=1",
            ]
            let stderr = Pipe()
            process.standardError = stderr
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let err = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                throw ExtractError.tarFailed(code: process.terminationStatus, stderr: err)
            }
        }

        // MARK: - Pruning

        /// Remove everything in the extracted tree that matches the exclusion rules.
        /// Runs post-extract so the logic is all Swift (easier to test than tar glob
        /// patterns, which vary subtly between bsdtar and gnutar).
        internal func prune(rootURL: URL) throws {
            try pruneTopLevelDirectories(at: rootURL)
            try pruneByPatterns(rootURL: rootURL)
        }

        private func pruneTopLevelDirectories(at root: URL) throws {
            for name in Self.excludedTopLevelDirectories {
                let candidate = root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    try FileManager.default.removeItem(at: candidate)
                }
            }
        }

        private func pruneByPatterns(rootURL: URL) throws {
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { return }

            var toRemove: [URL] = []
            while let candidate = enumerator.nextObject() as? URL {
                let name = candidate.lastPathComponent
                let ext = candidate.pathExtension.lowercased()
                let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

                if isDirectory, name.hasSuffix(".xcassets") {
                    toRemove.append(candidate)
                    enumerator.skipDescendants()
                    continue
                }

                if !isDirectory {
                    if Self.excludedExtensions.contains(ext) {
                        toRemove.append(candidate)
                    } else if Self.excludedHiddenFiles.contains(name) {
                        toRemove.append(candidate)
                    }
                }
            }

            for url in toRemove {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // MARK: - Enumeration helpers

        private func collectRelativePaths(under root: URL) -> [String] {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey]
            ) else {
                return []
            }
            var paths: [String] = []
            let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            while let candidate = enumerator.nextObject() as? URL {
                let isRegular = (try? candidate.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                guard isRegular else { continue }
                let full = candidate.path
                if full.hasPrefix(rootPrefix) {
                    paths.append(String(full.dropFirst(rootPrefix.count)))
                }
            }
            return paths.sorted()
        }

        private func totalBytesUnder(_ root: URL) -> Int64 {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
            ) else {
                return 0
            }
            var total: Int64 = 0
            while let candidate = enumerator.nextObject() as? URL {
                guard
                    let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                    values.isRegularFile == true,
                    let size = values.fileSize
                else { continue }
                total += Int64(size)
            }
            return total
        }

        // MARK: - Exclusion rules (visible for testing)

        internal static let excludedTopLevelDirectories: Set<String> = [
            ".github",
            ".build",
            "DerivedData",
            ".swiftpm",
            ".git",
            "Benchmarks",
        ]

        internal static let excludedExtensions: Set<String> = [
            "png",
            "jpg",
            "jpeg",
            "gif",
            "xib",
            "storyboard",
            "nib",
            "dsym",
            "zip",
            "tar",
            "dat",
            "ico",
            "pdf",
        ]

        internal static let excludedHiddenFiles: Set<String> = [
            ".editorconfig",
            ".gitignore",
            ".gitattributes",
            ".mailmap",
            ".licenseignore",
            ".swift-format",
            ".swift-version",
            ".travis.yml",
            ".codecov.yml",
            ".dockerignore",
        ]
    }
}
