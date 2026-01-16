# Artwork Audit Module - Ralph Wiggum Implementation Plan

## Task Reference
- **Plane Issue**: AGENT-105
- **Priority**: High
- **Status**: In Progress

---

## Overview

Build a unified audit workspace under Product Review that integrates formulation review, label review, pack copy, and documents for comprehensive artwork/label auditing against specifications.

---

## UI Layout (7 Panels Total)

### Left Sidebar (2 panels)
| Panel | Purpose |
|-------|---------|
| **Top-left** | Highlighted Text - Shows extracted text and annotations from selections on Panel 2 |
| **Bottom-left** | Ingredients - Shows ingredient table from specification (Google Drive or upload) |

### Main Area (5 panels)
| Panel 1 | Panel 2 | Panel 3 | Panel 4 | Panel 5 |
|---------|---------|---------|---------|---------|
| Pack Copy | Label/Artwork | Selectable | Selectable | Selectable |

### Panel Details
- **Panel 1 - Pack Copy**: Displays pack copy document. If none exists, user can GENERATE one.
- **Panel 2 - Label/Artwork**: Displays artwork from Google Drive (DesignArtwork model). Main panel for free-form rectangle selection to highlight regions.
- **Panel 3/4/5 - Selectable**: User independently selects what to display: Formulation Review, Label Review, Pack Copy Records, Documents, etc.

---

## Existing Infrastructure

### DesignArtwork Model
Located at: `backend/apps/reviews/models.py:826`
```python
- gdrive_file_url: Direct Google Drive file URL
- gdrive_folder_url: Google Drive folder containing artwork
- thumbnail_url: Preview image URL
- file_name, file_type, file_size_bytes: File metadata
- product: FK to Product
- pack_copy: FK to PackCopy
```

### Google Drive Service
Located at: `backend/apps/shared/infrastructure/google_drive_service.py`

---

## Implementation Phases

### Phase 1: Backend Foundation
**Goal**: Create ArtworkAudit model, migrations, and CRUD API

**Tasks**:
1. Create `ArtworkAudit` model in `backend/apps/reviews/models.py`
2. Create `AuditAnnotation` model for storing highlights and comments
3. Run migrations
4. Create serializers
5. Create ViewSet with CRUD endpoints
6. Add URL routes

**Models to Create**:
```python
class ArtworkAudit(models.Model):
    product = FK(Product)
    design_artwork = FK(DesignArtwork, null=True)
    specification_file = CharField
    status = CharField  # draft/in_review/approved/rejected
    created_by = FK(User)
    created_at = DateTimeField
    updated_at = DateTimeField

class AuditAnnotation(models.Model):
    audit = FK(ArtworkAudit)
    page_number = IntegerField
    bbox_x0 = FloatField
    bbox_y0 = FloatField
    bbox_x1 = FloatField
    bbox_y1 = FloatField
    extracted_text = TextField
    user_comment = TextField
    annotation_type = CharField  # highlight/issue/note
    created_at = DateTimeField
```

**API Endpoints**:
- GET/POST `/api/reviews/artwork-audits/`
- GET/PUT/DELETE `/api/reviews/artwork-audits/{id}/`
- POST `/api/reviews/artwork-audits/{id}/annotations/`
- GET `/api/reviews/artwork-audits/{id}/annotations/`
- POST `/api/reviews/artwork-audits/{id}/extract-region/`
- GET `/api/reviews/artwork-audits/{id}/related-records/?type={formulation|label|packcopy|documents}`
- POST `/api/reviews/artwork-audits/{id}/generate-pack-copy/`
- GET `/api/reviews/products/{id}/artworks/`

**Completion Criteria**:
- [ ] Models created and migrated
- [ ] All CRUD endpoints working
- [ ] Tests passing for all endpoints

---

### Phase 2: Frontend Layout
**Goal**: Create 7-panel layout (2 sidebar + 5 main)

**Tasks**:
1. Create route `/dashboard/artwork-audit`
2. Create `ArtworkAuditPage` component with product selector
3. Implement responsive 7-panel grid layout
4. Create panel container components

**Components**:
- `ArtworkAuditPage` - Main page with product selector
- `AuditPanelLayout` - Grid layout manager
- `SidebarPanel` - Container for left sidebar panels

**Completion Criteria**:
- [ ] Route accessible at `/dashboard/artwork-audit`
- [ ] 7-panel layout renders correctly
- [ ] Product selector functional
- [ ] Responsive on different screen sizes

---

### Phase 3: Pack Copy Panel
**Goal**: Implement Panel 1 with display and generate functionality

**Tasks**:
1. Create `PackCopyPanel` component
2. Display existing pack copy if available
3. Add "Generate Pack Copy" button when none exists
4. Connect to existing pack copy generation API

**Completion Criteria**:
- [ ] Displays pack copy when available
- [ ] Shows generate button when no pack copy
- [ ] Generation works and updates panel

---

### Phase 4: Artwork Panel
**Goal**: Load artwork from Google Drive with PDF/image viewer

**Tasks**:
1. Create `ArtworkPanel` component
2. Integrate with DesignArtwork.gdrive_file_url
3. Implement PDF viewer using react-pdf
4. Implement image viewer for non-PDF files
5. Add page navigation for multi-page PDFs

**Completion Criteria**:
- [ ] Loads artwork from Google Drive
- [ ] PDF rendering works
- [ ] Image rendering works
- [ ] Page navigation for PDFs

