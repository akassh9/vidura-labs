//
//  ExampleIndex.swift
//  Physics Companion
//
//  Parses Pythia8 example files, builds a hybrid keyword + semantic
//  embedding index, and provides top-K retrieval for the precedence stage.
//

import Foundation
import NaturalLanguage

// MARK: - ExampleRecord

/// Parsed metadata and content for a single Pythia8 example file.
private struct ExampleRecord {
    let filename: String          // e.g. "main101.cc"
    let keywords: [String]        // e.g. ["basic usage", "charged multiplicity"]
    let description: String       // e.g. "This is a simple test program..."
    let section: String           // e.g. "Basic Examples"
    let sourceCode: String        // Full file content
    let embeddingText: String     // keywords + description concatenated for embedding
    var embedding: [Double]?      // Cached NLEmbedding vector
}

// MARK: - ExampleIndex

/// Thread-safe index of Pythia8 example files supporting hybrid
/// keyword + semantic similarity search.
actor ExampleIndex {

    static let shared = ExampleIndex()

    private var records: [ExampleRecord] = []
    private var isLoaded = false

    /// Sentence embedding model, loaded once.
    private var sentenceEmbedding: NLEmbedding?

    // MARK: - Warm-up

    /// Loads all examples and pre-computes embeddings.
    /// Safe to call multiple times; subsequent calls are no-ops.
    func warmUp() {
        guard !isLoaded else { return }
        loadExamples()
        computeEmbeddings()
        isLoaded = true
    }

    // MARK: - Search

    /// Returns the top-K most relevant examples for the given query and intent.
    func search(
        query: String,
        intent: IntentResult?,
        topK: Int = 3
    ) -> [TemplateCandidate] {
        if !isLoaded { warmUp() }
        guard !records.isEmpty else { return [] }

        let queryKeywords = extractQueryKeywords(from: intent, query: query)

        // Build the query text for semantic similarity
        let queryText = [
            intent?.processHint,
            intent?.beamFrame,
            intent?.observables.joined(separator: " "),
            query
        ].compactMap { $0 }.joined(separator: " ")

        // Compute query embedding vector once
        let queryVector = sentenceEmbedding?.vector(for: queryText)

        let hasEmbeddings = queryVector != nil

        // Weight configuration
        let keywordWeight: Double  = hasEmbeddings ? 0.4 : 0.8
        let semanticWeight: Double = hasEmbeddings ? 0.4 : 0.0
        let bonusWeight: Double    = 0.2

        // Score each record
        var scored: [(index: Int, score: Double)] = []
        for (i, record) in records.enumerated() {
            let kw = keywordScore(queryKeywords: queryKeywords, record: record)
            let sem: Double
            if let qv = queryVector, let rv = record.embedding {
                sem = cosineSimilarity(qv, rv)
            } else {
                sem = 0.0
            }
            let bonus = bonusScore(intent: intent, record: record)
            let total = keywordWeight * kw + semanticWeight * sem + bonusWeight * bonus
            scored.append((i, total))
        }

        // Sort descending and take top-K
        scored.sort { $0.score > $1.score }
        let topResults = scored.prefix(topK)

        return topResults.map { item in
            let record = records[item.index]
            return TemplateCandidate(
                filename: record.filename,
                section: record.section,
                description: record.description,
                keywords: record.keywords,
                score: item.score,
                lines: truncateSnippet(record.sourceCode)
            )
        }
    }

    // MARK: - Loading

    private func loadExamples() {
        let examplesDir = Self.examplesDirectory()
        guard FileManager.default.fileExists(atPath: examplesDir.path) else {
            return
        }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: examplesDir,
            includingPropertiesForKeys: nil
        ) else { return }

        let ccFiles = files
            .filter { $0.pathExtension == "cc" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in ccFiles {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            let filename = file.lastPathComponent
            let record = parseHeader(from: content, filename: filename)
            records.append(record)
        }
    }

    // MARK: - Parsing

    private func parseHeader(from content: String, filename: String) -> ExampleRecord {
        let lines = content.components(separatedBy: "\n")

        // Extract keywords from "// Keywords: ..." line(s)
        var keywordsRaw = ""
        var foundKeywords = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("// Keywords:") {
                keywordsRaw = String(trimmed.dropFirst("// Keywords:".count))
                foundKeywords = true
            } else if foundKeywords && trimmed.hasPrefix("//") && !trimmed.hasPrefix("//=") {
                let continuation = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if continuation.isEmpty || continuation.hasPrefix("This") || continuation.hasPrefix("It ") ||
                   continuation.hasPrefix("A ") || continuation.hasPrefix("Simple") ||
                   continuation.hasPrefix("Illustration") || continuation.hasPrefix("Test") {
                    break
                }
                keywordsRaw += " " + continuation
            } else if foundKeywords {
                break
            }
        }

        let keywords = keywordsRaw
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Extract description: comment lines after keywords that describe the program
        var descriptionParts: [String] = []
        var pastKeywords = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("// Keywords:") {
                pastKeywords = true
                continue
            }
            if pastKeywords && trimmed.hasPrefix("//") && !trimmed.hasPrefix("//=") {
                let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if text.isEmpty {
                    if !descriptionParts.isEmpty { break }
                    continue
                }
                // Skip keyword continuation lines (already captured)
                if descriptionParts.isEmpty && keywords.last.map({ text.hasPrefix($0.prefix(5).description) }) == true {
                    continue
                }
                descriptionParts.append(text)
            } else if pastKeywords && !trimmed.hasPrefix("//") {
                break
            }
        }

        let description = descriptionParts.joined(separator: " ")
        let section = sectionName(for: filename)
        let embeddingText = keywords.joined(separator: ", ") + ". " + description

        return ExampleRecord(
            filename: filename,
            keywords: keywords,
            description: description,
            section: section,
            sourceCode: content,
            embeddingText: embeddingText,
            embedding: nil
        )
    }

    // MARK: - Embeddings

    private func computeEmbeddings() {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return
        }
        sentenceEmbedding = embedding

        for i in records.indices {
            records[i].embedding = embedding.vector(for: records[i].embeddingText)
        }
    }

    // MARK: - Scoring

    /// Computes keyword overlap score (0.0 to 1.0).
    private func keywordScore(queryKeywords: Set<String>, record: ExampleRecord) -> Double {
        guard !queryKeywords.isEmpty else { return 0.0 }
        let recordKeywords = record.keywords.map { $0.lowercased() }

        var matches = 0
        for qk in queryKeywords {
            if recordKeywords.contains(where: { $0.contains(qk) || qk.contains($0) }) {
                matches += 1
            }
        }
        return Double(matches) / Double(queryKeywords.count)
    }

    /// Computes bonus/penalty score based on context alignment.
    private func bonusScore(intent: IntentResult?, record: ExampleRecord) -> Double {
        var bonus = 0.0
        let kwLower = Set(record.keywords.map { $0.lowercased() })

        // Penalty for external dependencies
        let excludedDeps: Set<String> = [
            "root", "fastjet", "lhapdf", "hepmc", "rivet",
            "evtgen", "hdf5", "openmp", "python", "matplotlib", "yoda"
        ]
        if kwLower.contains(where: { kw in excludedDeps.contains(where: { kw.contains($0) }) }) {
            bonus -= 0.5
        }

        guard let intent = intent else { return bonus }

        // Beam frame alignment
        if intent.beamFrame == "ee" && kwLower.contains(where: { $0.contains("electron") }) {
            bonus += 0.5
        }
        if intent.beamFrame == "pp" && !kwLower.contains(where: { $0.contains("electron") }) {
            bonus += 0.1
        }

        // Analysis family alignment
        for candidate in intent.requestedAnalysisCandidates {
            let normalized = candidate.replacingOccurrences(of: "_", with: " ")
            if kwLower.contains(where: { $0.contains(normalized) || normalized.contains($0) }) {
                bonus += 1.0
                break
            }
        }

        return bonus
    }

    /// Extracts a set of lowercased query keywords from the intent and raw query.
    private func extractQueryKeywords(from intent: IntentResult?, query: String) -> Set<String> {
        var keywords = Set<String>()

        guard let intent = intent else {
            let words = query.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 }
            return Set(words)
        }

        // Beam frame mapping
        switch intent.beamFrame {
        case "ee": keywords.insert("electron-positron")
        case "pp": keywords.formUnion(["basic usage"])
        case "ep": keywords.insert("dis")
        default: break
        }

        // Process hint mapping
        let proc = intent.processHint.lowercased()
        if proc.contains("hardqcd")         { keywords.formUnion(["basic usage", "qcd"]) }
        if proc.contains("weaksingleboson") { keywords.formUnion(["z production", "w production"]) }
        if proc.contains("top")             { keywords.formUnion(["top"]) }
        if proc.contains("softqcd")         { keywords.formUnion(["minimum bias", "diffraction"]) }
        if proc.contains("higgs")           { keywords.formUnion(["higgs"]) }

        // Observable mapping
        for obs in intent.observables {
            let lower = obs.lowercased()
            if lower.contains("multiplicity") { keywords.insert("charged multiplicity") }
            if lower.contains("pt") || lower.contains("transverse") { keywords.insert("pt spectrum") }
            if lower.contains("eta") || lower.contains("rapidity") { keywords.insert("rapidity") }
            if lower.contains("mass") { keywords.insert("invariant mass") }
            if lower.contains("jet") { keywords.insert("jet finding") }
        }

        // Analysis candidate mapping
        for candidate in intent.requestedAnalysisCandidates {
            let normalized = candidate.replacingOccurrences(of: "_", with: " ")
            keywords.insert(normalized)
        }

        // Raw prompt words as fallback
        let promptWords = intent.prompt.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }
        keywords.formUnion(promptWords)

        return keywords
    }

    // MARK: - Helpers

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot   += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0.0 }
        return dot / denom
    }

    /// Truncates source code to a maximum number of lines.
    private func truncateSnippet(_ source: String, maxLines: Int = 200) -> String {
        let lines = source.components(separatedBy: "\n")
        if lines.count <= maxLines { return source }
        return lines.prefix(maxLines).joined(separator: "\n")
            + "\n// ... (truncated, \(lines.count) lines total)"
    }

    /// Maps a filename like "main301.cc" to a section name.
    private func sectionName(for filename: String) -> String {
        let digits = filename.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard let num = Int(digits) else { return "Other" }
        let series = num / 100
        switch series {
        case 1: return "Basic Examples"
        case 2: return "Parton Distributions & Jets"
        case 3: return "Processes & Decays"
        case 4: return "Showers & Advanced"
        case 5: return "BSM & Hidden Valley"
        default: return "Other"
        }
    }

    /// Locates the examples directory, preferring the installed copy.
    private static func examplesDirectory() -> URL {
        let installed = PathUtils.pythiaDir
            .appendingPathComponent("share")
            .appendingPathComponent("Pythia8")
            .appendingPathComponent("examples")
        if FileManager.default.fileExists(atPath: installed.path) {
            return installed
        }
        return PathUtils.bundledPythisDir
            .appendingPathComponent("share")
            .appendingPathComponent("Pythia8")
            .appendingPathComponent("examples")
    }
}
