import Foundation
import Combine

class StorageService: ObservableObject {
    let documentsDirectory: URL
    private let booksDirectory: URL
    private let coversDirectory: URL
    private let userDefaults = UserDefaults.standard
    private let keychainService = KeychainService()

    // Published properties
    @Published var books: [Book] = []
    @Published var catalogs: [OPDSCatalog] = []

    // UserDefaults keys
    private enum Keys {
        static let books = "stored_books"
        static let catalogs = "opds_catalogs"
        static let syncSettings = "sync_settings"
    }
    
    init() {
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.booksDirectory = documentsDirectory.appendingPathComponent("Books")
        self.coversDirectory = documentsDirectory.appendingPathComponent("Covers")
        
        setupDirectories()
        loadStoredData()
    }
    
    // MARK: - Setup
    
    private func setupDirectories() {
        let directories = [booksDirectory, coversDirectory]
        
        for directory in directories {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
    
    private func loadStoredData() {
        loadBooks()
        loadCatalogs()
    }
    
    // MARK: - Path Resolution
    
    /// Converts an absolute path to a path relative to the documents directory.
    func relativePath(for absolutePath: String) -> String {
        let docsPath = documentsDirectory.path
        if absolutePath.hasPrefix(docsPath) {
            let relative = String(absolutePath.dropFirst(docsPath.count))
            // Remove leading slash if present
            if relative.hasPrefix("/") {
                return String(relative.dropFirst())
            }
            return relative
        }
        // Already a relative path
        return absolutePath
    }
    
    /// Resolves a stored path (relative or absolute) to a valid absolute path.
    func resolveFilePath(_ storedPath: String) -> String {
        // If it's already an absolute path that exists, use it
        if storedPath.hasPrefix("/") && FileManager.default.fileExists(atPath: storedPath) {
            return storedPath
        }
        
        // If it's an absolute path that doesn't exist, try extracting the relative portion
        if storedPath.hasPrefix("/") {
            // Try to find the "Books/" or "Covers/" component and rebuild from there
            for component in ["Books/", "Covers/"] {
                if let range = storedPath.range(of: component) {
                    let relativePart = String(storedPath[range.lowerBound...])
                    let resolved = documentsDirectory.appendingPathComponent(relativePart).path
                    if FileManager.default.fileExists(atPath: resolved) {
                        return resolved
                    }
                }
            }
        }
        
        // Treat as relative path and resolve against documents directory
        return documentsDirectory.appendingPathComponent(storedPath).path
    }
    
    // MARK: - Books Management
    
    private func loadBooks() {
        if let data = userDefaults.data(forKey: Keys.books),
           let decodedBooks = try? JSONDecoder().decode([Book].self, from: data) {
            self.books = migrateBookPaths(decodedBooks)
        }
    }
    
    /// Migrates any books with stale absolute paths to relative paths,
    /// and removes books whose files no longer exist on disk.
    private func migrateBookPaths(_ books: [Book]) -> [Book] {
        var migrated = false
        var result: [Book] = []
        
        for var book in books {
            // Migrate filePath to relative if it's absolute
            if book.filePath.hasPrefix("/") {
                let resolved = resolveFilePath(book.filePath)
                if FileManager.default.fileExists(atPath: resolved) {
                    book.filePath = relativePath(for: resolved)
                    if let cover = book.coverImagePath, cover.hasPrefix("/") {
                        book.coverImagePath = relativePath(for: resolveFilePath(cover))
                    }
                    migrated = true
                } else {
                    // File doesn't exist at all — remove this book entry
                    migrated = true
                    continue
                }
            } else {
                // Already relative — verify file exists
                let resolved = resolveFilePath(book.filePath)
                if !FileManager.default.fileExists(atPath: resolved) {
                    migrated = true
                    continue
                }
            }
            
            result.append(book)
        }
        
        if migrated {
            // Persist the cleaned-up list
            if let encoded = try? JSONEncoder().encode(result) {
                userDefaults.set(encoded, forKey: Keys.books)
            }
        }
        
        return result
    }
    
    private func saveBooks() {
        if let encoded = try? JSONEncoder().encode(books) {
            userDefaults.set(encoded, forKey: Keys.books)
        }
    }
    
    func addBook(_ book: Book) {
        books.append(book)
        saveBooks()
    }
    
    func updateBook(_ book: Book) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index] = book
            saveBooks()
        }
    }
    
    func removeBook(_ book: Book) {
        books.removeAll { $0.id == book.id }
        
        // Remove associated files
        let resolvedBookPath = resolveFilePath(book.filePath)
        try? FileManager.default.removeItem(atPath: resolvedBookPath)
        
        if let coverPath = book.coverImagePath {
            let resolvedCoverPath = resolveFilePath(coverPath)
            try? FileManager.default.removeItem(atPath: resolvedCoverPath)
        }
        
        saveBooks()
    }
    
    func getBook(by id: UUID) -> Book? {
        return books.first { $0.id == id }
    }
    
    // MARK: - File Management
    
    func saveEPUBFile(_ data: Data, filename: String) throws -> URL {
        let fileURL = booksDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
    
    func saveCoverImage(_ data: Data, filename: String) throws -> URL {
        let fileURL = coversDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }
    
    func getStorageInfo() -> (totalSpace: Int64, usedSpace: Int64, availableSpace: Int64) {
        let totalSpace = try? booksDirectory.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity ?? 0
        let availableSpace = try? booksDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        
        let usedSpace = books.reduce(0) { $0 + $1.fileSize }
        
        return (
            totalSpace: Int64(totalSpace ?? 0),
            usedSpace: usedSpace,
            availableSpace: Int64(availableSpace ?? 0)
        )
    }
    
    // MARK: - OPDS Catalogs Management
    
    private func loadCatalogs() {
        if let data = userDefaults.data(forKey: Keys.catalogs),
           let decodedCatalogs = try? JSONDecoder().decode([OPDSCatalog].self, from: data) {
            self.catalogs = decodedCatalogs
        } else {
            // Add some default catalogs
            self.catalogs = [
                OPDSCatalog(name: "Project Gutenberg", url: "https://www.gutenberg.org/ebooks.opds/"),
                OPDSCatalog(name: "Internet Archive", url: "https://archive.org/services/opds")
            ]
            saveCatalogs()
        }
    }
    
    private func saveCatalogs() {
        if let encoded = try? JSONEncoder().encode(catalogs) {
            userDefaults.set(encoded, forKey: Keys.catalogs)
        }
    }
    
    func addCatalog(_ catalog: OPDSCatalog) {
        catalogs.append(catalog)
        saveCatalogs()
    }
    
    func updateCatalog(_ catalog: OPDSCatalog) {
        if let index = catalogs.firstIndex(where: { $0.id == catalog.id }) {
            catalogs[index] = catalog
            saveCatalogs()
        }
    }
    
    func removeCatalog(_ catalog: OPDSCatalog) {
        catalogs.removeAll { $0.id == catalog.id }
        saveCatalogs()
    }
    
    // MARK: - Sync Configuration

    /// Save sync configuration with credentials stored securely in Keychain
    func saveSyncConfiguration(_ config: SyncConfiguration) {
        // Store sensitive credentials in Keychain
        do {
            try keychainService.saveSyncCredentials(
                serverURL: config.serverURL,
                username: config.username,
                password: config.password
            )
        } catch {
            print("Failed to save sync credentials to Keychain: \(error)")
            return
        }

        // Store non-sensitive settings in UserDefaults
        let settings = SyncSettings(
            deviceName: config.deviceName,
            syncInterval: config.syncInterval,
            autoSync: config.autoSync
        )
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: Keys.syncSettings)
        }
    }

    /// Load sync configuration by combining Keychain credentials with UserDefaults settings
    func loadSyncConfiguration() -> SyncConfiguration? {
        // Load credentials from Keychain
        guard let credentials = keychainService.loadSyncCredentials() else {
            return nil
        }

        // Load settings from UserDefaults
        let settings: SyncSettings
        if let data = userDefaults.data(forKey: Keys.syncSettings),
           let decoded = try? JSONDecoder().decode(SyncSettings.self, from: data) {
            settings = decoded
        } else {
            settings = SyncSettings()
        }

        return SyncConfiguration(
            serverURL: credentials.serverURL,
            username: credentials.username,
            password: credentials.password,
            deviceName: settings.deviceName
        )
    }

    /// Remove sync configuration from both Keychain and UserDefaults
    func removeSyncConfiguration() {
        keychainService.deleteSyncCredentials()
        userDefaults.removeObject(forKey: Keys.syncSettings)
    }

    // MARK: - OPDS Catalog Credentials

    /// Save credentials for an OPDS catalog securely
    func saveOPDSCatalogCredentials(catalogId: UUID, username: String, password: String) {
        try? keychainService.saveOPDSCredentials(catalogId: catalogId, username: username, password: password)
    }

    /// Load credentials for an OPDS catalog
    func loadOPDSCatalogCredentials(for catalogId: UUID) -> (username: String, password: String)? {
        return keychainService.loadOPDSCredentials(for: catalogId)
    }

    /// Delete credentials for an OPDS catalog
    func deleteOPDSCatalogCredentials(for catalogId: UUID) {
        keychainService.deleteOPDSCredentials(for: catalogId)
    }
}
