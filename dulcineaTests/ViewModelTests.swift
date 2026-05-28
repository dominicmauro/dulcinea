import Testing
import Foundation
@testable import dulcinea

struct ViewModelTests {

    // MARK: - LibraryViewModel Sorting Tests

    @Test func sortBooks_byTitle_ascending() {
        let books = createTestBooks()
        let sorted = sortBooks(books, by: .title, ascending: true)

        #expect(sorted[0].title == "Alpha Book")
        #expect(sorted[1].title == "Beta Book")
        #expect(sorted[2].title == "Gamma Book")
    }

    @Test func sortBooks_byTitle_descending() {
        let books = createTestBooks()
        let sorted = sortBooks(books, by: .title, ascending: false)

        #expect(sorted[0].title == "Gamma Book")
        #expect(sorted[1].title == "Beta Book")
        #expect(sorted[2].title == "Alpha Book")
    }

    @Test func sortBooks_byAuthor() {
        let books = createTestBooks()
        let sorted = sortBooks(books, by: .author, ascending: true)

        #expect(sorted[0].author == "Alice")
        #expect(sorted[1].author == "Bob")
        #expect(sorted[2].author == "Charlie")
    }

    @Test func sortBooks_byProgress() {
        var books = createTestBooks()
        books[0].updateProgress(chapter: 5, position: 0.5) // ~55%
        books[1].updateProgress(chapter: 2, position: 0.0) // ~20%
        books[2].updateProgress(chapter: 8, position: 0.9) // ~89%

        let sorted = sortBooks(books, by: .progress, ascending: true)

        #expect(sorted[0].title == "Beta Book") // Lowest progress
        #expect(sorted[2].title == "Gamma Book") // Highest progress
    }

    @Test func sortBooks_caseInsensitive() {
        let books = [
            Book(title: "zebra", author: "a", identifier: "1", filePath: "/1", fileSize: 100),
            Book(title: "ALPHA", author: "b", identifier: "2", filePath: "/2", fileSize: 100),
            Book(title: "Beta", author: "c", identifier: "3", filePath: "/3", fileSize: 100)
        ]

        let sorted = sortBooks(books, by: .title, ascending: true)

        #expect(sorted[0].title == "ALPHA")
        #expect(sorted[1].title == "Beta")
        #expect(sorted[2].title == "zebra")
    }

    // MARK: - BrowseViewModel Filtering Tests

    @Test func filterEntries_bySearchText() {
        let entries = createTestEntries()
        let filtered = filterEntries(entries, searchText: "swift")

        #expect(filtered.count == 1)
        #expect(filtered[0].title == "Swift Programming")
    }

    @Test func filterEntries_caseInsensitive() {
        let entries = createTestEntries()
        let filtered = filterEntries(entries, searchText: "PYTHON")

        #expect(filtered.count == 1)
        #expect(filtered[0].title == "Python Basics")
    }

    @Test func filterEntries_emptySearch_returnsAll() {
        let entries = createTestEntries()
        let filtered = filterEntries(entries, searchText: "")

        #expect(filtered.count == entries.count)
    }

    @Test func filterEntries_byAuthor() {
        let entries = createTestEntries()
        let filtered = filterEntries(entries, searchText: "Smith")

        #expect(filtered.count == 1)
        #expect(filtered[0].title == "Swift Programming")
    }

    @Test func filterEntries_noMatch() {
        let entries = createTestEntries()
        let filtered = filterEntries(entries, searchText: "nonexistent")

        #expect(filtered.isEmpty)
    }

    // MARK: - Bookmark Position Matching

    @Test func bookmarkMatching_exactMatch() {
        let hasMatch = hasBookmarkAtPosition(
            bookmarks: createTestBookmarks(),
            chapterIndex: 2,
            position: 0.5
        )

        #expect(hasMatch == true)
    }

    @Test func bookmarkMatching_withinEpsilon() {
        let hasMatch = hasBookmarkAtPosition(
            bookmarks: createTestBookmarks(),
            chapterIndex: 2,
            position: 0.505 // Within 0.01 of 0.5
        )

        #expect(hasMatch == true)
    }

