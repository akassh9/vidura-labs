//
//  SettingsView.swift
//  Physics Companion
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    @State private var name: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSuccess: Bool = false

    var body: some View {
        Form {
            Section("Name") {
                TextField("", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .environment(\.layoutDirection, .rightToLeft)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else if showSuccess {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave || isSaving)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 200)
        .onAppear {
            name = settings.data.name
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        showSuccess = false
        Task { @MainActor in
            do {
                try await settings.update(name: name)
                isSaving = false
                showSuccess = true
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore.preview())
}
