import Foundation
import Shared

// MARK: - Packages release URL helpers
//
// URL construction for the `cupertino-packages` release zip is its own type
// so `SetupCommand` can call into it AND the CLI tests can guard the URL
// shape independently of any user-facing command. Originally lived on the
// (now-removed) `PackagesSetupCommand`; #192 collapsed package setup into
// the unified `cupertino setup` flow but the URL helpers stayed pure so the
// tests didn't have to be rewritten.

enum PackagesReleaseURL {
    static func makeReleaseTag(version: String) -> String {
        "v\(version)"
    }

    static func makeZipFilename(version: String) -> String {
        "cupertino-packages-\(makeReleaseTag(version: version)).zip"
    }

    static func makeReleaseURL(
        version: String,
        baseURL: String = Shared.Constants.App.packagesReleaseBaseURL
    ) -> String {
        "\(baseURL)/\(makeReleaseTag(version: version))"
    }

    static func makeDownloadURL(
        version: String,
        baseURL: String = Shared.Constants.App.packagesReleaseBaseURL
    ) -> String {
        "\(makeReleaseURL(version: version, baseURL: baseURL))/\(makeZipFilename(version: version))"
    }
}
