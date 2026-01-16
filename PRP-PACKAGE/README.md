# PRP Package - Clarity Implementation

This package contains all PRP (Product Requirement Prompts) related files from the Clarity codebase, ready to be forked into a hybrid implementation.

## Structure

```
PRP-PACKAGE/
├── README.md                    # This file
├── settings-reference.json      # Claude hooks configuration reference
├── commands/                    # Claude slash commands
│   ├── create-plan.md          # /create-plan - Creates implementation plans
│   ├── execute-plan.md         # /execute-plan - Executes plans with Archon
│   ├── validate.md             # /validate - Validation command
│   └── primer.md               # /primer - Context priming
├── ralph/                       # Autonomous loop system
│   ├── README.md               # Ralph documentation
│   ├── loop.sh                 # Main orchestration script
│   ├── PROMPT_unified.md       # Unified mode (implement + test + verify)
│   ├── PROMPT_plan.md          # Planning mode
│   ├── PROMPT_build.md         # Build mode (legacy)
│   ├── PROMPT_verify.md        # Visual verification mode
│   ├── AGENTS.md               # Agent operational guide
│   ├── IMPLEMENTATION_PLAN.md  # Shared state tracker
│   └── specs/                  # Feature specifications
│       └── *.md
├── agents/                      # Specialized agent definitions
│   ├── backend-architect.md
│   ├── frontend_developer.md
│   ├── python-pro.md
│   ├── security-auditor.md
│   ├── api-security-audit.md
│   └── supabase-schema-architect.md
└── example-plans/               # Example plan documents
    ├── artwork-generation-plan.md
    └── plan.md
```

## Key Components

### 1. Commands (`commands/`)

These are Claude Code slash commands:

| Command | Purpose |
|---------|---------|
| `/create-plan` | Creates comprehensive implementation plans with research phase |
| `/execute-plan [path]` | Executes plans with mandatory Archon task management |
| `/validate` | Runs validation suite |
| `/primer` | Primes context for new sessions |

### 2. Ralph Loop (`ralph/`)

Autonomous AI development loop based on [ghuntley/how-to-ralph-wiggum](https://github.com/ghuntley/how-to-ralph-wiggum).

**Key Principle**: Fresh context for each iteration. Progress tracked in:
- `IMPLEMENTATION_PLAN.md` - Task status
- Git commits - Code changes

**Modes**:
- **Unified** (recommended): `./ralph/loop.sh` - implement + test + verify
- **Planning**: `./ralph/loop.sh plan 5` - gap analysis
- **Verify**: `./ralph/loop.sh verify 3` - visual testing

### 3. Agents (`agents/`)

Specialized agent definitions for Task tool subagent types.

### 4. Integration Points

**Archon MCP**: This implementation heavily integrates with Archon for:
- Task management (`find_tasks`, `manage_task`)
- Project tracking (`find_projects`, `manage_project`)
- Knowledge base (`rag_search_knowledge_base`, `rag_search_code_examples`)

**Hooks**: See `settings-reference.json` for hook configuration.

## Differences from Wirasm/PRPs-agentic-eng

| Aspect | This Package | Wirasm |
|--------|--------------|--------|
| Task Management | Archon MCP (external) | File-based |
| Ralph Loop | Shell script (fresh sessions) | In-session skill |
| Namespace | `/create-plan`, `/execute-plan` | `/prp-*` prefix |
| File Storage | `PRPs/`, `DOCUMENTS/` | `.claude/PRPs/` |
| Issue Workflow | Not included | `/prp-issue-*`, `/prp-debug` |

## Creating a Hybrid

To merge with Wirasm's approach, consider:

1. **Add their issue commands**: `/prp-issue-investigate`, `/prp-issue-fix`, `/prp-debug`
2. **Add their review command**: `/prp-review`
3. **Keep this Ralph**: External orchestration is more robust
4. **Keep Archon integration**: Superior task tracking
5. **Namespace**: Either `/prp-*` for all, or keep split

## Installation

To use in another project:

1. Copy `commands/` to `.claude/commands/`
2. Copy `agents/` to `.claude/agents/`
3. Copy `ralph/` to project root
4. Add hook configuration from `settings-reference.json` to `.claude/settings.json`
5. Update paths in command files as needed

## License

Internal use - derived from Clarity codebase.
