# QA MODE - Test Generation & Coverage Improvement

You are running in a QA-focused loop. Each iteration:
1. **Syncs** current test state and coverage data
2. **Identifies** source files with missing or insufficient tests
3. **Generates** tests for the highest-priority gap
4. **Executes** tests and records results
5. **Reports** metrics and commits changes

**The goal is to systematically increase test coverage across the project.**

---

## Phase 0: Context Loading (Parallel Subagents)

Use parallel Sonnet subagents to load context quickly:

0a. Study `ralph/IMPLEMENTATION_PLAN.md` - Check for any QA-related tasks

0b. Read `.claude/PRPs/qa/test-results.csv` if it exists - Current test state

0c. Check latest coverage data:
    - `.claude/PRPs/coverage/` - Previous coverage reports
    - Run coverage commands to get current baseline

0d. Study project structure:
    - `apps/server/src/` - Bun server source files
    - `apps/client/src/` - Vue client source files
    - Existing test directories and patterns

---

## Phase 0.5: Archon Sync (CRITICAL)

**Before selecting a test target, synchronize with Archon if available.**

### Check Archon Availability

```python
# Try to access Archon MCP
try:
    projects = find_projects(query="qa")
    archon_available = True
except:
    archon_available = False
    print("Archon not configured - using file-based tracking only")
```

### If Archon Available

```python
# 1. Get the QA project or create one
projects = find_projects(query="qa-coverage")
if not projects:
    manage_project("create", name="QA Coverage Improvement", description="Systematic test generation")

# 2. Get existing QA tasks
qa_tasks = find_tasks(filter_by="project", filter_value=project_id)

# 3. Sync with local state
archon_status = {task["title"]: task["status"] for task in qa_tasks}
```

### Fallback (Archon Not Available)

If Archon is not configured:
1. Log warning: "Archon not configured, using file-based tracking"
2. Skip this phase
3. Use test-results.csv and coverage reports as source of truth
4. Continue with Phase 1

---

## Phase 1: Identify Coverage Gaps

Scan the project to find source files without corresponding test files.

### Discovery Strategy

```bash
# 1. Find all source files (server)
find apps/server/src -name "*.ts" -not -path "*__tests__*" -not -name "*.test.*" -not -name "*.spec.*"

# 2. Find all source files (client)
find apps/client/src -name "*.ts" -o -name "*.vue" | grep -v __tests__ | grep -v ".test." | grep -v ".spec."

# 3. Find existing test files
find apps/server/src -path "*__tests__*" -name "*.test.*"
find apps/client/src -path "*__tests__*" -name "*.test.*"

# 4. Cross-reference to find gaps
```

### Prioritization Criteria

Rank untested files by priority:

| Priority | Criteria | Weight |
|----------|----------|--------|
| P0 | Database/auth/API handlers | Highest |
| P1 | Files changed recently (`git log --since="2 weeks ago"`) | High |
| P2 | Files with highest complexity (line count, cyclomatic) | Medium |
| P3 | Utility/helper modules | Normal |
| P4 | Config, types, constants | Low |

### Critical Path Files (Always P0)

- Database operations (SQLite queries, migrations)
- Authentication/authorization logic
- API route handlers
- WebSocket connection handlers
- Data validation/sanitization

---

## Phase 2: Select Test Target

Pick the single highest-priority untested file.

### With Archon Available

```python
# 1. Check if there's already a "doing" QA task
doing_tasks = find_tasks(filter_by="status", filter_value="doing")
if doing_tasks:
    selected_file = doing_tasks[0]  # Resume in-progress task
else:
    # 2. Create task for the selected file
    manage_task("create",
        project_id=qa_project_id,
        title=f"Add tests for {selected_file}",
        status="doing"
    )
```

### Without Archon

1. Select the highest-priority gap from Phase 1
2. Log the selection: "Selected: {file} (priority: {P0-P4}, reason: {reason})"

---

## Phase 3: Generate Tests

Create tests for the selected file following project conventions.

### Server Tests (Bun)

Test location: `apps/server/src/__tests__/{module}.test.ts`

```typescript
import { describe, it, expect, beforeEach, afterEach, mock } from "bun:test";

describe("{ModuleName}", () => {
  // Arrange (shared setup)
  beforeEach(() => {
    // Setup test fixtures, mocks
  });

  afterEach(() => {
    // Cleanup
  });

  describe("{functionName}", () => {
    it("should {expected behavior} when {condition}", () => {
      // Arrange
      const input = { /* test data */ };

      // Act
      const result = functionUnderTest(input);

      // Assert
      expect(result).toEqual(expectedOutput);
    });

    it("should handle edge case: {description}", () => {
      // Arrange
      const edgeInput = { /* edge case data */ };

      // Act & Assert
      expect(() => functionUnderTest(edgeInput)).toThrow();
    });
  });
});
```

### Client Tests (Vitest)

Test location: `apps/client/src/{composables|components}/__tests__/{module}.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount } from "@vue/test-utils";

describe("{ComponentName}", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders correctly with default props", () => {
    // Arrange
    const wrapper = mount(ComponentUnderTest, {
      props: { /* default props */ },
    });

    // Assert
    expect(wrapper.exists()).toBe(true);
    expect(wrapper.text()).toContain("expected text");
  });

  it("emits {event} when {action}", async () => {
    // Arrange
    const wrapper = mount(ComponentUnderTest);

    // Act
    await wrapper.find("button").trigger("click");

    // Assert
    expect(wrapper.emitted("eventName")).toBeTruthy();
  });
});
```

