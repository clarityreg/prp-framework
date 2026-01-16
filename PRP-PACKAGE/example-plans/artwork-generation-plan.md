# Artwork Generation Module - Implementation Plan

## Overview

This plan implements the Artwork Generation module with client-facing portal, version management, Google Drive integration, and 4-role RBAC.

## Architecture Based on Exploration Findings

### Current State
- **Client Model**: Supabase-based entity in `backend/apps/clients/domain/entities.py` (not Django ORM)
- **Authentication**: Supabase JWT with JWKS validation
- **Permissions**: Basic `is_staff` flag, no formal role system
- **Google Drive**: Service exists at `backend/apps/shared/infrastructure/google_drive_service.py`
- **Plane Integration**: Pattern in `backend/apps/integrations/plane_sync/`

### Required Changes

## Phase 1: Database Schema & Models

### 1.1 User Roles Table (Supabase Migration)
```sql
-- New table for user roles
CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'designer', 'client')),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);

-- RLS policies
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
```

### 1.2 Client Module Flags (Supabase Migration)
```sql
-- Add module enable flags to clients table
ALTER TABLE clients ADD COLUMN artwork_module_enabled BOOLEAN DEFAULT false;
ALTER TABLE clients ADD COLUMN project_management_enabled BOOLEAN DEFAULT false;
```

### 1.3 Designer-Client Assignments (Supabase Migration)
```sql
-- Link designers to their assigned clients
CREATE TABLE designer_client_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    designer_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT now(),
    assigned_by UUID REFERENCES auth.users(id),
    UNIQUE(designer_id, client_id)
);
```

### 1.4 Artwork Models (Django)
```python
# backend/apps/artwork/models.py
class ArtworkProject(models.Model):
    """Represents an artwork project for a client"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    client_id = models.UUIDField()  # References Supabase clients table
    name = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    status = models.CharField(max_length=50, choices=[
        ('draft', 'Draft'),
        ('in_progress', 'In Progress'),
        ('review', 'Under Review'),
        ('approved', 'Approved'),
        ('completed', 'Completed'),
    ])
    google_drive_folder_id = models.CharField(max_length=255, blank=True)
    created_by = models.UUIDField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class ArtworkVersion(models.Model):
    """Version of an artwork file (V1, V2, V3, etc.)"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    project = models.ForeignKey(ArtworkProject, on_delete=models.CASCADE, related_name='versions')
    version_number = models.PositiveIntegerField()
    file_name = models.CharField(max_length=255)
    file_type = models.CharField(max_length=20)  # 'ai', 'pdf'
    google_drive_file_id = models.CharField(max_length=255)
    google_drive_url = models.URLField(blank=True)
    file_size = models.BigIntegerField(default=0)
    uploaded_by = models.UUIDField()
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ['project', 'version_number']
        ordering = ['-version_number']

class ArtworkComment(models.Model):
    """Comments on artwork versions"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    version = models.ForeignKey(ArtworkVersion, on_delete=models.CASCADE, related_name='comments')
    user_id = models.UUIDField()
    content = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
```

## Phase 2: RBAC Implementation

### 2.1 Role Permission Matrix
| Action | Owner | Admin | Designer | Client |
|--------|-------|-------|----------|--------|
| View all clients | ✓ | ✓ | ✗ (assigned only) | ✗ (own only) |
| Create artwork | ✓ | ✓ | ✓ | ✗ |
| Edit artwork | ✓ | ✓ | ✓ | ✗ |
| Delete artwork | ✓ | ✗ | ✗ | ✗ |
| Upload versions | ✓ | ✓ | ✓ | ✗ |
| View versions | ✓ | ✓ | ✓ | ✓ |
| Add comments | ✓ | ✓ | ✓ | ✓ |
| Approve artwork | ✓ | ✓ | ✗ | ✗ |
| Manage users | ✓ | ✗ | ✗ | ✗ |
| Enable modules | ✓ | ✓ | ✗ | ✗ |

### 2.2 Permission Classes
```python
# backend/apps/artwork/permissions.py
class IsOwner(BasePermission):
    """Only owner can perform action"""
    def has_permission(self, request, view):
        return get_user_role(request.user.id) == 'owner'

class IsOwnerOrAdmin(BasePermission):
    """Owner or admin can perform action"""
    def has_permission(self, request, view):
        role = get_user_role(request.user.id)
        return role in ('owner', 'admin')

class CanAccessClient(BasePermission):
    """Check if user can access specific client"""
    def has_object_permission(self, request, view, obj):
        role = get_user_role(request.user.id)
        if role in ('owner', 'admin'):
            return True
        if role == 'designer':
            return is_designer_assigned_to_client(request.user.id, obj.client_id)
        if role == 'client':
            return is_client_user(request.user.id, obj.client_id)
        return False
```

## Phase 3: Backend API

### 3.1 New Django App Structure
```
backend/apps/artwork/
├── __init__.py
├── models.py
├── serializers.py
├── views.py
├── urls.py
├── permissions.py
├── services/
│   ├── __init__.py
│   ├── artwork_service.py
│   ├── version_service.py
│   └── gdrive_sync_service.py
├── tasks.py  # Celery tasks for Google Drive sync
└── migrations/
```

