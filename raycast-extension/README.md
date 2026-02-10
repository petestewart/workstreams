# Workstreams Raycast Extension

Raycast interface for the [Workstreams](../) CLI. Lists your registered projects and lets you focus or park them with a keystroke.

## Setup

1. Install the CLI first (see [root README](../README.md))
2. Install Raycast extension dependencies:

```sh
cd raycast-extension
npm install
```

3. Open Raycast, go to Extensions > Import Extension, and select this directory.

Or use dev mode:

```sh
npm run dev
```

## Important

The extension hardcodes the CLI path at `~/Projects/workstreams/dist/cli.js` in `src/list-projects.tsx` line 17. If the project lives elsewhere, update `CLI_SCRIPT` to match.

## Features

- **Focus Project** (Enter) -- switches focus, brings iTerm tabs to front
- **Park Project** (Cmd+Shift+P) -- parks the project
- **Open in Terminal** (Cmd+O) -- opens project directory in iTerm
- **Show in Finder** -- reveals project directory

Projects are grouped into Active and Parked sections, sorted with the currently focused project first.

## Architecture

The extension reads state directly from `~/.workstreams/state.json` (synchronous read, no locking). State mutations are delegated to the CLI binary via `execFileSync`. iTerm tab focusing is reimplemented locally using `it2api` + `lsof` for faster operation from the Raycast context.

Types are duplicated from the CLI's `src/types.ts` into `src/utils/state.ts`. Keep these in sync when modifying the state schema.
