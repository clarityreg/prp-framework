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
    "CI templates (.claude/templates/ci/):1"
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

mkdir -p "$TARGET_DIR/.claude/PRPs/prds"
mkdir -p "$TARGET_DIR/.claude/PRPs/plans"
mkdir -p "$TARGET_DIR/.claude/PRPs/issues"
mkdir -p "$TARGET_DIR/.claude/PRPs/reviews"
mkdir -p "$TARGET_DIR/.claude/PRPs/audit"
mkdir -p "$TARGET_DIR/.claude/PRPs/coverage"
mkdir -p "$TARGET_DIR/.claude/PRPs/branches"
mkdir -p "$TARGET_DIR/.claude/hooks/sounds/voice"
ok "Directory structure created"

# ─── Install each selected component ────────────────────────────────────────

# 1. Core commands
if [[ ${SELECTED[0]} -eq 1 ]]; then
    header "Installing core commands"
    copy_dir "$PRP_SOURCE/.claude/commands/prp-core" "$TARGET_DIR/.claude/commands/prp-core"
    local_count=$(find "$TARGET_DIR/.claude/commands/prp-core" -name "*.md" | wc -l | tr -d ' ')
    ok "Installed $local_count command files"
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
    for skill_dir in "$PRP_SOURCE/.claude/skills"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_name=$(basename "$skill_dir")
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

# 6. CI templates
if [[ ${SELECTED[5]} -eq 1 ]]; then
    header "Installing CI templates"
    mkdir -p "$TARGET_DIR/.claude/templates/ci"
    for tmpl in "$PRP_SOURCE/.claude/templates/ci/"*.template; do
        [[ -f "$tmpl" ]] || continue
        cp "$tmpl" "$TARGET_DIR/.claude/templates/ci/"
    done
    local_count=$(find "$TARGET_DIR/.claude/templates/ci" -name "*.template" | wc -l | tr -d ' ')
    ok "Installed $local_count CI templates"
    INSTALLED+=("CI templates ($local_count files)")
fi

# 7. Pre-commit config + helper scripts
if [[ ${SELECTED[6]} -eq 1 ]]; then
    header "Installing pre-commit config"
    if [[ -f "$TARGET_DIR/.pre-commit-config.yaml" ]]; then
        backup_if_exists "$TARGET_DIR/.pre-commit-config.yaml"
    fi
    cp "$PRP_SOURCE/.pre-commit-config.yaml" "$TARGET_DIR/.pre-commit-config.yaml"
    ok "Installed .pre-commit-config.yaml"

    # Copy helper scripts (not observability scripts — those go with apps/)
    mkdir -p "$TARGET_DIR/scripts"
    for helper in lint-frontend.sh check-file-size.sh trivy-precommit.sh \
                  coverage-report.sh branch-viz.py; do
        if [[ -f "$PRP_SOURCE/scripts/$helper" ]]; then
            cp "$PRP_SOURCE/scripts/$helper" "$TARGET_DIR/scripts/$helper"
        fi
    done
    # Copy branch-viz template if present
    [[ -f "$PRP_SOURCE/scripts/branch-viz-template.html" ]] && \
        cp "$PRP_SOURCE/scripts/branch-viz-template.html" "$TARGET_DIR/scripts/branch-viz-template.html"
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
    warn "pre-commit not found — install with: pip install pre-commit"
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

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. cd $TARGET_DIR"
echo "  2. Edit .claude/prp-settings.json with your project details"
echo "  3. Run: claude"
echo "  4. Try: /prp-primer"
echo ""
echo -e "${DIM}To reinstall/update, run this script again (it's idempotent).${NC}"
