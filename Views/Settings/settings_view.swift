import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel(
        storageService: StorageService(),
        syncService: KOSyncService()
    )
    @State private var showingSyncConfig = false
    @State private var showingAbout = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var exportURL: URL?
    
    var body: some View {
        NavigationView {
            Form {
                syncSection
                readingDefaultsSection
                appSettingsSection
                storageSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingSyncConfig) {
                SyncConfigurationSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showingAbout) {
                AboutSheet(viewModel: viewModel)
            }
            .alert("Export Complete", isPresented: .constant(exportURL != nil)) {
                Button("Share") {
                    if let url = exportURL {
                        shareExportFile(url)
                    }
                }
                Button("OK") {
                    exportURL = nil
                }
            } message: {
                Text("Library exported successfully")
            }
            .fileImporter(
                isPresented: $showingImportSheet,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task {
                            await viewModel.importLibrary(from: url)
                        }
                    }
                case .failure(let error):
                    viewModel.errorMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Sync Section
    
    private var syncSection: some View {
        Section("Sync") {
            HStack {
                Label("KOSync Server", systemImage: "arrow.triangle.2.circlepath")
                
                Spacer()
                
                if viewModel.syncConfiguration != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Configured")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        Text(viewModel.syncStatus.displayText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Not Configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showingSyncConfig = true
            }
            
            if viewModel.syncConfiguration != nil {
                Button("Sync All Books") {
                    Task {
                        await viewModel.forceSyncAll()
                    }
                }
                .disabled(viewModel.isSyncing)
                
                if viewModel.isSyncing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Syncing...")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Reading Defaults Section
    
    private var readingDefaultsSection: some View {
        Section("Reading Defaults") {
            NavigationLink(destination: ReadingDefaultsView(viewModel: viewModel)) {
                Label("Font & Display", systemImage: "textformat")
            }
            
            HStack {
                Label("Font Size", systemImage: "textformat.size")
                Spacer()
                Text("\(Int(viewModel.defaultReadingSettings.fontSize))pt")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Font Family", systemImage: "textformat")
                Spacer()
                Text(viewModel.defaultReadingSettings.fontFamily.displayName)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Color Theme", systemImage: "paintpalette")
                Spacer()
                Text(viewModel.defaultReadingSettings.backgroundColor.displayName)
                    .foregroundColor(.secondary)
            }
            
            Button("Reset to Defaults") {
                viewModel.resetDefaultReadingSettings()
            }
            .foregroundColor(.red)
        }
    }
    
    // MARK: - App Settings Section
    
    private var appSettingsSection: some View {
        Section("Download & Storage") {
            Toggle("Download Only on Wi-Fi", isOn: $viewModel.downloadOnlyOnWiFi)
                .onChange(of: viewModel.downloadOnlyOnWiFi) {
                    viewModel.saveAppSettings()
                }
            
            Toggle("Show Reading Progress", isOn: $viewModel.showReadingProgress)
                .onChange(of: viewModel.showReadingProgress) {
                    viewModel.saveAppSettings()
                }
            
            Toggle("Automatic Backup", isOn: $viewModel.automaticBackup)
                .onChange(of: viewModel.automaticBackup) {
                    viewModel.saveAppSettings()
                }
            
            Toggle("Delete After Reading", isOn: $viewModel.deleteAfterReading)
                .onChange(of: viewModel.deleteAfterReading) {
                    viewModel.saveAppSettings()
                }
        }
    }
    
    // MARK: - Storage Section
    
    private var storageSection: some View {
        Section("Storage") {
            HStack {
                Label("Books", systemImage: "books.vertical")
                Spacer()
                Text("\(viewModel.storageInfo.bookCount)")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Used Space", systemImage: "internaldrive")
                Spacer()
                Text(viewModel.storageInfo.formattedUsedSpace)
                    .foregroundColor(.secondary)
            }
            
            if viewModel.storageInfo.totalSpace > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Storage Usage")
                        Spacer()
                        Text("\(Int(viewModel.storageInfo.usagePercentage * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: viewModel.storageInfo.usagePercentage)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
            
            Button("Clear Cache") {
                Task {
                    await viewModel.clearCache()
                }
            }
            
            Button("Export Library") {
                Task {
                    exportURL = await viewModel.exportLibrary()
                }
            }
            
            Button("Import Library") {
                showingImportSheet = true
            }
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Build", systemImage: "hammer")
                Spacer()
                Text(viewModel.buildNumber)
                    .foregroundColor(.secondary)
            }
            
            Button("About Dulcinea") {
                showingAbout = true
            }
            
            Link("Support", destination: URL(string: "mailto:support@dulcinea.app")!)
            
            Link("Privacy Policy", destination: URL(string: "https://dulcinea.app/privacy")!)
        }
    }
    
    // MARK: - Helper Methods
    
    private func shareExportFile(_ url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

// MARK: - Sync Configuration Sheet

struct SyncConfigurationSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            Form {
                if viewModel.syncConfiguration != nil {
                    configuredSection
                } else {
                    setupSection
                }
                
                helpSection
            }
            .navigationTitle("KOSync Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Remove Sync Configuration", isPresented: $showingDeleteConfirmation) {
                Button("Remove", role: .destructive) {
                    viewModel.removeSyncConfiguration()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove your sync configuration and stop syncing progress. Your local reading progress will not be affected.")
            }
        }
    }
    
    private var configuredSection: some View {
        Section("Current Configuration") {
            HStack {
                Text("Server")
                Spacer()
                Text(viewModel.serverURL)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            HStack {
                Text("Username")
                Spacer()
                Text(viewModel.username)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Device")
                Spacer()
                Text(viewModel.deviceName)
                    .foregroundColor(.secondary)
            }
            
            Toggle("Auto Sync", isOn: $viewModel.autoSync)
                .onChange(of: viewModel.autoSync) {
                    if let config = viewModel.syncConfiguration {
                        viewModel.saveSyncConfiguration(config)
                    }
                }
            
            if viewModel.autoSync {
                Picker("Sync Interval", selection: $viewModel.syncInterval) {
                    ForEach(SyncInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .onChange(of: viewModel.syncInterval) {
                    if let config = viewModel.syncConfiguration {
                        viewModel.saveSyncConfiguration(config)
                    }
                }
            }
            
            HStack {
                Text("Status")
                Spacer()
                Text(viewModel.syncStatus.displayText)
                    .foregroundColor(
                        viewModel.isSyncing ? .blue :
                        viewModel.syncStatus.displayText.contains("Error") ? .red : .green
                    )
            }
            
            Button("Test Connection") {
                Task {
                    if viewModel.syncConfiguration != nil {
                        await viewModel.testSyncConnection()
                    }
                }
            }
            .disabled(viewModel.isConfiguringSyncServer)
            
            Button("Remove Configuration") {
                showingDeleteConfirmation = true
            }
            .foregroundColor(.red)
        }
    }
    
    private var setupSection: some View {
        Section("Setup KOSync") {
            TextField("Server URL", text: $viewModel.serverURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocapitalization(.none)
            
            TextField("Username", text: $viewModel.username)
                .textContentType(.username)
                .autocapitalization(.none)
            
            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
            
            TextField("Device Name", text: $viewModel.deviceName)
            
            Toggle("Auto Sync", isOn: $viewModel.autoSync)
            
            if viewModel.autoSync {
                Picker("Sync Interval", selection: $viewModel.syncInterval) {
                    ForEach(SyncInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
            }
            
            Button("Test & Save") {
                Task {
                    await viewModel.testSyncConnection()
                }
            }
            .disabled(
                viewModel.serverURL.isEmpty ||
                viewModel.username.isEmpty ||
                viewModel.password.isEmpty ||
                viewModel.isConfiguringSyncServer
            )
            
            if viewModel.isConfiguringSyncServer {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Testing connection...")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var helpSection: some View {
        Section("About KOSync") {
            VStack(alignment: .leading, spacing: 8) {
                Text("KOSync allows you to synchronize your reading progress across devices using a KOReader-compatible sync server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("You can set up your own server or use a compatible service. Your reading progress will be automatically synced when you finish reading sessions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Link("Learn More", destination: URL(string: "https://github.com/koreader/koreader/wiki/KOSync")!)
        }
    }
}

// MARK: - Reading Defaults View

struct ReadingDefaultsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section("Font Settings") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Font Size")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("A")
                            .font(.caption)
                        
                        Slider(value: $viewModel.defaultReadingSettings.fontSize, in: 10...30, step: 1)
                            .onChange(of: viewModel.defaultReadingSettings.fontSize) {
                                viewModel.saveDefaultReadingSettings()
                            }
                        
                        Text("A")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    Text("Sample text at \(Int(viewModel.defaultReadingSettings.fontSize))pt")
                        .font(viewModel.defaultReadingSettings.fontFamily == .systemDefault ? .system(size: viewModel.defaultReadingSettings.fontSize) : .custom(viewModel.defaultReadingSettings.fontFamily.fontName, size: viewModel.defaultReadingSettings.fontSize))
                        .foregroundColor(.secondary)
                }
                
                Picker("Font Family", selection: $viewModel.defaultReadingSettings.fontFamily) {
                    ForEach(FontFamily.allCases, id: \.self) { font in
                        Text(font.displayName).tag(font)
                    }
                }
                .onChange(of: viewModel.defaultReadingSettings.fontFamily) {
                    viewModel.saveDefaultReadingSettings()
                }
            }
            
            Section("Appearance") {
                Picker("Color Theme", selection: $viewModel.defaultReadingSettings.backgroundColor) {
                    ForEach(BackgroundColor.allCases, id: \.self) { color in
                        Text(color.displayName).tag(color)
                    }
                }
                .onChange(of: viewModel.defaultReadingSettings.backgroundColor) {
                    viewModel.saveDefaultReadingSettings()
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Line Spacing")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Image(systemName: "text.alignleft")
                            .font(.caption)
                        
                        Slider(value: $viewModel.defaultReadingSettings.lineSpacing, in: 1.0...2.0, step: 0.1)
                            .onChange(of: viewModel.defaultReadingSettings.lineSpacing) {
                                viewModel.saveDefaultReadingSettings()
                            }
                        
                        Image(systemName: "text.alignleft")
                            .font(.caption)
                            .scaleEffect(1.5)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Margins")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("Narrow")
                            .font(.caption)
                        
                        Slider(value: $viewModel.defaultReadingSettings.margin, in: 10...50, step: 5)
                            .onChange(of: viewModel.defaultReadingSettings.margin) {
                                viewModel.saveDefaultReadingSettings()
                            }
                        
                        Text("Wide")
                            .font(.caption)
                    }
                }
            }
            
            Section {
                Button("Reset to Defaults") {
                    viewModel.resetDefaultReadingSettings()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Reading Defaults")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About Sheet

struct AboutSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 15) {
                    Image(systemName: "book.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Dulcinea")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("EPUB Reader")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 10) {
                    Text("Version \(viewModel.appVersion)")
                        .font(.headline)
                    
                    Text("Build \(viewModel.buildNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Running on \(viewModel.deviceInfo)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("A modern EPUB reader with OPDS catalog support and cross-device sync capabilities. Named after the impossible dream from Don Quixote.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 15) {
                    Link("Website", destination: URL(string: "https://dulcinea.app")!)
                        .buttonStyle(.borderedProminent)
                    
                    Link("GitHub", destination: URL(string: "https://github.com/yourusername/dulcinea")!)
                        .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - TextField Placeholder Extension

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    SettingsView()
}
