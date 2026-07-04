//
//  ContentView.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var researchStore: ResearchStore
    @EnvironmentObject private var orchestrator: OrchestratorService

    @State private var selectedThreadId: String? = nil
    @State private var initialProjectId: String? = nil

    var body: some View {
        NavigationSplitView {
            ResearchSidebarView(selectedThreadId: $selectedThreadId, initialProjectId: $initialProjectId)
        } detail: {
            if let threadId = selectedThreadId {
                ResearchThreadDetailView(threadId: threadId, selectedThreadId: $selectedThreadId)
            } else {
                WelcomeDetailView(selectedThreadId: $selectedThreadId, initialProjectId: initialProjectId)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ModelSelectorDropdown(selectedModel: $orchestrator.selectedModel)
            }
        }
    }
}

// MARK: - Model Selector Dropdown

struct ModelSelectorDropdown: View {
    @Binding var selectedModel: AIModel

    var body: some View {
        Menu {
            ForEach(AIModel.allCases) { model in
                Button {
                    selectedModel = model
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            Text(model.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model == selectedModel {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                Text(selectedModel.displayName)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

#Preview {
    let settings = SettingsStore.preview()
    let store = ResearchStore.preview()
    ContentView()
        .environmentObject(settings)
        .environmentObject(store)
        .environmentObject(OrchestratorService(store: store, settingsStore: settings))
}
