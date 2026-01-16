# UNIFIED MODE - Implement, Test, Verify

You are running in a unified development loop. Each iteration:
1. **Syncs** with Archon (if available) for task state
2. **Selects** the next task
3. **Writes tests** to define success criteria
4. **Implements** the feature
5. **Runs tests** to verify completion
6. **Updates** Archon task status
7. **Only proceeds** if tests pass

**Tests are not optional - they are the verification that work is done.**

---

## Phase 0: Context Loading (Parallel Subagents)

Use parallel Sonnet subagents to load context quickly:

0a. Study `ralph/specs/*` - Feature requirements

0b. Study `ralph/IMPLEMENTATION_PLAN.md` - Current progress and next tasks

0c. Study shared infrastructure:
    - `backend/apps/shared/*` - Utilities (supabase_client, secrets_manager)
    - `backend/apps/reviews/models.py` - Existing models
    - `frontend/lib/*` - API client and utilities
    - `tests/auth/test_supabase_jwt_auth.py` - Test patterns to follow

0d. Reference existing code patterns:
    - Backend: `backend/apps/reviews/*`
    - Frontend: `frontend/components/reviews/*`

---

## Phase 0.5: Archon Sync (CRITICAL)

**Before selecting a task, synchronize with Archon if available.**

### Check Archon Availability

```python
# Try to access Archon MCP
try:
    # Look for project matching current feature
    projects = find_projects(query="<current-feature-name>")
    archon_available = True
except:
    archon_available = False
    print("Archon not configured - using file-based tracking only")
```

### If Archon Available

```python
# 1. Get the relevant project
project = find_projects(query="<feature-name>")[0]
project_id = project["id"]

# 2. Get all tasks from Archon
archon_tasks = find_tasks(filter_by="project", filter_value=project_id)

# 3. Build status map
archon_status = {task["title"]: task["status"] for task in archon_tasks}
```

### Sync IMPLEMENTATION_PLAN.md with Archon

**Archon is the source of truth.** Update the plan file to match:

```python
for task_name, archon_status in archon_status.items():
    # Find corresponding checkbox in IMPLEMENTATION_PLAN.md
    if archon_status == "done":
        # Mark as [x] in plan
        update_checkbox(task_name, checked=True)
    elif archon_status == "doing":
        # Mark as [>] in plan (in progress)
        update_checkbox(task_name, in_progress=True)
    else:  # todo
        # Mark as [ ] in plan
        update_checkbox(task_name, checked=False)
```

### Check for Completion

```python
# If ALL Archon tasks are "done"
if all(t["status"] == "done" for t in archon_tasks):
    print("<promise>ALL_TASKS_COMPLETE</promise>")
    # Loop should terminate
```

### Fallback (Archon Not Available)

If Archon is not configured:
1. Log warning: "Archon not configured, using file-based tracking"
2. Skip this phase
3. Use IMPLEMENTATION_PLAN.md checkboxes as source of truth
4. Continue with Phase 1

---

## Phase 1: RLS Policy Check (CRITICAL)

**Before ANY database-touching work**, verify RLS policies allow your use case:

```sql
-- Use mcp__clarity-sup__execute_sql
SELECT tablename, policyname, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'your_table';
```

Expected: `authenticated` role should have SELECT/INSERT/UPDATE policies as needed.

If a required policy is missing, add a task to create it BEFORE proceeding.

### Supabase Client Pattern (CRITICAL)

**The `.auth()` method returns a NEW client - NEVER ignore the return value!**

```python
# WRONG - Return value ignored, JWT never applied
client.postgrest.auth(user_token)

# CORRECT - Capture the new authenticated client
client.postgrest = client.postgrest.auth(user_token)
```

---

## Phase 2: Select Next Task

### With Archon Available

```python
# 1. Get tasks with "todo" status
todo_tasks = find_tasks(filter_by="status", filter_value="todo")

# 2. Sort by task_order (priority)
sorted_tasks = sorted(todo_tasks, key=lambda t: t.get("task_order", 0), reverse=True)

# 3. Select highest priority non-blocked task
for task in sorted_tasks:
    if not is_blocked(task):
        selected_task = task
        break

# 4. Update status to "doing"
manage_task("update", task_id=selected_task["id"], status="doing")
```

### Without Archon

1. Read `ralph/IMPLEMENTATION_PLAN.md`
2. Find the highest priority incomplete task that is NOT blocked
3. If a task is blocked, note the blocker and skip to next task
4. If ALL tasks are complete, output: `<promise>ALL_TASKS_COMPLETE</promise>`