---

### Phase 5: Drawing Tools
**Goal**: Free-form rectangle selection on artwork

**Tasks**:
1. Add canvas overlay to ArtworkPanel
2. Implement click-and-drag rectangle drawing
3. Store rectangle coordinates (bbox)
4. Allow multiple rectangles
5. Add delete/edit functionality for selections

**Completion Criteria**:
- [ ] Can draw rectangles on artwork
- [ ] Rectangles persist visually
- [ ] Can delete selections
- [ ] Coordinates saved correctly

---

### Phase 6: OCR Integration
**Goal**: Text extraction from highlighted regions

**Tasks**:
1. Create OCR endpoint in backend
2. Use existing OCR infrastructure or integrate Tesseract/Document AI
3. Send bbox + page to backend
4. Display extracted text in annotation

**Completion Criteria**:
- [ ] OCR endpoint working
- [ ] Text extracted from highlighted regions
- [ ] Text displayed in UI

---

### Phase 7: Left Sidebar Panels
**Goal**: Highlighted text panel and Ingredients panel

**Tasks**:
1. Create `HighlightedTextPanel` component
2. Display all annotations with extracted text
3. Create `IngredientsPanel` component
4. Load ingredients from specification file
5. Support Google Drive auto-fetch AND manual upload

**Completion Criteria**:
- [ ] Highlighted text shows all annotations
- [ ] Ingredients load from spec
- [ ] Manual upload works

---

### Phase 8: Selectable Panels
**Goal**: Dropdown + dynamic content for Panels 3, 4 & 5

**Tasks**:
1. Create `SelectableInfoPanel` component
2. Add dropdown with options: Formulation Review, Label Review, Pack Copy Records, Documents
3. Fetch and display selected content type
4. Each panel independent

**Completion Criteria**:
- [ ] Dropdown works
- [ ] All content types load correctly
- [ ] Panels independent

---

### Phase 9: Workflow & Polish
**Goal**: Status flow, permissions, UI refinement

**Tasks**:
1. Implement status workflow (draft -> in_review -> approved/rejected)
2. Add permission checks
3. Polish UI with loading states, error handling
4. Add keyboard shortcuts
5. Final testing

**Completion Criteria**:
- [ ] Status workflow complete
- [ ] Permissions enforced
- [ ] UI polished
- [ ] All tests passing

---

## Completion Promise

When ALL phases are complete and verified:
- All backend endpoints working with tests
- Frontend 7-panel layout functional
- Drawing tools and OCR working
- All selectable panels loading content
- Status workflow implemented

Output: `<promise>ARTWORK_AUDIT_COMPLETE</promise>`

---

## Running with Ralph Wiggum (ghuntley/how-to-ralph-wiggum)

**Implementation files are in the `ralph/` directory.**

This uses the original Ralph Wiggum methodology with **fresh sessions per iteration**.
Progress is tracked in `ralph/IMPLEMENTATION_PLAN.md`.

### Quick Start

```bash
# 1. Planning mode - Analyze codebase and create/update plan
./ralph/loop.sh plan 3

# 2. Review the plan
cat ralph/IMPLEMENTATION_PLAN.md

# 3. Build mode - Implement features
./ralph/loop.sh 50
```

### File Structure

```
ralph/
├── loop.sh              # Main loop script
├── PROMPT_plan.md       # Planning mode instructions
├── PROMPT_build.md      # Build mode instructions
├── AGENTS.md            # Commands and constraints
├── IMPLEMENTATION_PLAN.md  # Task tracking (shared state)
├── specs/artwork-audit.md  # Feature specification
└── logs/                # Iteration logs
```

### Key Principle

Each iteration runs with a **completely fresh context**. Progress persists only in:
- `ralph/IMPLEMENTATION_PLAN.md` - Task status
- Git commits - Code changes

This prevents context window bloat and ensures consistent behavior.

---

## Key Files to Modify

### Backend
- `backend/apps/reviews/models.py` - Add ArtworkAudit models
- `backend/apps/reviews/serializers/` - Add serializers
- `backend/apps/reviews/views.py` - Add ViewSet (or create separate file)
- `backend/apps/reviews/urls.py` - Add routes
- `backend/apps/shared/infrastructure/` - OCR service if needed

### Frontend
- `frontend/app/dashboard/artwork-audit/page.tsx` - Main page
- `frontend/components/reviews/artwork-audit/` - New component directory
- `frontend/lib/api.ts` - Add API functions
- `frontend/lib/types.ts` - Add TypeScript types
- `frontend/components/sidebar.tsx` - Add navigation link

---

## Notes

- **File Size Limit**: Backend Python files must NOT exceed 500 lines. If `views.py` grows too large, split into separate files.
- **Secrets**: Use `apps.shared.infrastructure.secrets_manager.get_secret` for any API keys
- **Auth**: Use existing `SupabaseJWTAuthentication`
- **Validation**: All inputs must use Pydantic schemas

---

## Sources

- **[how-to-ralph-wiggum by Geoffrey Huntley](https://github.com/ghuntley/how-to-ralph-wiggum)** - Primary implementation reference
- [Original Ralph Wiggum Concept](https://ghuntley.com/ralph) - The original blog post
- [Ralph Wiggum Plugin - Anthropic Claude Code](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) - Plugin version (not used here)
