import SwiftUI
import Combine

class AppCoordinator: ObservableObject {
    enum Tab {
        case library, browse, settings
    }
    
    @Published var selectedTab: Tab = .library
    @Published var presentedBook: Book?
    
    // ViewModels
    let libraryViewModel: LibraryViewModel
    let readerViewModel: ReaderViewModel
    let browseViewModel: BrowseViewModel
    
    // Services
    private let epubService: EPUBService
    private let opdsService: OPDSService
    private let syncService: KOSyncService
    private let storageService: StorageService
    
    @MainActor
    init() {
        // Initialize services
        self.storageService = StorageService()
        self.epubService = EPUBService(storageService: storageService)
        self.opdsService = OPDSService(storageService: storageService)
        self.syncService = KOSyncService()
        
        // Initialize view models with dependencies
        self.libraryViewModel = LibraryViewModel(
            storageService: storageService,
            epubService: epubService,
            syncService: syncService
        )
        self.readerViewModel = ReaderViewModel(
            epubService: epubService,
            syncService: syncService,
            storageService: storageService
        )
        self.browseViewModel = BrowseViewModel(
            opdsService: opdsService,
            storageService: storageService
        )
    }
    
    // MARK: - Navigation Actions
    
    func presentReader(for book: Book) {
        presentedBook = book
    }
    
    func dismissReader() {
        presentedBook = nil
    }
    
    func switchToLibrary() {
        selectedTab = .library
    }
}
