import Foundation
import Combine

class KOSyncService: ObservableObject {
    @Published var status: SyncStatus = .notConfigured
    @Published var isConfigured = false
    
    private var configuration: SyncConfiguration?
    private let urlSession: URLSession
    private var syncTimer: Timer?
    
    private var isSyncing: Bool {
        switch status {
        case .syncing:
            return true
        default:
            return false
        }
    }
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Configuration
    
    func configure(with config: SyncConfiguration) {
        self.configuration = config
        self.isConfigured = true
        
        if config.autoSync {
            startAutoSync(interval: config.syncInterval)
        }
        
        status = .idle
    }
    
    func disconnect() {
        configuration = nil
        isConfigured = false
        stopAutoSync()
        status = .notConfigured
    }
    
    // MARK: - Connection Testing
    
    func testConnection(with config: SyncConfiguration) async throws {
        let testURL = URL(string: "\(config.serverURL)/users/auth")!
        var request = URLRequest(url: testURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let authData = [
            "username": config.username,
            "password": config.password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: authData)
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError(URLError(.badServerResponse))
        }
        
        switch httpResponse.statusCode {
        case 200:
            // Connection successful
            break
        case 401:
            throw SyncError.authenticationFailed
        case 404:
            throw SyncError.serverError("Server endpoint not found - check server URL")
        default:
            throw SyncError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
    
    // MARK: - Progress Upload
    
    func uploadProgress(for book: Book) async throws {
        guard let config = configuration else {
            throw SyncError.configurationMissing
        }
        
        status = .syncing
        
        do {
            let progressDetail = SyncProgressDetail(
                chapter: book.currentChapter,
                position: book.currentPosition,
                totalChapters: book.totalChapters,
                lastReadDate: book.lastOpened ?? Date(),
                readingTime: 0 // Would track actual reading time
            )
            
            let progressJSON = try JSONEncoder().encode(progressDetail)
            let progressString = String(data: progressJSON, encoding: .utf8) ?? ""
            
            let syncProgress = SyncProgress(
                document: book.identifier,
                progress: progressString,
                percentage: book.progressPercentage,
                device: config.deviceName,
                deviceId: config.deviceId,
                timestamp: Date()
            )
            
            try await uploadSyncProgress(syncProgress, config: config)
            status = .lastSynced(Date())
            
        } catch {
            status = .error(error as? SyncError ?? .networkError(error))
            throw error
        }
    }
    
    private func uploadSyncProgress(_ progress: SyncProgress, config: SyncConfiguration) async throws {
        let url = URL(string: "\(config.serverURL)/syncs/progress")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication
        let credentials = "\(config.username):\(config.password)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        // Prepare request body
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        request.httpBody = try encoder.encode(progress)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200, 201:
            // Success
            break
        case 401:
            throw SyncError.authenticationFailed
        case 404:
            throw SyncError.bookNotFound
        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorData["message"] as? String {
                throw SyncError.serverError(message)
            } else {
                throw SyncError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
    }
    
    // MARK: - Progress Download
    
    func downloadProgress(for book: Book) async throws -> SyncProgress? {
        guard let config = configuration else {
            throw SyncError.configurationMissing
        }
        
        let url = URL(string: "\(config.serverURL)/syncs/progress/\(book.identifier)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authentication
        let credentials = "\(config.username):\(config.password)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(SyncProgress.self, from: data)
        case 404:
            // No progress found for this book
            return nil
        case 401:
            throw SyncError.authenticationFailed
        default:
            throw SyncError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
    
    // MARK: - Bulk Sync
    
    func syncAllBooks(_ books: [Book]) async throws {
        guard let config = configuration else {
            throw SyncError.configurationMissing
        }
        
        status = .syncing
        
        do {
            // Upload all books that need syncing
            for book in books.filter({ $0.needsSync }) {
                try await uploadProgress(for: book)
            }
            
            // Download any updated progress from server
            for book in books {
                if let serverProgress = try await downloadProgress(for: book) {
                    // Check if server has newer progress
                    if let lastSync = book.lastSyncDate,
                       serverProgress.timestamp > lastSync {
                        
                        // Emit notification for updated progress
                        NotificationCenter.default.post(
                            name: .syncProgressUpdated,
                            object: nil,
                            userInfo: [
                                "book": book,
                                "serverProgress": serverProgress
                            ]
                        )
                    }
                }
            }
            
            status = .lastSynced(Date())
            
        } catch {
            status = .error(error as? SyncError ?? .networkError(error))
            throw error
        }
    }
    
    // MARK: - Auto Sync
    
    private func startAutoSync(interval: TimeInterval) {
        guard interval > 0 else { return }
        
        stopAutoSync()
        
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await self?.performAutoSync()
            }
        }
    }
    
    private func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    private func performAutoSync() async {
        guard isConfigured, !isSyncing else { return }
        // Get books that need syncing from storage
        // This would typically come from a storage service
        // For now, we'll emit a notification requesting sync
        NotificationCenter.default.post(name: .autoSyncRequested, object: nil)
    }
    
    // MARK: - Reading Session Tracking
    
    func startReadingSession(for book: Book) {
        // Track when user starts reading
        let sessionData: [String: Any] = [
            "book_id": book.identifier,
            "start_time": Date().timeIntervalSince1970
        ]
        
        NotificationCenter.default.post(
            name: .readingSessionStarted,
            object: nil,
            userInfo: sessionData
        )
    }
    
    func endReadingSession(for book: Book, readingTime: TimeInterval) {
        // Track reading session end and duration
        let sessionData: [String: Any] = [
            "book_id": book.identifier,
            "reading_time": readingTime,
            "end_time": Date().timeIntervalSince1970
        ]
        
        NotificationCenter.default.post(
            name: .readingSessionEnded,
            object: nil,
            userInfo: sessionData
        )
        
        // Auto-sync if configured
        if let config = configuration, config.autoSync {
            Task {
                try? await uploadProgress(for: book)
            }
        }
    }
    
    // MARK: - Device Management
    
    func registerDevice() async throws {
        guard let config = configuration else {
            throw SyncError.configurationMissing
        }
        
        let url = URL(string: "\(config.serverURL)/devices")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication
        let credentials = "\(config.username):\(config.password)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        let deviceInfo = [
            "device_id": config.deviceId,
            "device_name": config.deviceName,
            "device_type": "iOS",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: deviceInfo)
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw SyncError.serverError("Failed to register device")
        }
    }
    
    // MARK: - Statistics
    
    func getReadingStatistics() async throws -> ReadingStatistics? {
        guard let config = configuration else {
            throw SyncError.configurationMissing
        }
        
        let url = URL(string: "\(config.serverURL)/users/\(config.username)/stats")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authentication
        let credentials = "\(config.username):\(config.password)"
        let credentialsData = credentials.data(using: .utf8)!
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(ReadingStatistics.self, from: data)
        case 404:
            return nil
        case 401:
            throw SyncError.authenticationFailed
        default:
            throw SyncError.serverError("HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Supporting Types

struct ReadingStatistics: Codable {
    let totalReadingTime: TimeInterval
    let booksRead: Int
    let averageSessionTime: TimeInterval
    let longestSession: TimeInterval
    let currentStreak: Int
    let totalSessions: Int
    
    enum CodingKeys: String, CodingKey {
        case totalReadingTime = "total_reading_time"
        case booksRead = "books_read"
        case averageSessionTime = "average_session_time"
        case longestSession = "longest_session"
        case currentStreak = "current_streak"
        case totalSessions = "total_sessions"
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let syncProgressUpdated = Notification.Name("syncProgressUpdated")
    static let autoSyncRequested = Notification.Name("autoSyncRequested")
    static let readingSessionStarted = Notification.Name("readingSessionStarted")
    static let readingSessionEnded = Notification.Name("readingSessionEnded")
}
