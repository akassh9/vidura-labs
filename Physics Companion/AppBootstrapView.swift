import SwiftUI

struct AppBootstrapView: View {
    @EnvironmentObject private var appState: AppState

    @State private var progressMessage: String = "Preparing..."
    @State private var store: SettingsStore? = nil
    @State private var researchStore: ResearchStore? = nil
    @State private var orchestrator: OrchestratorService? = nil
    @State private var errorMessage: String? = nil
    @State private var showOnboarding: Bool = false
    @State private var didBootstrap: Bool = false
    @State private var showCLTAlert: Bool = false

    var body: some View {
        Group {
            if let store = store, let researchStore = researchStore, let orchestrator = orchestrator {
                ContentView()
                    .environmentObject(store)
                    .environmentObject(researchStore)
                    .environmentObject(orchestrator)
                    .onAppear { showOnboarding = store.requiresOnboarding }
                    .onReceive(store.$data) { _ in
                        showOnboarding = store.requiresOnboarding
                    }
                    .sheet(isPresented: $showOnboarding) {
                        OnboardingView()
                            .environmentObject(store)
                    }
            } else if errorMessage != nil {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Setup failed")
                        .font(.title2)
                        .bold()
                    Text(errorMessage ?? "Unknown error")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        errorMessage = nil
                        didBootstrap = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(progressMessage)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await bootstrap()
        }
        .alert("Xcode Command Line Tools Required", isPresented: $showCLTAlert) {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } message: {
            Text("Xcode Command Line Tools are not installed. The installer has been opened automatically.\n\nPlease complete the installation and restart the app.")
        }
    }

    @MainActor
    private func bootstrap() async {
        progressMessage = "Checking components..."

        // Check for Xcode Command Line Tools first
        if CompilerTools.needsCompilerInstall() {
            // Trigger the installer dialog
            try? CompilerTools.ensureCompiler()
            showCLTAlert = true
            return
        }

        do {
            try await Task.detached(priority: .userInitiated) {
                try await PythiaInstaller.ensureReady { msg in
                    Task { @MainActor in
                        self.progressMessage = msg
                    }
                }
            }.value

            let s = try await SettingsStore.connect()
            let r = try await ResearchStore.connect()
            let o = OrchestratorService(store: r, settingsStore: s)
            self.store = s
            self.researchStore = r
            self.orchestrator = o
            self.appState.settingsStore = s
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AppBootstrapView()
        .environmentObject(AppState())
}
