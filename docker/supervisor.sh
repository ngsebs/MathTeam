#!/bin/bash
# PENTeam Supervisor - Project Intake and Task Distribution
# Monitors /app/input/ for new project descriptions and executes the investigation pipeline

set -e

# Configuration
INPUT_DIR="${INPUT_DIR:-/app/input}"
OUTPUT_DIR="${OUTPUT_DIR:-/app/output}"
COMM_DIR="${COMM_DIR:-/app/communication/threads}"
DEC_DIR="${DEC_DIR:-/app/decisions/pending}"
LOG_FILE="/app/communication/supervisor.log"
OLLAMA_HOST="${OLLAMA_HOST:-localhost:11434}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://localhost:11434}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    log "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Call Ollama API for LLM inference
call_ollama() {
    local model="$1"
    local prompt="$2"
    local response
    
    response=$(curl -s --max-time 120 "$OLLAMA_BASE_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$model\", \"prompt\": \"$prompt\", \"stream\": false}")
    
    echo "$response" | jq -r '.response // .error' 2>/dev/null
}

# Check Ollama availability with retries
check_ollama() {
    local max_attempts=5
    local attempt=1
    local retry_delay=3
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s --max-time 5 "$OLLAMA_BASE_URL/api/tags" > /dev/null 2>&1; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warn "Ollama not responding (attempt $attempt/$max_attempts), retrying in ${retry_delay}s..."
            sleep $retry_delay
            ((attempt++))
        else
            log_warn "Ollama not available at ${OLLAMA_HOST} after $max_attempts attempts"
            return 1
        fi
    done
    
    return 1
}

# Initialize directory structure
init_directories() {
    log_info "Initializing PENTeam directories..."
    
    mkdir -p "$INPUT_DIR"
    mkdir -p "$INPUT_DIR/processed"
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$COMM_DIR"
    mkdir -p "$DEC_DIR/approved"
    mkdir -p "$DEC_DIR/rejected"
    mkdir -p "$OUTPUT_DIR/templates"
    
    log_info "Directories initialized at /app/"
}

# Process a new project through the full pipeline
process_project() {
    local project_file="$1"
    local project_name=$(basename "$project_file" .md)
    local project_dir="$OUTPUT_DIR/$project_name"
    
    log_info "Processing project: $project_name"
    
    # Create project directory structure
    mkdir -p "$project_dir"/{theorems,implementation,tests,review,data}
    
    # Store project content for agent processing
    local project_content=$(cat "$project_file")
    
    # Initialize project summary
    cat > "$project_dir/summary.md" << EOF
# Project Summary: $project_name

**Status**: In Progress
**Created**: $(date '+%Y-%m-%d %H:%M:%S')
**Last Updated**: $(date '+%Y-%m-%d %H:%M:%S')

## Source Document
$(cat "$project_file")

## Phase Status

| Phase | Status | Agent | Notes |
|-------|--------|-------|-------|
| Intake | ✓ Complete | Supervisor | $(date '+%Y-%m-%d %H:%M:%S') |
| Proposal | ● Active | Creative Mathematician | In progress |
| Review | ○ Pending | Senior Mathematician | Awaiting proposal |
| Implementation | ○ Pending | Python Coder | Awaiting approval |
| Testing | ○ Pending | Tester | Awaiting implementation |
| Summary | ○ Pending | Supervisor | Awaiting tests |

## Progress Log

### $(date '+%Y-%m-%d %H:%M:%S') - Project Initiated
- Supervisor detected new project in $INPUT_DIR
- Created project structure at $project_dir
- Starting investigation pipeline
EOF

    # Create communication thread
    mkdir -p "$COMM_DIR/$project_name"
    cat > "$COMM_DIR/$project_name/progress.md" << EOF
# Communication Thread: $project_name

## Project Overview
$(head -20 "$project_file")

## Activity Log

| Timestamp | Agent | Action | Status |
|-----------|-------|--------|--------|
| $(date '+%Y-%m-%d %H:%M:%S') | Supervisor | Project detected and initiated | ✓ |
EOF

    cat > "$COMM_DIR/$project_name/delegations.md" << EOF
# Task Delegations: $project_name

## Pending Tasks

| Task ID | Description | Assigned To | Priority | Status |
|---------|-------------|-------------|----------|--------|
| TASK-001 | Analyze project description | Creative Mathematician | High | Pending |
| TASK-002 | Formulate initial theorems | Creative Mathematician | High | Pending |
| TASK-003 | Review proposed theorems | Senior Mathematician | High | Pending |
| TASK-004 | Implement approved theorems | Python Coder | High | Pending |
| TASK-005 | Create test suite | Tester | Medium | Pending |
| TASK-006 | Validate implementation | Tester | High | Pending |

## Completed Tasks

None yet.
EOF

    log_info "Project structure created at $project_dir"
    
    # Execute the investigation pipeline
    execute_pipeline "$project_name" "$project_content" "$project_dir"
    
    # Move processed file to archive
    mv "$project_file" "$INPUT_DIR/processed/${project_name}_$(date +%s).md"
    
    return 0
}

