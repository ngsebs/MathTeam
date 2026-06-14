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
│   ├── pending/[project]/    # Decision files awaiting Project Owner
│   ├── approved/[project]/   # Approved decisions (moved after processing)
│   └── rejected/[project]/   # Rejected decisions (moved after processing)
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
The Supervisor delegates work through phases with built-in feedback loops:

1. **Proposal** → Creative Mathematician formulates theorems
2. **Review** → Senior Mathematician critically reviews (with iteration loop)
3. **Decision** → Project Owner decides on computationally challenging theorems
4. **Implementation** → Python Coder translates approved theorems to code
5. **Testing** → Tester validates with comprehensive tests
6. **Integration** → Supervisor summarizes findings

#### Feedback Loops

The workflow includes three important feedback mechanisms:

**Mathematician Feedback Loop**
- Senior Mathematician may reject theorems (max 3 iterations)
- Rejected theorems return to Creative Mathematician with feedback
- Only approved theorems proceed to implementation

**Tester Fix Loop** ⭐ NEW
- Tester creates tests and runs them against implementation
- If tests fail, Python Coder receives error details automatically
- Python Coder fixes implementation and tests are re-run
- Loop continues until tests pass or max iterations (3) reached
- If max iterations reached, manual intervention is flagged
- This ensures code quality before proceeding to summary

**Project Owner Escalation**
- When theorems are mathematically valid but computationally infeasible
- Project Owner chooses: Skip / Approximate / Theoretical Reference
- Decision stored in `/decisions/pending/[project]/`

**Next Steps Escalation (Phase 5.5)**
- When summary contains proposed next steps or further investigation
- Project Owner decides: Continue / Document / End
- Use `/app/docker/decide.sh` for interactive decision-making
- Decision triggers automatic continuation or documentation
- Optional custom instructions can guide the continuation project

### 3. Project Owner Involvement
Decisions requiring human approval are stored in `/decisions/`:

- Supervisor creates decision records in `pending/[project]/`
- Project Owner reviews and adds their decision
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

### 5. Make Decisions (Project Owner)

When the supervisor creates a decision file in `/decisions/pending/[project]/`, use the decision dialog:

```bash
# Inside container
/app/docker/decide.sh

# From host
docker exec pent-eam-math-team /app/docker/decide.sh
```

The dialog will:
1. List pending decisions by project
2. Allow selection by number or name
3. Show available options based on decision type
4. Accept signature and optional notes/prompts
5. Move processed decisions to `/decisions/approved/` or `/decisions/rejected/`

## Quick Start

### Using Docker

```bash
cd docker

# Build image (first time only)
./build.sh

# Run team (starts supervisor - monitors input/)
./run.sh

# Run in interactive mode (bash shell)
./run.sh interactive

# Run monitoring dashboard
./run.sh monitor

# In another terminal, monitor logs
docker logs -f pent-eam-math-team
```

### Inside the Container

```bash
# Activate virtual environment
source /app/.venv/bin/activate

# Run debug analysis
/app/docker/debug.sh

# Run OpenHands agent
/app/docker/openhands.sh

# Run supervisor manually
/app/docker/supervisor.sh start

# Check team status
/app/docker/monitor.sh

# View debug logs (LLM interaction tracing)
/app/docker/monitor.sh

# View LLM debug log (detailed API calls)
cat /app/communication/debug.log
```

### Debug Logging

Debug logging is **enabled by default** to help troubleshoot LLM interactions. The debug log is written to `/app/communication/debug.log`.

**What it logs:**
- Model used and prompt length
- Escaped prompt (JSON-encoded)
- Raw response from Ollama
- Extracted response length
- File write operations

**To disable debug logging:**
```bash
DEBUG_LOG=false docker-compose up
```

**To view debug log:**
```bash
# Inside container
cat /app/communication/debug.log

# From host
docker exec pent-eam-math-team cat /app/communication/debug.log
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
   └────┬────┘────┬────┘────┬────┘─────────┘─────────────┘
        │         │
        │         │◄──── REJECT? (max 3 iterations)
        │         │
        │    APPROVED
        │         │
        ▼         ▼
   ┌────────────────────────────────────────────────────┐
   │            PROJECT OWNER DECISION                   │
   │  (if mathematically sound but computationally      │
   │   challenging)                                      │
   └──────────────┬─────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────┐
│                      OUTPUT/                             │
│  theorems/  review/  implementation/  tests/  summary.md │
└─────────────────────────────────────────────────────────┘
```

### Investigation Pipeline Detail

```
1. Creative Mathematician proposes theorems
         │
         ▼
2. Senior Mathematician reviews
         │
         ├─► APPROVED ─────────────────────┐
         │                                   │
         └─► REJECTED ─► Revise (loop 1-3) ─┘
         │
         ▼
3. Project Owner Decision (if needed)
   - Skip / Approximate / Theoretical Reference
         │
         ▼
4. Python Coder implements approved theorems
         │
         ▼
5. Tester creates and runs tests
         │
         ├─► PASSED ──────────────────────┐
         │                                  │
         └─► FAILED ─► Fix (loop 1-3) ─────┘
         │
         ▼
6. Supervisor compiles final summary
```

## License

See LICENSE file for details.
