# Docker Setup for PENTeam Math Research Team

This directory contains Docker configuration and helper scripts for running the mathematical research team in a containerized environment.

## Quick Start

```bash
# Build the Docker image
./build.sh

# Run the team
./run.sh

# In another terminal, attach to logs
docker logs -f pent-eam-math-team
```

## Contents

| File | Description |
|------|-------------|
| `Dockerfile` | Container image definition with Python and OpenHands |
| `docker-compose.yml` | Multi-service orchestration (optional) |
| `build.sh` | Build the Docker image |
| `run.sh` | Start an interactive container session |
| `stop.sh` | Stop and remove the container |
| `README.md` | This documentation |

## Prerequisites

- Docker installed and running
- LLM API key (see Configuration)

## Configuration

Create a `.env` file in the project root (or export variables directly):

```bash
# Required for LLM access
export LLM_API_KEY="your-api-key-here"

# Optional: Override default model
export LLM_MODEL="anthropic/claude-sonnet-4-5-20250929"

# Optional: Custom API base URL
export LLM_BASE_URL="https://api.anthropic.com"
```

## Team Agents

The Docker container includes the following specialized agents:

| Agent | Role |
|-------|------|
| `supervisor` | Orchestrates workflow between team members |
| `creative-mathematician` | Formulates new theorems and proofs |
| `senior-mathematician` | Critical but open-minded reviewer |
| `python-coder` | Implements mathematical concepts in Python |
| `tester` | Validates implementations with rigorous tests |

## Using Docker Compose

For a more declarative setup:

```bash
cd docker
docker-compose up --build
```

## Volume Mounts

The container mounts:
- `./AI` → `/app/AI` (read-only) — Team agent configurations
- `./workdir` → `/app/workdir` — Working directory for outputs
- `~/.openhands` → `/root/.openhands` — OpenHands persistence

## Troubleshooting

### Container won't start
- Ensure Docker daemon is running: `docker info`
- Check port conflicts: `docker ps`

### LLM API errors
- Verify `LLM_API_KEY` is set correctly
- Check network connectivity from container

### Permission issues
- Ensure your user has Docker permissions (add to `docker` group)
- Check volume mount permissions