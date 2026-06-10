#!/bin/bash
# Run the PENTeam mathematical research team in Docker
# Agents run inside container, Ollama runs on macOS host
# Uses host network mode to access Ollama at localhost:11434

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables if .env exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "Loading environment from $PROJECT_ROOT/.env"
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Create workdir if it doesn't exist (legacy support)
mkdir -p "$PROJECT_ROOT/workdir"

# Create hidden directories if they don't exist
mkdir -p "$PROJECT_ROOT/.openhands"
mkdir -p "$PROJECT_ROOT/.agents"
mkdir -p "$PROJECT_ROOT/.mcp"

echo "=========================================="
echo "  PENTeam Math Research Team"
echo "=========================================="
echo ""
echo "Platform: macOS (Host) + Docker Container"
echo "Network Mode: host (direct localhost access)"
echo "Ollama Host: ${OLLAMA_HOST:-localhost:11434}"
echo "Python Environment: /app/.venv (auto-activated)"
echo ""

# Check Ollama availability on macOS host (with retries)
# Use host.docker.internal for macOS Docker host access
echo "Checking Ollama availability..."
OLLAMA_URL="http://host.docker.internal:11434/api/tags"
MAX_RETRIES=3
RETRY_DELAY=2
ollama_available=false

for i in $(seq 1 $MAX_RETRIES); do
    echo "  Attempt $i/$MAX_RETRIES..."
    if curl -s --max-time 5 "$OLLAMA_URL" > /dev/null 2>&1; then
        ollama_available=true
        break
    fi
    if [ $i -lt $MAX_RETRIES ]; then
        echo "  Retrying in ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
    fi
done

if [ "$ollama_available" = true ]; then
    echo ""
    echo "✓ Ollama is accessible at $OLLAMA_URL"
    echo "  Available models:"
    MODELS=$(curl -s "$OLLAMA_URL" 2>/dev/null | jq -r '.models[] | .name' 2>/dev/null || echo "")
    if [ -n "$MODELS" ]; then
        echo "$MODELS" | while read -r model; do
            [ -n "$model" ] && echo "    - $model"
        done
    else
        echo "    (no models found - pull with: ollama pull llama3.2:3b)"
    fi
else
    echo ""
    echo "⚠ Ollama not detected at $OLLAMA_URL (using host.docker.internal:11434)"
    echo ""
    echo "  In --network host mode, the container must reach Ollama via host.docker.internal"
    echo "  The container will still start and retry Ollama connection."
    echo "  To fix this, on macOS host run:"
    echo "    1. ollama serve"
    echo "    2. ollama pull llama3.2:3b"
    echo ""
    echo "  Waiting for Ollama to become available..."
fi
echo ""

# Display model configuration
echo "Agent Models:"
echo "  Supervisor:        ${SUPERVISOR_MODEL:-llama3.2:3b}"
echo "  Creative Math:     ${CREATIVE_MATH_MODEL:-llama3.2:3b}"
echo "  Senior Math:      ${SENIOR_MATH_MODEL:-llama3.2:3b}"
echo "  Python Coder:     ${PYTHON_CODER_MODEL:-codellama:7b}"
echo "  Tester:          ${TESTER_MODEL:-llama3.2:3b}"
echo ""

# Parse command line arguments
MODE="${1:-supervisor}"

case "$MODE" in
    supervisor)
        echo "Starting Supervisor mode (monitors input directory)..."
        echo ""
        COMMAND="/app/docker/supervisor.sh start"
        ;;
    interactive)
        echo "Starting Interactive mode..."
        echo ""
        COMMAND="/bin/bash"
        ;;
    monitor)
        echo "Starting Monitor mode..."
        echo ""
        COMMAND="/app/docker/monitor.sh"
        ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Usage: $0 [supervisor|interactive|monitor]"
        exit 1
        ;;
esac

# Run the container with host network mode
# In host network mode on macOS, use host.docker.internal to reach the host
echo "Starting Docker container..."
docker run \
    --rm \
    -it \
    --name pent-eam-math-team \
    --hostname pent-eam-math-team \
    --network host \
    -v "$PROJECT_ROOT/AI:/app/AI:ro" \
    -v "$PROJECT_ROOT/input:/app/input:rw" \
    -v "$PROJECT_ROOT/output:/app/output:rw" \
    -v "$PROJECT_ROOT/communication:/app/communication:rw" \
    -v "$PROJECT_ROOT/decisions:/app/decisions:rw" \
    -v "$PROJECT_ROOT/.openhands:/app/.openhands:rw" \
    -v "$PROJECT_ROOT/.agents:/app/.agents:ro" \
    -v "$PROJECT_ROOT/.mcp:/app/.mcp:ro" \
    -v "$PROJECT_ROOT/.cursorrules:/app/.cursorrules:ro" \
    -v "$PROJECT_ROOT/AGENTS.md:/app/AGENTS.md:ro" \
    -v "$PROJECT_ROOT/requirements.txt:/app/requirements.txt:ro" \
    -v "$SCRIPT_DIR:/app/docker:ro" \
    -v ~/.openhands:/root/.openhands \
    -w /app \
    -e OLLAMA_HOST=host.docker.internal:11434 \
    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
    ${SUPERVISOR_MODEL:+-e SUPERVISOR_MODEL="$SUPERVISOR_MODEL"} \
    ${CREATIVE_MATH_MODEL:+-e CREATIVE_MATH_MODEL="$CREATIVE_MATH_MODEL"} \
    ${SENIOR_MATH_MODEL:+-e SENIOR_MATH_MODEL="$SENIOR_MATH_MODEL"} \
    ${PYTHON_CODER_MODEL:+-e PYTHON_CODER_MODEL="$PYTHON_CODER_MODEL"} \
    ${TESTER_MODEL:+-e TESTER_MODEL="$TESTER_MODEL"} \
    ${LLM_API_KEY:+-e LLM_API_KEY="$LLM_API_KEY"} \
    ${LLM_MODEL:+-e LLM_MODEL="$LLM_MODEL"} \
    ${LLM_BASE_URL:+-e LLM_BASE_URL="$LLM_BASE_URL"} \
    pent-eam-math-team:latest $COMMAND