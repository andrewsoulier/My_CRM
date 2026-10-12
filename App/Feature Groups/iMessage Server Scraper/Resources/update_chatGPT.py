import json
import shutil
import os
from datetime import datetime

#
# Load path from User_Settings.json - try Application Support first, then fall back to Resources
script_dir = os.path.dirname(os.path.abspath(__file__))
APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/My_CRM")
APP_SUPPORT_PREFS = os.path.join(APP_SUPPORT_DIR, "User_Settings.json")
RESOURCES_PREFS = os.path.join(script_dir, "User_Settings.json")

if os.path.exists(APP_SUPPORT_PREFS):
    pref_path = APP_SUPPORT_PREFS
elif os.path.exists(RESOURCES_PREFS):
    pref_path = RESOURCES_PREFS
else:
    raise FileNotFoundError("User_Settings.json file not found in Application Support or Resources directory")

with open(pref_path, "r", encoding="utf-8") as f:
    prefs = json.load(f)

db_path = os.path.expanduser(prefs["database"]["path"])
# (Optional future-proofing)
user_name = prefs["user"].get("name", "")
user_phone = prefs["user"].get("phone", "")
user_email = prefs["user"].get("email", "")

timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
downloads_dir = os.path.join(os.path.expanduser("~"), "Downloads")
export_path = os.path.join(downloads_dir, f"chatGPT_upload_ready_{timestamp}.db")

# Delete older chatGPT_upload_ready files
if False:  # Disabled for now
    try:
        for fname in os.listdir(downloads_dir):
            if fname.startswith("chatGPT_upload_ready") and fname != os.path.basename(export_path):
                try:
                    os.remove(os.path.join(downloads_dir, fname))
                    print(f"🗑️ Deleted old file: {fname}")
                except Exception as e:
                    print(f"⚠️ Could not delete {fname}: {e}")
    except PermissionError:
        print("⚠️ Cannot access Downloads directory - skipping cleanup of old files")
    except Exception as e:
        print(f"⚠️ Error accessing Downloads directory: {e}")

# Copy the database file
    if os.path.exists(db_path):
        try:
            shutil.copy(db_path, export_path)
            print(f"✅ Database copied and renamed to: {export_path}")
            print("📤 Please upload this file to ChatGPT to update the Personal CRM project.")
        except PermissionError:
            print("⚠️ Cannot write to Downloads directory - database export skipped")
        except Exception as e:
            print(f"❌ Error copying database: {e}")
    else:
        print("❌ Could not find my_crm.db in the current directory.")