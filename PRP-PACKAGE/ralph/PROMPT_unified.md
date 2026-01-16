# UNIFIED MODE - Implement, Test, Verify

You are running in a unified development loop. Each iteration:
1. **Selects** the next task
2. **Writes tests** to define success criteria
3. **Implements** the feature
4. **Runs tests** to verify completion
5. **Only proceeds** if tests pass

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
# ❌ WRONG - Return value ignored, JWT never applied
client.postgrest.auth(user_token)

# ✅ CORRECT - Capture the new authenticated client
client.postgrest = client.postgrest.auth(user_token)
```

---

## Phase 2: Select Next Task

1. Read `ralph/IMPLEMENTATION_PLAN.md`
2. Find the highest priority incomplete task that is NOT blocked
3. If a task is blocked, note the blocker and skip to next task
4. If ALL tasks are complete, output: `<promise>ARTWORK_AUDIT_COMPLETE</promise>`

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
| ✅ All tests pass | Proceed to Phase 6 |
| ❌ Tests fail | Fix implementation, re-run tests |
| ❌ Still failing | Add debug logging, investigate root cause |

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

If database returns 0 but data should exist → RLS/auth issue. Debug before proceeding.

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
1. Split into smaller modules (e.g., `views.py` → `views/`)
2. Update imports
3. Re-run tests to verify refactoring didn't break anything

---

## Phase 8: Update Plan & Commit

1. Mark the task as complete in `ralph/IMPLEMENTATION_PLAN.md`:
   ```markdown
   - [x] Task description
   ```

2. Add any discovered tasks or blockers

3. Commit ALL changes (code + tests + plan):
   ```bash
   git add -A
   git commit -m "feat(artwork-audit): <description>

   - Implemented <feature>
   - Added tests: tests/unit/<module>/test_<feature>.py
   - All tests passing

   Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
   ```

---

## Key Rules

1. **TESTS ARE MANDATORY** - No task is complete without passing tests
2. **ONE TASK PER ITERATION** - Focus on completing one task fully
3. **RLS CHECK FIRST** - Verify database access before coding
4. **FILE SIZE LIMIT** - Backend Python files ≤ 500 lines
5. **SEARCH BEFORE WRITING** - Don't duplicate existing functionality
6. **FOLLOW PATTERNS** - Match existing code style

---

## Iteration Outcome

Each iteration ends with ONE of:

| Outcome | What to Output |
|---------|----------------|
| Task completed, tests pass | Mark [x] in plan, commit, proceed |
| Task blocked | Mark [!] with reason, skip to next task |
| Tests still failing | Document issue, attempt fix, or escalate |
| All tasks complete | `<promise>ARTWORK_AUDIT_COMPLETE</promise>` |

---

## Test Coverage Requirements

For each new feature, tests MUST cover:

| Category | Required Tests |
|----------|---------------|
| Authentication | Unauthenticated request → 401 |
| Authorization | Wrong role → 403 |
| Happy path | Valid request → 200 + data |
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

---

## Summary: The Unified Loop

```
┌─────────────────────────────────────────────────────────────┐
│  SELECT TASK → WRITE TESTS → IMPLEMENT → RUN TESTS         │
│                                              │              │
│                                              ↓              │
│                                    ┌─────────────────┐      │
│                                    │ TESTS PASS?     │      │
│                                    └────────┬────────┘      │
│                                             │               │
│                          ┌──────────────────┴────────────┐  │
│                          ↓                               ↓  │
│                      YES: Proceed               NO: Fix it  │
│                          │                               │  │
│                          ↓                               │  │
│                   VISUAL VERIFY                          │  │
│                   (if frontend)                          │  │
│                          │                               │  │
│                          ↓                               │  │
│                   COMMIT & NEXT ←────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

The key difference from before: **Tests are the verification gate.** Work isn't done until tests pass.
