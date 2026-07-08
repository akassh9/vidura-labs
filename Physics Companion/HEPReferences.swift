//
//  HEPReferences.swift
//  Physics Companion
//
//  Typed HEP reference models, source connector parsers, and deterministic pack assembly.
//

import Foundation

enum HEPReferenceSource: String, Codable, CaseIterable, Sendable {
    case arxiv
    case inspire
    case hepdata
    case pdg
}

struct HEPReference: Codable, Equatable, Sendable, Identifiable {
    var id: String { HEPReferenceNormalizer.stableKey(for: self) }

    let source: HEPReferenceSource
    let sources: [HEPReferenceSource]
    let title: String
    let authors: [String]
    let collaboration: String?
    let year: Int?
    let snippet: String?
    let doi: String?
    let arxivId: String?
    let inspireId: String?
    let hepDataId: String?
    let url: String?
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case source
        case sources
        case title
        case authors
        case collaboration
        case year
        case snippet
        case doi
        case arxivId = "arxiv_id"
        case inspireId = "inspire_id"
        case hepDataId = "hepdata_id"
        case url
        case tags
    }

    nonisolated init(
        source: HEPReferenceSource,
        sources: [HEPReferenceSource]? = nil,
        title: String,
        authors: [String] = [],
        collaboration: String? = nil,
        year: Int? = nil,
        snippet: String? = nil,
        doi: String? = nil,
        arxivId: String? = nil,
        inspireId: String? = nil,
        hepDataId: String? = nil,
        url: String? = nil,
        tags: [String] = []
    ) {
        self.source = source
        self.sources = sources ?? [source]
        self.title = title
        self.authors = authors
        self.collaboration = collaboration
        self.year = year
        self.snippet = snippet
        self.doi = doi
        self.arxivId = arxivId
        self.inspireId = inspireId
        self.hepDataId = hepDataId
        self.url = url
        self.tags = tags
    }
}

struct HEPReferencePack: Codable, Equatable, Sendable {
    let formatVersion: Int
    let generatedAt: String
    let query: String
    let references: [HEPReference]
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case generatedAt = "generated_at"
        case query
        case references
        case tags
    }
}

enum HEPReferenceNormalizer {
    nonisolated static func normalized(_ reference: HEPReference) -> HEPReference {
        HEPReference(
            source: reference.source,
            sources: uniqueSources(reference.sources.isEmpty ? [reference.source] : reference.sources),
            title: clean(reference.title) ?? reference.title,
            authors: uniqueStrings(reference.authors.compactMap(clean)),
            collaboration: clean(reference.collaboration),
            year: reference.year,
            snippet: clean(reference.snippet),
            doi: normalizedDOI(reference.doi),
            arxivId: normalizedArxivId(reference.arxivId),
            inspireId: normalizedIdentifier(reference.inspireId),
            hepDataId: normalizedIdentifier(reference.hepDataId),
            url: normalizedURL(reference.url),
            tags: uniqueStrings(reference.tags.compactMap(clean).map { $0.lowercased() })
        )
    }

    nonisolated static func stableKey(for reference: HEPReference) -> String {
        if let doi = normalizedDOI(reference.doi) { return "doi:\(doi)" }
        if let arxivId = normalizedArxivId(reference.arxivId) { return "arxiv:\(arxivId)" }
        if let inspireId = normalizedIdentifier(reference.inspireId) { return "inspire:\(inspireId)" }
        if let hepDataId = normalizedIdentifier(reference.hepDataId) { return "hepdata:\(hepDataId)" }
        if let url = normalizedURL(reference.url) { return "url:\(url)" }
        return "title:\(normalizedTitle(reference.title))"
    }

