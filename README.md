# Workstreams

Manage multiple concurrent software projects from a single CLI. When you switch context, Workstreams brings the right iTerm tabs, Chrome tabs, and application windows to the foreground automatically.

macOS only. Requires Node.js 18+.

## Install

```sh
git clone <repo-url> && cd workstreams
./scripts/install.sh
```

This builds the TypeScript source, installs dependencies, and links the `ws` binary globally via `npm link`.

### Shell Integration (Optional)

Add to `~/.zshrc` to auto-show project status when you `cd` into a git repo:

```sh
ws_chpwd() {
  if command -v ws &>/dev/null && [ -d .git ]; then
    ws status 2>/dev/null || true
  fi
}
chpwd_functions=(${chpwd_functions[@]} "ws_chpwd")
```

## Commands

### `ws add [name]`

Register the current directory as a project. Uses the git root if inside a repo, otherwise the working directory.

```sh
cd ~/Projects/my-app
ws add              # name defaults to directory name
ws add my-app       # explicit name
```

Auto-detects:
- **Git remote** from the repository origin
- **Ports** from `.env` (PORT variables), `package.json` (scripts with `--port`, `PORT=`, or `-p`), and `docker-compose.yml` (port mappings)
- **Database** from `config/database.yml` or `DATABASE_URL`/`DATABASE_NAME` in `.env`
- **URL patterns** derived from git remote and detected ports (e.g. `github.com/org/repo/**`, `localhost:3000/**`)

Assigns a unique color from the palette (red, blue, green, yellow, magenta, cyan, white) for visual identification. If the project already exists, updates it in place.

### `ws list`

Show all registered projects with status, color, and focus state. Active projects sort first, then parked. Alias: `ws ls`.

```sh
ws list
```

### `ws focus [name] [options]`

Set a project as the current focus, update state, and bring its windows to the front.

```sh
ws focus              # focus project detected from current directory
ws focus my-app       # focus by name
```

Window matching:
- **iTerm** -- activates tabs whose shell working directory starts with the project path
- **Chrome** -- activates tabs whose URL matches the project's URL patterns
- **Other apps** -- activates windows whose title contains the project name

Focusing a parked project automatically unparks it. Signatures are rescanned before each focus to pick up new ports or URL patterns.

**Options:**

| Flag | Description |
|------|-------------|
| `-w, --window <n>` | Activate only the Nth detected window |
| `-a, --app <name>` | Filter to windows from a specific app |

Selective focus examples:

```sh
ws focus --window 3           # raise only the 3rd detected window
ws focus --app Chrome         # raise all Chrome windows for the project
ws focus --app iTerm -w 2     # raise the 2nd iTerm match
```

Use `ws windows` to see the numbered list of matches before selecting.

### `ws windows [name] [options]`

List detected windows for a project without raising them. Outputs a numbered list showing the app and window/tab title.

```sh
ws windows
```

Example output:

```
   1  iTerm      ~/Projects/myapp (zsh)
   2  iTerm      ~/Projects/myapp/api (zsh)
   3  Chrome     github.com/org/myapp - PR #42
   4  Chrome     localhost:3000 - My App
   5  Cursor     myapp - src/index.ts
```

**Options:**

| Flag | Description |
|------|-------------|
| `--json` | Output structured JSON for programmatic use |

The `--json` output is designed for the Raycast extension and other tools that need structured window data.

### `ws park [message]`

Park the current project with an optional note. Clears it from focus.

```sh
ws park                           # park with no note
ws park "waiting on API review"   # park with a note
```

Must be run from within a registered project directory.

### `ws status`

Show detail for the current project: path, status, signatures, and recent history (last 5 entries). Alias: `ws st`.

```sh
ws status
```

Must be run from within a registered project directory.

### `ws rescan [name] [options]`

Re-scan project signatures to pick up changes to ports, git remote, database, or URL patterns. Shows a diff of what changed.

```sh
ws rescan              # rescan project detected from current directory
ws rescan my-app       # rescan by name
ws rescan --all        # rescan all registered projects
```

**Options:**

| Flag | Description |
|------|-------------|
| `-a, --all` | Rescan all registered projects |

## Raycast Extension

A companion Raycast extension provides a GUI for listing, focusing, and parking projects. See [`raycast-extension/`](raycast-extension/) for setup.

The extension uses `ws windows --json` for structured window data and `ws focus --window <n>` for selective activation.

## Architecture

```
src/
  cli.ts              CLI entry point (Commander.js)
  types.ts            Shared type definitions
  commands/           Command implementations
    add.ts            Register a project, scan signatures
    list.ts           List all projects
    focus.ts          Focus a project, orchestrate windows
    park.ts           Park a project with a note
    status.ts         Show project detail
    windows.ts        List detected windows without raising
    rescan.ts         Re-scan project signatures
  core/               Infrastructure
    state.ts          JSON state file with file locking (proper-lockfile)
    detect.ts         Git root and project name detection
    scan.ts           Port, database, and URL pattern scanning
  focus/              macOS window management (AppleScript)
    orchestrator.ts   Coordinates detection and activation across all apps
    iterm.ts          iTerm session detection and activation via it2api + AppleScript
    chrome.ts         Chrome tab detection and activation via AppleScript
    generic.ts        Generic window detection and activation by title match
```

State is stored at `~/.workstreams/state.json`. Concurrent access is protected by file locking via `proper-lockfile`.

Each focus module exposes separate `detect*()` and `activate*()` functions. The orchestrator composes these into `detectWindows()` (returns all matches) and `activateMatch()` (brings a single match to front), which are used by both `ws focus` and `ws windows`.

## Development

```sh
npm run dev    # Watch mode (tsc --watch)
npm run build  # One-time build
```

The CLI entry point is `dist/cli.js`, linked as `ws` via the `bin` field in `package.json`.