### 3.2 API Endpoints
```
# Artwork Projects
GET    /api/artwork/projects/              # List projects (filtered by role)
POST   /api/artwork/projects/              # Create project
GET    /api/artwork/projects/{id}/         # Get project details
PATCH  /api/artwork/projects/{id}/         # Update project
DELETE /api/artwork/projects/{id}/         # Delete (owner only)

# Artwork Versions
GET    /api/artwork/projects/{id}/versions/     # List versions
POST   /api/artwork/projects/{id}/versions/     # Upload new version
GET    /api/artwork/versions/{id}/              # Get version details
GET    /api/artwork/versions/{id}/download/     # Download file

# Comments
GET    /api/artwork/versions/{id}/comments/     # List comments
POST   /api/artwork/versions/{id}/comments/     # Add comment

# Client Portal (for client role)
GET    /api/portal/projects/                    # Client's projects only
GET    /api/portal/projects/{id}/               # Project detail

# Admin: User Roles
GET    /api/admin/users/                        # List users with roles
PATCH  /api/admin/users/{id}/role/              # Update user role (owner only)
POST   /api/admin/designers/{id}/clients/       # Assign client to designer
DELETE /api/admin/designers/{id}/clients/{cid}/ # Unassign client

# Client Module Settings
PATCH  /api/clients/{id}/modules/               # Enable/disable modules
```

## Phase 4: Google Drive Integration

### 4.1 Folder Structure
```
Clarity Artwork/
└── {Client Name}/
    └── {Project Name}/
        ├── V1_filename.ai
        ├── V1_filename.pdf
        ├── V2_filename.ai
        └── V2_filename.pdf
```

### 4.2 Sync Service
```python
# backend/apps/artwork/services/gdrive_sync_service.py
class GoogleDriveSyncService:
    def create_project_folder(self, project: ArtworkProject) -> str:
        """Create folder structure in Google Drive"""

    def upload_version(self, version: ArtworkVersion, file) -> dict:
        """Upload file to Google Drive, return file_id and url"""

    def sync_folder(self, project: ArtworkProject):
        """Sync local DB with Google Drive folder contents"""

    def watch_folder(self, project: ArtworkProject):
        """Set up webhook for folder changes"""
```

### 4.3 Celery Tasks
```python
# backend/apps/artwork/tasks.py
@shared_task
def sync_project_with_drive(project_id: str):
    """Periodic sync task"""

@shared_task
def process_drive_webhook(payload: dict):
    """Handle Google Drive change notifications"""
```

## Phase 5: Frontend Implementation

### 5.1 New Pages
```
frontend/app/dashboard/artwork/
├── page.tsx                    # Projects list
├── [projectId]/
│   └── page.tsx               # Project detail with versions
└── settings/
    └── page.tsx               # Module settings per client

frontend/app/portal/           # Client portal (separate layout)
├── layout.tsx
├── page.tsx                   # Portal home
└── projects/
    ├── page.tsx              # Client's projects
    └── [projectId]/
        └── page.tsx          # Project detail (view only)
```

### 5.2 Components
```
frontend/components/artwork/
├── ProjectCard.tsx
├── ProjectList.tsx
├── VersionTimeline.tsx
├── VersionUploader.tsx
├── CommentThread.tsx
└── ClientModuleSettings.tsx
```

## Implementation Order

### Step 1: Database & Models (Backend)
1. Create Supabase migrations for roles, assignments, module flags
2. Create Django `artwork` app with models
3. Run migrations

### Step 2: RBAC System
1. Create role utility functions
2. Create permission classes
3. Add role checking middleware

### Step 3: Core API
1. Implement serializers
2. Implement views with permissions
3. Add URL routes
4. Test endpoints

### Step 4: Google Drive Integration
1. Extend existing Google Drive service
2. Implement sync service
3. Add Celery tasks
4. Test sync functionality

### Step 5: Frontend - Admin Side
1. Create artwork pages
2. Create components
3. Add API client functions
4. Implement file upload with drag-drop

### Step 6: Frontend - Client Portal
1. Create portal layout
2. Create portal pages
3. Implement view-only functionality

### Step 7: Testing & Polish
1. Unit tests for services
2. Integration tests for API
3. E2E tests for critical flows
4. Documentation

## Files to Create/Modify

### New Files
- `backend/apps/artwork/` (entire app)
- `frontend/app/dashboard/artwork/` (pages)
- `frontend/app/portal/` (client portal)
- `frontend/components/artwork/` (components)
- `frontend/lib/api/artwork-api.ts`
- `frontend/lib/types/artwork.ts`
- Supabase migrations for roles/assignments

### Modified Files
- `backend/config/urls.py` - Add artwork URLs
- `backend/config/settings.py` - Add artwork app
- `backend/apps/clients/` - Add module flags
- `frontend/components/sidebar.tsx` - Add artwork nav
- `frontend/lib/types/index.ts` - Export artwork types
