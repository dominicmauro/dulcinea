import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showingImportSheet = false
    @State private var searchText = ""
    
    var filteredBooks: [Book] {
        if searchText.isEmpty {
            return viewModel.books
        } else {
            return viewModel.books.filter { book in
                book.title.localizedCaseInsensitiveContains(searchText) ||
                book.author.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.books.isEmpty {
                    EmptyLibraryView {
                        showingImportSheet = true
                    }
                } else {
                    booksList
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        showingImportSheet = true
                    }
                    .accessibilityLabel("Add books")
                    .accessibilityHint("Import EPUB files or browse catalogs")
                }
            }
            .searchable(text: $searchText, prompt: "Search books...")
            .sheet(isPresented: $showingImportSheet) {
                ImportBooksSheet { urls in
                    Task {
                        await viewModel.importEPUBFiles(from: urls)
                    }
                }
            }
            .refreshable {
                await viewModel.syncProgress()
            }
        }
    }
    
    private var booksList: some View {
        List {
            ForEach(filteredBooks) { book in
                BookRowView(book: book) {
                    coordinator.presentReader(for: book)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        viewModel.removeBook(book)
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

struct BookRowView: View {
    let book: Book
    let onTap: () -> Void

    private var accessibilityDescription: String {
        var description = "\(book.title) by \(book.author)"
        if book.progressPercentage > 0 {
            description += ", \(Int(book.progressPercentage * 100)) percent complete"
        }
        if book.needsSync {
            description += ", needs sync"
        }
        return description
    }

    var body: some View {
        HStack {
            // Cover image placeholder
            AsyncImage(url: book.coverImagePath.flatMap { URL(fileURLWithPath: $0) }) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "book.closed")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 60, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if book.progressPercentage > 0 {
                    ProgressView(value: book.progressPercentage)
                        .frame(height: 4)

                    Text("\(Int(book.progressPercentage * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(book.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if book.needsSync {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }

                    if let lastOpened = book.lastOpened {
                        Text(lastOpened, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to open book. Swipe left for delete option.")
        .accessibilityAddTraits(.isButton)
    }
}

struct EmptyLibraryView: View {
    let onAddBooks: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .accessibilityHidden(true)

            Text("No Books Yet")
                .font(.title2)
                .fontWeight(.medium)
                .accessibilityAddTraits(.isHeader)

            Text("Add books from OPDS catalogs or import your own EPUB files")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Add Books") {
                onAddBooks()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens options to import EPUB files or browse catalogs")
        }
        .padding()
    }
}

struct ImportBooksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingDocumentPicker = false
    var onImport: (([URL]) -> Void)?


    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 15) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                        .accessibilityHidden(true)

                    Text("Add Books")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(spacing: 15) {
                    Button("Import EPUB Files") {
                        showingDocumentPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Opens file picker to select EPUB files from your device")

                    Button("Browse Catalogs") {
                        // Switch to browse tab
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Go to the Browse tab to find free ebooks")
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Done")
                    .accessibilityHint("Closes the import sheet")
                }
            }
        }
        .fileImporter(
            isPresented: $showingDocumentPicker,
            allowedContentTypes: [.epub],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                onImport?(urls)
                dismiss()
            case .failure(let error):
                print("Import failed: \(error)")
            }
        }
    }
}

#Preview {
    let storageService = StorageService()
    let epubService = EPUBService(storageService: storageService)
    return LibraryView()
        .environmentObject(LibraryViewModel(storageService: storageService, epubService: epubService, syncService: KOSyncService()))
        .environmentObject(AppCoordinator())
}