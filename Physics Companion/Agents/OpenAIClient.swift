//
//  OpenAIClient.swift
//  Physics Companion
//
//  Minimal Responses API client used by the local macOS app.
//

import Foundation

enum OpenAIClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case requestFailed(statusCode: Int, message: String)
    case invalidResponse(String)
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing OPENAI_API_KEY. Add it to .env, launch through the Codex run script, or save it in app settings."
        case .invalidURL:
            return "The OpenAI API URL is invalid."
        case .requestFailed(let statusCode, let message):
            return "OpenAI request failed (\(statusCode)): \(message)"
        case .invalidResponse(let message):
            return "OpenAI returned an invalid response: \(message)"
        case .refused(let message):
            return "OpenAI refused the request: \(message)"
        }
    }

    var isRateLimit: Bool {
        if case .requestFailed(let statusCode, _) = self {
            return statusCode == 429
        }
        return false
    }
}

enum OpenAICredentials {
    static func resolve(settingsApiKey: String? = nil) throws -> String {
        if let key = normalized(settingsApiKey) {
            return key
        }

        let environment = ProcessInfo.processInfo.environment
        if let key = normalized(environment["OPENAI_API_KEY"]) {
            return key
        }

        for envFile in candidateEnvFiles(environment: environment) {
            if let key = readAPIKey(from: envFile) {
                return key
            }
        }

        throw OpenAIClientError.missingAPIKey
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        } else if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value.isEmpty ? nil : value
    }

    private static func candidateEnvFiles(environment: [String: String]) -> [URL] {
        var files: [URL] = []
        if let root = environment["VIDURA_REPO_ROOT"], !root.isEmpty {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            files.append(rootURL.appendingPathComponent(".env"))
            files.append(rootURL.appendingPathComponent(".env.local"))
        }

        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            files.append(dir.appendingPathComponent(".env"))
            files.append(dir.appendingPathComponent(".env.local"))
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }

        var seen = Set<String>()
        return files.filter { seen.insert($0.path).inserted }
    }

    private static func readAPIKey(from url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        for line in contents.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("export ") {
                trimmed.removeFirst("export ".count)
            }
            guard trimmed.hasPrefix("OPENAI_API_KEY") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            return normalized(String(parts[1]))
        }
        return nil
    }
}

struct OpenAIClient {
    let apiKey: String
    let model: String

    func responseText(
        instructions: String,
        input: String,
        textFormat: [String: Any]? = nil,
        reasoningEffort: String = "low",
        verbosity: String = "low"
    ) async throws -> String {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw OpenAIClientError.invalidURL
        }

        var text: [String: Any] = ["verbosity": verbosity]
        if let textFormat {
            text["format"] = textFormat
        }

        let body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input,
            "reasoning": ["effort": reasoningEffort],
            "text": text
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse("missing HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIClientError.requestFailed(
                statusCode: http.statusCode,
                message: Self.errorMessage(from: responseData)
            )
        }

        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw OpenAIClientError.invalidResponse("top-level response was not an object")
        }

        if let outputText = object["output_text"] as? String {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let refusal = Self.findRefusal(in: object) {
            throw OpenAIClientError.refused(refusal)
        }

        if let outputText = Self.findOutputText(in: object) {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw OpenAIClientError.invalidResponse("no output text found")
    }

    func responseObject<T: Decodable>(
        _ type: T.Type,
        instructions: String,
        input: String,
        textFormat: [String: Any],
        reasoningEffort: String = "low"
    ) async throws -> T {
        let text = try await responseText(
            instructions: instructions,
            input: input,
            textFormat: textFormat,
            reasoningEffort: reasoningEffort,
            verbosity: "low"
        )
        guard let data = text.data(using: .utf8) else {
            throw OpenAIClientError.invalidResponse("output text was not UTF-8")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OpenAIClientError.invalidResponse("JSON decode failed: \(error.localizedDescription)")
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any]
        else {
            return String(data: data, encoding: .utf8) ?? "unknown error"
        }

        if let message = error["message"] as? String {
            return message
        }
        return String(describing: error)
    }

    private static func findOutputText(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if dict["type"] as? String == "output_text",
               let text = dict["text"] as? String {
                return text
            }
            for child in dict.values {
                if let found = findOutputText(in: child) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findOutputText(in: child) {
                    return found
                }
            }
        }
        return nil
    }

    private static func findRefusal(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let refusal = dict["refusal"] as? String, !refusal.isEmpty {
                return refusal
            }
            for child in dict.values {
                if let found = findRefusal(in: child) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findRefusal(in: child) {
                    return found
                }
            }
        }
        return nil
    }
}

enum OpenAIResponseFormats {
    static let guideDecision: [String: Any] = jsonSchema(
        name: "guide_decision",
        properties: [
            "action": [
                "type": "string",
                "enum": ["answer", "propose_simulation", "run_simulation"]
            ],
            "assistant_message": ["type": "string"],
            "runnable_prompt": ["type": ["string", "null"]],
            "analysis_family": ["type": ["string", "null"]]
        ],
        required: ["action", "assistant_message", "runnable_prompt", "analysis_family"]
    )

    static let intent: [String: Any] = jsonSchema(
        name: "simulation_intent",
        properties: [
            "process_hint": ["type": "string"],
            "beam_frame": [
                "type": "string",
                "enum": ["pp", "ee", "ep"]
            ],
            "e_cm_gev": ["type": "number"],
            "event_count": ["type": "integer"],
            "observables": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "requested_analysis_candidates": [
                "type": "array",
                "items": [
                    "type": "string",
                    "enum": [
                        "charged_multiplicity",
                        "pt_spectrum",
                        "eta_rapidity",
                        "invariant_mass",
                        "pid_yields",
                        "event_scalars"
                    ]
                ]
            ],
            "prompt": ["type": "string"]
        ],
        required: [
            "process_hint",
            "beam_frame",
            "e_cm_gev",
            "event_count",
            "observables",
            "requested_analysis_candidates",
            "prompt"
        ]
    )

    static let codegen: [String: Any] = jsonSchema(
        name: "pythia_codegen",
        properties: [
            "source_code": ["type": "string"]
        ],
        required: ["source_code"]
    )

    private static func jsonSchema(
        name: String,
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "json_schema",
            "name": name,
            "strict": true,
            "schema": [
                "type": "object",
                "additionalProperties": false,
                "properties": properties,
                "required": required
            ]
        ]
    }
}
