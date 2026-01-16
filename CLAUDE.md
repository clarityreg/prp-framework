# PRP Framework - Unified Agentic Engineering System

This is a unified PRP (Prompt Reference Protocol) framework that combines:
- **Wirasm's PRPs-agentic-eng**: Structured workflows for PRD→Plan→Implement
- **Your PRP-PACKAGE**: Archon MCP integration and shell-based Ralph loop

## Command Reference

All commands use the `/prp-*` namespace:

| Command | Purpose | Archon Integration |
|---------|---------|-------------------|
| `/prp-prd <description>` | Generate a Product Requirements Document | None |
| `/prp-plan <prd-or-description>` | Create implementation plan | Creates Archon project + tasks |
| `/prp-implement <plan-file>` | Execute implementation plan | Updates task statuses |
| `/prp-issue-investigate <issue>` | Investigate GitHub issue | Creates Archon task |
| `/prp-issue-fix <artifact>` | Fix from investigation artifact | Updates task to done |
| `/prp-debug <symptom>` | Root cause analysis | None |
| `/prp-review <PR>` | Code review a pull request | None |
| `/prp-commit [target]` | Smart git commit | None |
| `/prp-pr [base]` | Create pull request | None |
| `/prp-validate [scope]` | Run comprehensive validation | None |
| `/prp-primer` | Load project context | Reports Archon status |

## Archon MCP Integration

When Archon MCP is configured, the system provides:

1. **Task-Driven Development** - All work tracked through Archon tasks
2. **RAG Knowledge Search** - Query documentation before implementation
3. **Project Organization** - Features organized into projects
4. **Status Synchronization** - Task statuses are source of truth

### Archon Functions Used

```python
# Projects
find_projects(query="...")
manage_project("create"/"update"/"delete", ...)

# Tasks
find_tasks(filter_by="status"/"project", filter_value="...")
manage_task("create"/"update"/"delete", ...)

# RAG
rag_get_available_sources()
rag_search_knowledge_base(query="...")
rag_search_code_examples(query="...")
```

### Task Status Flow

```
todo → doing → review → done
```

- Only ONE task should be in "doing" status at a time
- Tasks move to "review" after implementation, before validation
- Tasks move to "done" after tests pass

## Ralph Loop (Autonomous Development)

The Ralph loop enables autonomous iterative development:

```bash
./ralph/loop.sh              # Run indefinitely (unified mode)
./ralph/loop.sh 10           # Run 10 iterations
./ralph/loop.sh plan 5       # Run 5 planning iterations
./ralph/loop.sh verify 3     # Run 3 verification iterations
```

### How it Works

1. Each iteration runs Claude with fresh context
2. `ralph/PROMPT_unified.md` provides instructions
3. `ralph/IMPLEMENTATION_PLAN.md` tracks progress
4. Git commits are made after each completed task
5. Changes are pushed automatically

### With Archon

When Archon is available, the Ralph loop:
- Syncs task statuses at start of each iteration
- Updates Archon when tasks complete
- Uses Archon as source of truth over file checkboxes

## Directory Structure

```
.claude/
├── commands/prp-core/       # PRP commands
│   ├── prp-prd.md
│   ├── prp-plan.md          # + Archon integration
│   ├── prp-implement.md     # + Archon integration
│   ├── prp-issue-investigate.md # + Archon task creation
│   ├── prp-issue-fix.md     # + Archon status updates
│   ├── prp-debug.md
│   ├── prp-review.md
│   ├── prp-commit.md
│   ├── prp-pr.md
│   ├── prp-validate.md
│   └── prp-primer.md
├── agents/                  # Specialized agent prompts
├── PRPs/                    # Artifact storage
│   ├── prds/               # PRD documents
│   ├── plans/              # Implementation plans
│   ├── issues/             # Issue investigations
│   └── reviews/            # PR reviews
└── settings.json           # Hook configuration

ralph/                       # Ralph autonomous loop
├── loop.sh                 # Main loop script
├── PROMPT_unified.md       # + Archon sync
├── PROMPT_plan.md
├── PROMPT_verify.md
├── AGENTS.md
├── IMPLEMENTATION_PLAN.md
└── specs/

ARCHON-INTEGRATION.md       # Archon documentation
```

## Fallback Behavior

All commands gracefully handle missing Archon:

1. Log warning: "Archon not configured, using file-based tracking"
2. Skip Archon-specific phases
3. Continue with file-based state management
4. All workflows remain fully functional

## Quick Start

### New Feature Development

```bash
# 1. Create PRD
/prp-prd My new feature description

# 2. Generate implementation plan (creates Archon project)
/prp-plan .claude/PRPs/prds/my-new-feature.prd.md

# 3. Implement (updates Archon tasks)
/prp-implement .claude/PRPs/plans/my-new-feature.plan.md

# 4. Validate
/prp-validate

# 5. Create PR
/prp-pr
```

### Bug Fix Workflow

```bash
# 1. Investigate issue (creates Archon task)
/prp-issue-investigate #123

# 2. Fix (updates Archon task to done)
/prp-issue-fix .claude/PRPs/issues/issue-123.md
```

### Autonomous Development

```bash
# Run Ralph loop for autonomous implementation
./ralph/loop.sh 5
```

## Key Principles

1. **Archon First** - When available, Archon is the source of truth for task state
2. **Validation Always** - Run checks after every change
3. **Tests Required** - No task complete without passing tests
4. **Document Everything** - Plans, investigations, and reviews are saved as artifacts
5. **Graceful Fallback** - System works with or without Archon
