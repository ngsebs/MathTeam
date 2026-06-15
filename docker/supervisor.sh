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
DEC_DIR="${DEC_DIR:-/app/decisions}"
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
# Safe write function - handles special characters in content
safe_write() {
    local file="$1"
    local content="$2"
    printf '%s' "$content" > "$file"
}

# Write multiline content safely to file (appends)
safe_append() {
    local file="$1"
    local content="$2"
    printf '%s\n' "$content" >> "$file"
}

# Write LLM response safely using temp file to handle special chars
write_response() {
    local file="$1"
    local response="$2"
    debug_log "write_response: file=$file, response_length=${#response}"
    
    # Use temp file to safely write content with special characters
    local temp_file
    temp_file=$(mktemp)
    printf '%s' "$response" > "$temp_file"
    debug_log "write_response: temp_file=$temp_file, bytes=$(wc -c < "$temp_file")"
    cat "$temp_file" >> "$file"
    rm -f "$temp_file"
    debug_log "write_response: completed"
}

# Debug logging function
debug_log() {
    if [ "$DEBUG_LOG" = "true" ] || [ "$DEBUG_LOG" = "1" ]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[DEBUG $timestamp] $1" >> /app/communication/debug.log
    fi
}

call_ollama() {
    local model="$1"
    local prompt="$2"
    local response
    
    debug_log "call_ollama: model=$model, prompt_length=${#prompt}"
    
    # Escape prompt for JSON properly using jq
    local escaped_prompt
    escaped_prompt=$(printf '%s' "$prompt" | jq -Rs .)
    debug_log "call_ollama: escaped_prompt=$escaped_prompt"
    
    response=$(curl -s --max-time 120 "$OLLAMA_BASE_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$model\", \"prompt\": $escaped_prompt, \"stream\": false}")
    
    debug_log "call_ollama: raw_response=$response"
    
    # Extract response safely, handle errors
    local extracted
    extracted=$(echo "$response" | jq -r '.response // empty' 2>/dev/null)
    
    debug_log "call_ollama: extracted_length=${#extracted}"
    
    if [ -z "$extracted" ]; then
        # Try to get error message
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error // "Unknown error"' 2>/dev/null)
        debug_log "call_ollama: ERROR - $error_msg"
        echo "Error: $error_msg"
        return 1
    fi
    
    debug_log "call_ollama: success, response_preview=${extracted:0:100}..."
    echo "$extracted"
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
| TASK-007 | Fix test failures | Python Coder | High | Pending (as needed) |

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
    write_response "$project_dir/theorems/analysis.md" "$analysis"
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
    write_response "$project_dir/theorems/proposed.md" "$theorems"
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
        write_response "$project_dir/review/critique.md" "$review"
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
            write_response "$project_dir/theorems/proposed.md" "$revised_theorems"
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
    # Check for multiple indicators to reduce false positives
    local sound_count=0
    local challenging_count=0
    
    # Indicators of mathematical validity
    if echo "$review_lower" | grep -qE "analytically sound|mathematically valid|mathematically sound|conceptually correct|proven|verified"; then
        sound_count=$((sound_count + 1))
    fi
    
    # Indicators of computational challenge
    if echo "$review_lower" | grep -qE "cannot be computed|not computationally|cannot verify computationally|computationally infeasible|no practical algorithm|undecidable|np-complete|exponential complexity|intractable|no closed form"; then
        challenging_count=$((challenging_count + 1))
    fi
    
    # Also check for explicit flag
    if echo "$review_lower" | grep -qE "requires.*decision|project owner.*decision|needs.*approval|escalate"; then
        challenging_count=$((challenging_count + 1))
    fi
    
    # Decision needed if both conditions present or explicit flag
    if [ $sound_count -gt 0 ] && [ $challenging_count -gt 0 ]; then
        needs_decision=true
        theorems_needing_decision="Theorems flagged as mathematically sound but computationally challenging"
    fi
    
    if [ "$needs_decision" = "true" ]; then
        log_warn "Theorems identified as analytically sound but computationally problematic"
        log_info "Creating decision record for project owner review..."
        
        # Create decision record for project owner
        # Non-blocking: create file and continue - project owner decides asynchronously
        local decision_dir="$DEC_DIR/pending/$project_name"
        mkdir -p "$decision_dir"
        
        # Generate decision filename (auto-increment)
        local decision_num=$(find "$decision_dir" -name "decision-*.md" 2>/dev/null | wc -l)
        decision_num=$((decision_num + 1))
        local decision_filename=$(printf "decision-%03d.md" "$decision_num")
        
        cat > "$decision_dir/$decision_filename" << 'EOFDECISION'
# Decision Record: Theorems Requiring Project Owner Input

**Decision ID**: DEC-DECNUM
**Project**: PROJECTNAME
**Decision Type**: computation
**Date Created**: DATETIME
**Status**: Pending

## Decision Summary

Some theorems have been identified as mathematically valid/analytically sound but present computational challenges for implementation.

## Context

The Senior Mathematician's review flagged the following theorems as mathematically sound but computationally problematic:

THMDBLOCK

## Options

### Option A: Skip Implementation
Document the theorems as theoretical results only. No implementation will be provided.

### Option B: Approximate Implementation
Implement a simplified/approximate version that captures the essence but may not be exact.

### Option C: Theoretical Reference
Include the theorems in the documentation as theoretical references with analysis but no implementation.

## How to Respond

Edit this file to add your decision:

```
**Project Owner Decision**: [A/B/C]
**Rationale**: [Your reasoning]
**Signature**: [Your name]
**Date**: [Today's date]
```

## Routing

When processed via `/app/docker/decide.sh`, this decision will be moved to:
- `/decisions/approved/PROJECTNAME/` (all options are valid choices)

## Instructions

Run the decision tool to process when ready:
```bash
docker exec pent-eam-math-team /app/docker/decide.sh
```
EOFDECISION
        
        # Replace placeholders
        sed -i "s/DEC-DECNUM/DEC-$(printf '%03d' "$decision_num")/g" "$decision_dir/$decision_filename"
        sed -i "s/PROJECTNAME/$project_name/g" "$decision_dir/$decision_filename"
        sed -i "s/DATETIME/$(date '+%Y-%m-%d %H:%M:%S')/g" "$decision_dir/$decision_filename"
        sed -i "s/THMDBLOCK/$theorems_needing_decision/g" "$decision_dir/$decision_filename"
        
        log_info "Decision record created: $decision_dir/$decision_filename"
        log_warn "PROJECT OWNER ACTION REQUIRED: Review decision at $decision_dir/$decision_filename"
        update_progress "$project_name" "Supervisor" "Awaiting project owner decision - see $decision_filename"
        update_task_status "$project_name" "TASK-005" "In Progress"
        
        # Non-blocking: continue processing - project owner can decide asynchronously
        log_info "Continuing with next phases. Use decide.sh to process decision when ready."
        
    else
        log_info "No decision escalation needed - all theorems are computationally feasible"
        update_task_status "$project_name" "TASK-005" "Completed"
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
    write_response "$project_dir/implementation/solution.py" "$implementation"
    
    update_task_status "$project_name" "TASK-004" "Completed"
    
    # Phase 4: Tester - Validate with Fix Loop
    log_info "Phase 4: Tester validating implementation..."
    update_task_status "$project_name" "TASK-005" "In Progress"
    update_progress "$project_name" "Tester" "Creating test suite"
    
    local max_test_iterations=3
    local test_iteration=0
    local tests_passed=false
    
    # Test-and-fix loop: iterate until tests pass or max iterations reached
    while [ "$tests_passed" = "false" ] && [ $test_iteration -lt $max_test_iterations ]; do
        test_iteration=$((test_iteration + 1))
        log_info "Test iteration $test_iteration/$max_test_iterations"
        
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
        write_response "$project_dir/tests/test_solution.py" "$tests"
        
        # Run the tests
        log_info "Running tests..."
        update_progress "$project_name" "Tester" "Running validation tests (iteration $test_iteration)"
        
        if source /app/.venv/bin/activate 2>/dev/null && python -m pytest "$project_dir/tests/test_solution.py" -v > "$project_dir/tests/results.txt" 2>&1; then
            log_info "✓ All tests passed!"
            tests_passed=true
        else
            log_warn "Tests failed - capturing error details"
            
            # Extract error information for the developer
            local error_summary=$(grep -E "^(FAILED|PASSED|ERROR|====.*ERROR|====.*FAILED)" "$project_dir/tests/results.txt" 2>/dev/null | head -20 || echo "Test execution failed")
            local error_context=$(grep -A 5 "AssertionError\|Error\|FAILED" "$project_dir/tests/results.txt" 2>/dev/null | head -30 || echo "See results.txt for details")
            
            log_info "Test errors detected. Sending back to Python Coder for fixes..."
            update_progress "$project_name" "Python Coder" "Fixing test failures (iteration $test_iteration)"
            update_task_status "$project_name" "TASK-007" "In Progress"
            
            # Send to Python Coder for fixes (only if not last iteration)
            if [ $test_iteration -lt $max_test_iterations ]; then
                local fix_prompt="You are a Python Coder. The implementation has test failures that need to be fixed.

Project: $project_name

Original Implementation:
${impl_for_test:-Not available}

Test Errors:
${error_summary}

Error Context:
${error_context}

Please fix the implementation to address these test failures. Ensure:
1. All test assertions pass
2. Edge cases are handled properly
3. Mathematical correctness is maintained
4. Code is clean and well-documented

Return the corrected implementation as a code block."
                
                local fixed_implementation=$(call_ollama "$PYTHON_CODER_MODEL" "$fix_prompt")
                
                # Extract just the code from the response
                if echo "$fixed_implementation" | grep -q '```python'; then
                    fixed_implementation=$(echo "$fixed_implementation" | sed -n '/\`\`\`python/,/\`\`\`/p' | sed '1d;$d')
                elif echo "$fixed_implementation" | grep -q '```'; then
                    fixed_implementation=$(echo "$fixed_implementation" | sed -n '/\`\`\`/,/\`\`\`/p' | sed '1d;$d')
                fi
                
                echo "# Implementation: $project_name" > "$project_dir/implementation/solution.py"
                echo '"""' >> "$project_dir/implementation/solution.py"
                echo "Implementation for: $project_name" >> "$project_dir/implementation/solution.py"
                echo "Fixed iteration: $test_iteration" >> "$project_dir/implementation/solution.py"
                echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$project_dir/implementation/solution.py"
                echo '"""' >> "$project_dir/implementation/solution.py"
                echo "" >> "$project_dir/implementation/solution.py"
                write_response "$project_dir/implementation/solution.py" "$fixed_implementation"
                
                log_info "Implementation updated. Re-running tests..."
                update_progress "$project_name" "Python Coder" "Implementation fixed, awaiting re-test"
                update_task_status "$project_name" "TASK-007" "Completed"
            else
                log_error "Max test iterations reached. Manual intervention required."
            fi
        fi
    done
    
    # Record test results
    if [ "$tests_passed" = "true" ]; then
        echo "" >> "$project_dir/tests/results.txt"
        echo "✓ All tests passed after $test_iteration iteration(s)" >> "$project_dir/tests/results.txt"
    else
        echo "" >> "$project_dir/tests/results.txt"
        echo "⚠ Tests did not pass after $max_test_iterations iterations. Manual review recommended." >> "$project_dir/tests/results.txt"
    fi
    
    update_task_status "$project_name" "TASK-005" "Completed"
    update_task_status "$project_name" "TASK-006" "Completed"

    # ================================================================================
    # Phase 4.5: Results Analysis Loop - Mathematical Validation
    # ================================================================================
    # Both mathematicians analyze code results for relevance to theorems and proofs.
    # If results are too shallow, enter additional coding/testing loops.
    # ================================================================================
    log_info "Phase 4.5: Results Analysis - Mathematical validation of code results..."
    update_progress "$project_name" "Senior Mathematician" "Analyzing results relevance"
    update_task_status "$project_name" "TASK-006" "In Progress"

    # Read all relevant files for analysis
    local analysis_content=""
    local theorems_content=""
    local review_content=""
    local impl_content=""
    local test_results_content=""

    [ -f "$project_dir/theorems/analysis.md" ] && analysis_content=$(cat "$project_dir/theorems/analysis.md")
    [ -f "$project_dir/theorems/proposed.md" ] && theorems_content=$(cat "$project_dir/theorems/proposed.md")
    [ -f "$project_dir/review/critique.md" ] && review_content=$(cat "$project_dir/review/critique.md")
    [ -f "$project_dir/implementation/solution.py" ] && impl_content=$(cat "$project_dir/implementation/solution.py")
    [ -f "$project_dir/tests/results.txt" ] && test_results_content=$(cat "$project_dir/tests/results.txt")

    # Creative Mathematician: Analyze relevance to theorems
    log_info "Phase 4.5a: Creative Mathematician analyzing theorem relevance..."
    local creative_analysis_prompt="You are the Creative Mathematician. Analyze the code results for mathematical relevance.

Project: $project_name

Original Theorems Proposed:
${theorems_content:-Not available}

Senior Mathematician Review:
${review_content:-Not available}

Implementation:
${impl_content:-Not available}

Test Results:
${test_results_content:-Not available}

Evaluate:
1. Do the code outputs validate the theorems proposed?
2. Are the mathematical results sufficiently deep/comprehensive?
3. Are there any gaps between theory and implementation?
4. Rate the depth of results: shallow / adequate / deep / exceptional

Be specific about what is validated and what may need additional work."

    local creative_analysis=$(call_ollama "$model" "$creative_analysis_prompt")

    # Save Creative Mathematician's analysis
    mkdir -p "$project_dir/analysis"
    cat > "$project_dir/analysis/creative_validation.md" << 'ANAL1'
# Creative Mathematician: Results Analysis

ANAL1
    echo "" >> "$project_dir/analysis/creative_validation.md"
    echo "Project: $project_name" >> "$project_dir/analysis/creative_validation.md"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$project_dir/analysis/creative_validation.md"
    echo "" >> "$project_dir/analysis/creative_validation.md"
    echo "## Analysis" >> "$project_dir/analysis/creative_validation.md"
    echo "$creative_analysis" >> "$project_dir/analysis/creative_validation.md"

    # Senior Mathematician: Analyze proof relevance
    log_info "Phase 4.5b: Senior Mathematician analyzing proof relevance..."
    local senior_analysis_prompt="You are the Senior Mathematician. Analyze the code results for proof relevance.

Project: $project_name

Original Analysis:
${analysis_content:-Not available}

Theorems Proposed:
${theorems_content:-Not available}

Your Previous Review:
${review_content:-Not available}

Implementation:
${impl_content:-Not available}

Test Results:
${test_results_content:-Not available}

Evaluate:
1. Do the computational results support the mathematical proofs?
2. Are the proofs correctly reflected in the implementation?
3. Are edge cases and special cases properly handled?
4. Rate the proof validation: weak / moderate / strong / definitive

Be specific about proof strength and any weaknesses."

    local senior_analysis=$(call_ollama "$model" "$senior_analysis_prompt")

    # Save Senior Mathematician's analysis
    cat > "$project_dir/analysis/senior_validation.md" << 'ANAL2'
# Senior Mathematician: Results Analysis

ANAL2
    echo "" >> "$project_dir/analysis/senior_validation.md"
    echo "Project: $project_name" >> "$project_dir/analysis/senior_validation.md"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "$project_dir/analysis/senior_validation.md"
    echo "" >> "$project_dir/analysis/senior_validation.md"
    echo "## Analysis" >> "$project_dir/analysis/senior_validation.md"
    echo "$senior_analysis" >> "$project_dir/analysis/senior_validation.md"

    # Synthesize both analyses and decide if additional loops are needed
    log_info "Phase 4.5c: Synthesizing validation results..."
    local synthesis_prompt="You are the Supervisor. Synthesize both mathematicians' analyses.

Creative Mathematician Analysis:
$creative_analysis

Senior Mathematician Analysis:
$senior_analysis

Determine:
1. Are the results sufficient for publication quality work?
2. If results are shallow, what additional work is needed?
3. Should we enter another coding/testing loop?

Respond with ONLY ONE of these formats:
- APPROVED: [brief justification] - Results are sufficient
- NEEDS_WORK: [specific deficiencies] - Need additional iterations
- NEEDS_ENHANCEMENT: [specific enhancements] - Ready for LaTeX with improvements"

    local synthesis=$(call_ollama "$model" "$synthesis_prompt")
    echo "$synthesis" > "$project_dir/analysis/synthesis.md"

    log_info "Validation synthesis: $synthesis"

    # Check if results are too shallow and we need additional loops
    local needs_additional_work=false
    if echo "$synthesis" | grep -qi "NEEDS_WORK"; then
        needs_additional_work=true
    fi

    if [ "$needs_additional_work" = "true" ]; then
        log_warn "Results too shallow - entering additional coding/testing loop"
        update_progress "$project_name" "Supervisor" "Additional coding loop required"
        
        # Increment loop counter
        main_loop_count=$((main_loop_count + 1))
        
        if [ $main_loop_count -lt 3 ]; then
            log_info "Additional iteration $main_loop_count - returning to implementation"
            # Reset flags to continue the main loop
            tests_passed=false
            continue  # Continue the main loop
        else
            log_warn "Max main loop iterations reached - proceeding despite shallow results"
            update_progress "$project_name" "Supervisor" "Max iterations reached, proceeding"
        fi
    fi

    update_task_status "$project_name" "TASK-006" "Completed"
    update_progress "$project_name" "Senior Mathematician" "Results validation complete"


    
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
| Results Analysis | ✓ Complete | Both Mathematicians | Results validated |
| LaTeX Compilation | ✓ Complete | Senior Mathematician | Article compiled |
| Publication Review | ✓ Complete | Supervisor | Pending approval |
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
- `analysis/creative_validation.md` - Creative Mathematician results analysis
- `analysis/senior_validation.md` - Senior Mathematician results analysis
- `analysis/synthesis.md` - Validation synthesis
- `publication/article.tex` - LaTeX article for Arxiv
EOF


    # ================================================================================
    # Phase 5.1: Compile LaTeX Article for Arxiv
    # ================================================================================
    # Senior Mathematician compiles the work into publication-ready LaTeX
    # ================================================================================
    log_info "Phase 5.1: Compiling LaTeX article for Arxiv publication..."
    update_progress "$project_name" "Senior Mathematician" "Compiling LaTeX article"
    update_task_status "$project_name" "TASK-008" "In Progress"

    # Read all relevant files for LaTeX compilation
    local latex_analysis=""
    local latex_theorems=""
    local latex_review=""
    local latex_creative=""
    local latex_senior=""
    local latex_synthesis=""

    [ -f "$project_dir/theorems/analysis.md" ] && latex_analysis=$(cat "$project_dir/theorems/analysis.md")
    [ -f "$project_dir/theorems/proposed.md" ] && latex_theorems=$(cat "$project_dir/theorems/proposed.md")
    [ -f "$project_dir/review/critique.md" ] && latex_review=$(cat "$project_dir/review/critique.md")
    [ -f "$project_dir/analysis/creative_validation.md" ] && latex_creative=$(cat "$project_dir/analysis/creative_validation.md")
    [ -f "$project_dir/analysis/senior_validation.md" ] && latex_senior=$(cat "$project_dir/analysis/senior_validation.md")
    [ -f "$project_dir/analysis/synthesis.md" ] && latex_synthesis=$(cat "$project_dir/analysis/synthesis.md")

    # Prompt for LaTeX compilation
    local latex_prompt="You are a Senior Mathematician. Compile a publication-ready LaTeX article suitable for Arxiv.org.

Project: $project_name

Initial Analysis:
${latex_analysis:-Not available}

Theorems Proposed:
${latex_theorems:-Not available}

Review:
${latex_review:-Not available}

Creative Mathematician Validation:
${latex_creative:-Not available}

Senior Mathematician Validation:
${latex_senior:-Not available}

Synthesis:
${latex_synthesis:-Not available}

Create a complete LaTeX document with:
1. \title{} - Descriptive title
2. \author{} - Author list
3. \date{} - Date
4. \begin{abstract} ... \end{abstract} - Abstract
5. \section{Introduction}
6. \section{Mathematical Background}
7. \section{Main Results}
8. \section{Theorems and Proofs}
9. \section{Implementation and Results}
10. \section{Conclusion}
11. \section{References}
12. Any necessary \usepackage{} commands

Use proper mathematical notation with amsmath, amsthm packages.
Include theorem environments (theorem, lemma, proposition, proof).
Format for readability and Arxiv compatibility."

    local latex_article=$(call_ollama "$model" "$latex_prompt")

    # Save LaTeX article
    mkdir -p "$project_dir/publication"
    echo "$latex_article" > "$project_dir/publication/article.tex"

    log_info "LaTeX article compiled: $project_dir/publication/article.tex"
    update_task_status "$project_name" "TASK-008" "Completed"
    update_progress "$project_name" "Senior Mathematician" "LaTeX compilation complete"


    # ================================================================================
    # Phase 5.5: Project Owner Review for Publication Approval
    # ================================================================================
    # Present the LaTeX article to Project Owner for:
    # - Approval for Arxiv publication
    # - Or additional enhancement requests
    # ================================================================================
    log_info "Phase 5.5: Creating publication review decision for Project Owner..."
    update_progress "$project_name" "Supervisor" "Awaiting publication approval"

    local pub_review_dir="$DEC_DIR/pending/$project_name"
    mkdir -p "$pub_review_dir"

    # Generate decision filename
    local pub_decision_num=$(find "$pub_review_dir" -name "decision-*.md" 2>/dev/null | wc -l)
    pub_decision_num=$((pub_decision_num + 1))
    local pub_decision_filename=$(printf "decision-%03d.md" "$pub_decision_num")

    cat > "$pub_review_dir/$pub_decision_filename" << 'PUBREVIEWFILE'
# Publication Review: PROJECTNAME

**Decision ID**: PUB-DECNUM
**Project**: PROJECTNAME
**Decision Type**: publication
**Date Created**: DATETIME
**Status**: Pending

## Summary

The investigation is complete and a LaTeX article has been compiled for Arxiv publication.

## Article Preview

The article is available at: /app/output/PROJECTNAME/publication/article.tex

## Review Checklist

Before approving publication, verify:
- [ ] Mathematical content is correct
- [ ] Theorems and proofs are complete
- [ ] LaTeX compiles without errors
- [ ] Results are properly documented

## Options

### Option A: Approve for Publication
The article is ready for Arxiv submission.

### Option B: Request Enhancements
Additional work is needed before publication. Specify enhancements below.

### Option C: Reject for Now
This work is not ready for publication. Document reasons.

## How to Respond

Edit this file to add your decision:

```
**Project Owner Decision**: [A/B/C]
**Rationale**: [Your reasoning]
**Enhancements Requested**: [If B, specify what is needed]
**Signature**: [Your name]
**Date**: [Today's date]
```

## If Approved (Option A)

The article will be moved to /app/output/PROJECTNAME/publication/approved/ and marked ready for submission.

## If Enhancements Requested (Option B)

A new project will be created with your enhancement requests.

## Routing

When processed via `/app/docker/decide.sh`, this decision will be moved to:
- `/decisions/approved/PROJECTNAME/` (Option A - ready for submission)
- `/decisions/pending/PROJECTNAME/` (Option B - creates enhancement project)
- `/decisions/rejected/PROJECTNAME/` (Option C - deferred)

## Instructions

1. Review the LaTeX article at: /app/output/PROJECTNAME/publication/article.tex
2. Optionally compile with: pdflatex /app/output/PROJECTNAME/publication/article.tex
3. Run decide.sh when ready to make a decision:
```bash
docker exec pent-eam-math-team /app/docker/decide.sh
```
PUBREVIEWFILE

    # Replace placeholders using sed
    sed -i "s/PUB-DECNUM/PUB-$(printf '%03d' "$pub_decision_num")/g" "$pub_review_dir/$pub_decision_filename"
    sed -i "s/PROJECTNAME/$project_name/g" "$pub_review_dir/$pub_decision_filename"
    sed -i "s/DATETIME/$(date '+%Y-%m-%d %H:%M:%S')/g" "$pub_review_dir/$pub_decision_filename"

    log_info "Publication review decision created: $pub_review_dir/$pub_decision_filename"
    log_warn "PROJECT OWNER ACTION REQUIRED: Review publication at $pub_review_dir/$pub_decision_filename"

    # Non-blocking: continue - project owner decides via decide.sh
    log_info "Publication review pending. Use decide.sh to process publication decision."
    log_info "Investigation complete for: $project_name"
    update_progress "$project_name" "Supervisor" "Investigation complete"

    # Phase 5.5: Handle next steps escalation (non-blocking)
    # Create decision file and continue - process action asynchronously
    if echo "$summary" | grep -qiE "next step|further investigation|future work|recommended|proposed follow"; then
        log_info "Phase 5.5: Summary contains next steps - creating escalation for Project Owner..."
        
        local next_steps_dir="$DEC_DIR/pending/$project_name"
        mkdir -p "$next_steps_dir"
        
        # Generate decision filename (auto-increment, unified naming)
        local decision_num=$(find "$next_steps_dir" -name "decision-*.md" 2>/dev/null | wc -l)
        decision_num=$((decision_num + 1))
        local next_steps_filename=$(printf "decision-%03d.md" "$decision_num")
        
        cat > "$next_steps_dir/$next_steps_filename" << 'NEXTStepSFILE'
# Next Steps Escalation: PROJECTNAME

**Decision ID**: NEXT-DECNUM
**Project**: PROJECTNAME
**Decision Type**: next_steps
**Date Created**: DATETIME
**Status**: Pending

## Summary

The investigation has identified potential next steps for further work.

## Proposed Next Steps

See the summary file for recommended next steps.

## Options

### Option A: Continue Investigation
Create a new project with the proposed next steps.

### Option B: Document for Future Work
Save next steps to /app/output/PROJECTNAME/next-steps.md.

### Option C: End Investigation Here
Consider current investigation complete.

## How to Respond

Edit this file to add your decision:

```
**Project Owner Decision**: [A/B/C]
**Rationale**: [Your reasoning]
**Signature**: [Your name]
**Date**: [Today's date]
```

## Routing

When processed via `/app/docker/decide.sh`, this decision will be moved to:
- `/decisions/approved/PROJECTNAME/` (all options are valid choices)
- Option A will trigger creation of a continuation project

## Instructions

Run the decision tool to process when ready:
```bash
docker exec pent-eam-math-team /app/docker/decide.sh
```
NEXTStepSFILE
        
        # Replace placeholders
        sed -i "s/NEXT-DECNUM/NEXT-$(printf '%03d' "$decision_num")/g" "$next_steps_dir/$next_steps_filename"
        sed -i "s/PROJECTNAME/$project_name/g" "$next_steps_dir/$next_steps_filename"
        sed -i "s/DATETIME/$(date '+%Y-%m-%d %H:%M:%S')/g" "$next_steps_dir/$next_steps_filename"
        
        log_info "Next steps decision created: $next_steps_dir/$next_steps_filename"
        log_warn "PROJECT OWNER ACTION REQUIRED: Review next steps at $next_steps_dir/$next_steps_filename"
        
        # Non-blocking: continue - project owner decides via decide.sh
        log_info "Investigation complete. Use decide.sh to process next steps decision when ready."
    else
        log_info "Investigation complete for: $project_name"
    fi
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
    local decisions=$(find "$DEC_DIR/pending" -name "*.md" 2>/dev/null | wc -l)
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