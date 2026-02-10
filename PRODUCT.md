# Workstreams

A system-level tool for managing multiple concurrent software projects. It tracks what you're working on, what you're waiting on, and which windows belong to which project — then lets you switch between project contexts with a single action.

## The Problem

When working on multiple projects simultaneously, three things break down:

1. **Forgetting.** You park a project while CI runs or Claude iterates on a plan. Thirty minutes later, you've forgotten what you were going to do when it finished.

2. **Losing association.** You have 4 iTerm windows, 3 Chrome windows, a TablePlus connection, and a Typora doc open. Which ones belong to which project? You waste time hunting and guessing.

3. **No master view.** There's no single place that shows: here are your active projects, here's what each one is waiting on, here's what needs your attention now.

The workflow this tool supports is a **pipeline of attention**: while Claude runs tasks on project A, you review bugs on project B. When project B's CI finishes, you push it. If Claude is still running on A, you move to project C's planning phase. All of it tracked. All of it switchable. All of it resumable.

## The Solution

Three components that share a single state file:

### 1. CLI (`ws`)

A terminal command that knows which project you're in based on your working directory (via git root). It manages project state — registering projects, parking them with notes, marking them as ready.

**Commands:**

- `ws add [name]` — Register the current directory as a project. Auto-detects project name from git, scans for signatures (ports, database, GitHub remote). Assigns a color.
- `ws list` — Show all projects with status, color, parked note, and time since last activity.
- `ws focus [name]` — Switch context to a project. Updates state, then orchestrates window arrangement across all apps via AppleScript.
- `ws park [message]` — Park the current project with a note explaining what you're waiting on and what to do next. e.g. `ws park "CI running — merge when green"`
- `ws status` — Show detailed info for the current project: signatures, history, parked note.

### 2. Raycast Extension

The dashboard and quick-switch interface. Activated with a hotkey, it shows all projects at a glance and lets you act on them.

- Project list with color indicators, status, and parked notes
- Select a project to **focus** it (triggers the same AppleScript orchestration as `ws focus`)
- Quick action to **park** a project with a note
- Quick action to **open a terminal** at the project path

### 3. Chrome Extension (Post-MVP)

Handles the browser side — the one context that can't be auto-detected from the filesystem.

- Right-click or popup to **assign a tab to a project** manually
- Auto-assigns tabs based on URL patterns (GitHub repo URLs, localhost ports)
- Manages Chrome tab groups (color-coded, named per project)
- Responds to "focus" signals — expands the target project's tab group, collapses others

## Auto-Detection & Signatures

Each project has a set of **signatures** — patterns that identify which windows, tabs, and connections belong to it. Most are detected automatically when you register a project.

**Detected from git:**
- Project name (directory name)
- Git remote → GitHub URL patterns (PRs, branches, actions all auto-match)
- Current branch name

**Scanned from project files:**
- `.env` → `PORT`, `DATABASE_URL`
- `package.json` → dev server port
- `docker-compose.yml` → port mappings
- `database.yml` → database names
- `Procfile` → server ports

**Resulting signature set:**
```yaml
name: auth-refactor
path: ~/Projects/auth-refactor
color: red
signatures:
  git_remote: github.com/myorg/auth-refactor
  ports: [3001]
  database: auth_refactor_dev
  url_patterns:
    - github.com/myorg/auth-refactor/**
    - localhost:3001/**
```

**How signatures match across apps:**

| App | Match Strategy |
|---|---|
| iTerm | Tab's working directory starts with project path |
| Chrome | Tab URL matches a URL pattern or GitHub remote |
| TablePlus | Window title contains database name |
| Typora | Window title contains project path |
| VS Code / Cursor | Window title contains project path |
| Any other app | Window title contains project name (fallback) |

## The Focus Action

When you focus a project (via CLI or Raycast), the system:

1. Updates the `current_focus` in shared state
2. Finds all iTerm tabs whose working directory matches the project path → brings their windows to front
3. Finds all Chrome tabs whose URL matches a project signature → brings that window to front
4. Finds all TablePlus windows whose title matches the database name → brings to front
5. Finds any other windows whose title contains the project name → brings to front

Missing apps are silently skipped. The result: your screen rearranges to show everything related to the project you selected.

## State Model

All state lives in `~/.workstreams/state.json`, read and written by all three components.

