import Foundation
import Combine
import UIKit

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var syncConfiguration: SyncConfiguration?
    @Published var syncStatus: SyncStatus = .notConfigured
    @Published var isConfiguringSyncServer = false
    @Published var errorMessage: String?
    
    var isSyncing: Bool {
        switch syncStatus {
        case .syncing:
            return true
        default:
            return false
        }
    }
    
    // Sync server configuration
    @Published var serverURL = ""
    @Published var username = ""
    @Published var password = ""
    @Published var deviceName = UIDevice.current.name
    @Published var autoSync = true
    @Published var syncInterval: SyncInterval = .fiveMinutes
    
    // App settings
    @Published var defaultReadingSettings = ReadingSettings()
    @Published var downloadOnlyOnWiFi = true
    @Published var automaticBackup = false
    @Published var deleteAfterReading = false
    @Published var showReadingProgress = true
    
    // Storage settings
    @Published var storageInfo: StorageInfo = StorageInfo()
    
    private let storageService: StorageService
    private let syncService: KOSyncService
    private var cancellables = Set<AnyCancellable>()
    
    init(storageService: StorageService, syncService: KOSyncService) {
        self.storageService = storageService
        self.syncService = syncService
        
        loadSettings()
        setupBindings()
    }
    
    private func setupBindings() {
        syncService.$status
            .receive(on: DispatchQueue.main)
            .assign(to: \.syncStatus, on: self)
            .store(in: &cancellables)
    }
    
    private func loadSettings() {
        loadSyncConfiguration()
        loadAppSettings()
        updateStorageInfo()
    }
    
    // MARK: - Sync Configuration
    
    private func loadSyncConfiguration() {
        syncConfiguration = storageService.loadSyncConfiguration()
        
        if let config = syncConfiguration {
            serverURL = config.serverURL
            username = config.username
            password = config.password
            deviceName = config.deviceName
            autoSync = config.autoSync
            syncInterval = SyncInterval(timeInterval: config.syncInterval)
        }
    }
    
    func testSyncConnection() async {
        guard !serverURL.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all sync server details"
            return
        }
        
        isConfiguringSyncServer = true
        errorMessage = nil
        
        let testConfig = SyncConfiguration(
            serverURL: serverURL,
            username: username,
            password: password,
            deviceName: deviceName
        )
        
        do {
            try await syncService.testConnection(with: testConfig)
            
            // Connection successful
            saveSyncConfiguration(testConfig)
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isConfiguringSyncServer = false
    }
    
    func saveSyncConfiguration(_ config: SyncConfiguration? = nil) {
        let configToSave = config ?? SyncConfiguration(
            serverURL: serverURL,
            username: username,
            password: password,
            deviceName: deviceName
        )
        
        var finalConfig = configToSave
        finalConfig = SyncConfiguration(
            serverURL: finalConfig.serverURL,
            username: finalConfig.username,
            password: finalConfig.password,
            deviceName: finalConfig.deviceName
        )
        
        storageService.saveSyncConfiguration(finalConfig)
        syncConfiguration = finalConfig
        
        // Update sync service
        syncService.configure(with: finalConfig)
    }
    
    func removeSyncConfiguration() {
        storageService.removeSyncConfiguration()
        syncConfiguration = nil
        syncService.disconnect()
        
        // Clear form
        serverURL = ""
        username = ""
        password = ""
        deviceName = UIDevice.current.name
    }
    
    func forceSyncAll() async {
        guard syncService.isConfigured else {
            errorMessage = "Sync is not configured"
            return
        }
        
        do {
            try await syncService.syncAllBooks(storageService.books)
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - App Settings
    
    private func loadAppSettings() {
        let defaults = UserDefaults.standard
        
        downloadOnlyOnWiFi = defaults.bool(forKey: "download_wifi_only") 
        automaticBackup = defaults.bool(forKey: "automatic_backup")
        deleteAfterReading = defaults.bool(forKey: "delete_after_reading")
        showReadingProgress = defaults.bool(forKey: "show_reading_progress") != false // Default to true
        
        loadDefaultReadingSettings()
    }
    
    private func loadDefaultReadingSettings() {
        let defaults = UserDefaults.standard
        
        defaultReadingSettings = ReadingSettings(
            fontSize: defaults.double(forKey: "default_font_size") != 0 ? defaults.double(forKey: "default_font_size") : 16,
            fontFamily: FontFamily(rawValue: defaults.string(forKey: "default_font_family") ?? "") ?? .systemDefault,
            backgroundColor: BackgroundColor(rawValue: defaults.string(forKey: "default_background") ?? "") ?? .white,
            lineSpacing: defaults.double(forKey: "default_line_spacing") != 0 ? defaults.double(forKey: "default_line_spacing") : 1.2,
            margin: defaults.double(forKey: "default_margin") != 0 ? defaults.double(forKey: "default_margin") : 20
        )
    }
    
    func saveAppSettings() {
        let defaults = UserDefaults.standard
        
        defaults.set(downloadOnlyOnWiFi, forKey: "download_wifi_only")
        defaults.set(automaticBackup, forKey: "automatic_backup")
        defaults.set(deleteAfterReading, forKey: "delete_after_reading")
        defaults.set(showReadingProgress, forKey: "show_reading_progress")
        
        saveDefaultReadingSettings()
    }
    
    func saveDefaultReadingSettings() {
        let defaults = UserDefaults.standard
        
        defaults.set(defaultReadingSettings.fontSize, forKey: "default_font_size")
        defaults.set(defaultReadingSettings.fontFamily.rawValue, forKey: "default_font_family")
        defaults.set(defaultReadingSettings.backgroundColor.rawValue, forKey: "default_background")
        defaults.set(defaultReadingSettings.lineSpacing, forKey: "default_line_spacing")
        defaults.set(defaultReadingSettings.margin, forKey: "default_margin")
    }
    
    func resetDefaultReadingSettings() {
        defaultReadingSettings = ReadingSettings()
        saveDefaultReadingSettings()
    }
    
    // MARK: - Storage Management
    
    func updateStorageInfo() {
        let info = storageService.getStorageInfo()
        storageInfo = StorageInfo(
            totalSpace: info.totalSpace,
            usedSpace: info.usedSpace,
            availableSpace: info.availableSpace,
            bookCount: storageService.books.count
        )
    }
    
    func clearCache() async {
        // Clear any cached images, temporary files, etc.
        // This would be implemented in the storage service
        updateStorageInfo()
    }
    
    func exportLibrary() async -> URL? {
        // Export library metadata to JSON file
        do {
            let libraryData = LibraryExport(
                books: storageService.books.map { BookExport(from: $0) },
                catalogs: storageService.catalogs,
                exportDate: Date()
            )
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(libraryData)
            
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("dulcinea_library_export.json")
            
            try data.write(to: tempURL)
            return tempURL
            
        } catch {
            errorMessage = "Failed to export library: \(error.localizedDescription)"
            return nil
        }
    }
    
    func importLibrary(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let libraryData = try decoder.decode(LibraryExport.self, from: data)
            
            // Import catalogs first
            for catalog in libraryData.catalogs {
                if !storageService.catalogs.contains(where: { $0.url == catalog.url }) {
                    storageService.addCatalog(catalog)
                }
            }
            
            // Note: Books themselves aren't imported, just metadata
            // The actual EPUB files would need to be imported separately
            
        } catch {
            errorMessage = "Failed to import library: \(error.localizedDescription)"
        }
    }
    
    // MARK: - About Information
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    var deviceInfo: String {
        "\(UIDevice.current.model) - iOS \(UIDevice.current.systemVersion)"
    }
}

