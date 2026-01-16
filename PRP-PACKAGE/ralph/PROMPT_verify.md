# VERIFY MODE - Visual Testing & Compliance

You are in VERIFY mode. Your task is to visually test implementations, verify file size compliance, and **verify data access at the database layer**.

---

## ⚠️ CRITICAL: Ground Truth Checks (RLS Sanity)

**Before any UI testing, ALWAYS verify data exists and is accessible at the database layer.**

This catches authentication/RLS issues that UI testing alone cannot detect.

### Step 0: Query Database Directly via Supabase MCP

Use the `mcp__clarity-sup__execute_sql` tool to verify data exists:

```
# Check if expected data exists (service_role bypasses RLS)
SELECT id, client_name, managed_artwork
FROM clients
WHERE managed_artwork = true;
```

Expected: Should return the clients you expect to see in the UI.

### Step 1: Check RLS Policies

```
# List RLS policies on the table
SELECT schemaname, tablename, policyname, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'clients';
```

Look for:
- `authenticated` role has SELECT policy → ✅ User can read
- `anon` role has SELECT policy → ⚠️ Check if intentional
- No policy for `authenticated` → ❌ BUG - users can't read!

### Step 2: Simulate User Role Query

```
# Check what authenticated role sees
SET ROLE authenticated;
SELECT count(*) FROM clients WHERE managed_artwork = true;
RESET ROLE;
```

If this returns 0 but Step 0 returned rows → **RLS policy is blocking**.

### Step 3: Backend Log Assertion

After making an API request from the frontend, check Django logs for:
1. JWT present in Authorization header
2. User authenticated successfully
3. Query executed with correct role

Add this to any endpoint you're debugging:
```python
import structlog
logger = structlog.get_logger()

# In your view
logger.info("api_request",
    has_auth_header=bool(request.headers.get('Authorization')),
    user=str(request.user),
    is_authenticated=request.user.is_authenticated
)
```

### Step 4: Verify JWT Propagation

Check if the Supabase client is receiving the JWT correctly:
```python
# Add to supabase_client.py temporarily
logger.info("supabase_client_auth",
    token_present=bool(user_token),
    token_prefix=user_token[:20] if user_token else None,
    postgrest_headers=dict(client.postgrest.headers)
)
```

---

## Ground Truth Checklist

Before proceeding to UI testing, confirm:

| Check | Command/Tool | Expected | Status |
|-------|--------------|----------|--------|
| Data exists | `execute_sql` SELECT | N rows | ⬜ |
| RLS allows authenticated | `pg_policies` query | Policy exists | ⬜ |
| API returns data | curl with JWT | Same N rows | ⬜ |
| UI displays data | Playwright screenshot | Same N rows | ⬜ |

**If any check fails, debug THAT layer before proceeding.**

---

## CRITICAL: API Debugging Required

**Issue Found**: The database has 2 clients with `managed_artwork = true`:
- Codeage LLC (id: 4)
- WHS ESSEX LIMITED (id: 7)

But the UI shows 0 clients. We need to debug the API endpoint.

### Step 1: Test API Directly

After logging in, test the API endpoint directly:

```bash
# First, get the auth token from the browser
# Navigate to dashboard, then run this in browser console to get token:
curl -s -X POST http://playwright:3000/evaluate \
  -H "Content-Type: application/json" \
  -d '{"script": "return localStorage.getItem(\"sb-xhlfcjsgcrbexqdmnyhe-auth-token\")"}'

# Or check the network tab for Authorization header
```

### Step 2: Call the artwork clients API

```bash
# Use the backend API directly (requires auth token)
curl -s http://host.docker.internal:8000/api/clients/artworks/clients/ \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json"
```

Expected response should include:
```json
{
  "success": true,
  "data": [
    {"id": 4, "client_name": "Codeage LLC", ...},
    {"id": 7, "client_name": "WHS ESSEX LIMITED", ...}
  ],
  "count": 2
}
```

If it returns empty or error, there's a backend bug.

### Step 3: Check browser console for errors

```bash
curl -s -X POST http://playwright:3000/evaluate \
  -H "Content-Type: application/json" \
  -d '{"script": "return JSON.stringify(console._errors || [])"}'
```

