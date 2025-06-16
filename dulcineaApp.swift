import SwiftUI

@main
struct EPUBReaderApp: App {
    @StateObject private var appCoordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appCoordinator)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            LibraryView()
                .environmentObject(coordinator.libraryViewModel)
                .tabItem {
                    Image(systemName: "books.vertical")
                    Text("Library")
                }
                .tag(AppCoordinator.Tab.library)
            
            BrowseView()
                .environmentObject(coordinator.browseViewModel)
                .tabItem {
                    Image(systemName: "globe")
                    Text("Browse")
                }
                .tag(AppCoordinator.Tab.browse)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(AppCoordinator.Tab.settings)
        }
        .sheet(item: $coordinator.presentedBook) { book in
            ReaderView(book: book)
                .environmentObject(coordinator.readerViewModel)
        }
    }
}