    @Test func bookmarkMatching_outsideEpsilon() {
        let hasMatch = hasBookmarkAtPosition(
            bookmarks: createTestBookmarks(),
            chapterIndex: 2,
            position: 0.52 // Outside 0.01 of 0.5
        )

        #expect(hasMatch == false)
    }

    @Test func bookmarkMatching_wrongChapter() {
        let hasMatch = hasBookmarkAtPosition(
            bookmarks: createTestBookmarks(),
            chapterIndex: 3, // Different chapter
            position: 0.5
        )

        #expect(hasMatch == false)
    }

    @Test func bookmarkMatching_emptyBookmarks() {
        let hasMatch = hasBookmarkAtPosition(
            bookmarks: [],
            chapterIndex: 0,
            position: 0.0
        )

        #expect(hasMatch == false)
    }

    // MARK: - Helper Functions

    private func createTestBooks() -> [Book] {
        return [
            Book(title: "Gamma Book", author: "Charlie", identifier: "3", filePath: "/3", fileSize: 300, totalChapters: 10),
            Book(title: "Alpha Book", author: "Alice", identifier: "1", filePath: "/1", fileSize: 100, totalChapters: 10),
            Book(title: "Beta Book", author: "Bob", identifier: "2", filePath: "/2", fileSize: 200, totalChapters: 10)
        ]
    }

    private func createTestEntries() -> [OPDSEntry] {
        return [
            OPDSEntry(
                id: "1",
                title: "Swift Programming",
                summary: "Learn iOS development",
                authors: [OPDSAuthor(name: "John Smith", uri: nil)],
                published: nil,
                updated: Date(),
                links: [],
                categories: nil
            ),
            OPDSEntry(
                id: "2",
                title: "Python Basics",
                summary: "Introduction to Python",
                authors: [OPDSAuthor(name: "Jane Doe", uri: nil)],
                published: nil,
                updated: Date(),
                links: [],
                categories: nil
            ),
            OPDSEntry(
                id: "3",
                title: "Data Science",
                summary: "Machine learning fundamentals",
                authors: [OPDSAuthor(name: "Bob Wilson", uri: nil)],
                published: nil,
                updated: Date(),
                links: [],
                categories: nil
            )
        ]
    }

    private func createTestBookmarks() -> [Bookmark] {
        let bookId = UUID()
        return [
            Bookmark(bookId: bookId, chapterIndex: 0, position: 0.0, chapterTitle: "Intro", note: nil, dateCreated: Date()),
            Bookmark(bookId: bookId, chapterIndex: 2, position: 0.5, chapterTitle: "Chapter 2", note: "Important", dateCreated: Date()),
            Bookmark(bookId: bookId, chapterIndex: 5, position: 0.8, chapterTitle: "Chapter 5", note: nil, dateCreated: Date())
        ]
    }

    // Sorting logic matching LibraryViewModel
    private enum SortOption {
        case title, author, dateAdded, lastOpened, progress
    }

    private func sortBooks(_ books: [Book], by option: SortOption, ascending: Bool) -> [Book] {
        let sorted = books.sorted { lhs, rhs in
            let result: Bool
            switch option {
            case .title:
                result = lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .author:
                result = lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending
            case .dateAdded:
                result = lhs.dateAdded < rhs.dateAdded
            case .lastOpened:
                let lhsDate = lhs.lastOpened ?? Date.distantPast
                let rhsDate = rhs.lastOpened ?? Date.distantPast
                result = lhsDate < rhsDate
            case .progress:
                result = lhs.progressPercentage < rhs.progressPercentage
            }
            return ascending ? result : !result
        }
        return sorted
    }

    // Filtering logic matching BrowseViewModel
    private func filterEntries(_ entries: [OPDSEntry], searchText: String) -> [OPDSEntry] {
        guard !searchText.isEmpty else { return entries }

        return entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(searchText) ||
            entry.authorNames.localizedCaseInsensitiveContains(searchText) ||
            (entry.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // Bookmark matching logic from ReaderViewModel
    private func hasBookmarkAtPosition(bookmarks: [Bookmark], chapterIndex: Int, position: Double) -> Bool {
        bookmarks.contains { $0.chapterIndex == chapterIndex && abs($0.position - position) < 0.01 }
    }
}
