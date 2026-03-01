#!/bin/bash
# install-prp.sh — Install PRP Framework into an existing project
#
# Usage:
#   ./install-prp.sh ~/projects/my-app          # From PRP repo, pointing at a target
#   PRP_FRAMEWORK_DIR=~/Dev/prp-framework ./install-prp.sh   # From inside target project
#   ./install-prp.sh --all ~/projects/my-app     # Install everything, no menu
#   ./install-prp.sh --core ~/projects/my-app    # Install components 1-8 only
#   ./install-prp.sh --yes ~/projects/my-app     # Use defaults (1-8 ON, 9-10 OFF)
#   ./install-prp.sh --components 1,2,3,5 ~/projects/my-app  # Install specific components

set -euo pipefail

# ─── Colors & formatting ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
ok()    { echo -e "${GREEN}✓${NC}  $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
err()   { echo -e "${RED}✗${NC}  $*" >&2; }
header(){ echo -e "\n${BOLD}${CYAN}── $* ──${NC}\n"; }

# ─── Parse flags ─────────────────────────────────────────────────────────────
FLAG_ALL=false
FLAG_CORE=false
FLAG_YES=false
FLAG_COMPONENTS=""
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)  FLAG_ALL=true; shift ;;
        --core) FLAG_CORE=true; shift ;;
        --yes)  FLAG_YES=true; shift ;;
        --components) FLAG_COMPONENTS="$2"; shift 2 ;;
        --components=*) FLAG_COMPONENTS="${1#*=}"; shift ;;
        -h|--help)
            echo "Usage: install-prp.sh [--all|--core|--yes|--components N,N,...] [target-directory]"
            echo ""
            echo "Flags:"
            echo "  --all            Install all components (including observability + Ralph)"
            echo "  --core           Install components 1-8 only (skip observability + Ralph)"
            echo "  --yes            Skip interactive menu, use defaults (same as --core)"
            echo "  --components N   Comma-separated list of component numbers (1-10)"
            echo "  -h               Show this help"
            echo ""
            echo "Modes:"
            echo "  ./install-prp.sh ~/projects/my-app     Install into target from PRP repo"
            echo "  PRP_FRAMEWORK_DIR=... ./install-prp.sh  Install into current dir"
            exit 0
            ;;
        -*) err "Unknown flag: $1"; exit 1 ;;
        *)  POSITIONAL_ARGS+=("$1"); shift ;;
    esac
done

# ─── Resolve PRP_SOURCE and TARGET_DIR ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${#POSITIONAL_ARGS[@]} -gt 0 ]]; then
    # Mode 1: argument provided → that's the target, script's own dir is PRP source
    TARGET_DIR="$(cd "${POSITIONAL_ARGS[0]}" 2>/dev/null && pwd)" || {
        err "Target directory does not exist: ${POSITIONAL_ARGS[0]}"
        exit 1
    }
    PRP_SOURCE="$SCRIPT_DIR"
else
    # Mode 2: no argument → current dir is target
    TARGET_DIR="$(pwd)"
    if [[ -n "${PRP_FRAMEWORK_DIR:-}" ]]; then
        PRP_SOURCE="$(cd "$PRP_FRAMEWORK_DIR" 2>/dev/null && pwd)" || {
            err "PRP_FRAMEWORK_DIR does not exist: $PRP_FRAMEWORK_DIR"
            exit 1
        }
    else
        err "No target directory provided and PRP_FRAMEWORK_DIR is not set."
        echo ""
        echo "Usage:"
        echo "  From PRP repo:     ./install-prp.sh ~/projects/my-app"
        echo "  From target repo:  PRP_FRAMEWORK_DIR=~/Dev/prp-framework ./install-prp.sh"
        exit 1
    fi
fi

# Sanity: PRP source and target must be different
if [[ "$PRP_SOURCE" == "$TARGET_DIR" ]]; then
    err "PRP source and target are the same directory: $PRP_SOURCE"
    err "Use setup-prp.sh to initialize the PRP framework repo itself."
    exit 1
fi

header "PRP Framework Installer"
info "PRP source:  ${DIM}$PRP_SOURCE${NC}"
info "Target:      ${DIM}$TARGET_DIR${NC}"

