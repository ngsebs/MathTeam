# PENTeam
Agentic Loop for Math Investigations

A multi-agent team of specialized AI agents collaborating to investigate mathematical problems. The team operates autonomously with human oversight through a structured research methodology.

## Team Structure

| Agent | Role |
|-------|------|
| **Supervisor** | Orchestrates workflow, monitors projects, delegates tasks, manages Project Owner interactions |
| **Creative Mathematician** | Formulates new theorems, proofs, and mathematical concepts |
| **Senior Mathematician** | Critically reviews theorems with rigor and intellectual openness |
| **Python Coder** | Translates mathematical concepts into executable Python code |
| **Tester** | Validates implementations with rigorous test cases |

## Directory Structure

```
PENTeam/
├── AI/                    # Agent role definitions
│   ├── supervisor.md
│   ├── creative-mathematician.md
│   ├── senior-mathematician.md
│   ├── python-coder.md
│   └── tester.md
├── input/                 # Project descriptions for the team
│   └── [project-name].md
├── output/                # Results from investigations
│   └── [project-name]/
│       ├── summary.md
│       ├── theorems/
│       ├── implementation/
│       ├── tests/
│       └── review/
├── communication/         # Discussion protocols and threads
│   ├── threads/[project]/
│   ├── protocol/
│   └── owner-references/
├── decisions/             # Project Owner approval items
│   ├── pending/
│   ├── approved/
│   └── rejected/
├── docker/               # Docker setup
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── *.sh
├── .openhands/           # OpenHands runtime configuration
│   ├── config.toml       # Runtime settings
│   ├── agents.toml       # Agent definitions
│   └── skills.toml       # Skill mappings
├── .agents/              # Agent skills and definitions
│   ├── AGENTS.md         # Agent registry
│   └── skills/           # Reusable skill files
│       ├── math-theorem.md
│       ├── math-code.md
│       ├── math-testing.md
│       ├── math-review.md
│       └── coordination.md
├── .mcp/                 # MCP server configuration
│   ├── config.json       # Resource definitions
│   └── servers.toml      # Server settings
├── .cursorrules          # Project conventions for AI assistants
├── AGENTS.md             # Persistent agent knowledge
├── README.md
└── LICENSE
```

## How It Works

### 1. Submit a Project
Place a project description in `/input/`:
```bash
cp my-project.md input/
```

The Supervisor will:
- Detect the new project
- Create project directory structure
- Initialize communication thread
- Plan investigation approach

### 2. Team Investigates
The Supervisor delegates work through phases:

1. **Proposal** → Creative Mathematician formulates theorems
2. **Review** → Senior Mathematician critically reviews
3. **Implementation** → Python Coder translates to code
4. **Testing** → Tester validates with comprehensive tests
5. **Integration** → Supervisor summarizes findings

### 3. Project Owner Involvement
Decisions requiring human approval are stored in `/decisions/`:

- Supervisor creates decision records in `pending/`
- Project Owner reviews and approves/rejects
- Approved decisions unlock next steps
- Rejected decisions trigger revision

### 4. Track Progress
Monitor via communication threads:
```bash
# View active discussions
ls communication/threads/

# Check pending decisions
ls decisions/pending/

# Review completed results
ls output/
```

## Quick Start

### Using Docker

```bash
cd docker

# Build image
./build.sh

# Run team
./run.sh

# In another terminal, monitor logs
docker logs -f pent-eam-math-team
```

### Or using Docker Compose

```bash
cd docker
docker-compose up --build
```

## Project Description Format

```markdown
# Project Title

**Problem Statement**: [What needs to be investigated]

**Background/Context**: [Existing knowledge on the topic]

**Goals/Objectives**:
- [Primary goal 1]
- [Primary goal 2]

**Scope**: [What's included/excluded]

**Success Criteria**: [How to measure completion]

**Priority**: [High | Medium | Low]
```

See `input/project-template.md` for a complete template.

## Docker Configuration (macOS)

The agents run inside Docker containers on your MacBook Pro M5, while Ollama runs on the host machine.

### Quick Setup

```bash
# 1. Install and start Ollama on MacBook
brew install ollama
ollama serve

# 2. Pull models (in another terminal)
ollama pull llama3.2:3b      # Mathematicians, supervisor, tester
ollama pull codellama:7b      # Python coder

# 3. Build and run Docker container
cd docker && ./build.sh && ./run.sh
```

### Architecture

- **Host (MacBook M5)**: Ollama at `localhost:11434`
- **Container**: Accesses Ollama via `localhost:11434` (host network mode)
- **No GPU config needed**: Apple Silicon runs inference efficiently on CPU

### Environment Variables

Create `.env` from `.env.example` or export:

```bash
# Ollama (on macOS host - container uses host network mode)
export OLLAMA_HOST=localhost:11434
export OLLAMA_BASE_URL=http://localhost:11434

# Agent-specific models
export SUPERVISOR_MODEL=llama3.2:3b
export PYTHON_CODER_MODEL=codellama:7b
# ... other agent models

# OpenAI fallback (cloud)
export LLM_API_KEY="your-api-key"
export LLM_MODEL="gpt-4"
```

## Self-Sufficient Configuration

The project is self-contained with all necessary agent configurations:

| Directory | Purpose |
|-----------|---------|
| `.openhands/` | OpenHands runtime settings, agent definitions, skill mappings |
| `.agents/` | Reusable skill files for theorem, code, testing, review, coordination |
| `.mcp/` | Model Context Protocol server and resource configuration |
| `.cursorrules` | Project conventions for AI coding assistants |
| `AGENTS.md` | Persistent knowledge base for agent context |

### Key Configuration Files

- `.openhands/config.toml` - LLM settings, workspace paths, permissions
- `.openhands/agents.toml` - Agent registry and team coordination
- `.openhands/skills.toml` - Skill-to-agent mappings
- `.mcp/config.json` - MCP resources and context templates
- `.cursorrules` - Code style and mathematical standards

## Workflow Summary

```
┌─────────────────────────────────────────────────────────┐
│                    Project Owner                         │
│                  (Human in the Loop)                     │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ Submit project description
                      ▼
┌─────────────────────────────────────────────────────────┐
│                      INPUT/                              │
│              [project-description.md]                    │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│                    SUPERVISOR                            │
│         Monitor → Plan → Delegate → Track                │
└───────┬─────────┬─────────┬─────────┬─────────┬─────────┘
        │         │         │         │         │
        ▼         ▼         ▼         ▼         ▼
   ┌─────────┬─────────┬─────────┐ ┌─────────┐ ┌─────────┐
   │Creative │ Senior  │ Python  │ │ Tester  │ │Decision │
   │  Math   │   Math  │  Coder  │ │         │ │  Store  │
   └────┬────┘────┬────┘────┬────┘────┬────┘────┬────┘
        │         │         │         │         │
        ▼         ▼         ▼         ▼         ▼
┌─────────────────────────────────────────────────────────┐
│                      OUTPUT/                             │
│  theorems/  review/  implementation/  tests/  summary.md │
└─────────────────────────────────────────────────────────┘
```

## License

See LICENSE file for details.
