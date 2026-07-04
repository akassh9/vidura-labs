//
//  Physics_CompanionApp.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import SwiftUI
import SwiftData
import Combine

@main
struct Physics_CompanionApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .environmentObject(appState)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            if let store = appState.settingsStore {
                SettingsView()
                    .environmentObject(store)
            } else {
                Text("Settings are not available until the app finishes loading.")
                    .padding()
                    .frame(width: 300, height: 100)
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var settingsStore: SettingsStore?
}
