//
//  ThreadNamingAgent.swift
//  Physics Companion
//
//  Generates a short thread title from the user's first message.
//

import Foundation

enum ThreadNamingAgent {

    /// Generates a concise thread title (≤6 words) from the user's first message.
    /// Falls back to a truncated prefix of the message if the model call fails.
    static func generateTitle(
        for message: String
    ) async -> String {
        let fallback = String(message.prefix(40))

        let instructions = """
        You are a concise title generator. Given a user message, output ONLY a short title \
        (maximum 6 words) that summarises the topic. Do not use quotes, punctuation at the end, \
        or any explanation. Just the title.
        """

        do {
            let client = OpenAIClient(
                apiKey: try OpenAICredentials.resolve(),
                model: AIModel.gpt54Mini.rawValue
            )
            let title = try await client.responseText(
                instructions: instructions,
                input: message,
                reasoningEffort: "low",
                verbosity: "low"
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            if title.isEmpty {
                return fallback
            }

            // Cap at 60 characters just in case
            return String(title.prefix(60))
        } catch {
            return fallback
        }
    }
}
