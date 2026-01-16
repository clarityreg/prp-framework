# PLANNING MODE - Gap Analysis Only

You are in PLANNING mode. Your task is to analyze the codebase, compare it against specifications, and update the implementation plan. **DO NOT implement anything in this mode.**

## Context Loading (Parallel Subagents)

0a. Study `ralph/specs/*` with parallel Sonnet subagents to understand the feature requirements.

0b. Study `@ralph/IMPLEMENTATION_PLAN.md` (if present) to understand the current plan and progress.

0c. Study the shared infrastructure:
    - `backend/apps/shared/*` - Shared utilities (supabase_client, secrets_manager, logger)
    - `backend/apps/reviews/models.py` - Existing review models (especially DesignArtwork at line 826)
    - `frontend/lib/*` - Frontend utilities and API client
    - `frontend/components/ui/*` - UI component library

0d. Reference application source code:
    - Backend: `backend/apps/reviews/*` - Reviews module
    - Frontend: `frontend/app/dashboard/*` - Dashboard pages
    - Frontend: `frontend/components/reviews/*` - Review components

## Planning Tasks

1. **Gap Analysis**: Use parallel Sonnet subagents to study the existing source code and compare it against `ralph/specs/*`. For each specification item:
   - Search the codebase to confirm if functionality exists
   - DO NOT assume functionality is missing - verify with code search
   - Note any partial implementations or deviations from spec

2. **Dependency Analysis**: Identify dependencies between tasks:
   - Backend models must exist before API endpoints
   - API endpoints must exist before frontend integration
   - Base components must exist before specialized panels
   - **Unit tests must be planned for each backend endpoint**

3. **Test Planning**: For each feature, plan corresponding tests:
   - Create test file path: `tests/unit/<module>/test_<feature>.py`
   - Identify test cases: auth required, CRUD operations, edge cases
   - Reference existing test patterns in `tests/auth/test_supabase_jwt_auth.py`

4. **Update Implementation Plan**: Based on your analysis:
   - Create or update `@ralph/IMPLEMENTATION_PLAN.md`
   - Mark completed items with [x]
   - Mark in-progress items with [~]
   - Mark blocked items with [!] and note the blocker
   - Add new discovered tasks
   - Prioritize by dependency order and impact

5. **Commit the plan**:
   ```bash
   git add ralph/IMPLEMENTATION_PLAN.md
   git commit -m "chore(ralph): update implementation plan - iteration N"
   ```

## Key Rules

- **PLAN ONLY** - Do not write any implementation code
- **VERIFY FIRST** - Search before assuming something is missing
- **BE SPECIFIC** - Each task should be actionable (30min - 4hr of work)
- **FILE SIZE LIMIT** - Backend Python files must NOT exceed 500 lines. Plan for splits if needed.

## ⚠️ RLS Policy Analysis (CRITICAL)

When planning features that query Supabase tables, **analyze RLS policies first**:

### Check Table Policies

Use `mcp__clarity-sup__execute_sql` to understand access patterns:

```sql
-- List all policies on tables you'll be using
SELECT tablename, policyname, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```

### Document Access Requirements

For each table the feature will access, note in the implementation plan:

| Table | Operation | Role Needed | Policy Exists? |
|-------|-----------|-------------|----------------|
| clients | SELECT | authenticated | ✅ Yes |
| artworks | INSERT | authenticated | ❌ Needs creation |

### Plan for Missing Policies

If a required policy doesn't exist, add a task to create it:

```markdown
- [ ] Create RLS policy: `authenticated` SELECT on `artworks` table
  - File: Migration file
  - SQL: `CREATE POLICY "Authenticated users read artworks" ON artworks FOR SELECT TO authenticated USING (true);`
```

### Authentication Flow Awareness

When planning endpoints that need user-scoped data:

1. Note that `get_user_supabase_client(request)` must be used (not `get_supabase_client()`)
2. Verify the repository pattern passes the `request` object through the service layer
3. Document the expected auth flow in the plan

## Project Structure Reference

```
backend/
  apps/reviews/           # Target module for Artwork Audit
    models.py             # Add ArtworkAudit, AuditAnnotation models
    serializers/          # Add artwork audit serializers
    views.py              # Add ViewSet (or split to artwork_audit_views.py)
    urls.py               # Add routes
  apps/shared/infrastructure/  # OCR service if needed

frontend/
  app/dashboard/artwork-audit/  # New page
  components/reviews/artwork-audit/  # New components
  lib/api.ts              # Add API functions
  lib/types.ts            # Add TypeScript types
```

## Output

After completing analysis, your IMPLEMENTATION_PLAN.md should have:
1. Clear phase breakdown with completion status
2. Specific file paths for each change
3. Dependencies noted between tasks
4. Blockers identified with solutions

Remember: This iteration ends after committing the updated plan. Implementation happens in BUILD mode.
