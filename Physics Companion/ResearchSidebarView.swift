//
//  ResearchSidebarView.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import SwiftUI

struct ResearchSidebarView: View {
    @EnvironmentObject private var store: ResearchStore

    @State private var isCreatingProject = false
    @State private var newProjectTitle = ""

    @Binding var selectedThreadId: String?
    @Binding var initialProjectId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                newThreadButton
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                sectionHeader
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                if store.projects.isEmpty {
                    Text("No projects yet")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                } else {
                    projectsList
                }
            }
        }
        .frame(minWidth: 220, idealWidth: 260)
        .toolbar {
            ToolbarItem {
                Button {
                    isCreatingProject = true
                    newProjectTitle = ""
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .alert("New Project", isPresented: $isCreatingProject) {
            newProjectAlertContent
        } message: {
            Text("Enter a name for the new research project.")
        }
        .task {
            try? await store.loadAllProjectsAndThreads()
        }
    }

    // MARK: - Subviews

    private var newThreadButton: some View {
        Button {
            navigateToNewThread()
        } label: {
            Label("New thread", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var sectionHeader: some View {
        HStack {
            Text("Projects")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            Button {
                isCreatingProject = true
                newProjectTitle = ""
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var projectsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.projects) { project in
                ProjectGroupView(
                    project: project,
                    threads: store.threads(forProject: project.id),
                    selectedThreadId: $selectedThreadId,
                    onAddThread: { [project] in
                        navigateToNewThread(projectId: project.id)
                    },
                    onDeleteProject: { [project] in
                        deleteProject(project)
                    },
                    onDeleteThread: { thread in
                        deleteThread(thread)
                    }
                )
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Alert Content

    @ViewBuilder
    private var newProjectAlertContent: some View {
        TextField("Project title", text: $newProjectTitle)
        Button("Cancel", role: .cancel) { }
        Button("Create") { createProject() }
    }

    // MARK: - Actions

    private func createProject() {
        let title = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            if let project = try? await store.createProject(title: title) {
                initialProjectId = project.id
                selectedThreadId = nil
            }
        }
    }

    private func navigateToNewThread(projectId: String? = nil) {
        // Resolve the target project: explicit > current thread's project > first project
        let targetProjectId: String? = projectId ?? {
            if let selectedThreadId,
               let thread = store.threads.first(where: { $0.id == selectedThreadId }) {
                return thread.projectId
            }
            return store.projects.first?.id
        }()

        if let targetProjectId {
            initialProjectId = targetProjectId
            selectedThreadId = nil
        } else {
            isCreatingProject = true
            newProjectTitle = ""
        }
    }

    private func deleteProject(_ project: ResearchProject) {
        Task {
            let threadsInProject = store.threads(forProject: project.id)
            if let sel = selectedThreadId,
               threadsInProject.contains(where: { $0.id == sel }) {
                selectedThreadId = nil
            }
            try? await store.deleteProject(id: project.id)
        }
    }

    private func deleteThread(_ thread: ResearchThread) {
        Task {
            if selectedThreadId == thread.id { selectedThreadId = nil }
            try? await store.deleteThread(id: thread.id)
        }
    }
}

// MARK: - Project Group

private struct ProjectGroupView: View {
    let project: ResearchProject
    let threads: [ResearchThread]
    @Binding var selectedThreadId: String?
    let onAddThread: @MainActor () -> Void
    let onDeleteProject: @MainActor () -> Void
    let onDeleteThread: @MainActor (ResearchThread) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            projectRow
            if isExpanded {
                threadsList
            }
        }
    }

    private var projectRow: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text(project.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button("Delete Project", role: .destructive) { onDeleteProject() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { onAddThread() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var threadsList: some View {
        if threads.isEmpty {
            Text("No threads")
                .foregroundStyle(.tertiary)
                .font(.caption)
                .padding(.leading, 36)
                .padding(.vertical, 2)
        } else {
            ForEach(threads) { thread in
                ThreadRowView(
                    thread: thread,
                    isSelected: selectedThreadId == thread.id,
                    onSelect: { selectedThreadId = thread.id },
                    onDelete: { onDeleteThread(thread) }
                )
            }
        }
    }
}

// MARK: - Thread Row

private struct ThreadRowView: View {
    let thread: ResearchThread
    let isSelected: Bool
    let onSelect: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    var body: some View {
        Button { onSelect() } label: {
            HStack {
                Text(thread.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(relativeTime(from: thread.updatedAt))
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .padding(.leading, 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete Thread", role: .destructive) { onDelete() }
        }
    }

    private func relativeTime(from isoString: String) -> String {
        guard !isoString.isEmpty else { return "" }

        let sqlFormatter = DateFormatter()
        sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sqlFormatter.timeZone = TimeZone(identifier: "UTC")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let date = sqlFormatter.date(from: isoString)
            ?? isoFormatter.date(from: isoString)

        guard let date else { return "" }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationSplitView {
        ResearchSidebarView(selectedThreadId: .constant(nil), initialProjectId: .constant(nil))
            .environmentObject(ResearchStore.preview(
                projects: [
                    ResearchProject(id: "1", title: "physics_teammate", description: "", createdAt: "", updatedAt: ""),
                    ResearchProject(id: "2", title: "deephedging", description: "", createdAt: "", updatedAt: "")
                ],
                threads: [
                    ResearchThread(id: "t1", projectId: "1", title: "Explain codebase for presentation", description: "", createdAt: "", updatedAt: "2026-03-08 12:00:00"),
                    ResearchThread(id: "t2", projectId: "2", title: "Describe deep hedging architecture", description: "", createdAt: "", updatedAt: "2026-03-08 12:00:00")
                ]
            ))
    } detail: {
        Text("Select a thread")
    }
}
