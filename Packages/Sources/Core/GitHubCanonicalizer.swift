import Foundation
import Shared

extension Core {
    /// Canonicalizes `(owner, repo)` pairs using `api.github.com/repos/<owner>/<repo>`,
    /// resolving GitHub's silent redirects (e.g. `apple/swift-docc` → `swiftlang/swift-docc`)
    /// so the resolver can dedupe aliases. Results are memoised in-process and persisted
    /// to `canonical-owners.json`, so subsequent runs don't re-hit the API for known repos.
    public actor GitHubCanonicalizer {
        public struct CanonicalName: Sendable, Equatable {
            public let owner: String
            public let repo: String

            public init(owner: String, repo: String) {
                self.owner = owner
                self.repo = repo
            }
        }

        private let cacheURL: URL
        private let session: URLSession
        private var cache: [String: String] = [:]
        private var dirty = false

        public init(cacheURL: URL, session: URLSession = .shared) {
            self.cacheURL = cacheURL
            self.session = session
            if let data = try? Data(contentsOf: cacheURL),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            {
                cache = decoded
            }
        }

        /// Return the canonical owner/repo. If the API call fails (rate limit, network
        /// error, repo deleted), the input is returned unchanged and cached so we don't
        /// thrash the API on broken seeds.
        public func canonicalize(owner: String, repo: String) async -> CanonicalName {
            let key = Self.key(owner: owner, repo: repo)
            if let cached = cache[key], let parsed = Self.parse(cached) {
                return parsed
            }
            if let canonical = await fetchCanonical(owner: owner, repo: repo) {
                cache[key] = "\(canonical.owner)/\(canonical.repo)"
                dirty = true
                return canonical
            }
            // Cache the failure: "treat input as canonical" — avoids repeat API calls
            // for repos that 404 / are rate-limited / are temporarily unavailable.
            cache[key] = "\(owner)/\(repo)"
            dirty = true
            return CanonicalName(owner: owner, repo: repo)
        }

        /// Flush the in-memory cache to disk. Call once at the end of a resolve so we
        /// don't write on every canonicalize. Safe to call repeatedly — no-ops when
        /// nothing has changed.
        public func persist() {
            guard dirty else { return }
            do {
                let dir = cacheURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: dir.path) {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(cache)
                try data.write(to: cacheURL)
                dirty = false
            } catch {
                // Non-fatal: cache is a lifetime optimisation, not a correctness boundary.
            }
        }

        // MARK: - HTTP

        private func fetchCanonical(owner: String, repo: String) async -> CanonicalName? {
            guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else {
                return nil
            }
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue(Shared.Constants.App.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return nil
                }
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let fullName = json["full_name"] as? String
                else {
                    return nil
                }
                return Self.parse(fullName)
            } catch {
                return nil
            }
        }

        // MARK: - Test hooks

        /// Primes the in-memory cache (tests + direct integrations that want to bypass
        /// the API for a specific pair).
        public func primeCache(inputOwner: String, inputRepo: String, canonicalOwner: String, canonicalRepo: String) {
            cache[Self.key(owner: inputOwner, repo: inputRepo)] = "\(canonicalOwner)/\(canonicalRepo)"
            dirty = true
        }

        /// Snapshot of the current in-memory cache for tests.
        public func cacheSnapshot() -> [String: String] { cache }

        // MARK: - Helpers

        internal static func key(owner: String, repo: String) -> String {
            "\(owner.lowercased())/\(repo.lowercased())"
        }

        internal static func parse(_ full: String) -> CanonicalName? {
            let parts = full.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return CanonicalName(owner: parts[0], repo: parts[1])
        }
    }
}
