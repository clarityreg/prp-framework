# AGENTS.md - Operational Guide

## Project: Artwork Audit Module (AGENT-105)
## Repository: clarity-information

## Build Commands

```bash
# Backend - Run Django server
PYTHONPATH=backend poetry run python backend/manage.py runserver

# Backend - Run all tests
PYTHONPATH=backend poetry run pytest tests/ -v --tb=short

# Backend - Run specific module tests (create tests in tests/unit/<module>/)
PYTHONPATH=backend poetry run pytest tests/unit/reviews/ -v

# Backend - Run auth tests (good reference for test patterns)
PYTHONPATH=backend poetry run pytest tests/auth/ -v

# Backend - Make migrations
PYTHONPATH=backend poetry run python backend/manage.py makemigrations

# Backend - Apply migrations
PYTHONPATH=backend poetry run python backend/manage.py migrate

# Frontend - Development server
cd frontend && npm run dev

# Frontend - Build (type check)
cd frontend && npm run build

# Frontend - Lint
cd frontend && npm run lint
```

## File Size Constraint

**CRITICAL: Backend Python files must NOT exceed 500 lines.**

If a file grows too large, split it:
- `views.py` -> `views/` directory with `__init__.py`
- `serializers.py` -> `serializers/` directory
- Extract service classes to separate files

## Key Files

### Backend
- `backend/apps/reviews/models.py` - Models (DesignArtwork at line 826)
- `backend/apps/reviews/serializers/` - Serializers directory
- `backend/apps/reviews/views.py` - ViewSets (OVERSIZED - needs split)
- `backend/apps/reviews/urls.py` - URL routing
- `backend/apps/shared/infrastructure/google_drive_service.py` - GDrive integration

### Frontend
- `frontend/app/dashboard/artwork-audit/page.tsx` - Main page
- `frontend/components/reviews/artwork-audit/` - Components
- `frontend/lib/api.ts` - API client functions
- `frontend/lib/types.ts` - TypeScript types
- `frontend/components/sidebar.tsx` - Navigation

## Authentication

- Backend: `SupabaseJWTAuthentication` class
- Frontend: Supabase client with JWT tokens
- See: `DOCUMENTS/SECURITY/IMPORTANT-Supabase_RLS_Authentication_Error.md`

## Secrets

Never hardcode secrets. Use:
```python
from apps.shared.infrastructure.secrets_manager import get_secret
api_key = get_secret("OPENAI_API_KEY")
```

## Dependencies

- react-pdf: Already installed (v10.2.0)
- pdfjs-dist: Already installed (v5.4.449)

## Git Workflow

```bash
# After each task completion
git add -A
git commit -m "feat(artwork-audit): <description>"
git push origin <branch>
```

## Completion Promise

When ALL phases complete, output:
```
<promise>ARTWORK_AUDIT_COMPLETE</promise>
```
