# Clarity App Comprehensive Validation Command

This validates the entire Clarity Information Ingestion Platform across code quality, type safety, testing, and end-to-end workflows.

## Overview

The Clarity app is a regulatory food data aggregation system with:
- **Backend**: Django + DDD architecture with 8 ingestion modules (5 complete, 3 in development)
- **Frontend**: Next.js 16 + React 19 dashboard
- **Database**: Supabase PostgreSQL with Row-Level Security
- **Task Queue**: Celery with Redis broker
- **External APIs**: EC Data Lake, EFSA, RASFF, EUR-Lex, Zenodo

## Phase 1: Linting (Code Style & Quality)

### Python Backend
```bash
PYTHONPATH=backend poetry run flake8 backend/apps --max-line-length=100 --count --statistics
```

### TypeScript Frontend
```bash
cd frontend && npm run lint
```

**Expectations**: No E-class or F-class errors, line length <= 100 chars, proper import ordering

---

## Phase 2: Type Checking

### Python
```bash
PYTHONPATH=backend poetry run mypy backend/apps --ignore-missing-imports --strict
```

### TypeScript
```bash
cd frontend && npx tsc --noEmit
```

**Expectations**: Zero type errors, all parameters/returns properly typed

---

## Phase 3: Code Formatting

### Python - Check
```bash
PYTHONPATH=backend poetry run black --check backend/apps
PYTHONPATH=backend poetry run isort --check-only backend/apps
```

### Python - Fix
```bash
PYTHONPATH=backend poetry run black backend/apps
PYTHONPATH=backend poetry run isort backend/apps
```

### TypeScript - Check
```bash
cd frontend && npx prettier --check "app/**/*.{ts,tsx,js,jsx}"
```

### TypeScript - Fix
```bash
cd frontend && npx prettier --write "app/**/*.{ts,tsx,js,jsx}"
```

---

## Phase 4: Unit & Integration Testing

### Backend - All Tests with Coverage
```bash
PYTHONPATH=backend poetry run pytest tests/ -v \
  --cov=backend/apps \
  --cov-report=html \
  --cov-report=term-missing:skip-covered
```

### Backend - Specific Test Types
```bash
PYTHONPATH=backend poetry run pytest tests/unit/ -v
PYTHONPATH=backend poetry run pytest tests/integration/ -v
```

### Backend - Pattern-Based Testing
```bash
PYTHONPATH=backend poetry run pytest -k "novel_food" -v
PYTHONPATH=backend poetry run pytest -m "unit" -v
```

### Frontend Build
```bash
cd frontend && npm run build
```

**Coverage Targets**: 80%+ overall, 90%+ critical paths

**View Report**:
```bash
open htmlcov/index.html
```

---

## Phase 5: End-to-End Testing

### 5.1 Environment Connectivity

**Supabase PostgreSQL**:
```bash
PYTHONPATH=backend python backend/manage.py shell << 'EOF'
from django.db import connections
try:
    connections['default'].ensure_connection()
    print("✓ Supabase PostgreSQL connected")
except Exception as e:
    print(f"✗ Supabase connection failed: {e}")
EOF
```

**Redis**:
```bash
PYTHONPATH=backend python backend/manage.py shell << 'EOF'
from redis import Redis
try:
    redis_client = Redis(host='localhost', port=6379, decode_responses=True)
    redis_client.ping()
    print("✓ Redis connected")
except Exception as e:
    print(f"✗ Redis connection failed: {e}")
EOF
```

### 5.2 Django Management

```bash
PYTHONPATH=backend python backend/manage.py migrate --plan
PYTHONPATH=backend python backend/manage.py migrate
PYTHONPATH=backend python backend/manage.py shell -c "print('✓ Django shell works')"
```

### 5.3 API Endpoint Testing

**Terminal 1 - Start Backend**:
```bash
PYTHONPATH=backend python backend/manage.py runserver
```

