#!/bin/bash
# Run the mathematical research team in Docker

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables if .env exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

# Create workdir if it doesn't exist
mkdir -p "$PROJECT_ROOT/workdir"

# Run the container
echo "Starting PENTeam Math Research Team..."
docker run \
    --rm \
    -it \
    --name pent-eam-math-team \
    -v "$PROJECT_ROOT/AI:/app/AI:ro" \
    -v "$PROJECT_ROOT/workdir:/app/workdir" \
    -v ~/.openhands:/root/.openhands \
    -w /app \
    ${LLM_API_KEY:+-e LLM_API_KEY="$LLM_API_KEY"} \
    ${LLM_MODEL:+-e LLM_MODEL="$LLM_MODEL"} \
    ${LLM_BASE_URL:+-e LLM_BASE_URL="$LLM_BASE_URL"} \
    pent-eam-math-team:latest