# ─── Validate PRP source ────────────────────────────────────────────────────
validate_prp_source() {
    local missing=()
    [[ -d "$PRP_SOURCE/.claude/commands/prp-core" ]] || missing+=("commands/prp-core/")
    [[ -d "$PRP_SOURCE/.claude/hooks" ]]             || missing+=("hooks/")
    [[ -d "$PRP_SOURCE/.claude/scripts" ]]           || missing+=("scripts/")
    [[ -f "$PRP_SOURCE/.claude/settings.json" ]]     || missing+=("settings.json")
    [[ -f "$PRP_SOURCE/CLAUDE.md" ]]                 || missing+=("CLAUDE.md")

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "PRP source is missing expected files:"
        for f in "${missing[@]}"; do
            echo "    - .claude/$f"
        done
        exit 1
    fi
}
validate_prp_source

# ─── Validate target ────────────────────────────────────────────────────────
WARNINGS=()

if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    warn "Target is not a git repository. Pre-commit hooks won't work."
    WARNINGS+=("Not a git repo — pre-commit hooks disabled")
fi

if ! command -v python3 &>/dev/null; then
    warn "python3 not found. PRP hooks require Python 3."
    WARNINGS+=("python3 missing — hooks won't function")
fi

# ─── Component definitions ───────────────────────────────────────────────────
# Format: "label:default" (1=on, 0=off)
COMPONENTS=(
    "Core commands (.claude/commands/prp-core/):1"
    "Hook scripts (.claude/hooks/):1"
    "Git guard scripts (.claude/scripts/):1"
    "Skills (.claude/skills/):1"
    "Agents (.claude/agents/):1"
    "Templates (.claude/templates/ — CI + QA):1"
    "Pre-commit config (.pre-commit-config.yaml + scripts/):1"
    "Settings & wiring (settings.json, prp-settings.json):1"
    "Observability dashboard (apps/server + apps/client):0"
    "Ralph loop (ralph/):0"
)

NUM_COMPONENTS=${#COMPONENTS[@]}

# Initialize selection array from defaults
declare -a SELECTED
for i in "${!COMPONENTS[@]}"; do
    default="${COMPONENTS[$i]##*:}"
    SELECTED[$i]=$default
done

# Apply flags
if $FLAG_ALL; then
    for i in "${!COMPONENTS[@]}"; do SELECTED[$i]=1; done
fi
if $FLAG_CORE; then
    for i in $(seq 0 7); do SELECTED[$i]=1; done
    SELECTED[8]=0
    SELECTED[9]=0
fi
if [[ -n "$FLAG_COMPONENTS" ]]; then
    # --components overrides: start with all OFF, then turn on specified
    for i in "${!COMPONENTS[@]}"; do SELECTED[$i]=0; done
    IFS=',' read -ra COMP_NUMS <<< "$FLAG_COMPONENTS"
    for num in "${COMP_NUMS[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= NUM_COMPONENTS )); then
            SELECTED[$((num - 1))]=1
        fi
    done
fi

# ─── Interactive menu ────────────────────────────────────────────────────────
show_menu() {
    echo -e "${BOLD}Select components to install:${NC}"
    echo ""
    for i in "${!COMPONENTS[@]}"; do
        local label="${COMPONENTS[$i]%%:*}"
        local num=$((i + 1))
        if [[ ${SELECTED[$i]} -eq 1 ]]; then
            echo -e "  ${GREEN}[✓]${NC} ${BOLD}$num${NC}. $label"
        else
            echo -e "  ${DIM}[ ]${NC} ${BOLD}$num${NC}. $label"
        fi
    done
    echo ""
    echo -e "  ${DIM}Toggle: enter number (1-$NUM_COMPONENTS)  |  a=all on  |  n=all off  |  d=defaults${NC}"
    echo -e "  ${DIM}Confirm: y or Enter  |  q=quit${NC}"
}

if ! $FLAG_ALL && ! $FLAG_CORE && ! $FLAG_YES && [[ -z "$FLAG_COMPONENTS" ]]; then
    # Interactive mode
    while true; do
        echo ""
        show_menu
        echo ""
        read -rp "→ " choice

        case "$choice" in
            [yY]|"") break ;;
            [qQ])    echo "Aborted."; exit 0 ;;
            [aA])    for i in "${!COMPONENTS[@]}"; do SELECTED[$i]=1; done ;;
            [nN])    for i in "${!COMPONENTS[@]}"; do SELECTED[$i]=0; done ;;
            [dD])
                for i in "${!COMPONENTS[@]}"; do
                    SELECTED[$i]="${COMPONENTS[$i]##*:}"
                done
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= NUM_COMPONENTS )); then
                    local_idx=$((choice - 1))
                    SELECTED[$local_idx]=$(( 1 - SELECTED[$local_idx] ))
                else
                    warn "Invalid input: $choice"
                fi
                ;;
        esac
    done
