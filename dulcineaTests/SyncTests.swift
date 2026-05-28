import Testing
import Foundation
@testable import dulcinea

struct SyncTests {

    // MARK: - SyncStatus Display Text Tests

    @Test func syncStatus_notConfigured_displaysCorrectText() {
        let status = SyncStatus.notConfigured
        #expect(status.displayText == "Not configured")
    }

    @Test func syncStatus_idle_displaysCorrectText() {
        let status = SyncStatus.idle
        #expect(status.displayText == "Ready to sync")
    }

    @Test func syncStatus_syncing_displaysCorrectText() {
        let status = SyncStatus.syncing
        #expect(status.displayText == "Syncing...")
    }

    @Test func syncStatus_error_displaysErrorMessage() {
        let status = SyncStatus.error(.authenticationFailed)
        #expect(status.displayText.contains("Authentication failed"))
    }

    @Test func syncStatus_lastSynced_displaysRelativeTime() {
        let status = SyncStatus.lastSynced(Date())
        #expect(status.displayText.contains("Last synced"))
    }

    // MARK: - SyncError Descriptions

    @Test func syncError_networkError_hasDescription() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection failed"])
        let error = SyncError.networkError(underlyingError)
        #expect(error.errorDescription?.contains("Network error") == true)
    }

    @Test func syncError_authenticationFailed_hasDescription() {
        let error = SyncError.authenticationFailed
        #expect(error.errorDescription?.contains("Authentication failed") == true)
    }

    @Test func syncError_serverError_includesMessage() {
        let error = SyncError.serverError("Internal server error")
        #expect(error.errorDescription?.contains("Internal server error") == true)
    }

    @Test func syncError_invalidResponse_hasDescription() {
        let error = SyncError.invalidResponse
        #expect(error.errorDescription?.contains("Invalid response") == true)
    }

    @Test func syncError_bookNotFound_hasDescription() {
        let error = SyncError.bookNotFound
        #expect(error.errorDescription?.contains("not found") == true)
    }

    @Test func syncError_configurationMissing_hasDescription() {
        let error = SyncError.configurationMissing
        #expect(error.errorDescription?.contains("missing") == true)
    }

    @Test func syncError_invalidServerURL_hasDescription() {
        let error = SyncError.invalidServerURL
        #expect(error.errorDescription?.contains("Invalid server URL") == true)
    }

    // MARK: - SyncProgressDetail Codable Tests

    @Test func syncProgressDetail_encodesAndDecodes() throws {
        let original = SyncProgressDetail(
            chapter: 5,
            position: 0.75,
            totalChapters: 20,
            lastReadDate: Date(),
            readingTime: 3600.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SyncProgressDetail.self, from: data)

        #expect(decoded.chapter == 5)
        #expect(decoded.position == 0.75)
        #expect(decoded.totalChapters == 20)
        #expect(decoded.readingTime == 3600.0)
    }

    @Test func syncProgressDetail_usesCodingKeys() throws {
        let json = """
        {
            "chapter": 3,
            "position": 0.5,
            "total_chapters": 10,
            "last_read_date": 0,
            "reading_time": 1800
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let data = json.data(using: .utf8)!
        let detail = try decoder.decode(SyncProgressDetail.self, from: data)

        #expect(detail.chapter == 3)
        #expect(detail.totalChapters == 10)
    }

    // MARK: - SyncProgress Codable Tests

    @Test func syncProgress_usesCodingKeys() throws {
        let json = """
        {
            "document": "book-123",
            "progress": "{\\"chapter\\":1}",
            "percentage": 0.25,
            "device": "iPhone",
            "device_id": "ABC123",
            "timestamp": 1700000000
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let data = json.data(using: .utf8)!
        let progress = try decoder.decode(SyncProgress.self, from: data)

        #expect(progress.document == "book-123")
        #expect(progress.deviceId == "ABC123")
        #expect(progress.percentage == 0.25)
    }
}
