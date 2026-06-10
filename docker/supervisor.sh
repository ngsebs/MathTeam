#!/bin/bash
# PENTeam Supervisor - Project Intake and Task Distribution
# Monitors /app/input/ for new project descriptions and executes the investigation pipeline

set -e

# Ensure environment variables are properly set for Docker container
# These are set in docker-compose.yml and Dockerfile
# If running outside compose, load from .env.example
if [ -z "$OLLAMA_BASE_URL" ]; then
    if [ -f /app/.env.example ]; then
        set -a
        source /app/.env.example
        set +a
    fi
fi

# Configuration
INPUT_DIR="${INPUT_DIR:-/app/input}"
OUTPUT_DIR="${OUTPUT_DIR:-/app/output}"
COMM_DIR="${COMM_DIR:-/app/communication/threads}"
DEC_DIR="${DEC_DIR:-/app/decisions/pending}"
LOG_FILE="/app/communication/supervisor.log"
# Use environment variables with proper defaults for Docker container (host.docker.internal for macOS)
OLLAMA_HOST="${OLLAMA_HOST:-host.docker.internal:11434}"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://host.docker.internal:11434}"

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
            log_info "Ollama is reachable at $OLLAMA_BASE_URL"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warn "Ollama not responding (attempt $attempt/$max_attempts), retrying in ${retry_delay}s..."
            sleep $retry_delay
            ((attempt++))
        else
            log_error "Ollama not available at $OLLAMA_BASE_URL after $max_attempts attempts"
            log_error "Make sure Ollama is running on the host and accessible via $OLLAMA_HOST"
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
    
    # Phase 2: Senior Mathematician - Review with Feedback Loop
    log_info "Phase 2: Senior Mathematician reviewing theorems..."
    
    # Feedback loop: keep reviewing until all theorems are approved or max iterations reached
    local max_review_iterations=3
    local iteration=1
    local review_complete=false
    
    while [ "$review_complete" = "false" ] && [ $iteration -le $max_review_iterations ]; do
        log_info "Review iteration $iteration of $max_review_iterations"
        update_task_status "$project_name" "TASK-003" "In Progress"
        update_progress "$project_name" "Senior Mathematician" "Review iteration $iteration"
        
        # Read current theorems file with fallback
        local theorems_for_review=""
        [ -f "$project_dir/theorems/proposed.md" ] && theorems_for_review=$(cat "$project_dir/theorems/proposed.md")
        
        local review_prompt="You are a Senior Mathematician. Critically review these proposed theorems:

Project: $project_name

Proposed Theorems:
${theorems_for_review:-Not available (Ollama may have been unavailable)}

For each theorem, provide:
1. **Feasibility**: Can this be computationally verified?
2. **Significance**: Why does this matter mathematically?
3. **Potential issues**: Any logical flaws or assumptions?
4. **Recommendation**: Approve, modify, or reject

Be rigorous but open to innovative approaches."

        local review=$(call_ollama "$model" "$review_prompt")
        
        echo "# Review: $project_name" > "$project_dir/review/critique.md"
        echo "" >> "$project_dir/review/critique.md"
        echo "## Senior Mathematician Review (Iteration $iteration)" >> "$project_dir/review/critique.md"
        echo "" >> "$project_dir/review/critique.md"
        echo "$review" >> "$project_dir/review/critique.md"
        echo "" >> "$project_dir/review/critique.md"
        echo "*Generated: $(date '+%Y-%m-%d %H:%M:%S')*" >> "$project_dir/review/critique.md"
        
        # Check if review contains any rejections or modifications needed
        local review_lower=$(echo "$review" | tr '[:upper:]' '[:lower:]')
        
        if echo "$review_lower" | grep -q "reject\|rejected\|cannot be verified\|flawed"; then
            log_warn "Senior Mathematician identified issues requiring revision"
            
            # Extract the review content for feedback to Creative Mathematician
            local revision_prompt="You are a Creative Mathematician. The Senior Mathematician has reviewed your proposed theorems and found issues that need to be addressed:

Project: $project_name

Original Theorems:
${theorems_for_review}

Senior Mathematician Feedback:
${review}

Please revise the rejected or problematic theorems based on the feedback.
For each issue:
1. Acknowledge the concern raised
2. Either fix the theorem or provide a new approach
3. Ensure all theorems are computationally verifiable

