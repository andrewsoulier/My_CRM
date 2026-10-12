import Foundation
import GRDB

/// Database schema migrations
/// Each migration is versioned and runs only once
struct DatabaseMigrations {
    
    /// Register all migrations in order
    static func registerMigrations(on migrator: inout DatabaseMigrator) {
        
        // MARK: - Migration v1: Initial Schema
        
        migrator.registerMigration("v1_initial_schema") { db in
            // Create contacts table
            try db.create(table: "contacts", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("phone", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("first_name", .text)
                t.column("last_name", .text)
                t.column("email", .text)
                t.column("address", .text)
                t.column("notes", .text)
                t.column("creation_date", .text)
                t.column("business", .text)
                t.column("contact_group", .text)
                t.column("birthday", .text)
                t.column("apple_contact_id", .text)
                t.column("profile_photo", .blob)
                t.column("first_message_date", .text)
                t.column("last_message_date", .text)
                t.column("total_messages", .integer).defaults(to: 0)
                t.column("messages_sent", .integer).defaults(to: 0)
                t.column("messages_received", .integer).defaults(to: 0)
                t.column("is_primary_user", .integer).defaults(to: 0)
                t.column("sent_last_message", .integer)
                t.column("groups", .text).defaults(to: "[]")
            }
            
            // Create indexes for contacts
            try db.create(index: "idx_contacts_phone", on: "contacts", columns: ["phone"], unique: true, ifNotExists: true)
            try db.create(index: "idx_contacts_apple_id", on: "contacts", columns: ["apple_contact_id"], ifNotExists: true)
            try db.create(index: "idx_contacts_name", on: "contacts", columns: ["name"], ifNotExists: true)
            try db.create(index: "idx_contacts_business", on: "contacts", columns: ["business"], ifNotExists: true)
            
            // Create groups table
            try db.create(table: "groups", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("parent_id", .text)
                t.column("member_phones", .text)
                t.column("linked_group_ids", .text)
                t.column("metadata", .text)
                t.column("is_deck", .integer).defaults(to: 0)
                t.column("participants", .text).defaults(to: "[]")
                t.column("canvases", .text).defaults(to: "[]")
            }
            
            // Create indexes for groups
            try db.create(index: "idx_groups_id", on: "groups", columns: ["id"], unique: true, ifNotExists: true)
            try db.create(index: "idx_groups_name", on: "groups", columns: ["name"], ifNotExists: true)
            try db.create(index: "idx_groups_parent_id", on: "groups", columns: ["parent_id"], ifNotExists: true)
            
            // Create messages table
            try db.create(table: "messages", ifNotExists: true) { t in
                t.column("guid", .text).primaryKey()
                t.column("rowid", .integer)
                t.column("body", .text)
                t.column("phone_number", .text)
                t.column("is_from_me", .boolean).defaults(to: false)
                t.column("cache_roomname", .text)
                t.column("group_chat_name", .text)
                t.column("timestamp", .integer)
                t.column("service", .text)
                t.column("account", .text)
                t.column("chat_id", .text)
                t.column("attributedBody", .blob)
                t.column("subject", .text)
                t.column("country", .text)
                t.column("error", .integer).defaults(to: 0)
                t.column("date_read", .integer).defaults(to: 0)
                t.column("date_delivered", .integer).defaults(to: 0)
                t.column("is_sent", .integer).defaults(to: 0)
                t.column("is_read", .integer).defaults(to: 0)
                t.column("has_attachments", .boolean).defaults(to: false)
                t.column("contact_id", .integer)
                t.column("message_type", .text)
                t.column("is_first_message", .integer).defaults(to: 0)
                t.column("is_last_message", .integer).defaults(to: 0)
                t.column("is_new", .integer).defaults(to: 0)
                t.column("source", .text).defaults(to: "imessage")
            }
            
            // Create indexes for messages
            try db.create(index: "idx_messages_guid", on: "messages", columns: ["guid"], unique: true, ifNotExists: true)
            try db.create(index: "idx_messages_phone_number", on: "messages", columns: ["phone_number"], ifNotExists: true)
            try db.create(index: "idx_messages_timestamp", on: "messages", columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_messages_contact_id", on: "messages", columns: ["contact_id"], ifNotExists: true)
            try db.create(index: "idx_messages_chat_id", on: "messages", columns: ["chat_id"], ifNotExists: true)
            try db.create(index: "idx_messages_is_from_me", on: "messages", columns: ["is_from_me"], ifNotExists: true)
            
            // Create invites table
            try db.create(table: "invites", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("creation_date", .text).notNull()
                t.column("last_modified_date", .text).notNull()
                t.column("date_completed", .text)
                t.column("completed", .integer).defaults(to: 0)
                t.column("completion_status", .text).defaults(to: "pending")
                t.column("sent_received", .text).notNull()
                t.column("to_phone", .text)
                t.column("from_phone", .text)
                t.column("priority", .integer).defaults(to: 1)
                t.column("due_date", .text)
                t.column("parent_tasks", .text).defaults(to: "[]")
                t.column("child_tasks", .text).defaults(to: "[]")
                t.column("tags", .text).defaults(to: "{}")
                t.column("groups", .text).defaults(to: "[]")
                t.column("task_group", .text).defaults(to: "{}")
                t.column("ai_processed", .integer).defaults(to: 0)
                t.column("ai_suggestions", .text).defaults(to: "{}")
                t.column("ai_confidence", .double).defaults(to: 0.0)
                t.column("reminder_date", .text)
                t.column("message_origin_guid", .text)
                t.column("is_recurring", .integer).defaults(to: 0)
                t.column("recurrence_type", .text).defaults(to: "none")
                t.column("next_task_id", .text)
                t.column("previous_task_id", .text)
                t.column("is_next_task", .integer).defaults(to: 0)
                t.column("date_of_last_task", .text)
                t.column("created_by", .text)
                t.column("assigned_to", .text)
                t.column("category", .text)
                t.column("location", .text)
                t.column("estimated_duration", .integer)
                t.column("attachments", .text).defaults(to: "[]")
                t.column("external_id", .text)
                t.column("last_ai_analysis", .text)
            }
            
            // Create indexes for invites
            try db.create(index: "idx_invites_id", on: "invites", columns: ["id"], unique: true, ifNotExists: true)
            try db.create(index: "idx_invites_to_phone", on: "invites", columns: ["to_phone"], ifNotExists: true)
            try db.create(index: "idx_invites_from_phone", on: "invites", columns: ["from_phone"], ifNotExists: true)
            try db.create(index: "idx_invites_creation_date", on: "invites", columns: ["creation_date"], ifNotExists: true)
            try db.create(index: "idx_invites_due_date", on: "invites", columns: ["due_date"], ifNotExists: true)
            try db.create(index: "idx_invites_completed", on: "invites", columns: ["completed"], ifNotExists: true)
            try db.create(index: "idx_invites_priority", on: "invites", columns: ["priority"], ifNotExists: true)
            try db.create(index: "idx_invites_sent_received", on: "invites", columns: ["sent_received"], ifNotExists: true)
            
            print("✅ Migration v1: Initial schema completed")
        }
        
        // MARK: - Migration v2: Add Canvases Table
        
        migrator.registerMigration("v2_add_canvases") { db in
            try db.create(table: "canvases", ifNotExists: true) { t in
                t.column("canvas_id", .text).primaryKey()
                t.column("canvas_name", .text).notNull()
                t.column("canvas_elements", .text).notNull().defaults(to: "[]")
                t.column("element_counts", .text).notNull().defaults(to: "{}")
                t.column("date_created", .text).notNull()
                t.column("date_updated", .text).notNull()
                t.column("last_saved", .text)
                t.column("canvas_type", .text).notNull().defaults(to: "group_map")
                t.column("canvas_state", .text).defaults(to: "{}")
                t.column("metadata", .text).defaults(to: "{}")
            }
            
            // Create indexes for canvases
            try db.create(index: "idx_canvases_id", on: "canvases", columns: ["canvas_id"], unique: true, ifNotExists: true)
            try db.create(index: "idx_canvases_name", on: "canvases", columns: ["canvas_name"], ifNotExists: true)
            try db.create(index: "idx_canvases_type", on: "canvases", columns: ["canvas_type"], ifNotExists: true)
            try db.create(index: "idx_canvases_created", on: "canvases", columns: ["date_created"], ifNotExists: true)
            try db.create(index: "idx_canvases_updated", on: "canvases", columns: ["date_updated"], ifNotExists: true)
            
            print("✅ Migration v2: Canvases table added")
        }
        
        // MARK: - Migration v3: Add Batch Messages Table
        
        migrator.registerMigration("v3_add_batch_messages") { db in
            try db.create(table: "batch_messages", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("message_template", .text).notNull()
                t.column("chip_metadata", .text)
                t.column("recipients", .text).notNull()
                t.column("scheduled_time", .text)
                t.column("created_time", .text).notNull()
                t.column("status", .text).notNull()
                t.column("total_recipients", .integer).notNull()
                t.column("sent_count", .integer).defaults(to: 0)
                t.column("failed_count", .integer).defaults(to: 0)
                t.column("failed_contacts", .text).defaults(to: "{}")
                t.column("completed_time", .text)
                t.column("notify_when_sent", .integer).defaults(to: 0)
                t.column("error_log", .text).defaults(to: "[]")
                t.column("source_groups", .text)
            }
            
            // Create indexes for batch messages
            try db.create(index: "idx_batch_messages_id", on: "batch_messages", columns: ["id"], unique: true, ifNotExists: true)
            try db.create(index: "idx_batch_messages_status", on: "batch_messages", columns: ["status"], ifNotExists: true)
            try db.create(index: "idx_batch_messages_scheduled_time", on: "batch_messages", columns: ["scheduled_time"], ifNotExists: true)
            try db.create(index: "idx_batch_messages_created_time", on: "batch_messages", columns: ["created_time"], ifNotExists: true)
            
            print("✅ Migration v3: Batch messages table added")
        }
        
        // MARK: - Migration v4: Grid View support schema
        
        migrator.registerMigration("v4_grid_view_schema") { db in
            // Extend contacts table - check if columns exist first
            let contactColumns = try db.columns(in: "contacts").map { $0.name }
            if !contactColumns.contains("nickname") {
                try db.alter(table: "contacts") { t in
                    t.add(column: "nickname", .text)
                }
            }
            if !contactColumns.contains("tag_ids") {
                try db.alter(table: "contacts") { t in
                    t.add(column: "tag_ids", .text).defaults(to: "[]")
                }
            }
            if !contactColumns.contains("relationship_ids") {
                try db.alter(table: "contacts") { t in
                    t.add(column: "relationship_ids", .text).defaults(to: "[]")
                }
            }
            
            // Extend groups table - check if columns exist first
            let groupColumns = try db.columns(in: "groups").map { $0.name }
            if !groupColumns.contains("tags") {
                try db.alter(table: "groups") { t in
                    t.add(column: "tags", .text).defaults(to: "[]")
                }
            }
            if !groupColumns.contains("child_group_ids") {
                try db.alter(table: "groups") { t in
                    t.add(column: "child_group_ids", .text).defaults(to: "[]")
                }
            }
            if !groupColumns.contains("parent_group_ids") {
                try db.alter(table: "groups") { t in
                    t.add(column: "parent_group_ids", .text).defaults(to: "[]")
                }
            }
            
            // Create tags table
            try db.create(table: "tags", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("color", .text)
                t.column("description", .text)
                t.column("linked_contacts", .text).defaults(to: "[]")
                t.column("linked_groups", .text).defaults(to: "[]")
            }
            
            try db.create(index: "idx_tags_uuid", on: "tags", columns: ["uuid"], unique: true, ifNotExists: true)
            try db.create(index: "idx_tags_name", on: "tags", columns: ["name"], ifNotExists: true)
            
            // Create relationships table
            try db.create(table: "relationships", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("color", .text)
                t.column("description", .text)
                t.column("linked_contacts", .text).defaults(to: "[]")
                t.column("linked_groups", .text).defaults(to: "[]")
            }
            
            try db.create(index: "idx_relationships_uuid", on: "relationships", columns: ["uuid"], unique: true, ifNotExists: true)
            try db.create(index: "idx_relationships_name", on: "relationships", columns: ["name"], ifNotExists: true)

            // Create grid views table
            try db.create(table: "grid_views", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("entity_type", .text).notNull()
                t.column("user_id", .text).notNull().defaults(to: "default")
                t.column("visible_columns", .text).defaults(to: "[]")
                t.column("frozen_columns", .text).defaults(to: "[]")
                t.column("column_order", .text).defaults(to: "[]")
                t.column("sort_model", .text).defaults(to: "[]")
                t.column("filter_model", .text).defaults(to: "{}")
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            
            try db.create(index: "idx_grid_views_uuid", on: "grid_views", columns: ["uuid"], unique: true, ifNotExists: true)
            try db.create(index: "idx_grid_views_user_entity", on: "grid_views", columns: ["user_id", "entity_type"], ifNotExists: true)
            
            // Create custom columns table
            try db.create(table: "grid_custom_columns", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("view_uuid", .text)
                t.column("entity_type", .text).notNull()
                t.column("user_id", .text).notNull().defaults(to: "default")
                t.column("name", .text).notNull()
                t.column("data_type", .text).notNull()
                t.column("is_visible", .boolean).defaults(to: true)
                t.column("order_index", .integer)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            
            try db.create(index: "idx_grid_custom_columns_uuid", on: "grid_custom_columns", columns: ["uuid"], unique: true, ifNotExists: true)
            try db.create(index: "idx_grid_custom_columns_view", on: "grid_custom_columns", columns: ["view_uuid"], ifNotExists: true)
            try db.create(index: "idx_grid_custom_columns_user_entity", on: "grid_custom_columns", columns: ["user_id", "entity_type"], ifNotExists: true)
            
            // Create custom cell values table
            try db.create(table: "grid_custom_cell_values", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("column_uuid", .text).notNull()
                t.column("record_id", .text).notNull()
                t.column("entity_type", .text).notNull()
                t.column("value", .text)
                t.column("updated_at", .text).notNull()
                t.uniqueKey(["column_uuid", "record_id"], onConflict: .replace)
                t.foreignKey(["column_uuid"], references: "grid_custom_columns", onDelete: .cascade, onUpdate: .cascade)
            }
            
            try db.create(index: "idx_grid_custom_cell_values_entity", on: "grid_custom_cell_values", columns: ["entity_type", "record_id"], ifNotExists: true)
            
            // Create grid edit log table
            try db.create(table: "grid_edit_log", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("session_id", .text).notNull()
                t.column("entity_type", .text).notNull()
                t.column("record_id", .text).notNull()
                t.column("column_id", .text).notNull()
                t.column("previous_value", .text)
                t.column("next_value", .text)
                t.column("created_at", .text).notNull()
                t.column("direction", .text).notNull()
            }
            
            try db.create(index: "idx_grid_edit_log_session", on: "grid_edit_log", columns: ["session_id", "created_at"], ifNotExists: true)
            
            print("✅ Migration v4: Grid view schema updates applied")
        }

        // MARK: - Migration v5: Grid metrics enhancements

        migrator.registerMigration("v5_grid_metrics_enhancements") { db in
            let contactColumns = try db.columns(in: "contacts").map { $0.name }
            if !contactColumns.contains("last_message_sent_date") {
                try db.alter(table: "contacts") { t in
                    t.add(column: "last_message_sent_date", .text)
                }
            }
            if !contactColumns.contains("last_message_received_date") {
                try db.alter(table: "contacts") { t in
                    t.add(column: "last_message_received_date", .text)
                }
            }

            let groupColumns = try db.columns(in: "groups").map { $0.name }
            if !groupColumns.contains("size") {
                try db.alter(table: "groups") { t in
                    t.add(column: "size", .integer).defaults(to: 0)
                }
            }

            print("✅ Migration v5: Contact message dates and group size column added")
        }
        
        // MARK: - Migration v6: Add filter_model_data column
        
        migrator.registerMigration("v6_add_filter_model_data") { db in
            // Add filter_model_data column to grid_views table for new filter system
            try db.alter(table: "grid_views") { t in
                t.add(column: "filter_model_data", .blob)
            }
        }
        
        // MARK: - Migration v7: Add macOS Group ID for Contacts sync
        
        migrator.registerMigration("v7_add_macos_group_id") { db in
            // Add macos_group_id column to groups table for macOS Contacts sync
            let groupColumns = try db.columns(in: "groups").map { $0.name }
            if !groupColumns.contains("macos_group_id") {
                try db.alter(table: "groups") { t in
                    t.add(column: "macos_group_id", .text)
                }
                // Create index for faster lookups
                try db.create(index: "idx_groups_macos_group_id", on: "groups", columns: ["macos_group_id"], ifNotExists: true)
            }
            print("✅ Migration v7: macOS Group ID column added")
        }
        
        // MARK: - Future Migrations
        
        // Add new migrations below as schema evolves
        // Example:
        // migrator.registerMigration("v4_add_new_column") { db in
        //     try db.alter(table: "contacts") { t in
        //         t.add(column: "new_field", .text)
        //     }
        // }
    }
}