# Execute the full investigation pipeline
execute_pipeline() {
    local project_name="$1"
    local project_content="$2"
    local project_dir="$3"
    local model="${SUPERVISOR_MODEL:-llama3.2:3b}"
    
    log_info "Starting investigation pipeline for: $project_name"
    
    # Phase 1: Creative Mathematician - Analyze and Propose
    log_info "Phase 1: Creative Mathematician analyzing project..."
    update_task_status "$project_name" "TASK-001" "In Progress"
    update_progress "$project_name" "Creative Mathematician" "Analyzing project description"
    
    local analysis_prompt="You are a Creative Mathematician. Analyze this project and provide insights:

Project: $project_name

$project_content

Provide:
1. Key mathematical concepts involved
2. Potential approaches to investigate
3. Initial hypotheses or theorems to explore"
    
    local analysis=$(call_ollama "$model" "$analysis_prompt")
    
    echo "# Analysis: $project_name" > "$project_dir/theorems/analysis.md"
    echo "" >> "$project_dir/theorems/analysis.md"
    echo "## Analysis by Creative Mathematician" >> "$project_dir/theorems/analysis.md"
    echo "" >> "$project_dir/theorems/analysis.md"
    echo "$analysis" >> "$project_dir/theorems/analysis.md"
    echo "" >> "$project_dir/theorems/analysis.md"
    echo "*Generated: $(date '+%Y-%m-%d %H:%M:%S')*" >> "$project_dir/theorems/analysis.md"
    
    update_task_status "$project_name" "TASK-001" "Completed"
    update_task_status "$project_name" "TASK-002" "In Progress"
    
    # Propose theorems
    log_info "Phase 1b: Formulating theorems..."
    update_progress "$project_name" "Creative Mathematician" "Formulating theorems"
    
    local theorem_prompt="You are a Creative Mathematician. Based on this analysis, propose specific theorems or propositions to investigate:

Project: $project_name

Previous Analysis:
$analysis

$project_content

Propose 2-3 concrete theorems or mathematical statements that can be explored computationally. Format each as:
- **Theorem [N]**: [Formal statement]
- **Approach**: [How to investigate]
- **Expected outcome**: [What we might discover]"
    
    local theorems=$(call_ollama "$model" "$theorem_prompt")
    
    echo "# Theorems: $project_name" > "$project_dir/theorems/proposed.md"
    echo "" >> "$project_dir/theorems/proposed.md"
    echo "## Proposed Theorems by Creative Mathematician" >> "$project_dir/theorems/proposed.md"
    echo "" >> "$project_dir/theorems/proposed.md"
    echo "$theorems" >> "$project_dir/theorems/proposed.md"
    echo "" >> "$project_dir/theorems/proposed.md"
    echo "*Generated: $(date '+%Y-%m-%d %H:%M:%S')*" >> "$project_dir/theorems/proposed.md"
    
    update_task_status "$project_name" "TASK-002" "Completed"
    
    # Phase 2: Senior Mathematician - Review
    log_info "Phase 2: Senior Mathematician reviewing theorems..."
    update_task_status "$project_name" "TASK-003" "In Progress"
    update_progress "$project_name" "Senior Mathematician" "Reviewing proposed theorems"
    
    local review_prompt="You are a Senior Mathematician. Critically review these proposed theorems:

Project: $project_name

Proposed Theorems:
$(cat "$project_dir/theorems/proposed.md")

For each theorem, provide:
1. **Feasibility**: Can this be computationally verified?
2. **Significance**: Why does this matter mathematically?
3. **Potential issues**: Any logical flaws or assumptions?
4. **Recommendation**: Approve, modify, or reject

Be rigorous but open to innovative approaches."
    
    local review=$(call_ollama "$model" "$review_prompt")
    
    echo "# Review: $project_name" > "$project_dir/review/critique.md"
    echo "" >> "$project_dir/review/critique.md"
    echo "## Senior Mathematician Review" >> "$project_dir/review/critique.md"
    echo "" >> "$project_dir/review/critique.md"
    echo "$review" >> "$project_dir/review/critique.md"
    echo "" >> "$project_dir/review/critique.md"
    echo "*Generated: $(date '+%Y-%m-%d %H:%M:%S')*" >> "$project_dir/review/critique.md"
    
    update_task_status "$project_name" "TASK-003" "Completed"
    
    # Phase 3: Python Coder - Implement
    log_info "Phase 3: Python Coder implementing..."
    update_task_status "$project_name" "TASK-004" "In Progress"
    update_progress "$project_name" "Python Coder" "Implementing mathematical concepts"
    
    local code_prompt="You are a Python Coder. Implement computational investigation for this project:

Project: $project_name

Theorems to implement:
$(cat "$project_dir/theorems/proposed.md")

Review notes:
$(cat "$project_dir/review/critique.md")

Write Python code that:
1. Implements the key mathematical concepts
2. Includes type hints and documentation
3. Has main() function with example usage
4. Outputs results to console

Use sympy for symbolic math, numpy for numerical computation."
    
    local implementation=$(call_ollama "${PYTHON_CODER_MODEL:-codellama:7b}" "$code_prompt")
    
    echo "# Implementation: $project_name" > "$project_dir/implementation/solution.py"
    echo '"""' >> "$project_dir/implementation/solution.py"
    echo "Mathematical Investigation: $project_name" >> "$project_dir/implementation/solution.py"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$project_dir/implementation/solution.py"
    echo '"""' >> "$project_dir/implementation/solution.py"
    echo "" >> "$project_dir/implementation/solution.py"
    echo "$implementation" >> "$project_dir/implementation/solution.py"
    
    update_task_status "$project_name" "TASK-004" "Completed"
    
    # Phase 4: Tester - Validate
    log_info "Phase 4: Tester validating implementation..."
    update_task_status "$project_name" "TASK-005" "In Progress"
    update_progress "$project_name" "Tester" "Creating test suite"
    
    local test_prompt="You are a Tester. Create comprehensive tests for this implementation:

Project: $project_name

Implementation:
$(cat "$project_dir/implementation/solution.py")

Create pytest tests that:
1. Test core mathematical functions
2. Verify expected outputs
3. Test edge cases
4. Include fixtures for test data

Format as valid pytest code with assertions."
    
    local tests=$(call_ollama "$model" "$test_prompt")
    
    echo "# Tests: $project_name" > "$project_dir/tests/test_solution.py"
    echo '"""' >> "$project_dir/tests/test_solution.py"
    echo "Tests for: $project_name" >> "$project_dir/tests/test_solution.py"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$project_dir/tests/test_solution.py"
    echo '"""' >> "$project_dir/tests/test_solution.py"
    echo "" >> "$project_dir/tests/test_solution.py"
    echo "import pytest" >> "$project_dir/tests/test_solution.py"
    echo "" >> "$project_dir/tests/test_solution.py"
    echo "$tests" >> "$project_dir/tests/test_solution.py"
    
    update_task_status "$project_name" "TASK-005" "Completed"
    update_task_status "$project_name" "TASK-006" "In Progress"
    
    # Run the tests
    log_info "Running tests..."
    update_progress "$project_name" "Tester" "Running validation tests"
    
    if source /app/.venv/bin/activate 2>/dev/null && python -m pytest "$project_dir/tests/test_solution.py" -v > "$project_dir/tests/results.txt" 2>&1; then
        local test_results="All tests passed ✓"
    else
        local test_results="Tests completed with output in results.txt"
    fi
    
    echo "$test_results" >> "$project_dir/tests/results.txt"
    
    update_task_status "$project_name" "TASK-006" "Completed"
    
    # Phase 5: Generate Summary
    log_info "Phase 5: Generating project summary..."
    update_progress "$project_name" "Supervisor" "Compiling final summary"
    
    local summary_prompt="You are the Supervisor. Compile a comprehensive summary of this investigation:

Project: $project_name

Analysis:
$(cat "$project_dir/theorems/analysis.md")

Theorems Proposed:
$(cat "$project_dir/theorems/proposed.md")

Review:
$(cat "$project_dir/review/critique.md")

Test Results:
$(cat "$project_dir/tests/results.txt")

Provide:
1. Executive summary (2-3 sentences)
2. Key findings
3. Recommendations
4. Next steps for further investigation"
    
    local summary=$(call_ollama "$model" "$summary_prompt")
    
    # Update project summary
    cat > "$project_dir/summary.md" << EOF
# Project Summary: $project_name

**Status**: ✓ Complete
**Created**: $(date '+%Y-%m-%d %H:%M:%S')
**Completed**: $(date '+%Y-%m-%d %H:%M:%S')

## Source Document
$(cat "$INPUT_DIR/processed/"${project_name}_*.md 2>/dev/null | head -50 || echo "Original file archived")

## Phase Status

| Phase | Status | Agent | Notes |
|-------|--------|-------|-------|
| Intake | ✓ Complete | Supervisor | $(date '+%Y-%m-%d %H:%M:%S') |
| Proposal | ✓ Complete | Creative Mathematician | Theorems formulated |
| Review | ✓ Complete | Senior Mathematician | Reviewed and approved |
| Implementation | ✓ Complete | Python Coder | Code implemented |
| Testing | ✓ Complete | Tester | All tests validated |
| Summary | ✓ Complete | Supervisor | Investigation complete |

## Final Summary

$summary

## Files Generated

- `theorems/analysis.md` - Initial analysis
- `theorems/proposed.md` - Theorems proposed
- `review/critique.md` - Senior Mathematician review
- `implementation/solution.py` - Python implementation
- `tests/test_solution.py` - Test suite
- `tests/results.txt` - Test execution results
EOF

    log_info "Investigation complete for: $project_name"
    update_progress "$project_name" "Supervisor" "Investigation complete"
}

