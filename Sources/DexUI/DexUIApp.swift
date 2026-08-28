import DexKit
import SwiftUI

@main
struct DexUIApp: App {
    @State private var store = TaskStore()
    @State private var isCreating = false

    var body: some Scene {
        WindowGroup("Dex Tasks") {
            ContentView(store: store, isCreating: $isCreating)
                .frame(minWidth: 820, minHeight: 480)
                .task { await store.bootstrap() }
        }
        .defaultSize(width: 1080, height: 720)
        .commands { menuCommands }

        Settings {
            SettingsView(store: store)
        }
    }

    @CommandsBuilder
    private var menuCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { isCreating = true }
                .keyboardShortcut("n")
        }
        CommandGroup(after: .toolbar) {
            Button("Refresh") { Task { await store.reload() } }
                .keyboardShortcut("r")
            Divider()
            Picker("Show", selection: Binding(get: { store.filter }, set: { store.filter = $0 })) {
                ForEach(StatusFilter.allCases) { Text($0.label).tag($0) }
            }
            Picker("Sort By", selection: Binding(get: { store.sort }, set: { store.sort = $0 })) {
                ForEach(SortField.allCases) { Text($0.label).tag($0) }
            }
        }
    }
}
