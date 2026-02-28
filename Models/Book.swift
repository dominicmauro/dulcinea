import Foundation

struct Book: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let author: String
    let identifier: String // ISBN or other unique identifier
    var filePath: String // Local file path (stored as relative path)
    var coverImagePath: String?
    let fileSize: Int64
    let dateAdded: Date
    var lastOpened: Date?
    
    // Reading Progress
    var currentChapter: Int
    var currentPosition: Double // 0.0 to 1.0
    var totalChapters: Int
    var isFinished: Bool
    
    // Sync status
    var lastSyncDate: Date?
    var needsSync: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        identifier: String,
        filePath: String,
        coverImagePath: String? = nil,
        fileSize: Int64,
        currentChapter: Int = 0,
        currentPosition: Double = 0.0,
        totalChapters: Int = 1
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.identifier = identifier
        self.filePath = filePath
        self.coverImagePath = coverImagePath
        self.fileSize = fileSize
        self.dateAdded = Date()
        self.lastOpened = nil
        self.currentChapter = currentChapter
        self.currentPosition = currentPosition
        self.totalChapters = totalChapters
        self.isFinished = false
        self.lastSyncDate = nil
        self.needsSync = false
    }
    
    // MARK: - Computed Properties
    
    var progressPercentage: Double {
        guard totalChapters > 0 else { return 0.0 }
        let chapterProgress = Double(currentChapter) / Double(totalChapters)
        let positionProgress = currentPosition / Double(totalChapters)
        return chapterProgress + positionProgress
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        return formatter.string(fromByteCount: fileSize)
    }
    
    // MARK: - Methods
    
    mutating func updateProgress(chapter: Int, position: Double) {
        self.currentChapter = chapter
        self.currentPosition = position
        self.needsSync = true
        
        // Mark as finished if we're at the end
        if chapter >= totalChapters - 1 && position >= 0.95 {
            self.isFinished = true
        }
    }
    
    mutating func markAsOpened() {
        self.lastOpened = Date()
    }
    
    mutating func markAsSynced() {
        self.lastSyncDate = Date()
        self.needsSync = false
    }
}