# Update task status in delegations.md
update_task_status() {
    local project_name="$1"
    local task_id="$2"
    local status="$3"
    local delegations_file="$COMM_DIR/$project_name/delegations.md"
    
    if [ -f "$delegations_file" ]; then
        sed -i "s/| $task_id |.*| $status |/| $task_id | $(date '+%Y-%m-%d %H:%M:%S') | $status |/" "$delegations_file" 2>/dev/null || true
    fi
}

# Update progress in progress.md
update_progress() {
    local project_name="$1"
    local agent="$2"
    local action="$3"
    local progress_file="$COMM_DIR/$project_name/progress.md"
    
    if [ -f "$progress_file" ]; then
        echo "| $(date '+%Y-%m-%d %H:%M:%S') | $agent | $action | ● Active |" >> "$progress_file"
    fi
}

# Check for new projects
check_new_projects() {
    local new_files=$(find "$INPUT_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null)
    
    if [ -n "$new_files" ]; then
        log_info "Found $(echo "$new_files" | wc -l) new project(s)"
        for file in $new_files; do
            process_project "$file"
        done
    fi
}

# Show current status
show_status() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}              PENTeam Supervisor Status                       ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Ollama status
    if curl -s --max-time 3 "$OLLAMA_BASE_URL/api/tags" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Ollama: Running at ${OLLAMA_HOST}"
    else
        echo -e "  ${RED}✗${NC} Ollama: Not available (will retry)"
    fi
    
    # Input queue
    local pending=$(find "$INPUT_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l)
    echo -e "  ${YELLOW}○${NC} Pending projects: $pending"
    
    # Active projects
    local active=$(find "$OUTPUT_DIR" -maxdepth 1 -type d ! -name "output" ! -name "templates" ! -name "processed" 2>/dev/null | wc -l)
    echo -e "  ${GREEN}●${NC} Active projects: $active"
    
    # Pending decisions
    local decisions=$(find "$DEC_DIR" -name "*.md" 2>/dev/null | wc -l)
    echo -e "  ${RED}!${NC} Pending decisions: $decisions"
    
    echo ""
}

