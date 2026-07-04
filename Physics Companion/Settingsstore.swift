//
//  Settingsstore.swift
//  Physics Companion
//
//  Created by Lorenzo P on 4/11/26.
//

import Foundation
import GRDB
import Combine

// MARK: - SettingsStore
// Persistence layer for the single-row `settings` table.
// Uses GRDB (https://github.com/groue/GRDB.swift) which provides the same
//
// Table schema
// ┌──────────┬─────────┬─────────────────────────────────┐
// │ column   │ type    │ constraints                     │
// ├──────────┼─────────┼─────────────────────────────────┤
// │ id       │ INTEGER │ PRIMARY KEY, always 1           │
// │ name     │ TEXT    │ NOT NULL                        │
// │ api_key  │ TEXT    │ nullable                        │
// │created_at│ TEXT    │ NOT NULL DEFAULT datetime('now')│
// └──────────┴─────────┴─────────────────────────────────┘

// MARK: - Data Model
struct SettingsData: Sendable {
    var name:   String
    var apiKey: String?
}

// MARK: - Error

enum SettingsError: LocalizedError {
    case dbError(String)
    case connectionError(String)
    case insertError(String)
    case getError(String)

    var errorDescription: String? {
        switch self {
        case .dbError(let m):        return "DB error: \(m)"
        case .connectionError(let m): return "Connection error: \(m)"
        case .insertError(let m):    return "Insert error: \(m)"
        case .getError(let m):       return "Get error: \(m)"
        }
    }
}

// MARK: - Store

@MainActor          // keep DB access on one actor; swap for a background actor if desired
final class SettingsStore: ObservableObject {

    // MARK: Public state
    @Published private(set) var data = SettingsData(name: "", apiKey: nil)

    /// True when required onboarding fields are missing
    var requiresOnboarding: Bool {
        let trimmedName = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty
    }

    // MARK: Private
    private let db: DatabaseQueue

    // MARK: - Init (async factory — mirrors connect_settings_db)

    static func connect() async throws -> SettingsStore {
        let path = PathUtils.settingsDbPath

        // Ensure the containing directory exists
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let queue: DatabaseQueue
        do {
            queue = try DatabaseQueue(path: path.path)
        } catch {
            throw SettingsError.connectionError(error.localizedDescription)
        }

        let store = SettingsStore(db: queue)
        try await store.createTableIfNeeded()
        try await store.get()
        return store
    }

    private init(db: DatabaseQueue) {
        self.db = db
    }

    /// Creates an in-memory store pre-loaded with the given data.
    /// Intended for SwiftUI previews and tests only.
    static func preview(name: String = "Preview User", apiKey: String? = "sk-preview") -> SettingsStore {
        // An in-memory DatabaseQueue never touches disk.
        // Force-try is acceptable here — an in-memory DB cannot fail to open.
        let queue = try! DatabaseQueue()
        let store = SettingsStore(db: queue)
        store.data = SettingsData(name: name, apiKey: apiKey)
        return store
    }

    // MARK: - Table Setup

    private func createTableIfNeeded() async throws {
        do {
            try await db.write { db in
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS settings (
                        id         INTEGER PRIMARY KEY CHECK (id = 1),
                        name       TEXT    NOT NULL,
                        api_key    TEXT,
                        created_at TEXT    NOT NULL DEFAULT (datetime('now'))
                    )
                    """)
            }
        } catch {
            throw SettingsError.dbError(error.localizedDescription)
        }
    }

    // MARK: - CRUD

    /// Persists the current `data` to the database (INSERT OR REPLACE).
    func set() async throws {
        let name = self.data.name
        let apiKey = self.data.apiKey
        do {
            try await db.write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO settings (id, name, api_key) VALUES (1, ?, ?)",
                    arguments: [name, apiKey]
                )
            }
        } catch {
            throw SettingsError.insertError(error.localizedDescription)
        }
    }

    /// Loads settings from the database into `data`.
    /// If no row exists yet, writes the default empty row first.
    func get() async throws {
        do {
            // Read row without capturing self inside the Sendable closure
            let row: Row? = try db.read { db in
                try Row.fetchOne(db, sql: "SELECT name, api_key FROM settings WHERE id = 1")
            }

            if let row {
                let name: String = row["name"] ?? ""
                let key: String? = row["api_key"]
                // Assign back on the main actor (we are @MainActor here)
                self.data.name = name
                self.data.apiKey = key
            } else {
                // No row yet — persist defaults (mirrors Rust set() fallback)
                try await set()
            }
        } catch let e as SettingsError {
            throw e
        } catch {
            throw SettingsError.getError(error.localizedDescription)
        }
    }

    /// Convenience: update fields then persist.
    func update(name: String? = nil, apiKey: String?? = .none) async throws {
        if let name   { data.name   = name }
        if case let .some(key) = apiKey { data.apiKey = key }
        try await set()
    }
}

