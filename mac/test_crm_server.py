#!/usr/bin/env python3
"""Smoke tests for location → message join (stdlib only)."""

from __future__ import annotations

import json
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import crm_server


def http_json(method: str, url: str, token: str | None = None, payload: dict | None = None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8")
        return exc.code, json.loads(body) if body else {}


def test_location_attaches_to_message() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        settings_path = tmp_path / "settings.json"
        db_path = tmp_path / "crm.sqlite3"
        settings = {
            "database": {"path": str(db_path)},
            "server": {"host": "127.0.0.1", "port": 18787, "api_token": "test-token"},
            "location": {"max_skew_seconds": 600},
        }
        settings_path.write_text(json.dumps(settings), encoding="utf-8")

        loaded = crm_server.load_settings(settings_path)
        conn = crm_server.db_connect(loaded)
        crm_server.CRMHandler.settings = loaded
        crm_server.CRMHandler.conn = conn
        server = crm_server.ThreadingHTTPServer(("127.0.0.1", 18787), crm_server.CRMHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        time.sleep(0.2)
        base = "http://127.0.0.1:18787"
        token = "test-token"
        try:
            status, health = http_json("GET", f"{base}/health")
            assert status == 200 and health["ok"] is True

            status, msg = http_json(
                "POST",
                f"{base}/api/messages",
                token,
                {
                    "direction": "inbound",
                    "body": "Hello",
                    "sent_at": "2026-10-12T15:00:00.000Z",
                    "contact_name": "Ada",
                    "contact_phone": "+15551212",
                    "external_id": "msg-1",
                },
            )
            assert status == 201
            assert msg["located"] is False
            assert msg["message"]["latitude"] is None

            status, loc = http_json(
                "POST",
                f"{base}/api/location",
                token,
                {
                    "latitude": 37.7749,
                    "longitude": -122.4194,
                    "accuracy_m": 12.0,
                    "recorded_at": "2026-10-12T15:01:00.000Z",
                    "source": "ios",
                },
            )
            assert status == 201
            assert loc["messages_located"] == 1

            status, listing = http_json("GET", f"{base}/api/messages", token)
            assert status == 200
            row = listing["messages"][0]
            assert row["latitude"] == 37.7749
            assert row["longitude"] == -122.4194
            assert row["contact_name"] == "Ada"
        finally:
            server.shutdown()
            server.server_close()
            conn.close()


if __name__ == "__main__":
    test_location_attaches_to_message()
    print("ok")
