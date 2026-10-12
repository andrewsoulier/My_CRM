# My_CRM

Personal CRM that attaches **your location** to each message. v1 is a Mac-side SQLite service plus a minimal Swift iOS app that reports location. The iOS project is structured so we can grow into a **custom keyboard**, **iMessage extension**, and **standalone chat app**.

## How it works

1. Copy [`settings.example.json`](settings.example.json) → `settings.json` and set a strong `api_token`.
2. Run the Mac server; it creates the SQLite DB from [`mac/schema.sql`](mac/schema.sql).
3. On iPhone, the My CRM app uploads location samples to `POST /api/location` (use Tailscale).
4. When contacts/messages are imported (or posted to `POST /api/messages`), the server fills `latitude` / `longitude` on each message from the nearest location sample.

```text
iPhone (MyCRM app) --location samples--> Mac CRM API --join by time--> messages.lat/lon
                     Shared config also used later by Keyboard + iMessage stubs
```

## Mac server

```bash
cp settings.example.json settings.json
# edit api_token, and optionally database.path

python3 mac/crm_server.py --settings settings.json
# listens on http://0.0.0.0:8787 by default
```

Smoke test:

```bash
python3 mac/test_crm_server.py
```

Useful endpoints (all except `/health` require `Authorization: Bearer <api_token>`):

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Liveness |
| POST | `/api/location` | Ingest iOS location sample; backfills message locations |
| POST | `/api/messages` | Upsert a message (+ optional contact); attach location if possible |
| POST | `/api/contacts` | Upsert a contact |
| GET | `/api/messages` | Recent messages (includes location fields) |
| POST | `/api/location/backfill` | Re-run join for messages still missing location |

Keep the port on Tailscale/LAN only — do not expose it publicly.

## iOS app (Xcode on a Mac)

This environment cannot build iOS binaries. On a Mac with Xcode:

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. Create an App Group in your Apple Developer account: `group.com.mycrm.shared` (or change the id in sources + entitlements).
3. Generate and open the project:

```bash
cd ios
xcodegen generate
open MyCRM.xcodeproj
```

4. Set your Team / signing for **MyCRM**, **MyCRMKeyboard**, **MyCRMMessages**, and **MyCRMShared**.
5. Run **MyCRM** on a physical iPhone (Always + background location is unreliable on Simulator).
6. In the app: set base URL to `http://<mac-tailscale-ip>:8787` and the same API token as `settings.json`.
7. Grant **Always** location, then Start reporting.

### Targets

| Target | Role now | Later |
| --- | --- | --- |
| **MyCRM** | Settings UI + background location reporter | Full chat client against this API |
| **MyCRMShared** | Models, `APIClient`, App Group config | Chat sync models |
| **MyCRMKeyboard** | Stub keyboard (reads shared config) | CRM snippets / contact insert |
| **MyCRMMessages** | Stub iMessage extension | CRM cards / actions inside Messages |

**Platform note:** iOS cannot replace Apple Messages as the default SMS app. “Chat app” here means our CRM chat UI + an iMessage *extension*, not a system SMS replacement.

## Settings file

[`settings.example.json`](settings.example.json) is the single place that points at the CRM database and server auth. Import paths for contacts/messages can be filled in later under `import` without changing the iOS app.

## Roadmap

1. ~~Settings + SQLite + location→message join~~
2. ~~Minimal Swift app + Shared + Keyboard/iMessage stubs~~
3. Messages import from Mac `chat.db` (or JSONL feed) into `messages`
4. Chat UI in the main app (threads over `/api/messages`)
5. Flesh out keyboard + iMessage extensions using `MyCRMShared`
