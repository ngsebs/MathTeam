#!/bin/bash
# PENTeam Decision Poller
# Monitors decisions/approved/ and triggers follow-up actions
# This script runs in the background to close the decision loop

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Support both container and local execution paths
if [ -d "/app/decisions/approved" ]; then
    DECISIONS_DIR="/app/decisions"
    OUTPUT_DIR="/app/output"
    INPUT_DIR="/app/input"
else
    DECISIONS_DIR="$SCRIPT_DIR/../decisions"
    OUTPUT_DIR="$SCRIPT_DIR/../output"
    INPUT_DIR="$SCRIPT_DIR/../input"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /app/communication/decision-poller.log
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

# Track processed decisions to avoid reprocessing
PROCESSED_FILE="/tmp/processed_decisions.txt"
touch "$PROCESSED_FILE"

# Check if a decision has already been processed
is_processed() {
    local decision_file="$1"
    grep -q "^$decision_file$" "$PROCESSED_FILE" 2>/dev/null
}

# Mark a decision as processed
mark_processed() {
    local decision_file="$1"
    echo "$decision_file" >> "$PROCESSED_FILE"
}

# Extract decision type from file
get_decision_type() {
    local file="$1"
    grep -i "^\\*\\*Decision Type\\*\\*:" "$file" 2>/dev/null | sed 's/.*: *//' | tr -d ' '
}

# Extract decision choice from file
get_decision_choice() {
    local file="$1"
    grep -i "^\\*\\*Project Owner Decision\\*\\*:" "$file" 2>/dev/null | sed 's/.*: *//' | tr -d ' '
}

# Extract project name from file
get_project_name() {
    local file="$1"
    grep -i "^\\*\\*Project\\*\\*:" "$file" 2>/dev/null | sed 's/.*: *//'
}

# Extract decision ID from file
get_decision_id() {
    local file="$1"
    grep -i "^\\*\\*Decision ID\\*\\*:" "$file" 2>/dev/null | sed 's/.*: *//'
}

# Handle next_steps decision - Option A: Continue Investigation
handle_continue_investigation() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Creating continuation project for: $project_name"
    
    local original_project_dir="$OUTPUT_DIR/$project_name"
    local next_steps_content=$(cat "$decision_file")
    
    # Create continuation project based on summary recommendations
    local continuation_name="${project_name}-continuation"
    local continuation_dir="$OUTPUT_DIR/$continuation_name"
    local continuation_input="$INPUT_DIR/${continuation_name}.md"
    
    # Extract next steps from original summary
    local next_steps_summary=""
    if [ -f "$original_project_dir/summary.md" ]; then
        next_steps_summary=$(grep -A 50 "## Next Steps" "$original_project_dir/summary.md" 2>/dev/null || echo "")
    fi
    
    # Create continuation project description
    cat > "$continuation_input" << EOF
# Continuation Project: $continuation_name

**Project Title**: Continuation of $project_name

**Problem Statement**: 
Continue the investigation from $project_name based on Project Owner approval.

**Background/Context**:
This is an automated continuation project created from the decision loop.

## Previous Investigation
Previous project: $project_name
Summary next steps:
$next_steps_summary

## Original Decision
$(cat "$decision_file")

**Priority**: High

**Notes**: 
This continuation was automatically created by the decision poller.
EOF
    
    log_info "Continuation project created: $continuation_input"
    log_info "Supervisor will pick up this project on next scan"
}

# Handle next_steps decision - Option B: Document for Future
handle_document_future() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Documenting next steps for future work: $project_name"
    
    local project_dir="$OUTPUT_DIR/$project_name"
    local next_steps_file="$project_dir/next-steps.md"
    local next_steps_content=$(cat "$decision_file")
    
    # Create next-steps.md with full documentation
    cat > "$next_steps_file" << EOF
# Next Steps: $project_name

**Status**: Documented for Future Work
**Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Decision File**: $(basename "$decision_file")

## Decision Summary

The investigation for $project_name has been documented for potential future work.

## Decision Details
$(cat "$decision_file")

## Recommended Future Work

This section captures the next steps that were proposed during the investigation.

EOF
    
    log_info "Next steps documented: $next_steps_file"
}

# Handle next_steps decision - Option C: End Investigation
handle_end_investigation() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Ending investigation: $project_name"
    
    local project_dir="$OUTPUT_DIR/$project_name"
    local status_file="$project_dir/status.md"
    
    # Update project status
    cat > "$status_file" << EOF
# Project Status: $project_name

**Status**: Completed
**Completed Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Decision**: Investigation ended by Project Owner

## Final Decision
$(cat "$decision_file")

## Archive Location
All project files remain in: $project_dir

EOF
    
    log_info "Project marked as completed: $status_file"
}

