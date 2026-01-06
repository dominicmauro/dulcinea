import Foundation
import Combine

class OPDSService: ObservableObject {
    private let storageService: StorageService
    private let urlSession: URLSession
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    
    init(storageService: StorageService) {
        self.storageService = storageService
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Feed Fetching
    
    func fetchFeed(from url: String, catalog: OPDSCatalog?) async throws -> OPDSFeed {
        guard let feedURL = URL(string: url) else {
            throw OPDSError.invalidURL
        }
        
        var request = URLRequest(url: feedURL)
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        
        // Add authentication if required
        if let catalog = catalog, catalog.requiresAuthentication,
           let username = catalog.username,
           let password = catalog.password {
            let credentials = "\(username):\(password)"
            if let credentialsData = credentials.data(using: .utf8) {
                let base64Credentials = credentialsData.base64EncodedString()
                request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OPDSError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 401 {
                throw OPDSError.authenticationRequired
            }
            throw OPDSError.serverError(httpResponse.statusCode)
        }
        
        return try parseFeed(from: data, baseURL: feedURL)
    }
    
    private func parseFeed(from data: Data, baseURL: URL) throws -> OPDSFeed {
        let parser = XMLParser(data: data)
        let delegate = OPDSFeedParserDelegate(baseURL: baseURL)
        parser.delegate = delegate
        
        guard parser.parse() else {
            throw OPDSError.parsingFailed
        }
        
        guard let feed = delegate.feed else {
            throw OPDSError.invalidFeed
        }
        
        return feed
    }
    
    // MARK: - Search
    
    func searchCatalog(_ catalog: OPDSCatalog, query: String) async throws -> [OPDSEntry] {
        // Most OPDS feeds support OpenSearch
        let searchURL = try constructSearchURL(for: catalog, query: query)
        let feed = try await fetchFeed(from: searchURL, catalog: catalog)
        return feed.entries
    }
    
    private func constructSearchURL(for catalog: OPDSCatalog, query: String) throws -> String {
        // Try common search patterns
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let searchPatterns = [
            "\(catalog.url)/search?q=\(encodedQuery)",
            "\(catalog.url)/search.xml?query=\(encodedQuery)",
            "\(catalog.url)?search=\(encodedQuery)"
        ]
        
        // For now, use the first pattern - in production, you'd detect the search capability from the feed
        return searchPatterns[0]
    }
    
    // MARK: - Download Management
    
    func downloadBook(
        from url: String,
        entry: OPDSEntry,
        catalog: OPDSCatalog?,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> (URL, Book) {
        
        guard let downloadURL = URL(string: url) else {
            throw OPDSError.invalidURL
        }
        
        var request = URLRequest(url: downloadURL)
        
        // Add authentication if required
        if let catalog = catalog, catalog.requiresAuthentication,
           let username = catalog.username,
           let password = catalog.password {
            let credentials = "\(username):\(password)"
            if let credentialsData = credentials.data(using: .utf8) {
                let base64Credentials = credentialsData.base64EncodedString()
                request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // Declare timer variable first
            var progressTimer: Timer?
            
            let task = urlSession.downloadTask(with: request) { [weak self] localURL, response, error in
                // Clean up timer and task tracking immediately
                progressTimer?.invalidate()
                self?.downloadTasks.removeValue(forKey: entry.id)
                
                if let error = error {
                    continuation.resume(throwing: OPDSError.downloadFailed(error))
                    return
                }
                
                guard let localURL = localURL,
                      let httpResponse = response as? HTTPURLResponse,
                      200...299 ~= httpResponse.statusCode else {
                    continuation.resume(throwing: OPDSError.downloadFailed(URLError(.badServerResponse)))
                    return
                }
                
                do {
                    // Move file to permanent location
                    let data = try Data(contentsOf: localURL)
                    let filename = self?.generateFilename(from: entry, response: httpResponse) ?? "book.epub"
                    let permanentURL = try self?.storageService.saveEPUBFile(data, filename: filename)
                    
                    // Create book object
                    let book = Book(
                        title: entry.title,
                        author: entry.authorNames,
                        identifier: entry.id,
                        filePath: permanentURL?.path ?? "",
                        fileSize: Int64(data.count)
                    )
                    
                    continuation.resume(returning: (permanentURL!, book))
                    
                } catch {
                    continuation.resume(throwing: OPDSError.downloadFailed(error))
                }
            }
            
            // Now assign the timer
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                DispatchQueue.main.async {
                    progressHandler(task.progress.fractionCompleted)
                }
            }
            
            downloadTasks[entry.id] = task
            task.resume()
        }
    }
    
    // MARK: - Cancel active downloads
    
    func cancelDownload(entryId: String) {
        downloadTasks[entryId]?.cancel()
        downloadTasks.removeValue(forKey: entryId)
    }
    
    // MARK: - Generate safe filenames for downloaded books

    func generateFilename(from entry: OPDSEntry, response: HTTPURLResponse) -> String {
        // Try to get filename from Content-Disposition header
        if let contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           let filenameRange = contentDisposition.range(of: "filename="),
           let filename = contentDisposition[filenameRange.upperBound...].components(separatedBy: ";").first {
            return filename.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        
        // Generate filename from entry title
        let sanitizedTitle = entry.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "\"", with: "")
        
        return "\(sanitizedTitle).epub"
    }
    
    // MARK: - Cover Image Download
    
    func downloadCoverImage(from url: String) async throws -> Data {
        guard let imageURL = URL(string: url) else {
            throw OPDSError.invalidURL
        }
        
        let (data, response) = try await urlSession.data(from: imageURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw OPDSError.downloadFailed(URLError(.badServerResponse))
        }
        
        return data
    }
    
    // MARK: - Feed Validation
    
    func validateCatalog(_ catalog: OPDSCatalog) async throws -> Bool {
        do {
            let _ = try await fetchFeed(from: catalog.url, catalog: catalog)
            return true
        } catch OPDSError.authenticationRequired {
            // If auth is required but not provided, it's still a valid catalog
            return !catalog.requiresAuthentication
        } catch {
            throw error
        }
    }
}

// MARK: - OPDS Feed Parser

class OPDSFeedParserDelegate: NSObject, XMLParserDelegate {
    var feed: OPDSFeed?
    
    private let baseURL: URL
    private var currentElement = ""
    private var currentText = ""
    private var currentAttributes: [String: String] = [:]
    
    // Feed-level properties
    private var feedId = ""
    private var feedTitle = ""
    private var feedUpdated = Date()
    private var feedLinks: [OPDSLink] = []
    private var entries: [OPDSEntry] = []
    
    // Current entry being parsed
    private var currentEntry: ParsedEntry?
    
    init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        currentAttributes = attributeDict
        
        switch elementName {
        case "entry":
            currentEntry = ParsedEntry()
        case "link":
            let link = OPDSLink(
                href: resolveURL(attributeDict["href"] ?? ""),
                type: attributeDict["type"],
                rel: attributeDict["rel"],
                title: attributeDict["title"]
            )
            
            if currentEntry != nil {
                currentEntry?.links.append(link)
            } else {
                feedLinks.append(link)
            }
        case "category":
            if let term = attributeDict["term"] {
                let category = OPDSCategory(
                    term: term,
                    label: attributeDict["label"],
                    scheme: attributeDict["scheme"]
                )
                currentEntry?.categories.append(category)
            }
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "feed":
            feed = OPDSFeed(
                id: feedId,
                title: feedTitle,
                updated: feedUpdated,
                entries: entries,
                links: feedLinks
            )
        case "entry":
            if let entry = currentEntry?.toOPDSEntry() {
                entries.append(entry)
            }
            currentEntry = nil
        case "id":
            if currentEntry != nil {
                currentEntry?.id = text
            } else {
                feedId = text
            }
        case "title":
            if currentEntry != nil {
                currentEntry?.title = text
            } else {
                feedTitle = text
            }
        case "summary", "content":
            currentEntry?.summary = text
        case "updated":
            let date = parseDate(from: text)
            if currentEntry != nil {
                currentEntry?.updated = date
            } else {
                feedUpdated = date
            }
        case "published":
            currentEntry?.published = parseDate(from: text)
        case "name":
            currentEntry?.authorName = text
        case "author":
            if let name = currentEntry?.authorName {
                let author = OPDSAuthor(name: name, uri: nil)
                currentEntry?.authors.append(author)
                currentEntry?.authorName = nil
            }
        default:
            break
        }
        
        currentElement = ""
        currentText = ""
        currentAttributes = [:]
    }
    
    private func resolveURL(_ urlString: String) -> String {
        guard !urlString.isEmpty else { return "" }
        
        // If it's already an absolute URL, return as-is
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return urlString
        }
        
        // Resolve relative URL
        let resolvedURL = URL(string: urlString, relativeTo: baseURL)
        return resolvedURL?.absoluteString ?? urlString
    }
    
    private func parseDate(from string: String) -> Date {
        // Try ISO8601 first
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: string) {
            return date
        }
        
        // Try other formatters
        let formatters = [
            DateFormatter.rfc3339,
            DateFormatter.rfc822
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        
        return Date()
    }
}

// MARK: - Helper Classes

private class ParsedEntry {
    var id = ""
    var title = ""
    var summary: String?
    var authors: [OPDSAuthor] = []
    var authorName: String?
    var published: Date?
    var updated = Date()
    var links: [OPDSLink] = []
    var categories: [OPDSCategory] = []
    
    func toOPDSEntry() -> OPDSEntry {
        return OPDSEntry(
            id: id,
            title: title,
            summary: summary,
            authors: authors,
            published: published,
            updated: updated,
            links: links,
            categories: categories.isEmpty ? nil : categories
        )
    }
}

extension DateFormatter {
    static let rfc3339: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    static let rfc822: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

// MARK: - OPDS Errors

enum OPDSError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case authenticationRequired
    case serverError(Int)
    case parsingFailed
    case invalidFeed
    case downloadFailed(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid catalog URL"
        case .invalidResponse:
            return "Invalid response from catalog server"
        case .authenticationRequired:
            return "Authentication required for this catalog"
        case .serverError(let code):
            return "Server error: \(code)"
        case .parsingFailed:
            return "Failed to parse catalog feed"
        case .invalidFeed:
            return "Invalid catalog feed format"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
