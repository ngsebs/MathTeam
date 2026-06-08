#!/bin/bash
# Build the Docker image for the mathematical research team

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Building Docker image for PENTeam Math Research..."
docker build -f "$SCRIPT_DIR/Dockerfile" -t pent-eam-math-team:latest "$PROJECT_ROOT"

echo ""
echo "Build complete! Run './run.sh' to start the container."