import Foundation
import Combine
import AVFoundation

@MainActor
class ReaderViewModel: ObservableObject {
    @Published var currentBook: Book?
    @Published var currentChapter: Int = 0
    @Published var currentPosition: Double = 0.0
    @Published var chapters: [EPUBChapter] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Reading settings
    @Published var fontSize: Double = 16
    @Published var fontFamily: FontFamily = .systemDefault
    @Published var backgroundColor: BackgroundColor = .white
    @Published var textColor: TextColor = .black
    @Published var lineSpacing: Double = 1.2
    @Published var margin: Double = 20

    // Reading state
    @Published var isMenuVisible = false
    @Published var isSettingsVisible = false
    @Published var readingProgress: Double = 0.0

    // Text-to-speech state
    @Published var isSpeaking = false
    @Published var speechRate: Float = 0.5

    // Bookmarks
    @Published var bookmarks: [Bookmark] = []
    @Published var isBookmarksVisible = false

    // Pagination state
    @Published var currentPage: Int = 0
    @Published var totalPagesInChapter: Int = 1
    @Published var paginatedPages: [PageContent] = []
    
    private let paginator = TextPaginator()
    private var pageSize: CGSize = .zero
    
    private let epubService: EPUBService
    private let syncService: KOSyncService
    private let storageService: StorageService
    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: Timer?
    private var readingStartTime: Date?
    private var progressSaveTask: Task<Void, Error>?

    // Text-to-speech
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechDelegate: SpeechDelegate?

    init(epubService: EPUBService, syncService: KOSyncService, storageService: StorageService) {
        self.epubService = epubService
        self.syncService = syncService
        self.storageService = storageService


        speechDelegate = SpeechDelegate { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = false
            }
        }
        speechSynthesizer.delegate = speechDelegate

