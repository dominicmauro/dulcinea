import Foundation
import Combine

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
    
    private let epubService: EPUBService
    private let syncService: KOSyncService
    private var cancellables = Set<AnyCancellable>()
    private var progressTimer: Timer?
    private var readingStartTime: Date?
    private var progressSaveTask: Task<Void, Error>?
    
    init(epubService: EPUBService, syncService: KOSyncService) {
        self.epubService = epubService
        self.syncService = syncService

        loadReadingSettings()
        setupProgressTracking()
    }

    deinit {
        // Clean up timers to prevent memory leaks
        progressTimer?.invalidate()
        progressTimer = nil
        progressSaveTask?.cancel()
        progressSaveTask = nil
    }
    
    // MARK: - Book Loading
    
    func loadBook(_ book: Book) async {
        isLoading = true
        errorMessage = nil
        currentBook = book
        
        do {
            let bookContent = try await epubService.loadEPUB(from: book.filePath)
            chapters = bookContent.chapters
            currentChapter = book.currentChapter
            currentPosition = book.currentPosition
            updateReadingProgress()
            
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
        readingProgress = 0.0
    }
    
    // MARK: - Navigation
    
    func goToNextChapter() {
        guard currentChapter < chapters.count - 1 else { return }
        
        currentChapter += 1
        currentPosition = 0.0
        updateReadingProgress()
        saveProgress()
    }
    
    func goToPreviousChapter() {
        guard currentChapter > 0 else { return }
        
        currentChapter -= 1
        currentPosition = 0.0
        updateReadingProgress()
        saveProgress()
    }
    
    func goToChapter(_ chapterIndex: Int) {
        guard chapterIndex >= 0 && chapterIndex < chapters.count else { return }
        
        currentChapter = chapterIndex
        currentPosition = 0.0
        updateReadingProgress()
        saveProgress()
    }
    
    func updatePosition(_ position: Double) {
        currentPosition = max(0.0, min(1.0, position))
        updateReadingProgress()

        // Debounced progress saving
        progressSaveTask?.cancel()
        progressSaveTask = Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if !Task.isCancelled {
                saveProgress()
            }
        }
    }
    
    
    private func updateReadingProgress() {
        guard !chapters.isEmpty else {
            readingProgress = 0.0
            return
        }
        
        let chapterProgress = Double(currentChapter) / Double(chapters.count)
        let positionProgress = currentPosition / Double(chapters.count)
        readingProgress = chapterProgress + positionProgress
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
        // This would typically go through a storage service
        // For now, we'll emit this as a notification that can be caught by LibraryViewModel
        NotificationCenter.default.post(
            name: .bookProgressUpdated,
            object: nil,
            userInfo: ["book": book]
        )
    }
    
    // MARK: - Reading Session Tracking
    
    private func setupProgressTracking() {
        // Auto-save progress every 30 seconds during active reading
        progressTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.saveProgress()
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
    
    // MARK: - Text-to-Speech (Future Feature)
    
    @Published var isSpeaking = false
    @Published var speechRate: Float = 0.5
    
    func toggleSpeech() {
        // TODO: Implement text-to-speech
        isSpeaking.toggle()
    }
}

// MARK: - Reading Settings Models

enum FontFamily: String, CaseIterable {
    case systemDefault = "system"
    case serif = "Times New Roman"
    case sansSerif = "Helvetica"
    case monospace = "Courier"
    case dyslexic = "OpenDyslexic"
    
    var displayName: String {
        switch self {
        case .systemDefault: return "System Default"
        case .serif: return "Serif"
        case .sansSerif: return "Sans Serif"
        case .monospace: return "Monospace"
        case .dyslexic: return "Dyslexic Friendly"
        }
    }
    
    var fontName: String {
        switch self {
        case .systemDefault: return "system"
        case .serif: return "Times-Roman"
        case .sansSerif: return "Helvetica"
        case .monospace: return "Courier"
        case .dyslexic: return "OpenDyslexic-Regular"
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
