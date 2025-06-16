import Foundation
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var isLoading = false
    @Published var syncStatus: SyncStatus = .notConfigured
    @Published var errorMessage: String?
    
    private let storageService: StorageService
    private let syncService: KOSyncService
    private var cancellables = Set<AnyCancellable>()
    
    init(storageService: StorageService, syncService: KOSyncService) {
        self.storageService = storageService
        self.syncService = syncService
        
        setupBindings()
        loadBooks()
    }
    
    private func setupBindings() {
        // Listen to storage service for book updates
        storageService.$books
            .receive(on: DispatchQueue.main)
            .assign(to: \.books, on: self)
            .store(in: &cancellables)
        
        // Listen to sync service status
        syncService.$status
            .receive(on: DispatchQueue.main)
            .assign(to: \.syncStatus, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func loadBooks() {
        books = storageService.books
    }
    
    func addBook(_ book: Book) {
        storageService.addBook(book)
    }
    
    func removeBook(_ book: Book) {
        storageService.removeBook(book)
    }
    
    func updateBookProgress(_ book: Book, chapter: Int, position: Double) {
        var updatedBook = book
        updatedBook.updateProgress(chapter: chapter, position: position)
        storageService.updateBook(updatedBook)
        
        // Trigger sync if configured
        Task {
            await syncBookProgress(updatedBook)
        }
    }
    
    func syncProgress() async {
        guard syncService.isConfigured else {
            syncStatus = .notConfigured
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Sync all books that need syncing
            let booksToSync = books.filter { $0.needsSync }
            
            for book in booksToSync {
                try await syncService.uploadProgress(for: book)
                
                // Mark as synced
                var syncedBook = book
                syncedBook.markAsSynced()
                storageService.updateBook(syncedBook)
            }
            
            // Download any updated progress from server
            try await downloadUpdatedProgress()
            
            syncStatus = .lastSynced(Date())
            
        } catch {
            errorMessage = error.localizedDescription
            syncStatus = .error(error as? SyncError ?? .networkError(error))
        }
        
        isLoading = false
    }
    
    private func syncBookProgress(_ book: Book) async {
        guard syncService.isConfigured else { return }
        
        do {
            try await syncService.uploadProgress(for: book)
            
            var syncedBook = book
            syncedBook.markAsSynced()
            storageService.updateBook(syncedBook)
            
        } catch {
            // Silent fail for individual book sync - user can manually sync later
            print("Failed to sync progress for \(book.title): \(error)")
        }
    }
    
    private func downloadUpdatedProgress() async throws {
        for book in books {
            if let serverProgress = try await syncService.downloadProgress(for: book) {
                // Only update if server has newer progress
                if let lastSync = book.lastSyncDate,
                   serverProgress.timestamp > lastSync {
                    
                    var updatedBook = book
                    
                    // Parse progress detail from server
                    if let progressData = serverProgress.progress.data(using: .utf8),
                       let detail = try? JSONDecoder().decode(SyncProgressDetail.self, from: progressData) {
                        updatedBook.updateProgress(chapter: detail.chapter, position: detail.position)
                        updatedBook.markAsSynced()
                        storageService.updateBook(updatedBook)
                    }
                }
            }
        }
    }
    
    // MARK: - Import Functions
    
    func importEPUBFiles(from urls: [URL]) async {
        isLoading = true
        errorMessage = nil
        
        for url in urls {
            do {
                try await importSingleEPUB(from: url)
            } catch {
                errorMessage = "Failed to import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    private func importSingleEPUB(from url: URL) async throws {
        // Start accessing security scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // Read file data
        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent
        
        // Save to local storage
        let localURL = try storageService.saveEPUBFile(data, filename: filename)
        
        // Extract metadata (this would be handled by EPUBService in real implementation)
        let book = Book(
            title: extractTitle(from: filename),
            author: "Unknown Author", // Would be extracted from EPUB metadata
            identifier: UUID().uuidString,
            filePath: localURL.path,
            fileSize: Int64(data.count)
        )
        
        storageService.addBook(book)
    }
    
    private func extractTitle(from filename: String) -> String {
        // Simple title extraction from filename
        let nameWithoutExtension = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        return nameWithoutExtension.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
    
    // MARK: - Sorting and Filtering
    
    enum SortOption: CaseIterable {
        case title, author, dateAdded, lastOpened, progress
        
        var displayName: String {
            switch self {
            case .title: return "Title"
            case .author: return "Author"
            case .dateAdded: return "Date Added"
            case .lastOpened: return "Last Opened"
            case .progress: return "Progress"
            }
        }
    }
    
    func sortedBooks(by option: SortOption, ascending: Bool = true) -> [Book] {
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
}

// MARK: - Import Error

enum ImportError: Error, LocalizedError {
    case accessDenied
    case invalidFile
    case storageError
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Unable to access the selected file"
        case .invalidFile:
            return "The selected file is not a valid EPUB"
        case .storageError:
            return "Failed to save the file to storage"
        }
    }
}