//
//  ResearchStore.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import Foundation
import SwiftUI
import GRDB
import Combine

// MARK: - ResearchStore
// Persistence layer for the research hierarchy:
//   Research Project → Research Thread → Run
//
// Uses GRDB with raw SQL, following the same patterns as SettingsStore.
//
// Table schemas
// ┌────────────────────────────────────────────────────────────────────┐
// │ research_projects                                                  │
// ├──────────────┬─────────┬───────────────────────────────────────────┤
// │ id           │ TEXT    │ PRIMARY KEY (UUID)                        │
// │ title        │ TEXT    │ NOT NULL                                  │
// │ description  │ TEXT    │ NOT NULL DEFAULT ''                       │
// │ created_at   │ TEXT    │ NOT NULL DEFAULT datetime('now')          │
// │ updated_at   │ TEXT    │ NOT NULL DEFAULT datetime('now')          │
// └──────────────┴─────────┴───────────────────────────────────────────┘
//
// ┌────────────────────────────────────────────────────────────────────┐
// │ research_threads                                                   │
// ├──────────────┬─────────┬───────────────────────────────────────────┤
// │ id           │ TEXT    │ PRIMARY KEY (UUID)                        │
// │ project_id   │ TEXT    │ NOT NULL FK → research_projects ON DELETE │
// │              │         │ CASCADE                                   │
// │ title        │ TEXT    │ NOT NULL                                  │
// │ description  │ TEXT    │ NOT NULL DEFAULT ''                       │
// │ created_at   │ TEXT    │ NOT NULL DEFAULT datetime('now')          │
// │ updated_at   │ TEXT    │ NOT NULL DEFAULT datetime('now')          │
// └──────────────┴─────────┴───────────────────────────────────────────┘
//
// ┌────────────────────────────────────────────────────────────────────┐
// │ runs                                                               │
// ├────────────────┬─────────┬─────────────────────────────────────────┤
// │ id             │ TEXT    │ PRIMARY KEY (UUID)                      │
// │ thread_id      │ TEXT    │ NOT NULL FK → research_threads ON DELETE│
// │                │         │ CASCADE                                 │
// │ title          │ TEXT    │ NOT NULL                                │
// │ status         │ TEXT    │ NOT NULL DEFAULT 'pending'              │
// │ configuration  │ TEXT    │ NOT NULL DEFAULT '{}'  (JSON)           │
// │ artifacts      │ TEXT    │ NOT NULL DEFAULT '[]'  (JSON)           │
// │ result_summary │ TEXT    │ nullable                                │
// │ event_count    │ INTEGER │ nullable                                │
// │ cross_section  │ REAL    │ nullable                                │
// │ error_message  │ TEXT    │ nullable                                │
// │ created_at     │ TEXT    │ NOT NULL DEFAULT datetime('now')        │
// │ updated_at     │ TEXT    │ NOT NULL DEFAULT datetime('now')        │
// │ completed_at   │ TEXT    │ nullable                                │
// └────────────────┴─────────┴─────────────────────────────────────────┘
// ┌──────────────────────────────────────────────────────────────────────────┐
// │ messages                                                                 │
// ├────────────────────┬─────────┬───────────────────────────────────────────┤
// │ id                 │ TEXT    │ PRIMARY KEY (UUID)                        │
// │ run_id             │ TEXT    │ NOT NULL FK → runs ON DELETE CASCADE      │
// │ parent_message_id  │ TEXT    │ FK → messages ON DELETE CASCADE           │
// │ role               │ TEXT    │ NOT NULL DEFAULT ''                       │
// | content            | TEXT    | NOT NULL                                  |
// | chart_payload      | TEXT    | nullable                                  |
// │ created_at         │ TEXT    │ NOT NULL DEFAULT datetime('now')          │
// └────────────────────┴─────────┴───────────────────────────────────────────┘
//

// MARK: - JSON Sub-Models

/// Identifies which agent produced a chat message.
enum MessageSender: String, Codable, Sendable {
    case user     = "user"
    case guide    = "guide"
    case result   = "result"
    case plotting = "plotting"
    case reviewer = "reviewer"
}

struct ChatMessage: Codable, Sendable, Identifiable {
    let id: String
    let role: String        // "user" | "assistant" | "system"
    let content: String
    let timestamp: String   // ISO-8601
    let chartPayload: ChartPayload?
    let originRunId: String?
    let parentMessageId: String?
    let sender: MessageSender
    
    init(id: String, role: String, content: String,
         timestamp: String, chartPayload: ChartPayload? = nil,
         originRunId: String? = nil, parentMessageId: String? = nil,
         sender: MessageSender = .user) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.chartPayload = chartPayload
        self.originRunId = originRunId
        self.parentMessageId = parentMessageId
        self.sender = sender
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, sender
        case chartPayload = "chart_payload"
        case originRunId = "origin_run_id"
        case parentMessageId = "parent_message_id"
    }
}