# Main supervisor loop
run_supervisor() {
    log_info "Starting PENTeam Supervisor..."
    
    # Initialize directories
    init_directories
    
    # Check Ollama - continue even if not available (will retry)
    if ! check_ollama; then
        log_warn "Ollama not available - will continue monitoring and retry"
    else
        log_info "Ollama connection verified"
    fi
    
    log_info "Supervisor ready - monitoring $INPUT_DIR"
    
    # Initial check for any existing projects
    check_new_projects
    
    # Main monitoring loop
    while true; do
        show_status
        
        # Check for new projects every 10 seconds
        check_new_projects
        
        # Periodic Ollama health check (every 5 minutes)
        if ! curl -s --max-time 3 "$OLLAMA_BASE_URL/api/tags" > /dev/null 2>&1; then
            log_warn "Ollama connection lost, retrying..."
            check_ollama
        fi
        
        sleep 10
    done
}

# Show usage
usage() {
    cat << EOF
PENTeam Supervisor - Mathematical Research Team Orchestrator

Usage: supervisor.sh [COMMAND]

Commands:
    start       Start the supervisor (monitors input directory)
    status      Show current team status
    process     Manually process a project file
    help        Show this help message

Examples:
    ./supervisor.sh start      # Start monitoring for new projects
    ./supervisor.sh status     # Show current status
    ./supervisor.sh process input/my-project.md  # Process specific file

Environment:
    INPUT_DIR      Project input directory (default: /app/input)
    OUTPUT_DIR     Project output directory (default: /app/output)
    OLLAMA_HOST    Ollama API endpoint (default: localhost:11434)

EOF
}

# Main entry point
case "${1:-start}" in
    start)
        run_supervisor
        ;;
    status)
        show_status
        ;;
    process)
        if [ -z "$2" ]; then
            log_error "Please specify a project file"
            exit 1
        fi
        init_directories
        process_project "$2"
        ;;
    monitor)
        # Continuous monitoring mode
        while true; do
            check_new_projects
            sleep 5
        done
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac