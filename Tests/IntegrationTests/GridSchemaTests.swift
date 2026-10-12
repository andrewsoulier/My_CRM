import XCTest
import GRDB
@testable import My_CRM

final class GridSchemaTests: XCTestCase {
    
    func testGridSchemaMigrationCreatesRequiredStructures() throws {
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerMigrations(on: &migrator)
        
        let dbQueue = try DatabaseQueue()
        try migrator.migrate(dbQueue)
        
        try dbQueue.read { db in
            try assertColumnExists("contacts", column: "nickname", db: db)
            try assertColumnExists("contacts", column: "tag_ids", db: db)
            try assertColumnExists("contacts", column: "relationship_ids", db: db)
            
            try assertColumnExists("groups", column: "tags", db: db)
            try assertColumnExists("groups", column: "child_group_ids", db: db)
            try assertColumnExists("groups", column: "parent_group_ids", db: db)
            
            try assertTableExists("tags", db: db)
            try assertTableExists("relationships", db: db)
            try assertTableExists("grid_views", db: db)
            try assertTableExists("grid_custom_columns", db: db)
            try assertTableExists("grid_custom_cell_values", db: db)
            try assertTableExists("grid_edit_log", db: db)
        }
    }
    
    // MARK: - Helpers
    
    private func assertColumnExists(_ table: String, column: String, db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
        let containsColumn = rows.contains(where: { row in
            row["name"] == column
        })
        XCTAssertTrue(containsColumn, "Expected column \(column) in table \(table)")
    }
    
    private func assertTableExists(_ table: String, db: Database) throws {
        let exists = try Bool.fetchOne(db, sql: "SELECT COUNT(*) > 0 FROM sqlite_master WHERE type = 'table' AND name = ?", arguments: [table])
        XCTAssertEqual(exists, true, "Expected table \(table) to exist after migrations")
    }
}

