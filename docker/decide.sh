#!/bin/bash
# PENTeam Decision Dialog Script
# Interactive script for Project Owner to make decisions on escalated items

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support both container and local execution paths
if [ -d "/app/decisions/pending" ]; then
    DECISIONS_DIR="/app/decisions"
else
    DECISIONS_DIR="$SCRIPT_DIR/../decisions"
fi

# Ensure all decision directories exist
mkdir -p "$DECISIONS_DIR/pending"
mkdir -p "$DECISIONS_DIR/approved"
mkdir -p "$DECISIONS_DIR/rejected"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           PENTeam Decision Dialog                         ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check for pending decisions - get all .md files recursively
# Support both old naming (next-steps-*.md) and new naming (decision-*.md)
pending_count=0
for file in "$DECISIONS_DIR/pending"/*/*.md; do
    if [ -f "$file" ]; then
        pending_count=$((pending_count + 1))
    fi
done

if [ "$pending_count" -eq 0 ]; then
    echo -e "${GREEN}✓ No pending decisions.${NC}"
    echo "All decisions have been resolved."
    exit 0
fi

echo -e "${YELLOW}You have $pending_count pending decision(s)${NC}"
echo ""

# Build list of projects and their decision files (using simple arrays)
# Associative arrays can have issues in some bash versions
unset project_list
declare -a project_list
unset file_list
declare -a file_list
project_index=0

for file in "$DECISIONS_DIR/pending"/*/*.md; do
    if [ ! -f "$file" ]; then
        continue
    fi
    project=$(basename "$(dirname "$file")")
    # Check if project already in list
    found=false
    for i in "${!project_list[@]}"; do
        if [ "${project_list[$i]}" = "$project" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = "false" ]; then
        project_list[$project_index]="$project"
        file_list[$project_index]="$file"
        project_index=$((project_index + 1))
    fi
done

# Sort projects
sorted_indices=$(for i in "${!project_list[@]}"; do echo "$i"; done | sort -n)

# List projects sorted and build number-to-project mapping
echo -e "${BOLD}Pending Decisions:${NC}"
echo "─────────────────────────────────────────────────"
project_num=1
declare -a num_to_project
for idx in $sorted_indices; do
    proj="${project_list[$idx]}"
    echo -e "  ${CYAN}[$project_num]${NC} $proj"
    num_to_project[$project_num]="$proj"
    project_num=$((project_num + 1))
done
echo ""

# Let user select a decision by number or name
echo -e "${BOLD}Select a decision by number or project name (or 'q' to quit):${NC}"
read -r selection

if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
    echo "Exiting."
    exit 0
fi

# Resolve selection to project name
selected_project=""
if [[ "$selection" =~ ^[0-9]+$ ]]; then
    selected_project="${num_to_project[$selection]}"
else
    for proj in $sorted_projects; do
        if [[ "$proj" == *"$selection"* ]] || [[ "$selection" == *"$proj"* ]]; then
            selected_project="$proj"
            break
        fi
    done
fi

if [ -z "$selected_project" ]; then
    echo -e "${RED}Invalid selection. Please try again.${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Project: ${BOLD}$selected_project${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

# Find the index for selected project
selected_index=""
for idx in "${!project_list[@]}"; do
    if [ "${project_list[$idx]}" = "$selected_project" ]; then
        selected_index=$idx
        break
    fi
done

if [ -z "$selected_index" ]; then
    echo -e "${RED}Error: Project not found${NC}"
    exit 1
fi

# Get decision file
decision_file="${file_list[$selected_index]}"

# Single decision file per project in current implementation
decision_count=1


# Display the decision
echo ""
echo -e "${YELLOW}Decision Content:${NC}"
echo "─────────────────────────────────────────────────"
cat "$decision_file"
echo ""

# Detect decision type and show appropriate options
decision_type="general"
if grep -qi "next step\|further investigation\|continuation" "$decision_file"; then
    decision_type="next_steps"
elif grep -qi "computationally\|np-\|infeasible\|complexity" "$decision_file"; then
    decision_type="computation"
fi

echo -e "${BOLD}Available Options:${NC}"
echo "─────────────────────────────────────────────────"

if [ "$decision_type" = "next_steps" ]; then
    echo -e "  ${CYAN}[1]${NC} A) Continue Investigation"
    echo -e "  ${CYAN}[2]${NC} B) Document for Future"
    echo -e "  ${CYAN}[3]${NC} C) End Investigation"
