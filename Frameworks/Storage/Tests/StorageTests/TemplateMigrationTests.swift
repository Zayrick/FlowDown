//
//  TemplateMigrationTests.swift
//  StorageTests
//
//  Created by Assistant on 2025/12/07.
//

import Foundation
@testable import Storage
import Testing
import WCDBSwift

struct TemplateMigrationTests {
    @Test
    func `V4 -> V5 creates ChatTemplate table and bumps userVersion`() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("migration.db")
        let database = Database(at: databaseURL.path)
        defer { database.close() }

        // simulate existing schema at v4
        try database.exec(StatementPragma().pragma(.userVersion).to(DBVersion.Version4.rawValue))

        let migration = MigrationV4ToV5()
        try migration.migrate(db: database)

        #expect(try database.isTableExists(ChatTemplateRecord.tableName))
        let userVersion = try database.getValue(from: StatementPragma().pragma(.userVersion))?.intValue
        #expect(userVersion == DBVersion.Version5.rawValue)
    }
}