fi

# Check at least one component selected
any_selected=false
for s in "${SELECTED[@]}"; do
    [[ $s -eq 1 ]] && any_selected=true && break
done
if ! $any_selected; then
    err "No components selected. Nothing to install."
    exit 1
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TARGET_NAME=$(basename "$TARGET_DIR")
INSTALLED=()

# Copy directory, excluding unwanted files
copy_dir() {
    local src="$1" dst="$2"
    mkdir -p "$dst"
    rsync -a \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='*.jsonl' \
        --exclude='node_modules' \
        --exclude='.DS_Store' \
        --exclude='worktrees' \
        "$src/" "$dst/"
}

# Backup a file if it exists and differs from source
backup_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.bak.${TIMESTAMP}"
        cp "$file" "$backup"
        info "Backed up ${file##"$TARGET_DIR"/} → ${backup##"$TARGET_DIR"/}"
    fi
}

# ─── Create directory structure ──────────────────────────────────────────────
header "Creating directories"

# Warn if worktrees exist — they are never touched
if [[ -d "$TARGET_DIR/.claude/worktrees" ]]; then
    info "Existing .claude/worktrees/ detected — will be preserved"
fi

mkdir -p "$TARGET_DIR/.claude/PRPs/prds"
mkdir -p "$TARGET_DIR/.claude/PRPs/plans"
mkdir -p "$TARGET_DIR/.claude/PRPs/issues"
mkdir -p "$TARGET_DIR/.claude/PRPs/reviews"
mkdir -p "$TARGET_DIR/.claude/PRPs/audit"
mkdir -p "$TARGET_DIR/.claude/PRPs/coverage"
mkdir -p "$TARGET_DIR/.claude/PRPs/branches"
mkdir -p "$TARGET_DIR/.claude/PRPs/transcript-analysis"
mkdir -p "$TARGET_DIR/.claude/hooks/sounds/voice"
mkdir -p "$TARGET_DIR/.claude/docs"
ok "Directory structure created"

# ─── Install each selected component ────────────────────────────────────────

# 1. Core commands
if [[ ${SELECTED[0]} -eq 1 ]]; then
    header "Installing core commands"
    copy_dir "$PRP_SOURCE/.claude/commands/prp-core" "$TARGET_DIR/.claude/commands/prp-core"
    local_count=$(find "$TARGET_DIR/.claude/commands/prp-core" -name "*.md" | wc -l | tr -d ' ')
    ok "Installed $local_count command files"
    # Copy reference docs if they exist in PRP source
    if [[ -d "$PRP_SOURCE/.claude/docs" ]] && ls "$PRP_SOURCE/.claude/docs/"*.md &>/dev/null; then
        copy_dir "$PRP_SOURCE/.claude/docs" "$TARGET_DIR/.claude/docs"
        ok "Installed PRP reference docs (.claude/docs/)"
    fi
    INSTALLED+=("Core commands ($local_count files)")
fi

# 2. Hook scripts
if [[ ${SELECTED[1]} -eq 1 ]]; then
    header "Installing hook scripts"
    # Copy individual hook files (not the entire directory, to preserve existing hooks)
    for hook_file in auto_allow_readonly.py auto-format.sh backup_transcript.py \
                     hook_handler.py log_failures.py prp_settings.py status_line.py \
                     structure_change.py verify_file_size.py; do
        if [[ -f "$PRP_SOURCE/.claude/hooks/$hook_file" ]]; then
            cp "$PRP_SOURCE/.claude/hooks/$hook_file" "$TARGET_DIR/.claude/hooks/$hook_file"
        fi
    done
    # Copy observability subpackage
    if [[ -d "$PRP_SOURCE/.claude/hooks/observability" ]]; then
        copy_dir "$PRP_SOURCE/.claude/hooks/observability" "$TARGET_DIR/.claude/hooks/observability"
    fi
    # Copy README if present
    [[ -f "$PRP_SOURCE/.claude/hooks/README.md" ]] && \
        cp "$PRP_SOURCE/.claude/hooks/README.md" "$TARGET_DIR/.claude/hooks/README.md"
    ok "Installed hook scripts + observability/"
    INSTALLED+=("Hook scripts")