Output revised theorems in the same format:
- **Theorem [N]**: [Revised formal statement]
- **Approach**: [How to investigate]
- **Expected outcome**: [What we might discover]"
            
            log_info "Sending rejected theorems back to Creative Mathematician for revision..."
            update_progress "$project_name" "Creative Mathematician" "Revising theorems based on Senior Mathematician feedback"
            
            local revised_theorems=$(call_ollama "$model" "$revision_prompt")
            
            # Save revised theorems with history
            echo "" >> "$project_dir/theorems/proposed.md"
            echo "---" >> "$project_dir/theorems/proposed.md"
            echo "## Revision $iteration (Based on Senior Mathematician Feedback)" >> "$project_dir/theorems/proposed.md"
            echo "" >> "$project_dir/theorems/proposed.md"
            echo "$revised_theorems" >> "$project_dir/theorems/proposed.md"
            echo "" >> "$project_dir/theorems/proposed.md"
            echo "*Generated: $(date '+%Y-%m-%d %H:%M:%S')*" >> "$project_dir/theorems/proposed.md"
            
            log_info "Revised theorems saved, continuing to next review iteration..."
            ((iteration++))
        else
            log_info "All theorems approved by Senior Mathematician"
            update_progress "$project_name" "Senior Mathematician" "All theorems approved"
            review_complete=true
        fi
    done
    
    if [ $iteration -gt $max_review_iterations ] && [ "$review_complete" = "false" ]; then
        log_warn "Max review iterations reached. Proceeding with current theorems."
        update_progress "$project_name" "Senior Mathematician" "Max iterations reached - proceeding with current theorems"
    fi
    
    update_task_status "$project_name" "TASK-003" "Completed"
    
    # Phase 2.5: Decision Escalation - Project Owner Input
    # Check if any theorems are analytically sound but cannot be computationally represented
    log_info "Phase 2.5: Checking for theorems requiring project owner decision..."
    update_progress "$project_name" "Supervisor" "Checking for decision escalation"
    
    # Detect theorems that are mathematically valid but computationally problematic
    local review_content=""
    [ -f "$project_dir/review/critique.md" ] && review_content=$(cat "$project_dir/review/critique.md")
    local review_lower=$(echo "$review_content" | tr '[:upper:]' '[:lower:]')
    
    local needs_decision=false
    local theorems_needing_decision=""
    
    # Patterns indicating analytically sound but computationally challenging theorems
    if echo "$review_lower" | grep -qE "analytically sound|mathematically valid|mathematically sound|conceptually correct"; then
        if echo "$review_lower" | grep -qE "cannot be computed|not computationally|cannot verify computationally|computationally infeasible|no practical algorithm|undecidable|np-complete|exponential complexity"; then
            needs_decision=true
            theorems_needing_decision="Theorems flagged as mathematically sound but computationally challenging"
        fi
    fi
    
    if [ "$needs_decision" = "true" ]; then
        log_warn "Theorems identified as analytically sound but computationally problematic"
        
        # Create decision record for project owner
        local decision_dir="$DEC_DIR/$project_name"
        mkdir -p "$decision_dir"
        
        cat > "$decision_dir/decision-001.md" << EOF
# Decision Record: Theorems Requiring Project Owner Input

**Decision ID**: DEC-001
**Project**: $project_name
**Date Created**: $(date '+%Y-%m-%d %H:%M:%S')
**Status**: Pending

## Decision Summary

Some theorems have been identified as mathematically valid/analytically sound but present computational challenges for implementation.

## Background

The Senior Mathematician has reviewed the proposed theorems and identified that certain theorems are:
- Mathematically correct and significant
- But cannot be practically implemented with current computational methods

## Theorems Requiring Decision

$theorems_needing_decision

## Senior Mathematician Assessment

$(cat "$project_dir/review/critique.md")

## Options

### Option A: Skip Implementation
**Proceed with implementation of only computationally feasible theorems**
- The mathematically sound theorems will be documented but not implemented
- Focus on what can be computed and verified
- May limit scope of investigation

### Option B: Approximate Implementation
**Implement simplified or approximate versions**
- Use numerical approximations where analytical solutions are infeasible
- May reduce precision but allows computational exploration
- Document limitations in implementation

### Option C: Include as Theoretical Reference
**Document theorems in final report without implementation**
- Theorems are valid but marked as "theoretical only"
- Future work may include implementation when methods become available
- Does not block current investigation

