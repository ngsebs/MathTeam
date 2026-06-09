#!/bin/bash
# OpenHands Agent Runner for PENTeam
# Uses the installed openhands package via Python module

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}           PENTeam OpenHands Agent Runner                    ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Activate virtual environment if available
if [ -f "/app/.venv/bin/activate" ]; then
    echo -e "${GREEN}Activating virtual environment...${NC}"
    source /app/.venv/bin/activate
else
    echo -e "${YELLOW}Warning: Virtual environment not found at /app/.venv${NC}"
fi

# Check Python and OpenHands
echo "Checking environment..."
echo "  Python: $(which python)"
echo "  Python version: $(python --version 2>&1)"

# Check if openhands is installed
if python -c "import openhands" 2>/dev/null; then
    echo -e "  OpenHands: ${GREEN}✓ Installed${NC}"
    python -m openhands --version 2>/dev/null || echo "  Version: (unknown)"
else
    echo -e "  OpenHands: ${YELLOW}⚠ Not installed via Python module${NC}"
    echo ""
    echo "  Available methods:"
    echo "    1. Install: pip install openhands"
    echo "    2. Use CLI: openhands (if installed globally)"
fi

# Check Ollama
echo ""
echo "Checking Ollama..."
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"
if curl -s --max-time 3 "http://${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; then
    echo -e "  Ollama: ${GREEN}✓ Running at $OLLAMA_HOST${NC}"
    MODELS=$(curl -s "http://${OLLAMA_HOST}/api/tags" | python -c "import sys,json; print('\n'.join(m['name'] for m in json.load(sys.stdin).get('models',[])))" 2>/dev/null || echo "(none)")
    echo "  Models:"
    echo "$MODELS" | sed 's/^/    /'
else
    echo -e "  Ollama: ${YELLOW}⚠ Not available at $OLLAMA_HOST${NC}"
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo "Running OpenHands Agent..."
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Run OpenHands with configuration
if [ -f "/app/.openhands/config.toml" ]; then
    exec python -m openhands --config /app/.openhands/config.toml "$@"
else
    echo -e "${YELLOW}Warning: config.toml not found, using defaults${NC}"
    exec python -m openhands "$@"
fi