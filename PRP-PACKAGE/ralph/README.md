# Ralph Wiggum - Autonomous AI Development Loop

This directory contains the implementation of the [ghuntley/how-to-ralph-wiggum](https://github.com/ghuntley/how-to-ralph-wiggum) methodology for autonomous Claude-driven development.

## Key Principle: Fresh Sessions

Each iteration runs with a **completely fresh context window**. Progress is persisted in:
- `IMPLEMENTATION_PLAN.md` - Task tracking and status
- Git commits - Code changes

This prevents context bloat and ensures consistent behavior.

## Key Principle: Tests Are Verification

**Tests are not optional - they prove the work was done correctly.**

Each iteration must:
1. Write tests that define success
2. Implement the feature
3. Run tests to verify completion
4. Only proceed if tests pass

Without tests, there's no proof the code actually works.

## Directory Structure

```
ralph/
├── loop.sh               # Main orchestration script
├── PROMPT_unified.md     # Unified mode (RECOMMENDED) - implement + test + verify
├── PROMPT_plan.md        # Planning mode (gap analysis only)
├── PROMPT_build.md       # Build mode (legacy - implementation only)
├── PROMPT_verify.md      # Verify mode (visual testing)
├── AGENTS.md             # Operational guide (commands, constraints)
├── IMPLEMENTATION_PLAN.md  # Shared state between iterations
├── specs/                # Feature specifications
│   └── artwork-audit.md  # Artwork Audit Module spec
├── logs/                 # Iteration logs
└── README.md             # This file
```

## Usage

### Unified Mode (RECOMMENDED)

The unified mode combines implementation, testing, and verification in one loop.
**This is the recommended approach** - tests are the verification that work is done.

```bash
# Run unified mode indefinitely (RECOMMENDED)
./ralph/loop.sh

# Run 10 unified iterations
./ralph/loop.sh 10
```

Each unified iteration:
1. Selects next task from plan
2. Writes tests first (TDD)
3. Implements the feature
4. Runs tests - MUST PASS
5. Visual verification (if frontend)
6. Commits and proceeds to next task

### Planning Mode (Initial Analysis)

Use for initial gap analysis before implementation.

```bash
./ralph/loop.sh plan 3
```

### Legacy Modes

```bash
# Build only (no automatic testing)
./ralph/loop.sh build 10

# Verify only (visual testing)
./ralph/loop.sh verify 3
```

## Recommended Workflow

1. **Start with Planning**: Analyze the codebase
   ```bash
   ./ralph/loop.sh plan 3
   ```

2. **Review the Plan**: Check `IMPLEMENTATION_PLAN.md` for accuracy

3. **Run Unified Mode**: Implement with automatic verification
   ```bash
   ./ralph/loop.sh 20
   ```

4. **Monitor**: Check `logs/` for iteration details

5. **Intervene if Needed**: If tests keep failing, Ctrl+C and fix manually

## Completion

When all tasks in `IMPLEMENTATION_PLAN.md` are marked [x], the build mode will output:
```
<promise>ARTWORK_AUDIT_COMPLETE</promise>
```

## Current Project: Artwork Audit Module (AGENT-105)

A 7-panel unified audit workspace for artwork/label auditing:
- Left Sidebar: Highlighted Text, Ingredients
- Main Area: Pack Copy, Artwork, 3x Selectable panels

See `specs/artwork-audit.md` for full specification.

## Troubleshooting

### Loop exits unexpectedly
Check `logs/iteration_N.log` for error details.

### Permissions error
Run: `chmod +x ralph/loop.sh`

### Tests failing
The loop will continue but log the failure. Fix manually if needed.

## References

- [Original Ralph Wiggum by Geoffrey Huntley](https://ghuntley.com/ralph)
- [how-to-ralph-wiggum Repository](https://github.com/ghuntley/how-to-ralph-wiggum)
