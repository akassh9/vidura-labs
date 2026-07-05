//
//  ResearchThreadDetailView.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import SwiftUI

// MARK: - Orchestrator Alert Info

struct OrchestratorAlertInfo {
    let title: String
    let message: String

    private static let rateLimitTitle = "Rate Limit Reached"
    private static let rateLimitMessage = "The current AI model has exceeded its API quota (error 429). Please select a different model from the top right selector, or wait a few minutes before trying again."

    init(error: Error) {
        if let orchError = error as? OrchestratorError {
            switch orchError {
            case .rateLimitExceeded:
                self.title = Self.rateLimitTitle
                self.message = Self.rateLimitMessage
            case .stageFailed(let stage, let underlying):
                if OrchestratorError.isRateLimitError(underlying) {
                    self.title = Self.rateLimitTitle
                    self.message = Self.rateLimitMessage
                } else {
                    self.title = "\(stage) Failed"
                    self.message = underlying.localizedDescription
                }
            case .stageEmptyResponse(let stage):
                self.title = "\(stage) Failed"
                self.message = "The AI model did not produce a valid response during the \(stage) stage. Please try rephrasing your request or try again."
            case .rerunUnavailable(let message):
                self.title = "Exact Rerun Unavailable"
                self.message = message
            }
        } else if OrchestratorError.isRateLimitError(error) {
            self.title = Self.rateLimitTitle
            self.message = Self.rateLimitMessage
        } else {
            self.title = "Error"
            self.message = error.localizedDescription
        }
    }
}

// MARK: - Welcome Detail View (no thread selected)

/// Shown in the detail pane when no thread is selected.
/// Displays the project dropdown, suggestion cards, and an input bar.
/// Sending a message auto-creates a "New Thread" under the selected project.
struct WelcomeDetailView: View {
    @EnvironmentObject private var store: ResearchStore
    @EnvironmentObject private var orchestrator: OrchestratorService
    @Binding var selectedThreadId: String?
    var initialProjectId: String? = nil

    @State private var selectedProjectId: String? = nil
    @State private var inputText: String = ""
    @State private var isSendingMessage: Bool = false
    @State private var errorBanner: String? = nil
    @State private var isCreatingProject = false
    @State private var newProjectTitle = ""
    @State private var orchestratorAlert: OrchestratorAlertInfo? = nil

    private let suggestions: [(icon: String, title: String, subtitle: String, prompt: String)] = [
        ("tornado", "Run QCD dijets", "Simulate pp → 2 jets at 13 TeV",
         "Run a QCD dijet simulation at 13 TeV with 10000 events"),
        ("circle.hexagongrid", "Z boson production", "Drell-Yan process with decay",
         "Simulate Z boson production with leptonic decay"),
        ("chart.line.uptrend.xyaxis", "Run Proton Collision", "13 TeV for 7000 events with HardQCD enabled",
         "Run proton-proton collisions at 13 TeV for 7000 events with HardQCD enabled, analyze particle-ID yields for pi+, pi-, K+, K-, and proton, and report generated_events plus pid_211, pid_-211, pid_321, pid_-321, and pid_2212."),
        ("arrow.left.arrow.right", "Run e+e- Collision", "charged multiplicity",
         "Run e+e- collisions at 91.2 GeV for 10000 events, analyze charged multiplicity, and report generated_events plus mean_charged with histogram artifact.")
    ]

    private var currentProject: ResearchProject? {
        if let id = selectedProjectId {
            return store.projects.first { $0.id == id }
        }
        return store.projects.first
    }

    private var resolvedProjectId: String? {
        if let id = selectedProjectId, store.projects.contains(where: { $0.id == id }) {
            return id
        }
        if let id = initialProjectId, store.projects.contains(where: { $0.id == id }) {
            return id
        }
        return store.projects.first?.id
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Welcome content
                VStack(spacing: 32) {
                    Spacer()

                    Image(systemName: "atom")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        Text("Let's research")
                            .font(.title)
                            .fontWeight(.bold)

                        ProjectDropdown(
                            projects: store.projects,
                            selectedProjectId: Binding(
                                get: { selectedProjectId ?? store.projects.first?.id },
                                set: { selectedProjectId = $0 }
                            ),
                            onCreateProject: {
                                newProjectTitle = ""
                                isCreatingProject = true
                            }
                        )
                    }

                    Text("Start a simulation run or ask a question")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                            SuggestionCardView(
                                icon: suggestion.icon,
                                title: suggestion.title,
                                subtitle: suggestion.subtitle
                            ) {
                                inputText = suggestion.prompt
                                submitInput()
                            }
                        }
                    }
                    .frame(maxWidth: 560)

                    Spacer()
                    Spacer()
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                InputBar(
                    text: $inputText,
                    isLoading: isSendingMessage,
                    onSubmit: { submitInput() }
                )
            }

            if let error = errorBanner {
                errorBannerView(error)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            selectedProjectId = resolvedProjectId
        }
        .onChange(of: store.projects.map(\.id)) { _, _ in
            selectedProjectId = resolvedProjectId
        }
        .alert(Text("New Project"), isPresented: $isCreatingProject) {
            TextField("Project title", text: $newProjectTitle)
            Button("Cancel", role: .cancel) { }
            Button("Create") { createProject() }
        } message: {
            Text("Enter a name for the new research project.")
        }
        .alert(
            orchestratorAlert?.title ?? "Error",
            isPresented: Binding(
                get: { orchestratorAlert != nil },
                set: { if !$0 { orchestratorAlert = nil } }
            )
        ) {
            Button("OK", role: .cancel) { orchestratorAlert = nil }
        } message: {
            if let info = orchestratorAlert {
                Text(info.message)
            }
        }
    }

    private func submitInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingMessage else { return }

        isSendingMessage = true
        let capturedText = text
        inputText = ""

        Task {
            do {
                // Ensure we have a valid, existing project
                let projectId: String
                if let id = resolvedProjectId {
                    projectId = id
                    selectedProjectId = id
                } else {
                    let newProj = try await store.createProject(title: "My Project")
                    projectId = newProj.id
                    selectedProjectId = newProj.id
                }

                // Create a new thread
                let newThread = try await store.createThread(
                    projectId: projectId,
                    title: "New Thread"
                )

                // Find or create an active run (new thread → always creates one)
                let shortTitle = String(capturedText.prefix(40))
                let chatRun = try await store.activeRunForThread(
                    threadId: newThread.id,
                    fallbackTitle: shortTitle
                )

                // Append the user message
                let msg = ChatMessage(
                    id: UUID().uuidString,
                    role: "user",
                    content: capturedText,
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    originRunId: chatRun.id,
                    parentMessageId: nil
                )

                try await store.addChatMessage(runId: chatRun.id, message: msg)

                // Navigate to the new thread
                selectedThreadId = newThread.id

                // Kick off the orchestrator pipeline
                // The orchestrator will create a new simulation run if needed
                Task {
                    do {
                        let _ = try await orchestrator.run(
                            runId: chatRun.id,
                            threadId: newThread.id,
                            prompt: capturedText,
                            chatHistory: [msg]
                        )
                    } catch {
                        orchestratorAlert = OrchestratorAlertInfo(error: error)
                    }
                }
            } catch {
                errorBanner = error.localizedDescription
            }
            isSendingMessage = false
        }
    }

    private func createProject() {
        let title = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task {
            if let proj = try? await store.createProject(title: title) {
                selectedProjectId = proj.id
            }
        }
    }

    @ViewBuilder
    private func errorBannerView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                withAnimation { errorBanner = nil }
            }
            .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.15))
        .zIndex(1)
    }
}

// MARK: - ResearchThreadDetailView

struct ResearchThreadDetailView: View {
    @EnvironmentObject private var store: ResearchStore
    @EnvironmentObject private var orchestrator: OrchestratorService

    let threadId: String
    @Binding var selectedThreadId: String?

    @State private var selectedRunId: String? = nil
    @State private var inputText: String = ""
    @State private var isSendingMessage: Bool = false
    @State private var errorBanner: String? = nil
    @State private var showRunsConfig: Bool = false
    @State private var isMainChatThread: Bool = true
    @State private var orchestratorAlert: OrchestratorAlertInfo? = nil

    private var thread: ResearchThread? {
        store.threads.first { $0.id == threadId }
    }

    private var project: ResearchProject? {
        guard let thread else { return nil }
        return store.projects.first { $0.id == thread.projectId }
    }

    private var threadRuns: [SimulationRun] {
        store.runs.filter { $0.threadId == threadId }
    }

    private var selectedRun: SimulationRun? {
        guard let id = selectedRunId else { return threadRuns.first }
        return threadRuns.first { $0.id == id }
    }

