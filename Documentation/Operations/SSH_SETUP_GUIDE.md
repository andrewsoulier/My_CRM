# SSH Connection Setup for andreassoul-fuji.nord

## Current Status

✅ **Completed:**
- SSH key pair generated at `~/.ssh/id_ed25519`
- SSH config file updated with host entry
- build_app.sh updated to use new SSH key path

⚠️ **Needs Manual Setup:**
- SSH public key needs to be copied to the remote Mac

---

## Quick Setup (Choose One Method)

### Method 1: One-Line Command (Recommended)

Open Terminal and run this command. You'll be prompted for the password: `28VP04!!`

```bash
cat ~/.ssh/id_ed25519.pub | ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no andrewsoulier@100.106.80.41 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo "✅ SSH key installed successfully"'
```

### Method 2: Manual Copy

1. **Copy your public key:**
   ```bash
   cat ~/.ssh/id_ed25519.pub
   ```
   
   Your key is:
   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEfcZR0xkvmcKTndbalRb1mAraQRF1EFH7a6fSpii+wl My_CRM_Build_System
   ```

2. **On the remote Mac (andreassoul-fuji.nord):**
   - Open Terminal
   - Run these commands:
     ```bash
     mkdir -p ~/.ssh
     chmod 700 ~/.ssh
     nano ~/.ssh/authorized_keys
     ```
   - Paste the public key on a new line
   - Press Ctrl+X, then Y, then Enter to save
   - Run: `chmod 600 ~/.ssh/authorized_keys`

### Method 3: Use System Preferences (if enabled)

1. On the remote Mac: System Preferences → Sharing → Remote Login
2. Ensure "Remote Login" is enabled for your user
3. Use Method 1 or 2 above

---

## Testing Your Connection

After setup, test with:

```bash
ssh andreassoul-fuji.nord 'echo "✅ Connection successful!"'
```

Or using the shorthand:

```bash
ssh andreassoul-fuji 'echo "✅ Connection successful!"'
```

You should connect WITHOUT being prompted for a password!

---

## Troubleshooting

### Connection times out
```bash
# Check if remote Mac is reachable
ping -c 2 100.106.80.41

# Check if SSH port is open
nc -zv 100.106.80.41 22
```

### Still asks for password
```bash
# Verify key is installed on remote
ssh andrewsoulier@100.106.80.41 'cat ~/.ssh/authorized_keys'

# Check SSH config
cat ~/.ssh/config
```

### "Too many authentication failures"
This means SSH tried too many keys. The SSH config now has `IdentitiesOnly yes` which should fix this.

---

## What's Been Changed

### 1. SSH Config (`~/.ssh/config`)
Added entry for andreassoul-fuji.nord:
- Uses new SSH key at `~/.ssh/id_ed25519`
- Direct IP address: 100.106.80.41
- Proper username: andrewsoulier
- Connection timeouts and keepalives configured

### 2. Build Script (`build_app.sh`)
- Updated SSH_KEY_PATH from network volume to `~/.ssh/id_ed25519`
- Will now work even when network volume isn't mounted

### 3. Helper Script (`setup_ssh_key.sh`)
- Interactive script to help set up the SSH key
- Run with: `./setup_ssh_key.sh`

---

## After Successful Setup

Once SSH keys are working, you can:

1. **Connect easily:**
   ```bash
   ssh andreassoul-fuji
   ```

2. **Run remote commands:**
   ```bash
   ssh andreassoul-fuji 'hostname && uptime'
   ```

3. **Build script will work automatically:**
   ```bash
   ./build_app.sh "Your build description"
   ```
   The script will automatically kill processes on both local and remote Macs!

---

## Notes

- The remote Mac must be powered on and connected to Tailscale VPN
- IP Address: 100.106.80.41 (Tailscale address)
- Hostname: andreassoul-fuji.nord
- User: andrewsoulier
- Password (for initial setup): 28VP04!!

