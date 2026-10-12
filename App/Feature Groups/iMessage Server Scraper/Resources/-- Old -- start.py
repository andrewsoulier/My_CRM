#!/usr/bin/env python3
import argparse
import hashlib
import os
import shutil
import subprocess
import threading
import sys
import time
import sqlite3
import signal
import atexit
from contextlib import contextmanager
from pathlib import Path

import logging
from logging.handlers import RotatingFileHandler

LOGGER = logging.getLogger("MyCRM")



# --- Utilities --------------------------------------------------------------

def _print(msg: str):
    LOGGER.info(msg)

def _die(msg: str, code: int = 1):
    LOGGER.error(msg)
    sys.exit(code)

@contextmanager
def file_lock(lock_path: Path, wait_secs: int = 20):
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    start = time.time()
    while True:
        try:
            fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            os.close(fd)
            # Write our PID into the lock for stale-lock detection
            try:
                with open(lock_path, "w") as wf:
                    wf.write(str(os.getpid()))
            except Exception:
                pass
            break
        except FileExistsError:
            # Attempt to detect and clear stale lock
            try:
                with open(lock_path, "r") as rf:
                    content = rf.read().strip()
                pid = int(content) if content.isdigit() else None
            except Exception:
                pid = None

            if pid is not None:
                try:
                    # If process exists, this will not raise
                    os.kill(pid, 0)
                    # Another instance is alive; keep waiting
                except ProcessLookupError:
                    # No such process -> stale lock; remove and retry immediately
                    try:
                        os.unlink(lock_path)
                        continue
                    except Exception:
                        pass
                except PermissionError:
                    # Cannot check, fall back to waiting
                    pass
            else:
                # Lock file has no valid PID; consider stale and try to remove
                try:
                    os.unlink(lock_path)
                    continue
                except Exception:
                    pass
            if (time.time() - start) > wait_secs:
                _die(f"Another instance is running (lock: {lock_path}).")
            time.sleep(0.25)
    try:
        yield
    finally:
        try:
            lock_path.unlink(missing_ok=True)
        except Exception:
            pass

def sha256_file(p: Path) -> str:
    if not p.exists():
        return ""
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# --- Bootstrap logic --------------------------------------------------------

def setup_logging(logs_dir: Path) -> Path:
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_path = logs_dir / "crm.log"

    # Ensure the log file exists, is truncated, and writable; also write a pre-handler beacon
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("")  # truncate to start fresh
        try:
            os.chmod(log_path, 0o644)
        except Exception:
            pass
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} BOOT [MyCRM] pre-handler beacon\n")
    except Exception:
        # If we can't pre-create/seed the file, continue and let handlers try
        pass

    fmt = logging.Formatter(
        fmt="%(asctime)s %(levelname)s [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Try the normal rotating file + console handler setup
    try:
        file_handler = RotatingFileHandler(
            str(log_path), maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8"
        )
        file_handler.setLevel(logging.INFO)

        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(logging.INFO)

        file_handler.setFormatter(fmt)
        console_handler.setFormatter(fmt)

        LOGGER.setLevel(logging.INFO)
        LOGGER.handlers.clear()
        LOGGER.propagate = False
        LOGGER.addHandler(file_handler)
        LOGGER.addHandler(console_handler)
    except Exception:
        # Fallback: root basicConfig to file + separate console handler
        try:
            logging.basicConfig(
                level=logging.INFO,
                format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
                datefmt="%Y-%m-%d %H:%M:%S",
                filename=str(log_path),
                filemode="a",
            )
            # In fallback mode, allow propagation so LOGGER writes reach root handlers
            LOGGER.setLevel(logging.INFO)
            LOGGER.handlers.clear()
            LOGGER.propagate = True
            ch = logging.StreamHandler(sys.stdout)
            ch.setLevel(logging.INFO)
            ch.setFormatter(fmt)
            logging.getLogger().addHandler(ch)
        except Exception:
            pass

    LOGGER.info("📝 Logging initialized at %s", log_path)
    for h in LOGGER.handlers:
        try:
            h.flush()
        except Exception:
            pass

    # Quiet down noisy libraries if needed
    logging.getLogger("pip").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)

    return log_path


