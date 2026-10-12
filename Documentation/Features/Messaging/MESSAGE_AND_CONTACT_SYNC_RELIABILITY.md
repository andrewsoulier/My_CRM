# Message & Contact Sync Reliability

**Date**: July 7, 2026
**Status**: Implemented
**Goal**: Ensure the app always loads all contacts and stays current with new iMessages.

## Overview

Previously, contacts and messages could load incompletely or fall behind `chat.db`:

- Imports ran fire-and-forget at startup and the UI never refreshed when they finished.
- Message import was gated behind Automation authorization (used for *sending*), so it was usually skipped even when Full Disk Access was granted.
- `ChatDBMonitor` detected changes to `chat.db` but never triggered an import.
- Contacts without a first phone number, or with additional phone numbers, were silently dropped.
- The whole contacts table (including profile-photo BLOBs) was loaded into memory with a per-row `print()`, slowing startup.

This work introduces a single coordinator that runs imports, enriches contacts from messages, refreshes the UI, and keeps messages current via a file-system monitor and a periodic fallback timer.

## New Components

### `ImportSyncCoordinator` (`Core/Services/ImportSyncCoordinator.swift`)
Central `@MainActor` coordinator for all import + refresh work.

- `runStartupImports(useContacts:useMessages:)` — runs contact and message imports in parallel, enriches contacts, refreshes the UI, and posts `.importSyncCompleted`.
- `scheduleIncrementalMessageSync(debounceSeconds:)` — debounced incremental sync used by the `chat.db` monitor (default 5s).
- `runIncrementalMessageSync()` — imports new messages, enriches contacts, and refreshes the UI.
- Guards against overlapping runs with an `isSyncing` flag.

### `ContactMessageEnrichmentService` (`Core/Services/ContactMessageEnrichmentService.swift`)
Swift port of the legacy Python enrichment step. After a message import it:

- Links `messages` to `contacts` by exact phone match or last-10-digit normalized match.
- Recomputes `first_message_date`, `last_message_date`, `total_messages`, `messages_sent`, `messages_received`, and `sent_last_message`.
- Runs inside a single transaction.

### `.importSyncCompleted` notification (`Core/Services/ImportSyncNotifications.swift`)
Broadcast when an import/enrichment cycle finishes so view models can re-sync.

## Changed Components

### `StartOrchestrator`
- Message import is now gated on **Full Disk Access only** (`PermissionManager.shared.hasFullDiskAccess()`) instead of Automation authorization. Automation status is still checked separately for *sending*.
- Startup imports are awaited through `ImportSyncCoordinator` before verification checkpoints run.

### `ContactsImporter`
- When Contacts permission is `.notDetermined`, it now requests access on the main thread (with a 120s timeout) instead of returning zero results.
- Imports **all** phone numbers per contact (previously only the first); email is used only when no phone exists.
- Contacts skipped for having no phone and no email are logged with a reason.

### `MessagesImporter`
- Uses a parameterized `WHERE m.date >= ?` query.
- Decodes `attributedBody` when `message.text` is `NULL` so modern messages are not stored blank.
- Upserts in batches of 5,000 rows, each wrapped in a transaction.

### `MessagesDAO`
- `upsertBatch` now wraps inserts in `BEGIN IMMEDIATE TRANSACTION` / `COMMIT`.

### `ChatDBMonitor`
- Converted to a shared singleton.
- On detecting a `chat.db` modification (20s poll), it triggers a debounced incremental sync through `ImportSyncCoordinator`.

### `ContactsViewModel`
- Observer no longer requires a non-empty contact list, so an empty→populated transition after a background import now refreshes the UI.
- Subscribes to `.importSyncCompleted` to re-sync.
- Falls back to `SettingsManager.shared.settings.database.path` instead of a hard-coded database path.

### `SQLiteDataProvider`
- Startup contact query no longer selects `profile_photo`; photos load lazily. This removes large BLOBs from the hot path.
- Removed the per-contact `print()` in the load loop.
- macOS Contacts outbound sync is deferred ~3s after the UI loads.

### `MyCRMApp`
- Starts `ChatDBMonitor.shared` and `AppModel.startDataCheckTimer()` ~5s after launch.
- `AppModel.checkForNewData()` now calls `ImportSyncCoordinator.runIncrementalMessageSync()` instead of the deprecated Python path.
- Added a `--import-messages` CLI flag for headless catch-up imports (see below).

## Startup Flow

```
MyCRMApp.init (+3.5s)
  └─ StartOrchestrator.run
       └─ ImportSyncCoordinator.runStartupImports
            ├─ ContactsImporter.run            (parallel)
            ├─ MessagesImporter.run            (parallel, FDA required)
            ├─ ContactMessageEnrichmentService.run
            ├─ SQLiteDataProvider.refreshUIData
            └─ post .importSyncCompleted

MyCRMApp.init (+5s)
  ├─ ChatDBMonitor.shared.start   (20s poll → debounced incremental sync)
  └─ AppModel.startDataCheckTimer (90s fallback → incremental sync)
```

## Command-Line Catch-Up Import

Because a sandboxed GUI launch may not yet have Full Disk Access, you can run the
importer headlessly (the process must have Full Disk Access, e.g. Terminal):

```bash
"/Users/andrewsoulier/My_CRM Project/MY CRM/.build/arm64-apple-macosx/release/My CRM" --import-messages
```

This runs `MessagesImporter` + `ContactMessageEnrichmentService` and exits, printing the number of new messages and enriched contacts.

## Requirements

- **Full Disk Access** on `/Applications/My CRM.app` is required for the GUI app to read `~/Library/Messages/chat.db`. Grant it in *System Settings → Privacy & Security → Full Disk Access*, then relaunch.
- **Contacts permission** is requested on first launch; granting it enables the multi-phone contact import.

## Verification

- App launch shows all contacts without a manual refresh.
- `SELECT COUNT(*) FROM messages` tracks `chat.db` within the expected deleted/archived delta.
- Sending a new iMessage results in a new row appearing within ~20–30s via `ChatDBMonitor`.
- Restarting the app performs an incremental import only (no data loss).
