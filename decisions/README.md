# Decisions Directory

This directory stores all decisions that require involvement of the Project Owner, kept separate for clear audit trail and prioritization.

## Directory Structure

| Directory | Purpose | Created By |
|-----------|---------|------------|
| `pending/` | Unresolved decisions awaiting owner input | supervisor.sh |
| `approved/` | Approved decisions | decide.sh |
| `rejected/` | Rejected decisions | decide.sh |

Directories are auto-created by `docker/decide.sh` when needed.

## Decision Lifecycle

```
1. Created (pending/)     → supervisor.sh escalates a decision
2. Reviewed (pending/)     → Project Owner runs docker/decide.sh
3. Resolved (approved/ or rejected/)
```

## Using decide.sh

Run the decision dialog to process pending decisions:

```bash
cd docker && ./decide.sh
```

The script will:
1. List all pending decisions by project
2. Show decision content and options
3. Prompt for name, notes, and free-form instructions
4. Write the decision response
5. Move the file to `approved/` or `rejected/`

### Options by Decision Type

| Type | Option A | Option B | Option C |
|------|----------|----------|----------|
| General | Approve | Reject | Request More Info |
| Next Steps | Continue | Document for Future | End Investigation |
| Computation | Skip | Approximate | Theoretical Reference |

## Decision Format

Each decision file contains:

```markdown
# Decision Record: [Title]

**Decision ID**: DEC-[PROJECT]-[NUMBER]
**Project**: [Project Name]
**Date Created**: [Date]
**Status**: [Pending | Approved | Rejected]

## Summary
[What needs to be decided]

## Background
[Why this decision is needed]

## Options
### Option A: [Name]
### Option B: [Name]
### Option C: [Name]

## Required From Project Owner

Run `docker/decide.sh` to make a decision.

---

## Project Owner Decision

**Project Owner Decision**: A/B/C
**Timestamp**: [Date]
**Signature**: [Name] <[Date]>
**Notes**: [Optional notes]
**Free-form Prompt**: [Optional instructions]
```

## Creating Decisions (for Developers)

To escalate a decision from supervisor.sh:

1. Create directory: `decisions/pending/[project-name]/`
2. Create file: `decision-001.md` (or `next-steps-001.md`)
3. Include the decision template with options
4. Supervisor polls for "Project Owner Decision:" and "Signature:"

## Guidelines

1. **Never skip** - Always escalate controversial or high-impact decisions
2. **Be specific** - Include clear options and analysis in each decision
3. **Track all decisions** - Use approved/rejected for audit trail
4. **Reference in threads** - Link decision IDs in communication threads