```json
{
  "projects": {
    "auth-refactor": {
      "name": "auth-refactor",
      "path": "/Users/pete/Projects/auth-refactor",
      "color": "red",
      "status": "parked",
      "parked_note": "CI running — merge when green",
      "parked_at": "2025-02-07T14:30:00Z",
      "signatures": {
        "git_remote": "github.com/myorg/auth-refactor",
        "ports": [3001],
        "database": "auth_refactor_dev",
        "url_patterns": ["github.com/myorg/auth-refactor/**"]
      },
      "history": [
        { "action": "added", "at": "2025-02-06T09:00:00Z" },
        { "action": "focused", "at": "2025-02-07T10:00:00Z" },
        { "action": "parked", "note": "CI running — merge when green", "at": "2025-02-07T14:30:00Z" }
      ]
    },
    "api-v2": {
      "name": "api-v2",
      "path": "/Users/pete/Projects/api-v2",
      "color": "blue",
      "status": "active",
      "parked_note": null,
      "parked_at": null,
      "signatures": { ... },
      "history": [ ... ]
    }
  },
  "current_focus": "api-v2"
}
```

**Project statuses:**
- `active` — Currently being worked on or available to work on
- `parked` — Set aside, with a note about why and what's next

## Colors

Projects are assigned colors from a fixed palette. These colors are used consistently across:
- `ws list` terminal output
- Raycast extension project list
- Chrome tab groups (when extension is built)
- iTerm tab backgrounds (stretch goal)

Palette: red, blue, green, orange, purple, yellow, cyan, magenta. Assigned in order, recycled if exhausted.

## Triggers (Future)

A parked project can have an optional **trigger** — a condition that, when met, automatically executes a follow-up action.

```bash
ws park "Claude running PLAN.md" \
  --then "when process exits, run: claude '/review'"

ws park "CI running on PR #42" \
  --then "when 'gh run list --branch main' exits 0, run: post-to-slack"
```

**Trigger types:**
- `process_exit` — A specific PID or command finishes (covers: Claude sessions, test runs, builds)
- `file_changed` — A file is modified (covers: Claude writing output, build artifacts)
- `poll_command` — A command returns exit code 0 (covers: CI status, PR approval)

**Actions** are shell commands. Keep it simple and composable.

This is a post-MVP feature. The core park/focus loop needs to feel right first.

## What This Is Not

- **Not a task manager.** It doesn't track individual tasks within a project. That's what issue trackers, beads, or PLAN.md files are for. Workstreams operates one level above: which *projects* are you juggling, and what's the state of each.
- **Not a window manager.** It doesn't tile or resize windows. It brings the right windows to the front. Use Rectangle or similar for layout.
- **Not CI/CD.** Triggers are personal automation for your local workflow, not deployment pipelines.

## Technical Architecture

```
~/.workstreams/state.json    ← shared source of truth
         │
    ┌────┼───────────────┐
    │    │               │
 Raycast    Chrome          CLI
Extension  Extension       (ws)
    │    │               │
    │    ├─ tab groups   ├─ add/park/focus/status
    │    ├─ manual       ├─ auto-detect from CWD
    │    │  assignment   ├─ scan project files
    │    └─ URL matching └─ update state
    │
    ├─ read state, show dashboard
    ├─ focus action → AppleScript
    │   ├─ iTerm (tabs by directory)
    │   ├─ Chrome (tabs by URL)
    │   ├─ TablePlus (window title)
    │   └─ generic (window title)
    └─ park action → update state
```

**Language:** TypeScript/Node (CLI and Raycast share the language)
**State storage:** JSON file (simple, human-readable, debuggable)
**Window management:** AppleScript via `osascript` (native macOS, no dependencies)
**Raycast integration:** Raycast extension API (TypeScript/React)
**Chrome integration:** Chrome Extension Manifest V3 + native messaging for state file access

## MVP Scope

**In:**
- CLI: `add`, `list`, `focus`, `park`, `status`
- Auto-detection from git root and project file scanning
- AppleScript focus orchestration (iTerm, Chrome, generic title matching)
- Raycast extension with project list, focus, and park actions
- Shared state file

**Out (for now):**
- Chrome extension (manual tab assignment, tab group management)
- Triggers and automated follow-up actions
- Shell prompt integration
- iTerm tab color theming
- ###### Multi-machine sync
