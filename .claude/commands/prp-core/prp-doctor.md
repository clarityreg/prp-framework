---
description: Diagnose project health — environment, structure, code quality, and git status
argument-hint:
---

# Project Health Check

Run a comprehensive diagnostic of the project and report results as a checklist with pass/warn/fail per item.

---

## Check Group 1: ENVIRONMENT

Verify required tools are installed and configured.

```bash
# Python
python3 --version 2>/dev/null || python --version 2>/dev/null

# Node
node --version 2>/dev/null

# gh CLI
gh auth status 2>/dev/null

# pre-commit
pre-commit --version 2>/dev/null
# Check if hooks are installed
[ -f .git/hooks/pre-commit ] && echo "hooks installed"

# Optional tools
ruff --version 2>/dev/null
trivy --version 2>/dev/null
```

Read `.claude/prp-settings.json` to get expected versions:
- Compare installed Python version against `ci.python_version`
- Compare installed Node version against `ci.node_version`

Report:
- PASS: tool installed and version matches (or no version constraint)
- WARN: tool installed but version mismatch
- FAIL: tool not installed

---

## Check Group 2: PROJECT STRUCTURE

Verify essential files and directories exist.

1. **`.env`** — If `.env.example` exists, check that `.env` also exists and contains all the same keys (values can differ). Report missing keys.
2. **`.claude/prp-settings.json`** — Exists and has a non-empty `project.name`
3. **Backend directory** — Check `project.backend_dir` from settings (default `backend/`). PASS if exists, WARN if setting is configured but dir is missing, SKIP if not configured.
4. **Frontend directory** — Same logic for `project.frontend_dir` (default `frontend/`).
5. **Test directory** — Search for `tests/`, `test/`, `__tests__/`, or `*.test.*` files. PASS if found, WARN if not.
6. **README.md** — Exists and is non-empty.

---

## Check Group 3: CODE HEALTH

Assess code quality signals.

1. **Oversized Python files** — Find `.py` files over 500 lines:
   ```bash
   find . -name "*.py" -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/migrations/*" | while read f; do
     lines=$(wc -l < "$f")
     [ "$lines" -gt 500 ] && echo "WARN: $f ($lines lines)"
   done
   ```
   PASS: none found. WARN: list the offenders with line counts.

2. **TODO/FIXME count** — Non-blocking, just report:
   ```bash
   grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.py" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" --include="*.rs" --include="*.go" . | grep -v node_modules | grep -v .venv | wc -l
   ```
   Report count. No pass/fail — purely informational.

3. **Coverage** — Check if `.claude/PRPs/coverage/latest.json` exists. If yes, read `overall_coverage` and compare against `coverage.targets.overall` from settings. PASS if meets target, WARN if below.

4. **Merge conflict markers** — Search tracked files for `<<<<<<<`, `=======`, `>>>>>>>`:
   ```bash
   git grep -l "<<<<<<< \|======= \|>>>>>>> " -- ':!*.md' 2>/dev/null
   ```
   PASS: none found. FAIL: list files with unresolved conflicts.

---

## Check Group 4: GIT HEALTH

Assess repository state.

1. **Protected branch** — Check if current branch is `main` or `master`. WARN if so (you should be on a feature branch).
2. **Uncommitted changes** — Run `git status --porcelain`. PASS if clean, WARN with count of modified/untracked files.
3. **Stale branches** — Find branches already merged into main but not deleted:
   ```bash
   git branch --merged main 2>/dev/null | grep -v "main\|master\|\*" | wc -l
   ```
   PASS: none. WARN: list them with suggestion to delete.
4. **Remote** — Verify remote is set and reachable:
   ```bash
   git remote get-url origin 2>/dev/null
   git ls-remote --exit-code origin HEAD 2>/dev/null
   ```
   PASS: remote set and reachable. FAIL: no remote or unreachable.

---

## Check Group 5: PLANE / ARCHON (conditional)

Only run if `.claude/prp-settings.json` has `plane.workspace_slug` and `plane.project_id` set.

1. **Plane API reachable** — Use `PLANE_API_KEY` from env:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" \
     -H "X-API-Key: $PLANE_API_KEY" \
     "${PLANE_API_URL}/workspaces/${WORKSPACE_SLUG}/projects/${PROJECT_ID}/"
   ```
   PASS: 200. FAIL: any other status.

2. **Project ID valid** — Same call, check response has a valid project name.

3. **Tasks in "doing"** — Query Plane for in-progress tasks. Report count.
   PASS: 0 or 1. WARN: more than 1 (only one task should be in-progress at a time).

If Plane is not configured, SKIP this entire group.

---

## Output Format

Present results as a clean checklist:

```
Project Health Check
====================

Environment
  PASS  Python 3.12.1 (expected: 3.12)
  PASS  Node 20.11.0 (expected: 20)
  PASS  gh CLI authenticated as @username
  WARN  pre-commit installed but hooks not set up
        -> Fix: run `pre-commit install`
  PASS  ruff 0.4.1
  SKIP  trivy not installed (optional)

Project Structure
  PASS  .env exists, all keys from .env.example present
  PASS  .claude/prp-settings.json configured (project: "my-app")
  PASS  backend/ directory exists
  PASS  frontend/ directory exists
  PASS  tests/ directory exists
  PASS  README.md exists (42 lines)

Code Health
  WARN  2 Python files over 500 lines
        -> backend/apps/auth/views.py (612 lines)
        -> backend/apps/api/serializers.py (534 lines)
  INFO  14 TODO/FIXME markers found
  PASS  Coverage: 83.2% (target: 80%)
  PASS  No merge conflict markers

Git Health
  PASS  On branch feature/my-feature (not protected)
  WARN  3 uncommitted changes
  WARN  2 stale branches (merged but not deleted)
        -> feature/old-thing, fix/typo
        -> Fix: git branch -d feature/old-thing fix/typo
  PASS  Remote: origin -> git@github.com:user/repo.git (reachable)

Plane Integration
  PASS  API reachable
  PASS  Project "my-app" found
  PASS  1 task in "doing" status

Score: 14/16 checks pass, 2 warnings
```

For every WARN or FAIL item, include a one-line actionable fix suggestion (prefixed with `-> Fix:`).

End with a summary score: `X/Y checks pass, Z warnings, W failures`.