        loadReadingSettings()
        setupProgressTracking()
        setupSettingsObservers()
    }

    deinit {
        // Clean up timers and speech to prevent memory leaks
        progressTimer?.invalidate()
        progressTimer = nil
        progressSaveTask?.cancel()
        progressSaveTask = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
    }
    
    // MARK: - Book Loading
    
    func loadBook(_ book: Book) async {
        isLoading = true
        errorMessage = nil
        currentBook = book

        do {
            let resolvedPath = storageService.resolveFilePath(book.filePath)
            let bookContent = try await epubService.loadEPUB(from: resolvedPath)
            chapters = bookContent.chapters
            currentChapter = book.currentChapter
            currentPosition = book.currentPosition
            
            // Paginate if page size is already known (e.g. re-loading)
            if pageSize.width > 0 && pageSize.height > 0 {
                repaginate()
                restorePageFromPosition()
            }
            updateReadingProgress()

            // Load bookmarks for this book
            loadBookmarks()

            // Mark book as opened
            var openedBook = book
            openedBook.markAsOpened()
            await updateBookProgress(openedBook)

            startReadingSession()

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
    
    func closeBook() {
        endReadingSession()
        
        // Save final progress
        if let book = currentBook {
            Task {
                await saveCurrentProgress(book)
            }
        }
        
        currentBook = nil
        chapters = []
        currentChapter = 0
        currentPosition = 0.0
        currentPage = 0
        totalPagesInChapter = 1
        paginatedPages = []
        readingProgress = 0.0
    }
    
    // MARK: - Navigation
    
    func goToNextPage() {
        if currentPage < totalPagesInChapter - 1 {
            currentPage += 1
            updateReadingProgress()
            saveProgress()
        } else {
            // Last page of chapter -> advance to next chapter
            guard currentChapter < chapters.count - 1 else { return }
            currentChapter += 1
            currentPage = 0
            repaginate()
            saveProgress()
        }
    }
    
    func goToPreviousPage() {
        if currentPage > 0 {
            currentPage -= 1
            updateReadingProgress()
            saveProgress()
        } else {
            // First page of chapter -> go to previous chapter's last page
            guard currentChapter > 0 else { return }
            currentChapter -= 1
            repaginate()
            currentPage = max(0, totalPagesInChapter - 1)
            updateReadingProgress()
            saveProgress()
        }
    }
    
    func goToNextChapter() {
        guard currentChapter < chapters.count - 1 else { return }
        currentChapter += 1
        currentPage = 0
        currentPosition = 0.0
        repaginate()
        saveProgress()
    }
    
    func goToPreviousChapter() {
        guard currentChapter > 0 else { return }
        currentChapter -= 1
        currentPage = 0
        currentPosition = 0.0
        repaginate()
        saveProgress()
    }
    
    func goToChapter(_ chapterIndex: Int) {
        guard chapterIndex >= 0 && chapterIndex < chapters.count else { return }
        currentChapter = chapterIndex
        currentPage = 0
        currentPosition = 0.0
        repaginate()
        saveProgress()
    }
    
    // MARK: - Pagination
    
    func updatePageSize(_ size: CGSize) {
        let effectiveWidth = size.width - (margin * 2)
        let effectiveHeight = size.height - 80 // 40pt top + 40pt bottom padding
        let newSize = CGSize(width: effectiveWidth, height: effectiveHeight)
        
        guard newSize != pageSize, newSize.width > 0, newSize.height > 0 else { return }
        pageSize = newSize
        repaginate()
        
        // Restore page position when first receiving page size after book load
        if currentPosition > 0 && currentPage == 0 && totalPagesInChapter > 1 {
            restorePageFromPosition()
        }
    }
    
    func repaginate() {
        guard !chapters.isEmpty,
              currentChapter < chapters.count,
              pageSize.width > 0, pageSize.height > 0 else { return }
        
        let chapter = chapters[currentChapter]
        let size = pageSize
        let fs = fontSize
        let ff = fontFamily
        let ls = lineSpacing
        let ci = currentChapter
        
        let result = paginator.paginate(
            text: chapter.content,
            title: chapter.title,
            pageSize: size,
            fontSize: fs,
            fontFamily: ff,
            lineSpacing: ls,
            chapterIndex: ci
        )
        
        paginatedPages = result.pages
        totalPagesInChapter = result.pages.count
        
        if currentPage >= totalPagesInChapter {
            currentPage = max(0, totalPagesInChapter - 1)
        }
        
        updateReadingProgress()
    }
    
    private func restorePageFromPosition() {
        guard totalPagesInChapter > 1 else {
            currentPage = 0
            return
        }
        currentPage = Int(round(currentPosition * Double(totalPagesInChapter - 1)))
        currentPage = max(0, min(currentPage, totalPagesInChapter - 1))
    }
    
    private func updateReadingProgress() {
        guard !chapters.isEmpty else {
            readingProgress = 0.0
            return
        }
        
        // Derive position within chapter from page index
        if totalPagesInChapter > 1 {
            currentPosition = Double(currentPage) / Double(totalPagesInChapter - 1)
        } else {
            currentPosition = 0.0
        }
        
        let chapterProgress = Double(currentChapter) / Double(chapters.count)
        let positionProgress = currentPosition / Double(chapters.count)
        readingProgress = chapterProgress + positionProgress
    }
    
    private func setupSettingsObservers() {
        Publishers.CombineLatest4($fontSize, $fontFamily, $lineSpacing, $margin)
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.repaginate()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Progress Management
    
    private func saveProgress() {
        guard let book = currentBook else { return }
        
        Task {
            await saveCurrentProgress(book)
        }
    }
    
    private func saveCurrentProgress(_ book: Book) async {
        var updatedBook = book
        updatedBook.updateProgress(chapter: currentChapter, position: currentPosition)
        updatedBook.totalChapters = chapters.count
        
        await updateBookProgress(updatedBook)
        
        // Sync with KOSync if configured
        if syncService.isConfigured {
            do {
                try await syncService.uploadProgress(for: updatedBook)
                updatedBook.markAsSynced()
                await updateBookProgress(updatedBook)
            } catch {
                print("Failed to sync progress: \(error)")
            }
        }
    }
    
    private func updateBookProgress(_ book: Book) async {
        // Persist directly to storage. StorageService publishes `books`, so
        // LibraryViewModel picks up the change automatically.
        storageService.updateBook(book)
    }
    
    // MARK: - Reading Session Tracking
    
    private func setupProgressTracking() {
        // Auto-save progress every 30 seconds during active reading
        progressTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveProgress()
            }
        }
    }
    
    private func startReadingSession() {
        readingStartTime = Date()
    }
    
    private func endReadingSession() {
        progressTimer?.invalidate()
        progressTimer = nil
        readingStartTime = nil
    }
    
    // MARK: - Reading Settings
    
    private func loadReadingSettings() {
        let defaults = UserDefaults.standard
        fontSize = defaults.double(forKey: "reading_font_size") != 0 ? defaults.double(forKey: "reading_font_size") : 16
        fontFamily = FontFamily(rawValue: defaults.string(forKey: "reading_font_family") ?? "") ?? .systemDefault
        backgroundColor = BackgroundColor(rawValue: defaults.string(forKey: "reading_background") ?? "") ?? .white
        textColor = TextColor(rawValue: defaults.string(forKey: "reading_text_color") ?? "") ?? .black
        lineSpacing = defaults.double(forKey: "reading_line_spacing") != 0 ? defaults.double(forKey: "reading_line_spacing") : 1.2
        margin = defaults.double(forKey: "reading_margin") != 0 ? defaults.double(forKey: "reading_margin") : 20
    }
    
    func saveReadingSettings() {
        let defaults = UserDefaults.standard
        defaults.set(fontSize, forKey: "reading_font_size")
        defaults.set(fontFamily.rawValue, forKey: "reading_font_family")
        defaults.set(backgroundColor.rawValue, forKey: "reading_background")
        defaults.set(textColor.rawValue, forKey: "reading_text_color")
        defaults.set(lineSpacing, forKey: "reading_line_spacing")
        defaults.set(margin, forKey: "reading_margin")
    }
    
    func resetSettings() {
        fontSize = 16
        fontFamily = .systemDefault
        backgroundColor = .white
        textColor = .black
        lineSpacing = 1.2
        margin = 20
        saveReadingSettings()
    }
    
    // MARK: - UI State Management
    
    func toggleMenu() {
        isMenuVisible.toggle()
    }
    
    func hideMenu() {
        isMenuVisible = false
    }
    
    func showSettings() {
        isSettingsVisible = true
    }
    
    func hideSettings() {
        isSettingsVisible = false
    }
    
    // MARK: - Text-to-Speech

    func toggleSpeech() {
        if isSpeaking {
            stopSpeaking()
        } else {
            startSpeaking()
        }
    }

    func startSpeaking() {
        guard !chapters.isEmpty, currentChapter < chapters.count else { return }

        let chapter = chapters[currentChapter]
        let utterance = AVSpeechUtterance(string: chapter.content)
        utterance.rate = speechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        speechSynthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func setSpeechRate(_ rate: Float) {
        speechRate = max(0.0, min(1.0, rate))
        // If currently speaking, restart with new rate
        if isSpeaking {
            stopSpeaking()
            startSpeaking()
        }
    }

    // MARK: - Bookmarks

    func addBookmark(note: String? = nil) {
        guard let book = currentBook else { return }

        let bookmark = Bookmark(
            bookId: book.id,
            chapterIndex: currentChapter,
            position: currentPosition,
            chapterTitle: chapters.isEmpty ? "Chapter \(currentChapter + 1)" : chapters[currentChapter].title,
            note: note
        )

        bookmarks.append(bookmark)
        saveBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func goToBookmark(_ bookmark: Bookmark) {
        goToChapter(bookmark.chapterIndex)
        currentPosition = bookmark.position
        updateReadingProgress()
        hideBookmarks()
    }

    func loadBookmarks() {
        guard let book = currentBook else {
            bookmarks = []
            return
        }

        let defaults = UserDefaults.standard
        let key = "bookmarks_\(book.id.uuidString)"

        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        } else {
            bookmarks = []
        }
    }

    private func saveBookmarks() {
        guard let book = currentBook else { return }

        let defaults = UserDefaults.standard
        let key = "bookmarks_\(book.id.uuidString)"

        if let encoded = try? JSONEncoder().encode(bookmarks) {
            defaults.set(encoded, forKey: key)
        }
    }

    func showBookmarks() {
        isBookmarksVisible = true
    }

    func hideBookmarks() {
        isBookmarksVisible = false
    }

    func hasBookmarkAtCurrentPosition() -> Bool {
        bookmarks.contains { $0.chapterIndex == currentChapter && abs($0.position - currentPosition) < 0.01 }
    }

    // MARK: - Share

    func getShareContent() -> String? {
        guard let book = currentBook, !chapters.isEmpty, currentChapter < chapters.count else {
            return nil
        }

        let chapter = chapters[currentChapter]
        let excerpt = String(chapter.content.prefix(500))

        return """
        📖 \(book.title) by \(book.author)

        Chapter: \(chapter.title)

        "\(excerpt)..."

        Shared from Dulcinea
        """
    }

    func getShareItems() -> [Any] {
        var items: [Any] = []

        if let shareContent = getShareContent() {
            items.append(shareContent)
        }

        return items
    }
}

// MARK: - Speech Delegate

private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}

