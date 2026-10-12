#!/usr/bin/env python3
"""Minimal My_CRM Mac server: settings-backed SQLite, location ingest, message location join."""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SETTINGS = ROOT / "settings.json"
SCHEMA_PATH = Path(__file__).resolve().parent / "schema.sql"


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def parse_iso(value: str) -> datetime:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    dt = datetime.fromisoformat(text)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def load_settings(path: Path) -> dict[str, Any]:
    if not path.exists():
        example = ROOT / "settings.example.json"
        raise SystemExit(
            f"Missing {path}. Copy {example.name} to settings.json and set api_token."
        )
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def db_connect(settings: dict[str, Any]) -> sqlite3.Connection:
    db_path = Path(settings["database"]["path"])
    if not db_path.is_absolute():
        db_path = (ROOT / db_path).resolve()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    with SCHEMA_PATH.open(encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.commit()
    return conn


def authorize(handler: BaseHTTPRequestHandler, token: str) -> bool:
    header = handler.headers.get("Authorization", "")
    if header == f"Bearer {token}":
        return True
    handler.send_json(401, {"error": "unauthorized"})
    return False


def find_nearest_sample(
    conn: sqlite3.Connection, sent_at: str, max_skew_seconds: int
) -> sqlite3.Row | None:
    target = parse_iso(sent_at)
    rows = conn.execute(
        """
        SELECT * FROM location_samples
        ORDER BY ABS(strftime('%s', recorded_at) - strftime('%s', ?))
        LIMIT 1
        """,
        (sent_at,),
    ).fetchall()
    if not rows:
        return None
    sample = rows[0]
    delta = abs((parse_iso(sample["recorded_at"]) - target).total_seconds())
    if delta > max_skew_seconds:
        return None
    return sample


def attach_location_to_message(
    conn: sqlite3.Connection, message_id: int, max_skew_seconds: int
) -> bool:
    msg = conn.execute(
        "SELECT id, sent_at, latitude FROM messages WHERE id = ?",
        (message_id,),
    ).fetchone()
    if msg is None or msg["latitude"] is not None:
        return False
    sample = find_nearest_sample(conn, msg["sent_at"], max_skew_seconds)
    if sample is None:
        return False
    conn.execute(
        """
        UPDATE messages
        SET latitude = ?, longitude = ?, accuracy_m = ?,
            located_at = ?, location_sample_id = ?
        WHERE id = ?
        """,
        (
            sample["latitude"],
            sample["longitude"],
            sample["accuracy_m"],
            sample["recorded_at"],
            sample["id"],
            message_id,
        ),
    )
    return True


def backfill_message_locations(conn: sqlite3.Connection, max_skew_seconds: int) -> int:
    rows = conn.execute(
        "SELECT id FROM messages WHERE latitude IS NULL ORDER BY sent_at"
    ).fetchall()
    updated = 0
    for row in rows:
        if attach_location_to_message(conn, row["id"], max_skew_seconds):
            updated += 1
    conn.commit()
    return updated


def upsert_contact(
    conn: sqlite3.Connection, *, name: str | None, phone: str | None, imessage_id: str | None
) -> int:
    existing = None
    if phone:
        existing = conn.execute(
            "SELECT id FROM contacts WHERE phone = ?", (phone,)
        ).fetchone()
    if existing is None and imessage_id:
        existing = conn.execute(
            "SELECT id FROM contacts WHERE imessage_id = ?", (imessage_id,)
        ).fetchone()
    if existing:
        conn.execute(
            """
            UPDATE contacts
            SET name = COALESCE(?, name),
                phone = COALESCE(?, phone),
                imessage_id = COALESCE(?, imessage_id),
                updated_at = ?
            WHERE id = ?
            """,
            (name, phone, imessage_id, utc_now_iso(), existing["id"]),
        )
        return int(existing["id"])
    cur = conn.execute(
        """
        INSERT INTO contacts (name, phone, imessage_id)
        VALUES (?, ?, ?)
        """,
        (name, phone, imessage_id),
    )
    return int(cur.lastrowid)


class CRMHandler(BaseHTTPRequestHandler):
    settings: dict[str, Any]
    conn: sqlite3.Connection

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        if not raw:
            return {}
        data = json.loads(raw.decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("JSON object required")
        return data

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_json(200, {"ok": True, "time": utc_now_iso()})
            return
        token = self.settings["server"]["api_token"]
        if not authorize(self, token):
            return
        if parsed.path == "/api/messages":
            qs = parse_qs(parsed.query)
            limit = int(qs.get("limit", ["50"])[0])
            rows = self.conn.execute(
                """
                SELECT m.*, c.name AS contact_name, c.phone AS contact_phone
                FROM messages m
                LEFT JOIN contacts c ON c.id = m.contact_id
                ORDER BY m.sent_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
            self.send_json(200, {"messages": [dict(r) for r in rows]})
            return
        if parsed.path == "/api/location/latest":
            row = self.conn.execute(
                "SELECT * FROM location_samples ORDER BY recorded_at DESC LIMIT 1"
            ).fetchone()
            self.send_json(200, {"sample": dict(row) if row else None})
            return
        self.send_json(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        token = self.settings["server"]["api_token"]
        if parsed.path != "/health" and not authorize(self, token):
            return
        try:
            data = self.read_json()
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": "invalid_json", "detail": str(exc)})
            return

        max_skew = int(self.settings.get("location", {}).get("max_skew_seconds", 600))

        if parsed.path == "/api/location":
            required = ("latitude", "longitude", "recorded_at")
            if any(k not in data for k in required):
                self.send_json(400, {"error": "missing_fields", "required": list(required)})
                return
            cur = self.conn.execute(
                """
                INSERT INTO location_samples
                    (latitude, longitude, accuracy_m, altitude_m, speed_mps,
                     recorded_at, source, device_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    float(data["latitude"]),
                    float(data["longitude"]),
                    float(data["accuracy_m"]) if data.get("accuracy_m") is not None else None,
                    float(data["altitude_m"]) if data.get("altitude_m") is not None else None,
                    float(data["speed_mps"]) if data.get("speed_mps") is not None else None,
                    str(data["recorded_at"]),
                    str(data.get("source", "ios")),
                    data.get("device_id"),
                ),
            )
            sample_id = int(cur.lastrowid)
            attached = backfill_message_locations(self.conn, max_skew)
            self.conn.commit()
            self.send_json(
                201,
                {"id": sample_id, "messages_located": attached},
            )
            return

        if parsed.path == "/api/messages":
            required = ("direction", "sent_at")
            if any(k not in data for k in required):
                self.send_json(400, {"error": "missing_fields", "required": list(required)})
                return
            direction = data["direction"]
            if direction not in ("inbound", "outbound"):
                self.send_json(400, {"error": "invalid_direction"})
                return
            contact_id = data.get("contact_id")
            if contact_id is None and (
                data.get("contact_phone") or data.get("contact_imessage_id") or data.get("contact_name")
            ):
                contact_id = upsert_contact(
                    self.conn,
                    name=data.get("contact_name"),
                    phone=data.get("contact_phone"),
                    imessage_id=data.get("contact_imessage_id"),
                )
            try:
                cur = self.conn.execute(
                    """
                    INSERT INTO messages
                        (external_id, contact_id, direction, body, sent_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (
                        data.get("external_id"),
                        contact_id,
                        direction,
                        data.get("body"),
                        str(data["sent_at"]),
                    ),
                )
            except sqlite3.IntegrityError:
                existing = self.conn.execute(
                    "SELECT id FROM messages WHERE external_id = ?",
                    (data.get("external_id"),),
                ).fetchone()
                self.send_json(200, {"id": existing["id"] if existing else None, "deduped": True})
                return
            message_id = int(cur.lastrowid)
            located = attach_location_to_message(self.conn, message_id, max_skew)
            self.conn.commit()
            row = self.conn.execute(
                "SELECT * FROM messages WHERE id = ?", (message_id,)
            ).fetchone()
            self.send_json(201, {"message": dict(row), "located": located})
            return

        if parsed.path == "/api/contacts":
            if not data.get("phone") and not data.get("imessage_id"):
                self.send_json(400, {"error": "phone_or_imessage_id_required"})
                return
            contact_id = upsert_contact(
                self.conn,
                name=data.get("name"),
                phone=data.get("phone"),
                imessage_id=data.get("imessage_id"),
            )
            self.conn.commit()
            row = self.conn.execute(
                "SELECT * FROM contacts WHERE id = ?", (contact_id,)
            ).fetchone()
            self.send_json(201, {"contact": dict(row)})
            return

        if parsed.path == "/api/location/backfill":
            updated = backfill_message_locations(self.conn, max_skew)
            self.send_json(200, {"messages_located": updated})
            return

        self.send_json(404, {"error": "not_found"})


def main() -> None:
    parser = argparse.ArgumentParser(description="My_CRM local Mac server")
    parser.add_argument(
        "--settings",
        type=Path,
        default=DEFAULT_SETTINGS,
        help="Path to settings.json",
    )
    args = parser.parse_args()
    settings = load_settings(args.settings)
    conn = db_connect(settings)

    host = settings["server"].get("host", "127.0.0.1")
    port = int(settings["server"].get("port", 8787))

    CRMHandler.settings = settings
    CRMHandler.conn = conn
    server = ThreadingHTTPServer((host, port), CRMHandler)
    print(f"My_CRM listening on http://{host}:{port}", flush=True)
    print(f"Database: {Path(settings['database']['path']).resolve()}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down", flush=True)
    finally:
        server.server_close()
        conn.close()


if __name__ == "__main__":
    main()