### Step 4: Check network requests

After navigating to Client Artworks page, check what API calls were made:

```bash
curl -s http://playwright:3000/network
```

Look for `/api/clients/artworks/clients/` request and its response.

## Context Loading

1. Study `@ralph/IMPLEMENTATION_PLAN.md` to understand what was implemented
2. Identify which features need visual verification
3. Check file size compliance for all modified files

## Playwright Visual Testing

The app runs on your host machine. Use the Playwright HTTP API at `http://playwright:3000` for visual testing.

### Authentication (Required First)

The app requires authentication. Use the credentials file at `/workspace/ralph/.credentials`:

```bash
# Load credentials
source /workspace/ralph/.credentials

# 1. Launch browser
curl -s -X POST http://playwright:3000/browser/launch

# 2. Navigate to login page
curl -s -X POST http://playwright:3000/navigate \
  -H "Content-Type: application/json" \
  -d '{"url": "http://host.docker.internal:3000/login"}'

# 3. Wait for login page to load
sleep 2

# 4. Click "Continue with Email" button to show email form
curl -s -X POST http://playwright:3000/click \
  -H "Content-Type: application/json" \
  -d '{"selector": "button:has-text(\"Continue with Email\")"}'

sleep 1

# 5. Fill email field
curl -s -X POST http://playwright:3000/fill \
  -H "Content-Type: application/json" \
  -d "{\"selector\": \"input#email\", \"value\": \"$TEST_EMAIL\"}"

# 6. Fill password field
curl -s -X POST http://playwright:3000/fill \
  -H "Content-Type: application/json" \
  -d "{\"selector\": \"input#password\", \"value\": \"$TEST_PASSWORD\"}"

# 7. Click Sign In button
curl -s -X POST http://playwright:3000/click \
  -H "Content-Type: application/json" \
  -d '{"selector": "button[type=submit]"}'

# 8. Wait for redirect to dashboard
sleep 3

# 9. Verify login succeeded (should be on dashboard, not login)
curl -s http://playwright:3000/status
# Expected: url should contain "/dashboard" not "/login"
```

### How to Use Playwright

```bash
# 1. Launch browser
curl -s -X POST http://playwright:3000/browser/launch

# 2. Navigate to the app (adjust URL based on what you're testing)
curl -s -X POST http://playwright:3000/navigate \
  -H "Content-Type: application/json" \
  -d '{"url": "http://host.docker.internal:3000/dashboard/artwork-audit"}'

# 3. Wait for element to load
curl -s -X POST http://playwright:3000/wait \
  -H "Content-Type: application/json" \
  -d '{"selector": "[data-testid=audit-workspace]", "timeout": 10000}'

# 4. Take screenshot (uses Python for base64 decoding - jq not available)
mkdir -p /workspace/ralph/logs/screenshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCREENSHOT_NAME="${TIMESTAMP}_page.png"
curl -s -X POST http://playwright:3000/screenshot \
  -H "Content-Type: application/json" \
  -d '{"fullPage": true}' > /tmp/screenshot_response.json

python3 -c "
import json, base64
with open('/tmp/screenshot_response.json') as f:
    data = json.load(f)
    if 'image' in data:
        img = base64.b64decode(data['image'])
        with open('/workspace/ralph/logs/screenshots/$SCREENSHOT_NAME', 'wb') as out:
            out.write(img)
        print(f'Screenshot saved: $SCREENSHOT_NAME ({len(img)} bytes)')
    else:
        print(f'Error: {data}')
"

# 5. Click elements
curl -s -X POST http://playwright:3000/click \
  -H "Content-Type: application/json" \
  -d '{"selector": "button[data-testid=approve-btn]"}'

# 6. Fill forms
curl -s -X POST http://playwright:3000/fill \
  -H "Content-Type: application/json" \
  -d '{"selector": "input[name=search]", "value": "test query"}'

# 7. Get page status
curl -s http://playwright:3000/status

# 8. Close browser when done
curl -s -X POST http://playwright:3000/browser/close
```

### App URLs to Test

