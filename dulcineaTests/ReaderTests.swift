import Testing
import Foundation
@testable import dulcinea

struct ReaderTests {

    // MARK: - EPUBChapter Tests

    @Test func epubChapter_wordCount_countsWords() {
        let chapter = EPUBChapter(
            title: "Test Chapter",
            content: "This is a simple test with seven words.",
            htmlContent: "<p>This is a simple test with seven words.</p>",
            order: 0
        )

        #expect(chapter.wordCount == 8)
    }

    @Test func epubChapter_wordCount_handlesMultipleSpaces() {
        let chapter = EPUBChapter(
            title: "Test",
            content: "Word   with    multiple     spaces",
            htmlContent: "",
            order: 0
        )

        #expect(chapter.wordCount == 4)
    }

    @Test func epubChapter_wordCount_handlesNewlines() {
        let chapter = EPUBChapter(
            title: "Test",
            content: "Line one\nLine two\nLine three",
            htmlContent: "",
            order: 0
        )

        #expect(chapter.wordCount == 6)
    }

    @Test func epubChapter_wordCount_emptyContent() {
        let chapter = EPUBChapter(
            title: "Empty",
            content: "",
            htmlContent: "",
            order: 0
        )

        #expect(chapter.wordCount == 0)
    }

    @Test func epubChapter_wordCount_whitespaceOnly() {
        let chapter = EPUBChapter(
            title: "Whitespace",
            content: "   \n\t  ",
            htmlContent: "",
            order: 0
        )

        #expect(chapter.wordCount == 0)
    }

    // MARK: - TOCEntry Tests

    @Test func tocEntry_hasUniqueId() {
        let entry1 = TOCEntry(title: "Chapter 1", chapterIndex: 0, level: 1, children: [])
        let entry2 = TOCEntry(title: "Chapter 1", chapterIndex: 0, level: 1, children: [])

        #expect(entry1.id != entry2.id)
    }

    @Test func tocEntry_storesChildren() {
        let child1 = TOCEntry(title: "Section 1.1", chapterIndex: 1, level: 2, children: [])
        let child2 = TOCEntry(title: "Section 1.2", chapterIndex: 2, level: 2, children: [])
        let parent = TOCEntry(title: "Chapter 1", chapterIndex: 0, level: 1, children: [child1, child2])

        #expect(parent.children.count == 2)
        #expect(parent.children[0].title == "Section 1.1")
        #expect(parent.children[1].title == "Section 1.2")
    }

    // MARK: - Bookmark Tests

    @Test func bookmark_hasUniqueId() {
        let bookmark1 = Bookmark(
            bookId: UUID(),
            chapterIndex: 0,
            position: 0.5,
            chapterTitle: "Chapter 1",
            note: nil,
            dateCreated: Date()
        )
        let bookmark2 = Bookmark(
            bookId: UUID(),
            chapterIndex: 0,
            position: 0.5,
            chapterTitle: "Chapter 1",
            note: nil,
            dateCreated: Date()
        )

        #expect(bookmark1.id != bookmark2.id)
    }

    @Test func bookmark_encodesAndDecodes() throws {
        let bookId = UUID()
        let date = Date()
        let original = Bookmark(
            bookId: bookId,
            chapterIndex: 3,
            position: 0.75,
            chapterTitle: "Chapter 3",
            note: "Important passage",
            dateCreated: date
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Bookmark.self, from: data)

        #expect(decoded.bookId == bookId)
        #expect(decoded.chapterIndex == 3)
        #expect(decoded.position == 0.75)
        #expect(decoded.chapterTitle == "Chapter 3")
        #expect(decoded.note == "Important passage")
    }

    @Test func bookmark_optionalNote() throws {
        let bookmark = Bookmark(
            bookId: UUID(),
            chapterIndex: 0,
            position: 0.0,
            chapterTitle: "Start",
            note: nil,
            dateCreated: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(bookmark)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Bookmark.self, from: data)

        #expect(decoded.note == nil)
    }

    // MARK: - Reading Settings Tests

    @Test func fontFamily_hasDisplayName() {
        #expect(FontFamily.systemDefault.displayName == "System")
        #expect(FontFamily.georgia.displayName == "Georgia")
        #expect(FontFamily.palatino.displayName == "Palatino")
    }

    @Test func fontFamily_hasFontName() {
        // System default may return empty or system font name
        #expect(FontFamily.georgia.fontName == "Georgia")
        #expect(FontFamily.palatino.fontName == "Palatino")
    }

    @Test func backgroundColor_hasColorPair() {
        let white = BackgroundColor.white
        #expect(white.color.background.isEmpty == false)
        #expect(white.color.text.isEmpty == false)

        let sepia = BackgroundColor.sepia
        #expect(sepia.color.background.isEmpty == false)
        #expect(sepia.color.text.isEmpty == false)
    }

    @Test func backgroundColor_hasDisplayName() {
        #expect(BackgroundColor.white.displayName == "White")
        #expect(BackgroundColor.sepia.displayName == "Sepia")
        #expect(BackgroundColor.dark.displayName == "Dark")
        #expect(BackgroundColor.black.displayName == "Black")
    }
}