# --- Notification and Messages DB Preflight ---------------------------------

def safe_notify(title: str, message: str) -> None:
    """Best-effort macOS notification that never raises or blocks."""
    osa = "/usr/bin/osascript"
    # Pre-escape quotes for AppleScript; avoid backslashes in f-string expressions
    safe_title = str(title).replace('"', '\\"')
    safe_message = str(message).replace('"', '\\"')
    script = f'display notification "{safe_message}" with title "{safe_title}"'
    try:
        if os.path.isfile(osa) and os.access(osa, os.X_OK):
            subprocess.run([osa, "-e", script], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception:
        # Never crash on notify failures
        pass


def open_full_disk_access_pane():
    """Attempt to open macOS Full Disk Access preferences pane."""
    try:
        subprocess.run(
            ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"],
            check=False
        )
    except Exception:
        pass

def prompt_for_full_disk_access(venv_python: Path) -> bool:
    """Continuously prompt user to grant Full Disk Access until successful or user cancels."""
    chat_db = os.path.expanduser("~/Library/Messages/chat.db")
    
    # First check if Messages DB exists
    if not os.path.exists(chat_db):
        LOGGER.warning("Messages DB not found at %s; cannot proceed with Full Disk Access setup.", chat_db)
        return False
    
    attempt_count = 0
    max_attempts = 10  # Prevent infinite loops
    
    while attempt_count < max_attempts:
        attempt_count += 1
        
        # Test current access
        try:
            conn = sqlite3.connect(f"file:{chat_db}?mode=ro", uri=True)
            conn.execute("PRAGMA schema_version").fetchone()
            conn.close()
            LOGGER.info("✅ Full Disk Access granted! Messages DB is now accessible.")
            return True
        except sqlite3.DatabaseError as e:
            if "authorization denied" not in str(e).lower():
                LOGGER.error("Unexpected database error: %s", e)
                return False
        
        # Access still denied, prompt user
        if attempt_count == 1:
            # First attempt - show detailed instructions
            message = (
                "My CRM needs Full Disk Access to read your Messages database.\n\n"
                "To grant access:\n"
                "1. Click 'Open Settings' below\n"
                "2. Find 'My_CRM' in the list\n"
                "3. Check the box next to it\n"
                "4. Also check the box for the Python executable\n"
                "5. Return here and click 'Check Access'\n\n"
                "You can also click 'Skip' to continue without iMessage import."
            )
        else:
            # Subsequent attempts - shorter message
            message = (
                f"Full Disk Access still not granted (attempt {attempt_count}/{max_attempts}).\n\n"
                "Please ensure both 'My_CRM' and the Python executable are checked in Full Disk Access settings.\n\n"
                "Click 'Open Settings' to try again, or 'Skip' to continue without iMessage import."
            )
        
        # Try to show dialog, but handle GUI environment issues gracefully
        user_choice = None
        
        # First try to detect if we're in a GUI environment
        gui_available = False
        try:
            # Check if we can access the GUI
            test_script = '''
            tell application "System Events"
                return true
            end tell
            '''
            result = subprocess.run(
                ["/usr/bin/osascript", "-e", test_script],
                capture_output=True,
                text=True,
                timeout=5
            )
            gui_available = result.returncode == 0
        except Exception:
            gui_available = False
        
        if gui_available:
            # Create AppleScript dialog with proper escaping
            safe_message = message.replace('"', '\\"').replace('\\', '\\\\')
            script = f'''
            tell application "System Events"
                set frontmost to true
            end tell
            set theResponse to display dialog "{safe_message}" buttons {{"Open Settings", "Check Access", "Skip"}} default button "Open Settings" with title "My CRM - Full Disk Access Required"
            return button returned of theResponse
            '''
            
            try:
                result = subprocess.run(
                    ["/usr/bin/osascript", "-e", script],
                    capture_output=True,
                    text=True,
                    check=True,
                    timeout=30
                )
                user_choice = result.stdout.strip()
            except subprocess.CalledProcessError as e:
                LOGGER.warning("Dialog failed, falling back to notification: %s", e)
                user_choice = None
            except subprocess.TimeoutExpired:
                LOGGER.warning("Dialog timed out, falling back to notification")
                user_choice = None
            except Exception as e:
                LOGGER.warning("Unexpected dialog error, falling back to notification: %s", e)
                user_choice = None
        
        # If dialog failed or GUI not available, use notification and open settings
        if not user_choice:
            LOGGER.info("GUI dialog not available, using notification and opening settings")
            safe_notify(
                "My CRM - Full Disk Access Required",
                "Please grant Full Disk Access to My_CRM and the Python executable in System Preferences > Security & Privacy > Privacy > Full Disk Access"
            )
            open_full_disk_access_pane()
            user_choice = "Open Settings"
        
        # Handle user choice
        if user_choice == "Open Settings":
            open_full_disk_access_pane()
            LOGGER.info("Opened Full Disk Access settings pane")
            
            # Wait a moment for settings to open
            time.sleep(2)
            
            # Show a reminder notification
            safe_notify(
                "My CRM - Settings Opened",
                "Please find 'My_CRM' in the Full Disk Access list and check the box next to it, then also check the Python executable."
            )
            
            continue
        elif user_choice == "Check Access":
            LOGGER.info("User clicked 'Check Access' - testing permissions...")
            continue  # Will test access in next loop iteration
        elif user_choice == "Skip":
            LOGGER.info("User chose to skip Full Disk Access setup")
            return False
        else:
            LOGGER.warning("Unexpected user choice: %s", user_choice)
            return False
    
    LOGGER.warning("Maximum attempts reached for Full Disk Access setup")
    return False

def preflight_messages_access(venv_python: Path) -> bool:
    """Check access to the user's Messages chat.db. If blocked by TCC/FDA, log
    clear remediation steps, notify the user, and return False. Returns True when
    we can open the DB for read-only queries. If the DB is missing entirely, we log
    a warning and return False (so the iMessage import step can be skipped)."""
    chat_db = os.path.expanduser("~/Library/Messages/chat.db")
    if not os.path.exists(chat_db):
        LOGGER.warning("Messages DB not found at %s; skipping iMessage import.", chat_db)
        return False
    
    # Check if we're running in a non-interactive environment (like a cron job)
    is_interactive = (
        os.isatty(sys.stdin.fileno()) and 
        os.environ.get('TERM') is not None and
        not os.environ.get('CRON_JOB', '').lower() in ('true', '1', 'yes')
    )
    
    try:
        # Open read-only via URI to avoid creating files; a lightweight PRAGMA query suffices
        conn = sqlite3.connect(f"file:{chat_db}?mode=ro", uri=True)
        conn.execute("PRAGMA schema_version").fetchone()
        conn.close()
        LOGGER.info("✅ Messages DB is accessible: %s", chat_db)
        return True
    except sqlite3.DatabaseError as e:
        msg = str(e).lower()
        if "authorization denied" in msg:
            if is_interactive:
                LOGGER.warning("Messages DB access blocked - prompting user for Full Disk Access setup")
                # Use interactive prompt to guide user through Full Disk Access setup
                return prompt_for_full_disk_access(venv_python)
            else:
                LOGGER.warning("Messages DB access blocked - skipping interactive prompt in non-interactive environment")
                LOGGER.info("To enable iMessage import, manually grant Full Disk Access to My_CRM and the Python executable")
                return False
        LOGGER.error("Failed to open Messages DB at %s: %s", chat_db, e)
        return False
    except Exception as e:
        LOGGER.error("Unexpected error opening Messages DB: %s", e)
        return False

def ensure_venv(system_python: str, venv_dir: Path):
    """Create a venv if missing (idempotent)."""
    if not (venv_dir / "bin" / "python3").exists():
        _print("🐍 Creating virtual environment…")
        py = shutil.which(system_python) or shutil.which("python3") or sys.executable
        subprocess.check_call([py, "-m", "venv", str(venv_dir)])


def pip_install_if_needed(venv_python: Path, requirements: Path, markers_dir: Path):
    markers_dir.mkdir(parents=True, exist_ok=True)
    req_hash = sha256_file(requirements)
    marker_file = markers_dir / "requirements.sha256"
    prior_hash = marker_file.read_text().strip() if marker_file.exists() else ""

    # Always ensure pip tooling is up-to-date
    subprocess.check_call([str(venv_python), "-m", "pip", "install", "--upgrade", "pip", "setuptools", "wheel"])  # noqa: E501

    if not requirements.exists():
        _print("ℹ️  No requirements.txt found—skipping dependency install.")
        marker_file.write_text("(none)")
        return

    if req_hash == prior_hash:
        _print("✅ Dependencies up-to-date.")
        return

    _print("📦 Installing/refreshing dependencies…")
    subprocess.check_call([str(venv_python), "-m", "pip", "install", "-r", str(requirements)])
    marker_file.write_text(req_hash)


def reexec_inside_venv(venv_python: Path):
    exe = Path(sys.executable).resolve()
    if exe != venv_python.resolve():
        os.execv(str(venv_python), [str(venv_python)] + sys.argv)


def first_run_init(db_path: Path):
    """Create first-run DB if missing (idempotent)."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if not db_path.exists():
        db_path.touch()
        _print(f"📦 Created new database at {db_path}")


def resolve_db_path(resources_dir: Path, state_dir: Path) -> Path:
    """
    Resolve the CRM DB path in this order:
      1) App Support/User_Settings.json -> database.path (expanded)
      2) Resources/User_Settings.json -> database.path (expanded) (fallback)
      3) Fallback to App Support: <state_dir>/my_crm.db
    """
    # First try Application Support
    app_support_prefs = state_dir / "User_Settings.json"
    if app_support_prefs.exists():
        try:
            import json
            data = json.loads(app_support_prefs.read_text(encoding="utf-8"))
            db_path = (data.get("database") or {}).get("path")
            if db_path:
                p = Path(os.path.expanduser(db_path)).resolve()
                return p
        except Exception as e:
            LOGGER.warning("Could not read App Support User_Settings.json for DB path: %s", e)
    
    # Fallback to Resources directory
    resources_prefs = resources_dir / "User_Settings.json"
    if resources_prefs.exists():
        try:
            import json
            data = json.loads(resources_prefs.read_text(encoding="utf-8"))
            db_path = (data.get("database") or {}).get("path")
            if db_path:
                p = Path(os.path.expanduser(db_path)).resolve()
                return p
        except Exception as e:
            LOGGER.warning("Could not read Resources User_Settings.json for DB path: %s", e)
    
    return state_dir / "my_crm.db"

# --- File Monitoring ---------------------------------------------------------

class ChatDBMonitor:
    """Monitors chat.db for changes and triggers re-import when changes are detected."""
    
    def __init__(self, venv_python: Path, resources_dir: Path, state_dir: Path, db_path: Path, check_interval: int = 180):
        self.venv_python = venv_python
        self.resources_dir = resources_dir
        self.state_dir = state_dir
        self.db_path = db_path
        self.check_interval = check_interval  # 3 minutes = 180 seconds
        self.chat_db_path = os.path.expanduser("~/Library/Messages/chat.db")
        self.monitor_thread = None
        self.stop_event = threading.Event()
        self.last_modified = None
        self.last_size = None
        self.monitor_pid_file = state_dir / ".monitor.pid"
        
    def get_file_info(self):
        """Get current file modification time and size."""
        try:
            if os.path.exists(self.chat_db_path):
                stat = os.stat(self.chat_db_path)
                return stat.st_mtime, stat.st_size
            return None, None
        except Exception as e:
            LOGGER.warning("Could not get file info for %s: %s", self.chat_db_path, e)
            return None, None
    
    def has_changes(self):
        """Check if chat.db has changed since last check."""
        current_mtime, current_size = self.get_file_info()
        
        if current_mtime is None or current_size is None:
            return False
            
        if self.last_modified is None or self.last_size is None:
            # First check, just record current values
            self.last_modified = current_mtime
            self.last_size = current_size
            return False
            
        # Check for changes
        if current_mtime != self.last_modified or current_size != self.last_size:
            LOGGER.info("📱 Chat.db change detected: mtime=%s->%s, size=%s->%s", 
                       self.last_modified, current_mtime, self.last_size, current_size)
            self.last_modified = current_mtime
            self.last_size = current_size
            return True
            
        return False
    
    def run_import_scripts(self):
        """Run only the import_imessages.py script to update the database."""
        try:
            LOGGER.info("🔄 Running incremental import due to chat.db changes...")
            
            # Run only import_imessages.py for incremental updates
            cmd = [
                str(self.venv_python),
                "-u",            # unbuffered stdout/stderr
                "-X", "dev",     # developer mode
                str(self.resources_dir / "import_imessages.py"),
            ]
            
            # Environment variables
            env = os.environ.copy()
            env["PYTHONFAULTHANDLER"] = "1"
            env["MYCRM_STATE_DIR"] = str(self.state_dir)
            env["MYCRM_DB"] = str(self.db_path)
            env["MYCRM_LOG_DIR"] = str(self.state_dir / "Logs")
            
            LOGGER.info("▶️ Running incremental import_imessages.py")
            
            proc = subprocess.Popen(
                cmd,
                cwd=str(self.resources_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
            )
            
            # Capture output
            stdout, stderr = proc.communicate()
            
            if proc.returncode == 0:
                LOGGER.info("✅ Incremental import completed successfully")
                if stdout.strip():
                    LOGGER.info("[import_imessages.py][stdout] %s", stdout.strip())
                if stderr.strip():
                    LOGGER.warning("[import_imessages.py][stderr] %s", stderr.strip())
            else:
                LOGGER.error("❌ Incremental import failed with code %s", proc.returncode)
                if stdout.strip():
                    LOGGER.info("[import_imessages.py][stdout] %s", stdout.strip())
                if stderr.strip():
                    LOGGER.error("[import_imessages.py][stderr] %s", stderr.strip())
                    
        except Exception as e:
            LOGGER.error("❌ Failed to run incremental import: %s", e)
    
    def monitor_loop(self):
        """Main monitoring loop that checks for changes every check_interval seconds."""
        LOGGER.info("👁️ Starting chat.db monitor (checking every %d seconds)", self.check_interval)
        
        # Initialize file info
        self.last_modified, self.last_size = self.get_file_info()
        if self.last_modified is not None:
            LOGGER.info("📱 Initial chat.db state: mtime=%s, size=%s", self.last_modified, self.last_size)
        
        while not self.stop_event.is_set():
            try:
                # Check for changes
                if self.has_changes():
                    self.run_import_scripts()
                
                # Wait for next check or stop signal
                if self.stop_event.wait(self.check_interval):
                    break
                    
            except Exception as e:
                LOGGER.error("❌ Error in monitor loop: %s", e)
                # Wait a bit before retrying
                if self.stop_event.wait(30):
                    break
        
        LOGGER.info("👁️ Chat.db monitor stopped")
    
    def start(self):
        """Start the monitoring thread."""
        if self.monitor_thread is not None and self.monitor_thread.is_alive():
            LOGGER.warning("Monitor thread already running")
            return
            
        # Write PID file
        try:
            self.monitor_pid_file.write_text(str(os.getpid()))
        except Exception as e:
            LOGGER.warning("Could not write monitor PID file: %s", e)
        
        self.stop_event.clear()
        self.monitor_thread = threading.Thread(target=self.monitor_loop, daemon=True)
        self.monitor_thread.start()
        LOGGER.info("👁️ Chat.db monitor started in background thread")
    
    def stop(self):
        """Stop the monitoring thread."""
        LOGGER.info("🛑 Stopping chat.db monitor...")
        self.stop_event.set()
        
        if self.monitor_thread and self.monitor_thread.is_alive():
            self.monitor_thread.join(timeout=10)
            if self.monitor_thread.is_alive():
                LOGGER.warning("Monitor thread did not stop gracefully")
        
        # Clean up PID file
        try:
            if self.monitor_pid_file.exists():
                self.monitor_pid_file.unlink()
        except Exception as e:
            LOGGER.warning("Could not remove monitor PID file: %s", e)
        
        LOGGER.info("🛑 Chat.db monitor stopped")

# Global monitor instance
_monitor = None

def setup_signal_handlers(monitor):
    """Setup signal handlers to gracefully stop the monitor."""
    def signal_handler(signum, frame):
        LOGGER.info("📡 Received signal %d, stopping monitor...", signum)
        if monitor:
            monitor.stop()
        sys.exit(0)
    
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Register cleanup on exit
    def cleanup():
        if monitor:
            monitor.stop()
    
    atexit.register(cleanup)


def run_ordered_scripts(venv_python: Path, resources_dir: Path, scripts: list[str], state_dir: Path, db_path: Path) -> int:
    def _stream(prefix: str, pipe, level=logging.INFO):
        try:
            for line in iter(pipe.readline, ''):
                if not line:
                    break
                LOGGER.log(level, "%s%s", prefix, line.rstrip())
        finally:
            try:
                pipe.close()
            except Exception:
                pass

    failures = 0
    for name in scripts:
        script_path = resources_dir / name
        if not script_path.exists():
            LOGGER.warning("⚠️  Skipping missing script: %s", script_path)
            failures += 1
            continue

        # Build command: run most scripts in dev mode, but run import_contacts.py without debug allocator
        if name == "import_contacts.py":
            cmd = [
                str(venv_python),
                "-u",            # unbuffered stdout/stderr
                str(script_path)
            ]
        else:
            cmd = [
                str(venv_python),
                "-u",            # unbuffered stdout/stderr
                "-X", "dev",     # developer mode (extra warnings, may enable debug allocators)
                str(script_path),
            ]

        # Environment we pass down to each script
        env = os.environ.copy()
        # Avoid debug allocators for import_contacts.py to prevent _PyMem_DebugRawFree crashes from C-extensions
        if name == "import_contacts.py":
            env.pop("PYTHONMALLOC", None)
            env.pop("PYTHONDEVMODE", None)
        env["PYTHONFAULTHANDLER"] = "1"
        env["MYCRM_STATE_DIR"] = str(state_dir)
        env["MYCRM_DB"] = str(db_path)
        env["MYCRM_LOG_DIR"] = str(state_dir / "Logs")

        # Log exactly what we're about to run
        LOGGER.info(
            "▶️  Running %s (cmd=%s, MYCRM_DB=%s)",
            name, " ".join(cmd), env["MYCRM_DB"]
        )

        try:
            proc = subprocess.Popen(
                cmd,
                cwd=str(resources_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
            )
        except Exception as e:
            LOGGER.error("❌ Failed to start %s: %s", name, e)
            failures += 1
            continue

        t_out = threading.Thread(target=_stream, args=(f"[%s][stdout] " % name, proc.stdout, logging.INFO), daemon=True)
        t_err = threading.Thread(target=_stream, args=(f"[%s][stderr] " % name, proc.stderr, logging.WARNING), daemon=True)
        t_out.start(); t_err.start()
        rc = proc.wait()
        t_out.join(); t_err.join()

        if rc != 0:
            LOGGER.info("❌ %s exited with code %s", name, rc)
            failures += 1
        else:
            LOGGER.info("✅ Finished %s", name)
    return failures

# --- CLI / Main -------------------------------------------------------------

def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app-support", type=Path, default=Path.home() / "Library/Application Support/My_CRM")
    ap.add_argument("--logs", type=Path, default=None)
    ap.add_argument("--python", default="/usr/bin/python3", help="System Python used to create venv if needed")
    ap.add_argument("--venv-name", default=".venv")
    ap.add_argument("--requirements", type=Path, default=None)
    return ap.parse_args()


def main():
    args = parse_args()

    # Locations
    RESOURCES_DIR = Path(__file__).resolve().parent
    STATE_DIR = args.app_support
    LOGS_DIR = args.logs or (STATE_DIR / "Logs")
    VENV_DIR = STATE_DIR / args.venv_name
    VENV_PY = VENV_DIR / "bin" / "python3"

    REQUIREMENTS = args.requirements or (RESOURCES_DIR / "requirements.txt")
    MARKERS_DIR = STATE_DIR / ".markers"
    LOCK_FILE = STATE_DIR / ".run.lock"

    # Ensure dirs exist
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    setup_logging(LOGS_DIR)
        # Log interpreter paths to help with Full Disk Access permissions
    try:
        real_exe = Path(sys.executable).resolve()
        LOGGER.info("Python interpreter: sys.executable=%s  realpath=%s", sys.executable, real_exe)
    except Exception as e:
        LOGGER.warning("Could not resolve sys.executable realpath: %s", e)

    # Ensure we are running under the venv before taking the lock to avoid re-exec while locked
    if Path(sys.executable).resolve() != VENV_PY.resolve():
        ensure_venv(args.python, VENV_DIR)
        os.execv(str(VENV_PY), [str(VENV_PY)] + sys.argv)

    # Use shorter wait time for cron jobs to prevent blocking
    wait_time = 5 if os.environ.get('CRON_JOB') else 20
    with file_lock(LOCK_FILE, wait_secs=wait_time):
        LOGGER.info("🚀 My_CRM start sequence")
        # 2) install/refresh deps if needed
        ensure_venv(args.python, VENV_DIR)
        pip_install_if_needed(VENV_PY, REQUIREMENTS, MARKERS_DIR)

        # 4) resolve DB path (User_Settings.json overrides) and ensure it exists
        DB_PATH = resolve_db_path(RESOURCES_DIR, STATE_DIR)
        LOGGER.info("Using CRM DB: %s", DB_PATH)
        first_run_init(DB_PATH)

        # 5) Determine which tasks to run in a defined order
        messages_ok = preflight_messages_access(VENV_PY)

        ordered_scripts = [
            "vcf_check.py",
        ]
        if messages_ok:
            ordered_scripts.append("import_imessages.py")
        else:
            LOGGER.warning("📪 Skipping import_imessages.py because Messages chat.db is not accessible. (Grant Full Disk Access and relaunch to enable.)")

        ordered_scripts += [
            "import_contacts.py",
            "evaluate_date_of_first_contact.py",
            "update_chatGPT.py",
        ]

        failures = run_ordered_scripts(VENV_PY, RESOURCES_DIR, ordered_scripts, STATE_DIR, DB_PATH)

        if failures == 0:
            _print("🎉 All imports completed.")
        else:
            _print(f"⚠️ Completed with {failures} failure(s).")

        # Start chat.db monitor if Messages access is available
        global _monitor
        if messages_ok:
            try:
                _monitor = ChatDBMonitor(VENV_PY, RESOURCES_DIR, STATE_DIR, DB_PATH)
                setup_signal_handlers(_monitor)
                _monitor.start()
                _print("👁️ Chat.db monitor started (checking every 3 minutes)")
                
                # Keep the main process alive to allow the monitor to run
                try:
                    while True:
                        time.sleep(1)
                except KeyboardInterrupt:
                    LOGGER.info("📡 Received interrupt signal")
                finally:
                    if _monitor:
                        _monitor.stop()
                        
            except Exception as e:
                LOGGER.error("❌ Failed to start chat.db monitor: %s", e)
                _print("⚠️ Chat.db monitor failed to start")
        else:
            _print("📪 Chat.db monitor not started (Messages access not available)")

if __name__ == "__main__":
    main()