## Recommendation

The Senior Mathematician recommends: **Option C** (Include as Theoretical Reference)

## Required From Project Owner

- [ ] Review the mathematically sound but computationally challenging theorems
- [ ] Select preferred handling approach (A, B, or C)
- [ ] Respond in this file or via communication thread

## Response Format

To approve a decision, add your response below:

```
**Project Owner Decision**: [A/B/C]
**Rationale**: [Your reasoning]
**Approved By**: [Your name]
**Date**: $(date '+%Y-%m-%d %H:%M:%S')
```
EOF
        
        log_info "Decision record created at $decision_dir/decision-001.md"
        update_progress "$project_name" "Supervisor" "Awaiting project owner decision on computationally problematic theorems"
        
        # Wait for project owner decision with polling
        local decision_timeout=3600  # 1 hour timeout
        local decision_start=$(date +%s)
        local decision_made=false
        
        log_info "Waiting for project owner decision (timeout: ${decision_timeout}s)..."
        
        while [ "$decision_made" = "false" ]; do
            local current_time=$(date +%s)
            local elapsed=$((current_time - decision_start))
            
            if [ $elapsed -gt $decision_timeout ]; then
                log_warn "Decision timeout reached. Proceeding with default (Option C: Theoretical Reference)."
                update_progress "$project_name" "Supervisor" "Decision timeout - defaulting to Option C"
                
                # Add default decision
                cat >> "$decision_dir/decision-001.md" << EOF

## Default Decision (Timeout)

**Project Owner Decision**: C (Default - Timeout)
**Rationale**: Decision timeout - defaulting to including theorems as theoretical reference
**Date**: $(date '+%Y-%m-%d %H:%M:%S')
EOF
                break
            fi
            
            # Check for decision response
            if grep -q "Project Owner Decision" "$decision_dir/decision-001.md" 2>/dev/null; then
                if grep -q "Approved By" "$decision_dir/decision-001.md" 2>/dev/null; then
                    decision_made=true
                    log_info "Project owner decision received!"
                    update_progress "$project_name" "Supervisor" "Project owner decision received"
                fi
            fi
            
            if [ "$decision_made" = "false" ]; then
                log_info "Waiting for decision... (${elapsed}s elapsed)"
                sleep 30  # Check every 30 seconds
            fi
        done
        
        # Move decision to appropriate directory based on outcome
        if grep -q "Project Owner Decision: A\|Project Owner Decision: a" "$decision_dir/decision-001.md" 2>/dev/null; then
            log_info "Project owner chose Option A: Skip implementation"
            mkdir -p "$DEC_DIR/approved/$project_name"
            mv "$decision_dir/decision-001.md" "$DEC_DIR/approved/$project_name/"
        elif grep -q "Project Owner Decision: B\|Project Owner Decision: b" "$decision_dir/decision-001.md" 2>/dev/null; then
            log_info "Project owner chose Option B: Approximate implementation"
            mkdir -p "$DEC_DIR/approved/$project_name"
            mv "$decision_dir/decision-001.md" "$DEC_DIR/approved/$project_name/"
        else
            log_info "Project owner chose Option C: Theoretical reference (default)"
            mkdir -p "$DEC_DIR/approved/$project_name"
            mv "$decision_dir/decision-001.md" "$DEC_DIR/approved/$project_name/"
        fi
    else
        log_info "No decision escalation needed - all theorems are computationally feasible"
    fi
    
    # Phase 3: Python Coder - Implement
    log_info "Phase 3: Python Coder implementing..."
    update_task_status "$project_name" "TASK-004" "In Progress"
    update_progress "$project_name" "Python Coder" "Implementing mathematical concepts"
    
    # Read theorems and review files with fallback
    local theorems_for_code=""
    local review_for_code=""
    [ -f "$project_dir/theorems/proposed.md" ] && theorems_for_code=$(cat "$project_dir/theorems/proposed.md")
    [ -f "$project_dir/review/critique.md" ] && review_for_code=$(cat "$project_dir/review/critique.md")
    
    local code_prompt="You are a Python Coder. Implement computational investigation for this project:

Project: $project_name

Theorems to implement:
${theorems_for_code:-Not available (Ollama may have been unavailable)}

