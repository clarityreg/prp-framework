# Artwork Audit Module Specification

## Overview

Build a unified audit workspace under Product Review that integrates formulation review, label review, pack copy, and documents for comprehensive artwork/label auditing against specifications.

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

## Backend Requirements

### Models

```python
class ArtworkAudit(models.Model):
    """Main audit record linking product to artwork review session"""
    product = models.ForeignKey('Product', on_delete=models.CASCADE)
    design_artwork = models.ForeignKey('DesignArtwork', null=True, on_delete=models.SET_NULL)
    specification_file = models.CharField(max_length=500, blank=True)
    status = models.CharField(max_length=20, choices=[
        ('draft', 'Draft'),
        ('in_review', 'In Review'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ], default='draft')
    created_by = models.ForeignKey('auth.User', on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'reviews_artworkaudit'


class AuditAnnotation(models.Model):
    """Stores highlighted regions and extracted text from artwork"""
    audit = models.ForeignKey(ArtworkAudit, on_delete=models.CASCADE, related_name='annotations')
    page_number = models.IntegerField(default=1)
    bbox_x0 = models.FloatField()  # Bounding box coordinates (0-1 normalized)
    bbox_y0 = models.FloatField()
    bbox_x1 = models.FloatField()
    bbox_y1 = models.FloatField()
    extracted_text = models.TextField(blank=True)
    user_comment = models.TextField(blank=True)
    annotation_type = models.CharField(max_length=20, choices=[
        ('highlight', 'Highlight'),
        ('issue', 'Issue'),
        ('note', 'Note'),
    ], default='highlight')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'reviews_auditannotation'
```

### API Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET/POST | `/api/reviews/artwork-audits/` | List/create audits |
| GET/PUT/DELETE | `/api/reviews/artwork-audits/{id}/` | CRUD single audit |
| POST | `/api/reviews/artwork-audits/{id}/annotations/` | Create annotation |
| GET | `/api/reviews/artwork-audits/{id}/annotations/` | List annotations |
| POST | `/api/reviews/artwork-audits/{id}/extract-region/` | OCR text extraction |
| GET | `/api/reviews/artwork-audits/{id}/related-records/` | Get related formulation/label reviews |
| POST | `/api/reviews/artwork-audits/{id}/generate-pack-copy/` | Generate pack copy |
| GET | `/api/reviews/products/{id}/artworks/` | List artworks for product |

## Frontend Requirements

### Route

`/dashboard/artwork-audit` - Main artwork audit page

### Components

1. **ArtworkAuditPage** - Main page with product selector
2. **AuditPanelLayout** - 7-panel grid layout manager
3. **PackCopyPanel** - Panel 1: Pack copy display/generation
4. **ArtworkPanel** - Panel 2: Artwork viewer with drawing tools
5. **HighlightedTextPanel** - Left sidebar: Annotation list
6. **IngredientsPanel** - Left sidebar: Ingredient table
7. **SelectableInfoPanel** - Panels 3-5: Dropdown content selector

### Drawing Tools (Panel 2)

- Canvas overlay for rectangle drawing
- Click-and-drag to create bounding boxes
- Visual persistence of selections
- Delete/edit functionality
- Coordinates saved as normalized values (0-1)

### PDF/Image Viewing

- Use react-pdf for PDF rendering
- Support multi-page navigation
- Image viewer for non-PDF files
- Zoom and pan controls

## OCR Integration

- Backend endpoint receives: page image + bounding box coordinates
- Extract text from specified region
- Return extracted text to frontend
- Options: Tesseract, Google Document AI, or existing OCR service

## Workflow States

```
draft -> in_review -> approved
                  \-> rejected
```

## Technical Constraints

1. **File Size Limit**: Backend Python files must NOT exceed 500 lines
2. **Authentication**: Use SupabaseJWTAuthentication
3. **Validation**: Use Pydantic schemas for input validation
4. **Secrets**: Use secrets_manager for API keys

## Existing Infrastructure

### DesignArtwork Model (backend/apps/reviews/models.py:826)

```python
class DesignArtwork(models.Model):
    gdrive_file_url = models.URLField()      # Direct file URL
    gdrive_folder_url = models.URLField()    # Folder containing artwork
    thumbnail_url = models.URLField()        # Preview image
    file_name = models.CharField()
    file_type = models.CharField()
    file_size_bytes = models.BigIntegerField()
    product = models.ForeignKey('Product')
    pack_copy = models.ForeignKey('PackCopy', null=True)
```

### Google Drive Service

`backend/apps/shared/infrastructure/google_drive_service.py`

## Success Criteria

- [ ] All 9 phases implemented and tested
- [ ] 7-panel layout renders correctly on all screen sizes
- [ ] Drawing tools work reliably
- [ ] OCR extracts text accurately
- [ ] All selectable panels load their content
- [ ] Status workflow functions correctly
- [ ] All API endpoints tested
