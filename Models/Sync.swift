import Foundation
import UIKit

// MARK: - KOSync Models

struct SyncProgress: Codable {
    let document: String // Book identifier
    let progress: String // JSON string with progress data
    let percentage: Double
    let device: String
    let deviceId: String
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case document, progress, percentage, device
        case deviceId = "device_id"
        case timestamp
    }
}

struct SyncProgressDetail: Codable {
    let chapter: Int
    let position: Double
    let totalChapters: Int
    let lastReadDate: Date
    let readingTime: TimeInterval // Total time spent reading
    
    enum CodingKeys: String, CodingKey {
        case chapter, position
        case totalChapters = "total_chapters"
        case lastReadDate = "last_read_date"
        case readingTime = "reading_time"
    }
}

struct SyncConfiguration: Codable {
    let serverURL: String
    let username: String
    let password: String
    let deviceName: String
    let deviceId: String
    let syncInterval: TimeInterval // in seconds
    let autoSync: Bool
    
    init(serverURL: String, username: String, password: String, deviceName: String = UIDevice.current.name) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.deviceName = deviceName
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.syncInterval = 300 // 5 minutes default
        self.autoSync = true
    }
}

struct SyncResponse: Codable {
    let success: Bool
    let message: String?
    let data: SyncProgress?
    let timestamp: Date
}

enum SyncError: Error, LocalizedError {
    case networkError(Error)
    case authenticationFailed
    case serverError(String)
    case invalidResponse
    case bookNotFound
    case configurationMissing
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationFailed:
            return "Authentication failed. Please check your credentials."
        case .serverError(let message):
            return "Server error: \(message)"
        case .invalidResponse:
            return "Invalid response from sync server."
        case .bookNotFound:
            return "Book not found on sync server."
        case .configurationMissing:
            return "Sync configuration is missing or incomplete."
        }
    }
}

// MARK: - Sync Status

enum SyncStatus {
    case notConfigured
    case idle
    case syncing
    case error(SyncError)
    case lastSynced(Date)
    
    var displayText: String {
        switch self {
        case .notConfigured:
            return "Not configured"
        case .idle:
            return "Ready to sync"
        case .syncing:
            return "Syncing..."
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        case .lastSynced(let date):
            let formatter = RelativeDateTimeFormatter()
            return "Last synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        }
    }
}
