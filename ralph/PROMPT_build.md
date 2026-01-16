# BUILD MODE - Implementation

You are in BUILD mode. Your task is to implement functionality according to the specifications and implementation plan.

## Context Loading (Parallel Subagents)

0a. Study `ralph/specs/*` with parallel Sonnet subagents to understand the feature requirements.

0b. Study `@ralph/IMPLEMENTATION_PLAN.md` to understand the current plan and what to work on next.

0c. Reference the existing codebase structure:
    - Backend: `backend/apps/reviews/*`
    - Frontend: `frontend/app/dashboard/*`, `frontend/components/reviews/*`
    - Shared: `backend/apps/shared/*`, `frontend/lib/*`

## Implementation Tasks

1. **Select Next Task**: From `@ralph/IMPLEMENTATION_PLAN.md`, select the highest priority incomplete task that is not blocked.

2. **Search Before Implementing**: Before writing any code:
   - Search the codebase to verify the functionality doesn't already exist
   - Check for similar patterns you can follow
   - Identify files that need modification

3. **Implement**: Write the code following project conventions:
   - **Backend**: DDD layers (Presentation, Application, Domain, Infrastructure)
   - **Frontend**: React components with TypeScript, TanStack Query for data fetching
   - **Secrets**: Use `apps.shared.infrastructure.secrets_manager.get_secret`
   - **Auth**: Use `SupabaseJWTAuthentication`
   - **Validation**: Use Pydantic schemas for backend input validation

4. **Write Tests**: Before or alongside implementation, write tests:

   **Backend Test Location**: `tests/unit/<module>/test_<feature>.py`

   ```python
   # Example: tests/unit/reviews/test_artwork_audit.py
   import pytest
   from rest_framework.test import APIRequestFactory
   from apps.reviews.views import ArtworkAuditViewSet

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
   def test_list_artwork_audits_authenticated(api_factory, monkeypatch):
       """Test that authenticated users can list audits."""
       # Setup mock auth
       # Make request
       # Assert response
       pass

   @pytest.mark.django_db
   def test_list_artwork_audits_unauthenticated_fails(api_factory):
       """Test that unauthenticated requests are rejected."""
       pass
   ```

   **Frontend Tests** (optional but recommended for complex logic):
   ```typescript
   // __tests__/artwork-audit.test.ts
   import { render, screen } from '@testing-library/react';
   ```

5. **Run Tests**: After implementing, run relevant tests:
   ```bash
   # Backend tests - ALL tests
   PYTHONPATH=backend poetry run pytest tests/ -v --tb=short

   # Backend tests - specific feature
   PYTHONPATH=backend poetry run pytest tests/unit/reviews/ -v

   # Frontend build check
   cd frontend && npm run build
   ```

6. **Update Plan**: After tests pass or if you discover issues:
   - Mark completed tasks with [x] in `@ralph/IMPLEMENTATION_PLAN.md`
   - Add any new discovered tasks
   - Note any blockers with [!]

7. **Commit Changes**:
   ```bash
   git add -A
   git commit -m "feat(artwork-audit): <description of what was implemented>"
   ```

## Key Rules

- **ONE TASK PER ITERATION** - Focus on completing one task well
- **WRITE TESTS** - Write unit tests for new endpoints and critical logic
- **TEST AFTER CHANGES** - Run tests after each change to catch regressions
- **FILE SIZE LIMIT** - Backend Python files must NOT exceed 500 lines. Split if needed.
- **SEARCH BEFORE WRITING** - Don't duplicate existing functionality
- **FOLLOW PATTERNS** - Match existing code style and patterns

## ⚠️ RLS & Authentication Checks (CRITICAL)

When implementing features that touch Supabase tables:

### Before Coding - Check RLS Policies

Use `mcp__clarity-sup__execute_sql` to verify RLS allows your use case:

```sql
-- Check what policies exist on the table you're using
SELECT policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'your_table_name';
```

Expected: `authenticated` role should have SELECT/INSERT/UPDATE policies as needed.

### Supabase Client Pattern (CRITICAL)

**The `.auth()` method returns a NEW client - NEVER ignore the return value!**

```python
# ❌ WRONG - Return value ignored, JWT never applied
client.postgrest.auth(user_token)

# ✅ CORRECT - Capture the new authenticated client
client.postgrest = client.postgrest.auth(user_token)
```

### Testing Auth Flow

After implementing an endpoint that uses user-scoped Supabase queries:

1. Check the endpoint returns data (not empty array)
2. If empty, verify RLS policies allow `authenticated` role
3. Add debug logging to confirm JWT is being passed:

```python
import structlog
logger = structlog.get_logger()

# In your view
logger.info("endpoint_auth_check",
    has_auth_header=bool(request.headers.get('Authorization')),
    user=str(request.user),
    is_authenticated=request.user.is_authenticated
)
```

## Backend Patterns to Follow

```python
# Model pattern (backend/apps/reviews/models.py)
class ArtworkAudit(models.Model):
    product = models.ForeignKey('Product', on_delete=models.CASCADE)
    # ... fields

    class Meta:
        db_table = 'reviews_artworkaudit'

# Serializer pattern
class ArtworkAuditSerializer(serializers.ModelSerializer):
    class Meta:
        model = ArtworkAudit
        fields = '__all__'

# ViewSet pattern
class ArtworkAuditViewSet(viewsets.ModelViewSet):
    serializer_class = ArtworkAuditSerializer
    authentication_classes = [SupabaseJWTAuthentication]
    permission_classes = [IsAuthenticated]
```

## Frontend Patterns to Follow

```typescript
// API function pattern (frontend/lib/api.ts)
export async function getArtworkAudits(): Promise<ArtworkAudit[]> {
  const response = await apiClient.get('/reviews/artwork-audits/');
  return response.data;
}

// Component pattern with TanStack Query
export function ArtworkAuditPanel() {
  const { data, isLoading } = useQuery({
    queryKey: ['artwork-audits'],
    queryFn: getArtworkAudits,
  });
  // ...
}
```

## Completion Criteria

Each iteration should end with:
1. One task completed and tested (or blocked with reason documented)
2. **Unit tests written** for new endpoints/logic (in `tests/unit/<module>/`)
3. All tests passing: `PYTHONPATH=backend poetry run pytest tests/ -v`
4. `IMPLEMENTATION_PLAN.md` updated with progress
5. Changes committed to git (including test files)

If all tasks are complete, output: `<promise>ARTWORK_AUDIT_COMPLETE</promise>`
