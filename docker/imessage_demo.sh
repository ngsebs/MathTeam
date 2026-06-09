#!/bin/bash
# iMessage Integration Demo for PENTeam
# This script demonstrates how to send iMessages from macOS

# ============================================
# METHOD 1: Using AppleScript (Native macOS)
# ============================================

send_imessage_applescript() {
    local recipient="$1"
    local message="$2"
    
    osascript -e "
    tell application \"Messages\"
        set targetService to 1st service whose service type = iMessage
        set targetBuddy to \"$recipient\"
        set msg to \"$message\"
        send msg to buddy targetBuddy of targetService
    end tell
    "
}

# ============================================
# METHOD 2: Using Contacts (Simpler)
# ============================================

send_imessage_simple() {
    local recipient="$1"
    local message="$2"
    
    # This opens Messages app with pre-filled recipient and message
    osascript -e "
    tell application \"Messages\"
        activate
        set targetService to 1st service whose service type = iMessage
        set targetBuddy to \"$recipient\"
        set msg to \"$message\"
        send msg to buddy targetBuddy of targetService
    end tell
    "
}

# ============================================
# METHOD 3: Using Shortcuts App (Modern)
# ============================================

send_via_shortcuts() {
    local recipient="$1"
    local message="$2"
    
    # Create a Shortcut first in macOS Shortcuts app:
    # "Send iMessage" that takes "recipient" and "message" as input
    
    shortcuts run "Send iMessage" --input-text "$recipient|$message"
}

# ============================================
# DEMONSTRATION
# ============================================

echo "=========================================="
echo "  iMessage Integration Demo"
echo "=========================================="
echo ""
echo "This script demonstrates 3 methods to send iMessages:"
echo ""
echo "1. AppleScript (Native) - Most reliable"
echo "2. AppleScript Simple - Opens Messages app"
echo "3. Shortcuts App - Modern macOS approach"
echo ""
echo "=========================================="
echo ""
echo "USAGE:"
echo ""
echo "  # Method 1: Direct AppleScript"
echo "  ./imessage_demo.sh send_applescript \"+1234567890\" \"Hello from PENTeam!\""
echo ""
echo "  # Method 2: Simple AppleScript"  
echo "  ./imessage_demo.sh send_simple \"+1234567890\" \"Your approval is needed!\""
echo ""
echo "  # Method 3: Via Shortcuts"
echo "  ./imessage_demo.sh send_shortcuts \"+1234567890\" \"Milestone achieved!\""
echo ""
echo "=========================================="
echo ""
echo "PREREQUISITES:"
echo ""
echo "1. Messages app must be signed into iMessage"
echo "2. Contact must be in your Contacts app"
echo "3. For phone numbers: use format +1XXXXXXXXXX"
echo "4. For emails: use the registered iMessage email"
echo ""
echo "=========================================="
echo ""

# Handle command line arguments
case "${1:-demo}" in
    send_applescript)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 send_applescript <recipient> <message>"
            exit 1
        fi
        echo "Sending via AppleScript..."
        send_imessage_applescript "$2" "$3"
        echo "Done!"
        ;;
    send_simple)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 send_simple <recipient> <message>"
            exit 1
        fi
        echo "Sending via Simple AppleScript..."
        send_imessage_simple "$2" "$3"
        echo "Done!"
        ;;
    send_shortcuts)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 send_shortcuts <recipient> <message>"
            exit 1
        fi
        echo "Sending via Shortcuts..."
        send_via_shortcuts "$2" "$3"
        echo "Done!"
        ;;
    demo|*)
        echo "Running demo mode - no message sent"
        echo ""
        echo "To test on your macOS machine:"
        echo "1. Open Terminal"
        echo "2. Run: ./imessage_demo.sh send_applescript \"+1234567890\" \"Test\""
        echo ""
        ;;
esac