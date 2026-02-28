import SwiftUI

struct BrowseView: View {
    @EnvironmentObject var viewModel: BrowseViewModel
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showingAddCatalog = false
    @State private var showingCatalogDetails = false
    @State private var selectedCatalogForEdit: OPDSCatalog?
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.selectedCatalog == nil {
                    catalogListView
                } else {
                    catalogBrowseView
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if viewModel.selectedCatalog == nil {
                        Button("Add") {
                            showingAddCatalog = true
                        }
                    } else {
                        Menu {
                            Button("Refresh") {
                                Task {
                                    await viewModel.refreshCurrentFeed()
                                }
                            }
                            
                            Button("Back to Catalogs") {
                                viewModel.goToRoot()
                                viewModel.selectedCatalog = nil
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddCatalog) {
                AddCatalogSheet { catalog in
                    viewModel.addCatalog(
                        name: catalog.name,
                        url: catalog.url,
                        username: catalog.username,
                        password: catalog.password
                    )
                }
            }
            .sheet(item: $selectedCatalogForEdit) { catalog in
                EditCatalogSheet(catalog: catalog) { updatedCatalog in
                    viewModel.storageService.updateCatalog(updatedCatalog)
                }
            }
        }
    }
    
    // MARK: - Catalog List View
    
    private var catalogListView: some View {
        VStack {
            if viewModel.catalogs.isEmpty {
                emptyCatalogsView
            } else {
                List {
                    ForEach(viewModel.catalogs) { catalog in
                        CatalogRowView(catalog: catalog) {
                            Task {
                                await viewModel.browseCatalog(catalog)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Edit") {
                                selectedCatalogForEdit = catalog
                            }
                            .tint(.blue)
                            
                            Button("Delete", role: .destructive) {
                                viewModel.removeCatalog(catalog)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(catalog.isEnabled ? "Disable" : "Enable") {
                                viewModel.toggleCatalogEnabled(catalog)
                            }
                            .tint(catalog.isEnabled ? .orange : .green)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
    
    private var emptyCatalogsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Catalogs")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Add OPDS catalogs to browse and download books from online libraries")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Add Catalog") {
                showingAddCatalog = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Catalog Browse View
    
    private var catalogBrowseView: some View {
        VStack(spacing: 0) {
            // Breadcrumb navigation
            if !viewModel.navigationStack.isEmpty {
                breadcrumbView
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
            }
            
            // Search bar
            if viewModel.selectedCatalog != nil {
                searchBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            
            // Content area
            ZStack {
                if viewModel.isLoading {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(errorMessage)
                } else {
                    contentGrid
                }
            }
        }
    }
    
    private var breadcrumbView: some View {
        HStack {
            Button(action: viewModel.goBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                    Text("Back")
                        .font(.caption)
                }
            }
            .disabled(viewModel.navigationStack.count <= 1)
            
            Spacer()
            
            Text(viewModel.currentBreadcrumb)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            if viewModel.hasActiveDownloads {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading")
                        .font(.caption)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search books...", text: $viewModel.searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: viewModel.clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .cornerRadius(10)
            
            Menu {
                Picker("Filter", selection: $viewModel.selectedFilter) {
                    ForEach(BrowseViewModel.FilterOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                
                Picker("Sort", selection: $viewModel.selectedSort) {
                    ForEach(BrowseViewModel.SortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                
                Button(viewModel.sortAscending ? "Sort Descending" : "Sort Ascending") {
                    viewModel.sortAscending.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.blue)
            }
        }
    }
    
    private var contentGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2),
                spacing: 16
            ) {
                ForEach(viewModel.filteredAndSortedEntries) { entry in
                    BookEntryView(
                        entry: entry,
                        downloadProgress: viewModel.getDownloadProgress(for: entry.id),
                        downloadStatus: viewModel.getDownloadStatus(for: entry.id),
                        isDownloaded: viewModel.isBookDownloaded(entry)
                    ) {
                        // Handle tap
                        Task {
                            await viewModel.navigateToEntry(entry)
                        }
                    } onDownload: {
                        // Handle download
                        Task {
                            await viewModel.downloadBook(entry)
                        }
                    } onCancel: {
                        // Handle cancel
                        viewModel.cancelDownload(entry.id)
                    }
                }
            }
            .padding()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading catalog...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                Task {
                    await viewModel.refreshCurrentFeed()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Catalog Row View

struct CatalogRowView: View {
    let catalog: OPDSCatalog
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(catalog.name)
                    .font(.headline)
                    .foregroundColor(catalog.isEnabled ? .primary : .secondary)
                
                Text(catalog.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack {
                    if catalog.requiresAuthentication {
                        Label("Authenticated", systemImage: "lock")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if let lastUpdated = catalog.lastUpdated {
                        Text("Updated \(lastUpdated, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if !catalog.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if catalog.isEnabled {
                onTap()
            }
        }
    }
}

// MARK: - Book Entry View

struct BookEntryView: View {
    let entry: OPDSEntry
    let downloadProgress: Double
    let downloadStatus: DownloadStatus
    let isDownloaded: Bool
    let onTap: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image
            AsyncImage(url: entry.coverImageLink.flatMap { URL(string: $0.href) }) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "book.closed")
                            .foregroundColor(.gray)
                            .font(.title2)
                    )
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Book info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(entry.authorNames)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let summary = entry.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Download button/status
            downloadButton
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onTapGesture {
            if entry.links.contains(where: { $0.isNavigation }) {
                onTap()
            }
        }
    }
    
    @ViewBuilder
    private var downloadButton: some View {
        switch downloadStatus {
        case .notStarted:
            if isDownloaded {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Downloaded")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            } else if entry.downloadLink != nil {
                Button("Download") {
                    onDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.caption)
            } else {
                Text("Not Available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .downloading(let progress):
            VStack(spacing: 4) {
                HStack {
                    Text("Downloading...")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .completed:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Complete")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
        case .failed(_):
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Failed")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                Button("Retry") {
                    onDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.caption)
            }
            
        case .paused:
            Button("Resume") {
                onDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.caption)
        }
    }
}

// MARK: - Add Catalog Sheet

struct AddCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var requiresAuth = false
    @State private var isValidating = false
    @State private var validationError: String?
    
    let onAdd: (OPDSCatalog) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("Catalog Information") {
                    TextField("Name", text: $name)
                    TextField("URL", text: $url)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                Section("Authentication") {
                    Toggle("Requires Authentication", isOn: $requiresAuth)
                    
                    if requiresAuth {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                        
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }
                
                Section("Popular Catalogs") {
                    Button("Project Gutenberg") {
                        name = "Project Gutenberg"
                        url = "https://www.gutenberg.org/ebooks.opds/"
                        requiresAuth = false
                        username = ""
                        password = ""
                    }
                    
                    Button("Internet Archive") {
                        name = "Internet Archive"
                        url = "https://archive.org/services/opds"
                        requiresAuth = false
                        username = ""
                        password = ""
                    }
                    
                    Button("Standard Ebooks") {
                        name = "Standard Ebooks"
                        url = "https://standardebooks.org/feeds/opds"
                        requiresAuth = false
                        username = ""
                        password = ""
                    }
                }
                
                if let validationError = validationError {
                    Section {
                        Text(validationError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addCatalog()
                    }
                    .disabled(name.isEmpty || url.isEmpty || isValidating)
                }
            }
        }
    }
    
    private func addCatalog() {
        isValidating = true
        validationError = nil
        
        let catalog = OPDSCatalog(
            name: name,
            url: url,
            username: requiresAuth ? username : nil,
            password: requiresAuth ? password : nil
        )
        
        // In a real implementation, you would validate the catalog here
        // For now, we'll just add it
        onAdd(catalog)
        dismiss()
    }
}

// MARK: - Edit Catalog Sheet

struct EditCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var url: String
    @State private var username: String
    @State private var password: String
    @State private var requiresAuth: Bool
    
    let catalog: OPDSCatalog
    let onSave: (OPDSCatalog) -> Void
    
    init(catalog: OPDSCatalog, onSave: @escaping (OPDSCatalog) -> Void) {
        self.catalog = catalog
        self.onSave = onSave
        self._name = State(initialValue: catalog.name)
        self._url = State(initialValue: catalog.url)
        self._username = State(initialValue: catalog.username ?? "")
        self._password = State(initialValue: catalog.password ?? "")
        self._requiresAuth = State(initialValue: catalog.requiresAuthentication)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Catalog Information") {
                    TextField("Name", text: $name)
                    TextField("URL", text: $url)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                Section("Authentication") {
                    Toggle("Requires Authentication", isOn: $requiresAuth)
                    
                    if requiresAuth {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .autocapitalization(.none)
                        
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }
            }
            .navigationTitle("Edit Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCatalog()
                    }
                    .disabled(name.isEmpty || url.isEmpty)
                }
            }
        }
    }
    
    private func saveCatalog() {
        let updatedCatalog = OPDSCatalog(
            name: name,
            url: url,
            username: requiresAuth ? username : nil,
            password: requiresAuth ? password : nil
        )
        
        onSave(updatedCatalog)
        dismiss()
    }
}

#Preview {
    BrowseView()
        .environmentObject(BrowseViewModel(
            opdsService: OPDSService(storageService: StorageService()),
            storageService: StorageService()
        ))
        .environmentObject(AppCoordinator())
}