# Handle publication decision - Option A: Approve for Publication
handle_approve_publication() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Processing publication approval: $project_name"
    
    local project_dir="$OUTPUT_DIR/$project_name"
    local publication_dir="$project_dir/publication"
    local approved_dir="$publication_dir/approved"
    
    mkdir -p "$approved_dir"
    
    # Copy LaTeX to approved directory
    if [ -f "$publication_dir/article.tex" ]; then
        cp "$publication_dir/article.tex" "$approved_dir/article.tex"
        log_info "LaTeX article copied to: $approved_dir/article.tex"
    fi
    
    # Create approval marker
    cat > "$approved_dir/approval.md" << EOF
# Publication Approval

**Project**: $project_name
**Approved Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Decision File**: $(basename "$decision_file")

## Approval Details
$(cat "$decision_file")

## Ready for Submission
This article is approved for submission to Arxiv.org.

## Submission Checklist
- [ ] Verify all co-authors are listed
- [ ] Check for any necessary acknowledgments
- [ ] Run LaTeX compilation locally to verify
- [ ] Submit via https://arxiv.org/submit

EOF
    
    log_info "Publication approved and ready: $approved_dir/approval.md"
}

# Handle publication decision - Option B: Request Enhancements
handle_request_enhancements() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Creating enhancement project: $project_name"
    
    local enhancement_name="${project_name}-enhancements"
    local enhancement_input="$INPUT_DIR/${enhancement_name}.md"
    
    # Extract enhancement notes from decision
    local enhancement_notes=$(grep -A 20 "Enhancements Requested:" "$decision_file" 2>/dev/null || echo "See decision file for details")
    
    cat > "$enhancement_input" << EOF
# Enhancement Project: $enhancement_name

**Project Title**: Enhancement of $project_name

**Problem Statement**: 
Address enhancements requested by Project Owner for the $project_name publication.

**Background/Context**:
This enhancement project was automatically created from a publication review decision.

## Original Project
Previous project: $project_name

## Required Enhancements
$enhancement_notes

## Original Decision
$(cat "$decision_file")

**Priority**: High

**Notes**: 
This enhancement project was automatically created by the decision poller
based on the Project Owner's review feedback.

**Success Criteria**:
- [ ] Address all enhancement requests from decision file
- [ ] Update LaTeX article accordingly
- [ ] Ready for re-review

EOF
    
    log_info "Enhancement project created: $enhancement_input"
}

# Handle publication decision - Option C: Reject for Now
handle_reject_publication() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Marking publication as deferred: $project_name"
    
    local project_dir="$OUTPUT_DIR/$project_name"
    local publication_dir="$project_dir/publication"
    local rejected_dir="$publication_dir/rejected"
    
    mkdir -p "$rejected_dir"
    
    # Move/copy LaTeX to rejected directory
    if [ -f "$publication_dir/article.tex" ]; then
        cp "$publication_dir/article.tex" "$rejected_dir/article.tex"
    fi
    
    # Create rejection marker
    cat > "$rejected_dir/rejection.md" << EOF
# Publication Deferred

**Project**: $project_name
**Deferred Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Decision File**: $(basename "$decision_file")

## Rejection Details
$(cat "$decision_file")

## Notes
This publication was deferred by the Project Owner.
The article remains available at: $rejected_dir/article.tex

EOF
    
    log_info "Publication deferred: $rejected_dir/rejection.md"
}

# Handle computation decision - Option A: Skip Implementation
handle_computation_skip() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Handling computation skip decision: $project_name"
    
    local project_dir="$OUTPUT_DIR/$project_name"
    local implementation_dir="$project_dir/implementation"
    
    # Create marker file
    cat > "$implementation_dir/skip-marker.md" << EOF
# Implementation Skipped

**Project**: $project_name
**Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Decision**: Skip implementation (computationally infeasible)

$(cat "$decision_file")

## Impact
The theorems in this project were marked as theoretically sound but computationally
infeasible to implement. They remain available as theoretical references.

EOF
    
    log_info "Implementation marked as skipped: $implementation_dir/skip-marker.md"
}

# Handle computation decision - Option B: Approximate Implementation
handle_computation_approximate() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Creating approximate implementation task: $project_name"
    
    local project_dir="$OUTPUT_DIR/$project_name"
    local implementation_dir="$project_dir/implementation"
    
    # Create marker file with approximation flag
    cat > "$implementation_dir/approximate-marker.md" << EOF
# Approximate Implementation Required

**Project**: $project_name
**Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Decision**: Approximate implementation requested

$(cat "$decision_file")

## Implementation Guidance
The theorems in this project require approximate/simplified implementations
due to computational complexity constraints.

## Supervisor Action Required
The supervisor should re-enter the implementation phase with the APPROXIMATE flag.

EOF
    
    log_info "Approximate implementation task created: $implementation_dir/approximate-marker.md"
}

