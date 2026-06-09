#!/bin/bash
# PENTeam Agent Monitor
# Shows active agents, their status, and current workload

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Header
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         PENTeam Agent Monitor - $(date '+%Y-%m-%d %H:%M:%S')              ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check Ollama status
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Ollama Status${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

OLLAMA_URL="http://localhost:11434"
if curl -s --max-time 3 "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Ollama is running at $OLLAMA_URL"
    MODELS=$(curl -s "$OLLAMA_URL/api/tags" | jq -r '.models[] | .name' 2>/dev/null || echo "Unable to parse models")
    echo "  Available models:"
    echo "$MODELS" | while read -r model; do
        echo -e "    ${GREEN}•${NC} $model"
    done
else
    echo -e "  ${RED}✗${NC} Ollama not running at $OLLAMA_URL"
    echo "  Start Ollama: ollama serve"
fi
echo ""

# Agent definitions
AGENTS=(
    "supervisor:Orchestrates workflow|AI/supervisor.md"
    "creative-mathematician:Formulates theorems|AI/creative-mathematician.md"
    "senior-mathematician:Reviews theorems|AI/senior-mathematician.md"
    "python-coder:Implements code|AI/python-coder.md"
    "tester:Validates implementations|AI/tester.md"
)

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Agent Team Status${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

for agent_info in "${AGENTS[@]}"; do
    IFS=':' read -r name desc <<< "$agent_info"
    echo -e "  ${CYAN}•${NC} ${GREEN}$name${NC} - $desc"
done
echo ""

# Project queue
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Project Queue (input/)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -d "/app/input" ]; then
    INPUT_FILES=$(find /app/input -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l)
    echo "  Pending projects: $INPUT_FILES"
    
    if [ "$INPUT_FILES" -gt 0 ]; then
        echo "  Projects:"
        find /app/input -maxdepth 1 -name "*.md" -type f 2>/dev/null | while read -r file; do
            basename_file=$(basename "$file")
            modified=$(stat -c %Y "$file" 2>/dev/null || stat -f %Sm "$file" 2>/dev/null)
            age_seconds=$(( $(date +%s) - modified ))
            if [ "$age_seconds" -lt 60 ]; then
                age_str="just now"
            elif [ "$age_seconds" -lt 3600 ]; then
                age_str="$(( age_seconds / 60 ))m ago"
            else
                age_str="$(( age_seconds / 3600 ))h ago"
            fi
            echo -e "    ${YELLOW}○${NC} $basename_file (added $age_str)"
        done
    fi
else
    echo -e "  ${RED}✗${NC} Input directory not found"
fi
echo ""

# Active projects
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Active Projects (output/)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -d "/app/output" ]; then
    PROJECT_DIRS=$(find /app/output -maxdepth 1 -type d ! -name "output" 2>/dev/null | wc -l)
    echo "  Active projects: $PROJECT_DIRS"
    
    if [ "$PROJECT_DIRS" -gt 0 ]; then
        echo "  Projects:"
        find /app/output -maxdepth 1 -type d ! -name "output" 2>/dev/null | while read -r dir; do
            project_name=$(basename "$dir")
            if [ -f "$dir/summary.md" ]; then
                status=$(grep -i "status" "$dir/summary.md" 2>/dev/null | head -1 | sed 's/.*Status.*: *//' | tr -d '*' | xargs)
                if [ -n "$status" ]; then
                    echo -e "    ${GREEN}●${NC} $project_name - $status"
                else
                    echo -e "    ${YELLOW}●${NC} $project_name"
                fi
            else
                echo -e "    ${YELLOW}●${NC} $project_name (in progress)"
            fi
        done
    fi
else
    echo -e "  ${YELLOW}○${NC} No active projects"
fi
echo ""

# Pending decisions
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Pending Decisions${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -d "/app/decisions/pending" ]; then
    PENDING_COUNT=$(find /app/decisions/pending -name "*.md" 2>/dev/null | wc -l)
    echo "  Awaiting approval: $PENDING_COUNT"
    
    if [ "$PENDING_COUNT" -gt 0 ]; then
        echo "  Decisions:"
        find /app/decisions/pending -name "*.md" 2>/dev/null | while read -r file; do
            basename_file=$(basename "$file")
            echo -e "    ${RED}!${NC} $basename_file"
        done
    fi
else
    echo -e "  ${GREEN}✓${NC} No pending decisions"
fi
echo ""

# Communication threads
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Communication Threads${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -d "/app/communication/threads" ]; then
    THREAD_COUNT=$(find /app/communication/threads -maxdepth 1 -type d 2>/dev/null | wc -l)
    ((THREAD_COUNT--))  # Exclude the threads directory itself
    echo "  Active threads: $THREAD_COUNT"
else
    echo "  No active threads"
fi
echo ""

# System resources
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}System Resources${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo "  CPU Load: $(uptime | awk -F'load average:' '{print $2}' | xargs)"
echo "  Memory: $(free -h 2>/dev/null | awk '/Mem:/ {print $3 "/" $2}' || sysctl -n hw.memsize | numfmt --to=iec-i)"
echo "  Uptime: $(uptime | awk '{print $3, $4}' | tr -d ',')"
echo ""

# Footer
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "View logs: tail -f /root/.openhands/logs/openhands.log"
echo -e "Monitor projects: ls -la /app/output/"
echo -e "Check decisions: ls -la /app/decisions/pending/"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"