- **Client Artworks Management**: `http://host.docker.internal:3000/dashboard/client-artworks`
- **Artwork Audit**: `http://host.docker.internal:3000/dashboard/artwork-audit`
- **Dashboard**: `http://host.docker.internal:3000/dashboard`
- **API Health**: `http://host.docker.internal:8000/api/health/`

**Note**: Frontend runs on port 3000, Backend runs on port 8000.

## Visual Verification Checklist

### Client Artworks Page (`/dashboard/client-artworks`)

1. **Verify clients load**: Should show 2 clients (Codeage LLC, WHS ESSEX LIMITED)
2. **Stats cards**: Should show "2 Artwork Clients", "0 Total Artworks", "0 Clients with Artworks"
3. **Client cards**: Each client should have "View Artworks" button
4. **If showing 0 clients**: Debug the API (see API Debugging section above)

### Artwork Audit Page (`/dashboard/artwork-audit`)

1. **Page Loads**: Navigate to the page and confirm no errors
2. **Product sidebar**: Should show "Add product" button and search
3. **Main area**: Should show "Select a Product" placeholder when no product selected
4. **Add Product dialog**: Click "Add product" and verify form fields appear

For each implemented feature, verify:

1. **Page Loads**: Navigate to the page and confirm no errors
2. **Layout Correct**: Screenshot shows expected layout with all panels
3. **Interactive Elements**: Buttons, inputs, and controls are visible
4. **No Console Errors**: Check browser console via `/evaluate`
5. **Responsive**: Test at different viewports if applicable

### Console Error Check

```bash
# Run JavaScript to check for console errors
curl -X POST http://playwright:3000/evaluate \
  -H "Content-Type: application/json" \
  -d '{"script": "window.__errors = window.__errors || []; return window.__errors;"}'
```

## Unit Test Verification

**CRITICAL**: Run all unit tests before visual testing to catch regressions.

### Run Backend Tests

```bash
# Run all tests
PYTHONPATH=/workspace/backend poetry run pytest /workspace/tests/ -v --tb=short

# Run specific module tests
PYTHONPATH=/workspace/backend poetry run pytest /workspace/tests/unit/reviews/ -v
```

Expected: All tests should pass. If tests fail:
1. Note the failing tests in the verification report
2. Do NOT proceed to visual testing until tests pass
3. Return to BUILD mode to fix issues

### Check Test Coverage

```bash
# Check if tests exist for the feature
ls -la /workspace/tests/unit/reviews/ 2>/dev/null || echo "WARNING: No tests for reviews module!"
```

If no tests exist for implemented features, note this as a gap.

## File Size Compliance Check

**CRITICAL**: All backend Python files must be under 500 lines.

### Run File Size Check

```bash
# Check all Python files in backend/
find /workspace/backend -name "*.py" -exec wc -l {} \; | \
  awk '$1 > 500 {print "VIOLATION:", $0}' | sort -rn

# Or use the dedicated checker
python3 /workspace/ralph/file_size_checker.py
```

### Files That Commonly Exceed Limits

Monitor these files closely:
- `backend/apps/reviews/views.py` (historically large)
- `backend/apps/reviews/views/artwork.py`
- `backend/apps/omni_ingestion/presentation/views.py`
- `backend/apps/clients/presentation/views.py`

### Refactoring Strategy

If a file exceeds 500 lines:
1. Identify logical groupings of functionality
2. Extract to separate modules (e.g., `views/artwork.py`, `views/annotation.py`)
3. Update imports and URL routing
4. Run tests to verify refactoring didn't break anything

## Google Drive Folder Verification

The service account is mounted at `/secrets/clarity-drive-service-account.json`.

### Test Google Drive Access

```python
# Quick test script
from google.oauth2 import service_account
from googleapiclient.discovery import build

SCOPES = ['https://www.googleapis.com/auth/drive.readonly']
creds = service_account.Credentials.from_service_account_file(
    '/secrets/clarity-drive-service-account.json',
    scopes=SCOPES
)
service = build('drive', 'v3', credentials=creds)

# List files in shared folder
results = service.files().list(
    pageSize=10,
    fields="files(id, name, mimeType)"
).execute()

for item in results.get('files', []):
    print(f"  - {item['name']} ({item['mimeType']})")
```

## Iteration Workflow

