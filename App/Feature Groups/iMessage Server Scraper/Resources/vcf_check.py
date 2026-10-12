import glob
import tkinter as tk
print(tk.__file__)
from tkinter import filedialog, messagebox
import os
import json

def load_user_preferences(pref_path):
    if not os.path.exists(pref_path):
        return {}
    with open(pref_path, "r", encoding="utf-8") as f:
        return json.load(f)

def save_user_preferences(pref_path, data):
    with open(pref_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

def user_info_missing(user):
    return not user.get("name") or not user.get("phone") or not user.get("email")

def check_and_validate_vcf():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Try Application Support first, then fall back to Resources directory
    APP_SUPPORT_DIR = os.path.expanduser("~/Library/Application Support/My_CRM")
    APP_SUPPORT_PREFS = os.path.join(APP_SUPPORT_DIR, "User_Settings.json")
    RESOURCES_PREFS = os.path.join(script_dir, "User_Settings.json")
    
    if os.path.exists(APP_SUPPORT_PREFS):
        pref_path = APP_SUPPORT_PREFS
    elif os.path.exists(RESOURCES_PREFS):
        pref_path = RESOURCES_PREFS
    else:
        # Create in Application Support if it doesn't exist
        pref_path = APP_SUPPORT_PREFS
        os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
    
    prefs = load_user_preferences(pref_path)

    if not prefs.get("user") or user_info_missing(prefs["user"]):
        print("👤 Missing user info in preferences. Prompting for VCF selection...")

        root = tk.Tk()
        root.withdraw()
        file_path = filedialog.askopenfilename(
            title="Select a valid .vcf file to import user information",
            filetypes=[("vCard files", "*.vcf")],
            initialdir=os.path.expanduser("~")
        )
        if not file_path:
            print("❌ No file selected. Aborting.")
        else:
            while True:
                with open(file_path, "r", encoding="utf-8") as vcf:
                    content = vcf.read()
                    has_name = "FN:" in content
                    has_phone = "TEL" in content
                    has_email = "EMAIL" in content

                if has_name and has_phone and has_email:
                    print("✅ Valid VCF file selected.")

                    name_line = next((line for line in content.splitlines() if line.startswith("FN:")), "")
                    email_line = next((line for line in content.splitlines() if "EMAIL" in line), "")
                    phone_line = next((line for line in content.splitlines() if "TEL" in line), "")

                    name = name_line.replace("FN:", "").strip()
                    email = email_line.split(":")[-1].strip()
                    phone = phone_line.split(":")[-1].strip()

                    prefs["user"] = {
                        "name": name,
                        "phone": phone,
                        "email": email,
                        "nickname": name.split()[0] if name else ""
                    }
                    save_user_preferences(pref_path, prefs)
                    print("💾 User preferences updated from VCF.")
                    break
                else:
                    messagebox.showerror("Invalid VCF File", "The selected file is missing a name, phone number, or email.\nPlease select a valid .vcf file.")
                    file_path = filedialog.askopenfilename(
                        title="Select a valid .vcf file to import user information",
                        filetypes=[("vCard files", "*.vcf")],
                        initialdir=os.path.expanduser("~")
                    )
                    if not file_path:
                        print("❌ No file selected. Aborting.")
                        break

    db_path = prefs.get("database", {}).get("path")
    if not db_path or not os.path.isfile(os.path.expanduser(db_path)):
        print("📂 Invalid or missing database path. Prompting for a new location...")
        root = tk.Tk()
        root.withdraw()
        file_path = filedialog.asksaveasfilename(
            title="Select location to create or use my_crm.db",
            defaultextension=".db",
            initialfile="my_crm",
            filetypes=[("SQLite Database", "*.db")],
            initialdir=os.path.expanduser("~/Documents")
        )
        if not file_path:
            print("❌ No path selected. Aborting.")
        else:
            prefs["database"] = {
                "path": os.path.abspath(file_path),
                "name": os.path.basename(file_path)
            }
            save_user_preferences(pref_path, prefs)
            print("💾 User preferences updated with new database path.")
    else:
        print("✅ User preferences already populated. No action needed.")

if __name__ == "__main__":
    check_and_validate_vcf()