struct ArtifactRef: Codable, Sendable, Identifiable {
    let id: String
    let kind: String        // "plot" | "data" | "log" | "hepmc" | "other"
    let label: String
    let relativePath: String
    let createdAt: String
}

// MARK: - Run Status

enum RunStatus: String, Sendable, CaseIterable {
    case pending
    case queued
    case guide
    case discovery
    case codegen
    case compile
    case running
    case completed
    case failed

    /// Alias: the backend uses "succeeded" but we map to .completed
    static func fromBackend(_ raw: String) -> RunStatus {
        switch raw {
        case "succeeded": return .completed
        default: return RunStatus(rawValue: raw) ?? .pending
        }
    }
}

// MARK: - RunStatus UI Helpers

extension RunStatus {
    var displayName: String {
        switch self {
        case .pending:   return "Pending"
        case .queued:    return "Queued"
        case .guide:     return "Guide"
        case .discovery: return "Discovery"
        case .codegen:   return "Codegen"
        case .compile:   return "Compiling"
        case .running:   return "Running"
        case .completed: return "Completed"
        case .failed:    return "Failed"
        }
    }

    var iconName: String {
        switch self {
        case .pending:   return "clock"
        case .queued:    return "hourglass"
        case .guide:     return "text.bubble"
        case .discovery: return "magnifyingglass"
        case .codegen:   return "chevron.left.forwardslash.chevron.right"
        case .compile:   return "hammer"
        case .running:   return "bolt.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:   return .gray
        case .queued:    return .gray
        case .guide:     return .blue
        case .discovery: return .purple
        case .codegen:   return .orange
        case .compile:   return .yellow
        case .running:   return .yellow
        case .completed: return .green
        case .failed:    return .red
        }
    }

    /// Whether this status represents an active/in-progress state
    var isActive: Bool {
        switch self {
        case .queued, .guide, .discovery, .codegen, .compile, .running:
            return true
        default:
            return false
        }
    }
}

// MARK: - Entity Models

struct ResearchProject: Sendable, Identifiable {
    let id: String
    var title: String
    var description: String
    let createdAt: String
    var updatedAt: String
}

struct ResearchThread: Sendable, Identifiable {
    let id: String
    let projectId: String
    var title: String
    var description: String
    let createdAt: String
    var updatedAt: String
}

struct SimulationRun: Sendable, Identifiable {
    let id: String
    let threadId: String
    var title: String
    var status: RunStatus
    var configuration: [String: String]
    var artifacts: [ArtifactRef]
    var resultSummary: String?
    var eventCount: Int?
    var crossSection: Double?
    var errorMessage: String?
    let createdAt: String
    var updatedAt: String
    var completedAt: String?
}

// MARK: - Error

enum ResearchStoreError: LocalizedError {
    case connectionError(String)
    case dbError(String)
    case insertError(String)
    case fetchError(String)
    case updateError(String)
    case deleteError(String)
    case notFound(String)
    case encodingError(String)

    var errorDescription: String? {
        switch self {
        case .connectionError(let m): return "Research DB connection error: \(m)"
        case .dbError(let m):         return "Research DB error: \(m)"
        case .insertError(let m):     return "Research DB insert error: \(m)"
        case .fetchError(let m):      return "Research DB fetch error: \(m)"
        case .updateError(let m):     return "Research DB update error: \(m)"
        case .deleteError(let m):     return "Research DB delete error: \(m)"
        case .notFound(let m):        return "Not found: \(m)"
        case .encodingError(let m):   return "JSON encoding error: \(m)"
        }
    }
}

// MARK: - Store

@MainActor
final class ResearchStore: ObservableObject {

    private static let defaultProjectId = "project-default"
    private static let defaultProjectTitle = "Default"

    // MARK: Published State
    @Published private(set) var projects: [ResearchProject] = []
    @Published private(set) var threads: [ResearchThread] = []
    @Published private(set) var runs: [SimulationRun] = []
    @Published private(set) var messages: [ChatMessage] = []

    // MARK: Private
    private let db: DatabaseQueue
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init (async factory)

    static func connect() async throws -> ResearchStore {
        let path = PathUtils.researchDbPath

        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let queue: DatabaseQueue
        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
            queue = try DatabaseQueue(path: path.path, configuration: config)
        } catch {
            throw ResearchStoreError.connectionError(error.localizedDescription)
        }