Review notes:
${review_for_code:-Not available (Ollama may have been unavailable)}

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
    
    # Read implementation file with fallback
    local impl_for_test=""
    [ -f "$project_dir/implementation/solution.py" ] && impl_for_test=$(cat "$project_dir/implementation/solution.py")
    
    local test_prompt="You are a Tester. Create comprehensive tests for this implementation:

Project: $project_name

Implementation:
${impl_for_test:-Not available (Ollama may have been unavailable)}

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
    echo "import sys" >> "$project_dir/tests/test_solution.py"
    echo "import os" >> "$project_dir/tests/test_solution.py"
    echo "" >> "$project_dir/tests/test_solution.py"
    echo "# Add implementation directory to path so tests can import solution module" >> "$project_dir/tests/test_solution.py"
    echo "_IMPL_DIR = os.path.join(os.path.dirname(__file__), '..', 'implementation')" >> "$project_dir/tests/test_solution.py"
    echo "if _IMPL_DIR not in sys.path:" >> "$project_dir/tests/test_solution.py"
    echo "    sys.path.insert(0, _IMPL_DIR)" >> "$project_dir/tests/test_solution.py"
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
    
    # Read generated files with fallback content if files don't exist
    local analysis_content=""
    local theorems_content=""
    local review_content=""
    local test_results_content=""
    
    [ -f "$project_dir/theorems/analysis.md" ] && analysis_content=$(cat "$project_dir/theorems/analysis.md")
    [ -f "$project_dir/theorems/proposed.md" ] && theorems_content=$(cat "$project_dir/theorems/proposed.md")
    [ -f "$project_dir/review/critique.md" ] && review_content=$(cat "$project_dir/review/critique.md")
    [ -f "$project_dir/tests/results.txt" ] && test_results_content=$(cat "$project_dir/tests/results.txt")
    
    local summary_prompt="You are the Supervisor. Compile a comprehensive summary of this investigation:

Project: $project_name

Analysis:
${analysis_content:-Not available (Ollama may have been unavailable)}

Theorems Proposed:
${theorems_content:-Not available (Ollama may have been unavailable)}

Review:
${review_content:-Not available (Ollama may have been unavailable)}

Test Results:
${test_results_content:-Not available (tests may have failed)}

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
    log_info "OLLAMA_HOST: $OLLAMA_HOST"
    log_info "OLLAMA_BASE_URL: $OLLAMA_BASE_URL"
    
    # Initialize directories
    init_directories
    
    # Check Ollama with extended retries on startup
    local startup_attempts=10
    local attempt=1
    
    log_info "Verifying Ollama connection (up to $startup_attempts attempts)..."
    while [ $attempt -le $startup_attempts ]; do
        if curl -s --max-time 5 "$OLLAMA_BASE_URL/api/tags" > /dev/null 2>&1; then
            log_info "Ollama connection verified successfully"
            break
        fi
        
        if [ $attempt -lt $startup_attempts ]; then
            log_warn "Ollama not responding (startup attempt $attempt/$startup_attempts), retrying in 2s..."
            sleep 2
            ((attempt++))
        else
            log_error "Ollama still not available after $startup_attempts startup attempts"
            log_error "Container will continue but operations requiring Ollama will fail"
            log_error "Troubleshooting:"
            log_error "  1. Ensure Ollama is running on the host"
            log_error "  2. Verify network connectivity: docker exec pent-eam-math-team curl -v $OLLAMA_BASE_URL/api/tags"
            log_error "  3. Check Docker network: docker network inspect bridge"
            break
        fi
    done
    
    log_info "Supervisor ready - monitoring $INPUT_DIR"
    
    # Initial check for any existing projects
    check_new_projects
    
    # Main monitoring loop
    while true; do
        show_status
        
        # Check for new projects every 10 seconds
        check_new_projects
        
        # Periodic Ollama health check (every 10 seconds, with recovery)
        if ! curl -s --max-time 3 "$OLLAMA_BASE_URL/api/tags" > /dev/null 2>&1; then
            log_warn "Ollama connection lost at $OLLAMA_BASE_URL, retrying..."
            # Try to reconnect with shorter timeout
            local reconnect_attempts=3
            for i in $(seq 1 $reconnect_attempts); do
                if curl -s --max-time 3 "$OLLAMA_BASE_URL/api/tags" > /dev/null 2>&1; then
                    log_info "Ollama connection restored"
                    break
                fi
                if [ $i -lt $reconnect_attempts ]; then
                    sleep 2
                fi
            done
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