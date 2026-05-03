@testable import Distribution
import Foundation
@testable import Shared
import Testing

// MARK: - URL Construction

//
// PackagesSetupCommand was collapsed into the unified `cupertino setup`
// flow during #192 — the URL helpers moved to `Distribution.PackagesReleaseURL`
// in #246 alongside the rest of the setup pipeline.

@Suite("Distribution.PackagesReleaseURL construction")
struct PackagesReleaseURLTests {
    @Test("Release tag prepends v")
    func releaseTag() {
        #expect(Distribution.PackagesReleaseURL.makeReleaseTag(version: "0.1.0") == "v0.1.0")
        #expect(Distribution.PackagesReleaseURL.makeReleaseTag(version: "1.2.3") == "v1.2.3")
    }

    @Test("Zip filename follows cupertino-packages-v<version>.zip pattern")
    func zipFilename() {
        #expect(
            Distribution.PackagesReleaseURL.makeZipFilename(version: "0.1.0")
                == "cupertino-packages-v0.1.0.zip"
        )
        #expect(
            Distribution.PackagesReleaseURL.makeZipFilename(version: "1.0.0")
                == "cupertino-packages-v1.0.0.zip"
        )
    }

    @Test("Release URL uses default base URL from Shared constants")
    func releaseURLDefault() {
        let url = Distribution.PackagesReleaseURL.makeReleaseURL(version: "0.1.0")
        #expect(url == "https://github.com/mihaelamj/cupertino-packages/releases/download/v0.1.0")
    }

    @Test("Release URL honors a custom base URL")
    func releaseURLCustom() {
        let url = Distribution.PackagesReleaseURL.makeReleaseURL(
            version: "0.1.0",
            baseURL: "http://localhost:8080/releases"
        )
        #expect(url == "http://localhost:8080/releases/v0.1.0")
    }

    @Test("Download URL composes release URL and zip filename")
    func downloadURL() {
        let url = Distribution.PackagesReleaseURL.makeDownloadURL(version: "0.1.0")
        #expect(
            url
                == "https://github.com/mihaelamj/cupertino-packages/releases/download/v0.1.0/cupertino-packages-v0.1.0.zip"
        )
    }

    @Test("Download URL with custom base URL keeps the same filename pattern")
    func downloadURLCustom() {
        let url = Distribution.PackagesReleaseURL.makeDownloadURL(
            version: "1.0.0",
            baseURL: "http://localhost:8080/releases"
        )
        #expect(url == "http://localhost:8080/releases/v1.0.0/cupertino-packages-v1.0.0.zip")
    }
}