fi

# 3. Git guard scripts
if [[ ${SELECTED[2]} -eq 1 ]]; then
    header "Installing git guard scripts"
    mkdir -p "$TARGET_DIR/.claude/scripts"
    for script in branch_guard.py branch_naming.py commit_scope.py \
                  prepush_checklist.py session_context.py; do
        if [[ -f "$PRP_SOURCE/.claude/scripts/$script" ]]; then
            cp "$PRP_SOURCE/.claude/scripts/$script" "$TARGET_DIR/.claude/scripts/$script"
        fi
    done
    ok "Installed git guard scripts"
    INSTALLED+=("Git guard scripts (5 files)")
fi

# 4. Skills
if [[ ${SELECTED[3]} -eq 1 ]]; then
    header "Installing skills"
    mkdir -p "$TARGET_DIR/.claude/skills"
    # Skills that only apply to the PRP framework repo itself — never install into target projects
    local skip_skills="prp-sync-check"
    for skill_dir in "$PRP_SOURCE/.claude/skills"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name=$(basename "$skill_dir")
        if [[ "$skip_skills" == *"$skill_name"* ]]; then
            info "Skipping $skill_name (PRP framework repo only)"
            continue
        fi
        copy_dir "$skill_dir" "$TARGET_DIR/.claude/skills/$skill_name"
    done
    local_count=$(find "$TARGET_DIR/.claude/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    ok "Installed $local_count skill directories"
    INSTALLED+=("Skills ($local_count dirs)")
fi

# 5. Agents
if [[ ${SELECTED[4]} -eq 1 ]]; then
    header "Installing agents"
    mkdir -p "$TARGET_DIR/.claude/agents"
    for agent_file in "$PRP_SOURCE/.claude/agents/"*.md; do
        [[ -f "$agent_file" ]] || continue
        cp "$agent_file" "$TARGET_DIR/.claude/agents/"
    done
    local_count=$(find "$TARGET_DIR/.claude/agents" -name "*.md" | wc -l | tr -d ' ')
    ok "Installed $local_count agent definitions"
    INSTALLED+=("Agents ($local_count files)")
fi

# 6. Templates (CI + QA)
if [[ ${SELECTED[5]} -eq 1 ]]; then
    header "Installing templates (CI + QA)"
    copy_dir "$PRP_SOURCE/.claude/templates" "$TARGET_DIR/.claude/templates"
    local_count=$(find "$TARGET_DIR/.claude/templates" \( -name "*.template" -o -name "*.md" \) | wc -l | tr -d ' ')
    ok "Installed $local_count template files"
    INSTALLED+=("Templates ($local_count files)")
fi

# 7. Pre-commit config + helper scripts
if [[ ${SELECTED[6]} -eq 1 ]]; then
    header "Installing pre-commit config"

    PRP_PC_START="  # <!-- PRP-HOOKS-START -->"
    PRP_PC_END="  # <!-- PRP-HOOKS-END -->"

    # Extract repo entries from PRP's config (everything after the `repos:` line)
    # Using awk instead of sed for macOS/BSD compatibility
    PRP_REPOS=$(awk '/^repos:/{found=1; next} found{print}' "$PRP_SOURCE/.pre-commit-config.yaml")

    if [[ -f "$TARGET_DIR/.pre-commit-config.yaml" ]]; then
        backup_if_exists "$TARGET_DIR/.pre-commit-config.yaml"

        if grep -q "PRP-HOOKS-START" "$TARGET_DIR/.pre-commit-config.yaml"; then
            # Re-install: strip old PRP section between markers, then re-append
            TMPFILE=$(mktemp)
            awk '
                /PRP-HOOKS-START/ { skip=1; next }
                /PRP-HOOKS-END/   { skip=0; next }
                !skip             { print }
            ' "$TARGET_DIR/.pre-commit-config.yaml" > "$TMPFILE"
            mv "$TMPFILE" "$TARGET_DIR/.pre-commit-config.yaml"
        fi

        # Append PRP repos at the end (valid YAML — extends the existing repos: list)
        {
            echo ""
            echo "$PRP_PC_START"
            echo "$PRP_REPOS"
            echo "$PRP_PC_END"
        } >> "$TARGET_DIR/.pre-commit-config.yaml"
        ok "Appended PRP hooks to existing .pre-commit-config.yaml"
    else
        # No existing config — copy PRP's full file
        cp "$PRP_SOURCE/.pre-commit-config.yaml" "$TARGET_DIR/.pre-commit-config.yaml"
        ok "Installed .pre-commit-config.yaml"
    fi

    # Copy helper scripts via glob (skip observability + dev-only utilities)
    mkdir -p "$TARGET_DIR/scripts"
    local_skip="start-observability.sh|stop-observability.sh|tmux-input-watcher.sh"
    for helper in "$PRP_SOURCE/scripts/"*.{sh,py,html}; do
        [[ -f "$helper" ]] || continue
        helper_name=$(basename "$helper")
        if [[ ! "$helper_name" =~ ^($local_skip)$ ]]; then
            cp "$helper" "$TARGET_DIR/scripts/$helper_name"
        fi
    done
    ok "Installed pre-commit helper scripts"
    INSTALLED+=("Pre-commit config + helper scripts")
fi

# 8. Settings & wiring
if [[ ${SELECTED[7]} -eq 1 ]]; then
    header "Installing settings & wiring"

    # settings.json — backup and install with rewritten --source-app
    backup_if_exists "$TARGET_DIR/.claude/settings.json"
    sed "s/--source-app prp-framework/--source-app $TARGET_NAME/g" \
        "$PRP_SOURCE/.claude/settings.json" > "$TARGET_DIR/.claude/settings.json"
    ok "Installed settings.json (--source-app → $TARGET_NAME)"

    # prp-settings.json — only install if none exists
    if [[ ! -f "$TARGET_DIR/.claude/prp-settings.json" ]]; then
        if [[ -f "$PRP_SOURCE/.claude/prp-settings.template.json" ]]; then
            cp "$PRP_SOURCE/.claude/prp-settings.template.json" "$TARGET_DIR/.claude/prp-settings.json"
            ok "Created prp-settings.json from template"
        fi
    else
        info "prp-settings.json already exists — skipping (edit manually if needed)"
    fi

    INSTALLED+=("Settings & wiring")
fi

# 9. Observability dashboard
if [[ ${SELECTED[8]} -eq 1 ]]; then
    header "Installing observability dashboard"
    if [[ -d "$PRP_SOURCE/apps/server" ]] && [[ -d "$PRP_SOURCE/apps/client" ]]; then
        copy_dir "$PRP_SOURCE/apps/server" "$TARGET_DIR/apps/server"
        copy_dir "$PRP_SOURCE/apps/client" "$TARGET_DIR/apps/client"
        # Copy start/stop scripts
        mkdir -p "$TARGET_DIR/scripts"
        for s in start-observability.sh stop-observability.sh; do
            [[ -f "$PRP_SOURCE/scripts/$s" ]] && cp "$PRP_SOURCE/scripts/$s" "$TARGET_DIR/scripts/$s"
        done
        ok "Copied apps/server + apps/client"

        # Install bun dependencies
        if command -v bun &>/dev/null; then
            info "Running bun install for server..."
            (cd "$TARGET_DIR/apps/server" && bun install --silent 2>/dev/null) && ok "Server deps installed" || warn "Server bun install failed"
            info "Running bun install for client..."
            (cd "$TARGET_DIR/apps/client" && bun install --silent 2>/dev/null) && ok "Client deps installed" || warn "Client bun install failed"
        else
            warn "bun not found — skipping dependency install"
            warn "Install bun: curl -fsSL https://bun.sh/install | bash"
            WARNINGS+=("bun missing — run 'bun install' in apps/server and apps/client manually")
        fi
        INSTALLED+=("Observability dashboard")
    else
        warn "Observability apps not found in PRP source — skipping"
    fi
fi

# 10. Ralph loop
if [[ ${SELECTED[9]} -eq 1 ]]; then
    header "Installing Ralph loop"
    if [[ -d "$PRP_SOURCE/ralph" ]]; then
        copy_dir "$PRP_SOURCE/ralph" "$TARGET_DIR/ralph"
        # Reset IMPLEMENTATION_PLAN.md to a blank template
        cat > "$TARGET_DIR/ralph/IMPLEMENTATION_PLAN.md" <<'RALPH_EOF'
# Implementation Plan

## Current Status
- [ ] Task 1: (define your first task)

## Notes
(Add implementation notes here)
RALPH_EOF
        ok "Installed Ralph loop (with blank IMPLEMENTATION_PLAN.md)"
        INSTALLED+=("Ralph loop")
    else
        warn "Ralph directory not found in PRP source — skipping"
    fi
fi

# ─── Handle .gitignore ───────────────────────────────────────────────────────
header "Handling .gitignore"

PRP_GI_START="# <!-- PRP-GITIGNORE-START -->"
PRP_GI_END="# <!-- PRP-GITIGNORE-END -->"

PRP_GITIGNORE_CONTENT=$(cat <<'GIEOF'
# PRP Framework — runtime outputs (do not commit)
__pycache__/
*.pyc
*.pyo
.coverage
.coverage.*
coverage.json
htmlcov/
.claude/hooks/*.jsonl
.claude/hooks/generated/*
!.claude/hooks/generated/.gitkeep
.claude/PRPs/coverage/
.claude/PRPs/branches/
.claude/PRPs/doctor/
.claude/PRPs/transcript-analysis/
.claude/PRPs/qa/
.claude/transcripts/
*.jsonl
security-reports/
e2e-screenshots/
e2e-test-report.md
.secrets.baseline
apps/server/events.db*
apps/server/node_modules/
apps/client/node_modules/
apps/client/dist/
.claude/hooks/observability/logs/
GIEOF
)

if [[ -f "$TARGET_DIR/.gitignore" ]]; then
    if grep -q "PRP-GITIGNORE-START" "$TARGET_DIR/.gitignore"; then
        # Replace existing PRP section
        TMPFILE=$(mktemp)
        awk '
            /PRP-GITIGNORE-START/ { skip=1; next }
            /PRP-GITIGNORE-END/   { skip=0; next }
            !skip                 { print }
        ' "$TARGET_DIR/.gitignore" > "$TMPFILE"
        {
            cat "$TMPFILE"
            echo ""
            echo "$PRP_GI_START"
            echo "$PRP_GITIGNORE_CONTENT"
            echo "$PRP_GI_END"
        } > "$TARGET_DIR/.gitignore"
        rm "$TMPFILE"
        ok "Updated PRP section in .gitignore"
    else
        # Append PRP section
        {
            echo ""
            echo "$PRP_GI_START"
            echo "$PRP_GITIGNORE_CONTENT"
            echo "$PRP_GI_END"
        } >> "$TARGET_DIR/.gitignore"
        ok "Appended PRP patterns to .gitignore"
    fi
else
    # Create new .gitignore
    {
        echo "$PRP_GI_START"
        echo "$PRP_GITIGNORE_CONTENT"
        echo "$PRP_GI_END"
    } > "$TARGET_DIR/.gitignore"
    ok "Created .gitignore with PRP patterns"
fi

# ─── Handle CLAUDE.md ────────────────────────────────────────────────────────
header "Handling CLAUDE.md"

PRP_MARKER_START="<!-- PRP-FRAMEWORK-START -->"
PRP_MARKER_END="<!-- PRP-FRAMEWORK-END -->"
PRP_CLAUDE_CONTENT=$(cat "$PRP_SOURCE/CLAUDE.md")

if [[ -f "$TARGET_DIR/CLAUDE.md" ]]; then
    # Check if PRP section already exists
    if grep -q "$PRP_MARKER_START" "$TARGET_DIR/CLAUDE.md"; then
        # Replace existing PRP section
        # Create temp file with content before marker, new PRP content, and content after marker
        TMPFILE=$(mktemp)
        awk -v start="$PRP_MARKER_START" -v end="$PRP_MARKER_END" '
            BEGIN { skip=0; printed=0 }
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            !skip       { print }
        ' "$TARGET_DIR/CLAUDE.md" > "$TMPFILE"

        # Append PRP section at end
        {
            cat "$TMPFILE"
            echo ""
            echo "$PRP_MARKER_START"
            echo "$PRP_CLAUDE_CONTENT"
            echo "$PRP_MARKER_END"
        } > "$TARGET_DIR/CLAUDE.md"
        rm "$TMPFILE"
        ok "Updated existing PRP section in CLAUDE.md"
    else
        # Append PRP section
        {
            echo ""
            echo "$PRP_MARKER_START"
            echo "$PRP_CLAUDE_CONTENT"
            echo "$PRP_MARKER_END"
        } >> "$TARGET_DIR/CLAUDE.md"
        ok "Appended PRP section to existing CLAUDE.md"
    fi
else
    # No CLAUDE.md — create fresh
    {
        echo "$PRP_MARKER_START"
        echo "$PRP_CLAUDE_CONTENT"
        echo "$PRP_MARKER_END"
    } > "$TARGET_DIR/CLAUDE.md"
    ok "Created CLAUDE.md with PRP content"
fi

# ─── Make scripts executable ─────────────────────────────────────────────────
header "Setting permissions"

chmod +x "$TARGET_DIR/.claude/hooks/"*.py 2>/dev/null || true
chmod +x "$TARGET_DIR/.claude/hooks/"*.sh 2>/dev/null || true
chmod +x "$TARGET_DIR/.claude/hooks/observability/"*.py 2>/dev/null || true
chmod +x "$TARGET_DIR/.claude/scripts/"*.py 2>/dev/null || true
chmod +x "$TARGET_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$TARGET_DIR/scripts/"*.py 2>/dev/null || true
chmod +x "$TARGET_DIR/ralph/loop.sh" 2>/dev/null || true
ok "Made scripts executable"

# ─── Post-install steps ─────────────────────────────────────────────────────
header "Post-install"

# Install pre-commit hooks if available
if [[ ${SELECTED[6]} -eq 1 ]] && command -v pre-commit &>/dev/null; then
    if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        info "Installing pre-commit hooks..."
        (cd "$TARGET_DIR" && pre-commit install 2>/dev/null) && ok "Pre-commit hooks installed" \
            || warn "pre-commit install failed"
    fi
elif [[ ${SELECTED[6]} -eq 1 ]]; then
    if command -v uv &>/dev/null; then
        warn "pre-commit not found — install with: uv pip install pre-commit"
    else
        warn "pre-commit not found — install with: pip install pre-commit"
    fi
    WARNINGS+=("pre-commit not installed")
fi

# Generate audio files if macOS
if command -v say &>/dev/null && command -v afplay &>/dev/null; then
    if [[ -f "$TARGET_DIR/.claude/hooks/hook_handler.py" ]]; then
        info "Generating audio files..."
        (cd "$TARGET_DIR" && python3 .claude/hooks/hook_handler.py --generate-all 2>/dev/null) \
            && ok "Audio files generated" || warn "Audio generation failed (non-critical)"
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
header "Installation Complete"

echo -e "${BOLD}Installed into:${NC} $TARGET_DIR"
echo ""
echo -e "${BOLD}Components:${NC}"
for item in "${INSTALLED[@]}"; do
    echo -e "  ${GREEN}✓${NC} $item"
done

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}Warnings:${NC}"
    for w in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} $w"
    done
fi

PLUGIN_DIR="$PRP_SOURCE/prp-browser.nvim"
PLUGIN_DIR_SHORT="${PLUGIN_DIR/#$HOME/\~}"

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. cd $TARGET_DIR"
echo "  2. Edit .claude/prp-settings.json with your project details"
echo "  3. Run: claude"
echo "  4. Try: /prp-primer"

if [[ -d "$PLUGIN_DIR" ]]; then
    echo ""
    echo -e "${BOLD}Neovim plugin:${NC}"
    echo -e "  Add to ${DIM}~/.config/nvim/lua/plugins/prp-browser.lua${NC}:"
    echo ""
    echo "  return {"
    echo "    dir = \"$PLUGIN_DIR_SHORT\","
    echo '    dependencies = { "MunifTanjim/nui.nvim" },'
    echo '    cmd = { "PRPBrowser" },'
    echo '    keys = { { "<leader>pb", "<cmd>PRPBrowser<cr>", desc = "PRP Browser" } },'
    echo "    config = function()"
    echo '      require("prp-browser").setup({})'
    echo "    end,"
    echo "  }"
fi

echo ""
echo -e "${DIM}To reinstall/update, run this script again (it's idempotent).${NC}"
