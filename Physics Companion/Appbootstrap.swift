//
//  Appbootstrap.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import Foundation

// MARK: - AppBootstrap
// Call `AppBootstrap.run(onProgress:)` once from your AppDelegate /
// @main App.init before presenting any UI that depends on Pythia or the DB.

@MainActor
enum AppBootstrap {

    struct BootstrapResult {
        let settings: SettingsStore
        let research: ResearchStore
    }

    /// Runs all startup checks in order:
    ///  1. Installs / updates Pythia libraries if needed.
    ///  2. Optionally verifies the C++ compiler is available.
    ///  3. Opens (and migrates) the settings database.
    ///
    /// - Parameter onProgress: Receives human-readable status strings suitable
    ///   for display in a splash / loading screen.
    static func run(onProgress: @escaping (String) -> Void) async throws -> BootstrapResult {

        // ── 1. Pythia ──────────────────────────────────────────────────────
        onProgress("Checking Pythia installation…")
        try PythiaInstaller.ensureReady(onProgress: onProgress)

        // ── 2. Compiler (non-fatal: warn but continue) ─────────────────────
        if CompilerTools.needsCompilerInstall() {
            onProgress("⚠️  Xcode Command Line Tools not found — simulations cannot be compiled.")
        }

        // ── 3. Settings DB ─────────────────────────────────────────────────
        onProgress("Opening settings database…")
        let settings = try await SettingsStore.connect()

        // ── 4. Research DB ─────────────────────────────────────────────────
        onProgress("Opening research database…")
        let research = try await ResearchStore.connect()

        // ── 5. Example Index ──────────────────────────────────────────────
        onProgress("Indexing Pythia examples…")
        await ExampleIndex.shared.warmUp()

        onProgress("Ready.")
        return BootstrapResult(settings: settings, research: research)
    }
}
