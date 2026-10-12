#!/bin/bash
set -euo pipefail

# Minimal launcher; handle env quirks when launched from Finder.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

# Updated path resolution for the new environment structure
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SUPPORT_DIR="$HOME/Library/Application Support/My_CRM"
mkdir -p "$APP_SUPPORT_DIR"

# Logging for launcher itself
LAUNCH_LOG="$APP_SUPPORT_DIR/Logs/launcher.log"
mkdir -p "$(dirname "$LAUNCH_LOG")"
: >"$LAUNCH_LOG"
log(){ printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LAUNCH_LOG"; }

if [[ -f "$LAUNCH_LOG" ]]; then
  _exists="yes"
else
  _exists="no"
fi
_perms="$(stat -f %Sp "$LAUNCH_LOG" 2>/dev/null || echo '?')"
log "LAUNCH_LOG at $LAUNCH_LOG (exists=${_exists}, perms=${_perms})"

# Environment banner to help debug Finder vs Terminal launches
log "=== My_CRM Launch_Server.sh ==="
log "whoami=$(whoami)"
log "pwd=$(pwd)"
log "PATH=$PATH"
log "SCRIPT_DIR=$SCRIPT_DIR"
log "APP_BUNDLE_DIR=$APP_BUNDLE_DIR"
log "APP_SUPPORT_DIR=$APP_SUPPORT_DIR"

# Detect App Translocation (Gatekeeper) which can break bundle-relative paths
case "$APP_BUNDLE_DIR" in
  *"/AppTranslocation/"*|*"/AppTranslocation-"*)
    log "⚠️ Detected App Translocation. Move app to /Applications and remove quarantine: xattr -dr com.apple.quarantine /Applications/My_CRM.app"
    ;;
esac

# User notification function with logging
notify() {
  /usr/bin/osascript -e 'display notification "Starting My CRM…" with title "My CRM"' >>"$LAUNCH_LOG" 2>&1 && return 0
  /usr/bin/osascript -e 'display dialog "Starting My CRM…" buttons ["Okay"] default button "Okay" with title "My CRM" giving up after 5' >>"$LAUNCH_LOG" 2>&1 && return 0
  log "osascript failed; likely no GUI session or permissions."
  return 1
}
notify || true

# Choose bootstrap script (handle Start.py vs start.py case differences)
PY_BOOTSTRAP="$APP_BUNDLE_DIR/Resources/start.py"
if [ ! -f "$PY_BOOTSTRAP" ] && [ -f "$APP_BUNDLE_DIR/Resources/Start.py" ]; then
  PY_BOOTSTRAP="$APP_BUNDLE_DIR/Resources/Start.py"
fi

log "Checking for bootstrap script at: $PY_BOOTSTRAP"
if [ ! -f "$PY_BOOTSTRAP" ]; then
  log "❌ Could not find bootstrap at $APP_BUNDLE_DIR/Resources/{start.py,Start.py}"
  log "Available files in Resources:"
  ls -la "$APP_BUNDLE_DIR/Resources/" >>"$LAUNCH_LOG" 2>&1 || log "Could not list Resources directory"
  exit 1
fi
log "✅ Found bootstrap script: $PY_BOOTSTRAP"

# Resolve and log actual Python binaries (helps Full Disk Access debugging)
resolve_realpath() {
  /usr/bin/python3 - "$1" <<'PY'
import os, sys
p = sys.argv[1]
try:
    print(os.path.realpath(p))
except Exception:
    print(p)
PY
}

SYS_PY="/usr/bin/python3"
REAL_SYS_PY="$(resolve_realpath "$SYS_PY" 2>/dev/null || echo "$SYS_PY")"
VENV_PY="$APP_SUPPORT_DIR/.venv/bin/python3"
if [ -x "$VENV_PY" ]; then
  REAL_VENV_PY="$(resolve_realpath "$VENV_PY" 2>/dev/null || echo "$VENV_PY")"
  log "Detected venv python: $VENV_PY -> $REAL_VENV_PY"
else
  log "No venv python at $VENV_PY"
fi
log "System python: $SYS_PY -> $REAL_SYS_PY"
# Simplified python detection
if command -v python3 >/dev/null 2>&1; then
  log "python3 found in PATH"
else
  log "python3 not found in PATH=$PATH"
fi

log "=== Launch_Server.sh: STARTING Python script at $(date '+%Y-%m-%d %H:%M:%S') ==="
log "Command: /usr/bin/python3 \"$PY_BOOTSTRAP\" --app-support \"$APP_SUPPORT_DIR\" --logs \"$APP_SUPPORT_DIR/Logs\""

# Execute Python script with proper output redirection
/usr/bin/python3 "$PY_BOOTSTRAP" \
  --app-support "$APP_SUPPORT_DIR" \
  --logs "$APP_SUPPORT_DIR/Logs" 2>&1 | tee -a "$LAUNCH_LOG"

PYTHON_EXIT_CODE=${PIPESTATUS[0]}
log "=== Launch_Server.sh: FINISHED Python script at $(date '+%Y-%m-%d %H:%M:%S') with exit code $PYTHON_EXIT_CODE ==="

exit $PYTHON_EXIT_CODE