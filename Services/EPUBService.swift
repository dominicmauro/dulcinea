import Foundation
import Combine
import ZIPFoundation

class EPUBService: ObservableObject {
    private let storageService: StorageService
    
    init(storageService: StorageService) {
        self.storageService = storageService
    }
    
    // MARK: - EPUB Loading and Parsing
    
    func loadEPUB(from filePath: String) async throws -> EPUBContent {
        let fileURL = URL(fileURLWithPath: filePath)
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw EPUBError.fileNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let content = try self.parseEPUBFile(at: fileURL)
                    continuation.resume(returning: content)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func parseEPUBFile(at url: URL) throws -> EPUBContent {
        // Create unique temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub_\(UUID().uuidString)")
        
        // Ensure the directory doesn't exist and create it
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Extract EPUB (it's a ZIP file)
        do {
            let archive = try Archive(url: url, accessMode: .read)
            for entry in archive {
                let destinationURL = tempDir.appendingPathComponent(entry.path)
                
                // Create intermediate directories if needed
                let parentDir = destinationURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                
                // Extract the entry
                _ = try archive.extract(entry, to: destinationURL.deletingLastPathComponent())
            }
        } catch {
            throw EPUBError.extractionFailed
        }
        
        // Parse container.xml to find OPF file
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        guard FileManager.default.fileExists(atPath: containerPath.path) else {
            throw EPUBError.invalidContainer
        }
        
        let opfPath = try parseContainer(at: containerPath, baseURL: tempDir)
        
        // Parse OPF file for metadata and manifest
        let (metadata, manifest, spine) = try parseOPF(at: opfPath)
        
        // Extract chapters from spine
        let chapters = try extractChapters(from: spine, manifest: manifest, baseURL: opfPath.deletingLastPathComponent())
        
        // Generate table of contents
        let tableOfContents = try generateTableOfContents(from: manifest, baseURL: opfPath.deletingLastPathComponent())
        
        return EPUBContent(
            metadata: metadata,
            chapters: chapters,
            tableOfContents: tableOfContents
        )
    }
    
    // MARK: - Container Parsing
    
    private func parseContainer(at url: URL, baseURL: URL) throws -> URL {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        let delegate = ContainerParserDelegate()
        parser.delegate = delegate
        
        guard parser.parse(), let opfPath = delegate.opfPath else {
            throw EPUBError.invalidContainer
        }
        
        return baseURL.appendingPathComponent(opfPath)
    }
    
    // MARK: - OPF Parsing
    
    private func parseOPF(at url: URL) throws -> (EPUBMetadata, [String: ManifestItem], [String]) {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        let delegate = OPFParserDelegate()
        parser.delegate = delegate
        
        guard parser.parse() else {
            throw EPUBError.invalidOPF
        }
        
        return (delegate.metadata, delegate.manifest, delegate.spine)
    }
    
    // MARK: - Chapter Extraction
    
    private func extractChapters(from spine: [String], manifest: [String: ManifestItem], baseURL: URL) throws -> [EPUBChapter] {
        var chapters: [EPUBChapter] = []
        
        for (index, spineItemId) in spine.enumerated() {
            guard let manifestItem = manifest[spineItemId] else { continue }
            
            let chapterURL = baseURL.appendingPathComponent(manifestItem.href)
            
            guard FileManager.default.fileExists(atPath: chapterURL.path) else { continue }
            
            let htmlContent = try String(contentsOf: chapterURL, encoding: .utf8)
            let textContent = extractTextFromHTML(htmlContent)
            let title = extractChapterTitle(from: htmlContent) ?? "Chapter \(index + 1)"
            
            let chapter = EPUBChapter(
                title: title,
                content: textContent,
                htmlContent: htmlContent,
                order: index
            )
            
            chapters.append(chapter)
        }
        
        return chapters
    }
    
    // MARK: - Table of Contents Generation
    
    private func generateTableOfContents(from manifest: [String: ManifestItem], baseURL: URL) throws -> [TOCEntry] {
        // Look for NCX or NAV file in manifest
        let tocItem = manifest.values.first { item in
            item.mediaType == "application/x-dtbncx+xml" || 
            item.properties?.contains("nav") == true
        }
        
        guard let tocItem = tocItem else {
            // Generate simple TOC from spine
            return []
        }
        
        let tocURL = baseURL.appendingPathComponent(tocItem.href)
        
        if tocItem.mediaType == "application/x-dtbncx+xml" {
            return try parseNCXFile(at: tocURL)
        } else {
            return try parseNavFile(at: tocURL)
        }
    }
    
    private func parseNCXFile(at url: URL) throws -> [TOCEntry] {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        let delegate = NCXParserDelegate()
        parser.delegate = delegate
        
        guard parser.parse() else {
            throw EPUBError.invalidNCX
        }
        
        return delegate.tocEntries
    }
    
    private func parseNavFile(at url: URL) throws -> [TOCEntry] {
        // Simplified NAV parsing - would need more robust HTML parsing
        return []
    }
    
    // MARK: - HTML Processing
    
    private func extractTextFromHTML(_ html: String) -> String {
        // Simple HTML tag removal - in production, use a proper HTML parser
        let pattern = "<[^>]+>"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: html.utf16.count)
        let text = regex?.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "")
        
        return text?
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    private func extractChapterTitle(from html: String) -> String? {
        // Look for title in h1, h2, or title tags
        let patterns = ["<title[^>]*>([^<]+)</title>", "<h1[^>]*>([^<]+)</h1>", "<h2[^>]*>([^<]+)</h2>"]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return nil
    }
    
    // MARK: - Cover Image Extraction
    
    // In EPUBService.swift, replace the extractCoverImage method with this fixed version:

    func extractCoverImage(from filePath: String) async throws -> Data? {
        let fileURL = URL(fileURLWithPath: filePath)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover_\(UUID().uuidString)")
        
        // Ensure clean temporary directory
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        do {
            // Extract EPUB
            let archive = try Archive(url: fileURL, accessMode: .read)
            for entry in archive {
                let destinationURL = tempDir.appendingPathComponent(entry.path)
                let parentDir = destinationURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: parentDir)
            }
            
            // Parse container and OPF to find cover
            let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
            guard FileManager.default.fileExists(atPath: containerPath.path) else {
                return nil
            }
            
            let opfPath = try parseContainer(at: containerPath, baseURL: tempDir)
            let (_, manifest, _) = try parseOPF(at: opfPath)
            
            // Look for cover image in manifest
            let coverItem = manifest.values.first { item in
                item.properties?.contains("cover-image") == true ||
                item.id == "cover" ||
                item.id == "cover-image" ||
                item.id.lowercased().contains("cover")
            }
            
            guard let coverItem = coverItem else { return nil }
            
            let coverURL = opfPath.deletingLastPathComponent().appendingPathComponent(coverItem.href)
            
            guard FileManager.default.fileExists(atPath: coverURL.path) else { return nil }
            
            return try Data(contentsOf: coverURL)
            
        } catch {
            print("Error extracting cover image: \(error)")
            return nil
        }
    }
    
