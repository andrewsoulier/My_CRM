#!/usr/bin/env bash
# One-shot My_CRM setup for macOS (server + XcodeGen project).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Repo: $ROOT"
git fetch origin cursor/swift-crm-location-2e78 2>/dev/null || true
git checkout cursor/swift-crm-location-2e78 2>/dev/null || true

if [[ ! -f settings.json ]]; then
  cp settings.example.json settings.json
  TOKEN="$(openssl rand -hex 24)"
  python3 - <<PY
import json
from pathlib import Path
p = Path("settings.json")
data = json.loads(p.read_text())
data["server"]["api_token"] = "$TOKEN"
p.write_text(json.dumps(data, indent=2) + "\n")
print("Wrote settings.json with new api_token")
PY
else
  echo "settings.json already exists (leaving token unchanged)"
fi

echo "==> Smoke test"
python3 mac/test_crm_server.py

if ! curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1; then
  echo "==> Starting CRM server on :8787"
  nohup python3 mac/crm_server.py --settings settings.json > /tmp/mycrm-server.log 2>&1 &
  echo $! > /tmp/mycrm-server.pid
  sleep 0.5
fi

echo "==> Health"
curl -sS http://127.0.0.1:8787/health
echo

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> Installing xcodegen via Homebrew"
    brew install xcodegen
  else
    echo "ERROR: install Homebrew, then: brew install xcodegen" >&2
    exit 1
  fi
fi

echo "==> Generating Xcode project"
(
  cd ios
  xcodegen generate
  ls -la MyCRM.xcodeproj
)

TOKEN_VALUE="$(python3 -c 'import json; print(json.load(open("settings.json"))["server"]["api_token"])')"
TS_IP="$(tailscale ip -4 2>/dev/null || true)"

echo
echo "======== Setup complete ========"
echo "API token (paste into iOS app): $TOKEN_VALUE"
echo "Local health: http://127.0.0.1:8787/health"
if [[ -n "$TS_IP" ]]; then
  echo "Tailscale base URL for iPhone: http://${TS_IP}:8787"
else
  echo "Tailscale IP unavailable — run: tailscale ip -4"
fi
echo
echo "Next:"
echo "  open ios/MyCRM.xcodeproj"
echo "  Set Team + App Group group.com.mycrm.shared on all targets"
echo "  Run MyCRM on a physical iPhone"
echo "  In app: base URL + token above; Always location; Start reporting"
echo "==============================="
