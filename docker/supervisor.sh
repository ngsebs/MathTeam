#!/bin/bash
# PENTeam Supervisor - Project Intake and Task Distribution
# Monitors /app/input/ for new project descriptions and initiates investigation

set -e

# Configuration
INPUT_DIR="/app/input"
OUTPUT_DIR="/app/output"
COMM_DIR="/app/communication/threads"
DEC_DIR="/app/decisions/pending"
LOG_FILE="/app/communication/supervisor.log"

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

# Check Ollama availability
check_ollama() {
    curl -s --max-time 5 "http://localhost:11434/api/tags" > /dev/null 2>&1
}

# Initialize directory structure
init_directories() {
    log_info "Initializing PENTeam directories..."
    
    mkdir -p "$INPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$COMM_DIR"
    mkdir -p "$DEC_DIR/approved"
    mkdir -p "$DEC_DIR/rejected"
    mkdir -p "$OUTPUT_DIR/templates"
    
    log_info "Directories initialized at /app/"
}

# Process a new project
process_project() {
    local project_file="$1"
    local project_name=$(basename "$project_file" .md)
    local project_dir="$OUTPUT_DIR/$project_name"
    
    log_info "Processing project: $project_name"
    
    # Create project directory structure
    mkdir -p "$project_dir"/{theorems,implementation,tests,review,data}
    
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
| Proposal | ○ Pending | Creative Mathematician | Awaiting initiation |
| Review | ○ Pending | Senior Mathematician | Awaiting proposal |
| Implementation | ○ Pending | Python Coder | Awaiting approval |
| Testing | ○ Pending | Tester | Awaiting implementation |
| Summary | ○ Pending | Supervisor | Awaiting tests |

## Progress Log

### $(date '+%Y-%m-%d %H:%M:%S') - Project Initiated
- Supervisor detected new project in $INPUT_DIR
- Created project structure at $project_dir
- Project is ready for investigation pipeline
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
    log_info "Communication thread initialized at $COMM_DIR/$project_name"
    
    # Move processed file to archive
    mkdir -p "$INPUT_DIR/processed"
    mv "$project_file" "$INPUT_DIR/processed/${project_name}_$(date +%s).md"
    
    return 0
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
    if check_ollama; then
        echo -e "  ${GREEN}✓${NC} Ollama: Running at localhost:11434"
    else
        echo -e "  ${RED}✗${NC} Ollama: Not available"
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
    
    # Check Ollama before starting
    if ! check_ollama; then
        log_error "Ollama not available at localhost:11434"
        log_error "Please start Ollama: ollama serve"
        exit 1
    fi
    
    log_info "Ollama connection verified"
    log_info "Supervisor ready - monitoring $INPUT_DIR"
    
    # Initial check for any existing projects
    check_new_projects
    
    # Main monitoring loop
    while true; do
        show_status
        
        # Check for new projects every 10 seconds
        check_new_projects
        
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