    nonisolated static func merge(_ lhs: HEPReference, _ rhs: HEPReference) -> HEPReference {
        let left = normalized(lhs)
        let right = normalized(rhs)
        return normalized(HEPReference(
            source: left.source,
            sources: uniqueSources(left.sources + right.sources),
            title: preferred(left.title, right.title) ?? left.title,
            authors: uniqueStrings(left.authors + right.authors),
            collaboration: preferred(left.collaboration, right.collaboration),
            year: left.year ?? right.year,
            snippet: preferred(left.snippet, right.snippet),
            doi: left.doi ?? right.doi,
            arxivId: left.arxivId ?? right.arxivId,
            inspireId: left.inspireId ?? right.inspireId,
            hepDataId: left.hepDataId ?? right.hepDataId,
            url: preferred(left.url, right.url),
            tags: uniqueStrings(left.tags + right.tags)
        ))
    }

    nonisolated static func dedupe(_ references: [HEPReference]) -> [HEPReference] {
        var merged: [HEPReference] = []

        for reference in references.map(normalized) where !reference.title.isEmpty {
            if let index = merged.firstIndex(where: { matches($0, reference) }) {
                merged[index] = merge(merged[index], reference)
            } else {
                merged.append(reference)
            }
        }

        return merged.sorted { lhs, rhs in
            if lhs.year != rhs.year {
                return (lhs.year ?? 0) > (rhs.year ?? 0)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private nonisolated static func matches(_ lhs: HEPReference, _ rhs: HEPReference) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        if let leftDOI = left.doi, let rightDOI = right.doi, leftDOI == rightDOI { return true }
        if let leftArxiv = left.arxivId, let rightArxiv = right.arxivId, leftArxiv == rightArxiv { return true }
        if let leftInspire = left.inspireId, let rightInspire = right.inspireId, leftInspire == rightInspire { return true }
        if let leftHEPData = left.hepDataId, let rightHEPData = right.hepDataId, leftHEPData == rightHEPData { return true }
        if let leftURL = left.url, let rightURL = right.url, leftURL == rightURL { return true }
        return normalizedTitle(left.title) == normalizedTitle(right.title)
    }

    private nonisolated static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private nonisolated static func preferred(_ lhs: String?, _ rhs: String?) -> String? {
        let left = clean(lhs)
        let right = clean(rhs)
        guard let left else { return right }
        guard let right else { return left }
        return right.count > left.count ? right : left
    }

    private nonisolated static func uniqueSources(_ sources: [HEPReferenceSource]) -> [HEPReferenceSource] {
        var seen = Set<HEPReferenceSource>()
        return sources.filter { seen.insert($0).inserted }
    }

    private nonisolated static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = value.lowercased()
            return seen.insert(key).inserted
        }
    }

    private nonisolated static func normalizedDOI(_ value: String?) -> String? {
        guard var value = clean(value)?.lowercased() else { return nil }
        for prefix in ["https://doi.org/", "http://doi.org/", "doi:", "doi "] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }

    private nonisolated static func normalizedArxivId(_ value: String?) -> String? {
        guard var value = clean(value)?.lowercased() else { return nil }
        for prefix in ["https://arxiv.org/abs/", "http://arxiv.org/abs/", "https://arxiv.org/pdf/", "http://arxiv.org/pdf/", "arxiv:"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        if value.hasSuffix(".pdf") {
            value.removeLast(4)
        }
        if let versionRange = value.range(of: #"v\d+$"#, options: .regularExpression) {
            value.removeSubrange(versionRange)
        }
        return value
    }

    private nonisolated static func normalizedIdentifier(_ value: String?) -> String? {
        clean(value)?.lowercased()
    }

    private nonisolated static func normalizedURL(_ value: String?) -> String? {
        guard var value = clean(value) else { return nil }
        if value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private nonisolated static func normalizedTitle(_ value: String) -> String {
        clean(value)?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") ?? ""
    }
}

enum HEPReferencePackAssembler {
    nonisolated static func assemble(
        query: String,
        references: [HEPReference],
        generatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> HEPReferencePack {
        let normalized = HEPReferenceNormalizer.dedupe(references)
        let tags = normalized.reduce(into: Set<String>()) { result, reference in
            reference.tags.forEach { result.insert($0) }
        }
        return HEPReferencePack(
            formatVersion: 1,
            generatedAt: generatedAt,
            query: query,
            references: normalized,
            tags: tags.sorted()
        )
    }

    nonisolated static func baselinePack(
        query: String,
        simulationSpec: SimulationSpec?,
        generatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) -> HEPReferencePack {
        var tags = ["hep", "pythia", "simulation"]
        if let family = simulationSpec?.analysisPlan?.family {
            tags.append(family)
        }
        if simulationSpec?.processSettings.contains(where: { $0.lowercased().contains("hardqcd") }) == true {
            tags.append("qcd")
        }

        let references = [
            HEPReference(
                source: .arxiv,
                title: "An Introduction to PYTHIA 8.2",
                authors: ["Torbjorn Sjostrand", "Stefan Ask", "Jesper R. Christiansen", "Richard Corke", "Nishita Desai", "Philip Ilten", "Stephen Mrenna", "Stefan Prestel", "Christine O. Rasmussen", "Peter Z. Skands"],
                year: 2015,
                snippet: "Canonical Pythia 8.2 generator reference for event-generation setup and tune context.",
                doi: "10.1016/j.cpc.2015.01.024",
                arxivId: "1410.3012",
                url: "https://arxiv.org/abs/1410.3012",
                tags: tags
            ),
            HEPReference(
                source: .inspire,
                title: "An Introduction to PYTHIA 8.2",
                year: 2015,
                doi: "10.1016/j.cpc.2015.01.024",
                arxivId: "1410.3012",
                inspireId: "1321709",
                url: "https://inspirehep.net/literature/1321709",
                tags: tags + ["generator"]
            ),
            HEPReference(
                source: .hepdata,
                title: "HEPData: a repository for high energy physics data",
                authors: ["Eamonn Maguire", "Lukas Heinrich", "Graeme Watt"],
                year: 2017,
                snippet: "Reference-data repository context for future comparisons to published HEP measurements.",
                doi: "10.1088/1742-6596/898/10/102006",
                arxivId: "1704.05473",
                url: "https://www.hepdata.net",
                tags: ["hepdata", "reference-data", "measurements"]
            ),
            HEPReference(
                source: .pdg,
                title: "Review of Particle Physics",
                collaboration: "Particle Data Group",
                snippet: "Canonical particle-property and constants reference for HEP interpretation checks.",
                url: "https://pdg.lbl.gov",
                tags: ["pdg", "particle-data", "constants"]
            )
        ]

        return assemble(query: query, references: references, generatedAt: generatedAt)
    }
}

enum ArxivConnector {
    nonisolated static func searchURL(query: String, maxResults: Int = 10) -> URL {
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: query),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: "\(maxResults)")
        ]
        return components.url!
    }

    nonisolated static func abstractURL(arxivId: String) -> URL {
        URL(string: "https://arxiv.org/abs/\(HEPReferenceNormalizer.normalized(HEPReference(source: .arxiv, title: "x", arxivId: arxivId)).arxivId ?? arxivId)")!
    }

    nonisolated static func fetch(query: String, maxResults: Int = 10) async throws -> [HEPReference] {
        let (data, _) = try await URLSession.shared.data(from: searchURL(query: query, maxResults: maxResults))
        return try parse(data: data)
    }

    nonisolated static func parse(data: Data) throws -> [HEPReference] {
        let parser = XMLParser(data: data)
        let delegate = ArxivFeedParser()
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? HEPConnectorError.parseFailed("arXiv Atom parse failed")
        }
        return delegate.references.map(HEPReferenceNormalizer.normalized)
    }
}

enum InspireConnector {
    nonisolated static func searchURL(query: String, size: Int = 10) -> URL {
        var components = URLComponents(string: "https://inspirehep.net/api/literature")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "size", value: "\(size)")
        ]
        return components.url!
    }

    nonisolated static func recordURL(inspireId: String) -> URL {
        URL(string: "https://inspirehep.net/api/literature/\(inspireId)")!
    }

    nonisolated static func doiURL(_ doi: String) -> URL {
        URL(string: "https://inspirehep.net/api/doi/\(doi)")!
    }

    nonisolated static func arxivURL(_ arxivId: String) -> URL {
        URL(string: "https://inspirehep.net/api/arxiv/\(arxivId)")!
    }

    nonisolated static func fetch(query: String, size: Int = 10) async throws -> [HEPReference] {
        let (data, _) = try await URLSession.shared.data(from: searchURL(query: query, size: size))
        return try parse(data: data)
    }

    nonisolated static func parse(data: Data) throws -> [HEPReference] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let dictionary = object as? [String: Any],
           let hits = ((dictionary["hits"] as? [String: Any])?["hits"] as? [[String: Any]]) {
            return hits.compactMap(reference(from:)).map(HEPReferenceNormalizer.normalized)
        }
        if let dictionary = object as? [String: Any] {
            return reference(from: dictionary).map { [HEPReferenceNormalizer.normalized($0)] } ?? []
        }
        return []
    }

    private nonisolated static func reference(from record: [String: Any]) -> HEPReference? {
        let metadata = record["metadata"] as? [String: Any] ?? record
        let title = firstString(in: metadata["titles"], keys: ["title"]) ?? string(metadata["title"])
        guard let title else { return nil }

        let inspireId = string(record["id"]) ?? string(metadata["control_number"])
        let authors = array(metadata["authors"]).compactMap { author in
            string(author["full_name"]) ?? string(author["name"])
        }
        let collaboration = firstString(in: metadata["collaborations"], keys: ["value", "name", "collaboration"])
        let doi = firstString(in: metadata["dois"], keys: ["value", "doi"])
        let arxivId = firstString(in: metadata["arxiv_eprints"], keys: ["value", "arxiv_id"])
        let year = publicationYear(metadata)
        let snippet = string(metadata["abstracts"].flatMap { firstString(in: $0, keys: ["value", "summary"]) })
        let url = inspireId.map { "https://inspirehep.net/literature/\($0)" } ?? string((record["links"] as? [String: Any])?["html"])
        let tags = ["inspire", "literature"] + array(metadata["keywords"]).compactMap { string($0["value"]) }

        return HEPReference(
            source: .inspire,
            title: title,
            authors: authors,
            collaboration: collaboration,
            year: year,
            snippet: snippet,
            doi: doi,
            arxivId: arxivId,
            inspireId: inspireId,
            url: url,
            tags: tags
        )
    }
}

enum HEPDataConnector {
    nonisolated static func recordURL(hepDataId: String) -> URL {
        URL(string: "https://www.hepdata.net/record/\(hepDataId)")!
    }

    nonisolated static func recordURL(inspireId: String, format: String = "json") -> URL {
        var components = URLComponents(string: "https://www.hepdata.net/record/ins\(inspireId)")!
        components.queryItems = [URLQueryItem(name: "format", value: format)]
        return components.url!
    }

    nonisolated static func fetch(inspireId: String) async throws -> [HEPReference] {
        let (data, _) = try await URLSession.shared.data(from: recordURL(inspireId: inspireId))
        return try parse(data: data)
    }

    nonisolated static func parse(data: Data) throws -> [HEPReference] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let records = object as? [[String: Any]] {
            return records.compactMap(reference(from:)).map(HEPReferenceNormalizer.normalized)
        }
        if let dictionary = object as? [String: Any] {
            return reference(from: dictionary).map { [HEPReferenceNormalizer.normalized($0)] } ?? []
        }
        return []
    }

    private nonisolated static func reference(from record: [String: Any]) -> HEPReference? {
        let title = string(record["name"]) ?? string(record["headline"]) ?? string(record["title"])
        guard let title else { return nil }
        let identifiers = flattenedStrings(record["identifier"])
        let sameAs = flattenedStrings(record["sameAs"])
        let url = string(record["url"]) ?? string(record["@id"]) ?? sameAs.first(where: { $0.contains("hepdata.net") })
        let hepDataId = recordId(from: url) ?? identifiers.first(where: { $0.lowercased().hasPrefix("ins") })
        let doi = identifiers.first(where: { $0.lowercased().contains("10.") || $0.lowercased().hasPrefix("doi:") })
        let arxivId = (identifiers + sameAs).first(where: { $0.lowercased().contains("arxiv") })
        let inspireId = (identifiers + sameAs).compactMap(inspireId(from:)).first
        let authors = flattenedStrings(record["author"])
        let year = year(from: string(record["datePublished"]) ?? string(record["date_published"]))
        let snippet = string(record["description"]) ?? string(record["abstract"])
        let tags = ["hepdata", "reference-data"] + flattenedStrings(record["keywords"]).map { $0.lowercased() }

        return HEPReference(
            source: .hepdata,
            title: title,
            authors: authors,
            year: year,
            snippet: snippet,
            doi: doi,
            arxivId: arxivId,
            inspireId: inspireId,
            hepDataId: hepDataId,
            url: url,
            tags: tags
        )
    }

    private nonisolated static func recordId(from value: String?) -> String? {
        guard let value else { return nil }
        return value.components(separatedBy: "/record/").last?.components(separatedBy: "?").first
    }

    private nonisolated static func inspireId(from value: String) -> String? {
        let lower = value.lowercased()
        if let range = lower.range(of: #"ins\d+"#, options: .regularExpression) {
            return String(lower[range].dropFirst(3))
        }
        if let range = lower.range(of: #"/literature/\d+"#, options: .regularExpression) {
            return String(lower[range].split(separator: "/").last ?? "")
        }
        return nil
    }
}

enum PDGConnector {
    nonisolated static func canonicalURL(path: String = "") -> URL {
        URL(string: "https://pdg.lbl.gov\(path)")!
    }

    nonisolated static func reference(for topic: String) -> HEPReference {
        HEPReference(
            source: .pdg,
            title: topic.isEmpty ? "Review of Particle Physics" : "Review of Particle Physics: \(topic)",
            collaboration: "Particle Data Group",
            snippet: "Canonical PDG reference entry for particle properties, constants, and review tables.",
            url: canonicalURL().absoluteString,
            tags: ["pdg", "particle-data", "constants"]
        )
    }

    nonisolated static func parse(data: Data) throws -> [HEPReference] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let records = object as? [[String: Any]] {
            return records.compactMap(reference(from:)).map(HEPReferenceNormalizer.normalized)
        }
        if let dictionary = object as? [String: Any] {
            return reference(from: dictionary).map { [HEPReferenceNormalizer.normalized($0)] } ?? []
        }
        return []
    }

    private nonisolated static func reference(from record: [String: Any]) -> HEPReference? {
        let title = string(record["title"]) ?? string(record["name"]) ?? string(record["description"])
        guard let title else { return nil }
        let identifier = string(record["pdgid"]) ?? string(record["pdg_id"]) ?? string(record["identifier"])
        let identifierTags = identifier.map { ["pdg:\($0)"] } ?? []
        return HEPReference(
            source: .pdg,
            title: title,
            collaboration: string(record["collaboration"]) ?? "Particle Data Group",
            year: year(from: string(record["year"]) ?? string(record["date"])),
            snippet: string(record["summary"]) ?? string(record["description"]),
            hepDataId: nil,
            url: string(record["url"]) ?? canonicalURL().absoluteString,
            tags: ["pdg", "particle-data"] + identifierTags + flattenedStrings(record["tags"])
        )
    }
}

enum HEPConnectorError: Error {
    case parseFailed(String)
}

