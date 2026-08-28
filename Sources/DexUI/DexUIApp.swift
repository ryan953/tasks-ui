import DexKit
import LinearKit
import SwiftUI

@main
struct DexUIApp: App {
    @State private var model = AppModel()
    @State private var isCreating = false

    var body: some Scene {
        WindowGroup("Tasks") {
            ContentView(model: model, isCreating: $isCreating)
                .frame(minWidth: 860, minHeight: 480)
                .task { await model.bootstrap() }
                // Registered for the `task` scheme in Info.plist, so
                // `task://dex/<id>` opens the app and selects that task.
                .onOpenURL { url in model.open(url) }
        }
        .defaultSize(width: 1120, height: 740)
        .commands { menuCommands }

        Settings {
            SettingsView(model: model)
        }
    }

    @CommandsBuilder
    private var menuCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") { isCreating = true }
                .keyboardShortcut("n")
                .disabled(model.source != .dex)
        }
        CommandGroup(after: .toolbar) {
            Picker("Source", selection: Binding(get: { model.source }, set: { model.source = $0 })) {
                ForEach(Source.allCases) { Text($0.label).tag($0) }
            }
            Button("Refresh") {
                Task {
                    switch model.source {
                    case .dex: await model.dex.reload()
                    case .linear: await model.linear.reload()
                    }
                }
            }
            .keyboardShortcut("r")
        }
    }
}