        let store = ResearchStore(db: queue)
        try await store.createTablesIfNeeded()
        try await store.ensureDefaultProjectExists()
        try await store.loadProjects()
        return store
    }

    private init(db: DatabaseQueue) {
        self.db = db
    }

    /// In-memory store for SwiftUI previews and tests.
    static func preview(
        projects: [ResearchProject] = [],
        threads: [ResearchThread] = [],
        runs: [SimulationRun] = [],
        messages: [ChatMessage] = []
    ) -> ResearchStore {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try! DatabaseQueue(configuration: config)

        // Create tables so queries don't crash
        try! queue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS research_projects (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS research_threads (
                    id TEXT PRIMARY KEY,
                    project_id TEXT NOT NULL REFERENCES research_projects(id) ON DELETE CASCADE,
                    title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS runs (
                    id TEXT PRIMARY KEY,
                    thread_id TEXT NOT NULL REFERENCES research_threads(id) ON DELETE CASCADE,
                    title TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
                    configuration TEXT NOT NULL DEFAULT '{}',
                    artifacts TEXT NOT NULL DEFAULT '[]',
                    result_summary TEXT, event_count INTEGER, cross_section REAL,
                    error_message TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
                    completed_at TEXT
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,                    -- UUID
                    run_id TEXT NOT NULL,                   -- FK to runs
                    parent_message_id TEXT,                 -- FK to messages(id), NULL if it's the very first message
                    role TEXT NOT NULL,                     -- e.g., 'user', 'assistant', 'system'
                    content TEXT NOT NULL DEFAULT '',       -- The actual message text
                    chart_payload TEXT,
                    sender TEXT NOT NULL DEFAULT 'user',    -- 'user', 'guide', 'result', 'plotting'
                    created_at TEXT NOT NULL,
                    
                    FOREIGN KEY(run_id) REFERENCES runs(id) ON DELETE CASCADE,
                    FOREIGN KEY(parent_message_id) REFERENCES messages(id) ON DELETE SET NULL
                );
            """)
        }

        let store = ResearchStore(db: queue)

        // Seed the DB with the provided preview data so that load*() queries return it
        let encoder = JSONEncoder()
        try! queue.write { db in
            // Projects
            for p in projects {
                try db.execute(
                    sql: """
                        INSERT INTO research_projects (id, title, description, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [p.id, p.title, p.description, p.createdAt, p.updatedAt]
                )
            }

            // Threads
            for t in threads {
                try db.execute(
                    sql: """
                        INSERT INTO research_threads (id, project_id, title, description, created_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [t.id, t.projectId, t.title, t.description, t.createdAt, t.updatedAt]
                )
            }

            // Runs
            for r in runs {
                let configJson = String(data: try encoder.encode(r.configuration), encoding: .utf8) ?? "{}"
                let artifactsJson = String(data: try encoder.encode(r.artifacts), encoding: .utf8) ?? "[]"

                try db.execute(
                    sql: """
                        INSERT INTO runs (
                            id, thread_id, title, status, configuration, artifacts,
                            result_summary, event_count, cross_section, error_message,
                            created_at, updated_at, completed_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        r.id, r.threadId, r.title, r.status.rawValue, configJson, artifactsJson,
                        r.resultSummary, r.eventCount, r.crossSection, r.errorMessage,
                        r.createdAt, r.updatedAt, r.completedAt
                    ]
                )
            }
            
            for m in messages {
                try db.execute(sql: "INSERT INTO messages (id, run_id, parent_message_id, role, content, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                               arguments: [m.id, m.originRunId, m.parentMessageId, m.role, m.content, m.timestamp])
            }
        }

        // Keep the in-memory Published state; .task loaders will query the DB and match these
        store.projects = projects
        store.threads = threads
        store.runs = runs
        return store
    }

    // MARK: - Table Setup

    private func createTablesIfNeeded() async throws {
        do {
            try await db.write { db in
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS research_projects (
                        id          TEXT PRIMARY KEY,
                        title       TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT '',
                        created_at  TEXT NOT NULL DEFAULT (datetime('now')),
                        updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
                    )
                """)

                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS research_threads (
                        id          TEXT PRIMARY KEY,
                        project_id  TEXT NOT NULL
                            REFERENCES research_projects(id) ON DELETE CASCADE,
                        title       TEXT NOT NULL,
                        description TEXT NOT NULL DEFAULT '',
                        created_at  TEXT NOT NULL DEFAULT (datetime('now')),
                        updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
                    )
                """)

                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS runs (
                        id              TEXT PRIMARY KEY,
                        thread_id       TEXT NOT NULL
                            REFERENCES research_threads(id) ON DELETE CASCADE,
                        title           TEXT NOT NULL,
                        status          TEXT NOT NULL DEFAULT 'pending',
                        configuration   TEXT NOT NULL DEFAULT '{}',
                        artifacts       TEXT NOT NULL DEFAULT '[]',
                        result_summary  TEXT,
                        event_count     INTEGER,
                        cross_section   REAL,
                        error_message   TEXT,
                        created_at      TEXT NOT NULL DEFAULT (datetime('now')),
                        updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
                        completed_at    TEXT
                    )
                """)
                
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS messages (
                        id TEXT PRIMARY KEY,                    -- UUID
                        run_id TEXT NOT NULL,                   -- FK to runs
                        parent_message_id TEXT,                 -- FK to messages(id), NULL if it's the very first message
                        role TEXT NOT NULL,                     -- e.g., 'user', 'assistant', 'system'
                        content TEXT NOT NULL DEFAULT '',       -- The actual message text
                        chart_payload TEXT,
                        sender TEXT NOT NULL DEFAULT 'user',    -- 'user', 'guide', 'result', 'plotting'
                        created_at TEXT NOT NULL,
                        
                        FOREIGN KEY(run_id) REFERENCES runs(id) ON DELETE CASCADE,
                        FOREIGN KEY(parent_message_id) REFERENCES messages(id) ON DELETE SET NULL
                    );
                """)

                // Migration: add sender column for existing databases
                let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(messages)")
                let columnNames = columns.map { $0["name"] as String }
                if !columnNames.contains("sender") {
                    try db.execute(sql: "ALTER TABLE messages ADD COLUMN sender TEXT NOT NULL DEFAULT 'user'")
                }
            }
        } catch {
            throw ResearchStoreError.dbError(error.localizedDescription)
        }
    }

    // MARK: - Projects CRUD

    private func ensureDefaultProjectExists() async throws {
        let defaultProjectId = Self.defaultProjectId
        let defaultProjectTitle = Self.defaultProjectTitle

        do {
            try await db.write { db in
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO research_projects (id, title, description)
                        VALUES (?, ?, ?)
                    """,
                    arguments: [defaultProjectId, defaultProjectTitle, ""]
                )
            }
        } catch {
            throw ResearchStoreError.insertError(error.localizedDescription)
        }
    }

    /// Loads all projects, ordered by most recently updated.
    func loadProjects() async throws {
        do {
            let rows: [Row] = try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, title, description, created_at, updated_at
                    FROM research_projects
                    ORDER BY updated_at DESC
                """)
            }
            self.projects = rows.map { row in
                ResearchProject(
                    id: row["id"],
                    title: row["title"],
                    description: row["description"],
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"]
                )
            }
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }

    @discardableResult
    func createProject(title: String, description: String = "") async throws -> ResearchProject {
        let id = UUID().uuidString
        do {
            try await db.write { db in
                try db.execute(
                    sql: "INSERT INTO research_projects (id, title, description) VALUES (?, ?, ?)",
                    arguments: [id, title, description]
                )
            }
        } catch {
            throw ResearchStoreError.insertError(error.localizedDescription)
        }
        try await loadProjects()
        return projects.first { $0.id == id }!
    }

    func updateProject(id: String, title: String? = nil, description: String? = nil) async throws {
        do {
            try await db.write { db in
                if let title {
                    try db.execute(
                        sql: "UPDATE research_projects SET title = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [title, id]
                    )
                }
                if let description {
                    try db.execute(
                        sql: "UPDATE research_projects SET description = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [description, id]
                    )
                }
            }
        } catch {
            throw ResearchStoreError.updateError(error.localizedDescription)
        }
        try await loadProjects()
    }

    func deleteProject(id: String) async throws {
        do {
            try await db.write { db in
                try db.execute(
                    sql: "DELETE FROM research_projects WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
            throw ResearchStoreError.deleteError(error.localizedDescription)
        }
        runs = []
        try await loadAllProjectsAndThreads()
    }

    // MARK: - Threads CRUD

    /// Returns threads for a specific project from the cached list.
    func threads(forProject projectId: String) -> [ResearchThread] {
        threads.filter { $0.projectId == projectId }
    }

    /// Loads all threads across all projects.
    func loadAllThreads() async throws {
        do {
            let rows: [Row] = try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, project_id, title, description, created_at, updated_at
                    FROM research_threads
                    ORDER BY updated_at DESC
                """)
            }
            self.threads = rows.map { row in
                ResearchThread(
                    id: row["id"],
                    projectId: row["project_id"],
                    title: row["title"],
                    description: row["description"],
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"]
                )
            }
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }

    /// Convenience: loads all projects and all threads in one call.
    func loadAllProjectsAndThreads() async throws {
        try await loadProjects()
        try await loadAllThreads()
    }

    /// Loads threads for a single project into the cache.
    func loadThreads(forProject projectId: String) async throws {
        try await loadAllThreads()
    }

    @discardableResult
    func createThread(projectId: String, title: String, description: String = "") async throws -> ResearchThread {
        let id = UUID().uuidString
        do {
            try await db.write { db in
                try db.execute(
                    sql: "INSERT INTO research_threads (id, project_id, title, description) VALUES (?, ?, ?, ?)",
                    arguments: [id, projectId, title, description]
                )
                try db.execute(
                    sql: "UPDATE research_projects SET updated_at = datetime('now') WHERE id = ?",
                    arguments: [projectId]
                )
            }
        } catch {
            throw ResearchStoreError.insertError(error.localizedDescription)
        }
        try await loadAllProjectsAndThreads()
        return threads.first { $0.id == id }!
    }

    func updateThread(id: String, title: String? = nil, description: String? = nil) async throws {
        guard threads.contains(where: { $0.id == id }) else {
            throw ResearchStoreError.notFound("Thread \(id)")
        }
        do {
            try await db.write { db in
                if let title {
                    try db.execute(
                        sql: "UPDATE research_threads SET title = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [title, id]
                    )
                }
                if let description {
                    try db.execute(
                        sql: "UPDATE research_threads SET description = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [description, id]
                    )
                }
            }
        } catch {
            throw ResearchStoreError.updateError(error.localizedDescription)
        }
        try await loadAllThreads()
    }

    func deleteThread(id: String) async throws {
        do {
            try await db.write { db in
                try db.execute(
                    sql: "DELETE FROM research_threads WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
            throw ResearchStoreError.deleteError(error.localizedDescription)
        }
        runs = []
        messages = []
        try await loadAllThreads()
    }

    // MARK: - Messages CRUD
    
    func loadRunMessages(forRun runId: String) async throws {
        do {
            let rows: [Row] = try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT 
                        id, 
                        run_id, 
                        parent_message_id, 
                        role, 
                        content,
                        chart_payload,
                        sender,
                        created_at
                    FROM messages
                    WHERE run_id = ?
                    ORDER BY created_at ASC;
                """, arguments: [runId])
            }
            self.messages = try rows.map { row in try self.messageFromRow(row) }
        } catch let e as ResearchStoreError {
            throw e
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }
    
    func fetchRunMessages(forRun runId: String) async throws -> [ChatMessage] {
        do {
            let rows: [Row] = try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT 
                        id, 
                        run_id, 
                        parent_message_id, 
                        role, 
                        content,
                        chart_payload,
                        sender,
                        created_at
                    FROM messages
                    WHERE run_id = ?
                    ORDER BY created_at ASC;
                """, arguments: [runId])
            }
            return try rows.map { row in try self.messageFromRow(row) }
        } catch let e as ResearchStoreError {
            throw e
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }
    
    func loadThreadMessages(forThread threadId: String) async throws {
        do {
            var messages = [ChatMessage]()
            for run in self.runs.filter({$0.threadId == threadId}) {
                messages.append(contentsOf: try await self.fetchRunMessages(forRun: run.id))
            }
            self.messages = messages
        } catch let e as ResearchStoreError {
            throw e
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }
    
    func loadRunMessagesAndParents(forRun runId: String) async throws {
        do {
            let rows: [Row] = try db.read { db in
                try Row.fetchAll(db, sql: """
                    WITH RECURSIVE conversation_path AS (
                        -- 1. Base case: Find the final message of the target run using a subquery
                        SELECT 
                            id, 
                            run_id, 
                            parent_message_id, 
                            role, 
                            content,
                            chart_payload,
                            sender,
                            created_at, 
                            1 AS depth
                        FROM (
                            SELECT 
                                id, run_id, parent_message_id, role, content, chart_payload, sender, created_at
                            FROM messages
                            WHERE run_id = ?
                            ORDER BY created_at DESC
                            LIMIT 1
                        ) AS base_message

                        UNION ALL

                        -- 2. Recursive step: Walk up the tree following parent_message_id
                        SELECT 
                            m.id, 
                            m.run_id, 
                            m.parent_message_id, 
                            m.role, 
                            m.content,
                            m.chart_payload,
                            m.sender,
                            m.created_at, 
                            cp.depth + 1
                        FROM messages m
                        JOIN conversation_path cp ON m.id = cp.parent_message_id
                    )
                    -- 3. Output the results chronologically (oldest context first, newest run messages last)
                    SELECT 
                        id, 
                        run_id, 
                        parent_message_id, 
                        role, 
                        content,
                        chart_payload,
                        sender,
                        created_at
                    FROM conversation_path
                    ORDER BY depth DESC;
                """, arguments: [runId])
            }
            self.messages = try rows.map { row in try self.messageFromRow(row) }
        } catch let e as ResearchStoreError {
            throw e
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }
    
    func fetchRunMessagesAndParents(forRun runId: String) async throws -> [ChatMessage] {
        do {
            let rows: [Row] = try db.read { db in
                try Row.fetchAll(db, sql: """
                    WITH RECURSIVE conversation_path AS (
                        -- 1. Base case: Find the final message of the target run using a subquery
                        SELECT 
                            id, 
                            run_id, 
                            parent_message_id, 
                            role, 
                            content,
                            chart_payload,
                            sender,
                            created_at, 
                            1 AS depth
                        FROM (
                            SELECT 
                                id, run_id, parent_message_id, role, content, chart_payload, sender, created_at
                            FROM messages
                            WHERE run_id = ?
                            ORDER BY created_at DESC
                            LIMIT 1
                        ) AS base_message

                        UNION ALL

                        -- 2. Recursive step: Walk up the tree following parent_message_id
                        SELECT 
                            m.id, 
                            m.run_id, 
                            m.parent_message_id, 
                            m.role, 
                            m.content,
                            m.chart_payload,
                            m.sender,
                            m.created_at, 
                            cp.depth + 1
                        FROM messages m
                        JOIN conversation_path cp ON m.id = cp.parent_message_id
                    )
                    -- 3. Output the results chronologically (oldest context first, newest run messages last)
                    SELECT 
                        id, 
                        run_id, 
                        parent_message_id, 
                        role, 
                        content,
                        chart_payload,
                        sender,
                        created_at
                    FROM conversation_path
                    ORDER BY depth DESC;
                """, arguments: [runId])
            }
            return try rows.map { row in try self.messageFromRow(row) }
        } catch let e as ResearchStoreError {
            throw e
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }

    // MARK: - Runs CRUD

    /// Loads all runs for the given thread.
    func loadRuns(forThread threadId: String) async throws {
        do {
            let rows: [Row] = try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, thread_id, title, status, configuration,
                           artifacts, result_summary, event_count, cross_section,
                           error_message, created_at, updated_at, completed_at
                    FROM runs
                    WHERE thread_id = ?
                    ORDER BY created_at DESC
                """, arguments: [threadId])
            }
            self.runs = try rows.map { row in try self.runFromRow(row) }
        } catch let e as ResearchStoreError {
            throw e
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }

    /// Fetches a single run by ID.
    func fetchRun(id: String) async throws -> SimulationRun {
        do {
            let row: Row? = try db.read { db in
                try Row.fetchOne(db, sql: """
                    SELECT id, thread_id, title, status, configuration,
                           artifacts, result_summary, event_count, cross_section,
                           error_message, created_at, updated_at, completed_at
                    FROM runs WHERE id = ?
                """, arguments: [id])
            }
            guard let row else { throw ResearchStoreError.notFound("Run \(id)") }
            return try runFromRow(row)
        } catch let e as ResearchStoreError {
            throw e
        } catch {
            throw ResearchStoreError.fetchError(error.localizedDescription)
        }
    }

    @discardableResult
    func createRun(
        threadId: String,
        title: String,
        configuration: [String: String] = [:]
    ) async throws -> SimulationRun {
        let id = UUID().uuidString
        let configJson: String
        do {
            let data = try encoder.encode(configuration)
            configJson = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            throw ResearchStoreError.encodingError(error.localizedDescription)
        }

        do {
            try await db.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO runs (id, thread_id, title, configuration)
                        VALUES (?, ?, ?, ?)
                    """,
                    arguments: [id, threadId, title, configJson]
                )
                try db.execute(
                    sql: "UPDATE research_threads SET updated_at = datetime('now') WHERE id = ?",
                    arguments: [threadId]
                )
            }
        } catch {
            throw ResearchStoreError.insertError(error.localizedDescription)
        }
        try await loadRuns(forThread: threadId)
        return runs.first { $0.id == id }!
    }

    /// Updates a run's status. Sets completed_at when transitioning to completed or failed.
    func updateRunStatus(id: String, status: RunStatus, errorMessage: String? = nil) async throws {
        let threadId = runs.first(where: { $0.id == id })?.threadId
        do {
            try await db.write { db in
                if status == .completed || status == .failed {
                    try db.execute(
                        sql: """
                            UPDATE runs
                            SET status = ?, error_message = ?,
                                updated_at = datetime('now'), completed_at = datetime('now')
                            WHERE id = ?
                        """,
                        arguments: [status.rawValue, errorMessage, id]
                    )
                } else {
                    try db.execute(
                        sql: """
                            UPDATE runs
                            SET status = ?, error_message = ?, updated_at = datetime('now')
                            WHERE id = ?
                        """,
                        arguments: [status.rawValue, errorMessage, id]
                    )
                }
            }
        } catch {
            throw ResearchStoreError.updateError(error.localizedDescription)
        }
        if let threadId {
            try await loadRuns(forThread: threadId)
        }
    }
    
    func addChatMessage(runId: String, message: ChatMessage) async throws {
        do {
            let targetRunId = message.originRunId ?? runId
            let storedMessage = ChatMessage(
                id: message.id,
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                chartPayload: message.chartPayload,
                originRunId: targetRunId,
                parentMessageId: message.parentMessageId,
                sender: message.sender
            )

            if storedMessage.chartPayload != nil {
                let data = try encoder.encode(storedMessage.chartPayload)
                let json = String(data: data, encoding: .utf8) ?? "{}"

                try await db.write { db in
                    try db.execute(sql: "INSERT INTO messages (id, run_id, parent_message_id, role, content, chart_payload, sender, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                   arguments: [storedMessage.id, targetRunId, storedMessage.parentMessageId, storedMessage.role, storedMessage.content, json, storedMessage.sender.rawValue, storedMessage.timestamp])
                }
            } else {
                try await db.write { db in
                    try db.execute(sql: "INSERT INTO messages (id, run_id, parent_message_id, role, content, sender, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                                   arguments: [storedMessage.id, targetRunId, storedMessage.parentMessageId, storedMessage.role, storedMessage.content, storedMessage.sender.rawValue, storedMessage.timestamp])
                }
            }
            // Append to in-memory array only after DB write succeeds
            messages.append(storedMessage)
        } catch {
            throw ResearchStoreError.updateError(error.localizedDescription)
        }
    }

    /// Adds an artifact reference to a run.
    func addArtifact(runId: String, artifact: ArtifactRef) async throws {
        var run = try await fetchRun(id: runId)
        run.artifacts.append(artifact)
        let data = try encoder.encode(run.artifacts)
        let json = String(data: data, encoding: .utf8) ?? "[]"
        do {
            try await db.write { db in
                try db.execute(
                    sql: "UPDATE runs SET artifacts = ?, updated_at = datetime('now') WHERE id = ?",
                    arguments: [json, runId]
                )
            }
        } catch {
            throw ResearchStoreError.updateError(error.localizedDescription)
        }
        try await loadRuns(forThread: run.threadId)
    }

    /// Updates a run's numeric results and summary.
    func updateRunResults(
        id: String,
        resultSummary: String? = nil,
        eventCount: Int? = nil,
        crossSection: Double? = nil
    ) async throws {
        let threadId = runs.first(where: { $0.id == id })?.threadId
        do {
            try await db.write { db in
                if let resultSummary {
                    try db.execute(
                        sql: "UPDATE runs SET result_summary = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [resultSummary, id]
                    )
                }
                if let eventCount {
                    try db.execute(
                        sql: "UPDATE runs SET event_count = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [eventCount, id]
                    )
                }
                if let crossSection {
                    try db.execute(
                        sql: "UPDATE runs SET cross_section = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [crossSection, id]
                    )
                }
            }
        } catch {
            throw ResearchStoreError.updateError(error.localizedDescription)
        }
        if let threadId {
            try await loadRuns(forThread: threadId)
        }
    }

    /// Updates a run's Pythia configuration.
    func updateRunConfiguration(id: String, configuration: [String: String]) async throws {
        let threadId = runs.first(where: { $0.id == id })?.threadId
        let data = try encoder.encode(configuration)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        do {
            try await db.write { db in
                try db.execute(
                    sql: "UPDATE runs SET configuration = ?, updated_at = datetime('now') WHERE id = ?",
                    arguments: [json, id]
                )
            }
        } catch {
            throw ResearchStoreError.updateError(error.localizedDescription)
        }
        if let threadId {
            try await loadRuns(forThread: threadId)
        }
    }

    /// Creates a run pre-seeded with an existing chat history.
    @discardableResult
    func createRunWithChatHistory(
        threadId: String,
        title: String,
        chatHistory: [ChatMessage],
        configuration: [String: String] = [:]
    ) async throws -> SimulationRun {
        let id = UUID().uuidString
        let configJson: String
        let copiedMessages: [(id: String, parentMessageId: String?, role: String, content: String, chartPayload: String?, sender: String, timestamp: String)]
        do {
            let configData = try encoder.encode(configuration)
            configJson = String(data: configData, encoding: .utf8) ?? "{}"

            let idMap = Dictionary(uniqueKeysWithValues: chatHistory.map { ($0.id, UUID().uuidString) })
            copiedMessages = try chatHistory.map { message in
                let chartJSON: String?
                if let chartPayload = message.chartPayload {
                    let chartData = try encoder.encode(chartPayload)
                    chartJSON = String(data: chartData, encoding: .utf8) ?? "{}"
                } else {
                    chartJSON = nil
                }

                return (
                    id: idMap[message.id] ?? UUID().uuidString,
                    parentMessageId: message.parentMessageId.flatMap { idMap[$0] },
                    role: message.role,
                    content: message.content,
                    chartPayload: chartJSON,
                    sender: message.sender.rawValue,
                    timestamp: message.timestamp
                )
            }
        } catch {
            throw ResearchStoreError.encodingError(error.localizedDescription)
        }

        do {
            try await db.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO runs (id, thread_id, title, configuration)
                        VALUES (?, ?, ?, ?)
                    """,
                    arguments: [id, threadId, title, configJson]
                )
                for message in copiedMessages {
                    if let chartPayload = message.chartPayload {
                        try db.execute(
                            sql: "INSERT INTO messages (id, run_id, parent_message_id, role, content, chart_payload, sender, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                            arguments: [message.id, id, message.parentMessageId, message.role, message.content, chartPayload, message.sender, message.timestamp]
                        )
                    } else {
                        try db.execute(
                            sql: "INSERT INTO messages (id, run_id, parent_message_id, role, content, sender, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                            arguments: [message.id, id, message.parentMessageId, message.role, message.content, message.sender, message.timestamp]
                        )
                    }
                }
                try db.execute(
                    sql: "UPDATE research_threads SET updated_at = datetime('now') WHERE id = ?",
                    arguments: [threadId]
                )
            }
        } catch {
            throw ResearchStoreError.insertError(error.localizedDescription)
        }
        try await loadRuns(forThread: threadId)
        return runs.first { $0.id == id }!
    }

    /// Returns the latest active (non-completed, non-failed) run for a thread,
    /// or creates a new one if all existing runs are terminal.
    @discardableResult
    func activeRunForThread(threadId: String, fallbackTitle: String) async throws -> SimulationRun {
        // Ensure runs are loaded for this thread
        try await loadRuns(forThread: threadId)

        // Find the most recent run that is still active (not completed/failed)
        if let active = runs.first(where: { $0.threadId == threadId && $0.status != .completed && $0.status != .failed }) {
            return active
        }

        // All runs are terminal (or none exist) — create a new one
        return try await createRun(threadId: threadId, title: fallbackTitle)
    }

    /// Deletes a run.
    func deleteRun(id: String) async throws {
        let threadId = runs.first(where: { $0.id == id })?.threadId
        do {
            try await db.write { db in
                try db.execute(
                    sql: "DELETE FROM runs WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
            throw ResearchStoreError.deleteError(error.localizedDescription)
        }
        if let threadId {
            try await loadRuns(forThread: threadId)
        }
    }

    // MARK: - Private Helpers
    
    private func messageFromRow(_ row: Row) throws -> ChatMessage {
        
        var decodedPayload: ChartPayload? = nil
        
        do {
            if let payloadString = row["chart_payload"] as? String,
               let payloadData = payloadString.data(using: .utf8) {
                decodedPayload = try decoder.decode(ChartPayload.self, from: payloadData)
            }
        } catch {
            throw ResearchStoreError.encodingError("Failed to decode JSON: \(error.localizedDescription)")
        }
        
        let senderRaw: String = row["sender"] ?? "user"
        let sender = MessageSender(rawValue: senderRaw) ?? .user

        return ChatMessage(
            id: row["id"],
            role: row["role"],
            content: row["content"],
            timestamp: row["created_at"],
            chartPayload: decodedPayload,
            originRunId: row["run_id"],
            parentMessageId: row["parent_message_id"],
            sender: sender
        )
    }

    private func runFromRow(_ row: Row) throws -> SimulationRun {
        let statusStr: String = row["status"] ?? "pending"
        let status = RunStatus(rawValue: statusStr) ?? .pending

        let configJson: String = row["configuration"] ?? "{}"
        let artifactsJson: String = row["artifacts"] ?? "[]"

        let configuration: [String: String]
        let artifacts: [ArtifactRef]

        do {
            configuration = try decoder.decode([String: String].self, from: Data(configJson.utf8))
            artifacts = try decoder.decode([ArtifactRef].self, from: Data(artifactsJson.utf8))
        } catch {
            throw ResearchStoreError.encodingError("Failed to decode JSON: \(error.localizedDescription)")
        }

        return SimulationRun(
            id: row["id"],
            threadId: row["thread_id"],
            title: row["title"],
            status: status,
            configuration: configuration,
            artifacts: artifacts,
            resultSummary: row["result_summary"],
            eventCount: row["event_count"],
            crossSection: row["cross_section"],
            errorMessage: row["error_message"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            completedAt: row["completed_at"]
        )
    }
}