    var body: some View {
        Group {
        if let thread {
            ZStack(alignment: .top) {
                if threadRuns.isEmpty {
                    VStack(spacing: 0) {
                        ThreadWelcomeView(
                            thread: thread,
                            projects: store.projects,
                            currentProject: project,
                            onSuggestionTap: { prompt in
                                inputText = prompt
                                submitInput()
                            },
                            onChangeProject: { newProjectId in
                                moveThreadToProject(newProjectId)
                            },
                            onCreateProject: nil
                        )
                        Divider()
                        InputBar(
                            text: $inputText,
                            isLoading: isSendingMessage,
                            onSubmit: { submitInput() }
                        )
                    }
                } else {
                    ThreadConversationView(
                        thread: thread,
                        project: project,
                        runs: threadRuns,
                        messages: store.messages,
                        isMainChatThread: $isMainChatThread,
                        selectedRunId: $selectedRunId,
                        inputText: $inputText,
                        isSendingMessage: $isSendingMessage,
                        showRunsConfig: $showRunsConfig,
                        simulationProgress: orchestrator.simulationProgress,
                        estimatedSecondsRemaining: orchestrator.estimatedSecondsRemaining,
                        currentPhase: orchestrator.currentPhase,
                        activeThreadId: orchestrator.activeThreadId,
                        threadId: threadId,
                        onSubmit: submitInput
                    )
                }

                if let error = errorBanner {
                    errorBannerView(error)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: threadId) {
                selectedRunId = nil
                isMainChatThread = true
                try? await store.loadRuns(forThread: threadId)
                try? await store.loadThreadMessages(forThread: threadId)
            }
        } else {
            ContentUnavailableView {
                Label("Thread Not Found", systemImage: "questionmark.folder")
            } description: {
                Text("The selected thread could not be found.")
            }
        }
        }
        .alert(
            orchestratorAlert?.title ?? "Error",
            isPresented: Binding(
                get: { orchestratorAlert != nil },
                set: { if !$0 { orchestratorAlert = nil } }
            )
        ) {
            Button("OK", role: .cancel) { orchestratorAlert = nil }
        } message: {
            if let info = orchestratorAlert {
                Text(info.message)
            }
        }
    }

    // MARK: - Actions

    private func submitInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingMessage else { return }

        isSendingMessage = true
        let capturedText = text
        inputText = ""

        Task {
            do {
                // Find or create an active (non-completed) run for this thread
                let shortTitle = String(capturedText.prefix(40))
                let activeRun = try await store.activeRunForThread(
                    threadId: threadId,
                    fallbackTitle: shortTitle
                )
                let chatRunId = activeRun.id

                // Append the user message to the chat run
                // Parent only within this run; cross-run fallbacks can link unrelated threads.
                let lastThreadMsgId = store.messages.last(where: {
                    $0.originRunId == chatRunId
                })?.id
                let msg = ChatMessage(
                    id: UUID().uuidString,
                    role: "user",
                    content: capturedText,
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    originRunId: chatRunId,
                    parentMessageId: lastThreadMsgId
                )
                try await store.addChatMessage(runId: chatRunId, message: msg)

                // Get full chat history for the run
                let messages = try await store.fetchRunMessagesAndParents(forRun: chatRunId)

                // Kick off the orchestrator pipeline
                // The orchestrator will create a new simulation run if needed
                Task {
                    do {
                        let _ = try await orchestrator.run(
                            runId: chatRunId,
                            threadId: threadId,
                            prompt: capturedText,
                            chatHistory: messages
                        )
                    } catch {
                        orchestratorAlert = OrchestratorAlertInfo(error: error)
                    }
                }
            } catch {
                errorBanner = error.localizedDescription
            }
            isSendingMessage = false
        }
    }

    private func branchFromMessage(run: SimulationRun, message: ChatMessage) {
        guard let thread else { return }
        Task {
            do {
                // Include the full run chat history (messages, charts, and summary)
                let branchTitle = "Branch: \(thread.title)"
                let newThread = try await store.createThread(
                    projectId: thread.projectId,
                    title: branchTitle
                )
                
                let messages = try await store.fetchRunMessagesAndParents(forRun: run.id)

                // Create a run seeded with the entire run's chat history
                try await store.createRunWithChatHistory(
                    threadId: newThread.id,
                    title: run.title,
                    chatHistory: messages,
                    configuration: run.configuration
                )

                // Navigate to the new thread
                selectedThreadId = newThread.id
            } catch {
                errorBanner = error.localizedDescription
            }
        }
    }

    private func moveThreadToProject(_ newProjectId: String) {
        guard let thread, thread.projectId != newProjectId else { return }
        Task {
            try? await store.deleteThread(id: thread.id)
            let newThread = try? await store.createThread(
                projectId: newProjectId,
                title: thread.title,
                description: thread.description
            )
            if let newThread {
                selectedThreadId = newThread.id
            }
        }
    }

    @ViewBuilder
    private func errorBannerView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                withAnimation { errorBanner = nil }
            }
            .font(.callout)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.15))
        .zIndex(1)
    }
}

// MARK: - Project Dropdown

/// A dropdown button styled like the Codex project picker.
/// Shows the current project name with a chevron; clicking opens a menu
/// listing all projects with a checkmark on the selected one, plus
/// an "Add new project" option at the bottom.
struct ProjectDropdown: View {
    let projects: [ResearchProject]
    @Binding var selectedProjectId: String?
    let onCreateProject: () -> Void

    private var currentProject: ResearchProject? {
        if let id = selectedProjectId {
            return projects.first { $0.id == id }
        }
        return projects.first
    }

