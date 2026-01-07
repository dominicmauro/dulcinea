import SwiftUI
import UIKit

struct ReaderView: View {
    let book: Book
    @EnvironmentObject var viewModel: ReaderViewModel
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var dragOffset: CGSize = .zero
    @State private var lastDragValue: DragGesture.Value?
    @State private var showingShareSheet = false

    var body: some View {
        ZStack {
            // Background color
            Color(hex: viewModel.backgroundColor.color.background)
                .ignoresSafeArea()

            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(errorMessage)
            } else {
                readerContent
            }

            // Reading menu overlay
            if viewModel.isMenuVisible {
                readerMenu
            }

            // Settings overlay
            if viewModel.isSettingsVisible {
                settingsOverlay
            }

            // Bookmarks overlay
            if viewModel.isBookmarksVisible {
                bookmarksOverlay
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let shareContent = viewModel.getShareContent() {
                ShareSheet(items: [shareContent])
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!viewModel.isMenuVisible)
        .onAppear {
            Task {
                await viewModel.loadBook(book)
            }
        }
        .onDisappear {
            viewModel.closeBook()
        }
        .gesture(
            TapGesture()
                .onEnded { _ in
                    viewModel.toggleMenu()
                }
        )
    }
    
    // MARK: - Reading Content
    
    private var readerContent: some View {
        GeometryReader { geometry in
            if !viewModel.chapters.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        chapterContent
                            .padding(.horizontal, viewModel.margin)
                            .padding(.vertical, 40)
                    }
                }
                .scrollPosition(id: .init(get: {
                    viewModel.currentPosition
                }, set: { newValue in
                    if let position = newValue {
                        viewModel.updatePosition(position)
                    }
                }))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            lastDragValue = value
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            handlePageTurn(value, geometry: geometry)
                            dragOffset = .zero
                            lastDragValue = nil
                        }
                )
            } else {
                emptyChapterView
            }
        }
    }
    
    private var chapterContent: some View {
        VStack(alignment: .leading, spacing: viewModel.lineSpacing * 10) {
            if !viewModel.chapters.isEmpty {
                let currentChapter = viewModel.chapters[viewModel.currentChapter]

                Text(currentChapter.title)
                    .font(viewModel.fontFamily == .systemDefault ? .system(size: viewModel.fontSize + 4) : .custom(viewModel.fontFamily.fontName, size: viewModel.fontSize + 4))
                    .fontWeight(.semibold)
                    .foregroundColor(Color(hex: viewModel.backgroundColor.color.text))
                    .padding(.bottom, 20)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Chapter title: \(currentChapter.title)")

                Text(currentChapter.content)
                    .font(viewModel.fontFamily == .systemDefault ? .system(size: viewModel.fontSize) : .custom(viewModel.fontFamily.fontName, size: viewModel.fontSize))
                    .lineSpacing(viewModel.lineSpacing * viewModel.fontSize * 0.2)
                    .foregroundColor(Color(hex: viewModel.backgroundColor.color.text))
                    .textSelection(.enabled)
                    .accessibilityLabel("Chapter content")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Tap anywhere to show reading controls. Swipe left or right to change chapters.")
    }
    
    private var emptyChapterView: some View {
        VStack {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No content available")
                .font(.headline)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Loading and Error States
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading \(book.title)...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
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
            
            Button("Close") {
                coordinator.dismissReader()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Reader Menu
    
    private var readerMenu: some View {
        VStack {
            // Top menu bar
            HStack {
                Button("Close") {
                    coordinator.dismissReader()
                }
                .foregroundColor(.white)
                .accessibilityLabel("Close book")
                .accessibilityHint("Returns to the library")

                Spacer()

                Text(book.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button("Settings") {
                    viewModel.showSettings()
                }
                .foregroundColor(.white)
                .accessibilityLabel("Reading settings")
                .accessibilityHint("Opens font, color, and spacing options")
            }
            .padding()
            .background(Color.black.opacity(0.8))

            Spacer()

            // Bottom controls
            VStack(spacing: 15) {
                // Progress bar
                VStack(spacing: 8) {
                    HStack {
                        Text("Chapter \(viewModel.currentChapter + 1) of \(viewModel.chapters.count)")
                            .font(.caption)
                            .foregroundColor(.white)

                        Spacer()

                        Text("\(Int(viewModel.readingProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Reading progress: Chapter \(viewModel.currentChapter + 1) of \(viewModel.chapters.count), \(Int(viewModel.readingProgress * 100)) percent complete")

                    ProgressView(value: viewModel.readingProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .accessibilityHidden(true)
                }

                // Navigation controls
                HStack(spacing: 30) {
                    Button(action: viewModel.goToPreviousChapter) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(viewModel.currentChapter > 0 ? .white : .gray)
                    }
                    .disabled(viewModel.currentChapter <= 0)
                    .accessibilityLabel("Previous chapter")
                    .accessibilityHint(viewModel.currentChapter > 0 ? "Go to chapter \(viewModel.currentChapter)" : "Already at first chapter")

                    Button("Contents") {
                        // Show table of contents
                    }
                    .foregroundColor(.white)
                    .accessibilityLabel("Table of contents")
                    .accessibilityHint("Shows chapter list")

                    Button(action: viewModel.goToNextChapter) {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundColor(viewModel.currentChapter < viewModel.chapters.count - 1 ? .white : .gray)
                    }
                    .disabled(viewModel.currentChapter >= viewModel.chapters.count - 1)
                    .accessibilityLabel("Next chapter")
                    .accessibilityHint(viewModel.currentChapter < viewModel.chapters.count - 1 ? "Go to chapter \(viewModel.currentChapter + 2)" : "Already at last chapter")
                }

                // Additional controls
                HStack(spacing: 40) {
                    Button(action: {
                        if viewModel.hasBookmarkAtCurrentPosition() {
                            viewModel.showBookmarks()
                        } else {
                            viewModel.addBookmark()
                        }
                    }) {
                        VStack {
                            Image(systemName: viewModel.hasBookmarkAtCurrentPosition() ? "bookmark.fill" : "bookmark")
                                .font(.title3)
                            Text("Bookmark")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                    .accessibilityLabel(viewModel.hasBookmarkAtCurrentPosition() ? "View bookmarks" : "Add bookmark")
                    .accessibilityHint(viewModel.hasBookmarkAtCurrentPosition() ? "Shows saved bookmarks" : "Saves current reading position")

                    Button(action: viewModel.toggleSpeech) {
                        VStack {
                            Image(systemName: viewModel.isSpeaking ? "speaker.slash" : "speaker.wave.2")
                                .font(.title3)
                            Text(viewModel.isSpeaking ? "Stop" : "Speak")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                    .accessibilityLabel(viewModel.isSpeaking ? "Stop speaking" : "Read aloud")
                    .accessibilityHint(viewModel.isSpeaking ? "Stops text-to-speech" : "Reads the chapter aloud")

                    Button(action: {
                        showingShareSheet = true
                    }) {
                        VStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                            Text("Share")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                    .accessibilityLabel("Share")
                    .accessibilityHint("Share an excerpt from the current chapter")
                }
            }
            .padding()
            .background(Color.black.opacity(0.8))
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isMenuVisible)
    }
    
    // MARK: - Settings Overlay
    
    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.hideSettings()
                }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Reading Settings")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Button("Done") {
                            viewModel.hideSettings()
                            viewModel.saveReadingSettings()
                        }
                        .fontWeight(.medium)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    Divider()
                    
                    ScrollView {
                        VStack(spacing: 25) {
                            fontSizeSection
                            fontFamilySection
                            colorThemeSection
                            spacingSection
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: 400)
                    
                    // Reset button
                    Button("Reset to Defaults") {
                        viewModel.resetSettings()
                    }
                    .foregroundColor(.red)
                    .padding(.bottom)
                }
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Settings Sections
    
    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Font Size")
                .font(.subheadline)
                .fontWeight(.medium)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Text("A")
                    .font(.caption)
                    .accessibilityHidden(true)

                Slider(value: $viewModel.fontSize, in: 10...30, step: 1)
                    .accessibilityLabel("Font size")
                    .accessibilityValue("\(Int(viewModel.fontSize)) points")

                Text("A")
                    .font(.title3)
                    .fontWeight(.bold)
                    .accessibilityHidden(true)
            }

            Text("Sample text at \(Int(viewModel.fontSize))pt")
                .font(viewModel.fontFamily == .systemDefault ? .system(size: viewModel.fontSize) : .custom(viewModel.fontFamily.fontName, size: viewModel.fontSize))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
    }
    
    private var fontFamilySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Font Family")
                .font(.subheadline)
                .fontWeight(.medium)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                ForEach(FontFamily.allCases, id: \.self) { font in
                    Button(action: {
                        viewModel.fontFamily = font
                    }) {
                        VStack {
                            Text("Aa")
                                .font(font == .systemDefault ? .system(size: 20) : .custom(font.fontName, size: 20))
                                .foregroundColor(viewModel.fontFamily == font ? .white : .primary)

                            Text(font.displayName)
                                .font(.caption)
                                .foregroundColor(viewModel.fontFamily == font ? .white : .secondary)
                        }
                        .frame(height: 60)
                        .frame(maxWidth: .infinity)
                        .background(viewModel.fontFamily == font ? Color.blue : Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .accessibilityLabel("\(font.displayName) font")
                    .accessibilityAddTraits(viewModel.fontFamily == font ? [.isSelected] : [])
                    .accessibilityHint(viewModel.fontFamily == font ? "Currently selected" : "Double tap to select")
                }
            }
        }
    }
    
    private var colorThemeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color Theme")
                .font(.subheadline)
                .fontWeight(.medium)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 10) {
                ForEach(BackgroundColor.allCases, id: \.self) { theme in
                    Button(action: {
                        viewModel.backgroundColor = theme
                    }) {
                        VStack {
                            Circle()
                                .fill(Color(hex: theme.color.background))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color(hex: theme.color.text), lineWidth: 2)
                                        .frame(width: 20, height: 20)
                                )

                            Text(theme.displayName)
                                .font(.caption)
                                .foregroundColor(viewModel.backgroundColor == theme ? .blue : .secondary)
                        }
                        .frame(height: 60)
                        .frame(maxWidth: .infinity)
                        .background(viewModel.backgroundColor == theme ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                    .accessibilityLabel("\(theme.displayName) theme")
                    .accessibilityAddTraits(viewModel.backgroundColor == theme ? [.isSelected] : [])
                    .accessibilityHint(viewModel.backgroundColor == theme ? "Currently selected" : "Double tap to select")
                }
            }
        }
    }
    
    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Line Spacing")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityAddTraits(.isHeader)

                HStack {
                    Image(systemName: "text.alignleft")
                        .font(.caption)
                        .accessibilityHidden(true)

                    Slider(value: $viewModel.lineSpacing, in: 1.0...2.0, step: 0.1)
                        .accessibilityLabel("Line spacing")
                        .accessibilityValue(String(format: "%.1fx", viewModel.lineSpacing))

                    Image(systemName: "text.alignleft")
                        .font(.caption)
                        .scaleEffect(1.5)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Margins")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .accessibilityAddTraits(.isHeader)

                HStack {
                    Text("Narrow")
                        .font(.caption)
                        .accessibilityHidden(true)

                    Slider(value: $viewModel.margin, in: 10...50, step: 5)
                        .accessibilityLabel("Page margins")
                        .accessibilityValue("\(Int(viewModel.margin)) points")

                    Text("Wide")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: - Bookmarks Overlay

    private var bookmarksOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.hideBookmarks()
                }

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Bookmarks")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .accessibilityAddTraits(.isHeader)

                        Spacer()

                        Button("Done") {
                            viewModel.hideBookmarks()
                        }
                        .fontWeight(.medium)
                        .accessibilityLabel("Close bookmarks")
                    }
                    .padding()

                    Divider()

                    if viewModel.bookmarks.isEmpty {
                        VStack(spacing: 15) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                                .accessibilityHidden(true)

                            Text("No Bookmarks")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Text("Tap the bookmark button while reading to save your place")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.vertical, 40)
                    } else {
                        List {
                            ForEach(viewModel.bookmarks) { bookmark in
                                Button(action: {
                                    viewModel.goToBookmark(bookmark)
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.chapterTitle)
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        if let note = bookmark.note {
                                            Text(note)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }

                                        Text(bookmark.dateCreated, style: .relative)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .accessibilityLabel("\(bookmark.chapterTitle), bookmarked \(bookmark.dateCreated, style: .relative)")
                                .accessibilityHint("Double tap to go to this bookmark")
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button("Delete", role: .destructive) {
                                        viewModel.removeBookmark(bookmark)
                                    }
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                        .frame(maxHeight: 300)
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(20)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Gesture Handling
    
    private func handlePageTurn(_ value: DragGesture.Value, geometry: GeometryProxy) {
        let horizontalThreshold: CGFloat = 50
        let verticalThreshold: CGFloat = 100
        
        // Horizontal swipe for chapter navigation
        if abs(value.translation.width) > horizontalThreshold && abs(value.translation.height) < verticalThreshold {
            if value.translation.width > 0 {
                // Swipe right - previous chapter
                viewModel.goToPreviousChapter()
            } else {
                // Swipe left - next chapter
                viewModel.goToNextChapter()
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ReaderView(book: Book(
        title: "Sample Book",
        author: "Sample Author",
        identifier: "sample-id",
        filePath: "/path/to/book.epub",
        fileSize: 1024000
    ))
    .environmentObject(ReaderViewModel(epubService: EPUBService(storageService: StorageService()), syncService: KOSyncService()))
    .environmentObject(AppCoordinator())
}
