#!/bin/bash
# PENTeam Decision Dialog Script
# Interactive script for Project Owner to make decisions on escalated items
#
# Features:
# - Number-based selection for decisions and options
# - Support for any decision file (not just decision-001.md)
# - Free-form prompt option
# - Name-signature and timestamp in decision

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECISIONS_DIR="$(dirname "$SCRIPT_DIR")/decisions"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           PENTeam Decision Dialog                         ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check for pending decisions
mapfile -t pending_files < <(find "$DECISIONS_DIR/pending" -name "*.md" 2>/dev/null | sort)
pending_count=${#pending_files[@]}

if [ "$pending_count" -eq 0 ]; then
    echo -e "${GREEN}✓ No pending decisions.${NC}"
    echo "All decisions have been resolved."
    exit 0
fi

echo -e "${YELLOW}You have $pending_count pending decision(s)${NC}"
echo ""

# Build array of unique projects
declare -A project_map
idx=1
for file in "${pending_files[@]}"; do
    project=$(basename "$(dirname "$file")")
    if [ -z "${project_map[$project]}" ]; then
        project_map[$project]=$idx
        ((idx++))
    fi
done

# List pending decisions by number
echo -e "${BOLD}Pending Decisions:${NC}"
echo "─────────────────────────────────────────────────"
for project in "${!project_map[@]}"; do
    num=${project_map[$project]}
    count=$(find "$DECISIONS_DIR/pending/$project" -name "*.md" 2>/dev/null | wc -l)
    echo -e "  ${CYAN}[$num]${NC} $project (${count} decision file$( [ $count -gt 1 ] && echo "s" || true ))"
done
echo ""

# Let user select a decision by number
echo -e "${BOLD}Select a decision by number (or 'q' to quit):${NC}"
read -r selection

if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
    echo "Exiting."
    exit 0
fi

# Validate selection and get project name
selected_project=""
for project in "${!project_map[@]}"; do
    if [ "${project_map[$project]}" = "$selection" ]; then
        selected_project="$project"
        break
    fi
done

if [ -z "$selected_project" ]; then
    echo -e "${RED}Invalid selection. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Project: ${BOLD}$selected_project${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

# List decision files for selected project
mapfile -t decision_files < <(find "$DECISIONS_DIR/pending/$selected_project" -name "*.md" 2>/dev/null | sort)

if [ ${#decision_files[@]} -gt 1 ]; then
    echo ""
    echo -e "${BOLD}Multiple decision files found:${NC}"
    for i in "${!decision_files[@]}"; do
        file="${decision_files[$i]}"
        fname=$(basename "$file")
        echo -e "  ${CYAN}[$((i+1))]${NC} $fname"
    done
    echo ""
    echo -e "${BOLD}Select decision file by number:${NC}"
    read -r file_selection
    
    if [ -n "$file_selection" ] && [ "$file_selection" -ge 1 ] && [ "$file_selection" -le ${#decision_files[@]} ]; then
        decision_file="${decision_files[$((file_selection-1))]}"
    else
        echo -e "${RED}Invalid selection, using first file.${NC}"
        decision_file="${decision_files[0]}"
    fi
else
    decision_file="${decision_files[0]}"
fi

# Display the decision
echo ""
echo -e "${YELLOW}Decision Content:${NC}"
echo "─────────────────────────────────────────────────"
cat "$decision_file"
echo ""

# Detect decision type and show appropriate options
decision_type="general"
if grep -qi "next step\|further investigation\|continuation" "$decision_file" 2>/dev/null; then
    decision_type="next_steps"
elif grep -qi "computationally\|np-\|infeasible\|complexity" "$decision_file" 2>/dev/null; then
    decision_type="computation"
fi

# Show options based on decision type
echo -e "${BOLD}Available Options:${NC}"
echo "─────────────────────────────────────────────────"

if [ "$decision_type" = "next_steps" ]; then
    echo -e "  ${CYAN}[1]${NC} A) Continue Investigation"
    echo -e "        Start a new project with the proposed next steps"
    echo -e "  ${CYAN}[2]${NC} B) Document for Future"
    echo -e "        Save next steps to a file for later consideration"
    echo -e "  ${CYAN}[3]${NC} C) End Investigation"
    echo -e "        Consider current investigation complete"
elif [ "$decision_type" = "computation" ]; then
    echo -e "  ${CYAN}[1]${NC} A) Skip"
    echo -e "        Don't implement these theorems"
    echo -e "  ${CYAN}[2]${NC} B) Approximate"
    echo -e "        Implement simplified versions"
    echo -e "  ${CYAN}[3]${NC} C) Theoretical Reference"
    echo -e "        Document without implementation (default)"
else
    echo -e "  ${CYAN}[1]${NC} A) Approve"
    echo -e "        Accept the proposal as-is"
    echo -e "  ${CYAN}[2]${NC} B) Reject"
    echo -e "        Decline the proposal"
    echo -e "  ${CYAN}[3]${NC} C) Request More Info"
    echo -e "        Ask for additional details"
fi
echo ""

# Get user choice by number
echo -e "${BOLD}Enter your choice (1/2/3) or 'q' to quit:${NC}"
read -r choice

case "$choice" in
    1)
        decision="A"
        if [ "$decision_type" = "next_steps" ]; then
            desc="Continue Investigation - Start new project with next steps"
        elif [ "$decision_type" = "computation" ]; then
            desc="Skip - Don't implement these theorems"
        else
            desc="Approve - Accept the proposal"
        fi
        ;;
    2)
        decision="B"
        if [ "$decision_type" = "next_steps" ]; then
            desc="Document for Future - Save for later consideration"
        elif [ "$decision_type" = "computation" ]; then
            desc="Approximate - Implement simplified versions"
        else
            desc="Reject - Decline the proposal"
        fi
        ;;
    3|"")
        decision="C"
        if [ "$decision_type" = "next_steps" ]; then
            desc="End Investigation - Consider complete as-is"
        elif [ "$decision_type" = "computation" ]; then
            desc="Theoretical Reference - Document without implementation"
        else
            desc="Request More Info - Ask for additional details"
        fi
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
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Decision Details${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"

# Get name and signature
echo ""
echo -e "${BOLD}Enter your name (required for signature):${NC}"
read -r approver_name

while [ -z "$approver_name" ]; do
    echo -e "${RED}Name is required. Please enter your name:${NC}"
    read -r approver_name
done

# Generate signature
signature="${approver_name} <$(date '+%Y-%m-%d %H:%M:%S')>"

# Optional notes/reasoning
echo ""
echo -e "${BOLD}Enter optional notes or reasoning:${NC}"
echo -e "(Press Enter to skip)"
read -r approver_notes

# Free-form prompt/instructions
echo ""
echo -e "${BOLD}Enter free-form prompt or instructions:${NC}"
echo -e "${YELLOW}(Optional - This will be included in the decision response)${NC}"
echo -e "(Press Enter to skip, or enter multiple lines ending with empty line)"
echo ""

# Multi-line input for free-form prompt
free_form_prompt=""
while true; do
    read -r line
    if [ -z "$line" ]; then
        break
    fi
    if [ -z "$free_form_prompt" ]; then
        free_form_prompt="$line"
    else
        free_form_prompt="$free_form_prompt"$'\n'"$line"
    fi
done

# Add decision to the file
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
echo "" >> "$decision_file"
echo "---" >> "$decision_file"
echo "" >> "$decision_file"
echo "## Project Owner Decision" >> "$decision_file"
echo "" >> "$decision_file"
echo "**Decision**: $decision ($desc)" >> "$decision_file"
echo "" >> "$decision_file"
echo "**Timestamp**: $timestamp" >> "$decision_file"
echo "" >> "$decision_file"
echo "**Signature**: $signature" >> "$decision_file"
echo "" >> "$decision_file"
if [ -n "$approver_notes" ]; then
    echo "**Notes**: $approver_notes" >> "$decision_file"
    echo "" >> "$decision_file"
fi
if [ -n "$free_form_prompt" ]; then
    echo "**Free-form Prompt**: " >> "$decision_file"
    echo "$free_form_prompt" >> "$decision_file"
    echo "" >> "$decision_file"
fi

# Move to approved directory
mkdir -p "$DECISIONS_DIR/approved/$selected_project"
mv "$decision_file" "$DECISIONS_DIR/approved/$selected_project/"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Decision recorded and saved!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Decision:${NC} Option $decision - $desc"
echo -e "${BOLD}Signature:${NC} $signature"
if [ -n "$approver_notes" ]; then
    echo -e "${BOLD}Notes:${NC} $approver_notes"
fi
if [ -n "$free_form_prompt" ]; then
    echo -e "${BOLD}Free-form Prompt:${NC}"
    echo "$free_form_prompt" | sed 's/^/    /'
fi
echo ""
echo -e "${CYAN}The workflow will now continue processing.${NC}"
