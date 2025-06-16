import Foundation

// MARK: - OPDS Feed Models

struct OPDSFeed: Codable {
    let id: String
    let title: String
    let updated: Date
    let entries: [OPDSEntry]
    let links: [OPDSLink]
    
    enum CodingKeys: String, CodingKey {
        case id, title, updated, entries, links
    }
}

struct OPDSEntry: Identifiable, Codable {
    let id: String
    let title: String
    let summary: String?
    let authors: [OPDSAuthor]
    let published: Date?
    let updated: Date
    let links: [OPDSLink]
    let categories: [OPDSCategory]?
    
    // Computed properties
    var authorNames: String {
        authors.map { $0.name }.joined(separator: ", ")
    }
    
    var downloadLink: OPDSLink? {
        links.first { $0.type?.contains("epub") == true }
    }
    
    var coverImageLink: OPDSLink? {
        links.first { 
            $0.rel == "http://opds-spec.org/image" || 
            $0.rel == "http://opds-spec.org/image/thumbnail" 
        }
    }
}

struct OPDSAuthor: Codable {
    let name: String
    let uri: String?
}

struct OPDSLink: Codable {
    let href: String
    let type: String?
    let rel: String?
    let title: String?
    
    var isAcquisition: Bool {
        rel?.contains("http://opds-spec.org/acquisition") == true
    }
    
    var isNavigation: Bool {
        type?.contains("application/atom+xml") == true
    }
}

struct OPDSCategory: Codable {
    let term: String
    let label: String?
    let scheme: String?
}

// MARK: - OPDS Catalog Configuration

struct OPDSCatalog: Identifiable, Codable {
    let id: UUID
    let name: String
    let url: String
    let username: String?
    let password: String?
    let isEnabled: Bool
    let lastUpdated: Date?
    
    init(name: String, url: String, username: String? = nil, password: String? = nil) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.username = username
        self.password = password
        self.isEnabled = true
        self.lastUpdated = nil
    }
    
    var requiresAuthentication: Bool {
        return username != nil && password != nil
    }
}

// MARK: - Download Status

enum DownloadStatus {
    case notStarted
    case downloading(progress: Double)
    case completed
    case failed(error: Error)
    case paused
}

struct DownloadTask: Identifiable {
    let id = UUID()
    let entry: OPDSEntry
    var status: DownloadStatus = .notStarted
    var localURL: URL?
    
    var progress: Double {
        switch status {
        case .downloading(let progress):
            return progress
        case .completed:
            return 1.0
        default:
            return 0.0
        }
    }
}