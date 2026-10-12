#!/usr/bin/env python3
"""
ChatGPT Connection Script for My CRM
This script handles ChatGPT API key management and authentication
"""

import os
import sys
import json
import getpass
import keyring
import requests
from pathlib import Path
from typing import Optional, Dict, Any

class ChatGPTConnector:
    def __init__(self):
        self.service_name = "My_CRM_ChatGPT"
        self.api_key_key = "openai_api_key"
        self.organization_key = "openai_organization"
        self.user_preferences_file = self._get_user_preferences_path()
        
    def _get_user_preferences_path(self) -> Path:
        """Get the path to user preferences file"""
        # Try multiple possible locations
        possible_paths = [
            Path.home() / "Library" / "Application Support" / "My_CRM" / "User_Settings.json",
            Path.home() / "My_CRM Project" / "User_Settings.json",
            Path.cwd() / "User_Settings.json"
        ]
        
        for path in possible_paths:
            if path.exists():
                return path
                
        # If none exist, create the first one
        default_path = possible_paths[0]
        default_path.parent.mkdir(parents=True, exist_ok=True)
        return default_path
    
    def _load_user_preferences(self) -> Dict[str, Any]:
        """Load user preferences from file"""
        try:
            if self.user_preferences_file.exists():
                with open(self.user_preferences_file, 'r') as f:
                    return json.load(f)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Could not load user preferences: {e}")
        
        return {}
    
    def _save_user_preferences(self, preferences: Dict[str, Any]) -> bool:
        """Save user preferences to file"""
        try:
            with open(self.user_preferences_file, 'w') as f:
                json.dump(preferences, f, indent=2)
            return True
        except IOError as e:
            print(f"Error: Could not save user preferences: {e}")
            return False
    
    def _get_api_key_from_keyring(self) -> Optional[str]:
        """Get API key from macOS keychain"""
        try:
            return keyring.get_password(self.service_name, self.api_key_key)
        except Exception as e:
            print(f"Warning: Could not access keychain: {e}")
            return None
    
    def _save_api_key_to_keyring(self, api_key: str) -> bool:
        """Save API key to macOS keychain"""
        try:
            keyring.set_password(self.service_name, self.api_key_key, api_key)
            return True
        except Exception as e:
            print(f"Error: Could not save to keychain: {e}")
            return False
    
    def _get_organization_from_keyring(self) -> Optional[str]:
        """Get organization ID from macOS keychain"""
        try:
            return keyring.get_password(self.service_name, self.organization_key)
        except Exception as e:
            print(f"Warning: Could not access keychain: {e}")
            return None
    
    def _save_organization_to_keyring(self, organization_id: str) -> bool:
        """Save organization ID to macOS keychain"""
        try:
            keyring.set_password(self.service_name, self.organization_key, organization_id)
            return True
        except Exception as e:
            print(f"Error: Could not save to keychain: {e}")
            return False
    
    def test_api_connection(self, api_key: str, organization_id: Optional[str] = None) -> Dict[str, Any]:
        """Test the API connection with the provided credentials"""
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        
        if organization_id:
            headers["OpenAI-Organization"] = organization_id
        
        # Test with a simple models list request
        try:
            response = requests.get(
                "https://api.openai.com/v1/models",
                headers=headers,
                timeout=10
            )
            
            if response.status_code == 200:
                models = response.json()
                return {
                    "success": True,
                    "message": "API connection successful",
                    "models_count": len(models.get("data", [])),
                    "organization": organization_id
                }
            else:
                return {
                    "success": False,
                    "message": f"API request failed: {response.status_code} - {response.text}",
                    "error_code": response.status_code
                }
        except requests.exceptions.RequestException as e:
            return {
                "success": False,
                "message": f"Network error: {str(e)}",
                "error_type": "network"
            }
    
    def get_current_status(self) -> Dict[str, Any]:
        """Get current ChatGPT connection status"""
        api_key = self._get_api_key_from_keyring()
        organization_id = self._get_organization_from_keyring()
        
        if not api_key:
            return {
                "connected": False,
                "message": "No API key found",
                "has_api_key": False,
                "has_organization": False
            }
        
        # Test the connection
        test_result = self.test_api_connection(api_key, organization_id)
        
        return {
            "connected": test_result["success"],
            "message": test_result["message"],
            "has_api_key": True,
            "has_organization": organization_id is not None,
            "organization": organization_id,
            "test_result": test_result
        }
    
    def connect(self) -> Dict[str, Any]:
        """Interactive connection process"""
        print("🤖 ChatGPT Connection Setup for My CRM", file=sys.stderr)
        print("=" * 50, file=sys.stderr)
        
        # Check if already connected
        current_status = self.get_current_status()
        if current_status["connected"]:
            print("✅ Already connected to ChatGPT!", file=sys.stderr)
            print(f"Organization: {current_status.get('organization', 'None')}", file=sys.stderr)
            return current_status
        
        print("\nTo connect to ChatGPT, you'll need:", file=sys.stderr)
        print("1. An OpenAI API key (get one at https://platform.openai.com/api-keys)", file=sys.stderr)
        print("2. Optionally, your Organization ID (if you have one)", file=sys.stderr)
        print(file=sys.stderr)
        
        # Check if we can read from stdin (interactive mode)
        import sys
        if not sys.stdin.isatty():
            # Non-interactive mode (called from Swift app)
            return {
                "success": False,
                "message": "Interactive setup required. Please run this script from the command line to set up your API key.",
                "requires_interactive": True
            }
        
        try:
            # Interactive mode - we can read from stdin
            api_key = input("Enter your OpenAI API key: ").strip()
            if not api_key:
                return {
                    "success": False,
                    "message": "No API key provided"
                }
            
            # Get organization ID (optional)
            organization_id = input("Enter your Organization ID (optional, press Enter to skip): ").strip()
            if not organization_id:
                organization_id = None
        except (EOFError, OSError):
            # Handle case where stdin is not available
            return {
                "success": False,
                "message": "Interactive setup required. Please run this script from the command line to set up your API key.",
                "requires_interactive": True
            }
        
        # Test the connection
        print("\n🔍 Testing API connection...", file=sys.stderr)
        test_result = self.test_api_connection(api_key, organization_id)
        
        if not test_result["success"]:
            print(f"❌ Connection failed: {test_result['message']}", file=sys.stderr)
            return test_result
        
        print("✅ API connection successful!", file=sys.stderr)
        print(f"📊 Available models: {test_result.get('models_count', 'Unknown')}", file=sys.stderr)
        
        # Save credentials
        print("\n💾 Saving credentials to secure storage...", file=sys.stderr)
        
        api_saved = self._save_api_key_to_keyring(api_key)
        org_saved = True
        if organization_id:
            org_saved = self._save_organization_to_keyring(organization_id)
        
        if not api_saved:
            print("❌ Failed to save API key to keychain", file=sys.stderr)
            return {
                "success": False,
                "message": "Failed to save API key to secure storage"
            }
        
        if not org_saved:
            print("⚠️  Warning: Failed to save organization ID to keychain", file=sys.stderr)
        
        # Update user preferences
        preferences = self._load_user_preferences()
        preferences["chatgpt"] = {
            "connected": True,
            "connected_at": self._get_current_timestamp(),
            "has_organization": organization_id is not None
        }
        
        if self._save_user_preferences(preferences):
            print("✅ User preferences updated", file=sys.stderr)
        else:
            print("⚠️  Warning: Could not update user preferences", file=sys.stderr)
        
        print("\n🎉 ChatGPT connection setup complete!", file=sys.stderr)
        print("You can now use AI features in My CRM.", file=sys.stderr)
        
        return {
            "success": True,
            "message": "ChatGPT connection established successfully",
            "has_organization": organization_id is not None,
            "organization": organization_id
        }
    
    def disconnect(self) -> Dict[str, Any]:
        """Disconnect from ChatGPT by removing stored credentials"""
        print("🔌 Disconnecting from ChatGPT...", file=sys.stderr)
        
        try:
            # Remove from keychain
            keyring.delete_password(self.service_name, self.api_key_key)
            keyring.delete_password(self.service_name, self.organization_key)
            
            # Update user preferences
            preferences = self._load_user_preferences()
            if "chatgpt" in preferences:
                preferences["chatgpt"]["connected"] = False
                preferences["chatgpt"]["disconnected_at"] = self._get_current_timestamp()
                self._save_user_preferences(preferences)
            
            print("✅ Disconnected from ChatGPT", file=sys.stderr)
            return {
                "success": True,
                "message": "Successfully disconnected from ChatGPT"
            }
        except Exception as e:
            print(f"❌ Error during disconnect: {e}", file=sys.stderr)
            return {
                "success": False,
                "message": f"Failed to disconnect: {str(e)}"
            }
    
    def _get_current_timestamp(self) -> str:
        """Get current timestamp in ISO format"""
        from datetime import datetime
        return datetime.now().isoformat()
    
    def get_api_credentials(self) -> Dict[str, Optional[str]]:
        """Get stored API credentials (for use by other parts of the app)"""
        return {
            "api_key": self._get_api_key_from_keyring(),
            "organization_id": self._get_organization_from_keyring()
        }

def main():
    """Main function for command-line usage"""
    connector = ChatGPTConnector()
    
    if len(sys.argv) > 1:
        command = sys.argv[1].lower()
        
        if command == "connect":
            result = connector.connect()
            print(json.dumps(result, indent=2))
        elif command == "disconnect":
            result = connector.disconnect()
            print(json.dumps(result, indent=2))
        elif command == "status":
            result = connector.get_current_status()
            print(json.dumps(result, indent=2))
        elif command == "test":
            credentials = connector.get_api_credentials()
            if credentials["api_key"]:
                result = connector.test_api_connection(
                    credentials["api_key"], 
                    credentials["organization_id"]
                )
                print(json.dumps(result, indent=2))
            else:
                print(json.dumps({
                    "success": False,
                    "message": "No API key found"
                }, indent=2))
        else:
            print("Usage: python connectToChatGPT.py [connect|disconnect|status|test]")
    else:
        # Interactive mode
        result = connector.connect()
        print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
