#!/bin/bash
# PENTeam Decision Dialog Script
# Interactive script for Project Owner to make decisions on escalated items

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECISIONS_DIR="$(dirname "$SCRIPT_DIR")/decisions"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}           PENTeam Decision Dialog                         ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check for pending decisions
pending_count=$(find "$DECISIONS_DIR/pending" -name "*.md" 2>/dev/null | wc -l)

if [ "$pending_count" -eq 0 ]; then
    echo -e "${GREEN}✓ No pending decisions.${NC}"
    echo "All decisions have been resolved."
    exit 0
fi

echo -e "${YELLOW}You have $pending_count pending decision(s)${NC}"
echo ""

# List pending decisions
echo "Pending Decisions:"
echo "─────────────────────────────────────────────"
find "$DECISIONS_DIR/pending" -name "*.md" 2>/dev/null | while read -r file; do
    project=$(basename "$(dirname "$file")")
    decision=$(basename "$file")
    echo "  📋 $project / $decision"
done
echo ""

# Let user select a decision to review
echo "Enter the project name to review its decision (or 'q' to quit):"
read -r selected_project

if [ "$selected_project" = "q" ] || [ "$selected_project" = "Q" ]; then
    echo "Exiting."
    exit 0
fi

# Find the decision file for the selected project
decision_file="$DECISIONS_DIR/pending/$selected_project/decision-001.md"

if [ ! -f "$decision_file" ]; then
    echo -e "${RED}No decision found for project: $selected_project${NC}"
    exit 1
fi

# Display the decision
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Decision: $selected_project${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo ""
cat "$decision_file"
echo ""

# Show options
echo -e "${YELLOW}Available Options:${NC}"
echo "  A) Skip - Don't implement these theorems"
echo "  B) Approximate - Implement simplified versions"
echo "  C) Theoretical Reference - Document but don't implement (default)"
echo ""

# Get user choice
echo "Enter your choice (A/B/C) or 'q' to quit:"
read -r choice

case "$choice" in
    a|A)
        decision="A"
        desc="Skip implementation"
        ;;
    b|B)
        decision="B"
        desc="Approximate implementation"
        ;;
    c|C|"")
        decision="C"
        desc="Theoretical reference (default)"
        ;;
    q|Q)
        echo "Exiting without making a decision."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}Enter your name (for the record):${NC}"
read -r approver_name

# Optional notes/reasoning
echo ""
echo -e "${CYAN}Enter optional notes or reasoning (press Enter to skip):${NC}"
read -r approver_notes

# Custom prompt for continuation (Option A only)
echo ""
echo -e "${CYAN}Enter optional custom instructions for continuation project (press Enter to skip):${NC}"
echo -e "${YELLOW}This will be added to the next investigation project.${NC}"
read -r custom_prompt

# Add decision to the file
echo "" >> "$decision_file"
echo "---" >> "$decision_file"
echo "" >> "$decision_file"
echo "## Project Owner Decision" >> "$decision_file"
echo "" >> "$decision_file"
echo "**Project Owner Decision**: $decision" >> "$decision_file"
echo "" >> "$decision_file"
echo "**Rationale**: $desc" >> "$decision_file"
echo "" >> "$decision_file"
echo "**Approved By**: $approver_name" >> "$decision_file"
echo "" >> "$decision_file"
if [ -n "$approver_notes" ]; then
    echo "**Notes**: $approver_notes" >> "$decision_file"
    echo "" >> "$decision_file"
fi
if [ -n "$custom_prompt" ]; then
    echo "**Custom Prompt**: $custom_prompt" >> "$decision_file"
    echo "" >> "$decision_file"
fi
echo "**Date**: $(date '+%Y-%m-%d %H:%M:%S')" >> "$decision_file"

# Move to approved directory
mkdir -p "$DECISIONS_DIR/approved/$selected_project"
mv "$decision_file" "$DECISIONS_DIR/approved/$selected_project/"

echo ""
echo -e "${GREEN}✓ Decision recorded and saved!${NC}"
echo "Decision: Option $decision - $desc"
echo "Approved by: $approver_name"
if [ -n "$approver_notes" ]; then
    echo "Notes: $approver_notes"
fi
echo ""
echo "The workflow will now continue processing."