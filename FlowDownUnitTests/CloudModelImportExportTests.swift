//
//  CloudModelImportExportTests.swift
//  FlowDownUnitTests
//
//  Created by GitHub Copilot on 12/19/2025.
//

@testable import ChatClientKit
import Combine
@testable import FlowDown
import Foundation
@testable import OrderedCollections
@testable import Storage
import Testing

struct ImportExportRoundTripSuite {
    private func ensureEnvironment() throws {
        if AppEnvironment.isBootstrapped {
            return
        }

        let storage = try Storage.db()
        let syncEngine = SyncEngine(
            storage: storage,
            containerIdentifier: CloudKitConfig.containerIdentifier,
            mode: .mock,
            automaticallySync: false,
        )
        AppEnvironment.bootstrap(.init(storage: storage, syncEngine: syncEngine))
    }

    @MainActor
    private func resetRelevantData() {
        // Cloud models
        for model in sdb.cloudModelList() {
            sdb.cloudModelRemove(identifier: model.id)
        }

        // MCP servers
        for server in MCPService.shared.servers.value {
            MCPService.shared.remove(server.id)
        }

        // Chat templates
        for templateId in Array(ChatTemplateManager.shared.templates.keys) {
            ChatTemplateManager.shared.remove(for: templateId)
        }
    }

    @Test
    func `Cloud model .fdmodel export/import round-trip persists data`() async throws {
        try ensureEnvironment()
        await resetRelevantData()

        // Ensure a clean slate.
        #expect(sdb.cloudModelList().isEmpty)

        // Create a model with enough fields to catch partial imports.
        let original = CloudModel(
            deviceId: Storage.deviceId,
            objectId: "test-object-id",
            model_identifier: "test-scope/test-model",
            model_list_endpoint: "$INFERENCE_ENDPOINT$/../../models",
            creation: Date(timeIntervalSince1970: 1_735_000_000),
            endpoint: "https://example.invalid/v1/chat/completions",
            token: "test-token",
            headers: [
                "Authorization": "Bearer OVERRIDE",
                "X-Title": "FlowDown",
            ],
            bodyFields: #"{"foo":"bar","temperature":0.2}"#,
            context: .medium_64k,
            capabilities: [.visual, .tool],
            comment: "test-comment",
            name: "Test Model",
            response_format: .chatCompletions,
        )
        try sdb.cloudModelPut(original)
        #expect(sdb.cloudModelList().count == 1)

        // Export to .fdmodel (plist XML), mimicking the app's export.
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudModelRoundTrip")
            .appendingPathExtension(ModelManager.flowdownModelConfigurationExtension)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let exported = try encoder.encode(original)
        try exported.write(to: fileURL, options: .atomic)

        // Remove existing data and import from file.
        sdb.cloudModelRemove(identifier: original.id)
        #expect(sdb.cloudModelList().isEmpty)

        let imported = try ModelManager.shared.importCloudModel(at: fileURL)

        // Import should treat the file as a new local object.
        #expect(imported.id != original.id)

        // Validate it actually persisted.
        let stored = sdb.cloudModel(with: imported.id)
        #expect(stored != nil)

        // Validate key fields survived the round trip.
        #expect(imported.deviceId == Storage.deviceId)
        #expect(imported.model_identifier == original.model_identifier)
        #expect(imported.endpoint == original.endpoint)
        #expect(imported.token == original.token)
        #expect(imported.headers == original.headers)
        #expect(imported.bodyFields == original.bodyFields)
        #expect(imported.context == original.context)
        #expect(imported.capabilities == original.capabilities)
        #expect(imported.comment == original.comment)
        #expect(imported.name == original.name)
        #expect(imported.response_format == original.response_format)
    }

    @Test
    func `MCP server .fdmcp export/import round-trip persists data`() async throws {
        try ensureEnvironment()
        await resetRelevantData()

        #expect(MCPService.shared.servers.value.isEmpty)

        let original = ModelContextServer(
            name: "Test MCP",
            comment: "test-comment",
            type: .http,
            endpoint: "https://example.invalid/mcp",
            header: "Authorization: Bearer test",
            timeout: 15,
            isEnabled: true,
        )
        original.update(\.objectId, to: "test-mcp-object-id")
        MCPService.shared.insert(original)
        #expect(MCPService.shared.servers.value.count == 1)

        let exported = try MCPService.shared.exportServerData(original)

        MCPService.shared.remove(original.id)
        #expect(MCPService.shared.servers.value.isEmpty)

        let imported = try await MainActor.run {
            try MCPService.shared.importServer(from: exported)
        }

        // Import should treat the file as a new local object.
        #expect(imported.id != original.id)

        let stored = MCPService.shared.server(with: imported.id)
        #expect(stored != nil)
        #expect(imported.endpoint == original.endpoint)
        #expect(imported.header == original.header)
        #expect(imported.timeout == original.timeout)
        #expect(imported.type == original.type)
        #expect(imported.name == original.name)
        #expect(imported.comment == original.comment)
    }

    @Test
    func `Chat template .fdtemplate export/import round-trip persists data`() async throws {
        try ensureEnvironment()
        await resetRelevantData()

        #expect(ChatTemplateManager.shared.templates.isEmpty)

        var original = ChatTemplate()
        original.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        original.name = "Test Template"
        original.prompt = "You are a helpful assistant."
        original.inheritApplicationPrompt = false
        original.avatar = Data([0x01, 0x02, 0x03])

        await MainActor.run {
            ChatTemplateManager.shared.addTemplate(original)
        }
        #expect(ChatTemplateManager.shared.templates.count == 1)

        let exported = try ChatTemplateManager.shared.exportTemplateData(original)

        await MainActor.run {
            ChatTemplateManager.shared.remove(for: original.id)
        }
        #expect(ChatTemplateManager.shared.templates.isEmpty)

        let imported = try await MainActor.run {
            try ChatTemplateManager.shared.importTemplate(from: exported)
        }

        // Import should treat the file as a new local object.
        #expect(imported.id != original.id)

        let stored = await MainActor.run {
            ChatTemplateManager.shared.template(for: imported.id)
        }
        #expect(stored != nil)
        #expect(imported.name == original.name)
        #expect(imported.prompt == original.prompt)
        #expect(imported.inheritApplicationPrompt == original.inheritApplicationPrompt)
        #expect(imported.avatar == original.avatar)
    }
}