elif [ "$decision_type" = "computation" ]; then
    echo -e "  ${CYAN}[1]${NC} A) Skip"
    echo -e "  ${CYAN}[2]${NC} B) Approximate"
    echo -e "  ${CYAN}[3]${NC} C) Theoretical Reference"
else
    echo -e "  ${CYAN}[1]${NC} A) Approve"
    echo -e "  ${CYAN}[2]${NC} B) Reject"
    echo -e "  ${CYAN}[3]${NC} C) Request More Info"
fi
echo ""

echo -e "${BOLD}Enter your choice (1/2/3) or 'q' to quit:${NC}"
read -r choice

case "$choice" in
    1) decision="A"
       [ "$decision_type" = "next_steps" ] && desc="Continue Investigation"
       [ "$decision_type" = "computation" ] && desc="Skip"
       [ "$decision_type" = "general" ] && desc="Approve"
       ;;
    2) decision="B"
       [ "$decision_type" = "next_steps" ] && desc="Document for Future"
       [ "$decision_type" = "computation" ] && desc="Approximate"
       [ "$decision_type" = "general" ] && desc="Reject"
       ;;
    3|"") decision="C"
       [ "$decision_type" = "next_steps" ] && desc="End Investigation"
       [ "$decision_type" = "computation" ] && desc="Theoretical Reference"
       [ "$decision_type" = "general" ] && desc="Request More Info"
       ;;
    q|Q) echo "Exiting."; exit 0 ;;
    *) echo -e "${RED}Invalid choice.${NC}"; exit 1 ;;
esac

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Decision Details${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

echo ""
echo -e "${BOLD}Enter your name (required):${NC}"
read -r approver_name
while [ -z "$approver_name" ]; do
    echo -e "${RED}Name is required:${NC}"
    read -r approver_name
done

signature="${approver_name} <$(date '+%Y-%m-%d %H:%M:%S')>"

echo ""
echo -e "${BOLD}Enter optional notes (Enter to skip):${NC}"
read -r approver_notes

echo ""
echo -e "${BOLD}Enter free-form prompt/instructions:${NC}"
echo -e "(Press Enter to skip, or enter multiple lines ending with empty line)"
free_form_prompt=""
while read -r line; do
    [ -z "$line" ] && break
    [ -z "$free_form_prompt" ] && free_form_prompt="$line" || free_form_prompt="$free_form_prompt"$'
'"$line"
done

# Write decision
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
{
    echo ""
    echo "---"
    echo ""
    echo "## Project Owner Decision"
    echo ""
    echo "**Project Owner Decision**: $decision ($desc)"
    echo ""
    echo "**Timestamp**: $timestamp"
    echo ""
    echo "**Signature**: $signature"
    echo ""
    [ -n "$approver_notes" ] && echo "**Notes**: $approver_notes" && echo ""
    [ -n "$free_form_prompt" ] && echo "**Free-form Prompt**: " && echo "$free_form_prompt" && echo ""
} >> "$decision_file"

# Move to appropriate directory based on decision type and option
# 
# Routing Rules:
# - computation/next_steps decisions: ALL options (A/B/C) go to approved/
# - general decisions: Option A→approved/, Option B→rejected/, Option C→approved/
#
if [ "$decision_type" = "general" ] && [ "$decision" = "B" ]; then
    # Option B for general decisions is "Reject" -> rejected/
    mkdir -p "$DECISIONS_DIR/rejected/$selected_project"
    mv "$decision_file" "$DECISIONS_DIR/rejected/$selected_project/"
    echo ""
    echo -e "${RED}⚠ Decision recorded as REJECTED.${NC}"
else
    # A (Approve/Continue/Skip), B (Approximate/Document), and C (Request Info/Theoretical/End)
    # All valid choices go to approved/
    mkdir -p "$DECISIONS_DIR/approved/$selected_project"
    mv "$decision_file" "$DECISIONS_DIR/approved/$selected_project/"
    echo ""
    echo -e "${GREEN}✓ Decision recorded and saved to approved/.${NC}"
fi

echo ""
echo -e "${GREEN}✓ Decision recorded and saved!${NC}"
echo ""
echo -e "${BOLD}Decision:${NC} Option $decision - $desc"
echo -e "${BOLD}Signature:${NC} $signature"
[ -n "$approver_notes" ] && echo -e "${BOLD}Notes:${NC} $approver_notes"
[ -n "$free_form_prompt" ] && echo -e "${BOLD}Free-form Prompt:${NC}" && echo "$free_form_prompt" | sed 's/^/    /'
echo ""
echo -e "${CYAN}The workflow will now continue processing.${NC}"
