//
//  ConversationSession+Icon.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/18/25.
//

import ChatClientKit
import Foundation
import FoundationModels
import Storage
import XMLCoder

// MARK: - XML Models

private struct IconResponse: Codable {
    let icon: String
}

private struct IconConversationXML: Codable {
    let task: String
    let last_user_message: String
    let last_assistant_message: String
    let output_format: OutputFormat

    private enum CodingKeys: String, CodingKey {
        case task
        case last_user_message
        case last_assistant_message
        case output_format
    }

    struct OutputFormat: Codable {
        let icon: String
    }
}

// MARK: - FoundationModels Generable

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable(description: "A single emoji character that best represents the conversation. ")
struct ConversationIcon: Equatable {
    @Guide(description: "Only respond with one emoji character. Example: 🔖")
    var icon: String
}

extension ConversationSessionManager.Session {
    func generateConversationIcon() async -> String? {
        guard let userMessage = messages.last(where: { $0.role == .user })?.document else {
            return nil
        }
        guard let assistantMessage = messages.last(where: { $0.role == .assistant })?.document else {
            return nil
        }

        let task = "Generate a single emoji icon that best represents this conversation. Only respond with one emoji character."

        let conversationData = IconConversationXML(
            task: task,
            last_user_message: userMessage,
            last_assistant_message: assistantMessage,
            output_format: IconConversationXML.OutputFormat(icon: "💬"),
        )

        do {
            let encoder = XMLEncoder()
            encoder.outputFormatting = .prettyPrinted
            let xmlData = try encoder.encode(conversationData, withRootKey: "conversation")
            let xmlString = String(data: xmlData, encoding: .utf8) ?? ""

            let messages: [ChatRequestBody.Message] = [
                .system(content: .text(task)),
                .user(content: .text(xmlString)),
            ]

            guard let model = models.auxiliary else { throw NSError() }
            let ans = try await ModelManager.shared.infer(
                with: model,
                input: messages,
            )

            let raw = ans.text
            let sanitizedContent = ModelResponseSanitizer.stripReasoning(from: raw)

            if let icon = extractIconFromXML(sanitizedContent) {
                return validateIcon(icon)
            }

            let ret = sanitizedContent.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            Logger.ui.debugFile("generated conversation icon: \(ret)")
            return validateIcon(ret)
        } catch {
            Logger.ui.errorFile("failed to generate icon: \(error)")
            return nil
        }
    }

    private func extractIconFromXML(_ xmlString: String) -> String? {
        // Try XMLCoder first
        if let icon = extractIconUsingXMLCoder(xmlString) {
            return icon
        }

        // Fallback to regex method
        return extractIconUsingRegex(xmlString)
    }

    private func extractIconUsingXMLCoder(_ xmlString: String) -> String? {
        let decoder = XMLDecoder()

        // Try to decode as IconResponse directly
        if let data = xmlString.data(using: .utf8),
           let iconResponse = try? decoder.decode(IconResponse.self, from: data)
        {
            let cleanIcon = iconResponse.icon
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanIcon.isEmpty ? nil : cleanIcon
        }

        return nil
    }

    private func extractIconUsingRegex(_ xmlString: String) -> String? {
        let pattern = #"<icon>(.*?)</icon>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(xmlString.startIndex ..< xmlString.endIndex, in: xmlString)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else {
            return nil
        }

        guard let iconRange = Range(match.range(at: 1), in: xmlString) else {
            return nil
        }

        let icon = String(xmlString[iconRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return icon.isEmpty ? nil : icon
    }

    private func validateIcon(_ icon: String) -> String? {
        guard !icon.isEmpty else { return nil }

        // Check if it's a single emoji character
        guard icon.count == 1 else {
            // If multiple characters, try to get the first emoji
            let firstEmoji = icon.first { $0.isEmoji }
            return firstEmoji.map(String.init)
        }

        return icon
    }
}

// MARK: - Character Extension for Emoji Detection

private extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji &&
            (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