    // MARK: - Book Creation Helper
    
    func createBookFromEPUB(at url: URL, data: Data) async throws -> Book {
        // Save EPUB file
        let filename = url.lastPathComponent
        let localURL = try storageService.saveEPUBFile(data, filename: filename)
        
        // Extract metadata
        let content = try await loadEPUB(from: localURL.path)
        
        // Extract and save cover image
        var coverImagePath: String?
        if let coverData = try await extractCoverImage(from: localURL.path) {
            let coverFilename = "\(UUID().uuidString).jpg"
            let coverURL = try storageService.saveCoverImage(coverData, filename: coverFilename)
            coverImagePath = coverURL.path
        }
        
        return Book(
            title: content.metadata.title,
            author: content.metadata.author,
            identifier: content.metadata.identifier,
            filePath: localURL.path,
            coverImagePath: coverImagePath,
            fileSize: Int64(data.count),
            totalChapters: content.chapters.count
        )
    }
}

// MARK: - Supporting Types

struct ManifestItem {
    let id: String
    let href: String
    let mediaType: String
    let properties: [String]?
}

enum EPUBError: Error, LocalizedError {
    case fileNotFound
    case invalidContainer
    case invalidOPF
    case invalidNCX
    case extractionFailed
    case parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "EPUB file not found"
        case .invalidContainer:
            return "Invalid EPUB container"
        case .invalidOPF:
            return "Invalid EPUB package file"
        case .invalidNCX:
            return "Invalid navigation file"
        case .extractionFailed:
            return "Failed to extract EPUB contents"
        case .parsingFailed:
            return "Failed to parse EPUB structure"
        }
    }
}

