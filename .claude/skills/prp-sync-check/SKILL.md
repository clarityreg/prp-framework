---
name: checking-framework-sync
description: "PRP FRAMEWORK REPO ONLY — when PRP framework files are modified (commands, hooks, scripts, settings, install script), checks whether related artifacts need updating: Obsidian notes, Neovim plugin (scanner, install, doctor modules), shell scripts, install-prp.sh, and the observability dashboard. Asks the user to confirm before proceeding."
---

# Framework Sync Check

When changes are made to PRP framework source files, check whether downstream artifacts are out of sync and ask the user if they want to update them.

## Scope: PRP Framework Repo ONLY

This skill ONLY applies when working inside the PRP framework repository itself (`/Users/chidionyejuruwa/Development/prp-framework`).

**Do NOT trigger in projects that have PRP installed.** Those projects consume PRP — they don't develop it. The presence of `install-prp.sh` in the repo root is the indicator that you're in the framework repo. If `install-prp.sh` does not exist in the project root, this skill does not apply.

## When to trigger

Activate after the user writes or edits ANY file matching these patterns (and `install-prp.sh` exists in the project root):

- `.claude/commands/prp-core/*.md` — a command was added, removed, or modified
- `.claude/hooks/*.py` or `.claude/hooks/*.sh` — a hook was added or changed
- `.claude/scripts/*.py` — a git guard script was changed
- `.claude/skills/*/SKILL.md` — a skill was added or changed
- `.claude/agents/*.md` — an agent was added or changed
- `.claude/settings.json` — hook wiring changed
- `.claude/prp-settings.template.json` — settings schema changed
- `install-prp.sh` — installer logic changed
- `scripts/*.sh` or `scripts/*.py` — helper scripts changed
- `CLAUDE.md` — command table or directory structure may need updating

Do NOT trigger on:
- Files inside `.claude/PRPs/` (those are artifacts, not framework source)
- Files inside `apps/` (observability app has its own dev cycle)
- Files inside `ralph/` (Ralph prompts are self-contained)
- Test files, `.gitignore`, README, or this skill's own SKILL.md

## What to check

For each changed file, evaluate which downstream artifacts MIGHT need updating:

### 1. Obsidian Notes

| Changed File Pattern | Obsidian Note to Check |
|---------------------|----------------------|
| `.claude/commands/prp-core/*.md` (add/remove) | `PRP Commands Reference.md` — command count, command list |
| `.claude/hooks/*.py` (add/remove) | `PRP Hooks and Scripts.md` — hook list, event table |
| `.claude/scripts/*.py` | `PRP Hooks and Scripts.md` — scripts section |
| `.claude/settings.json` | `PRP Hooks and Scripts.md` — hook event wiring |
| `.claude/skills/*/SKILL.md` (add/remove) | `PRP Commands Reference.md` — skills section |
| `install-prp.sh` | `PRP Framework Guide` notes — install instructions |
| Any significant structural change | `PRP Framework.md` — overview and quick reference |

Obsidian vault path: `/Users/chidionyejuruwa/obsidian_vaults/coding/02 - Projects/PRP-framework/`

### 2. Neovim Plugin

| Changed File Pattern | Nvim Module to Check |
|---------------------|---------------------|
| `.claude/commands/prp-core/*.md` (add/remove) | `scanner.lua` — auto-discovers via glob, but check `install.lua` command count in component description |
| `.claude/hooks/*.py` (add/remove) | `scanner.lua` — check glob patterns still match |
| `.claude/settings.json` (structural change) | `settings_view.lua` — verify it can still parse the schema |
| `install-prp.sh` (component changes) | `install.lua` — component list, descriptions, count |
| `.claude/hooks/generated/` convention change | `scanner.lua` — verify generated hooks appear in Hooks category |
| Doctor command changes | `doctor.lua` — check groups still align |

Nvim plugin path: `prp-browser.nvim/lua/prp-browser/`

### 3. Install Script

| Changed File Pattern | What to Check in `install-prp.sh` |
|---------------------|----------------------------------|
| New hook file in `.claude/hooks/` | Is it in the explicit copy list (line ~300)? |
| New script in `.claude/scripts/` | Is it in the explicit copy list (line ~322)? |
| New directory convention | Is `mkdir -p` creating it? |
| New `.gitignore` pattern needed | Is it in the PRP_GITIGNORE_CONTENT block? |

### 4. CLAUDE.md

| Changed File Pattern | What to Check |
|---------------------|--------------|
| New command in `.claude/commands/prp-core/` | Command table — add row |
| New command in `.claude/commands/prp-core/` | Directory structure listing — add entry |
| New hook or script | Directory structure listing |
| New skill | Auto-triggered skills table |

### 5. Gap Analysis

If any of the above are updated, also check:
- `.claude/PRPs/audit/obsidian-gap-analysis.md` — command count, hook count, script list

## How to present

After detecting a change, present a concise checklist of what MIGHT need updating:

```
Framework Sync Check
════════════════════

You modified: .claude/commands/prp-core/prp-hookify.md (new command)

Potentially out of sync:
  [ ] Obsidian: PRP Commands Reference.md — command count (was 25, now 26)
  [ ] Nvim: install.lua — component 1 description says "21 command files"
  [ ] CLAUDE.md — command table, directory structure
  [ ] Gap analysis — command list count

Update these now?
```

Then ask the user which ones to update. Only update what they confirm.

## Rules

- **Always ask** — never auto-update downstream artifacts. Present the checklist and wait for confirmation.
- **Once per file per session** — if the user already confirmed or declined updates for a file, don't ask again for the same file.
- **Be specific** — don't say "Obsidian might need updating." Say exactly which note and which section.
- **Count changes** — if a command was added, count the current files and compare against what the downstream artifact claims.
- **Skip if trivial** — if the edit was a typo fix or comment change inside an existing command, don't trigger. Only trigger for structural changes (add/remove files, change descriptions, modify schemas).
- **Group related updates** — if one change affects 4 artifacts, present them all in one checklist, not 4 separate prompts.