---

## Phase 3: Write Tests FIRST

**Before writing any implementation code**, create tests that define success:

### Backend Test Template

Create test file: `tests/unit/<module>/test_<feature>.py`

```python
import pytest
from rest_framework.test import APIRequestFactory
from rest_framework import status

@pytest.fixture
def api_factory():
    return APIRequestFactory()

@pytest.fixture(autouse=True)
def use_test_db(settings):
    settings.DATABASES["default"] = {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
    }

@pytest.mark.django_db
def test_endpoint_requires_authentication(api_factory):
    """Unauthenticated requests should be rejected."""
    from apps.reviews.views import YourViewSet
    view = YourViewSet.as_view({'get': 'list'})
    request = api_factory.get('/api/your-endpoint/')
    response = view(request)
    assert response.status_code == status.HTTP_401_UNAUTHORIZED

@pytest.mark.django_db
def test_endpoint_returns_data_authenticated(api_factory, monkeypatch):
    """Authenticated requests should return data."""
    # Mock authentication
    # Make request
    # Assert response contains expected data
    pass
```

### Run Tests - MUST PASS (even if empty/placeholder)

```bash
PYTHONPATH=backend poetry run pytest tests/unit/<module>/ -v --tb=short
```

**If tests fail at this point**, they should fail because the feature doesn't exist yet (expected).

---

## Phase 4: Implement the Feature

Now implement to make the tests pass:

### Backend Patterns

```python
# Model (backend/apps/reviews/models.py)
class YourModel(models.Model):
    # fields...
    class Meta:
        db_table = 'reviews_yourmodel'

# Serializer (backend/apps/reviews/serializers/)
class YourSerializer(serializers.ModelSerializer):
    class Meta:
        model = YourModel
        fields = '__all__'

# ViewSet (backend/apps/reviews/views/)
class YourViewSet(viewsets.ModelViewSet):
    serializer_class = YourSerializer
    authentication_classes = [SupabaseJWTAuthentication]
    permission_classes = [IsAuthenticated]
```

### Frontend Patterns

```typescript
// API function (frontend/lib/api.ts)
export async function getYourData(): Promise<YourType[]> {
  const response = await apiClient.get('/reviews/your-endpoint/');
  return response.data;
}

// Component with React Query
export function YourComponent() {
  const { data, isLoading } = useQuery({
    queryKey: ['your-data'],
    queryFn: getYourData,
  });
  // ...
}
```

---

## Phase 5: Run Tests - MUST PASS

After implementation, run tests again:

```bash
# Run the specific tests you wrote
PYTHONPATH=backend poetry run pytest tests/unit/<module>/test_<feature>.py -v --tb=short

# Run ALL tests to check for regressions
PYTHONPATH=backend poetry run pytest tests/ -v --tb=short
```

### Test Outcome Actions

| Result | Action |
|--------|--------|
| All tests pass | Proceed to Phase 6 |
| Tests fail | Fix implementation, re-run tests |
| Still failing | Add debug logging, investigate root cause |

**DO NOT proceed to Phase 6 if tests are failing.**

---

## Phase 6: Visual Verification (Frontend Work Only)

If the task involved frontend changes, verify visually:

### Ground Truth Check

Before UI testing, verify data exists at database layer:

```sql
-- Use mcp__clarity-sup__execute_sql
SELECT count(*) FROM your_table WHERE your_condition;
```

If database returns 0 but data should exist - RLS/auth issue. Debug before proceeding.

### Playwright Visual Test

```bash
# Navigate to the page
mcp__playwright__browser_navigate --url "http://host.docker.internal:3000/dashboard/your-page"

# Take screenshot
mcp__playwright__browser_take_screenshot --name "your-feature"

# Check console for errors
mcp__playwright__browser_console_messages
```

### Visual Verification Checklist

- [ ] Page loads without errors
- [ ] Expected data displays (matches database count)
- [ ] UI elements are interactive
- [ ] No console errors

---

## Phase 7: File Size Compliance

**Backend Python files must NOT exceed 500 lines.**

```bash
wc -l backend/apps/<module>/**/*.py | awk '$1 > 500 {print "VIOLATION:", $0}'
```

If violations found:
1. Split into smaller modules (e.g., `views.py` -> `views/`)
2. Update imports
3. Re-run tests to verify refactoring didn't break anything

---

## Phase 8: Update Plan, Archon & Commit

### 8.1 Update Archon Task (if available)