// MARK: - XML Parser Delegates

class ContainerParserDelegate: NSObject, XMLParserDelegate {
    var opfPath: String?
    private var currentElement = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "rootfile" {
            opfPath = attributeDict["full-path"]
        }
    }
}

class OPFParserDelegate: NSObject, XMLParserDelegate {
    var metadata = EPUBMetadata(
        title: "",
        author: "",
        identifier: "",
        language: "en",
        publisher: nil,
        publishDate: nil,
        description: nil,
        coverImagePath: nil
    )
    var manifest: [String: ManifestItem] = [:]
    var spine: [String] = []
    
    private var currentElement = ""
    private var currentText = ""
    private var currentItemId = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        
        switch elementName {
        case "item":
            if let id = attributeDict["id"],
               let href = attributeDict["href"],
               let mediaType = attributeDict["media-type"] {
                let properties = attributeDict["properties"]?.components(separatedBy: " ")
                manifest[id] = ManifestItem(id: id, href: href, mediaType: mediaType, properties: properties)
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spine.append(idref)
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
        case "dc:title":
            metadata = EPUBMetadata(
                title: text,
                author: metadata.author,
                identifier: metadata.identifier,
                language: metadata.language,
                publisher: metadata.publisher,
                publishDate: metadata.publishDate,
                description: metadata.description,
                coverImagePath: metadata.coverImagePath
            )
        case "dc:creator":
            metadata = EPUBMetadata(
                title: metadata.title,
                author: text,
                identifier: metadata.identifier,
                language: metadata.language,
                publisher: metadata.publisher,
                publishDate: metadata.publishDate,
                description: metadata.description,
                coverImagePath: metadata.coverImagePath
            )
        case "dc:identifier":
            metadata = EPUBMetadata(
                title: metadata.title,
                author: metadata.author,
                identifier: text,
                language: metadata.language,
                publisher: metadata.publisher,
                publishDate: metadata.publishDate,
                description: metadata.description,
                coverImagePath: metadata.coverImagePath
            )
        case "dc:language":
            metadata = EPUBMetadata(
                title: metadata.title,
                author: metadata.author,
                identifier: metadata.identifier,
                language: text,
                publisher: metadata.publisher,
                publishDate: metadata.publishDate,
                description: metadata.description,
                coverImagePath: metadata.coverImagePath
            )
        case "dc:publisher":
            metadata = EPUBMetadata(
                title: metadata.title,
                author: metadata.author,
                identifier: metadata.identifier,
                language: metadata.language,
                publisher: text,
                publishDate: metadata.publishDate,
                description: metadata.description,
                coverImagePath: metadata.coverImagePath
            )
        case "dc:description":
            metadata = EPUBMetadata(
                title: metadata.title,
                author: metadata.author,
                identifier: metadata.identifier,
                language: metadata.language,
                publisher: metadata.publisher,
                publishDate: metadata.publishDate,
                description: text,
                coverImagePath: metadata.coverImagePath
            )
        default:
            break
        }
        
        currentElement = ""
        currentText = ""
    }
}

class NCXParserDelegate: NSObject, XMLParserDelegate {
    var tocEntries: [TOCEntry] = []
    private var currentNavPoint: TOCEntry?
    private var currentText = ""
    private var currentElement = ""
    private var navPointStack: [TOCEntry] = []
    private var currentLevel = 0
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        
        if elementName == "navPoint" {
            currentLevel += 1
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "text":
            if currentNavPoint == nil {
                currentNavPoint = TOCEntry(title: text, chapterIndex: 0, level: currentLevel, children: [])
            }
        case "navPoint":
            if let navPoint = currentNavPoint {
                if currentLevel == 1 {
                    tocEntries.append(navPoint)
                }
                currentNavPoint = nil
            }
            currentLevel -= 1
        default:
            break
        }
        
        currentElement = ""
        currentText = ""
    }
}
