# Grid View Implementation

## Overview

The Grid View page provides a spreadsheet-style editing surface for contacts and groups. It embeds an AG Grid frontend bundle inside a SwiftUI `WKWebView`, with a two-way bridge that keeps the database, Swift services, and grid state in sync. The experience supports virtual scrolling (200-row pages), inline editing, multi-column sorting/filtering, custom columns, undo/redo, and column layout presets.

## Database Updates

- `contacts`
  - Added `nickname`, `tag_ids`, `relationship_ids`, `last_message_sent_date`, `last_message_received_date` columns.
- `groups`
  - Added `size`, `tags`, `child_group_ids`, `parent_group_ids` columns and default JSON storage for participants/member phones.
- New tables: `tags`, `relationships`, `grid_views`, `grid_custom_columns`, `grid_custom_cell_values`, `grid_edit_log`.
- All schema updates recorded in `database_requirements.json` with migrations in `DatabaseMigrations.swift` (`v5_grid_metrics_enhancements`).

## Service Layer

- `ContactRepository` and `GroupRepository`
  - Added paged fetch APIs with server-side sorting & filtering.
  - Added message metrics helpers and grid-friendly count methods.
- `GridViewService`
  - Centralizes preset management, custom column CRUD, undo/redo logging, and custom cell persistence.
  - Provides helper to fetch custom column values per record for each page.
- `TagService` / `RelationshipService`
  - Supply lookup & on-demand creation used when editing smart-chip fields (tags, relationships, groups).

## SwiftUI Bridge

- `GridViewPage` wraps `GridWebView` and the view preset sidebar with an in-view contacts/groups segmented toggle, a collapsible toolbar, and a native “New View” button that clones the current preset.
- `GridViewViewModel`
  - Streams pages to/from WebView, persists column layout changes, and manages per-user view presets.
  - Fetches custom column definitions/values and injects them into each paged row.
  - Exposes native UI for creating custom columns (name + type) and cloning presets, including default column scaffolding when no template exists.
- `GridWebView` coordinator routes messages:
  - `requestPage` → fetch page with sort/filter.
  - `edit` → apply database updates & append undo entry.
  - `columnStateChanged` → persist column order/visibility/frozen state for active view.
  - `customColumnsUpdated`, `activeViewChanged`, `entityChanged` keep the grid state aligned with Swift.

## AG Grid Frontend

- Infinite row model (200 row block size) with virtualized rendering for contacts & groups tabs.
- Column definitions include:
  - Contact columns (name, first/last, nickname, phone, email, address, notes, creation/birthday, groups, tags, relationships, message metrics, last sent/received).
  - Group columns (name, participants, color, created date, size, tags, children, parents).
  - Custom columns appended dynamically per view.
- Built-in AG Grid sorting/filtering are forwarded to Swift to execute at the database layer.
- Column moves, pinning, and visibility changes debounce into `columnStateChanged` messages so layouts persist.
- Undo/redo triggered by keyboard shortcuts updates rows via `editApplied` / `undoApplied` events.
- Copy/paste uses AG Grid clipboard (multi-cell paste surfaces multiple `cellValueChanged` events which the service layer processes sequentially).
- Grid background tracks the host macOS appearance so the web bundle inherits light/dark theming cues.

## Editing Semantics

- Smart chip columns (groups, tags, relationships) accept comma-separated entries; the service resolves them to database IDs, creating tags/relationships when missing.
- Non-editable metrics (message totals, last message timestamps) are flagged read-only server-side.
- Invalid pastes trigger `GridViewServiceError` which surfaces toast notifications via `editError` events.
- Undo/redo stack persisted per session in `grid_edit_log` and replayed through `GridViewService` helpers.
- Repeated database connectivity failures are deduplicated before surfacing UI/system notifications to avoid stacked warnings.

## View Presets & Custom Columns

- `GridViewConfig` stores visible columns, frozen columns, ordering, sort model, and filters per user + entity.
- Custom columns support per-view or global scope, data type metadata (text, number, date, phone, email, smartchip), and persisted values.
- Swift sidebar provides an “Add Column” workflow; web context menu interactions update presets automatically via column state messaging.

## Future Enhancements

- Smart chip editors with autocomplete (contacts, tags, relationships).
- Batch paste expansion (auto-adding rows/columns when pasted range exceeds current size).
- In-grid column creation UI and advanced filter builders.