// MARK: - Supporting Models

struct ReadingSettings {
    var fontSize: Double = 16
    var fontFamily: FontFamily = .systemDefault
    var backgroundColor: BackgroundColor = .white
    var lineSpacing: Double = 1.2
    var margin: Double = 20
}

enum SyncInterval: Double, CaseIterable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case manual = 0
    
    init(timeInterval: TimeInterval) {
        self = SyncInterval.allCases.first { $0.rawValue == timeInterval } ?? .fiveMinutes
    }
    
    var displayName: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .manual: return "Manual only"
        }
    }
}

struct StorageInfo {
    let totalSpace: Int64
    let usedSpace: Int64
    let availableSpace: Int64
    let bookCount: Int
    
    init(totalSpace: Int64 = 0, usedSpace: Int64 = 0, availableSpace: Int64 = 0, bookCount: Int = 0) {
        self.totalSpace = totalSpace
        self.usedSpace = usedSpace
        self.availableSpace = availableSpace
        self.bookCount = bookCount
    }
    
    var formattedTotalSpace: String {
        ByteCountFormatter().string(fromByteCount: totalSpace)
    }
    
    var formattedUsedSpace: String {
        ByteCountFormatter().string(fromByteCount: usedSpace)
    }
    
    var formattedAvailableSpace: String {
        ByteCountFormatter().string(fromByteCount: availableSpace)
    }
    
    var usagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }
}

struct LibraryExport: Codable {
    let books: [BookExport]
    let catalogs: [OPDSCatalog]
    let exportDate: Date
}

struct BookExport: Codable {
    let title: String
    let author: String
    let identifier: String
    let currentChapter: Int
    let currentPosition: Double
    let totalChapters: Int
    let isFinished: Bool
    let dateAdded: Date
    let lastOpened: Date?
    
    init(from book: Book) {
        self.title = book.title
        self.author = book.author
        self.identifier = book.identifier
        self.currentChapter = book.currentChapter
        self.currentPosition = book.currentPosition
        self.totalChapters = book.totalChapters
        self.isFinished = book.isFinished
        self.dateAdded = book.dateAdded
        self.lastOpened = book.lastOpened
    }
}
