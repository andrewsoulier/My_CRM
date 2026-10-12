# My CRM Documentation Index

This directory centralizes every markdown and text asset that explains how the project works. Use the table below to jump directly to the area you need.

| Folder | Purpose |
| --- | --- |
| `Architecture/` | High-level system overviews and navigation models that explain how data flows through My CRM. |
| `Build/` | Distribution, signing, and packaging guides for repeatable releases. |
| `Database/` | Schema requirements, GRDB notes, and repair playbooks for the persistence layer. |
| `Development/` | Refactoring plans, cleanup work, and major migration summaries. |
| `Features/` | Deep dives organized by feature area (Canvas, Chips, Contacts, Groups, Integrations, Messaging, Settings). |
| `Canvas/` | High-level system overviews and navigation models that explain how data flows through My CRM. |
| `Chips/` | Deep dives organized by feature area (Canvas, Chips, Contacts, Groups, Integrations, Messaging, Settings). |
| `Contacts/` | Contact import and normalization guides. |
| `Groups/` | Group management, toolbar, and participant handling documentation. |
| `Integrations/` | OpenAI/Gemini integration overview. |
| `Messaging/` | Batch messaging authorization, scheduling, message processing, and [message/contact sync reliability](Features/Messaging/MESSAGE_AND_CONTACT_SYNC_RELIABILITY.md) guides. |
| `Settings/` | Application settings and user preference documentation. |
| `Grid/` | [GRID_VIEW_IMPLEMENTATION.md](Features/Grid/GRID_VIEW_IMPLEMENTATION.md) – AG Grid-based spreadsheet editing architecture. |
| `Meta/` | Project rules, structural maps, and other reference utilities that govern how the repo stays organized. |
| `Notes/` | Ongoing working notes that capture context not yet distilled into formal docs. |
| `Operations/` | Field guides for remote recovery, permission automation, and other operational checklists. |
| `Requirements/` | Product and feature requirement specifications. |
| `Testing/` | Automated testing plans, validation checklists, and portability verification notes. |
| `User/` | End-user installation and onboarding guides. |

### Quick Start

- Start with `Architecture/` if you need the big picture.
- Check `Build/` before preparing a new release or signing run.
- Visit `Features/` for implementation specifics on individual modules.
- Use `Operations/` when supporting customer machines in the field.

### Contribution Rules

- Never leave markdown or text docs outside `Documentation/`; migrate ad-hoc notes here immediately.
- Update this index whenever you add, rename, or relocate a document so the table above stays accurate.
- Pick the narrowest folder that matches the topic; create subdirectories only if the category already exists in this index.

> After updating documentation or adding new guides, make sure the file lands in the appropriate folder above so future contributors can find it instantly.

