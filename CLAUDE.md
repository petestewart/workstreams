# Workstreams - Claude Code Instructions

## Project Overview

macOS CLI tool (`ws`) + Raycast extension for managing concurrent software projects. TypeScript, ESM modules, Commander.js CLI, AppleScript for window management. State stored at `~/.workstreams/state.json`.

## Build & Run

```sh
npm run build          # Compile TypeScript
npm run dev            # Watch mode
node dist/cli.js       # Run directly
ws <command>           # If npm-linked
```

No test suite exists yet. Validate changes by building (`npm run build`) and running commands manually.

## Architecture

Three-layer structure with strict downward dependency flow:

- **commands/** - CLI command handlers. Each exports a single async function.
- **core/** - State management (`withState` for locked read-modify-write), project detection, project scanning.
- **focus/** - macOS AppleScript window management. Orchestrator coordinates iTerm, Chrome, and generic strategies.
- **raycast-extension/** - Separate Raycast app with its own build. Reads the same state file, delegates writes to the CLI binary.

## Key Patterns

- `withState(fn)` in `core/state.ts` provides transactional state updates with file locking. Always use this for writes.
- Focus modules return `boolean` (or `string[]` for generic) indicating whether matching windows were found.
- Project detection cascades: git root -> registered project path -> directory name.
- Scanning happens once at `ws add` time, reading `.env`, `package.json`, `docker-compose.yml`, and `config/database.yml`.

## Known Issues to Be Aware Of

### AppleScript injection
All three focus modules (`chrome.ts`, `iterm.ts`, `generic.ts`) interpolate values directly into AppleScript strings without escaping. Project names or paths containing double quotes will break AppleScript execution. If fixing, add an `escapeAppleScript()` utility that escapes `\` and `"`.

### Code duplication between CLI and Raycast extension
- Types are fully duplicated in `raycast-extension/src/utils/state.ts` (already drifted: `HistoryEntry.action` is `string` in Raycast vs a union type in CLI).
- `timeAgo()` exists in three places: `commands/list.ts`, `commands/status.ts`, `raycast-extension/src/utils/state.ts`.
- iTerm hierarchy parsing is reimplemented in the Raycast extension.
- When modifying types or state logic, update both locations.

### Hardcoded path in Raycast extension
`raycast-extension/src/list-projects.tsx` line 17 hardcodes `~/Projects/workstreams/dist/cli.js`. This must match the actual install location.

### process.exit inside withState
`commands/park.ts` calls `process.exit(1)` inside the `withState` callback, which can leave a stale lockfile. Validation should happen before acquiring the lock.

## Conventions

- **Type fields**: snake_case (`parked_note`, `git_remote`, `current_focus`) - matches the JSON state file format.
- **Functions/variables**: camelCase (`readState`, `projectName`).
- **Constants**: UPPER_SNAKE_CASE (`STATE_DIR`, `STATE_FILE`).
- **Command functions**: `{verb}Command` pattern (`addCommand`, `focusCommand`).
- **Focus functions**: `focus{App}` pattern (`focusIterm`, `focusChrome`).
- **File names**: single lowercase words in CLI src, kebab-case in Raycast extension.

## State File Schema

```json
{
  "projects": {
    "project-name": {
      "name": "project-name",
      "path": "/absolute/path",
      "color": "red|blue|green|yellow|magenta|cyan|white",
      "status": "active|parked",
      "parked_note": "string or null",
      "parked_at": "ISO date or null",
      "signatures": {
        "git_remote": "string or null",
        "ports": [3000],
        "database": "string or null",
        "url_patterns": ["github.com/org/repo/**"]
      },
      "history": [
        { "action": "added|focused|parked|unparked", "note": "optional", "at": "ISO date" }
      ]
    }
  },
  "current_focus": "project-name or null"
}
```

No schema version field exists. The state file has no migration mechanism - be careful when changing the schema.