// MARK: - Bookmark Model

struct Bookmark: Identifiable, Codable {
    let id: UUID
    let bookId: UUID
    let chapterIndex: Int
    let position: Double
    let chapterTitle: String
    let note: String?
    let dateCreated: Date

    init(bookId: UUID, chapterIndex: Int, position: Double, chapterTitle: String, note: String? = nil, dateCreated: Date = Date()) {
        self.id = UUID()
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.position = position
        self.chapterTitle = chapterTitle
        self.note = note
        self.dateCreated = dateCreated
    }
}

// MARK: - Reading Settings Models

enum FontFamily: String, CaseIterable {
    case systemDefault = "system"
    case serif = "Times New Roman"
    case sansSerif = "Helvetica"
    case monospace = "Courier"
    case dyslexic = "OpenDyslexic"
    case georgia = "Georgia"
    case palatino = "Palatino"

    var displayName: String {
        switch self {
        case .systemDefault: return "System"
        case .serif: return "Serif"
        case .sansSerif: return "Sans Serif"
        case .monospace: return "Monospace"
        case .dyslexic: return "Dyslexic Friendly"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        }
    }

    var fontName: String {
        switch self {
        case .systemDefault: return "system"
        case .serif: return "Times-Roman"
        case .sansSerif: return "Helvetica"
        case .monospace: return "Courier"
        case .dyslexic: return "OpenDyslexic-Regular"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        }
    }
}

