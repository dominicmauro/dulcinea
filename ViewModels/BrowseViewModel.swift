import Foundation
import Combine

@MainActor
class BrowseViewModel: ObservableObject {
    @Published var catalogs: [OPDSCatalog] = []
    @Published var currentFeed: OPDSFeed?
    @Published var currentEntries: [OPDSEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var downloadTasks: [String: DownloadTask] = [:]
    
    // Navigation state
    @Published var navigationStack: [NavigationState] = []
    @Published var selectedCatalog: OPDSCatalog?
    
    private let opdsService: OPDSService
    let storageService: StorageService
    private var cancellables = Set<AnyCancellable>()
    
    init(opdsService: OPDSService, storageService: StorageService) {
        self.opdsService = opdsService
        self.storageService = storageService
        
        setupBindings()
        loadCatalogs()
    }
    
    private func setupBindings() {
        // Listen to storage service for catalog updates
        storageService.$catalogs
            .receive(on: DispatchQueue.main)
            .assign(to: \.catalogs, on: self)
            .store(in: &cancellables)
        
        // Debounced search
        $searchQuery
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                if !query.isEmpty {
                    Task {
                        await self?.performSearch(query)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Catalog Management
    
    private func loadCatalogs() {
        catalogs = storageService.catalogs
    }
    
    func addCatalog(name: String, url: String, username: String? = nil, password: String? = nil) {
        let catalog = OPDSCatalog(name: name, url: url, username: username, password: password)
        storageService.addCatalog(catalog)
    }
    
    func removeCatalog(_ catalog: OPDSCatalog) {
        storageService.removeCatalog(catalog)
        
        // Clear current feed if it's from the removed catalog
        if selectedCatalog?.id == catalog.id {
            selectedCatalog = nil
            currentFeed = nil
            currentEntries = []
            navigationStack = []
        }
    }
    
    func toggleCatalogEnabled(_ catalog: OPDSCatalog) {
        var updatedCatalog = catalog
        updatedCatalog = OPDSCatalog(
            name: updatedCatalog.name,
            url: updatedCatalog.url,
            username: updatedCatalog.username,
            password: updatedCatalog.password
        )
        storageService.updateCatalog(updatedCatalog)
    }
    
    // MARK: - Feed Navigation
    
    func browseCatalog(_ catalog: OPDSCatalog) async {
        selectedCatalog = catalog
        await loadFeed(from: catalog.url, title: catalog.name)
    }
    
    func loadFeed(from url: String, title: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let feed = try await opdsService.fetchFeed(from: url, catalog: selectedCatalog)
            
            currentFeed = feed
            currentEntries = feed.entries
            
            // Add to navigation stack
            let state = NavigationState(title: title, url: url, entries: feed.entries)
            navigationStack.append(state)
            
        } catch let opdsError as OPDSError {
            errorMessage = opdsError.localizedDescription
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func navigateToEntry(_ entry: OPDSEntry) async {
        // Check if entry has navigation links (subcategories)
        if let navLink = entry.links.first(where: { $0.isNavigation }) {
            await loadFeed(from: navLink.href, title: entry.title)
        }
    }
    
    func goBack() {
        guard navigationStack.count > 1 else {
            // Go back to catalog list
            selectedCatalog = nil
            currentFeed = nil
            currentEntries = []
            navigationStack = []
            return
        }
        
        navigationStack.removeLast()
        
        if let previousState = navigationStack.last {
            currentEntries = previousState.entries
            // Optionally reload the feed to get fresh data
        }
    }
    
    func goToRoot() {
        selectedCatalog = nil
        currentFeed = nil
        currentEntries = []
        navigationStack = []
        errorMessage = nil
    }
    
    // MARK: - Search
    
    func performSearch(_ query: String) async {
        guard let catalog = selectedCatalog,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let searchResults = try await opdsService.searchCatalog(catalog, query: query)
            currentEntries = searchResults
            
            // Add search state to navigation
            let searchState = NavigationState(
                title: "Search: \(query)",
                url: "",
                entries: searchResults
            )
            
            // Replace the last item if it's also a search, otherwise add new
            if let lastState = navigationStack.last, lastState.title.hasPrefix("Search:") {
                navigationStack[navigationStack.count - 1] = searchState
            } else {
                navigationStack.append(searchState)
            }
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func clearSearch() {
        searchQuery = ""
        
        // Remove search results from navigation
        if let lastState = navigationStack.last, lastState.title.hasPrefix("Search:") {
            navigationStack.removeLast()
            
            if let previousState = navigationStack.last {
                currentEntries = previousState.entries
            }
        }
    }
    
    private func sortEntries(_ entries: [OPDSEntry], by sort: SortOption, ascending: Bool) -> [OPDSEntry] {
        let sorted = entries.sorted { lhs, rhs in
            let result: Bool
            switch sort {
            case .title:
                result = lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .author:
                result = lhs.authorNames.localizedCaseInsensitiveCompare(rhs.authorNames) == .orderedAscending
            case .published:
                let lhsDate = lhs.published ?? Date.distantPast
                let rhsDate = rhs.published ?? Date.distantPast
                result = lhsDate < rhsDate
            case .popular:
                // For now, just sort by title since we don't have popularity data
                result = lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return ascending ? result : !result
        }
        return sorted
    }
    
    // MARK: - Utility Methods
    
    func refreshCurrentFeed() async {
        guard let lastState = navigationStack.last else { return }
        
        if !lastState.url.isEmpty {
            await loadFeed(from: lastState.url, title: lastState.title)
        }
    }
    
    func getDownloadProgress(for entryId: String) -> Double {
        return downloadTasks[entryId]?.progress ?? 0.0
    }
    
    func getDownloadStatus(for entryId: String) -> DownloadStatus {
        return downloadTasks[entryId]?.status ?? .notStarted
    }
    
    var hasActiveDownloads: Bool {
        downloadTasks.values.contains { task in
            switch task.status {
            case .downloading:
                return true
            default:
                return false
            }
        }
    }
    
    var currentBreadcrumb: String {
        navigationStack.map { $0.title }.joined(separator: " > ")
    }
    
    
    // MARK: - Navigation State
    
    struct NavigationState {
        let title: String
        let url: String
        let entries: [OPDSEntry]
    }
    
    // MARK: - Download Management
    
    func downloadBook(_ entry: OPDSEntry) async {
        guard let downloadLink = entry.downloadLink else {
            errorMessage = "No download link available for this book"
            return
        }
        
        // Create download task
        var task = DownloadTask(entry: entry)
        task.status = .downloading(progress: 0.0)
        downloadTasks[entry.id] = task
        
        do {
            let (localURL, book) = try await opdsService.downloadBook(
                from: downloadLink.href,
                entry: entry,
                catalog: selectedCatalog
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(entryId: entry.id, progress: progress)
                }
            }
            
            // Update task status
            downloadTasks[entry.id]?.status = .completed
            downloadTasks[entry.id]?.localURL = localURL
            
            // Add book to library
            storageService.addBook(book)
            
            // Remove task after successful completion
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.downloadTasks.removeValue(forKey: entry.id)
            }
            
        } catch {
            downloadTasks[entry.id]?.status = .failed(error: error)
            errorMessage = "Failed to download \(entry.title): \(error.localizedDescription)"
        }
    }
    
    func cancelDownload(_ entryId: String) {
        downloadTasks[entryId]?.status = .paused
        opdsService.cancelDownload(entryId: entryId)
    }
    
    func retryDownload(_ entry: OPDSEntry) async {
        await downloadBook(entry)
    }
    
    private func updateDownloadProgress(entryId: String, progress: Double) {
        downloadTasks[entryId]?.status = .downloading(progress: progress)
    }
    
    func isBookDownloaded(_ entry: OPDSEntry) -> Bool {
        return storageService.books.contains { book in
            book.identifier == entry.id || book.title == entry.title
        }
    }
    
    // MARK: - Filtering and Sorting
    
    enum FilterOption: CaseIterable {
        case all, books, audiobooks, magazines
        
        var displayName: String {
            switch self {
            case .all: return "All"
            case .books: return "Books"
            case .audiobooks: return "Audiobooks"
            case .magazines: return "Magazines"
            }
        }
    }
    
    enum SortOption: CaseIterable {
        case title, author, published, popular
        
        var displayName: String {
            switch self {
            case .title: return "Title"
            case .author: return "Author"
            case .published: return "Published"
            case .popular: return "Popular"
            }
        }
    }
    
    @Published var selectedFilter: FilterOption = .all
    @Published var selectedSort: SortOption = .title
    @Published var sortAscending = true
    
    var filteredAndSortedEntries: [OPDSEntry] {
        let filtered = filterEntries(currentEntries, by: selectedFilter)
        return sortEntries(filtered, by: selectedSort, ascending: sortAscending)
    }
    
    private func filterEntries(_ entries: [OPDSEntry], by filter: FilterOption) -> [OPDSEntry] {
        switch filter {
        case .all:
            return entries
        case .books:
            return entries.filter { entry in
                entry.links.contains { link in
                    link.type?.contains("epub") == true ||
                    link.type?.contains("pdf") == true
                }
            }
        case .audiobooks:
            return entries.filter { entry in
                entry.links.contains { link in
                    link.type?.contains("audio") == true
                }
            }
        case .magazines:
            return entries.filter { entry in
                entry.categories?.contains { category in
                    category.term.lowercased().contains("magazine") ||
                    category.term.lowercased().contains("periodical")
                } == true
            }
        }
    }
}