    var body: some View {
        Menu {
            ForEach(projects) { project in
                Button {
                    selectedProjectId = project.id
                } label: {
                    HStack {
                        Label(project.title, systemImage: "folder")
                        if project.id == (selectedProjectId ?? projects.first?.id) {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                onCreateProject()
            } label: {
                Label("Add new project", systemImage: "folder.badge.plus")
            }
        } label: {
            HStack(spacing: 4) {
                Text(currentProject?.title ?? "Select project")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Thread Welcome View

private struct ThreadWelcomeView: View {
    let thread: ResearchThread
    let projects: [ResearchProject]
    let currentProject: ResearchProject?
    let onSuggestionTap: (String) -> Void
    let onChangeProject: (String) -> Void
    let onCreateProject: (() -> Void)?

    private let suggestions: [(icon: String, title: String, subtitle: String, prompt: String)] = [
        ("tornado", "Run QCD dijets", "Simulate pp → 2 jets at 13 TeV",
         "Run a QCD dijet simulation at 13 TeV with 10000 events"),
        ("circle.hexagongrid", "Z boson production", "Drell-Yan process with decay",
         "Simulate Z boson production with leptonic decay"),
        ("chart.line.uptrend.xyaxis", "Run Proton Collision", "13 TeV for 7000 events with HardQCD enabled",
         "Run proton-proton collisions at 13 TeV for 7000 events with HardQCD enabled, analyze particle-ID yields for pi+, pi-, K+, K-, and proton, and report generated_events plus pid_211, pid_-211, pid_321, pid_-321, and pid_2212."),
        ("arrow.left.arrow.right", "Run e+e- Collision", "charged multiplicity",
         "Run e+e- collisions at 91.2 GeV for 10000 events, analyze charged multiplicity, and report generated_events plus mean_charged with histogram artifact.")
    ]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "atom")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Let's research")
                    .font(.title)
                    .fontWeight(.bold)

                ProjectDropdown(
                    projects: projects,
                    selectedProjectId: Binding(
                        get: { currentProject?.id },
                        set: { if let id = $0 { onChangeProject(id) } }
                    ),
                    onCreateProject: { onCreateProject?() }
                )
            }

            Text("Start a simulation run or ask a question")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                    SuggestionCardView(
                        icon: suggestion.icon,
                        title: suggestion.title,
                        subtitle: suggestion.subtitle
                    ) {
                        onSuggestionTap(suggestion.prompt)
                    }
                }
            }
            .frame(maxWidth: 560)

            Spacer()
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Suggestion Card

private struct SuggestionCardView: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thread Conversation View

private struct ThreadConversationView: View {
    let thread: ResearchThread
    let project: ResearchProject?
    let runs: [SimulationRun]
    let messages: [ChatMessage]
    @Binding var isMainChatThread: Bool
    @Binding var selectedRunId: String?
    @Binding var inputText: String
    @Binding var isSendingMessage: Bool
    @Binding var showRunsConfig: Bool
    var simulationProgress: Double?
    var estimatedSecondsRemaining: Double?
    var currentPhase: String
    var activeThreadId: String?
    let threadId: String
    let onSubmit: () -> Void

    private var selectedRun: SimulationRun? {
        guard let id = selectedRunId else { return nil }
        return runs.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Top bar with run selector and config button
                    HStack(spacing: 0) {
                        RunSelectorStrip(runs: runs, selectedRunId: $selectedRunId, mainChatSelected: $isMainChatThread)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRunsConfig.toggle()
                            }
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 14))
                                .foregroundStyle(showRunsConfig ? .primary : .secondary)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(showRunsConfig ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Show run configurations")
                        .padding(.trailing, 12)
                    }

                    if let run = selectedRun {
                        RunHeaderBanner(run: run)
                    }

                    Divider()
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .zIndex(1)

                chatScrollArea

                Divider()

                InputBar(
                    text: $inputText,
                    isLoading: isSendingMessage || isOrchestratorActive,
                    onSubmit: { onSubmit() }
                )
            }

            if showRunsConfig {
                Divider()
                RunsConfigurationPanel(runs: runs, messages: messages)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    private var isOrchestratorActive: Bool {
        currentPhase != "idle" && activeThreadId == threadId
    }

    /// Messages to display for the currently selected run.
    /// Chat runs (empty configuration) show everything.
    /// Simulation runs filter to messages that originated from that run.
    private var visibleMessages: [ChatMessage] {
        if isMainChatThread {
            return messages
        }

        guard let run = selectedRun else { return [] }

        return messages.filter { msg in
            msg.originRunId == run.id
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            if isOrchestratorActive {
                proxy.scrollTo("progress-bubble", anchor: .bottom)
            } else if let last = visibleMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }

        if animated {
            withAnimation {
                action()
            }
        } else {
            action()
        }
    }

    private var chatScrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if isMainChatThread {
                        let messages = visibleMessages
                        ForEach(messages) { message in
                            ChatBubbleView(message: message)
                            .id(message.id)
                        }
                    }
                    if let run = selectedRun {
                        let messages = visibleMessages
                        if messages.isEmpty {
                            emptyRunPlaceholder(run: run)
                        } else {
                            ForEach(messages) { message in
                                ChatBubbleView(message: message)
                                .id(message.id)
                            }
                        }
                    }

                    if isOrchestratorActive {
                        SimulationProgressBubble(
                            phase: currentPhase,
                            progress: simulationProgress,
                            estimatedSecondsRemaining: estimatedSecondsRemaining
                        )
                        .id("progress-bubble")
                        .padding(.top, 4)
                    }
                }
                .padding()
            }
            .clipped()
            .task(id: "\(threadId)-\(visibleMessages.last?.id ?? "none")-\(isOrchestratorActive)") {
                // Stabilize first render: scroll after layout, then once more after
                // the initial async view updates settle.
                await Task.yield()
                scrollToLatest(proxy, animated: false)
                try? await Task.sleep(nanoseconds: 140_000_000)
                scrollToLatest(proxy, animated: false)
            }
            .onChange(of: visibleMessages.count) {
                scrollToLatest(proxy, animated: true)
            }
            .onChange(of: simulationProgress) {
                if isOrchestratorActive {
                    scrollToLatest(proxy, animated: true)
                }
            }
            .onChange(of: currentPhase) {
                if isOrchestratorActive {
                    scrollToLatest(proxy, animated: true)
                }
            }
        }
    }

    /// Returns a mapping from message ID → the SimulationRun the branch button should use.
    /// For simulation-specific runs, this is just the last assistant text of that run (if terminal).
    /// For the main chat run, it finds the last assistant text message of every terminal run.
    private func branchableMessages(
        messages: [ChatMessage],
        selectedRun: SimulationRun,
        allRuns: [SimulationRun]
    ) -> [String: SimulationRun] {
        let isChatRun = selectedRun.configuration.isEmpty

        if isChatRun {
            // For each terminal run, find its last assistant text message in the chat
            var result: [String: SimulationRun] = [:]
            let terminalRuns = allRuns.filter {
                $0.status == .completed || $0.status == .failed
            }
            for run in terminalRuns {
                if let msg = messages.last(where: {
                    $0.originRunId == run.id
                    && $0.role == "assistant"
                    && $0.chartPayload == nil
                    && !$0.content.isEmpty
                }) {
                    result[msg.id] = run
                }
            }
            return result
        } else {
            // Simulation-specific view: single branch button on last assistant text
            let isTerminal = selectedRun.status == .completed || selectedRun.status == .failed
            guard isTerminal else { return [:] }
            if let msg = messages.last(where: {
                $0.role == "assistant" && $0.chartPayload == nil && !$0.content.isEmpty
            }) {
                return [msg.id: selectedRun]
            }
            return [:]
        }
    }

    private func emptyRunPlaceholder(run: SimulationRun) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Run \"\(run.title)\" is \(run.status.displayName.lowercased())")
                .font(.headline)
                .foregroundStyle(.secondary)
            if run.status == .failed, let err = run.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if run.status == .completed, let summary = run.resultSummary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Run Selector Strip

private struct RunSelectorStrip: View {
    let runs: [SimulationRun]
    @Binding var selectedRunId: String?
    @Binding var mainChatSelected: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                MainChatRunTabButton(
                    isSelected: mainChatSelected,
                    onSelect: {
                        mainChatSelected = true
                        selectedRunId = nil
                    }
                )
                
                ForEach(runs) { run in
                    RunTabButton(
                        run: run,
                        isSelected: selectedRunId == run.id,
                        onSelect: {
                            selectedRunId = run.id
                            mainChatSelected = false
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(height: 40)
    }
}

private struct RunTabButton: View {
    let run: SimulationRun
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Circle()
                    .fill(run.status.color)
                    .frame(width: 8, height: 8)
                Text(run.title)
                    .lineLimit(1)
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 140)
    }
}

private struct MainChatRunTabButton: View {
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Main Chat")
                    .lineLimit(1)
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 140)
    }
}

// MARK: - Run Header Banner

private struct RunHeaderBanner: View {
    let run: SimulationRun

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(run.status.displayName, systemImage: run.status.iconName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(run.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(run.status.color.opacity(0.12))
                    )

                if let count = run.eventCount {
                    MetricChip(label: "Events", value: "\(count)")
                }
                if let sigma = run.crossSection {
                    MetricChip(label: "σ", value: String(format: "%.3g mb", sigma))
                }

                Spacer()

                Text(run.title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

private struct MetricChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.tertiary)
            Text(value)
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Chat Bubble

private struct ChatBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }
    private var isSystem: Bool { message.role == "system" }

    var body: some View {
        if isSystem {
            systemBubble
        } else {
            messageBubble
        }
    }

    private var systemBubble: some View {
        Text(message.content)
            .font(.caption)
            .italic()
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }

    private var messageBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "atom")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    )
                    .padding(.top, 2)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if let chart = message.chartPayload {
                    ChartBubbleContent(payload: chart)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if isUser {
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    MarkdownContentView(content: message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text(formattedTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isUser { Spacer(minLength: 60) }

            if isUser {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    )
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedTime: String {
        guard !message.timestamp.isEmpty else { return "" }
        let isoFmt = ISO8601DateFormatter()
        let sqlFmt = DateFormatter()
        sqlFmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sqlFmt.timeZone = TimeZone(identifier: "UTC")
        let date = isoFmt.date(from: message.timestamp)
            ?? sqlFmt.date(from: message.timestamp)
        guard let date else { return "" }
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return fmt.string(from: date)
    }
}

// MARK: - Simulation Progress Bubble

/// Inline progress indicator shown in the chat while the orchestrator is active.
private struct SimulationProgressBubble: View {
    let phase: String
    let progress: Double?
    let estimatedSecondsRemaining: Double?

    private var phaseLabel: String {
        switch phase {
        case "guide":     return "Analyzing request…"
        case "discovery": return "Planning simulation…"
        case "codegen":   return "Generating code…"
        case "compile":   return "Compiling & running…"
        case "results":   return "Parsing results…"
        case "plotting":  return "Rendering charts…"
        case "queued":    return "Starting…"
        default:          return "Working…"
        }
    }

    private var etaText: String? {
        guard let eta = estimatedSecondsRemaining, eta > 0 else { return nil }
        if eta < 60 {
            return "~\(Int(eta))s remaining"
        } else {
            let minutes = Int(eta) / 60
            let seconds = Int(eta) % 60
            return "~\(minutes)m \(seconds)s remaining"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "atom")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(phaseLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let progress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(.accentColor)

                        HStack {
                            Text("Generating events")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            if let eta = etaText {
                                Text(eta)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Text("\(Int(progress * 100))%")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 400, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 60)
        }
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

// MARK: - Run Evidence Panel

private struct RunsConfigurationPanel: View {
    let runs: [SimulationRun]
    let messages: [ChatMessage]
    @State private var selectedMode: RunSidePanelMode = .evidence
    @State private var compareLeftRunId: String?
    @State private var compareRightRunId: String?

    private var simulationRuns: [SimulationRun] {
        runs.filter { !$0.configuration.isEmpty }
    }

    private var completedSimulationRuns: [SimulationRun] {
        simulationRuns.filter { $0.status == .completed }
    }

    private var artifactCount: Int {
        simulationRuns.reduce(0) { $0 + RunEvidenceResolver.artifacts(for: $1).count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selectedMode.title)
                    .font(.headline)
                Spacer()
                Text("\(simulationRuns.count) runs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(artifactCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.secondary.opacity(0.12))
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Picker("Panel", selection: $selectedMode) {
                ForEach(RunSidePanelMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            if simulationRuns.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No simulation runs yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Evidence will appear here after a Pythia run completes.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if selectedMode == .evidence {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(simulationRuns) { run in
                            RunEvidenceCard(
                                run: run,
                                chartPayloads: messages
                                    .filter { $0.originRunId == run.id }
                                    .compactMap(\.chartPayload)
                            )
                        }
                    }
                    .padding(12)
                }
            } else {
                RunComparePanel(
                    completedRuns: completedSimulationRuns,
                    messages: messages,
                    leftRunId: $compareLeftRunId,
                    rightRunId: $compareRightRunId
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private enum RunSidePanelMode: String, CaseIterable, Identifiable {
    case evidence
    case compare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .evidence: return "Run Evidence"
        case .compare: return "Run Compare"
        }
    }

    var iconName: String {
        switch self {
        case .evidence: return "list.bullet.rectangle"
        case .compare: return "arrow.left.arrow.right"
        }
    }
}

private struct RunComparePanel: View {
    let completedRuns: [SimulationRun]
    let messages: [ChatMessage]
    @Binding var leftRunId: String?
    @Binding var rightRunId: String?

    private var leftRun: SimulationRun? {
        resolvedRun(for: leftRunId) ?? completedRuns.first
    }

    private var rightRun: SimulationRun? {
        resolvedRun(for: rightRunId) ?? completedRuns.dropFirst().first ?? completedRuns.first
    }

    private var comparison: RunComparison? {
        guard let leftRun, let rightRun else { return nil }
        return RunComparison(left: leftRun, right: rightRun, messages: messages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if completedRuns.count < 2 {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Need two completed runs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Run Compare is available when a thread has at least two completed simulation runs.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    RunComparePicker(
                        title: "A",
                        runs: completedRuns,
                        selectedRunId: Binding(
                            get: { leftRun?.id },
                            set: { leftRunId = $0 }
                        )
                    )
                    RunComparePicker(
                        title: "B",
                        runs: completedRuns,
                        selectedRunId: Binding(
                            get: { rightRun?.id },
                            set: { rightRunId = $0 }
                        )
                    )
                }
                .padding(12)

                Divider()

                if let comparison {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            RunCompareSummaryCard(comparison: comparison)
                            RunCompareSection(title: "Identity", rows: comparison.identityRows)
                            RunCompareSection(title: "Configuration", rows: comparison.configurationRows)
                            RunCompareSection(title: "Summary Metrics", rows: comparison.summaryMetricRows)
                            RunCompareSection(title: "Artifacts", rows: comparison.artifactRows)
                            RunCompareSection(title: "Charts", rows: comparison.chartRows)
                            RunCompareSection(title: "Exact Rerun", rows: comparison.byteMatchRows)
                        }
                        .padding(12)
                    }
                }
            }
        }
        .onAppear(perform: seedSelections)
        .onChange(of: completedRuns.map(\.id)) {
            seedSelections()
        }
    }

    private func resolvedRun(for id: String?) -> SimulationRun? {
        guard let id else { return nil }
        return completedRuns.first { $0.id == id }
    }

    private func seedSelections() {
        guard completedRuns.count >= 2 else { return }

        if resolvedRun(for: leftRunId) == nil {
            leftRunId = completedRuns.first?.id
        }

        if resolvedRun(for: rightRunId) == nil || rightRunId == leftRunId {
            rightRunId = completedRuns.first { $0.id != leftRunId }?.id
        }
    }
}

private struct RunComparePicker: View {
    let title: String
    let runs: [SimulationRun]
    @Binding var selectedRunId: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Picker(title, selection: $selectedRunId) {
                ForEach(runs) { run in
                    Text(run.title)
                        .tag(Optional(run.id))
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }
}

private struct RunCompareSummaryCard: View {
    let comparison: RunComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                CompareRunBadge(label: "A", run: comparison.left)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                CompareRunBadge(label: "B", run: comparison.right)
            }

            HStack(spacing: 6) {
                MetricChip(label: "Metrics", value: "\(comparison.summaryMetricRows.count)")
                MetricChip(label: "Charts", value: "\(comparison.leftCharts.count)/\(comparison.rightCharts.count)")
                MetricChip(label: "Artifacts", value: "\(comparison.leftArtifacts.count)/\(comparison.rightArtifacts.count)")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

private struct CompareRunBadge: View {
    let label: String
    let run: SimulationRun

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text(run.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
            Text(run.id)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RunCompareSection: View {
    let title: String
    let rows: [RunCompareRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 1) {
                ForEach(rows) { row in
                    RunCompareRowView(row: row)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.06))
            )
        }
    }
}

private struct RunCompareRowView: View {
    let row: RunCompareRow

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: row.matches ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                .font(.caption2)
                .foregroundStyle(row.matches ? .green : .orange)
                .frame(width: 12)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(alignment: .top, spacing: 8) {
                    CompareValueColumn(label: "A", value: row.leftValue)
                    CompareValueColumn(label: "B", value: row.rightValue)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
    }
}

private struct CompareValueColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RunCompareRow: Identifiable {
    let id = UUID()
    let label: String
    let leftValue: String
    let rightValue: String
    let matches: Bool
}

private struct RunComparison {
    let left: SimulationRun
    let right: SimulationRun
    let leftArtifacts: [ArtifactRef]
    let rightArtifacts: [ArtifactRef]
    let leftCharts: [ChartPayload]
    let rightCharts: [ChartPayload]

    init(left: SimulationRun, right: SimulationRun, messages: [ChatMessage]) {
        self.left = left
        self.right = right
        self.leftArtifacts = RunEvidenceResolver.artifacts(for: left)
        self.rightArtifacts = RunEvidenceResolver.artifacts(for: right)
        self.leftCharts = messages
            .filter { $0.originRunId == left.id }
            .compactMap(\.chartPayload)
        self.rightCharts = messages
            .filter { $0.originRunId == right.id }
            .compactMap(\.chartPayload)
    }

    var identityRows: [RunCompareRow] {
        [
            row("Run ID", left.id, right.id),
            row("Status", left.status.displayName, right.status.displayName),
            row("Events", formatInt(left.eventCount), formatInt(right.eventCount)),
            row("Completed", left.completedAt ?? "none", right.completedAt ?? "none")
        ]
    }

    var configurationRows: [RunCompareRow] {
        let keys = Set(left.configuration.keys).union(right.configuration.keys).sorted()
        guard !keys.isEmpty else {
            return [row("Configuration", "none", "none")]
        }
        return keys.map { key in
            row(key, left.configuration[key] ?? "missing", right.configuration[key] ?? "missing")
        }
    }

    var summaryMetricRows: [RunCompareRow] {
        let leftMetrics = summaryMetrics(for: left)
        let rightMetrics = summaryMetrics(for: right)
        let keys = Set(leftMetrics.keys).union(rightMetrics.keys).sorted()
        guard !keys.isEmpty else {
            return [row("summary.json", "missing or empty", "missing or empty")]
        }
        return keys.map { key in
            row(key, leftMetrics[key] ?? "missing", rightMetrics[key] ?? "missing")
        }
    }

    var artifactRows: [RunCompareRow] {
        let leftPresence = artifactPresence(leftArtifacts)
        let rightPresence = artifactPresence(rightArtifacts)
        let labels = Set(leftPresence.keys).union(rightPresence.keys).sorted()
        guard !labels.isEmpty else {
            return [row("Artifacts", "none", "none")]
        }
        return labels.map { label in
            row(label, leftPresence[label] ?? "missing", rightPresence[label] ?? "missing")
        }
    }

    var chartRows: [RunCompareRow] {
        let leftMap = chartPointCounts(leftCharts)
        let rightMap = chartPointCounts(rightCharts)
        let titles = Set(leftMap.keys).union(rightMap.keys).sorted()
        guard !titles.isEmpty else {
            return [row("Charts", "none", "none")]
        }
        return titles.map { title in
            row(title, leftMap[title] ?? "missing", rightMap[title] ?? "missing")
        }
    }

    var byteMatchRows: [RunCompareRow] {
        [
            byteMatchRow(fileName: "run.cc"),
            byteMatchRow(fileName: "simulation_spec.json")
        ]
    }

    private func row(_ label: String, _ leftValue: String, _ rightValue: String) -> RunCompareRow {
        RunCompareRow(
            label: label,
            leftValue: leftValue,
            rightValue: rightValue,
            matches: leftValue == rightValue
        )
    }

    private func formatInt(_ value: Int?) -> String {
        guard let value else { return "none" }
        return "\(value)"
    }

    private func artifactPresence(_ artifacts: [ArtifactRef]) -> [String: String] {
        Dictionary(grouping: artifacts) { artifact in
            artifact.label
        }
        .mapValues { artifacts in
            "\(artifacts.count) present"
        }
    }

    private func chartPointCounts(_ charts: [ChartPayload]) -> [String: String] {
        var counts: [String: Int] = [:]
        for chart in charts {
            let count = chart.series.reduce(0) { $0 + $1.points.count }
            counts[chart.title, default: 0] += count
        }
        return counts.mapValues { "\($0) points" }
    }

    private func byteMatchRow(fileName: String) -> RunCompareRow {
        let leftURL = artifactURL(named: fileName, in: leftArtifacts)
        let rightURL = artifactURL(named: fileName, in: rightArtifacts)

        guard let leftURL else {
            return RunCompareRow(label: fileName, leftValue: "missing", rightValue: rightURL == nil ? "missing" : "present", matches: false)
        }
        guard let rightURL else {
            return RunCompareRow(label: fileName, leftValue: "present", rightValue: "missing", matches: false)
        }

        guard let leftData = try? Data(contentsOf: leftURL),
              let rightData = try? Data(contentsOf: rightURL) else {
            return RunCompareRow(label: fileName, leftValue: "unreadable", rightValue: "unreadable", matches: false)
        }

        return RunCompareRow(
            label: fileName,
            leftValue: "\(leftData.count) bytes",
            rightValue: "\(rightData.count) bytes",
            matches: leftData == rightData
        )
    }

    private func artifactURL(named fileName: String, in artifacts: [ArtifactRef]) -> URL? {
        artifacts.first { artifact in
            URL(fileURLWithPath: artifact.relativePath).lastPathComponent == fileName
                && FileManager.default.fileExists(atPath: artifact.relativePath)
        }
        .map { URL(fileURLWithPath: $0.relativePath) }
    }

    private func summaryMetrics(for run: SimulationRun) -> [String: String] {
        guard let url = artifactURL(named: "summary.json", in: RunEvidenceResolver.artifacts(for: run)),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }

        return flattenSummaryMetrics(object)
    }

    private func flattenSummaryMetrics(_ value: Any, prefix: String = "") -> [String: String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [:]) { result, pair in
                let key = prefix.isEmpty ? pair.key : "\(prefix).\(pair.key)"
                result.merge(flattenSummaryMetrics(pair.value, prefix: key), uniquingKeysWith: { _, new in new })
            }
        }

        if let array = value as? [Any] {
            return [prefix: "\(array.count) items"]
        }

        if let number = value as? NSNumber {
            return [prefix: number.stringValue]
        }

        if let string = value as? String {
            return [prefix: string]
        }

        if value is NSNull {
            return [prefix: "null"]
        }

        return [prefix: String(describing: value)]
    }
}

private struct RunEvidenceCard: View {
    @EnvironmentObject private var orchestrator: OrchestratorService
    let run: SimulationRun
    let chartPayloads: [ChartPayload]
    @State private var selectedArtifact: ArtifactRef?
    @State private var isRerunning = false
    @State private var rerunError: String?
    @State private var isExporting = false
    @State private var exportResult: RunBundleExportResult?
    @State private var exportError: String?

    private var artifacts: [ArtifactRef] {
        RunEvidenceResolver.artifacts(for: run)
    }

    private var groups: [ArtifactGroup] {
        RunEvidenceResolver.groups(for: artifacts)
    }

    private var runFolderURL: URL? {
        RunEvidenceResolver.runFolderURL(for: run, artifacts: artifacts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(run.status.color)
                    .frame(width: 8, height: 8)
                Text(run.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(run.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(run.status.color)
            }

            HStack(spacing: 6) {
                Button {
                    RunEvidenceActions.copy(run.id)
                } label: {
                    Image(systemName: "number")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy Run ID")

                Button {
                    if let runFolderURL {
                        RunEvidenceActions.reveal(url: runFolderURL)
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(runFolderURL == nil)
                .help("Reveal Run Folder")

                Button {
                    rerunExact()
                } label: {
                    if isRerunning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.trianglehead.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!canRerunExact)
                .help("Rerun Exact")

                Button {
                    exportRunBundle()
                } label: {
                    if isExporting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!canExportRunBundle)
                .help("Export Run Bundle")

                Text("\(artifacts.count) artifacts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if run.configuration.isEmpty {
                Text("No configuration")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(run.configuration.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 4) {
                            Text(key)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text("=")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if run.eventCount != nil || run.crossSection != nil {
                HStack(spacing: 8) {
                    if let count = run.eventCount {
                        MetricChip(label: "Events", value: "\(count)")
                    }
                    if let sigma = run.crossSection {
                        MetricChip(label: "σ", value: String(format: "%.3g mb", sigma))
                    }
                }
            }

            Divider()

            if groups.isEmpty {
                Text("No persisted evidence artifacts for this run.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 5) {
                                Image(systemName: group.icon)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(group.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(spacing: 3) {
                                ForEach(group.artifacts) { artifact in
                                    ArtifactEvidenceRow(artifact: artifact) {
                                        selectedArtifact = artifact
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .sheet(item: $selectedArtifact) { artifact in
            ArtifactViewer(title: run.title, artifact: artifact)
        }
        .alert(
            "Exact Rerun Failed",
            isPresented: Binding(
                get: { rerunError != nil },
                set: { if !$0 { rerunError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { rerunError = nil }
        } message: {
            Text(rerunError ?? "")
        }
        .alert(item: $exportResult) { result in
            Alert(
                title: Text("Run Bundle Exported"),
                message: Text(result.bundleURL.path),
                primaryButton: .default(Text("Reveal")) {
                    RunEvidenceActions.reveal(url: result.bundleURL)
                },
                secondaryButton: .default(Text("Copy Path")) {
                    RunEvidenceActions.copy(result.bundleURL.path)
                }
            )
        }
        .alert(
            "Export Failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var canRerunExact: Bool {
        run.status == .completed && !isRerunning && !orchestrator.isRunning
    }

    private var canExportRunBundle: Bool {
        run.status == .completed && !isExporting && !artifacts.isEmpty
    }

    private func rerunExact() {
        guard canRerunExact else { return }
        isRerunning = true
        rerunError = nil

        Task {
            do {
                _ = try await orchestrator.rerunExact(run: run)
            } catch {
                rerunError = error.localizedDescription
            }
            isRerunning = false
        }
    }

    private func exportRunBundle() {
        guard canExportRunBundle else { return }

        let panel = NSOpenPanel()
        panel.title = "Export Run Bundle"
        panel.message = "Choose a folder where Vidura Labs should create the run bundle."
        panel.prompt = "Export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let parentURL = panel.url else {
            return
        }

        isExporting = true
        exportError = nil

        Task {
            do {
                let result = try RunBundleExporter.export(
                    run: run,
                    artifacts: artifacts,
                    chartPayloads: chartPayloads,
                    toParentDirectory: parentURL
                )
                exportResult = result
            } catch {
                exportError = error.localizedDescription
            }
            isExporting = false
        }
    }
}

private struct ArtifactEvidenceRow: View {
    let artifact: ArtifactRef
    let onView: () -> Void

    private var url: URL {
        URL(fileURLWithPath: artifact.relativePath)
    }

    private var canViewText: Bool {
        RunEvidenceResolver.isTextArtifact(artifact)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: RunEvidenceResolver.icon(for: artifact))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(artifact.label)
                    .font(.caption)
                    .lineLimit(1)
                Text(url.deletingLastPathComponent().lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                onView()
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canViewText)
            .help("View Artifact")

            Button {
                RunEvidenceActions.copy(artifact.relativePath)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Copy Path")

            Button {
                RunEvidenceActions.reveal(url: url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct ArtifactGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let order: Int
    let artifacts: [ArtifactRef]
}

private enum RunEvidenceResolver {
    private static let expectedEvidenceNames: [(name: String, kind: String)] = [
        ("run.cc", "source"),
        ("simulation_spec.json", "spec"),
        ("summary.json", "summary"),
        ("summary_lines.txt", "summary"),
        ("compile.log", "log"),
        ("run.log", "log")
    ]

    private static let standaloneEvidenceNames = Set(expectedEvidenceNames.map(\.name))

    static func artifacts(for run: SimulationRun) -> [ArtifactRef] {
        var artifacts = run.artifacts
        var seenPaths = Set(artifacts.map { $0.relativePath })

        for artifact in discoveredArtifacts(for: run) where !seenPaths.contains(artifact.relativePath) {
            artifacts.append(artifact)
            seenPaths.insert(artifact.relativePath)
        }

        return artifacts.sorted { lhs, rhs in
            let lhsGroup = groupMetadata(for: lhs).order
            let rhsGroup = groupMetadata(for: rhs).order
            if lhsGroup != rhsGroup {
                return lhsGroup < rhsGroup
            }
            return lhs.label < rhs.label
        }
    }

    static func groups(for artifacts: [ArtifactRef]) -> [ArtifactGroup] {
        let grouped = Dictionary(grouping: artifacts) { artifact in
            groupMetadata(for: artifact).id
        }

        return grouped.map { groupId, artifacts in
            let metadata = groupMetadata(forGroupId: groupId)
            return ArtifactGroup(
                id: metadata.id,
                title: metadata.title,
                icon: metadata.icon,
                order: metadata.order,
                artifacts: artifacts.sorted { $0.label < $1.label }
            )
        }
        .sorted { $0.order < $1.order }
    }

    static func runFolderURL(for run: SimulationRun, artifacts: [ArtifactRef]) -> URL? {
        let expectedRunFolder = PathUtils.simulationsDir.appendingPathComponent(run.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: expectedRunFolder.path) {
            return expectedRunFolder
        }

        guard let firstPath = artifacts.first?.relativePath else {
            return nil
        }
        let artifactDir = URL(fileURLWithPath: firstPath).deletingLastPathComponent()
        if artifactDir.lastPathComponent.hasPrefix("attempt_") {
            return artifactDir.deletingLastPathComponent()
        }
        return artifactDir
    }

    static func icon(for artifact: ArtifactRef) -> String {
        switch groupMetadata(for: artifact).id {
        case "source": return "chevron.left.forwardslash.chevron.right"
        case "spec": return "slider.horizontal.3"
        case "summary": return "list.bullet.rectangle"
        case "log": return "terminal"
        case "data": return "chart.xyaxis.line"
        default: return "doc"
        }
    }

    static func isTextArtifact(_ artifact: ArtifactRef) -> Bool {
        let ext = URL(fileURLWithPath: artifact.relativePath).pathExtension.lowercased()
        return ["cc", "cpp", "c", "h", "hpp", "json", "txt", "log", "csv", "dat"].contains(ext)
    }

    private static func groupMetadata(for artifact: ArtifactRef) -> (id: String, title: String, icon: String, order: Int) {
        switch artifact.kind {
        case "source":
            return ("source", "Generated Code", "chevron.left.forwardslash.chevron.right", 0)
        case "spec":
            return ("spec", "Simulation Spec", "slider.horizontal.3", 1)
        case "summary", "summary_json":
            return ("summary", "Summary", "list.bullet.rectangle", 2)
        case "log":
            return ("log", "Logs", "terminal", 3)
        case "data", "plot":
            return ("data", "Plots and Tables", "chart.xyaxis.line", 4)
        default:
        return ("other", "Other Evidence", "doc", 5)
        }
    }

    private static func groupMetadata(forGroupId groupId: String) -> (id: String, title: String, icon: String, order: Int) {
        switch groupId {
        case "source":
            return ("source", "Generated Code", "chevron.left.forwardslash.chevron.right", 0)
        case "spec":
            return ("spec", "Simulation Spec", "slider.horizontal.3", 1)
        case "summary":
            return ("summary", "Summary", "list.bullet.rectangle", 2)
        case "log":
            return ("log", "Logs", "terminal", 3)
        case "data":
            return ("data", "Plots and Tables", "chart.xyaxis.line", 4)
        default:
            return ("other", "Other Evidence", "doc", 5)
        }
    }

    private static func discoveredArtifacts(for run: SimulationRun) -> [ArtifactRef] {
        let fm = FileManager.default
        let runFolder = PathUtils.simulationsDir.appendingPathComponent(run.id, isDirectory: true)
        guard let attemptDirs = try? fm.contentsOfDirectory(
            at: runFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sortedAttemptDirs = attemptDirs.filter { url in
            guard url.lastPathComponent.hasPrefix("attempt_") else { return false }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var artifacts: [ArtifactRef] = []
        for attemptDir in sortedAttemptDirs {
            for expected in expectedEvidenceNames {
                appendIfPresent(
                    attemptDir.appendingPathComponent(expected.name),
                    kind: expected.kind,
                    run: run,
                    into: &artifacts
                )
            }

            guard let files = try? fm.contentsOfDirectory(
                at: attemptDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = file.lastPathComponent
                let ext = file.pathExtension.lowercased()
                guard !standaloneEvidenceNames.contains(name),
                      ["txt", "csv", "dat"].contains(ext) else {
                    continue
                }
                appendIfPresent(file, kind: "data", run: run, into: &artifacts)
            }
        }

        return artifacts
    }

    private static func appendIfPresent(_ url: URL, kind: String, run: SimulationRun, into artifacts: inout [ArtifactRef]) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        artifacts.append(
            ArtifactRef(
                id: "discovered-\(run.id)-\(url.path.hashValue)",
                kind: kind,
                label: url.lastPathComponent,
                relativePath: url.path,
                createdAt: run.completedAt ?? run.updatedAt
            )
        )
    }
}

private enum RunEvidenceActions {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func reveal(url: URL) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

private struct RunBundleExportResult: Identifiable {
    let id = UUID()
    let bundleURL: URL
    let entries: [RunBundleExporter.BundleArtifact]
    let missingArtifacts: [RunBundleExporter.MissingArtifact]
    let missingExpectedArtifacts: [String]
}

private enum RunBundleExporter {
    struct BundleArtifact: Codable {
        let label: String
        let kind: String
        let path: String
        let byteSize: UInt64

        enum CodingKeys: String, CodingKey {
            case label
            case kind
            case path
            case byteSize = "byte_size"
        }
    }

    struct MissingArtifact: Codable {
        let label: String
        let kind: String
        let sourcePath: String

        enum CodingKeys: String, CodingKey {
            case label
            case kind
            case sourcePath = "source_path"
        }
    }

    private struct BundleManifest: Codable {
        let formatVersion: Int
        let exportedAt: String
        let appName: String
        let threadId: String
        let run: RunSummary
        let configuration: [String: String]
        let simulationSpec: [String: String]
        let summaryMetrics: [String: String]
        let charts: [ChartSummary]
        let artifacts: [BundleArtifact]
        let missingArtifacts: [MissingArtifact]
        let missingExpectedArtifacts: [String]

        enum CodingKeys: String, CodingKey {
            case formatVersion = "format_version"
            case exportedAt = "exported_at"
            case appName = "app_name"
            case threadId = "thread_id"
            case run
            case configuration
            case simulationSpec = "simulation_spec"
            case summaryMetrics = "summary_metrics"
            case charts
            case artifacts
            case missingArtifacts = "missing_artifacts"
            case missingExpectedArtifacts = "missing_expected_artifacts"
        }
    }

    private struct RunSummary: Codable {
        let id: String
        let title: String
        let status: String
        let eventCount: Int?
        let crossSection: Double?
        let createdAt: String
        let updatedAt: String
        let completedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case status
            case eventCount = "event_count"
            case crossSection = "cross_section"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case completedAt = "completed_at"
        }
    }

    private struct ChartSummary: Codable {
        let title: String
        let chartType: String
        let seriesCount: Int
        let pointCount: Int
        let metricCount: Int

        enum CodingKeys: String, CodingKey {
            case title
            case chartType = "chart_type"
            case seriesCount = "series_count"
            case pointCount = "point_count"
            case metricCount = "metric_count"
        }
    }

    private static let expectedArtifactNames = [
        "run.cc",
        "simulation_spec.json",
        "summary.json",
        "summary_lines.txt",
        "compile.log",
        "run.log"
    ]

    static func export(
        run: SimulationRun,
        artifacts: [ArtifactRef],
        chartPayloads: [ChartPayload],
        toParentDirectory parentURL: URL
    ) throws -> RunBundleExportResult {
        let fm = FileManager.default
        let bundleURL = try uniqueBundleURL(parentURL: parentURL, run: run)
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        var usedRelativePaths = Set<String>()
        var copiedArtifacts: [BundleArtifact] = []
        let existingArtifacts = artifacts.filter { fm.fileExists(atPath: $0.relativePath) }
        let missingArtifacts = artifacts
            .filter { !fm.fileExists(atPath: $0.relativePath) }
            .sorted(by: artifactSort)
            .map {
                MissingArtifact(
                    label: $0.label,
                    kind: $0.kind,
                    sourcePath: $0.relativePath
                )
            }

        for artifact in existingArtifacts.sorted(by: artifactSort) {
            let sourceURL = URL(fileURLWithPath: artifact.relativePath)
            let relativePath = uniqueRelativePath(
                preferredFileName: sourceURL.lastPathComponent,
                usedRelativePaths: &usedRelativePaths
            )
            let destinationURL = bundleURL.appendingPathComponent(relativePath)
            try fm.copyItem(at: sourceURL, to: destinationURL)

            copiedArtifacts.append(
                BundleArtifact(
                    label: artifact.label,
                    kind: artifact.kind,
                    path: relativePath,
                    byteSize: fileSize(for: destinationURL)
                )
            )
        }

        let copiedNames = Set(copiedArtifacts.map { URL(fileURLWithPath: $0.path).lastPathComponent })
        let missingExpectedArtifacts = expectedArtifactNames.filter { !copiedNames.contains($0) }
        let simulationSpec = flattenedJSONValues(from: bundleURL.appendingPathComponent("simulation_spec.json"))
        let summaryMetrics = flattenedJSONValues(from: bundleURL.appendingPathComponent("summary.json"))
        let chartSummaries = chartPayloads.map { chart in
            ChartSummary(
                title: chart.title,
                chartType: chart.chartType.rawValue,
                seriesCount: chart.series.count,
                pointCount: chart.series.reduce(0) { $0 + $1.points.count },
                metricCount: chart.metrics.count
            )
        }

        let manifest = BundleManifest(
            formatVersion: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            appName: "Vidura Labs",
            threadId: run.threadId,
            run: RunSummary(
                id: run.id,
                title: run.title,
                status: run.status.rawValue,
                eventCount: run.eventCount,
                crossSection: run.crossSection,
                createdAt: run.createdAt,
                updatedAt: run.updatedAt,
                completedAt: run.completedAt
            ),
            configuration: run.configuration,
            simulationSpec: simulationSpec,
            summaryMetrics: summaryMetrics,
            charts: chartSummaries,
            artifacts: copiedArtifacts,
            missingArtifacts: missingArtifacts,
            missingExpectedArtifacts: missingExpectedArtifacts
        )

        try writeJSON(manifest, to: bundleURL.appendingPathComponent("manifest.json"))
        try runReport(
            run: run,
            simulationSpec: simulationSpec,
            summaryMetrics: summaryMetrics,
            charts: chartSummaries,
            artifacts: copiedArtifacts,
            missingArtifacts: missingArtifacts,
            missingExpectedArtifacts: missingExpectedArtifacts
        ).write(
            to: bundleURL.appendingPathComponent("run_report.md"),
            atomically: true,
            encoding: .utf8
        )

        return RunBundleExportResult(
            bundleURL: bundleURL,
            entries: copiedArtifacts,
            missingArtifacts: missingArtifacts,
            missingExpectedArtifacts: missingExpectedArtifacts
        )
    }

    private static func uniqueBundleURL(parentURL: URL, run: SimulationRun) throws -> URL {
        let fm = FileManager.default
        let title = sanitizedFileName(run.title)
        let shortId = String(run.id.prefix(8))
        let baseName = title.isEmpty
            ? "vidura-run-\(shortId)"
            : "vidura-run-\(title)-\(shortId)"

        var candidate = parentURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces = value
            .lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
        return String(pieces.joined(separator: "-").prefix(48))
    }

    private nonisolated static func artifactSort(_ lhs: ArtifactRef, _ rhs: ArtifactRef) -> Bool {
        if lhs.label != rhs.label {
            return lhs.label < rhs.label
        }
        return lhs.relativePath < rhs.relativePath
    }

    private static func uniqueRelativePath(
        preferredFileName: String,
        usedRelativePaths: inout Set<String>
    ) -> String {
        let url = URL(fileURLWithPath: preferredFileName)
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = preferredFileName
        var suffix = 2

        while usedRelativePaths.contains(candidate) {
            candidate = ext.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(ext)"
            suffix += 1
        }

        usedRelativePaths.insert(candidate)
        return candidate
    }

    private static func fileSize(for url: URL) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.uint64Value
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func flattenedJSONValues(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        return flattenSummaryMetrics(object)
    }

    private static func flattenSummaryMetrics(_ value: Any, prefix: String = "") -> [String: String] {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [:]) { result, pair in
                let key = prefix.isEmpty ? pair.key : "\(prefix).\(pair.key)"
                result.merge(flattenSummaryMetrics(pair.value, prefix: key), uniquingKeysWith: { _, new in new })
            }
        }

        if let array = value as? [Any] {
            return [prefix: "\(array.count) items"]
        }

        if let number = value as? NSNumber {
            return [prefix: number.stringValue]
        }

        if let string = value as? String {
            return [prefix: string]
        }

        if value is NSNull {
            return [prefix: "null"]
        }

        return [prefix: String(describing: value)]
    }

    private static func runReport(
        run: SimulationRun,
        simulationSpec: [String: String],
        summaryMetrics: [String: String],
        charts: [ChartSummary],
        artifacts: [BundleArtifact],
        missingArtifacts: [MissingArtifact],
        missingExpectedArtifacts: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("# Vidura Run Bundle")
        lines.append("")
        lines.append("## Run")
        lines.append("")
        lines.append("- Title: \(run.title)")
        lines.append("- Run ID: \(run.id)")
        lines.append("- Thread ID: \(run.threadId)")
        lines.append("- Status: \(run.status.displayName)")
        if let eventCount = run.eventCount {
            lines.append("- Event count: \(eventCount)")
        }
        if let crossSection = run.crossSection {
            lines.append("- Cross section: \(crossSection)")
        }
        lines.append("- Created: \(run.createdAt)")
        lines.append("- Updated: \(run.updatedAt)")
        if let completedAt = run.completedAt {
            lines.append("- Completed: \(completedAt)")
        }

        lines.append("")
        lines.append("## Configuration")
        lines.append("")
        if run.configuration.isEmpty {
            lines.append("No run configuration was persisted.")
        } else {
            for key in run.configuration.keys.sorted() {
                lines.append("- `\(key)`: \(run.configuration[key] ?? "")")
            }
        }

        lines.append("")
        lines.append("## Simulation Spec")
        lines.append("")
        if simulationSpec.isEmpty {
            lines.append("No simulation spec metadata was available.")
        } else {
            for key in simulationSpec.keys.sorted() {
                lines.append("- `\(key)`: \(simulationSpec[key] ?? "")")
            }
        }

        lines.append("")
        lines.append("## Summary Metrics")
        lines.append("")
        if summaryMetrics.isEmpty {
            lines.append("No summary metrics were available.")
        } else {
            for key in summaryMetrics.keys.sorted() {
                lines.append("- `\(key)`: \(summaryMetrics[key] ?? "")")
            }
        }

        lines.append("")
        lines.append("## Charts")
        lines.append("")
        if charts.isEmpty {
            lines.append("No chart payloads were available in the current thread context.")
        } else {
            for chart in charts {
                lines.append("- \(chart.title): \(chart.pointCount) points across \(chart.seriesCount) series")
            }
        }

        lines.append("")
        lines.append("## Artifacts")
        lines.append("")
        if artifacts.isEmpty {
            lines.append("No artifact files were copied.")
        } else {
            for artifact in artifacts {
                lines.append("- `\(artifact.path)` (\(artifact.kind), \(artifact.byteSize) bytes)")
            }
        }

        if !missingArtifacts.isEmpty {
            lines.append("")
            lines.append("## Missing Artifact References")
            lines.append("")
            for artifact in missingArtifacts {
                lines.append("- `\(artifact.label)` (\(artifact.kind)) expected at `\(artifact.sourcePath)`")
            }
        }

        if !missingExpectedArtifacts.isEmpty {
            lines.append("")
            lines.append("## Missing Expected Artifacts")
            lines.append("")
            for name in missingExpectedArtifacts {
                lines.append("- `\(name)`")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}

private struct ArtifactViewer: View {
    let title: String
    let artifact: ArtifactRef
    @Environment(\.dismiss) private var dismiss

    private var content: String {
        (try? String(contentsOfFile: artifact.relativePath, encoding: .utf8))
            ?? "Unable to read artifact at:\n\(artifact.relativePath)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: RunEvidenceResolver.icon(for: artifact))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(artifact.label)
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    RunEvidenceActions.copy(content)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy Contents")

                Button {
                    RunEvidenceActions.copy(artifact.relativePath)
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy Path")

                Button {
                    RunEvidenceActions.reveal(url: URL(fileURLWithPath: artifact.relativePath))
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal in Finder")

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ArtifactTextView(content: content, fileName: artifact.label)
        }
        .frame(minWidth: 700, idealWidth: 850, minHeight: 500, idealHeight: 700)
    }
}

/// NSViewRepresentable that wraps an NSTextView for read-only artifact display.
private struct ArtifactTextView: NSViewRepresentable {
    let content: String
    let fileName: String

    // Extracted to a static constant so the preview thunk does not wrap
    // each element with __designTimeString, which overwhelms the type-checker.
    private static let cppKeywords: [String] = [
        "auto", "break", "case", "catch", "class", "const", "constexpr",
        "continue", "default", "delete", "do", "double", "else", "enum",
        "explicit", "extern", "false", "float", "for", "friend", "goto",
        "if", "inline", "int", "long", "namespace", "new", "nullptr",
        "operator", "private", "protected", "public", "return", "short",
        "signed", "sizeof", "static", "struct", "switch", "template",
        "this", "throw", "true", "try", "typedef", "typename", "unsigned",
        "using", "virtual", "void", "volatile", "while", "bool", "char",
        "include", "define", "ifdef", "ifndef", "endif", "pragma"
    ]

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true

        // Line number gutter via ruler
        scrollView.hasVerticalRuler = false
        scrollView.rulersVisible = false

        textView.textStorage?.setAttributedString(Self.attributedContent(content, fileName: fileName))

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(Self.attributedContent(content, fileName: fileName))
    }

    // MARK: - Text Highlighting

    private static func attributedContent(_ content: String, fileName: String) -> NSAttributedString {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        if ["cc", "cpp", "c", "h", "hpp"].contains(ext) {
            return highlightCpp(content)
        }

        return NSAttributedString(
            string: content,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
        )
    }

    /// Applies basic C++ syntax highlighting to the source string.
    private static func highlightCpp(_ source: String) -> NSAttributedString {
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let baseColor = NSColor.textColor

        let result = NSMutableAttributedString(
            string: source,
            attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ]
        )

        let fullRange = NSRange(location: 0, length: (source as NSString).length)

        // Keywords
        let keywordColor = NSColor.systemPink
        let keywordPattern = "\\b(" + cppKeywords.joined(separator: "|") + ")\\b"
        applyPattern(keywordPattern, to: result, in: fullRange, color: keywordColor, font: baseFont)

        // Preprocessor directives: lines starting with #
        let preprocessorColor = NSColor.systemOrange
        applyPattern("^\\s*#.*$", to: result, in: fullRange, color: preprocessorColor, font: baseFont, options: .anchorsMatchLines)

        // Strings: "..." and <...> in includes
        let stringColor = NSColor.systemRed
        applyPattern("\"[^\"\\\\]*(\\\\.[^\"\\\\]*)*\"", to: result, in: fullRange, color: stringColor, font: baseFont)
        applyPattern("<[^>]+>", to: result, in: fullRange, color: stringColor, font: baseFont)

        // Numbers
        let numberColor = NSColor.systemBlue
        applyPattern("\\b\\d+(\\.\\d+)?([eE][+-]?\\d+)?\\b", to: result, in: fullRange, color: numberColor, font: baseFont)

        // Single-line comments
        let commentColor = NSColor.systemGreen
        applyPattern("//.*$", to: result, in: fullRange, color: commentColor, font: baseFont, options: .anchorsMatchLines)

        // Multi-line comments
        applyPattern("/\\*[\\s\\S]*?\\*/", to: result, in: fullRange, color: commentColor, font: baseFont, options: .dotMatchesLineSeparators)

        return result
    }

    private static func applyPattern(
        _ pattern: String,
        to attrString: NSMutableAttributedString,
        in range: NSRange,
        color: NSColor,
        font: NSFont,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        regex.enumerateMatches(in: attrString.string, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            attrString.addAttribute(.foregroundColor, value: color, range: matchRange)
        }
    }
}

// MARK: - Input Bar

private struct InputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSubmit: () -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message...", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .disabled(isLoading)
                .onSubmit {
                    onSubmit()
                }

            Button(action: onSubmit) {
                Group {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(trimmedText.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(trimmedText.isEmpty || isLoading)
            .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Previews

#Preview("Welcome - No Thread") {
    let store = ResearchStore.preview(
        projects: [
            ResearchProject(id: "p1", title: "physics_teammate", description: "", createdAt: "", updatedAt: ""),
            ResearchProject(id: "p2", title: "deephedging", description: "", createdAt: "", updatedAt: ""),
            ResearchProject(id: "p3", title: "VisuSurface", description: "", createdAt: "", updatedAt: "")
        ]
    )
    let settings = SettingsStore.preview()
    WelcomeDetailView(selectedThreadId: .constant(nil))
        .environmentObject(store)
        .environmentObject(OrchestratorService(store: store, settingsStore: settings))
        .frame(width: 800, height: 600)
}

#Preview("Welcome - Thread (no runs)") {
    let store = ResearchStore.preview(
        projects: [
            ResearchProject(id: "p1", title: "QCD Studies", description: "", createdAt: "", updatedAt: "")
        ],
        threads: [
            ResearchThread(id: "t1", projectId: "p1", title: "Dijet Analysis", description: "", createdAt: "", updatedAt: "")
        ],
        runs: []
    )
    let settings = SettingsStore.preview()
    ResearchThreadDetailView(threadId: "t1", selectedThreadId: .constant("t1"))
        .environmentObject(store)
        .environmentObject(OrchestratorService(store: store, settingsStore: settings))
        .frame(width: 800, height: 600)
}

#Preview("Conversation") {
    let store = ResearchStore.preview(
        projects: [
            ResearchProject(id: "p1", title: "QCD Studies", description: "", createdAt: "", updatedAt: "")
        ],
        threads: [
            ResearchThread(id: "t1", projectId: "p1", title: "Dijet Analysis", description: "", createdAt: "", updatedAt: "")
        ],
        runs: [
            SimulationRun(
                id: "r1", threadId: "t1", title: "QCD Dijets 13TeV",
                status: .completed,
                configuration: ["Beams:eCM": "13000", "HardQCD:all": "on"],
                artifacts: [],
                resultSummary: "10k events generated successfully",
                eventCount: 10000,
                crossSection: 2.34,
                errorMessage: nil,
                createdAt: "2026-03-22T12:00:00Z",
                updatedAt: "2026-03-22T12:03:00Z",
                completedAt: "2026-03-22T12:01:00Z"
            ),
            SimulationRun(
                id: "r2", threadId: "t1", title: "Z Boson Run",
                status: .running,
                configuration: ["WeakSingleBoson:ffbar2gmZ": "on"],
                artifacts: [],
                resultSummary: nil,
                eventCount: nil,
                crossSection: nil,
                errorMessage: nil,
                createdAt: "2026-03-22T13:00:00Z",
                updatedAt: "2026-03-22T13:00:00Z",
                completedAt: nil
            )
        ],
        messages: [
            ChatMessage(id: "m1", role: "user", content: "Run a QCD dijet simulation at 13 TeV with 10000 events", timestamp: "2026-03-22T12:00:00Z", originRunId: "r1", sender: .user),
            ChatMessage(id: "m2", role: "assistant", content: "Simulation complete. Generated 10,000 events with σ = 2.34 mb. The dijet pT spectrum shows the expected power-law falloff.", timestamp: "2026-03-22T12:01:00Z", originRunId: "r1", sender: .result),
            ChatMessage(id: "m3", role: "user", content: "Can you show the pT distribution?", timestamp: "2026-03-22T12:02:00Z", originRunId: "r1", sender: .user),
            ChatMessage(id: "m4", role: "assistant", content: "Here is the transverse momentum distribution for the leading jet. The spectrum peaks around 20 GeV and falls steeply, consistent with perturbative QCD predictions.", timestamp: "2026-03-22T12:03:00Z", originRunId: "r1", sender: .guide),
            ChatMessage(id: "m5", role: "user", content: "Simulate Z boson production with leptonic decay", timestamp: "2026-03-22T13:00:00Z", originRunId: "r2", sender: .user)
        ]
    )
    let settings = SettingsStore.preview()
    ResearchThreadDetailView(threadId: "t1", selectedThreadId: .constant("t1"))
        .environmentObject(store)
        .environmentObject(OrchestratorService(store: store, settingsStore: settings))
        .frame(width: 800, height: 600)
}
