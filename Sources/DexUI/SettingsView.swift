import DexKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: TaskStore

    @State private var dexPath = Preferences.dexPath ?? ""
    @State private var storagePath = Preferences.storagePath ?? ""

    var body: some View {
        Form {
            Section {
                TextField("dex path", text: $dexPath, prompt: Text("Found automatically"))
                    .textFieldStyle(.roundedBorder)
                LabeledContent("Using") {
                    Text(store.resolvedBinary ?? "not found")
                        .font(.caption.monospaced())
                        .foregroundStyle(store.resolvedBinary == nil ? .red : .secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Executable")
            } footer: {
                Text("Leave blank to search your login shell's PATH. dex runs on Node, so the app asks your shell where things live rather than guessing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Storage path", text: $storagePath, prompt: Text("From ~/.config/dex/dex.toml"))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Task storage")
            } footer: {
                Text("Leave blank to use the store dex is configured for. Set it to work against a different collection of tasks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Apply") { apply() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func apply() {
        Preferences.dexPath = dexPath.trimmingCharacters(in: .whitespaces)
        Preferences.storagePath = storagePath.trimmingCharacters(in: .whitespaces)
        Task { await store.reconfigure() }
    }
}