**IMPORTANT**: All screenshots MUST be saved to `/workspace/ralph/logs/screenshots/` - this folder is mounted to the host at `ralph/logs/screenshots/` so user can view them.

1. **Launch Browser**: `curl -X POST http://playwright:3000/browser/launch`

2. **Visual Test Each Feature**:
   ```bash
   # Create screenshots directory
   mkdir -p /workspace/ralph/logs/screenshots

   # For each page, take a timestamped screenshot with feature name
   TIMESTAMP=$(date +%Y%m%d_%H%M%S)

   # Navigate to page
   curl -X POST http://playwright:3000/navigate \
     -H "Content-Type: application/json" \
     -d '{"url": "http://host.docker.internal:3000/dashboard/client-artworks"}'

   # Wait for load
   sleep 3

   # Take screenshot with descriptive name
   curl -X POST http://playwright:3000/screenshot \
     -H "Content-Type: application/json" \
     -d '{"fullPage": true}' | jq -r '.image' | base64 -d > /workspace/ralph/logs/screenshots/${TIMESTAMP}_client_artworks.png

   echo "Screenshot saved: ralph/logs/screenshots/${TIMESTAMP}_client_artworks.png"
   ```

   - Verify elements are present in screenshot
   - Check for console errors
   - Record pass/fail

3. **File Size Check**: Run compliance check on all backend files

4. **Google Drive Check**: Verify service account can access required folders

5. **Generate Report**: Update `ralph/VERIFICATION_REPORT.md` with results

6. **Fix Issues**: If violations found:
   - For UI issues: Note for build mode to fix
   - For file size: Refactor immediately
   - For Google Drive: Check permissions

7. **Close Browser**: `curl -X POST http://playwright:3000/browser/close`

8. **Commit Report and Screenshots**:
   ```bash
   git add ralph/VERIFICATION_REPORT.md
   git add ralph/logs/screenshots/*.png
   git commit -m "verify: visual testing and compliance check iteration"
   ```

## Verification Report Template

Create/update `ralph/VERIFICATION_REPORT.md`:

```markdown
# Verification Report

**Date**: [timestamp]
**Iteration**: [N]

## Unit Tests

| Test Suite | Tests | Passed | Failed | Status |
|------------|-------|--------|--------|--------|
| tests/unit/reviews/ | N | N | 0 | PASS/FAIL |
| tests/auth/ | N | N | 0 | PASS/FAIL |

## Visual Tests

| Feature | URL | Status | Screenshot |
|---------|-----|--------|------------|
| Client Artworks | /dashboard/client-artworks | PASS/FAIL | `logs/screenshots/YYYYMMDD_HHMMSS_client_artworks.png` |
| Artwork Audit | /dashboard/artwork-audit | PASS/FAIL | `logs/screenshots/YYYYMMDD_HHMMSS_artwork_audit.png` |

## API Tests

| Endpoint | Expected | Actual | Status |
|----------|----------|--------|--------|
| /api/clients/artworks/clients/ | 2 clients | ??? | PASS/FAIL |

## File Size Compliance

| File | Lines | Status |
|------|-------|--------|
| views/artwork.py | 450 | PASS |
| views.py | 520 | FAIL - needs refactoring |

## Google Drive Access

- [ ] Service account authenticated
- [ ] Can list files in shared folder
- [ ] Required folders accessible

## Issues Found

1. [Issue description]
   - Severity: HIGH/MEDIUM/LOW
   - Action: [what needs to be fixed]

## Actions Taken

- [Refactored X into Y]
- [Noted UI issue for build mode]
```

## Completion Criteria

Each verification iteration should:
1. **Run unit tests first** - ALL tests must pass before visual testing
2. Verify RLS/auth at database layer (Ground Truth Checks)
3. Test all recently implemented features visually
4. **Debug API if showing 0 clients** (there should be 2!)
5. Check file size compliance
6. Verify Google Drive access
7. Update verification report with all results
8. Refactor any oversized files immediately
9. Commit report and any fixes

**STOP CONDITIONS** (return to BUILD mode):
- Unit tests fail
- RLS policies missing or misconfigured
- API returns empty when data exists

If all verifications pass, output: `<promise>VERIFICATION_COMPLETE</promise>`
