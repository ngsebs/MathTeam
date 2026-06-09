#!/bin/bash
# Debug script for PENTeam - Analyzes and fixes common issues

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}          PENTeam Debug & Analysis Tool                       ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if we're in Docker
if [ ! -f "/.dockerenv" ] && [ "$HOSTNAME" != "pent-eam-math-team" ]; then
    echo -e "${YELLOW}Note: This script is designed to run inside the Docker container${NC}"
    echo ""
fi

# 1. System Information
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}System Information${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Hostname: $(hostname)"
echo "  User: $(whoami)"
echo "  Python: $(python --version 2>&1)"
echo "  Working Directory: $(pwd)"
echo ""

# 2. Ollama Status
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Ollama Status${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"
echo "  Ollama Host: $OLLAMA_HOST"

if curl -s --max-time 5 "http://${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; then
    echo -e "  Status: ${GREEN}✓ Running${NC}"
    echo "  Available models:"
    curl -s "http://${OLLAMA_HOST}/api/tags" 2>/dev/null | jq -r '.models[] | "    - \(.name)"' 2>/dev/null || echo "    (unable to list models)"
else
    echo -e "  Status: ${RED}✗ Not Available${NC}"
    echo ""
    echo -e "  ${YELLOW}Troubleshooting:${NC}"
    echo "    1. On macOS host, ensure Ollama is running:"
    echo "       - Run: ollama serve"
    echo "       - Verify: curl http://localhost:11434/api/tags"
    echo "    2. Check if port 11434 is blocked:"
    echo "       - Run: lsof -i :11434"
    echo "    3. Restart Ollama on host:"
    echo "       - Run: pkill ollama && ollama serve"
fi
echo ""

# 3. Environment Variables
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Environment Variables${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  OLLAMA_HOST: ${OLLAMA_HOST:-not set}"
echo "  OLLAMA_BASE_URL: ${OLLAMA_BASE_URL:-not set}"
echo "  INPUT_DIR: ${INPUT_DIR:-not set}"
echo "  OUTPUT_DIR: ${OUTPUT_DIR:-not set}"
echo "  VIRTUAL_ENV: ${VIRTUAL_ENV:-not set}"
echo "  PATH: $(echo $PATH | tr ':' '\n' | head -5 | sed 's/^/    /')"
echo ""

# 4. Python Environment
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Python Environment${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Python: $(which python || echo 'not found')"
echo "  Python version: $(python --version 2>&1)"
echo "  Virtual Environment: ${VIRTUAL_ENV:-none}"

if [ -n "$VIRTUAL_ENV" ] && [ -d "$VIRTUAL_ENV" ]; then
    echo "  Venv path: $VIRTUAL_ENV"
    if [ -f "$VIRTUAL_ENV/bin/python" ]; then
        echo -e "  Venv Python: ${GREEN}✓ Found${NC}"
        echo "  Installed packages:"
        $VIRTUAL_ENV/bin/pip list 2>/dev/null | grep -E "openhands|uv|httpx" | sed 's/^/    /' || echo "    (none found)"
    else
        echo -e "  Venv Python: ${RED}✗ Not Found${NC}"
    fi
else
    echo -e "  Virtual Environment: ${YELLOW}⚠ Not Active${NC}"
fi
echo ""

# 5. Directory Structure
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Directory Structure${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
DIRS=("/app" "/app/input" "/app/output" "/app/communication" "/app/decisions" "/app/AI")
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✓${NC} $dir ($count items)"
    else
        echo -e "  ${RED}✗${NC} $dir (missing)"
    fi
done
echo ""

# 6. Supervisor Status
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Supervisor Status${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ -f "/app/communication/supervisor.log" ]; then
    echo "  Log file: /app/communication/supervisor.log"
    echo "  Last 10 lines:"
    tail -10 /app/communication/supervisor.log 2>/dev/null | sed 's/^/    /'
else
    echo "  Log file: ${YELLOW}Not found${NC}"
fi
echo ""

# 7. Docker Scripts
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Docker Scripts${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
SCRIPTS=("/app/docker/supervisor.sh" "/app/docker/monitor.sh" "/app/docker/run.sh")
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        perms=$(ls -la "$script" 2>/dev/null | awk '{print $1, $9}')
        echo -e "  ${GREEN}✓${NC} $script"
    else
        echo -e "  ${RED}✗${NC} $script (missing)"
    fi
done
echo ""

# 8. Run OpenHands Analysis
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}OpenHands Agent (AI Analysis)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check if openhands is available via Python module
if python -c "import openhands" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} OpenHands Python module available"
    echo ""
    echo "  To run OpenHands agent, use:"
    echo "    python -m openhands --config /app/.openhands/config.toml"
    echo ""
else
    echo -e "  ${RED}✗${NC} OpenHands not installed"
    echo ""
    echo "  To install OpenHands:"
    echo "    pip install openhands"
    echo ""
fi

# Show agent configuration
if [ -f "/app/.openhands/config.toml" ]; then
    echo "  Config: /app/.openhands/config.toml"
    grep -E "model|OLLAMA" /app/.openhands/config.toml 2>/dev/null | head -5 | sed 's/^/    /'
fi
echo ""

# 9. Quick Fix Commands
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Quick Fix Commands${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Fix Ollama connection:"
echo "    1. Restart Ollama on macOS: pkill ollama && ollama serve"
echo "    2. Check port: lsof -i :11434"
echo "    3. Test: curl http://localhost:11434/api/tags"
echo ""
echo "  Restart supervisor:"
echo "    /app/docker/supervisor.sh start"
echo ""
echo "  Run monitor:"
echo "    /app/docker/monitor.sh"
echo ""
echo "  Activate venv:"
echo "    source /app/.venv/bin/activate"
echo ""

# 10. AI Analysis Section
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}AI Analysis Request${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Paste your problem description and I'll analyze it:"
echo "  (or press Ctrl+C to exit)"
echo ""
read -p "  Problem: " problem
if [ -n "$problem" ]; then
    echo ""
    echo -e "${YELLOW}Analyzing: $problem${NC}"
    echo ""
    echo "  Common issues and fixes:"
    echo ""
    echo "  1. Ollama not running:"
    echo "     → On macOS: ollama serve"
    echo "     → Pull models: ollama pull llama3.2:3b"
    echo ""
    echo "  2. Connection refused:"
    echo "     → Check firewall: sudo ufw allow 11434"
    echo "     → Verify host network mode in Docker"
    echo ""
    echo "  3. Supervisor not starting:"
    echo "     → Check logs: cat /app/communication/supervisor.log"
    echo "     → Run manually: /app/docker/supervisor.sh start"
    echo ""
    echo "  4. Import errors:"
    echo "     → Activate venv: source /app/.venv/bin/activate"
    echo "     → Reinstall: pip install openhands httpx aiohttp"
fi
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo "Debug complete. Check the sections above for issues."
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"