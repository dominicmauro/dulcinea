import Testing
@testable import dulcinea

struct BookTests {

    // MARK: - Progress Percentage Tests

    @Test func progressPercentage_atStart_isZero() {
        let book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000,
            currentChapter: 0,
            currentPosition: 0.0,
            totalChapters: 10
        )

        #expect(book.progressPercentage == 0.0)
    }

    @Test func progressPercentage_midwayThroughBook() {
        let book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000,
            currentChapter: 5,
            currentPosition: 0.5,
            totalChapters: 10
        )

        // Chapter 5/10 = 0.5, position 0.5/10 = 0.05, total = 0.55
        #expect(book.progressPercentage == 0.55)
    }

    @Test func progressPercentage_atEnd() {
        let book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000,
            currentChapter: 9,
            currentPosition: 1.0,
            totalChapters: 10
        )

        // Chapter 9/10 = 0.9, position 1.0/10 = 0.1, total = 1.0
        #expect(book.progressPercentage == 1.0)
    }

    @Test func progressPercentage_withZeroChapters_returnsZero() {
        let book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000,
            currentChapter: 0,
            currentPosition: 0.5,
            totalChapters: 0
        )

        #expect(book.progressPercentage == 0.0)
    }

    // MARK: - Update Progress Tests

    @Test func updateProgress_setsChapterAndPosition() {
        var book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000,
            totalChapters: 10
        )

        book.updateProgress(chapter: 3, position: 0.7)

        #expect(book.currentChapter == 3)
        #expect(book.currentPosition == 0.7)
        #expect(book.needsSync == true)
    }

    @Test func updateProgress_marksAsFinished_whenNearEnd() {
        var book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000,
            totalChapters: 10
        )

        // Last chapter (index 9) with position >= 0.95
        book.updateProgress(chapter: 9, position: 0.96)

        #expect(book.isFinished == true)
    }

    @Test func updateProgress_doesNotMarkFinished_whenNotAtEnd() {
        var book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000,
            totalChapters: 10
        )

        book.updateProgress(chapter: 8, position: 0.99)

        #expect(book.isFinished == false)
    }

    // MARK: - Sync Status Tests

    @Test func markAsOpened_setsLastOpened() {
        var book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000
        )

        #expect(book.lastOpened == nil)

        book.markAsOpened()

        #expect(book.lastOpened != nil)
    }

    @Test func markAsSynced_clearsSyncFlag() {
        var book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1000
        )

        book.updateProgress(chapter: 1, position: 0.5) // Sets needsSync = true
        #expect(book.needsSync == true)

        book.markAsSynced()

        #expect(book.needsSync == false)
        #expect(book.lastSyncDate != nil)
    }

    // MARK: - File Size Formatting

    @Test func formattedFileSize_formatsBytes() {
        let book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 1024
        )

        #expect(book.formattedFileSize == "1 KB")
    }

    @Test func formattedFileSize_formatsMegabytes() {
        let book = Book(
            title: "Test Book",
            author: "Author",
            identifier: "123",
            filePath: "/test.epub",
            fileSize: 2_500_000
        )

        // Should be around 2.4 MB
        #expect(book.formattedFileSize.contains("MB"))
    }
}
