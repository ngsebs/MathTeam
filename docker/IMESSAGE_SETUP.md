# iMessage Integration Setup Guide

This guide explains how to enable iMessage notifications from the PENTeam supervisor running in Docker.

## Overview

The supervisor can send iMessages to a whitelisted contact when:
- ✅ Milestones are achieved
- ⚠️ Interaction is required (decisions pending)
- 📊 Status updates requested

## Prerequisites

### macOS Requirements

1. **Messages app signed in** to iMessage
2. **AppleScript enabled** (default on macOS)
3. **Docker Desktop** with file sharing enabled

### Contact Requirements

The recipient must be:
- In your macOS Contacts app
- Registered with iMessage (phone number or email)
- Whitelisted in the configuration

## Setup Instructions

### Step 1: Verify iMessage Access

Open Terminal and test:

```bash
# Test AppleScript access to Messages
osascript -e 'tell application "Messages" to get name'

# Should return: "Messages"
```

### Step 2: Create Test Contact

1. Open **Contacts** app
2. Create a new contact (e.g., "PENTeam Owner")
3. Add their iMessage-enabled phone number or email
4. Note the format: `+1234567890` or `user@email.com`

### Step 3: Test iMessage Sending

```bash
cd PENTeam/docker

# Make script executable
chmod +x imessage_demo.sh

# Test with a real contact (replace with your test contact)
./imessage_demo.sh send_applescript "+1234567890" "PENTeam test message"
```

### Step 4: Configure Whitelist

Create `docker/.imessage_whitelist` with approved contacts:

```
# iMessage Whitelist - One contact per line
# Format: phone_number or email
+1234567890
owner@example.com
```

### Step 5: Set Environment Variable

```bash
# In your shell or .env file
export IMESSAGE_WHITELIST="/path/to/.imessage_whitelist"
export IMESSAGE_DEFAULT_RECIPIENT="+1234567890"
```

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Container                          │
│                                                              │
│  Supervisor detects milestone/completion                     │
│                        │                                    │
│                        ▼                                    │
│  Writes message to /app/communication/imessage_queue.txt    │
└────────────────────────────┬────────────────────────────────┘
                             │
                    Volume Mount
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    macOS Host                                │
│                                                              │
│  Host script polls queue file (every 10s)                    │
│                        │                                    │
│                        ▼                                    │
│  osascript sends iMessage via Messages app                  │
│                        │                                    │
│                        ▼                                    │
│  Responses stored in imessage_responses.txt                  │
└─────────────────────────────────────────────────────────────┘
```

## For Docker Container (Host Network Mode)

Since the container uses `--network host`, it can access localhost. The iMessage sender runs on the host:

### Option A: Host Script Polling

Create `send_imessage_host.sh` on your Mac:

```bash
#!/bin/bash
# Location: ~/Scripts/send_imessage.sh

QUEUE_FILE="$HOME/PENTeam/communication/imessage_queue.txt"
RESPONSE_FILE="$HOME/PENTeam/communication/imessage_responses.txt"
WHITELIST="$HOME/PENTeam/docker/.imessage_whitelist"

# Default recipient if whitelist not found
DEFAULT_RECIPIENT="+1234567890"

# Check for new messages
while true; do
    if [ -f "$QUEUE_FILE" ] && [ -s "$QUEUE_FILE" ]; then
        while IFS='|' read -r recipient message; do
            # Skip empty lines
            [ -z "$recipient" ] && continue
            
            # Validate recipient against whitelist
            if grep -q "^${recipient}$" "$WHITELIST" 2>/dev/null || \
               grep -q "^${recipient}$" <(echo "$DEFAULT_RECIPIENT"); then
                
                # Send via AppleScript
                osascript -e "
                tell application \"Messages\"
                    set targetService to 1st service whose service type = iMessage
                    send \"$message\" to buddy \"$recipient\" of targetService
                end tell
                "
                
                echo "$(date): Sent to $recipient" >> "$RESPONSE_FILE"
            fi
        done < "$QUEUE_FILE"
        
        # Clear queue
        > "$QUEUE_FILE"
    fi
    sleep 10
done
```

### Option B: LaunchDaemon (Background Service)

Create `~/Library/LaunchAgents/com.penteam.imessage.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.penteam.imessage</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/YOUR_USER/Scripts/send_imessage.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.penteam.imessage.plist
```

## Security Considerations

1. **Whitelist Only**: Only approved contacts receive messages
2. **No External Access**: Messages go only to whitelisted recipients
3. **Local Only**: No cloud/API dependencies
4. **Audit Trail**: All messages logged in responses file

## Troubleshooting

### "Operation not permitted" Error

Go to **System Preferences → Security & Privacy → Privacy → Automation**
- Enable "Terminal" to control "Messages"

### "Can't get buddy" Error

- Verify recipient is in Contacts
- Verify recipient has iMessage enabled
- Check phone number format (+1XXXXXXXXXX)

### Messages Not Sending

1. Check Messages app is signed in
2. Verify network connectivity
3. Check whitelist file format

## Example Notifications

The supervisor will send:

```
🏆 MILESTONE: Project "fibonacci" complete!
   • Theorems proposed: 3
   • Implementation: ✓
   • Tests: 5/5 passed
   Reply with "status" for details
```

```
⚠️ DECISION NEEDED: Approve theorem for "prime-research"?
   Reply YES/NO/PENDING
```

```
📊 STATUS: Team idle, 0 active projects
   Reply "projects" for queue, "help" for commands
```