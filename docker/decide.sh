#!/bin/bash
# PENTeam Decision Dialog Script
# Interactive script for Project Owner to make decisions on escalated items

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support both container and local execution paths
if [ -d "/app/decisions" ]; then
    DECISIONS_DIR="/app/decisions"
else
    DECISIONS_DIR="$SCRIPT_DIR/../decisions"
fi

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

# Build associative array of projects and their decision files
declare -A project_files
for file in "$DECISIONS_DIR/pending"/*/*.md; do
    if [ ! -f "$file" ]; then
        continue
    fi
    project=$(basename "$(dirname "$file")")
    if [ -z "${project_files[$project]}" ]; then
        project_files[$project]="$file"
    else
        project_files[$project]="${project_files[$project]}"$'
'"$file"
    fi
done

# List projects sorted
echo -e "${BOLD}Pending Decisions:${NC}"
echo "─────────────────────────────────────────────────"
sorted_projects=$(for p in "${!project_files[@]}"; do echo "$p"; done | sort)
project_num=1
declare -A num_to_project
for proj in $sorted_projects; do
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

# Get decision files for selected project - convert newline-separated to array
IFS_backup="$IFS"
IFS=$'\n'
decision_files=()
for line in ${project_files[$selected_project]}; do
    [ -n "$line" ] && decision_files+=("$line")
done
IFS="$IFS_backup"
decision_count=${#decision_files[@]}

# If multiple files, let user select
if [ $decision_count -gt 1 ]; then
    echo ""
    echo -e "${BOLD}Multiple decision files found:${NC}"
    for i in "${!decision_files[@]}"; do
        fname=$(basename "${decision_files[$i]}")
        echo -e "  ${CYAN}[$((i+1))]${NC} $fname"
    done
    echo ""
    echo -e "${BOLD}Select decision file by number (or Enter for first):${NC}"
    read -r file_selection
    
    if [ -n "$file_selection" ] && [ "$file_selection" -ge 1 ] && [ "$file_selection" -le $decision_count ]; then
        decision_file="${decision_files[$((file_selection-1))]}"
    else
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
    echo "**Decision**: $decision ($desc)"
    echo ""
    echo "**Timestamp**: $timestamp"
    echo ""
    echo "**Signature**: $signature"
    echo ""
    [ -n "$approver_notes" ] && echo "**Notes**: $approver_notes" && echo ""
    [ -n "$free_form_prompt" ] && echo "**Free-form Prompt**: " && echo "$free_form_prompt" && echo ""
} >> "$decision_file"

# Move to approved
mkdir -p "$DECISIONS_DIR/approved/$selected_project"
mv "$decision_file" "$DECISIONS_DIR/approved/$selected_project/"

echo ""
echo -e "${GREEN}✓ Decision recorded and saved!${NC}"
echo ""
echo -e "${BOLD}Decision:${NC} Option $decision - $desc"
echo -e "${BOLD}Signature:${NC} $signature"
[ -n "$approver_notes" ] && echo -e "${BOLD}Notes:${NC} $approver_notes"
[ -n "$free_form_prompt" ] && echo -e "${BOLD}Free-form Prompt:${NC}" && echo "$free_form_prompt" | sed 's/^/    /'
echo ""
echo -e "${CYAN}The workflow will now continue processing.${NC}"