enum BackgroundColor: String, CaseIterable {
    case white = "white"
    case sepia = "sepia"
    case dark = "dark"
    case black = "black"
    
    var displayName: String {
        switch self {
        case .white: return "White"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        case .black: return "Black"
        }
    }
    
    var color: (background: String, text: String) {
        switch self {
        case .white: return ("#FFFFFF", "#000000")
        case .sepia: return ("#F7F3E9", "#5C4B3A")
        case .dark: return ("#2C2C2E", "#FFFFFF")
        case .black: return ("#000000", "#FFFFFF")
        }
    }
}

enum TextColor: String, CaseIterable {
    case black = "black"
    case darkGray = "darkGray"
    case white = "white"
    case sepia = "sepia"
    
    var displayName: String {
        switch self {
        case .black: return "Black"
        case .darkGray: return "Dark Gray"
        case .white: return "White"
        case .sepia: return "Sepia"
        }
    }
}

// MARK: - EPUB Models

struct EPUBChapter: Identifiable {
    let id = UUID()
    let title: String
    let content: String
    let htmlContent: String
    let order: Int
    
    var wordCount: Int {
        content.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }
}

struct EPUBMetadata {
    let title: String
    let author: String
    let identifier: String
    let language: String
    let publisher: String?
    let publishDate: Date?
    let description: String?
    let coverImagePath: String?
}

struct EPUBContent {
    let metadata: EPUBMetadata
    let chapters: [EPUBChapter]
    let tableOfContents: [TOCEntry]
}

struct TOCEntry: Identifiable {
    let id = UUID()
    let title: String
    let chapterIndex: Int
    let level: Int
    let children: [TOCEntry]
}

// MARK: - Notifications

extension Notification.Name {
    static let bookProgressUpdated = Notification.Name("bookProgressUpdated")
}
