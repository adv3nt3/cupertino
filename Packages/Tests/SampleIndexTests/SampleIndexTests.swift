import Foundation
import Testing

@testable import SampleIndex

@Suite("SampleIndex Tests")
struct SampleIndexTests {
    @Test("Project ID extraction from filename")
    func projectIdFromFilename() {
        // Test that the File model extracts path components correctly
        let file = SampleIndex.File(
            projectId: "test-project",
            path: "Sources/Views/ContentView.swift",
            content: "import SwiftUI"
        )

        #expect(file.filename == "ContentView.swift")
        #expect(file.folder == "Sources/Views")
        #expect(file.fileExtension == "swift")
        #expect(file.projectId == "test-project")
    }

    @Test("Indexable file extensions")
    func indexableExtensions() {
        // Swift files should be indexed
        #expect(SampleIndex.shouldIndex(path: "main.swift"))
        #expect(SampleIndex.shouldIndex(path: "ViewController.m"))
        #expect(SampleIndex.shouldIndex(path: "Header.h"))

        // Binary files should not be indexed
        #expect(!SampleIndex.shouldIndex(path: "image.png"))
        #expect(!SampleIndex.shouldIndex(path: "model.usdz"))
        #expect(!SampleIndex.shouldIndex(path: "binary.dat"))
    }

    @Test("Project model creation")
    func projectModel() {
        let project = SampleIndex.Project(
            id: "sample-app",
            title: "Sample App",
            description: "A sample application",
            frameworks: ["SwiftUI", "Combine"],
            readme: "# Sample App\n\nA demo.",
            webURL: "https://developer.apple.com/sample",
            zipFilename: "sample-app.zip",
            fileCount: 10,
            totalSize: 5000
        )

        #expect(project.id == "sample-app")
        #expect(project.frameworks == ["swiftui", "combine"]) // lowercased
        #expect(project.fileCount == 10)
    }
}

// MARK: - SampleIndexDatabase SQL Injection Tests

@Suite("SampleIndexDatabase SQL safety")
struct SampleIndexDatabaseSQLSafetyTests {
    @Test("getFile with SQL injection metacharacters in path returns nil without throwing")
    func getFileWithSQLInjectionPath() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("sampleindex-sqlinject-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let database = try await SampleIndex.Database(dbPath: tempDB)

        // Parameterized binding means the injection payload is treated as a literal string;
        // the call must return nil (no matching row) rather than throw or modify the schema.
        let result = try await database.getFile(
            projectId: "test",
            path: "'; DROP TABLE files;--"
        )
        await database.disconnect()
        #expect(result == nil)
    }
}