```python
if archon_available and current_task_id:
    # Move task to "review" (awaiting verification) or "done"
    if tests_pass and visual_verification_pass:
        manage_task("update", task_id=current_task_id, status="done")
    else:
        manage_task("update", task_id=current_task_id, status="review")
```

### 8.2 Update IMPLEMENTATION_PLAN.md

1. Mark the task as complete:
   ```markdown
   - [x] Task description
   ```

2. Add any discovered tasks or blockers

### 8.3 Commit ALL changes

```bash
git add -A
git commit -m "feat(<scope>): <description>

- Implemented <feature>
- Added tests: tests/unit/<module>/test_<feature>.py
- All tests passing
- Archon task: <task_id> -> done

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Key Rules

1. **ARCHON SYNC FIRST** - Synchronize with Archon before starting work
2. **TESTS ARE MANDATORY** - No task is complete without passing tests
3. **ONE TASK PER ITERATION** - Focus on completing one task fully
4. **RLS CHECK FIRST** - Verify database access before coding
5. **FILE SIZE LIMIT** - Backend Python files <= 500 lines
6. **SEARCH BEFORE WRITING** - Don't duplicate existing functionality
7. **FOLLOW PATTERNS** - Match existing code style
8. **UPDATE ARCHON** - Keep task statuses synchronized

---

## Iteration Outcome

Each iteration ends with ONE of:

| Outcome | What to Output | Archon Action |
|---------|----------------|---------------|
| Task completed, tests pass | Mark [x] in plan, commit, proceed | status -> done |
| Task blocked | Mark [!] with reason, skip to next task | Add blocker note |
| Tests still failing | Document issue, attempt fix, or escalate | status remains doing |
| All tasks complete | `<promise>ALL_TASKS_COMPLETE</promise>` | All tasks done |

---

## Test Coverage Requirements

For each new feature, tests MUST cover:

| Category | Required Tests |
|----------|---------------|
| Authentication | Unauthenticated request -> 401 |
| Authorization | Wrong role -> 403 |
| Happy path | Valid request -> 200 + data |
| Edge cases | Empty data, invalid input |
| RLS | Data access respects row-level security |

---

## Debugging Checklist

If something isn't working:

1. **Check RLS policies** - Is `authenticated` allowed?
2. **Check JWT flow** - Is `.auth()` return value captured?
3. **Check backend logs** - Add `structlog.get_logger()` debug output
4. **Check frontend network** - Is the request being made with Authorization header?
5. **Check database directly** - Does the expected data exist?
6. **Check Archon sync** - Are task statuses accurate?

---

## Summary: The Unified Loop with Archon

```
┌──────────────────────────────────────────────────────────────────┐
│  ARCHON SYNC → SELECT TASK → WRITE TESTS → IMPLEMENT → RUN TESTS│
│       │              │                                    │      │
│       │              ↓                                    ↓      │
│       │     Archon: doing                       ┌─────────────┐  │
│       │                                         │ TESTS PASS? │  │
│       │                                         └──────┬──────┘  │
│       │                                                │         │
│       │                            ┌───────────────────┴───────┐ │
│       │                            ↓                           ↓ │
│       │                       YES: Proceed               NO: Fix │
│       │                            │                           │ │
│       │                            ↓                           │ │
│       │                     VISUAL VERIFY                      │ │
│       │                     (if frontend)                      │ │
│       │                            │                           │ │
│       │                            ↓                           │ │
│       └─────────────────── ARCHON: done ←──────────────────────┘ │
│                                    │                             │
│                                    ↓                             │
│                              COMMIT & NEXT                       │
└──────────────────────────────────────────────────────────────────┘
```

The key additions from before:
1. **Archon Sync** at start ensures task state is accurate
2. **Archon Updates** track progress through the lifecycle
3. **Source of Truth** - Archon status takes precedence over file checkboxes

---

## Archon Task Lifecycle in Ralph Loop

```
Ralph Iteration Start
        │
        ↓
┌───────────────┐
│ Phase 0.5:    │
│ Archon Sync   │ ── Sync plan checkboxes with Archon
└───────┬───────┘
        │
        ↓
┌───────────────┐
│ Phase 2:      │
│ Select Task   │ ── manage_task("update", status="doing")
└───────┬───────┘
        │
        ↓
┌───────────────┐
│ Phases 3-7:   │
│ Implement     │ ── Task remains in "doing"
└───────┬───────┘
        │
        ↓
┌───────────────┐
│ Phase 8:      │
│ Complete      │ ── manage_task("update", status="done")
└───────┬───────┘
        │
        ↓
    Next Iteration
```
