# PENTeam Decision Workflow Analysis

**Date**: 2026-06-15  
**Status**: ✅ IMPLEMENTED - Closed-Loop Decision Workflow  
**Branch**: improved-workflow  
**Repository**: MathTeam

---

## Executive Summary

This document describes the closed-loop decision workflow implementation in the PENTeam mathematical research team system. The decision loop is a critical component that allows human Project Owners to approve/reject/escalate key decisions during the automated research pipeline.

**Key Achievement**: The decision workflow has been upgraded from **open-loop** (non-blocking decisions) to **closed-loop** (blocking checkpoints with automatic follow-up actions).

---

## Decision Workflow Overview

### Improved Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SUPERVISOR PIPELINE                              │
├─────────────────────────────────────────────────────────────────────┤
│  1. Input → Process Project → Create Structure                      │
│  2. Creative Mathematician → Propose Theorems                       │
│  3. Senior Mathematician → Review Theorems (with feedback loop)    │
│  4. Python Coder → Implement Code                                   │
│  5. Tester → Validate (with fix loop)                               │
│  6. Senior Mathematician → Validate Results                         │
│  7. LaTeX → Compile Publication                                     │
│  8. Summary → Generate Report                                       │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (blocking checkpoint)
┌─────────────────────────────────────────────────────────────────────┐
│                    DECISION CREATION POINTS                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  DECISION POINT 1: Computation Challenge (Phase 2.5)                 │
│  ─────────────────────────────────────────────                      │
│  - Trigger: Theorems mathematically sound but computationally       │
│             infeasible                                              │
│  - File: decisions/pending/{project}/decision-001.md                │
│  - Type: computation                                                │
│  - Options: A) Skip | B) Approximate | C) Theoretical Reference     │
│  - BLOCKS: Phase 3 (Implementation)                                  │
│                                                                     │
│  DECISION POINT 2: Publication Review (Phase 5.5)                   │
│  ─────────────────────────────────────────────                      │
│  - Trigger: Investigation complete, LaTeX compiled                  │
│  - File: decisions/pending/{project}/decision-002.md                 │
│  - Type: publication                                                │
│  - Options: A) Approve | B) Request Enhancements | C) Reject       │
│  - BLOCKS: Finalization                                             │
│                                                                     │
│  DECISION POINT 3: Next Steps (Phase 5.5)                           │
│  ─────────────────────────────────────────────                      │
│  - Trigger: Summary contains "next step" keywords                   │
│  - File: decisions/pending/{project}/decision-003.md                │
│  - Type: next_steps                                                 │
│  - Options: A) Continue | B) Document Future | C) End               │
│  - TRIGGERS: Continuation project creation                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (blocking wait)
┌─────────────────────────────────────────────────────────────────────┐
│                    PROJECT OWNER ACTION                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Run: docker exec pent-eam-math-team /app/docker/decide.sh          │
│                                                                     │
│  Process:                                                            │
│  1. List pending decisions                                          │
│  2. Select decision by project                                      │
│  3. Review content                                                  │
│  4. Choose option (A/B/C)                                          │
│  5. Enter name, notes, free-form prompt                            │
│  6. Decision appended to file                                      │
│  7. File moved to: decisions/approved/{project}/                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (CLOSED LOOP)
                    ┌─────────────────────────┐
                    │  PIPELINE RESUMES      │
                    │  (Decision processed)   │
                    └─────────────────────────┘
                              │
                              ▼ (automatic action)
                    ┌─────────────────────────┐
                    │  FOLLOW-UP ACTIONS      │
                    └─────────────────────────┘
                              │
                              ├── A: Create continuation project
                              ├── B: Document next steps
                              └── C: Mark investigation complete
```

---

## Implementation Summary

### New Files Created

| File | Purpose |
|------|---------|
| `docker/poll-decisions.sh` | Background poller for decision processing |
| `docker/supervisor.sh` (updated) | Added decision checkpoint functions |
| `docker/docker-compose.yml` (updated) | Added decision-poller service |

### Key Changes

#### 1. Decision Checkpoint Functions (supervisor.sh)

Added blocking checkpoint mechanism:

```bash
# Wait for a specific decision type to be resolved
wait_for_decision() {
    local project_name="$1"
    local decision_type="$2"  # computation, publication, next_steps
    local timeout_seconds="${3:-3600}"
    
    while true; do
        # Check approved/ and rejected/ directories
        # for resolved decision
        ...
        sleep $poll_interval
    done
}
```

#### 2. Decision Action Handlers

Added local handlers for immediate decision processing:

- `handle_continue_investigation_local()` - Creates continuation project
- `handle_next_steps_document()` - Saves next steps to file
- `handle_next_steps_end()` - Marks project complete

#### 3. Decision Poller Service

Background process for asynchronous decision handling:

```yaml
# docker-compose.yml service
decision-poller:
    command: ["/app/docker/poll-decisions.sh", "start"]
    restart: unless-stopped
