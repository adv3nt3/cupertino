import Foundation
import Testing

@testable import CLI
@testable import Shared

// MARK: - Version tracking (#168)

@Suite("SetupCommand.SetupStatus classification")
struct SetupStatusTests {

    @Test("Missing DBs classify as .missing regardless of version stamp")
    func missingDBs() {
        let status = SetupCommand.setupStatus(
            searchDBExists: false,
            samplesDBExists: true,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("Both DBs missing also classifies as .missing")
    func bothDBsMissing() {
        let status = SetupCommand.setupStatus(
            searchDBExists: false,
            samplesDBExists: false,
            installedVersion: nil,
            currentVersion: "0.9.0"
        )
        #expect(status == .missing)
    }

    @Test("DBs present + nil version file = .unknown (legacy install)")
    func unknownLegacyInstall() {
        let status = SetupCommand.setupStatus(
            searchDBExists: true,
            samplesDBExists: true,
            installedVersion: nil,
            currentVersion: "0.9.0"
        )
        #expect(status == .unknown(current: "0.9.0"))
    }

    @Test("DBs present + matching version = .current")
    func currentDBs() {
        let status = SetupCommand.setupStatus(
            searchDBExists: true,
            samplesDBExists: true,
            installedVersion: "0.9.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .current(version: "0.9.0"))
    }

    @Test("DBs present + different version = .stale")
    func staleDBs() {
        let status = SetupCommand.setupStatus(
            searchDBExists: true,
            samplesDBExists: true,
            installedVersion: "0.8.0",
            currentVersion: "0.9.0"
        )
        #expect(status == .stale(installed: "0.8.0", current: "0.9.0"))
    }
}

// MARK: - Version file read/write

@Suite("SetupCommand version file helpers")
struct SetupVersionFileTests {

    private static func tempBaseDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cupertino-setup-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Read returns nil when the version file is absent")
    func readMissingReturnsNil() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SetupCommand.readInstalledVersion(in: dir) == nil)
    }

    @Test("Write then read round-trips the version string")
    func writeThenRead() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try SetupCommand.writeInstalledVersion("0.9.0", in: dir)
        #expect(SetupCommand.readInstalledVersion(in: dir) == "0.9.0")
    }

    @Test("Read trims surrounding whitespace and newlines")
    func readTrimsWhitespace() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Shared.Constants.FileName.setupVersionFile)
        try "  0.9.0  \n".write(to: url, atomically: true, encoding: .utf8)
        #expect(SetupCommand.readInstalledVersion(in: dir) == "0.9.0")
    }

    @Test("Read returns nil for an empty/whitespace-only file")
    func readEmptyFileReturnsNil() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(Shared.Constants.FileName.setupVersionFile)
        try "   \n\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(SetupCommand.readInstalledVersion(in: dir) == nil)
    }

    @Test("Write overwrites the existing version")
    func writeOverwrites() throws {
        let dir = try Self.tempBaseDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try SetupCommand.writeInstalledVersion("0.8.0", in: dir)
        try SetupCommand.writeInstalledVersion("0.9.0", in: dir)
        #expect(SetupCommand.readInstalledVersion(in: dir) == "0.9.0")
    }
}
