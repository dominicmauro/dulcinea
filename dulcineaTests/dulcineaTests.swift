import Testing
@testable import dulcinea

// Main test suite entry point.
// Individual test files:
// - BookTests.swift: Book model tests (progress, sync status)
// - OPDSTests.swift: OPDS feed and catalog model tests
// - EPUBParserTests.swift: XML parser delegate tests (NAV, NCX, OPF)
// - SyncTests.swift: Sync models and error handling tests
// - ReaderTests.swift: Reader models (chapters, TOC, bookmarks, settings)
// - HTMLProcessingTests.swift: HTML tag stripping and entity decoding
// - ViewModelTests.swift: Business logic tests (sorting, filtering, matching)

struct DulcineaTests {

    @Test func appCanImportModels() async throws {
        // Verify basic module import works
        let book = Book(
            title: "Test",
            author: "Author",
            identifier: "id",
            filePath: "/test.epub",
            fileSize: 1000
        )
        #expect(book.title == "Test")
    }
}
