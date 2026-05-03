import Foundation
import Shared

extension Distribution {
    /// URL construction for the `cupertino-packages` release zip. Pure
    /// helpers, separated from `SetupService` so tests can guard URL shape
    /// independently of any orchestration. Originally lived in the CLI as
    /// `CLI.PackagesReleaseURL` (#192); moved to Distribution in #246
    /// alongside the rest of the setup pipeline.
    public enum PackagesReleaseURL {
        public static func makeReleaseTag(version: String) -> String {
            "v\(version)"
        }

        public static func makeZipFilename(version: String) -> String {
            "cupertino-packages-\(makeReleaseTag(version: version)).zip"
        }

        public static func makeReleaseURL(
            version: String,
            baseURL: String = Shared.Constants.App.packagesReleaseBaseURL
        ) -> String {
            "\(baseURL)/\(makeReleaseTag(version: version))"
        }

        public static func makeDownloadURL(
            version: String,
            baseURL: String = Shared.Constants.App.packagesReleaseBaseURL
        ) -> String {
            "\(makeReleaseURL(version: version, baseURL: baseURL))/\(makeZipFilename(version: version))"
        }
    }
}