**Terminal 2 - Test Endpoints**:
```bash
python << 'EOF'
import requests

BASE = "http://localhost:8000/api"

endpoints = [
    "/novel-food/statistics/",
    "/novel-food/sync/status/",
    "/consultations/statistics/",
    "/consultations/sync/status/",
    "/food-additives/statistics/",
    "/feed-additives/statistics/",
    "/news/articles/",
    "/news/feed-sources/",
    "/efsa-documents/statistics/",
]

print("\n=== API Health Check ===")
for endpoint in endpoints:
    try:
        resp = requests.get(f"{BASE}{endpoint}", timeout=10)
        status = "✓" if resp.ok else "✗"
        print(f"{status} {endpoint:40} -> {resp.status_code}")
    except Exception as e:
        print(f"✗ {endpoint:40} -> ERROR")
EOF
```

### 5.4 Celery Task Execution

**Terminal 1 - Start Celery Worker**:
```bash
PYTHONPATH=backend poetry run celery -A config worker --loglevel=info
```

**Terminal 2 - Start Celery Beat**:
```bash
PYTHONPATH=backend poetry run celery -A config beat --loglevel=info
```

**Terminal 3 - Test Sync Task**:
```bash
PYTHONPATH=backend python backend/manage.py shell << 'EOF'
from apps.ingestion.novel_food_catalogue.application import SyncCatalogueUseCase
import asyncio

async def test_sync():
    use_case = SyncCatalogueUseCase()
    result = await use_case.incremental_sync()
    print(f"✓ Processed: {result.sync_result.total_processed}")
    print(f"✓ Updated: {result.sync_result.total_updated}")
    print(f"✓ New: {result.sync_result.total_new}")

asyncio.run(test_sync())
EOF
```

### 5.5 Frontend Integration

**Development Server**:
```bash
cd frontend && npm run dev
# Visit http://localhost:3000
```

**Production Build**:
```bash
cd frontend && npm run build
```

**Full-Stack Testing**:
1. Dashboard loads without errors
2. API calls visible in Network tab
3. Module pages accessible (Novel Food, News, Food Additives)
4. Sync triggers work from UI
5. Real-time status updates work

### 5.6 Database State Validation

```bash
PYTHONPATH=backend python backend/manage.py shell << 'EOF'
from django.db import connection

tables = {
    'Novel Food': 'ingestion_novelfoodcatalogueentity',
    'Consultations': 'ingestion_novelfoodconsultationentity',
    'Food Additives': 'ingestion_foodadditiveentity',
    'Feed Additives': 'ingestion_feedadditiveentity',
    'News Articles': 'ingestion_newsarticleentity',
    'EFSA Documents': 'ingestion_efsadocumententity',
}

print("\n=== Database Record Counts ===")
with connection.cursor() as cursor:
    for label, table in tables.items():
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = cursor.fetchone()[0]
            print(f"{label:20}: {count:,} records")
        except:
            print(f"{label:20}: TABLE MISSING")
EOF
```

---

## Complete Validation Script

Save as `scripts/validate.sh`:

```bash
#!/bin/bash
set -e

echo "=========================================="
echo "Clarity App Comprehensive Validation"
echo "=========================================="

echo -e "\n[PHASE 1] Running Linters..."
PYTHONPATH=backend poetry run flake8 backend/apps --max-line-length=100 --count --statistics
cd frontend && npm run lint && cd ..

echo -e "\n[PHASE 2] Running Type Checkers..."
PYTHONPATH=backend poetry run mypy backend/apps --ignore-missing-imports
cd frontend && npx tsc --noEmit && cd ..

echo -e "\n[PHASE 3] Checking Code Formatting..."
PYTHONPATH=backend poetry run black --check backend/apps
PYTHONPATH=backend poetry run isort --check-only backend/apps

echo -e "\n[PHASE 4] Running Tests with Coverage..."
PYTHONPATH=backend poetry run pytest tests/ -v \
  --cov=backend/apps \
  --cov-report=html \
  --cov-report=term-missing:skip-covered

echo -e "\n=========================================="
echo "✓ All validations passed!"
echo "=========================================="
```