### Test Coverage Requirements

For each file, tests MUST cover:

| Category | Required Tests |
|----------|---------------|
| Happy path | Normal inputs -> expected output |
| Edge cases | Empty input, null, undefined, boundary values |
| Error handling | Invalid input -> appropriate error |
| Integration points | Mock external dependencies, verify calls |

---

## Phase 4: Execute Tests

Run the generated tests and capture results.

### Server Tests

```bash
cd apps/server && bun test src/__tests__/{module}.test.ts --verbose 2>&1
```

### Client Tests

```bash
cd apps/client && npx vitest run src/{path}/__tests__/{module}.test.ts --reporter=verbose 2>&1
```

### Test Outcome Actions

| Result | Action |
|--------|--------|
| All tests pass | Proceed to Phase 5 |
| Tests fail (implementation bug found) | File a bug report using `.claude/templates/qa/bug-report.md`, then fix test expectations or note the bug |
| Tests fail (test error) | Fix the test code, re-run |
| Import/setup errors | Fix test configuration, re-run |

**Iterate up to 3 times to get tests passing. If still failing after 3 attempts, document the issue and move on.**

---

## Phase 5: Report & Commit

### 5.1 Record Results

Create or update `.claude/PRPs/qa/test-results.csv`:

```csv
date,file,test_file,tests_written,tests_passing,tests_failing,category,priority
2026-02-28,apps/server/src/db.ts,apps/server/src/__tests__/db.test.ts,5,5,0,unit,P0
```

### 5.2 Update Coverage

```bash
# Server coverage
cd apps/server && bun test --coverage 2>&1 | tail -20

# Client coverage
cd apps/client && npx vitest run --coverage 2>&1 | tail -20
```

### 5.3 Update Archon (if available)

```python
if archon_available and current_task_id:
    if all_tests_pass:
        manage_task("update", task_id=current_task_id, status="done")
    else:
        manage_task("update", task_id=current_task_id, status="review",
                    notes=f"{passing}/{total} tests passing")
```

### 5.4 Commit Changes

```bash
git add -A
git commit -m "test: add tests for {file}

- {N} tests written ({passing} passing, {failing} failing)
- Category: {unit|integration|e2e}
- Priority: {P0-P4}
- Coverage: {before}% -> {after}%

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Key Rules

1. **ONE FILE PER ITERATION** - Focus on fully testing one source file
2. **AAA PATTERN** - All tests follow Arrange/Act/Assert
3. **PRIORITIZE CRITICAL PATHS** - DB, auth, and API handlers first
4. **RECORD EVERYTHING** - Update test-results.csv after every iteration
5. **DON'T SKIP FAILURES** - If tests reveal bugs, file bug reports
6. **MATCH CONVENTIONS** - Use bun:test for server, vitest for client
7. **MOCK EXTERNAL DEPS** - Never hit real databases or APIs in tests
8. **COMMIT AFTER EACH FILE** - Small, focused commits

---

## Iteration Outcome

Each iteration ends with ONE of:

| Outcome | What to Output | Archon Action |
|---------|----------------|---------------|
| Tests written and passing | Update CSV, commit, proceed | status -> done |
| Tests written, some failing (bug found) | File bug report, commit tests, proceed | Add bug note |
| Could not generate tests (complex setup) | Document blocker, skip to next file | status -> review |
| All files have tests | `<promise>ALL_TASKS_COMPLETE</promise>` | All tasks done |

---

## Coverage Targets

Track progress toward these goals:

| Metric | Target | Priority |
|--------|--------|----------|
| Overall line coverage | 80% | High |
| Critical path coverage | 90% | Highest |
| Branch coverage | 70% | Medium |
| Files with zero tests | 0 | Highest |

---

## Summary: The QA Loop

```
┌──────────────────────────────────────────────────────────────────┐
│  SYNC STATE → FIND GAPS → SELECT TARGET → WRITE TESTS → RUN    │
│       │            │                              │              │
│       │            ↓                              ↓              │
│       │     Prioritize by                  ┌───────────┐        │
│       │     criticality                    │ PASS?     │        │
│       │                                    └─────┬─────┘        │
│       │                          ┌───────────────┴─────────┐    │
│       │                          ↓                         ↓    │
│       │                     YES: Record              NO: Fix    │
│       │                          │                   (3 tries)  │
│       │                          ↓                         │    │
│       │                   UPDATE CSV                       │    │
│       │                          │                         │    │
│       └──────────────────── COMMIT ←───────────────────────┘    │
│                                  │                               │
│                                  ↓                               │
│                            NEXT FILE                             │
└──────────────────────────────────────────────────────────────────┘
```

---

## Bug Report Integration

When tests reveal actual bugs in the codebase:

1. Create bug report from template: `.claude/templates/qa/bug-report.md`
2. Save to `.claude/PRPs/qa/bugs/BUG-{CATEGORY}-{NUMBER}.md`
3. If Archon available, create a task for the bug fix
4. Continue writing tests (don't fix bugs in QA mode - just document them)

---

## Security Test Integration

For P0 files (auth, DB, API), also check against:
- `.claude/templates/qa/owasp-checklist.md` - OWASP Top 10 items
- Write security-specific test cases where applicable
- Flag any OWASP violations as P0 bugs