```

---

## Closed-Loop Behavior

### Phase 2.5: Computation Decision

**Flow with Checkpoint**:
- Creates decision file in `decisions/pending/`
- **BLOCKS** pipeline until decision resolved
- Reads decision from `decisions/approved/` or `decisions/rejected/`
- Skips/adapts Phase 3 implementation based on decision

### Phase 5.5: Publication Decision

**Flow with Checkpoint**:
- Creates decision file after LaTeX compilation
- **BLOCKS** finalization until decision resolved
- Reads publication decision
- Creates marker file with decision outcome

### Phase 5.5: Next Steps Decision

**Flow with Automatic Action**:
- Creates decision file when summary has next steps
- **BLOCKS** until decision resolved
- **AUTOMATICALLY** executes follow-up actions:
  - Option A: Creates continuation project in `input/`
  - Option B: Saves next steps to `output/{project}/next-steps.md`
  - Option C: Marks project complete in `status.md`

---

## Decision Actions Matrix

| Decision Type | Option | Supervisor Action | Poller Action |
|--------------|--------|------------------|---------------|
| computation | A: Skip | Skip Phase 3-4 | Mark in .implementation_mode |
| computation | B: Approximate | Run Phase 3 with APPROXIMATE flag | Log |
| computation | C: Reference | Create reference doc | Mark in .implementation_mode |
| publication | A: Approve | Create .publication_decision | Mark approved |
| publication | B: Enhance | Create .publication_decision | Create enhancement project |
| publication | C: Reject | Create .publication_decision | Mark rejected |
| next_steps | A: Continue | Create continuation project | Create in input/ |
| next_steps | B: Document | Save next-steps.md | Create next-steps.md |
| next_steps | C: End | Mark status.md complete | Update summary status |

---

## File Locations Reference

### Scripts
- `/app/docker/supervisor.sh` - Main pipeline orchestrator (UPDATED)
- `/app/docker/decide.sh` - Interactive decision processor
- `/app/docker/monitor.sh` - Status dashboard
- `/app/docker/poll-decisions.sh` - Background decision poller (NEW)

### Docker
- `/app/docker/docker-compose.yml` - Updated with decision-poller service

### Directories
- `/app/decisions/pending/{project}/` - Awaiting decisions
- `/app/decisions/approved/{project}/` - Resolved decisions
- `/app/decisions/rejected/{project}/` - Rejected decisions
- `/app/output/{project}/publication/` - LaTeX articles
- `/app/output/{project}/publication/approved/` - Approved publications (NEW)
- `/app/output/{project}/publication/rejected/` - Rejected publications (NEW)
- `/app/input/` - Project queue (for continuation/enhancement projects)

### Marker Files
- `/app/output/{project}/.implementation_mode` - Stores computation decision
- `/app/output/{project}/.publication_decision` - Stores publication decision
- `/app/output/{project}/.next_steps_decision` - Stores next steps decision
- `/app/output/{project}/status.md` - Project completion status

---

## Testing the Decision Loop

To verify the workflow:

1. Create a test project:
   ```bash
   echo "# Test Project" > /app/input/test-project.md
   ```

2. Start supervisor:
   ```bash
   ./docker/run.sh supervisor
   ```

3. Watch for decision creation:
   ```bash
   tail -f /app/communication/supervisor.log
   ls -la /app/decisions/pending/
   ```

4. Process decision:
   ```bash
   ./docker/decide.sh
   ```

5. Verify pipeline behavior:
   ```bash
   # Check decision resolved
   ls -la /app/decisions/approved/
   
   # Check marker file created
   cat /app/output/{project}/.implementation_mode
   
   # Verify continuation project created (if applicable)
   ls -la /app/input/*-continuation*.md
   ```

6. Test decision poller:
   ```bash
   docker exec pent-eam-decision-poller /app/docker/poll-decisions.sh once
   ```

---

## Conclusion

The PENTeam decision workflow is now a **true closed-loop system**:

1. ✅ Decision creation points (EXISTING)
2. ✅ Decision checkpoints (IMPLEMENTED)
3. ✅ Decision resolution triggers (IMPLEMENTED)
4. ✅ Pipeline resume mechanism (IMPLEMENTED)
5. ✅ Closed-loop feedback (IMPLEMENTED)

The system now:
- **Pauses** at decision points until Project Owner responds
- **Processes** decisions automatically upon resolution
- **Creates** continuation/enhancement projects when needed
- **Documents** decisions and their outcomes
- **Monitors** decision directories via background poller