Run with:
```bash
chmod +x scripts/validate.sh
./scripts/validate.sh
```

---

## CI/CD Integration: GitHub Actions

Create `.github/workflows/validate.yml`:

```yaml
name: Comprehensive Validation

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s

    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with:
          python-version: "3.11"
      - uses: actions/setup-node@v3
        with:
          node-version: "20"

      - name: Install Poetry
        run: curl -sSL https://install.python-poetry.org | python3 -

      - name: Install dependencies
        run: |
          poetry install
          cd frontend && npm install && cd ..

      - name: Lint
        run: |
          PYTHONPATH=backend poetry run flake8 backend/apps
          cd frontend && npm run lint && cd ..

      - name: Type check
        run: |
          PYTHONPATH=backend poetry run mypy backend/apps --ignore-missing-imports
          cd frontend && npx tsc --noEmit && cd ..

      - name: Format check
        run: |
          PYTHONPATH=backend poetry run black --check backend/apps
          PYTHONPATH=backend poetry run isort --check-only backend/apps

      - name: Run tests
        run: PYTHONPATH=backend poetry run pytest tests/ -v --cov=backend/apps --cov-report=xml

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.xml
```

---

## Troubleshooting Common Issues

| Problem | Solution |
|---------|----------|
| PYTHONPATH errors | `export PYTHONPATH=backend` |
| Celery connection fails | `redis-cli ping` (local) or `redis-cli -h 192.168.2.10 -p 6382 ping` (work server) |
| Database migration errors | `python backend/manage.py migrate --plan && python backend/manage.py migrate` |
| MyPy too strict | `poetry run mypy backend/apps --ignore-missing-imports --allow-untyped-defs` |
| Frontend build fails | `cd frontend && rm -rf .next node_modules && npm install && npm run build` |

---

## Success Criteria

All validations pass when:

1. **Linting**: Zero E-class errors, no critical warnings
2. **Type Checking**: Zero type errors, strict mode passes
3. **Formatting**: All files formatted consistently (Black, isort, Prettier)
4. **Testing**: 80%+ coverage (90%+ critical paths)
5. **E2E Tests**:
   - Database connectivity verified
   - Celery tasks execute successfully
   - All API endpoints respond (< 2s)
   - Data syncs complete without errors
   - Frontend builds without errors
   - Full-stack integration works

6. **Performance**:
   - All API responses < 2 seconds
   - Sync operations complete within expected timeframes
   - No memory leaks or connection pooling issues

---

## Local Development Setup

**Terminal 1 - Backend**:
```bash
PYTHONPATH=backend python backend/manage.py runserver
```

**Terminal 2 - Celery Worker**:
```bash
PYTHONPATH=backend poetry run celery -A config worker --loglevel=info
```

**Terminal 3 - Celery Beat**:
```bash
PYTHONPATH=backend poetry run celery -A config beat --loglevel=info
```

**Terminal 4 - Frontend**:
```bash
cd frontend && npm run dev
```

**Terminal 5 - Testing**:
```bash
PYTHONPATH=backend poetry run pytest tests/ -v --watch
```

**Access Points**:
- Frontend Dashboard: http://localhost:3000
- Backend API: http://localhost:8000/api/
- Django Admin: http://localhost:8000/admin/

---

## Key Modules Validated

**Completed (5/8)**:
- Novel Food Catalogue: EC Data Lake API, SHA-256 deduplication
- Novel Food Consultations: Web scraping, PDF processing, AI summaries
- Food Additives: Dual-module (food/feed), EC Data Lake v2.0 NDJSON
- Country News: RSS/web/email for 11+ EU countries
- EFSA Documents: 7-category scraping, PDF uploads to Supabase

**In Development (3/8)**:
- QPS Database: EFSA microbial species (Zenodo)
- RASFF Alerts: EC RASFF OData API
- EUR-Lex: European legal documents search