# Handle computation decision - Option C: Theoretical Reference
handle_computation_reference() {
    local project_name="$1"
    local decision_file="$2"
    
    log_info "Documenting as theoretical reference: $project_name"
    
    local project_dir="$OUTPUT_DIR/$project_name"
    local reference_dir="$project_dir/references"
    mkdir -p "$reference_dir"
    
    cat > "$reference_dir/theoretical-reference.md" << EOF
# Theoretical Reference

**Project**: $project_name
**Date**: $(date '+%Y-%m-%d %H:%M:%S')
**Decision**: Document as theoretical reference

$(cat "$decision_file")

## Reference Information
This project contains theorems that are documented as theoretical references
only. No computational implementation was requested.

EOF
    
    log_info "Theoretical reference documented: $reference_dir/theoretical-reference.md"
}

# Process a single decision file
process_decision() {
    local decision_file="$1"
    local project_name=$(get_project_name "$decision_file")
    local decision_id=$(get_decision_id "$decision_file")
    local decision_type=$(get_decision_type "$decision_file")
    local decision_choice=$(get_decision_choice "$decision_file")
    
    log_info "Processing: $decision_id ($decision_type: $decision_choice)"
    
    case "$decision_type" in
        next_steps)
            case "$decision_choice" in
                A*|Continue*|Continue\ Investigation)
                    handle_continue_investigation "$project_name" "$decision_file"
                    ;;
                B*|Document*|Document\ for\ Future)
                    handle_document_future "$project_name" "$decision_file"
                    ;;
                C*|End*|End\ Investigation)
                    handle_end_investigation "$project_name" "$decision_file"
                    ;;
                *)
                    log_warn "Unknown next_steps choice: $decision_choice"
                    ;;
            esac
            ;;
        publication)
            case "$decision_choice" in
                A*|Approve*|Approve\ for\ Publication)
                    handle_approve_publication "$project_name" "$decision_file"
                    ;;
                B*|Enhancements*|Request\ Enhancements)
                    handle_request_enhancements "$project_name" "$decision_file"
                    ;;
                C*|Reject*|Reject\ for\ Now)
                    handle_reject_publication "$project_name" "$decision_file"
                    ;;
                *)
                    log_warn "Unknown publication choice: $decision_choice"
                    ;;
            esac
            ;;
        computation)
            case "$decision_choice" in
                A*|Skip*)
                    handle_computation_skip "$project_name" "$decision_file"
                    ;;
                B*|Approximate*)
                    handle_computation_approximate "$project_name" "$decision_file"
                    ;;
                C*|Reference*|Theoretical\ Reference)
                    handle_computation_reference "$project_name" "$decision_file"
                    ;;
                *)
                    log_warn "Unknown computation choice: $decision_choice"
                    ;;
            esac
            ;;
        *)
            log_warn "Unknown decision type: $decision_type"
            ;;
    esac
    
    mark_processed "$decision_file"
}

# Main polling loop
run_poller() {
    log_info "Starting Decision Poller..."
    log_info "Monitoring: $DECISIONS_DIR/approved/"
    log_info "Log file: /app/communication/decision-poller.log"
    
    local poll_interval="${POLL_INTERVAL:-5}"
    
    while true; do
        # Check approved directory for new decisions
        if [ -d "$DECISIONS_DIR/approved" ]; then
            for project_dir in "$DECISIONS_DIR/approved"/*/; do
                if [ -d "$project_dir" ]; then
                    project_name=$(basename "$project_dir")
                    
                    for decision_file in "$project_dir"*.md; do
                        if [ -f "$decision_file" ] && ! is_processed "$decision_file"; then
                            process_decision "$decision_file"
                        fi
                    done
                fi
            done
        fi
        
        sleep "$poll_interval"
    done
}

# Show usage
usage() {
    cat << EOF
PENTeam Decision Poller - Closes the decision loop

Usage: poll-decisions.sh [COMMAND]

Commands:
    start       Start the poller (monitors approved decisions)
    once        Process any pending decisions once and exit
    help        Show this help message

Environment:
    POLL_INTERVAL    Seconds between polls (default: 5)
    DECISIONS_DIR    Decisions directory (default: /app/decisions)

Examples:
    ./poll-decisions.sh start      # Start continuous monitoring
    ./poll-decisions.sh once       # Process once and exit
    POLL_INTERVAL=10 ./poll-decisions.sh start   # Poll every 10 seconds

EOF
}

# Main entry point
case "${1:-start}" in
    start|run)
        run_poller
        ;;
    once|process)
        log_info "Processing decisions once..."
        if [ -d "$DECISIONS_DIR/approved" ]; then
            for project_dir in "$DECISIONS_DIR/approved"/*/; do
                if [ -d "$project_dir" ]; then
                    project_name=$(basename "$project_dir")
                    for decision_file in "$project_dir"*.md; do
                        if [ -f "$decision_file" ] && ! is_processed "$decision_file"; then
                            process_decision "$decision_file"
                        fi
                    done
                fi
            done
        fi
        log_info "Processing complete"
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