private final class ArxivFeedParser: NSObject, XMLParserDelegate {
    private struct Entry {
        var title: String?
        var summary: String?
        var id: String?
        var published: String?
        var doi: String?
        var authors: [String] = []
        var tags: [String] = []

        nonisolated init() {}
    }

    private nonisolated(unsafe) var currentEntry: Entry?
    private nonisolated(unsafe) var currentElement = ""
    private nonisolated(unsafe) var currentText = ""
    private nonisolated(unsafe) var insideAuthor = false
    private(set) nonisolated(unsafe) var references: [HEPReference] = []

    nonisolated override init() {
        super.init()
    }

    nonisolated func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = qName ?? elementName
        currentText = ""
        if elementName == "entry" {
            currentEntry = Entry()
        } else if elementName == "author" {
            insideAuthor = true
        } else if elementName == "category", let term = attributeDict["term"] {
            currentEntry?.tags.append(term)
        }
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    nonisolated func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if elementName == "entry" {
            if let reference = currentEntry.flatMap(reference(from:)) {
                references.append(reference)
            }
            currentEntry = nil
        } else if elementName == "author" {
            insideAuthor = false
        } else if currentEntry != nil {
            switch elementName {
            case "title":
                currentEntry?.title = text
            case "summary":
                currentEntry?.summary = text
            case "id":
                currentEntry?.id = text
            case "published":
                currentEntry?.published = text
            case "doi":
                currentEntry?.doi = text
            case "name" where insideAuthor:
                currentEntry?.authors.append(text)
            default:
                if (qName ?? elementName).hasSuffix(":doi") {
                    currentEntry?.doi = text
                }
            }
        }
        currentText = ""
    }

    private nonisolated func reference(from entry: Entry) -> HEPReference? {
        guard let title = entry.title else { return nil }
        return HEPReference(
            source: .arxiv,
            title: title,
            authors: entry.authors,
            year: year(from: entry.published),
            snippet: entry.summary,
            doi: entry.doi,
            arxivId: arxivId(from: entry.id),
            url: entry.id,
            tags: ["arxiv"] + entry.tags
        )
    }

    private nonisolated func arxivId(from value: String?) -> String? {
        guard let value else { return nil }
        return value.components(separatedBy: "/abs/").last ?? value
    }
}

private nonisolated func string(_ value: Any?) -> String? {
    if let value = value as? String {
        return value
    }
    if let value = value as? NSNumber {
        return value.stringValue
    }
    return nil
}

private nonisolated func array(_ value: Any?) -> [[String: Any]] {
    value as? [[String: Any]] ?? []
}

private nonisolated func firstString(in value: Any?, keys: [String]) -> String? {
    if let string = string(value) {
        return string
    }
    if let dictionary = value as? [String: Any] {
        for key in keys {
            if let found = string(dictionary[key]) {
                return found
            }
        }
    }
    if let array = value as? [[String: Any]] {
        for item in array {
            for key in keys {
                if let found = string(item[key]) {
                    return found
                }
            }
        }
    }
    return nil
}

private nonisolated func flattenedStrings(_ value: Any?) -> [String] {
    if let string = string(value) {
        return [string]
    }
    if let strings = value as? [String] {
        return strings
    }
    if let dictionary = value as? [String: Any] {
        return dictionary.values.flatMap(flattenedStrings)
    }
    if let array = value as? [Any] {
        return array.flatMap(flattenedStrings)
    }
    return []
}

private nonisolated func publicationYear(_ metadata: [String: Any]) -> Int? {
    if let year = array(metadata["publication_info"]).compactMap({ item in
        string(item["year"]).flatMap(Int.init)
    }).first {
        return year
    }
    return year(from: string(metadata["preprint_date"]) ?? string(metadata["date"]))
}

private nonisolated func year(from value: String?) -> Int? {
    guard let value else { return nil }
    if let exact = Int(value), exact > 1800 {
        return exact
    }
    if let range = value.range(of: #"\d{4}"#, options: .regularExpression) {
        return Int(value[range])
    }
    return nil
}
