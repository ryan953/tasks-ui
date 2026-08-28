import DexKit
import LinearKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            DexSettings(store: model.dex)
                .tabItem { Label("Dex", systemImage: "checklist") }
            LinearSettings(store: model.linear, searchPath: model.dex.searchPath)
                .tabItem { Label("Linear", systemImage: "circle.grid.2x2") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DexSettings: View {
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
                if store.cliTooOld {
                    Label("This dex is older than 0.16. Run: npm install -g @zeeg/dex", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
                Text("Leave blank to use the store dex is configured for.")
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
    }

    private func apply() {
        Preferences.dexPath = dexPath.trimmingCharacters(in: .whitespaces)
        Preferences.storagePath = storagePath.trimmingCharacters(in: .whitespaces)
        Task { await store.reconfigure() }
    }
}

private struct LinearSettings: View {
    @Bindable var store: LinearStore
    let searchPath: String

    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private enum TestResult: Equatable {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                SecureField("Personal API key", text: $apiKey, prompt: Text(store.hasKey ? "Saved in your keychain" : "lin_api_…"))
                    .textFieldStyle(.roundedBorder)

                if let account = store.account {
                    LabeledContent("Connected as") {
                        Text("\(account.user.name) · \(account.organizationName)")
                            .foregroundStyle(.secondary)
                    }
                }

                if case let .cli(workspace) = store.keySource {
                    Label(
                        workspace.map { "Using the linear CLI's key for \($0)." }
                            ?? "Using the linear CLI's key.",
                        systemImage: "terminal"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                switch testResult {
                case let .success(message):
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case let .failure(message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                case nil:
                    EmptyView()
                }

                HStack {
                    if store.hasKey {
                        Button("Forget Saved Key", role: .destructive) {
                            Task {
                                _ = await store.setAPIKey("", searchPath: searchPath)
                                apiKey = ""
                                testResult = nil
                            }
                        }
                        .help("Remove the key from the keychain and fall back to the linear CLI's, if it has one")
                    }
                    Spacer()
                    Button(isTesting ? "Checking…" : "Save and Test") { saveAndTest() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTesting || (apiKey.isEmpty && !store.hasKey))
                }
            } header: {
                Text("Linear")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If the linear CLI is installed and logged in, its key is used automatically — nothing to set up. Otherwise create one at linear.app → Settings → Security & access → Personal API keys. A key you enter here is stored in your login keychain, never in preferences, and takes precedence over the CLI's.")
                    Link("Open Linear API settings", destination: URL(string: "https://linear.app/settings/account/security")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func saveAndTest() {
        isTesting = true
        testResult = nil
        Task {
            // An empty field with a key already saved means "test what is stored".
            let ok = apiKey.isEmpty
                ? await store.reload()
                : await store.setAPIKey(apiKey, searchPath: searchPath)
            isTesting = false
            if ok, let account = store.account {
                apiKey = ""
                testResult = .success(
                    "Connected to \(account.organizationName) — \(store.issues.count) issues, \(store.projects.count) projects."
                )
            } else {
                testResult = .failure(store.errorMessage ?? "Could not reach Linear.")
            }
        }
    }
}
